#import "tbx/temporal_binary_switch";
#import "tbx/collision";
#import "tbx/engine";
#import "Input";

CPMA_Movement_Parameters :: struct {

    gravity: float = 35.0; // 800 ups/s^2 -> 25 m/s^2

    // ground
    friction: float = 6.0;
    stopspeed: float = 3.125;        // 100 ups -> 3.125 m/s
    run_acceleration: float = 15.0;
    max_run_speed: float = 10.0;     // 320 ups -> 10 m/s

    // air normal movement
    air_acceleration: float = 1.0;
    max_air_speed: float = 10.0;     // 320 ups -> 10 m/s

    // air pure strafe: a/d only, no w/s
    side_strafe_acceleration: float = 70.0;
    side_strafe_max_speed: float = 0.9375; // 30 ups -> 0.9375 m/s

    // air control: w/s only, no a/d
    use_air_control: bool = true;
    aircontrol_amount: float = 150.0;
    aircontrol_power: float = 2.0;
    aircontrol_base: float = 32.0;
    forward_wish_accel: float = 0.0;

    jump_velocity: float = 8.4375;        // 270 ups -> 8.4375 m/s
    double_jump_velocity: float = 3.125;  // 100 ups -> 3.125 m/s
    double_jump_window_ms: float = 400.0;

    input_axis_max: float = 1.0;
    jump_input_value: float = 1.0;

    // Defrag CPM default is false.
    // If true, holding jump does not affect command scaling.
    cmd_scale_ignore_upmove: bool = false;
}

CPMA_Movement_State :: struct {
    jump_tbs: Temporal_Binary_Switch;
    pressed_and_held_jump_since_last_jump: bool = false;

    time_since_last_jump_ms: float = 999999.0;
}


get_horizontal_component :: (v: Vector3) -> Vector3 {
    return .{v.x, 0, v.z};
}

get_horizontal_speed :: (v: Vector3) -> float {
    return length(get_horizontal_component(v));
}

get_horizontal_direction_normalized :: (dir: Vector3) -> Vector3 {
    h := get_horizontal_component(dir);
    l := length(h);
    if l < 0.0001 return .{0, 0, 1};
    return h / l;
}

calculate_input_speed_scale :: (
    forward_input: float,
    right_input: float,
    up_input: float,
    max_speed: float,
    input_axis_max: float,
    ignore_upmove: bool
) -> float {
    f := abs(forward_input);
    s := abs(right_input);
    u := abs(up_input);

    max_axis := f;
    if s > max_axis max_axis = s;
    if !ignore_upmove && u > max_axis max_axis = u;

    if max_axis < 0.0001 return 0;

    total: float;
    if ignore_upmove {
        total = sqrt(f * f + s * s);
    } else {
        total = sqrt(f * f + s * s + u * u);
    }

    if total < 0.0001 return 0;

    return max_speed * max_axis / (input_axis_max * total);
}

accelerate_velocity_toward_wish_direction :: (
    velocity: *Vector3,
    wishdir: Vector3,
    wishspeed: float,
    accel: float,
    basespeed: float,
    dt: float
) {
    wishspeed_c := wishspeed;
    if wishspeed_c > basespeed wishspeed_c = basespeed;

    currentspeed := dot(velocity.*, wishdir);
    addspeed := wishspeed_c - currentspeed;
    if addspeed <= 0 return;

    accelspeed := accel * wishspeed_c * dt;
    if accelspeed > addspeed accelspeed = addspeed;

    velocity.x += accelspeed * wishdir.x;
    velocity.y += accelspeed * wishdir.y;
    velocity.z += accelspeed * wishdir.z;
}

adjust_velocity_direction_for_air_control :: (
    velocity: *Vector3,
    wishdir_flat: Vector3,
    wishspeed_for_scale: float,
    dt: float,
    p: CPMA_Movement_Parameters
) {
    if !p.use_air_control return;

    y_vel := velocity.y;
    h := get_horizontal_component(velocity.*);
    speed := length(h);

    if speed < 0.0001 {
        velocity.y = y_vel;
        return;
    }

    vel_horiz_norm := h / speed;
    dot_val := dot(vel_horiz_norm, wishdir_flat);

    if dot_val <= 0 {
        velocity.y = y_vel;
        return;
    }

    k := p.aircontrol_base * p.aircontrol_amount * pow(dot_val, p.aircontrol_power) * dt;

    blended := vel_horiz_norm * speed + wishdir_flat * k;
    new_len := length(blended);

    if new_len < 0.0001 {
        velocity.y = y_vel;
        return;
    }

    new_dir := blended / new_len;

    velocity.x = new_dir.x * speed;
    velocity.z = new_dir.z * speed;
    velocity.y = y_vel;

    if p.forward_wish_accel != 0 {
        velocity.x += wishdir_flat.x * p.forward_wish_accel * dt;
        velocity.z += wishdir_flat.z * p.forward_wish_accel * dt;
    }
}

apply_ground_friction_to_velocity :: ( velocity: *Vector3, dt: float, p: CPMA_Movement_Parameters) {
    h := get_horizontal_component(velocity.*);
    speed := length(h);

    if speed < 1.0e-4 {
        velocity.x = 0;
        velocity.z = 0;
        return;
    }

    control: float;
    if speed < p.stopspeed {
        control = p.stopspeed;
    } else {
        control = speed;
    }

    drop := control * p.friction * dt;
    newspeed := speed - drop;
    if newspeed < 0 newspeed = 0;

    scale := newspeed / speed;

    velocity.x *= scale;
    velocity.z *= scale;
}

transform_input_direction_to_world_space :: ( camera_forward: Vector3, local_input_direction: Vector3) -> Vector3 {
    camera_forward_horizontal := camera_forward;
    camera_forward_horizontal.y = 0;
    camera_forward_horizontal = unit_vector(camera_forward_horizontal);

    camera_right_horizontal := Vector3.{-camera_forward_horizontal.z, 0, camera_forward_horizontal.x};

    world_direction := camera_right_horizontal * local_input_direction.x
                     + camera_forward_horizontal * local_input_direction.z;

    world_direction.y = local_input_direction.y;

    return world_direction;
}

calculate_flat_wish_move :: (movement_input: First_Person_Movement_Input, forward_direction: Vector3) -> (
    wishdir: Vector3,
    wishspeed: float,
    forward_input: float,
    right_input: float,
    valid: bool
) {
    forward_input, right_input := get_forward_and_side_input(movement_input);

    f_fwd := forward_direction;
    f_fwd.y = 0;

    if length(f_fwd) < 0.0001 {
        return .{0, 0, 0}, 0, forward_input, right_input, false;
    }

    f_fwd = unit_vector(f_fwd);
    f_right := Vector3.{-f_fwd.z, 0, f_fwd.x};

    wishvel := f_right * right_input + f_fwd * forward_input;
    wishvel.y = 0;

    wishspeed := length(wishvel);

    if wishspeed < 0.0001 {
        return .{0, 0, 0}, 0, forward_input, right_input, false;
    }

    wishdir := wishvel / wishspeed;

    return wishdir, wishspeed, forward_input, right_input, true;
}

update_velocity_while_on_ground :: (
    velocity: *Vector3,
    movement_input: First_Person_Movement_Input,
    movement_state: *CPMA_Movement_State,
    forward_direction: Vector3,
    dt: float,
    p: CPMA_Movement_Parameters = .{}
) -> bool {
    if movement_state.pressed_and_held_jump_since_last_jump {
        if velocity.y > 0 {
            velocity.y += p.jump_velocity;
        } else {
            velocity.y = p.jump_velocity;
        }

        if movement_state.time_since_last_jump_ms > 0 &&
           movement_state.time_since_last_jump_ms <= p.double_jump_window_ms {
            velocity.y += p.double_jump_velocity;
        }

        movement_state.time_since_last_jump_ms = 0;
        movement_state.pressed_and_held_jump_since_last_jump = false;

        return true;
    }

    apply_ground_friction_to_velocity(velocity, dt, p);

    wishdir, wishspeed, forward_input, right_input, valid :=
        calculate_flat_wish_move(movement_input, forward_direction);

    if !valid return false;

    up_input: float = 0;
    if movement_input.jump_pressed {
        up_input = p.jump_input_value;
    }

    scale := calculate_input_speed_scale(
        forward_input,
        right_input,
        up_input,
        p.max_run_speed,
        p.input_axis_max,
        p.cmd_scale_ignore_upmove
    );

    real_wish_spd := wishspeed * scale;

    accelerate_velocity_toward_wish_direction(
        velocity,
        wishdir,
        real_wish_spd,
        p.run_acceleration,
        p.max_run_speed,
        dt
    );

    return false;
}

update_velocity_while_in_air :: (
    velocity: *Vector3,
    movement_input: First_Person_Movement_Input,
    forward_direction: Vector3,
    dt: float,
    p: CPMA_Movement_Parameters = .{}
) {
    wishdir, wishspeed, forward_input, right_input, valid :=
        calculate_flat_wish_move(movement_input, forward_direction);

    if valid {
        up_input: float = 0;
        if movement_input.jump_pressed {
            up_input = p.jump_input_value;
        }

        scale := calculate_input_speed_scale(
            forward_input,
            right_input,
            up_input,
            p.max_run_speed,
            p.input_axis_max,
            p.cmd_scale_ignore_upmove
        );

        real_wish_spd := wishspeed * scale;

        do_side := abs(right_input) > 0.1;
        do_forward := abs(forward_input) > 0.1;
        do_aircontrol := p.use_air_control && do_forward && !do_side;

        accel: float;
        basespeed: float;

        if do_side && !do_forward {
            accel = p.side_strafe_acceleration;
            basespeed = p.side_strafe_max_speed;
        } else {
            accel = p.air_acceleration;
            basespeed = p.max_air_speed;
        }

        accelerate_velocity_toward_wish_direction(
            velocity,
            wishdir,
            real_wish_spd,
            accel,
            basespeed,
            dt
        );

        if do_aircontrol {
            adjust_velocity_direction_for_air_control(
                velocity,
                wishdir,
                real_wish_spd,
                dt,
                p
            );
        }
    }

}

update :: (
    movement_state: *CPMA_Movement_State,
    movement_input: First_Person_Movement_Input,
    position: *Vector3,
    velocity: *Vector3,
    on_ground: *bool,
    forward: Vector3,
    collision_map: *Collision_Geometries,
    dt: float,
    movement_params: CPMA_Movement_Parameters = .{}
) -> bool {
    movement_state.time_since_last_jump_ms += dt * 1000.0;

    set(*movement_state.jump_tbs, movement_input.jump_pressed);
    process(*movement_state.jump_tbs);

    if just_switched_on(movement_state.jump_tbs) {
        movement_state.pressed_and_held_jump_since_last_jump = true;
    }

    if !movement_input.jump_pressed {
        movement_state.pressed_and_held_jump_since_last_jump = false;
    }

    jump_occurred: bool = false;

    if on_ground.* {
        jump_occurred = update_velocity_while_on_ground(
            velocity,
            movement_input,
            movement_state,
            forward,
            dt,
            movement_params
        );
    } else {
        update_velocity_while_in_air(
            velocity,
            movement_input,
            forward,
            dt,
            movement_params
        );
    }

    displacement := velocity.* * dt;
    gravity_displacement := Vector3.{0, -movement_params.gravity * dt * dt, 0};

    ellipsoid_radius := Vector3.{0.4, 1.75 / 2.0, 0.4};

    resolve_collisions_against_body_ellipsoid(
        collision_map.*,
        ellipsoid_radius,
        position,
        *displacement,
        on_ground,
        gravity_displacement
    );

    if dt > 0.000001 {
        velocity.* = displacement / dt;
    }

    return jump_occurred;
}
