render_frame :: (data: *Render_Data, main_queue: Gpu_Queue, compute_queue: Gpu_Queue,
        image: Gpu_Texture_View, depth_view: Gpu_Texture_View,
        view_projection: Mat4, frustum_planes: [6] Vec4) {

    frame_index := gpu_frame_index();
    assert(frame_index < MAX_FRAMES_IN_FLIGHT);
    frame := *data.dynamic[frame_index];

    // Pools reuse holes. Dispatch through their occupied extent and let the
    // cull pass reject destroyed instance slots.
    refresh_gpu_roots(data);
    frame.params.group_count = data.group_pool.max;
    frame.params.instance_count = data.instance_pool.max;
    frame.params.frustum_planes = frustum_planes;
    frame.vertex_params.view_projection = view_projection;

    result, compute_cmd := gpu_start_command_recording(compute_queue);
    assert(result == .SUCCESS);

    // Pass 1: Reset
    gpu_set_pipeline(compute_cmd, data.pipelines[0]);
    gg := max(xx 1, (data.group_pool.max + 63) / 64);
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[xx gg, 1, 1]);
    gpu_barrier(compute_cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 2: Count-Cull
    gpu_set_pipeline(compute_cmd, data.pipelines[1]);
    ig := max(xx 1, (data.instance_pool.max + 63) / 64);
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[xx ig, 1, 1]);
    gpu_barrier(compute_cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 3: Prefix
    gpu_set_pipeline(compute_cmd, data.pipelines[2]);
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[1, 1, 1]);
    gpu_barrier(compute_cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 4: Scatter
    gpu_set_pipeline(compute_cmd, data.pipelines[3]);
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[xx ig, 1, 1]);
    gpu_barrier(compute_cmd, .COMPUTE_SHADER, .COMPUTE_SHADER);

    // Pass 5: Build draws
    gpu_set_pipeline(compute_cmd, data.pipelines[4]);
    gpu_dispatch(compute_cmd, frame.params_gpu, u32.[xx gg, 1, 1]);

    data.compute_done_value += 1;
    compute_done := Gpu_Timeline_Pair.{data.compute_done, data.compute_done_value};
    gpu_submit(compute_cmd, signals = .[compute_done]);

    result2, cmd := gpu_start_command_recording(main_queue);
    assert(result2 == .SUCCESS);

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

    gpu_draw_indexed_indirect_count(cmd, frame.vertex_params_gpu, data.fragment_params_gpu,
            index_data_gpu, frame.params.draw_commands,
            frame.params.draw_count, MAX_DRAWS);

    gpu_end_render_pass(cmd);
    gpu_submit_and_present(cmd, waits = .[compute_done]);
}
