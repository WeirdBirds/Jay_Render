Global_Uniforms :: struct {
    view:       Mat4;
    proj:       Mat4;
    resolution: Vec2;
    time:       float32;
    _padding0:  float32;
    camera_pos: Vec4;
    world_data: Vec4;
}

Object_Data :: struct {
    model:         Mat4 #align 16;
    texture_index: u32 #align 16;
}

MAX_OBJECTS_PER_FRAME :: 1;
MAX_TEXTURES          :: 4096;

Descriptor_Data :: struct {
    set_layout:         VkDescriptorSetLayout;
    pool:               VkDescriptorPool;
    sets:               [FRAME_COUNT]VkDescriptorSet;
    compute_set_layout: VkDescriptorSetLayout;
    compute_sets:       [FRAME_COUNT]VkDescriptorSet;
    global_ubos:        [FRAME_COUNT]GPU_Buffer;
    global_ubo_mapped:  [FRAME_COUNT]*void;
    object_ssbos:       [FRAME_COUNT]GPU_Buffer;
    object_ssbo_mapped: [FRAME_COUNT]*void;
    visible_instances:  [FRAME_COUNT]GPU_Buffer;
    bucket_counts:      [FRAME_COUNT]GPU_Buffer;
    bucket_heads:       [FRAME_COUNT]GPU_Buffer;
    indirect_buffers:   [FRAME_COUNT]GPU_Buffer;

    post_set_layout:    VkDescriptorSetLayout;
    post_set:           VkDescriptorSet;
}

create_descriptors :: () {
    bindings: [4]VkDescriptorSetLayoutBinding;

    bindings[0] = .{binding = 0, descriptorType = .UNIFORM_BUFFER,         descriptorCount = 1,            stageFlags = .VERTEX_BIT | .TESSELLATION_CONTROL_BIT | .TESSELLATION_EVALUATION_BIT | .FRAGMENT_BIT};
    bindings[1] = .{binding = 1, descriptorType = .STORAGE_BUFFER,         descriptorCount = 1,            stageFlags = .VERTEX_BIT | .FRAGMENT_BIT};
    bindings[2] = .{binding = 2, descriptorType = .STORAGE_BUFFER,         descriptorCount = 1,            stageFlags = .VERTEX_BIT};
    bindings[3] = .{binding = 3, descriptorType = .COMBINED_IMAGE_SAMPLER, descriptorCount = MAX_TEXTURES, stageFlags = .FRAGMENT_BIT};

    binding_flags: [4]VkDescriptorBindingFlags = .[
        0,
        0,
        0,
        .PARTIALLY_BOUND_BIT | .UPDATE_AFTER_BIND_BIT | .VARIABLE_DESCRIPTOR_COUNT_BIT,
    ];

    flags_info: VkDescriptorSetLayoutBindingFlagsCreateInfo = .{bindingCount = binding_flags.count, pBindingFlags = binding_flags.data};
    layout_info: VkDescriptorSetLayoutCreateInfo = .{
        pNext        = *flags_info,
        flags        = .UPDATE_AFTER_BIND_POOL_BIT,
        bindingCount = bindings.count,
        pBindings    = bindings.data,
    };
    vkCreateDescriptorSetLayout(render_app.device, *layout_info, null, *render_app.descriptor_data.set_layout);

    compute_bindings: [4]VkDescriptorSetLayoutBinding = .[
        .{binding = 0, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, stageFlags = .COMPUTE_BIT},
        .{binding = 1, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, stageFlags = .COMPUTE_BIT},
        .{binding = 2, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, stageFlags = .COMPUTE_BIT},
        .{binding = 3, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, stageFlags = .COMPUTE_BIT},
    ];
    compute_layout_info: VkDescriptorSetLayoutCreateInfo = .{bindingCount = compute_bindings.count, pBindings = compute_bindings.data};
    vkCreateDescriptorSetLayout(render_app.device, *compute_layout_info, null, *render_app.descriptor_data.compute_set_layout);

    post_bindings: [3]VkDescriptorSetLayoutBinding = .[
        .{binding = 0, descriptorType = .COMBINED_IMAGE_SAMPLER, descriptorCount = 1, stageFlags = .FRAGMENT_BIT},
        .{binding = 1, descriptorType = .SAMPLED_IMAGE,          descriptorCount = 1, stageFlags = .FRAGMENT_BIT},
        .{binding = 2, descriptorType = .SAMPLER,                descriptorCount = 1, stageFlags = .FRAGMENT_BIT},
    ];
    post_layout_info: VkDescriptorSetLayoutCreateInfo = .{bindingCount = post_bindings.count, pBindings = post_bindings.data};
    vkCreateDescriptorSetLayout(render_app.device, *post_layout_info, null, *render_app.descriptor_data.post_set_layout);

    pool_sizes: [5]VkDescriptorPoolSize = .[
        .{type = .UNIFORM_BUFFER,         descriptorCount = FRAME_COUNT},
        .{type = .STORAGE_BUFFER,         descriptorCount = FRAME_COUNT * 6},
        .{type = .COMBINED_IMAGE_SAMPLER, descriptorCount = MAX_TEXTURES * FRAME_COUNT + 1},
        .{type = .SAMPLED_IMAGE,          descriptorCount = 1},
        .{type = .SAMPLER,                descriptorCount = 1},
    ];
    pool_info: VkDescriptorPoolCreateInfo = .{flags = .UPDATE_AFTER_BIND_BIT, maxSets = FRAME_COUNT + FRAME_COUNT + 1, poolSizeCount = pool_sizes.count, pPoolSizes = pool_sizes.data};
    vkCreateDescriptorPool(render_app.device, *pool_info, null, *render_app.descriptor_data.pool);

    layouts: [FRAME_COUNT]VkDescriptorSetLayout;
    for 0..FRAME_COUNT - 1 layouts[it] = render_app.descriptor_data.set_layout;

    variable_counts: [FRAME_COUNT]u32;
    for 0..FRAME_COUNT - 1 variable_counts[it] = MAX_TEXTURES;

    variable_count_info: VkDescriptorSetVariableDescriptorCountAllocateInfo = .{descriptorSetCount = FRAME_COUNT, pDescriptorCounts = variable_counts.data};
    alloc_info: VkDescriptorSetAllocateInfo = .{
        pNext              = *variable_count_info,
        descriptorPool     = render_app.descriptor_data.pool,
        descriptorSetCount = FRAME_COUNT,
        pSetLayouts        = layouts.data,
    };
    vkAllocateDescriptorSets(render_app.device, *alloc_info, render_app.descriptor_data.sets.data);

    compute_layouts: [FRAME_COUNT]VkDescriptorSetLayout;
    for 0..FRAME_COUNT - 1 compute_layouts[it] = render_app.descriptor_data.compute_set_layout;
    compute_alloc_info: VkDescriptorSetAllocateInfo = .{descriptorPool = render_app.descriptor_data.pool, descriptorSetCount = FRAME_COUNT, pSetLayouts = compute_layouts.data};
    vkAllocateDescriptorSets(render_app.device, *compute_alloc_info, render_app.descriptor_data.compute_sets.data);

    post_alloc_info: VkDescriptorSetAllocateInfo = .{descriptorPool = render_app.descriptor_data.pool, descriptorSetCount = 1, pSetLayouts = *render_app.descriptor_data.post_set_layout};
    vkAllocateDescriptorSets(render_app.device, *post_alloc_info, *render_app.descriptor_data.post_set);

    for 0..FRAME_COUNT - 1 {
        render_app.descriptor_data.global_ubos[it] = create_buffer(size_of(Global_Uniforms), .UNIFORM_BUFFER_BIT, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);
        vkMapMemory(render_app.device, render_app.descriptor_data.global_ubos[it].memory, 0, xx size_of(Global_Uniforms), 0, *render_app.descriptor_data.global_ubo_mapped[it]);

        render_app.descriptor_data.object_ssbos[it] = create_buffer(size_of(Object_Data) * MAX_OBJECTS_PER_FRAME, .STORAGE_BUFFER_BIT, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);
        vkMapMemory(render_app.device, render_app.descriptor_data.object_ssbos[it].memory, 0, xx (size_of(Object_Data) * MAX_OBJECTS_PER_FRAME), 0, *render_app.descriptor_data.object_ssbo_mapped[it]);

        render_app.descriptor_data.visible_instances[it] = create_buffer(size_of(u32) * MAX_VISIBLE_INSTANCES, .STORAGE_BUFFER_BIT, .DEVICE_LOCAL_BIT);
        render_app.descriptor_data.bucket_counts[it]     = create_buffer(size_of(u32) * MAX_DEPTH_BUCKETS, .STORAGE_BUFFER_BIT, .DEVICE_LOCAL_BIT);
        render_app.descriptor_data.bucket_heads[it]      = create_buffer(size_of(u32) * MAX_DEPTH_BUCKETS, .STORAGE_BUFFER_BIT, .DEVICE_LOCAL_BIT);
        render_app.descriptor_data.indirect_buffers[it]  = create_buffer(size_of(VkDrawIndexedIndirectCommand) * TOTAL_PLANES, .STORAGE_BUFFER_BIT | .INDIRECT_BUFFER_BIT, .DEVICE_LOCAL_BIT);
    }

    for 0..FRAME_COUNT - 1 {
        ubo_info: VkDescriptorBufferInfo = .{buffer = render_app.descriptor_data.global_ubos[it].buffer,       offset = 0, range = xx size_of(Global_Uniforms)};
        object_info: VkDescriptorBufferInfo = .{buffer = render_app.descriptor_data.object_ssbos[it].buffer,      offset = 0, range = xx (size_of(Object_Data) * MAX_OBJECTS_PER_FRAME)};
        visible_info: VkDescriptorBufferInfo = .{buffer = render_app.descriptor_data.visible_instances[it].buffer, offset = 0, range = xx (size_of(u32) * MAX_VISIBLE_INSTANCES)};
        writes: [3]VkWriteDescriptorSet = .[
            .{dstSet = render_app.descriptor_data.sets[it], dstBinding = 0, dstArrayElement = 0, descriptorType = .UNIFORM_BUFFER, descriptorCount = 1, pBufferInfo = *ubo_info},
            .{dstSet = render_app.descriptor_data.sets[it], dstBinding = 1, dstArrayElement = 0, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, pBufferInfo = *object_info},
            .{dstSet = render_app.descriptor_data.sets[it], dstBinding = 2, dstArrayElement = 0, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, pBufferInfo = *visible_info},
        ];
        vkUpdateDescriptorSets(render_app.device, writes.count, writes.data, 0, null);

        bucket_counts_info: VkDescriptorBufferInfo = .{buffer = render_app.descriptor_data.bucket_counts[it].buffer,    offset = 0, range = xx (size_of(u32) * MAX_DEPTH_BUCKETS)};
        bucket_heads_info: VkDescriptorBufferInfo = .{buffer = render_app.descriptor_data.bucket_heads[it].buffer,     offset = 0, range = xx (size_of(u32) * MAX_DEPTH_BUCKETS)};
        indirect_info: VkDescriptorBufferInfo = .{buffer = render_app.descriptor_data.indirect_buffers[it].buffer, offset = 0, range = xx (size_of(VkDrawIndexedIndirectCommand) * TOTAL_PLANES)};
        compute_writes: [4]VkWriteDescriptorSet = .[
            .{dstSet = render_app.descriptor_data.compute_sets[it], dstBinding = 0, dstArrayElement = 0, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, pBufferInfo = *visible_info},
            .{dstSet = render_app.descriptor_data.compute_sets[it], dstBinding = 1, dstArrayElement = 0, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, pBufferInfo = *bucket_counts_info},
            .{dstSet = render_app.descriptor_data.compute_sets[it], dstBinding = 2, dstArrayElement = 0, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, pBufferInfo = *bucket_heads_info},
            .{dstSet = render_app.descriptor_data.compute_sets[it], dstBinding = 3, dstArrayElement = 0, descriptorType = .STORAGE_BUFFER, descriptorCount = 1, pBufferInfo = *indirect_info},
        ];
        vkUpdateDescriptorSets(render_app.device, compute_writes.count, compute_writes.data, 0, null);
    }
}

destroy_descriptors :: () {
    vkDeviceWaitIdle(render_app.device);

    for 0..FRAME_COUNT - 1 {
        if render_app.descriptor_data.global_ubo_mapped[it] {
            vkUnmapMemory(render_app.device, render_app.descriptor_data.global_ubos[it].memory);
            render_app.descriptor_data.global_ubo_mapped[it] = null;
        }
        if render_app.descriptor_data.object_ssbo_mapped[it] {
            vkUnmapMemory(render_app.device, render_app.descriptor_data.object_ssbos[it].memory);
            render_app.descriptor_data.object_ssbo_mapped[it] = null;
        }

        destroy_buffer(*render_app.descriptor_data.global_ubos[it]);
        destroy_buffer(*render_app.descriptor_data.object_ssbos[it]);
        destroy_buffer(*render_app.descriptor_data.visible_instances[it]);
        destroy_buffer(*render_app.descriptor_data.bucket_counts[it]);
        destroy_buffer(*render_app.descriptor_data.bucket_heads[it]);
        destroy_buffer(*render_app.descriptor_data.indirect_buffers[it]);
    }

    vkDestroyDescriptorPool(render_app.device, render_app.descriptor_data.pool, null);
    vkDestroyDescriptorSetLayout(render_app.device, render_app.descriptor_data.set_layout, null);
    vkDestroyDescriptorSetLayout(render_app.device, render_app.descriptor_data.compute_set_layout, null);
    vkDestroyDescriptorSetLayout(render_app.device, render_app.descriptor_data.post_set_layout, null);

    render_app.descriptor_data.pool               = VK_NULL_HANDLE;
    render_app.descriptor_data.set_layout         = VK_NULL_HANDLE;
    render_app.descriptor_data.compute_set_layout = VK_NULL_HANDLE;
    render_app.descriptor_data.post_set_layout    = VK_NULL_HANDLE;
}
