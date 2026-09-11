struct Vertex_Output { float4 position; };
struct EmptyMirror {};
float4 main(Vertex_Output input, EmptyMirror params, EmptyMirror second_params) {
    return input.position;
}
