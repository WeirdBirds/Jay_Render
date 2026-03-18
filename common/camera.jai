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
    mat.cells[0][0] = right.x;
    mat.cells[0][1] = right.y;
    mat.cells[0][2] = right.z;

    mat.cells[1][0] = up.x;
    mat.cells[1][1] = up.y;
    mat.cells[1][2] = up.z;

    mat.cells[2][0] = forward.x;
    mat.cells[2][1] = forward.y;
    mat.cells[2][2] = forward.z;

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

make_look_at :: (eye: Vec3, target: Vec3, up: Vec3) -> Mat4 {
    fwd := normalize(target - eye);
    right := normalize(cross(fwd, up));
    actual_up := cross(right, fwd);

    mat := Mat4.identity();
    mat.cells[0][0] = right.x;
    mat.cells[0][1] = right.y;
    mat.cells[0][2] = right.z;

    mat.cells[1][0] = actual_up.x;
    mat.cells[1][1] = actual_up.y;
    mat.cells[1][2] = actual_up.z;

    mat.cells[2][0] = -fwd.x;
    mat.cells[2][1] = -fwd.y;
    mat.cells[2][2] = -fwd.z;

    mat.cells[0][3] = -dot(right,     eye);
    mat.cells[1][3] = -dot(actual_up, eye);
    mat.cells[2][3] = dot(fwd,       eye);

    return mat;
}

Camera_Orbit :: struct {
    #as using base: Camera;
   
    // Orbit camera state
    orbit_yaw:      float32 = 0.0;
    orbit_pitch:    float32 = PI/2;
    orbit_distance: float32 = 100.0;

    orbit_target:   Vec3;
    orbit_dragging: bool;
    orbit_view:     Mat4;
}

camera_orbit_zoom :: (camera: *Camera_Orbit, delta: float32) {
    camera.orbit_distance -= delta;
    camera.orbit_distance = clamp(camera.orbit_distance, 0, 100);
    update_camera_transform(camera); 
}

camera_orbit_move :: (camera: *Camera_Orbit, dx: float32, dy: float32) {
    camera.orbit_yaw   += dx * 0.005;
    camera.orbit_pitch += dy * 0.005;
    camera.orbit_pitch = clamp(camera.orbit_pitch, 0.001, PI-0.001);

    update_camera_transform(camera);
}

update_camera_transform :: (camera: *Camera_Orbit) {
    cp, sp := sincos(camera.orbit_pitch, true, true);
    cy, sy := sincos(camera.orbit_yaw, true, true);

    offset := Vec3.{
        cast(float32)(cp * sy) * camera.orbit_distance,
        cast(float32) sp      * camera.orbit_distance,
        cast(float32)(cp * cy) * camera.orbit_distance,
    };

    eye := camera.orbit_target + offset;
    camera.orbit_view            = make_look_at(eye, camera.orbit_target, Vec3.{0.0, 1.0, 0.0});
    camera.transform.translation = eye;
}

