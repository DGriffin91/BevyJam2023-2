use bevy::{
    core_pipeline::{
        core_3d::{self},
        fullscreen_vertex_shader::fullscreen_shader_vertex_state,
    },
    ecs::query::QueryItem,
    prelude::*,
    render::{
        camera::ExtractedCamera,
        extract_component::{ExtractComponent, ExtractComponentPlugin},
        render_graph::{
            NodeRunError, RenderGraphApp, RenderGraphContext, ViewNode, ViewNodeRunner,
        },
        render_resource::{
            BindGroupEntries, BindGroupLayout, BindGroupLayoutDescriptor, CachedRenderPipelineId,
            ColorTargetState, ColorWrites, Extent3d, FragmentState, MultisampleState, Operations,
            PipelineCache, PrimitiveState, RenderPassColorAttachment, RenderPassDescriptor,
            RenderPipelineDescriptor, TextureDescriptor, TextureDimension, TextureFormat,
            TextureUsages, TextureViewDimension,
        },
        renderer::{RenderContext, RenderDevice},
        texture::{CachedTexture, TextureCache},
        view::{ExtractedView, ViewTarget, ViewUniformOffset},
        Render, RenderApp, RenderSet,
    },
};

use crate::{
    bind_group_utils::{
        globals_binding, globals_layout_entry, utexture_layout_entry, view_binding,
        view_layout_entry,
    },
    shader_def_uint,
    units::{UnitsDataTextures, UnitsNode, ATTACK_RADIUS, UNITS_DATA_HEIGHT, UNITS_DATA_WIDTH},
};

pub const MINIMAP_DATA_FORMAT: TextureFormat = TextureFormat::Rgba8Uint;
pub const MINIMAP_SCALE: u32 = 4;

pub struct MinimapPlugin;

impl Plugin for MinimapPlugin {
    fn build(&self, app: &mut App) {
        app.add_plugins((ExtractComponentPlugin::<MinimapPass>::default(),));
        let Ok(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app
            .add_systems(Render, prepare_textures.in_set(RenderSet::PrepareResources))
            .add_render_graph_node::<ViewNodeRunner<MinimapNode>>(
                core_3d::graph::NAME,
                MinimapNode::NAME,
            )
            .add_render_graph_edges(
                core_3d::graph::NAME,
                &[
                    UnitsNode::NAME,
                    MinimapNode::NAME,
                    core_3d::graph::node::START_MAIN_PASS,
                ],
            );
    }

    fn finish(&self, app: &mut App) {
        let Ok(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app.init_resource::<MinimapPipeline>();
    }
}

#[derive(Component, ExtractComponent, Clone, Reflect)]
pub struct MinimapPass;

#[derive(Default)]
struct MinimapNode;
impl MinimapNode {
    pub const NAME: &'static str = "minimap_pass";
}

impl ViewNode for MinimapNode {
    type ViewQuery = (
        &'static ViewUniformOffset,
        &'static ViewTarget,
        &'static UnitsDataTextures,
        &'static MinimapTextures,
    );

    fn run(
        &self,
        _graph: &mut RenderGraphContext,
        render_context: &mut RenderContext,
        (view_uniform_offset, _view_target, unit_data_texture, minimap_textures): QueryItem<
            Self::ViewQuery,
        >,
        world: &World,
    ) -> Result<(), NodeRunError> {
        let unit_pipeline = world.resource::<MinimapPipeline>();

        let pipeline_cache = world.resource::<PipelineCache>();

        // ---------------------------------------
        // Generate Minimap Texture
        // ---------------------------------------

        {
            let Some(pipeline) =
                pipeline_cache.get_render_pipeline(unit_pipeline.update_pipeline_id)
            else {
                return Ok(());
            };

            let bind_group = render_context.render_device().create_bind_group(
                "minimap_bind_group",
                &unit_pipeline.update_layout,
                &BindGroupEntries::with_indices((
                    (0, view_binding(world)),
                    (9, globals_binding(world)),
                    (101, &unit_data_texture.b.default_view),
                    (103, &unit_data_texture.attack_a.default_view),
                )),
            );

            let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
                label: Some("unit_pass"),
                color_attachments: &[Some(RenderPassColorAttachment {
                    view: &minimap_textures.a.default_view,
                    resolve_target: None,
                    ops: Operations::default(),
                })],
                depth_stencil_attachment: None,
            });

            render_pass.set_render_pipeline(pipeline);
            render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);

            render_pass.draw(0..3, 0..1);
        }

        Ok(())
    }
}

#[derive(Resource)]
struct MinimapPipeline {
    update_layout: BindGroupLayout,
    update_pipeline_id: CachedRenderPipelineId,
}

impl FromWorld for MinimapPipeline {
    fn from_world(world: &mut World) -> Self {
        let mut shader_defs = Vec::new();
        shader_defs.extend_from_slice(&[shader_def_uint!(ATTACK_RADIUS)]);
        shader_defs.extend_from_slice(&[shader_def_uint!(MINIMAP_SCALE)]);

        let render_device = world.resource::<RenderDevice>();

        let update_layout = render_device.create_bind_group_layout(&BindGroupLayoutDescriptor {
            label: Some("unit_update_bind_group_layout"),
            entries: &[
                view_layout_entry(0),
                globals_layout_entry(9),
                utexture_layout_entry(101, TextureViewDimension::D2), // Prev Particle State
                utexture_layout_entry(103, TextureViewDimension::D2), // Attack data
            ],
        });

        let shader = world
            .resource::<AssetServer>()
            .load("shaders/minimap_update.wgsl");

        let update_pipeline_id =
            world
                .resource_mut::<PipelineCache>()
                .queue_render_pipeline(RenderPipelineDescriptor {
                    label: Some("unit_update_pipeline".into()),
                    layout: vec![update_layout.clone()],

                    vertex: fullscreen_shader_vertex_state(),
                    fragment: Some(FragmentState {
                        shader: shader.clone(),
                        shader_defs: shader_defs.clone(),

                        entry_point: "fragment".into(),
                        targets: vec![Some(ColorTargetState {
                            format: MINIMAP_DATA_FORMAT,
                            blend: None,
                            write_mask: ColorWrites::ALL,
                        })],
                    }),

                    primitive: PrimitiveState::default(),
                    depth_stencil: None,
                    multisample: MultisampleState::default(),
                    push_constant_ranges: vec![],
                });

        Self {
            update_layout,
            update_pipeline_id,
        }
    }
}

#[derive(Component)]
pub struct MinimapTextures {
    pub a: CachedTexture,
}

fn prepare_textures(
    mut commands: Commands,
    mut texture_cache: ResMut<TextureCache>,
    render_device: Res<RenderDevice>,
    views: Query<(Entity, &ExtractedCamera, &ExtractedView), With<MinimapPass>>,
) {
    for (entity, _camera, _view) in &views {
        let mut texture_descriptor = TextureDescriptor {
            label: None,
            size: Extent3d {
                depth_or_array_layers: 1,
                width: UNITS_DATA_WIDTH / MINIMAP_SCALE,
                height: UNITS_DATA_HEIGHT / MINIMAP_SCALE,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: TextureDimension::D2,
            format: MINIMAP_DATA_FORMAT,
            usage: TextureUsages::RENDER_ATTACHMENT
                | TextureUsages::TEXTURE_BINDING
                | TextureUsages::COPY_DST,
            view_formats: &[],
        };

        texture_descriptor.label = Some("minimap_data_texture");
        let minimap_data_texture = texture_cache.get(&render_device, texture_descriptor.clone());

        commands.entity(entity).insert(MinimapTextures {
            a: minimap_data_texture,
        });
    }
}
