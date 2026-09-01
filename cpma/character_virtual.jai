// SPDX-License-Identifier: GPL-2.0-or-later
//
// Production integration boundary between exact CPMA movement math and the
// toolbox virtual character. CPMA owns intent/velocity; CharacterVirtual owns
// displacement, contacts, grounding, stance collision and stairs.

#import "Basic";
#import "Math";
#import "tbx/physics";
#import "tbx/collision";

CPMA_UNITS_PER_METER :: 32.0;
CPMA_TICK_SECONDS    :: cast(float32) (1.0 / 125.0);
CPMA_TICK_MSEC       :: 8;
CPMA_EYE_FROM_BOTTOM :: cast(float32) (50.0 / CPMA_UNITS_PER_METER);
CPMA_STANDING_HEIGHT :: 56.0;
CPMA_CROUCHED_HEIGHT :: 40.0;
CPMA_CAPSULE_RADIUS  :: 15.0;

// Serializable movement/reconciliation state. CharacterVirtual's contact
// scratch is deliberately not stored here: contacts are rebuilt from the map
// for each fixed movement step, keeping network snapshots compact and free of
// transient physics-engine internals.
CPMA_Movement_State :: struct {
    test: CPMA_Test_Case;
    position: Vector3;
    linear_velocity: Vector3;
    ground_state: Physics_Character_Virtual_Ground_State = .IN_AIR;
    ground_position: Vector3;
    ground_normal: Vector3 = .{0, 1, 0};
    ground_velocity: Vector3;
    ground_triangle_index: int = -1;
    accumulator_seconds: float64;
    crouched: bool;
    uncrouch_blocked: bool;
    initialized: bool;
}

cpma_movement_character_settings :: (crouched: bool) -> Physics_Character_Virtual_Settings {
    result: Physics_Character_Virtual_Settings;
    result.capsule_radius = cast(float32)(CPMA_CAPSULE_RADIUS / CPMA_UNITS_PER_METER);
    height := ifx crouched then CPMA_CROUCHED_HEIGHT else CPMA_STANDING_HEIGHT;
    result.capsule_half_height_of_cylinder = cpma_movement_capsule_half_height(height);
    result.supporting_volume_constant = -result.capsule_radius;
    return result;
}

cpma_movement_make_character :: (state: *CPMA_Movement_State) -> Physics_Character_Virtual {
    result := physics_character_virtual_make(
        cpma_movement_character_settings(state.crouched),
        state.position
    );
    result.linear_velocity = state.linear_velocity;
    result.ground_state = state.ground_state;
    result.ground_position = state.ground_position;
    result.ground_normal = state.ground_normal;
    result.ground_velocity = state.ground_velocity;
    result.ground_triangle_index = state.ground_triangle_index;
    return result;
}

cpma_movement_capture_character :: (
    state: *CPMA_Movement_State,
    character: *Physics_Character_Virtual
) {
    state.position = character.position;
    state.linear_velocity = character.linear_velocity;
    state.ground_state = character.ground_state;
    state.ground_position = character.ground_position;
    state.ground_normal = character.ground_normal;
    state.ground_velocity = character.ground_velocity;
    state.ground_triangle_index = character.ground_triangle_index;
}

cpma_movement_extended_settings :: () -> Physics_Character_Virtual_Extended_Update_Settings {
    result: Physics_Character_Virtual_Extended_Update_Settings;
    result.walk_stairs_step_up = .{0, cast(float32)(CPMA_STEPSIZE / CPMA_UNITS_PER_METER), 0};
    result.stick_to_floor_step_down = .{0, -0.25, 0};
    result.walk_stairs_step_down_extra = .{0, -0.05, 0};
    return result;
}

cpma_movement_world_velocity :: inline (q3: CPMA_Vec3) -> Vector3 {
    return .{
        q3[0] / CPMA_UNITS_PER_METER,
        q3[2] / CPMA_UNITS_PER_METER,
        q3[1] / CPMA_UNITS_PER_METER,
    };
}

cpma_movement_q3_velocity :: inline (world: Vector3) -> CPMA_Vec3 {
    return .[
        world.x * CPMA_UNITS_PER_METER,
        world.z * CPMA_UNITS_PER_METER,
        world.y * CPMA_UNITS_PER_METER,
    ];
}

cpma_movement_q3_direction :: inline (world: Vector3) -> CPMA_Vec3 {
    return .[world.x, world.z, world.y];
}

cpma_movement_sync_origin :: (controller: *CPMA_Movement_State) {
    bottom := controller.position;
    // Q3's player-state origin is 24 units above the bottom of its standing
    // bounding box.  The virtual character stores the capsule bottom.
    controller.test.ps.origin = .[
        bottom.x * CPMA_UNITS_PER_METER,
        bottom.z * CPMA_UNITS_PER_METER,
        bottom.y * CPMA_UNITS_PER_METER + 24.0,
    ];
}

cpma_movement_eye_from_bottom :: inline (controller: *CPMA_Movement_State) -> float32 {
    return cast(float32)(24 + controller.test.ps.viewheight) / CPMA_UNITS_PER_METER;
}

cpma_movement_capsule_half_height :: inline (total_height_q3: float32) -> float32 {
    return cast(float32)((total_height_q3 - 2.0 * CPMA_CAPSULE_RADIUS) * 0.5 / CPMA_UNITS_PER_METER);
}

// CPMA-local capsule specialization of Jolt CharacterVirtual::SetShape. The
// physics port stores capsule dimensions directly rather than retaining a
// generic Shape reference, so movement owns this stance policy and only uses
// the existing CharacterVirtual contact/query operations.
cpma_movement_set_capsule_half_height :: (
    character: *Physics_Character_Virtual,
    half_height_of_cylinder: float32,
    max_penetration_depth: float32,
    triangles: [] Geometry_Triangle
) -> bool {
    if half_height_of_cylinder < 0.0 || max_penetration_depth < 0.0 return false;
    if character.settings.capsule_half_height_of_cylinder == half_height_of_cylinder return true;

    candidate := character.*;
    candidate.settings.capsule_half_height_of_cylinder = half_height_of_cylinder;
    physics_character_virtual_refresh_contacts(
        *candidate,
        triangles,
        physics_normalized_or_zero(candidate.linear_velocity)
    );

    for i: 0..candidate.active_contact_count - 1 {
        contact := candidate.active_contacts[i];
        if contact.was_discarded continue;
        if contact.distance < -max_penetration_depth return false;
    }

    physics_character_virtual_update_supporting_contact(*candidate, true);
    character.* = candidate;
    return true;
}

cpma_movement_apply_stance_state :: (controller: *CPMA_Movement_State) {
    ps := *controller.test.ps;
    controller.test.mins = .[-15.0, -15.0, -24.0];
    controller.test.maxs[0] = 15.0;
    controller.test.maxs[1] = 15.0;
    if controller.crouched {
        ps.pm_flags |= CPMA_PMF_DUCKED;
        controller.test.maxs[2] = 16.0;
        ps.viewheight = 12;
    } else {
        ps.pm_flags &= cast(s32) ~CPMA_PMF_DUCKED;
        controller.test.maxs[2] = 32.0;
        ps.viewheight = 26;
    }
}

// Match CPMA's bottom-anchored standing/crouched bounds while using the
// CharacterVirtual collision system. Releasing crouch uses the same guarded
// shape replacement pattern as Jolt CharacterVirtual::SetShape.
cpma_movement_update_stance :: (
    controller: *CPMA_Movement_State,
    crouch_requested: bool,
    collision_triangles: [] Geometry_Triangle
) -> bool {
    if crouch_requested == controller.crouched {
        controller.uncrouch_blocked = false;
        cpma_movement_apply_stance_state(controller);
        return true;
    }

    target_height := ifx crouch_requested then CPMA_CROUCHED_HEIGHT else CPMA_STANDING_HEIGHT;
    target_half_height := cpma_movement_capsule_half_height(target_height);
    character := cpma_movement_make_character(controller);
    physics_character_virtual_refresh_contacts(
        *character,
        collision_triangles,
        physics_normalized_or_zero(character.linear_velocity)
    );
    max_penetration := 1.5 * character.settings.character_padding;
    changed := cpma_movement_set_capsule_half_height(
        *character,
        target_half_height,
        max_penetration,
        collision_triangles
    );
    if changed {
        controller.crouched = crouch_requested;
        cpma_movement_capture_character(controller, *character);
    }
    controller.uncrouch_blocked = !crouch_requested && !changed;
    cpma_movement_apply_stance_state(controller);
    return changed;
}

cpma_movement_reset :: (controller: *CPMA_Movement_State, spawn_bottom: Vector3 = .{0, 0.03, 0}) {
    controller.test = .{};
    controller.test.ps.pm_type = CPMA_PM_NORMAL;
    controller.test.ps.commandTime = 1;
    controller.test.ps.gravity = 800;
    controller.test.ps.speed = 320;
    controller.test.ps.groundEntityNum = CPMA_ENTITYNUM_NONE;
    controller.test.ps.viewheight = 26;
    controller.test.ps.stats[CPMA_STAT_HEALTH] = 100;
    controller.test.mins = .[-15.0, -15.0, -24.0];
    controller.test.maxs = .[15.0, 15.0, 32.0];
    controller.test.tracemask = CPMA_CONTENTS_SOLID;

    // Values captured from CPMA 1.53's CPM ruleset and used by the exact
    // oracle corpus.
    controller.test.classPhysics[CPMA_CLASS_AIR_CONTROL] = 150.0;
    controller.test.classPhysics[CPMA_CLASS_GROUND_ACCELERATE] = 15.0;
    controller.test.classPhysics[CPMA_CLASS_DOUBLE_JUMP] = 1.0;
    controller.test.classPhysics[CPMA_CLASS_RAMP_JUMP] = 1.0;
    controller.test.classPhysics[CPMA_CLASS_DEEP_WATER_SCALE] = 0.75;
    controller.test.classPhysics[CPMA_CLASS_SHALLOW_WATER_SCALE] = 1.0;
    controller.test.classPhysics[CPMA_CLASS_WATER_FRICTION] = 0.75;
    controller.test.classPhysics[CPMA_CLASS_WATER_ACCELERATE] = 5.0;
    controller.test.classPhysics[CPMA_CLASS_FLAG_SPEED_SCALE] = 1.5;

    controller.position = spawn_bottom;
    controller.linear_velocity = .{};
    controller.ground_state = .IN_AIR;
    controller.ground_position = .{};
    controller.ground_normal = .{0, 1, 0};
    controller.ground_velocity = .{};
    controller.ground_triangle_index = -1;
    controller.accumulator_seconds = 0.0;
    controller.crouched = false;
    controller.uncrouch_blocked = false;
    controller.initialized = true;
    cpma_movement_apply_stance_state(controller);
    cpma_movement_sync_origin(controller);
}

cpma_movement_init :: (controller: *CPMA_Movement_State, spawn_bottom: Vector3 = .{0, 0.03, 0}) {
    cpma_movement_reset(controller, spawn_bottom);
}

cpma_movement_ground_normal_q3 :: (controller: *CPMA_Movement_State) -> CPMA_Vec3 {
    normal := controller.ground_normal;
    if length_squared(normal) < 1.0e-8 normal = .{0, 1, 0};
    return cpma_movement_q3_direction(normal);
}

cpma_movement_prepare_tick :: (
    controller: *CPMA_Movement_State,
    ctx: *CPMA_Context,
    forward_world: Vector3,
    right_world: Vector3,
    forwardmove: s8,
    rightmove: s8,
    upmove: s8,
    walk_button: bool = false
) {
    test := *controller.test;
    ps := *test.ps;
    ctx.* = .{};
    ctx.test = *controller.test;

    test.cmd.forwardmove = forwardmove;
    test.cmd.rightmove = rightmove;
    test.cmd.upmove = upmove;
    test.cmd.buttons = cast(s32)(ifx walk_button then 16 else 0);
    test.cmd.serverTime = ps.commandTime + CPMA_TICK_MSEC;
    ps.commandTime = test.cmd.serverTime;
    ps.pmove_framecount = (ps.pmove_framecount + 1) & 63;

    ctx.pml = .{};
    ctx.pml.msec = CPMA_TICK_MSEC;
    ctx.pml.frametime = CPMA_TICK_SECONDS;
    ctx.pml.previous_origin = ps.origin;
    ctx.pml.previous_velocity = ps.velocity;
    ctx.pml.forward = cpma_movement_q3_direction(forward_world);
    ctx.pml.right = cpma_movement_q3_direction(right_world);
    ctx.pml.up = .[0.0, 0.0, 1.0];

    ground_normal := cpma_movement_ground_normal_q3(controller);
    supported := controller.ground_state == .ON_GROUND;
    has_ground_plane := controller.ground_state == .ON_GROUND ||
                        controller.ground_state == .ON_STEEP_GROUND;
    // Match PM_GroundTrace's upward-departure rule. This matters when a rocket
    // impulse is applied after the preceding CharacterVirtual update: the
    // character still reports support until its next upward movement.
    departing_ground := ps.velocity[2] > 0.0 && cpma_dot(ps.velocity, ground_normal) > 10.0;
    grounded := supported && !departing_ground;
    ground_plane := has_ground_plane && !departing_ground;
    ctx.pml.walking = grounded;
    ctx.pml.groundPlane = ground_plane;
    ctx.pml.groundTrace.fraction = 0.0;
    ctx.pml.groundTrace.entityNum = CPMA_ENTITYNUM_WORLD;
    ctx.pml.groundTrace.plane.normal = ground_normal;
    ps.groundEntityNum = cast(s32) (ifx grounded then CPMA_ENTITYNUM_WORLD else CPMA_ENTITYNUM_NONE);

    if test.cmd.upmove < 10 ps.pm_flags &= cast(s32) ~CPMA_PMF_JUMP_HELD;
    if test.cmd.forwardmove < 0 ps.pm_flags |= 16;
    else if test.cmd.forwardmove > 0 || (test.cmd.forwardmove == 0 && test.cmd.rightmove != 0) ps.pm_flags &= cast(s32) ~16;

    cpma_drop_movement_timers(ctx);
    if ps.stats[CPMA_STAT_JUMPTIME] > 0 ps.stats[CPMA_STAT_JUMPTIME] -= ctx.pml.msec;
    else if ps.stats[CPMA_STAT_DJUMPED] != 0 ps.stats[CPMA_STAT_DJUMPED] = 0;
}

cpma_movement_air_velocity :: (controller: *CPMA_Movement_State, ctx: *CPMA_Context) {
    test := *controller.test;
    ps := *test.ps;

    cpma_friction(ctx);
    cpma_set_movement_dir(ctx);
    ctx.pml.forward[2] = 0.0;
    ctx.pml.right[2] = 0.0;
    cpma_vector_normalize(*ctx.pml.forward);
    cpma_vector_normalize(*ctx.pml.right);

    wishvel: CPMA_Vec3;
    for i: 0..1 wishvel[i] = ctx.pml.forward[i] * cast(float32)cast(s32)test.cmd.forwardmove +
                               ctx.pml.right[i] * cast(float32)cast(s32)test.cmd.rightmove;
    wishvel[2] = 0.0;
    wishdir := wishvel;
    wishspeed := cpma_vector_normalize(*wishdir) * cpma_cmd_scale(ctx, *test.cmd);
    accel: float32 = 1.0;

    if test.classPhysics[CPMA_CLASS_AIR_CONTROL] != 0.0 {
        cpma_air_control(ctx, wishdir, wishspeed, ctx.pml.frametime);
        if cpma_dot(ps.velocity, wishdir) < 0.0 accel = 2.5;
        if ps.movementDir == 2 || ps.movementDir == 6 {
            if wishspeed > 30.0 wishspeed = 30.0;
            accel = 70.0;
        }
    }
    cpma_accelerate(ctx, wishdir, wishspeed, accel);
    if ctx.pml.groundPlane cpma_clip_velocity(ps.velocity, ctx.pml.groundTrace.plane.normal, *ps.velocity, CPMA_OVERCLIP);
}

// Returns true when the walking jump path transitioned into air movement.
cpma_movement_walk_velocity :: (controller: *CPMA_Movement_State, ctx: *CPMA_Context) -> bool {
    test := *controller.test;
    ps := *test.ps;

    if cpma_check_jump(ctx) {
        cpma_movement_air_velocity(controller, ctx);
        return true;
    }

    cpma_friction(ctx);
    cpma_set_movement_dir(ctx);
    ctx.pml.forward[2] = 0.0;
    ctx.pml.right[2] = 0.0;
    cpma_clip_velocity(ctx.pml.forward, ctx.pml.groundTrace.plane.normal, *ctx.pml.forward, CPMA_OVERCLIP);
    cpma_clip_velocity(ctx.pml.right, ctx.pml.groundTrace.plane.normal, *ctx.pml.right, CPMA_OVERCLIP);
    cpma_vector_normalize(*ctx.pml.forward);
    cpma_vector_normalize(*ctx.pml.right);

    wishvel: CPMA_Vec3;
    for i: 0..2 wishvel[i] = ctx.pml.forward[i] * cast(float32)cast(s32)test.cmd.forwardmove +
                               ctx.pml.right[i] * cast(float32)cast(s32)test.cmd.rightmove;
    wishdir := wishvel;
    wishspeed := cpma_vector_normalize(*wishdir) * cpma_cmd_scale(ctx, *test.cmd);
    if (ps.pm_flags & CPMA_PMF_DUCKED) != 0 && wishspeed > cast(float32)ps.speed * 0.25 {
        wishspeed = cast(float32)ps.speed * 0.25;
    }
    cpma_accelerate(ctx, wishdir, wishspeed, test.classPhysics[CPMA_CLASS_GROUND_ACCELERATE]);
    cpma_clip_velocity(ps.velocity, ctx.pml.groundTrace.plane.normal, *ps.velocity, CPMA_OVERCLIP);
    return false;
}

cpma_movement_tick :: (
    controller: *CPMA_Movement_State,
    forward_world: Vector3,
    right_world: Vector3,
    forwardmove: s8,
    rightmove: s8,
    upmove: s8,
    collision_triangles: [] Geometry_Triangle,
    walk_button: bool = false,
    crouch_requested: bool = false
) -> bool {
    cpma_movement_update_stance(controller, crouch_requested, collision_triangles);
    effective_upmove := upmove;
    if crouch_requested effective_upmove = cast(s8)(ifx walk_button then -64 else -127);
    ctx: CPMA_Context;
    cpma_movement_prepare_tick(controller, *ctx, forward_world, right_world, forwardmove, rightmove, effective_upmove, walk_button);

    ps := *controller.test.ps;
    was_walking := ctx.pml.walking;
    jumped := false;
    if was_walking jumped = cpma_movement_walk_velocity(controller, *ctx);
    else cpma_movement_air_velocity(controller, *ctx);

    final_velocity := ps.velocity;
    movement_velocity := final_velocity;
    if !was_walking || jumped {
        final_velocity[2] -= cast(float32)ps.gravity * CPMA_TICK_SECONDS;
        movement_velocity[2] = (movement_velocity[2] + final_velocity[2]) * 0.5;
    }

    character := cpma_movement_make_character(controller);
    character.linear_velocity = cpma_movement_world_velocity(movement_velocity);
    physics_character_virtual_extended_update(
        *character,
        CPMA_TICK_SECONDS,
        .{0, 0, 0},
        cpma_movement_extended_settings(),
        collision_triangles
    );

    resolved_velocity := physics_character_virtual_clip_velocity(
        *character,
        cpma_movement_world_velocity(final_velocity)
    );
    character.linear_velocity = resolved_velocity;
    cpma_movement_capture_character(controller, *character);
    ps.velocity = cpma_movement_q3_velocity(resolved_velocity);
    ps.groundEntityNum = cast(s32) (ifx controller.ground_state == .ON_GROUND then CPMA_ENTITYNUM_WORLD else CPMA_ENTITYNUM_NONE);
    controller.test.xyspeed = sqrtf(ps.velocity[0] * ps.velocity[0] + ps.velocity[1] * ps.velocity[1]);
    cpma_movement_sync_origin(controller);
    return jumped;
}

cpma_movement_apply_impulse :: (state: *CPMA_Movement_State, impulse_world: Vector3) {
    state.linear_velocity += impulse_world;
    state.test.ps.velocity = cpma_movement_q3_velocity(state.linear_velocity);
    if dot(impulse_world, Vector3.{0, 1, 0}) > 0.0 {
        state.ground_state = .IN_AIR;
        state.test.ps.groundEntityNum = CPMA_ENTITYNUM_NONE;
    }
}

// Apply an externally generated weapon impulse through the same player-state
// boundary used by CPMA's G_Damage path. The movement timer temporarily limits
// air control after knockback; changing linear_velocity alone omits that part
// of the weapon/movement interaction.
cpma_movement_apply_knockback :: (
    state: *CPMA_Movement_State,
    impulse_world: Vector3,
    knockback_points: s32
) {
    if knockback_points <= 0 || length_squared(impulse_world) <= 1.0e-12 return;

    cpma_movement_apply_impulse(state, impulse_world);
    if state.test.ps.pm_time == 0 {
        timer_msec := knockback_points * 2;
        if timer_msec < 50 timer_msec = 50;
        if timer_msec > 200 timer_msec = 200;
        state.test.ps.pm_time = timer_msec;
        state.test.ps.pm_flags |= CPMA_PMF_TIME_KNOCKBACK;
    }
}

// Compatibility facade for the client/server movement call site. Simulation is
// always stepped at CPMA's 8 ms pmove cadence; render/network frame time only
// feeds the serialized accumulator.
update :: (
    movement_state: *CPMA_Movement_State,
    movement_input: First_Person_Movement_Input,
    position: *Vector3,
    velocity: *Vector3,
    on_ground: *bool,
    forward: Vector3,
    collision_map: *Collision_Geometries,
    dt: float,
    ground_normal: *Vector3 = null,
    walk_requested: bool = false,
    crouch_requested: bool = false
) -> bool {
    if !movement_state.initialized cpma_movement_init(movement_state, position.*);

    movement_state.position = position.*;
    movement_state.linear_velocity = velocity.*;
    movement_state.test.ps.velocity = cpma_movement_q3_velocity(velocity.*);
    movement_state.ground_state = ifx on_ground.* then .ON_GROUND else .IN_AIR;
    if ground_normal != null movement_state.ground_normal = ground_normal.*;
    cpma_movement_sync_origin(movement_state);

    forward_horizontal := Vector3.{forward.x, 0, forward.z};
    if length_squared(forward_horizontal) < 1.0e-8 forward_horizontal = .{0, 0, -1};
    else forward_horizontal = normalize(forward_horizontal);
    right_horizontal := normalized_cross(forward_horizontal, Vector3.{0, 1, 0});

    move_axis_magnitude := ifx walk_requested then 64 else 127;
    forward_axis := 0;
    if movement_input.forward_pressed forward_axis += move_axis_magnitude;
    if movement_input.back_pressed forward_axis -= move_axis_magnitude;
    right_axis := 0;
    if movement_input.right_pressed right_axis += move_axis_magnitude;
    if movement_input.left_pressed right_axis -= move_axis_magnitude;
    up_axis := ifx movement_input.jump_pressed then 127 else 0;

    movement_state.accumulator_seconds += cast(float64)max(dt, 0.0);
    jump_occurred := false;
    steps := 0;
    while movement_state.accumulator_seconds >= cast(float64)CPMA_TICK_SECONDS && steps < 8 {
        jumped := cpma_movement_tick(
            movement_state,
            forward_horizontal,
            right_horizontal,
            cast(s8)forward_axis,
            cast(s8)right_axis,
            cast(s8)up_axis,
            collision_map.character_virtual_triangles,
            walk_requested,
            crouch_requested
        );
        jump_occurred = jump_occurred || jumped;
        movement_state.accumulator_seconds -= cast(float64)CPMA_TICK_SECONDS;
        steps += 1;
    }
    if steps == 8 && movement_state.accumulator_seconds >= cast(float64)CPMA_TICK_SECONDS {
        movement_state.accumulator_seconds = 0.0;
    }

    position.* = movement_state.position;
    velocity.* = movement_state.linear_velocity;
    on_ground.* = movement_state.ground_state == .ON_GROUND;
    if ground_normal != null {
        ground_normal.* = ifx on_ground.* then movement_state.ground_normal else Vector3.{0, 1, 0};
    }
    return jump_occurred;
}
