Vertex_Params :: struct {
    view_projection: Mat4;

    vertices:          Gpu_Ptr;
    instances:         Gpu_Ptr;
    transforms:        Gpu_Ptr;
    visible_instances: Gpu_Ptr;
}

Fragment_Params :: struct {
    instances: Gpu_Ptr;
}

Frame_Params :: struct {
    params: *Draw_Params;
    params_gpu: Gpu_Ptr;

    vertex_params: *Vertex_Params;
    vertex_params_gpu: Gpu_Ptr;

    // GPU-only slices (for alloc/free ownership, not CPU indexing)
    visibility_flags_cpu:     [] u32;
    instance_groups_cpu:      [] u32;
    group_counts_cpu:         [] u32;
    group_offsets_cpu:        [] u32;
    group_write_cursor_cpu:   [] u32;
    visible_instances_cpu:    [] u32;
    draw_commands_cpu:        [] Draw_Indexed_Command;
}

Render_Data :: struct {
    transforms_cpu: [] Mat4;
    instances_cpu:  [] Mesh_Instance;
    bounds_cpu:     [] Bounds;
    meshes_cpu:     [] Mesh_GPU;
    groups_cpu:     [] Draw_Group;
    instance_group_static_cpu: [] u32;

    transforms_gpu: Gpu_Ptr;
    instances_gpu:  Gpu_Ptr;
    bounds_gpu:     Gpu_Ptr;
    meshes_gpu:     Gpu_Ptr;
    groups_gpu:     Gpu_Ptr;
    instance_group_static_gpu: Gpu_Ptr;

    vertex_allocator: Allocator;
    index_allocator: Allocator;

    material_allocator: Allocator;

    dynamic: [MAX_FRAMES_IN_FLIGHT] Frame_Params; 

    fragment_params:     *Fragment_Params;
    fragment_params_gpu:  Gpu_Ptr;

    compute_done:       Gpu_Semaphore;
    compute_done_value: u64;

    pipelines: [6] Gpu_Pipeline;

    instance_pool: Index_Pool;
    group_pool: Index_Pool;
    mesh_pool: Index_Pool;
}

gpu_array_init :: (cpu: *[]$T, gpu: *Gpu_Ptr, $count: s64, memory_type: Memory_Type = .DEFAULT) {
    c_ptr, g_ptr := gpu_malloc([count]T, memory_type);
    cpu.count = xx count;
    cpu.data = xx c_ptr;

    gpu.* = g_ptr;
}

render_init :: () -> Render_Data {
    result: Render_Data;

    result.fragment_params, result.fragment_params_gpu = gpu_malloc(Fragment_Params);
    result.compute_done = gpu_create_semaphore(0);
    assert(result.compute_done != 0);

    for *frame: result.dynamic {
        frame.params,        frame.params_gpu        = gpu_malloc(Draw_Params);
        frame.vertex_params, frame.vertex_params_gpu = gpu_malloc(Vertex_Params);
    }

    result.vertex_allocator = Gpu_Heap(VERTICES_BUDGET, size_of(Vertex));
    result.index_allocator = Gpu_Heap(INDICES_BUDGET, size_of(u32));

    result.material_allocator = Gpu_Heap(MATERIAL_BUDGET);

    _, vertex_data_gpu := gpu_heap_head(result.vertex_allocator);

    // Shared persistent data.
    gpu_array_init(*result.transforms_cpu, *result.transforms_gpu, MAX_INSTANCES);
    gpu_array_init(*result.instances_cpu,  *result.instances_gpu,  MAX_INSTANCES);
    gpu_array_init(*result.bounds_cpu,     *result.bounds_gpu,     MAX_INSTANCES);
    gpu_array_init(*result.meshes_cpu,     *result.meshes_gpu,     MAX_MESHES);
    gpu_array_init(*result.groups_cpu,     *result.groups_gpu,     MAX_GROUPS);
    gpu_array_init(*result.instance_group_static_cpu, *result.instance_group_static_gpu, MAX_INSTANCES);

    // Per-frame visibility and indirect draw scratch.
    for *frame: result.dynamic {
        frame.params.instances             = result.instances_gpu;
        frame.params.transforms            = result.transforms_gpu;
        frame.params.bounds                = result.bounds_gpu;
        frame.params.meshes                = result.meshes_gpu;
        frame.params.groups                = result.groups_gpu;
        frame.params.instance_group_static = result.instance_group_static_gpu;

        gpu_array_init(*frame.visibility_flags_cpu,   *frame.params.visible_flags,      MAX_INSTANCES, .GPU);
        gpu_array_init(*frame.instance_groups_cpu,    *frame.params.instance_groups,    MAX_INSTANCES, .GPU);
        gpu_array_init(*frame.group_counts_cpu,       *frame.params.group_counts,       MAX_GROUPS,    .GPU);
        gpu_array_init(*frame.group_offsets_cpu,      *frame.params.group_offsets,      MAX_GROUPS,    .GPU);
        gpu_array_init(*frame.group_write_cursor_cpu, *frame.params.group_write_cursor, MAX_GROUPS,    .GPU);
        gpu_array_init(*frame.visible_instances_cpu,  *frame.params.visible_instances,  MAX_INSTANCES, .GPU);
        gpu_array_init(*frame.draw_commands_cpu,      *frame.params.draw_commands,      MAX_DRAWS,     .GPU);

        _, frame.params.total_visible = gpu_malloc(u32, .GPU);
        _, frame.params.draw_count    = gpu_malloc(u32, .GPU);

        frame.vertex_params.vertices          = vertex_data_gpu;
        frame.vertex_params.instances         = result.instances_gpu;
        frame.vertex_params.transforms        = result.transforms_gpu;
        frame.vertex_params.visible_instances = frame.params.visible_instances;
    }

    result.fragment_params.instances = result.instances_gpu;

    return result;
}
