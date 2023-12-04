#![allow(clippy::too_many_arguments, clippy::type_complexity)]

pub mod bind_group_utils;
pub mod particles;
pub mod units;

use bevy::{
    asset::AssetMetaCheck,
    core_pipeline::prepass::{DeferredPrepass, DepthPrepass},
    diagnostic::{FrameTimeDiagnosticsPlugin, LogDiagnosticsPlugin},
    math::*,
    pbr::{DefaultOpaqueRendererMethod, PbrPlugin},
    prelude::*,
    window::{PresentMode, PrimaryWindow},
};
use bevy_basic_camera::{CameraController, CameraControllerPlugin};
use bevy_mod_taa::{TAABundle, TAAPlugin};
use bevy_ridiculous_ssgi::{ssgi::SSGIPass, SSGIBundle, SSGIPlugin};
use particles::{ParticleCommand, ParticlesPass, ParticlesPlugin};
use shared_exponent_formats::{rgb9e5::vec3_to_rgb9e5, xyz8e5::vec3_to_xyz8e5};
use units::{UnitCommand, UnitsPass, UnitsPlugin};

fn main() {
    App::new()
        .insert_resource(AssetMetaCheck::Never)
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
                        present_mode: PresentMode::AutoVsync,
                        ..default()
                    }),
                    ..default()
                }),
        )
        .add_plugins((
            CameraControllerPlugin,
            //ParticlesPlugin,
            UnitsPlugin,
            TAAPlugin,
            //SSGIPlugin,
            LogDiagnosticsPlugin::default(),
            FrameTimeDiagnosticsPlugin::default(),
        ))
        .add_systems(Startup, setup)
        .add_systems(Update, (restart_particle_system, command_units))
        .run();
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
) {
    //// circular base
    //commands.spawn(PbrBundle {
    //    mesh: meshes.add(shape::Circle::new(100.0).into()),
    //    material: materials.add(Color::rgb(0.6, 0.6, 0.6).into()),
    //    transform: Transform::from_rotation(Quat::from_rotation_x(-std::f32::consts::FRAC_PI_2)),
    //    ..default()
    //});
    //
    //commands.spawn(PbrBundle {
    //    mesh: meshes.add(Mesh::from(shape::Cube { size: 2.0 })),
    //    material: materials.add(Color::rgb(0.6, 0.6, 0.6).into()),
    //    transform: Transform::from_xyz(0.0, 1.0, 0.0),
    //    ..default()
    //});

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
                transform: Transform::from_xyz(-30.0, 200.0, -30.0)
                    .looking_at(vec3(150.8, 0.0, 150.8), Vec3::Y),
                ..default()
            },
            ParticlesPass,
            DeferredPrepass,
            DepthPrepass,
            UnitsPass,
        ))
        .insert(CameraController {
            mouse_key_enable_mouse: MouseButton::Middle,
            run_speed: 150.0,
            walk_speed: 50.0,
            ..default()
        })
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

pub fn from_screenspace(
    cursor_pos_screen: Vec2,
    camera: &Camera,
    camera_transform: &GlobalTransform,
    window: &Window,
) -> Option<Ray> {
    let mut viewport_pos = cursor_pos_screen;
    if let Some(viewport) = &camera.viewport {
        viewport_pos -= viewport.physical_position.as_vec2() / window.scale_factor() as f32;
    }
    camera.viewport_to_world(camera_transform, viewport_pos)
}

fn ray_plane_intersection(ray: Ray, plane_point: Vec3, plane_normal: Vec3) -> Option<Vec3> {
    let denominator = plane_normal.dot(ray.direction);
    if denominator.abs() < 1e-6 {
        return None; // Ray is parallel to the plane
    }

    let t = plane_normal.dot(plane_point - ray.origin) / denominator;
    if t < 0.0 {
        return None; // Intersection is behind the ray origin
    }

    Some(ray.origin + ray.direction * t)
}

fn command_units(
    mouse_button_input: Res<Input<MouseButton>>,
    window: Query<&Window, With<PrimaryWindow>>,
    cameras: Query<(&Camera, &GlobalTransform)>,
    mut unit_command: ResMut<UnitCommand>,
    //mut select_start: Local<Option<Vec3>>,
    //mut select_end: Local<Option<Vec3>>,
) {
    let window = window.get_single().unwrap();
    if let Some((camera, transform)) = cameras.iter().next() {
        if mouse_button_input.just_pressed(MouseButton::Right) {
            let ray = window
                .cursor_position()
                .and_then(|cursor_pos| from_screenspace(cursor_pos, camera, transform, window));
            if let Some(ray) = ray {
                let intersection =
                    ray_plane_intersection(ray, vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0));
                if let Some(intersection) = intersection {
                    if intersection.x > 0.0 && intersection.z > 0.0 {
                        unit_command.dest = uvec2(intersection.x as u32, intersection.z as u32);
                        unit_command.command = 1u32;
                    }
                }
            }
        }
    }
}
