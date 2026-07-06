Shader_Data :: struct {
    code_words: []u32;
}

Shader_Text :: struct {
    code: string;
}

get_shader :: (path: string) -> string {
    asset_name := Name.from_path(path); 

    text := get_asset(Shader_Text, asset_name);
    // defer unload_asset(Shader_Text, asset_name);

    if text
        return text.code;

    return "";
}
