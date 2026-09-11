struct Vertex_Output { float4 position; };
struct ResourceParams { Texture2D<float4> texture; };
float4 main(Vertex_Output input, ResourceParams params, ResourceParams second_params) {
    return input.position;
}
