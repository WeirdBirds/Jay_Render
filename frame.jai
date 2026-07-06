render_frame :: (data: *Render_Data, main_queue: Gpu_Queue,
        image: Gpu_Texture_View, depth_view: Gpu_Texture_View,
        view_projection: Mat4, frustum_planes: [6] Vec4) {

    // Per-frame values
    data.params.group_count    = data.group_pool.count;
    data.params.instance_count = data.instance_pool.count;
    data.params.frustum_planes = frustum_planes;
    data.vertex_params.view_projection = view_projection;

    result, cmd := gpu_start_command_recording(main_queue);
    assert(result == .SUCCESS);

    // Pass 1: Reset
    gpu_set_pipeline(cmd, data.pipelines[0]);
    gg := (data.group_pool.count + 63) / 64;
    gpu_dispatch(cmd, data.params_gpu, .[gg, 1, 1]);
    gpu_barrier(cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 2: Count-Cull
    gpu_set_pipeline(cmd, data.pipelines[1]);
    ig := (data.instance_pool.count + 63) / 64;
    gpu_dispatch(cmd, data.params_gpu, .[ig, 1, 1]);
    gpu_barrier(cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 3: Prefix
    gpu_set_pipeline(cmd, data.pipelines[2]);
    gpu_dispatch(cmd, data.params_gpu, .[1, 1, 1]);
    gpu_barrier(cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 4: Scatter
    gpu_set_pipeline(cmd, data.pipelines[3]);
    gpu_dispatch(cmd, data.params_gpu, .[ig, 1, 1]);
    gpu_barrier(cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 5: Build draws
    gpu_set_pipeline(cmd, data.pipelines[4]);
    gpu_dispatch(cmd, data.params_gpu, .[gg, 1, 1]);
    gpu_barrier(cmd, .COMPUTE_SHADER, .DRAW_INDIRECT);
    gpu_barrier(cmd, .COMPUTE_SHADER, .VERTEX_SHADER);
    gpu_barrier(cmd, .COMPUTE_SHADER, .PIXEL_SHADER);

    gpu_begin_render_pass(cmd, .{
        color_targets = .[
            .{ view = image, load_op = .CLEAR, store_op = .STORE,
               clear_color._float = .[0.03, 0.03, 0.04, 1.0] }
        ],
        depth_target = .{
            view = depth_view, load_op = .CLEAR, store_op = .STORE,
            clear_value.depth = 0.0 },
    });

    gpu_set_pipeline(cmd, data.pipelines[5]);

    w, h := gpu_get_surface_extent();
    gpu_set_viewport(cmd, .{x=0, y=0, width=xx w, height=xx h, min_depth=0, max_depth=1});
    gpu_set_scissor(cmd, .{x=0, y=0, width=xx w, height=xx h});
    gpu_set_depth_stencil_state(cmd, .{ depth_test = .GREATER, depth_mode = .READ | .WRITE });

    _, index_data_gpu := gpu_heap_head(data.index_allocator);
    _, vertex_data_gpu := gpu_heap_head(data.vertex_allocator);

    data.vertex_params.vertices = vertex_data_gpu;

    gpu_draw_indexed_indirect_count(cmd, data.vertex_params_gpu, data.fragment_params_gpu,
            index_data_gpu, data.params.draw_commands,
            data.params.draw_count, MAX_DRAWS);

    gpu_end_render_pass(cmd);
    gpu_submit_and_present(cmd);
}
