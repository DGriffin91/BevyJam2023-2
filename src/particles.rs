use bevy::{
    core::FrameCount,
    core_pipeline::{
        core_3d::{self, CORE_3D_DEPTH_FORMAT},
        deferred::{DEFERRED_LIGHTING_PASS_ID_FORMAT, DEFERRED_PREPASS_FORMAT},
        fullscreen_vertex_shader::fullscreen_shader_vertex_state,
        prepass::ViewPrepassTextures,
    },
    ecs::query::QueryItem,
    prelude::*,
    render::{
        camera::ExtractedCamera,
        extract_component::{ExtractComponent, ExtractComponentPlugin},
        extract_resource::{ExtractResource, ExtractResourcePlugin},
        mesh::Indices,
        render_graph::{
            NodeRunError, RenderGraphApp, RenderGraphContext, ViewNode, ViewNodeRunner,
        },
        render_resource::{
            BindGroupEntries, BindGroupLayout, BindGroupLayoutDescriptor, BufferInitDescriptor,
            BufferUsages, CachedRenderPipelineId, ColorTargetState, ColorWrites, CompareFunction,
            DepthBiasState, DepthStencilState, Extent3d, FragmentState, IndexFormat, LoadOp,
            MultisampleState, Operations, PipelineCache, PrimitiveState, RenderPassColorAttachment,
            RenderPassDepthStencilAttachment, RenderPassDescriptor, RenderPipelineDescriptor,
            ShaderType, StencilState, TextureDescriptor, TextureDimension, TextureFormat,
            TextureUsages, TextureViewDimension, VertexState,
        },
        renderer::{RenderContext, RenderDevice},
        texture::{CachedTexture, TextureCache},
        view::{ExtractedView, ViewDepthTexture, ViewTarget, ViewUniformOffset},
        Extract, Render, RenderApp, RenderSet,
    },
};

use crate::bind_group_utils::{
    ftexture_layout_entry, globals_binding, globals_layout_entry, uniform_buffer,
    uniform_layout_entry, view_binding, view_layout_entry,
};

const PARTICLES_DATA_FORMAT: TextureFormat = TextureFormat::Rgba32Float;
const PARTICLES_PASS_WIDTH: u32 = 256;
const PARTICLES_PASS_HEIGHT: u32 = 128;

#[derive(Component, Clone, ExtractComponent, Copy, ShaderType, Debug, Default)]
pub struct ParticleCommand {
    pub spawn_position: Vec3,
    pub spawn_spread: u32, //rgb9e5
    pub velocity: u32,     //xyz8e5
    /// 0.0 for hemisphere, -1.0 for sphere
    pub direction_random_spread: f32,
    pub category: u32,
    pub flags: u32,
    pub color1_: u32, //rgb9e5
    pub color2_: u32, //rgb9e5
    pub _webgl2_padding_1_: f32,
    pub _webgl2_padding_2_: f32,
}

#[derive(Resource, ExtractResource, Clone, Copy, ShaderType, Debug, Default)]
struct ParticleCommands {
    pub commands: [ParticleCommand; 12],
}

#[derive(Clone, Debug, Copy, Default, ShaderType)]
struct ParticleSystem {
    pub age: f32,
    pub command_assignment: u32,
    padding_1_: f32,
    padding_2_: f32,
}

#[derive(Resource, ExtractResource, Clone, Copy, ShaderType, Debug)]
struct ParticleSystems {
    pub systems: [ParticleSystem; 128],
}

impl Default for ParticleSystems {
    fn default() -> Self {
        Self {
            systems: [ParticleSystem::default(); 128],
        }
    }
}

pub struct ParticlesPlugin;

impl Plugin for ParticlesPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(PostUpdate, queue_particle_commands)
            .init_resource::<ParticleCommands>()
            .init_resource::<ParticleSystems>()
            .add_plugins((
                ExtractResourcePlugin::<ParticleCommands>::default(),
                ExtractResourcePlugin::<ParticleSystems>::default(),
                ExtractComponentPlugin::<ParticlesPass>::default(),
            ))
            .add_plugins(ExtractComponentPlugin::<ParticleCommand>::default());
        let Ok(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app
            .add_systems(Render, prepare_textures.in_set(RenderSet::PrepareResources))
            .add_render_graph_node::<ViewNodeRunner<ParticlesNode>>(
                core_3d::graph::NAME,
                ParticlesNode::NAME,
            )
            .add_render_graph_edges(
                core_3d::graph::NAME,
                &[
                    core_3d::graph::node::DEFERRED_PREPASS,
                    ParticlesNode::NAME,
                    core_3d::graph::node::COPY_DEFERRED_LIGHTING_ID,
                ],
            );
    }

    fn finish(&self, app: &mut App) {
        let Ok(render_app) = app.get_sub_app_mut(RenderApp) else {
            return;
        };

        render_app.init_resource::<ParticlesPipeline>();
    }
}

#[derive(Component, ExtractComponent, Clone, Reflect)]
pub struct ParticlesPass;

#[derive(Default)]
struct ParticlesNode;
impl ParticlesNode {
    pub const NAME: &'static str = "deferred_particles_pass";
}

impl ViewNode for ParticlesNode {
    type ViewQuery = (
        &'static ViewUniformOffset,
        &'static ViewTarget,
        &'static ViewDepthTexture,
        &'static ViewPrepassTextures,
        &'static ParticlesDataTextures,
    );

    fn run(
        &self,
        _graph: &mut RenderGraphContext,
        render_context: &mut RenderContext,
        (
            view_uniform_offset,_view_target, depth, view_prepass_textures, particles_data_texture): QueryItem<
            Self::ViewQuery,
        >,
        world: &World,
    ) -> Result<(), NodeRunError> {
        let particles_pipeline = world.resource::<ParticlesPipeline>();
        let particle_commands = world.resource::<ParticleCommands>();
        let particle_systems = world.resource::<ParticleSystems>();

        let pipeline_cache = world.resource::<PipelineCache>();

        let gbuffer = view_prepass_textures.deferred.clone().unwrap();
        let lighting_pass_id = view_prepass_textures
            .deferred_lighting_pass_id
            .clone()
            .unwrap();
        // ---------------------------------------
        // Particles Update
        // ---------------------------------------

        let commands_uniform = uniform_buffer(
            particle_commands,
            render_context,
            "Particle Commands Uniform",
        );

        let systems_uniform =
            uniform_buffer(particle_systems, render_context, "Particle Systems Uniform");

        {
            let Some(pipeline) =
                pipeline_cache.get_render_pipeline(particles_pipeline.update_pipeline_id)
            else {
                return Ok(());
            };

            let bind_group = render_context.render_device().create_bind_group(
                "particles_bind_group",
                &particles_pipeline.update_layout,
                &BindGroupEntries::with_indices((
                    (0, view_binding(world)),
                    (9, globals_binding(world)),
                    (101, &particles_data_texture.read.default_view),
                    (102, commands_uniform.as_entire_binding()),
                    (103, systems_uniform.as_entire_binding()),
                )),
            );

            let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
                label: Some("particles_pass"),
                color_attachments: &[Some(RenderPassColorAttachment {
                    view: &particles_data_texture.write.default_view,
                    resolve_target: None,
                    ops: Operations::default(),
                })],
                depth_stencil_attachment: None,
            });

            render_pass.set_render_pipeline(pipeline);
            render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);

            render_pass.draw(0..3, 0..1);
        }
        // ---------------------------------------
        // Particles Draw
        // ---------------------------------------
        {
            let Some(pipeline) =
                pipeline_cache.get_render_pipeline(particles_pipeline.draw_pipeline_id)
            else {
                return Ok(());
            };

            let bind_group = render_context.render_device().create_bind_group(
                "particles_bind_group",
                &particles_pipeline.draw_layout,
                &BindGroupEntries::with_indices((
                    (0, view_binding(world)),
                    (9, globals_binding(world)),
                    (101, &particles_data_texture.write.default_view),
                    (102, commands_uniform.as_entire_binding()),
                    (103, systems_uniform.as_entire_binding()),
                )),
            );

            let mut render_pass = render_context.begin_tracked_render_pass(RenderPassDescriptor {
                label: Some("particles_pass"),
                color_attachments: &[
                    Some(RenderPassColorAttachment {
                        view: &gbuffer.default_view,
                        resolve_target: None,
                        ops: Operations {
                            load: LoadOp::Load,
                            store: true,
                        },
                    }),
                    Some(RenderPassColorAttachment {
                        view: &lighting_pass_id.default_view,
                        resolve_target: None,
                        ops: Operations {
                            load: LoadOp::Load,
                            store: true,
                        },
                    }),
                ],
                depth_stencil_attachment: Some(RenderPassDepthStencilAttachment {
                    view: &depth.view,
                    depth_ops: Some(Operations {
                        load: LoadOp::Load,
                        store: true,
                    }),
                    stencil_ops: None,
                }),
            });

            render_pass.set_render_pipeline(pipeline);
            render_pass.set_bind_group(0, &bind_group, &[view_uniform_offset.offset]);
            render_pass.draw(0..PARTICLES_PASS_WIDTH * PARTICLES_PASS_WIDTH * 6, 0..1);
        }

        Ok(())
    }
}

#[derive(Resource)]
struct ParticlesPipeline {
    update_layout: BindGroupLayout,
    draw_layout: BindGroupLayout,
    update_pipeline_id: CachedRenderPipelineId,
    draw_pipeline_id: CachedRenderPipelineId,
}

impl FromWorld for ParticlesPipeline {
    fn from_world(world: &mut World) -> Self {
        let render_device = world.resource::<RenderDevice>();

        let update_layout = render_device.create_bind_group_layout(&BindGroupLayoutDescriptor {
            label: Some("particles_update_bind_group_layout"),
            entries: &[
                view_layout_entry(0),
                globals_layout_entry(9),
                ftexture_layout_entry(101, TextureViewDimension::D2), // Prev Particle State
                uniform_layout_entry(102, ParticleCommands::min_size()),
                uniform_layout_entry(103, ParticleCommands::min_size()),
            ],
        });

        let draw_layout = render_device.create_bind_group_layout(&BindGroupLayoutDescriptor {
            label: Some("particles_draw_bind_group_layout"),
            entries: &[
                view_layout_entry(0),
                globals_layout_entry(9),
                ftexture_layout_entry(101, TextureViewDimension::D2), // Current Particle State
                uniform_layout_entry(102, ParticleCommands::min_size()),
                uniform_layout_entry(103, ParticleCommands::min_size()),
            ],
        });
        let shader = world
            .resource::<AssetServer>()
            .load("shaders/particles_update.wgsl");

        let update_pipeline_id =
            world
                .resource_mut::<PipelineCache>()
                .queue_render_pipeline(RenderPipelineDescriptor {
                    label: Some("particles_update_pipeline".into()),
                    layout: vec![update_layout.clone()],

                    vertex: fullscreen_shader_vertex_state(),
                    fragment: Some(FragmentState {
                        shader: shader.clone(),
                        shader_defs: vec![],

                        entry_point: "fragment".into(),
                        targets: vec![Some(ColorTargetState {
                            format: PARTICLES_DATA_FORMAT,
                            blend: None,
                            write_mask: ColorWrites::ALL,
                        })],
                    }),

                    primitive: PrimitiveState::default(),
                    depth_stencil: None,
                    multisample: MultisampleState::default(),
                    push_constant_ranges: vec![],
                });

        let shader = world
            .resource::<AssetServer>()
            .load("shaders/particles_material.wgsl");

        let draw_pipeline_id =
            world
                .resource_mut::<PipelineCache>()
                .queue_render_pipeline(RenderPipelineDescriptor {
                    label: Some("particles_draw_pipeline".into()),
                    layout: vec![draw_layout.clone()],

                    vertex: VertexState {
                        shader: shader.clone(),
                        shader_defs: Vec::new(),
                        entry_point: "vertex".into(),
                        buffers: Vec::new(),
                    },
                    fragment: Some(FragmentState {
                        shader: shader.clone(),
                        shader_defs: vec![],

                        entry_point: "fragment".into(),
                        targets: vec![
                            Some(ColorTargetState {
                                format: DEFERRED_PREPASS_FORMAT,
                                blend: None,
                                write_mask: ColorWrites::ALL,
                            }),
                            Some(ColorTargetState {
                                format: DEFERRED_LIGHTING_PASS_ID_FORMAT,
                                blend: None,
                                write_mask: ColorWrites::ALL,
                            }),
                        ],
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

        Self {
            draw_layout,
            draw_pipeline_id,
            update_layout,
            update_pipeline_id,
        }
    }
}

#[derive(Component)]
pub struct ParticlesDataTextures {
    pub read: CachedTexture,
    pub write: CachedTexture,
}

fn prepare_textures(
    mut commands: Commands,
    mut texture_cache: ResMut<TextureCache>,
    render_device: Res<RenderDevice>,
    views: Query<(Entity, &ExtractedCamera, &ExtractedView), With<ParticlesPass>>,
    frame_count: Res<FrameCount>,
) {
    for (entity, _camera, _view) in &views {
        let mut texture_descriptor = TextureDescriptor {
            label: None,
            size: Extent3d {
                depth_or_array_layers: 1,
                width: PARTICLES_PASS_WIDTH,
                height: PARTICLES_PASS_HEIGHT,
            },
            mip_level_count: 1,
            sample_count: 1,
            dimension: TextureDimension::D2,
            format: PARTICLES_DATA_FORMAT,
            usage: TextureUsages::RENDER_ATTACHMENT
                | TextureUsages::TEXTURE_BINDING
                | TextureUsages::COPY_DST,
            view_formats: &[],
        };

        texture_descriptor.label = Some("particles_data_a");
        let ssgi_resolve_texture_a = texture_cache.get(&render_device, texture_descriptor.clone());
        texture_descriptor.label = Some("particles_data_b");
        let ssgi_resolve_texture_b = texture_cache.get(&render_device, texture_descriptor.clone());

        let textures = if frame_count.0 % 2 == 0 {
            ParticlesDataTextures {
                write: ssgi_resolve_texture_a,
                read: ssgi_resolve_texture_b,
            }
        } else {
            ParticlesDataTextures {
                write: ssgi_resolve_texture_b,
                read: ssgi_resolve_texture_a,
            }
        };
        commands.entity(entity).insert(textures);
    }
}

fn queue_particle_commands(
    time: Res<Time>,
    mut commands: Commands,
    mut particle_commands: ResMut<ParticleCommands>,
    particle_command_entites: Query<(Entity, &ParticleCommand)>,
    mut particle_systems: ResMut<ParticleSystems>,
) {
    for system in &mut particle_systems.systems {
        // Age systems
        system.age += time.delta_seconds();
        // Reset command indices from last frame
        system.command_assignment = u32::MAX;
    }
    let mut new_cmd_iter = particle_command_entites.iter();
    for (command_n, command) in particle_commands.commands.iter_mut().enumerate() {
        let next = new_cmd_iter.next();
        if let Some((entity, new_command)) = next {
            *command = *new_command;
            commands.entity(entity).despawn_recursive();
            let mut oldest = 0;
            let mut oldest_time = 0.0;
            // TODO *very* inefficient
            for (i, system) in particle_systems.systems.iter().enumerate() {
                if system.age > oldest_time {
                    oldest = i;
                    oldest_time = system.age;
                }
            }
            // Reset age and assign new command
            particle_systems.systems[oldest].command_assignment = command_n as u32;
            particle_systems.systems[oldest].age = 0.0;
            dbg!(oldest, particle_systems.systems[oldest].command_assignment);
        } else {
            *command = ParticleCommand::default();
        }
    }
}
