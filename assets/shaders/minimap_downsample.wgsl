#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/sampling.wgsl" as sampling
#import "shaders/common.wgsl" as com

@group(0) @binding(101) var minimap_texture: texture_2d<u32>;

@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<u32> {
    let frag_coord = in.position.xy;
    let ifrag_coord = vec2<i32>(frag_coord) * #{MINIMAP_SCALE};

    var sum = vec4(0u);

    for (var x = 0; x < #{MINIMAP_SCALE}; x += 1) {
        for (var y = 0; y < #{MINIMAP_SCALE}; y += 1) {
            let offset = vec2(x, y);
            let data = textureLoad(minimap_texture, ifrag_coord + offset, 0);
            sum += data;
        }
    }
    
    return sum;
}

