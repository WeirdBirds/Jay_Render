Global_Uniforms :: struct {
    view:       Mat4;
    proj:       Mat4;
    resolution: Vec2;
    time:       float32;
}

Object_Data :: struct {
    model: Mat4;
}

MAX_OBJECTS_PER_FRAME :: 1024;

Descriptor_Data :: struct {
    set_layout:         VkDescriptorSetLayout;        // shape of set 0
    pool:               VkDescriptorPool;             // allocator for descriptor sets
    sets:               [FRAME_COUNT]VkDescriptorSet; // one set per frame-in-flight
    global_ubos:        [FRAME_COUNT]GPU_Buffer;      // per-frame uniform buffers
    global_ubo_mapped:  [FRAME_COUNT]*void;           // persistently mapped pointers
    object_ssbos:       [FRAME_COUNT]GPU_Buffer;      // per-frame storage buffers
    object_ssbo_mapped: [FRAME_COUNT]*void;           // persistently mapped pointers
    indirect_buffer:    GPU_Buffer;                   // indirect draw command buffer
    indirect_mapped:    *void;                        // persistently mapped pointer
}

create_descriptors :: () {
    // --- Descriptor set layout ---
    bindings: [2]VkDescriptorSetLayoutBinding;


    // Binding 0: Global uniforms (UBO)
    bindings[0] = .{
        binding         = 0,
        descriptorType  = .UNIFORM_BUFFER,
        descriptorCount = 1,
        stageFlags      = .VERTEX_BIT | .FRAGMENT_BIT
    };

    // Binding 1: Object data (SSBO)
    bindings[1] = .{
        binding         = 1,
        descriptorType  = .STORAGE_BUFFER,
        descriptorCount = 1,
        stageFlags      = .VERTEX_BIT
    };
    layout_info: VkDescriptorSetLayoutCreateInfo = .{
        bindingCount = bindings.count,
        pBindings    = bindings.data
    };
    vkCreateDescriptorSetLayout(render_app.device, *layout_info, null, *render_app.descriptor_data.set_layout);

    // --- Descriptor pool ---
    pool_sizes: [2]VkDescriptorPoolSize    = .[
        .{type = .UNIFORM_BUFFER, descriptorCount = FRAME_COUNT},
        .{type = .STORAGE_BUFFER, descriptorCount = FRAME_COUNT
        } ];
    pool_info:  VkDescriptorPoolCreateInfo = .{
        maxSets       = FRAME_COUNT,
        poolSizeCount = pool_sizes.count,
        pPoolSizes    = pool_sizes.data
    };
    vkCreateDescriptorPool(render_app.device, *pool_info, null,
                           *render_app.descriptor_data.pool);

    // --- Allocate descriptor sets ---
    layouts: [FRAME_COUNT]VkDescriptorSetLayout;

    for 0..FRAME_COUNT - 1
        layouts[it] = render_app.descriptor_data.set_layout;

    alloc_info: VkDescriptorSetAllocateInfo = .{
        descriptorPool     = render_app.descriptor_data.pool,
        descriptorSetCount = FRAME_COUNT,
        pSetLayouts        = layouts.data
    };
    vkAllocateDescriptorSets(render_app.device, *alloc_info, render_app.descriptor_data.sets.data);

    // --- 4. Create and map buffers ---
    for 0..FRAME_COUNT - 1 {
        // Per-frame UBO (Global_Uniforms)
        render_app.descriptor_data.global_ubos[it] = create_buffer(
            size_of(Global_Uniforms),
            .UNIFORM_BUFFER_BIT,
            .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);

        vkMapMemory(render_app.device, render_app.descriptor_data.global_ubos[it].memory,
                    0, xx size_of(Global_Uniforms), 0,
                    *render_app.descriptor_data.global_ubo_mapped[it]);

        // Per-frame SSBO (Object_Data — start with room for 1 object)
        render_app.descriptor_data.object_ssbos[it] = create_buffer(
            size_of(Object_Data) * MAX_OBJECTS_PER_FRAME,
            .STORAGE_BUFFER_BIT,
            .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);

        vkMapMemory(render_app.device, render_app.descriptor_data.object_ssbos[it].memory,
                    0, xx (size_of(Object_Data) * MAX_OBJECTS_PER_FRAME), 0,
                    *render_app.descriptor_data.object_ssbo_mapped[it]);
    }

    // Indirect draw command buffer (one, not per-frame)
    render_app.descriptor_data.indirect_buffer = create_buffer(
            size_of(VkDrawIndexedIndirectCommand),
            .INDIRECT_BUFFER_BIT,
            .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);

    vkMapMemory(render_app.device, render_app.descriptor_data.indirect_buffer.memory,
                0, xx size_of(VkDrawIndexedIndirectCommand), 0,
                *render_app.descriptor_data.indirect_mapped);

    // --- Write descriptor sets (point bindings at buffers) ---
    for 0..FRAME_COUNT - 1 {
        ubo_info:  VkDescriptorBufferInfo = .{
            buffer = render_app.descriptor_data.global_ubos[it].buffer,
            offset = 0,
            range  = xx size_of(Global_Uniforms)
        };
        ssbo_info: VkDescriptorBufferInfo = .{
            buffer = render_app.descriptor_data.object_ssbos[it].buffer,
            offset = 0,
            range  = xx (size_of(Object_Data) * MAX_OBJECTS_PER_FRAME)
        };
        writes: [2]VkWriteDescriptorSet;

        // Binding 0: UBO
        writes[0] = .{
            dstSet          = render_app.descriptor_data.sets[it],
            dstBinding      = 0,
            dstArrayElement = 0,
            descriptorType  = .UNIFORM_BUFFER,
            descriptorCount = 1,
            pBufferInfo     = *ubo_info
        };

        // Binding 1: SSBO
        writes[1] = .{
            dstSet          = render_app.descriptor_data.sets[it],
            dstBinding      = 1,
            dstArrayElement = 0,
            descriptorType  = .STORAGE_BUFFER,
            descriptorCount = 1,
            pBufferInfo     = *ssbo_info
        };
        vkUpdateDescriptorSets(render_app.device, writes.count, writes.data, 0, null);
    }
}

destroy_descriptors :: () {
    // Make sure GPU is not using descriptor-backed buffers while we destroy them.
    vkDeviceWaitIdle(render_app.device);

    // Per-frame mapped buffers
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
    }

    // Indirect buffer
    if render_app.descriptor_data.indirect_mapped {
        vkUnmapMemory(render_app.device, render_app.descriptor_data.indirect_buffer.memory);
        render_app.descriptor_data.indirect_mapped = null;
    }
    destroy_buffer(*render_app.descriptor_data.indirect_buffer);

    // Pool owns allocated sets; destroying pool invalidates/frees them
    vkDestroyDescriptorPool(render_app.device, render_app.descriptor_data.pool, null);
    vkDestroyDescriptorSetLayout(render_app.device, render_app.descriptor_data.set_layout, null);

    render_app.descriptor_data.pool       = VK_NULL_HANDLE;
    render_app.descriptor_data.set_layout = VK_NULL_HANDLE;
}
