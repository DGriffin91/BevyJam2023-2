use bevy::{
    core_pipeline::core_3d,
    ecs::query::QueryItem,
    prelude::*,
    render::{
        render_graph::{
            NodeRunError, RenderGraphApp, RenderGraphContext, ViewNode, ViewNodeRunner,
        },
        render_resource::{
            BindGroupEntries, BindGroupLayout, BindGroupLayoutDescriptor, CachedRenderPipelineId,
            PipelineCache, RenderPassDescriptor, Sampler, SamplerDescriptor, TextureFormat,
            TextureViewDimension,
        },
        renderer::{RenderContext, RenderDevice},
        view::{ViewTarget, ViewUniformOffset},
        RenderApp,
    },
};
use bevy_ridiculous_ssgi::bind_group_utils::{fsampler_layout_entry, ftexture_layout_entry};

use crate::{
    bind_group_utils::{
        basic_fullscreen_tri_pipeline, globals_binding, globals_layout_entry,
        load_color_attachment, opaque_target, utexture_layout_entry, view_binding,
        view_layout_entry,
    },
    minimap::{MinimapTextures, MINIMAP_SCALE},
    shader_def_uint,
};

pub struct PostProcessPlugin;

impl Plugin for PostProcessPlugin {
    fn build(&self, app: &mut App) {
        let Ok(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app
            .add_render_graph_node::<ViewNodeRunner<PostProcessNode>>(
                core_3d::graph::NAME,
                PostProcessNode::NAME,
            )
            .add_render_graph_edges(
                core_3d::graph::NAME,
                &[
                    core_3d::graph::node::BLOOM,
                    PostProcessNode::NAME,
                    core_3d::graph::node::TONEMAPPING,
                ],
            );
    }

    fn finish(&self, app: &mut App) {
        let Ok(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app.init_resource::<PostProcessPipeline>();
    }
}

#[derive(Default)]
struct PostProcessNode;
impl PostProcessNode {
    pub const NAME: &'static str = "game_post_process";
}

impl ViewNode for PostProcessNode {
    type ViewQuery = (
        &'static ViewTarget,
        &'static ViewUniformOffset,
        &'static MinimapTextures,
    );

    fn run(
        &self,
        _graph: &mut RenderGraphContext,
        render_context: &mut RenderContext,
        (view_target, view_uniform_offset, minimap_textures): QueryItem<Self::ViewQuery>,
        world: &World,
    ) -> Result<(), NodeRunError> {
        let post_process_pipeline = world.resource::<PostProcessPipeline>();

        let pipeline_cache = world.resource::<PipelineCache>();

        let Some(pipeline) = pipeline_cache.get_render_pipeline(post_process_pipeline.pipeline_id)
        else {
            return Ok(());
        };

        let post_process = view_target.post_process_write();

        let bind_group = render_context.render_device().create_bind_group(
            "post_process_bind_group",
            &post_process_pipeline.layout,
            &BindGroupEntries::with_indices((
                (0, view_binding(world)),
                (9, globals_binding(world)),
                (101, post_process.source),
                (102, &post_process_pipeline.sampler),
                (103, &minimap_textures.a.default_view),
            )),
        );

        let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
            label: Some("post_process_pass"),
            color_attachments: &[load_color_attachment(&post_process.destination)],
            depth_stencil_attachment: None,
        });

        render_pass.set_render_pipeline(pipeline);
        render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);
        render_pass.draw(0..3, 0..1);

        Ok(())
    }
}

#[derive(Resource)]
struct PostProcessPipeline {
    layout: BindGroupLayout,
    sampler: Sampler,
    pipeline_id: CachedRenderPipelineId,
}

impl FromWorld for PostProcessPipeline {
    fn from_world(world: &mut World) -> Self {
        let mut shader_defs = Vec::new();
        shader_defs.extend_from_slice(&[shader_def_uint!(MINIMAP_SCALE)]);
        let render_device = world.resource::<RenderDevice>();

        let layout = render_device.create_bind_group_layout(&BindGroupLayoutDescriptor {
            label: Some("post_process_bind_group_layout"),
            entries: &[
                view_layout_entry(0),
                globals_layout_entry(9),
                ftexture_layout_entry(101, TextureViewDimension::D2),
                fsampler_layout_entry(102),
                utexture_layout_entry(103, TextureViewDimension::D2), // Minimap
            ],
        });

        let sampler = render_device.create_sampler(&SamplerDescriptor::default());

        let pipeline_id = basic_fullscreen_tri_pipeline(
            "post_process_pipeline",
            "shaders/post_processing.wgsl",
            world,
            &layout,
            shader_defs,
            vec![opaque_target(TextureFormat::Rgba16Float)],
        );

        Self {
            layout,
            sampler,
            pipeline_id,
        }
    }
}
