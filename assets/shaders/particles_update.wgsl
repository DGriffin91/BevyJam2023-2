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
    if system.command_assignment <= 12u {
        let command = commands[system.command_assignment];
        let spawn_spread = rgb9e5_to_vec3_(command.spawn_spread);
        new_pos = command.spawn_position;
        //new_pos.x += (sampling::hash_noise(ufrag_coord, globals.frame_count + 56432u) * 2.0 - 1.0) * spawn_spread.x;
        //new_pos.y += (sampling::hash_noise(ufrag_coord, globals.frame_count + 45674u) * 2.0 - 1.0) * spawn_spread.y;
        //new_pos.z += (sampling::hash_noise(ufrag_coord, globals.frame_count + 12344u) * 2.0 - 1.0) * spawn_spread.z;
        velocity = xyz8e5_to_vec3_(command.velocity);
        let velocity_rnd = vec2(
            sampling::hash_noise(ufrag_coord, 5345u),
            sampling::hash_noise(ufrag_coord, 6784u),
        );
        let velocity_dir = normalize(velocity);
        let velocity_basis = sampling::build_orthonormal_basis(velocity_dir);
        velocity = normalize(sampling::uniform_sample_cone(velocity_rnd, command.direction_random_spread) * velocity_basis) * length(velocity);
    } else {
        if data.y < particle_size {
            if sampling::hash_noise(ufrag_coord, globals.frame_count) > 0.99 || vel_scale < 0.001 {
                new_pos.y = sampling::hash_noise(ufrag_coord, globals.frame_count + 1024u) * 1.0 + 5.0;
                new_pos.z = (sampling::hash_noise(ufrag_coord, globals.frame_count) * 2.0 - 1.0) * 0.5;
                new_pos.x = (sampling::hash_noise(ufrag_coord, globals.frame_count + 52345u) * 2.0 - 1.0) * 0.5;
                velocity.y = 0.01;
                velocity.x = (sampling::hash_noise(ufrag_coord, globals.frame_count + 2048u) * 2.0 - 1.0) * 0.01;
                velocity.z = (sampling::hash_noise(ufrag_coord, globals.frame_count + 4096u) * 2.0 - 1.0) * 0.01;
            } else {
                let damping = mix(0.5, 0.8, sampling::hash_noise(ufrag_coord, globals.frame_count + 1024u));
                let R = reflect(normalize(velocity), vec3(0.0, 1.0, 0.0));
                velocity = R * damping * vel_scale;
            }
        }
        new_pos += velocity;
        velocity.y -= 0.000001;
    }


    

    return vec4<f32>(new_pos, bitcast<f32>(vec3_to_xyz8e5_(velocity)));
}

