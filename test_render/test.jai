camera: Camera_Orbit = .{
    fov_radians = 60.0 * DEG_TO_RAD,
    near_plane  = 0.4,
    far_plane   = 5000,
    move_speed  = 1000
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

WORLD_SIZE   :: 4096;
WORLD_HEIGHT :: 512;
MAX_DEPTH_BUCKETS :: 1024;

WORLD_HALF_X :: cast(float32) WORLD_SIZE * 0.5;
WORLD_HALF_Y :: cast(float32) WORLD_SIZE * 0.5;

X_PLANE_COUNT :: WORLD_SIZE + 1;
Y_PLANE_COUNT :: WORLD_SIZE + 1;
Z_PLANE_COUNT :: WORLD_HEIGHT + 1;

PLANE_INDEX_COUNT      :: 4;
INDIRECT_COMMAND_COUNT :: X_PLANE_COUNT + Y_PLANE_COUNT + Z_PLANE_COUNT;
TOTAL_PLANES           :: X_PLANE_COUNT + Y_PLANE_COUNT + Z_PLANE_COUNT;
TOTAL_INDEX_COUNT      :: TOTAL_PLANES * PLANE_INDEX_COUNT;

TOTAL_INSTANCES       :: 1;
MAX_VISIBLE_INSTANCES :: 1;

// A single world-sized mesh, centered on XY at (-WORLD_HALF..+WORLD_HALF),
// with Z spanning 0..WORLD_HEIGHT.

world_mesh :: #run -> Mesh {
    result: Mesh;

    vertices: [..]Vertex;
    indices:  [..]u32;

    add_quad :: (verts: *[..]Vertex, idxs: *[..]u32, plane_normal: Vec3, plane_coord: float32,
    uv0: Vec2, uv1: Vec2, uv2: Vec2, uv3: Vec2,
    p0: Vec3, p1: Vec3, p2: Vec3, p3: Vec3) {
        base := cast(u32) verts.count;

        array_add(verts, .{ position = p0, color = plane_normal, uv = uv0, plane_coord = plane_coord });
        array_add(verts, .{ position = p1, color = plane_normal, uv = uv1, plane_coord = plane_coord });
        array_add(verts, .{ position = p2, color = plane_normal, uv = uv2, plane_coord = plane_coord });
        array_add(verts, .{ position = p3, color = plane_normal, uv = uv3, plane_coord = plane_coord });
        
        array_add(idxs, base + 0);
        array_add(idxs, base + 1);
        array_add(idxs, base + 2);
        array_add(idxs, base + 3);
    }

    // Block 0: X-walls (x = -WORLD_HALF_X .. +WORLD_HALF_X, spanning Y × Z of world)
    for coord: 0..WORLD_SIZE {
        x := cast(float32) coord - WORLD_HALF_X;
        uv0: Vec2 = .{0, 0};
        uv1: Vec2 = .{0, 1};
        uv2: Vec2 = .{1, 1};
        uv3: Vec2 = .{1, 0};
        add_quad(*vertices, *indices, .{-1, 0, 0}, cast(float32) coord,
        uv0, uv1, uv2, uv3,
        .{x, -WORLD_HALF_Y, 0           },
        .{x, -WORLD_HALF_Y, WORLD_HEIGHT},
        .{x,  WORLD_HALF_Y, WORLD_HEIGHT},
        .{x,  WORLD_HALF_Y, 0           });
    }

    // Block 1: Y-walls (y = -WORLD_HALF_Y .. +WORLD_HALF_Y, spanning X × Z of world)
    for coord: 0..WORLD_SIZE {
        y := cast(float32) coord - WORLD_HALF_Y;
        uv0: Vec2 = .{0, 0};
        uv1: Vec2 = .{0, 1};
        uv2: Vec2 = .{1, 1};
        uv3: Vec2 = .{1, 0};
        add_quad(*vertices, *indices, .{0, 1, 0}, cast(float32) coord,
        uv0, uv1, uv2, uv3,
        .{-WORLD_HALF_X, y, 0           },
        .{-WORLD_HALF_X, y, WORLD_HEIGHT},
        .{ WORLD_HALF_X, y, WORLD_HEIGHT},
        .{ WORLD_HALF_X, y, 0           });
    }

    // Block 2: Z-floors (z = 0 .. WORLD_HEIGHT, spanning X × Y of world)
    for coord: 0..WORLD_HEIGHT {
        z := cast(float32) coord;
        uv0: Vec2 = .{0, 0};
        uv1: Vec2 = .{0, 1};
        uv2: Vec2 = .{1, 1};
        uv3: Vec2 = .{1, 0};
        add_quad(*vertices, *indices, .{0, 0, -1}, cast(float32) coord,
        uv0, uv1, uv2, uv3,
        .{-WORLD_HALF_X, -WORLD_HALF_Y, z},
        .{-WORLD_HALF_X,  WORLD_HALF_Y, z},
        .{ WORLD_HALF_X,  WORLD_HALF_Y, z},
        .{ WORLD_HALF_X, -WORLD_HALF_Y, z});
    }

    result.vertices = vertices;
    result.indices  = indices;

    return result;
}

// Push constants for the frustum population shader.
Populate_Push :: struct {
    mode:              u32;
    total_planes:      u32;
    bucket_count:      u32;
    plane_index_count: u32;
    world_size:        u32;
    world_height:      u32;
    _padding0:         u32;
    _padding1:         u32;
    tan_half_fov_h:    float32;
    tan_half_fov_v:    float32;
    near_plane:        float32;
    far_plane:         float32;
    camera_pos:        Vec4;
    camera_forward:    Vec4;
    camera_right:      Vec4;
    camera_up:         Vec4;
}

#load "../passes/compute.jai";
#load "../passes/main.jai";
#load "../passes/post.jai";

Test_Render :: struct {

    upload_geometry :: (mesh: Mesh) {
        // Create device-local vertex buffer
        vertex_size := size_of(Vertex) * mesh.vertices.count;
        render_app.vertex_buffer = create_buffer(xx vertex_size,
                                                 .VERTEX_BUFFER_BIT | .TRANSFER_DST_BIT,
                                                 .DEVICE_LOCAL_BIT);

        log("Upload vertices");
        upload_buffer_data_sync(*render_app.vertex_buffer, mesh.vertices.data, xx vertex_size);

        // Create and upload index buffer for the world mesh
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
        gpu_timing_collect(index);

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
        gpu_timing_mark_frame_start(cmd, index);

        aspect := cast(float32)extent.width / cast(float32)extent.height;

        clearColor:       VkClearValue;
        clearColor.color._float32 = float.[ 0.1, 0.1, 0.1, 1.0 ];

        compute_pass(cmd, index, aspect);
        gpu_timing_mark_after_compute(cmd, index);
        main_pass(cmd, index, extent, aspect, clearColor);
        gpu_timing_mark_after_main(cmd, index);
        post_pass(cmd, index, imageIndex, extent, clearColor);
        gpu_timing_mark_after_post(cmd, index);
        gpu_timing_mark_frame_end(cmd, index);

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
