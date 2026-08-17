Draw_Params :: struct {
    group_count:    u32;
    instance_count: u32;
    padding0:       u32;
    padding1:       u32;

    frustum_planes: [6]Vec4;

    // Root addresses. All persistent mesh/material references are scalar
    // indices or offsets relative to their owning root.
    instances:             Gpu_Ptr;
    transforms:            Gpu_Ptr;
    bounds:                Gpu_Ptr;
    meshes:                Gpu_Ptr;
    groups:                Gpu_Ptr;
    instance_group_static: Gpu_Ptr;

    visible_flags:      Gpu_Ptr;
    instance_groups:    Gpu_Ptr;
    group_counts:       Gpu_Ptr;
    group_offsets:      Gpu_Ptr;
    group_write_cursor: Gpu_Ptr;
    total_visible:      Gpu_Ptr;
    visible_instances:  Gpu_Ptr;
    draw_commands:      Gpu_Ptr;
    draw_count:         Gpu_Ptr;
}

// Material is intentionally absent. Material selection is per instance, so
// grouping only by mesh avoids redundant indirect commands for same mesh.
Draw_Group :: struct {
    mesh_id:  u32;
    padding0: u32;
    padding1: u32;
    padding2: u32;
}

Draw_Indexed_Command :: struct {
    index_count:   u32;
    instance_count: u32;
    first_index:   u32;
    vertex_offset: s32;
    first_instance: u32;
}

new_draw_group :: (data: *Render_Data, mesh_id: u32) -> u32 {
    assert(mesh_id < data.mesh_pool.max, "Jay_Render: invalid mesh for draw group");
    assert(data.group_pool.thumbstones.count > 0 || data.group_pool.max < MAX_GROUPS,
        "Jay_Render: MAX_GROUPS reached");

    id := get_index(*data.group_pool);
    data.groups_cpu[id] = .{mesh_id = mesh_id};
    return id;
}
