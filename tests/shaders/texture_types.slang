struct Vertex_Output {
    float4 position;
};

struct CoatedParams {
    float4 base_color;
    float roughness;
};

float4 main(Vertex_Output input, CoatedParams params, Texture2D<float4> albedo, SamplerState sampler) {
    return params.base_color;
}
