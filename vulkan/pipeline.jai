Pipeline_Data :: struct {
    scene_pipeline:          VkPipeline;
    post_pipeline:           VkPipeline;
    compute_pipeline:        VkPipeline;
    pipeline_layout:         VkPipelineLayout;
    post_pipeline_layout:    VkPipelineLayout;
    compute_pipeline_layout: VkPipelineLayout;
}

Shader_Globals :: struct {
    view:       Mat4;
    proj:       Mat4;
    time:       float32;
    resolution: Vec2;
}

make_shader_stages :: (path: string) -> [2]VkPipelineShaderStageCreateInfo {
    shader_module := create_shader_module(Name.from_path(path));

    return .[
        .{
            stage  = .VERTEX_BIT,
            module = shader_module,
            pName  = "vert_main",
        },
        .{
            stage  = .FRAGMENT_BIT,
            module = shader_module,
            pName  = "frag_main",
        },
    ];
}

make_tessellated_shader_stages :: (path: string) -> [4]VkPipelineShaderStageCreateInfo {
    shader_module := create_shader_module(Name.from_path(path));

    return .[
        .{
            stage  = .VERTEX_BIT,
            module = shader_module,
            pName  = "vert_main",
        },
        .{
            stage  = .TESSELLATION_CONTROL_BIT,
            module = shader_module,
            pName  = "hull_main",
        },
        .{
            stage  = .TESSELLATION_EVALUATION_BIT,
            module = shader_module,
            pName  = "domain_main",
        },
        .{
            stage  = .FRAGMENT_BIT,
            module = shader_module,
            pName  = "frag_main",
        },
    ];
}

create_pipeline :: () {
    // Scene pipeline layout: set 0 only (globals + bindless textures)
    layout_info: VkPipelineLayoutCreateInfo = .{
        setLayoutCount = 1,
        pSetLayouts    = *render_app.descriptor_data.set_layout,
    };
    vkCreatePipelineLayout(render_app.device, *layout_info, null, *render_app.pipeline_data.pipeline_layout);

    // Post-process pipeline layout: set 0 (globals) + set 1 (scene framebuffer)
    post_set_layouts: [2]VkDescriptorSetLayout = .[
        render_app.descriptor_data.set_layout,
        render_app.descriptor_data.post_set_layout,
    ];
    post_layout_info: VkPipelineLayoutCreateInfo = .{
        setLayoutCount = 2,
        pSetLayouts    = post_set_layouts.data,
    };
    vkCreatePipelineLayout(render_app.device, *post_layout_info, null, *render_app.pipeline_data.post_pipeline_layout);

    compute_push_range: VkPushConstantRange = .{
        stageFlags = .COMPUTE_BIT,
        offset     = 0,
        size       = xx size_of(Populate_Push),
    };

    compute_layout_info: VkPipelineLayoutCreateInfo = .{
        setLayoutCount         = 1,
        pSetLayouts            = *render_app.descriptor_data.compute_set_layout,
        pushConstantRangeCount = 1,
        pPushConstantRanges    = *compute_push_range,
    };
    vkCreatePipelineLayout(render_app.device, *compute_layout_info, null, *render_app.pipeline_data.compute_pipeline_layout);

    create_scene_pipeline();
    create_post_pipeline();
    create_compute_pipeline();
}

WIREFRAME :: false;

create_scene_pipeline :: () {
    shader_stages := make_tessellated_shader_stages("/shaders/test.slang");
    defer destroy_shader_module(shader_stages[0].module);

    dynamic_states := VkDynamicState.[
        VkDynamicState.VIEWPORT,
        VkDynamicState.SCISSOR,
    ];

    dyn_state_info: VkPipelineDynamicStateCreateInfo = .{
        dynamicStateCount = dynamic_states.count,
        pDynamicStates    = dynamic_states.data,
    };

    vertex_binding: VkVertexInputBindingDescription = .{
        binding   = 0,
        stride    = 36,
        inputRate = .VERTEX,
    };

    vertex_attributes: []VkVertexInputAttributeDescription = .[
        .{location = 0, binding = 0, format = .R32G32B32_SFLOAT, offset = 0},
        .{location = 1, binding = 0, format = .R32G32B32_SFLOAT, offset = 12},
        .{location = 2, binding = 0, format = .R32G32_SFLOAT,    offset = 24},
        .{location = 3, binding = 0, format = .R32_SFLOAT,       offset = 32},
    ];

    vertex_info: VkPipelineVertexInputStateCreateInfo = .{
        vertexBindingDescriptionCount   = 1,
        pVertexBindingDescriptions      = *vertex_binding,
        vertexAttributeDescriptionCount = xx vertex_attributes.count,
        pVertexAttributeDescriptions    = vertex_attributes.data,
    };

    vertex_assembly: VkPipelineInputAssemblyStateCreateInfo = .{
        topology = .PATCH_LIST,
    };

    tessellation_domain_origin: VkPipelineTessellationDomainOriginStateCreateInfo = .{
        domainOrigin = .LOWER_LEFT,
    };

    tessellation_state: VkPipelineTessellationStateCreateInfo = .{
        pNext              = *tessellation_domain_origin,
        patchControlPoints = 4,
    };

    viewport_state: VkPipelineViewportStateCreateInfo = .{
        viewportCount = 1,
        scissorCount  = 1,
    };

    rasterization_state: VkPipelineRasterizationStateCreateInfo = .{
        polygonMode = ifx WIREFRAME then .LINE else .FILL,
        cullMode    = .NONE,
        frontFace   = .CLOCKWISE,
        lineWidth   = 1.0,
    };

    multisample_state: VkPipelineMultisampleStateCreateInfo = .{
        rasterizationSamples = ._1_BIT,
    };

    depth_stencil_state: VkPipelineDepthStencilStateCreateInfo = .{
        depthTestEnable       = VK_TRUE,
        depthWriteEnable      = VK_TRUE,
        depthCompareOp        = .GREATER,
        depthBoundsTestEnable = VK_FALSE,
        stencilTestEnable     = VK_FALSE,
    };

    color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
        colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
    };

    color_blend_state: VkPipelineColorBlendStateCreateInfo = .{
        attachmentCount = 1,
        pAttachments    = *color_blend_attachment,
    };

    color_format := render_app.post_framebuffer.format;
    pipeline_rendering: VkPipelineRenderingCreateInfo = .{
        colorAttachmentCount    = 1,
        pColorAttachmentFormats = *color_format,
        depthAttachmentFormat   = render_app.depth_data.format,
    };

    pipeline_info: VkGraphicsPipelineCreateInfo = .{
        pNext               = *pipeline_rendering,
        stageCount          = xx shader_stages.count,
        pStages             = shader_stages.data,
        pVertexInputState   = *vertex_info,
        pInputAssemblyState = *vertex_assembly,
        pTessellationState  = *tessellation_state,
        pViewportState      = *viewport_state,
        pRasterizationState = *rasterization_state,
        pMultisampleState   = *multisample_state,
        pDepthStencilState  = *depth_stencil_state,
        pColorBlendState    = *color_blend_state,
        pDynamicState       = *dyn_state_info,
        layout              = render_app.pipeline_data.pipeline_layout,
    };

    result := vkCreateGraphicsPipelines(render_app.device, VK_NULL_HANDLE, 1, *pipeline_info, null, *render_app.pipeline_data.scene_pipeline);
    if result != .SUCCESS
        log_error("Failed to create scene pipeline: %", result);
}

create_post_pipeline :: () {
    shader_stages := make_shader_stages("/shaders/postprocess.slang");
    defer destroy_shader_module(shader_stages[0].module);

    dynamic_states := VkDynamicState.[
        VkDynamicState.VIEWPORT,
        VkDynamicState.SCISSOR,
    ];

    dyn_state_info: VkPipelineDynamicStateCreateInfo = .{
        dynamicStateCount = dynamic_states.count,
        pDynamicStates    = dynamic_states.data,
    };

    vertex_info: VkPipelineVertexInputStateCreateInfo = .{};

    vertex_assembly: VkPipelineInputAssemblyStateCreateInfo = .{
        topology = .TRIANGLE_LIST,
    };

    viewport_state: VkPipelineViewportStateCreateInfo = .{
        viewportCount = 1,
        scissorCount  = 1,
    };

    rasterization_state: VkPipelineRasterizationStateCreateInfo = .{
        polygonMode = .FILL,
        cullMode    = .NONE,
        frontFace   = .CLOCKWISE,
        lineWidth   = 1.0,
    };

    multisample_state: VkPipelineMultisampleStateCreateInfo = .{
        rasterizationSamples = ._1_BIT,
    };

    depth_stencil_state: VkPipelineDepthStencilStateCreateInfo = .{
        depthTestEnable       = VK_FALSE,
        depthWriteEnable      = VK_FALSE,
        depthBoundsTestEnable = VK_FALSE,
        stencilTestEnable     = VK_FALSE,
    };

    color_blend_attachment: VkPipelineColorBlendAttachmentState = .{
        colorWriteMask = .R_BIT | .G_BIT | .B_BIT | .A_BIT,
    };

    color_blend_state: VkPipelineColorBlendStateCreateInfo = .{
        attachmentCount = 1,
        pAttachments    = *color_blend_attachment,
    };

    color_format := render_app.swapchain_data.surfaceFormat.format;
    pipeline_rendering: VkPipelineRenderingCreateInfo = .{
        colorAttachmentCount    = 1,
        pColorAttachmentFormats = *color_format,
    };

    pipeline_info: VkGraphicsPipelineCreateInfo = .{
        pNext               = *pipeline_rendering,
        stageCount          = xx shader_stages.count,
        pStages             = shader_stages.data,
        pVertexInputState   = *vertex_info,
        pInputAssemblyState = *vertex_assembly,
        pViewportState      = *viewport_state,
        pRasterizationState = *rasterization_state,
        pMultisampleState   = *multisample_state,
        pDepthStencilState  = *depth_stencil_state,
        pColorBlendState    = *color_blend_state,
        pDynamicState       = *dyn_state_info,
        layout              = render_app.pipeline_data.post_pipeline_layout,
    };

    result := vkCreateGraphicsPipelines(render_app.device, VK_NULL_HANDLE, 1, *pipeline_info, null, *render_app.pipeline_data.post_pipeline);
    if result != .SUCCESS
        log_error("Failed to create post-process pipeline: %", result);
}

create_compute_pipeline :: () {
    shader_module := create_shader_module(Name.from_path("/shaders/reorder_indices.slang"));
    defer destroy_shader_module(shader_module);

    stage_info: VkPipelineShaderStageCreateInfo = .{
        stage  = .COMPUTE_BIT,
        module = shader_module,
        pName  = "main",
    };

    pipeline_info: VkComputePipelineCreateInfo = .{
        stage  = stage_info,
        layout = render_app.pipeline_data.compute_pipeline_layout,
    };

    result := vkCreateComputePipelines(render_app.device, VK_NULL_HANDLE, 1, *pipeline_info, null, *render_app.pipeline_data.compute_pipeline);
    if result != .SUCCESS
        log_error("Failed to create compute pipeline: %", result);
}

destroy_pipeline :: () {
    if render_app.pipeline_data.scene_pipeline != VK_NULL_HANDLE
        vkDestroyPipeline(render_app.device, render_app.pipeline_data.scene_pipeline, null);
    if render_app.pipeline_data.post_pipeline != VK_NULL_HANDLE
        vkDestroyPipeline(render_app.device, render_app.pipeline_data.post_pipeline, null);
    if render_app.pipeline_data.compute_pipeline != VK_NULL_HANDLE
        vkDestroyPipeline(render_app.device, render_app.pipeline_data.compute_pipeline, null);
    if render_app.pipeline_data.pipeline_layout != VK_NULL_HANDLE
        vkDestroyPipelineLayout(render_app.device, render_app.pipeline_data.pipeline_layout, null);
    if render_app.pipeline_data.post_pipeline_layout != VK_NULL_HANDLE
        vkDestroyPipelineLayout(render_app.device, render_app.pipeline_data.post_pipeline_layout, null);
    if render_app.pipeline_data.compute_pipeline_layout != VK_NULL_HANDLE
        vkDestroyPipelineLayout(render_app.device, render_app.pipeline_data.compute_pipeline_layout, null);
    clear_shaders();
}
