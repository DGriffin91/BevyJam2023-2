#import bevy_pbr::mesh_view_bindings::{view, globals}
#import bevy_pbr::mesh_bindings
#import bevy_render::instance_index::get_instance_index
#import bevy_pbr::mesh_functions
#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/common.wgsl" as com
#import "shaders/sampling.wgsl" as sampling
#import bevy_pbr::view_transformations as vt

#import bevy_pbr::{
    pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
    pbr_deferred_functions::deferred_gbuffer_from_pbr_input,
    pbr_functions, 
    pbr_types::{PbrInput, standard_material_new, pbr_input_new},
}


#import bevy_pbr::pbr_types
#import bevy_pbr::utils::PI

@group(0) @binding(101) var data_texture: texture_2d<u32>;
@group(0) @binding(102) var<uniform> commands: com::UnitCommand;
@group(0) @binding(103) var attack_texture: texture_2d<u32>;
// Cursed, but work on both webgl2 and native
// Discussion: https://discord.com/channels/691052431525675048/743663924229963868/1182466862190186627
@group(0) @binding(104) var unit_texture: texture_2d_array<f32>;
@group(0) @binding(105) var nearest_sampler: sampler;
@group(0) @binding(106) var large_unit_tex: texture_2d<u32>;

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
    @location(5) unit_data: vec4<u32>,
    @location(6) udata_xy: vec2<u32>,
}

struct Vertex {
    @builtin(instance_index) instance_index: u32,
    @builtin(vertex_index) index: u32,
};

@vertex
fn vertex(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;

    let dims = textureDimensions(large_unit_tex).xy;

    let unit_index = (vertex.index / 6u);
    let vert_index = vertex.index % 6u;
    
    let data_x = i32(unit_index % dims.x);
    let data_y = i32(unit_index / dims.x);
    let idata_xy = vec2(data_x, data_y);
    let udata_xy = vec2<u32>(idata_xy);

    let unit_data = textureLoad(large_unit_tex, idata_xy, 0);
    let unit = com::unpack_large_unit(unit_data, udata_xy);
 
    var size = com::LARGE_UNIT_SIZE;

    if unit.health == 0u {
        out.position = vec4(0.0);
        return out;
    }

    out.uv = vec2<f32>(vec2(
        (50u >> vert_index) & 1u, //50 is 110010
        (44u >> vert_index) & 1u, //44 is 101100
    ));


    var center = vec3(f32(unit.pos.x), 1.0, f32(unit.pos.y));

    //let center = vec3(2.0, 2.0, 0.0);

    let idx = vertex.index % 6u;

    let vert_pos = vec3(
        select(-1.0, 1.0, idx == 1u || idx == 4u || idx == 5u), 
        select(-1.0, 1.0, idx == 2u || idx == 3u || idx == 5u),
        0.0,
    ) * size;


#ifdef LOCK_ROTATION
    let vertex_position = vec4<f32>(vert_pos.x, vert_pos.y, 0.0, 1.0);
    let position = view.view_proj * model * vertex_position;
#else // LOCK_ROTATION
    let camera_right = normalize(vec3<f32>(view.view_proj.x.x, view.view_proj.y.x, view.view_proj.z.x));
    #ifdef LOCK_Y
        let camera_up = vec3<f32>(0.0, 1.0, 0.0);
    #else // LOCK_Y
        let camera_up = normalize(vec3<f32>(view.view_proj.x.y, view.view_proj.y.y, view.view_proj.z.y));
    #endif // LOCK_Y

    var world_space = camera_right * vert_pos.x + camera_up * vert_pos.y + center;

    // FOR TAA ---
    var noise = sampling::r2_sequence(globals.frame_count % 8u) * 2.0 - 1.0;
    noise *= (1.0 / view.viewport.zw) * 1.0; // 1.0 since ndc is -1.0 to 1.0
    world_space = vt::position_ndc_to_world(vt::position_world_to_ndc(world_space) + vec3(noise, 0.0));
    // END FOR TAA ---

    let position = view.view_proj * vec4<f32>(world_space, 1.0);
#endif // LOCK_ROTATION

    out.position = vec4(position.xy, position.zw);
    out.unit_data = unit_data;
    out.udata_xy = udata_xy;


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

    let ndc = vt::position_world_to_ndc(in.world_position.xyz);
    let frag_coord = vec4(vt::ndc_to_uv(vt::position_world_to_ndc(in.world_position.xyz).xy) * view.viewport.zw, ndc.z, 0.0);


    let unit = com::unpack_large_unit(in.unit_data, in.udata_xy);

    var pbr = pbr_input_new();
    pbr.N = normalize(vec3(pow(in.uv, vec2(8.0)), 0.0));
    pbr.material.base_color = vec4(vec3(0.1), 1.0);
    pbr.material.reflectance = 0.5;
    
    var color = select(vec3(0.4, 0.02, 0.02), vec3(0.02, 0.15, 0.02), unit.team == 1u);
    color = select(color, vec3(0.0, 0.0, 0.0), unit.team == 0u);
    //pbr.material.base_color = vec4(color, 1.0);


    let uv = vec2(in.uv.x, 1.0 - in.uv.y);
    let mip = 0u; //TODO select mip, TODO only mip 0 works in WebGL2
    var index = 7;


    //let dims = vec2<f32>(textureDimensions(unit_texture).xy) / f32(1u << mip);
    //let data = bitcast<vec2<u32>>(textureLoad(unit_texture, vec2<i32>(uv * dims), u32(index), i32(mip)).xy);
    // Cursed, but work on both webgl2 and native
    // Discussion: https://discord.com/channels/691052431525675048/743663924229963868/1182466862190186627
    //let data = bitcast<vec2<u32>>(textureSampleLevel(unit_texture, nearest_sampler, uv, u32(index), f32(mip)));
    let data = bitcast<vec2<u32>>(textureSample(unit_texture, nearest_sampler, uv, unit.dir_index));
    pbr = com::decompress_gbuffer(frag_coord, data.xy);
    

    out.deferred = deferred_gbuffer_from_pbr_input(pbr);
    out.deferred_lighting_pass_id = 1u;

    if pbr.material.base_color.w < 0.5 || unit.health == 0u {
        discard;
    }


    // TODO: use prev frame state texture?
    // out.motion_vector = calculate_motion_vector(in.world_position, in.previous_world_position);
    return out;
}

