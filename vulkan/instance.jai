
#if DEBUG {
debug_callback_handle : VkDebugReportCallbackEXT;
}

create_instance :: () {

    api_version: u32;
    vkEnumerateInstanceVersion(*api_version);
    
    log("Vulkan version: %.%.%", VK_VERSION_MAJOR(api_version), VK_VERSION_MINOR(api_version), VK_VERSION_PATCH(api_version));

    app_info: VkApplicationInfo = .{};
    app_info.pApplicationName = "Jay_Render".data;
    app_info.applicationVersion = VK_MAKE_VERSION(1, 0, 0);
    app_info.pEngineName = "Jay".data;
    app_info.engineVersion = VK_MAKE_VERSION(1, 0, 0);
    app_info.apiVersion = api_version;

    create_info: VkInstanceCreateInfo = .{};
    create_info.pApplicationInfo = *app_info;     

    #if !DEBUG {
        #if OS == .WINDOWS {
            extensions: [2] *u8;
            extensions[0] = VK_KHR_SURFACE_EXTENSION_NAME.data;
            extensions[1] = VK_KHR_WIN32_SURFACE_EXTENSION_NAME.data;
        } else #if OS == .LINUX {
            extensions: [2] *u8;
            extensions[0] = VK_KHR_SURFACE_EXTENSION_NAME.data;
            extensions[1] = ifx COMPOSER == .WAYLAND then VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME.data else VK_KHR_XLIB_SURFACE_EXTENSION_NAME.data; 
        }

    } else {
        #if OS == .WINDOWS {
            extensions: [3] *u8;
            extensions[0] = VK_KHR_SURFACE_EXTENSION_NAME.data;
            extensions[1] = VK_KHR_WIN32_SURFACE_EXTENSION_NAME.data;
            extensions[2] = VK_EXT_DEBUG_REPORT_EXTENSION_NAME.data;
        } else 
        #if OS == .LINUX {
            extensions: [3] *u8;
            extensions[0] = VK_KHR_SURFACE_EXTENSION_NAME.data;
            extensions[1] = ifx COMPOSER == .WAYLAND then VK_KHR_WAYLAND_SURFACE_EXTENSION_NAME.data else VK_KHR_XLIB_SURFACE_EXTENSION_NAME.data;
            extensions[2] = VK_EXT_DEBUG_REPORT_EXTENSION_NAME.data;
        }
    }

    create_info.enabledExtensionCount   = extensions.count;
    create_info.ppEnabledExtensionNames = extensions.data;

    result : VkResult = .ERROR_INITIALIZATION_FAILED;

    #if DEBUG {
        create_info.enabledLayerCount = 1;
        create_info.ppEnabledLayerNames = (*u8).["VK_LAYER_KHRONOS_validation"].data;
    }

    result = vkCreateInstance(*create_info, null, *render_app.instance);


    #if DEBUG {
        if result == .SUCCESS {
            vkCreateDebugReportCallbackEXT  : PFN_vkCreateDebugReportCallbackEXT = xx vkGetInstanceProcAddr(render_app.instance, "vkCreateDebugReportCallbackEXT");
            vkDestroyDebugReportCallbackEXT = xx vkGetInstanceProcAddr(render_app.instance, "vkDestroyDebugReportCallbackEXT");
            vkDebugReportMessageEXT         : PFN_vkDebugReportMessageEXT = xx vkGetInstanceProcAddr(render_app.instance, "vkDebugReportMessageEXT");

            if vkCreateDebugReportCallbackEXT {
                debug_callback_create_info: VkDebugReportCallbackCreateInfoEXT;
                debug_callback_create_info.flags |= .ERROR_BIT_EXT;
                debug_callback_create_info.flags |= .WARNING_BIT_EXT;
                debug_callback_create_info.pfnCallback = debug_callback;

                vkCreateDebugReportCallbackEXT(render_app.instance, *debug_callback_create_info, null, *debug_callback_handle);
            }
        }
    }

    if result != .SUCCESS {
        log_error("Unable to create Vulkan instance: %", result);
    }

    load_instance_proc_addresses(render_app.instance);

}


destroy_instance :: () {
    #if DEBUG {
        if vkDestroyDebugReportCallbackEXT && debug_callback_handle {
            vkDestroyDebugReportCallbackEXT(render_app.instance, debug_callback_handle, null);
        }
    }
    vkDestroyInstance(render_app.instance, null);
}
