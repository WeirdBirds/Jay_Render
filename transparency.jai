#scope_module

create_transparency_buffers :: () {
    width, height := gpu_get_surface_extent();
    if width == 0 || height == 0 return;

    result, translucent_color := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .R16G16B16A16_SFLOAT,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    }, label = "Jay_Render translucent color");
    assert(result == .SUCCESS && translucent_color != 0, "Jay_Render: translucent color creation failed");

    result=, translucent_coverage := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .R16_SFLOAT,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    }, label = "Jay_Render translucent coverage");
    assert(result == .SUCCESS && translucent_coverage != 0, "Jay_Render: translucent coverage creation failed");

    translucent_color_view := gpu_texture_view(translucent_color);
    translucent_coverage_view := gpu_texture_view(translucent_coverage);
    assert(translucent_color_view != 0 && translucent_coverage_view != 0, "Jay_Render: translucent view creation failed");

    render.viewport.translucent_color = translucent_color;
    render.viewport.translucent_color_view = translucent_color_view;
    render.viewport.translucent_coverage = translucent_coverage;
    render.viewport.translucent_coverage_view = translucent_coverage_view;
    render.data.fragment_params.translucent_color = cast(u32) translucent_color_view;
    render.data.fragment_params.translucent_coverage = cast(u32) translucent_coverage_view;
}

destroy_transparency_buffers :: () {
    if render.viewport.translucent_color gpu_free(render.viewport.translucent_color);
    if render.viewport.translucent_coverage gpu_free(render.viewport.translucent_coverage);
    render.viewport.translucent_color = 0;
    render.viewport.translucent_color_view = 0;
    render.viewport.translucent_coverage = 0;
    render.viewport.translucent_coverage_view = 0;
}

recreate_transparency_buffers :: () {
    destroy_transparency_buffers();
    create_transparency_buffers();
}
