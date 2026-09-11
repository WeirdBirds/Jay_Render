Material_Domain :: enum u32 {
    OPAQUE;
    TRANSLUCENT;
}

Material_Stage :: enum u32 {
    VERTEX   :: 1;
    FRAGMENT :: 2;
}

Material_Entry :: struct {
    vertex_id:       Name;
    fragment_id:     Name;
}

#no_reset opaque_registry: [MAX_MATERIALS] Material_Entry;
#no_reset opaque_registry_count: s64;

#no_reset translucent_registry: [MAX_MATERIALS] Material_Entry;
#no_reset translucent_registry_count: s64;

_generated_shaders: Table(string, string);
_generated_types: Table(Shader_Type, string);

Material :: struct(vs_name: string, fs_name: string, domain: Material_Domain = .OPAQUE) {
    #insert -> string {
        body_builder: String_Builder;

        vertex_path := get_asset_source_path(vs_name);
        fragment_path := get_asset_source_path(fs_name);

        vertex_reflection := get_shader_reflection(vertex_path);
        fragment_reflection := get_shader_reflection(fragment_path);

        v_id := Name.new(vs_name);
        f_id := Name.new(fs_name);
        fragment_package_id := f_id;
        if domain == .TRANSLUCENT {
            fragment_package_id = Name.new(sprint("%/translucent", fs_name));
        }

        material_index := register_material(domain, v_id, fragment_package_id);

        packer_builder: String_Builder;

        print_to_builder(*body_builder, "MATERIAL_INDEX :: %;\n", material_index);
        print_to_builder(*body_builder, "vertex: struct {\n");
            vertex_end := generate_wrappers(vertex_reflection, *body_builder, *packer_builder, .VERTEX, "vertex", 0);
        print_to_builder(*body_builder, "};\n");
        print_to_builder(*body_builder, "fragment: struct {\n");
            total := generate_wrappers(fragment_reflection, *body_builder, *packer_builder, .FRAGMENT, "fragment", vertex_end);
        print_to_builder(*body_builder, "};\n\n");
        emit_upload_proc(*body_builder, *packer_builder, total);

        compile_stage_wrapper(vertex_path, vertex_reflection, 0, .VERTEX, v_id.id, domain);
        compile_stage_wrapper(fragment_path, fragment_reflection, vertex_end, .FRAGMENT, fragment_package_id.id, domain);

        body_text := builder_to_string(*body_builder);
        return body_text;
    }
}

upload_material :: (data: *Render_Data, material: $M) -> Material_Id {
    return M.upload(data, material);
}

#scope_module

register_material :: (domain: Material_Domain, vertex_id: Name, fragment_id: Name) -> s64 {
    assert(domain == .OPAQUE || domain == .TRANSLUCENT,
        "Material: unsupported domain");
    registry := ifx domain == .OPAQUE then *opaque_registry else *translucent_registry;
    registry_count := ifx domain == .OPAQUE then *opaque_registry_count else *translucent_registry_count;
    assert(registry_count.* < MAX_MATERIALS, "Material: % registry full", domain);

    material_index := registry_count.*;
    registry.*[material_index] = .{
        vertex_id = vertex_id,
        fragment_id = fragment_id,
    };
    registry_count.* += 1;
    return material_index;
}

is_vertex_output :: (shader_type: Shader_Type) -> bool {
    if !shader_type return false;
    if shader_type.kind != .STRUCT return false;
    return shader_type.name == "Vertex_Output";
}

is_uint32 :: (shader_type: Shader_Type) -> bool {
    if !shader_type return false;
    if shader_type.kind != .SCALAR return false;
    return shader_type.(*Shader_Type_Scalar).scalar_type == .UINT32;
}

is_float4 :: (shader_type: Shader_Type) -> bool {
    if !shader_type return false;
    if shader_type.kind != .VECTOR return false;
    type := shader_type.(*Shader_Type_Vector);
    return type.scalar_type == .FLOAT32 && type.scalar_count == 4;
}

emit_upload_proc :: (body_builder: *String_Builder, packer_builder: *String_Builder, total: s64) {
    // Generated upload: all blob management inline, numbers baked.
    // Structs memcpy whole, resources resolve to indices in place.
    packer_text := builder_to_string(packer_builder);
    defer free(packer_text);
    print_to_builder(body_builder, "upload :: (data: *Render_Data, material: Material(vs_name, fs_name, domain)) -> Material_Id {\n");
    if total == 0 {
        print_to_builder(body_builder, "    return cast(Material_Id) 0;\n");
    } else {
        print_to_builder(body_builder, "    cpu, gpu := gpu_malloc(%);\n", total);
        print_to_builder(body_builder, "    assert(cpu != null && gpu != 0, \"Material: GPU allocation failed\");\n");
        print_to_builder(body_builder, "    cpu8 := cast(*u8) cpu;\n");
        print_to_builder(body_builder, "%", packer_text);
        print_to_builder(body_builder, "    hash: u64 = 14695981039346656037;\n");
        print_to_builder(body_builder, "    for i: 0..%-1 {\n", total);
        print_to_builder(body_builder, "        hash ^= xx (cpu8 + i).*;\n");
        print_to_builder(body_builder, "        hash *= 1099511628211;\n");
        print_to_builder(body_builder, "    }\n");
        print_to_builder(body_builder, "    found := table_find_pointer(*data.material_cache, hash);\n");
        print_to_builder(body_builder, "    if found {\n");
        print_to_builder(body_builder, "        found.ref_count += 1;\n");
        print_to_builder(body_builder, "        gpu_free(cpu);\n");
        print_to_builder(body_builder, "        return found.id;\n");
        print_to_builder(body_builder, "    }\n");
        print_to_builder(body_builder, "    id := cast(Material_Id) gpu;\n");
        print_to_builder(body_builder, "    table_add(*data.material_cache, hash, Uploaded_Material.{ id = id, item_hash = hash, ref_count = 1, allocation = cpu, gpu = gpu, size = % });\n", total);
        print_to_builder(body_builder, "    return id;\n");
    }
    print_to_builder(body_builder, "}\n");
}

// Every material stage compiles through a generated wrapper, never the
// user source. The wrapper lives in _generated_shaders under a virtual
// sibling path, so relative includes resolve against the real dir.
compile_stage_wrapper :: (asset_path: string, reflection: Shader_Reflection, base_off: s64, stage: Material_Stage, package_id: u64, domain: Material_Domain) {
    asset_dir := path_strip_filename(asset_path);
    asset_file := string.{ data = asset_path.data + asset_dir.count, count = asset_path.count - asset_dir.count };
    generated_path := sprint("%/_generated_%.slang", asset_dir, package_id);
    wrapper_text := make_shader_wrapper(reflection, asset_file, stage, base_off, domain);
    table_add(*_generated_shaders, generated_path, wrapper_text);
    compiled, spirv := compile_shader(generated_path, "", null, "_jay_main");
    defer if spirv.data free(spirv.data);
    assert(compiled, "Jay_Render: material shader compilation failed: %", asset_path);
    write(sprint("%/%.jpkg", Paths.assets_out, package_id), Shader_Data.{ code_words = spirv, reflection = "" });
}

// One shared layout pass: finds main, counts system args, measures the
// params region and slots. Both the recipe generator and the shader
// wrapper generator consume it, so the two sides cannot drift apart.
stage_schema :: (reflection: *Shader_Reflection, stage: Material_Stage) -> (*Shader_Function, s64, s64, s64) {
    main_func: *Shader_Function = null;
    system_args: s64 = 0;
    params_bytes: s64 = 0;
    slots: s64 = 0;
    for reflection.functions {
        if it.name == "main" main_func = *reflection.functions[it_index];
    }
    assert(main_func != null, "Material: % shader has no main function", stage);

    if stage == {
        case .VERTEX; system_args = 2;
        case .FRAGMENT; system_args = 1;
    }

    for system_args..main_func.args.count-1 {
        decl := main_func.args[it];
        assert(decl.type != null, "Material: parameter % has no reflected type", decl.name);
        if decl.type.kind == .STRUCT {
            t := decl.type.(*Shader_Type_Struct);
            params_bytes = (params_bytes + t.alignment - 1) / t.alignment * t.alignment + xx t.stride;
            continue;
        }
        if decl.type.kind == .RESOURCE {
            assert(decl.type.(*Shader_Type_Resource).shape == .TEXTURE_2D,
                "Material: only Texture2D resources are supported, got %", decl.name);
            slots += 1;
            continue;
        }
        if decl.type.kind == .SAMPLER_STATE {
            slots += 1;
            continue;
        }
        assert(false, "Material: unsupported top-level parameter %", decl.name);
    }
    return main_func, system_args, params_bytes, slots;
}

make_shader_wrapper :: (reflection: Shader_Reflection, source_name: string, stage: Material_Stage, base_off: s64, domain: Material_Domain = .OPAQUE) -> string {
    main_func, system_args, _, slots := stage_schema(*reflection, stage);
    translucent := stage == .FRAGMENT && domain == .TRANSLUCENT;
    params_base := base_off + 8 + slots * 4;

    builder: String_Builder;
    print_to_builder(*builder, "#include \"%\"\n", source_name);
    if stage == .VERTEX {
        print_to_builder(*builder, "[shader(\"vertex\")]\nVertex_Output _jay_main(uint vertex_id : SV_VulkanVertexID, uint instance_id : SV_VulkanInstanceID) {\n");
        print_to_builder(*builder, "    uint64_t blob = Jay::material_blob(instance_id);\n");
        print_to_builder(*builder, "    return main(vertex_id, instance_id");
    } else {
        if translucent {
            print_to_builder(*builder, "[shader(\"fragment\")]\nTranslucent_Fragment _jay_main(Vertex_Output input) {\n");
        } else {
            print_to_builder(*builder, "[shader(\"fragment\")]\nfloat4 _jay_main(Vertex_Output input) : SV_Target0 {\n");
        }
        print_to_builder(*builder, "    uint64_t blob = Jay::material_blob(input.instance_id);\n");
        if translucent {
            print_to_builder(*builder, "    return translucent_fragment(main(input");
        } else {
            print_to_builder(*builder, "    return main(input");
        }
    }

    params_off := params_base;
    slot := 0;
    for system_args..main_func.args.count-1 {
        decl := main_func.args[it];
        if decl.type.kind == .STRUCT {
            t := decl.type.(*Shader_Type_Struct);
            params_off = (params_off + t.alignment - 1) / t.alignment * t.alignment;
            print_to_builder(*builder, ", *(%*)(Jay::params_blob(blob) + %)", decl.type.name, params_off - params_base);
            params_off += xx t.stride;
        } else if decl.type.kind == .SAMPLER_STATE {
            print_to_builder(*builder, ", g_samplers[Jay::slot_index(blob, %)]", slot);
            slot += 1;
        } else {
            print_to_builder(*builder, ", g_textures_2d[Jay::slot_index(blob, %)]", slot);
            slot += 1;
        }
    }
    if translucent {
        print_to_builder(*builder, "), input.position.z);\n}\n");
    } else {
        print_to_builder(*builder, ");\n}\n");
    }
    return builder_to_string(*builder);
}

generate_wrappers :: (reflection: Shader_Reflection, body_builder: *String_Builder, packer_builder: *String_Builder, stage: Material_Stage, root: string, base_off: s64) -> s64 {
    main_func, system_args, params_bytes, slots := stage_schema(*reflection, stage);

    // Leading system arguments are engine-owned. Everything after them is
    // material schema. Only types are enforced; argument names stay loose.
    if stage == {
        case .VERTEX;
            assert(is_vertex_output(main_func.return_type),
                "Material: vertex main must return Vertex_Output. Check the return type; the vertex stage feeds the fragment stage through it.");
            assert(main_func.args.count >= 2,
                "Material: vertex main needs two leading uint arguments (vertex id, instance id), got %", main_func.args.count);
            assert(is_uint32(main_func.args[0].type) && is_uint32(main_func.args[1].type),
                "Material: vertex main leading arguments must both be uint (vertex id, instance id).");
        case .FRAGMENT;
            assert(is_float4(main_func.return_type),
                "Material: fragment main must return float4. Opaque output is plain color; translucent conversion happens in the generated wrapper, not in user code.");
            assert(main_func.args.count >= 1,
                "Material: fragment main needs a leading Vertex_Output input, got %", main_func.args.count);
            assert(is_vertex_output(main_func.args[0].type),
                "Material: fragment main first argument must be Vertex_Output carrying the interpolated vertex data.");
    }

    // Blob region layout matches common.slang: [params byte size u32]
    // [slot count u32][slots u32...][params bytes]. Schema measured above;
    // here only emit with final offsets.
    // An empty region emits zero bytes, not even a header.
    if params_bytes == 0 && slots == 0 return base_off;

    params_base := base_off + 8 + slots * 4;
    print_to_builder(packer_builder, "    (cast(*u32)(cpu8 + %)).* = xx %;\n", base_off + 0, params_bytes);
    print_to_builder(packer_builder, "    (cast(*u32)(cpu8 + %)).* = xx %;\n", base_off + 4, slots);
    params_off := params_base;
    slot := 0;
    for system_args..main_func.args.count-1 {
        decl := main_func.args[it];
        if decl.type.kind == .STRUCT {
            t := decl.type.(*Shader_Type_Struct);
            params_off = (params_off + t.alignment - 1) / t.alignment * t.alignment;
            type_name := slang_to_jai(decl.type);
            assert(type_name.count > 0, "Material: unsupported struct parameter %", decl.name);
            print_to_builder(body_builder, "\t%: %;\n", decl.name, type_name);
            print_to_builder(packer_builder, "    memcpy(cpu8 + %, *material.%.%, %);\n", params_off, root, decl.name, xx t.stride);
            params_off += xx t.stride;
            continue;
        }
        if decl.type.kind == .RESOURCE {
            slot_off := base_off + 8 + slot * 4;
            print_to_builder(body_builder, "\t%: Name;\n", decl.name);
            print_to_builder(packer_builder, "    (cast(*u32)(cpu8 + %)).* = resolve_texture_index(data, material.%.%);\n", slot_off, root, decl.name);
            slot += 1;
            continue;
        }
        // SAMPLER_STATE is the only remaining kind; measured above.
        slot_off := base_off + 8 + slot * 4;
        print_to_builder(packer_builder, "    (cast(*u32)(cpu8 + %)).* = default_sampler_index(data);\n", slot_off);
        slot += 1;
    }

    return params_base + params_bytes;
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

to_jai_type_name :: (name: string) -> string {
    builder: String_Builder;
    init_string_builder(*builder);
    defer free_buffers(*builder);

    is_lower :: (c: u8) -> bool {
        return c >= #char "a" && c <= #char "z";
    }

    is_upper :: (c: u8) -> bool {
        return c >= #char "A" && c <= #char "Z";
    }

    is_digit :: (c: u8) -> bool {
        return c >= #char "0" && c <= #char "9";
    }

    is_alpha :: (c: u8) -> bool {
        return is_lower(c) || is_upper(c);
    }

    to_upper :: (c: u8) -> u8 {
        if is_lower(c) return cast(u8)(c - #char "a" + #char "A");
        return c;
    }

    to_lower :: (c: u8) -> u8 {
        if is_upper(c) return cast(u8)(c - #char "A" + #char "a");
        return c;
    }

    word_start := true;
    wrote_any  := false;
    pending_sep := false;

    i := 0;
    while i < name.count {
        c := name[i];

        prev: u8 = 0;
        next: u8 = 0;

        if i > 0 then prev = name[i - 1];
        if i + 1 < name.count then next = name[i + 1];

        // Anything except ASCII letters/digits is a word separator.
        if !is_alpha(c) && !is_digit(c) {
            if wrote_any {
                word_start = true;
                pending_sep = true;
            }

            i += 1;
            continue;
        }

        camel_boundary := is_upper(c) && i > 0 && (is_lower(prev) || (is_upper(prev) && is_lower(next)));

        if camel_boundary {
            append(*builder, #char "_");
            pending_sep = false;
            word_start = true;
        } else if pending_sep {
            append(*builder, #char "_");
            pending_sep = false;
        }

        // Identifier cannot start with a digit.
        if !wrote_any && is_digit(c) {
            append(*builder, #char "_");
        }

        if word_start && is_alpha(c) {
            append(*builder, to_upper(c));
            word_start = false;
        } else if is_alpha(c) {
            append(*builder, to_lower(c));
        } else {
            append(*builder, c);
            word_start = false;
        }

        wrote_any = true;
        i += 1;
    }

    return builder_to_string(*builder);
}

#import "Compiler";

GENERATED_TYPE_SCOPE :: #code {};

build_jai_struct :: (shader_type: *Shader_Type_Struct, name: string) -> string {
    builder: String_Builder;
    defer free_buffers(*builder);

    print_to_builder(*builder, "#scope_export\n% :: struct {\n", name);
    for field: shader_type.fields {
        field_name := slang_to_jai(field.type);
        assert(field_name.count > 0, "Material: unsupported field %.%", shader_type.name, field.name);
        print_to_builder(*builder, "    %: %;\n", field.name, field_name);
    }

    print_to_builder(*builder, "}\n\n#run validate_shader_mirror(%, %, %, .[", name, shader_type.stride, shader_type.alignment);
    for field: shader_type.fields {
        if it_index > 0 print_to_builder(*builder, ", ");
        print_to_builder(*builder, "%", field.offset);
    }

    print_to_builder(*builder, "]);\n");

    return builder_to_string(*builder);
}

validate_shader_mirror :: ($T: Type, stride: u64, alignment: s64, offsets: []u64) {
    // Jai includes tail padding in size_of; Slang reports it separately as stride.
    assert(size_of(T) == stride, "Material: % Jai size % does not match shader stride %", T, size_of(T), stride);

    Alignment :: struct { prefix: u8; value: T; }
    sample: Alignment;
    jai_alignment := cast(s64) *sample.value - cast(s64) *sample;
    assert(jai_alignment == alignment, "Material: % Jai alignment % does not match shader alignment %", T, jai_alignment, alignment);

    info := type_info(T);
    assert(info.members.count == offsets.count, "Material: % field count does not match shader layout", T);
    for member: info.members {
        assert(cast(u64) member.offset_in_bytes == offsets[it_index],
            "Material: %.% Jai offset % does not match shader offset %", T, member.name, member.offset_in_bytes, offsets[it_index]);
    }
}

slang_to_jai :: (shader_type: Shader_Type) -> string {
    if !shader_type return "";

    found, cached_name := table_find(*_generated_types, shader_type);
    if found return cached_name;

    return build_jai_type(shader_type);
}

build_jai_type :: (shader_type: Shader_Type) -> string {
    if shader_type.kind == {
        case .SCALAR; {
            type := shader_type.(*Shader_Type_Scalar);
            // Slang bool occupies four bytes in uniform data; Jai bool occupies one.
            // FLOAT16 has no Jai mirror; VOID/NONE are not material data.
            if type.scalar_type == {
                case .BOOL;   return "u32";
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
            assert(false, "Scalar type % is illegal for scalar variables.", type.scalar_type);        }

        case .ARRAY; {
            type := shader_type.(*Shader_Type_Array);
            element_name := slang_to_jai(type.element_type);
            assert(element_name.count > 0, "Material: unsupported array element type %", type.element_type.name);
            return sprint("[%]%", type.element_count, element_name);
        }

        case .VECTOR; {
            type := shader_type.(*Shader_Type_Vector);
            components := type.scalar_count;

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
            assert(false, "Scalar type % is illegal for vector variables", type.scalar_type);
        }
        case .MATRIX; {
            type := shader_type.(*Shader_Type_Matrix);
            assert(type.layout == .ROW_MAJOR, "Material: column-major matrix field found, only row-major mirrors are supported. Remove the column_major qualifier from the shader field and check the Slang session matrix layout mode. Jai Matrix stores rows contiguously, so a column-major shader matrix would read back transposed.");
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
            assert(false, "Material: unsupported matrix shape %x%", type.row_count, type.column_count);
        }

        case .STRUCT; {
            type: *Shader_Type_Struct = shader_type.(*Shader_Type_Struct);
            name := to_jai_type_name(type.name);
            body := build_jai_struct(type, name);
            defer free(body);
            add_build_string(body, -1, GENERATED_TYPE_SCOPE);
            table_add(*_generated_types, shader_type, name);
            return name;
        }
        case .RESOURCE; {
            type := shader_type.(*Shader_Type_Resource);
            // Texture assets resolve through the asset system at upload time,
            // so the recipe holds a Name, not GPU data.
            if type.shape == .TEXTURE_2D return "Name";
        }
        case .SAMPLER_STATE; {
            // Samplers resolve to the stock sampler at upload time.
            // No recipe field needed; the slot still counts in declaration order.
            return "";
        }
        case; {
            log_warning("Unsupported shader type kind: %: %", shader_type.name, shader_type.kind);
        }
    }
    return "";
}
