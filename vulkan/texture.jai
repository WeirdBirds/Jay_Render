Texture :: struct {
    image:  VkImage;
    memory: VkDeviceMemory;
    view:   VkImageView;
    width:  s32;
    height: s32;
    format: VkFormat;
}

transition_image_layout :: (cmd: VkCommandBuffer, image: VkImage, old_layout: VkImageLayout, new_layout: VkImageLayout) {
    src_stage:  VkPipelineStageFlags2;
    dst_stage:  VkPipelineStageFlags2;
    src_access: VkAccessFlags2;
    dst_access: VkAccessFlags2;

    if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
        src_stage  = .TOP_OF_PIPE;
        dst_stage  = .TRANSFER;
        src_access = .NONE;
        dst_access = .TRANSFER_WRITE;
    } else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
        src_stage  = .TRANSFER;
        dst_stage  = .FRAGMENT_SHADER;
        src_access = .TRANSFER_WRITE;
        dst_access = .SHADER_READ;
    } else
        assert(false, "Unsupported layout transition: % -> %", old_layout, new_layout);

    image_barrier: VkImageMemoryBarrier2 = .{
        srcStageMask        = src_stage,
        srcAccessMask       = src_access,
        dstStageMask        = dst_stage,
        dstAccessMask       = dst_access,
        oldLayout           = old_layout,
        newLayout           = new_layout,
        srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED,
        image               = image,
        subresourceRange    = .{
            aspectMask     = .COLOR_BIT,
            baseMipLevel   = 0,
            levelCount     = 1,
            baseArrayLayer = 0,
            layerCount     = 1,
        },
    };

    dependency_info: VkDependencyInfo = .{
        imageMemoryBarrierCount = 1,
        pImageMemoryBarriers    = *image_barrier,
    };

    vkCmdPipelineBarrier2(cmd, *dependency_info);
}

upload_texture_data :: (texture: *Texture, pixels: *u8, data_size: u64) {
    render_app := get_render_app();
    // 1. Create staging buffer (same as upload_buffer_data_sync)
    staging := create_buffer(
    data_size,
    .TRANSFER_SRC_BIT,
    .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT,
    );
    defer destroy_buffer(*staging);
    // 2. Map + copy pixel data into staging buffer
    mapped: *void;
    vkMapMemory(render_app.device, staging.memory, 0, data_size, 0, *mapped);
    memcpy(mapped, pixels, data_size);
    vkUnmapMemory(render_app.device, staging.memory);
    // 3. Record commands — use graphics queue (not transfer queue!)
    //    because FRAGMENT_SHADER stage requires graphics capability
    cmd := render_app.cmd_buffers.graphics[0];  // or allocate a one-shot command buffer
    begin_info: VkCommandBufferBeginInfo = .{
        flags = .ONE_TIME_SUBMIT_BIT,
    };
    vkResetCommandBuffer(cmd, 0);
    vkBeginCommandBuffer(cmd, *begin_info);
    // 3a. Transition: UNDEFINED -> TRANSFER_DST_OPTIMAL
    transition_image_layout(cmd, texture.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL);
    // 3b. Copy staging buffer -> image
    region: VkBufferImageCopy = .{
        bufferOffset      = 0,
        bufferRowLength   = 0,                                                         // 0 = tightly packed (no row padding)
        bufferImageHeight = 0,                                                         // 0 = tightly packed
        imageSubresource  = .{
            aspectMask     = .COLOR_BIT,
            mipLevel       = 0,
            baseArrayLayer = 0,
            layerCount     = 1,
        },
        imageOffset       = .{ 0, 0, 0 },
        imageExtent       = .{ cast(u32) texture.width, cast(u32) texture.height, 1 },
    };
    vkCmdCopyBufferToImage(
    cmd,
    staging.buffer,
    texture.image,
    .TRANSFER_DST_OPTIMAL,   // current layout of the image
    1,
    *region,
    );
    // 3c. Transition: TRANSFER_DST_OPTIMAL -> SHADER_READ_ONLY_OPTIMAL
    transition_image_layout(cmd, texture.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);
    // 4. Submit and wait
    vkEndCommandBuffer(cmd);
    submit_info: VkSubmitInfo = .{
        commandBufferCount = 1,
        pCommandBuffers    = *cmd,
    };
    vkQueueSubmit(render_app.graphics_queue, 1, *submit_info, VK_NULL_HANDLE);
    vkQueueWaitIdle(render_app.graphics_queue);  // simple sync — fine for loading
}

create_texture :: (name: Name) -> Texture {
    image := get_asset(Image_Data, name);
    defer unload_asset(Image_Data, name);
    
    texture := create_texture(image.width, image.height);
    upload_texture_data(*texture, xx image.pixels, image.pixels.count * 4);
    
    return texture;
}

create_texture :: (width: s32, height: s32, format: VkFormat = .R8G8B8A8_SRGB) -> Texture {
    render_app := get_render_app();
    texture: Texture;
    texture.width  = width;
    texture.height = height;
    texture.format = format;
    
    // 1. Create VkImage
    image_info: VkImageCreateInfo = .{
        imageType     = ._2D,
        format        = format,
        extent        = .{ cast(u32) width, cast(u32) height, 1 },
        mipLevels     = 1,
        arrayLayers   = 1,
        samples       = ._1_BIT,
        tiling        = .OPTIMAL,
        usage         = .TRANSFER_DST_BIT | .SAMPLED_BIT,          // receive uploads + read in shaders
        sharingMode   = .EXCLUSIVE,
        initialLayout = .UNDEFINED,
    };
    
    result := vkCreateImage(render_app.device, *image_info, null, *texture.image);
    assert(result == .SUCCESS, "Failed to create texture image: %", result);

    // 2. Allocate memory (same pattern as your buffer allocation in memory.jai)
    mem_requirements: VkMemoryRequirements;
    vkGetImageMemoryRequirements(render_app.device, texture.image, *mem_requirements);
    
    alloc_info: VkMemoryAllocateInfo = .{
        allocationSize  = mem_requirements.size,
        memoryTypeIndex = find_memory_type(
            mem_requirements.memoryTypeBits,
            .DEVICE_LOCAL_BIT   // texture lives on GPU only
        ),
    };

    result = vkAllocateMemory(render_app.device, *alloc_info, null, *texture.memory);
    assert(result == .SUCCESS, "Failed to allocate texture memory: %", result);
    vkBindImageMemory(render_app.device, texture.image, texture.memory, 0);

    // 3. Create image view (reuse your existing helper from image.jai)
    texture.view = create_image_view(
        texture.image,
        format,
        .{ .R, .G, .B, .A },        // identity swizzle
        .{
            aspectMask     = .COLOR_BIT,
            baseMipLevel   = 0,
            levelCount     = 1,
            baseArrayLayer = 0,
            layerCount     = 1,
        },
    );
    return texture;
}

destroy_texture :: (texture: *Texture) {
    render_app := get_render_app();
    if texture.view
        vkDestroyImageView(render_app.device, texture.view, null);
    if texture.image
        vkDestroyImage(render_app.device, texture.image, null);
    if texture.memory
        vkFreeMemory(render_app.device, texture.memory, null);
    texture.* = .{};
}

create_sampler :: () -> VkSampler {
    render_app := get_render_app();
    // Query device limits for max anisotropy
    properties: VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(render_app.physical_device, *properties);
    sampler_info: VkSamplerCreateInfo = .{
        magFilter               = .LINEAR,
        minFilter               = .LINEAR,
        mipmapMode              = .LINEAR,
        addressModeU            = .REPEAT,
        addressModeV            = .REPEAT,
        addressModeW            = .REPEAT,
        anisotropyEnable        = VK_TRUE,
        maxAnisotropy           = properties.limits.maxSamplerAnisotropy,
        borderColor             = .INT_OPAQUE_BLACK,
        unnormalizedCoordinates = VK_FALSE,
        compareEnable           = VK_FALSE,
        minLod                  = 0.0,
        maxLod                  = 0.0,                                    // no mipmaps yet — set to VK_LOD_CLAMP_NONE when you add them
    };
    sampler: VkSampler;
    result := vkCreateSampler(render_app.device, *sampler_info, null, *sampler);
    assert(result == .SUCCESS, "Failed to create sampler: %", result);
    return sampler;
}
