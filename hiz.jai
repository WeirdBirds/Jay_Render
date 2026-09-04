// Hierarchical-Z occlusion culling.
//
// The pyramid stores reverse-Z depth (Z-up left-handed projection: near -> 1.0,
// far -> 0.0, depth test GREATER, clear 0.0). The conservative tile value is
// the MINIMUM depth over the tile = the tile's farthest occluder surface.
//
// Levels are separate R32_SFLOAT textures (not one mip-chained image) so each
// level's dimensions can be (ceil half of the parent, rounded to even). Every
// interior reduction is then an exact 2x2 block. Padding blocks beyond the
// source extent are written 0.0 (far) — unusable as occluders, conservative.

#scope_module

HiZ_Data :: struct {
    pyramid_textures: [HIZ_MAX_MIPS] Gpu_Texture;
    mip_views:        [HIZ_MAX_MIPS] Gpu_Texture_View;
    depth_view:       Gpu_Texture_View;   // native D32 view of the main depth buffer
    sampler:          Gpu_Sampler;

    full_width:  u32;   // full-resolution depth size
    full_height: u32;
    base_width:  u32;   // pyramid base size, rounded to even
    base_height: u32;
    mips:        u32;

    // Pyramid base texel budget per long axis. The base follows the frame's
    // aspect ratio (budget scales the wider axis), so culling density stays
    // constant across window sizes; it is clamped to at most half of the
    // render resolution per axis (see hiz_init). 512 avoids coarse tiles
    // collapsing to sky-depth 0.0 while keeping the reduction work bounded.
    hiz_base_texels: u32 = 512;

    params:      [MAX_FRAMES_IN_FLIGHT][HIZ_MAX_MIPS]*HiZ_Params;
    params_gpu:  [MAX_FRAMES_IN_FLIGHT][HIZ_MAX_MIPS]Gpu_Ptr;
    counters:    [MAX_FRAMES_IN_FLIGHT]*HiZ_Counters;
    counters_gpu:[MAX_FRAMES_IN_FLIGHT]Gpu_Ptr;

    pipeline: Gpu_Pipeline;
    created:  bool;
}

hiz_init :: (data: *Render_Data) {
    hiz := *data.hiz;
    #if DEBUG { assert(hiz.pyramid_textures[0] == 0, "hiz_init: pyramid already exists"); }

    full_w, full_h := gpu_get_surface_extent();
    if full_w == 0 || full_h == 0 return;

    if hiz.params[0][0] == null {
        for i: 0..MAX_FRAMES_IN_FLIGHT - 1 {
            // One param slot per dispatch: the CPU writes a slot exactly once
            // per frame, then the GPU reads it (much later, async). A shared
            // buffer would let the CPU overwrite a dispatch's params before the
            // GPU executed it — racing the async reads. Same-queue in-order
            // only orders GPU execution, not CPU writes vs GPU reads.
            allocated, gpu_ptr_0 := gpu_malloc(cast(s64)size_of(HiZ_Params) * HIZ_MAX_MIPS);
            hiz.params[i][0] = cast(*HiZ_Params) allocated;
            hiz.params_gpu[i][0] = gpu_ptr_0;
            for slot: 1..HIZ_MAX_MIPS - 1 {
                hiz.params[i][slot] = hiz.params[i][0] + slot;
                hiz.params_gpu[i][slot] = cast(Gpu_Ptr)(cast(u64)hiz.params_gpu[i][0] + cast(u64)size_of(HiZ_Params) * cast(u64)slot);
            }
            assert(hiz.params[i][0] != null && hiz.params_gpu[i][0] != 0, "hiz: params allocation failed");
            #if DEBUG {
                hiz.counters[i], hiz.counters_gpu[i] = gpu_malloc(HiZ_Counters);
                assert(hiz.counters[i] != null && hiz.counters_gpu[i] != 0, "hiz: counters allocation failed");
            } else {
                // Release: no GPU->CPU telemetry. counters pointer stays 0 so
                // the shaders skip every InterlockedAdd; nothing is allocated.
                hiz.counters[i] = null;
                hiz.counters_gpu[i] = 0;
            }
        }
    }


    hiz.full_width = full_w;
    hiz.full_height = full_h;
    // Base size: budget scaled by the frame's aspect ratio, clamped to at most
    // half the render resolution. A base larger than half-res makes the
    // reduction chain nearly useless and costs more than it saves.
    budget_w := hiz_even_dim((hiz.hiz_base_texels * full_w + full_h - 1) / full_h);
    budget_h := hiz_even_dim(hiz.hiz_base_texels);
    half_w   := hiz_even_dim((full_w + 1) / 2);
    half_h   := hiz_even_dim((full_h + 1) / 2);
    hiz.base_width  = min(budget_w, half_w);
    hiz.base_height = min(budget_h, half_h);
    hiz.mips = hiz_mip_count(hiz.base_width, hiz.base_height);

    #if DEBUG { assert(hiz.mips <= HIZ_MAX_MIPS, "hiz: pyramid exceeds HIZ_MAX_MIPS"); }

    for mip: 0..hiz.mips - 1 {
        w := hiz_mip_dim(hiz.base_width, mip);
        h := hiz_mip_dim(hiz.base_height, mip);
        #if DEBUG log("hiz: creating mip % %x%", mip, w, h);
        result, tex := gpu_create_texture(.{
            dimensions = .[w, h, 1],
            format = .R32_SFLOAT,
            mip_count = 1,
            usage = .SAMPLED | .STORAGE,
        }, label = tprint("Jay_Render hiz mip %", mip));
        assert(result == .SUCCESS && tex != 0, "hiz: pyramid texture creation failed");
        hiz.pyramid_textures[mip] = tex;

        hiz.mip_views[mip] = gpu_texture_view(tex);

        assert(hiz.mip_views[mip] != 0, "hiz: pyramid view creation failed");
    }

    // Native D32 view of the depth buffer. Sampling depth with a plain
    // (non-comparison) sampler is valid and returns the depth as float —
    // no format reinterpretation, so no mutable-format or compatibility-class
    // constraints like the old R32 color view had.

    hiz.depth_view = gpu_texture_view(render.viewport.depth_buffer);

    assert(hiz.depth_view != 0, "hiz: depth view creation failed");


    if hiz.sampler == 0 {
        hiz.sampler = gpu_create_sampler(.{
            min_filter = .NEAREST, mag_filter = .NEAREST, mip_filter = .NEAREST,
            address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
            mip_lod_bias = 0, mip_lod = 0, enable_anisotropy = false,
        }, "Jay_Render hiz nearest");
        assert(hiz.sampler != 0, "hiz: sampler creation failed");
    }

    hiz.pipeline = data.pipelines[6];
    hiz.created = true;

    #if DEBUG log("hiz: base %x% (% mips)", hiz.base_width, hiz.base_height, hiz.mips);
}

hiz_destroy :: (data: *Render_Data) {
    hiz := *data.hiz;

    for textures: hiz.pyramid_textures {
        if textures != 0 gpu_free(textures);
    }
    if hiz.sampler != 0 gpu_free(hiz.sampler);
    for i: 0..MAX_FRAMES_IN_FLIGHT - 1 {
        if hiz.params[i][0] != null {
            free_gpu_cpu(hiz.params[i][0]);
            if hiz.counters[i] != null free_gpu_cpu(hiz.counters[i]);
        }
    }
    // depth_view is owned by the depth texture and dies with it.
    hiz.* = .{};
}

// Extent changed (framebuffer resize). The old depth texture and its views are
// already gone; rebuild the pyramid and the depth read view against the new one.
hiz_recreate :: (data: *Render_Data) {
    hiz_destroy(data);
    hiz_init(data);
}

// Read last frame's counters and log them. The slot the GPU filled three
// frames ago is complete by pacing, and the entry can never race the reset
// (the reset is GPU-side, ordered before this frame's adds).
hiz_frame_begin :: (data: *Render_Data, delta_time: float64) {
    hiz := *data.hiz;
    if !hiz.created return;

    #if DEBUG {
        frame_index := gpu_frame_slot();
        counters := hiz.counters[frame_index];
        // Chain B's reset must no longer wipe the ring. If these fail, the
        // reset_counters gate regressed. (base==0 also happens legitimately
        // right after a resize recreate, hence frames_logged warmup guard.)
        if data.frames_logged > 3 && hiz.created {
            assert(counters.base_texels > 0,
                "hiz: base counter 0 — stats ring was wiped or pyramid build skipped");
            assert(counters.rejected == counters.rescued + counters.confirmed,
                tprint("hiz: conservation broken rej=% res=% conf=%",
                    counters.rejected, counters.rescued, counters.confirmed));
        }
        // Debug draw args via counters (build/prefix write counters[18]/[19]).
        dc := counters.per_dispatch[11]; // counters[18]
        tvv := counters.per_dispatch[12]; // counters[19]
        if data.frames_logged > 0 && delta_time > 0 {
            ms := delta_time * 1000.0;
            fps_i: s64 = xx (1000.0 / ms + 0.5);
            ms_fmt := FormatFloat.{ value = ms, trailing_width = 4 };
            log("Frame %: %ms (%fps), base=% mip=% zero=% rej=% res=% conf=% hist=% drawn=% dc=% vis=% pd=% % % % % % %",
                cast(s64) data.frames_logged, ms_fmt, fps_i,
                counters.base_texels, counters.mip_texels, counters.zero_tiles,
                counters.rejected, counters.rescued, counters.confirmed, counters.history,
                counters.per_dispatch[16], dc, tvv,
                counters.per_dispatch[0], counters.per_dispatch[1], counters.per_dispatch[2],
                counters.per_dispatch[3], counters.per_dispatch[4], counters.per_dispatch[5],
                counters.per_dispatch[6], counters.per_dispatch[7], counters.per_dispatch[8],
                counters.per_dispatch[10]);
        }
    } else {
        // Release build: per-frame FPS line only. No GPU counter readback —
        // delta_time is CPU-side, so this costs nothing on the GPU timeline.
        if data.frames_logged > 0 && delta_time > 0 {
            ms := delta_time * 1000.0;
            fps_i: s64 = xx (1000.0 / ms + 0.5);
            ms_fmt := FormatFloat.{ value = ms, trailing_width = 4 };
            log("Frame %: %ms (%fps)", cast(s64) data.frames_logged, ms_fmt, fps_i);
        }
    }
}

// Build the pyramid from this frame's depth on the main queue, right after the
// opaque render pass. In-buffer execution barriers only — no cross-queue sync.
// The counter reset no longer lives here: the reset dispatch at the start of
// chain A (compute queue) zeroes this frame's slot before its chains add.
hiz_build :: (data: *Render_Data, cmd: Gpu_Command_Buffer) {
    hiz := *data.hiz;
    if !hiz.created return;

    frame_index := gpu_frame_slot();

    params := hiz.params[frame_index][0];
    params.counters = hiz.counters_gpu[frame_index];
    params.depth_view_index = cast(u32) hiz.depth_view;
    params.sampler_index = cast(u32) hiz.sampler;

    // Depth-write (late fragment tests) -> compute-read sync: the pyramid base
    // reads the depth just written by the render pass.
    gpu_barrier(cmd, .LATE_FRAGMENT_TESTS, .COMPUTE_SHADER);
    result := gpu_set_pipeline(cmd, hiz.pipeline);
    #if DEBUG { assert(result == .SUCCESS, "hiz: pipeline bind failed"); }

    // Base mip: min of the corresponding 2x2 full-res depth values.
    params.mode = 0;
    params.dispatch_index = 0;
    params.src_width = hiz.full_width;
    params.src_height = hiz.full_height;
    params.dst_width = hiz.base_width;
    params.dst_height = hiz.base_height;
    params.dst_view_index = cast(u32) hiz.mip_views[0];
    gx := max((hiz.base_width + 7) / 8, 1);
    gy := max((hiz.base_height + 7) / 8, 1);
    gpu_dispatch(cmd, hiz.params_gpu[frame_index][0], u32.[gx, gy, 1]);

    // Higher mips: min-reduce the previous level. Each dispatch has its own
    // param slot (written once, never overwritten), so even though the GPU
    // executes asynchronously and long after the CPU wrote the slot, every
    // dispatch reads its intended extent. In-buffer compute barriers order
    // the dispatches against each other on the queue.
    for mip: 1..hiz.mips - 1 {
        gpu_barrier(cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);
        params_mip := hiz.params[frame_index][mip];
        params_mip.mode = 1;
        params_mip.dispatch_index = mip;
        params_mip.src_width = hiz_mip_dim(hiz.base_width, mip - 1);
        params_mip.src_height = hiz_mip_dim(hiz.base_height, mip - 1);
        params_mip.dst_width = hiz_mip_dim(hiz.base_width, mip);
        params_mip.dst_height = hiz_mip_dim(hiz.base_height, mip);
        params_mip.src_view_index = cast(u32) hiz.mip_views[mip - 1];
        params_mip.dst_view_index = cast(u32) hiz.mip_views[mip];
        params_mip.counters = hiz.counters_gpu[frame_index];
        params_mip.depth_view_index = 0;
        params_mip.sampler_index = 0;
        gx = max((params_mip.dst_width + 7) / 8, 1);
        gy = max((params_mip.dst_height + 7) / 8, 1);
        gpu_dispatch(cmd, hiz.params_gpu[frame_index][mip], u32.[gx, gy, 1]);
    }
}

#scope_file

HIZ_MAX_MIPS :: 16;

HiZ_Counters :: struct {
    base_texels: u32;   // threads that wrote the base level
    mip_texels:  u32;   // threads that wrote higher levels
    zero_tiles:  u32;   // base tiles whose min is exactly 0 (uncovered => no occluder)
    // Stage 2: occlusion stats. Written by the cull dispatches after the
    // counter reset at the start of chain A; read back three frames later.
    rejected:    u32;   // pass A rejected (deferred to pass B)
    rescued:     u32;   // pass B drew (was rejected, fresh pyramid says visible)
    confirmed:   u32;   // pass B kept occluded (fresh pyramid agrees)
    history:     u32;   // pass A engaged the history test on a candidate
    per_dispatch: [32]u32;   // debug: survivor count per dispatch (reset zeroes [0..31])
}

// Mirrors HiZ_Params in hiz_downsample.slang (scalar layout).
HiZ_Params :: struct {
    depth_view_index: u32;   // sampled depth view of the full-res depth buffer
    sampler_index:    u32;   // nearest / clamp-to-edge sampler
    src_view_index:   u32;   // storage view of source mip (mode >= 1)
    dst_view_index:   u32;   // storage view of destination mip
    src_width:        u32;
    src_height:       u32;
    dst_width:        u32;
    dst_height:       u32;
    mode:             u32;   // 0 = base from depth, 1 = mip-to-mip
    dispatch_index:   u32;   // 0 = base, 1..N-1 = mips (debug per-dispatch counter)
    counters:         Gpu_Ptr;
}

// Round up to the next even value. Base dims stay even so every mip reduction
// is an exact 2x2 block (up to padding blocks written as 0).
hiz_even_dim :: (d: u32) -> u32 {
    return (d + 1) / 2 * 2;
}

// Next pyramid level dim: ceil half of the parent, rounded to even.
hiz_next_dim :: (d: u32) -> u32 {
    if d <= 2 return 1;
    half := (d + 1) / 2;
    return (half + 1) / 2 * 2;
}

hiz_mip_dim :: (dim: u32, mip: u32) -> u32 {
    if mip == 0 return dim;
    d := dim;
    for 0..mip - 1 {
        d = hiz_next_dim(d);
    }
    return d;
}

hiz_mip_count :: (w: u32, h: u32) -> u32 {
    mips: u32 = 1;
    d := max(w, h);
    while d > 1 {
        d = hiz_next_dim(d);
        mips += 1;
    }
    return mips;
}
