struct Vertex_Output { float4 position; };
struct ColumnParams { column_major float3x4 basis; };
float4 main(Vertex_Output input, ColumnParams params, ColumnParams second_params) {
    return input.position;
}
