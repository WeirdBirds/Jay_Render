create_render :: () {
    log("%", render_app.q_indices);
    make_cmd_data(*render_app.cmd_pools.graphics, render_app.cmd_buffers.graphics, render_app.q_indices.graphics);
    make_cmd_data(*render_app.cmd_pools.transfer, render_app.cmd_buffers.transfer, render_app.q_indices.transfer);
    make_cmd_data(*render_app.cmd_pools.compute, render_app.cmd_buffers.compute, render_app.q_indices.compute);

    semaphore_info: VkSemaphoreCreateInfo = .{};
    fence_info:     VkFenceCreateInfo     = .{};
    fence_info.flags = .SIGNALED_BIT;

    for 0..FRAME_COUNT - 1 {
        vkCreateSemaphore(render_app.device, *semaphore_info, null, *render_app.render_data.image_available_semaphores[it]);
        vkCreateFence(render_app.device, *fence_info, null, *render_app.render_data.frame_fences[it]);
    }

    // Present-wait semaphores indexed per swapchain image, not per frame-in-flight.
    for 0..render_app.swapchain_data.swapchainImageCount - 1
        vkCreateSemaphore(render_app.device, *semaphore_info, null, *render_app.render_data.image_finished_semaphores[it]);

    create_gpu_timing();
    create_postprocess();
    render_app.sampler = create_sampler(.NEAREST, anisotropy = false, max_lod = 16.0);
}

destroy_render :: () {
    vkDeviceWaitIdle(render_app.device);

    destroy_postprocess();
    destroy_gpu_timing();

    if render_app.sampler
        vkDestroySampler(render_app.device, render_app.sampler, null);
    render_app.sampler = VK_NULL_HANDLE;

    // Destroy loaded textures
    for 0..cast(s64) render_app.texture_count - 1
        destroy_texture(*render_app.textures[it]);


    for 0..FRAME_COUNT - 1 {
        vkDestroyFence(render_app.device, render_app.render_data.frame_fences[it], null);
        vkDestroySemaphore(render_app.device, render_app.render_data.image_available_semaphores[it], null);
    }

    for 0..render_app.swapchain_data.swapchainImageCount - 1
        vkDestroySemaphore(render_app.device, render_app.render_data.image_finished_semaphores[it], null);

    vkDestroyCommandPool(render_app.device, render_app.cmd_pools.graphics, null);
    vkDestroyCommandPool(render_app.device, render_app.cmd_pools.transfer, null);
    vkDestroyCommandPool(render_app.device, render_app.cmd_pools.compute, null);
}

// Destroy and recreate fences + semaphores. Called during swapchain recreation
// to avoid corrupted sync state after a failed acquire on some drivers.
recreate_sync_objects :: () {
    // Destroy old
    for 0..FRAME_COUNT - 1 {
        vkDestroyFence(render_app.device, render_app.render_data.frame_fences[it], null);
        vkDestroySemaphore(render_app.device, render_app.render_data.image_available_semaphores[it], null);
    }

    for 0..render_app.swapchain_data.swapchainImageCount - 1
        vkDestroySemaphore(render_app.device, render_app.render_data.image_finished_semaphores[it], null);

    // Create fresh
    semaphore_info: VkSemaphoreCreateInfo = .{};
    fence_info:     VkFenceCreateInfo     = .{};
    fence_info.flags = .SIGNALED_BIT;

    for 0..FRAME_COUNT - 1 {
        vkCreateSemaphore(render_app.device, *semaphore_info, null, *render_app.render_data.image_available_semaphores[it]);
        vkCreateFence(render_app.device, *fence_info, null, *render_app.render_data.frame_fences[it]);
    }

    for 0..render_app.swapchain_data.swapchainImageCount - 1
        vkCreateSemaphore(render_app.device, *semaphore_info, null, *render_app.render_data.image_finished_semaphores[it]);
}

create_postprocess :: () {
    render_app.post_sampler = create_sampler(.NEAREST, .CLAMP_TO_EDGE);
    create_post_framebuffer();
}

destroy_postprocess :: () {
    destroy_texture(*render_app.post_framebuffer);

    if render_app.post_sampler != VK_NULL_HANDLE
        vkDestroySampler(render_app.device, render_app.post_sampler, null);

    render_app.post_sampler = VK_NULL_HANDLE;
}

create_gpu_timing :: () {
    reset_gpu_timing_history();
    set_gpu_timing_enabled(render_app.gpu_timing.enabled);

    if !render_app.gpu_timing.enabled
        return;

    query_info: VkQueryPoolCreateInfo = .{
        queryType  = .TIMESTAMP,
        queryCount = xx (FRAME_COUNT * GPU_TIMING_QUERY_COUNT),
    };

    result := vkCreateQueryPool(render_app.device, *query_info, null, *render_app.gpu_timing.query_pool);
    if result != .SUCCESS {
        render_app.gpu_timing.enabled = false;
        set_gpu_timing_enabled(false);
        log_error("Failed to create GPU timestamp query pool: %", result);
    }
}

destroy_gpu_timing :: () {
    if render_app.gpu_timing.query_pool != VK_NULL_HANDLE
        vkDestroyQueryPool(render_app.device, render_app.gpu_timing.query_pool, null);

    render_app.gpu_timing.query_pool = VK_NULL_HANDLE;
    set_gpu_timing_enabled(false);
    reset_gpu_timing_history();
}

reset_gpu_timing_history :: () {
    render_app.gpu_timing.slot_valid = .[false, false, false];
    clear_gpu_timings();
}

gpu_timing_query_base :: (frame_slot: s64) -> u32 {
    return cast(u32) (frame_slot * GPU_TIMING_QUERY_COUNT);
}

gpu_timing_mark_frame_start :: (cmd: VkCommandBuffer, frame_slot: s64) {
    if !render_app.gpu_timing.enabled || render_app.gpu_timing.query_pool == VK_NULL_HANDLE
        return;

    base := gpu_timing_query_base(frame_slot);
    vkCmdResetQueryPool(cmd, render_app.gpu_timing.query_pool, base, GPU_TIMING_QUERY_COUNT);
    vkCmdWriteTimestamp2(cmd, VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT,
                         render_app.gpu_timing.query_pool, base + GPU_TIMING_QUERY_FRAME_START);
}

gpu_timing_mark_after_compute :: (cmd: VkCommandBuffer, frame_slot: s64) {
    gpu_timing_write(cmd, frame_slot, GPU_TIMING_QUERY_AFTER_COMPUTE);
}

gpu_timing_mark_after_main :: (cmd: VkCommandBuffer, frame_slot: s64) {
    gpu_timing_write(cmd, frame_slot, GPU_TIMING_QUERY_AFTER_MAIN);
}

gpu_timing_mark_after_post :: (cmd: VkCommandBuffer, frame_slot: s64) {
    gpu_timing_write(cmd, frame_slot, GPU_TIMING_QUERY_AFTER_POST);
}

gpu_timing_mark_frame_end :: (cmd: VkCommandBuffer, frame_slot: s64) {
    if !render_app.gpu_timing.enabled || render_app.gpu_timing.query_pool == VK_NULL_HANDLE
        return;

    base := gpu_timing_query_base(frame_slot);
    vkCmdWriteTimestamp2(cmd, VK_PIPELINE_STAGE_2_BOTTOM_OF_PIPE_BIT,
                         render_app.gpu_timing.query_pool, base + GPU_TIMING_QUERY_FRAME_END);
    render_app.gpu_timing.slot_valid[frame_slot] = true;
}

gpu_timing_write :: (cmd: VkCommandBuffer, frame_slot: s64, query_index: u32) {
    if !render_app.gpu_timing.enabled || render_app.gpu_timing.query_pool == VK_NULL_HANDLE
        return;

    base := gpu_timing_query_base(frame_slot);
    vkCmdWriteTimestamp2(cmd, VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT,
                         render_app.gpu_timing.query_pool, base + query_index);
}

gpu_timing_collect :: (frame_slot: s64) {
    if !render_app.gpu_timing.enabled || render_app.gpu_timing.query_pool == VK_NULL_HANDLE
        return;

    if !render_app.gpu_timing.slot_valid[frame_slot]
        return;

    results: [GPU_TIMING_QUERY_COUNT]u64;
    results_ptr := cast(*u64) *results;
    base := gpu_timing_query_base(frame_slot);
    result := vkGetQueryPoolResults(render_app.device, render_app.gpu_timing.query_pool,
                                    base, GPU_TIMING_QUERY_COUNT,
                                    xx (GPU_TIMING_QUERY_COUNT * size_of(u64)), cast(*void) results_ptr,
                                    8, ._64_BIT);

    if result == .NOT_READY
        return;

    if result != .SUCCESS {
        log_error("Failed to read GPU timestamp queries: %", result);
        return;
    }

    compute_ns := gpu_ticks_to_ns(results[GPU_TIMING_QUERY_AFTER_COMPUTE] - results[GPU_TIMING_QUERY_FRAME_START]);
    main_ns    := gpu_ticks_to_ns(results[GPU_TIMING_QUERY_AFTER_MAIN]    - results[GPU_TIMING_QUERY_AFTER_COMPUTE]);
    post_ns    := gpu_ticks_to_ns(results[GPU_TIMING_QUERY_AFTER_POST]    - results[GPU_TIMING_QUERY_AFTER_MAIN]);
    tail_ns    := gpu_ticks_to_ns(results[GPU_TIMING_QUERY_FRAME_END]     - results[GPU_TIMING_QUERY_AFTER_POST]);
    total_ns   := gpu_ticks_to_ns(results[GPU_TIMING_QUERY_FRAME_END]     - results[GPU_TIMING_QUERY_FRAME_START]);

    set_gpu_timings(ns_to_us(compute_ns), ns_to_us(main_ns), ns_to_us(post_ns), ns_to_us(tail_ns), ns_to_us(total_ns));
}

gpu_ticks_to_ns :: (ticks: u64) -> float64 {
    return cast(float64) ticks * render_app.gpu_timing.timestamp_period_ns;
}

ns_to_us :: (ns: float64) -> u64 {
    return cast(u64) (ns / 1000.0 + 0.5);
}

make_cmd_data :: (pool: *VkCommandPool, buffers: []VkCommandBuffer, q_index: s64) {
    command_pool_info: VkCommandPoolCreateInfo = .{};
    command_pool_info.flags            = .RESET_COMMAND_BUFFER_BIT;
    command_pool_info.queueFamilyIndex = xx q_index;
    vkCreateCommandPool(render_app.device, *command_pool_info, null, pool);

    command_buffer_info: VkCommandBufferAllocateInfo = .{};
    command_buffer_info.commandPool        = pool.*;
    command_buffer_info.level              = .PRIMARY;
    command_buffer_info.commandBufferCount = FRAME_COUNT;
    vkAllocateCommandBuffers(render_app.device, *command_buffer_info, buffers.data);
}

Render_Data :: struct {
    frame_index := 0;
    // Fences and acquire semaphores are indexed by frame-in-flight index.
    frame_fences:               [FRAME_COUNT]VkFence;
    image_available_semaphores: [FRAME_COUNT]VkSemaphore;
    // Submit/present semaphores are indexed by swapchain image index.
    // This prevents reusing a semaphore that the presentation engine still holds.
    // See: https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html
    image_finished_semaphores:  [MAX_SWAPCHAIN_IMAGES]VkSemaphore;
}

Command_Pool_Set :: struct {
    graphics: VkCommandPool;
    transfer: VkCommandPool;
    compute:  VkCommandPool;
}

Command_Buffer_Set :: struct {
    graphics: [FRAME_COUNT]VkCommandBuffer;
    transfer: [FRAME_COUNT]VkCommandBuffer;
    compute:  [FRAME_COUNT]VkCommandBuffer;
}

Gpu_Timing_Data :: struct {
    enabled:             bool;
    query_pool:          VkQueryPool;
    timestamp_period_ns: float64;
    slot_valid:          [FRAME_COUNT]bool;
}

// Public for engine modules

FRAME_COUNT :: 3;
MAX_SWAPCHAIN_IMAGES :: 3;
GPU_TIMING_QUERY_COUNT :: 5;
GPU_TIMING_QUERY_FRAME_START :: 0;
GPU_TIMING_QUERY_AFTER_COMPUTE :: 1;
GPU_TIMING_QUERY_AFTER_MAIN :: 2;
GPU_TIMING_QUERY_AFTER_POST :: 3;
GPU_TIMING_QUERY_FRAME_END :: 4;
