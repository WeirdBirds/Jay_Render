#scope_module

Shader_Data :: struct {
    code_words: []u8;
    reflection: string;
}

shader_asset_load :: (slot: *Asset_Registry.Asset_Slot) -> bool {
    if slot.object == null return false;
    code := cast(*Shader_Data)slot.object;
    return code.code_words.count > 0;
}

shader_asset_unload :: (slot: *Asset_Registry.Asset_Slot) {
    if slot.object == null return;
    free(slot.object);
    slot.object = null;
}


