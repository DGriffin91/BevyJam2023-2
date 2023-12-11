#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/sampling.wgsl" as sampling

struct ParticleCommand {
    spawn_position: vec3<f32>,
    spawn_spread: u32, //rgb9e5
    velocity: u32,     //xyz8e5
    direction_random_spread: f32,
    category: u32,
    flags: u32,
    color1_: u32, //rgb9e5
    color2_: u32, //rgb9e5
    _webgl2_padding_1_: f32,
    _webgl2_padding_2_: f32,
};

struct ParticleSystem {
    age: f32,
    command_assignment: u32,
    padding_1_: f32,
    padding_2_: f32,
};

@group(0) @binding(101) var data_texture: texture_2d<f32>;
@group(0) @binding(102) var<uniform> commands: array<ParticleCommand, 12u>;
@group(0) @binding(103) var<uniform> systems: array<ParticleSystem, 128u>; // Check your assignment for a command index (frag_coord.y == )

// see e0e3dad6a4fcfc40df77b1174920b18f7a831d6e or earlier for usable particle system

@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<f32> {
    let frag_coord = in.position.xy;
    let ufrag_coord = vec2<u32>(frag_coord);
    let ifrag_coord = vec2<i32>(ufrag_coord);

    let system_index = ufrag_coord.y;

    let data = textureLoad(data_texture, ifrag_coord, 0);
    var velocity = xyz8e5_to_vec3_(bitcast<u32>(data.w));
    var new_pos = data.xyz;

    let vel_scale = length(velocity);

    let particle_size = 0.01;

    let system = systems[system_index];

    if sampling::hash_noise(ufrag_coord + globals.frame_count, globals.frame_count + 2048u) > 0.999 || vel_scale < 0.001  {
        new_pos.y = sampling::hash_noise(ufrag_coord, globals.frame_count + 1024u) * 2.0 + 300.0;
        new_pos.z = (sampling::hash_noise(ufrag_coord, globals.frame_count) * 2.0 - 1.0) * 500.0 + 128.0;
        new_pos.x = (sampling::hash_noise(ufrag_coord, globals.frame_count + 52345u) * 2.0 - 1.0) * 500.0 + 128.0;
        let rng_velx = sampling::hash_noise(ufrag_coord, globals.frame_count + 67353u) * 2.0 - 1.0;
        let rng_vely = sampling::hash_noise(ufrag_coord, globals.frame_count + 45341u);
        let rng_velz = sampling::hash_noise(ufrag_coord, globals.frame_count + 89921u) * 2.0 - 1.0;
        velocity = vec3(rng_velx * 0.001, -0.1 - rng_vely * 0.01, rng_velz * 0.001);
    }
    if new_pos.y <= 5.0 {
        let damping = mix(0.3, 0.8, sampling::hash_noise(ufrag_coord, globals.frame_count + 1024u));
        let R = reflect(normalize(velocity), vec3(0.0, 0.0, 0.0));
        velocity = R * damping * vel_scale;
    }
    
    new_pos += velocity; // * globals.delta_time * 100.0
    velocity.y -= 0.001 * globals.delta_time * 100.0;
    


    

    return vec4<f32>(new_pos, bitcast<f32>(vec3_to_xyz8e5_(velocity)));
}

