Pipeline_Data :: struct {
    pipeline: VkPipeline;
    pipeline_layout: VkPipelineLayout;
}

Shader_Globals :: struct {
    view: Mat4;
    proj: Mat4;
    time: float32;
    resolution: Vec2;
}

create_pipeline :: () {
    shader_module := create_shader_module("test");

    shader_stages: []VkPipelineShaderStageCreateInfo = .[    
        .{ 
            stage = .VERTEX_BIT, 
            module = shader_module,  
            pName = "vert_main" 
        },
        .{
            stage = .FRAGMENT_BIT,
            module = shader_module,
            pName = "frag_main"
        }
    ]; 
    
    dynamic_states := VkDynamicState.[
        VkDynamicState.VIEWPORT,
        VkDynamicState.SCISSOR
    ];

    dyn_state_info: VkPipelineDynamicStateCreateInfo = .{};
    dyn_state_info.dynamicStateCount = dynamic_states.count;
    dyn_state_info.pDynamicStates = dynamic_states.data;

    vertex_binding: VkVertexInputBindingDescription = .{
        binding = 0,
        stride = 24,
        inputRate = .VERTEX,
    };

    vertex_attributes: []VkVertexInputAttributeDescription = .[
        .{ location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = 0 },
        .{ location = 1, binding = 0, format = .R32G32B32_SFLOAT, offset = 12 },
    ];

    vertex_info: VkPipelineVertexInputStateCreateInfo = .{
        vertexBindingDescriptionCount = 1,
        pVertexBindingDescriptions = *vertex_binding,
        vertexAttributeDescriptionCount = xx vertex_attributes.count,
        pVertexAttributeDescriptions = vertex_attributes.data,
    };

    vertex_assembly: VkPipelineInputAssemblyStateCreateInfo = .{
        topology = .TRIANGLE_LIST,
    };

    viewport_state: VkPipelineViewportStateCreateInfo = .{
        viewportCount = 1,
        scissorCount = 1,
    };

    rasterization_state: VkPipelineRasterizationStateCreateInfo = .{
        polygonMode = .FILL,
        cullMode = .BACK_BIT,
        frontFace = .CLOCKWISE,
        lineWidth = 1.0
    };

    multisample_state: VkPipelineMultisampleStateCreateInfo = .{
        rasterizationSamples = ._1_BIT,   
    };

    color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
        colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT
    };
    
    color_blend_state: VkPipelineColorBlendStateCreateInfo = .{
        attachmentCount = 1,
        pAttachments = *color_blend_attachment
    };
    
    push_constant_range: VkPushConstantRange = .{
        stageFlags = .VERTEX_BIT | .FRAGMENT_BIT,
        offset = 0,
        size = xx (size_of(Mat4) + 4),
    };

    layout_info: VkPipelineLayoutCreateInfo = .{
        pushConstantRangeCount = 1,
        pPushConstantRanges = *push_constant_range,
    };
    vkCreatePipelineLayout(render_app.device, *layout_info, null, *render_app.pipeline_data.pipeline_layout);
    
    color_format := render_app.swapchain_data.surfaceFormat.format;
    pipeline_rendering: VkPipelineRenderingCreateInfo = .{
        colorAttachmentCount = 1,
        pColorAttachmentFormats = *color_format
    };

    pipeline_info: VkGraphicsPipelineCreateInfo = .{
        pNext = *pipeline_rendering,
        stageCount = xx shader_stages.count,
        pStages = shader_stages.data,
        pVertexInputState = *vertex_info,
        pInputAssemblyState = *vertex_assembly,
        pViewportState = *viewport_state,
        pRasterizationState = *rasterization_state,
        pMultisampleState = *multisample_state,
        pColorBlendState = *color_blend_state,
        pDynamicState = *dyn_state_info,
        layout = render_app.pipeline_data.pipeline_layout,
    };

    result := vkCreateGraphicsPipelines(render_app.device, VK_NULL_HANDLE, 1, *pipeline_info, null, *render_app.pipeline_data.pipeline);
    if result != .SUCCESS {
        log_error("Failed to create graphics pipeline: %", result);
    }
}

destroy_pipeline :: () {
    vkDestroyPipeline(render_app.device, render_app.pipeline_data.pipeline, null);
    vkDestroyPipelineLayout(render_app.device, render_app.pipeline_data.pipeline_layout, null);
    clear_shaders();
}
