#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/sampling.wgsl" as sampling
#import "shaders/common.wgsl" as com



@group(0) @binding(101) var data_texture: texture_2d<u32>;
@group(0) @binding(102) var<uniform> command: com::UnitCommand;
@group(0) @binding(103) var attack_texture: texture_2d<u32>;
@group(0) @binding(106) var large_unit_tex: texture_2d<u32>;
@group(0) @binding(108) var minimap_sm_texture: texture_2d<u32>;
@group(0) @binding(109) var minimap_sm3_texture: texture_2d<u32>;


fn get_minimap_sum() -> vec4<u32> {
    var sum = vec4(0u);

    for (var x = 0; x < 2; x += 1) {
        for (var y = 0; y < 2; y += 1) {
            let offset = vec2(x, y);
            let data = textureLoad(minimap_sm3_texture, offset, 0);
            sum += data;
        }
    }

    return sum;
}


@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<u32> {
    let frag_coord = in.position.xy;
    let ufrag_coord = vec2<u32>(frag_coord);
    let ifrag_coord = vec2<i32>(ufrag_coord);
    

    if ufrag_coord.x >= #{LARGE_UNITS_DATA_WIDTH}u {
        var out = vec4(0u);
        // Process players
        let team = select(0u, 1u, ufrag_coord.y == 1u);
        let other_team = select(1u, 0u, ufrag_coord.y == 1u);
        var prev_tracker = textureLoad(large_unit_tex, vec2(#{LARGE_UNITS_DATA_WIDTH}u, ufrag_coord.y), 0);
        var prev_upgrade = textureLoad(large_unit_tex, vec2(#{LARGE_UNITS_DATA_WIDTH}u + 1u, ufrag_coord.y), 0);
        if ufrag_coord.x == #{LARGE_UNITS_DATA_WIDTH}u + 1u {
            out = prev_upgrade;
        }
        var credits = prev_tracker.y;
        let upgrade_request_movment = (command.upgrade_request & 1u) > 0u || team == 1u; // AI just auto upgrades everything
        let upgrade_request_attack = (command.upgrade_request & 2u) > 0u || team == 1u;
        let upgrade_request_spawn = (command.upgrade_request & 4u) > 0u || team == 1u;
        let upgrade_movment_cost = 100u * u32(sqrt(f32(prev_upgrade.x + 1u)));
        let upgrade_attack_cost = 100u * u32(sqrt(f32(prev_upgrade.y + 1u)));
        let upgrade_spawn_cost = 100u * u32(sqrt(f32(prev_upgrade.z + 1u)));
        if upgrade_request_attack && credits > upgrade_attack_cost {
            credits -= upgrade_attack_cost;
            if ufrag_coord.x == #{LARGE_UNITS_DATA_WIDTH}u + 1u {
                out.y += 1u;
            }
        }
        if upgrade_request_spawn && credits > upgrade_spawn_cost {
            credits -= upgrade_spawn_cost;
            if ufrag_coord.x == #{LARGE_UNITS_DATA_WIDTH}u + 1u {
                out.z += 1u;
            }
        }
        // This is last so AI upgrades spawn and movment first
        if upgrade_request_movment && credits > upgrade_movment_cost {
            credits -= upgrade_movment_cost;
            if ufrag_coord.x == #{LARGE_UNITS_DATA_WIDTH}u + 1u {
                out.x += 1u;
            }
        }
        if ufrag_coord.x == #{LARGE_UNITS_DATA_WIDTH}u {
            let minimap_sum = get_minimap_sum(); 
            // Died tracker
            out.x = minimap_sum[team + 2u] + prev_tracker.x;

            // Credits tracker
            out.y = minimap_sum[other_team + 2u] * 3u + credits; 
            
        } 
        return out;
    }

    let system_index = ufrag_coord.y;

    var out = vec4(0u);

    let data = textureLoad(large_unit_tex, ifrag_coord, 0);
    var unit = com::unpack_large_unit(data, ufrag_coord);
    let unit_stats = com::get_unit_stats(large_unit_tex, #{LARGE_UNITS_DATA_WIDTH}u, unit.team);
    

    // --- Random spawn ---
    let rng = sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 34121u);
    // if unit.health == 0u && distance(rng, 0.5) < 0.001 * globals.delta_time {
    if unit.health == 0u && ufrag_coord.x == 0u && globals.frame_count < 5000u {
        unit = com::unpack_large_unit(vec4(0u), ufrag_coord);
        unit.health = com::HYDRA_INIT_HEALTH;
        var spawn = vec2(
            sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 43567u),
            sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 56423u),
        );
        spawn.x *= 0.25;
        spawn.x = select(spawn.x, spawn.x + 0.75, unit.team == 2u);
        spawn *= vec2(#{UNITS_DATA_WIDTH}.0, #{UNITS_DATA_HEIGHT}.0);
        unit.pos = select(vec2(256.0, 200.0), vec2(256.0, 300.0), unit.team == 2u);
        unit.dest = unit.pos;
        return com::pack_large_unit(unit);
    }

    if command.command > 0u && unit.health > 0u && unit.team == 1u {
        unit.dest = vec2<f32>(command.dest);
        if unit.mode != com::UNIT_MODE_MOVEING {
            unit.mode = com::UNIT_MODE_MOVEING;
            unit.progress = 0.0;
        }
    }

    if unit.mode == com::UNIT_MODE_MOVEING {
        // Will look funny at 1000FPS
        if distance(unit.dest, unit.pos) > 0.1 {
            unit.pos += clamp(normalize(unit.dest - unit.pos), vec2(-1.0), vec2(1.0)) * unit_stats.large_move_rate * globals.delta_time;
        } else {
            unit.mode = com::UNIT_MODE_IDLE;
        }
    }

    // See if there's any other large units in close proximity and if so move away a bit
    var other_rng = sampling::hash_noise(ufrag_coord, globals.frame_count + 45245u);
    let other_unit_frag_coord = vec2(i32(other_rng * #{LARGE_UNITS_DATA_WIDTH}.0), ifrag_coord.y);
    let other_data = textureLoad(large_unit_tex, other_unit_frag_coord, 0);
    var other_unit = com::unpack_large_unit(other_data, vec2<u32>(other_unit_frag_coord));
    if unit.mode == com::UNIT_MODE_IDLE {
        if other_unit.health > 0u && other_unit_frag_coord.x != ifrag_coord.x && distance(other_unit.pos, unit.pos) < com::LARGE_UNIT_SIZE {
            var roam_rng = vec2(
                sampling::hash_noise(ufrag_coord, globals.frame_count + 67821u),
                sampling::hash_noise(ufrag_coord, globals.frame_count + 15348u),
            ) * 2.0 - 1.0;
            unit.dest += roam_rng * com::LARGE_UNIT_SIZE;
            unit.mode = com::UNIT_MODE_MOVEING;
        }
    }

    if unit.mode == com::UNIT_MODE_MOVEING {
        // TODO optimize 
        let step_dir = com::sign2i(vec2<i32>(unit.dest - unit.pos));
        unit.dir_index = select(unit.dir_index, 0u, all(step_dir == vec2( 1,  0)));
        unit.dir_index = select(unit.dir_index, 1u, all(step_dir == vec2( 1, -1)));
        unit.dir_index = select(unit.dir_index, 2u, all(step_dir == vec2( 0, -1)));
        unit.dir_index = select(unit.dir_index, 3u, all(step_dir == vec2(-1, -1)));
        unit.dir_index = select(unit.dir_index, 4u, all(step_dir == vec2(-1,  0)));
        unit.dir_index = select(unit.dir_index, 5u, all(step_dir == vec2(-1,  1)));
        unit.dir_index = select(unit.dir_index, 6u, all(step_dir == vec2( 0,  1)));
        unit.dir_index = select(unit.dir_index, 7u, all(step_dir == vec2( 1,  1)));
    }

    
    let radius = #{ATTACK_RADIUS};
    // Check if a unit attacked us
    for (var x = -radius; x <= radius; x += 1) {
        for (var y = -radius; y <= radius; y += 1) {
            let offset = vec2(x, y);
            let read_coord = vec2<i32>(unit.pos) + offset;

            let other_data = textureLoad(data_texture, read_coord, 0);
            let other_unit = com::unpack_unit(other_data);
            let attack_damage = 1u;

            if attack_damage > 0u && other_unit.attacking_hydra > 0u && 
               other_unit.attacking_hydra - 1u == ufrag_coord.x && other_unit.team != unit.team &&
               other_unit.progress > 0.9
               
               {
                unit.health -= attack_damage;
                if unit.health == 0u {
                    var dead_unit = com::unpack_large_unit(vec4(0u), ufrag_coord);
                    return com::pack_large_unit(dead_unit);
                }
            }
        }
    }

    return com::pack_large_unit(unit);
}

