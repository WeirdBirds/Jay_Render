Shader_Data :: struct {
    code: string;
}


create_shader_module :: (name: Name) -> VkShaderModule {
    found, shader := table_find(*shader_registry, name.id);

    if !found {
        s_data := get_asset(Shader_Data, name);
        defer unload_asset(Shader_Data, name);

        create_info := VkShaderModuleCreateInfo.{};
        create_info.codeSize = xx s_data.code.count;
        create_info.pCode    = xx s_data.code.data;

        vkCreateShaderModule(render_app.device, *create_info, null, *shader);

        table_add(*shader_registry, name.id, shader);
    }

    return shader;
}

destroy_shader_module :: (module: VkShaderModule) {
    vkDestroyShaderModule(render_app.device, module, null);
}

clear_shaders :: () {
    for shader: shader_registry
        destroy_shader_module(shader);

    clear_asset_registry(Shader_Data);
}

#scope_file

shader_registry: Table(u64, VkShaderModule);
