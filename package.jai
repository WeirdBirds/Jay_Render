Jay_Render :: struct {

    after:  Lifecycle.SimulationComplete;
    before: Lifecycle.RenderComplete;
    
    before_begin :: (engine: *Engine) {
        log("Starting Jay_Render");

        gpu_init();

        #if OS == .LINUX {
            if SDL_getenv("WAYLAND_DISPLAY") != null {
                SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "wayland");
                render.window_type = .WAYLAND;
                log("Requested SDL video driver: wayland");
            } else {
                SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "x11");
                render.window_type = .X11;
                log("Requested SDL video driver: x11");
            }

            
            #if DEBUG {
                
                SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "x11");
                render.window_type = .X11;
                log("Requested SDL video driver: x11");
            }
        }

        SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO);

        window := SDL_CreateWindow("Hello Sailor", 1920, 1080, SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE);
        render.sdl_window = window;
        props := SDL_GetWindowProperties(window);
        
        if render.window_type == .WAYLAND {
            display := xx SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, null);
            surface := xx SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, null);
            gpu_init_swapchain(display, surface, render.window_type);
        } else {
            window_handle := cast(u64) SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
            gpu_init_swapchain(window_handle, render.window_type, .[]);
        }

        render.queues.main     = gpu_get_queue(.MAIN, 0);
        render.queues.compute  = gpu_get_queue(.COMPUTE, 0);
        render.queues.transfer = gpu_get_queue(.TRANSFER, 0);

        render.data = render_init();

        create_pipelines(*render.data);

        create_depth_buffer();

        log("Jay_Render started");
        
    }

    begin :: (engine: *Engine) { 
        mesh := get_asset(Mesh_Data, "/meshes/cow.obj");
        mesh_id := gpu_upload_mesh(*render.data, mesh);

        colors := Vec4.[
            .{x=0.8, y=0.3, z=0.2, w=1},
            .{x=0.3, y=0.8, z=0.2, w=1},
            .{x=0.2, y=0.3, z=0.8, w=1},
        ];

        material_gpu: [3] Gpu_Ptr;
        for i: 0..2 {
            ctx: #Context;
            push_context ctx {
                context.allocator = render.data.material_allocator;
                mat := New(Material_GPU);
                assert(mat != null);
                mat.* = .{ base_color = colors[i], texture_index = 0, sampler_index = 0, flags = 0 };
                material_gpu[i] = to_gpu_ptr(render.data.material_allocator, mat);
            }
        }
        
        gids: [3]u32;

        gids[0] = new_draw_group(*render.data, mesh_id, material_gpu[0]);
        gids[1] = new_draw_group(*render.data, mesh_id, material_gpu[1]);
        gids[2] = new_draw_group(*render.data, mesh_id, material_gpu[2]);

        for i: 0..100 {
            for j: 0..100 {
                
                transform := to_matrix(Transform.{
                    translation = Vec3.{xx (i-50), xx (j-50), 0},
                    rotation = to_quat(Radians.{
                        0,
                        0,
                         xx (i/(j+1))
                    }), 
                    scale = Vec3.new(0.1)
                });
                
                new_mesh_instance(*render.data, gids[(i+j)%3], transform, Vec4.new(get_translation(transform), 10));
            }
        }
        log("Assets loaded");

    }

    before_tick :: (engine: *Engine) {
        ev: SDL_Event;
        while SDL_PollEvent(*ev) {
            if ev.type == {
                case xx SDL_EventType.QUIT;
                    engine.is_running = false;

                case xx SDL_EventType.KEY_DOWN;
                    if ev.key.key == SDLK_ESCAPE {
                        engine.is_running = false;
                    }

                case xx SDL_EventType.WINDOW_RESIZED;
                    // Skip the initial Wayland configure event.
                    if render.frames_rendered > 0 {
                        render.framebuffer_resized = true;
                    }

                case;
            }
        }
    }

    after_tick :: (engine: *Engine) {
        
        w, h: s32;
        SDL_GetWindowSize(render.sdl_window, *w, *h);

        if render.framebuffer_resized {
            

            if w <= 0 || h <= 0 {
                return;
            }

            log("new window size: %x%", w, h);
            gpu_wait_idle();
            gpu_swapchain_resize(xx w, xx h);
            recreate_depth_buffer();
            render.framebuffer_resized = false;
        }
         
        acquire_result, swapchain_image := gpu_swapchain_acquire();
        if acquire_result != .SUCCESS || !swapchain_image { return; }
        render.viewport.image = swapchain_image;

        camera: Camera;
        camera.aspect_ratio = cast(float32)w/h;
        camera.fov = PI_2;
        camera.target = *render.viewport;
        camera.far = 50;

        sin_t :float32 = xx sin(engine.timer.time);

        transform := to_matrix(Transform.{
            translation = Vec3.{-20, -20 * sin_t, 20}, 
            rotation = to_quat(Euler.{
                0,
                -45,
                45 * sin_t
            }), 
            scale = Vec3.new(1)
        });

        log("% FPS, ", 1/engine.timer.delta_time);

        camera_capture(camera, transform);
        render.frames_rendered += 1;
    }

    after_end :: (engine: *Engine) {
        log("\nShutting Jay_Render down!");

        gpu_wait_idle();

        if render.data.compute_done {
            gpu_destroy_semaphore(render.data.compute_done);
        }

        destroy_depth_buffer();
        
        gpu_destroy_swapchain();
        gpu_shutdown();

        SDL_DestroyWindow(render.sdl_window);
        
        log("Bye!\n");
    }
}
