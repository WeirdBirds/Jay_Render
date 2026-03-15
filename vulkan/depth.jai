Depth_Data :: struct {
    image:  VkImage;
    memory: VkDeviceMemory;
    view:   VkImageView;
    format: VkFormat;
}

find_supported_depth_format :: () -> VkFormat {
    candidates := VkFormat.[
        .D32_SFLOAT,
        .D32_SFLOAT_S8_UINT,
        .D24_UNORM_S8_UINT
    ];
    for candidates {
        props: VkFormatProperties;
        vkGetPhysicalDeviceFormatProperties(render_app.physical_device, it, *props);
        if (props.optimalTilingFeatures & .DEPTH_STENCIL_ATTACHMENT_BIT) != 0
            return it;
    }

    assert(false, "Failed to find supported depth format");
    return .UNDEFINED;
}


create_depth :: () {
    render_app.depth_data.format = find_supported_depth_format();

    extent := render_app.swapchain_data.swapchainExtent;

    image_info: VkImageCreateInfo = .{
        imageType     = ._2D,
        format        = render_app.depth_data.format,
        extent        = .{
            width  = extent.width,
            height = extent.height,
            depth  = 1,
        },
        mipLevels     = 1,
        arrayLayers   = 1,
        samples       = ._1_BIT,
        tiling        = .OPTIMAL,
        usage         = .DEPTH_STENCIL_ATTACHMENT_BIT,
        sharingMode   = .EXCLUSIVE,
        initialLayout = .UNDEFINED,
    };

    vkCreateImage(render_app.device, *image_info, null, *render_app.depth_data.image);

    mem_requirements: VkMemoryRequirements;
    vkGetImageMemoryRequirements(render_app.device, render_app.depth_data.image, *mem_requirements);


    alloc_info: VkMemoryAllocateInfo = .{
        allocationSize  = xx mem_requirements.size,
        memoryTypeIndex = find_memory_type(mem_requirements.memoryTypeBits, .DEVICE_LOCAL_BIT),
    };

    vkAllocateMemory(render_app.device, *alloc_info, null, *render_app.depth_data.memory);
    vkBindImageMemory(render_app.device, render_app.depth_data.image, render_app.depth_data.memory, 0);

    render_app.depth_data.view = create_image_view(render_app.depth_data.image, 
                                                   render_app.depth_data.format,
                                                   .{ .IDENTITY, .IDENTITY, .IDENTITY, .IDENTITY },
                                                   .{
                                                       aspectMask     = .DEPTH_BIT,
                                                       baseMipLevel   = 0,
                                                       levelCount     = 1,
                                                       baseArrayLayer = 0,
                                                       layerCount     = 1,
                                                   });

}

destroy_depth :: () {
    if render_app.depth_data.view != VK_NULL_HANDLE {
        vkDestroyImageView(render_app.device, render_app.depth_data.view, null);
        render_app.depth_data.view = VK_NULL_HANDLE;
    }

    if render_app.depth_data.image != VK_NULL_HANDLE {
        vkDestroyImage(render_app.device, render_app.depth_data.image, null);
        render_app.depth_data.image = VK_NULL_HANDLE;
    }

    if render_app.depth_data.memory != VK_NULL_HANDLE {
        vkFreeMemory(render_app.device, render_app.depth_data.memory, null);
        render_app.depth_data.memory = VK_NULL_HANDLE;
    }
}
