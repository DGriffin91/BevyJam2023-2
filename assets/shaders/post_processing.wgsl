
#import bevy_core_pipeline::fullscreen_vertex_shader::FullscreenVertexOutput
#import "shaders/printing.wgsl" as printing
#import bevy_pbr::mesh_view_bindings::{view, globals}

@group(0) @binding(101) var screen_texture: texture_2d<f32>;
@group(0) @binding(102) var texture_sampler: sampler;
@group(0) @binding(103) var minimap_texture: texture_2d<u32>;
@group(0) @binding(104) var minimap_sm3_texture: texture_2d<u32>;
@group(0) @binding(105) var large_unit_tex: texture_2d<u32>;

fn get_minimap_sum() -> vec4<u32> {
    var sum = vec4(0u);

    for (var x = 0; x < 2; x += 1) {
        for (var y = 0; y < 2; y += 1) {
            let offset = vec2(x, y);
            let data = textureLoad(minimap_sm3_texture, offset, 0);
            sum += data;
        }
    }

    return sum;
}

fn print_value(
    frag_coord: vec2<f32>,
    color: vec4<f32>,
    row: i32,
    value: u32,
) -> vec4<f32> {
    let row_height = 10.5;
    let mask = printing::print_value_custom(
        frag_coord - vec2(0.0, row_height * f32(row) * 2.0),
        vec2(row_height),
        vec2(row_height),
        f32(min(value, 9999995u)), // Rendering past this seems broken
        0.0,
        0.0
    );
    return select(color, vec4(1.0), mask > 0.0);
}

fn get_scale() -> f32 {
    return max(round(view.viewport.w / 720.0), 1.0);
}

@fragment
fn fragment(in: FullscreenVertexOutput) -> @location(0) vec4<f32> {
    let frag_coord = in.position.xy;
    let ufrag_coord = vec2<u32>(frag_coord);
    let ifrag_coord = vec2<i32>(ufrag_coord);

    let minimap_dimensions = vec2<u32>(textureDimensions(minimap_texture).xy);

    var color = textureSample(screen_texture, texture_sampler, in.uv);

    let ucoord = vec2<u32>(frag_coord / get_scale());
    let fcoord = vec2<f32>(ucoord);

    if all(ucoord < minimap_dimensions) {
        // Rotate for player
        var mapping = vec2(ucoord.x, minimap_dimensions.y - ucoord.y); //view.viewport.y / 720.0
        color = vec4(vec3(0.0), 1.0);
        let minimap = textureLoad(minimap_texture, mapping, 0);
        let died = minimap.b + minimap.a;
        color.r = f32(minimap.y) * 0.5;
        color.g = f32(minimap.x) * 0.5;
        color.b = f32(died) * 1000.0;
    } else if ucoord.x < minimap_dimensions.x + 70u && ucoord.y < minimap_dimensions.y {
        color = vec4(vec3(0.0), 1.0);
    }

    let minimap_sum = get_minimap_sum();

    
    let t1stats = textureLoad(large_unit_tex, vec2(#{LARGE_UNITS_DATA_WIDTH}u, 0u), 0);
    let t2stats = textureLoad(large_unit_tex, vec2(#{LARGE_UNITS_DATA_WIDTH}u, 1u), 0);
    var t1upgrades = textureLoad(large_unit_tex, vec2(#{LARGE_UNITS_DATA_WIDTH}u + 1u, 0u), 0);
    var t2upgrades = textureLoad(large_unit_tex, vec2(#{LARGE_UNITS_DATA_WIDTH}u + 1u, 1u), 0);

    let left_align = 180.0;

    let t1_alive = minimap_sum.x;
    let t2_alive = minimap_sum.y;
    let t1_lost = t1stats.x;
    let t2_lost = t2stats.x;
    let t1_credits = t1stats.y / 100u;

    
    let upgrade_movment_cost = u32(sqrt(f32(t1upgrades.x + 1u)));
    let upgrade_attack_cost = u32(sqrt(f32(t1upgrades.y + 1u)));
    let upgrade_spawn_cost = u32(sqrt(f32(t1upgrades.z + 1u)));

    color = print_value(fcoord.xy - vec2(left_align, 21.0), color, 5, t1_alive);
    color = print_value(fcoord.xy - vec2(left_align, 21.0), color, 6, t1_lost);
    color = print_value(fcoord.xy - vec2(left_align, 21.0), color, 7, t2_lost);
    color = print_value(fcoord.xy - vec2(left_align, 21.0), color, 8, t2_alive);
    color = print_value(fcoord.xy - vec2(left_align, 21.0), color, 9, t1_credits);
    color = print_value(fcoord.xy - vec2(left_align - 70.0, 21.0), color, 12, upgrade_movment_cost);
    color = print_value(fcoord.xy - vec2(left_align - 70.0, 21.0), color, 13, upgrade_attack_cost);
    color = print_value(fcoord.xy - vec2(left_align - 70.0, 21.0), color, 14, upgrade_spawn_cost);
    color = print_value(fcoord.xy - vec2(left_align, 21.0), color, 12, t1upgrades.x);
    color = print_value(fcoord.xy - vec2(left_align, 21.0), color, 13, t1upgrades.y);
    color = print_value(fcoord.xy - vec2(left_align, 21.0), color, 14, t1upgrades.z);

    color = print_value(fcoord.xy - vec2(left_align + 50.0, 21.0), color, 12, t2upgrades.x);
    color = print_value(fcoord.xy - vec2(left_align + 50.0, 21.0), color, 13, t2upgrades.y);
    color = print_value(fcoord.xy - vec2(left_align + 50.0, 21.0), color, 14, t2upgrades.z);


    //color = print_value(fcoord.xy - vec2(left_align, 21.0), color, 14, t1upgrades.w);

    return color;
}

