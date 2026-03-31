Mesh :: struct {
    vertices: []Vertex;
    indices:  []u32;
}

Vertex :: struct {
    position:    Vec3;
    color:       Vec3;
    uv:          Vec2;
    plane_coord: float32;
}
