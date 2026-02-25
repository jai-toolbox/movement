CPMA_Movement_Parameters :: struct {
    gravity  : float = 20.0;
    friction : float = 6.0;

    // all speeds are measured in meters per second
    // acceleration is mps/s
    move_speed               : float = 7.0;
    run_acceleration         : float = 14.0;
    run_deacceleration       : float = 10.0;
    air_acceleration         : float = 0.7;
    air_decceleration        : float = 2.0;
    air_control              : float = 0.3;
    side_strafe_acceleration : float = 50.0;
    side_strafe_speed        : float = 1.0;
    jump_speed               : float = 8.0;

}

// velocity and pos here, because we assume they are controlled by other systems
CPMA_Movement_State :: struct {
    pressed_jump_since_last_jump : bool = false;
    // we only read this value. should we extract it?
    forward_input : float;
    right_input   : float;
}

set_movement_input :: (using cms: *CPMA_Movement_State) {
    forward_input = 0.0;
    right_input   = 0.0;

    if is_key_down(xx #char "W") forward_input += 1.0;
    if is_key_down(xx #char "S") forward_input -= 1.0;
    if is_key_down(xx #char "D") right_input   += 1.0;
    if is_key_down(xx #char "A") right_input   -= 1.0;
}


apply_velocity_in_input_direction_capped_to_scaled_speed :: (velocity: *Vector3, movement_state: *CPMA_Movement_State, input_direction: Vector3, speed_scaling_factor: float, accel: float, dt: float) {

    current_speed_in_input_direction := dot(velocity.*, input_direction);

    speed_needed_to_reach_scaled_speed_in_input_direction := speed_scaling_factor - current_speed_in_input_direction;

    if speed_needed_to_reach_scaled_speed_in_input_direction <= 0 return;

    velocity_gained_from_acceleration_this_frame := accel * dt * speed_scaling_factor;
    if velocity_gained_from_acceleration_this_frame > speed_needed_to_reach_scaled_speed_in_input_direction
        velocity_gained_from_acceleration_this_frame = speed_needed_to_reach_scaled_speed_in_input_direction;

    velocity.x += velocity_gained_from_acceleration_this_frame * input_direction.x;
    velocity.z += velocity_gained_from_acceleration_this_frame * input_direction.z;
}

adjust_velocity_direction_for_air_control :: (velocity: *Vector3, movement_state: *CPMA_Movement_State, wishdir: Vector3, wishspeed: float, dt: float, movement_params : CPMA_Movement_Parameters = .{}) {
    if abs(movement_state.forward_input) < 0.001 || abs(wishspeed) < 0.001
        return;

    original_vertical_speed := velocity.y;
    velocity.y = 0;

    current_horizontal_speed := length(velocity.*);
    velocity.* = unit_vector(velocity.*);

    velocity_alignment_with_wishdir := dot(velocity.*, wishdir);

    air_control_turning_strength : float = 32.0;
    air_control_turning_strength *= movement_params.air_control * velocity_alignment_with_wishdir * velocity_alignment_with_wishdir * dt;

    if velocity_alignment_with_wishdir > 0 {
        velocity.* = unit_vector(velocity.* * current_horizontal_speed + wishdir * air_control_turning_strength);
    }

    // this reads wrong, but it's not because velocity at this point is a unit vector (confusing and bad)
    velocity.x *= current_horizontal_speed;
    velocity.y = original_vertical_speed;
    velocity.z *= current_horizontal_speed;
}

update_velocity_while_in_air :: (velocity: *Vector3, movement_state: *CPMA_Movement_State, forward_direction: Vector3, dt: float, movement_params : CPMA_Movement_Parameters = .{}) {
    set_movement_input(movement_state);

    input_direction := Vector3.{movement_state.right_input, 0, movement_state.forward_input};
    input_direction = transform_input_direction_to_world_space(forward_direction, input_direction);

    desired_speed := length(input_direction) * movement_params.move_speed;

    input_direction = unit_vector(input_direction);

    desired_speed_for_air_control := desired_speed;

    acceleration : float;
    if dot(velocity.*, input_direction) < 0
        acceleration = movement_params.air_decceleration;
    else
        acceleration = movement_params.air_acceleration;

    is_side_strafing_only := movement_state.forward_input == 0 && movement_state.right_input != 0;
    is_moving_forward_only := movement_state.forward_input != 0 && movement_state.right_input == 0;

    if is_side_strafing_only {
        if desired_speed > movement_params.side_strafe_speed
            desired_speed = movement_params.side_strafe_speed;
        acceleration = movement_params.side_strafe_acceleration;
    }

    if is_moving_forward_only {
        horizontal_velocity := Vector3.{velocity.x, 0, velocity.z};
        current_horizontal_speed := length(horizontal_velocity);

        if current_horizontal_speed > 0.001 {
            horizontal_direction := unit_vector(horizontal_velocity);

            velocity_alignment_with_input := dot(horizontal_direction, input_direction);

            // holy dumb magic numbers, this needs some cleanup...
            forward_only_turn_rate := movement_params.air_control * 10.0;
            forward_only_turning_strength := 32.0 * forward_only_turn_rate * velocity_alignment_with_input * velocity_alignment_with_input * dt;

            if velocity_alignment_with_input > 0 {
                horizontal_direction = unit_vector(horizontal_direction * current_horizontal_speed + input_direction * forward_only_turning_strength);
            }

            velocity.x = horizontal_direction.x * current_horizontal_speed;
            velocity.z = horizontal_direction.z * current_horizontal_speed;
        }
    } else {
        // note that this doesn't take in movement params, it's not a typo
        apply_velocity_in_input_direction_capped_to_scaled_speed(velocity, movement_state, input_direction, desired_speed, acceleration, dt);
    }

    if movement_params.air_control > 0
        adjust_velocity_direction_for_air_control(velocity, movement_state, input_direction, desired_speed_for_air_control, dt, movement_params);

    velocity.y -= movement_params.gravity * dt;
}

// precond, on_ground is true
apply_ground_friction_to_velocity :: (velocity: *Vector3, movement_state: *CPMA_Movement_State, friction_scale: float, dt: float, movement_params : CPMA_Movement_Parameters = .{}) {
    horizontal_velocity := velocity.*;
    horizontal_velocity.y = 0.0;
    current_horizontal_speed := length(horizontal_velocity);
    speed_drop_from_friction : float = 0.0;

    control_speed := ifx current_horizontal_speed < movement_params.run_deacceleration then movement_params.run_deacceleration else current_horizontal_speed;
    speed_drop_from_friction = control_speed * movement_params.friction * dt * friction_scale;

    speed_after_friction := current_horizontal_speed - speed_drop_from_friction;
    if speed_after_friction < 0 speed_after_friction = 0;

    speed_retention_ratio := ifx current_horizontal_speed > 0 then speed_after_friction / current_horizontal_speed else 0.0;

    velocity.x *= speed_retention_ratio;
    velocity.z *= speed_retention_ratio;
}

update_velocity_while_on_ground :: (velocity: *Vector3, movement_state: *CPMA_Movement_State, forward_direction: Vector3, dt: float, movement_params : CPMA_Movement_Parameters = .{}) {
    if !movement_state.pressed_jump_since_last_jump
        apply_ground_friction_to_velocity(velocity, movement_state, 1.0, dt, movement_params);

    set_movement_input(movement_state);

    input_direction := Vector3.{movement_state.right_input, 0, movement_state.forward_input};
    input_direction = transform_input_direction_to_world_space(forward_direction, input_direction);
    input_direction = unit_vector(input_direction);

    desired_speed := length(input_direction) * movement_params.move_speed;

    is_moving_forward_only := movement_state.forward_input != 0 && movement_state.right_input == 0;

    if is_moving_forward_only {
        horizontal_velocity := Vector3.{velocity.x, 0, velocity.z};
        current_horizontal_speed := length(horizontal_velocity);

        if current_horizontal_speed > 0.001 {
            horizontal_direction := unit_vector(horizontal_velocity);

            velocity_alignment_with_input := dot(horizontal_direction, input_direction);
            ground_turn_rate := movement_params.air_control * 3.0;
            ground_turning_strength := 32.0 * ground_turn_rate * velocity_alignment_with_input * velocity_alignment_with_input * dt;

            if velocity_alignment_with_input > 0 {
                horizontal_direction = unit_vector(horizontal_direction * current_horizontal_speed + input_direction * ground_turning_strength);
            }

            if current_horizontal_speed < desired_speed {
                apply_velocity_in_input_direction_capped_to_scaled_speed(velocity, movement_state, input_direction, desired_speed, movement_params.run_acceleration, dt);
            } else {
                velocity.x = horizontal_direction.x * current_horizontal_speed;
                velocity.z = horizontal_direction.z * current_horizontal_speed;
            }
        } else {
            apply_velocity_in_input_direction_capped_to_scaled_speed(velocity, movement_state, input_direction, desired_speed, movement_params.run_acceleration, dt);
        }
    } else {
        apply_velocity_in_input_direction_capped_to_scaled_speed(velocity, movement_state, input_direction, desired_speed, movement_params.run_acceleration, dt);
    }

    velocity.y = -movement_params.gravity * dt;

    if movement_state.pressed_jump_since_last_jump {
        velocity.y = movement_params.jump_speed;
        movement_state.pressed_jump_since_last_jump = false;
    }
}

transform_input_direction_to_world_space :: (camera_forward: Vector3, local_input_direction: Vector3) -> Vector3 {
    camera_forward_horizontal := camera_forward;
    camera_forward_horizontal.y = 0;
    camera_forward_horizontal = unit_vector(camera_forward_horizontal);

    camera_right_horizontal := Vector3.{-camera_forward_horizontal.z, 0, camera_forward_horizontal.x};

    world_direction := camera_right_horizontal * local_input_direction.x + camera_forward_horizontal * local_input_direction.z;
    world_direction.y = local_input_direction.y;
    return world_direction;
}

#import "tbx/collision";
#import "tbx/engine";
#import "Input";


update :: (movement_state: *CPMA_Movement_State, position: *Vector3, velocity: *Vector3, on_ground: *bool, forward: Vector3, collision_map: *Collision_Geometries, dt: float, movement_params : CPMA_Movement_Parameters = .{}) {

    if is_key_just_pressed(xx #char " ") movement_state.pressed_jump_since_last_jump = true;
    if !is_key_down(xx #char " ") movement_state.pressed_jump_since_last_jump = false;

    if on_ground.*
        update_velocity_while_on_ground(velocity, movement_state, forward, dt, movement_params);
    else
        update_velocity_while_in_air(velocity, movement_state, forward, dt, movement_params);

    displacement := velocity.* * dt;

    ellipsoid_radius := Vector3.{0.4, 1.75 / 2.0, 0.4};
    resolve_collisions_against_body_ellipsoid(collision_map.*, ellipsoid_radius, position, *displacement, on_ground);

}
