Material_Id :: #type,distinct Gpu_Ptr;

#scope_module

// Renderer-owned GPU material record behind a Material_Id.
Uploaded_Material :: struct {
    id: Material_Id;
    item_hash: u64;
    ref_count: s64;
    allocation: *void;
    gpu: Gpu_Ptr;
    size: s64;
}
