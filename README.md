# Jay_Render

Vulkan forward renderer for the Jay engine. Uses Vulkan 1.3 dynamic rendering, indirect drawing, and per-frame descriptors. Plugs into Jay_Core as a lifecycle package.

## What it does right now

- Creates a Vulkan 1.3 instance with validation layers (debug) on Linux (Wayland/X11)
- Picks the best GPU (discrete > integrated > virtual)
- Sets up a swapchain with mailbox present mode (falls back to FIFO)
- Renders instanced geometry via a single `vkCmdDrawIndexedIndirect` call
- Per-frame UBO for camera (view, proj, resolution, time) and SSBO for per-object transforms
- Depth testing with D32_SFLOAT
- Shaders written in Slang, compiled to SPIR-V at build time through the asset pipeline
- Handles window resize (swapchain recreation + depth buffer rebuild)
- 3 frames in flight with proper fence/semaphore synchronization

## How it fits in the engine

Jay_Render is a package struct that hooks into the Jay_Core lifecycle:

- `before_begin` — SDL init, window creation, full Vulkan init
- `begin` — upload vertex/index buffers to GPU
- `before_tick` — poll SDL events (quit, resize, scroll)
- `after_tick` — draw frame, handle out-of-date swapchain
- `after_end` — destroy GPU resources, shut down Vulkan

It declares `after: Lifecycle.SimulationComplete` and `before: Lifecycle.RenderComplete` so the Mixer knows where to place it relative to other packages.

## File layout

```
Jay_Render/
  module.jai          # Imports and loads
  package.jai         # Package struct, Render_App, lifecycle callbacks
  camera.jai          # Camera, perspective/view matrices, look-at
  vulkan.jai          # init_vulkan/deinit_vulkan, loads vulkan/*.jai
  common/
    image.jai         # Pixel and Image_Data types
  vulkan/
    instance.jai      # VkInstance, debug report callback
    surface.jai       # VkSurfaceKHR (Wayland/X11)
    device.jai        # Physical/logical device, queue selection
    swapchain.jai     # Swapchain create/destroy/recreate
    depth.jai         # Depth buffer (image + view)
    image.jai         # Image view helpers
    callback.jai      # Vulkan debug + error callbacks
    memory.jai        # GPU_Buffer, create/destroy, staging upload
    descriptors.jai   # UBO/SSBO layout, descriptor pool/sets, indirect buffer
    pipeline.jai      # Graphics pipeline (Slang shaders, vertex input, rasterization)
    shader_module.jai # Shader loading from asset pipeline, registry
    texture.jai       # Texture struct, image upload, sampler creation
    render.jai        # Command pools/buffers, sync objects (fences, semaphores)
  test_render/
    test.jai          # Cube geometry, camera control, draw_frame()
```

## Current state

Phases 1-3 complete (triangle → buffers → descriptors + indirect draw). Working on Phase 4: bindless textures via descriptor indexing.

## Dependencies

- `Jay_Core` (lifecycle, assets, names)
- `Jay_Vulkan` (Vulkan 1.4.313 bindings)
- `jai-sdl3` (SDL3 windowing)
- `Jay_Math` (via Jay_Core — vectors, matrices)
- `Jay_Logger` (via Jay_Core — logging)
