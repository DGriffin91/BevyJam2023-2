#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/sampling.wgsl" as sampling
#import "shaders/common.wgsl" as com



@group(0) @binding(101) var data_texture: texture_2d<u32>;
@group(0) @binding(103) var attack_texture: texture_2d<u32>;


@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<u32> {
    let frag_coord = in.position.xy;
    let ifrag_coord = vec2<i32>(frag_coord) * #{MINIMAP_SCALE};

    var out = vec4(0u);

    for (var x = 0; x < #{MINIMAP_SCALE}; x += 1) {
        for (var y = 0; y < #{MINIMAP_SCALE}; y += 1) {
            let offset = vec2(x, y);
            let data = textureLoad(data_texture, ifrag_coord + offset, 0);
            var unit = com::unpack_unit(data);
            if unit.health > 0u && unit.id > 0u {
                if unit.team == 1u {
                    out.x += 1u;
                } else if unit.team == 2u {
                    out.y += 1u;
                }
            }
            if unit.health == 0u && unit.id > 0u {
                if unit.id == 1u {
                    out.z += 1u;
                } else if unit.id == 2u {
                    out.w += 1u;
                }
            }

        }
    }
    
    return out;
}

