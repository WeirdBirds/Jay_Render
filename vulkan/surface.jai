create_surface :: () {
    #if OS == .LINUX {
        props := SDL_GetWindowProperties(render_app.window);

        driver: string = to_string(SDL_GetCurrentVideoDriver());

        log("SDL: Video deiver: %", driver);
    
        if COMPOSER == .WAYLAND {
            surface_info := VkWaylandSurfaceCreateInfoKHR.{};
            surface_info.display = xx SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_DISPLAY_POINTER, null);
            surface_info.surface = xx SDL_GetPointerProperty(props, SDL_PROP_WINDOW_WAYLAND_SURFACE_POINTER, null);
            
            if surface_info.display == null || surface_info.surface == null {
                log_error("Unable to get wayland display or surface");
                exit(1);
            }

            log("Creating wayland surface");
            result := vkCreateWaylandSurfaceKHR(render_app.instance, *surface_info, null, *render_app.surface);
            log("Created");
            
            if result != .SUCCESS {
                log_error("Unable to create Vulkan surface: %", result);
            }
            return;
        }
        
        if COMPOSER == .X11 {
            surface_info := VkXlibSurfaceCreateInfoKHR.{};
            surface_info.dpy = xx SDL_GetPointerProperty(props, SDL_PROP_WINDOW_X11_DISPLAY_POINTER, null);
            surface_info.window = xx SDL_GetNumberProperty(props, SDL_PROP_WINDOW_X11_WINDOW_NUMBER, 0);
            
            if surface_info.dpy == null {
                log_error("Unable to get X11 display");
                exit(1);
            }
            if surface_info.window == 0 {
                log_error("Unable to get X11 window");
                exit(1);
            }

            log("Creating X11 surface");
            result := vkCreateXlibSurfaceKHR(render_app.instance, *surface_info, null, *render_app.surface);
            log("Created");

            
            if result != .SUCCESS {
                log_error("Unable to create Vulkan surface: %", result);
            }
            return;
        }
    }
}

destroy_surface :: () {
    #if OS == .LINUX {
        vkDestroySurfaceKHR(render_app.instance, render_app.surface, null);
    }
}


