#import bevy_pbr::mesh_view_bindings::{view, globals}
#import bevy_pbr::mesh_bindings
#import bevy_render::instance_index::get_instance_index
#import bevy_pbr::mesh_functions

#import bevy_pbr::pbr_types
#import bevy_pbr::utils::PI

@group(1) @binding(0)
var data_texture: texture_2d<f32>;
@group(1) @binding(1)
var texture_sampler: sampler;

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
    @location(5) @interpolate(flat) instance_index: u32,
}

struct Vertex {
    @builtin(instance_index) instance_index: u32,
    @builtin(vertex_index) index: u32,
};

@vertex
fn vertex(vertex: Vertex) -> VertexOutput {
    var out: VertexOutput;

    let data_index = vertex.index / 6u;

    let data = textureLoad(data_texture, vec2<i32>(i32(data_index), 0i), 0);

    let center = data.xyz;
    let size = data.w;


    let idx = vertex.index % 6u;

    let vert_pos = vec3(
        select(-1.0, 1.0, idx == 1u || idx == 4u || idx == 5u), 
        select(-1.0, 1.0, idx == 2u || idx == 3u || idx == 5u),
        0.0,
    ) * size;


    var model = mesh_functions::get_model_matrix(vertex.instance_index);
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




    out.instance_index = get_instance_index(vertex.instance_index);
#ifdef BASE_INSTANCE_WORKAROUND
    // Hack: this ensures the push constant is always used, which works around this issue:
    // https://github.com/bevyengine/bevy/issues/10509
    // This can be removed when wgpu 0.19 is released
    out.position.x += min(f32(get_instance_index(0u)), 0.0);
#endif
    return out;
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    //var N = normalize(in.world_normal);
    //var V = normalize(view.world_position.xyz - in.world_position.xyz);

    return vec4(1.0, 0.0, 1.0, 1.0);
}
