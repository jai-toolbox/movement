#scope_file
#import "tbx/physics";
#scope_export

Character_Virtual_Movement_Result :: struct {
    movement: Movement_Output;
    ground_state: Physics_Character_Virtual_Ground_State;
    ground_normal: Vector3;
    collision_occurred: bool;
}

// the movement controller owns velocity intent; CharacterVirtual owns position,
// contacts, slopes, sliding, floor sticking, and stairs.
update_character_virtual_movement :: (
    state: *Movement_State,
    character: *Physics_Character_Virtual,
    command: Movement_Command,
    view_forward: Vector3,
    view_right: Vector3,
    triangles: [] Geometry_Triangle,
    dt: float,
    surface_friction: float = 1.0,
    jump_factor: float = 1.0,
    parameters: Movement_Parameters = .{},
    extended_settings: Physics_Character_Virtual_Extended_Update_Settings = .{}
) -> Character_Virtual_Movement_Result {
    contact: Movement_Contact_State;
    contact.on_ground = character.ground_state == .ON_GROUND;
    contact.surface_friction = surface_friction;
    contact.jump_factor = jump_factor;

    prepared := prepare_movement(
        state,
        character.linear_velocity,
        command,
        view_forward,
        view_right,
        contact,
        dt,
        parameters
    );

    character.linear_velocity = prepared.velocity;
    physics_character_virtual_extended_update(
        character,
        cast(float32)dt,
        .{},
        extended_settings,
        triangles
    );

    collision_velocity := physics_character_virtual_clip_velocity(character, character.linear_velocity);
    on_ground_after_collision := character.ground_state == .ON_GROUND;
    movement := finish_movement(
        prepared,
        collision_velocity,
        on_ground_after_collision,
        dt,
        parameters
    );
    character.linear_velocity = movement.final_velocity;

    result: Character_Virtual_Movement_Result;
    result.movement = movement;
    result.ground_state = character.ground_state;
    result.ground_normal = character.ground_normal;
    result.collision_occurred = character.active_contact_count > 0;
    return result;
}
