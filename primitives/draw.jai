Draw_Group :: struct {
    mesh_id:     u32;
    material_id: u32;
}

Draw_Indexed_Command :: struct {
    index_count:    u32;
    instance_count: u32;
    first_index:    u32;
    vertex_offset:  s32;
    first_instance: u32;
}

new_draw_group :: (data: *Render_Data, mesh_id: u32, material_id: u32) -> u32 {
    id := get_index(*data.group_pool);
    
    assert(id < MAX_GROUPS, "Unable to add new group to renderer: MAX groups count reached");

    data.groups_cpu[id] = .{
        mesh_id = mesh_id,
        material_id = material_id
    };

    return id;
}
