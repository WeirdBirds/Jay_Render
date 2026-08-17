Gpu_Heap :: (capacity: s64, alignment: s64 = 8, memory_type: Memory_Type = .DEFAULT) -> Allocator {
    assert(capacity > 0, "Gpu_Heap capacity must be positive");
    assert(alignment > 0, "Gpu_Heap alignment must be positive");
    assert(memory_type != .GPU, "Gpu_Heap requires CPU-visible memory");

    heap: *Gpu_Heap_Data = New(Gpu_Heap_Data);
    heap.owner_allocator = context.allocator;
    heap.cpu_base, heap.gpu_base = gpu_malloc(capacity, memory_type);
    assert(heap.cpu_base != null && heap.gpu_base != 0, "Gpu_Heap: GPU allocation failed");

    heap.capacity = capacity;
    heap.minimum_capacity = capacity;
    heap.alignment = alignment;
    push_allocator(heap.owner_allocator);
    array_add(*heap.free_list, .{0, capacity});

    return .{proc = heap_proc, data = heap};
}

gpu_heap_destroy :: (allocator: *Allocator) {
    if !allocator.data return;

    data: *Gpu_Heap_Data = allocator.data;
    // Free by device base. It remains stable even when host mapping details
    // differ across SGPU allocation modes.
    if data.gpu_base != 0 {
        gpu_free(data.gpu_base);
    }
    push_allocator(data.owner_allocator);
    array_free(data.free_list);
    free(data);
    allocator.* = .{};
}

// Grows one contiguous VkBuffer. Allocation offsets stay stable; callers must
// refresh any root Gpu_Ptr derived from this heap after a successful resize.
gpu_heap_reserve :: (allocator: Allocator, required_capacity: s64) -> bool {
    data: *Gpu_Heap_Data = allocator.data;
    if !data || required_capacity <= data.capacity return true;
    if required_capacity <= 0 || required_capacity > S64_MAX / 8 return false;

    target := data.capacity;
    while target < required_capacity {
        if target > S64_MAX / 8 return false;

        grown := cast(s64) (cast(float64) target * GPU_HEAP_GROWTH_FACTOR);
        if grown <= target then grown = target + 1;
        target = max(grown, required_capacity);
    }

    old_capacity := data.capacity;
    if !heap_reallocate_storage(data, target) return false;
    heap_free_raw(data, old_capacity, target - old_capacity);
    return true;
}

// Explicit trim only. Never call this per frame. It preserves offsets and
// declines to shrink when live allocations would exceed the target buffer.
gpu_heap_trim :: (allocator: Allocator, required_capacity: s64 = 0) -> bool {
    data: *Gpu_Heap_Data = allocator.data;
    if !data || data.capacity <= data.minimum_capacity return false;

    required_capacity = max(required_capacity, heap_high_water_mark(data));
    target := max(data.minimum_capacity, required_capacity);
    target = max(target, data.capacity / 2);
    target = align_forward(target, data.alignment);

    if target >= data.capacity return false;

    old_capacity := data.capacity;
    if !heap_reallocate_storage(data, target) return false;
    heap_trim_free_tail(data, old_capacity, target);
    return true;
}

to_gpu_ptr :: (alloc: Allocator, cpu_ptr: *void) -> Gpu_Ptr {
    heap: *Gpu_Heap_Data = cast(*Gpu_Heap_Data) alloc.data;
    assert(heap != null && cpu_ptr != null, "to_gpu_ptr requires a live heap allocation");

    offset := cast(s64) cpu_ptr - cast(s64) heap.cpu_base;
    assert(offset >= 0 && offset < heap.capacity, "to_gpu_ptr pointer is outside heap");
    return heap.gpu_base + offset.(Gpu_Ptr);
}

gpu_heap_head :: (allocator: Allocator) -> (*void, Gpu_Ptr) {
    data: *Gpu_Heap_Data = allocator.data;
    assert(data != null, "gpu_heap_head requires a live heap");
    return data.cpu_base, data.gpu_base;
}

to_element_offset :: (alloc: Allocator, cpu_ptr: *void, element_size: s64) -> s64 {
    heap: *Gpu_Heap_Data = cast(*Gpu_Heap_Data) alloc.data;
    assert(heap != null && cpu_ptr != null, "to_element_offset requires a live heap allocation");
    assert(element_size > 0, "to_element_offset requires a positive element size");

    offset := cast(s64) cpu_ptr - cast(s64) heap.cpu_base;
    assert(offset >= 0 && offset < heap.capacity, "to_element_offset pointer is outside heap");
    assert(offset % element_size == 0, "to_element_offset pointer is not element aligned");
    return offset / element_size;
}

#scope_file

Gpu_Heap_Data :: struct {
    owner_allocator:  Allocator;
    cpu_base:         *void;
    gpu_base:         Gpu_Ptr;
    capacity:         s64;
    minimum_capacity: s64;
    alignment:        s64;
    free_list:        [..] Heap_Block;
}

Heap_Block :: struct {
    offset: s64;
    size:   s64;
}

GPU_HEAP_MAGIC :: cast(u16) 0x4750; // "GP"
GPU_HEAP_HEADER_SIZE :: size_of(Gpu_Heap_Header);

Gpu_Heap_Header :: struct {
    magic:        u16;
    padding_size: u16;
    size:         u32;
}

align_forward :: (value: s64, alignment: s64) -> s64 {
    if alignment <= 1 return value;
    return ((value + alignment - 1) / alignment) * alignment;
}

heap_reallocate_storage :: (data: *Gpu_Heap_Data, new_capacity: s64) -> bool {
    if new_capacity <= 0 || new_capacity == data.capacity return new_capacity == data.capacity;
    if new_capacity < heap_high_water_mark(data) return false;

    // SGPU does not expose buffer resize. Synchronize before replacing the
    // single backing VkBuffer, then preserve every allocation offset.
    gpu_wait_idle();

    new_cpu, new_gpu := gpu_malloc(new_capacity);
    if !new_cpu || new_gpu == 0 return false;

    copy_size := min(data.capacity, new_capacity);
    memcpy(new_cpu, data.cpu_base, copy_size);

    old_cpu := data.cpu_base;
    data.cpu_base = new_cpu;
    data.gpu_base = new_gpu;
    data.capacity = new_capacity;

    gpu_free(old_cpu);
    return true;
}

heap_high_water_mark :: (data: *Gpu_Heap_Data) -> s64 {
    for block: data.free_list {
        if block.offset + block.size == data.capacity return block.offset;
    }
    return data.capacity;
}

heap_trim_free_tail :: (data: *Gpu_Heap_Data, old_capacity: s64, new_capacity: s64) {
    for *block, index: data.free_list {
        if block.offset + block.size != old_capacity continue;

        assert(block.offset <= new_capacity, "Gpu_Heap trim would discard a live allocation");
        block.size = new_capacity - block.offset;
        if block.size == 0 array_ordered_remove_by_index(*data.free_list, index);
        return;
    }
}

heap_allocate_aligned :: (data: *Gpu_Heap_Data, payload_size: s64) -> *void {
    best_block: *Heap_Block = null;
    best_delta: s64 = S64_MAX;
    best_index: s64 = -1;
    best_padding: s64 = 0;
    best_raw_size: s64 = 0;

    for *candidate, index: data.free_list {
        payload_offset := align_forward(candidate.offset + GPU_HEAP_HEADER_SIZE, data.alignment);
        padding := payload_offset - candidate.offset - GPU_HEAP_HEADER_SIZE;
        if padding > U16_MAX continue;

        raw_size := padding + GPU_HEAP_HEADER_SIZE + payload_size;
        if candidate.size < raw_size then continue;

        if candidate.size == raw_size {
            best_block = candidate;
            best_delta = 0;
            best_index = index;
            best_padding = padding;
            best_raw_size = raw_size;
            break;
        }

        delta := candidate.size - raw_size;
        if delta < best_delta {
            best_block = candidate;
            best_delta = delta;
            best_index = index;
            best_padding = padding;
            best_raw_size = raw_size;
        }
    }

    if !best_block return null;

    raw_offset := best_block.offset;
    payload_offset := raw_offset + best_padding + GPU_HEAP_HEADER_SIZE;
    header: *Gpu_Heap_Header = cast(*Gpu_Heap_Header) (data.cpu_base + payload_offset - GPU_HEAP_HEADER_SIZE);
    header.magic = GPU_HEAP_MAGIC;
    header.padding_size = cast(u16) best_padding;
    header.size = cast(u32) payload_size;

    if best_delta == 0 {
        array_ordered_remove_by_index(*data.free_list, best_index);
    } else {
        best_block.offset += best_raw_size;
        best_block.size = best_delta;
    }

    return data.cpu_base + payload_offset;
}

heap_free_raw :: (data: *Gpu_Heap_Data, offset: s64, size: s64) {
    new_block := Heap_Block.{offset, size};
    insert_index := data.free_list.count;

    for *block, index: data.free_list {
        block_end := block.offset + block.size;
        new_end := new_block.offset + new_block.size;

        if block_end == new_block.offset {
            block.size += new_block.size;
            if index + 1 < data.free_list.count {
                next := *data.free_list[index + 1];
                if block.offset + block.size == next.offset {
                    block.size += next.size;
                    array_ordered_remove_by_index(*data.free_list, index + 1);
                }
            }
            return;
        }

        if new_end == block.offset {
            block.offset = new_block.offset;
            block.size += new_block.size;
            return;
        }

        if new_block.offset < block.offset {
            insert_index = index;
            break;
        }
    }

    array_insert_at(*data.free_list, new_block, insert_index);
}

heap_get_header :: (data: *Gpu_Heap_Data, memory: *void) -> *Gpu_Heap_Header {
    if !memory return null;

    memory_offset := cast(s64) memory - cast(s64) data.cpu_base;
    if memory_offset < GPU_HEAP_HEADER_SIZE || memory_offset >= data.capacity return null;

    header_offset := memory_offset - GPU_HEAP_HEADER_SIZE;
    header: *Gpu_Heap_Header = cast(*Gpu_Heap_Header) (data.cpu_base + header_offset);
    if header.magic != GPU_HEAP_MAGIC return null;

    raw_offset := header_offset - cast(s64) header.padding_size;
    if raw_offset < 0 return null;

    raw_size := cast(s64) header.padding_size + GPU_HEAP_HEADER_SIZE + cast(s64) header.size;
    if raw_offset + raw_size > data.capacity return null;

    return header;
}

heap_proc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
    data: *Gpu_Heap_Data = allocator_data;

    if mode == {
        case .ALLOCATE; {
            if size <= 0 || size > U32_MAX return null;

            memory := heap_allocate_aligned(data, size);
            if memory return memory;

            // Emergency growth keeps this heap one contiguous VkBuffer.
            required := size + GPU_HEAP_HEADER_SIZE + data.alignment;
            if !gpu_heap_reserve(.{proc = heap_proc, data = data}, data.capacity + required) return null;
            return heap_allocate_aligned(data, size);
        }

        case .RESIZE; {
            if !old_memory return heap_proc(.ALLOCATE, size, 0, null, allocator_data);
            if size <= 0 {
                heap_proc(.FREE, 0, 0, old_memory, allocator_data);
                return null;
            }
            if size > U32_MAX return null;

            header := heap_get_header(data, old_memory);
            if !header return null;

            old_size = cast(s64) header.size;
            if size == old_size return old_memory;

            payload_offset := cast(s64) old_memory - cast(s64) data.cpu_base;
            old_end := payload_offset + old_size;

            if size < old_size {
                heap_free_raw(data, payload_offset + size, old_size - size);
                header.size = cast(u32) size;
                return old_memory;
            }

            needed := size - old_size;
            for *block, index: data.free_list {
                if block.offset > old_end break;
                if block.offset == old_end {
                    if block.size >= needed {
                        if block.size == needed array_ordered_remove_by_index(*data.free_list, index);
                        else {
                            block.offset += needed;
                            block.size -= needed;
                        }
                        header.size = cast(u32) size;
                        return old_memory;
                    }
                    break;
                }
            }

            // The allocator contract permits a moved CPU pointer. Durable GPU
            // references must use offsets/handles, never this transient pointer.
            new_memory := heap_proc(.ALLOCATE, size, 0, null, allocator_data);
            if !new_memory return null;
            memcpy(new_memory, old_memory, old_size);
            heap_proc(.FREE, 0, 0, old_memory, allocator_data);
            return new_memory;
        }

        case .FREE; {
            header := heap_get_header(data, old_memory);
            if !header return null;

            offset := (cast(s64) old_memory - cast(s64) data.cpu_base) - GPU_HEAP_HEADER_SIZE - cast(s64) header.padding_size;
            block_size := cast(s64) header.padding_size + GPU_HEAP_HEADER_SIZE + cast(s64) header.size;
            header.magic = 0;
            heap_free_raw(data, offset, block_size);
            return null;
        }
    }

    return null;
}
