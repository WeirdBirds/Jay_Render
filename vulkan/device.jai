create_device :: () {
    device_handles:          [MAX_DEVICE_COUNT] VkPhysicalDevice;
    queue_family_properties: [MAX_QUEUE_COUNT] VkQueueFamilyProperties;
    
    physical_device_count:   u32;

    vkEnumeratePhysicalDevices(render_app.instance, *physical_device_count, null);
    physical_device_count = min(physical_device_count, MAX_DEVICE_COUNT);
    vkEnumeratePhysicalDevices(render_app.instance, *physical_device_count, device_handles.data);

    log("Phisical devices total: %", physical_device_count);

    device_id := get_suitable_device(device_handles, physical_device_count);

    render_app.physical_device = device_handles[device_id];

    queue_family_count: u32 = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(render_app.physical_device, *queue_family_count, null);
    queue_family_count = min(queue_family_count, MAX_QUEUE_COUNT);
    vkGetPhysicalDeviceQueueFamilyProperties(render_app.physical_device, *queue_family_count, queue_family_properties.data);

    log("    Queue families: %", queue_family_count);

    q_ids := Queue_Indices.{};

    for j: 0..queue_family_count-1 {
        log("    Queue family %:", j);
      
        supports_present := VK_FALSE;
        vkGetPhysicalDeviceSurfaceSupportKHR(render_app.physical_device, j, render_app.surface, *supports_present);

        log("        Presentation support %:", supports_present);

        print("        Queue family properites: %.\n", FormatStruct.{formatter =.{queue_family_properties[j]}, draw_type_name=false, use_long_form_if_more_than_this_many_members = -1});

        if supports_present && q_ids.graphics < 0 && (queue_family_properties[j].queueFlags & .GRAPHICS_BIT) {        
            q_ids.graphics = j;
            continue;
        }

        if !supports_present && q_ids.transfer < 0 && (queue_family_properties[j].queueFlags & .TRANSFER_BIT) && !(queue_family_properties[j].queueFlags & .COMPUTE_BIT) {        
            q_ids.transfer = j;
            continue;
        }

        if q_ids.compute < 0 && (queue_family_properties[j].queueFlags & .COMPUTE_BIT) {        
            q_ids.compute = j;
            continue;
        }
    }

    //fallback to graphics
    q_ids.transfer       = ifx q_ids.transfer < 0 then q_ids.graphics else q_ids.transfer;
    q_ids.compute        = ifx q_ids.compute  < 0 then q_ids.graphics else q_ids.compute;

    render_app.q_indices = q_ids;

    queue_infos: [3]VkDeviceQueueCreateInfo; 

    // GRAPHICS QUEUES
    queue_infos[0].queueFamilyIndex = xx q_ids.graphics;
    queue_infos[0].queueCount       = 1;
    queue_infos[0].pQueuePriorities = float.[1.0].data;

    // TRANSFER QUEUES
    queue_infos[1].queueFamilyIndex = xx q_ids.transfer;
    queue_infos[1].queueCount       = 1;
    queue_infos[1].pQueuePriorities = float.[1.0].data;

    // COMPUTE QUEUES
    queue_infos[2].queueFamilyIndex = xx q_ids.compute;
    queue_infos[2].queueCount       = 1;
    queue_infos[2].pQueuePriorities = float.[1.0].data;

    log("     GRAPHICS QUEUE: %", q_ids.graphics);
    log("     TRANSFER QUEUE: %", q_ids.transfer);
    log("     COMPUTE QUEUE: %", q_ids.compute);



    extensions: [2]*u8;
    extensions[0] = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    extensions[1] = VK_KHR_SHADER_DRAW_PARAMETERS_EXTENSION_NAME;

    // Enable Vulkan 1.3 features (dynamic rendering, synchronization2)
    vulkan13_features: VkPhysicalDeviceVulkan13Features = .{};
    vulkan13_features.dynamicRendering = VK_TRUE;
    vulkan13_features.synchronization2 = VK_TRUE;

    // Enable Vulkan 1.2 features (descriptor indexing for bindless textures)
    vulkan12_features: VkPhysicalDeviceVulkan12Features = .{};
    vulkan12_features.pNext                                        = *vulkan13_features;
    vulkan12_features.runtimeDescriptorArray                       = VK_TRUE;
    vulkan12_features.descriptorBindingPartiallyBound              = VK_TRUE;
    vulkan12_features.descriptorBindingVariableDescriptorCount     = VK_TRUE;
    vulkan12_features.shaderSampledImageArrayNonUniformIndexing    = VK_TRUE;
    vulkan12_features.descriptorBindingSampledImageUpdateAfterBind = VK_TRUE;

    // Enable base Vulkan 1.0 features
    device_features: VkPhysicalDeviceFeatures = .{};
    device_features.samplerAnisotropy = VK_TRUE;
    device_features.fillModeNonSolid  = VK_TRUE;
    device_features.multiDrawIndirect = VK_TRUE;

    device_info: VkDeviceCreateInfo = .{};
    device_info.pNext                   = *vulkan12_features;
    device_info.queueCreateInfoCount    = queue_infos.count;
    device_info.pQueueCreateInfos       = queue_infos.data;
    device_info.enabledLayerCount       = 0;
    device_info.ppEnabledLayerNames     = null;
    device_info.enabledExtensionCount   = extensions.count;
    device_info.ppEnabledExtensionNames = extensions.data;
    device_info.pEnabledFeatures        = *device_features;

    result := vkCreateDevice(render_app.physical_device, *device_info, null, *render_app.device);

    if result != .SUCCESS
        log_error("Unable to create Vulkan device: %", result);

    vkGetDeviceQueue(render_app.device, xx q_ids.graphics, queueIndex=0, *render_app.queues.graphics);
    vkGetDeviceQueue(render_app.device, xx q_ids.transfer, queueIndex=0, *render_app.queues.transfer);
    vkGetDeviceQueue(render_app.device, xx q_ids.compute, queueIndex=0, *render_app.queues.compute);

    load_device_proc_addresses(render_app.device);
}

destroy_device :: () {
    vkDestroyDevice(render_app.device, null);
}

get_suitable_device :: (device_handles: [] VkPhysicalDevice, count: u32) -> s64 {
    best_device_id: s64 = 0;
    best_score:     s64 = -1;
    
    for i: 0..count-1 {
        props: VkPhysicalDeviceProperties;
        vkGetPhysicalDeviceProperties(device_handles[i], *props);
        
        // Score devices: DISCRETE_GPU=3, INTEGRATED_GPU=2, VIRTUAL_GPU=1, others=0
        score: s64 = 0;
        if props.deviceType == .DISCRETE_GPU {
            score = 3;
        } else if props.deviceType == .INTEGRATED_GPU {
            score = 2;
        } else if props.deviceType == .VIRTUAL_GPU
            score = 1;
        
        if score > best_score {
            best_score     = score;
            best_device_id = i;
        }
        
        // Log device info
        device_name := to_string(props.deviceName.data);
        log("    Device %: % (type: %)", i, device_name, props.deviceType);
    }
    
    // Log selected device
    selected_props: VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(device_handles[best_device_id], *selected_props);
    selected_name := to_string(selected_props.deviceName.data);
    log("Selected device: % (type: %)", selected_name, selected_props.deviceType);
    
    return best_device_id;
}

#scope_module

MAX_DEVICE_COUNT :: 8;
MAX_QUEUE_COUNT  :: 8;  

Queue_Indices :: struct {
    graphics: s64 = -1;
    transfer: s64 = -1;
    compute: s64 = -1;
}
