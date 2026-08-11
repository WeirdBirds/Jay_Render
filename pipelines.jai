create_pipelines :: (data: *Render_Data) {
    reset_spv   := get_asset(Shader_Data, "/shaders/compute/reset.slang");
    cull_spv    := get_asset(Shader_Data, "/shaders/compute/count_cull.slang");
    prefix_spv  := get_asset(Shader_Data, "/shaders/compute/prefix.slang");
    scatter_spv := get_asset(Shader_Data, "/shaders/compute/scatter.slang");
    build_spv   := get_asset(Shader_Data, "/shaders/compute/build_draws.slang");
    vs_spv      := get_asset(Shader_Data, "/shaders/vertex/opaque.slang");
    fs_spv      := get_asset(Shader_Data, "/shaders/fragment/opaque.slang");

    assert(reset_spv && cull_spv && prefix_spv && scatter_spv && build_spv && vs_spv && fs_spv, "One of shaders are not loaded");

    log("All shaders compiled.");

    data.pipelines[0] = gpu_create_compute_pipeline(reset_spv.code_words);
    data.pipelines[1] = gpu_create_compute_pipeline(cull_spv.code_words);
    data.pipelines[2] = gpu_create_compute_pipeline(prefix_spv.code_words);
    data.pipelines[3] = gpu_create_compute_pipeline(scatter_spv.code_words);
    data.pipelines[4] = gpu_create_compute_pipeline(build_spv.code_words);

    blend: Gpu_Blend_Desc = {};

    raster: Gpu_Raster_Desc = .{
        cull = .CCW,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
        depth_format = .D32_SFLOAT,
        blend_state = *blend
    };

    data.pipelines[5] = gpu_create_graphics_pipeline(vs_spv.code_words, fs_spv.code_words, raster);
}
