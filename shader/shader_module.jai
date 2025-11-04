// SHADER COMPILE-TIME PROCESSING

#run {
    #import "Slang";
    #import "File";
    #import "File_Utilities";
    #import "Process";
    #import "String";
    #import "System";

    shader_in := sprint("%/assets/shaders/", get_working_directory());
    shader_out := sprint("%/.intermediate/shaders/", get_working_directory());
    
    make_directory_if_it_does_not_exist(shader_in, true);
    make_directory_if_it_does_not_exist(shader_out, true);

    shader_compiler_available :: () -> bool
    {
        result := run_command("slangc", "-version", capture_and_return_output = true);
        return result.exit_code == 0;
    }

    build_shader :: (filename : string, output : string) #expand
    {
        result, out_string, error_string := run_command("slangc", filename, "-o", output, "-target", "spirv", "-profile", "spirv_1_5", "-emit-spirv-directly", capture_and_return_output = true);
        if result.exit_code != 0
            log("Couldn't build shader %!! Error: %\n", filename, out_string);
        else
            log("Built % to %\n", filename, output);
    }

    shaders: [] string = file_list(shader_in, true);

    in_time := file_modtime_and_size(shader_in);
    out_time := file_modtime_and_size(shader_out);

    if in_time>out_time {
        shaders_out : [] string = file_list(shader_out, true);
        for shader: shaders_out {
            in: string = trim_right(replace(shader, shader_out, shader_in), ".spv");
            if !file_exists(in) {
                file_delete(shader);
            }
        }
    }

    
    if shader_compiler_available() {
        
        for shader: shaders {
            if ends_with(shader, ".slang") {
                out: string = join(replace(shader, shader_in, shader_out), ".spv");
                in_time = file_modtime_and_size(shader);
                out_time = file_modtime_and_size(out);
                if out_time<in_time {
                    build_shader(shader, out);
                }
            }
        }
    }
    else
    {
        log("Not building shaders because we couldn't find a compiler to do it\n");
    }
}

create_shader_module :: (name: string) -> VkShaderModule {
    file_path := join(path_strip_filename(get_path_of_running_executable()), "assets/shaders/", name, ".spv");
    defer free(file_path);
    code, success := read_entire_file(file_path); // context.execution_path
    defer free(code); 

    if !success {
        log_error("Unable to read shader file: %", name);
    }

    create_info := VkShaderModuleCreateInfo.{};
    create_info.codeSize = xx code.count;
    create_info.pCode = xx code.data;

    module: VkShaderModule = null;
    vkCreateShaderModule(render_app.device, *create_info, null, *module);
    return module;
}


