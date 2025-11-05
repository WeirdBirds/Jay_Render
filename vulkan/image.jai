create_image_view :: (image: VkImage, format: VkFormat, components: VkComponentMapping, subresource_range: VkImageSubresourceRange) -> VkImageView {
    create_info: VkImageViewCreateInfo;
    create_info.image = image;
    create_info.components = components;
    create_info.format = format;
    create_info.subresourceRange = subresource_range;
    create_info.viewType = ._2D;

    view: VkImageView;
    
    result := vkCreateImageView(render_app.device, *create_info, null, *view);

    if result != .SUCCESS {
        log_error("Unable to create image_view: %", result);
    }

    return view;
}
create_swapchain_image_view :: #bake_arguments 
    create_image_view(
        components = .{
            .IDENTITY,
            .IDENTITY,
            .IDENTITY,
            .IDENTITY
        }, 
        subresource_range = .{
            aspectMask = .COLOR_BIT,
            baseMipLevel = 0,
            levelCount = 1,
            baseArrayLayer = 0,
            layerCount = 1
        }
    );

