#![allow(clippy::too_many_arguments, clippy::type_complexity)]

pub mod bind_group_utils;
pub mod particles;

use std::f32::consts::FRAC_PI_4;

use bevy::{
    core::cast_slice,
    core_pipeline::prepass::{DeferredPrepass, DepthPrepass},
    diagnostic::{FrameTimeDiagnosticsPlugin, LogDiagnosticsPlugin},
    math::*,
    pbr::{CascadeShadowConfigBuilder, DefaultOpaqueRendererMethod, PbrPlugin},
    prelude::*,
    render::{
        mesh::Indices,
        render_resource::{
            AsBindGroup, Extent3d, PrimitiveTopology, ShaderRef, TextureDimension, TextureFormat,
        },
    },
    window::PresentMode,
};
use bevy_basic_camera::{CameraController, CameraControllerPlugin};
use bevy_mod_taa::{TAABundle, TAAPlugin};
use bevy_ridiculous_ssgi::{ssgi::SSGIPass, SSGIBundle, SSGIPlugin};
use particles::{ParticleCommand, ParticlesPass, ParticlesPlugin};
use shared_exponent_formats::{rgb9e5::vec3_to_rgb9e5, xyz8e5::vec3_to_xyz8e5};

fn main() {
    App::new()
        .insert_resource(Msaa::Off)
        .insert_resource(ClearColor(Color::rgb(0.0, 0.0, 0.0)))
        .insert_resource(AmbientLight {
            color: Color::rgb(1.0, 1.0, 1.0),
            brightness: 0.0,
        })
        .insert_resource(DefaultOpaqueRendererMethod::deferred())
        .add_plugins(
            DefaultPlugins
                .set(PbrPlugin {
                    add_default_deferred_lighting_plugin: true,
                    ..default()
                })
                .set(WindowPlugin {
                    primary_window: Some(Window {
                        present_mode: PresentMode::AutoNoVsync,
                        ..default()
                    }),
                    ..default()
                }),
        )
        .add_plugins((
            CameraControllerPlugin,
            ParticlesPlugin,
            TAAPlugin,
            //SSGIPlugin,
            LogDiagnosticsPlugin::default(),
            FrameTimeDiagnosticsPlugin::default(),
        ))
        .add_systems(Startup, setup)
        .add_systems(Update, restart_particle_system)
        .run();
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    // circular base
    commands.spawn(PbrBundle {
        mesh: meshes.add(shape::Circle::new(100.0).into()),
        material: materials.add(Color::rgb(0.6, 0.6, 0.6).into()),
        transform: Transform::from_rotation(Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2)),
        ..default()
    });

    commands.spawn(PbrBundle {
        mesh: meshes.add(Mesh::from(shape::Cube { size: 2.0 })),
        material: materials.add(Color::rgb(0.6, 0.6, 0.6).into()),
        transform: Transform::from_xyz(0.0, 1.0, 0.0),
        ..default()
    });

    // light
    //commands.spawn(DirectionalLightBundle {
    //    directional_light: DirectionalLight {
    //        shadows_enabled: true,
    //        illuminance: 100000.0,
    //        ..default()
    //    },
    //    cascade_shadow_config: CascadeShadowConfigBuilder {
    //        num_cascades: 2,
    //        maximum_distance: 20.0,
    //        ..default()
    //    }
    //    .into(),
    //    transform: Transform::from_rotation(Quat::from_euler(EulerRot::ZYX, 0.0, 0.0, -FRAC_PI_4)),
    //    ..default()
    //});

    // camera
    commands
        .spawn((
            Camera3dBundle {
                camera: Camera {
                    hdr: true,
                    ..default()
                },
                transform: Transform::from_xyz(9.0, 3.0, 9.0).looking_at(Vec3::Y, Vec3::Y),
                ..default()
            },
            ParticlesPass,
            DeferredPrepass,
            DepthPrepass,
        ))
        .insert(CameraController::default())
        .insert(TAABundle::sample8())
        .insert(SSGIBundle {
            ssgi_pass: SSGIPass {
                brightness: 1.0,
                square_falloff: true,
                horizon_occlusion: 100.0,
                render_scale: 6,
                cascade_0_directions: 8,
                interval_overlap: 0.1,
                mip_min: 3.0,
                mip_max: 4.0,
                divide_steps_by_square_of_cascade_exp: false,
                backside_illumination: 0.0,
                rough_specular: 1.0,
                rough_specular_sharpness: 1.0,
                ..default()
            },
            ..default()
        });
}

fn restart_particle_system(mut commands: Commands, mouse_button_input: Res<Input<MouseButton>>) {
    if mouse_button_input.just_pressed(MouseButton::Left) {
        commands.spawn(ParticleCommand {
            spawn_position: vec3(0.0, 10.0, 0.0),
            spawn_spread: vec3_to_rgb9e5(vec3(2.0, 2.0, 2.0).into()),
            velocity: vec3_to_xyz8e5(vec3(0.0, 0.01, 0.01).into()),
            direction_random_spread: 0.8,
            category: 0u32,
            flags: 0u32,
            color1_: 0u32,
            color2_: 0u32,
            _webgl2_padding_1_: 0.0,
            _webgl2_padding_2_: 0.0,
        });
    }
}
