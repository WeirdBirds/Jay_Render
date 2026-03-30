post_pass :: (cmd: VkCommandBuffer, index: s64, image_index: u32,
              extent: VkExtent2D, clear_color: VkClearValue) {
    sub_resource_range: VkImageSubresourceRange = .{
        aspectMask     = .COLOR_BIT,
        baseMipLevel   = 0,
        levelCount     = VK_REMAINING_MIP_LEVELS,
        baseArrayLayer = 0,
        layerCount     = VK_REMAINING_ARRAY_LAYERS,
    };

    img_memory_barrier: VkImageMemoryBarrier = .{
        srcAccessMask       = 0,
        dstAccessMask       = .COLOR_ATTACHMENT_WRITE_BIT,
        oldLayout           = .UNDEFINED,
        newLayout           = .COLOR_ATTACHMENT_OPTIMAL,
        srcQueueFamilyIndex = xx render_app.q_indices.graphics,
        dstQueueFamilyIndex = xx render_app.q_indices.graphics,
        image               = render_app.swapchain_data.swapchainImages[image_index],
        subresourceRange    = sub_resource_range,
    };

    vkCmdPipelineBarrier(cmd, .TOP_OF_PIPE_BIT, .COLOR_ATTACHMENT_OUTPUT_BIT,
                         0, 0, null, 0, null, 1, *img_memory_barrier);

    post_color_attachment: VkRenderingAttachmentInfo = .{
        imageView   = render_app.swapchain_data.imageViews[image_index],
        imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
        loadOp      = .CLEAR,
        storeOp     = .STORE,
        clearValue  = clear_color,
    };

    post_rendering_info: VkRenderingInfo = .{
        renderArea           = .{offset = .{0, 0}, extent = extent},
        layerCount           = 1,
        colorAttachmentCount = 1,
        pColorAttachments    = *post_color_attachment,
    };

    viewport: VkViewport = .{
        x        = 0,
        y        = 0,
        width    = xx extent.width,
        height   = xx extent.height,
        minDepth = 0.0,
        maxDepth = 1.0,
    };

    scissor: VkRect2D = .{offset = .{0, 0}, extent = extent};

    vkCmdBeginRendering(cmd, *post_rendering_info);
    vkCmdBindPipeline(cmd, .GRAPHICS, render_app.pipeline_data.post_pipeline);
    vkCmdSetViewport(cmd, 0, 1, *viewport);
    vkCmdSetScissor(cmd, 0, 1, *scissor);

    post_descriptor_sets: [2]VkDescriptorSet = .[
        render_app.descriptor_data.sets[index],
        render_app.descriptor_data.post_set,
    ];
    vkCmdBindDescriptorSets(cmd, .GRAPHICS, render_app.pipeline_data.post_pipeline_layout,
                            0, 2, post_descriptor_sets.data, 0, null);
    vkCmdDraw(cmd, 3, 1, 0, 0);
    vkCmdEndRendering(cmd);

    img_memory_barrier.srcAccessMask = .COLOR_ATTACHMENT_WRITE_BIT;
    img_memory_barrier.dstAccessMask = 0;
    img_memory_barrier.oldLayout     = .COLOR_ATTACHMENT_OPTIMAL;
    img_memory_barrier.newLayout     = .PRESENT_SRC_KHR;

    vkCmdPipelineBarrier(cmd, .COLOR_ATTACHMENT_OUTPUT_BIT, .BOTTOM_OF_PIPE_BIT,
                         0, 0, null, 0, null, 1, *img_memory_barrier);
}
