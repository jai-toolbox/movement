God_Mode_Input :: struct {
    fast_move_pressed : bool;
    slow_move_pressed : bool;
    forward_pressed : bool;
    backward_pressed : bool;
    right_pressed : bool;
    left_pressed : bool;
    up_pressed : bool;
    down_pressed : bool;
}

get_normalized_input_direction_xyz :: (forward: Vector3, using gmi: God_Mode_Input) -> Vector3 {
    up := Y3;
    right := normalized_cross(forward, up);

    movement_direction : Vector3;

    if forward_pressed
        movement_direction += forward;
    if backward_pressed
        movement_direction -= forward;
    if left_pressed
        movement_direction -= right;
    if right_pressed
        movement_direction += right;
    if up_pressed
        movement_direction += up;
    if down_pressed
        movement_direction -= up;

    if length(movement_direction) > 0.0
        movement_direction = normalize(movement_direction);

    return movement_direction;
}

get_new_god_mode_velocity :: (
    velocity: Vector3,
    forward: Vector3,
    god_mode_input: God_Mode_Input,
    delta_time: float,
    acceleration: float = 20.0,
    friction: float = 5.0,
    max_speed: float = 10.0
) -> Vector3 {
    current_velocity := velocity;

    accel_dir := get_normalized_input_direction_xyz(forward, god_mode_input);

    // apply acceleration
    current_velocity += accel_dir * acceleration * delta_time;

    // apply friction if no input
    if length(accel_dir) < 0.001
        current_velocity -= current_velocity * min(friction * delta_time, 1.0);

    speed_multiplier := 1.0;
    if god_mode_input.slow_move_pressed
        speed_multiplier = 0.25;
    if god_mode_input.fast_move_pressed
        speed_multiplier = 4.0;
    effective_max_speed := max_speed * speed_multiplier;

    // clamp velocity to max speed
    if length(current_velocity) > effective_max_speed
        current_velocity = normalize(current_velocity) * effective_max_speed;

    return current_velocity;
}
