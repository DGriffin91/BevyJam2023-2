
#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput

@group(0) @binding(101) var screen_texture: texture_2d<f32>;
@group(0) @binding(102) var texture_sampler: sampler;
@group(0) @binding(103) var minimap_texture: texture_2d<u32>;

@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<f32> {
    let frag_coord = in.position.xy;
    let ufrag_coord = vec2<u32>(frag_coord);
    let ifrag_coord = vec2<i32>(ufrag_coord);

    let minimap_dimensions = vec2<u32>(textureDimensions(minimap_texture).xy);

    var color = textureSample(screen_texture, texture_sampler, in.uv);

    if all(ufrag_coord < minimap_dimensions) {
        color = vec4(vec3(0.0), 1.0);
        let minimap = textureLoad(minimap_texture, ufrag_coord, 0);
        color.x = f32(minimap.r); // / #{MINIMAP_SCALE}.0 // Letting push into tonemapping
        color.y = f32(minimap.g); // / #{MINIMAP_SCALE}.0 // Letting push into tonemapping
    }

    return color;
}

