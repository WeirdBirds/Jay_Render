struct Vertex_Output {
    float4 position;
};

struct MirrorChild {
    float2 uv;
    float weight;
    uint mode;
};

struct MirrorParams {
    float4 base_color;
    float2 uv_shift;
    float4x4 transform;
    MirrorChild child;
    MirrorChild children[2];
    bool enabled;
    float values[3];
    float3x4 basis;
};

float4 main(Vertex_Output input, MirrorParams params, MirrorParams second_params) {
    return params.base_color + second_params.base_color;
}
