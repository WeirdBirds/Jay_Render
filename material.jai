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

Material :: struct(vertex: string, fragment: string, domain: Material_Domain = .OPAQUE) {
    #insert -> string {
        vertex_path := get_asset_source_path(vertex);
        fragment_path := get_asset_source_path(fragment);
        assert(vertex_path.count > 0 && fragment_path.count > 0, "Material: shader asset path not found");

        // Compile, validate, and package both stages. Packaging here (not in
        // a generic handler) guarantees the runtime Shader_Data packages
        // exist for exactly the shaders materials use. Reflection runs after
        // successful compilation: it alone may accept a module that fails
        // entry-point linking.
        compile_pipeline_shader(vertex);
        compile_pipeline_shader(fragment);

        vfs := make_shader_vfs(get_asset_source);
        defer cleanup_shader_vfs(vfs);

        vertex_decls := get_shader_declarations(vertex_path, vfs);
        defer free_shader_declarations(*vertex_decls);
        fragment_decls := get_shader_declarations(fragment_path, vfs);
        defer free_shader_declarations(*fragment_decls);

        // Register the (vertex, fragment, domain) triple. Same triple from
        // any module reuses one index; the runtime builds one pipeline each.
        v_id := Name.new(vertex).id;
        f_id := Name.new(fragment).id;
        domain_rank := cast(u32) domain;
        material_index: s64 = -1;
        for i: 0..material_registry_count - 1 {
            entry := material_registry[i];
            if entry.vertex_id == v_id && entry.fragment_id == f_id {
                assert(entry.domain == domain_rank, "Material: same shaders with different domains (%)", vertex);
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

        // ---- vertex stage (Params only in V1; may be empty) ----
        vertex_seen: [..] string;
        vertex_seen.allocator = temp;
        vertex_size := build_stage(vertex_decls, *builder, vertex_seen, vertex_path, "vertex");

        // ---- fragment stage ----

        fragment_seen: [..] string;
        fragment_seen.allocator = temp;

        fragment_size := build_stage(fragment_decls, *builder, fragment_seen, fragment_path, "fragment");
        total_size = fragment_size + vertex_size;

        print_to_builder(*builder, "VERTEX_SIZE :: %;\n", vertex_size);
        print_to_builder(*builder, "FRAGMENT_SIZE :: %;\n", fragment_size);

        print_to_builder(*builder, "CONSTANTS_SIZE :: %;\n", total_size);
        print_to_builder(*builder, "MATERIAL_INDEX :: %;\n", material_index);
        print_to_builder(*builder, "DOMAIN :: %;\n", domain_rank);

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

    frag_ptr := cast(*u8) *recipe.fragment;
    vert_ptr := cast(*u8) *recipe.vertex;

    hash: u64 = 14695981039346656037;
    if frag_size > 0 {
        for i: 0..frag_size-1 {
            hash ^= xx (frag_ptr + i).*;
            hash *= 1099511628211;
        }
    }
    if vert_size > 0 {
        for i: 0..vert_size-1 {
            hash ^= xx (vert_ptr + i).*;
            hash *= 1099511628211;
        }
    }
    hash ^= cast(u64) type_info(M);
    hash *= 1099511628211;

    found := table_find_pointer(*data.material_cache, hash);
    if found {
        found.ref_count += 1;
        return found.id;
    }

    cpu, gpu := gpu_malloc(size);
    assert(cpu != null && gpu != 0, "upload_material: GPU allocation failed");
    if frag_size > 0 memcpy(cpu, frag_ptr, frag_size);
    if vert_size > 0 memcpy(cast(*u8) cpu + frag_size, vert_ptr, vert_size);

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

#scope_file

// GPU blob layout: fragment bytes first (offset 0, preserves current shader
// behavior), vertex bytes appended after. Emptiness is legal for vertex only;
// the fragment caller asserts non-empty.
build_stage :: (reflection: Shader_Reflection, builder: *String_Builder, seen: [..]string, path: string, stage: string) -> u64  {
    print_to_builder(builder, "%: struct {\n", stage);

    total_size : u64 = 0;

    for reflection.decls {
        kind := jay_material_decl_kind(it);
        if kind == .UNSUPPORTED then continue;
        if kind == .TEXTURE_2D {
            assert(false, "Material: Jay::Texture2D not supported in V1 (shader %, field %). Use Jay::Params scalar/vector only.", path, it.name);
        }
        if kind == .SAMPLER {
            assert(false, "Material: Jay::Sampler not supported in V1 (shader %, field %)", path, it.name);
        }
        if kind != .PARAMS then continue;

        for seen {
            assert(it != seen[it_index], "Material: duplicate material field in %", path);
        }

        array_add(*seen, it.name);

        params_type := it.type.generic_arg;
        assert(params_type != null, "Material: Jay::Params missing generic arg (shader %, field %)", path, it.name);
        assert(params_type.fields.count > 0, "Material: Jay::Params struct has no fields (shader %, field %)", path, it.name);

        print_to_builder(builder, "    %: struct {\n", it.name);

        for params_type.fields {
            jai_name := jay_material_jai_name(it.type);
            assert(jai_name.count > 0, "Material: unsupported field type % (shader %)", it.type.name, path);
            print_to_builder(builder, "        %: %;\n", it.name, jai_name);
            field_size := jay_material_gpu_type_size(it.type);
            assert(field_size > 0, "Material: zero-size field % (shader %)", it.name, path);
            total_size += field_size;
        }

            print_to_builder(builder, "    };\n");
    }

    print_to_builder(builder, "};\n");

    return total_size;
}

Jay_Material_Kind :: enum {
    UNSUPPORTED;
    PARAMS;
    TEXTURE_2D;
    SAMPLER;
}

jay_material_decl_kind :: (decl: Reflection_Decl) -> Jay_Material_Kind {
    if decl.type.namespace != "Jay" return .UNSUPPORTED;
    if decl.type.name == "Params" return .PARAMS;
    if decl.type.name == "Texture2D" return .TEXTURE_2D;
    if decl.type.name == "Sampler" return .SAMPLER;
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
