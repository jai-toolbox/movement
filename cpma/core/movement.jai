// SPDX-License-Identifier: GPL-2.0-or-later
#import "Basic";

#load "types.jai";

cpma_libm :: #library,system,link_always "libm";
sqrtf :: (value: float32) -> float32 #foreign cpma_libm;
sinf  :: (value: float32) -> float32 #foreign cpma_libm;
cosf  :: (value: float32) -> float32 #foreign cpma_libm;

CPMA_PM_NORMAL         :: 0;
CPMA_PM_NOCLIP         :: 1;
CPMA_PM_SPECTATOR      :: 2;
CPMA_PM_DEAD           :: 3;
CPMA_PM_FREEZE         :: 4;
CPMA_PM_INTERMISSION   :: 5;
CPMA_PM_SPINTERMISSION :: 6;

CPMA_PMF_DUCKED          :: 1;
CPMA_PMF_JUMP_HELD       :: 2;
CPMA_PMF_BACKWARDS_JUMP  :: 8;
CPMA_PMF_TIME_LAND       :: 32;
CPMA_PMF_TIME_KNOCKBACK  :: 64;
CPMA_PMF_TIME_WATERJUMP  :: 256;
CPMA_PMF_RESPAWNED       :: 512;
CPMA_PMF_GRAPPLE_PULL    :: 2048;
CPMA_PMF_FOLLOW          :: 4096;

CPMA_STAT_HEALTH   :: 0;
CPMA_STAT_JUMPTIME :: 7;
CPMA_STAT_DJUMPED  :: 8;

CPMA_PW_FLIGHT   :: 6;
CPMA_PW_REDFLAG  :: 7;
CPMA_PW_BLUEFLAG :: 8;

CPMA_SURF_SLICK       :: 2;
CPMA_ENTITYNUM_NONE   :: 1023;
CPMA_ENTITYNUM_WORLD  :: 1022;
CPMA_STEPSIZE         :: 18.0;
CPMA_MAX_CLIP_PLANES  :: 5;
CPMA_OVERCLIP         :: 1.001;

CPMA_CONTENTS_SOLID :: 1;
CPMA_CONTENTS_LAVA  :: 8;
CPMA_CONTENTS_SLIME :: 16;
CPMA_CONTENTS_WATER :: 32;
CPMA_CONTENTS_BODY  :: 0x02000000;
CPMA_ARENAFLAG_CLASSIC_CTF_SPEED :: 0x20000000;

CPMA_CLASS_AIR_CONTROL         :: 0;
CPMA_CLASS_GROUND_ACCELERATE   :: 1;
CPMA_CLASS_DOUBLE_JUMP         :: 2;
CPMA_CLASS_RAMP_JUMP           :: 3;
CPMA_CLASS_DEEP_WATER_SCALE    :: 21;
CPMA_CLASS_SHALLOW_WATER_SCALE :: 22;
CPMA_CLASS_WATER_FRICTION      :: 23;
CPMA_CLASS_WATER_ACCELERATE    :: 24;
CPMA_CLASS_FLAG_SPEED_SCALE    :: 34;

cpma_abs_s8 :: inline (value: s8) -> s32 {
    widened := cast(s32) value;
    if widened < 0 return -widened;
    return widened;
}

cpma_float_bits :: inline (value: float32) -> u32 {
    return (.*) cast(*u32) *value;
}

cpma_s32_bits :: inline (value: s32) -> u32 {
    return (.*) cast(*u32) *value;
}

cpma_dot :: inline (a: CPMA_Vec3, b: CPMA_Vec3) -> float32 {
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

cpma_vector_length :: inline (value: CPMA_Vec3) -> float32 {
    return sqrtf(cpma_dot(value, value));
}

cpma_vector_normalize :: (value: *CPMA_Vec3) -> float32 {
    length := cpma_vector_length(value.*);
    if length != 0.0 {
        scale := 1.0 / length;
        value.*[0] *= scale;
        value.*[1] *= scale;
        value.*[2] *= scale;
    }
    return length;
}

cpma_vector_normalize2 :: (input: CPMA_Vec3, output: *CPMA_Vec3) -> float32 {
    output.* = input;
    return cpma_vector_normalize(output);
}

cpma_cross :: inline (a: CPMA_Vec3, b: CPMA_Vec3) -> CPMA_Vec3 {
    return .[
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ];
}

cpma_trace :: (
    ctx: *CPMA_Context,
    result: *CPMA_Test_Trace,
    start: CPMA_Vec3,
    mins: CPMA_Vec3,
    maxs: CPMA_Vec3,
    end: CPMA_Vec3,
    pass_entity_num: s32,
    content_mask: s32
) {
    result.* = .{};
    if ctx.collision.trace == null ||
       !ctx.collision.trace(
           ctx.collision.user_data,
           result,
           start,
           mins,
           maxs,
           end,
           pass_entity_num,
           content_mask
       ) {
        ctx.callback_error = true;
    }
}

cpma_point_contents :: (ctx: *CPMA_Context, point: CPMA_Vec3, pass_entity_num: s32) -> s32 {
    result: s32;
    if ctx.collision.point_contents == null {
        ctx.callback_error = true;
        return result;
    }
    ok: bool;
    result, ok = ctx.collision.point_contents(ctx.collision.user_data, point, pass_entity_num);
    if !ok ctx.callback_error = true;
    return result;
}

cpma_add_touch_ent :: (test: *CPMA_Test_Case, entity_num: s32) {
    if entity_num == CPMA_ENTITYNUM_WORLD || test.numtouch == 32 return;
    for i: 0..cast(int)test.numtouch-1 {
        if test.touchents[i] == entity_num return;
    }
    test.touchents[test.numtouch] = entity_num;
    test.numtouch += 1;
}

cpma_clip_velocity :: (input: CPMA_Vec3, normal: CPMA_Vec3, output: *CPMA_Vec3, overbounce: float32) {
    backoff := cpma_dot(input, normal);
    if backoff < 0.0 backoff *= overbounce;
    else backoff /= overbounce;
    for i: 0..2 output.*[i] = input[i] - normal[i] * backoff;
}

cpma_clip_velocity_xy :: (input: CPMA_Vec3, normal: CPMA_Vec3, output: *CPMA_Vec3, overbounce: float32) {
    backoff := cpma_dot(input, normal);
    if backoff < 0.0 backoff *= overbounce;
    else backoff /= overbounce;
    for i: 0..1 output.*[i] = input[i] - normal[i] * backoff;
}

cpma_slide_move :: (ctx: *CPMA_Context, gravity: bool) -> bool {
    test := ctx.test;
    ps := *test.ps;
    planes: [CPMA_MAX_CLIP_PLANES] CPMA_Vec3;
    primal_velocity := ps.velocity;
    clip_velocity: CPMA_Vec3;
    end_velocity: CPMA_Vec3;
    end_clip_velocity: CPMA_Vec3;

    if gravity {
        end_velocity = ps.velocity;
        end_velocity[2] -= cast(float32)ps.gravity * ctx.pml.frametime;
        ps.velocity[2] = (ps.velocity[2] + end_velocity[2]) * 0.5;
        primal_velocity[2] = end_velocity[2];
        if ctx.pml.groundPlane {
            cpma_clip_velocity(ps.velocity, ctx.pml.groundTrace.plane.normal, *ps.velocity, CPMA_OVERCLIP);
        }
    } else {
        end_velocity = .[0.0, 0.0, 0.0];
    }

    time_left := ctx.pml.frametime;
    numplanes := 0;
    if ctx.pml.groundPlane {
        numplanes = 1;
        planes[0] = ctx.pml.groundTrace.plane.normal;
    }
    cpma_vector_normalize2(ps.velocity, *planes[numplanes]);
    numplanes += 1;

    bumpcount := 0;
    while bumpcount < 4 {
        end: CPMA_Vec3;
        for i: 0..2 end[i] = ps.origin[i] + time_left * ps.velocity[i];

        trace: CPMA_Test_Trace;
        cpma_trace(ctx, *trace, ps.origin, test.mins, test.maxs, end, ps.clientNum, test.tracemask);
        if trace.allsolid != 0 {
            ps.velocity[2] = 0.0;
            return true;
        }
        if trace.fraction > 0.0 ps.origin = trace.endpos;
        if trace.fraction == 1.0 break;

        cpma_add_touch_ent(test, trace.entityNum);
        time_left -= time_left * trace.fraction;
        if numplanes >= CPMA_MAX_CLIP_PLANES {
            ps.velocity = .[0.0, 0.0, 0.0];
            return true;
        }

        i := 0;
        while i < numplanes {
            if cpma_dot(trace.plane.normal, planes[i]) > 0.99 {
                ps.velocity[0] += trace.plane.normal[0];
                ps.velocity[1] += trace.plane.normal[1];
                ps.velocity[2] += trace.plane.normal[2];
                break;
            }
            i += 1;
        }
        if i < numplanes {
            bumpcount += 1;
            continue;
        }
        planes[numplanes] = trace.plane.normal;
        numplanes += 1;

        i = 0;
        while i < numplanes {
            into := cpma_dot(ps.velocity, planes[i]);
            if into >= 0.1 {
                i += 1;
                continue;
            }
            if -into > ctx.pml.impactSpeed ctx.pml.impactSpeed = -into;

            cpma_clip_velocity(ps.velocity, planes[i], *clip_velocity, CPMA_OVERCLIP);
            cpma_clip_velocity(end_velocity, planes[i], *end_clip_velocity, CPMA_OVERCLIP);

            j := 0;
            while j < numplanes {
                if j == i || cpma_dot(clip_velocity, planes[j]) >= 0.1 {
                    j += 1;
                    continue;
                }
                cpma_clip_velocity(clip_velocity, planes[j], *clip_velocity, CPMA_OVERCLIP);
                cpma_clip_velocity(end_clip_velocity, planes[j], *end_clip_velocity, CPMA_OVERCLIP);
                if cpma_dot(clip_velocity, planes[i]) >= 0.0 {
                    j += 1;
                    continue;
                }

                dir := cpma_cross(planes[i], planes[j]);
                cpma_vector_normalize(*dir);
                d := cpma_dot(dir, ps.velocity);
                clip_velocity[0] = dir[0] * d;
                clip_velocity[1] = dir[1] * d;
                clip_velocity[2] = dir[2] * d;

                dir = cpma_cross(planes[i], planes[j]);
                cpma_vector_normalize(*dir);
                d = cpma_dot(dir, end_velocity);
                end_clip_velocity[0] = dir[0] * d;
                end_clip_velocity[1] = dir[1] * d;
                end_clip_velocity[2] = dir[2] * d;

                for k: 0..numplanes-1 {
                    if k == i || k == j || cpma_dot(clip_velocity, planes[k]) >= 0.1 continue;
                    ps.velocity = .[0.0, 0.0, 0.0];
                    return true;
                }
                j += 1;
            }

            ps.velocity = clip_velocity;
            end_velocity = end_clip_velocity;
            break;
        }
        bumpcount += 1;
    }

    if gravity ps.velocity = end_velocity;
    if ps.pm_time != 0 ps.velocity = primal_velocity;
    return bumpcount != 0;
}

cpma_step_slide_move :: (ctx: *CPMA_Context, gravity: bool) {
    test := ctx.test;
    ps := *test.ps;
    start_o := ps.origin;
    start_v := ps.velocity;
    if !cpma_slide_move(ctx, gravity) return;
    if ps.pm_flags & CPMA_PMF_GRAPPLE_PULL return;

    down := start_o;
    down[2] -= CPMA_STEPSIZE;
    trace: CPMA_Test_Trace;
    cpma_trace(ctx, *trace, start_o, test.mins, test.maxs, down, ps.clientNum, test.tracemask);
    if ps.velocity[2] > 0.0 && (trace.fraction == 1.0 || trace.plane.normal[2] < 0.7) {
        if ps.velocity[2] > 380.0 || ps.stats[CPMA_STAT_JUMPTIME] <= 0 return;
    }

    up := start_o;
    up[2] += CPMA_STEPSIZE;
    cpma_trace(ctx, *trace, up, test.mins, test.maxs, up, ps.clientNum, test.tracemask);
    if trace.allsolid != 0 return;

    ps.origin = up;
    ps.velocity = start_v;
    cpma_slide_move(ctx, gravity);

    down = ps.origin;
    down[2] -= CPMA_STEPSIZE;
    cpma_trace(ctx, *trace, ps.origin, test.mins, test.maxs, down, ps.clientNum, test.tracemask);
    if trace.allsolid == 0 ps.origin = trace.endpos;
    if trace.fraction >= 1.0 return;
    if ps.stats[CPMA_STAT_DJUMPED] != 0 {
        cpma_clip_velocity_xy(ps.velocity, trace.plane.normal, *ps.velocity, CPMA_OVERCLIP);
    } else {
        cpma_clip_velocity(ps.velocity, trace.plane.normal, *ps.velocity, CPMA_OVERCLIP);
    }
    delta := ps.origin[2] - start_o[2];
    if delta > 2.0 test.evstepHack = cast(s32) delta;
}

cpma_friction :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    vec := ps.velocity;
    if ctx.pml.walking vec[2] = 0.0;
    speed := cpma_vector_length(vec);
    if speed < 1.0 {
        ps.velocity[0] = 0.0;
        ps.velocity[1] = 0.0;
        if ps.pm_type == CPMA_PM_SPECTATOR ps.velocity[2] = 0.0;
        return;
    }

    drop: float32 = 0.0;
    if test.waterlevel <= 1 && ctx.pml.walking &&
       !(ctx.pml.groundTrace.surfaceFlags & CPMA_SURF_SLICK) &&
       !(ps.pm_flags & CPMA_PMF_TIME_KNOCKBACK) {
        control := speed;
        if speed < 100.0 control = 100.0;
        friction: float32 = 6.0;
        if test.physicsMode == 3 friction = 5.6;
        drop += control * ctx.pml.frametime * friction;
    }
    if test.waterlevel != 0 {
        drop += speed * ctx.pml.frametime * test.classPhysics[CPMA_CLASS_WATER_FRICTION] * cast(float32)test.waterlevel;
    }
    if ps.powerups[CPMA_PW_FLIGHT] != 0 drop += speed * ctx.pml.frametime * 3.0;
    if ps.pm_type == CPMA_PM_SPECTATOR drop += speed * ctx.pml.frametime * 5.0;

    newspeed := speed - drop;
    if newspeed < 0.0 newspeed = 0.0;
    newspeed /= speed;
    ps.velocity[0] *= newspeed;
    ps.velocity[1] *= newspeed;
    ps.velocity[2] *= newspeed;
}

cpma_accelerate :: (ctx: *CPMA_Context, wishdir: CPMA_Vec3, wishspeed: float32, accel: float32) {
    ps := *ctx.test.ps;
    currentspeed := cpma_dot(ps.velocity, wishdir);
    addspeed := wishspeed - currentspeed;
    if addspeed <= 0.0 return;
    accelspeed := accel * (ctx.pml.frametime * wishspeed);
    if accelspeed > addspeed accelspeed = addspeed;
    for i: 0..2 ps.velocity[i] += accelspeed * wishdir[i];
}

cpma_cmd_scale :: (ctx: *CPMA_Context, cmd: *CPMA_Test_Usercmd) -> float32 {
    max_axis := cpma_abs_s8(cmd.forwardmove);
    if cpma_abs_s8(cmd.rightmove) > max_axis max_axis = cpma_abs_s8(cmd.rightmove);
    if cpma_abs_s8(cmd.upmove) > max_axis max_axis = cpma_abs_s8(cmd.upmove);
    if max_axis == 0 return 0.0;

    forward := cast(float32)cast(s32)cmd.forwardmove;
    right := cast(float32)cast(s32)cmd.rightmove;
    up := cast(float32)cast(s32)cmd.upmove;
    total := sqrtf(forward * cast(float32)cast(s32)cmd.forwardmove +
                   right * cast(float32)cast(s32)cmd.rightmove +
                   up * cast(float32)cast(s32)cmd.upmove);
    return cast(float32)ctx.test.ps.speed * cast(float32)max_axis / (127.0 * total);
}

cpma_wishvel :: (ctx: *CPMA_Context, cmd: *CPMA_Test_Usercmd, wishspeed: *float32, wishdir: *CPMA_Vec3) -> bool {
    scale := cpma_cmd_scale(ctx, cmd);
    fmove := cast(float32)cast(s32)ctx.test.cmd.forwardmove;
    smove := cast(float32)cast(s32)ctx.test.cmd.rightmove;
    if scale == 0.0 {
        wishdir.* = .[0.0, 0.0, 0.0];
        wishspeed.* = 0.0;
        return false;
    }
    for i: 0..2 wishdir.*[i] = ctx.pml.forward[i] * fmove + ctx.pml.right[i] * smove;
    wishdir.*[2] += cast(float32)cast(s32)ctx.test.cmd.upmove;
    wishspeed.* = scale * cpma_vector_normalize(wishdir);
    return true;
}

cpma_set_movement_dir :: (ctx: *CPMA_Context) {
    test := ctx.test;
    forward := test.cmd.forwardmove;
    right := test.cmd.rightmove;
    if forward != 0 || right != 0 {
        if right == 0 && forward > 0 test.ps.movementDir = 0;
        else if right < 0 && forward > 0 test.ps.movementDir = 1;
        else if right < 0 && forward == 0 test.ps.movementDir = 2;
        else if right < 0 && forward < 0 test.ps.movementDir = 3;
        else if right == 0 && forward < 0 test.ps.movementDir = 4;
        else if right > 0 && forward < 0 test.ps.movementDir = 5;
        else if right > 0 && forward == 0 test.ps.movementDir = 6;
        else if right > 0 && forward > 0 test.ps.movementDir = 7;
    } else if test.ps.movementDir == 2 {
        test.ps.movementDir = 1;
    } else if test.ps.movementDir == 6 {
        test.ps.movementDir = 7;
    }
}

cpma_check_jump :: (ctx: *CPMA_Context) -> bool {
    test := ctx.test;
    ps := *test.ps;
    ramp_jump := cast(s32)test.classPhysics[CPMA_CLASS_RAMP_JUMP];
    double_jump := cast(s32)test.classPhysics[CPMA_CLASS_DOUBLE_JUMP];
    if (ps.pm_flags & CPMA_PMF_RESPAWNED) != 0 || test.cmd.upmove < 10 return false;
    if ps.pm_flags & CPMA_PMF_JUMP_HELD {
        test.cmd.upmove = 0;
        return false;
    }

    ctx.pml.groundPlane = false;
    ctx.pml.walking = false;
    ps.pm_flags |= CPMA_PMF_JUMP_HELD;
    ps.groundEntityNum = CPMA_ENTITYNUM_NONE;
    if test.ntfEnabled != 0 {
        ramp_jump = test.ntfRampJump;
        double_jump = test.ntfDoubleJump;
    }
    if ramp_jump != 0 && ps.velocity[2] > 0.0 ps.velocity[2] += 275.0;
    else ps.velocity[2] = 275.0;

    if double_jump != 0 {
        if ps.stats[CPMA_STAT_JUMPTIME] > 0 {
            ps.velocity[2] += 105.0;
            ps.stats[CPMA_STAT_DJUMPED] = 1;
        }
        ps.stats[CPMA_STAT_JUMPTIME] = 400;
        if test.physicsMode == 3 ps.stats[CPMA_STAT_JUMPTIME] = 152;
    }
    if test.cmd.forwardmove >= 0 ps.pm_flags &= cast(s32)~CPMA_PMF_BACKWARDS_JUMP;
    else ps.pm_flags |= CPMA_PMF_BACKWARDS_JUMP;
    return true;
}

cpma_check_water_jump :: (ctx: *CPMA_Context) -> bool {
    test := ctx.test;
    ps := *test.ps;
    if ps.pm_time != 0 || test.waterlevel != 2 return false;
    flatforward := ctx.pml.forward;
    flatforward[2] = 0.0;
    cpma_vector_normalize(*flatforward);
    spot: CPMA_Vec3;
    for i: 0..2 spot[i] = ps.origin[i] + 30.0 * flatforward[i];
    spot[2] += 4.0;
    contents := cpma_point_contents(ctx, spot, ps.clientNum);
    if !(contents & CPMA_CONTENTS_SOLID) return false;
    spot[2] += 16.0;
    contents = cpma_point_contents(ctx, spot, ps.clientNum);
    if contents != 0 return false;

    ps.velocity[0] = ctx.pml.forward[0] * 200.0;
    ps.velocity[1] = ctx.pml.forward[1] * 200.0;
    ps.velocity[2] = 350.0;
    ps.pm_flags |= CPMA_PMF_TIME_WATERJUMP;
    ps.pm_time = 2000;
    return true;
}

cpma_water_jump_move :: (ctx: *CPMA_Context) {
    ps := *ctx.test.ps;
    cpma_step_slide_move(ctx, true);
    ps.velocity[2] -= cast(float32)ps.gravity * ctx.pml.frametime;
    if ps.velocity[2] < 0.0 {
        ps.pm_flags &= cast(s32)~(CPMA_PMF_TIME_WATERJUMP | CPMA_PMF_TIME_LAND | CPMA_PMF_TIME_KNOCKBACK);
        ps.pm_time = 0;
    }
}

cpma_water_move :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    if cpma_check_water_jump(ctx) {
        cpma_water_jump_move(ctx);
        return;
    }
    cpma_friction(ctx);
    wishdir: CPMA_Vec3;
    wishspeed: float32;
    if !cpma_wishvel(ctx, *test.cmd, *wishspeed, *wishdir) {
        wishdir = .[0.0, 0.0, -60.0];
        wishspeed = cpma_vector_normalize(*wishdir);
    }
    water_scale := test.classPhysics[CPMA_CLASS_DEEP_WATER_SCALE];
    if test.waterlevel == 1 water_scale = test.classPhysics[CPMA_CLASS_SHALLOW_WATER_SCALE];
    cap := cast(float32)ps.speed * water_scale;
    if wishspeed > cap wishspeed = cap;
    cpma_accelerate(ctx, wishdir, wishspeed, test.classPhysics[CPMA_CLASS_WATER_ACCELERATE]);
    if ctx.pml.groundPlane && cpma_dot(ps.velocity, ctx.pml.groundTrace.plane.normal) < 0.0 {
        cpma_clip_velocity(ps.velocity, ctx.pml.groundTrace.plane.normal, *ps.velocity, CPMA_OVERCLIP);
    }
    cpma_slide_move(ctx, false);
}

cpma_fly_move :: (ctx: *CPMA_Context) {
    cpma_friction(ctx);
    wishdir: CPMA_Vec3;
    wishspeed: float32;
    cpma_wishvel(ctx, *ctx.test.cmd, *wishspeed, *wishdir);
    cpma_accelerate(ctx, wishdir, wishspeed, 8.0);
    cpma_step_slide_move(ctx, false);
}

cpma_air_control :: (ctx: *CPMA_Context, wishdir: CPMA_Vec3, wishspeed: float32, frametime: float32) {
    ps := *ctx.test.ps;
    if (ps.movementDir != 0 && ps.movementDir != 4) || wishspeed == 0.0 return;
    zspeed := ps.velocity[2];
    ps.velocity[2] = 0.0;
    speed := cpma_vector_normalize(*ps.velocity);
    dot := cpma_dot(ps.velocity, wishdir);
    if dot > 0.0 {
        k := 32.0 * ctx.test.classPhysics[CPMA_CLASS_AIR_CONTROL] * dot * dot * frametime;
        ps.velocity[0] = ps.velocity[0] * speed + wishdir[0] * k;
        ps.velocity[1] = ps.velocity[1] * speed + wishdir[1] * k;
        cpma_vector_normalize(*ps.velocity);
    }
    ps.velocity[0] *= speed;
    ps.velocity[1] *= speed;
    ps.velocity[2] = zspeed;
}

cpma_air_move :: (ctx: *CPMA_Context) {
    test := ctx.test;
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

    speed: float32 = 0.0;
    maxspeed: float32 = 0.0;
    if test.ntfEnabled != 0 {
        speed = sqrtf(ps.velocity[0] * ps.velocity[0] + ps.velocity[1] * ps.velocity[1]);
        maxspeed = 2.0 * cast(float32)ps.speed;
        if ps.powerups[CPMA_PW_REDFLAG] != 0 || ps.powerups[CPMA_PW_BLUEFLAG] != 0 maxspeed *= 0.75;
    } else if (test.arenaFlags & CPMA_ARENAFLAG_CLASSIC_CTF_SPEED) != 0 &&
              (ps.powerups[CPMA_PW_REDFLAG] != 0 || ps.powerups[CPMA_PW_BLUEFLAG] != 0) {
        speed = sqrtf(ps.velocity[0] * ps.velocity[0] + ps.velocity[1] * ps.velocity[1]);
        maxspeed = cast(float32)ps.speed * test.classPhysics[CPMA_CLASS_FLAG_SPEED_SCALE];
    }
    if speed > maxspeed {
        ratio := (speed - maxspeed) / maxspeed;
        ratio *= ratio;
        scale := 1.0 - ratio * ctx.pml.frametime;
        ps.velocity[0] *= scale;
        ps.velocity[1] *= scale;
    }
    if ctx.pml.groundPlane cpma_clip_velocity(ps.velocity, ctx.pml.groundTrace.plane.normal, *ps.velocity, CPMA_OVERCLIP);
    cpma_step_slide_move(ctx, true);
}

cpma_grapple_move :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    grapple_speed := test.serverGrappleSpeed;
    if grapple_speed == 0 grapple_speed = 800;
    if test.ntfEnabled != 0 grapple_speed = cast(s32)test.ntfGrappleSpeed;
    if grapple_speed < 100 grapple_speed = 100;
    if grapple_speed > 2000 grapple_speed = 2000;
    target: CPMA_Vec3;
    velocity: CPMA_Vec3;
    for i: 0..2 {
        target[i] = ps.grapplePoint[i] - 16.0 * ctx.pml.forward[i];
        velocity[i] = target[i] - ps.origin[i];
    }
    length := cpma_vector_length(velocity);
    cpma_vector_normalize(*velocity);
    if length <= 100.0 {
        scale := 10.0 * length;
        for i: 0..2 velocity[i] *= scale;
    } else {
        for i: 0..2 velocity[i] *= cast(float32)grapple_speed;
    }
    ps.velocity = velocity;
    ctx.pml.groundPlane = false;
}

cpma_walk_move :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    if test.waterlevel > 2 && cpma_dot(ctx.pml.forward, ctx.pml.groundTrace.plane.normal) > 0.0 {
        cpma_water_move(ctx);
        return;
    }
    if cpma_check_jump(ctx) {
        if test.waterlevel > 1 cpma_water_move(ctx);
        else cpma_air_move(ctx);
        return;
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
    if test.waterlevel != 0 {
        depth := cast(float32)test.waterlevel / 3.0;
        water_target := test.classPhysics[CPMA_CLASS_DEEP_WATER_SCALE];
        if test.waterlevel == 1 water_target = test.classPhysics[CPMA_CLASS_SHALLOW_WATER_SCALE];
        water_scale := 1.0 - (1.0 - water_target) * depth;
        if wishspeed > cast(float32)ps.speed * water_scale wishspeed = cast(float32)ps.speed * water_scale;
    }

    accelerate := test.classPhysics[CPMA_CLASS_GROUND_ACCELERATE];
    if (ctx.pml.groundTrace.surfaceFlags & CPMA_SURF_SLICK) != 0 ||
       (ps.pm_flags & CPMA_PMF_TIME_KNOCKBACK) != 0 accelerate = 1.0;
    cpma_accelerate(ctx, wishdir, wishspeed, accelerate);
    if (ctx.pml.groundTrace.surfaceFlags & CPMA_SURF_SLICK) != 0 ||
       (ps.pm_flags & CPMA_PMF_TIME_KNOCKBACK) != 0 {
        ps.velocity[2] -= cast(float32)ps.gravity * ctx.pml.frametime;
    }
    cpma_clip_velocity(ps.velocity, ctx.pml.groundTrace.plane.normal, *ps.velocity, CPMA_OVERCLIP);
    if ps.velocity[0] == 0.0 && ps.velocity[1] == 0.0 return;
    cpma_step_slide_move(ctx, false);
}

cpma_noclip_move :: (ctx: *CPMA_Context) {
    ps := *ctx.test.ps;
    ps.viewheight = 26;
    speed := cpma_vector_length(ps.velocity);
    if speed < 1.0 {
        ps.velocity = .[0.0, 0.0, 0.0];
    } else {
        control := speed;
        if control < 100.0 control = 100.0;
        drop := 10.0 * ctx.pml.frametime * control;
        newspeed := speed - drop;
        if newspeed < 0.0 newspeed = 0.0;
        newspeed /= speed;
        ps.velocity[0] *= newspeed;
        ps.velocity[1] *= newspeed;
        ps.velocity[2] *= newspeed;
    }
    wishdir: CPMA_Vec3;
    wishspeed: float32;
    cpma_wishvel(ctx, *ctx.test.cmd, *wishspeed, *wishdir);
    cpma_accelerate(ctx, wishdir, wishspeed, 10.0);
    for i: 0..2 ps.origin[i] += ctx.pml.frametime * ps.velocity[i];
}

cpma_dead_move :: (ctx: *CPMA_Context) {
    if !ctx.pml.walking return;
    ps := *ctx.test.ps;
    forward := cpma_vector_length(ps.velocity) - 20.0;
    if forward <= 0.0 {
        ps.velocity = .[0.0, 0.0, 0.0];
    } else {
        cpma_vector_normalize(*ps.velocity);
        ps.velocity[0] *= forward;
        ps.velocity[1] *= forward;
        ps.velocity[2] *= forward;
    }
}

cpma_set_water_level :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    water_mask := CPMA_CONTENTS_WATER | CPMA_CONTENTS_LAVA | CPMA_CONTENTS_SLIME;
    test.waterlevel = 0;
    test.watertype = 0;
    point := ps.origin;
    point[2] += -24.0;
    point[2] += 1.0;
    contents := cpma_point_contents(ctx, point, ps.clientNum);
    test.watertype = contents;
    if !(contents & water_mask) return;

    test.waterlevel = 1;
    point[2] = ps.origin[2];
    contents = cpma_point_contents(ctx, point, ps.clientNum);
    if contents & water_mask {
        test.waterlevel = 2;
        point[2] = ps.origin[2] + cast(float32)ps.viewheight;
        contents = cpma_point_contents(ctx, point, ps.clientNum);
        if contents & water_mask test.waterlevel = 3;
    }
}

cpma_check_duck :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    test.mins[0] = -15.0;
    test.mins[1] = -15.0;
    test.mins[2] = -24.0;
    test.maxs[0] = 15.0;
    test.maxs[1] = 15.0;
    if ps.pm_type == CPMA_PM_DEAD {
        ps.viewheight = -16;
        if !(ps.eFlags & 512) test.maxs[2] = -8.0;
        return;
    }
    if test.cmd.upmove < 0 {
        ps.pm_flags |= CPMA_PMF_DUCKED;
    } else if ps.pm_flags & CPMA_PMF_DUCKED {
        test.maxs[2] = 32.0;
        trace: CPMA_Test_Trace;
        cpma_trace(ctx, *trace, ps.origin, test.mins, test.maxs, ps.origin, ps.clientNum, test.tracemask);
        if trace.allsolid == 0 ps.pm_flags &= cast(s32)~CPMA_PMF_DUCKED;
    }
    if ps.pm_flags & CPMA_PMF_DUCKED {
        test.maxs[2] = 16.0;
        ps.viewheight = 12;
    } else {
        test.maxs[2] = 32.0;
        ps.viewheight = 26;
    }
}

cpma_correct_all_solid :: (ctx: *CPMA_Context, trace: *CPMA_Test_Trace) -> bool {
    test := ctx.test;
    ps := *test.ps;
    for i: -1..1 {
        for j: -1..1 {
            for k: -1..1 {
                point: CPMA_Vec3;
                point[0] = ps.origin[0] + cast(float32)i;
                point[1] = ps.origin[0] + cast(float32)j;
                point[2] = ps.origin[0] + cast(float32)k;
                cpma_trace(ctx, trace, point, test.mins, test.maxs, point, ps.clientNum, test.tracemask);
                if trace.allsolid == 0 {
                    point = ps.origin;
                    point[2] -= 0.25;
                    cpma_trace(ctx, trace, ps.origin, test.mins, test.maxs, point, ps.clientNum, test.tracemask);
                    ctx.pml.groundTrace = trace.*;
                    return true;
                }
            }
        }
    }
    ps.groundEntityNum = CPMA_ENTITYNUM_NONE;
    ctx.pml.groundPlane = false;
    ctx.pml.walking = false;
    return false;
}

cpma_ground_trace_missed :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    if ps.groundEntityNum != CPMA_ENTITYNUM_NONE {
        point := ps.origin;
        point[2] -= 64.0;
        trace: CPMA_Test_Trace;
        cpma_trace(ctx, *trace, ps.origin, test.mins, test.maxs, point, ps.clientNum, test.tracemask);
        if trace.fraction == 1.0 {
            if test.cmd.forwardmove >= 0 ps.pm_flags &= cast(s32)~CPMA_PMF_BACKWARDS_JUMP;
            else ps.pm_flags |= CPMA_PMF_BACKWARDS_JUMP;
        }
    }
    ps.groundEntityNum = CPMA_ENTITYNUM_NONE;
    ctx.pml.groundPlane = false;
    ctx.pml.walking = false;
}

cpma_ground_trace :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    point := ps.origin;
    point[2] -= 0.25;
    trace: CPMA_Test_Trace;
    cpma_trace(ctx, *trace, ps.origin, test.mins, test.maxs, point, ps.clientNum, test.tracemask);
    ctx.pml.groundTrace = trace;
    if trace.allsolid != 0 && !cpma_correct_all_solid(ctx, *trace) return;
    if trace.fraction == 1.0 {
        cpma_ground_trace_missed(ctx);
        return;
    }
    if ps.velocity[2] > 0.0 && cpma_dot(ps.velocity, trace.plane.normal) > 10.0 {
        if test.cmd.forwardmove >= 0 ps.pm_flags &= cast(s32)~CPMA_PMF_BACKWARDS_JUMP;
        else ps.pm_flags |= CPMA_PMF_BACKWARDS_JUMP;
        ps.groundEntityNum = CPMA_ENTITYNUM_NONE;
        ctx.pml.groundPlane = false;
        ctx.pml.walking = false;
        return;
    }
    if trace.plane.normal[2] < 0.7 {
        ps.groundEntityNum = CPMA_ENTITYNUM_NONE;
        ctx.pml.groundPlane = true;
        ctx.pml.walking = false;
        return;
    }
    ctx.pml.groundPlane = true;
    ctx.pml.walking = true;
    if ps.pm_flags & CPMA_PMF_TIME_WATERJUMP {
        ps.pm_flags &= cast(s32)~(CPMA_PMF_TIME_WATERJUMP | CPMA_PMF_TIME_LAND);
        ps.pm_time = 0;
    }
    if ps.groundEntityNum == CPMA_ENTITYNUM_NONE && ctx.pml.previous_velocity[2] < -200.0 {
        ps.pm_flags |= CPMA_PMF_TIME_LAND;
        ps.pm_time = 250;
    }
    ps.groundEntityNum = trace.entityNum;
    cpma_add_touch_ent(test, trace.entityNum);
}

cpma_drop_movement_timers :: (ctx: *CPMA_Context) {
    ps := *ctx.test.ps;
    if ps.pm_time != 0 {
        if ctx.pml.msec >= ps.pm_time {
            ps.pm_flags &= cast(s32)~(CPMA_PMF_TIME_WATERJUMP | CPMA_PMF_TIME_LAND | CPMA_PMF_TIME_KNOCKBACK);
            ps.pm_time = 0;
        } else {
            ps.pm_time -= ctx.pml.msec;
        }
    }
}

cpma_angle_vectors :: (angles: CPMA_Vec3, forward: *CPMA_Vec3, right: *CPMA_Vec3, up: *CPMA_Vec3) {
    degrees_to_radians: float32 = cast(float32) 0.01745329251994329577;
    angle := angles[1] * degrees_to_radians;
    sy := sinf(angle);
    cy := cosf(angle);
    angle = angles[0] * degrees_to_radians;
    sp := sinf(angle);
    cp := cosf(angle);
    angle = angles[2] * degrees_to_radians;
    sr := sinf(angle);
    cr := cosf(angle);

    forward.*[0] = cp * cy;
    forward.*[1] = cp * sy;
    forward.*[2] = -sp;
    right.*[0] = -sr * sp * cy + -cr * -sy;
    right.*[1] = -sr * sp * sy + -cr * cy;
    right.*[2] = -sr * cp;
    up.*[0] = cr * sp * cy + -sr * -sy;
    up.*[1] = cr * sp * sy + -sr * cy;
    up.*[2] = cr * cp;
}

cpma_update_view_angles :: (ps: *CPMA_Test_Playerstate, cmd: *CPMA_Test_Usercmd) {
    if ps.pm_type == CPMA_PM_INTERMISSION || ps.pm_type == CPMA_PM_SPINTERMISSION ||
       (ps.pm_type != CPMA_PM_SPECTATOR && ps.stats[CPMA_STAT_HEALTH] <= 0) ||
       (ps.pm_type != CPMA_PM_SPECTATOR && (ps.pm_flags & CPMA_PMF_FOLLOW) != 0) return;
    for i: 0..2 {
        summed := cmd.angles[i] + ps.delta_angles[i];
        // C/QVM int16 conversion keeps the low 16 bits.
        temp := (.*) cast(*s16) *summed;
        if i == 0 {
            if temp > 16000 {
                ps.delta_angles[i] = 16000 - cmd.angles[i];
                temp = 16000;
            } else if temp < -16000 {
                ps.delta_angles[i] = -16000 - cmd.angles[i];
                temp = -16000;
            }
        }
        ps.viewangles[i] = cast(float32)temp * (360.0 / 65536.0);
    }
}

cpma_pmove_single_physical :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    test.numtouch = 0;
    test.watertype = 0;
    test.waterlevel = 0;
    if ps.stats[CPMA_STAT_HEALTH] <= 0 && test.arenaGameType != 6 test.tracemask &= cast(s32)~CPMA_CONTENTS_BODY;
    if cpma_abs_s8(test.cmd.forwardmove) > 64 || cpma_abs_s8(test.cmd.rightmove) > 64 test.cmd.buttons &= cast(s32)~16;
    if ps.stats[CPMA_STAT_HEALTH] > 0 && !(test.cmd.buttons & 1) ps.pm_flags &= cast(s32)~CPMA_PMF_RESPAWNED;
    if test.cmd.buttons & 2 {
        test.cmd.buttons = 2;
        test.cmd.forwardmove = 0;
        test.cmd.rightmove = 0;
        test.cmd.upmove = 0;
    }

    ctx.pml = .{};
    ctx.pml.msec = test.cmd.serverTime - ps.commandTime;
    if ctx.pml.msec < 1 ctx.pml.msec = 1;
    else if ctx.pml.msec > 200 ctx.pml.msec = 200;
    ps.commandTime = test.cmd.serverTime;
    ctx.pml.previous_origin = ps.origin;
    ctx.pml.previous_velocity = ps.velocity;
    ctx.pml.frametime = cast(float32)ctx.pml.msec * 0.001;
    cpma_angle_vectors(ps.viewangles, *ctx.pml.forward, *ctx.pml.right, *ctx.pml.up);

    if test.cmd.upmove < 10 ps.pm_flags &= cast(s32)~CPMA_PMF_JUMP_HELD;
    if test.cmd.forwardmove < 0 ps.pm_flags |= 16;
    else if test.cmd.forwardmove > 0 || (test.cmd.forwardmove == 0 && test.cmd.rightmove != 0) ps.pm_flags &= cast(s32)~16;
    if ps.pm_type >= CPMA_PM_DEAD {
        test.cmd.forwardmove = 0;
        test.cmd.rightmove = 0;
        test.cmd.upmove = 0;
    }

    if ps.pm_type == CPMA_PM_SPECTATOR {
        cpma_check_duck(ctx);
        cpma_fly_move(ctx);
        cpma_drop_movement_timers(ctx);
        return;
    }
    if ps.pm_type == CPMA_PM_NOCLIP {
        cpma_noclip_move(ctx);
        cpma_drop_movement_timers(ctx);
        return;
    }
    if ps.pm_type == CPMA_PM_INTERMISSION || ps.pm_type == CPMA_PM_SPINTERMISSION return;

    cpma_set_water_level(ctx);
    ctx.pml.previous_waterlevel = test.waterlevel;
    if ps.pm_type == CPMA_PM_FREEZE return;
    cpma_check_duck(ctx);
    cpma_ground_trace(ctx);
    if ps.pm_type == CPMA_PM_DEAD cpma_dead_move(ctx);
    cpma_drop_movement_timers(ctx);

    if ps.stats[CPMA_STAT_JUMPTIME] > 0 ps.stats[CPMA_STAT_JUMPTIME] -= ctx.pml.msec;
    else if ps.stats[CPMA_STAT_DJUMPED] != 0 ps.stats[CPMA_STAT_DJUMPED] = 0;

    if ps.powerups[CPMA_PW_FLIGHT] != 0 cpma_fly_move(ctx);
    else if ps.pm_flags & CPMA_PMF_GRAPPLE_PULL {
        cpma_grapple_move(ctx);
        cpma_air_move(ctx);
    } else if ps.pm_flags & CPMA_PMF_TIME_WATERJUMP cpma_water_jump_move(ctx);
    else if test.waterlevel > 1 cpma_water_move(ctx);
    else if ctx.pml.walking cpma_walk_move(ctx);
    else cpma_air_move(ctx);

    cpma_ground_trace(ctx);
    cpma_set_water_level(ctx);
    test.xyspeed = sqrtf(ps.velocity[0] * ps.velocity[0] + ps.velocity[1] * ps.velocity[1]);
}

cpma_pmove :: (ctx: *CPMA_Context) {
    test := ctx.test;
    ps := *test.ps;
    final_time := test.cmd.serverTime;
    test.mins = .[-15.0, -15.0, -24.0];
    test.maxs = .[15.0, 15.0, 32.0];
    if final_time < ps.commandTime || ps.commandTime == 0 return;
    if final_time > ps.commandTime + 1000 ps.commandTime = final_time;
    ps.pmove_framecount = (ps.pmove_framecount + 1) & 63;
    cpma_update_view_angles(ps, *test.cmd);
    cpma_pmove_single_physical(ctx);
    if ps.pm_flags & CPMA_PMF_JUMP_HELD test.cmd.upmove = 20;
}
