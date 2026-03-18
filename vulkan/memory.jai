GPU_Buffer :: struct {
    buffer: VkBuffer;
    memory: VkDeviceMemory;
    size:   s64;
}

find_memory_type :: (type_filter: u32, properties: VkMemoryPropertyFlags) -> u32 {
    mem_props: VkPhysicalDeviceMemoryProperties;
    vkGetPhysicalDeviceMemoryProperties(render_app.physical_device, *mem_props);

    for i: 0..mem_props.memoryTypeCount - 1
        if (type_filter & (1 << i)) != 0 && (mem_props.memoryTypes[i].propertyFlags & properties) == properties
            return i;

    assert(false, "Failed to find suitable memory type (filter: %, properties: %)", type_filter, properties);
    return 0;
}

create_buffer :: (size: s64, usage: VkBufferUsageFlags, properties: VkMemoryPropertyFlags) -> GPU_Buffer {
    result: GPU_Buffer;
    result.size = size;


    buffer_info: VkBufferCreateInfo = .{
        size        = xx size,
        usage       = usage,
        sharingMode = .EXCLUSIVE
    };
    vkCreateBuffer(render_app.device, *buffer_info, null, *result.buffer);

    mem_requirements: VkMemoryRequirements;
    vkGetBufferMemoryRequirements(render_app.device, result.buffer, *mem_requirements);

    alloc_info: VkMemoryAllocateInfo = .{
        allocationSize  = xx mem_requirements.size,
        memoryTypeIndex = find_memory_type(mem_requirements.memoryTypeBits, properties)
    };

    vkAllocateMemory(render_app.device, *alloc_info, null, *result.memory);
    vkBindBufferMemory(render_app.device, result.buffer, result.memory, 0);

    return result;
}

destroy_buffer :: (buf: *GPU_Buffer) {
    vkDestroyBuffer(render_app.device, buf.buffer, null);
    vkFreeMemory(render_app.device, buf.memory, null);
    buf.buffer = VK_NULL_HANDLE;
    buf.memory = VK_NULL_HANDLE;
}

// Async version - caller manages synchronization (for frame-pipelined streaming)
// Returns the staging buffer - caller MUST destroy it after GPU completes
upload_buffer_data_async :: (dst: *GPU_Buffer, data: *void, size: s64) -> GPU_Buffer {
    staging := create_buffer(size, .TRANSFER_SRC_BIT, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);

    mapped: *void;
    vkMapMemory(render_app.device, staging.memory, 0, xx size, 0, *mapped);
    memcpy(mapped, data, size);
    vkUnmapMemory(render_app.device, staging.memory);

    cmd := render_app.cmd_buffers.transfer[0];
    begin_info: VkCommandBufferBeginInfo = .{ flags = .ONE_TIME_SUBMIT_BIT };
    vkBeginCommandBuffer(cmd, *begin_info);

    copy_region: VkBufferCopy = .{ size = xx size };
    vkCmdCopyBuffer(cmd, staging.buffer, dst.buffer, 1, *copy_region);

    vkEndCommandBuffer(cmd);

    submit_info: VkSubmitInfo = .{
        commandBufferCount = 1,
        pCommandBuffers    = *cmd
    };

    vkQueueSubmit(render_app.queues.transfer, 1, *submit_info, VK_NULL_HANDLE);

    // NOTE: Caller is responsible for:
    // 1. Waiting for completion (vkQueueWaitIdle or fence)
    // 2. Resetting the command buffer
    // 3. Destroying the staging buffer

    return staging;
}

// Sync version - blocks until transfer is complete, cleans up automatically
upload_buffer_data_sync :: (dst: *GPU_Buffer, data: *void, size: s64) {
    staging := create_buffer(size, .TRANSFER_SRC_BIT, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);

    mapped: *void;
    vkMapMemory(render_app.device, staging.memory, 0, xx size, 0, *mapped);
    memcpy(mapped, data, size);
    vkUnmapMemory(render_app.device, staging.memory);

    cmd := render_app.cmd_buffers.transfer[0];
    begin_info: VkCommandBufferBeginInfo = .{ flags = .ONE_TIME_SUBMIT_BIT };
    vkBeginCommandBuffer(cmd, *begin_info);

    copy_region: VkBufferCopy = .{ size = xx size };
    vkCmdCopyBuffer(cmd, staging.buffer, dst.buffer, 1, *copy_region);

    vkEndCommandBuffer(cmd);

    submit_info: VkSubmitInfo = .{
        commandBufferCount = 1,
        pCommandBuffers    = *cmd
    };

    vkQueueSubmit(render_app.queues.transfer, 1, *submit_info, VK_NULL_HANDLE);

    // Wait for GPU to finish
    vkQueueWaitIdle(render_app.queues.transfer);

    // Now safe to reset and clean up
    vkResetCommandBuffer(cmd, 0);
    destroy_buffer(*staging);

    #if DEBUG
        log("% bytes uploaded to GPU", size);
}
