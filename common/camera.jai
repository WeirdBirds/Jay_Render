    // Camera definition and projection utilities.

Camera :: struct {
    transform:   Mat4;
    fov_radians: float32;
    near_plane:  float32;
    far_plane:   float32;
}

// Builds a perspective projection matrix (depth [0..1]).
// `aspect` is width / height.
get_projection_matrix :: (cam: Camera, aspect: float32) -> Mat4 {
    return make_perspective(cam.fov_radians, aspect, cam.near_plane, cam.far_plane);
}

// Extracts a view matrix from the camera pose using Jay_Math directions.
get_view_matrix :: (cam: Camera) -> Mat4 {
    eye     := get_translation(cam.transform);
    forward := get_forward(cam.transform);
    up      := get_up(cam.transform);
    return make_look_at(eye, eye + forward, up);
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

Move_Keys :: enum_flags u8 {
    FORWARD;
    BACK;
    LEFT;
    RIGHT;
}

Camera_Orbit :: struct {
    #as using base: Camera;
   
    // Orbit camera state
    orbit_yaw:      float32 = 0.0;
    orbit_pitch:    float32 = 0.0;
    orbit_distance: float32 = 0.001;

    orbit_target:   Vec3;
    orbit_dragging: bool;
    keys_held:      Move_Keys;
    move_speed:     float32 = 2000.0;
}

camera_orbit_zoom :: (camera: *Camera_Orbit, delta: float32) {
    camera.orbit_distance -= delta;
    camera.orbit_distance = clamp(camera.orbit_distance, 0, 100);
    update_camera_transform(camera); 
}

camera_orbit_move :: (camera: *Camera_Orbit, dx: float32, dy: float32) {
    camera.orbit_yaw   += dx * 0.005;
    camera.orbit_pitch -= dy * 0.005;
    camera.orbit_pitch = clamp(camera.orbit_pitch, -PI/2+EPSILON, PI/2-EPSILON);

    update_camera_transform(camera);
}

camera_orbit_wasd :: (camera: *Camera_Orbit, dt: float32) {
    
    move := Vec3.{};

    forward := get_forward(camera.transform);
    right := get_right(camera.transform);

    if camera.keys_held & .FORWARD  move += forward;
    if camera.keys_held & .BACK     move -= forward;
    if camera.keys_held & .RIGHT    move += right;
    if camera.keys_held & .LEFT     move -= right;

    len := length(move);
    if len > 0 {
        move *= camera.move_speed * dt / len;
        camera.orbit_target += move;
        update_camera_transform(camera);
    }
}

update_camera_transform :: (camera: *Camera_Orbit) {
    cp, sp := sincos(camera.orbit_pitch, true, true);
    cy, sy := sincos(camera.orbit_yaw, true, true);

    offset := Vec3.{
        cast(float32)(sp * cy) * camera.orbit_distance,
        cast(float32)(sp * sy) * camera.orbit_distance,
        cast(float32) cp       * camera.orbit_distance,
    };

    eye := camera.orbit_target + offset;
    camera.transform = Mat4.identity();
    set_translation(*camera.transform, eye);
    set_face(*camera.transform, camera.orbit_target, Vec3.{0.0, 0.0, 1.0});
}
