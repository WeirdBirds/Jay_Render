#scope_module

#import "File";
#import "String";

Render_Pipeline_Id :: enum {
    RESET;
    COUNT_CULL;
    PREFIX;
    SCATTER;
    BUILD_DRAWS;
    TRANSLUCENT_COMPOSITE;
    HIZ_DOWNSAMPLE;
    COUNT;
}

retain_shader :: (path: string) -> Handle {
    return retain(Shader_Data, Name.new(tprint(path)));
}

create_pipelines :: (data: *Render_Data) {
    #run {
        compile_pipeline_shader("/shaders/compute/reset.slang");
        compile_pipeline_shader("/shaders/compute/count_cull.slang");
        compile_pipeline_shader("/shaders/compute/prefix.slang");
        compile_pipeline_shader("/shaders/compute/scatter.slang");
        compile_pipeline_shader("/shaders/compute/build_draws.slang");
        compile_pipeline_shader("/shaders/compute/hiz_downsample.slang");
        compile_pipeline_shader("/shaders/vertex/translucent_composite.slang");
        compile_pipeline_shader("/shaders/fragment/translucent_composite.slang");
    }

    reset_h := retain_shader("/shaders/compute/reset.slang");
    defer release(reset_h);
    cull_h := retain_shader("/shaders/compute/count_cull.slang");
    defer release(cull_h);
    prefix_h := retain_shader("/shaders/compute/prefix.slang");
    defer release(prefix_h);
    scatter_h := retain_shader("/shaders/compute/scatter.slang");
    defer release(scatter_h);
    build_h := retain_shader("/shaders/compute/build_draws.slang");
    defer release(build_h);
    hiz_h := retain_shader("/shaders/compute/hiz_downsample.slang");
    defer release(hiz_h);
    translucent_vs_h := retain_shader("/shaders/vertex/translucent_composite.slang");
    defer release(translucent_vs_h);
    translucent_fs_h := retain_shader("/shaders/fragment/translucent_composite.slang");
    defer release(translucent_fs_h);

    reset_spv   := get_asset(reset_h, Shader_Data);
    cull_spv    := get_asset(cull_h, Shader_Data);
    prefix_spv  := get_asset(prefix_h, Shader_Data);
    scatter_spv := get_asset(scatter_h, Shader_Data);
    build_spv   := get_asset(build_h, Shader_Data);
    hiz_spv     := get_asset(hiz_h, Shader_Data);
    translucent_vs_spv := get_asset(translucent_vs_h, Shader_Data);
    translucent_fs_spv := get_asset(translucent_fs_h, Shader_Data);

    data.pipelines[Render_Pipeline_Id.RESET] = gpu_create_compute_pipeline(reset_spv.code_words, "Jay_Render reset");
    data.pipelines[Render_Pipeline_Id.COUNT_CULL] = gpu_create_compute_pipeline(cull_spv.code_words, "Jay_Render count-cull");
    data.pipelines[Render_Pipeline_Id.PREFIX] = gpu_create_compute_pipeline(prefix_spv.code_words, "Jay_Render prefix");
    data.pipelines[Render_Pipeline_Id.SCATTER] = gpu_create_compute_pipeline(scatter_spv.code_words, "Jay_Render scatter");
    data.pipelines[Render_Pipeline_Id.BUILD_DRAWS] = gpu_create_compute_pipeline(build_spv.code_words, "Jay_Render build draws");
    data.pipelines[Render_Pipeline_Id.TRANSLUCENT_COMPOSITE] = gpu_create_graphics_pipeline(translucent_vs_spv.code_words, translucent_fs_spv.code_words, .{
        cull = .NONE,
        color_targets = .[.{
            format = .B8G8R8A8_UNORM,
            blend_state = .{
                enabled = true,
                src_color_factor = .SRC_ALPHA,
                dst_color_factor = .ONE_MINUS_SRC_ALPHA,
                src_alpha_factor = .ONE,
                dst_alpha_factor = .ONE_MINUS_SRC_ALPHA,
            },
        }],
    }, "Jay_Render translucent composite");
    assert(data.pipelines[Render_Pipeline_Id.TRANSLUCENT_COMPOSITE] != 0, "Jay_Render: translucent composite pipeline creation failed");
    data.pipelines[Render_Pipeline_Id.HIZ_DOWNSAMPLE] = gpu_create_compute_pipeline(hiz_spv.code_words, "Jay_Render hiz downsample");

    // assert(opaque_registry_count + translucent_registry_count > 0, "Jay_Render: no materials registered");
    assert(opaque_registry_count <= MAX_MATERIALS && translucent_registry_count <= MAX_MATERIALS, "Jay_Render: material registry exceeds capacity");

    data.opaque_pipeline_count = opaque_registry_count;
    if opaque_registry_count > 0 {
        for i: 0..opaque_registry_count - 1 {
            entry := opaque_registry[i];
            vs_h := retain(Shader_Data, entry.vertex_id);
            defer release(vs_h);
            fs_h := retain(Shader_Data, entry.fragment_id);
            defer release(fs_h);
            vs_spv := get_asset(vs_h, Shader_Data);
            fs_spv := get_asset(fs_h, Shader_Data);

            raster: Gpu_Raster_Desc = .{
                cull = .CCW,
                color_targets = .[.{ format = .B8G8R8A8_UNORM }],
                depth_format = .D32_SFLOAT,
            };
            data.opaque_pipelines[i] = gpu_create_graphics_pipeline(
                vs_spv.code_words, fs_spv.code_words, raster, tprint("Jay_Render opaque material %", i));
            assert(data.opaque_pipelines[i] != 0, "Jay_Render: opaque material pipeline creation failed");
        }
    }

    data.translucent_pipeline_count = translucent_registry_count;
    if translucent_registry_count > 0 {
        for i: 0..translucent_registry_count - 1 {
            entry := translucent_registry[i];
            vs_h := retain(Shader_Data, entry.vertex_id);
            defer release(vs_h);
            fs_h := retain(Shader_Data, entry.fragment_id);
            defer release(fs_h);
            vs_spv := get_asset(vs_h, Shader_Data);
            fs_spv := get_asset(fs_h, Shader_Data);

            raster: Gpu_Raster_Desc = .{
                cull = .CCW,
                color_targets = .[
                    .{
                        format = .R16G16B16A16_SFLOAT,
                        blend_state = .{
                            enabled = true,
                            src_color_factor = .ONE,
                            dst_color_factor = .ONE,
                            src_alpha_factor = .ONE,
                            dst_alpha_factor = .ONE,
                        },
                    },
                    .{
                        format = .R16_SFLOAT,
                        blend_state = .{
                            enabled = true,
                            src_color_factor = .ZERO,
                            dst_color_factor = .ONE_MINUS_SRC_COLOR,
                            src_alpha_factor = .ZERO,
                            dst_alpha_factor = .ONE_MINUS_SRC_ALPHA,
                        },
                    },
                ],
                depth_format = .D32_SFLOAT,
            };
            data.translucent_pipelines[i] = gpu_create_graphics_pipeline(
                vs_spv.code_words, fs_spv.code_words, raster, tprint("Jay_Render translucent material %", i));
            assert(data.translucent_pipelines[i] != 0, "Jay_Render: translucent material pipeline creation failed");
        }
    }
}

// Pipeline #run owns Slang packaging (no generic slang handler).
// It compiles each shader and writes its Shader_Data package so runtime
// retains serve owned SPIR-V bytes. Shared with Material #insert, which
// packages exactly the shaders materials use.
compile_pipeline_shader :: (asset_path: string) {
    source_path := get_asset_source_path(asset_path);
    assert(source_path.count > 0, "Jay_Render: shader source not found: %", asset_path);

    vfs := make_shader_vfs(get_asset_source);
    defer cleanup_shader_vfs(vfs);

    compiled, spirv := compile_shader(source_path, "", vfs);
    defer if spirv.data free(spirv.data);
    assert(compiled, "Jay_Render: shader compilation failed: %", source_path);

    name := Name.new(asset_path);
    out_path := sprint("%/%", Paths.assets_out, sprint("%.jpkg", name.id));
    pkg := Shader_Data.{ code_words = spirv, reflection = "" };
    write(out_path, pkg);
}
