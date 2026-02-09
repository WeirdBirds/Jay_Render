Swapchain_Data :: struct {
  swapchain: VkSwapchainKHR;
  swapchainImageCount: u32;
  swapchainImages: [MAX_SWAPCHAIN_IMAGES] VkImage;
  imageViews: [MAX_SWAPCHAIN_IMAGES] VkImageView;
  swapchainExtent: VkExtent2D;
  surfaceFormat  : VkSurfaceFormatKHR;
}

create_swapchain :: () {
    formatCount : u32 = 1;
    vkGetPhysicalDeviceSurfaceFormatsKHR(render_app.physical_device, render_app.surface, *formatCount, null);
    vkGetPhysicalDeviceSurfaceFormatsKHR(render_app.physical_device, render_app.surface, *formatCount, *render_app.swapchain_data.surfaceFormat);
    render_app.swapchain_data.surfaceFormat.format = ifx render_app.swapchain_data.surfaceFormat.format == .UNDEFINED then .B8G8R8A8_UNORM else render_app.swapchain_data.surfaceFormat.format;
  
    presentModeCount: u32 = 0;
    vkGetPhysicalDeviceSurfacePresentModesKHR(render_app.physical_device, render_app.surface, *presentModeCount, null);
    presentModes: [MAX_PRESENT_MODE_COUNT] VkPresentModeKHR;
    presentModeCount = min(presentModeCount, MAX_PRESENT_MODE_COUNT);
    vkGetPhysicalDeviceSurfacePresentModesKHR(render_app.physical_device, render_app.surface, *presentModeCount, presentModes.data);

    presentMode : VkPresentModeKHR = .FIFO_KHR;   // always supported.
    for 0..presentModeCount-1 {
        if presentModes[it] == .MAILBOX_KHR {
            presentMode = .MAILBOX_KHR;
            break;
        }
    }

    render_app.swapchain_data.swapchainImageCount = ifx presentMode == .MAILBOX_KHR  then PRESENT_MODE_MAILBOX_IMAGE_COUNT else PRESENT_MODE_DEFAULT_IMAGE_COUNT;

    surfaceCapabilities: VkSurfaceCapabilitiesKHR;

    vkGetPhysicalDeviceSurfaceCapabilitiesKHR(render_app.physical_device, render_app.surface, *surfaceCapabilities);

    render_app.swapchain_data.swapchainExtent = surfaceCapabilities.currentExtent;
    if render_app.swapchain_data.swapchainExtent.width == U32_MAX {
        render_app.swapchain_data.swapchainExtent.width  = clamp(render_app.frame_size.width, surfaceCapabilities.minImageExtent.width, surfaceCapabilities.maxImageExtent.width);
        render_app.swapchain_data.swapchainExtent.height = clamp(render_app.frame_size.height, surfaceCapabilities.minImageExtent.height, surfaceCapabilities.maxImageExtent.height);
    }

    swapchain_info: VkSwapchainCreateInfoKHR;
    swapchain_info.surface = render_app.surface;
    swapchain_info.minImageCount = render_app.swapchain_data.swapchainImageCount;
    swapchain_info.imageFormat = render_app.swapchain_data.surfaceFormat.format;
    swapchain_info.imageColorSpace = render_app.swapchain_data.surfaceFormat.colorSpace;
    swapchain_info.imageExtent = render_app.swapchain_data.swapchainExtent;
    swapchain_info.imageArrayLayers = 1;
    swapchain_info.imageUsage |= .COLOR_ATTACHMENT_BIT;
    swapchain_info.imageUsage |= .TRANSFER_DST_BIT;
    swapchain_info.imageSharingMode = .EXCLUSIVE;
    swapchain_info.preTransform = surfaceCapabilities.currentTransform;
    swapchain_info.compositeAlpha = .OPAQUE_BIT_KHR;
    swapchain_info.presentMode = presentMode;
    swapchain_info.clipped = VK_TRUE;

    result := vkCreateSwapchainKHR(render_app.device, *swapchain_info, null, *render_app.swapchain_data.swapchain);
    
    if result != .SUCCESS {
      log_error("Unable co create_swapchain: %", result);
    }

    vkGetSwapchainImagesKHR(render_app.device, render_app.swapchain_data.swapchain, *render_app.swapchain_data.swapchainImageCount, null);
    vkGetSwapchainImagesKHR(render_app.device, render_app.swapchain_data.swapchain, *render_app.swapchain_data.swapchainImageCount, render_app.swapchain_data.swapchainImages.data);


    for index: 0..render_app.swapchain_data.swapchainImageCount-1 {
        render_app.swapchain_data.imageViews[index] = create_swapchain_image_view(render_app.swapchain_data.swapchainImages[index], render_app.swapchain_data.surfaceFormat.format);
    }

}

destroy_swapchain :: () {
    for index: 0..render_app.swapchain_data.swapchainImageCount-1 { 
        vkDestroyImageView(render_app.device, render_app.swapchain_data.imageViews[index], null);
    }

    vkDestroySwapchainKHR(render_app.device, render_app.swapchain_data.swapchain, null); 
}

#scope_file

MAX_PRESENT_MODE_COUNT :: 6; // At the moment in spec

PRESENT_MODE_MAILBOX_IMAGE_COUNT :u32: 3;
PRESENT_MODE_DEFAULT_IMAGE_COUNT :u32: 2;

