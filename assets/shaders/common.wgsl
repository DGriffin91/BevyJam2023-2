#import bevy_pbr::mesh_view_bindings::{view, globals}
#import bevy_pbr::mesh_bindings
#import bevy_render::instance_index::get_instance_index
#import bevy_pbr::mesh_functions
#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
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


fn unpack_2x4_from_8(v: u32) -> vec2<u32> {
    return vec2(
        v & 0xFu,
        (v >> 4u) & 0xFu,
    );
}

fn pack_2x4_to_8(v: vec2<u32>) -> u32 {
    return ((v.y & 0xFu) << 4u) | (v.x & 0xFu);
}

fn unpack_4x8_(v: u32) -> vec4<u32> {
    return vec4(
        v & 0xFFu,
        (v >> 8u) & 0xFFu,
        (v >> 16u) & 0xFFu,
        (v >> 24u) & 0xFFu
    );
}

fn pack_4x8_(v: vec4<u32>) -> u32 {
    return ((v.w & 0xFFu) << 24u) | ((v.z & 0xFFu) << 16u) | ((v.y & 0xFFu) << 8u) | (v.x & 0xFFu);
}

fn unpack_2x16_(v: u32) -> vec2<u32> {
    return vec2(
        v & 0xFFFFu,
        (v >> 16u) & 0xFFFFu,
    );
}

fn pack_2x16_(v: vec2<u32>) -> u32 {
    return ((v.y & 0xFFFFu) << 16u) | (v.x & 0xFFFFu);
}

fn sign2i(n: vec2<i32>) -> vec2<i32> {
    return vec2(
        select(select(-1, 1, n.x > 0), 0, n.x == 0),
        select(select(-1, 1, n.y > 0), 0, n.y == 0),
    );
}

struct UnitCommand {
    select_region: vec4<u32>,
    dest: vec2<u32>,
    command: u32,
    delta_time: f32,
    upgrade_request: u32,
    spare1_: u32,
    spare2_: u32,
    spare3_: u32,
};

struct Unit {
    health: u32,
    progress: f32,
    step_dir: vec2<i32>,
    dest: vec2<u32>,
    mode: u32,
    team: u32,
    id: u32,    
}

// -----------------------------------------------------------

struct LargeUnit {
    pos: vec2<f32>,
    dest: vec2<f32>,
    health: u32,
    mode: u32,
    progress: f32,
    team: u32,
    dir_index: u32,
}

fn unpack_large_unit(data: vec4<u32>, ufrag_coord: vec2<u32>) -> LargeUnit {
    var unit: LargeUnit;

    //unit.pos = unpack2x16float(data.x) * 0.001;
    //unit.dest = unpack2x16float(data.y) * 0.001;
    //unit.progress = unpack2x16float(data.z).x; // Spare 16 bits
    //let d1 = unpack_4x8_(data.w);
    //unit.health = d1.x;
    //unit.mode = d1.y;
    //unit.team = select(1u, 2u, ufrag_coord.y == 1u);

    // f16 was not accurate enough for pos given a small enough delta time
    unit.pos = vec2(bitcast<f32>(data.x), bitcast<f32>(data.y)); 
    unit.dest = unpack2x16float(data.z) * 0.01;
    let d1 = unpack_4x8_(data.w);
    unit.health = d1.x;
    unit.mode = d1.y;
    unit.dir_index = d1.z;
    unit.team = select(1u, 2u, ufrag_coord.y == 1u);

    return unit;
}


fn pack_large_unit(unit: LargeUnit) -> vec4<u32> {
    var data = vec4(0u);

    //data.x = pack2x16float(unit.pos * 1000.0);
    //data.y = pack2x16float(unit.dest * 1000.0);
    //data.z = pack2x16float(vec2(unit.progress, 0.0)); // Spare 16 bits
    //data.w = pack_4x8_(vec4(unit.health, unit.mode, 0u, 0u));

    // f16 was not accurate enough for pos given a small enough delta time
    data.x = bitcast<u32>(unit.pos.x);
    data.y = bitcast<u32>(unit.pos.y);
    data.z = pack2x16float(unit.dest * 100.0);
    data.w = pack_4x8_(vec4(unit.health, unit.mode, unit.dir_index, 0u));

    return data;
}

// -----------------------------------------------------------

const UNIT_MODE_IDLE: u32 = 0u;
const UNIT_MODE_MOVE: u32 = 1u;
const UNIT_MODE_MOVEING: u32 = 2u;
const UNIT_MODE_ATTACK: u32 = 3u;

const SPEED_MOVE: f32 = 5.0;
const SPEED_ATTACK: f32 = 1.0;
const SMALL_UNIT_SIZE: f32 = 1.0;

const LARGE_SPEED_MOVE: f32 = 5.0;
const LARGE_SPEED_ATTACK: f32 = 1.0;
const LARGE_UNIT_SIZE: f32 = 4.0;

const SPAWN_RADIUS: f32 = 8.0;
const SPAWN_RATE: f32 = 0.6;

struct UnitStats {
    move_rate: f32,
    attack_rate: f32,
    large_move_rate: f32,
    large_attack_rate: f32,
    spawn_radius: f32,
    spawn_rate: f32,
}

// Why can't I use #{LARGE_UNITS_DATA_WIDTH}u here?
fn get_unit_stats(large_unit_tex: texture_2d<u32>, ludw: u32, team: u32) -> UnitStats {
    var stats: UnitStats;
    let team1_buff = select(1.0, 1.4, team == 1u);
    let upgrades = sqrt(vec4<f32>(textureLoad(large_unit_tex, vec2(ludw + 1u, team - 1u), 0) + 1u));
    stats.move_rate = upgrades.x * SPEED_MOVE;
    stats.attack_rate = upgrades.y * SPEED_ATTACK * team1_buff;
    stats.large_move_rate = upgrades.x * LARGE_SPEED_MOVE;
    stats.large_attack_rate = upgrades.y * LARGE_SPEED_ATTACK;
    stats.spawn_radius = upgrades.z * SPAWN_RADIUS;
    stats.spawn_rate = upgrades.z * SPAWN_RATE * team1_buff;
    return stats;
}

fn unpack_unit(data: vec4<u32>) -> Unit {
    var unit: Unit;
    unit.progress = unpack2x16float(data.x).x; //spare 16 bits
    let d = unpack_4x8_(data.y);
    unit.step_dir = vec2<i32>(unpack_2x4_from_8(d.x)) - 1;
    // d.y is spare
    unit.health = d.z;
    let mode_team = unpack_2x4_from_8(d.w);
    unit.mode = mode_team.x; 
    unit.team = mode_team.y;
    unit.dest = unpack_2x16_(data.z);
    unit.id = data.w;
    return unit;
}

fn pack_unit(unit: Unit) -> vec4<u32> {
    return vec4<u32>(
        pack2x16float(vec2(unit.progress, 0.0)), //spare 16 bits
        pack_4x8_(vec4(
                pack_2x4_to_8(vec2(
                    u32(unit.step_dir.x + 1),
                    u32(unit.step_dir.y + 1), 
                )), 
                0u, //spare
                unit.health, 
                pack_2x4_to_8(vec2(unit.mode, unit.team)),
        )),
        pack_2x16_(unit.dest),
        unit.id,
    );
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