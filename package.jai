
Jay_Render :: struct {

    after: Lifecycle.SimulationComplete;
    before: Lifecycle.RenderComplete;

    before_begin :: (engine: *Engine) {
        log("Starting Jay_Render");

        default_logger = context.logger;

        if (SDL_getenv("WAYLAND_DISPLAY")) {

            SDL_SetHint(SDL_HINT_VIDEO_DRIVER, "wayland");

        }
        SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO);

        render_app.frame_size = .{ 1600, 800 };

        render_app.window = SDL_CreateWindow("Hello Sailor", xx render_app.frame_size.width, xx render_app.frame_size.height, SDL_WINDOW_VULKAN);

        init_vulkan();
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
                case; 
            } 
        }
    }

    after_tick :: (engine: *Engine) {
        draw_frame();
    }


    after_end :: (engine: *Engine) {
        log("\nShutting down!");
        deinit_vulkan();
        log("Bye!\n");
    }
}


#scope_module

Render_App :: struct {
    frame_size: Frame_Size;
    window: *SDL_Window; 
    instance: VkInstance;
    surface: VkSurfaceKHR;
    physical_device: VkPhysicalDevice;
    device: VkDevice;
    q_indices: Queue_Indices;
    queues: Queue_Set = .{};
    swapchain_data: Swapchain_Data;
    render_data: Render_Data;
    cmd_pools: Command_Pool_Set;
    cmd_buffers: Command_Buffer_Set;
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

