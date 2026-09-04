Mesh_Data :: struct {
    vertices: []Vertex;
    indices:  []u32;
}

Vertex :: struct {
    position: Vec3;
    normal:   Vec3;
    masks:    Vec3;
    uv:       Vec2;
}

new_mesh_instance :: (
    data: *Render_Data,
    group_id: u32,
    transform: Mat4,
    world_bounds: Vec4,
    material: Material_Id
) -> u32 {
    assert(group_id < data.group_pool.max, "Jay_Render: invalid draw group");
    assert(data.instance_pool.thumbstones.count > 0 || data.instance_pool.max < MAX_INSTANCES,
        "Jay_Render: MAX_INSTANCES reached");

    instance_id := get_index(*data.instance_pool);
    group := data.groups_cpu[group_id];

    data.transforms_cpu[instance_id] = transform;
    data.instances_cpu[instance_id] = .{
        mesh_id = group.mesh_id,
        flags = .NONE,
        material = material,
    };
    data.bounds_cpu[instance_id] = .{center_radius = world_bounds};
    data.instance_group_static_cpu[instance_id] = group_id;
    return instance_id;
}

gpu_upload_mesh :: (data: *Render_Data, mesh: Mesh_Data) -> u32 {
    assert(mesh.vertices.count > 0 && mesh.indices.count > 0, "Jay_Render: mesh must contain vertices and indices");
    assert(data.mesh_pool.thumbstones.count > 0 || data.mesh_pool.max < MAX_MESHES,
        "Jay_Render: MAX_MESHES reached");

    mesh_id := get_index(*data.mesh_pool);
    verts := array_copy(mesh.vertices,, allocator = data.vertex_allocator);
    idxs := array_copy(mesh.indices,, allocator = data.index_allocator);
    assert(verts && idxs, "Jay_Render: mesh heap allocation failed");

    data.meshes_cpu[mesh_id] = .{
        first_index = cast(u32) to_element_offset(data.index_allocator, idxs.data, size_of(u32)),
        index_count = cast(u32) idxs.count,
        vertex_offset = cast(s32) to_element_offset(data.vertex_allocator, verts.data, size_of(Vertex)),
    };
    return mesh_id;
}

#scope_module

Mesh_Instance_Flags :: enum_flags u32 {
    NONE      :: 0;
    DESTROYED :: 1;
}

// Keep 16-byte stride. Compute shaders index this physical-buffer array.
// material is a direct GPU pointer into the material constants heap (Material_Id).
Mesh_Instance :: struct {
    mesh_id:  u32;
    flags:    Mesh_Instance_Flags;
    material: Material_Id;
}

Mesh_GPU :: struct {
    first_index:  u32;
    index_count:  u32;
    vertex_offset: s32;
}

#scope_file

operator == :: inline (a: Vertex, b: Vertex) -> bool {
    return memcmp(*a, *b, size_of(Vertex)) == 0;
}

destroy_mesh_instance :: (data: *Render_Data, instance_id: u32) {
    #if DEBUG { assert(instance_id < data.instance_pool.max, "Jay_Render: invalid mesh instance"); }
    data.instances_cpu[instance_id].flags = .DESTROYED;
    free_index(*data.instance_pool, instance_id);
}
