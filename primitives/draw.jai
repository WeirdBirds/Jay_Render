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

Draw_Group :: struct {
    mesh_id:     u32;
    material: Gpu_Ptr;
}

Draw_Indexed_Command :: struct {
    index_count:    u32;
    instance_count: u32;
    first_index:    u32;
    vertex_offset:  s32;
    first_instance: u32;
}

new_draw_group :: (data: *Render_Data, mesh_id: u32, material: Gpu_Ptr) -> u32 {
    id := get_index(*data.group_pool);
    
    assert(id < MAX_GROUPS, "Unable to add new group to renderer: MAX groups count reached");

    data.groups_cpu[id] = .{
        mesh_id = mesh_id,
        material = material
    };

    return id;
}
