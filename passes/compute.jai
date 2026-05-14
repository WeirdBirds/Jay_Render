compute_barrier :: (cmd: VkCommandBuffer,
                    src_stage: VkPipelineStageFlags2, src_access: VkAccessFlags2,
                    dst_stage: VkPipelineStageFlags2, dst_access: VkAccessFlags2) {
    buffer_barrier: VkMemoryBarrier2 = .{
        srcStageMask  = src_stage,
        srcAccessMask = src_access,
        dstStageMask  = dst_stage,
        dstAccessMask = dst_access,
    };

    dep_info: VkDependencyInfo = .{
        memoryBarrierCount = 1,
        pMemoryBarriers    = *buffer_barrier,
    };

    vkCmdPipelineBarrier2(cmd, *dep_info);
}

compute_pass :: (cmd: VkCommandBuffer, index: s64, aspect: float32) {
    half_fov_v := camera.fov_radians * 0.5;
    half_fov_h := atan(tan(half_fov_v) * aspect);

    cam_pos := get_translation(camera.transform);
    cam_forward := get_forward(camera.transform);
    cam_right := get_right(camera.transform);
    cam_up := get_up(camera.transform);

    vkCmdBindPipeline(cmd, .COMPUTE, render_app.pipeline_data.compute_pipeline);
    vkCmdBindDescriptorSets(cmd, .COMPUTE, render_app.pipeline_data.compute_pipeline_layout,
                            0, 1, *render_app.descriptor_data.compute_sets[index], 0, null);

    bucket_count: u32 = MAX_DEPTH_BUCKETS;
    clear_count := max(TOTAL_PLANES, cast(s64) bucket_count);

    push: Populate_Push = .{
        total_planes      = xx TOTAL_PLANES,
        bucket_count      = bucket_count,
        plane_index_count = xx PLANE_INDEX_COUNT,
        world_size        = xx WORLD_SIZE,
        world_height      = xx WORLD_HEIGHT,
        tan_half_fov_h    = tan(half_fov_h),
        tan_half_fov_v    = tan(half_fov_v),
        near_plane        = camera.near_plane,
        far_plane         = camera.far_plane,
        camera_pos        = .{cam_pos.x,     cam_pos.y,     cam_pos.z,     0},
        camera_forward    = .{cam_forward.x, cam_forward.y, cam_forward.z, 0},
        camera_right      = .{cam_right.x,   cam_right.y,   cam_right.z,   0},
        camera_up         = .{cam_up.x,      cam_up.y,      cam_up.z,      0},
    };

    push.mode = 0;
    vkCmdPushConstants(cmd, render_app.pipeline_data.compute_pipeline_layout,
                       .COMPUTE_BIT, 0, xx size_of(Populate_Push), *push);
    vkCmdDispatch(cmd, xx ((clear_count + 63) / 64), 1, 1);

    compute_barrier(cmd,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                    VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);

    push.mode = 1;
    vkCmdPushConstants(cmd, render_app.pipeline_data.compute_pipeline_layout,
                       .COMPUTE_BIT, 0, xx size_of(Populate_Push), *push);
    vkCmdDispatch(cmd, (TOTAL_PLANES + 63) / 64, 1, 1);

    compute_barrier(cmd,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                    VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);

    push.mode = 2;
    vkCmdPushConstants(cmd, render_app.pipeline_data.compute_pipeline_layout,
                       .COMPUTE_BIT, 0, xx size_of(Populate_Push), *push);
    vkCmdDispatch(cmd, 1, 1, 1);

    compute_barrier(cmd,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT,
                    VK_ACCESS_2_SHADER_STORAGE_READ_BIT | VK_ACCESS_2_SHADER_STORAGE_WRITE_BIT);

    push.mode = 3;
    vkCmdPushConstants(cmd, render_app.pipeline_data.compute_pipeline_layout,
                       .COMPUTE_BIT, 0, xx size_of(Populate_Push), *push);
    vkCmdDispatch(cmd, (TOTAL_PLANES + 63) / 64, 1, 1);

    compute_barrier(cmd,
                    VK_PIPELINE_STAGE_2_COMPUTE_SHADER_BIT, VK_ACCESS_2_SHADER_WRITE_BIT,
                    VK_PIPELINE_STAGE_2_INDEX_INPUT_BIT,
                    VK_ACCESS_2_INDEX_READ_BIT);
}
