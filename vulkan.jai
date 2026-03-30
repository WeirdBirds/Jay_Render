#load "vulkan/device.jai";
#load "vulkan/instance.jai";
#load "vulkan/callback.jai";
#load "vulkan/surface.jai";
#load "vulkan/swapchain.jai";
#load "vulkan/render.jai";
#load "vulkan/image.jai";
#load "vulkan/depth.jai";
#load "vulkan/shader_module.jai";
#load "vulkan/memory.jai";
#load "vulkan/descriptors.jai";
#load "vulkan/pipeline.jai";
#load "vulkan/texture.jai";
#load "vulkan/mesh.jai";

init_vulkan :: () {
    load_global_proc_addresses();

    print_available_vulkan_layers();
    print_available_vulkan_extensions();

    create_instance();
    create_surface();
    create_device();
    create_swapchain();
    create_depth();
    create_descriptors();
    create_render();
    create_pipeline();
}

deinit_vulkan :: () {
    destroy_pipeline();
    destroy_render();
    destroy_descriptors();
    destroy_depth();
    destroy_swapchain();
    destroy_device();
    destroy_surface();
    destroy_instance();
}

print_available_vulkan_extensions :: () {
    extension_count: u32;
    vkEnumerateInstanceExtensionProperties(null, *extension_count, null);
    extension_array := NewArray(extension_count, VkExtensionProperties);
    defer free(extension_array.data);
    vkEnumerateInstanceExtensionProperties(null, *extension_count, extension_array.data);
    print("Available extensions:\n");
    for extension_array
        print("    % (%)\n", to_string(it.extensionName.data), it.specVersion);
}

print_available_vulkan_layers :: () {
    extension_count: u32;
    vkEnumerateInstanceLayerProperties(*extension_count, null);
    extension_array := NewArray(extension_count, VkLayerProperties);
    defer free(extension_array.data);
    vkEnumerateInstanceLayerProperties(*extension_count, extension_array.data);
    print("Available layers:\n");
    for extension_array
        print("    % (%.%.%)\n", to_string(it.layerName.data), VK_VERSION_MAJOR(it.specVersion), VK_VERSION_MINOR(it.specVersion), VK_VERSION_PATCH(it.specVersion));
}
