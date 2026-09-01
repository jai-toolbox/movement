// collision-independent walking velocity controller.
//
// the engine is Y-up, distances are metres, and velocities are metres per
// second. Tuning values expressed in movement units are converted through one
// scale while dimensionless acceleration and friction coefficients stay intact.

MOVEMENT_UNITS_PER_METRE :: 32.0;

Movement_Parameters :: struct {
    gravity: float = 800.0 / MOVEMENT_UNITS_PER_METRE;
    entity_gravity_scale: float = 1.0;

    stop_speed: float = 100.0 / MOVEMENT_UNITS_PER_METRE;
    friction: float = 4.0;
    ground_acceleration: float = 10.0;
    air_acceleration: float = 10.0;
    air_speed_cap: float = 30.0 / MOVEMENT_UNITS_PER_METRE;

    max_speed: float = 320.0 / MOVEMENT_UNITS_PER_METRE;
    max_velocity: float = 3500.0 / MOVEMENT_UNITS_PER_METRE;
    walk_stop_speed: float = 1.0 / MOVEMENT_UNITS_PER_METRE;
    friction_skip_speed: float = 0.1 / MOVEMENT_UNITS_PER_METRE;

    jump_impulse: float = cast(float)268.3281572999747 / MOVEMENT_UNITS_PER_METRE;
}

default_movement_parameters :: () -> Movement_Parameters {
    return .{};
}

low_gravity_movement_parameters :: () -> Movement_Parameters {
    result: Movement_Parameters;
    result.gravity = 600.0 / MOVEMENT_UNITS_PER_METRE;
    result.jump_impulse = 160.0 / MOVEMENT_UNITS_PER_METRE;
    return result;
}

Movement_Command :: struct {
    // desired forward and side speeds in metres per second. Digital input
    // normally supplies +/-parameters.max_speed.
    forward_move: float;
    side_move: float;
    jump_down: bool;
}

Movement_Contact_State :: struct {
    on_ground: bool;
    surface_friction: float = 1.0;
    jump_factor: float = 1.0;
}

Movement_State :: struct {
    // tracks the previous jump input so holding the button does not retrigger it.
    jump_was_down: bool;
}

Source_Movement_Mode :: enum u32 {
    GROUND;
    AIR;
}

Prepared_Movement :: struct {
    // velocity passed to the collision solver, including the first gravity
    // half-step.
    velocity: Vector3;
    wish_velocity: Vector3;
    jump_velocity: Vector3;
    mode: Source_Movement_Mode;
    jumped: bool;
}

Movement_Output :: struct {
    pre_collision_velocity: Vector3;
    final_velocity: Vector3;
    requested_displacement: Vector3;
    wish_velocity: Vector3;
    jump_velocity: Vector3;
    mode: Source_Movement_Mode;
    jumped: bool;
    on_ground: bool;
}

movement_float_is_nan :: (value: float) -> bool {
    return value != value;
}

clamp_movement_velocity :: (velocity: *Vector3, max_velocity: float) {
    if movement_float_is_nan(velocity.x) velocity.x = 0.0;
    if movement_float_is_nan(velocity.y) velocity.y = 0.0;
    if movement_float_is_nan(velocity.z) velocity.z = 0.0;

    velocity.x = clamp(velocity.x, -max_velocity, max_velocity);
    velocity.y = clamp(velocity.y, -max_velocity, max_velocity);
    velocity.z = clamp(velocity.z, -max_velocity, max_velocity);
}

// keep normalization deterministic with the x64 runtime's reciprocal-square-
// root estimate and refinement. Other architectures use the scalar equivalent.
movement_reciprocal_sqrt :: inline (value: float) -> float {
    #if CPU == .X64 {
        input := Vector4.{value, 0.0, 0.0, 0.0};
        three := Vector4.{3.0, 0.0, 0.0, 0.0};
        half := Vector4.{0.5, 0.0, 0.0, 0.0};
        result: Vector4;
        #asm SSE {
            movaps input_reg:, input;
            rsqrtss estimate:, input_reg;
            movaps estimate_squared:, estimate;
            mulss estimate_squared, estimate;
            mulss estimate_squared, input_reg;
            movaps correction:, three;
            subss correction, estimate_squared;
            mulss correction, half;
            mulss estimate, correction;
            movaps result, estimate;
        }
        return result.x;
    } else {
        return 1.0 / sqrt(value);
    }
}

// returns the approximate magnitude used by the normalization path.
normalize_movement_vector :: (value: *Vector3) -> float {
    square_length := value.x * value.x + value.y * value.y + value.z * value.z + 1.0e-10;
    inverse_length := movement_reciprocal_sqrt(square_length);
    value.x *= inverse_length;
    value.y *= inverse_length;
    value.z *= inverse_length;
    return square_length * inverse_length;
}

movement_basis_from_forward :: (forward: Vector3) -> (flat_forward: Vector3, flat_right: Vector3) {
    flat_forward := forward;
    flat_forward.y = 0.0;
    normalize_movement_vector(*flat_forward);
    flat_right := Vector3.{-flat_forward.z, 0.0, flat_forward.x};
    return flat_forward, flat_right;
}

crop_movement_command :: (command: Movement_Command, max_speed: float) -> Movement_Command {
    result := command;
    speed_squared := result.forward_move * result.forward_move + result.side_move * result.side_move;
    max_speed_squared := max_speed * max_speed;
    if speed_squared != 0.0 && speed_squared > max_speed_squared {
        ratio := max_speed / sqrt(speed_squared);
        result.forward_move *= ratio;
        result.side_move *= ratio;
    }
    return result;
}

make_movement_wish :: (
    command: Movement_Command,
    view_forward: Vector3,
    view_right: Vector3,
    max_speed: float,
    always_normalize_basis: bool
) -> (wish_direction: Vector3, wish_speed: float) {
    forward := view_forward;
    right := view_right;

    if always_normalize_basis {
        forward.y = 0.0;
        right.y = 0.0;
        normalize_movement_vector(*forward);
        normalize_movement_vector(*right);
    } else {
        // ground movement only needs to renormalize a basis that contained a
        // vertical component before flattening.
        if forward.y != 0.0 {
            forward.y = 0.0;
            normalize_movement_vector(*forward);
        }
        if right.y != 0.0 {
            right.y = 0.0;
            normalize_movement_vector(*right);
        }
    }

    wish_velocity := forward * command.forward_move + right * command.side_move;
    wish_velocity.y = 0.0;
    wish_direction := wish_velocity;
    wish_speed := normalize_movement_vector(*wish_direction);

    if wish_speed != 0.0 && wish_speed > max_speed {
        wish_speed = max_speed;
    }
    return wish_direction, wish_speed;
}

accelerate_movement :: (
    velocity: *Vector3,
    wish_direction: Vector3,
    wish_speed: float,
    acceleration: float,
    surface_friction: float,
    dt: float
) {
    current_speed := dot(velocity.*, wish_direction);
    add_speed := wish_speed - current_speed;
    if add_speed <= 0.0 return;

    acceleration_speed := acceleration * dt * wish_speed * surface_friction;
    if acceleration_speed > add_speed acceleration_speed = add_speed;
    velocity.* += acceleration_speed * wish_direction;
}

accelerate_air_movement :: (
    velocity: *Vector3,
    wish_direction: Vector3,
    wish_speed: float,
    acceleration: float,
    air_speed_cap: float,
    surface_friction: float,
    dt: float,
    wish_velocity_output: *Vector3
) {
    capped_wish_speed := wish_speed;
    if capped_wish_speed > air_speed_cap capped_wish_speed = air_speed_cap;

    current_speed := dot(velocity.*, wish_direction);
    add_speed := capped_wish_speed - current_speed;
    if add_speed <= 0.0 return;

    // deliberately use uncapped wish_speed here. The cap limits how much speed
    // may be added along the wish direction, not the acceleration response.
    acceleration_speed := acceleration * wish_speed * dt * surface_friction;
    if acceleration_speed > add_speed acceleration_speed = add_speed;

    delta := acceleration_speed * wish_direction;
    velocity.* += delta;
    wish_velocity_output.* += delta;
}

apply_ground_friction :: (
    velocity: *Vector3,
    surface_friction: float,
    dt: float,
    parameters: Movement_Parameters,
    wish_velocity_output: *Vector3
) {
    speed := sqrt(velocity.x * velocity.x + velocity.y * velocity.y + velocity.z * velocity.z);
    if speed < parameters.friction_skip_speed return;

    control := ifx speed < parameters.stop_speed then parameters.stop_speed else speed;
    drop := control * parameters.friction * surface_friction * dt;
    new_speed := speed - drop;
    if new_speed < 0.0 new_speed = 0.0;

    if new_speed != speed {
        new_speed /= speed;
        velocity.* *= new_speed;
    }

    wish_velocity_output.* -= (1.0 - new_speed) * velocity.*;
}

prepare_movement :: (
    state: *Movement_State,
    velocity: Vector3,
    command_in: Movement_Command,
    view_forward: Vector3,
    view_right: Vector3,
    contact: Movement_Contact_State,
    dt: float,
    parameters: Movement_Parameters = .{}
) -> Prepared_Movement {
    result: Prepared_Movement;
    working_velocity := velocity;
    command := crop_movement_command(command_in, parameters.max_speed);

    // first gravity half-step before collision resolution.
    working_velocity.y -= parameters.entity_gravity_scale * parameters.gravity * 0.5 * dt;
    clamp_movement_velocity(*working_velocity, parameters.max_velocity);

    on_ground_for_movement := contact.on_ground;
    if command.jump_down && contact.on_ground && !state.jump_was_down {
        start_y := working_velocity.y;
        on_ground_for_movement = false;
        working_velocity.y += contact.jump_factor * parameters.jump_impulse;

        // jump preparation consumes another gravity half-step. The finish phase
        // applies the remaining post-collision half-step.
        working_velocity.y -= parameters.entity_gravity_scale * parameters.gravity * 0.5 * dt;
        clamp_movement_velocity(*working_velocity, parameters.max_velocity);
        result.jump_velocity.y += working_velocity.y - start_y;
        result.jumped = true;
    }

    if on_ground_for_movement {
        result.mode = .GROUND;
        working_velocity.y = 0.0;
        apply_ground_friction(
            *working_velocity,
            contact.surface_friction,
            dt,
            parameters,
            *result.wish_velocity
        );
        clamp_movement_velocity(*working_velocity, parameters.max_velocity);

        wish_direction, wish_speed := make_movement_wish(
            command,
            view_forward,
            view_right,
            parameters.max_speed,
            false
        );
        working_velocity.y = 0.0;
        accelerate_movement(
            *working_velocity,
            wish_direction,
            wish_speed,
            parameters.ground_acceleration,
            contact.surface_friction,
            dt
        );
        working_velocity.y = 0.0;

        if sqrt(working_velocity.x * working_velocity.x + working_velocity.y * working_velocity.y + working_velocity.z * working_velocity.z) < parameters.walk_stop_speed {
            working_velocity = .{};
        } else {
            result.wish_velocity += wish_direction * wish_speed;
        }
    } else {
        result.mode = .AIR;
        wish_direction, wish_speed := make_movement_wish(
            command,
            view_forward,
            view_right,
            parameters.max_speed,
            true
        );
        accelerate_air_movement(
            *working_velocity,
            wish_direction,
            wish_speed,
            parameters.air_acceleration,
            parameters.air_speed_cap,
            contact.surface_friction,
            dt,
            *result.wish_velocity
        );
    }

    state.jump_was_down = command.jump_down;
    result.velocity = working_velocity;
    return result;
}

finish_movement :: (
    prepared: Prepared_Movement,
    collision_velocity: Vector3,
    on_ground_after_collision: bool,
    dt: float,
    parameters: Movement_Parameters = .{}
) -> Movement_Output {
    final_velocity := collision_velocity;

    // final gravity half-step after collision resolution.
    final_velocity.y -= parameters.entity_gravity_scale * parameters.gravity * 0.5 * dt;
    clamp_movement_velocity(*final_velocity, parameters.max_velocity);
    if on_ground_after_collision final_velocity.y = 0.0;

    result: Movement_Output;
    result.pre_collision_velocity = prepared.velocity;
    result.final_velocity = final_velocity;
    result.requested_displacement = prepared.velocity * dt;
    result.wish_velocity = prepared.wish_velocity;
    result.jump_velocity = prepared.jump_velocity;
    result.mode = prepared.mode;
    result.jumped = prepared.jumped;
    result.on_ground = on_ground_after_collision;
    return result;
}

// useful for movement-only tests or games that resolve collision elsewhere.
step_movement :: (
    state: *Movement_State,
    velocity: Vector3,
    command: Movement_Command,
    view_forward: Vector3,
    view_right: Vector3,
    contact_before: Movement_Contact_State,
    on_ground_after_collision: bool,
    dt: float,
    parameters: Movement_Parameters = .{}
) -> Movement_Output {
    prepared := prepare_movement(
        state,
        velocity,
        command,
        view_forward,
        view_right,
        contact_before,
        dt,
        parameters
    );
    return finish_movement(
        prepared,
        prepared.velocity,
        on_ground_after_collision,
        dt,
        parameters
    );
}
