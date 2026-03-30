main_pass :: (cmd: VkCommandBuffer, index: s64, extent: VkExtent2D,
              aspect: float32, clear_color: VkClearValue) {
    scene_color := *render_app.post_framebuffer;
    transition_image_layout(cmd, scene_color.image, scene_color.layout, .COLOR_ATTACHMENT_OPTIMAL);
    render_app.post_framebuffer.layout = .COLOR_ATTACHMENT_OPTIMAL;
    transition_depth_layout(cmd, render_app.depth_data.layout, .DEPTH_STENCIL_ATTACHMENT_OPTIMAL);
    render_app.depth_data.layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL;

    scene_color_attachment: VkRenderingAttachmentInfo = .{
        imageView   = scene_color.view,
        imageLayout = .COLOR_ATTACHMENT_OPTIMAL,
        loadOp      = .CLEAR,
        storeOp     = .STORE,
        clearValue  = clear_color,
    };

    clear_depth: VkClearValue;
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

    vertex_buffers: [1]VkBuffer = .[ render_app.vertex_buffer.buffer ];
    offsets:        [1]u64      = .[ 0 ];
    vkCmdBindVertexBuffers(cmd, 0, 1, vertex_buffers.data, offsets.data);
    vkCmdBindIndexBuffer(cmd, render_app.index_buffer.buffer, 0, .UINT32);

    projection := get_projection_matrix(camera, aspect);
    view := get_view_matrix(camera);
    globals: Global_Uniforms;
    globals.view       = view;
    globals.proj       = projection;
    globals.resolution = .{ cast(float32)extent.width, cast(float32)extent.height };
    globals.time       = 0;
    memcpy(render_app.descriptor_data.global_ubo_mapped[index], *globals, size_of(Global_Uniforms));

    object_data: Object_Data = .{
        model         = Mat4.identity(),
        texture_index = 0,
    };
    memcpy(render_app.descriptor_data.object_ssbo_mapped[index], *object_data,
           size_of(Object_Data));

    vkCmdBindDescriptorSets(cmd, .GRAPHICS, render_app.pipeline_data.pipeline_layout,
                            0, 1, *render_app.descriptor_data.sets[index], 0, null);
    vkCmdDrawIndexedIndirect(cmd, render_app.descriptor_data.indirect_buffers[index].buffer,
                             0, xx TOTAL_PLANES, xx size_of(VkDrawIndexedIndirectCommand));
    vkCmdEndRendering(cmd);

    transition_image_layout(cmd, scene_color.image, .COLOR_ATTACHMENT_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);
    render_app.post_framebuffer.layout = .SHADER_READ_ONLY_OPTIMAL;
    transition_depth_layout(cmd, render_app.depth_data.layout, .DEPTH_STENCIL_READ_ONLY_OPTIMAL);
    render_app.depth_data.layout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL;
}
