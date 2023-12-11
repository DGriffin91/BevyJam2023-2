#import bevy_pbr::mesh_view_bindings::{view, globals}
#import bevy_pbr::mesh_bindings
#import bevy_render::instance_index::get_instance_index
#import bevy_pbr::mesh_functions
#import bevy_pbr::pbr_types::{PbrInput, pbr_input_new}
#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/particles_update.wgsl"::{ParticleCommand, ParticleSystem}
#import "shaders/sampling.wgsl"::sampling

#import bevy_pbr::{
    pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
    pbr_deferred_functions::deferred_gbuffer_from_pbr_input,
}


#import bevy_pbr::pbr_types
#import bevy_pbr::utils::PI

@group(0) @binding(101) var data_texture: texture_2d<f32>;
@group(0) @binding(102) var<uniform> commands: array<ParticleCommand, 12u>;
@group(0) @binding(103) var<uniform> systems: array<ParticleSystem, 128u>;

struct VertexOutput {
    // this is `clip position` when the struct is used as a vertex stage output 
    // and `frag coord` when used as a fragment stage input
    @builtin(position) position: vec4<f32>,
    @location(0) world_position: vec4<f32>,
    @location(1) world_normal: vec3<f32>,
    @location(2) uv: vec2<f32>,
#ifdef VERTEX_TANGENTS
    @location(3) world_tangent: vec4<f32>,
#endif
#ifdef VERTEX_COLORS
    @location(4) color: vec4<f32>,
#endif
    @location(5) velocity: vec4<f32>,
    @location(6) particle_index: u32,
    @location(7) system_index: u32,
    @location(8) splash: u32,

}

struct Vertex {
    @builtin(instance_index) instance_index: u32,
    @builtin(vertex_index) index: u32,
};

@vertex
fn vertex(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;

    let dims = textureDimensions(data_texture).xy;

    out.particle_index = (vertex.index / 6u);

    out.system_index = out.particle_index / 256u;
    
    let data_x = i32(out.particle_index % dims.x);
    let data_y = i32(out.particle_index / dims.x);

    let data = textureLoad(data_texture, vec2<i32>(data_x, data_y), 0);
    var velocity = xyz8e5_to_vec3_(bitcast<u32>(data.w));
    let vel_scale = length(velocity);
    var new_pos = data.xyz;

    let pixel_radius = 1.0 / (0.5 * view.viewport.w * view.projection[1][1]);

    let center = data.xyz;
    var sizex = pixel_radius * 0.2;
    var sizey = max(0.8, pixel_radius * 3.0);

    var splash = 0u;

    if new_pos.y <= 5.0 {
        sizex = max(0.15, pixel_radius * 0.5);
        sizey = max(0.15, pixel_radius * 0.5);
        splash = 1u;
    }


    let idx = vertex.index % 6u;

    let vert_pos = vec3(
        select(-1.0, 1.0, idx == 1u || idx == 4u || idx == 5u) * sizex, 
        select(-1.0, 1.0, idx == 2u || idx == 3u || idx == 5u) * sizey,
        0.0,
    );


#ifdef LOCK_ROTATION
    let vertex_position = vec4<f32>(vert_pos.x, vert_pos.y, 0.0, 1.0);
    let position = view.view_proj * model * vertex_position;
#else
    let camera_right = normalize(vec3<f32>(view.view_proj.x.x, view.view_proj.y.x, view.view_proj.z.x));
#ifdef LOCK_Y
    let camera_up = vec3<f32>(0.0, 1.0, 0.0);
#else
    let camera_up = normalize(vec3<f32>(view.view_proj.x.y, view.view_proj.y.y, view.view_proj.z.y));
#endif

    let world_space = camera_right * vert_pos.x + camera_up * vert_pos.y + center;
    let position = view.view_proj * vec4<f32>(world_space, 1.0);
#endif

    out.position = position;
    out.velocity = vec4(xyz8e5_to_vec3_(bitcast<u32>(data.w)), 1.0);
    out.splash = splash;

    return out;
}

struct FragmentOutput {
    @location(0) deferred: vec4<u32>,
    @location(1) deferred_lighting_pass_id: u32,
}

@fragment
fn fragment(in: VertexOutput) -> FragmentOutput {
    var out: FragmentOutput;
    var N = normalize(in.world_normal);
    var V = normalize(view.world_position.xyz - in.world_position.xyz);

    let system = systems[in.system_index];

    var pbr = pbr_input_new();
    pbr.N = vec3(0.0, -1.0, 0.0);
    //pbr.material.flags |= STANDARD_MATERIAL_FLAGS_UNLIT_BIT;
    
    let color = mix(vec3(1.0, 0.0, 0.0) * 1.0, vec3(0.1, 0.2, 0.5) * 1.0, saturate(pow(length(in.velocity.xyz), 1.0) * 2.0));
    pbr.material.base_color = vec4(color * 0.15, 1.0);
    if in.splash == 1u {
        pbr.material.base_color = vec4(0.2, 0.1, 0.1, 1.0);
    }
    pbr.material.reflectance = 0.4;
    pbr.material.perceptual_roughness = 1.0;



    out.deferred = deferred_gbuffer_from_pbr_input(pbr);
    out.deferred_lighting_pass_id = 1u;

    // TODO: use prev frame state texture?
    // out.motion_vector = calculate_motion_vector(in.world_position, in.previous_world_position);


    return out;
}
