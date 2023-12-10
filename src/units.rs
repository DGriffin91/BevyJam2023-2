use bevy::render::render_resource::*;
use bevy::{
    core::FrameCount,
    core_pipeline::{
        core_3d::{self},
        deferred::{DEFERRED_LIGHTING_PASS_ID_FORMAT, DEFERRED_PREPASS_FORMAT},
        prepass::ViewPrepassTextures,
    },
    ecs::query::QueryItem,
    prelude::*,
    render::{
        camera::ExtractedCamera,
        extract_component::{ExtractComponent, ExtractComponentPlugin},
        extract_resource::{ExtractResource, ExtractResourcePlugin},
        render_asset::RenderAssets,
        render_graph::{
            NodeRunError, RenderGraphApp, RenderGraphContext, ViewNode, ViewNodeRunner,
        },
        renderer::{RenderContext, RenderDevice},
        texture::{CachedTexture, TextureCache},
        view::{ExtractedView, ViewDepthTexture, ViewTarget, ViewUniformOffset},
        Render, RenderApp, RenderSet,
    },
};

use crate::bind_group_utils::ftexture_layout_entry;
use crate::minimap::{MinimapTextures, MINIMAP_SCALE};
use crate::{
    bind_group_utils::{
        basic_fullscreen_tri_pipeline, basic_opaque_pipeline, fsampler_layout_entry,
        globals_binding, globals_layout_entry, load_color_attachment, load_depth_attachment,
        nearest_sampler, opaque_target, uniform_buffer, uniform_layout_entry,
        utexture_layout_entry, view_binding, view_layout_entry,
    },
    image, resource, shader_def_uint, UnitTexture,
};

pub const UNITS_DATA_FORMAT: TextureFormat = TextureFormat::Rgba32Uint;
pub const UNITS_ATTACK_FORMAT: TextureFormat = TextureFormat::Rgba8Uint;
pub const UNITS_DATA_WIDTH: u32 = 512;
pub const UNITS_DATA_HEIGHT: u32 = 512;
pub const ATTACK_RADIUS: u32 = 5;
pub const LARGE_UNITS_DATA_FORMAT: TextureFormat = TextureFormat::Rgba32Uint;
pub const LARGE_UNITS_TEXTURE_WIDTH: u32 = 67;
pub const LARGE_UNITS_DATA_WIDTH: u32 = 65;
pub const LARGE_UNITS_TEXTURE_HEIGHT: u32 = 2;

#[derive(Resource, Clone, ExtractResource, Copy, ShaderType, Debug, Default)]
pub struct UnitCommand {
    pub select_region: UVec4,
    pub dest: UVec2,
    pub command: u32,
    pub delta_time: f32,
}

pub struct UnitsPlugin;

impl Plugin for UnitsPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(PreUpdate, clear_unit_command)
            .init_resource::<UnitCommand>()
            .add_plugins((
                ExtractResourcePlugin::<UnitCommand>::default(),
                ExtractComponentPlugin::<UnitsPass>::default(),
            ));
        let Ok(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app
            .add_systems(Render, prepare_textures.in_set(RenderSet::PrepareResources))
            .add_render_graph_node::<ViewNodeRunner<UnitsNode>>(
                core_3d::graph::NAME,
                UnitsNode::NAME,
            )
            .add_render_graph_edges(
                core_3d::graph::NAME,
                &[
                    core_3d::graph::node::DEFERRED_PREPASS,
                    UnitsNode::NAME,
                    core_3d::graph::node::COPY_DEFERRED_LIGHTING_ID,
                ],
            );
    }

    fn finish(&self, app: &mut App) {
        let Ok(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app.init_resource::<UnitPipeline>();
    }
}

#[derive(Component, ExtractComponent, Clone, Reflect)]
pub struct UnitsPass;

#[derive(Default)]
pub struct UnitsNode;
impl UnitsNode {
    pub const NAME: &'static str = "units_pass";
}

impl ViewNode for UnitsNode {
    type ViewQuery = (
        &'static ViewUniformOffset,
        &'static ViewTarget,
        &'static ViewDepthTexture,
        &'static ViewPrepassTextures,
    );

    fn run(
        &self,
        _graph: &mut RenderGraphContext,
        render_context: &mut RenderContext,
        (view_uniform_offset, _view_target, depth, view_prepass_textures): QueryItem<
            Self::ViewQuery,
        >,
        world: &World,
    ) -> Result<(), NodeRunError> {
        let unit_pipeline = world.resource::<UnitPipeline>();
        let unit_command = world.resource::<UnitCommand>();
        let time = world.resource::<Time>();
        let minimap_textures = world.resource::<MinimapTextures>();
        let unit_data_texture = world.resource::<UnitsDataTextures>();

        let pipeline_cache = world.resource::<PipelineCache>();

        let gbuffer = view_prepass_textures.deferred.clone().unwrap();
        let lighting_pass_id = view_prepass_textures
            .deferred_lighting_pass_id
            .clone()
            .unwrap();

        let images = world.resource::<RenderAssets<Image>>();
        let small_goose = image!(images, &resource!(world, UnitTexture).small_goose);
        let big_goose = image!(images, &resource!(world, UnitTexture).big_goose);

        // ---------------------------------------
        // Units Evaluate
        // ---------------------------------------

        let mut unit_command = *unit_command;
        unit_command.delta_time = time.delta_seconds();

        let commands_uniform = uniform_buffer(unit_command, render_context, "Unit Command Uniform");

        {
            let Some(pipeline) =
                pipeline_cache.get_render_pipeline(unit_pipeline.evaluate_pipeline_id)
            else {
                return Ok(());
            };

            let bind_group = render_context.render_device().create_bind_group(
                "unit_evaluate_bind_group",
                &unit_pipeline.evaluate_layout,
                &BindGroupEntries::with_indices((
                    (0, view_binding(world)),
                    (9, globals_binding(world)),
                    (101, &unit_data_texture.a.default_view),
                    (102, commands_uniform.as_entire_binding()),
                    (103, &unit_data_texture.attack_b.default_view),
                    (104, &small_goose.texture_view),
                    (105, &unit_pipeline.sampler),
                    (106, &unit_data_texture.large_unit_a.default_view),
                    (107, &big_goose.texture_view),
                    (108, &minimap_textures.minimap_sm_tex.default_view),
                    (109, &minimap_textures.minimap_sm3_tex.default_view),
                )),
            );

            let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
                label: Some("Units Evaluate"),
                color_attachments: &[
                    load_color_attachment(&unit_data_texture.b.default_view),
                    load_color_attachment(&unit_data_texture.attack_a.default_view),
                ],
                depth_stencil_attachment: None,
            });

            render_pass.set_render_pipeline(pipeline);
            render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);

            render_pass.draw(0..3, 0..1);
        }

        // ---------------------------------------
        // Units Update
        // ---------------------------------------

        let commands_uniform = uniform_buffer(unit_command, render_context, "Unit Command Uniform");

        {
            let Some(pipeline) =
                pipeline_cache.get_render_pipeline(unit_pipeline.update_pipeline_id)
            else {
                return Ok(());
            };

            let bind_group = render_context.render_device().create_bind_group(
                "unit_update_bind_group",
                &unit_pipeline.update_layout,
                &BindGroupEntries::with_indices((
                    (0, view_binding(world)),
                    (9, globals_binding(world)),
                    (101, &unit_data_texture.b.default_view),
                    (102, commands_uniform.as_entire_binding()),
                    (103, &unit_data_texture.attack_a.default_view),
                    (104, &small_goose.texture_view),
                    (105, &unit_pipeline.sampler),
                    (106, &unit_data_texture.large_unit_a.default_view),
                    (107, &big_goose.texture_view),
                    (108, &minimap_textures.minimap_sm_tex.default_view),
                    (109, &minimap_textures.minimap_sm3_tex.default_view),
                )),
            );

            let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
                label: Some("Units Update"),
                color_attachments: &[load_color_attachment(&unit_data_texture.a.default_view)],
                depth_stencil_attachment: None,
            });

            render_pass.set_render_pipeline(pipeline);
            render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);

            render_pass.draw(0..3, 0..1);
        }

        // ---------------------------------------
        // Large Units Update
        // ---------------------------------------

        let commands_uniform = uniform_buffer(unit_command, render_context, "Unit Command Uniform");

        {
            let Some(pipeline) =
                pipeline_cache.get_render_pipeline(unit_pipeline.large_update_pipeline_id)
            else {
                return Ok(());
            };

            let bind_group = render_context.render_device().create_bind_group(
                "unit_update_bind_group",
                &unit_pipeline.large_update_layout,
                &BindGroupEntries::with_indices((
                    (0, view_binding(world)),
                    (9, globals_binding(world)),
                    (101, &unit_data_texture.a.default_view),
                    (102, commands_uniform.as_entire_binding()),
                    (103, &unit_data_texture.attack_a.default_view),
                    (104, &small_goose.texture_view),
                    (105, &unit_pipeline.sampler),
                    (106, &unit_data_texture.large_unit_a.default_view),
                    (107, &big_goose.texture_view),
                    (108, &minimap_textures.minimap_sm_tex.default_view),
                    (109, &minimap_textures.minimap_sm3_tex.default_view),
                )),
            );

            let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
                label: Some("Large Units Update"),
                color_attachments: &[load_color_attachment(
                    &unit_data_texture.large_unit_b.default_view,
                )],
                depth_stencil_attachment: None,
            });

            render_pass.set_render_pipeline(pipeline);
            render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);

            render_pass.draw(0..3, 0..1);
        }
        // ---------------------------------------
        // Units Draw
        // ---------------------------------------
        {
            let Some(pipeline) = pipeline_cache.get_render_pipeline(unit_pipeline.draw_pipeline_id)
            else {
                return Ok(());
            };

            let bind_group = render_context.render_device().create_bind_group(
                "unit_draw_bind_group",
                &unit_pipeline.draw_layout,
                &BindGroupEntries::with_indices((
                    (0, view_binding(world)),
                    (9, globals_binding(world)),
                    (101, &unit_data_texture.a.default_view),
                    (102, commands_uniform.as_entire_binding()),
                    (103, &unit_data_texture.attack_a.default_view),
                    (104, &small_goose.texture_view),
                    (105, &unit_pipeline.sampler),
                    (106, &unit_data_texture.large_unit_b.default_view),
                    (107, &big_goose.texture_view),
                    (108, &minimap_textures.minimap_sm_tex.default_view),
                    (109, &minimap_textures.minimap_sm3_tex.default_view),
                )),
            );

            let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
                label: Some("Units Draw"),
                color_attachments: &[
                    load_color_attachment(&gbuffer.default_view),
                    load_color_attachment(&lighting_pass_id.default_view),
                ],
                depth_stencil_attachment: load_depth_attachment(&depth.view),
            });

            // DRAW UNITS
            render_pass.set_render_pipeline(pipeline);
            render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);
            render_pass.draw(0..UNITS_DATA_WIDTH * UNITS_DATA_HEIGHT * 6, 0..1);

            let Some(pipeline) =
                pipeline_cache.get_render_pipeline(unit_pipeline.draw_projectiles_pipeline_id)
            else {
                return Ok(());
            };

            // DRAW UNIT PROJECTILES
            render_pass.set_render_pipeline(pipeline);
            render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);
            render_pass.draw(0..UNITS_DATA_WIDTH * UNITS_DATA_HEIGHT * 6, 0..1);
        }

        // ---------------------------------------
        // Large Units Draw
        // ---------------------------------------
        {
            let Some(pipeline) =
                pipeline_cache.get_render_pipeline(unit_pipeline.large_draw_pipeline_id)
            else {
                return Ok(());
            };

            let bind_group = render_context.render_device().create_bind_group(
                "large_unit_draw_bind_group",
                &unit_pipeline.large_unit_draw_layout,
                &BindGroupEntries::with_indices((
                    (0, view_binding(world)),
                    (9, globals_binding(world)),
                    (101, &unit_data_texture.a.default_view),
                    (102, commands_uniform.as_entire_binding()),
                    (103, &unit_data_texture.attack_a.default_view),
                    (104, &small_goose.texture_view),
                    (105, &unit_pipeline.sampler),
                    (106, &unit_data_texture.large_unit_b.default_view),
                    (107, &big_goose.texture_view),
                    (108, &minimap_textures.minimap_sm_tex.default_view),
                    (109, &minimap_textures.minimap_sm3_tex.default_view),
                )),
            );

            let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
                label: Some("Units Draw"),
                color_attachments: &[
                    load_color_attachment(&gbuffer.default_view),
                    load_color_attachment(&lighting_pass_id.default_view),
                ],
                depth_stencil_attachment: load_depth_attachment(&depth.view),
            });

            // DRAW LARGE UNITS
            render_pass.set_render_pipeline(pipeline);
            render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);
            render_pass.draw(
                0..LARGE_UNITS_DATA_WIDTH * LARGE_UNITS_TEXTURE_HEIGHT * 6,
                0..1,
            );
        }
        Ok(())
    }
}

#[derive(Resource)]
struct UnitPipeline {
    sampler: Sampler,
    update_layout: BindGroupLayout,
    draw_layout: BindGroupLayout,
    update_pipeline_id: CachedRenderPipelineId,
    large_update_layout: BindGroupLayout,
    large_update_pipeline_id: CachedRenderPipelineId,
    draw_pipeline_id: CachedRenderPipelineId,
    evaluate_pipeline_id: CachedRenderPipelineId,
    evaluate_layout: BindGroupLayout,
    draw_projectiles_pipeline_id: CachedRenderPipelineId,
    large_draw_pipeline_id: CachedRenderPipelineId,
    large_unit_draw_layout: BindGroupLayout,
}

impl FromWorld for UnitPipeline {
    fn from_world(world: &mut World) -> Self {
        let mut shader_defs = Vec::new();
        shader_defs.extend_from_slice(&[
            shader_def_uint!(MINIMAP_SCALE),
            shader_def_uint!(UNITS_DATA_WIDTH),
            shader_def_uint!(UNITS_DATA_HEIGHT),
            shader_def_uint!(LARGE_UNITS_DATA_WIDTH),
            shader_def_uint!(LARGE_UNITS_TEXTURE_WIDTH),
            shader_def_uint!(LARGE_UNITS_TEXTURE_HEIGHT),
            shader_def_uint!(ATTACK_RADIUS),
        ]);

        let render_device = world.resource::<RenderDevice>();

        let layout_descriptor = &BindGroupLayoutDescriptor {
            label: Some("unit_bind_group_layout"),
            entries: &[
                view_layout_entry(0),
                globals_layout_entry(9),
                utexture_layout_entry(101, TextureViewDimension::D2), // Prev Particle State
                uniform_layout_entry(102, UnitCommand::min_size()),
                utexture_layout_entry(103, TextureViewDimension::D2), // Prev Attack data
                ftexture_layout_entry(104, TextureViewDimension::D2Array), // Unit Material Texture
                fsampler_layout_entry(105),
                utexture_layout_entry(106, TextureViewDimension::D2), // Prev Large Unit Data
                ftexture_layout_entry(107, TextureViewDimension::D2Array), // Unit Material Texture
                utexture_layout_entry(108, TextureViewDimension::D2), // Minimap sm
                utexture_layout_entry(109, TextureViewDimension::D2), // Minimap sm3
            ],
        };

        let evaluate_layout = render_device.create_bind_group_layout(layout_descriptor);
        let update_layout = render_device.create_bind_group_layout(layout_descriptor);
        let large_update_layout = render_device.create_bind_group_layout(layout_descriptor);
        let draw_layout = render_device.create_bind_group_layout(layout_descriptor);
        let large_unit_draw_layout = render_device.create_bind_group_layout(layout_descriptor);

        let sampler = nearest_sampler(render_device);

        let evaluate_pipeline_id = basic_fullscreen_tri_pipeline(
            "unit_evaluate_pipeline",
            "shaders/unit_evaluate.wgsl",
            world,
            &evaluate_layout,
            shader_defs.clone(),
            vec![
                opaque_target(UNITS_DATA_FORMAT),
                opaque_target(UNITS_ATTACK_FORMAT),
            ],
        );

        let update_pipeline_id = basic_fullscreen_tri_pipeline(
            "unit_update_pipeline",
            "shaders/unit_update.wgsl",
            world,
            &update_layout,
            shader_defs.clone(),
            vec![opaque_target(UNITS_DATA_FORMAT)],
        );

        let large_update_pipeline_id = basic_fullscreen_tri_pipeline(
            "large_unit_update_pipeline",
            "shaders/large_unit_update.wgsl",
            world,
            &update_layout,
            shader_defs.clone(),
            vec![opaque_target(LARGE_UNITS_DATA_FORMAT)],
        );

        let draw_pipeline_id = basic_opaque_pipeline(
            "unit_draw_pipeline",
            "shaders/unit_material.wgsl",
            world,
            &draw_layout,
            shader_defs.clone(),
            vec![
                opaque_target(DEFERRED_PREPASS_FORMAT),
                opaque_target(DEFERRED_LIGHTING_PASS_ID_FORMAT),
            ],
        );

        let draw_projectiles_pipeline_id = basic_opaque_pipeline(
            "unit_projectile_draw_pipeline",
            "shaders/unit_projectile_material.wgsl",
            world,
            &draw_layout,
            shader_defs.clone(),
            vec![
                opaque_target(DEFERRED_PREPASS_FORMAT),
                opaque_target(DEFERRED_LIGHTING_PASS_ID_FORMAT),
            ],
        );

        let large_draw_pipeline_id = basic_opaque_pipeline(
            "large_unit_draw_pipeline",
            "shaders/large_unit_material.wgsl",
            world,
            &draw_layout,
            shader_defs,
            vec![
                opaque_target(DEFERRED_PREPASS_FORMAT),
                opaque_target(DEFERRED_LIGHTING_PASS_ID_FORMAT),
            ],
        );

        Self {
            sampler,
            draw_layout,
            draw_pipeline_id,
            update_layout,
            update_pipeline_id,
            large_update_layout,
            large_update_pipeline_id,
            evaluate_layout,
            evaluate_pipeline_id,
            draw_projectiles_pipeline_id,
            large_draw_pipeline_id,
            large_unit_draw_layout,
        }
    }
}

#[derive(Resource)]
pub struct UnitsDataTextures {
    pub a: CachedTexture,
    pub b: CachedTexture,
    pub attack_a: CachedTexture,
    pub attack_b: CachedTexture,
    pub large_unit_a: CachedTexture,
    pub large_unit_b: CachedTexture,
}

fn prepare_textures(
    mut commands: Commands,
    mut texture_cache: ResMut<TextureCache>,
    render_device: Res<RenderDevice>,
    views: Query<(Entity, &ExtractedCamera, &ExtractedView), With<UnitsPass>>,
    frame_count: Res<FrameCount>,
) {
    for (_entity, _camera, _view) in &views {
        let mut texture_descriptor = TextureDescriptor {
            label: None,
            size: Extent3d {
                depth_or_array_layers: 1,
                width: UNITS_DATA_WIDTH,
                height: UNITS_DATA_HEIGHT,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: TextureDimension::D2,
            format: UNITS_DATA_FORMAT,
            usage: TextureUsages::RENDER_ATTACHMENT
                | TextureUsages::TEXTURE_BINDING
                | TextureUsages::COPY_DST,
            view_formats: &[],
        };

        texture_descriptor.label = Some("unit_data_a");
        let unit_data_texture_a = texture_cache.get(&render_device, texture_descriptor.clone());
        texture_descriptor.label = Some("unit_data_b");
        let unit_data_texture_b = texture_cache.get(&render_device, texture_descriptor.clone());

        texture_descriptor.format = UNITS_ATTACK_FORMAT;
        texture_descriptor.label = Some("unit_attack_map_a");
        let unit_attack_texture_a = texture_cache.get(&render_device, texture_descriptor.clone());
        texture_descriptor.label = Some("unit_attack_map_b");
        let unit_attack_texture_b = texture_cache.get(&render_device, texture_descriptor.clone());

        texture_descriptor.format = LARGE_UNITS_DATA_FORMAT;
        texture_descriptor.size = Extent3d {
            depth_or_array_layers: 1,
            width: LARGE_UNITS_TEXTURE_WIDTH,
            height: LARGE_UNITS_TEXTURE_HEIGHT,
        };
        texture_descriptor.label = Some("large_unit_data_a");
        let large_unit_data_texture_a =
            texture_cache.get(&render_device, texture_descriptor.clone());
        texture_descriptor.label = Some("large_unit_data_b");
        let large_unit_data_texture_b =
            texture_cache.get(&render_device, texture_descriptor.clone());

        let textures = if frame_count.0 % 2 == 0 {
            UnitsDataTextures {
                a: unit_data_texture_a,
                b: unit_data_texture_b,
                attack_a: unit_attack_texture_a,
                attack_b: unit_attack_texture_b,
                large_unit_a: large_unit_data_texture_a,
                large_unit_b: large_unit_data_texture_b,
            }
        } else {
            UnitsDataTextures {
                // Using the same for both unit data a/b since a flip flop happens in the node
                a: unit_data_texture_a,
                b: unit_data_texture_b,
                attack_a: unit_attack_texture_b,
                attack_b: unit_attack_texture_a,
                large_unit_a: large_unit_data_texture_b,
                large_unit_b: large_unit_data_texture_a,
            }
        };
        commands.insert_resource(textures);
    }
}

fn clear_unit_command(mut unit_command: ResMut<UnitCommand>) {
    *unit_command = UnitCommand::default();
}
