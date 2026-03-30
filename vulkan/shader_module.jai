Shader_Data :: struct {
    code: string;
}


create_shader_module :: (name: Name) -> VkShaderModule {
    shader: VkShaderModule;

    s_data := get_asset(Shader_Data, name);
    defer unload_asset(Shader_Data, name);

    assert(s_data.code.count > 0, "Shader asset '%' is empty.", name.id);

    create_info := VkShaderModuleCreateInfo.{};
    create_info.codeSize = xx s_data.code.count;
    create_info.pCode    = xx s_data.code.data;

    result := vkCreateShaderModule(render_app.device, *create_info, null, *shader);
    assert(result == .SUCCESS, "Failed to create shader module '%': %", name.id, result);

    return shader;
}

destroy_shader_module :: (module: VkShaderModule) {
    vkDestroyShaderModule(render_app.device, module, null);
}

clear_shaders :: () {
    clear_asset_registry(Shader_Data);
}
