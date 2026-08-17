# Jay_Render

SGPU-backed Vulkan forward renderer for Jay. It uses GPU-driven visibility,
indirect indexed draws, Slang shaders, SDL3 windows, dynamic rendering, and
three SGPU-owned frames in flight.

`Jay_Render` remains Jay_Core package API. The temporary cow scene in
`package.jai` is development-only and will later be replaced by ECS scene data.

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
    MATERIAL_HEAP_BUDGET = 128 * MiB,
    GPU_HEAP_ALIGNMENT = 8,
    GPU_HEAP_GROWTH_FACTOR = 1.5,
);
```

All limits are compile-time module parameters. Invalid values fail before GPU
initialization. `MAX_DRAWS` must be at least `MAX_GROUPS`. Different textual
parameter lists create distinct Jai module instances; use one shared import
configuration across renderer users.

SGPU currently fixes frames in flight at three. Jay_Render intentionally keeps
`MAX_FRAMES_IN_FLIGHT` coupled to that SGPU value.

## Debug, capture, and windows

- `DEBUG` enables SGPU validation layers, debug assertions, markers, and
  renderer diagnostic logging.
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
2. `begin`: load current development assets and create cow instances.
3. `before_tick`: process SDL events.
4. `after_tick`: recreate swapchain/depth after resize, acquire, cull, build
   indirect commands, and submit/present.
5. `after_end`: wait idle, release all renderer-owned resources, destroy
   swapchain, shut down SGPU, then destroy SDL state.

Startup failure invokes the same guarded shutdown path. Shutdown clears renderer
state, so partially initialized resources are not reused.

## Contiguous GPU heaps

Vertex, index, and material storage each use one contiguous SGPU-backed
`VkBuffer`. Heap growth waits for GPU idle, allocates one larger buffer, copies
mapped bytes, preserves allocation offsets, refreshes root addresses, then frees
the old buffer.

No heap is segmented. Persistent references are offsets or indices, not durable
raw GPU addresses:

- mesh vertex and index data use offsets from their heap roots;
- `Material_Handle` is a packed material-buffer index;
- each `Mesh_Instance` stores `material_index`;
- `Fragment_Params.materials` is the one material-buffer root address.

This means material-buffer relocation updates one root address rather than every
instance. Draw groups contain only mesh identity; material is per instance, so
same-mesh material variants share one indirect draw group.

Growth is automatic. Shrink is deliberately explicit:

```jai
renderer_trim_memory();
```

Call it only at a scene unload, loading screen, or another maintenance boundary.
It waits for GPU idle, retains allocation offsets, and shrinks only when all live
allocation data fits. There is no frame-count delay or automatic grow/shrink
oscillation.

## Compile-time materials

`Material(vertex, fragment)` remains a compile-time metaprogram construct. Its
`#insert` pass:

1. resolves both shader asset source paths;
2. creates a Slang virtual filesystem;
3. compiles both shader stages to SPIR-V, with debug symbols following `DEBUG`;
4. fails compilation with the offending shader path when Slang fails;
5. reflects declarations only after successful stage compilation;
6. frees SPIR-V, reflection, and VFS temporary resources.

Material construction is not runtime reflection or descriptor setup.

## Current renderer path

- Compute reset, cull/count, prefix, scatter, and indirect-draw generation.
- Indirect indexed drawing with dynamic depth rendering.
- Per-instance material index lookup in fragment shading.
- Destroyed instance slots are skipped by culling, allowing index-pool reuse.
- Resize rebuilds depth state after swapchain resize.

## Dependencies

- Jay_Core
- Jay_Utils
- SGPU
- jai-sdl3
- Slang compiler support supplied through SGPU
