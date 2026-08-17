create_pipelines :: (data: *Render_Data) {
    // Recompile pipeline sources at build time so shared Slang ABI changes
    // cannot leave this pipeline with stale shader cache entries.
    #run {
        compile_pipeline_shader("/shaders/compute/reset.slang");
        compile_pipeline_shader("/shaders/compute/count_cull.slang");
        compile_pipeline_shader("/shaders/compute/prefix.slang");
        compile_pipeline_shader("/shaders/compute/scatter.slang");
        compile_pipeline_shader("/shaders/compute/build_draws.slang");
        compile_pipeline_shader("/shaders/vertex/opaque.slang");
        compile_pipeline_shader("/shaders/fragment/opaque.slang");
    }

    reset_spv   := get_asset(Shader_Data, "/shaders/compute/reset.slang");
    cull_spv    := get_asset(Shader_Data, "/shaders/compute/count_cull.slang");
    prefix_spv  := get_asset(Shader_Data, "/shaders/compute/prefix.slang");
    scatter_spv := get_asset(Shader_Data, "/shaders/compute/scatter.slang");
    build_spv   := get_asset(Shader_Data, "/shaders/compute/build_draws.slang");
    vs_spv      := get_asset(Shader_Data, "/shaders/vertex/opaque.slang");
    fs_spv      := get_asset(Shader_Data, "/shaders/fragment/opaque.slang");

    assert(reset_spv && cull_spv && prefix_spv && scatter_spv && build_spv && vs_spv && fs_spv, "One of shaders are not loaded");

    #if DEBUG log("All shaders compiled.");

    data.pipelines[0] = gpu_create_compute_pipeline(reset_spv.code_words, "Jay_Render reset");
    data.pipelines[1] = gpu_create_compute_pipeline(cull_spv.code_words, "Jay_Render count-cull");
    data.pipelines[2] = gpu_create_compute_pipeline(prefix_spv.code_words, "Jay_Render prefix");
    data.pipelines[3] = gpu_create_compute_pipeline(scatter_spv.code_words, "Jay_Render scatter");
    data.pipelines[4] = gpu_create_compute_pipeline(build_spv.code_words, "Jay_Render build draws");

    blend: Gpu_Blend_Desc = {};

    raster: Gpu_Raster_Desc = .{
        cull = .CCW,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
        depth_format = .D32_SFLOAT,
        blend_state = *blend
    };

    data.pipelines[5] = gpu_create_graphics_pipeline(vs_spv.code_words, fs_spv.code_words, raster, "Jay_Render opaque");
}

compile_pipeline_shader :: (asset_path: string) {
    source_path := get_asset_source_path(asset_path);
    assert(source_path.count > 0, "Pipeline shader asset path not found: %", asset_path);

    vfs := make_shader_vfs(get_asset_source);
    defer cleanup_shader_vfs(vfs);

    compiled, spirv := compile_shader(source_path, "", DEBUG, vfs);
    defer if spirv.data free(spirv.data);
    assert(compiled, "Pipeline shader compilation failed: %", source_path);
}
