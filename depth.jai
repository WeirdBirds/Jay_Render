create_depth_buffer :: () {
    width, height := gpu_get_surface_extent();
    if width == 0 || height == 0 {
        return;
    }

    result, texture := gpu_create_texture(.{
        dimensions = .[width, height, 1],
        format = .D32_SFLOAT,
        usage = .DEPTH_STENCIL_ATTACHMENT,
    }, label = "Jay_Render depth buffer");
    assert(result == .SUCCESS && texture != 0);

    view := gpu_texture_view(texture);
    assert(view != 0);

    render.viewport.depth_buffer = texture;
    render.viewport.depth = view;
}

destroy_depth_buffer :: () {
    if render.viewport.depth_buffer {
        gpu_free(render.viewport.depth_buffer);
    }

    render.viewport.depth_buffer = 0;
    render.viewport.depth = 0;
}

recreate_depth_buffer :: () {
    destroy_depth_buffer();
    create_depth_buffer();
}
