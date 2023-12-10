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
@group(0) @binding(107) var minimap_sm_texture: texture_2d<u32>;
@group(0) @binding(108) var minimap_sm3_texture: texture_2d<u32>;


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
        let team = select(1u, 2u, ufrag_coord.y == 1u);
        if ufrag_coord.x == #{LARGE_UNITS_DATA_WIDTH}u {
            let prev = textureLoad(large_unit_tex, ifrag_coord, 0);
            let minimap_sum = get_minimap_sum();
            out.x = minimap_sum.z + prev.x;
            out.y = minimap_sum.w + prev.y;
            // Kill/Death Tracker / Econ
            //let kills = minimap_sum[team - 1u]
        } else {
            // Extra fragment

        }
        return out;
    }

    let system_index = ufrag_coord.y;

    var out = vec4(0u);

    let data = textureLoad(large_unit_tex, ifrag_coord, 0);
    var unit = com::unpack_large_unit(data, ufrag_coord);
    

    // --- Random spawn ---
    let rng = sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 34121u);
    if unit.health == 0u && distance(rng, 0.5) < 0.001 * globals.delta_time {
        unit = com::unpack_large_unit(vec4(0u), ufrag_coord);
        unit.health = 255u;
        var spawn = vec2(
            sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 43567u),
            sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 56423u),
        );
        spawn.x *= 0.25;
        spawn.x = select(spawn.x, spawn.x + 0.75, unit.team == 2u);
        spawn *= vec2(#{UNITS_DATA_WIDTH}.0, #{UNITS_DATA_HEIGHT}.0);
        unit.pos = vec2(2.0);
        unit.dest = vec2(2.0);
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
            unit.pos += clamp(normalize(unit.dest - unit.pos), vec2(-1.0), vec2(1.0)) * com::LARGE_SPEED_MOVE * globals.delta_time;
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

    return com::pack_large_unit(unit);
}

