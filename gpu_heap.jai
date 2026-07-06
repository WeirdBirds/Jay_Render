Gpu_Heap :: (capacity: s64, alignment: s64 = 8, memory_type: Memory_Type = .DEFAULT) -> Allocator {
    heap: *Gpu_Heap_Data = New(Gpu_Heap_Data);
    heap.cpu_base, heap.gpu_base = gpu_malloc(capacity, memory_type);
    heap.capacity = capacity;
    heap.alignment = max(alignment, 1);
    array_add(*heap.free_list, .{0, capacity});

    return Allocator.{proc = heap_proc, data = heap};
};

to_gpu_ptr :: (alloc: Allocator, cpu_ptr: *void) -> Gpu_Ptr {
    heap: *Gpu_Heap_Data = cast(*Gpu_Heap_Data) alloc.data;
    offset := cast(s64) cpu_ptr - cast(s64) heap.cpu_base;                                                                                                          
    return heap.gpu_base + offset;                                                                                                                                  
}

gpu_heap_head :: (allocator: Allocator) -> (*void, Gpu_Ptr) {
    data: *Gpu_Heap_Data = allocator.data;
    return data.cpu_base, data.gpu_base;
}

to_index_offset :: (alloc: Allocator, cpu_ptr: *void) -> s64 {
    heap: *Gpu_Heap_Data = cast(*Gpu_Heap_Data) alloc.data;
    offset := (cast(s64) cpu_ptr - cast(s64) heap.cpu_base) / heap.alignment;
    return offset;
}
#scope_file

Gpu_Heap_Data :: struct {
    cpu_base: *void;
    gpu_base: Gpu_Ptr;
    capacity: s64;
    alignment: s64;
    free_list: [..] Heap_Block;
}

Heap_Block :: struct {
    offset: s64;
    size: s64;
}

GPU_HEAP_MAGIC :: cast(u16) 0x4750; // "GP"
GPU_HEAP_HEADER_SIZE :: size_of(Gpu_Heap_Header);

Gpu_Heap_Header :: struct {
    magic: u16;
    padding_size: u16;
    size: u32;
}

align_forward :: (value: s64, alignment: s64) -> s64 {
    if alignment <= 1 return value;
    return ((value + alignment - 1) / alignment) * alignment;
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
        
        if (delta < best_delta) {
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
        best_block.size = best_delta;
        best_block.offset += best_raw_size;
    }

    return data.cpu_base + payload_offset;
}

heap_free_raw :: (data: *Gpu_Heap_Data, offset: s64, size: s64) {
    new_block := Heap_Block.{offset, size};
    insert_index := data.free_list.count;

    for *block, index: data.free_list {
        block_end := block.offset + block.size;
        new_end   := new_block.offset + new_block.size;

        if block_end == new_block.offset {
            block.size += new_block.size;
            insert_index = index;

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
            if size < 0 || size > U32_MAX return null;

            return heap_allocate_aligned(data, size);
        }

        case .RESIZE; {
            if !old_memory {
                return heap_proc(.ALLOCATE, size, 0, null, allocator_data);
            }

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
            old_offset := payload_offset - GPU_HEAP_HEADER_SIZE - cast(s64) header.padding_size;
            old_end := payload_offset + old_size;

            // Shrink in place. Free tail only.
            if size < old_size {
                tail_offset := payload_offset + size;
                heap_free_raw(data, tail_offset, old_size - size);
                header.size = cast(u32) size;
                return old_memory;
            }

            // Grow in place from next adjacent free block.
            needed := size - old_size;

            for *block, index: data.free_list {
                if block.offset > old_end break;

                if block.offset == old_end {
                    if block.size >= needed {
                        if block.size == needed {
                            array_ordered_remove_by_index(*data.free_list, index);
                        } else {
                            block.offset += needed;
                            block.size -= needed;
                        }

                        header.size = cast(u32) size;
                        return old_memory;
                    }

                    break;
                }
            }

            // Fallback: move.
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
};
