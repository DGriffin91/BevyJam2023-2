#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}

@group(0) @binding(101) var data_texture: texture_2d<f32>;

fn uhash(a: u32, b: u32) -> u32 { 
    var x = ((a * 1597334673u) ^ (b * 3812015801u));
    // from https://nullprogram.com/blog/2018/07/31/
    x = x ^ (x >> 16u);
    x = x * 0x7feb352du;
    x = x ^ (x >> 15u);
    x = x * 0x846ca68bu;
    x = x ^ (x >> 16u);
    return x;
}

fn unormf(n: u32) -> f32 { 
    return f32(n) * (1.0 / f32(0xffffffffu)); 
}

fn hash_noise(ufrag_coord: vec2<u32>, frame: u32) -> f32 {
    let urnd = uhash(ufrag_coord.x, (ufrag_coord.y << 11u) + frame);
    return unormf(urnd);
}

@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<f32> {
    let frag_coord = in.position.xy;
    let ufrag_coord = vec2<u32>(frag_coord);
    let ifrag_coord = vec2<i32>(ufrag_coord);

    let data = textureLoad(data_texture, ifrag_coord, 0);
    var velocity = xyz8e5_to_vec3_(bitcast<u32>(data.w));

    var new_pos = data.xyz;

    let vel_scale = length(velocity);

    let particle_size = 0.04;

    if data.y < particle_size {
        if hash_noise(ufrag_coord, globals.frame_count) > 0.99 || vel_scale < 0.001 {
            new_pos.x *= 5.0;
            new_pos.y = hash_noise(ufrag_coord, globals.frame_count + 1024u) * 1.0 + 5.0;
            new_pos.z = (hash_noise(ufrag_coord, globals.frame_count) * 2.0 - 1.0) * 0.5;
            new_pos.x = (hash_noise(ufrag_coord, globals.frame_count + 52345u) * 2.0 - 1.0) * 0.5;
            velocity.y = 0.01;
            velocity.x = (hash_noise(ufrag_coord, globals.frame_count + 2048u) * 2.0 - 1.0) * 0.01;
            velocity.z = (hash_noise(ufrag_coord, globals.frame_count + 4096u) * 2.0 - 1.0) * 0.01;
        } else {
            let damping = mix(0.5, 0.8, hash_noise(ufrag_coord, globals.frame_count + 1024u));
            let R = reflect(normalize(velocity), vec3(0.0, 1.0, 0.0));
            velocity = R * damping * vel_scale;
        }
    }
    new_pos += velocity;
    velocity.y -= 0.0001;
    

    return vec4<f32>(new_pos, bitcast<f32>(vec3_to_xyz8e5_(velocity)));
}

