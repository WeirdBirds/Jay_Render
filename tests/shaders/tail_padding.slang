struct Vertex_Output { float4 position; };
struct TailChild { double large; float small; };
struct TailParams { TailChild child; float reused_tail; };
float4 main(Vertex_Output input, TailParams params, TailParams second_params) {
    return input.position;
}
