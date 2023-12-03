#![allow(clippy::too_many_arguments, clippy::type_complexity)]

pub mod bind_group_utils;
pub mod particles;

use std::f32::consts::FRAC_PI_4;

use bevy::{
    core::cast_slice,
    core_pipeline::prepass::{DeferredPrepass, DepthPrepass},
    math::*,
    pbr::{CascadeShadowConfigBuilder, DefaultOpaqueRendererMethod, PbrPlugin},
    prelude::*,
    render::{
        mesh::Indices,
        render_resource::{
            AsBindGroup, Extent3d, PrimitiveTopology, ShaderRef, TextureDimension, TextureFormat,
        },
    },
};
use bevy_basic_camera::{CameraController, CameraControllerPlugin};
use bevy_mod_taa::{TAABundle, TAAPlugin};
use bevy_ridiculous_ssgi::{ssgi::SSGIPass, SSGIBundle, SSGIPlugin};
use particles::{ParticlesPass, ParticlesPlugin};

fn main() {
    App::new()
        .insert_resource(Msaa::Off)
        .insert_resource(ClearColor(Color::rgb(0.0, 0.0, 0.0)))
        .insert_resource(AmbientLight {
            color: Color::rgb(1.0, 1.0, 1.0),
            brightness: 0.0,
        })
        .insert_resource(DefaultOpaqueRendererMethod::deferred())
        .add_plugins(DefaultPlugins.set(PbrPlugin {
            add_default_deferred_lighting_plugin: false,
            ..default()
        }))
        .add_plugins((
            CameraControllerPlugin,
            ParticlesPlugin,
            TAAPlugin,
            SSGIPlugin,
        ))
        .add_systems(Startup, setup)
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
                render_scale: 4,
                cascade_0_directions: 8,
                interval_overlap: 0.1,
                mip_min: 3.0,
                mip_max: 4.0,
                divide_steps_by_square_of_cascade_exp: false,
                backside_illumination: 2.0,
                rough_specular: 2.0,
                rough_specular_sharpness: 2.0,
                ..default()
            },
            ..default()
        });
}
