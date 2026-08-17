Material_Handle :: #type,distinct u32;
INVALID_MATERIAL_HANDLE :: U32_MAX;

// GPU material records stay tightly packed in one contiguous material heap.
// Shader-visible users keep Material_Handle indices, never raw device pointers.
// Match Slang physical-buffer layout: 16-byte alignment and 32-byte stride.
Material_GPU :: struct {
    base_color:    Vec4;
    texture_index: u32;
    sampler_index: u32;
    flags:         u32;
    padding:       u32;
}
