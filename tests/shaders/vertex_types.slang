struct Vertex_Output {
    float4 position;
    float3 normal;
    float4 color;
    float2 uv;
    uint instance_id;
};

Vertex_Output main(uint vertex_id, uint instance_id) {
    Vertex_Output output;
    output.position = float4(0.0, 0.0, 0.0, 1.0);
    output.normal = float3(0.0, 0.0, 1.0);
    output.color = float4(1.0, 1.0, 1.0, 1.0);
    output.uv = float2(0.0, 0.0);
    output.instance_id = instance_id;
    return output;
}
