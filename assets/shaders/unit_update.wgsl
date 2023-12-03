#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/sampling.wgsl" as sampling
#import "shaders/unit_evaluate.wgsl"::{UnitCommand, unpack_unit, pack_unit}



@group(0) @binding(101) var data_texture: texture_2d<u32>;
@group(0) @binding(102) var<uniform> command: UnitCommand;


@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<u32> {
    let frag_coord = in.position.xy;
    let ufrag_coord = vec2<u32>(frag_coord);
    let ifrag_coord = vec2<i32>(ufrag_coord);

    let system_index = ufrag_coord.y;
    
    let data = textureLoad(data_texture, ifrag_coord, 0);
    let unit = unpack_unit(data);

    // if there is not living unit in this cell, we can allow another unit to take this spot
    if unit.health == 0u {
        // Check to see if any of the surrounding tiles want to move into this one and pick one
        for (var x = -1; x <= 1; x += 1) {
            for (var y = -1; y <= 1; y += 1) {
                let offset = vec2(x, y);

                let read_coord = ifrag_coord + offset;

                let other_data = textureLoad(data_texture, read_coord, 0);
                let other_unit = unpack_unit(other_data);
                if other_unit.health > 0u && all(read_coord + other_unit.step_dir == ifrag_coord) {
                    return other_data;
                }
            }
        }
    }

    return pack_unit(unit);
}

