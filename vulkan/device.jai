create_device :: () {
    device_handles:        [MAX_DEVICE_COUNT]VkPhysicalDevice;
    physical_device_count: u32;

    vkEnumeratePhysicalDevices(render_app.instance, *physical_device_count, null);
    assert(physical_device_count > 0, "No Vulkan physical devices found.");

    physical_device_count = min(physical_device_count, MAX_DEVICE_COUNT);
    vkEnumeratePhysicalDevices(render_app.instance, *physical_device_count, device_handles.data);

    log("Phisical devices total: %", physical_device_count);

    device_id := get_suitable_device(device_handles, physical_device_count);
    render_app.physical_device = device_handles[device_id];

    q_ids := get_queue_indices(render_app.physical_device, log_details = true);
    assert(q_ids.graphics >= 0, "Selected Vulkan device is missing a graphics+present queue.");
    assert(q_ids.transfer >= 0, "Selected Vulkan device is missing a transfer-capable queue.");
    assert(q_ids.compute  >= 0, "Selected Vulkan device is missing a compute-capable queue.");
    render_app.q_indices = q_ids;

    queue_family_properties: [MAX_QUEUE_COUNT]VkQueueFamilyProperties;
    queue_family_count: u32 = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(render_app.physical_device, *queue_family_count, null);
    queue_family_count = min(queue_family_count, MAX_QUEUE_COUNT);
    vkGetPhysicalDeviceQueueFamilyProperties(render_app.physical_device, *queue_family_count, queue_family_properties.data);

    graphics_timestamps_supported := queue_family_properties[xx q_ids.graphics].timestampValidBits > 0;
    selected_props: VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(render_app.physical_device, *selected_props);

    render_app.gpu_timing.timestamp_period_ns = cast(float64) selected_props.limits.timestampPeriod;
    render_app.gpu_timing.enabled             = selected_props.limits.timestampComputeAndGraphics != VK_FALSE && graphics_timestamps_supported;

    if render_app.gpu_timing.enabled {
        log("GPU timestamps enabled: period=% ns", render_app.gpu_timing.timestamp_period_ns);
    } else {
        log("GPU timestamps unavailable on graphics queue; GPU pass timings disabled");
    }

    queue_infos: [3]VkDeviceQueueCreateInfo;
    queue_priorities := float.[1.0];
    queue_info_count: u32 = 1;

    queue_infos[0].queueFamilyIndex = xx q_ids.graphics;
    queue_infos[0].queueCount       = 1;
    queue_infos[0].pQueuePriorities = queue_priorities.data;

    if q_ids.transfer != q_ids.graphics {
        queue_infos[queue_info_count].queueFamilyIndex = xx q_ids.transfer;
        queue_infos[queue_info_count].queueCount       = 1;
        queue_infos[queue_info_count].pQueuePriorities = queue_priorities.data;
        queue_info_count += 1;
    }

    if q_ids.compute != q_ids.graphics && q_ids.compute != q_ids.transfer {
        queue_infos[queue_info_count].queueFamilyIndex = xx q_ids.compute;
        queue_infos[queue_info_count].queueCount       = 1;
        queue_infos[queue_info_count].pQueuePriorities = queue_priorities.data;
        queue_info_count += 1;
    }

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
    device_features.samplerAnisotropy  = VK_TRUE;
    device_features.fillModeNonSolid   = VK_TRUE;
    device_features.multiDrawIndirect  = VK_TRUE;
    device_features.tessellationShader = VK_TRUE;

    device_info: VkDeviceCreateInfo = .{};
    device_info.pNext                   = *vulkan12_features;
    device_info.queueCreateInfoCount    = queue_info_count;
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

get_suitable_device :: (device_handles: []VkPhysicalDevice, count: u32) -> s64 {
    best_device_id: s64 = 0;
    best_score:     s64 = -1;

    if count > 0 {
        for i: 0..count - 1 {
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

            supported := device_meets_requirements(device_handles[i], *props);
            if !supported
                score = -1;

            if score > best_score {
                best_score     = score;
                best_device_id = i;
            }

            device_name := to_string(props.deviceName.data);
            if supported {
                log("    Device %: % (type: %) [supported]", i, device_name, props.deviceType);
            } else {
                log("    Device %: % (type: %) [missing required Vulkan features/extensions]", i, device_name, props.deviceType);
            }
        }
    }

    assert(best_score >= 0, "No suitable Vulkan device supports the required renderer features.");

    selected_props: VkPhysicalDeviceProperties;
    vkGetPhysicalDeviceProperties(device_handles[best_device_id], *selected_props);
    selected_name := to_string(selected_props.deviceName.data);
    log("Selected device: % (type: %)", selected_name, selected_props.deviceType);

    return best_device_id;
}

get_queue_indices :: (physical_device: VkPhysicalDevice, log_details := false) -> Queue_Indices {
    queue_family_properties: [MAX_QUEUE_COUNT]VkQueueFamilyProperties;
    queue_family_count: u32 = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(physical_device, *queue_family_count, null);
    queue_family_count = min(queue_family_count, MAX_QUEUE_COUNT);
    vkGetPhysicalDeviceQueueFamilyProperties(physical_device, *queue_family_count, queue_family_properties.data);

    if log_details
        log("    Queue families: %", queue_family_count);

    q_ids := Queue_Indices.{};

    if queue_family_count > 0 {
        for j: 0..queue_family_count - 1 {
            supports_present := VK_FALSE;
            vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, j, render_app.surface, *supports_present);

            if log_details {
                log("    Queue family %:", j);
                log("        Presentation support %:", supports_present);
                print("        Queue family properites: %.\n", FormatStruct.{formatter =.{queue_family_properties[j]}, draw_type_name=false, use_long_form_if_more_than_this_many_members = -1});
            }

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
    }

    if q_ids.transfer < 0 && q_ids.graphics >= 0
        q_ids.transfer = q_ids.graphics;

    if q_ids.compute < 0 && q_ids.graphics >= 0 && (queue_family_properties[xx q_ids.graphics].queueFlags & .COMPUTE_BIT)
        q_ids.compute = q_ids.graphics;

    return q_ids;
}

has_required_device_extensions :: (physical_device: VkPhysicalDevice) -> bool {
    required_extensions := string.[
        "VK_KHR_swapchain",
        "VK_KHR_shader_draw_parameters",
    ];

    extension_count: u32 = 0;
    result := vkEnumerateDeviceExtensionProperties(physical_device, null, *extension_count, null);
    if result != .SUCCESS
        return false;

    available_extensions := NewArray(extension_count, VkExtensionProperties);
    defer free(available_extensions.data);

    result = vkEnumerateDeviceExtensionProperties(physical_device, null, *extension_count, available_extensions.data);
    if result != .SUCCESS
        return false;

    found: [2]bool;
    for available_extensions {
        extension_name := to_string(it.extensionName.data);
        for required_index: 0..required_extensions.count - 1 {
            if extension_name == required_extensions[required_index]
                found[required_index] = true;
        }
    }

    for found {
        if !it
            return false;
    }

    return true;
}

has_required_device_features :: (physical_device: VkPhysicalDevice, props: *VkPhysicalDeviceProperties) -> bool {
    device_props := props.*;

    major := VK_VERSION_MAJOR(device_props.apiVersion);
    minor := VK_VERSION_MINOR(device_props.apiVersion);
    if major < 1 || (major == 1 && minor < 3)
        return false;

    vulkan13_features: VkPhysicalDeviceVulkan13Features = .{};
    vulkan12_features: VkPhysicalDeviceVulkan12Features = .{pNext = *vulkan13_features};
    device_features2:  VkPhysicalDeviceFeatures2        = .{pNext = *vulkan12_features};
    vkGetPhysicalDeviceFeatures2(physical_device, *device_features2);

    base_features := device_features2.features;

    return base_features.samplerAnisotropy  == VK_TRUE &&
    base_features.fillModeNonSolid   == VK_TRUE &&
    base_features.multiDrawIndirect  == VK_TRUE &&
    base_features.tessellationShader == VK_TRUE &&
    vulkan13_features.dynamicRendering == VK_TRUE &&
    vulkan13_features.synchronization2 == VK_TRUE &&
    vulkan12_features.runtimeDescriptorArray                       == VK_TRUE &&
    vulkan12_features.descriptorBindingPartiallyBound              == VK_TRUE &&
    vulkan12_features.descriptorBindingVariableDescriptorCount     == VK_TRUE &&
    vulkan12_features.shaderSampledImageArrayNonUniformIndexing    == VK_TRUE &&
    vulkan12_features.descriptorBindingSampledImageUpdateAfterBind == VK_TRUE;
}

supports_required_depth_format :: (physical_device: VkPhysicalDevice) -> bool {
    candidates := VkFormat.[
        .D32_SFLOAT,
        .D32_SFLOAT_S8_UINT,
        .D24_UNORM_S8_UINT,
    ];

    for candidates {
        format_props: VkFormatProperties;
        vkGetPhysicalDeviceFormatProperties(physical_device, it, *format_props);
        if ((format_props.optimalTilingFeatures & .DEPTH_STENCIL_ATTACHMENT_BIT) != 0) &&
        ((format_props.optimalTilingFeatures & .SAMPLED_IMAGE_BIT) != 0)
            return true;
    }

    return false;
}

device_meets_requirements :: (physical_device: VkPhysicalDevice, props: *VkPhysicalDeviceProperties) -> bool {
    q_ids := get_queue_indices(physical_device);
    if q_ids.graphics < 0 || q_ids.transfer < 0 || q_ids.compute < 0
        return false;

    if !has_required_device_extensions(physical_device)
        return false;

    if !has_required_device_features(physical_device, props)
        return false;

    if !supports_required_depth_format(physical_device)
        return false;

    return true;
}

#scope_module

MAX_DEVICE_COUNT :: 8;
MAX_QUEUE_COUNT  :: 8;

Queue_Indices :: struct {
    graphics: s64 = -1;
    transfer: s64 = -1;
    compute:  s64 = -1;
}
