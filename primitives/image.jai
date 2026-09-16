Pixel :: Vector(4, u8, .["r", "g", "b", "a"]);

Image_Data :: struct {
    pixels:   []Pixel;
    width:    s32;
    height:   s32;
    channels: s32;
    texture:  Gpu_Texture;
    view:     Gpu_Texture_View;
}

image_asset_load :: (slot: *Asset_Registry.Asset_Slot) -> bool {
    assert(render.data_initialized, "Texture asset retained before renderer init");
    if slot.object == null return false;
    image := cast(*Image_Data)slot.object;
    if image.pixels.data == null || image.width <= 0 || image.height <= 0 return false;

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

    image.view = gpu_texture_view(texture);
    assert(image.view != 0, "material: texture view creation failed");
    image.texture = texture;
    return true;
}

image_asset_unload :: (slot: *Asset_Registry.Asset_Slot) {
    if slot.object == null return;
    image := cast(*Image_Data)slot.object;
    if render.data_initialized {
        gpu_wait_idle();
        if image.texture != 0 gpu_free(image.texture);
    }
    free(slot.object);
    slot.object = null;
}


