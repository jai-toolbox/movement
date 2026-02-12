#import "Math";
#import "Basic";

#import "tbx/math";
#import "tbx/turns";

#load "god_mode.jai";

Movement_Params :: struct {
    gravity_mpss := -9.81;
    acceleration_mpss : float = 10;

    jump_force : float = 5;
    moving_friction_per_second : float = 0.06;
    stopping_friction_per_second : float = 0.01;
}


First_Person_Movement_Input :: struct {
    forward_pressed : bool;
    back_pressed : bool;
    right_pressed : bool;
    left_pressed : bool;
    jump_pressed : bool;
}

Ground_State :: enum u32 {
    ON_GROUND;
    IN_AIR;
}

get_xz_input :: (using fpmi : First_Person_Movement_Input) -> Vector3 {
    input : Vector3;

    if (forward_pressed)
        input.z += 1.0;
    if (back_pressed)
        input.z -= 1.0;

    if (right_pressed)
        input.x += 1.0;
    if (left_pressed)
        input.x -= 1.0;

    len := length(input);
    if (len > 0.0)
        normalize(*input);

    return input;
}

// log_var :: (var_name : string) #expand {
//     #code #run sprint("log(\"%: \%\", %);", var_name, var_name);
// }

get_new_first_person_velocity :: ( 
            current_velocity : Vector3, 
            fpmi : First_Person_Movement_Input, 
            camera_forward: Vector3, 
            dt : float, 
            ground_state : Ground_State, 
            mp : Movement_Params = .{}
            ) -> Vector3, jump_occurred: bool {

    current_velocity_copy := current_velocity;

    xz_camera_forward := normalize(Vector3.{camera_forward.x, 0, camera_forward.z});
    xz_camera_right := normalized_cross(xz_camera_forward , Y3);

    raw_input := get_xz_input(fpmi);

    // #insert #run log_var("raw_input");

    look_input := raw_input.z * xz_camera_forward + raw_input.x * xz_camera_right;

    horizontal_velocity := Vector3.{current_velocity_copy.x, 0, current_velocity_copy.z};

    if (length(look_input) > 0.0) {
        horizontal_velocity += look_input * dt * mp.acceleration_mpss;
        horizontal_velocity *= pow(mp.moving_friction_per_second, dt);
    } else {
        horizontal_velocity *= pow(mp.stopping_friction_per_second, dt);
    }
    current_velocity_copy.x = horizontal_velocity.x;
    current_velocity_copy.z = horizontal_velocity.z;

    jump_occurred := false;

    if (ground_state == .ON_GROUND) {
        if (current_velocity_copy.y < 0.0)
            current_velocity_copy.y = 0;

        if (fpmi.jump_pressed) {
            current_velocity_copy.y = mp.jump_force;
            jump_occurred = true;
        }
    }
    
    current_velocity_copy.y += mp.gravity_mpss * dt;

    return current_velocity_copy, jump_occurred;
}

Rotating_Movement :: struct {
    origin : Vector3;
    rotation_axis : Vector3;
    radius : float;
    rotation_rate_hz : float;
    accumulated_time_sec : float = 0;
}

get_current_position :: (using rm : *Rotating_Movement, delta_time : float) -> Vector3 {
    accumulated_time_sec += delta_time;

    angle := accumulated_time_sec * rotation_rate_hz;
    axis := normalize(rotation_axis);

    perp : Vector3;
    if abs(axis.x) < 0.9 {
        perp = normalized_cross(axis, .{1, 0, 0});
    } else {
        perp = normalized_cross(axis, .{0, 1, 0});
    }

    // her axis, perp, and perp_basis_2 make an orthonormal basis. where
    // perp and perp basis_2 are on the plane, allowing us to do rotations 
    // using them
    perp_basis_2 := cross(axis, perp);

    rotated := perp * cos_turns(angle) +  perp_basis_2 * sin_turns(angle);

    return origin + rotated * radius;
}




















