#import "Random";

renderer_shutdown :: () {
    if render.gpu_initialized {
        gpu_wait_idle();
    }

    if render.data_initialized {
        render_data_destroy(*render.data);
        render.data_initialized = false;
    }

    destroy_depth_buffer();

    if render.swapchain_initialized {
        gpu_destroy_swapchain();
        render.swapchain_initialized = false;
    }
    if render.gpu_initialized {
        gpu_shutdown();
        render.gpu_initialized = false;
    }
    if render.sdl_window {
        SDL_DestroyWindow(render.sdl_window);
        render.sdl_window = null;
    }
    if render.sdl_initialized {
        SDL_Quit();
        render.sdl_initialized = false;
    }

    render = .{};
}

renderer_start_failed :: (engine: *Engine, message: string) {
    log_error("Jay_Render: %", message);
    engine.is_running = false;
    renderer_shutdown();
}

// Call only at an explicit scene-loading or memory-maintenance boundary.
// It waits for GPU idle and preserves every live allocation offset.
renderer_trim_memory :: () {
    if render.data_initialized {
        trim_render_memory(*render.data);
    }
}

Jay_Render :: struct {
    after: Lifecycle.SimulationComplete;
    before: Lifecycle.RenderComplete;

    before_begin :: (engine: *Engine) {
        log("Starting Jay_Render");
        validate_render_config();

        gpu_result := gpu_init();
        if gpu_result != .SUCCESS {
            renderer_start_failed(engine, "gpu_init failed");
            return;
        }
        render.gpu_initialized = true;

        #if OS == .LINUX {
            // RenderDoc upstream still requires XWayland. Ordinary Linux runs
            // retain native Wayland when compositor support is available.
            if DEBUG || RENDER_CAPTURE || SDL_getenv("WAYLAND_DISPLAY") == null {
                SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "x11");
                render.window_type = .X11;
                log("Requested SDL video driver: x11");
            } else {
                SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "wayland");
                render.window_type = .WAYLAND;
                log("Requested SDL video driver: wayland");
            }
        } else #if OS == .WINDOWS {
            render.window_type = .WIN32;
        } else #if OS == .MACOS {
            render.window_type = .COCOA;
        } else {
            renderer_start_failed(engine, "unsupported platform");
            return;
        }

        if !SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) {
            renderer_start_failed(engine, "SDL_Init failed");
            return;
        }
        render.sdl_initialized = true;

        render.sdl_window = SDL_CreateWindow("Hello Sailor", 1920, 1080, SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE);
        if !render.sdl_window {
            renderer_start_failed(engine, "SDL_CreateWindow failed");
            return;
        }

        props := SDL_GetWindowProperties(render.sdl_window);
        if props == 0 {
            renderer_start_failed(engine, "SDL window properties unavailable");
            return;
        }

        if render.window_type == .WAYLAND {
            display := xx SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, null);
            surface := xx SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, null);
            if display == null || surface == null {
                renderer_start_failed(engine, "invalid Wayland handles");
                return;
            }
            gpu_init_swapchain(display, surface, render.window_type);
        } else if render.window_type == .X11 {
            window_handle := cast(u64) SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
            if window_handle == 0 {
                renderer_start_failed(engine, "invalid X11 window handle");
                return;
            }
            gpu_init_swapchain(window_handle, render.window_type, .[]);
        } else if render.window_type == .WIN32 {
            window_handle := SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, null);
            if window_handle == null {
                renderer_start_failed(engine, "invalid Win32 window handle");
                return;
            }
            gpu_init_swapchain(cast(u64) window_handle, render.window_type, .[]);
        } else {
            cocoa_window := SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
            if cocoa_window == null {
                renderer_start_failed(engine, "invalid Cocoa window handle");
                return;
            }
            gpu_init_swapchain(cast(u64) cocoa_window, render.window_type, .[]);
        }
        render.swapchain_initialized = true;

        render.queues.main = gpu_get_queue(.MAIN, 0);
        render.queues.compute = gpu_get_queue(.COMPUTE, 0);
        render.queues.transfer = gpu_get_queue(.TRANSFER, 0);
        if render.queues.main == 0 || render.queues.compute == 0 || render.queues.transfer == 0 {
            renderer_start_failed(engine, "required GPU queue unavailable");
            return;
        }

        render.data = render_init();
        // JAY_OCCLUSION=0 forces the stage-1 path (frustum only, no rescue
        // pass) — used for A/B pixel-identity validation and cull bisecting.
        cached := SDL_getenv("JAY_OCCLUSION");
        if cached != null && cached[0] == 48 {  // 48 = '0'
            render.data.occlusion_enabled = false;
        }
        probe_cached := SDL_getenv("JAY_PROBE");
        if probe_cached != null && probe_cached[0] == 49 { // '1'
            render.data.probe_enabled = true;
        }
        render.data_initialized = true;
        create_pipelines(*render.data);
        create_depth_buffer();
        hiz_init(*render.data);

        if !render.viewport.depth {
            renderer_start_failed(engine, "depth buffer creation failed");
            return;
        }

        log("Jay_Render started");
    }

    begin :: (engine: *Engine) {
        if !render.data_initialized return;

        mesh := get_asset(Mesh_Data, "/meshes/cow.obj");
        mesh_id := gpu_upload_mesh(*render.data, mesh);

        colors := Vec4.[
            .{x=0.8, y=0.3, z=0.2, w=1},
            .{x=0.3, y=0.8, z=0.2, w=1},
            .{x=0.2, y=0.3, z=0.8, w=1},
        ];

        materials: [3]Material_Handle;
        for i: 0..materials.count - 1 {
            materials[i] = new_material(*render.data, .{
                base_color = colors[i],
                texture_index = 0,
                sampler_index = 0,
                flags = 0,
            });
        }

        // Material varies per instance, not per draw group. One mesh group
        // produces one indirect command for all cows.
        group_id := new_draw_group(*render.data, mesh_id);
        for i: 0..100 {
            for j: 0..100 {
                size:float32 = xx (random_get_zero_to_one_new()+0.1) * 0.5;
                transform := to_matrix(Transform.{
                    translation = Vec3.{xx (i - 50), xx (j - 50), xx random_get_zero_to_one_new() * 20.0},
                    rotation = to_quat(Radians.{0, 0, xx (i / (j + 1))}),
                    scale = Vec3.new(size),
                });
                new_mesh_instance(
                    *render.data,
                    group_id,
                    transform,
                    Vec4.new(get_translation(transform), size * 6.13),
                    materials[(i + j) % materials.count],
                );
            }
        }
        refresh_gpu_roots(*render.data);
        log("Assets loaded");
    }

    before_tick :: (engine: *Engine) {
        if !render.sdl_initialized return;

        ev: SDL_Event;
        while SDL_PollEvent(*ev) {
            if ev.type == {
                case xx SDL_EventType.QUIT;
                    engine.is_running = false;
                case xx SDL_EventType.KEY_DOWN;
                    if ev.key.key == SDLK_ESCAPE engine.is_running = false;
                case xx SDL_EventType.WINDOW_RESIZED;
                    if render.frames_rendered > 0 render.framebuffer_resized = true;
                case;
            }
        }
    }

    after_tick :: (engine: *Engine) {
        if !render.data_initialized || !render.sdl_window return;

        w, h: s32;
        SDL_GetWindowSize(render.sdl_window, *w, *h);
        if w <= 0 || h <= 0 return;

        if render.framebuffer_resized {
            #if DEBUG log("new window size: %x%", w, h);
            gpu_wait_idle();
            gpu_swapchain_resize(xx w, xx h);
            recreate_depth_buffer();
            hiz_recreate(*render.data);
            render.framebuffer_resized = false;
            if !render.viewport.depth return;
        }

        acquire_result, swapchain_image := gpu_swapchain_acquire();
        if acquire_result != .SUCCESS || !swapchain_image return;
        render.viewport.image = swapchain_image;

        camera: Camera;
        camera.aspect_ratio = cast(float32) w / h;
        camera.fov = PI_2;
        camera.target = *render.viewport;
        camera.far = 50;

        sin_t: float32 = xx sin(engine.timer.time);
        transform := to_matrix(Transform.{
            translation = Vec3.{-20, -20 * sin_t, 20},
            rotation = to_quat(Euler.{0, -45, 45 * sin_t}),
            scale = Vec3.new(1),
        });

        #if DEBUG {
            if engine.timer.delta_time > 0 render.data.last_frame_ms = engine.timer.delta_time * 1000.0;
        }
        // Freeze the camera while the pixel-identical check runs (stages 1-2),
        // otherwise the two compared frames differ by camera motion alone.
        if render.data.compare_stage == 1 {
            render.data.compare_transform = transform;
        } else if render.data.compare_stage == 2 {
            transform = render.data.compare_transform;
        }
        camera_capture(camera, transform);
// Pixel-identical check: uses three NORMAL frames (no inline re-render, so
// every frame acquires its own swapchain image — no validation hazards).
//   stage 0 at frame 300: enable probe + occlusion, save nothing yet
//   stage 1 at frame 301: copy "on" image + flags, switch occlusion off
//   stage 2 at frame 302: compare, log, restore everything
        if !render.data.compare_done {
            if render.frames_rendered == 300 {
                render.data.compare_stage = 1;
                render.data.probe_enabled = true;
                render.data.compare_saved_occ = render.data.occlusion_enabled;
                render.data.occlusion_enabled = true;
                log("compare: frame 300 - occlusion ON (probe armed)");
            } else if render.frames_rendered == 301 && render.data.compare_stage == 1 {
                gpu_wait_idle();  // previous frame's probe copy must be complete before CPU read
                if render.data.probe_map != null && render.data.probe_bytes > 0 {
                    render.data.compare_bytes = render.data.probe_bytes;
                    if render.data.compare_buf == null {
                        render.data.compare_buf = cast(*u8) alloc(render.data.compare_bytes);
                    }
                    if render.data.occluded_flags_save == null {
                        render.data.occluded_flags_save = cast(*u32) alloc(cast(s64) MAX_INSTANCES * 4);
                    }
                    memcpy(render.data.compare_buf, render.data.probe_map, render.data.compare_bytes);
                    memcpy(cast(*u8) render.data.occluded_flags_save, render.data.occluded_flags_cpu.data, cast(s64) MAX_INSTANCES * 4);
                    log("compare: frame 301 - saved ON image (% bytes), switching OFF", render.data.compare_bytes);
                }
                render.data.occlusion_enabled = false;
                render.data.compare_stage = 2;
            } else if render.frames_rendered == 302 && render.data.compare_stage == 2 {
                render.data.compare_stage = 3;
                gpu_wait_idle();  // this frame's OFF-image copy must be complete too
                if render.data.probe_map != null && render.data.compare_buf != null {
                    pixelDiff: s64 = 0;
                    totalPixels := render.data.compare_bytes / 4;
                    for p: 0..totalPixels-1 {
                        off := p*4;
                        b0 := render.data.compare_buf[off+0];
                        g0 := render.data.compare_buf[off+1];
                        r0 := render.data.compare_buf[off+2];
                        b1 := render.data.probe_map[off+0];
                        g1 := render.data.probe_map[off+1];
                        r1 := render.data.probe_map[off+2];
                        if b0 != b1 || g0 != g1 || r0 != r1 pixelDiff += 1;
                    }
                    if pixelDiff == 0 {
                        log("compare: IDENTICAL - no false positives (% pixels)", totalPixels);
                    } else {
                        log("compare: DIFFERENT - %/% pixels differ (false occlusion)", pixelDiff, totalPixels);
                    }
                } else {
                    log("compare: probe missing, check skipped");
                }
                // Restore. Free the big scratch HERE (same allocator context
                // as the alloc above) — freeing in render_data_destroy crashes:
                // different context at shutdown.
                render.data.occlusion_enabled = render.data.compare_saved_occ;
                render.data.probe_enabled = false;
                if render.data.compare_buf != null {
                    free(render.data.compare_buf);
                    render.data.compare_buf = null;
                    render.data.compare_bytes = 0;
                }
                if render.data.occluded_flags_save != null {
                    free(render.data.occluded_flags_save);
                    render.data.occluded_flags_save = null;
                }
                render.data.compare_done = true;
                log("compare: done, settings restored");
            }
        }
        render.frames_rendered += 1;
    }

    after_end :: (engine: *Engine) {
        if render.gpu_initialized || render.sdl_initialized {
            log("Shutting Jay_Render down");
            renderer_shutdown();
        }
    }
}
