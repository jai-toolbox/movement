// SPDX-License-Identifier: GPL-2.0-or-later
#import "Basic";

// Exact 32-bit Q3/CPMA movement ABI. These state types contain no host
// pointers, so they are suitable for deterministic simulation, snapshots and
// the CPMAORC1 verification corpus.

CPMA_MOVEMENT_CASE_SIZE :: 856;

CPMA_Vec3 :: [3] float32;

CPMA_Test_Playerstate :: struct {
    commandTime: s32;
    pm_type: s32;
    bobCycle: s32;
    pm_flags: s32;
    pm_time: s32;
    origin: CPMA_Vec3;
    velocity: CPMA_Vec3;
    weaponTime: s32;
    gravity: s32;
    speed: s32;
    delta_angles: [3] s32;
    groundEntityNum: s32;
    legsTimer: s32;
    legsAnim: s32;
    torsoTimer: s32;
    torsoAnim: s32;
    movementDir: s32;
    grapplePoint: CPMA_Vec3;
    eFlags: s32;
    eventSequence: s32;
    events: [2] s32;
    eventParms: [2] s32;
    externalEvent: s32;
    externalEventParm: s32;
    externalEventTime: s32;
    clientNum: s32;
    weapon: s32;
    weaponstate: s32;
    viewangles: CPMA_Vec3;
    viewheight: s32;
    damageEvent: s32;
    damageYaw: s32;
    damagePitch: s32;
    damageCount: s32;
    stats: [16] s32;
    persistant: [16] s32;
    powerups: [16] s32;
    ammo: [16] s32;
    generic1: s32;
    loopSound: s32;
    jumppad_ent: s32;
    ping: s32;
    pmove_framecount: s32;
    jumppad_frame: s32;
    entityEventSequence: s32;
}

CPMA_Test_Usercmd :: struct {
    serverTime: s32;
    angles: [3] s32;
    buttons: s32;
    weapon: u8;
    forwardmove: s8;
    rightmove: s8;
    upmove: s8;
}

CPMA_Test_Plane :: struct {
    normal: CPMA_Vec3;
    dist: float32;
    type_: u8;
    signbits: u8;
    pad: [2] u8;
}

CPMA_Test_Trace :: struct {
    allsolid: s32;
    startsolid: s32;
    fraction: float32;
    endpos: CPMA_Vec3;
    plane: CPMA_Test_Plane;
    surfaceFlags: s32;
    contents: s32;
    entityNum: s32;
}

CPMA_Test_Case :: struct {
    ps: CPMA_Test_Playerstate;
    cmd: CPMA_Test_Usercmd;
    tracemask: s32;
    debugLevel: s32;
    noFootsteps: s32;
    gauntletHit: s32;
    framecount: s32;
    numtouch: s32;
    touchents: [32] s32;
    mins: CPMA_Vec3;
    maxs: CPMA_Vec3;
    watertype: s32;
    waterlevel: s32;
    xyspeed: float32;
    evstepHack: s32;
    classPhysics: [35] float32;
    ntfEnabled: s32;
    ntfGrappleSpeed: float32;
    ntfDoubleJump: s32;
    ntfRampJump: s32;
    arenaFlags: s32;
    physicsMode: s32;
    serverGrappleSpeed: s32;
    arenaGameType: s32;
}

CPMA_Trace_Callback :: #type (
    user_data: *void,
    result: *CPMA_Test_Trace,
    start: CPMA_Vec3,
    mins: CPMA_Vec3,
    maxs: CPMA_Vec3,
    end: CPMA_Vec3,
    pass_entity_num: s32,
    content_mask: s32
) -> bool;

CPMA_Point_Contents_Callback :: #type (
    user_data: *void,
    point: CPMA_Vec3,
    pass_entity_num: s32
) -> result: s32, ok: bool;

CPMA_Collision_Interface :: struct {
    user_data: *void;
    trace: CPMA_Trace_Callback;
    point_contents: CPMA_Point_Contents_Callback;
}

CPMA_Pml :: struct {
    forward: CPMA_Vec3;
    right: CPMA_Vec3;
    up: CPMA_Vec3;
    frametime: float32;
    msec: s32;
    walking: bool;
    groundPlane: bool;
    groundTrace: CPMA_Test_Trace;
    impactSpeed: float32;
    previous_origin: CPMA_Vec3;
    previous_velocity: CPMA_Vec3;
    previous_waterlevel: s32;
}

CPMA_Context :: struct {
    test: *CPMA_Test_Case;
    collision: CPMA_Collision_Interface;
    pml: CPMA_Pml;
    callback_error: bool;
}

#assert size_of(CPMA_Test_Playerstate) == 468;
#assert size_of(CPMA_Test_Usercmd) == 24;
#assert size_of(CPMA_Test_Plane) == 20;
#assert size_of(CPMA_Test_Trace) == 56;
#assert size_of(CPMA_Test_Case) == CPMA_MOVEMENT_CASE_SIZE;
