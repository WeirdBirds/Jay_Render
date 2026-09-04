Material :: struct(vertex: string, fragment: string) {
    #insert -> string {
        vertex_path := get_asset_source_path(vertex);
        fragment_path := get_asset_source_path(fragment);
        assert(vertex_path.count > 0 && fragment_path.count > 0, "Material: shader asset path not found");

        vfs := make_shader_vfs(get_asset_source);
        defer cleanup_shader_vfs(vfs);

        // Reflection alone may accept a module that fails entry-point linking.
        // Compile both stages in this metaprogram pass before using reflection.
        vertex_ok, vertex_spirv := compile_shader(vertex_path, "", DEBUG, vfs, DEBUG);
        defer if vertex_spirv.data free(vertex_spirv.data);
        assert(vertex_ok, "Material: vertex Slang compilation failed for %", vertex_path);

        fragment_ok, fragment_spirv := compile_shader(fragment_path, "", DEBUG, vfs, DEBUG);
        defer if fragment_spirv.data free(fragment_spirv.data);
        assert(fragment_ok, "Material: fragment Slang compilation failed for %", fragment_path);

        vertex_decls := get_shader_declarations(vertex_path, vfs);
        defer free_shader_declarations(*vertex_decls);
        fragment_decls := get_shader_declarations(fragment_path, vfs);
        defer free_shader_declarations(*fragment_decls);

        builder: String_Builder;
        schema: String_Builder;

        total_size: u64 = 0;

        // ---- vertex stage (V1: no material fields allowed) ----
        print_to_builder(*builder, "vertex: struct {};\n");
        for vertex_decls.decls {
            kind := jay_material_decl_kind(it);
            if kind == .PARAMS {
                assert(false, "Material: vertex Jay::Params not supported in V1 (shader %, field %)", vertex_path, it.name);
            } else if kind == .TEXTURE_2D {
                assert(false, "Material: vertex Jay::Texture2D not supported in V1 (shader %, field %)", vertex_path, it.name);
            } else if kind == .SAMPLER {
                assert(false, "Material: vertex Jay::Sampler not supported in V1 (shader %, field %)", vertex_path, it.name);
            }
        }

        // ---- fragment stage ----
        print_to_builder(*builder, "fragment: struct {\n");

        fragment_seen: [..] string;
        fragment_seen.allocator = temp;
        fragment_field_count := 0;

        for fragment_decls.decls {
            kind := jay_material_decl_kind(it);
            if kind == .UNSUPPORTED then continue;
            if kind == .TEXTURE_2D {
                assert(false, "Material: Jay::Texture2D not supported in V1 (shader %, field %). Use Jay::Params scalar/vector only.", fragment_path, it.name);
            }
            if kind == .SAMPLER {
                assert(false, "Material: Jay::Sampler not supported in V1 (shader %, field %)", fragment_path, it.name);
            }
            if kind != .PARAMS then continue;

            for fragment_seen {
                assert(it != fragment_seen[it_index], "Material: duplicate material field in %", fragment_path);
            }
            array_add(*fragment_seen, it.name);

            params_type := it.type.generic_arg;
            assert(params_type != null, "Material: Jay::Params missing generic arg (shader %, field %)", fragment_path, it.name);
            assert(params_type.fields.count > 0, "Material: Jay::Params struct has no fields (shader %, field %)", fragment_path, it.name);

            print_to_builder(*builder, "    %: struct {\n", it.name);
            print_to_builder(*schema, "fragment:%:%:", it.name, params_type.name);

            for params_type.fields {
                jai_name := jay_material_jai_name(it.type);
                assert(jai_name.count > 0, "Material: unsupported field type % (shader %)", it.type.name, fragment_path);
                print_to_builder(*builder, "        %: %;\n", it.name, jai_name);
                print_to_builder(*schema, "%:%;", it.name, jai_name);
                field_size := jay_material_gpu_type_size(it.type);
                assert(field_size > 0, "Material: zero-size field % (shader %)", it.name, fragment_path);
                total_size += field_size;
            }

            print_to_builder(*builder, "    };\n");
            fragment_field_count += 1;
        }

        print_to_builder(*builder, "};\n");

        assert(fragment_field_count > 0, "Material: fragment shader has no Jay::Params material fields (%)", fragment_path);

        schema_str := builder_to_string(*schema);
        defer free(schema_str.data);
        hash: u64 = 14695981039346656037;
        for 0..schema_str.count-1 {
            hash ^= xx schema_str.data[it];
            hash *= 1099511628211;
        }

        print_to_builder(*builder, "LAYOUT_HASH :: cast(u64) %;\n", hash);
        print_to_builder(*builder, "CONSTANTS_SIZE :: %;\n", total_size);

        return builder_to_string(*builder);
    }
}

// Upload a compile-time material recipe. V1: fragment-only Params blob,
// deduplicated by recipe hash. Returns a direct GPU pointer (Material_Id).
// The recipe value has call-site lifetime only and may be discarded after return.
upload_material :: (data: *Render_Data, recipe: *$M) -> Material_Id {
    size := xx M.CONSTANTS_SIZE;
    assert(size > 0 && size <= 65536, "upload_material: invalid CONSTANTS_SIZE");

    frag_ptr := cast(*u8) *recipe.fragment;

    hash: u64 = 14695981039346656037;
    for i: 0..size-1 {
        hash ^= xx (frag_ptr + i).*;
        hash *= 1099511628211;
    }
    hash ^= M.LAYOUT_HASH;
    hash *= 1099511628211;

    found := table_find_pointer(*data.material_cache, hash);
    if found {
        found.ref_count += 1;
        return found.id;
    }

    cpu, gpu := gpu_malloc(size);
    assert(cpu != null && gpu != 0, "upload_material: GPU allocation failed");
    memcpy(cpu, frag_ptr, size);

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

// Jay-specific material reflection (kept out of third-party SGPU).
// SGPU provides general Reflection_Type + slang_scalar_byte_size only.

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
