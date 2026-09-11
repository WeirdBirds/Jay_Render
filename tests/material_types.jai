#import "Basic";
#import "Compiler";
#load "../module.jai";

#run {
    set_build_options_dc(.{ do_output = false });
    opaque_registry_count = 0;
    translucent_registry_count = 0;
    opaque_index := register_material(.OPAQUE, Name.{ id = 1 }, Name.{ id = 2 });
    translucent_index := register_material(.TRANSLUCENT, Name.{ id = 3 }, Name.{ id = 4 });
    assert(opaque_index == 0 && translucent_index == 0,
        "Per-domain material indexes must start at zero");
    assert(opaque_registry_count == 1 && translucent_registry_count == 1,
        "Each material domain must own its registry count");
    assert(opaque_registry[0].vertex_id.id == 1 && translucent_registry[0].vertex_id.id == 3,
        "Per-domain material entries must remain isolated");

    args := get_build_options().compile_time_command_line;
    fixture := ifx args.count > 0 then args[0] else "material_types";
    body, packer: String_Builder;
    defer free_buffers(*body);
    defer free_buffers(*packer);

    if args.count > 0 {
        reflection := get_shader_reflection(tprint("%/shaders/%.slang", #filepath, fixture));
        defer free_reflection(*reflection);
        generate_wrappers(reflection, *body, *packer, .FRAGMENT, "fragment", 0);
        return;
    }

    draw_reflection := get_shader_reflection(tprint("%/shaders/draw_layout.slang", #filepath));
    defer free_reflection(*draw_reflection);
    draw_main := find_main(*draw_reflection);
    print("draw_layout: args %\n", draw_main.args.count);
    assert(draw_main.args.count == 2, "Draw layout reflection must expose input and command arguments");
    draw_type := draw_main.args[1].type.(*Shader_Type_Struct);
    print("draw_layout: host stride %, shader stride %\n", size_of(Draw_Indexed_Command), draw_type.stride);
    assert(size_of(Draw_Indexed_Command) == draw_type.stride,
        "Indirect command host stride must match the shader array stride");
    assert(draw_type.stride == 20 && draw_type.fields.count == 5);
    host_draw := type_info(Draw_Indexed_Command);
    assert(host_draw.members.count == draw_type.fields.count);
    for field: draw_type.fields {
        assert(field.offset == cast(u64)(it_index * 4));
        assert(cast(u64) host_draw.members[it_index].offset_in_bytes == field.offset);
        scalar := field.type.(*Shader_Type_Scalar);
        if it_index == 3 {
            assert(scalar.scalar_type == .INT32);
        } else {
            assert(scalar.scalar_type == .UINT32);
        }
    }
    commands: [2]Draw_Indexed_Command;
    assert(cast(s64) *commands[1] - cast(s64) *commands[0] == 20,
        "Group 1 must read the command written at shader byte offset 20");

    vertex_reflection := get_shader_reflection(tprint("%/shaders/vertex_types.slang", #filepath));
    defer free_reflection(*vertex_reflection);
    vertex_end := generate_wrappers(vertex_reflection, *body, *packer, .VERTEX, "vertex", 0);
    assert(vertex_end == 0, "Empty vertex recipe must end at offset 0, got %", vertex_end);

    reflection := get_shader_reflection(tprint("%/shaders/material_types.slang", #filepath));
    defer free_reflection(*reflection);

    main := find_main(*reflection);
    assert(main.args.count == 3, "Expected three main parameters, got %", main.args.count);
    assert(main.args[0].name == "input");

    total := generate_wrappers(reflection, *body, *packer, .FRAGMENT, "fragment", vertex_end);
    assert(total == 408, "Fragment blob must total 408 bytes, got %", total);
    emit_upload_proc(*body, *packer, total);
    text := builder_to_string(*body);
    defer free(text);
    assert(text == EXPECTED_BODY, "Fragment body mismatch, got %", text);
    wrapper_text := make_shader_wrapper(reflection, "material_types.slang", .FRAGMENT, vertex_end);
    defer free(wrapper_text);
    assert(wrapper_text == EXPECTED_WRAPPER, "Fragment wrapper mismatch, got %", wrapper_text);
    translucent_wrapper := make_shader_wrapper(reflection, "material_types.slang", .FRAGMENT, vertex_end, .TRANSLUCENT);
    defer free(translucent_wrapper);
    assert(translucent_wrapper == EXPECTED_TRANSLUCENT_WRAPPER,
        "Translucent wrapper mismatch, got %", translucent_wrapper);

    texture_reflection := get_shader_reflection(tprint("%/shaders/texture_types.slang", #filepath));
    defer free_reflection(*texture_reflection);
    texture_body, texture_packer: String_Builder;
    defer free_buffers(*texture_body);
    defer free_buffers(*texture_packer);
    texture_total := generate_wrappers(texture_reflection, *texture_body, *texture_packer, .FRAGMENT, "fragment", 0);
    assert(texture_total == 36, "Texture blob must total 36 bytes, got %", texture_total);
    texture_wrapper := make_shader_wrapper(texture_reflection, "texture_types.slang", .FRAGMENT, 0);
    defer free(texture_wrapper);
    assert(texture_wrapper == EXPECTED_TEXTURE_WRAPPER, "Texture wrapper mismatch, got %", texture_wrapper);
    emit_upload_proc(*texture_body, *texture_packer, texture_total);
    texture_text := builder_to_string(*texture_body);
    defer free(texture_text);
    assert(texture_text == EXPECTED_TEXTURE_BODY, "Texture body mismatch, got %", texture_text);

    found, name := table_find(*_generated_types, main.args[1].type);
    assert(found && name == "Mirror_Params");

    before := 0;
    for _generated_types before += 1;
    generate_wrappers(reflection, *body, *packer, .FRAGMENT, "fragment", 0);
    after := 0;
    for _generated_types after += 1;
    assert(after == before, "A cached type must not generate a second body");

    add_build_string(CHECK_GENERATED_TYPES, -1, TEST_SCOPE);
}

find_main :: (reflection: *Shader_Reflection) -> *Shader_Function {
    for reflection.functions {
        if it.name == "main" return *reflection.functions[it_index];
    }
    assert(false, "Material test: main function not found");
    return null;
}

free_reflection :: (reflection: *Shader_Reflection) {
    for reflection.functions array_free(it.args);
    array_free(reflection.functions);
    array_free(reflection.variables);
}

EXPECTED_BODY :: #string END
	params: Mirror_Params;
	second_params: Mirror_Params;
upload :: (data: *Render_Data, material: Material(vs_name, fs_name, domain)) -> Material_Id {
    cpu, gpu := gpu_malloc(408);
    assert(cpu != null && gpu != 0, "Material: GPU allocation failed");
    cpu8 := cast(*u8) cpu;
    (cast(*u32)(cpu8 + 0)).* = xx 400;
    (cast(*u32)(cpu8 + 4)).* = xx 0;
    memcpy(cpu8 + 8, *material.fragment.params, 200);
    memcpy(cpu8 + 208, *material.fragment.second_params, 200);
    hash: u64 = 14695981039346656037;
    for i: 0..408-1 {
        hash ^= xx (cpu8 + i).*;
        hash *= 1099511628211;
    }
    found := table_find_pointer(*data.material_cache, hash);
    if found {
        found.ref_count += 1;
        gpu_free(cpu);
        return found.id;
    }
    id := cast(Material_Id) gpu;
    table_add(*data.material_cache, hash, Uploaded_Material.{ id = id, item_hash = hash, ref_count = 1, allocation = cpu, gpu = gpu, size = 408 });
    return id;
}
END

EXPECTED_WRAPPER :: #string END
#include "material_types.slang"
[shader("fragment")]
float4 _jay_main(Vertex_Output input) : SV_Target0 {
    uint64_t blob = Jay::material_blob(input.instance_id);
    return main(input, *(MirrorParams*)(Jay::params_blob(blob) + 0), *(MirrorParams*)(Jay::params_blob(blob) + 200));
}
END

EXPECTED_TRANSLUCENT_WRAPPER :: #string END
#include "material_types.slang"
[shader("fragment")]
Translucent_Fragment _jay_main(Vertex_Output input) {
    uint64_t blob = Jay::material_blob(input.instance_id);
    return translucent_fragment(main(input, *(MirrorParams*)(Jay::params_blob(blob) + 0), *(MirrorParams*)(Jay::params_blob(blob) + 200)), input.position.z);
}
END

EXPECTED_TEXTURE_BODY :: #string END
	params: Coated_Params;
	albedo: Name;
upload :: (data: *Render_Data, material: Material(vs_name, fs_name, domain)) -> Material_Id {
    cpu, gpu := gpu_malloc(36);
    assert(cpu != null && gpu != 0, "Material: GPU allocation failed");
    cpu8 := cast(*u8) cpu;
    (cast(*u32)(cpu8 + 0)).* = xx 20;
    (cast(*u32)(cpu8 + 4)).* = xx 2;
    memcpy(cpu8 + 16, *material.fragment.params, 20);
    (cast(*u32)(cpu8 + 8)).* = resolve_texture_index(data, material.fragment.albedo);
    (cast(*u32)(cpu8 + 12)).* = default_sampler_index(data);
    hash: u64 = 14695981039346656037;
    for i: 0..36-1 {
        hash ^= xx (cpu8 + i).*;
        hash *= 1099511628211;
    }
    found := table_find_pointer(*data.material_cache, hash);
    if found {
        found.ref_count += 1;
        gpu_free(cpu);
        return found.id;
    }
    id := cast(Material_Id) gpu;
    table_add(*data.material_cache, hash, Uploaded_Material.{ id = id, item_hash = hash, ref_count = 1, allocation = cpu, gpu = gpu, size = 36 });
    return id;
}
END

EXPECTED_TEXTURE_WRAPPER :: #string END
#include "texture_types.slang"
[shader("fragment")]
float4 _jay_main(Vertex_Output input) : SV_Target0 {
    uint64_t blob = Jay::material_blob(input.instance_id);
    return main(input, *(CoatedParams*)(Jay::params_blob(blob) + 0), g_textures_2d[Jay::slot_index(blob, 0)], g_samplers[Jay::slot_index(blob, 1)]);
}
END

TEST_SCOPE :: #code {};

CHECK_GENERATED_TYPES :: #string END
#run {
    value: Mirror_Params;
    child: Mirror_Child;
    value.child = child;
    value.children[0] = child;
    assert(type_of(value.child) == type_of(value.children[0]));
    assert(type_of(value.base_color) == Vec4);
    assert(type_of(value.uv_shift) == Vec2);
    assert(type_of(value.transform) == Mat4);
    assert(type_of(value.enabled) == u32);
    assert(size_of(Mirror_Child) == 16);
    assert(size_of(Mirror_Params) == 200);
    assert(type_of(value.basis).ROW == 3);
    assert(type_of(value.basis).COL == 4);

    for row: 0..2 {
        for column: 0..3 value.basis.cells[row][column] = xx (row * 4 + column + 1);
    }
    bytes := cast(*float32) *value.basis;
    for 0..11 assert(bytes[it] == cast(float32)(it + 1));
    print("material_types: global declarations, shared identity, cache hits, and row-major storage passed\n");
}
END
