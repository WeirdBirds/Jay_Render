#import "Basic";
#import "Jay_Core";
#import "Jay_Utils";
#import "Window_Creation"(DEFAULT_MSAA = 1);
#import "sgpu"(VALIDATION = true, DEBUG_ASSERTS = true);
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

DEBUG :: true;

MAX_FRAMES_IN_FLIGHT :: 3;

MAX_INSTANCES :: 262144;
MAX_MESHES    :: 65536;
MAX_GROUPS    :: 65536;
MAX_DRAWS     :: MAX_GROUPS;

VERTICES_BUDGET :: 512 * MiB;
INDICES_BUDGET :: 128 * MiB;
MATERIAL_BUDGET :: 128 * MiB;
