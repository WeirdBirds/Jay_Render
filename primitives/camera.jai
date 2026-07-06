Projection_Type :: enum {
    PERSPECTIVE;
    ORTHOGRAPHIC;
}

Camera :: struct {
    projection: Projection_Type = .PERSPECTIVE;
    target: *Render_Target; 
    fov: float32 = PI_3;
    ortho_size: float32 = 4;
    
    near: float32 = 0.1; 
    far: float32 = 1000;

    aspect_ratio: float32 = 1920.0/1080.0;
}

camera_capture :: (camera: Camera, transform: Mat4) {
    
    v := make_view(transform);
    p := make_projection(camera);

    view_projection := p * v;

    frustum_planes := get_frustum_planes(view_projection); 
    render_frame(*render.data, render.queues.main, camera.target.image, camera.target.depth, view_projection, frustum_planes);
}

make_projection :: (using camera: Camera) -> Mat4 {
    if projection == .PERSPECTIVE {
        result: Mat4 = .{};

        f := 1.0 / tan(fov * 0.5);

        result._11 = f / aspect_ratio;
        result._22 = f; 
        result._33 = near / (far - near);
        result._34 = far * near / (far - near);
        result._43 = -1;
        return result;
    
    } else {

        result: Mat4 = .{};

        half_h := ortho_size * 0.5;
        half_w := half_h * aspect_ratio;

        result._11 = 1.0 / half_w;
        result._22 = 1.0 / half_h;
        result._33 = near / (far - near);
        result._34 = far * near / (far - near);
        result._44 = 1;

        return result;
    }
}


make_view :: (transform: Mat4) -> Mat4 {
    result: Mat4 = .{};

    // Row 0 = right    = transform row 1
    result._11 = transform._21;  result._12 = transform._22;  result._13 = transform._23;
    // Row 1 = up       = transform row 2
    result._21 = transform._31;  result._22 = transform._32;  result._23 = transform._33;
    // Row 2 = -forward = -transform row 0
    result._31 = -transform._11; result._32 = -transform._12; result._33 = -transform._13;

    pos_x := transform._14;  pos_y := transform._24;  pos_z := transform._34;

    result._14 = -(result._11*pos_x + result._12*pos_y + result._13*pos_z);
    result._24 = -(result._21*pos_x + result._22*pos_y + result._23*pos_z);
    result._34 = -(result._31*pos_x + result._32*pos_y + result._33*pos_z);
    result._44 = 1;

    return result;
}

make_view_to :: (from: Vec3, target: Vec3, up: Vec3 = UP) -> Mat4 {
    fwd := normalize(target - from);
    right := normalize(cross(up, fwd));
    cam_up := cross(fwd, right); 

    result: Mat4 = .{};

    result._11 = right.x;   result._12 = right.y;   result._13 = right.z;
    result._21 = cam_up.x;  result._22 = cam_up.y;  result._23 = cam_up.z;
    result._31 = -fwd.x;    result._32 = -fwd.y;    result._33 = -fwd.z;

    result._14 = -dot(right, from);
    result._24 = -dot(cam_up, from);
    result._34 =  dot(fwd,   from);
    result._44 = 1;

    return result;
}


get_frustum_planes :: (vp: Mat4) -> [6] Vec4 {
    row0: Vec4 = .{vp._11, vp._12, vp._13, vp._14};
    row1: Vec4 = .{vp._21, vp._22, vp._23, vp._24};
    row2: Vec4 = .{vp._31, vp._32, vp._33, vp._34};
    row3: Vec4 = .{vp._41, vp._42, vp._43, vp._44};

    planes: [6] Vec4;

    planes[0] = row3 + row0;   // left
    planes[1] = row3 - row0;   // right
    planes[2] = row3 + row1;   // bottom
    planes[3] = row3 - row1;   // top
    planes[4] = row2;          // near
    planes[5] = row3 - row2;   // far

    for *p: planes {
        len := sqrt(p.x*p.x + p.y*p.y + p.z*p.z);
        if len > 0.000001 {
            p.x /= len;  p.y /= len;  p.z /= len;
        }
    }

    return planes;
}
