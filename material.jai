Material_Domain :: enum u32 {
    OPAQUE      :: 0;
    TRANSLUCENT :: 1;
}
Material_Entry :: struct {
    vertex_id:   u64;
    fragment_id: u64;
    domain:      u32;
}

#no_reset material_registry: [MAX_MATERIALS] Material_Entry;
#no_reset material_registry_count: s64;

Material :: struct(vs_name: string, fs_name: string, domain: Material_Domain = .OPAQUE) {
    #insert -> string {
        vertex_path := get_asset_source_path(vs_name);
        fragment_path := get_asset_source_path(fs_name);
        assert(vertex_path.count > 0 && fragment_path.count > 0, "Material: shader asset path not found");

        compile_pipeline_shader(vs_name);
        vfs := make_shader_vfs(get_asset_source);
        defer cleanup_shader_vfs(vfs);
        vertex_decls: Shader_Reflection;
        fragment_decls := get_shader_declarations(fragment_path, vfs);
        defer free_shader_declarations(*fragment_decls);
        compile_material_pipeline_shader(fs_name, fragment_decls);

        // Register the (vertex, fragment, domain) triple. Same triple from
        // any module reuses one index; the runtime builds one pipeline each.
        v_id := Name.new(vs_name).id;
        f_id := Name.new(fs_name).id;
        domain_rank := cast(u32) domain;
        material_index: s64 = -1;
        for i: 0..material_registry_count - 1 {
            entry := material_registry[i];
            if entry.vertex_id == v_id && entry.fragment_id == f_id {
                assert(entry.domain == domain_rank, "Material: same shaders with different domains (%)", vs_name);
                material_index = i;
                break;
            }
        }
        if material_index < 0 {
            assert(material_registry_count < MAX_MATERIALS, "Material: registry full");
            material_registry[material_registry_count] = .{ vertex_id = v_id, fragment_id = f_id, domain = domain_rank };
            material_index = material_registry_count;
            material_registry_count += 1;
        }

        builder: String_Builder;

        total_size: u64 = 0;

        // ---- vertex + fragment stages (Params, Texture2D, Sampler) ----
        pack: String_Builder;

        vertex_seen: [..] string;
        vertex_seen.allocator = temp;
        vertex_size := build_stage(vertex_decls, *builder, *pack, vertex_seen, vertex_path, "vertex", "vert", 0);

        fragment_seen: [..] string;
        fragment_seen.allocator = temp;

        fragment_size := build_stage(fragment_decls, *builder, *pack, fragment_seen, fragment_path, "fragment", "frag", xx vertex_size);
        total_size = fragment_size + vertex_size;

        print_to_builder(*builder, "VERTEX_SIZE :: %;\n", vertex_size);
        print_to_builder(*builder, "FRAGMENT_SIZE :: %;\n", fragment_size);

        print_to_builder(*builder, "CONSTANTS_SIZE :: %;\n", total_size);
        print_to_builder(*builder, "MATERIAL_INDEX :: %;\n", material_index);
        print_to_builder(*builder, "DOMAIN :: %;\n", domain_rank);
        print_to_builder(*builder, "pack_material :: (data: *Render_Data, frag: *$F, vert: *$V, dst: *u8) {\n");
        pack_str := builder_to_string(*pack);
        defer free(pack_str.data);
        print_to_builder(*builder, "%", pack_str);
        print_to_builder(*builder, "}\n");

        return builder_to_string(*builder);
    }
}

// Upload a compile-time material recipe. V1: fragment-only Params blob,
// deduplicated by recipe hash. Returns a direct GPU pointer (Material_Id).
// The recipe value has call-site lifetime only and may be discarded after return.
upload_material :: (data: *Render_Data, recipe: *$M) -> Material_Id {
    size := xx M.CONSTANTS_SIZE;
    frag_size := xx M.FRAGMENT_SIZE;
    vert_size := xx M.VERTEX_SIZE;
    assert(size <= 65536, "upload_material: invalid CONSTANTS_SIZE");
    assert(size == frag_size + vert_size, "upload_material: size mismatch");

    // Empty material: no bytes, no allocation. All empty recipes share id 0;
    // shaders without material fields never dereference it.
    if size == 0 return cast(Material_Id) 0;

    cpu, gpu := gpu_malloc(size);
    assert(cpu != null && gpu != 0, "upload_material: GPU allocation failed");
    M.pack_material(data, *recipe.fragment, *recipe.vertex, cpu);

    // Hash the packed bytes: recipes hold paths and padding, the blob is
    // canonical. Allocating before dedup wastes one alloc on hits only.
    hash: u64 = 14695981039346656037;
    packed := cast(*u8) cpu;
    for i: 0..size-1 {
        hash ^= xx (packed + i).*;
        hash *= 1099511628211;
    }
    hash ^= cast(u64) type_info(M);
    hash *= 1099511628211;

    found := table_find_pointer(*data.material_cache, hash);
    if found {
        found.ref_count += 1;
        gpu_free(cpu);
        return found.id;
    }

    id := cast(Material_Id) gpu;
    table_add(*data.material_cache, hash, Uploaded_Material.{ id = id, item_hash = hash, ref_count = 1, allocation = cpu, gpu = gpu, size = size });
    return id;
}

release_material :: (data: *Render_Data, id: Material_Id) {
    // V1: find by id, decrement refcount; free GPU allocation when zero.
    // Demo never releases during a frame; shutdown frees remaining entries.
    found_key: u64 = 0;
    found_it := false;
    for data.material_cache {
        if it.id == id {
            found_key = it_index;
            found_it = true;
            break;
        }
    }
    if !found_it return;
    entry := table_find_pointer(*data.material_cache, found_key);
    if !entry return;
    entry.ref_count -= 1;
    if entry.ref_count <= 0 {
        gpu_free(entry.allocation);
        table_remove(*data.material_cache, found_key);
    }
}

// SamplerState parameters resolve to the stock sampler.
default_sampler_index :: (data: *Render_Data) -> u32 {
    assert(data.default_sampler != 0, "material: default sampler missing");
    return cast(u32) data.default_sampler;
}

// Resolve a texture asset to a bindless view index, uploading once.
// The Name comes from Name.static at the recipe site, so the png handler
// prepared its package at compile time and get_asset serves it here.
// Runs at scene-build time; the copy targets a fresh texture nothing
// else touches, so no sync needed.
resolve_texture_index :: (data: *Render_Data, name: Name) -> u32 {
    found := table_find_pointer(*data.texture_cache, name.id);
    if found return cast(u32) found.view;

    image := get_asset(Image_Data, name);
    assert(image != null, "material: texture asset missing");
    assert(image.pixels.data != null && image.width > 0 && image.height > 0,
        "material: texture asset empty");

    result, texture := gpu_create_texture(.{
        dimensions = .[xx image.width, xx image.height, 1],
        format = .R8G8B8A8_SRGB,
        usage = .SAMPLED | .TRANSFER_DST,
    });
    assert(result == .SUCCESS && texture != 0, "material: texture creation failed");
    // vkCopyMemoryToImage (host copy) needs VK_EXT_host_image_copy, which
    // this device does not enable. Staged command copy like the texture
    // example instead; one wait_idle at build time, no per-frame sync.
    byte_count := cast(s64) image.width * cast(s64) image.height * 4;
    staging, staging_gpu := gpu_malloc(byte_count);
    assert(staging != null && staging_gpu != 0, "material: texture staging failed");
    memcpy(staging, image.pixels.data, byte_count);
    submit_result, cmd := gpu_start_command_recording(gpu_get_queue(.MAIN, 0));
    assert(submit_result == .SUCCESS, "material: texture command recording failed");
    copy_result := gpu_copy_to_texture(cmd, texture, staging_gpu);
    assert(copy_result == .SUCCESS, "material: texture copy failed");
    gpu_submit(cmd);
    gpu_wait_idle();
    gpu_free(staging);

    view := gpu_texture_view(texture);
    assert(view != 0, "material: texture view creation failed");
    table_add(*data.texture_cache, name.id, Uploaded_Texture.{ texture = texture, view = view });
    return cast(u32) view;
}

#scope_file

// Blob region layout: [params byte size u32][slot count u32][slots u32...]
// [params bytes]. Slots hold resolved bindless indices in declaration order.
// An empty region emits zero bytes (no header). Pass 1 measures and
// validates, pass 2 emits the recipe struct and pack statements with final
// offsets. root names the pack-proc pointer (frag/vert), base_off is the
// region's byte offset in the blob.
build_stage :: (reflection: Shader_Reflection, builder: *String_Builder, pack: *String_Builder, seen: [..]string, path: string, stage: string, root: string, base_off: s64) -> u64  {
    params_bytes: s64 = 0;
    params_count: s64 = 0;
    slots: s64 = 0;
    for reflection.decls {
        kind := jay_material_decl_kind(it);
        if kind == .UNSUPPORTED {
            assert(false, "Material: unsupported parameter type % for '%' in %", it.type.name, it.name, path);
        }
        decl_name := it.name;
        for s: seen {
            assert(s != decl_name, "Material: duplicate material field % in %", decl_name, path);
        }
        array_add(*seen, decl_name);
        if kind == .TEXTURE_2D || kind == .SAMPLER {
            slots += 1;
            continue;
        }
        params_count += 1;
        assert(params_count == 1, "Material: one struct parameter per stage is supported (shader %)", path);
        params_type := it.type;
        assert(params_type.fields.count > 0, "Material: material parameter '%' must be a struct (shader %)", it.name, path);
        for params_type.fields {
            jai_name := jay_material_jai_name(it.type);
            assert(jai_name.count > 0, "Material: unsupported field type % (shader %)", it.type.name, path);
            field_size := jay_material_gpu_type_size(it.type);
            assert(field_size > 0, "Material: zero-size field % (shader %)", it.name, path);
            params_bytes += xx field_size;
        }
    }
    if params_bytes == 0 && slots == 0 {
        print_to_builder(builder, "%: struct {\n", stage);
        print_to_builder(builder, "};\n");
        return 0;
    }

    print_to_builder(builder, "%: struct {\n", stage);
    slot := 0;
    params_off := base_off + 8 + slots * 4;
    for reflection.decls {
        kind := jay_material_decl_kind(it);
        if kind == .UNSUPPORTED then continue;
        if kind == .TEXTURE_2D {
            print_to_builder(builder, "    %: Name;\n", it.name);
            print_to_builder(pack, "    (cast(*u32)(dst + %)).* = resolve_texture_index(data, %.%);\n", base_off + 8 + slot * 4, root, it.name);
            slot += 1;
            continue;
        }
        if kind == .SAMPLER {
            print_to_builder(pack, "    (cast(*u32)(dst + %)).* = default_sampler_index(data);\n", base_off + 8 + slot * 4);
            slot += 1;
            continue;
        }
        params_type := it.type;
        decl_name := it.name;
        print_to_builder(builder, "    %: struct {\n", decl_name);
        for params_type.fields {
            jai_name := jay_material_jai_name(it.type);
            print_to_builder(builder, "        %: %;\n", it.name, jai_name);
            field_size := jay_material_gpu_type_size(it.type);
            print_to_builder(pack, "    (cast(*%)(dst + %)).* = %.%.%;\n", jai_name, params_off, root, decl_name, it.name);
            params_off += xx field_size;
        }
        print_to_builder(builder, "    };\n");
    }
    print_to_builder(builder, "};\n");

    print_to_builder(pack, "    (cast(*u32)(dst + %)).* = xx %;\n", base_off + 0, params_bytes);
    print_to_builder(pack, "    (cast(*u32)(dst + %)).* = xx %;\n", base_off + 4, slots);
    return xx (8 + slots * 4 + params_bytes);
}

Jay_Material_Kind :: enum {
    UNSUPPORTED;
    PARAMS;
    TEXTURE_2D;
    SAMPLER;
}

jay_material_decl_kind :: (decl: Reflection_Decl) -> Jay_Material_Kind {
    if decl.type.resource_shape == .TEXTURE_2D return .TEXTURE_2D;
    if decl.type.name == "SamplerState" return .SAMPLER;
    if decl.type.kind == .STRUCT return .PARAMS;
    return .UNSUPPORTED;
}

// Map a scalar/vector reflection type to a Jai type name. "" when unsupported.
jay_material_jai_name :: (type: *Reflection_Type) -> string {
    if !type return "";

    if type.kind == .SCALAR {
        // FLOAT16 has no Jai mirror; VOID/NONE are not material data.
        if type.scalar_type == {
            case .BOOL;   return "bool";
            case .INT8;   return "s8";
            case .UINT8;  return "u8";
            case .INT16;  return "s16";
            case .UINT16; return "u16";
            case .INT32;  return "s32";
            case .UINT32; return "u32";
            case .INT64;   return "s64";
            case .INTPTR;  return "s64";
            case .UINT64;  return "u64";
            case .UINTPTR; return "u64";
            case .FLOAT32; return "float32";
            case .FLOAT64; return "float64";
        }
        return "";
    }
    // VECTOR is always rows == 1 (probe-verified). Matrices arrive as MATRIX.
    if type.kind == .VECTOR {
        components := type.row_count * type.column_count;

        if type.scalar_type == {
            case .FLOAT32; {
                if components == {
                    case 2; return "Vec2";
                    case 3; return "Vec3";
                    case 4; return "Vec4";
                }
            }
            case .FLOAT64; {
                if components == {
                    case 2; return "Vec2d";
                    case 3; return "Vec3d";
                    case 4; return "Vec4d";
                }
            }
        }
    }
    if type.kind == .MATRIX {
        components := type.row_count * type.column_count;

        if type.scalar_type == {
            case .FLOAT32; {
                if components == {
                    case 4;  return "Mat2";
                    case 9;  return "Mat3";
                    case 12; return "Mat4x3";
                    case 16; return "Mat4";
                }
            }
            case .FLOAT64; {
                if components == {
                    case 4;  return "Mat2d";
                    case 9;  return "Mat3d";
                    case 12; return "Mat4x3d";
                    case 16; return "Mat4d";
                }
            }
        }
    }
    return "";
}

jay_material_gpu_type_size :: (type: *Reflection_Type) -> u64 {
    if !type return 0;
    if type.kind == .SCALAR {
        return slang_scalar_byte_size(type.scalar_type);
    }
    if type.kind == .VECTOR {
        return slang_scalar_byte_size(type.scalar_type) * xx (type.row_count * type.column_count);
    }
    if type.kind == .MATRIX {
        return slang_scalar_byte_size(type.scalar_type) * xx (type.row_count * type.column_count);
    }
    return 0;
}
