new_draw_group :: (data: *Render_Data, mesh_id: u32) -> u32 {
    assert(data.group_pool.thumbstones.count > 0 || data.group_pool.max < MAX_GROUPS,
        "Jay_Render: MAX_GROUPS reached");

    group_id := get_index(*data.group_pool);
    data.groups_cpu[group_id] = .{mesh_id = mesh_id};
    #if DEBUG { assert(group_id < MAX_GROUPS); }
    return group_id;
}

#scope_module

// Draw_Params mirrors common.slang's Draw_Params exactly (scalar layout,
// 476 bytes: 17 GPU root pointers at offset 340..476). Shaders dereference
// the pushed pointer directly, so field order must never diverge.

Draw_Params :: struct {
    group_count:     u32;
    instance_count:  u32;
    cull_mode:       u32;   // 0 = pass A (frustum + history), 1 = pass B (rescue retest)
    history_enabled: u32;   // camera-motion gate: 0 = frustum only
    reset_counters:  u32;   // 1 = zero HiZ stats ring too (chain A only; chain B sets 0)

    frustum_planes: [6]Vec4;

    // Culling helpers (Z-up LH, reverse-Z: near -> 1.0, far -> 0.0).
    view_projection: Mat4;  // full VP (matches the render pass)
    view:            Mat4;  // view matrix (sphere -> view-space depth)
    hiz_base_size:   Vec2;  // pyramid base dims
    ndc_coeffs:      Vec2;  // reverse-Z coefficients: revz(d) = coeffs.y / d - coeffs.x
    hiz_epsilon:     float32; // depth slack against the tile min (never culls past it)
    pad_hiz:         float32;
    hiz_levels:      u32;
    first_frame:     u32;   // 1 => zero occluded_flags before culling

    hiz_view_indices: [16]u32;  // storage-view index per pyramid level

    occluded_flags: Gpu_Ptr;  // persistent: 1 = pass-A rejected (rescue retest set)
    counters:       Gpu_Ptr;  // per-frame stats ring

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
    index_count:    u32;
    instance_count: u32;
    first_index:    u32;
    vertex_offset:  u32;
    first_instance: u32;
    padding:        u32;
}
