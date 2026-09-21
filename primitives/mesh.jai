Mesh_Data :: struct {
    vertices:   []Vertex;
    slot_count: u32;
    // Material slot i owns indices[i] into the shared vertex array.
    indices:    [MAX_MATERIAL_SLOTS][]u32;
    _gpu:       Uploaded_Mesh; @jpkg_ignore
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

mesh_asset_load :: (slot: *Asset_Registry.Asset_Slot) -> bool {
    assert(render.data_initialized, "Mesh asset retained before renderer init");
    if slot.object == null return false;
    data := *render.data;
    mesh := cast(*Mesh_Data)slot.object;
    assert(!mesh._gpu.uploaded, "Jay_Render: mesh is already uploaded");
    assert(data.mesh_pool.thumbstones.count + MAX_MESHES - data.mesh_pool.max >= mesh.slot_count,
        "Jay_Render: MAX_MESHES reached (one entry required per material slot)");

    index_count: s64;
    for i: 0..mesh.slot_count - 1 index_count += mesh.indices[i].count;

    verts := array_copy(mesh.vertices,, allocator = data.vertex_allocator);
    indices: *u32;
    {
        push_allocator(data.index_allocator);
        indices = cast(*u32) alloc(index_count * size_of(u32));
    }
    assert(verts && indices, "Jay_Render: mesh heap allocation failed");

    mesh._gpu.allocation = .{
        first_index = cast(u32) to_element_offset(data.index_allocator, indices, size_of(u32)),
        index_count = cast(u32) index_count,
        vertex_offset = cast(s32) to_element_offset(data.vertex_allocator, verts.data, size_of(Vertex)),
    };

    offset: u32;
    for i: 0..mesh.slot_count - 1 {
        slot_indices := mesh.indices[i];
        memcpy(indices + offset, slot_indices.data, slot_indices.count * size_of(u32));
        descriptor := get_index(*data.mesh_pool);
        mesh._gpu.descriptors[i] = descriptor;
        data.meshes_cpu[descriptor] = .{
            first_index = mesh._gpu.allocation.first_index + offset,
            index_count = cast(u32) slot_indices.count,
            vertex_offset = mesh._gpu.allocation.vertex_offset,
        };
        offset += cast(u32) slot_indices.count;
    }

    mesh._gpu.uploaded = true;
    refresh_gpu_roots(data);
    return true;
}

mesh_asset_unload :: (slot: *Asset_Registry.Asset_Slot) {
    if slot.object == null return;
    mesh := cast(*Mesh_Data)slot.object;
    if render.data_initialized && mesh._gpu.uploaded {
        gpu_wait_idle();
        data := *render.data;
        vbase, _ := gpu_heap_head(data.vertex_allocator);
        ibase, _ := gpu_heap_head(data.index_allocator);
        vptr := vbase + cast(s64)mesh._gpu.allocation.vertex_offset * size_of(Vertex);
        iptr := ibase + cast(s64)mesh._gpu.allocation.first_index * size_of(u32);
        {
            push_allocator(data.vertex_allocator);
            free(vptr);
        }
        {
            push_allocator(data.index_allocator);
            free(iptr);
        }
        for i: 0..mesh.slot_count - 1 {
            descriptor := mesh._gpu.descriptors[i];
            data.meshes_cpu[descriptor] = .{};
            free_index(*data.mesh_pool, descriptor);
        }
    }
    free(slot.object);
    slot.object = null;
}



// Importers call this before packaging. Runtime upload trusts the imported data.
validate_mesh_import :: (mesh: *Mesh_Data) -> bool {
    if mesh.vertices.count <= 0 || mesh.vertices.count > U32_MAX / size_of(Vertex) ||
       mesh.slot_count == 0 || mesh.slot_count > MAX_MATERIAL_SLOTS {
        log_error("Jay_Render: invalid mesh vertex or material slot count");
        return false;
    }

    total: s64;
    for i: 0..mesh.slot_count - 1 {
        indices := mesh.indices[i];
        if indices.count <= 0 || indices.count % 3 != 0 {
            log_error("Jay_Render: material slots require nonempty triangle index buffers");
            return false;
        }
        if indices.count > U32_MAX / size_of(u32) - total {
            log_error("Jay_Render: mesh index allocation exceeds the heap limit");
            return false;
        }
        for index: indices {
            if index >= mesh.vertices.count {
                log_error("Jay_Render: material slot index is outside the shared vertex buffer");
                return false;
            }
        }
        total += indices.count;
    }
    return true;
}

#scope_module

Uploaded_Mesh :: struct {
    allocation: Mesh_GPU;
    descriptors: [MAX_MATERIAL_SLOTS]u32;
    uploaded: bool;
}

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
