Renderer :: struct {
    sdl_window:          *SDL_Window;
    window_type:         Native_Window_Type;
    queues:               Queues;
    frames_rendered:     u64;
    framebuffer_resized: bool;
    viewport:            Render_Target;
    data:                Render_Data;

    sdl_initialized:      bool;
    gpu_initialized:      bool;
    swapchain_initialized: bool;
    data_initialized:     bool;
}

Render_Target :: struct {
    image: Gpu_Texture_View;
    depth: Gpu_Texture_View;
    depth_buffer: Gpu_Texture;

    translucent_color: Gpu_Texture;
    translucent_color_view: Gpu_Texture_View;
    translucent_coverage: Gpu_Texture;
    translucent_coverage_view: Gpu_Texture_View;
}

Queues :: struct {
    main:    Gpu_Queue;
    compute: Gpu_Queue;
}

render: Renderer = {};
