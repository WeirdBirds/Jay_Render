Mesh_Flags :: enum_flags u64 {
    NONE;
}

Mesh_Instance :: struct {
    mesh_id:     u32;
    flags:       u32;
    material: Gpu_Ptr;
}

Mesh_GPU :: struct {
    first_index:   u32;
    index_count:   u32;
    vertex_offset: s32;
}

Mesh_Data :: struct {
    vertices: []Vertex;
    indices:  []u32;
}

Vertex :: struct {
    position:    Vec3;
    normal:      Vec3;
    masks:       Vec3;
    uv:          Vec2;
}

operator == :: inline (a: Vertex, b: Vertex) -> bool {
    return memcmp(*a, *b, size_of(Vertex)) > 0;
}

new_mesh_instance :: (
        data: *Render_Data,
        group_id: u32,
        transform: Mat4,
        world_bounds: Vec4
    ) -> u32 {

    instance_id := get_index(*data.instance_pool);
    assert(instance_id < MAX_INSTANCES);

    data.transforms_cpu[instance_id] = transform;

    group := data.groups_cpu[group_id];

    data.instances_cpu[instance_id] = .{
        mesh_id = group.mesh_id,
        flags = 0,
        material = group.material
    };

    data.bounds_cpu[instance_id] = .{
        center_radius = world_bounds,
    };

    data.instance_group_static_cpu[instance_id] = group_id;

    return instance_id;
}

destroy_mesh_instace :: (render_data: *Render_Data, instance: u32) {
    free_index(render_data.instance_pool);
}

gpu_upload_mesh :: (data: *Render_Data, mesh: Mesh_Data) -> u32 {
    mesh_id := get_index(*data.mesh_pool);

    verts := array_copy(mesh.vertices,, allocator = data.vertex_allocator);
    idxs := array_copy(mesh.indices,, allocator = data.index_allocator);

    assert(verts && idxs); 

    data.meshes_cpu[mesh_id] = .{
        first_index  = xx to_index_offset(data.index_allocator, idxs.data),
        index_count  = xx idxs.count,
        vertex_offset = xx to_index_offset(data.vertex_allocator, verts.data),
    };

    // data.meshes_used += 1;  // if you add this counter
    return mesh_id;
}
