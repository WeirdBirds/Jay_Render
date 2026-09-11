struct Vertex_Output {
    float4 position;
};

float3 main(Vertex_Output input, float4 params) {
    return params.rgb;
}
