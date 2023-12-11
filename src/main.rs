#![allow(clippy::too_many_arguments, clippy::type_complexity)]

pub mod bind_group_utils;
pub mod camera_controller;
pub mod minimap;
pub mod particles;
pub mod post_process;
pub mod ui;
pub mod units;

use bevy::{
    asset::AssetMetaCheck,
    core_pipeline::prepass::{DeferredPrepass, DepthPrepass, MotionVectorPrepass},
    diagnostic::{FrameTimeDiagnosticsPlugin, LogDiagnosticsPlugin},
    math::*,
    pbr::{DefaultOpaqueRendererMethod, NotShadowCaster, PbrPlugin},
    prelude::*,
    render::{
        extract_resource::{ExtractResource, ExtractResourcePlugin},
        view::{ColorGrading, RenderLayers},
    },
    window::{PresentMode, PrimaryWindow},
};

use bevy_mod_taa::{TAAPlugin, TAASettings};
use bevy_picoui::{pico::Pico2dCamera, PicoPlugin};
use bevy_ridiculous_ssgi::{ssgi::SSGIPass, SSGIBundle};
use camera_controller::{OrthoCameraController, OrthoCameraControllerPlugin};
use minimap::{MinimapPass, MinimapPlugin};
use particles::{ParticleCommand, ParticlesPass, ParticlesPlugin};
use post_process::PostProcessPlugin;
use shared_exponent_formats::{rgb9e5::vec3_to_rgb9e5, xyz8e5::vec3_to_xyz8e5};
use ui::UIPlugin;
use units::{UnitCommand, UnitsPass, UnitsPlugin};

fn main() {
    App::new()
        .insert_resource(AssetMetaCheck::Never)
        .insert_resource(Msaa::Off)
        .insert_resource(ClearColor(Color::rgb(0.0, 0.0, 0.0)))
        .insert_resource(AmbientLight {
            color: Color::rgb(1.0, 1.0, 1.0),
            brightness: 0.5,
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
        // Put gizmos on layer 1 so they don't show up on the 2d camera
        .insert_resource(GizmoConfig {
            render_layers: RenderLayers::layer(1),
            ..default()
        })
        .add_plugins((
            OrthoCameraControllerPlugin,
            ParticlesPlugin,
            UnitsPlugin,
            TAAPlugin,
            MinimapPlugin,
            //SSGIPlugin, // If you turn this off use the default lighting plugin
            PostProcessPlugin,
            LogDiagnosticsPlugin::default(),
            FrameTimeDiagnosticsPlugin,
            ExtractResourcePlugin::<UnitTexture>::default(),
            PicoPlugin::default(),
            UIPlugin,
        ))
        .add_systems(Startup, (setup, load_unit_texture))
        .add_systems(Update, (restart_particle_system, command_units))
        .run();
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut materials: ResMut<Assets<StandardMaterial>>,
    asset_server: Res<AssetServer>,
) {
    // Water
    commands.spawn(PbrBundle {
        mesh: meshes.add(
            shape::Plane {
                size: 10000.0,
                subdivisions: 0,
            }
            .into(),
        ),
        material: materials.add(StandardMaterial {
            base_color: Vec4::splat(0.01).into(),
            reflectance: 0.01,
            ..default()
        }),
        ..default()
    });

    //commands.spawn(PbrBundle {
    //    mesh: meshes.add(Mesh::from(shape::Cube { size: 2.0 })),
    //    material: materials.add(Color::rgb(0.6, 0.6, 0.6).into()),
    //    transform: Transform::from_xyz(0.0, 1.0, 0.0),
    //    ..default()
    //});

    // vvv Lighting is broken without this, don't delete vvv
    commands.spawn((
        PbrBundle {
            mesh: meshes.add(Mesh::from(shape::Cube { size: 100000.0 })),
            material: materials.add(StandardMaterial {
                base_color: Vec4::splat(0.0).into(),
                double_sided: true,
                cull_mode: None,
                unlit: true,
                ..default()
            }),
            transform: Transform::from_xyz(0.0, 1.0, 0.0),
            ..default()
        },
        NotShadowCaster,
    ));

    commands.spawn(SceneBundle {
        scene: asset_server.load("models/FlightHelmet/FlightHelmet.gltf#Scene0"),
        ..default()
    });

    // light
    commands.spawn(DirectionalLightBundle {
        directional_light: DirectionalLight {
            color: Color::rgb(0.75, 0.95, 1.0),
            shadows_enabled: false,
            illuminance: 7000.0,
            ..default()
        },
        transform: Transform::from_rotation(Quat::from_euler(
            EulerRot::XYZ,
            -2.4347053,
            -0.9712761,
            2.5132747,
        )),
        ..default()
    });

    let cam_rot = Transform::from_rotation(Quat::from_euler(
        EulerRot::ZYX,
        180.0_f32.to_radians(),
        -45.0_f32.to_radians(),
        135.0_f32.to_radians(),
    ));

    // camera
    commands
        .spawn((
            Camera3dBundle {
                camera: Camera {
                    hdr: true,
                    ..default()
                },
                //transform: cam_rot.with_translation(-cam_rot.forward() * 500.0),
                transform: cam_rot.with_translation(vec3(-107.78326, 514.22394, -164.99352)),
                projection: Projection::Orthographic(OrthographicProjection {
                    scale: 0.03,
                    far: 2000.0,
                    near: 0.0,
                    ..default()
                }),
                color_grading: ColorGrading {
                    gamma: 1.2,
                    exposure: 1.0,
                    post_saturation: 1.1,
                    pre_saturation: 1.1,
                },
                ..default()
            },
            UnitsPass,
            ParticlesPass,
            MinimapPass,
            DeferredPrepass,
            DepthPrepass,
            MotionVectorPrepass,
            Pico2dCamera,
            RenderLayers::all(),
            EnvironmentMapLight {
                diffuse_map: asset_server.load("environment_maps/moonless_golf_4k_diffuse.ktx2"),
                specular_map: asset_server.load("environment_maps/moonless_golf_4k_specular.ktx2"),
            },
        ))
        .insert(OrthoCameraController {
            mouse_key_enable_mouse: MouseButton::Middle,
            ..default()
        })
        .insert((
            //FxaaPrepass::default(),
            TAASettings::default(),
            //TemporalJitter,
            MotionVectorPrepass,
            //NormalPrepass,
            //DisocclusionSettings::default(),
        ))
        .insert(SSGIBundle {
            ssgi_pass: SSGIPass {
                brightness: 6.0,
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
    cameras: Query<(&Camera, &GlobalTransform), With<Camera3d>>,
    mut unit_command: ResMut<UnitCommand>,
    //mut select_start: Local<Option<Vec3>>,
    //mut select_end: Local<Option<Vec3>>,
) {
    let window = window.get_single().unwrap();
    if let Some((camera, transform)) = cameras.iter().next() {
        //dbg!(transform);
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

#[derive(Resource, ExtractResource, Clone)]
pub struct UnitTexture {
    pub small_goose: Handle<Image>,
    pub big_goose: Handle<Image>,
}

pub fn load_unit_texture(mut commands: Commands, ass: Res<AssetServer>) {
    commands.insert_resource(UnitTexture {
        small_goose: ass.load("models/SmallGoose.ktx2"),
        big_goose: ass.load("models/GooseHydra.ktx2"),
    });
}

//fn move_directional_light(
//    mut query: Query<&mut Transform, With<DirectionalLight>>,
//    mut motion_evr: EventReader<MouseMotion>,
//    keys: Res<Input<KeyCode>>,
//    mut e_rot: Local<Vec3>,
//) {
//    if !keys.pressed(KeyCode::L) {
//        return;
//    }
//    for mut trans in &mut query {
//        let euler = trans.rotation.to_euler(EulerRot::XYZ);
//        let euler = vec3(euler.0, euler.1, euler.2);
//
//        for ev in motion_evr.read() {
//            *e_rot = vec3(
//                (euler.x.to_degrees() + ev.delta.y * 2.0).to_radians(),
//                (euler.y.to_degrees() + ev.delta.x * 2.0).to_radians(),
//                euler.z,
//            );
//        }
//        let store = euler.lerp(*e_rot, 0.2);
//        dbg!(store);
//        trans.rotation = Quat::from_euler(EulerRot::XYZ, store.x, store.y, store.z);
//    }
//}
