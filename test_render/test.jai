camera: Camera = .{
    transform   = .{translation = .{0.0, 0.0, 2.5}},
    fov_radians = cast(float32)(60.0 * DEG_TO_RAD),
    near_plane  = cast(float32)0.1,
    far_plane   = cast(float32)100.0,
};

time_seconds: float32 = 0;

TEST_INSTANCE_COUNT :: 10;
TEST_UNIFORM_SCALE :: cast(float32)0.75;

test_instance_offsets:          [TEST_INSTANCE_COUNT]Vec3;
test_instance_base_angles:      [TEST_INSTANCE_COUNT]float32;
test_instance_rotation_speeds:  [TEST_INSTANCE_COUNT]float32;

Mesh :: struct {
    vertices: []Vertex;
    indices:  []u32;
}

Vertex :: struct {
    position: Vec3;
    color:    Vec3;
}

Test_Render :: struct {
    cube_vertices :: Vertex.[
        // Front face (z = +0.5) — Red
        .{position = .{-0.5, -0.5,  0.5}, color = .{1.0, 0.0, 0.0}}, //  0: bottom-left
        .{position = .{ 0.5, -0.5,  0.5}, color = .{1.0, 0.0, 0.0}}, //  1: bottom-right
        .{position = .{ 0.5,  0.5,  0.5}, color = .{1.0, 0.0, 0.0}}, //  2: top-right
        .{position = .{-0.5,  0.5,  0.5}, color = .{1.0, 0.0, 0.0}}, //  3: top-left
        // Back face (z = -0.5) — Green
        .{position = .{ 0.5, -0.5, -0.5}, color = .{0.0, 1.0, 0.0}}, //  4: bottom-left  (viewed from back)
        .{position = .{-0.5, -0.5, -0.5}, color = .{0.0, 1.0, 0.0}}, //  5: bottom-right
        .{position = .{-0.5,  0.5, -0.5}, color = .{0.0, 1.0, 0.0}}, //  6: top-right
        .{position = .{ 0.5,  0.5, -0.5}, color = .{0.0, 1.0, 0.0}}, //  7: top-left
        // Top face (y = +0.5) — Blue
        .{position = .{-0.5,  0.5,  0.5}, color = .{0.0, 0.0, 1.0}}, //  8: front-left
        .{position = .{ 0.5,  0.5,  0.5}, color = .{0.0, 0.0, 1.0}}, //  9: front-right
        .{position = .{ 0.5,  0.5, -0.5}, color = .{0.0, 0.0, 1.0}}, // 10: back-right
        .{position = .{-0.5,  0.5, -0.5}, color = .{0.0, 0.0, 1.0}}, // 11: back-left
        // Bottom face (y = -0.5) — Yellow
        .{position = .{-0.5, -0.5, -0.5}, color = .{1.0, 1.0, 0.0}}, // 12: back-left
        .{position = .{ 0.5, -0.5, -0.5}, color = .{1.0, 1.0, 0.0}}, // 13: back-right
        .{position = .{ 0.5, -0.5,  0.5}, color = .{1.0, 1.0, 0.0}}, // 14: front-right
        .{position = .{-0.5, -0.5,  0.5}, color = .{1.0, 1.0, 0.0}}, // 15: front-left
        // Right face (x = +0.5) — Cyan
        .{position = .{ 0.5, -0.5,  0.5}, color = .{0.0, 1.0, 1.0}}, // 16: front-bottom
        .{position = .{ 0.5, -0.5, -0.5}, color = .{0.0, 1.0, 1.0}}, // 17: back-bottom
        .{position = .{ 0.5,  0.5, -0.5}, color = .{0.0, 1.0, 1.0}}, // 18: back-top
        .{position = .{ 0.5,  0.5,  0.5}, color = .{0.0, 1.0, 1.0}}, // 19: front-top
        // Left face (x = -0.5) — Purple
        .{position = .{-0.5, -0.5, -0.5}, color = .{1.0, 0.0, 1.0}}, // 20: back-bottom
        .{position = .{-0.5, -0.5,  0.5}, color = .{1.0, 0.0, 1.0}}, // 21: front-bottom
        .{position = .{-0.5,  0.5,  0.5}, color = .{1.0, 0.0, 1.0}}, // 22: front-top
        .{position = .{-0.5,  0.5, -0.5}, color = .{1.0, 0.0, 1.0}}  // 23: back-top
    ];

    cube_indices :: u32.[
        // Front   (0,  1,  2,  3)
        0, 1, 2, 2, 3, 0,
        // Back    (4,  5,  6,  7)
        4, 5, 6, 6, 7, 4,
        // Top     (8,  9, 10, 11)
        8, 9, 10, 10, 11, 8,
        // Bottom  (12, 13, 14, 15)
        12, 13, 14, 14, 15, 12,
        // Right   (16, 17, 18, 19)
        16, 17, 18, 18, 19, 16,
        // Left    (20, 21, 22, 23)
        20, 21, 22, 22, 23, 20
    ];

    camera_zoom :: (delta: float32) {
        camera.transform.translation.z = max(0.5, min(20.0, camera.transform.translation.z - delta * 0.2));
    }

    set_time_seconds :: (t: float32) {
        time_seconds = t;
    }

    upload_geometry :: () {
        assert(TEST_INSTANCE_COUNT <= MAX_OBJECTS_PER_FRAME,
               "TEST_INSTANCE_COUNT (%) exceeds MAX_OBJECTS_PER_FRAME (%)", TEST_INSTANCE_COUNT, MAX_OBJECTS_PER_FRAME);

        // Copy vertices to mutable array and rotate
        vertices:         [cube_vertices.count]Vertex = cube_vertices;
        rotation := to_matrix(to_quat(Euler.{45, 45,  0}));
        for *vertices
            it.position = rotation * it.position;

        // Create device-local vertex buffer
        vertex_size := size_of(Vertex) * vertices.count;
        render_app.vertex_buffer = create_buffer(
        xx vertex_size,
        .VERTEX_BUFFER_BIT | .TRANSFER_DST_BIT,
        .DEVICE_LOCAL_BIT);

        log("Upload vertices");
        upload_buffer_data_sync(*render_app.vertex_buffer, vertices.data, xx vertex_size);
        // Create device-local index buffer
        index_size := size_of(u32) * cube_indices.count;
        render_app.index_buffer = create_buffer(
        xx index_size,
        .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT,
        .DEVICE_LOCAL_BIT);

        log("Upload indices");
        upload_buffer_data_sync(*render_app.index_buffer, cube_indices.data, xx index_size);

        SDL_srand(1337);
        for 0..TEST_INSTANCE_COUNT - 1 {
            test_instance_offsets[it]         = .{
                SDL_randf() * 5.0 - 2.5,
                SDL_randf() * 3.0 - 1.5,
                -(1.5 + SDL_randf() * 6.0)
            };
            test_instance_base_angles[it]     = SDL_randf() * 6.2831855;
            test_instance_rotation_speeds[it] = 0.4 + SDL_randf() * 1.2;
        }
    }

    destroy_geometry :: () {
        // Wait for all GPU work to complete before destroying buffers
        vkDeviceWaitIdle(render_app.device);
        destroy_buffer(*render_app.vertex_buffer);
        destroy_buffer(*render_app.index_buffer);
    }

    draw_frame :: () -> bool {
        u64_low, u64_high := get_integer_range(u64);

        render_app.render_data.frame_index += 1;
        index := render_app.render_data.frame_index % FRAME_COUNT;
        vkWaitForFences(render_app.device, 1, *render_app.render_data.frame_fences[index], VK_TRUE, u64_high);

        imageIndex:       u32;
        acquire_result := vkAcquireNextImageKHR(render_app.device, render_app.swapchain_data.swapchain, u64_high, render_app.render_data.image_available_semaphores[index], VK_NULL_HANDLE, *imageIndex);

        if acquire_result == .ERROR_OUT_OF_DATE_KHR || acquire_result == .SUBOPTIMAL_KHR
            return false;

        if acquire_result != .SUCCESS {
            log_error("Failed to acquire swapchain image: %", acquire_result);
            return false;
        }

        // Only reset the fence after a successful acquire — if we returned early
        // the fence stays signaled so the next frame doesn't deadlock.
        vkResetFences(render_app.device, 1, *render_app.render_data.frame_fences[index]);

        beginInfo:        VkCommandBufferBeginInfo;
        beginInfo.flags = .ONE_TIME_SUBMIT_BIT;

        vkBeginCommandBuffer(render_app.cmd_buffers.graphics[index], *beginInfo);

        cmd := render_app.cmd_buffers.graphics[index];
        extent := render_app.swapchain_data.swapchainExtent;

        // --- Barrier: UNDEFINED -> COLOR_ATTACHMENT_OPTIMAL ---
        // Transition swapchain image for rendering. oldLayout = UNDEFINED because
        // we don't care about previous contents (loadOp = CLEAR will overwrite).
        subResourceRange: VkImageSubresourceRange = .{
            aspectMask     = .COLOR_BIT,
            baseMipLevel   = 0,
            levelCount     = VK_REMAINING_MIP_LEVELS,
            baseArrayLayer = 0,
            layerCount     = VK_REMAINING_ARRAY_LAYERS,
        };

        imgMemoryBarrier: VkImageMemoryBarrier = .{
            srcAccessMask       = 0,
            dstAccessMask       = .COLOR_ATTACHMENT_WRITE_BIT,
            oldLayout           = .UNDEFINED,
            newLayout           = .COLOR_ATTACHMENT_OPTIMAL,
            srcQueueFamilyIndex = xx render_app.q_indices.graphics,
            dstQueueFamilyIndex = xx render_app.q_indices.graphics,
            image               = render_app.swapchain_data.swapchainImages[imageIndex],
            subresourceRange    = subResourceRange,
        };

        vkCmdPipelineBarrier(cmd, .TOP_OF_PIPE_BIT, .COLOR_ATTACHMENT_OUTPUT_BIT,
                             0, 0, null, 0, null, 1, *imgMemoryBarrier);


        depth_subresource_range: VkImageSubresourceRange = .{
            aspectMask     = .DEPTH_BIT,
            baseMipLevel   = 0,
            levelCount     = 1,
            baseArrayLayer = 0,
            layerCount     = 1,
        };

        depth_barrier: VkImageMemoryBarrier = .{
            srcAccessMask       = 0,
            dstAccessMask       = .DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
            oldLayout           = .UNDEFINED,
            newLayout           = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            srcQueueFamilyIndex = xx render_app.q_indices.graphics,
            dstQueueFamilyIndex = xx render_app.q_indices.graphics,
            image               = render_app.depth_data.image,
            subresourceRange    = depth_subresource_range,
        };

        vkCmdPipelineBarrier(cmd, .TOP_OF_PIPE_BIT, .EARLY_FRAGMENT_TESTS_BIT,
                             0, 0, null, 0, null, 1, *depth_barrier);

        // --- Begin dynamic rendering ---
        // This replaces vkCmdBeginRenderPass. We tell Vulkan: render into this
        // image view, clear it first, and keep the result when done.
        clearColor:       VkClearValue;
        clearColor.color._float32 = float.[ 0.1, 0.1, 0.1, 1.0 ];

        color_attachment: VkRenderingAttachmentInfo = .{
            imageView   = render_app.swapchain_data.imageViews[imageIndex],
            imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
            loadOp      = .CLEAR,
            storeOp     = .STORE,
            clearValue  = clearColor,
        };

        clear_depth:      VkClearValue;
        clear_depth.depthStencil = .{depth = 1.0, stencil = 0};

        depth_attachment: VkRenderingAttachmentInfo = .{
            imageView   = render_app.depth_data.view,
            imageLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
            loadOp      = .CLEAR,
            storeOp     = .STORE,
            clearValue  = clear_depth,
        };

        rendering_info: VkRenderingInfo = .{
            renderArea           = .{offset = .{0, 0}, extent = extent},
            layerCount           = 1,
            colorAttachmentCount = 1,
            pColorAttachments    = *color_attachment,
            pDepthAttachment     = *depth_attachment,
        };

        vkCmdBeginRendering(cmd, *rendering_info);

        // --- Bind pipeline and set dynamic state ---
        vkCmdBindPipeline(cmd, .GRAPHICS, render_app.pipeline_data.pipeline);

        viewport: VkViewport = .{
            x        = 0,
            y        = 0,
            width    = xx extent.width,
            height   = xx extent.height,
            minDepth = 0.0,
            maxDepth = 1.0,
        };

        vkCmdSetViewport(cmd, 0, 1, *viewport);

        scissor: VkRect2D = .{offset = .{0, 0}, extent = extent};
        vkCmdSetScissor(cmd, 0, 1, *scissor);

        // --- Bind vertex and index buffers ---
        vertex_buffers: [1]VkBuffer = .[ render_app.vertex_buffer.buffer ];
        offsets:        [1]u64      = .[ 0 ];

        vkCmdBindVertexBuffers(cmd, 0, 1, vertex_buffers.data, offsets.data);
        vkCmdBindIndexBuffer(cmd, render_app.index_buffer.buffer, 0, .UINT32);

        aspect := cast(float32)extent.width / cast(float32)extent.height;
        projection := get_projection_matrix(camera, aspect);
        view := get_view_matrix(camera);
        globals:          Global_Uniforms;
        globals.view       = view;
        globals.proj       = projection;
        globals.resolution = .{ cast(float32)extent.width, cast(float32)extent.height };
        globals.time       = time_seconds;
        memcpy(render_app.descriptor_data.global_ubo_mapped[index], *globals, size_of(Global_Uniforms));

        object_data: [TEST_INSTANCE_COUNT]Object_Data;
        for 0..TEST_INSTANCE_COUNT - 1 {
            model := Mat4.identity();
            angle := test_instance_base_angles[it] + time_seconds * test_instance_rotation_speeds[it];
            set_rotation(*model, angle, Vec3.{0.0, 1.0, 0.0});
            scale(*model, Vec3.{ TEST_UNIFORM_SCALE, TEST_UNIFORM_SCALE, TEST_UNIFORM_SCALE });
            set_translation(*model, test_instance_offsets[it]);
            object_data[it].model = model;
        }
        memcpy(render_app.descriptor_data.object_ssbo_mapped[index], object_data.data,
               size_of(Object_Data) * TEST_INSTANCE_COUNT);

        indirect_cmd: VkDrawIndexedIndirectCommand = .{
            indexCount    = xx cube_indices.count,
            instanceCount = TEST_INSTANCE_COUNT,
            firstIndex    = 0,
            vertexOffset  = 0,
            firstInstance = 0,
        };

        memcpy(render_app.descriptor_data.indirect_mapped, *indirect_cmd, size_of(VkDrawIndexedIndirectCommand));

        vkCmdBindDescriptorSets(cmd, .GRAPHICS, render_app.pipeline_data.pipeline_layout,
                                0, 1, *render_app.descriptor_data.sets[index], 0, null);

        // --- Draw indexed indirect ---
        vkCmdDrawIndexedIndirect(cmd, render_app.descriptor_data.indirect_buffer.buffer,
                                 0, 1, xx size_of(VkDrawIndexedIndirectCommand));

        vkCmdEndRendering(cmd);
        // --- Barrier: COLOR_ATTACHMENT_OPTIMAL -> PRESENT_SRC_KHR ---
        // Rendering is done. Transition the image so the presentation
        // engine can display it.
        imgMemoryBarrier.srcAccessMask = .COLOR_ATTACHMENT_WRITE_BIT;
        imgMemoryBarrier.dstAccessMask = 0;
        imgMemoryBarrier.oldLayout     = .COLOR_ATTACHMENT_OPTIMAL;
        imgMemoryBarrier.newLayout     = .PRESENT_SRC_KHR;
        vkCmdPipelineBarrier(cmd, .COLOR_ATTACHMENT_OUTPUT_BIT, .BOTTOM_OF_PIPE_BIT,
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
        submitInfo.pWaitDstStageMask    = VkPipelineStageFlags.[ .COLOR_ATTACHMENT_OUTPUT_BIT ].data;
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

        if present_result == .ERROR_OUT_OF_DATE_KHR || present_result == .SUBOPTIMAL_KHR
            return false;

        return true;
    }
}
