CPMA_Movement_Parameters :: struct {
}

CPMA_Movement :: struct {

    gravity  : float = 20.0;
    friction : float = 6.0;

    move_speed               : float = 7.0;
    run_acceleration         : float = 14.0;
    run_deacceleration       : float = 10.0;
    air_acceleration         : float = 0.7;
    air_decceleration        : float = 2.0;
    air_control              : float = 0.3;
    side_strafe_acceleration : float = 50.0;
    side_strafe_speed        : float = 1.0;
    jump_speed               : float = 8.0;

    move_direction_norm  : Vector3 = .{0, 0, 0};

    player_top_velocity  : float   = 0.0;
    player_friction      : float   = 0.0;

    pressed_jump_since_last_jump : bool = false;
    on_ground                    : bool = false;

    movement_input : Movement_Input;
}

Movement_Input :: struct {
    forward_move : float;
    right_move   : float;
}

set_movement_input :: (player: *CPMA_Movement) {
    player.movement_input.forward_move = 0.0;
    player.movement_input.right_move   = 0.0;

    if is_key_down(xx #char "W") player.movement_input.forward_move += 1.0;
    if is_key_down(xx #char "S") player.movement_input.forward_move -= 1.0;
    if is_key_down(xx #char "D") player.movement_input.right_move   += 1.0;
    if is_key_down(xx #char "A") player.movement_input.right_move   -= 1.0;
}


apply_velocity_in_wishdir_capped_to_scaled_speed :: (velocity: *Vector3, player: *CPMA_Movement, wishdir: Vector3, speed_scaling_factor: float, accel: float, dt: float) {

    current_speed_in_wishdir := dot(velocity.*, wishdir);

    speed_needed_to_reach_scaled_speed_in_wishdir := speed_scaling_factor - current_speed_in_wishdir;

    if speed_needed_to_reach_scaled_speed_in_wishdir <= 0 return;

    velocity_gained_from_acceleration_this_frame := accel * dt * speed_scaling_factor;
    if velocity_gained_from_acceleration_this_frame > speed_needed_to_reach_scaled_speed_in_wishdir
        velocity_gained_from_acceleration_this_frame = speed_needed_to_reach_scaled_speed_in_wishdir;

    velocity.x += velocity_gained_from_acceleration_this_frame * wishdir.x;
    velocity.z += velocity_gained_from_acceleration_this_frame * wishdir.z;
}

adjust_velocity_direction_for_air_control :: (velocity: *Vector3, player: *CPMA_Movement, wishdir: Vector3, wishspeed: float, dt: float) {
    if abs(player.movement_input.forward_move) < 0.001 || abs(wishspeed) < 0.001
        return;

    original_vertical_speed := velocity.y;
    velocity.y = 0;

    current_horizontal_speed := length(velocity.*);
    velocity.* = unit_vector(velocity.*);

    velocity_alignment_with_wishdir := dot(velocity.*, wishdir);

    air_control_turning_strength : float = 32.0;
    air_control_turning_strength *= player.air_control * velocity_alignment_with_wishdir * velocity_alignment_with_wishdir * dt;

    if velocity_alignment_with_wishdir > 0 {
        velocity.* = unit_vector(velocity.* * current_horizontal_speed + wishdir * air_control_turning_strength);
        player.move_direction_norm = velocity.*;
    }

    velocity.x *= current_horizontal_speed;
    velocity.y = original_vertical_speed;
    velocity.z *= current_horizontal_speed;
}

update_velocity_while_in_air :: (velocity: *Vector3, player: *CPMA_Movement, forward_direction: Vector3, dt: float) {
    set_movement_input(player);

    input_direction := Vector3.{player.movement_input.right_move, 0, player.movement_input.forward_move};
    input_direction = transform_input_direction_to_world_space(forward_direction, input_direction);

    desired_speed := length(input_direction) * player.move_speed;

    input_direction = unit_vector(input_direction);
    player.move_direction_norm = input_direction;

    desired_speed_for_air_control := desired_speed;

    acceleration : float;
    if dot(velocity.*, input_direction) < 0
        acceleration = player.air_decceleration;
    else
        acceleration = player.air_acceleration;

    is_side_strafing_only := player.movement_input.forward_move == 0 && player.movement_input.right_move != 0;
    is_moving_forward_only := player.movement_input.forward_move != 0 && player.movement_input.right_move == 0;

    if is_side_strafing_only {
        if desired_speed > player.side_strafe_speed
            desired_speed = player.side_strafe_speed;
        acceleration = player.side_strafe_acceleration;
    }

    if is_moving_forward_only {
        horizontal_velocity := Vector3.{velocity.x, 0, velocity.z};
        current_horizontal_speed := length(horizontal_velocity);

        if current_horizontal_speed > 0.001 {
            horizontal_direction := unit_vector(horizontal_velocity);

            velocity_alignment_with_input := dot(horizontal_direction, input_direction);
            forward_only_turn_rate := player.air_control * 10.0;
            forward_only_turning_strength := 32.0 * forward_only_turn_rate * velocity_alignment_with_input * velocity_alignment_with_input * dt;

            if velocity_alignment_with_input > 0 {
                horizontal_direction = unit_vector(horizontal_direction * current_horizontal_speed + input_direction * forward_only_turning_strength);
            }

            velocity.x = horizontal_direction.x * current_horizontal_speed;
            velocity.z = horizontal_direction.z * current_horizontal_speed;
        }
    } else {
        apply_velocity_in_wishdir_capped_to_scaled_speed(velocity, player, input_direction, desired_speed, acceleration, dt);
    }

    if player.air_control > 0
        adjust_velocity_direction_for_air_control(velocity, player, input_direction, desired_speed_for_air_control, dt);

    velocity.y -= player.gravity * dt;
}

apply_ground_friction_to_velocity :: (velocity: *Vector3, player: *CPMA_Movement, friction_scale: float, dt: float) {
    horizontal_velocity := velocity.*;
    horizontal_velocity.y = 0.0;
    current_horizontal_speed := length(horizontal_velocity);
    speed_drop_from_friction : float = 0.0;

    if player.on_ground {
        control_speed := ifx current_horizontal_speed < player.run_deacceleration then player.run_deacceleration else current_horizontal_speed;
        speed_drop_from_friction = control_speed * player.friction * dt * friction_scale;
    }

    speed_after_friction := current_horizontal_speed - speed_drop_from_friction;
    player.player_friction = speed_after_friction;
    if speed_after_friction < 0 speed_after_friction = 0;

    speed_retention_ratio := ifx current_horizontal_speed > 0 then speed_after_friction / current_horizontal_speed else 0.0;

    velocity.x *= speed_retention_ratio;
    velocity.z *= speed_retention_ratio;
}

update_velocity_while_on_ground :: (velocity: *Vector3, player: *CPMA_Movement, forward_direction: Vector3, dt: float) {
    if !player.pressed_jump_since_last_jump
        apply_ground_friction_to_velocity(velocity, player, 1.0, dt);
    else
        apply_ground_friction_to_velocity(velocity, player, 0, dt);

    set_movement_input(player);

    input_direction := Vector3.{player.movement_input.right_move, 0, player.movement_input.forward_move};
    input_direction = transform_input_direction_to_world_space(forward_direction, input_direction);
    input_direction = unit_vector(input_direction);
    player.move_direction_norm = input_direction;

    desired_speed := length(input_direction) * player.move_speed;

    is_moving_forward_only := player.movement_input.forward_move != 0 && player.movement_input.right_move == 0;

    if is_moving_forward_only {
        horizontal_velocity := Vector3.{velocity.x, 0, velocity.z};
        current_horizontal_speed := length(horizontal_velocity);

        if current_horizontal_speed > 0.001 {
            horizontal_direction := unit_vector(horizontal_velocity);

            velocity_alignment_with_input := dot(horizontal_direction, input_direction);
            ground_turn_rate := player.air_control * 3.0;
            ground_turning_strength := 32.0 * ground_turn_rate * velocity_alignment_with_input * velocity_alignment_with_input * dt;

            if velocity_alignment_with_input > 0 {
                horizontal_direction = unit_vector(horizontal_direction * current_horizontal_speed + input_direction * ground_turning_strength);
            }

            if current_horizontal_speed < desired_speed {
                apply_velocity_in_wishdir_capped_to_scaled_speed(velocity, player, input_direction, desired_speed, player.run_acceleration, dt);
            } else {
                velocity.x = horizontal_direction.x * current_horizontal_speed;
                velocity.z = horizontal_direction.z * current_horizontal_speed;
            }
        } else {
            apply_velocity_in_wishdir_capped_to_scaled_speed(velocity, player, input_direction, desired_speed, player.run_acceleration, dt);
        }
    } else {
        apply_velocity_in_wishdir_capped_to_scaled_speed(velocity, player, input_direction, desired_speed, player.run_acceleration, dt);
    }

    velocity.y = -player.gravity * dt;

    if player.pressed_jump_since_last_jump {
        velocity.y = player.jump_speed;
        player.pressed_jump_since_last_jump = false;
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


update :: (cpma_movement: *CPMA_Movement, position: *Vector3, velocity: *Vector3, forward: Vector3, collision_map: *Collision_Geometries, dt: float) {

    if is_key_just_pressed(xx #char " ") cpma_movement.pressed_jump_since_last_jump = true;
    if !is_key_down(xx #char " ") cpma_movement.pressed_jump_since_last_jump = false;

    if cpma_movement.on_ground
        update_velocity_while_on_ground(velocity, cpma_movement, forward, dt);
    else
        update_velocity_while_in_air(velocity, cpma_movement, forward, dt);

    displacement := velocity.* * dt;

    ellipsoid_radius := Vector3.{0.4, 1.75 / 2.0, 0.4};
    resolve_collisions_against_body_ellipsoid(collision_map.*, ellipsoid_radius, position, *displacement, *cpma_movement.on_ground);

    udp := velocity.*;
    udp.y = 0.0;
    mag := length(udp);
    if mag > cpma_movement.player_top_velocity
        cpma_movement.player_top_velocity = mag;
}
