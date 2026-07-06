Draw_Params :: struct {
    group_count:    u32;
    instance_count: u32;
    padding0:       u32;
    padding1:       u32;

    frustum_planes: [6] Vec4;

    // pointers — shaders dereference what they need, ignore the rest
    instances:             Gpu_Ptr;
    transforms:            Gpu_Ptr;
    bounds:                Gpu_Ptr;
    meshes:                Gpu_Ptr;
    materials:             Gpu_Ptr;
    groups:                Gpu_Ptr;
    instance_group_static: Gpu_Ptr;

    visible_flags:       Gpu_Ptr;
    instance_groups:     Gpu_Ptr;
    group_counts:        Gpu_Ptr;
    group_offsets:       Gpu_Ptr;
    group_write_cursor:  Gpu_Ptr;
    total_visible:       Gpu_Ptr;
    visible_instances:   Gpu_Ptr;
    draw_commands:       Gpu_Ptr;
    draw_count:          Gpu_Ptr;
}

Vertex_Params :: struct {
    view_projection: Mat4;

    vertices:          Gpu_Ptr;
    instances:         Gpu_Ptr;
    transforms:        Gpu_Ptr;
    visible_instances: Gpu_Ptr;
}

Fragment_Params :: struct {
    materials: Gpu_Ptr;
}

Render_Data :: struct {
    transforms_cpu: [] Mat4;
    instances_cpu:  [] Mesh_Instance;
    bounds_cpu:     [] Bounds;
    meshes_cpu:     [] Mesh_GPU;
    materials_cpu:  [] Material_GPU;
    groups_cpu:     [] Draw_Group;
    instance_group_static_cpu: [] u32;

    // GPU-only slices (for alloc/free, not indexed by CPU)
    visibility_flags_cpu:     [] u32;
    instance_groups_cpu:      [] u32;
    group_counts_cpu:         [] u32;
    group_offsets_cpu:        [] u32;
    group_write_cursor_cpu:   [] u32;
    visible_instances_cpu:    [] u32;
    draw_commands_cpu:        [] Draw_Indexed_Command;

    vertex_allocator: Allocator;
    index_allocator: Allocator;

    params:        *Draw_Params;
    params_gpu:     Gpu_Ptr;

    vertex_params:      *Vertex_Params;
    vertex_params_gpu:   Gpu_Ptr;

    fragment_params:     *Fragment_Params;
    fragment_params_gpu:  Gpu_Ptr;

    total_visible_cpu:  *u32;
    draw_count_cpu:     *u32;

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

    result.params,        result.params_gpu        = gpu_malloc(Draw_Params);
    result.vertex_params, result.vertex_params_gpu = gpu_malloc(Vertex_Params);
    result.fragment_params, result.fragment_params_gpu = gpu_malloc(Fragment_Params);

    result.vertex_allocator = Gpu_Heap(VERTICES_BUDGET, size_of(Vertex));
    result.index_allocator = Gpu_Heap(INDICES_BUDGET, size_of(u32));

    _, result.vertex_params.vertices = gpu_heap_head(result.vertex_allocator);
    _, result.vertex_params.instances = gpu_heap_head(result.index_allocator);

    // Host-visible — GPU address goes directly into params
    gpu_array_init(*result.transforms_cpu, *result.params.transforms, MAX_INSTANCES);
    gpu_array_init(*result.instances_cpu,  *result.params.instances,  MAX_INSTANCES);
    gpu_array_init(*result.bounds_cpu,     *result.params.bounds,     MAX_INSTANCES);
    gpu_array_init(*result.meshes_cpu,     *result.params.meshes,     MAX_MESHES);
    gpu_array_init(*result.materials_cpu,  *result.params.materials,  MAX_MATERIALS);
    gpu_array_init(*result.groups_cpu,     *result.params.groups,     MAX_GROUPS);
    gpu_array_init(*result.instance_group_static_cpu, *result.params.instance_group_static, MAX_INSTANCES);

    // GPU-only — also directly into params
    gpu_array_init(*result.visibility_flags_cpu,     *result.params.visible_flags,      MAX_INSTANCES, .GPU);
    gpu_array_init(*result.instance_groups_cpu,      *result.params.instance_groups,    MAX_INSTANCES, .GPU);
    gpu_array_init(*result.group_counts_cpu,         *result.params.group_counts,       MAX_GROUPS,    .GPU);
    gpu_array_init(*result.group_offsets_cpu,        *result.params.group_offsets,      MAX_GROUPS,    .GPU);
    gpu_array_init(*result.group_write_cursor_cpu,   *result.params.group_write_cursor, MAX_GROUPS,    .GPU);
    gpu_array_init(*result.visible_instances_cpu,    *result.params.visible_instances,  MAX_INSTANCES, .GPU);
    gpu_array_init(*result.draw_commands_cpu,        *result.params.draw_commands,      MAX_DRAWS,     .GPU);

    result.total_visible_cpu, result.params.total_visible = gpu_malloc(u32, .GPU);
    result.draw_count_cpu,    result.params.draw_count    = gpu_malloc(u32, .GPU);

    result.vertex_params.instances         = result.params.instances;
    result.vertex_params.transforms        = result.params.transforms;
    result.vertex_params.visible_instances = result.params.visible_instances;
    result.fragment_params.materials       = result.params.materials;

    return result;
}
