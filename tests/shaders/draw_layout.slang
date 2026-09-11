struct Vertex_Output {
    float4 position;
};

struct Draw_Indexed_Command {
    uint index_count;
    uint instance_count;
    uint first_index;
    int vertex_offset;
    uint first_instance;
}

float4 main(Vertex_Output input, Draw_Indexed_Command command) {
    return input.position + float4(command.vertex_offset, 0.0, 0.0, 0.0);
}
