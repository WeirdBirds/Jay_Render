#scope_module

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

camera_capture :: (camera: Camera, transform: Mat4, delta_time: float64) {
    assert(camera.target != null, "Jay_Render: camera target is required");
    assert(camera.aspect_ratio > 0, "Jay_Render: camera aspect ratio must be positive");
    assert(camera.near > 0 && camera.far > camera.near, "Jay_Render: camera clip range is invalid");
    if camera.projection == .PERSPECTIVE {
        assert(camera.fov > 0 && camera.fov < PI, "Jay_Render: camera field of view is invalid");
    } else {
        assert(camera.ortho_size > 0, "Jay_Render: camera orthographic size must be positive");
    }

    v := make_view(transform);
    p := make_projection(camera);

    view_projection := p * v;

    frustum_planes := get_frustum_planes(view_projection);
    render_frame(*render.data, render.queues.main, render.queues.compute, camera.target.image, camera.target.depth,
        view_projection, v, frustum_planes, transform, camera.near, camera.far, delta_time);
}

#scope_file

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
        result._33 = 1.0 / (far - near);
        result._34 = far / (far - near);
        result._44 = 1;

        return result;
    }
}


make_view :: (transform: Mat4) -> Mat4 {
    result: Mat4 = .{};

    // Pose stores basis in columns. View matrix stores inverse basis in rows.
    result._11 = transform._12;  result._12 = transform._22;  result._13 = transform._32; // right
    result._21 = transform._13;  result._22 = transform._23;  result._23 = transform._33; // up
    result._31 = -transform._11; result._32 = -transform._21; result._33 = -transform._31; // -forward

    pos_x := transform._14;  pos_y := transform._24;  pos_z := transform._34;

    result._14 = -(result._11*pos_x + result._12*pos_y + result._13*pos_z);
    result._24 = -(result._21*pos_x + result._22*pos_y + result._23*pos_z);
    result._34 = -(result._31*pos_x + result._32*pos_y + result._33*pos_z);
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
            p.x /= len;  p.y /= len;  p.z /= len;  p.w /= len;
        }
    }

    return planes;
}
