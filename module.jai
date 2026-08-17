#module_parameters(
    // Renderer-wide debug and SGPU feature switches.
    DEBUG := true,
    RENDER_CAPTURE := false,
    // Resource limits. These are compile-time contract values so all users
    // of Jay_Render see the same pool and buffer sizes.
    MAX_INSTANCES := 262144,
    MAX_MESHES := 65536,
    MAX_GROUPS := 65536,
    MAX_DRAWS := 65536,

    // CPU-visible renderer heap policy and budgets.
    GPU_HEAP_ALIGNMENT := 8,
    VERTEX_HEAP_BUDGET := 512 * 1024 * 1024,
    INDEX_HEAP_BUDGET := 128 * 1024 * 1024,
    MATERIAL_HEAP_BUDGET := 128 * 1024 * 1024,
    GPU_HEAP_GROWTH_FACTOR := 1.5
);

#import "Basic";
#import "Jay_Core";
#import "Jay_Utils";
#import "Window_Creation"(DEFAULT_MSAA = 1);
#if DEBUG {
    #if RENDER_CAPTURE {
        #import "sgpu"(VALIDATION = true, DEBUG_ASSERTS = true, RENDER_CAPTURE = true, SLANG_COMPILER = true, DEBUG_MARKERS = true);
    } else {
        #import "sgpu"(VALIDATION = true, DEBUG_ASSERTS = true, RENDER_CAPTURE = false, SLANG_COMPILER = true, DEBUG_MARKERS = true);
    }
} else {
    #if RENDER_CAPTURE {
        #import "sgpu"(VALIDATION = false, DEBUG_ASSERTS = false, RENDER_CAPTURE = true, SLANG_COMPILER = true, DEBUG_MARKERS = true);
    } else {
        #import "sgpu"(VALIDATION = false, DEBUG_ASSERTS = false, RENDER_CAPTURE = false, SLANG_COMPILER = true, DEBUG_MARKERS = false);
    }
}
#import "jai-sdl3";

#load "primitives/bounds.jai";
#load "primitives/camera.jai";
#load "primitives/draw.jai";
#load "primitives/image.jai";
#load "primitives/material.jai";
#load "primitives/mesh.jai";
#load "primitives/shader.jai";
#load "gpu_heap.jai";
#load "render_data.jai";
#load "renderer.jai";
#load "depth.jai";
#load "pipelines.jai";
#load "frame.jai";
#load "package.jai";
#load "material.jai";

#load "ecs.jai";

// SGPU owns the frame ring; keep this coupled to its fixed value.
MAX_FRAMES_IN_FLIGHT :: 3;

validate_render_config :: () {
    // Keep this before gpu_init: bad contracts must not leave Vulkan or SDL
    // partially initialized. Pool dimensions remain compile-time values.
    assert(MAX_INSTANCES > 0, "MAX_INSTANCES must be positive");
    assert(MAX_MESHES > 0, "MAX_MESHES must be positive");
    assert(MAX_GROUPS > 0, "MAX_GROUPS must be positive");
    assert(MAX_DRAWS >= MAX_GROUPS, "MAX_DRAWS must be >= MAX_GROUPS");
    assert(VERTEX_HEAP_BUDGET > 0 && VERTEX_HEAP_BUDGET <= S64_MAX - 64, "VERTEX_HEAP_BUDGET is invalid");
    assert(INDEX_HEAP_BUDGET > 0 && INDEX_HEAP_BUDGET <= S64_MAX - 64, "INDEX_HEAP_BUDGET is invalid");
    assert(MATERIAL_HEAP_BUDGET > 0 && MATERIAL_HEAP_BUDGET <= S64_MAX - 64, "MATERIAL_HEAP_BUDGET is invalid");
    assert(GPU_HEAP_ALIGNMENT > 0, "GPU_HEAP_ALIGNMENT must be positive");
    assert(GPU_HEAP_GROWTH_FACTOR > 1 && GPU_HEAP_GROWTH_FACTOR <= 8, "GPU_HEAP_GROWTH_FACTOR must be in (1, 8]");
}
