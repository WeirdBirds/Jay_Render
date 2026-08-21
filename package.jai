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

        #if DEBUG if engine.timer.delta_time > 0 log("% FPS", 1 / engine.timer.delta_time);
        camera_capture(camera, transform);
        // Pixel-identical check at frame 300: same transform, on vs off, must be identical (no false positives).
        if (!render.data.compare_done && render.frames_rendered == 300) {
            log("compare: starting pixel-identical check (on vs off, same transform)");
            render.data.probe_enabled = true;
            gpu_wait_idle();
            // On
            savedOcc := render.data.occlusion_enabled;
            render.data.occlusion_enabled = true;
            camera_capture(camera, transform);
            gpu_wait_idle();
            if (render.data.probe_map == null || render.data.probe_bytes == 0) {
                log("compare: probe not ready for on");
            } else {
                render.data.compare_bytes = render.data.probe_bytes;
                render.data.compare_buf = cast(*u8) alloc(render.data.compare_bytes);
                occluded_save_bytes := cast(s64) MAX_INSTANCES * 4;
                occluded_save_u32 := cast(*u32) alloc(occluded_save_bytes);
                memcpy(cast(*u8) occluded_save_u32, render.data.occluded_flags_cpu.data, occluded_save_bytes);
                depth_save_bytes := render.data.depth_probe_bytes;
                depth_save := cast(*u8) alloc(depth_save_bytes);
                if (render.data.depth_probe_map != null) memcpy(depth_save, render.data.depth_probe_map, depth_save_bytes);
                if (render.data.compare_buf != null) {
                    memcpy(render.data.compare_buf, render.data.probe_map, render.data.compare_bytes);
                    log("compare: saved on (% bytes)", render.data.compare_bytes);
                    // Off, same transform
                    render.data.occlusion_enabled = false;
                    camera_capture(camera, transform);
                    gpu_wait_idle();
                    if (render.data.probe_map != null) {
                        diffBytes: s64 = 0;
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
                            if (b0 != b1 || g0 != g1 || r0 != r1) pixelDiff += 1;
                            if (render.data.compare_buf[off] != render.data.probe_map[off]) diffBytes += 1;
                            if (render.data.compare_buf[off+1] != render.data.probe_map[off+1]) diffBytes += 1;
                            if (render.data.compare_buf[off+2] != render.data.probe_map[off+2]) diffBytes += 1;
                            if (render.data.compare_buf[off+3] != render.data.probe_map[off+3]) diffBytes += 1;
                        }
                        log("compare: diffBytes=% pixelDiff=% totalPixels=%", diffBytes, pixelDiff, totalPixels);
                        if (pixelDiff == 0) {
                            log("compare: IDENTICAL - no false positives");
                        } else {
                            log("compare: DIFFERENT - % pixels differ (false occlusion)", pixelDiff);
                            w, h := gpu_get_surface_extent();
                            screenW := cast(s64) w;
                            screenH := cast(s64) h;
                            view := make_view(transform);
                            proj := make_projection(camera);
                            viewProj := proj * view;
                            culledTotal: s64 = 0;
                            falseCulled: s64 = 0;
                            for id: 0..xx render.data.instance_pool.max-1 {
                                if (occluded_save_u32[id] != 1) continue;
                                culledTotal += 1;
                                b := render.data.bounds_cpu[id];
                                cv := view * Vec4.new(Vec3.{b.center_radius.x, b.center_radius.y, b.center_radius.z}, 1.0);
                                d := -cv.z;
                                r := b.center_radius.w;
                                if (d - r <= 0.0) continue;
                                c_clip := viewProj * Vec4.new(Vec3.{b.center_radius.x, b.center_radius.y, b.center_radius.z}, 1.0);
                                if (c_clip.w <= 0.0) continue;
                                c_ndc := Vec2.{c_clip.x / c_clip.w, c_clip.y / c_clip.w};
                                cx := cast(s64) ((c_ndc.x * 0.5 + 0.5) * cast(float32) screenW);
                                cy := cast(s64) ((c_ndc.y * 0.5 + 0.5) * cast(float32) screenH);
                                foundDiff := false;
                                for dy: -32..32 {
                                    for dx: -32..32 {
                                        x := cx + dx; y := cy + dy;
                                        if (x < 0 || y < 0 || x >= screenW || y >= screenH) continue;
                                        pIdx := y * screenW + x;
                                        off2 := pIdx * 4;
                                        if (off2+2 >= render.data.compare_bytes) continue;
                                        b0 := render.data.compare_buf[off2+0];
                                        g0 := render.data.compare_buf[off2+1];
                                        r0 := render.data.compare_buf[off2+2];
                                        b1 := render.data.probe_map[off2+0];
                                        g1 := render.data.probe_map[off2+1];
                                        r1 := render.data.probe_map[off2+2];
                                        if (b0 != b1 || g0 != g1 || r0 != r1) { foundDiff = true; break; }
                                    }
                                    if (foundDiff) break;
                                }
                                if (foundDiff) falseCulled += 1;
                                if (falseCulled < 5) {
                                    log("false culled id=% center=(% % %) r=% ndc=(% %) screen=(% %)", cast(s64) id, b.center_radius.x, b.center_radius.y, b.center_radius.z, r, c_ndc.x, c_ndc.y, cx, cy);
                                }
                            }
                            log("ground truth: culled=% falseCulled=%", culledTotal, falseCulled);
                        }
                    }
                    render.data.occlusion_enabled = savedOcc;
                    free(cast(*u8) occluded_save_u32);
                    free(depth_save);
                }
            }
            render.data.compare_done = true;
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
