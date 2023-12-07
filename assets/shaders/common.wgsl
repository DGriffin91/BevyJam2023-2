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
const UNIT_MODE_MOVEING: u32 = 2u;
const UNIT_MODE_ATTACK: u32 = 3u;

const SPEED_MOVE: f32 = 1.0;
const SPEED_ATTACK: f32 = 1.0;


fn unpack_unit(data: vec4<u32>) -> Unit {
    var unit: Unit;
    unit.progress = bitcast<f32>(data.x);
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
        bitcast<u32>(unit.progress),
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
