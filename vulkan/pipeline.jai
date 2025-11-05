create_pipeline :: () {
    shader_module := create_shader_module("test");

    shader_stages: []VkPipelineShaderStageCreateInfo = .[    
        .{ 
            stage = .VERTEX_BIT, 
            module = shader_module,  
            pName = "vertMain" 
        },
        .{
            stage = .FRAGMENT_BIT,
            module = shader_module,
            pName = "fragMain"
        }
    ]; 
    
    dynamic_states := VkDynamicState.[
        VkDynamicState.VIEWPORT,
        VkDynamicState.SCISSOR
    ];

    dyn_state_info: VkPipelineDynamicStateCreateInfo = .{};
    dyn_state_info.dynamicStateCount = dynamic_states.count;
    dyn_state_info.pDynamicStates = dynamic_states.data;

    vertex_info: VkPipelineVertexInputStateCreateInfo = .{};

    vertex_assembly: VkPipelineInputAssemblyStateCreateInfo = .{
        topology = .TRIANGLE_LIST,
    };
}

destroy_pipeline :: () {
    clear_shaders();
}
