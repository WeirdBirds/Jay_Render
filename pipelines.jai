create_pipelines :: (data: *Render_Data, shader_vfs: *Shader_VFS) {
    ok_r,  reset_spv   := compile_shader("/shaders/compute/reset.slang",      file_system = shader_vfs);
    ok_c,  cull_spv    := compile_shader("/shaders/compute/count_cull.slang", file_system = shader_vfs);
    ok_p,  prefix_spv  := compile_shader("/shaders/compute/prefix.slang",     file_system = shader_vfs);
    ok_s,  scatter_spv := compile_shader("/shaders/compute/scatter.slang",    file_system = shader_vfs);
    ok_b,  build_spv   := compile_shader("/shaders/compute/build_draws.slang", file_system = shader_vfs);
    ok_vs, vs_spv      := compile_shader("/shaders/vertex/opaque.slang",      file_system = shader_vfs);
    ok_fs, fs_spv      := compile_shader("/shaders/fragment/opaque.slang",    file_system = shader_vfs);

    assert(ok_r && ok_c && ok_p && ok_s && ok_b && ok_vs && ok_fs);

    log("All shaders compiled.");

    data.pipelines[0] = gpu_create_compute_pipeline(reset_spv);
    data.pipelines[1] = gpu_create_compute_pipeline(cull_spv);
    data.pipelines[2] = gpu_create_compute_pipeline(prefix_spv);
    data.pipelines[3] = gpu_create_compute_pipeline(scatter_spv);
    data.pipelines[4] = gpu_create_compute_pipeline(build_spv);

    blend: Gpu_Blend_Desc = {};

    raster: Gpu_Raster_Desc = .{
        cull = .CCW,
        color_targets = .[ .{format = .B8G8R8A8_UNORM} ],
        depth_format = .D32_SFLOAT,
        blend_state = *blend
    };

    data.pipelines[5] = gpu_create_graphics_pipeline(vs_spv, fs_spv, raster);
}
