#![allow(clippy::too_many_arguments, clippy::type_complexity)]

use std::f32::consts::*;

use bevy::{
    core::cast_slice,
    math::*,
    prelude::*,
    render::{
        mesh::Indices,
        render_resource::{
            AsBindGroup, Extent3d, PrimitiveTopology, ShaderRef, TextureDimension, TextureFormat,
        },
    },
};
use bevy_basic_camera::{CameraController, CameraControllerPlugin};

fn main() {
    App::new()
        .add_plugins(DefaultPlugins)
        .add_plugins((
            CameraControllerPlugin,
            MaterialPlugin::<ParticlesMaterial>::default(),
        ))
        .add_systems(Startup, setup)
        .run();
}

fn setup(
    mut commands: Commands,
    mut meshes: ResMut<Assets<Mesh>>,
    mut images: ResMut<Assets<Image>>,
    mut materials: ResMut<Assets<ParticlesMaterial>>,
    asset_server: Res<AssetServer>,
) {
    let indices = Indices::U32((0..1024 * 6).collect());
    let mesh = Mesh::new(PrimitiveTopology::TriangleList).with_indices(Some(indices));

    commands.spawn((MaterialMeshBundle {
        mesh: meshes.add(mesh),
        material: materials.add(ParticlesMaterial {
            data_texture: images.add(create_texture()),
        }),
        transform: Transform::from_xyz(0.0, 0.0, 0.0),
        ..default()
    },));

    // camera
    commands
        .spawn(Camera3dBundle {
            transform: Transform::from_xyz(0.0, 0.0, 9.0).looking_at(Vec3::ZERO, Vec3::Y),
            ..default()
        })
        .insert(CameraController::default());
}

/// The Material trait is very configurable, but comes with sensible defaults for all methods.
/// You only need to implement functions for features that need non-default behavior. See the Material api docs for details!
impl Material for ParticlesMaterial {
    fn vertex_shader() -> ShaderRef {
        "shaders/particles_material.wgsl".into()
    }
    fn fragment_shader() -> ShaderRef {
        "shaders/particles_material.wgsl".into()
    }
}

// This is the struct that will be passed to your shader
#[derive(Asset, TypePath, AsBindGroup, Debug, Clone)]
pub struct ParticlesMaterial {
    #[texture(0)]
    #[sampler(1)]
    pub data_texture: Handle<Image>,
}

fn create_texture() -> Image {
    let positions = [
        vec4(0.0, 0.0, 0.0, 0.1),
        vec4(0.5, 0.0, 0.0, 0.01),
        vec4(0.0, 0.5, 0.0, 0.01),
        vec4(0.0, 0.0, 0.5, 0.01),
        vec4(-0.5, 0.0, 0.0, 0.01),
        vec4(0.0, -0.5, 0.0, 0.01),
        vec4(0.0, 0.0, -0.5, 0.01),
    ];

    let bytes: &[u8] = cast_slice(positions.as_slice());

    Image::new(
        Extent3d {
            width: positions.len() as u32,
            height: 1u32,
            depth_or_array_layers: 1,
        },
        TextureDimension::D2,
        bytes.to_vec(),
        TextureFormat::Rgba32Float,
    )
}
