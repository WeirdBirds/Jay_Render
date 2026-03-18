Texture :: struct {
    image:      VkImage;
    memory:     VkDeviceMemory;
    view:       VkImageView;
    width:      s32;
    height:     s32;
    mip_levels: u32;
    format:     VkFormat;
    layout:     VkImageLayout;
}

transition_image_layout :: (cmd: VkCommandBuffer, image: VkImage, old_layout: VkImageLayout, new_layout: VkImageLayout, base_mip: u32 = 0, level_count: u32 = 1) {
    src_stage:  VkPipelineStageFlags2;
    dst_stage:  VkPipelineStageFlags2;
    src_access: VkAccessFlags2;
    dst_access: VkAccessFlags2;

    if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
        src_stage  = VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT;
        dst_stage  = VK_PIPELINE_STAGE_2_TRANSFER_BIT;
        src_access = VK_ACCESS_2_NONE;
        dst_access = VK_ACCESS_2_TRANSFER_WRITE_BIT;
    } else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
        src_stage  = VK_PIPELINE_STAGE_2_TRANSFER_BIT;
        dst_stage  = VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
        src_access = VK_ACCESS_2_TRANSFER_WRITE_BIT;
        dst_access = VK_ACCESS_2_SHADER_READ_BIT;
    } else if old_layout == .UNDEFINED && new_layout == .COLOR_ATTACHMENT_OPTIMAL {
        src_stage  = VK_PIPELINE_STAGE_2_TOP_OF_PIPE_BIT;
        dst_stage  = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
        src_access = VK_ACCESS_2_NONE;
        dst_access = VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT;
    } else if old_layout == .SHADER_READ_ONLY_OPTIMAL && new_layout == .COLOR_ATTACHMENT_OPTIMAL {
        src_stage  = VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
        dst_stage  = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
        src_access = VK_ACCESS_2_SHADER_READ_BIT;
        dst_access = VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT;
    } else if old_layout == .COLOR_ATTACHMENT_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
        src_stage  = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
        dst_stage  = VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
        src_access = VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT;
        dst_access = VK_ACCESS_2_SHADER_READ_BIT;
    } else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .TRANSFER_SRC_OPTIMAL {
        src_stage  = VK_PIPELINE_STAGE_2_TRANSFER_BIT;
        dst_stage  = VK_PIPELINE_STAGE_2_TRANSFER_BIT;
        src_access = VK_ACCESS_2_TRANSFER_WRITE_BIT;
        dst_access = VK_ACCESS_2_TRANSFER_READ_BIT;
    } else if old_layout == .TRANSFER_SRC_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
        src_stage  = VK_PIPELINE_STAGE_2_TRANSFER_BIT;
        dst_stage  = VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT;
        src_access = VK_ACCESS_2_TRANSFER_READ_BIT;
        dst_access = VK_ACCESS_2_SHADER_READ_BIT;
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
            baseMipLevel   = base_mip,
            levelCount     = level_count,
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

upload_texture_data :: (texture: *Texture, pixels: *u8, data_size: s64) {
    staging := create_buffer(data_size, .TRANSFER_SRC_BIT, .HOST_VISIBLE_BIT | .HOST_COHERENT_BIT);
    defer destroy_buffer(*staging);

    mapped: *void;
    vkMapMemory(render_app.device, staging.memory, 0, xx data_size, 0, *mapped);
    memcpy(mapped, pixels, data_size);
    vkUnmapMemory(render_app.device, staging.memory);

    cmd := render_app.cmd_buffers.graphics[0];
    begin_info: VkCommandBufferBeginInfo = .{ flags = .ONE_TIME_SUBMIT_BIT };

    vkResetCommandBuffer(cmd, 0);
    vkBeginCommandBuffer(cmd, *begin_info);

    // Transition all mip levels to TRANSFER_DST for the initial upload.
    transition_image_layout(cmd, texture.image, .UNDEFINED, .TRANSFER_DST_OPTIMAL, 0, texture.mip_levels);

    region: VkBufferImageCopy = .{
        imageSubresource = .{aspectMask = .COLOR_BIT, mipLevel = 0, baseArrayLayer = 0, layerCount = 1},
        imageExtent = .{ cast(u32) texture.width, cast(u32) texture.height, 1 },
    };

    vkCmdCopyBufferToImage(cmd, staging.buffer, texture.image, .TRANSFER_DST_OPTIMAL, 1, *region);

    // Generate mipmaps by blitting each level from the previous one.
    // NEAREST filter preserves crisp pixel-art texels at every mip level.
    if texture.mip_levels > 1
        generate_mipmaps(cmd, texture);
    else {
        transition_image_layout(cmd, texture.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL);
    }

    texture.layout = .SHADER_READ_ONLY_OPTIMAL;

    vkEndCommandBuffer(cmd);
    submit_info: VkSubmitInfo = .{commandBufferCount = 1, pCommandBuffers = *cmd};
    vkQueueSubmit(render_app.queues.graphics, 1, *submit_info, VK_NULL_HANDLE);
    vkQueueWaitIdle(render_app.queues.graphics);
    vkResetCommandBuffer(cmd, 0);
}

// Generate mipmaps via successive blits with NEAREST filtering.
// Expects mip 0 in TRANSFER_DST_OPTIMAL and all other mips in TRANSFER_DST_OPTIMAL.
// Leaves all mip levels in SHADER_READ_ONLY_OPTIMAL.
generate_mipmaps :: (cmd: VkCommandBuffer, texture: *Texture) {
    mip_width  := texture.width;
    mip_height := texture.height;

    for level: 1..cast(s64) texture.mip_levels - 1 {
        // Transition previous level from TRANSFER_DST to TRANSFER_SRC (we read from it).
        transition_image_layout(cmd, texture.image, .TRANSFER_DST_OPTIMAL, .TRANSFER_SRC_OPTIMAL, cast(u32)(level - 1), 1);

        src_w := mip_width;
        src_h := mip_height;
        mip_width  = max(mip_width  >> 1, 1);
        mip_height = max(mip_height >> 1, 1);

        blit: VkImageBlit = .{
            srcSubresource = .{aspectMask = .COLOR_BIT, mipLevel = cast(u32)(level - 1), baseArrayLayer = 0, layerCount = 1},
            srcOffsets = .[.{0, 0, 0}, .{src_w, src_h, 1}],
            dstSubresource = .{aspectMask = .COLOR_BIT, mipLevel = cast(u32) level, baseArrayLayer = 0, layerCount = 1},
            dstOffsets = .[.{0, 0, 0}, .{mip_width, mip_height, 1}],
        };

        vkCmdBlitImage(cmd,
                       texture.image, .TRANSFER_SRC_OPTIMAL,
                       texture.image, .TRANSFER_DST_OPTIMAL,
                       1, *blit, .NEAREST);

        // Transition the source level to SHADER_READ_ONLY (done with it).
        transition_image_layout(cmd, texture.image, .TRANSFER_SRC_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, cast(u32)(level - 1), 1);
    }

    // Transition the last mip level from TRANSFER_DST to SHADER_READ_ONLY.
    transition_image_layout(cmd, texture.image, .TRANSFER_DST_OPTIMAL, .SHADER_READ_ONLY_OPTIMAL, texture.mip_levels - 1, 1);
}

create_texture :: (name: Name) -> Texture {
    image := get_asset(Image_Data, name);
    defer unload_asset(Image_Data, name);

    texture := create_texture(image.width, image.height);
    upload_texture_data(*texture, xx image.pixels.data, image.pixels.count * size_of(Pixel));
    return texture;
}

compute_mip_levels :: (width: s32, height: s32) -> u32 {
    max_dim := max(width, height);
    levels: u32 = 1;
    while max_dim > 1 { max_dim >>= 1; levels += 1; }
    return levels;
}

create_texture :: (width: s32, height: s32, format: VkFormat = .R8G8B8A8_SRGB, usage: VkImageUsageFlags = .TRANSFER_DST_BIT | .SAMPLED_BIT, mipmapped: bool = true) -> Texture {
    texture: Texture;
    texture.width  = width;
    texture.height = height;
    texture.format = format;
    texture.layout = .UNDEFINED;

    mip_count: u32 = ifx mipmapped then compute_mip_levels(width, height) else 1;
    texture.mip_levels = mip_count;

    // Mipmap generation blits from each level to the next, requiring TRANSFER_SRC.
    actual_usage := usage;
    if mipmapped && mip_count > 1
        actual_usage |= .TRANSFER_SRC_BIT;

    image_info: VkImageCreateInfo = .{
        imageType     = ._2D,
        format        = format,
        extent        = .{ cast(u32) width, cast(u32) height, 1 },
        mipLevels     = mip_count,
        arrayLayers   = 1,
        samples       = ._1_BIT,
        tiling        = .OPTIMAL,
        usage         = actual_usage,
        sharingMode   = .EXCLUSIVE,
        initialLayout = .UNDEFINED,
    };

    result := vkCreateImage(render_app.device, *image_info, null, *texture.image);
    assert(result == .SUCCESS, "Failed to create texture image: %", result);

    mem_requirements: VkMemoryRequirements;
    vkGetImageMemoryRequirements(render_app.device, texture.image, *mem_requirements);

    alloc_info: VkMemoryAllocateInfo = .{
        allocationSize  = mem_requirements.size,
        memoryTypeIndex = find_memory_type(mem_requirements.memoryTypeBits, .DEVICE_LOCAL_BIT),
    };

    result = vkAllocateMemory(render_app.device, *alloc_info, null, *texture.memory);
    assert(result == .SUCCESS, "Failed to allocate texture memory: %", result);
    vkBindImageMemory(render_app.device, texture.image, texture.memory, 0);

    texture.view = create_image_view(
        texture.image,
        format,
        .{ .R, .G, .B, .A },
        .{ aspectMask = .COLOR_BIT, baseMipLevel = 0, levelCount = mip_count, baseArrayLayer = 0, layerCount = 1 },
    );
    return texture;
}

destroy_texture :: (texture: *Texture) {
    if texture.view   vkDestroyImageView(render_app.device, texture.view, null);
    if texture.image  vkDestroyImage(render_app.device, texture.image, null);
    if texture.memory vkFreeMemory(render_app.device, texture.memory, null);
    texture.* = .{};
}

create_sampler :: (filter: VkFilter = .LINEAR, address_mode: VkSamplerAddressMode = .REPEAT, anisotropy: bool = false, max_lod: float32 = 0.0) -> VkSampler {
    properties: VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(render_app.physical_device, *properties);
    sampler_info: VkSamplerCreateInfo = .{
        magFilter               = filter,
        minFilter               = filter,
        mipmapMode              = ifx filter == .NEAREST then .NEAREST else .LINEAR,
        addressModeU            = address_mode,
        addressModeV            = address_mode,
        addressModeW            = address_mode,
        anisotropyEnable        = ifx anisotropy then VK_TRUE else VK_FALSE,
        maxAnisotropy           = ifx anisotropy then properties.limits.maxSamplerAnisotropy else 1.0,
        borderColor             = .INT_OPAQUE_BLACK,
        unnormalizedCoordinates = VK_FALSE,
        compareEnable           = VK_FALSE,
        minLod                  = 0.0,
        maxLod                  = max_lod,
    };

    sampler: VkSampler;
    result := vkCreateSampler(render_app.device, *sampler_info, null, *sampler);
    assert(result == .SUCCESS, "Failed to create sampler: %", result);
    return sampler;
}

register_texture :: (texture: *Texture, slot: u32) {
    register_texture_with_sampler(texture, slot, render_app.sampler);
}

register_texture_with_sampler :: (texture: *Texture, slot: u32, sampler: VkSampler) {
    for 0..FRAME_COUNT - 1 {
        image_info: VkDescriptorImageInfo = .{
            sampler     = sampler,
            imageView   = texture.view,
            imageLayout = .SHADER_READ_ONLY_OPTIMAL,
        };

        write: VkWriteDescriptorSet = .{
            dstSet          = render_app.descriptor_data.sets[it],
            dstBinding      = 2,
            dstArrayElement = slot,
            descriptorType  = .COMBINED_IMAGE_SAMPLER,
            descriptorCount = 1,
            pImageInfo      = *image_info,
        };

        vkUpdateDescriptorSets(render_app.device, 1, *write, 0, null);
    }
}

create_post_framebuffer :: () {
    extent := render_app.swapchain_data.swapchainExtent;

    if render_app.post_framebuffer.image != VK_NULL_HANDLE
        destroy_texture(*render_app.post_framebuffer);

    render_app.post_framebuffer = create_texture(
        cast(s32) extent.width,
        cast(s32) extent.height,
        render_app.swapchain_data.surfaceFormat.format,
        .COLOR_ATTACHMENT_BIT | .SAMPLED_BIT,
        mipmapped = false,
    );

    update_post_descriptors();
}

update_post_descriptors :: () {
    scene_color_info: VkDescriptorImageInfo = .{
        sampler     = render_app.post_sampler,
        imageView   = render_app.post_framebuffer.view,
        imageLayout = .SHADER_READ_ONLY_OPTIMAL,
    };

    depth_image_info: VkDescriptorImageInfo = .{
        imageView   = render_app.depth_data.view,
        imageLayout = .DEPTH_STENCIL_READ_ONLY_OPTIMAL,
    };

    depth_sampler_info: VkDescriptorImageInfo = .{
        sampler = render_app.post_sampler,
    };

    writes: [3]VkWriteDescriptorSet = .[
        .{  // binding 0: scene color
            dstSet          = render_app.descriptor_data.post_set,
            dstBinding      = 0,
            dstArrayElement = 0,
            descriptorType  = .COMBINED_IMAGE_SAMPLER,
            descriptorCount = 1,
            pImageInfo      = *scene_color_info,
        },
        .{  // binding 1: depth texture
            dstSet          = render_app.descriptor_data.post_set,
            dstBinding      = 1,
            dstArrayElement = 0,
            descriptorType  = .SAMPLED_IMAGE,
            descriptorCount = 1,
            pImageInfo      = *depth_image_info,
        },
        .{  // binding 2: depth sampler
            dstSet          = render_app.descriptor_data.post_set,
            dstBinding      = 2,
            dstArrayElement = 0,
            descriptorType  = .SAMPLER,
            descriptorCount = 1,
            pImageInfo      = *depth_sampler_info,
        },
    ];

    vkUpdateDescriptorSets(render_app.device, writes.count, writes.data, 0, null);
}
