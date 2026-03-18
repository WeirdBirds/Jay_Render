camera: Camera_Orbit = .{
    fov_radians = cast(float32)(60.0 * DEG_TO_RAD),
    near_plane  = cast(float32)0.1,
    far_plane   = cast(float32)1000.0,

    orbit_pitch = PI/2,
};


cube_mesh: Mesh : {
    vertices = .[
        // Front face (z = +0.5) — Red
        .{position = .{-0.5, -0.5,  0.5}, color = .{1.0, 0.0, 0.0}, uv = .{0.0, 1.0}}, //  0: bottom-left
        .{position = .{ 0.5, -0.5,  0.5}, color = .{1.0, 0.0, 0.0}, uv = .{1.0, 1.0}}, //  1: bottom-right
        .{position = .{ 0.5,  0.5,  0.5}, color = .{1.0, 0.0, 0.0}, uv = .{1.0, 0.0}}, //  2: top-right
        .{position = .{-0.5,  0.5,  0.5}, color = .{1.0, 0.0, 0.0}, uv = .{0.0, 0.0}}, //  3: top-left
        // Back face (z = -0.5) — Green
        .{position = .{ 0.5, -0.5, -0.5}, color = .{0.0, 1.0, 0.0}, uv = .{0.0, 1.0}}, //  4: bottom-left  (viewed from back)
        .{position = .{-0.5, -0.5, -0.5}, color = .{0.0, 1.0, 0.0}, uv = .{1.0, 1.0}}, //  5: bottom-right
        .{position = .{-0.5,  0.5, -0.5}, color = .{0.0, 1.0, 0.0}, uv = .{1.0, 0.0}}, //  6: top-right
        .{position = .{ 0.5,  0.5, -0.5}, color = .{0.0, 1.0, 0.0}, uv = .{0.0, 0.0}}, //  7: top-left
        // Top face (y = +0.5) — Blue
        .{position = .{-0.5,  0.5,  0.5}, color = .{0.0, 0.0, 1.0}, uv = .{0.0, 1.0}}, //  8: front-left
        .{position = .{ 0.5,  0.5,  0.5}, color = .{0.0, 0.0, 1.0}, uv = .{1.0, 1.0}}, //  9: front-right
        .{position = .{ 0.5,  0.5, -0.5}, color = .{0.0, 0.0, 1.0}, uv = .{1.0, 0.0}}, // 10: back-right
        .{position = .{-0.5,  0.5, -0.5}, color = .{0.0, 0.0, 1.0}, uv = .{0.0, 0.0}}, // 11: back-left
        // Bottom face (y = -0.5) — Yellow
        .{position = .{-0.5, -0.5, -0.5}, color = .{1.0, 1.0, 0.0}, uv = .{0.0, 1.0}}, // 12: back-left
        .{position = .{ 0.5, -0.5, -0.5}, color = .{1.0, 1.0, 0.0}, uv = .{1.0, 1.0}}, // 13: back-right
        .{position = .{ 0.5, -0.5,  0.5}, color = .{1.0, 1.0, 0.0}, uv = .{1.0, 0.0}}, // 14: front-right
        .{position = .{-0.5, -0.5,  0.5}, color = .{1.0, 1.0, 0.0}, uv = .{0.0, 0.0}}, // 15: front-left
        // Right face (x = +0.5) — Cyan
        .{position = .{ 0.5, -0.5,  0.5}, color = .{0.0, 1.0, 1.0}, uv = .{0.0, 1.0}}, // 16: front-bottom
        .{position = .{ 0.5, -0.5, -0.5}, color = .{0.0, 1.0, 1.0}, uv = .{1.0, 1.0}}, // 17: back-bottom
        .{position = .{ 0.5,  0.5, -0.5}, color = .{0.0, 1.0, 1.0}, uv = .{1.0, 0.0}}, // 18: back-top
        .{position = .{ 0.5,  0.5,  0.5}, color = .{0.0, 1.0, 1.0}, uv = .{0.0, 0.0}}, // 19: front-top
        // Left face (x = -0.5) — Purple
        .{position = .{-0.5, -0.5, -0.5}, color = .{1.0, 0.0, 1.0}, uv = .{0.0, 1.0}}, // 20: back-bottom
        .{position = .{-0.5, -0.5,  0.5}, color = .{1.0, 0.0, 1.0}, uv = .{1.0, 1.0}}, // 21: front-bottom
        .{position = .{-0.5,  0.5,  0.5}, color = .{1.0, 0.0, 1.0}, uv = .{1.0, 0.0}}, // 22: front-top
        .{position = .{-0.5,  0.5, -0.5}, color = .{1.0, 0.0, 1.0}, uv = .{0.0, 0.0}}  // 23: back-top
    ],
    indices  = u32.[
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
    ]
};

world_mesh :: #run -> Mesh {
    result: Mesh;

    WORLD_SIZE :: 100;
    WORLD_HEIGHT :: 100;

    vertices: [..]Vertex;
    indices: [..]u32;
    
    for coord: 0..WORLD_SIZE {
        {
            array_add(*vertices, .{
                position = .{xx coord, 0, 0},
                uv = .{0, 0}
            });

            array_add(*vertices, .{ 
                position = .{xx coord, 0, WORLD_HEIGHT},
                uv = .{0, 1}
            });
 
            array_add(*vertices, .{
                position = .{xx coord, WORLD_SIZE, WORLD_HEIGHT},
                uv = .{1, 1}
            });

            array_add(*vertices, .{
                position = .{xx coord, WORLD_SIZE, 0},
                uv = .{1, 0}
            });

            array_add(*indices, xx (vertices.count-4));
            array_add(*indices, xx (vertices.count-3));
            array_add(*indices, xx (vertices.count-2));
            array_add(*indices, xx (vertices.count-4));
            array_add(*indices, xx (vertices.count-2));
            array_add(*indices, xx (vertices.count-1));
        }

        {
            array_add(*vertices, .{
                position = .{ 0, xx coord, 0},
                uv = .{0, 0}
            });

            array_add(*vertices, .{ 
                position = .{ 0, xx coord, WORLD_HEIGHT},
                uv = .{0, 1}
            });

            array_add(*vertices, .{
                position = .{ WORLD_SIZE, xx coord, WORLD_HEIGHT},
                uv = .{1, 1}
            });

            array_add(*vertices, .{
                position = .{ WORLD_SIZE, xx coord, 0},
                uv = .{1, 0}
            });

            array_add(*indices, xx (vertices.count-4));
            array_add(*indices, xx (vertices.count-3));
            array_add(*indices, xx (vertices.count-2));
            array_add(*indices, xx (vertices.count-4));
            array_add(*indices, xx (vertices.count-2));
            array_add(*indices, xx (vertices.count-1));
        }
        
    }

    result.vertices = vertices;
    result.indices = indices;

    return result;
}

Test_Render :: struct {

    upload_geometry :: (mesh: Mesh) {
        // Create device-local vertex buffer
        vertex_size := size_of(Vertex) * mesh.vertices.count;
        render_app.vertex_buffer = create_buffer(xx vertex_size,
                                                 .VERTEX_BUFFER_BIT | .TRANSFER_DST_BIT,
                                                 .DEVICE_LOCAL_BIT);

        log("Upload vertices");
        upload_buffer_data_sync(*render_app.vertex_buffer, mesh.vertices.data, xx vertex_size);

        // Create device-local index buffer
        index_size := size_of(u32) * mesh.indices.count;
        render_app.index_buffer = create_buffer(xx index_size,
                                                .INDEX_BUFFER_BIT | .TRANSFER_DST_BIT,
                                                .DEVICE_LOCAL_BIT);

        log("Upload indices");
        upload_buffer_data_sync(*render_app.index_buffer, mesh.indices.data, xx index_size);

        // Load texture and register in bindless array
        render_app.textures    = NewArray(2, Texture);
        render_app.textures[0] = create_texture(Name.from_asset_path("/textures/debug_corners.png"));
        render_app.textures[1] = create_texture(Name.from_asset_path("/textures/debug_corners2.png"));

        register_texture(*render_app.textures[0], 0);
        register_texture(*render_app.textures[1], 1);

        render_app.texture_count = 2;

        update_camera_transform(*camera);
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

        subResourceRange: VkImageSubresourceRange = .{
            aspectMask     = .COLOR_BIT,
            baseMipLevel   = 0,
            levelCount     = VK_REMAINING_MIP_LEVELS,
            baseArrayLayer = 0,
            layerCount     = VK_REMAINING_ARRAY_LAYERS,
        };

        scene_color := *render_app.post_framebuffer;
        transition_image_layout(cmd, scene_color.image, scene_color.layout, .COLOR_ATTACHMENT_OPTIMAL);
        render_app.post_framebuffer.layout = .COLOR_ATTACHMENT_OPTIMAL;
        transition_depth_layout(cmd, render_app.depth_data.layout, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
        render_app.depth_data.layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

        clearColor:       VkClearValue;
        clearColor.color._float32 = float.[ 0.1, 0.1, 0.1, 1.0 ];

        scene_color_attachment: VkRenderingAttachmentInfo = .{
            imageView   = scene_color.view,
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

        scene_rendering_info: VkRenderingInfo = .{
            renderArea           = .{offset = .{0, 0}, extent = extent},
            layerCount           = 1,
            colorAttachmentCount = 1,
            pColorAttachments    = *scene_color_attachment,
            pDepthAttachment     = *depth_attachment,
        };

        vkCmdBeginRendering(cmd, *scene_rendering_info);

        vkCmdBindPipeline(cmd, .GRAPHICS, render_app.pipeline_data.scene_pipeline);

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
        view := camera.orbit_view;
        globals:          Global_Uniforms;
        globals.view       = view;
        globals.proj       = projection;
        globals.resolution = .{ cast(float32)extent.width, cast(float32)extent.height };
        globals.time       = 0;
        memcpy(render_app.descriptor_data.global_ubo_mapped[index], *globals, size_of(Global_Uniforms));

        object_data: Object_Data = .{
            model         = to_matrix(Transform.{translation = .{-50, -50, -50}}),
            texture_index = 0,
        };

        memcpy(render_app.descriptor_data.object_ssbo_mapped[index], *object_data,
               size_of(Object_Data));

        indirect_cmd: VkDrawIndexedIndirectCommand = .{
            indexCount    = xx world_mesh.indices.count,
            instanceCount = 1,
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

        transition_image_layout(cmd, scene_color.image, .COLOR_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);
        render_app.post_framebuffer.layout = .SHADER_READ_ONLY_OPTIMAL;
        transition_depth_layout(cmd, render_app.depth_data.layout, .DEPTH_STENCIL_READ_ONLY_OPTIMAL);
        render_app.depth_data.layout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL;

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

        post_color_attachment: VkRenderingAttachmentInfo = .{
            imageView   = render_app.swapchain_data.imageViews[imageIndex],
            imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
            loadOp      = .CLEAR,
            storeOp     = .STORE,
            clearValue  = clearColor,
        };

        post_rendering_info: VkRenderingInfo = .{
            renderArea           = .{offset = .{0, 0}, extent = extent},
            layerCount           = 1,
            colorAttachmentCount = 1,
            pColorAttachments    = *post_color_attachment,
        };

        vkCmdBeginRendering(cmd, *post_rendering_info);
        vkCmdBindPipeline(cmd, .GRAPHICS, render_app.pipeline_data.post_pipeline);
        vkCmdSetViewport(cmd, 0, 1, *viewport);
        vkCmdSetScissor(cmd, 0, 1, *scissor);
        // Bind set 0 (globals) and set 1 (post-process framebuffer)
        post_descriptor_sets: [2]VkDescriptorSet = .[
            render_app.descriptor_data.sets[index],
            render_app.descriptor_data.post_set,
        ];
        vkCmdBindDescriptorSets(cmd, .GRAPHICS, render_app.pipeline_data.post_pipeline_layout,
                                0, 2, post_descriptor_sets.data, 0, null);
        vkCmdDraw(cmd, 3, 1, 0, 0);
        vkCmdEndRendering(cmd);

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
