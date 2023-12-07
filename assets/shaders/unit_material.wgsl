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
@group(0) @binding(104) var unit_texture: texture_2d_array<u32>;

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
}

struct Vertex {
    @builtin(instance_index) instance_index: u32,
    @builtin(vertex_index) index: u32,
};

@vertex
fn vertex(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;

    let dims = textureDimensions(data_texture).xy;

    let unit_index = (vertex.index / 6u);
    let vert_index = vertex.index % 6u;
    
    let data_x = i32(unit_index % dims.x);
    let data_y = i32(unit_index / dims.x);

    let unit_data = textureLoad(data_texture, vec2<i32>(data_x, data_y), 0);
    let unit = com::unpack_unit(unit_data);

    var size = 0.4;

    if unit.health == 0u {
        out.position = vec4(0.0);
        return out;
    }

    out.uv = vec2<f32>(vec2(
        (50u >> vert_index) & 1u, //50 is 110010
        (44u >> vert_index) & 1u, //44 is 101100
    ));


    var center = vec3(f32(data_x), 0.5, f32(data_y));

    if unit.mode == com::UNIT_MODE_MOVEING {
        let prev = vec3(f32(data_x - unit.step_dir.x), 0.5, f32(data_y - unit.step_dir.y));
        center = mix(prev, center, saturate(unit.progress));
    }

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


    let unit = com::unpack_unit(in.unit_data);

    var pbr = pbr_input_new();
    pbr.N = normalize(vec3(pow(in.uv, vec2(8.0)), 0.0));
    pbr.material.base_color = vec4(vec3(0.1), 1.0);
    pbr.material.reflectance = 0.5;
    
    var color = select(vec3(0.4, 0.02, 0.02), vec3(0.02, 0.15, 0.02), unit.team == 1u);
    color = select(color, vec3(0.0, 0.0, 0.0), unit.team == 0u);

    let uv = vec2(in.uv.x, 1.0 - in.uv.y);
    let mip = 1; //TODO select mip
    var index = 7;
    // TODO optimize 
    if unit.progress > 0.0 {
        index = select(index, 1, all(unit.step_dir == vec2( 1, -1)));
        index = select(index, 2, all(unit.step_dir == vec2( 0, -1)));
        index = select(index, 3, all(unit.step_dir == vec2(-1, -1)));
        index = select(index, 4, all(unit.step_dir == vec2(-1,  0)));
        index = select(index, 5, all(unit.step_dir == vec2(-1,  1)));
        index = select(index, 6, all(unit.step_dir == vec2( 0,  1)));
        index = select(index, 7, all(unit.step_dir == vec2( 1,  1)));
    }

    let dims = vec2<f32>(textureDimensions(unit_texture, mip).xy);
    let data = textureLoad(unit_texture, vec2<i32>(uv * dims), u32(index), mip);
    pbr = decompress_gbuffer(frag_coord, data.xy);
    
    //pbr.material.base_color = vec4(color, 1.0);

    out.deferred = deferred_gbuffer_from_pbr_input(pbr);
    out.deferred_lighting_pass_id = 1u;

    if pbr.material.base_color.w < 0.5 {
        discard;
    }


    // TODO: use prev frame state texture?
    // out.motion_vector = calculate_motion_vector(in.world_position, in.previous_world_position);
    return out;
}

fn decompress_gbuffer(frag_coord: vec4<f32>, in: vec2<u32>) -> PbrInput {
    var pbr: PbrInput;
    pbr.material = standard_material_new();
    pbr.frag_coord = frag_coord;
    let world_position = vec4(vt::position_ndc_to_world(vt::frag_coord_to_ndc(frag_coord)), 1.0);
    let is_orthographic = view.projection[3].w == 1.0;
    pbr.is_orthographic = is_orthographic;
    let V = pbr_functions::calculate_view(world_position, is_orthographic);
    pbr.world_position = world_position;
    pbr.V = V;

    let ut_nor_x     = (in.y >> 22u) & 0x3FFu;
    let ut_nor_y     = (in.y >> 12u) & 0x3FFu;
    let metallic     = (in.y >> 10u) & 0x1u;
    let mask         = (in.y >> 9u)  & 0x1u;
    let is_emissive  = (in.y >> 8u)  & 0x1u;
    let rough        =  in.y & 0xFFu;

    if is_emissive == 1u {
        pbr.material.emissive = vec4(rgb9e5_to_vec3_(in.x), 1.0);
    } else {
        pbr.material.base_color = vec4(rgb9e5_to_vec3_(in.x), 1.0);
    }
    pbr.material.base_color.w = f32(mask);

    pbr.material.metallic = select(0.0, 1.0, metallic == 1u);
    pbr.material.perceptual_roughness = f32(rough) / 255.0;

    var t_nor = vec2<f32>(f32(ut_nor_x), f32(ut_nor_y)) / 255.0;
    pbr.N = octahedral_decode(t_nor);
    pbr.world_normal = pbr.N;
    
    return pbr;
}

// For encoding normals or unit direction vectors as octahedral coordinates.
fn octahedral_encode(v: vec3<f32>) -> vec2<f32> {
    var n = v / (abs(v.x) + abs(v.y) + abs(v.z));
    let octahedral_wrap = (1.0 - abs(n.yx)) * select(vec2(-1.0), vec2(1.0), n.xy > 0.0);
    let n_xy = select(octahedral_wrap, n.xy, n.z >= 0.0);
    return n_xy * 0.5 + 0.5;
}

// For decoding normals or unit direction vectors from octahedral coordinates.
fn octahedral_decode(v: vec2<f32>) -> vec3<f32> {
    let f = v * 2.0 - 1.0;
    var n = vec3(f.xy, 1.0 - abs(f.x) - abs(f.y));
    let t = saturate(-n.z);
    let w = select(vec2(t), vec2(-t), n.xy >= vec2(0.0));
    n = vec3(n.xy + w, n.z);
    return normalize(n);
}