#import bevy_pbr::mesh_view_bindings::{view, globals}
#import bevy_pbr::mesh_bindings
#import bevy_render::instance_index::get_instance_index
#import bevy_pbr::mesh_functions
#import bevy_pbr::pbr_types::{PbrInput, pbr_input_new}
#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/common.wgsl" as com
#import "shaders/sampling.wgsl" as sampling

#import bevy_pbr::{
    pbr_types::STANDARD_MATERIAL_FLAGS_UNLIT_BIT,
    pbr_deferred_functions::deferred_gbuffer_from_pbr_input,
}

#import bevy_pbr::pbr_types
#import bevy_pbr::utils::PI

@group(0) @binding(101) var data_texture: texture_2d<u32>;
@group(0) @binding(102) var<uniform> commands: com::UnitCommand;
@group(0) @binding(103) var attack_texture: texture_2d<u32>;

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

    let iunit_coord = vec2<i32>(
        i32(unit_index % dims.x), 
        i32(unit_index / dims.x)
    );

    let unit_data = textureLoad(data_texture, iunit_coord, 0);
    let unit = com::unpack_unit(unit_data);

    var size = 0.1;
    var projectile_y = 0.7;


    var center = vec3(f32(iunit_coord.x), projectile_y, f32(iunit_coord.y));

    let attack_data = textureLoad(attack_texture, iunit_coord, 0);
    let attack_vector = vec2<i32>(attack_data.xy) - #{ATTACK_RADIUS};
    let attack_damage = attack_data.z;
    if unit.health != 0u && unit.mode == com::UNIT_MODE_ATTACK && !all(attack_vector == vec2(0))  {

        let iprojectile_dest = iunit_coord + attack_vector;
        let fprojectile_dest = vec3(f32(iprojectile_dest.x), projectile_y, f32(iprojectile_dest.y));

        center = mix(center, fprojectile_dest, saturate(unit.progress));
    } else {
        out.position = vec4(0.0);
        return out;
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

    let unit = com::unpack_unit(in.unit_data);

    var pbr = pbr_input_new();
    pbr.N = V;
    pbr.material.flags |= STANDARD_MATERIAL_FLAGS_UNLIT_BIT;
    
    var color = select(vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), unit.team == 1u);
    pbr.material.base_color = vec4(color * 3.0, 1.0);

    out.deferred = deferred_gbuffer_from_pbr_input(pbr);
    out.deferred_lighting_pass_id = 1u;

    // TODO: use prev frame state texture?
    // out.motion_vector = calculate_motion_vector(in.world_position, in.previous_world_position);
    return out;
}
