Vertex_Params :: struct {
    view_projection: Mat4;

    // Root GPU addresses. Mesh records keep offsets relative to these roots.
    vertices:          Gpu_Ptr;
    instances:         Gpu_Ptr;
    transforms:        Gpu_Ptr;
    visible_instances: Gpu_Ptr;
}

Fragment_Params :: struct {
    // Root GPU addresses. Mesh_Instance carries a material index, not a raw
    // device address, so material-heap relocation updates only this base.
    instances: Gpu_Ptr;
    materials: Gpu_Ptr;
}

Frame_Params :: struct {
    params:     *Draw_Params;
    params_gpu: Gpu_Ptr;

    vertex_params:     *Vertex_Params;
    vertex_params_gpu: Gpu_Ptr;

    // GPU-only slices. CPU views remain null and exist only for ownership.
    visibility_flags_cpu:   []u32;
    instance_groups_cpu:    []u32;
    group_counts_cpu:       []u32;
    group_offsets_cpu:      []u32;
    group_write_cursor_cpu: []u32;
    visible_instances_cpu:  []u32;
    draw_commands_cpu:      []Draw_Indexed_Command;
}

Render_Data :: struct {
    transforms_cpu:             []Mat4;
    instances_cpu:              []Mesh_Instance;
    bounds_cpu:                 []Bounds;
    meshes_cpu:                 []Mesh_GPU;
    groups_cpu:                 []Draw_Group;
    instance_group_static_cpu:  []u32;

    transforms_gpu:             Gpu_Ptr;
    instances_gpu:              Gpu_Ptr;
    bounds_gpu:                 Gpu_Ptr;
    meshes_gpu:                 Gpu_Ptr;
    groups_gpu:                 Gpu_Ptr;
    instance_group_static_gpu:  Gpu_Ptr;

    vertex_allocator:   Allocator;
    index_allocator:    Allocator;
    material_allocator: Allocator;
    material_pool:      Index_Pool;

    dynamic: [MAX_FRAMES_IN_FLIGHT]Frame_Params;

    fragment_params:     *Fragment_Params;
    fragment_params_gpu: Gpu_Ptr;

    compute_done:       Gpu_Semaphore;
    compute_done_value: u64;

    pipelines: [6]Gpu_Pipeline;

    instance_pool: Index_Pool;
    group_pool:    Index_Pool;
    mesh_pool:     Index_Pool;
}

gpu_array_init :: (cpu: *[]$T, gpu: *Gpu_Ptr, $count: s64, memory_type: Memory_Type = .DEFAULT) {
    #if DEBUG { assert(count > 0, "gpu_array_init count must be positive"); }

    c_ptr, g_ptr := gpu_malloc([count]T, memory_type);
    #if DEBUG {
        assert(g_ptr != 0, "gpu_array_init: GPU allocation failed");
        if memory_type != .GPU {
            assert(c_ptr != null, "gpu_array_init: mapped allocation failed");
        }
    }

    cpu.count = xx count;
    cpu.data = xx c_ptr;
    gpu.* = g_ptr;
}

material_stride :: () -> s64 {
    return size_of(Material_GPU);
}

new_material :: (data: *Render_Data, material: Material_GPU) -> Material_Handle {
    index := get_index(*data.material_pool);
    required := (cast(s64) index + 1) * material_stride();
    #if DEBUG { assert(required > 0 && required <= S64_MAX / 8, "Jay_Render: material heap size overflow"); }
    reserved := gpu_heap_reserve(data.material_allocator, required);
    #if DEBUG { assert(reserved, "Jay_Render: material heap growth failed"); }

    material_base, _ := gpu_heap_head(data.material_allocator);
    destination: *Material_GPU = cast(*Material_GPU) (material_base + cast(s64) index * material_stride());
    destination.* = material;
    return cast(Material_Handle) index;
}

refresh_gpu_roots :: (data: *Render_Data) {
    _, vertex_base := gpu_heap_head(data.vertex_allocator);
    _, material_base := gpu_heap_head(data.material_allocator);

    for *frame: data.dynamic {
        frame.vertex_params.vertices = vertex_base;
    }
    data.fragment_params.materials = material_base;
}

trim_render_memory :: (data: *Render_Data) {
    // Explicit maintenance API. Scene transitions may call this after releasing
    // resources; no frame-time shrinking or FPS-dependent hysteresis exists.
    material_bytes := cast(s64) data.material_pool.max * material_stride();
    gpu_heap_trim(data.vertex_allocator);
    gpu_heap_trim(data.index_allocator);
    gpu_heap_trim(data.material_allocator, material_bytes);
    refresh_gpu_roots(data);
}

render_init :: () -> Render_Data {
    result: Render_Data;

    result.fragment_params, result.fragment_params_gpu = gpu_malloc(Fragment_Params);
    #if DEBUG { assert(result.fragment_params != null && result.fragment_params_gpu != 0, "Jay_Render: fragment parameter allocation failed"); }

    result.compute_done = gpu_create_semaphore(0);
    #if DEBUG { assert(result.compute_done != 0, "Jay_Render: compute semaphore creation failed"); }

    for *frame: result.dynamic {
        frame.params, frame.params_gpu = gpu_malloc(Draw_Params);
        frame.vertex_params, frame.vertex_params_gpu = gpu_malloc(Vertex_Params);
        #if DEBUG {
            assert(frame.params != null && frame.params_gpu != 0, "Jay_Render: draw parameter allocation failed");
            assert(frame.vertex_params != null && frame.vertex_params_gpu != 0, "Jay_Render: vertex parameter allocation failed");
        }
    }

    result.vertex_allocator = Gpu_Heap(VERTEX_HEAP_BUDGET, max(size_of(Vertex), GPU_HEAP_ALIGNMENT));
    result.index_allocator = Gpu_Heap(INDEX_HEAP_BUDGET, max(size_of(u32), GPU_HEAP_ALIGNMENT));
    result.material_allocator = Gpu_Heap(MATERIAL_HEAP_BUDGET, max(material_stride(), GPU_HEAP_ALIGNMENT));

    // Shared persistent data.
    gpu_array_init(*result.transforms_cpu, *result.transforms_gpu, MAX_INSTANCES);
    gpu_array_init(*result.instances_cpu, *result.instances_gpu, MAX_INSTANCES);
    gpu_array_init(*result.bounds_cpu, *result.bounds_gpu, MAX_INSTANCES);
    gpu_array_init(*result.meshes_cpu, *result.meshes_gpu, MAX_MESHES);
    gpu_array_init(*result.groups_cpu, *result.groups_gpu, MAX_GROUPS);
    gpu_array_init(*result.instance_group_static_cpu, *result.instance_group_static_gpu, MAX_INSTANCES);

    for *frame: result.dynamic {
        frame.params.instances = result.instances_gpu;
        frame.params.transforms = result.transforms_gpu;
        frame.params.bounds = result.bounds_gpu;
        frame.params.meshes = result.meshes_gpu;
        frame.params.groups = result.groups_gpu;
        frame.params.instance_group_static = result.instance_group_static_gpu;

        gpu_array_init(*frame.visibility_flags_cpu, *frame.params.visible_flags, MAX_INSTANCES, .GPU);
        gpu_array_init(*frame.instance_groups_cpu, *frame.params.instance_groups, MAX_INSTANCES, .GPU);
        gpu_array_init(*frame.group_counts_cpu, *frame.params.group_counts, MAX_GROUPS, .GPU);
        gpu_array_init(*frame.group_offsets_cpu, *frame.params.group_offsets, MAX_GROUPS, .GPU);
        gpu_array_init(*frame.group_write_cursor_cpu, *frame.params.group_write_cursor, MAX_GROUPS, .GPU);
        gpu_array_init(*frame.visible_instances_cpu, *frame.params.visible_instances, MAX_INSTANCES, .GPU);
        gpu_array_init(*frame.draw_commands_cpu, *frame.params.draw_commands, MAX_DRAWS, .GPU);

        _, frame.params.total_visible = gpu_malloc(u32, .GPU);
        _, frame.params.draw_count = gpu_malloc(u32, .GPU);
        #if DEBUG { assert(frame.params.total_visible != 0 && frame.params.draw_count != 0, "Jay_Render: indirect counter allocation failed"); }

        frame.vertex_params.instances = result.instances_gpu;
        frame.vertex_params.transforms = result.transforms_gpu;
        frame.vertex_params.visible_instances = frame.params.visible_instances;
    }

    result.fragment_params.instances = result.instances_gpu;
    refresh_gpu_roots(*result);
    return result;
}

free_gpu_ptr :: (ptr: Gpu_Ptr) {
    if ptr != 0 gpu_free(ptr);
}

free_gpu_cpu :: (ptr: *void) {
    if ptr != null gpu_free(ptr);
}

destroy_frame_params :: (frame: *Frame_Params) {
    if frame.params {
        free_gpu_ptr(frame.params.visible_flags);
        free_gpu_ptr(frame.params.instance_groups);
        free_gpu_ptr(frame.params.group_counts);
        free_gpu_ptr(frame.params.group_offsets);
        free_gpu_ptr(frame.params.group_write_cursor);
        free_gpu_ptr(frame.params.total_visible);
        free_gpu_ptr(frame.params.draw_count);
        free_gpu_ptr(frame.params.visible_instances);
        free_gpu_ptr(frame.params.draw_commands);
        free_gpu_cpu(frame.params);
    }
    if frame.vertex_params free_gpu_cpu(frame.vertex_params);
    frame.* = .{};
}

render_data_destroy :: (data: *Render_Data) {
    for *pipeline: data.pipelines {
        if pipeline.* != 0 gpu_free_pipeline(pipeline.*);
    }

    if data.compute_done != 0 gpu_destroy_semaphore(data.compute_done);
    for *frame: data.dynamic destroy_frame_params(frame);

    free_gpu_cpu(data.transforms_cpu.data);
    free_gpu_cpu(data.instances_cpu.data);
    free_gpu_cpu(data.bounds_cpu.data);
    free_gpu_cpu(data.meshes_cpu.data);
    free_gpu_cpu(data.groups_cpu.data);
    free_gpu_cpu(data.instance_group_static_cpu.data);
    free_gpu_cpu(data.fragment_params);

    gpu_heap_destroy(*data.vertex_allocator);
    gpu_heap_destroy(*data.index_allocator);
    gpu_heap_destroy(*data.material_allocator);

    array_free(data.instance_pool.thumbstones);
    array_free(data.group_pool.thumbstones);
    array_free(data.mesh_pool.thumbstones);
    array_free(data.material_pool.thumbstones);
    data.* = .{};
}
