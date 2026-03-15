#load "test_render/test.jai";

COMPOSER : ComposerType = .UNKNOWN;

Jay_Render :: struct {

    after: Lifecycle.SimulationComplete;
    before: Lifecycle.RenderComplete;

    before_begin :: (engine: *Engine) {
        log("Starting Jay_Render");

        default_logger = context.logger;

        #if OS == .LINUX {
            if (!LINUX_RENDERDOC && SDL_getenv("WAYLAND_DISPLAY")) {
                COMPOSER = .WAYLAND;
                SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "wayland");
            } else {
                COMPOSER = .X11;
            }
        }

        SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO);
        
        render_app.frame_size = .{ 1600, 800 };

        render_app.window = SDL_CreateWindow("Hello Sailor", xx render_app.frame_size.width, xx render_app.frame_size.height, SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE);

        init_vulkan();
    }

    begin :: (engine: *Engine) {
        log("BEGIN!!!!----------------------------------------------------------");
        Test_Render.upload_geometry();
    }

    before_tick :: (engine: *Engine) {
        ev: SDL_Event;
        while(SDL_PollEvent(*ev)) {

            if ev.type == {

                case xx SDL_EventType.QUIT;
                    engine.is_running = false;

                case xx SDL_EventType.KEY_DOWN;
                    if ev.key.key == SDLK_ESCAPE
                        engine.is_running = false;

                case xx SDL_EventType.MOUSE_WHEEL;
                    wheel := cast(float32) ev.wheel.y;
                    if ev.wheel.direction == SDL_MouseWheelDirection.FLIPPED {
                        wheel = -wheel;
                    }
                    if wheel != 0 {
                        Test_Render.camera_zoom(wheel);
                    }

                case xx SDL_EventType.WINDOW_RESIZED;
                    // Ignore the initial configure event from Wayland — the
                    // swapchain was just created with the correct extent.
                    if render_app.frames_rendered > 0 {
                        render_app.framebuffer_resized = true;
                    }

                case; 
            } 
        }

        // Handle pending resize before drawing — recreate swapchain once,
        // then draw with the fresh swapchain.
        if render_app.framebuffer_resized {
            recreate_swapchain();
        }
    }

    after_tick :: (engine: *Engine) {
        Test_Render.set_time_seconds(cast(float32) engine.timer.time);
        success := Test_Render.draw_frame();
        render_app.frames_rendered += 1;
        if !success && !render_app.framebuffer_resized {
            // Acquire or present reported out-of-date — recreate for next frame.
            // Skip if framebuffer_resized is already set — before_tick will handle it.
            render_app.framebuffer_resized = true;
        }
    }

    after_end :: (engine: *Engine) {
        Test_Render.destroy_geometry();

        log("\nShutting down!");
        deinit_vulkan();
        log("Bye!\n");
    }
}


// Public for engine modules

ComposerType :: enum {
    UNKNOWN;
    WINDOWS;
    X11;
    WAYLAND;
}

Render_App :: struct {
    frame_size: Frame_Size;
    framebuffer_resized: bool;
    frames_rendered: u64;
    window: *SDL_Window; 
    instance: VkInstance;
    surface: VkSurfaceKHR;
    physical_device: VkPhysicalDevice;
    device: VkDevice;
    q_indices: Queue_Indices;
    queues: Queue_Set = .{};
    swapchain_data: Swapchain_Data;
    depth_data: Depth_Data;
    render_data: Render_Data;
    cmd_pools: Command_Pool_Set;
    cmd_buffers: Command_Buffer_Set;
    
    descriptor_data: Descriptor_Data;
    
    pipeline_data: Pipeline_Data;
    vertex_buffer: GPU_Buffer;
    index_buffer: GPU_Buffer;
}

Frame_Size :: struct {
    width: u32;
    height: u32;
}

Queue_Set :: struct {
    graphics: VkQueue;
    transfer: VkQueue;
    compute: VkQueue;
}

render_app := Render_App.{};
