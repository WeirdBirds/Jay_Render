test :: Material("/shaders/vertex/opaque.slang", "/shaders/fragment/opaque.slang");

Material :: struct(vertex: string, fragment: string) {
    #insert -> string {
        vertex_path := get_asset_source_path(vertex);
        fragment_path := get_asset_source_path(fragment);
        
        vfs := make_shader_vfs(get_asset_source);
        defer cleanup_shader_vfs(vfs);

        vertex_decls := get_shader_declarations(vertex_path, vfs);
        fragment_decls := get_shader_declarations(fragment_path, vfs);

        for vertex_decls.decls {
            log("%: %", it.name, it.type.generic_arg[0]);
        }
        // log("%", fragment_decls);

        return "";
    }
}
