#scope_module

create_transparency_buffers :: () {
    width, height := gpu_get_surface_extent();
    if width == 0 || height == 0 return;

    result, accumulator := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .R16G16B16A16_SFLOAT,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    }, label = "Jay_Render OIT accumulator");
    assert(result == .SUCCESS && accumulator != 0, "Jay_Render: OIT accumulator creation failed");

    result=, revealage := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .R16_SFLOAT,
        usage = .COLOR_ATTACHMENT | .SAMPLED,
    }, label = "Jay_Render OIT revealage");
    assert(result == .SUCCESS && revealage != 0, "Jay_Render: OIT revealage creation failed");

    accumulator_view := gpu_texture_view(accumulator);
    revealage_view := gpu_texture_view(revealage);
    assert(accumulator_view != 0 && revealage_view != 0, "Jay_Render: OIT view creation failed");

    render.viewport.oit_accumulator = accumulator;
    render.viewport.oit_accumulator_view = accumulator_view;
    render.viewport.oit_revealage = revealage;
    render.viewport.oit_revealage_view = revealage_view;
    render.data.fragment_params.oit_accumulator = cast(u32) accumulator_view;
    render.data.fragment_params.oit_revealage = cast(u32) revealage_view;
}

destroy_transparency_buffers :: () {
    if render.viewport.oit_accumulator gpu_free(render.viewport.oit_accumulator);
    if render.viewport.oit_revealage gpu_free(render.viewport.oit_revealage);
    render.viewport.oit_accumulator = 0;
    render.viewport.oit_accumulator_view = 0;
    render.viewport.oit_revealage = 0;
    render.viewport.oit_revealage_view = 0;
}

recreate_transparency_buffers :: () {
    destroy_transparency_buffers();
    create_transparency_buffers();
}
