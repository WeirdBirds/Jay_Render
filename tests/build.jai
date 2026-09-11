// Run from the Jay root: jai engine/Jay_Render/tests/build.jai -import_dir "$PWD/engine"
#import "Basic";
#import "Compiler";
#import,file "material_types.jai";

#if #run get_build_options().compile_time_command_line.count == 0 {
#run {
    value: Mirror_Params;
    child: Mirror_Child;
    value.child = child;
    assert(size_of(type_of(value)) == 200);
    print("material_types: generated declarations are visible to importing consumers\n");
}
}
