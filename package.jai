
Renderer :: struct {
    sdl_window:           *SDL_Window;
    window_type:          Native_Window_Type;
    queues:               Queues;
    square_pipeline:      Gpu_Pipeline;
    square_arena:         Gpu_Arena;
    square_vertex_params: Gpu_Ptr;
    square_pixel_data:    Gpu_Ptr;
    square_index_data:    Gpu_Ptr;
    frames_rendered:      u64;
    framebuffer_resized:  bool;
}

Queues :: struct {
    main:     Gpu_Queue;
    compute:  Gpu_Queue;
    transfer: Gpu_Queue;
}

render: Renderer = {};

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
            gpu_init_swapchain(window_handle, render.window_type);
        }

        render.queues.main     = gpu_get_queue(.MAIN, 0);
        render.queues.compute  = gpu_get_queue(.COMPUTE, 0);
        render.queues.transfer = gpu_get_queue(.TRANSFER, 0);

        shader_vfs := make_shader_vfs(get_shader);
        defer cleanup_shader_vfs(shader_vfs);

        ok_v, vs := compile_shader("/shaders/test_vs.slang", file_system = shader_vfs);
        defer free(vs.data);
        ok_f, fs := compile_shader("/shaders/test_fs.slang", file_system = shader_vfs);
        defer free(fs.data);

        clear_asset_registry(Shader_Text);

        blend_desc: Gpu_Blend_Desc;
        raster_desc: Gpu_Raster_Desc = .{
            cull = .CW,
            color_targets = .[
                .{format = .B8G8R8A8_UNORM}
            ],
            blend_state = *blend_desc,
        };

        render.square_pipeline = gpu_create_graphics_pipeline(vs, fs, raster_desc);

        // Allocate GPU arena for square vertex+color+index data.
        render.square_arena = gpu_make_arena(1024);

        // 4 vertex positions: float2 each (top-left origin, NDC space)
        Vertex2D :: struct { x: float; y: float; }
        vertex_buffer, vertex_gpu := gpu_arena_alloc(*render.square_arena, [4] Vertex2D);
        vertex_buffer.* = .[
            .{ 0.5,   0.5 },
            .{ 0.5,  -0.5 },
            .{ -0.5, -0.5 },
            .{ -0.5, +0.5 },
        ];

        // 4 vertex colors: float3 each (RGB, 12 floats total)
        vertex_colors, colors_gpu := gpu_arena_alloc(*render.square_arena, [12] float);
        vertex_colors.* = .[
            1., 0., 0.,    // red
            0., 1., 0.,    // green
            0., 0., 1.,    // blue
            1., 1., 1.,    // white
        ];

        // Vertex push-constant block: [positions_gpu_ptr, colors_gpu_ptr]
        param_block, vertex_params_gpu := gpu_arena_alloc(*render.square_arena, [2] Gpu_Ptr);
        param_block.* = .[vertex_gpu, colors_gpu];
        render.square_vertex_params = vertex_params_gpu;

        // Pixel push-constant data (unused, but pipeline expects it).
        pixel_data, pixel_gpu := gpu_arena_alloc(*render.square_arena, [3] float);
        pixel_data.* = .[1., 0., 1.];
        render.square_pixel_data = pixel_gpu;

        // 6 indices for 2 triangles forming a quad.
        index_buffer, index_gpu := gpu_arena_alloc(*render.square_arena, [6] u32);
        index_buffer.* = .[
            0, 3, 1,
            1, 3, 2,
        ];
        render.square_index_data = index_gpu;
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
        if render.framebuffer_resized {
            gpu_swapchain_resize();
            render.framebuffer_resized = false;
        }

        acquire_result, swapchain_image := gpu_swapchain_acquire();
        if acquire_result != .SUCCESS || !swapchain_image {
            return;
        }

        record_result, cmd_buff := gpu_start_command_recording(render.queues.main);
        if record_result != .SUCCESS {
            return;
        }

        render_desc := Gpu_Render_Pass_Desc.{
            color_targets = .[
                .{
                    view = swapchain_image,
                    load_op = .CLEAR,
                    store_op = .STORE,
                    clear_color._float = .[0, 0, 0, 1],
                }
            ]
        };
        gpu_begin_render_pass(cmd_buff, render_desc);
        gpu_set_depth_stencil_state(cmd_buff, .{depth_test = .NEVER, depth_mode = .NONE});

        gpu_set_pipeline(cmd_buff, render.square_pipeline);
        gpu_draw_indexed_instanced(cmd_buff, render.square_vertex_params, render.square_pixel_data, render.square_index_data, 6, 1);

        gpu_end_render_pass(cmd_buff);
        gpu_submit_and_present(cmd_buff);

        render.frames_rendered += 1;
    }

    after_end :: (engine: *Engine) {
        log("\nShutting Jay_Render down!");

        gpu_wait_idle();
        gpu_free_arena(render.square_arena);
        gpu_free_pipeline(render.square_pipeline);
        SDL_DestroyWindow(render.sdl_window);
        gpu_destroy_swapchain();
        gpu_shutdown();

        log("Bye!\n");
    }
}


get_window_type :: () -> Native_Window_Type {
    driver := to_string(SDL_GetCurrentVideoDriver());

    if driver == {
        case "x11"; return .X11;
        case "wayland"; return .WAYLAND;
        case "cocoa"; return .COCOA;
        case "windows"; return .WIN32;
        case; log_error("Unknown video driver: %", driver);
    };

    return .UNKNOWN;
}
