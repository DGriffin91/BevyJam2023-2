use bevy::core_pipeline::clear_color::ClearColorConfig;
use bevy::core_pipeline::tonemapping::Tonemapping;
use bevy::math::*;
use bevy::prelude::*;
use bevy::sprite::Anchor;
use bevy::utils::tracing::Instrument;
use bevy_picoui::palette::RGB_PALETTE;
use bevy_picoui::pico::*;

use crate::post_process::PostProcessPass;
use crate::post_process::PostProcessPlugin;

pub struct UIPlugin;

impl Plugin for UIPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Startup, setup_2d_camera)
            .add_systems(Update, update);
    }
}

fn setup_2d_camera(mut commands: Commands) {
    commands
        .spawn(Camera2dBundle {
            camera: Camera {
                order: 1,
                hdr: true,
                ..default()
            },
            camera_2d: Camera2d {
                clear_color: ClearColorConfig::None,
            },
            tonemapping: Tonemapping::TonyMcMapface,
            ..default()
        })
        .insert(PostProcessPass);
}

fn update(mut gizmos: Gizmos, mut pico: ResMut<Pico>, windows: Query<&Window>) {
    let Some(window) = windows.iter().next() else {
        return;
    };

    // using physical_height to match minimap shader
    let minimap_scale = (window.physical_height() as f32 / 720.0).round().max(1.0);
    let window_factor = 1.0 / window.scale_factor() as f32;

    let scale = minimap_scale * window_factor;

    let minimap_size = 128.0 * scale;

    let sidebar = pico.add(PicoItem {
        depth: Some(0.01),
        x: Val::Px(0.0),
        y: Val::Px(0.0),
        width: Val::Px(minimap_size),
        height: Val::Vh(100.0),
        style: ItemStyle {
            background_color: Color::WHITE * 0.1,
            ..default()
        },
        anchor: Anchor::TopLeft,
        anchor_parent: Anchor::TopLeft,
        ..default()
    });

    let main_box = pico.add(PicoItem {
        depth: Some(0.5),
        x: Val::Px(0.0),
        y: Val::Px(minimap_size),
        width: Val::Percent(100.0),
        height: Val::Px(window.physical_height() as f32 - minimap_size),
        style: ItemStyle::default(),
        anchor: Anchor::TopLeft,
        anchor_parent: Anchor::TopLeft,
        parent: Some(sidebar),
        ..default()
    });

    pico.add(PicoItem {
        x: Val::Px(6.0 * scale),
        y: Val::Px(6.0 * scale),
        text: String::from("UNITS"),
        style: ItemStyle {
            anchor_text: Anchor::TopLeft,
            font_size: Val::Px(18.0 * scale),
            text_alignment: TextAlignment::Left,
            ..default()
        },
        anchor: Anchor::TopLeft,
        anchor_parent: Anchor::TopLeft,

        parent: Some(main_box),
        ..default()
    });

    pico.add(PicoItem {
        x: Val::Px(6.0 * scale),
        y: Val::Px(48.0 * scale),
        text: String::from("ENEMY UNITS"),
        style: ItemStyle {
            anchor_text: Anchor::TopLeft,
            font_size: Val::Px(18.0 * scale),
            text_alignment: TextAlignment::Left,
            ..default()
        },
        anchor: Anchor::TopLeft,
        anchor_parent: Anchor::TopLeft,

        parent: Some(main_box),
        ..default()
    });
}
