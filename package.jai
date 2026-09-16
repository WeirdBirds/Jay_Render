register_render_asset_types :: () {
        Asset_Registry.register_asset_type(Mesh_Data, mesh_asset_load, mesh_asset_unload);
        Asset_Registry.register_asset_type(Image_Data, image_asset_load, image_asset_unload);
        Asset_Registry.register_asset_type(Shader_Data, shader_asset_load, shader_asset_unload);
}

Jay_Render :: struct {

    after: Lifecycle.SimulationComplete;
    before: Lifecycle.RenderComplete;

    before_begin :: (engine: *Engine) {
        log("Starting Jay_Render");
        register_render_asset_types();
        validate_render_config();

        gpu_result := gpu_init();
        if gpu_result != .SUCCESS {
            renderer_start_failed(engine, "gpu_init failed");
            return;
        }
        render.gpu_initialized = true;

        present_text := SDL_getenv("JAY_PRESENT");
        present_preferred: [..] Present_Mode;
        if present_text != null && present_text[0] != 0 {
            if present_text[0] == 105 {      // 'i' = immediate
                array_add(*present_preferred, .IMMEDIATE);
            } else if present_text[0] == 109 { // 'm' = mailbox
                array_add(*present_preferred, .MAILBOX);
            } else if present_text[0] == 102 { // 'f' = fifo
                array_add(*present_preferred, .FIFO);
            }
        }

        #if OS == .LINUX {
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
            gpu_init_swapchain(display, surface, render.window_type, present_preferred);
        } else if render.window_type == .X11 {
            window_handle := cast(u64) SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
            if window_handle == 0 {
                renderer_start_failed(engine, "invalid X11 window handle");
                return;
            }
            gpu_init_swapchain(window_handle, render.window_type, present_preferred);
        } else if render.window_type == .WIN32 {
            window_handle := SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WIN32_HWND_POINTER, null);
            if window_handle == null {
                renderer_start_failed(engine, "invalid Win32 window handle");
                return;
            }
            gpu_init_swapchain(cast(u64) window_handle, render.window_type, present_preferred);
        } else {
            cocoa_window := SDL_GetPointerProperty(props, SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, null);
            if cocoa_window == null {
                renderer_start_failed(engine, "invalid Cocoa window handle");
                return;
            }
            gpu_init_swapchain(cast(u64) cocoa_window, render.window_type, present_preferred);
        }
        render.swapchain_initialized = true;

        render.queues.main = gpu_get_queue(.MAIN, 0);
        render.queues.compute = gpu_get_queue(.COMPUTE, 0);
        if render.queues.main == 0 || render.queues.compute == 0 {
            renderer_start_failed(engine, "required GPU queue unavailable");
            return;
        }

        render.data = render_init();

        cached := SDL_getenv("JAY_OCCLUSION");
        if cached != null && cached[0] == 48 {  // 48 = '0'
            render.data.occlusion_enabled = false;
        }

        render.data_initialized = true;
        create_pipelines(*render.data);
        create_depth_buffer();
        create_transparency_buffers();
        hiz_init(*render.data);

        log("Jay_Render started");
    }

    before_tick :: (engine: *Engine) {
        if !render.sdl_initialized return;

        t_poll := current_time_monotonic();
        ev: SDL_Event;
        while SDL_PollEvent(*ev) {
            if ev.type == {
                case xx SDL_EventType.QUIT;
                    engine.is_running = false;
                case xx SDL_EventType.KEY_DOWN;
                    if ev.key.key == SDLK_ESCAPE engine.is_running = false;
                case xx SDL_EventType.WINDOW_RESIZED; #through;
                case xx SDL_EventType.WINDOW_PIXEL_SIZE_CHANGED;
                    render.framebuffer_resized = true;
                case;
            }
        }
        render.data.poll_ms = to_float64_seconds(current_time_monotonic() - t_poll) * 1000.0;
    }

    after_tick :: (engine: *Engine) {
        if !render.data_initialized || !render.sdl_window return;

        t_frame := current_time_monotonic();
        w, h: s32;
        if !SDL_GetWindowSizeInPixels(render.sdl_window, *w, *h) return;
        if w <= 0 || h <= 0 return;

        if render.framebuffer_resized || !render.viewport.depth {
            #if DEBUG log("new framebuffer size: %x%", w, h);
            gpu_wait_idle();
            gpu_swapchain_resize(xx w, xx h);
            recreate_depth_buffer();
            recreate_transparency_buffers();
            hiz_recreate(*render.data);
            if !render.viewport.depth || !render.viewport.translucent_color_view return;
            render.framebuffer_resized = false;
        }

        t_acquire := current_time_monotonic();
        render.data.pre_ms = to_float64_seconds(t_acquire - t_frame) * 1000.0;
        acquire_result, swapchain_image := gpu_swapchain_acquire();
        t_submit := current_time_monotonic();
        render.data.acquire_ms = to_float64_seconds(t_submit - t_acquire) * 1000.0;
        if acquire_result == .ERROR_SWAPCHAIN_OUT_OF_DATE {
            render.framebuffer_resized = true;
            return;
        }
        if acquire_result != .SUCCESS || !swapchain_image {
            renderer_start_failed(engine, "swapchain acquisition failed");
            return;
        }
        render.viewport.image = swapchain_image;

        camera: Camera;
        camera.aspect_ratio = cast(float32) w / h;
        camera.fov = PI_2;
        camera.target = *render.viewport;
        camera.far = 50;

        // Static look-at: X-forward/Y-right/Z-up, camera looks at origin.
        cam_pos := Vec3.{1.6, -2.0, 1.2};
        cam_f := normalize(Vec3.{0, 0, 0} - cam_pos);
        cam_r := normalize(cross(Vec3.{0, 0, 1}, cam_f));
        cam_u := cross(cam_f, cam_r);
        cam_basis: Mat3;
        cam_basis._11 = cam_f.x;  cam_basis._21 = cam_f.y;  cam_basis._31 = cam_f.z;
        cam_basis._12 = cam_r.x;  cam_basis._22 = cam_r.y;  cam_basis._32 = cam_r.z;
        cam_basis._13 = cam_u.x;  cam_basis._23 = cam_u.y;  cam_basis._33 = cam_u.z;
        transform := to_matrix(Transform.{
            translation = cam_pos,
            rotation = to_quat(cam_basis),
            scale = Vec3.new(1),
        });

        camera_capture(camera, transform, engine.timer.delta_time);
        t_end := current_time_monotonic();
        render.data.submit_ms = to_float64_seconds(t_end - t_submit) * 1000.0;
        render.frames_rendered += 1;
    }

    after_end :: (engine: *Engine) {
        if render.gpu_initialized || render.sdl_initialized {
            log("Shutting Jay_Render down");
            renderer_shutdown();
        }
    }
}

#scope_file

renderer_shutdown :: () {
    if render.gpu_initialized {
        gpu_wait_idle();
    }

    if render.data_initialized {
        render_data_destroy(*render.data);
        render.data_initialized = false;
    }

    destroy_transparency_buffers();
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
