Swapchain_Data :: struct {
    swapchain:           VkSwapchainKHR;
    swapchainImageCount: u32;
    swapchainImages:     [MAX_SWAPCHAIN_IMAGES]VkImage;
    imageViews:          [MAX_SWAPCHAIN_IMAGES]VkImageView;
    swapchainExtent:     VkExtent2D;
    surfaceFormat:       VkSurfaceFormatKHR;
}

create_swapchain :: (old_swapchain: VkSwapchainKHR = VK_NULL_HANDLE) {
    formatCount: u32 = 0;
    vkGetPhysicalDeviceSurfaceFormatsKHR(render_app.physical_device, render_app.surface, *formatCount, null);

    formats: [MAX_SURFACE_FORMAT_COUNT]VkSurfaceFormatKHR;
    formatCount = min(formatCount, MAX_SURFACE_FORMAT_COUNT);
    vkGetPhysicalDeviceSurfaceFormatsKHR(render_app.physical_device, render_app.surface, *formatCount, formats.data);

    chosen_format := formats[0];

    if chosen_format.format == .UNDEFINED {
        chosen_format.format     = .B8G8R8A8_SRGB;
        chosen_format.colorSpace = .COLOR_SPACE_SRGB_NONLINEAR_KHR;
    } else {
        for index: 0..formatCount - 1 {
            format := formats[index];
            if format.format == .B8G8R8A8_SRGB && format.colorSpace == .COLOR_SPACE_SRGB_NONLINEAR_KHR {
                chosen_format = format;
                break;
            }
        }
    }

    render_app.swapchain_data.surfaceFormat = chosen_format;
    log("Swapchain surface format: % / %", chosen_format.format, chosen_format.colorSpace);

    presentModeCount: u32 = 0;
    vkGetPhysicalDeviceSurfacePresentModesKHR(render_app.physical_device, render_app.surface, *presentModeCount, null);
    presentModes: [MAX_PRESENT_MODE_COUNT]VkPresentModeKHR;
    presentModeCount = min(presentModeCount, MAX_PRESENT_MODE_COUNT);
    vkGetPhysicalDeviceSurfacePresentModesKHR(render_app.physical_device, render_app.surface, *presentModeCount, presentModes.data);

    presentMode: VkPresentModeKHR = .FIFO_KHR;   // always supported.
    for 0..presentModeCount - 1
        if presentModes[it] == .MAILBOX_KHR {
            presentMode = .MAILBOX_KHR;
            break;
        }

    render_app.swapchain_data.swapchainImageCount = ifx presentMode == .MAILBOX_KHR then PRESENT_MODE_MAILBOX_IMAGE_COUNT else PRESENT_MODE_DEFAULT_IMAGE_COUNT;

    surfaceCapabilities: VkSurfaceCapabilitiesKHR;

    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(render_app.physical_device, render_app.surface, *surfaceCapabilities);

    render_app.swapchain_data.swapchainExtent = surfaceCapabilities.currentExtent;
    if render_app.swapchain_data.swapchainExtent.width == U32_MAX {
        render_app.swapchain_data.swapchainExtent.width  = clamp(render_app.frame_size.width, surfaceCapabilities.minImageExtent.width, surfaceCapabilities.maxImageExtent.width);
        render_app.swapchain_data.swapchainExtent.height = clamp(render_app.frame_size.height, surfaceCapabilities.minImageExtent.height, surfaceCapabilities.maxImageExtent.height);
    }

    swapchain_info: VkSwapchainCreateInfoKHR;
    swapchain_info.surface          = render_app.surface;
    swapchain_info.minImageCount    = render_app.swapchain_data.swapchainImageCount;
    swapchain_info.imageFormat      = render_app.swapchain_data.surfaceFormat.format;
    swapchain_info.imageColorSpace  = render_app.swapchain_data.surfaceFormat.colorSpace;
    swapchain_info.imageExtent      = render_app.swapchain_data.swapchainExtent;
    swapchain_info.imageArrayLayers = 1;
    swapchain_info.imageUsage |= .COLOR_ATTACHMENT_BIT;
    swapchain_info.imageUsage |= .TRANSFER_DST_BIT;
    swapchain_info.imageSharingMode = .EXCLUSIVE;
    swapchain_info.preTransform     = surfaceCapabilities.currentTransform;
    swapchain_info.compositeAlpha   = .OPAQUE_BIT_KHR;
    swapchain_info.presentMode      = presentMode;
    swapchain_info.clipped          = VK_TRUE;
    swapchain_info.oldSwapchain     = old_swapchain;

    result := vkCreateSwapchainKHR(render_app.device, *swapchain_info, null, *render_app.swapchain_data.swapchain);

    if result != .SUCCESS
        log_error("Unable to create_swapchain: %", result);

    vkGetSwapchainImagesKHR(render_app.device, render_app.swapchain_data.swapchain, *render_app.swapchain_data.swapchainImageCount, null);
    assert(render_app.swapchain_data.swapchainImageCount <= MAX_SWAPCHAIN_IMAGES, "Swapchain image count (%) exceeds MAX_SWAPCHAIN_IMAGES (%)", render_app.swapchain_data.swapchainImageCount, MAX_SWAPCHAIN_IMAGES);
    vkGetSwapchainImagesKHR(render_app.device, render_app.swapchain_data.swapchain, *render_app.swapchain_data.swapchainImageCount, render_app.swapchain_data.swapchainImages.data);

    for index: 0..render_app.swapchain_data.swapchainImageCount - 1
        render_app.swapchain_data.imageViews[index] = create_swapchain_image_view(render_app.swapchain_data.swapchainImages[index], render_app.swapchain_data.surfaceFormat.format);
}

destroy_swapchain :: () {
    for index: 0..render_app.swapchain_data.swapchainImageCount - 1
        vkDestroyImageView(render_app.device, render_app.swapchain_data.imageViews[index], null);

    vkDestroySwapchainKHR(render_app.device, render_app.swapchain_data.swapchain, null);
}

recreate_swapchain :: () {
    // Wait until the window has a non-zero size (e.g. minimized)
    w, h: s32;
    SDL_GetWindowSizeInPixels(render_app.window, *w, *h);
    while w == 0 || h == 0 {
        SDL_WaitEvent(null);
        SDL_GetWindowSizeInPixels(render_app.window, *w, *h);
    }

    vkDeviceWaitIdle(render_app.device);

    // Save old swapchain handle — the driver can retire internal resources
    // more gracefully when we pass it to vkCreateSwapchainKHR.
    old_swapchain := render_app.swapchain_data.swapchain;

    // Destroy image views (they reference old swapchain images)
    for index: 0..render_app.swapchain_data.swapchainImageCount - 1
        vkDestroyImageView(render_app.device, render_app.swapchain_data.imageViews[index], null);

    // Update frame size from the actual window
    render_app.frame_size.width  = xx w;
    render_app.frame_size.height = xx h;

    // Create new swapchain, passing old handle so the driver can reuse resources
    create_swapchain(old_swapchain);

    // Depth and post-process framebuffer depend on swapchain extent and must be recreated.
    destroy_texture(*render_app.post_framebuffer);
    destroy_depth();
    create_depth();
    create_post_framebuffer();

    destroy_pipeline();
    create_pipeline();

    // Now destroy the old swapchain handle
    vkDestroySwapchainKHR(render_app.device, old_swapchain, null);

    // Don't recreate sync objects — after vkDeviceWaitIdle all fences are
    // signaled and semaphores are unsignaled, so they're in a clean state.
    // Destroying/recreating them crashes Nvidia 590.x drivers.

    // Reset frame index so we start clean with fence[0]
    render_app.render_data.frame_index = 0;
    reset_gpu_timing_history();

    render_app.framebuffer_resized     = false;

    log("Swapchain recreated: %x%", render_app.swapchain_data.swapchainExtent.width, render_app.swapchain_data.swapchainExtent.height);
}

#scope_file

MAX_PRESENT_MODE_COUNT :: 6; // At the moment in spec
MAX_SURFACE_FORMAT_COUNT :: 16;

PRESENT_MODE_MAILBOX_IMAGE_COUNT: u32: 3;
PRESENT_MODE_DEFAULT_IMAGE_COUNT: u32: 2;
