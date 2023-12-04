#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/sampling.wgsl" as sampling


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
        select(-1, 1, n.x >= 0),
        select(-1, 1, n.y >= 0),
    );
}

struct UnitCommand {
    select_region: vec4<u32>,
    dest: vec2<u32>,
    command: u32,
    padding: u32,
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

const UNIT_MODE_IDLE: u32 = 0u;
const UNIT_MODE_MOVE: u32 = 1u;
const UNIT_MODE_ATTACK: u32 = 2u;


fn unpack_unit(data: vec4<u32>) -> Unit {
    var unit: Unit;
    unit.progress = bitcast<f32>(data.x);
    let d = unpack_4x8_(data.y);
    unit.step_dir = vec2<i32>(vec2(d.x, d.y)) - 1; // Could be smaller
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
        bitcast<u32>(unit.progress),
        pack_4x8_(vec4(
                u32(unit.step_dir.x + 1), 
                u32(unit.step_dir.y + 1), 
                unit.health, 
                pack_2x4_to_8(vec2(unit.mode, unit.team)),
        )),
        pack_2x16_(unit.dest),
        unit.id,
    );
}

@group(0) @binding(101) var data_texture: texture_2d<u32>;
@group(0) @binding(102) var<uniform> command: UnitCommand;
@group(0) @binding(103) var prev_attack: texture_2d<u32>;

struct FragmentOutput {
    @location(0) unit_data: vec4<u32>,
    @location(1) attack_data: vec4<u32>,
}

@fragment
fn fragment(in: FullscreenVertexOutput) -> FragmentOutput {
    var out: FragmentOutput;

    let frag_coord = in.position.xy;
    let ufrag_coord = vec2<u32>(frag_coord);
    let ifrag_coord = vec2<i32>(ufrag_coord);

    let system_index = ufrag_coord.y;

    let data = textureLoad(data_texture, ifrag_coord, 0);
    var unit = unpack_unit(data);

    // if there is living unit in this cell check if it moved to another cell last frame
    if unit.health != 0u {
        for (var x = -1; x <= 1; x += 1) {
            for (var y = -1; y <= 1; y += 1) {
                let offset = vec2(x, y);

                let read_coord = ifrag_coord + offset;

                let other_data = textureLoad(data_texture, read_coord, 0);
                let other_unit = unpack_unit(other_data);

                // If we're the same id and we're in the spot this unit came from, delete this one as it has moved
                if other_unit.id == unit.id && all(read_coord == ifrag_coord + other_unit.step_dir) {
                    out.unit_data = vec4(0u);
                    out.attack_data = vec4(0u);
                    return out;
                }
            }
        }
    }        
    
    let rng = sampling::hash_noise(ufrag_coord, globals.frame_count + 3498u);
    if in.uv.y < 0.2 || in.uv.y > 0.8 {
        if unit.health == 0u && rng > 0.99999 {
            // Random spawn
            unit = unpack_unit(vec4(0u));
            unit.health = 255u;
            unit.id = u32(sampling::hash_noise(ufrag_coord, globals.frame_count + 96421u) * f32(sampling::U32_MAX)) + 1u;
            unit.dest = ufrag_coord;
            unit.team = select(1u, 2u, in.uv.y > 0.5);
            out.unit_data = pack_unit(unit);
            out.attack_data = vec4(0u);
            return out;
        }
    }

    // If there is no unit here, return none
    if unit.health == 0u || unit.id == 0u {
        out.unit_data = vec4(0u);
        out.attack_data = vec4(0u);
        return out;
    }

    if unit.mode == UNIT_MODE_IDLE || unit.mode == UNIT_MODE_ATTACK {
        // First check if the unit we were shooting at is still there and use that one first otherwise find a new one
        let prev_attack_data = textureLoad(prev_attack, ifrag_coord, 0);
        let prev_attack_vector = vec2<i32>(prev_attack_data.xy) - #{ATTACK_RADIUS};
        let prev_attack_damage = prev_attack_data.z;

        var other_data = textureLoad(data_texture, ifrag_coord + prev_attack_vector, 0);
        var other_unit = unpack_unit(other_data);
        if other_unit.id != unit.id && other_unit.health != 0u && other_unit.team > 0u && unit.team != other_unit.team {
            out.attack_data = prev_attack_data;
            unit.mode = UNIT_MODE_ATTACK;
        } else {
            let noise = vec2(
                sampling::hash_noise(ufrag_coord, globals.frame_count + 45623u),
                sampling::hash_noise(ufrag_coord, globals.frame_count + 25674u),
            ) * 2.0 + 1.0;
            let attack_offset = clamp(vec2<i32>(noise * #{ATTACK_RADIUS}.0), vec2(-#{ATTACK_RADIUS}), vec2(#{ATTACK_RADIUS}));
            let attack_coord = attack_offset + ifrag_coord;

            other_data = textureLoad(data_texture, attack_coord, 0);
            other_unit = unpack_unit(other_data);
            let attack_damage = 1u;

            if other_unit.id != unit.id && other_unit.health > 0u && other_unit.team > 0u && unit.team != other_unit.team {
                out.attack_data = vec4(vec2<u32>(attack_offset + #{ATTACK_RADIUS}), attack_damage, 0u);
                unit.mode = UNIT_MODE_ATTACK;
            }
        }
    }

    if command.command > 0u && unit.team == 1u {
        unit.dest = command.dest;
    }

    if (unit.mode == UNIT_MODE_IDLE || unit.mode == UNIT_MODE_MOVE) && any(ufrag_coord != unit.dest) {
        unit.progress += globals.delta_time;


        let f_to_dest = vec2<f32>(unit.dest) - vec2<f32>(ufrag_coord);

        var dir_noise = vec2(0.0);
        dir_noise = vec2(
            sampling::hash_noise(ufrag_coord, globals.frame_count + 74856u),
            sampling::hash_noise(ufrag_coord, globals.frame_count + 36422u),
        ) * 2.0 - 1.0;
        dir_noise *= length(f_to_dest);

        unit.step_dir = sign2i(vec2<i32>((f_to_dest + dir_noise)));
        unit.mode = UNIT_MODE_MOVE;
        out.attack_data = vec4(0u);
    }



    
    out.unit_data = pack_unit(unit);
    return out;
}

