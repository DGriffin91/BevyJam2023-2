use bevy::asset::AssetServer;
use bevy::core_pipeline::core_3d::CORE_3D_DEPTH_FORMAT;
use bevy::core_pipeline::fullscreen_vertex_shader::fullscreen_shader_vertex_state;
use bevy::ecs::world::World;
use bevy::pbr::{GpuLights, LightMeta};

use bevy::render::globals::{GlobalsBuffer, GlobalsUniform};
use bevy::render::render_resource::encase::internal::WriteInto;
use bevy::render::render_resource::{
    self, BindGroupLayout, BindGroupLayoutEntry, BindingResource, BindingType, Buffer,
    BufferBindingType, BufferInitDescriptor, BufferUsages, CachedRenderPipelineId,
    ColorTargetState, ColorWrites, CompareFunction, DepthBiasState, DepthStencilState, FilterMode,
    FragmentState, LoadOp, MultisampleState, Operations, PipelineCache, PrimitiveState,
    RenderPassColorAttachment, RenderPassDepthStencilAttachment, RenderPipelineDescriptor, Sampler,
    SamplerBindingType, SamplerDescriptor, ShaderDefVal, ShaderStages, ShaderType, StencilState,
    TextureFormat, TextureSampleType, TextureView, TextureViewDimension, VertexState,
};
use bevy::render::renderer::{RenderContext, RenderDevice};
use bevy::render::view::{ViewUniform, ViewUniforms};

pub fn fsampler_layout_entry(binding: u32) -> BindGroupLayoutEntry {
    BindGroupLayoutEntry {
        binding,
        visibility: ShaderStages::VERTEX_FRAGMENT,
        ty: BindingType::Sampler(SamplerBindingType::Filtering),
        count: None,
    }
}

pub fn csampler_layout_entry(binding: u32) -> BindGroupLayoutEntry {
    BindGroupLayoutEntry {
        binding,
        visibility: ShaderStages::VERTEX_FRAGMENT,
        ty: BindingType::Sampler(SamplerBindingType::Comparison),
        count: None,
    }
}

pub fn nsampler_layout_entry(binding: u32) -> BindGroupLayoutEntry {
    BindGroupLayoutEntry {
        binding,
        visibility: ShaderStages::VERTEX_FRAGMENT,
        ty: BindingType::Sampler(SamplerBindingType::NonFiltering),
        count: None,
    }
}

pub fn texture_layout_entry(
    binding: u32,
    dim: TextureViewDimension,
    sample_type: TextureSampleType,
) -> BindGroupLayoutEntry {
    BindGroupLayoutEntry {
        binding,
        visibility: ShaderStages::VERTEX_FRAGMENT,
        ty: BindingType::Texture {
            sample_type,
            view_dimension: dim,
            multisampled: false,
        },
        count: None,
    }
}

pub fn ftexture_layout_entry(binding: u32, dim: TextureViewDimension) -> BindGroupLayoutEntry {
    texture_layout_entry(binding, dim, TextureSampleType::Float { filterable: true })
}

pub fn dtexture_layout_entry(binding: u32, dim: TextureViewDimension) -> BindGroupLayoutEntry {
    texture_layout_entry(binding, dim, TextureSampleType::Depth)
}

pub fn utexture_layout_entry(binding: u32, dim: TextureViewDimension) -> BindGroupLayoutEntry {
    texture_layout_entry(binding, dim, TextureSampleType::Uint)
}

pub fn stexture_layout_entry(binding: u32, dim: TextureViewDimension) -> BindGroupLayoutEntry {
    texture_layout_entry(binding, dim, TextureSampleType::Sint)
}

pub fn view_layout_entry(binding: u32) -> BindGroupLayoutEntry {
    BindGroupLayoutEntry {
        binding,
        visibility: ShaderStages::VERTEX | ShaderStages::VERTEX_FRAGMENT | ShaderStages::COMPUTE,
        ty: BindingType::Buffer {
            ty: BufferBindingType::Uniform,
            has_dynamic_offset: true,
            min_binding_size: Some(ViewUniform::min_size()),
        },
        count: None,
    }
}

pub fn lights_layout_entry(binding: u32) -> BindGroupLayoutEntry {
    BindGroupLayoutEntry {
        binding,
        visibility: ShaderStages::VERTEX | ShaderStages::VERTEX_FRAGMENT,
        ty: BindingType::Buffer {
            ty: BufferBindingType::Uniform,
            has_dynamic_offset: true,
            min_binding_size: Some(GpuLights::min_size()),
        },
        count: None,
    }
}

pub fn globals_layout_entry(binding: u32) -> BindGroupLayoutEntry {
    BindGroupLayoutEntry {
        binding,
        visibility: ShaderStages::VERTEX | ShaderStages::VERTEX_FRAGMENT,
        ty: BindingType::Buffer {
            ty: BufferBindingType::Uniform,
            has_dynamic_offset: false,
            min_binding_size: Some(GlobalsUniform::min_size()),
        },
        count: None,
    }
}

pub fn uniform_layout_entry(binding: u32, min_size: std::num::NonZeroU64) -> BindGroupLayoutEntry {
    BindGroupLayoutEntry {
        binding,
        visibility: ShaderStages::VERTEX_FRAGMENT,
        ty: BindingType::Buffer {
            ty: render_resource::BufferBindingType::Uniform,
            has_dynamic_offset: false,
            min_binding_size: Some(min_size),
        },
        count: None,
    }
}

#[macro_export]
macro_rules! resource {
    ($world:expr, $resource_type:ty) => {
        if let Some(res) = $world.get_resource::<$resource_type>() {
            res
        } else {
            return Ok(());
        }
    };
}

#[macro_export]
macro_rules! image {
    ($images:expr, $image_handle:expr) => {
        if let Some(res) = $images.get($image_handle) {
            res
        } else {
            return Ok(());
        }
    };
}

pub fn linear_sampler(render_device: &RenderDevice) -> Sampler {
    
    render_device.create_sampler(&SamplerDescriptor {
        mag_filter: FilterMode::Linear,
        min_filter: FilterMode::Linear,
        ..SamplerDescriptor::default()
    })
}

pub fn nearest_sampler(render_device: &RenderDevice) -> Sampler {
    
    render_device.create_sampler(&SamplerDescriptor {
        mag_filter: FilterMode::Nearest,
        min_filter: FilterMode::Nearest,
        ..SamplerDescriptor::default()
    })
}

pub fn view_binding(world: &World) -> BindingResource<'_> {
    let view_uniforms = world.resource::<ViewUniforms>();
    view_uniforms.uniforms.binding().unwrap().clone()
}

pub fn globals_binding(world: &World) -> BindingResource<'_> {
    let globals_buffer = world.resource::<GlobalsBuffer>();
    globals_buffer.buffer.binding().unwrap().clone()
}

pub fn lights_binding(world: &World) -> BindingResource<'_> {
    let light_meta = world.resource::<LightMeta>();
    light_meta.view_gpu_lights.binding().unwrap().clone()
}

#[macro_export]
macro_rules! shader_def_uint {
    ($var:expr) => {
        bevy::render::render_resource::ShaderDefVal::UInt(stringify!($var).into(), $var as u32)
    };
}

pub fn uniform_buffer<T>(data: T, render_context: &mut RenderContext, label: &str) -> Buffer
where
    T: ShaderType + WriteInto,
{
    let mut buffer = render_resource::encase::UniformBuffer::new(Vec::new());
    buffer.write(&data).unwrap();

    let config_uniform =
        render_context
            .render_device()
            .create_buffer_with_data(&BufferInitDescriptor {
                label: Some(label),
                contents: buffer.as_ref(),
                usage: BufferUsages::UNIFORM | BufferUsages::COPY_DST,
            });
    config_uniform
}

pub fn basic_fullscreen_tri_pipeline(
    label: &'static str,
    shader: &'static str,
    world: &mut World,
    layout: &BindGroupLayout,
    shader_defs: Vec<ShaderDefVal>,
    targets: Vec<Option<ColorTargetState>>,
) -> CachedRenderPipelineId {
    let shader = world.resource::<AssetServer>().load(shader);
    let pipeline_id =
        world
            .resource_mut::<PipelineCache>()
            .queue_render_pipeline(RenderPipelineDescriptor {
                label: Some(std::borrow::Cow::Borrowed(label)),
                layout: vec![layout.clone()],
                vertex: fullscreen_shader_vertex_state(),
                fragment: Some(FragmentState {
                    shader,
                    shader_defs,
                    entry_point: "fragment".into(),
                    targets,
                }),
                primitive: PrimitiveState::default(),
                depth_stencil: None,
                multisample: MultisampleState::default(),
                push_constant_ranges: vec![],
            });
    pipeline_id
}

pub fn basic_opaque_pipeline(
    label: &'static str,
    shader: &'static str,
    world: &mut World,
    layout: &BindGroupLayout,
    shader_defs: Vec<ShaderDefVal>,
    targets: Vec<Option<ColorTargetState>>,
) -> CachedRenderPipelineId {
    let shader = world.resource::<AssetServer>().load(shader);

    let pipeline_id =
        world
            .resource_mut::<PipelineCache>()
            .queue_render_pipeline(RenderPipelineDescriptor {
                label: Some(std::borrow::Cow::Borrowed(label)),
                layout: vec![layout.clone()],

                vertex: VertexState {
                    shader: shader.clone(),
                    shader_defs: shader_defs.clone(),
                    entry_point: "vertex".into(),
                    buffers: Vec::new(),
                },
                fragment: Some(FragmentState {
                    shader,
                    shader_defs,
                    entry_point: "fragment".into(),
                    targets,
                }),

                primitive: PrimitiveState::default(),
                depth_stencil: Some(DepthStencilState {
                    format: CORE_3D_DEPTH_FORMAT,
                    depth_write_enabled: true,
                    depth_compare: CompareFunction::GreaterEqual,
                    stencil: StencilState::default(),
                    bias: DepthBiasState::default(),
                }),
                multisample: MultisampleState::default(),
                push_constant_ranges: vec![],
            });

    pipeline_id
}

pub fn opaque_target(format: TextureFormat) -> Option<ColorTargetState> {
    Some(ColorTargetState {
        format,
        blend: None,
        write_mask: ColorWrites::ALL,
    })
}

pub fn load_color_attachment(view: &TextureView) -> Option<RenderPassColorAttachment<'_>> {
    Some(RenderPassColorAttachment {
        view,
        resolve_target: None,
        ops: Operations {
            load: LoadOp::Load,
            store: true,
        },
    })
}

pub fn clear_color_attachment(view: &TextureView) -> Option<RenderPassColorAttachment<'_>> {
    Some(RenderPassColorAttachment {
        view,
        resolve_target: None,
        ops: Operations {
            load: LoadOp::Clear(Default::default()),
            store: true,
        },
    })
}

pub fn load_depth_attachment(
    view: &TextureView,
) -> Option<RenderPassDepthStencilAttachment<'_>> {
    Some(RenderPassDepthStencilAttachment {
        view,
        depth_ops: Some(Operations {
            load: LoadOp::Load,
            store: true,
        }),
        stencil_ops: None,
    })
}
