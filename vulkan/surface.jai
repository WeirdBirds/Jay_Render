create_surface :: () {
    #if OS == .LINUX {
        props := SDL_GetWindowProperties(render_app.window);

        driver: string = to_string(SDL_GetCurrentVideoDriver());

        log("Video deiver: %", driver);

        surface_info := VkWaylandSurfaceCreateInfoKHR.{};
        surface_info.display = xx SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, null);
        surface_info.surface = xx SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, null);

        if surface_info.display == null || surface_info.surface == null {
            log_error("Unable to get wayland device or surface");
            exit(1);
        }

        result := vkCreateWaylandSurfaceKHR(render_app.instance, *surface_info, null, *render_app.surface);
        if result != .SUCCESS {
        log_error("Unable to create Vulkan surface: %", result);
        }
    }
}

destroy_surface :: () {
    #if OS == .LINUX {
        vkDestroySurfaceKHR(render_app.instance, render_app.surface, null);
    }
}


