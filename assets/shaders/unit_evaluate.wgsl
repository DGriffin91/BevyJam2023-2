#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/sampling.wgsl" as sampling
#import "shaders/common.wgsl" as com





@group(0) @binding(101) var data_texture: texture_2d<u32>;
@group(0) @binding(102) var<uniform> command: com::UnitCommand;
@group(0) @binding(103) var prev_attack: texture_2d<u32>;
@group(0) @binding(106) var large_unit_tex: texture_2d<u32>;

struct FragmentOutput {
    @location(0) unit_data: vec4<u32>,
    @location(1) attack_data: vec4<u32>,
}

@fragment
fn fragment(in: FullscreenVertexOutput) -> FragmentOutput {
    var out: FragmentOutput;

    let frag_coord = in.position.xy;
    let ufrag_coord = vec2<u32>(frag_coord);
    let ifrag_coord = vec2<i32>(ufrag_coord);

    let system_index = ufrag_coord.y;

    out.attack_data = textureLoad(prev_attack, ifrag_coord, 0);

    let data = textureLoad(data_texture, ifrag_coord, 0);
    var unit = com::unpack_unit(data);
    
    let unit_stats = com::get_unit_stats(large_unit_tex, #{LARGE_UNITS_DATA_WIDTH}u, unit.team);

    if unit.progress >= 1.0 {
        unit.mode = com::UNIT_MODE_IDLE;
        unit.attacking_hydra = 0u;
    }

    
    var step_mult = 0.0;
    if unit.mode == com::UNIT_MODE_MOVEING {
        step_mult = unit_stats.move_rate;
    } else if unit.mode == com::UNIT_MODE_ATTACK || unit.mode == com::UNIT_MODE_ATTACK_HYDRA {
        step_mult = unit_stats.attack_rate;
    } else if unit.mode == com::UNIT_MODE_ATTACK_HYDRA {
        step_mult = unit_stats.attack_rate;
    }

    unit.progress += globals.delta_time * step_mult;

    // if there is living unit in this cell check if it moved to another cell last frame
    if unit.health != 0u {
        for (var x = -1; x <= 1; x += 1) {
            for (var y = -1; y <= 1; y += 1) {
                let offset = vec2(x, y);

                let read_coord = ifrag_coord + offset;

                let other_data = textureLoad(data_texture, read_coord, 0);
                let other_unit = com::unpack_unit(other_data);

                // If we're the same id and we're in the spot this unit came from, delete this one as it has moved
                if other_unit.id == unit.id && all(read_coord == ifrag_coord + other_unit.step_dir) {
                    out.unit_data = vec4(0u);
                    out.attack_data = vec4(0u);
                    return out;
                }
            }
        }
    }    

    // --- Spawn around large ---
    var large_rng = sampling::hash_noise(ufrag_coord, globals.frame_count + 45245u);
    var team_rng = u32(round(sampling::hash_noise(ufrag_coord, globals.frame_count + 647132u))) + 1u;
    let large_unit_frag_coord = vec2(i32(large_rng * #{LARGE_UNITS_DATA_WIDTH}.0), i32(team_rng - 1u));
    let large_data = textureLoad(large_unit_tex, large_unit_frag_coord, 0);
    var large_unit = com::unpack_large_unit(large_data, vec2<u32>(large_unit_frag_coord));

    let spawn_unit_stats = com::get_unit_stats(large_unit_tex, #{LARGE_UNITS_DATA_WIDTH}u, team_rng);

    let rng = sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 34121u);

    if large_unit.health > 0u && distance(large_unit.pos.xy, frag_coord.xy) < spawn_unit_stats.spawn_radius {
        if unit.health == 0u && distance(rng, 0.5) < spawn_unit_stats.spawn_rate * globals.delta_time { 
            unit = com::unpack_unit(vec4(0u));
            unit.health = 255u;
            unit.id = u32(sampling::hash_noise(ufrag_coord, globals.frame_count + 96421u) * f32(sampling::U32_MAX - 10u)) + 5u;
            unit.dest = ufrag_coord;
            unit.team = team_rng;
            out.unit_data = com::pack_unit(unit);
            out.attack_data = vec4(0u);
            return out;
        }
    }
    

    // -----------------------

    // If there is no unit here, return none
    if unit.health == 0u || unit.id <= 4u {
        out.unit_data = vec4(0u);
        out.attack_data = vec4(0u);
        return out;
    }
    if unit.team == 1u {
        if command.command > 0u && command.unit_group == 1u {
            unit.dest = command.dest;
            if unit.mode != com::UNIT_MODE_MOVEING {
                unit.mode = com::UNIT_MODE_MOVE;
                unit.progress = 0.0;
            }
        }
    } else if unit.team == 2u {
        var t2upgrades = textureLoad(large_unit_tex, vec2(#{LARGE_UNITS_DATA_WIDTH}u + 1u, 1u), 0);
        if t2upgrades.y > 0u && t2upgrades.y % 10u == 0u {
            let large_data = textureLoad(large_unit_tex, vec2(0), 0);
            var large_unit = com::unpack_large_unit(large_data, vec2<u32>(large_unit_frag_coord));
            unit.dest = vec2<u32>(large_unit.pos);
        }
    }

        

    
    if unit.health > 0u && 
       // unit.mode == com::UNIT_MODE_IDLE && not working
       large_unit.health > 0u && 
       large_unit.team != unit.team &&
       distance(large_unit.pos, vec2<f32>(ufrag_coord)) < #{ATTACK_RADIUS}.0 - 1.0 {
        unit.attacking_hydra = u32(large_unit_frag_coord.x) + 1u;
        unit.mode = com::UNIT_MODE_ATTACK_HYDRA;
        unit.progress = 0.0;
    }
    
    var clear_attack_data = true;
    if unit.mode == com::UNIT_MODE_IDLE {
        // First check if the unit we were shooting at is still there and use that one first otherwise find a new one
        let prev_attack_data = textureLoad(prev_attack, ifrag_coord, 0);
        let prev_attack_vector = vec2<i32>(prev_attack_data.xy) - #{ATTACK_RADIUS};
        let prev_attack_damage = prev_attack_data.z;

        var other_data = textureLoad(data_texture, ifrag_coord + prev_attack_vector, 0);
        var other_unit = com::unpack_unit(other_data);
        if other_unit.id != unit.id && other_unit.health != 0u && other_unit.team > 0u && unit.team != other_unit.team {
            unit.mode = com::UNIT_MODE_ATTACK;
            unit.progress = 0.0;
            clear_attack_data = false;
        } else {
            let noise = vec2(
                sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 4563u),
                sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 2564u),
            ) * 2.0 - 1.0;
            let attack_offset = clamp(vec2<i32>(noise * #{ATTACK_RADIUS}.0), vec2(-#{ATTACK_RADIUS}), vec2(#{ATTACK_RADIUS}));
            let attack_coord = attack_offset + ifrag_coord;

            other_data = textureLoad(data_texture, attack_coord, 0);
            other_unit = com::unpack_unit(other_data);
            let attack_damage = 1u + u32(unit_stats.attack_mult);

            if other_unit.id != unit.id && other_unit.health > 0u && other_unit.team > 0u && unit.team != other_unit.team {
                out.attack_data = vec4(vec2<u32>(attack_offset + #{ATTACK_RADIUS}), attack_damage, 0u);
                unit.mode = com::UNIT_MODE_ATTACK;
                unit.progress = 0.0;
                clear_attack_data = false;
            }
        }
    }
    if unit.mode != com::UNIT_MODE_ATTACK && clear_attack_data {
        out.attack_data = vec4(0u);
    }


    if unit.mode == com::UNIT_MODE_IDLE || (unit.mode == com::UNIT_MODE_MOVE && !all(ufrag_coord == unit.dest)) {
        let f_to_dest = vec2<f32>(unit.dest) - vec2<f32>(ufrag_coord);

        var dir_noise = vec2(0.0);
        dir_noise = vec2(
            sampling::hash_noise(ufrag_coord, globals.frame_count + 74856u),
            sampling::hash_noise(ufrag_coord, globals.frame_count + 36422u),
        ) * 2.0 - 1.0;
        dir_noise *= length(f_to_dest);

        let step_dir = com::sign2i(vec2<i32>(f_to_dest + dir_noise));
        if !all(step_dir == vec2(0)) {
            unit.step_dir = step_dir;
            unit.mode = com::UNIT_MODE_MOVE;
            out.attack_data = vec4(0u);
            unit.progress = 0.0;
        }
    }

    
    out.unit_data = com::pack_unit(unit);
    return out;
}

