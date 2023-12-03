#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import bevy_pbr::mesh_view_bindings::{view, globals}

#import "shaders/xyz8e5.wgsl"::{xyz8e5_to_vec3_, vec3_to_xyz8e5_}
#import "shaders/rgb9e5.wgsl"::{rgb9e5_to_vec3_, vec3_to_rgb9e5_}
#import "shaders/sampling.wgsl" as sampling


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
    id: u32,
}

fn unpack_unit(data: vec4<u32>) -> Unit {
    var unit: Unit;
    unit.progress = bitcast<f32>(data.x);
    let d = unpack_4x8_(data.y);
    unit.step_dir = vec2<i32>(vec2(d.x, d.y)) - 1; // Could be smaller
    unit.health = d.z;
    unit.dest = unpack_2x16_(data.z);
    unit.id = data.w;
    return unit;
}

fn pack_unit(unit: Unit) -> vec4<u32> {
    return vec4<u32>(
        bitcast<u32>(unit.progress),
        pack_4x8_(vec4(u32(unit.step_dir.x + 1), u32(unit.step_dir.y + 1), unit.health, 0u)),
        pack_2x16_(unit.dest),
        unit.id,
    );
}

@group(0) @binding(101) var data_texture: texture_2d<u32>;
@group(0) @binding(102) var<uniform> command: UnitCommand;

@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<u32> {
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

                let data = textureLoad(data_texture, read_coord, 0);
                let other_unit = unpack_unit(data);

                // If we're the same id and we're in the spot this unit came from, delete this one as it has moved
                if other_unit.id == unit.id && all(read_coord == ifrag_coord + other_unit.step_dir) {
                    unit.health = 0u;
                    unit.id = 0u;
                    return pack_unit(unit);
                }
            }
        }
    }

    unit.progress += globals.delta_time;

    if command.command > 0u {
        unit.dest = command.dest;
    }

    let rng = sampling::hash_noise(ufrag_coord, globals.frame_count + 3498u);

    if unit.health == 0u && rng > 0.99999 {
        // Random spawn
        unit.health = 255u;
        unit.id = u32(sampling::hash_noise(ufrag_coord, globals.frame_count + 96421u) * f32(sampling::U32_MAX)) + 1u;
    }

    unit.step_dir = sign2i(vec2<i32>(unit.dest) - vec2<i32>(ufrag_coord));
    
    return pack_unit(unit);
}

