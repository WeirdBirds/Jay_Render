# Jay_Render

SGPU-backed Vulkan forward renderer for Jay. It uses GPU-driven visibility,
indirect indexed draws, Slang shaders, SDL3 windows, dynamic rendering, and
three SGPU-owned frames in flight.

`Jay_Render` owns renderer lifecycle and consumes caller-provided scene data.
`main.jai` owns the development camera scene.

## Import configuration

```jai
#import "Jay_Render"(
    DEBUG = true,
    RENDER_CAPTURE = false,

    MAX_INSTANCES = 262144,
    MAX_MESHES = 65536,
    MAX_GROUPS = 65536,
    MAX_DRAWS = 65536,

    VERTEX_HEAP_BUDGET = 512 * MiB,
    INDEX_HEAP_BUDGET = 128 * MiB,
    GPU_HEAP_ALIGNMENT = 8,
    GPU_HEAP_GROWTH_FACTOR = 1.5,
);
```

All settings are compile-time module parameters. `DEBUG` controls SGPU,
renderer code, and direct shader compilation from one renderer module instance.
Invalid values fail before GPU initialization. `MAX_DRAWS` must be at least
`MAX_GROUPS`. Different textual parameter lists create distinct Jai module
instances; use one shared configuration across renderer users.

SGPU currently fixes frames in flight at three. Jay_Render intentionally keeps
`MAX_FRAMES_IN_FLIGHT` coupled to that SGPU value.

## Debug, capture, and windows

- `DEBUG` enables SGPU validation layers, debug assertions, markers, shader
  debug symbols, and renderer diagnostic logging. Jay_Render compiles shaders
  directly, so release shaders compile out counter atomics and telemetry
  branches while retaining their ABI.
- `RENDER_CAPTURE` enables SGPU RenderDoc capture support and debug markers.
- Linux forces X11 when either `DEBUG` or `RENDER_CAPTURE` is enabled. RenderDoc
  upstream still requires XWayland for reliable Linux frame debugging.
- Normal Linux runs prefer native Wayland when `WAYLAND_DISPLAY` exists; X11 is
  fallback.
- Win32 and Cocoa native-handle paths are compile-time maintained. They are not
  runtime-validated by this Linux repository.

## Ownership and lifecycle

`Jay_Render` owns its SDL window, SGPU initialization, swapchain, depth target,
pipelines, renderer semaphore, parameter blocks, persistent arrays, frame
scratch allocations, index-pool metadata, and GPU heaps.

Lifecycle order:

1. `before_begin`: validate configuration, initialize SGPU and SDL, create the
   native swapchain, queues, render data, pipelines, and depth target.
2. Application `begin`: load scene assets and create scene instances.
3. `before_tick`: process SDL events.
4. `after_tick`: recreate swapchain/depth after coordinate or pixel-size
   changes, acquire, cull, build indirect commands, and submit/present.
5. `after_end`: wait idle, release all renderer-owned resources, destroy
   swapchain, shut down SGPU, then destroy SDL state.

Startup failure invokes the same guarded shutdown path. Shutdown clears renderer
state, so partially initialized resources are not reused.

## Contiguous GPU heaps

Vertex and index storage each use one contiguous SGPU-backed `VkBuffer`. Heap
growth waits for GPU idle, allocates one larger buffer, copies mapped bytes,
preserves allocation offsets, refreshes root addresses, then frees the old
buffer.

Mesh vertex and index data use offsets from their heap roots. Materials work
differently: each upload owns a stable GPU allocation, so a material pointer
never moves.

## Compile-time materials

`Material(vertex = ..., fragment = ..., domain = ...)` generates its recipe
struct from ordinary Slang `main` function parameters. A stage may accept
reflected struct parameters, `Texture2D` parameters, and `SamplerState`
parameters. The generated Jai recipe mirrors struct fields and uses texture
asset names for texture parameters. No hand-written host mirror exists.

Jay_Render generates private `_jay_main` entry point code. It loads one
instance material blob, resolves bindless resource slots, then calls authored
`main` with normal Slang values. `upload_material` packs that blob,
deduplicates identical recipes by hash, and returns a direct GPU pointer
(`Material_Id`). Each `Mesh_Instance` stores that pointer. Draw groups contain mesh identity, domain, and a domain-local pipeline index.
Same-mesh material variants share one pipeline when their reflected shader
schemas match.

Pipeline `#run` owns Slang packaging (no generic slang handler): it compiles
each shader and writes its `Shader_Data` package, so runtime `get_asset` loads
owned SPIR-V bytes.

## Current renderer path

- Compute reset, cull/count, prefix, scatter, and indirect-draw generation.
- Indirect indexed drawing with dynamic depth rendering.
- Per-instance direct material pointer lookup in fragment shading.
- Destroyed instance slots are skipped by culling, allowing index-pool reuse.
- Resize uses framebuffer pixel extent and rebuilds depth and HiZ state after swapchain resize.
- Pipeline `#run` recompiles and repackages every shader, so shared shader
  includes cannot leave stale SPIR-V packages.

## Dependencies

- Jay_Core
- Jay_Utils
- SGPU
- jai-sdl3
- Slang compiler support supplied through SGPU
