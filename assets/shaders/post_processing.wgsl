
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
    let row_height = 11.0 * get_scale();
    let mask = printing::print_value_custom(
        frag_coord - vec2(0.0, row_height * f32(row) * 2.0),
        vec2(row_height),
        vec2(row_height),
        f32(value),
        6.0,
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

    if all(ucoord < minimap_dimensions) {
        // Rotate for player
        var mapping = vec2(ucoord.x, minimap_dimensions.y - ucoord.y); //view.viewport.y / 720.0
        color = vec4(vec3(0.0), 1.0);
        let minimap = textureLoad(minimap_texture, mapping, 0);
        let died = minimap.b + minimap.a;
        color.r = f32(minimap.y) * 0.5;
        color.g = f32(minimap.x) * 0.5;
        color.b = f32(died) * 1000.0;
    } else if ucoord.x < minimap_dimensions.x + 30u && ucoord.y < minimap_dimensions.y {
        color = vec4(vec3(0.0), 1.0);
    }

    let minimap_sum = get_minimap_sum();

    
    let stats_1 = textureLoad(large_unit_tex, vec2(#{LARGE_UNITS_DATA_WIDTH}u, 0u), 0);
    let stats_2 = textureLoad(large_unit_tex, vec2(#{LARGE_UNITS_DATA_WIDTH}u, 1u), 0);

    let left_align = 70.0;

    let t1_alive = minimap_sum.x;
    let t2_alive = minimap_sum.y;
    let t1_lost = stats_1.x;
    let t2_lost = stats_1.y;

    color = print_value(frag_coord.xy - vec2(left_align, 14.0), color, 6, t1_alive);
    color = print_value(frag_coord.xy - vec2(left_align, 14.0), color, 8, t1_lost);
    color = print_value(frag_coord.xy - vec2(left_align, 14.0), color, 10, t2_lost);
    color = print_value(frag_coord.xy - vec2(left_align, 14.0), color, 12, t2_alive);

    return color;
}

