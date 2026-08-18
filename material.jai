test :: Material("/shaders/vertex/opaque.slang", "/shaders/fragment/opaque.slang");

Material :: struct(vertex: string, fragment: string) {
    #insert -> string {
        vertex_path := get_asset_source_path(vertex);
        fragment_path := get_asset_source_path(fragment);
        #if DEBUG { assert(vertex_path && fragment_path, "Material: shader asset path not found"); }

        vfs := make_shader_vfs(get_asset_source);
        defer cleanup_shader_vfs(vfs);

        // Reflection alone may accept a module that fails entry-point linking.
        // Compile both stages in this metaprogram pass before using reflection.
        vertex_ok, vertex_spirv := compile_shader(vertex_path, "", DEBUG, vfs);
        defer if vertex_spirv.data free(vertex_spirv.data);
        #if DEBUG { assert(vertex_ok, "Material: vertex Slang compilation failed for %", vertex_path); }

        fragment_ok, fragment_spirv := compile_shader(fragment_path, "", DEBUG, vfs);
        defer if fragment_spirv.data free(fragment_spirv.data);
        #if DEBUG { assert(fragment_ok, "Material: fragment Slang compilation failed for %", fragment_path); }

        vertex_decls := get_shader_declarations(vertex_path, vfs);
        defer free_shader_declarations(*vertex_decls);
        fragment_decls := get_shader_declarations(fragment_path, vfs);
        defer free_shader_declarations(*fragment_decls);

        return "";
    }
}
