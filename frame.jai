#scope_module

render_frame :: (data: *Render_Data, main_queue: Gpu_Queue, compute_queue: Gpu_Queue,
        image: Gpu_Texture_View, depth_view: Gpu_Texture_View,
        view_projection: Mat4, view: Mat4, frustum_planes: [6] Vec4,
        camera_transform: Mat4, camera_near: float32, camera_far: float32,
        delta_time: float64) {

    frame_index := gpu_frame_slot();
    #if DEBUG { assert(frame_index < MAX_FRAMES_IN_FLIGHT); }
    frame := *data.dynamic[frame_index];

    // Log the counters for the slot we are about to reuse (3 frames old, GPU
    // done via wait_next_frame). Must read before the reset dispatch zeroes it.
    hiz_frame_begin(data, delta_time);
    data.frames_logged += 1;

    // Pools reuse holes. Dispatch through their occupied extent and let the
    // cull pass reject destroyed instance slots.
    refresh_gpu_roots(data);
    frame.params.group_count = data.group_pool.max;
    frame.params.instance_count = data.instance_pool.max;

    // Common culling helpers (Z-up LH, reverse-Z: near -> 1.0, far -> 0.0).
    frame.params.cull_mode = 0;
    frame.params.frustum_planes = frustum_planes;
    frame.params.view_projection = view_projection;
    frame.params.view = view;
    frame.vertex_params.view_projection = view_projection;

    w, h := gpu_get_surface_extent();
    if data.hiz.created {
        frame.params.hiz_base_size = .{xx data.hiz.base_width, xx data.hiz.base_height};
        frame.params.hiz_levels = data.hiz.mips;
    } else {
        frame.params.hiz_base_size = .{1, 1};
        frame.params.hiz_levels = 1;
    }

    // Reverse-Z coefficients: revz(d) = b / d - a  (near -> 1, far -> 0).
    a := camera_near / (camera_far - camera_near);
    b := camera_far * camera_near / (camera_far - camera_near);
    frame.params.ndc_coeffs = .{a, b};
    frame.params.hiz_epsilon = -0.022;
    frame.params.first_frame = data.first_frame;
    frame.params.reset_counters = 1;   // chain A owns the stats-ring reset
    frame.params.occluded_flags = data.occluded_flags_gpu;
    frame.params.counters = data.hiz.counters_gpu[frame_index];

    // Camera-motion gate with hysteresis: turn history ON below the tight
    // threshold, OFF only past the loose one. Without this, velocity hovering
    // at the limit flips the gate every other frame (2-submit <-> 4-submit
    // alternation = visible stutter).
    history_enabled: u32 = 0;
    if data.occlusion_enabled && data.history_ready && data.hiz.created {
        px := Vec3.{camera_transform._14, camera_transform._24, camera_transform._34};
        fwd := normalize(Vec3.{camera_transform._11, camera_transform._21, camera_transform._31});
        pp := Vec3.{data.prev_transform._14, data.prev_transform._24, data.prev_transform._34};
        pfwd := normalize(Vec3.{data.prev_transform._11, data.prev_transform._21, data.prev_transform._31});
        pos_delta := length(px - pp);
        angle_delta := acos(clamp(dot(fwd, pfwd), -1.0, 1.0));
        if data.history_active {
            data.history_active = pos_delta <= HISTORY_OFF_POS_DELTA && angle_delta <= HISTORY_OFF_ANGLE;
        } else {
            data.history_active = pos_delta <= HISTORY_MAX_POS_DELTA && angle_delta <= HISTORY_MAX_ANGLE;
        }
        history_enabled = xx data.history_active;
    } else {
        data.history_active = false;
    }
    frame.params.history_enabled = history_enabled;

    for mip: 0..data.hiz.mips - 1 {
        frame.params.hiz_view_indices[mip] = cast(u32) data.hiz.mip_views[mip];
    }

    // Whether this frame needs the rescue pass (history predicted some occlusions).
    // Skip the 4-dispatch rescue chain when history is off (camera moving) — it would
    // find zero rejects and waste time. Still signal the pyramid for next frame.
    do_rescue := data.occlusion_enabled && history_enabled != 0 && data.first_frame == 0 && data.history_ready;

    // Pass B (rescue) reads the same frame-level state; its own chain compiles
    // only the pass-A rejects (occluded_flags != 0), retested against the
    // fresh pyramid. The view matrices and frustum planes are mandatory —
    // leaving them zeroed made the retest read garbage and explode the draws.
    frame.params_b.group_count = data.group_pool.max;
    frame.params_b.instance_count = data.instance_pool.max;
    frame.params_b.frustum_planes = frustum_planes;
    frame.params_b.view_projection = view_projection;
    frame.params_b.view = view;
    frame.params_b.cull_mode = 1;
    frame.params_b.history_enabled = 0;
    frame.params_b.hiz_base_size = frame.params.hiz_base_size;
    frame.params_b.hiz_levels = frame.params.hiz_levels;
    frame.params_b.ndc_coeffs = frame.params.ndc_coeffs;
    frame.params_b.hiz_epsilon = -0.022;
    frame.params_b.first_frame = 0;
    frame.params_b.reset_counters = 0; // must NOT wipe the ring: base/mip/zero/rej/hist
                                       // were written earlier this frame and get read 3 frames later
    frame.params_b.occluded_flags = data.occluded_flags_gpu;
    frame.params_b.counters = data.hiz.counters_gpu[frame_index];
    for mip: 0..data.hiz.mips - 1 {
        frame.params_b.hiz_view_indices[mip] = frame.params.hiz_view_indices[mip];
    }
    frame.vertex_params_b.view_projection = view_projection;

    // Chain A runs on the compute queue (stage-1 structure: stable on this
    // GPU). The main buffer waits its completion before rendering.
    result0, compute_cmd := gpu_start_command_recording(compute_queue);
    #if DEBUG { assert(result0 == .SUCCESS); }

    // Zero this frame's counter slot before its chains add to it (the ring is
    // read three frames later, so the slot must hold only this frame's work:
    // reset -> A adds -> hiz adds -> B adds).
    reset_pipeline_result := gpu_set_pipeline(compute_cmd, data.pipelines[0]);
    #if DEBUG { assert(reset_pipeline_result == .SUCCESS); }
    gg := max(xx 1, (data.group_pool.max + 63) / 64);
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[xx gg, 1, 1]);
    gpu_barrier(compute_cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 1: Count-Cull A (frustum + history)
    cull_pipeline_result := gpu_set_pipeline(compute_cmd, data.pipelines[1]);
    #if DEBUG { assert(cull_pipeline_result == .SUCCESS); }
    ig := max(xx 1, (data.instance_pool.max + 63) / 64);
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[xx ig, 1, 1]);
    gpu_barrier(compute_cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 2: Prefix A
    prefix_pipeline_result := gpu_set_pipeline(compute_cmd, data.pipelines[2]);
    #if DEBUG { assert(prefix_pipeline_result == .SUCCESS); }
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[1, 1, 1]);
    gpu_barrier(compute_cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 3: Scatter A
    scatter_pipeline_result := gpu_set_pipeline(compute_cmd, data.pipelines[3]);
    #if DEBUG { assert(scatter_pipeline_result == .SUCCESS); }
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[xx ig, 1, 1]);
    gpu_barrier(compute_cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 4: Build draws A
    build_pipeline_result := gpu_set_pipeline(compute_cmd, data.pipelines[4]);
    #if DEBUG { assert(build_pipeline_result == .SUCCESS); }
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[xx gg, 1, 1]);

    data.compute_done_value += 1;
    compute_done := Gpu_Timeline_Pair.{data.compute_done, data.compute_done_value};
    // Pass A reads the pyramid main-A built last frame (history prediction).
    // Order it after that build via the shared timeline; value 0 (initial)
    // and already-signaled values resolve immediately.
    prev_pyr := Gpu_Timeline_Pair.{data.compute_done, data.pyr_prev};
    gpu_submit(compute_cmd, signals = .[compute_done], waits = .[prev_pyr]);

    result, cmd := gpu_start_command_recording(main_queue);
    #if DEBUG { assert(result == .SUCCESS); }

    // Render pass A: the frame's real pass. Clear color and depth.
    gpu_begin_render_pass(cmd, .{
        color_targets = .[
            .{ view = image, load_op = .CLEAR, store_op = .STORE,
               clear_color._float = .[0.03, 0.03, 0.04, 1.0] }
        ],
        depth_target = .{
            view = depth_view, load_op = .CLEAR, store_op = .STORE,
            clear_value.depth = 0.0 },
    });

    opaque_pipeline_result := gpu_set_pipeline(cmd, data.pipelines[5]);
    #if DEBUG { assert(opaque_pipeline_result == .SUCCESS); }

    gpu_set_viewport(cmd, .{x=0, y=0, width=xx w, height=xx h, min_depth=0, max_depth=1});
    gpu_set_scissor(cmd, .{x=0, y=0, width=xx w, height=xx h});
    gpu_set_depth_stencil_state(cmd, .{ depth_test = .GREATER, depth_mode = .READ | .WRITE });

    _, index_data_gpu := gpu_heap_head(data.index_allocator);

    draw_result := gpu_draw_indexed_indirect_count(cmd, frame.vertex_params_gpu, data.fragment_params_gpu,
            index_data_gpu, frame.params.draw_commands,
            frame.params.draw_count, MAX_DRAWS);
    #if DEBUG { assert(draw_result == .SUCCESS); }

    gpu_end_render_pass(cmd);

    // Pyramid from this frame's depth (reverse-Z min-reduce).
    hiz_build(data, cmd);

    // Main-A: render + pyramid. Submit it before recording the rescue chain so
    // the pyramid read by pass B is ordered after the writes on the timeline.
    if !data.occlusion_enabled {
        gpu_submit_and_present(cmd, waits = .[compute_done]);
    } else if !do_rescue {
        // History off (camera moving) or first frame — no rejects to rescue.
        // Still signal the pyramid so next frame's history has fresh data.
        data.compute_done_value += 1;
        pyramid_done := Gpu_Timeline_Pair.{data.compute_done, data.compute_done_value};
        data.pyr_prev = pyramid_done.value;
        gpu_submit_and_present(cmd, signals = .[pyramid_done], waits = .[compute_done]);
    } else {
        // Same-frame rescue on the compute queue: the compute-chain dispatches
        // hang on the MAIN queue on this GPU/driver (verified by bisection),
        // so the rescue chain is its own compute submit, ordered after the
        // pyramid build via the shared timeline.
        data.compute_done_value += 1;
        pyramid_done := Gpu_Timeline_Pair.{data.compute_done, data.compute_done_value};
        data.pyr_prev = pyramid_done.value;
        gpu_submit(cmd, signals = .[pyramid_done], waits = .[compute_done]);

        result_b, compute_b := gpu_start_command_recording(compute_queue);
        #if DEBUG { assert(result_b == .SUCCESS); }

        // Reset the SHARED scratch first. Chain B accumulates via atomic adds;
        // without this it stacks onto pass A's counts and pass B re-draws the
        // whole scene (was 9ms for a handful of rescued cows).
        reset_pipeline_result_b := gpu_set_pipeline(compute_b, data.pipelines[0]);
        #if DEBUG { assert(reset_pipeline_result_b == .SUCCESS); }
        gpu_dispatch(compute_b, frame.params_b_gpu, u32.[xx gg, 1, 1]);
        gpu_barrier(compute_b, .COMPUTE_SHADER, .COMPUTE_SHADER);

        // Rescue chain B: retest every pass-A reject against the fresh pyramid.
        gpu_barrier(compute_b, .COMPUTE_SHADER, .COMPUTE_SHADER);

        cull_pipeline_result_b := gpu_set_pipeline(compute_b, data.pipelines[1]);
        #if DEBUG { assert(cull_pipeline_result_b == .SUCCESS); }
        gpu_dispatch(compute_b, frame.params_b_gpu, u32.[xx ig, 1, 1]);
        gpu_barrier(compute_b, .COMPUTE_SHADER, .COMPUTE_SHADER);

        prefix_pipeline_result_b := gpu_set_pipeline(compute_b, data.pipelines[2]);
        #if DEBUG { assert(prefix_pipeline_result_b == .SUCCESS); }
        gpu_dispatch(compute_b, frame.params_b_gpu, u32.[1, 1, 1]);
        gpu_barrier(compute_b, .COMPUTE_SHADER, .COMPUTE_SHADER);

        scatter_pipeline_result_b := gpu_set_pipeline(compute_b, data.pipelines[3]);
        #if DEBUG { assert(scatter_pipeline_result_b == .SUCCESS); }
        gpu_dispatch(compute_b, frame.params_b_gpu, u32.[xx ig, 1, 1]);
        gpu_barrier(compute_b, .COMPUTE_SHADER, .COMPUTE_SHADER);

        build_pipeline_result_b := gpu_set_pipeline(compute_b, data.pipelines[4]);
        #if DEBUG { assert(build_pipeline_result_b == .SUCCESS); }
        gpu_dispatch(compute_b, frame.params_b_gpu, u32.[xx gg, 1, 1]);

        data.compute_done_value += 1;
        rescue_done := Gpu_Timeline_Pair.{data.compute_done, data.compute_done_value};
        gpu_submit(compute_b, signals = .[rescue_done], waits = .[pyramid_done]);

        // Main-B: rescue render on LOADED color+depth, then present. The depth
        // test GREATER keeps rescued fragments behind pass-A content hidden,
        // and identical depth re-writes are naturally rejected (no z-fight).
        result_b2, cmd_b := gpu_start_command_recording(main_queue);
        #if DEBUG { assert(result_b2 == .SUCCESS); }

        gpu_begin_render_pass(cmd_b, .{
            color_targets = .[
                .{ view = image, load_op = .LOAD, store_op = .STORE }
            ],
            depth_target = .{
                view = depth_view, load_op = .LOAD, store_op = .STORE },
        });

        opaque_pipeline_result_b := gpu_set_pipeline(cmd_b, data.pipelines[5]);
        #if DEBUG { assert(opaque_pipeline_result_b == .SUCCESS); }

        gpu_set_viewport(cmd_b, .{x=0, y=0, width=xx w, height=xx h, min_depth=0, max_depth=1});
        gpu_set_scissor(cmd_b, .{x=0, y=0, width=xx w, height=xx h});
        gpu_set_depth_stencil_state(cmd_b, .{ depth_test = .GREATER, depth_mode = .READ | .WRITE });

        draw_result_b := gpu_draw_indexed_indirect_count(cmd_b, frame.vertex_params_b_gpu, data.fragment_params_gpu,
                index_data_gpu, frame.params_b.draw_commands,
                frame.params_b.draw_count, MAX_DRAWS);
        #if DEBUG { assert(draw_result_b == .SUCCESS); }

        gpu_end_render_pass(cmd_b);

        gpu_submit_and_present(cmd_b, waits = .[rescue_done]);
    }

    data.prev_transform = camera_transform;
    data.first_frame = 0;
    data.history_ready = data.hiz.created;
}

#scope_file

HISTORY_MAX_POS_DELTA :: 0.05;   // world units (near plane is 0.1)
HISTORY_MAX_ANGLE    :: 0.02;    // radians
HISTORY_OFF_POS_DELTA :: 0.12;   // hysteresis: turn off only past this (prevents
                                 // on/off flapping when velocity hovers at the limit)
HISTORY_OFF_ANGLE     :: 0.05;