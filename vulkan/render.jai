create_render :: () {
    log("%", render_app.q_indices);
    make_cmd_data(*render_app.cmd_pools.graphics, render_app.cmd_buffers.graphics, render_app.q_indices.graphics);
    make_cmd_data(*render_app.cmd_pools.transfer, render_app.cmd_buffers.transfer, render_app.q_indices.transfer);
    make_cmd_data(*render_app.cmd_pools.compute, render_app.cmd_buffers.compute, render_app.q_indices.compute);

    semaphore_info: VkSemaphoreCreateInfo = .{};
    fence_info: VkFenceCreateInfo = .{};
    fence_info.flags = .SIGNALED_BIT;

    for 0..FRAME_COUNT - 1 {
        vkCreateSemaphore(render_app.device, *semaphore_info, null, *render_app.render_data.image_available_semaphores[it]);
        vkCreateFence(render_app.device, *fence_info, null, *render_app.render_data.frame_fences[it]);
    }

    // Present-wait semaphores indexed per swapchain image, not per frame-in-flight.
    for 0..render_app.swapchain_data.swapchainImageCount - 1 {
        vkCreateSemaphore(render_app.device, *semaphore_info, null, *render_app.render_data.image_finished_semaphores[it]);
    }
}

destroy_render :: () {
    vkDeviceWaitIdle(render_app.device);

    for 0..FRAME_COUNT - 1 {
        vkDestroyFence(render_app.device, render_app.render_data.frame_fences[it], null);
        vkDestroySemaphore(render_app.device, render_app.render_data.image_available_semaphores[it], null);
    }

    for 0..render_app.swapchain_data.swapchainImageCount - 1 {
        vkDestroySemaphore(render_app.device, render_app.render_data.image_finished_semaphores[it], null);
    }

    vkDestroyCommandPool(render_app.device, render_app.cmd_pools.graphics, null);
    vkDestroyCommandPool(render_app.device, render_app.cmd_pools.transfer, null);
    vkDestroyCommandPool(render_app.device, render_app.cmd_pools.compute, null);
}

make_cmd_data :: (
        pool: *VkCommandPool,
        buffers: []VkCommandBuffer,
        q_index: s64) {
    command_pool_info: VkCommandPoolCreateInfo = .{};
    command_pool_info.flags = .RESET_COMMAND_BUFFER_BIT;
    command_pool_info.queueFamilyIndex = xx q_index;
    vkCreateCommandPool(render_app.device, *command_pool_info, null, pool);

    command_buffer_info: VkCommandBufferAllocateInfo = .{};
    command_buffer_info.commandPool = pool.*;
    command_buffer_info.level = .PRIMARY;
    command_buffer_info.commandBufferCount = FRAME_COUNT;
    vkAllocateCommandBuffers(render_app.device, *command_buffer_info, buffers.data);
}

Render_Data :: struct {
    frame_index := 0;
    // Fences and acquire semaphores are indexed by frame-in-flight index.
    frame_fences: [FRAME_COUNT]VkFence;
    image_available_semaphores: [FRAME_COUNT]VkSemaphore;
    // Submit/present semaphores are indexed by swapchain image index.
    // This prevents reusing a semaphore that the presentation engine still holds.
    // See: https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html
    image_finished_semaphores: [MAX_SWAPCHAIN_IMAGES]VkSemaphore;
}

Command_Pool_Set :: struct {
    graphics: VkCommandPool;
    transfer: VkCommandPool;
    compute: VkCommandPool;
}

Command_Buffer_Set :: struct {
    graphics: [FRAME_COUNT]VkCommandBuffer;
    transfer: [FRAME_COUNT]VkCommandBuffer;
    compute: [FRAME_COUNT]VkCommandBuffer;
}

#scope_module

FRAME_COUNT          :: 3;
MAX_SWAPCHAIN_IMAGES :: 3;
