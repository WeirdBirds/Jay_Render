draw_frame :: () -> bool {

    u64_low, u64_high := get_integer_range(u64);

    render_app.render_data.frame_index += 1;
    index := render_app.render_data.frame_index % FRAME_COUNT;    
    vkWaitForFences(render_app.device, 1, *render_app.render_data.frame_fences[index], VK_TRUE, u64_high);

    imageIndex: u32;
    acquire_result := vkAcquireNextImageKHR(render_app.device, render_app.swapchain_data.swapchain, u64_high, render_app.render_data.image_available_semaphores[index], VK_NULL_HANDLE, *imageIndex);

    if acquire_result == .ERROR_OUT_OF_DATE_KHR || acquire_result == .SUBOPTIMAL_KHR {
        return false;
    }

    if acquire_result != .SUCCESS {
        log_error("Failed to acquire swapchain image: %", acquire_result);
        return false;
    }

    // Only reset the fence after a successful acquire — if we returned early
    // the fence stays signaled so the next frame doesn't deadlock.
    vkResetFences(render_app.device, 1, *render_app.render_data.frame_fences[index]);

    beginInfo: VkCommandBufferBeginInfo;
    beginInfo.flags = .ONE_TIME_SUBMIT_BIT;

    vkBeginCommandBuffer(render_app.cmd_buffers.graphics[index], *beginInfo);

    // @@ ...


    // Clear frame.
    subResourceRange : VkImageSubresourceRange;
    {
        using subResourceRange;
        aspectMask     = .COLOR_BIT;
        baseMipLevel   = 0;
        levelCount     = VK_REMAINING_MIP_LEVELS;
        baseArrayLayer = 0;
        layerCount     = VK_REMAINING_ARRAY_LAYERS;
    }
    
    // Change layout of image to be optimal for clearing
    imgMemoryBarrier : VkImageMemoryBarrier;
    {
        using imgMemoryBarrier;
        srcAccessMask       = 0;
        dstAccessMask       = .TRANSFER_WRITE_BIT;
        oldLayout           = .UNDEFINED;
        newLayout           = .TRANSFER_DST_OPTIMAL;
        srcQueueFamilyIndex = xx render_app.q_indices.graphics;
        dstQueueFamilyIndex = xx render_app.q_indices.graphics;
        image               = render_app.swapchain_data.swapchainImages[imageIndex];
        subresourceRange    = subResourceRange;
    }
    
    vkCmdPipelineBarrier(render_app.cmd_buffers.graphics[index], .TRANSFER_BIT, .TRANSFER_BIT, 
                         0, 0, null, 0, null, 1, *imgMemoryBarrier);

    clearColor : VkClearColorValue;
    {
        // Pick a color with which to clear the screen.
        color1 := Vec4.{1,  1, 0, 1};
        color2 := Vec4.{.5, 0, 1, 1};

        now := seconds_since_init();
        t := cos(cast(float) now) * .5 + .5;
        t = clamp(t, 0, 1);
        color := lerp(color1, color2, t);
        clearColor._float32 = color.values;
        // clearColor.float32 = float.[1, 1, 0, 1];
    }
    
    vkCmdClearColorImage(render_app.cmd_buffers.graphics[index], render_app.swapchain_data.swapchainImages[imageIndex], .TRANSFER_DST_OPTIMAL, *clearColor, 1, *subResourceRange);

    // Change layout of image to be optimal for presenting
    imgMemoryBarrier.srcAccessMask = .TRANSFER_WRITE_BIT;
    imgMemoryBarrier.dstAccessMask = .MEMORY_READ_BIT;
    imgMemoryBarrier.oldLayout     = .TRANSFER_DST_OPTIMAL;
    imgMemoryBarrier.newLayout     = .PRESENT_SRC_KHR;
    vkCmdPipelineBarrier(render_app.cmd_buffers.graphics[index], .TRANSFER_BIT, .BOTTOM_OF_PIPE_BIT,
        0, 0, null, 0, null, 1, *imgMemoryBarrier);


    vkEndCommandBuffer(render_app.cmd_buffers.graphics[index]);

    // image_available_semaphores indexed by frame-in-flight (index).
    // image_finished_semaphores indexed by swapchain image (imageIndex).
    // This ensures present-wait semaphores aren't reused while the presentation
    // engine still holds them. Acquiring the image guarantees the previous
    // present operation for that image has completed.
    submitInfo: VkSubmitInfo; 
    submitInfo.waitSemaphoreCount   = 1;
    submitInfo.pWaitSemaphores      = *render_app.render_data.image_available_semaphores[index];
    submitInfo.pWaitDstStageMask    = VkPipelineStageFlags.[.COLOR_ATTACHMENT_OUTPUT_BIT].data;
    submitInfo.commandBufferCount   = 1;
    submitInfo.pCommandBuffers      = *render_app.cmd_buffers.graphics[index];
    submitInfo.signalSemaphoreCount = 1;
    submitInfo.pSignalSemaphores    = *render_app.render_data.image_finished_semaphores[imageIndex];
    vkQueueSubmit(render_app.queues.graphics, 1, *submitInfo, render_app.render_data.frame_fences[index]);

    // Present.
    presentInfo: VkPresentInfoKHR;
    presentInfo.waitSemaphoreCount = 1;
    presentInfo.pWaitSemaphores    = *render_app.render_data.image_finished_semaphores[imageIndex];
    presentInfo.swapchainCount     = 1;
    presentInfo.pSwapchains        = *render_app.swapchain_data.swapchain;
    presentInfo.pImageIndices      = *imageIndex;
    present_result := vkQueuePresentKHR(render_app.queues.graphics, *presentInfo);

    if present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR {
        return false;
    }

    return true;
}



