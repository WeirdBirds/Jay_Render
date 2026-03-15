error_callback :: (error: s32, description: *u8) #c_call {
    push_context {
        context.logger = default_logger;
        log("[Vulkan %]: %", error, to_string(description), flags=Log_Flags.ERROR);
    }
}


debug_callback :: (flags: VkDebugReportFlagsEXT, objType: VkDebugReportObjectTypeEXT, obj: u64, location: u64, code: s32, layerPrefix: *u8, msg: *u8, userData: *void) -> VkBool32 #c_call {
    push_context {
        context.logger = default_logger;

        l_flags: Log_Flags;

        if flags & VkDebugReportFlagsEXT.INFORMATION_BIT_EXT then l_flags |= Log_Flags.CONTENT;
        if flags & VkDebugReportFlagsEXT.WARNING_BIT_EXT then l_flags |= Log_Flags.WARNING;
        if flags & VkDebugReportFlagsEXT.PERFORMANCE_WARNING_BIT_EXT then l_flags |= Log_Flags.WARNING;
        if flags & VkDebugReportFlagsEXT.ERROR_BIT_EXT then l_flags |= Log_Flags.ERROR;

    
        object := "";
        if objType == { 
            case VkDebugReportObjectTypeEXT.INSTANCE_EXT;                       object = "Instance";
            case VkDebugReportObjectTypeEXT.PHYSICAL_DEVICE_EXT;                object = "PhysicalDevice";
            case VkDebugReportObjectTypeEXT.DEVICE_EXT;                         object = "Device";
            case VkDebugReportObjectTypeEXT.QUEUE_EXT;                          object = "Queue";
            case VkDebugReportObjectTypeEXT.SEMAPHORE_EXT;                      object = "Semaphore";
            case VkDebugReportObjectTypeEXT.COMMAND_BUFFER_EXT;                 object = "CommandBuffer";
            case VkDebugReportObjectTypeEXT.FENCE_EXT;                          object = "Fence";
            case VkDebugReportObjectTypeEXT.DEVICE_MEMORY_EXT;                  object = "DeviceMemory";
            case VkDebugReportObjectTypeEXT.BUFFER_EXT;                         object = "Buffer";
            case VkDebugReportObjectTypeEXT.IMAGE_EXT;                          object = "Image";
            case VkDebugReportObjectTypeEXT.EVENT_EXT;                          object = "Event";
            case VkDebugReportObjectTypeEXT.QUERY_POOL_EXT;                     object = "QueryPool";
            case VkDebugReportObjectTypeEXT.BUFFER_VIEW_EXT;                    object = "BufferView";
            case VkDebugReportObjectTypeEXT.IMAGE_VIEW_EXT;                     object = "ImageView";
            case VkDebugReportObjectTypeEXT.SHADER_MODULE_EXT;                  object = "ShaderModule";
            case VkDebugReportObjectTypeEXT.PIPELINE_CACHE_EXT;                 object = "PipelineCache";
            case VkDebugReportObjectTypeEXT.PIPELINE_LAYOUT_EXT;                object = "PipelineLayout";
            case VkDebugReportObjectTypeEXT.RENDER_PASS_EXT;                    object = "RenderPass";
            case VkDebugReportObjectTypeEXT.PIPELINE_EXT;                       object = "Pipeline";
            case VkDebugReportObjectTypeEXT.DESCRIPTOR_SET_LAYOUT_EXT;          object = "DescriptorSetLayout";
            case VkDebugReportObjectTypeEXT.SAMPLER_EXT;                        object = "Sampler";
            case VkDebugReportObjectTypeEXT.DESCRIPTOR_POOL_EXT;                object = "DescriptorPool";
            case VkDebugReportObjectTypeEXT.DESCRIPTOR_SET_EXT;                 object = "DescriptorSet";
            case VkDebugReportObjectTypeEXT.FRAMEBUFFER_EXT;                    object = "Framebuffer";
            case VkDebugReportObjectTypeEXT.COMMAND_POOL_EXT;                   object = "CommandPool";
            case VkDebugReportObjectTypeEXT.SURFACE_KHR_EXT;                    object = "SurfaceKHR";
            case VkDebugReportObjectTypeEXT.SWAPCHAIN_KHR_EXT;                  object = "SwapchainKHR";
            // Aliases (same numeric value) grouped together:
            case VkDebugReportObjectTypeEXT.DEBUG_REPORT_CALLBACK_EXT_EXT;      object = "DebugReportCallback";
            case VkDebugReportObjectTypeEXT.DISPLAY_KHR_EXT;                    object = "Display";
            case VkDebugReportObjectTypeEXT.DISPLAY_MODE_KHR_EXT;               object = "DisplayMode";
            // Aliases (same numeric value) grouped together:
            case VkDebugReportObjectTypeEXT.VALIDATION_CACHE_EXT_EXT;           object = "ValidationCache";
            // Aliases (same numeric value) grouped together:
            case VkDebugReportObjectTypeEXT.SAMPLER_YCBCR_CONVERSION_EXT;       object = "SamplerYcbcrConversion";
            // Aliases (same numeric value) grouped together:
            case VkDebugReportObjectTypeEXT.DESCRIPTOR_UPDATE_TEMPLATE_EXT;     object = "DescriptorUpdateTemplate";
            case VkDebugReportObjectTypeEXT.CU_MODULE_NVX_EXT;                  object = "CUModuleNVX";
            case VkDebugReportObjectTypeEXT.CU_FUNCTION_NVX_EXT;                object = "CUFunctionNVX";
            case VkDebugReportObjectTypeEXT.ACCELERATION_STRUCTURE_KHR_EXT;     object = "AccelerationStructureKHR";
            case VkDebugReportObjectTypeEXT.ACCELERATION_STRUCTURE_NV_EXT;      object = "AccelerationStructureNV";
            case VkDebugReportObjectTypeEXT.CUDA_MODULE_NV_EXT;                 object = "CudaModuleNV";
            case VkDebugReportObjectTypeEXT.CUDA_FUNCTION_NV_EXT;               object = "CudaFunctionNV";
            case VkDebugReportObjectTypeEXT.BUFFER_COLLECTION_FUCHSIA_EXT;      object = "BufferCollectionFUCHSIA"; 
        }

        log("\x1b[0m[\x1b[35m\x1b[1mVulkan % %\x1b[0m]: %",object, to_string(layerPrefix), to_string(msg), flags=l_flags);
    }
    
    return VK_FALSE;
}

#scope_module

default_logger: #type (message: string, data: *void, info: Log_Info) -> ();
