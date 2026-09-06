#scope_module

#import "File";
#import "String";

create_pipelines :: (data: *Render_Data) {
    #run {
        compile_pipeline_shader("/shaders/compute/reset.slang");
        compile_pipeline_shader("/shaders/compute/count_cull.slang");
        compile_pipeline_shader("/shaders/compute/prefix.slang");
        compile_pipeline_shader("/shaders/compute/scatter.slang");
        compile_pipeline_shader("/shaders/compute/build_draws.slang");
        compile_pipeline_shader("/shaders/compute/hiz_downsample.slang");
    }

    reset_spv   := get_asset(Shader_Data, "/shaders/compute/reset.slang");
    cull_spv    := get_asset(Shader_Data, "/shaders/compute/count_cull.slang");
    prefix_spv  := get_asset(Shader_Data, "/shaders/compute/prefix.slang");
    scatter_spv := get_asset(Shader_Data, "/shaders/compute/scatter.slang");
    build_spv   := get_asset(Shader_Data, "/shaders/compute/build_draws.slang");
    hiz_spv     := get_asset(Shader_Data, "/shaders/compute/hiz_downsample.slang");

    assert(reset_spv && cull_spv && prefix_spv && scatter_spv && build_spv && hiz_spv,
        "Jay_Render: shader asset loading failed");

    data.pipelines[0] = gpu_create_compute_pipeline(reset_spv.code_words, "Jay_Render reset");
    data.pipelines[1] = gpu_create_compute_pipeline(cull_spv.code_words, "Jay_Render count-cull");
    data.pipelines[2] = gpu_create_compute_pipeline(prefix_spv.code_words, "Jay_Render prefix");
    data.pipelines[3] = gpu_create_compute_pipeline(scatter_spv.code_words, "Jay_Render scatter");
    data.pipelines[4] = gpu_create_compute_pipeline(build_spv.code_words, "Jay_Render build draws");
    data.pipelines[6] = gpu_create_compute_pipeline(hiz_spv.code_words, "Jay_Render hiz downsample");

    // One graphics pipeline per registered material. Raster state follows
    // the domain: opaque writes depth with no blending, translucent blends
    // over it with depth read-only. Packages were written at compile time
    // by Material #insert, so runtime only loads and creates.
    assert(material_registry_count > 0 && material_registry_count <= MAX_MATERIALS,
        "Jay_Render: no materials registered");
    data.material_pipeline_count = material_registry_count;
    for i: 0..material_registry_count - 1 {
        entry := material_registry[i];
        vs_spv := get_asset(Shader_Data, Name.{ id = entry.vertex_id });
        fs_spv := get_asset(Shader_Data, Name.{ id = entry.fragment_id });
        assert(vs_spv && fs_spv, "Jay_Render: material shader asset loading failed");

        if entry.domain == cast(u32) Material_Domain.OPAQUE {
            blend: Gpu_Blend_Desc = {};
            raster: Gpu_Raster_Desc = .{
                cull = .CCW,
                color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
                depth_format = .D32_SFLOAT,
                blend_state = *blend,
            };
            data.material_pipelines[i] = gpu_create_graphics_pipeline(vs_spv.code_words, fs_spv.code_words, raster, tprint("Jay_Render material % opaque", i));
        } else {
            blend: Gpu_Blend_Desc = .{
                src_color_factor = .SRC_ALPHA, dst_color_factor = .ONE_MINUS_SRC_ALPHA,
                src_alpha_factor = .ONE, dst_alpha_factor = .ONE_MINUS_SRC_ALPHA,
            };
            raster: Gpu_Raster_Desc = .{
                cull = .CCW,
                color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
                depth_format = .D32_SFLOAT,
                blend_state = *blend,
            };
            data.material_pipelines[i] = gpu_create_graphics_pipeline(vs_spv.code_words, fs_spv.code_words, raster, tprint("Jay_Render material % translucent", i));
        }
        assert(data.material_pipelines[i] != 0, "Jay_Render: material pipeline creation failed");
    }
}

// Pipeline #run owns Slang packaging (no generic slang handler).
// It compiles each shader and writes its Shader_Data package so runtime
// get_asset loads owned SPIR-V bytes. Shared with Material #insert, which
// packages exactly the shaders materials use.
compile_pipeline_shader :: (asset_path: string) {
    source_path := get_asset_source_path(asset_path);
    assert(source_path.count > 0, "Jay_Render: shader source not found: %", asset_path);

    vfs := make_shader_vfs(get_asset_source);
    defer cleanup_shader_vfs(vfs);

    compiled, spirv := compile_shader(source_path, "", DEBUG, vfs, DEBUG);
    defer if spirv.data free(spirv.data);
    assert(compiled, "Jay_Render: shader compilation failed: %", source_path);

    name := Name.new(asset_path);
    out_path := sprint("%/%", Paths.assets_out, sprint("%.jpkg", name.id));
    pkg := Shader_Data.{ code_words = spirv, reflection = "" };
    write(out_path, pkg);
}

// Material shaders expose an ordinary main() with material arguments. Compile
// a virtual sibling source whose sole entry resolves one instance blob then
// calls that function with native Slang values.
compile_material_pipeline_shader :: (asset_path: string, reflection: Shader_Reflection) {
    source_path := get_asset_source_path(asset_path);
    assert(source_path.count > 0, "Jay_Render: shader source not found: %", asset_path);
    source_dir := path_strip_filename(source_path);
    source_name := string.{ data = source_path.data + source_dir.count, count = source_path.count - source_dir.count };
    generated_path := sprint("%/_jay_material_entry.slang", source_dir);

    generated: String_Builder;
    print_to_builder(*generated, "#include \"%\"\n", source_name);
    print_to_builder(*generated, "[shader(\"fragment\")]\nfloat4 _jay_main(Vertex_Output input) : SV_Target0 {\n");
    print_to_builder(*generated, "    uint64_t blob = Jay::material_blob(input.instance_id);\n    return main(input");
    slot := 0;
    params_count := 0;
    for reflection.decls {
        if it.type.resource_shape == .TEXTURE_2D {
            print_to_builder(*generated, ", g_textures_2d[Jay::slot_index(blob, %)]", slot);
            slot += 1;
        } else if it.type.name == "SamplerState" {
            print_to_builder(*generated, ", g_samplers[Jay::slot_index(blob, %)]", slot);
            slot += 1;
        } else {
            assert(it.type.kind == .STRUCT, "Material: unsupported main parameter %", it.name);
            params_count += 1;
            assert(params_count == 1, "Material: one struct parameter per fragment shader is supported");
            print_to_builder(*generated, ", *(%*)Jay::params_blob(blob)", it.type.name);
        }
    }
    print_to_builder(*generated, ");\n}\n");
    generated_source := builder_to_string(*generated);
    defer free(generated_source.data);

    vfs := make_shader_vfs(get_asset_source, generated_path, generated_source);
    defer cleanup_shader_vfs(vfs);
    compiled, spirv := compile_shader(generated_path, "", DEBUG, vfs, DEBUG, "_jay_main");
    defer if spirv.data free(spirv.data);
    assert(compiled, "Jay_Render: material shader compilation failed: %", source_path);

    name := Name.new(asset_path);
    write(sprint("%/%.jpkg", Paths.assets_out, name.id), Shader_Data.{ code_words = spirv, reflection = "" });
}
