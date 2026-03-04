// Camera definition and projection utilities.

Camera :: struct {
    transform:   Transform;
    fov_radians: float32;
    near_plane:  float32;
    far_plane:   float32;
}

// Builds a perspective projection matrix (right-handed, depth [0..1], Y-up).
// `aspect` is width / height.
get_projection_matrix :: (cam: Camera, aspect: float32) -> Mat4 {
    return make_perspective(cam.fov_radians, aspect, cam.near_plane, cam.far_plane);
}

// Extracts a view matrix from the camera's transform.
// Translation is the eye position; rotation encodes the orientation.
// Camera looks along -Z in its local space (right-handed convention).
get_view_matrix :: (cam: Camera) -> Mat4 {
    rot := to_matrix(cam.transform.rotation);  // Quat -> Mat3

    right      := Vec3.{ rot.cells[0][0], rot.cells[0][1], rot.cells[0][2] };
    up         := Vec3.{ rot.cells[1][0], rot.cells[1][1], rot.cells[1][2] };
    forward    := Vec3.{ rot.cells[2][0], rot.cells[2][1], rot.cells[2][2] };

    eye := cam.transform.translation;

    mat := Mat4.identity();
    mat.cells[0][0] =  right.x;
    mat.cells[0][1] =  right.y;
    mat.cells[0][2] =  right.z;

    mat.cells[1][0] =  up.x;
    mat.cells[1][1] =  up.y;
    mat.cells[1][2] =  up.z;

    mat.cells[2][0] =  forward.x;
    mat.cells[2][1] =  forward.y;
    mat.cells[2][2] =  forward.z;

    mat.cells[0][3] = -dot(right,   eye);
    mat.cells[1][3] = -dot(up,      eye);
    mat.cells[2][3] = -dot(forward, eye);

    return mat;
}

// Builds a right-handed perspective projection matrix.
// Depth maps to [0..1] (Vulkan convention), Y is flipped.
make_perspective :: (fov_radians: float32, aspect: float32, near_plane: float32, far_plane: float32) -> Mat4 {
    f := 1.0 / tan(fov_radians * 0.5);
    mat := Mat4.identity();
    mat.cells[0][0] = f / aspect;
    mat.cells[1][1] = f;
    mat.cells[2][2] = far_plane / (near_plane - far_plane);
    mat.cells[2][3] = (far_plane * near_plane) / (near_plane - far_plane);
    mat.cells[3][2] = -1.0;
    mat.cells[3][3] = 0.0;
    return mat;
}

// Builds a view matrix looking from `eye` toward `target` with the given `up` hint.
make_look_at :: (eye: Vec3, target: Vec3, up: Vec3) -> Mat4 {
    fwd := target - eye;
    normalize(*fwd);
    right := cross(fwd, up);
    normalize(*right);
    actual_up := cross(right, fwd);

    mat := Mat4.identity();
    mat.cells[0][0] =  right.x;
    mat.cells[0][1] =  right.y;
    mat.cells[0][2] =  right.z;

    mat.cells[1][0] =  actual_up.x;
    mat.cells[1][1] =  actual_up.y;
    mat.cells[1][2] =  actual_up.z;

    mat.cells[2][0] = -fwd.x;
    mat.cells[2][1] = -fwd.y;
    mat.cells[2][2] = -fwd.z;

    mat.cells[0][3] = -dot(right,     eye);
    mat.cells[1][3] = -dot(actual_up, eye);
    mat.cells[2][3] =  dot(fwd,       eye);

    return mat;
}
