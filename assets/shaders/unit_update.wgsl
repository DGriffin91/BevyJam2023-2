#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/sampling.wgsl" as sampling
#import "shaders/common.wgsl" as com



@group(0) @binding(101) var data_texture: texture_2d<u32>;
@group(0) @binding(102) var<uniform> command: com::UnitCommand;
@group(0) @binding(103) var attack_texture: texture_2d<u32>;


@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<u32> {
    let frag_coord = in.position.xy;
    let ufrag_coord = vec2<u32>(frag_coord);
    let ifrag_coord = vec2<i32>(ufrag_coord);

    let system_index = ufrag_coord.y;
    
    let data = textureLoad(data_texture, ifrag_coord, 0);
    var unit = com::unpack_unit(data);

    let shuffle_x = max(i32(round(sampling::hash_noise(ufrag_coord, globals.frame_count + 83746u) * 3.0)), 0);
    let shuffle_y = max(i32(round(sampling::hash_noise(ufrag_coord, globals.frame_count + 12339u) * 3.0)), 0);

    // if there is not living unit in this cell, we can allow another unit to take this spot
    if unit.health == 0u {
        // Check to see if any of the surrounding tiles want to move into this one and pick one
        for (var x = 0; x < 3; x += 1) {
            for (var y = 0; y < 3; y += 1) {
                let offset = vec2(
                    (x + shuffle_x) % 3 - 1, 
                    (y + shuffle_y) % 3 - 1,
                );
                if all(offset == vec2(0)) {
                    continue;
                }

                let read_coord = ifrag_coord + offset;

                let other_data = textureLoad(data_texture, read_coord, 0);
                var other_unit = com::unpack_unit(other_data);
                if other_unit.mode == com::UNIT_MODE_MOVE && other_unit.health > 0u && all(read_coord + other_unit.step_dir == ifrag_coord) && other_unit.progress == 0.0 {
                    other_unit.mode = com::UNIT_MODE_MOVEING;
                    return com::pack_unit(other_unit);
                }
            }
        }
    } else {
        let radius = #{ATTACK_RADIUS};
        // Check if a unit attacked us
        for (var x = -radius; x <= radius; x += 1) {
            for (var y = -radius; y <= radius; y += 1) {
                let offset = vec2(x, y);
                if all(offset == vec2(0, 0)) {
                    continue;
                }
                let read_coord = ifrag_coord + offset;
                let attack_data = textureLoad(attack_texture, read_coord, 0);
                let attack_vector = vec2<i32>(attack_data.xy) - radius;
                let attack_damage = attack_data.z;

                // check team?
                if attack_damage > 0u && all(read_coord + attack_vector == ifrag_coord) {
                    var health = i32(unit.health) - i32(attack_damage);
                    unit.health = u32(max(health, 0));
                    if unit.health == 0u {
                        var dead_unit = com::unpack_unit(vec4(0u));
                        dead_unit.id = unit.team;
                        return com::pack_unit(dead_unit);
                    }
                }
            }
        }
    }


    return com::pack_unit(unit);
}

