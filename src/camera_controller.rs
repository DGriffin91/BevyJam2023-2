use bevy::{
    input::mouse::{MouseMotion, MouseScrollUnit, MouseWheel},
    prelude::*,
};

/// Provides basic movement functionality to the attached camera
#[derive(Component, Clone)]
pub struct OrthoCameraController {
    pub enabled: bool,
    pub initialized: bool,
    pub sensitivity: f32,
    pub key_forward: KeyCode,
    pub key_back: KeyCode,
    pub key_left: KeyCode,
    pub key_right: KeyCode,
    pub key_up: KeyCode,
    pub key_down: KeyCode,
    pub key_run: KeyCode,
    pub click_zoom_modifier: KeyCode,
    pub mouse_key_enable_mouse: MouseButton,
    pub keyboard_key_enable_mouse: KeyCode,
    pub click_zoom_speed: f32,
    pub walk_speed: f32,
    pub run_speed: f32,
    pub friction: f32,
    pub pitch: f32,
    pub yaw: f32,
    pub velocity: Vec3,
    pub orbit_focus: Vec3,
    pub scroll_wheel_speed: f32,
    pub lock_y: bool,
    pub max_zoom: f32,
    pub min_zoom: f32,
}

impl Default for OrthoCameraController {
    fn default() -> Self {
        Self {
            enabled: true,
            initialized: false,
            sensitivity: 1.251,
            key_forward: KeyCode::W,
            key_back: KeyCode::S,
            key_left: KeyCode::A,
            key_right: KeyCode::D,
            key_up: KeyCode::E,
            key_down: KeyCode::Q,
            key_run: KeyCode::ShiftLeft,
            click_zoom_modifier: KeyCode::ControlLeft,
            mouse_key_enable_mouse: MouseButton::Left,
            keyboard_key_enable_mouse: KeyCode::M,
            click_zoom_speed: 1.0,
            walk_speed: 1000.0,
            run_speed: 2000.0,
            friction: 0.5,
            pitch: 0.0,
            yaw: 0.0,
            velocity: Vec3::ZERO,
            orbit_focus: Vec3::ZERO,
            scroll_wheel_speed: 0.12,
            lock_y: false,
            max_zoom: 0.5,
            min_zoom: 0.001,
        }
    }
}

#[derive(Default)]
pub struct OrthoCameraControllerPlugin;

impl Plugin for OrthoCameraControllerPlugin {
    fn build(&self, app: &mut App) {
        app.add_systems(Update, camera_controller);
    }
}

fn camera_controller(
    time: Res<Time>,
    mut camera: Query<(
        &mut Transform,
        &mut Projection,
        &mut Camera,
        &mut OrthoCameraController,
    )>,
    mut scroll_evr: EventReader<MouseWheel>,
    key_input: Res<Input<KeyCode>>,
    mut move_toggled: Local<bool>,
    mouse_button_input: Res<Input<MouseButton>>,
    mut mouse_events: EventReader<MouseMotion>,
) {
    let dt = time.delta_seconds();
    let Some((mut transform, mut projection, _camera, mut options)) = camera.iter_mut().next()
    else {
        return;
    };
    if !options.enabled {
        return;
    }
    let mut o_scale = 0.0;
    match projection.as_mut() {
        Projection::Orthographic(o) => {
            o_scale = o.scale;
        }
        Projection::Perspective(_) => (),
    }

    // Handle key input
    let mut axis_input = Vec3::ZERO;
    if key_input.pressed(options.key_forward) {
        axis_input.y += 1.0;
    }
    if key_input.pressed(options.key_back) {
        axis_input.y -= 1.0;
    }
    if key_input.pressed(options.key_right) {
        axis_input.x += 1.0;
    }
    if key_input.pressed(options.key_left) {
        axis_input.x -= 1.0;
    }
    if key_input.pressed(options.key_up) {
        axis_input.z += 1.0;
    }
    if key_input.pressed(options.key_down) {
        axis_input.z -= 1.0;
    }
    if key_input.just_pressed(options.keyboard_key_enable_mouse) {
        *move_toggled = !*move_toggled;
    }

    // Apply movement update
    if axis_input != Vec3::ZERO {
        let max_speed = if key_input.pressed(options.key_run) {
            options.run_speed
        } else {
            options.walk_speed
        };
        options.velocity = axis_input.normalize() * max_speed;
    } else {
        let friction = options.friction.clamp(0.0, 1.0);
        options.velocity *= 1.0 - friction;
        if options.velocity.length_squared() < 1e-6 {
            options.velocity = Vec3::ZERO;
        }
    }
    if !key_input.pressed(options.click_zoom_modifier) {
        let right = transform.right();
        let up = transform.up();
        let translation_delta = options.velocity.x * dt * right + options.velocity.y * dt * up;
        transform.translation += translation_delta * o_scale;
    }

    // Handle mouse input
    let mut mouse_delta = Vec2::ZERO;
    if mouse_button_input.pressed(options.mouse_key_enable_mouse) || 
    // TODO clean up hard coded stuff
    (mouse_button_input.pressed(MouseButton::Left) && key_input.pressed(KeyCode::ShiftLeft)) || 
    (mouse_button_input.pressed(MouseButton::Left) && key_input.pressed(KeyCode::ControlLeft)) || *move_toggled {
        for mouse_event in mouse_events.read() {
            mouse_delta += mouse_event.delta;
        }
    } else {
        mouse_events.clear();
    }

    match projection.as_mut() {
        Projection::Orthographic(o) => {
            let mut scroll_distance = 0.0;
            for ev in scroll_evr.read() {
                match ev.unit {
                    MouseScrollUnit::Line => {
                        scroll_distance = ev.y;
                    }
                    MouseScrollUnit::Pixel => (),
                }
            }
            if scroll_distance > 0.0 {
                o.scale /= (1.0 + options.scroll_wheel_speed) * scroll_distance.abs();
            }
            if scroll_distance < 0.0 {
                o.scale *= (1.0 + options.scroll_wheel_speed) * scroll_distance.abs();
            }
            if key_input.pressed(options.click_zoom_modifier)
                // TODO clean up hard coded stuff
                && (mouse_button_input.pressed(options.mouse_key_enable_mouse)
                    || mouse_button_input.pressed(MouseButton::Left))
            {
                o.scale *=
                    1.0 + (-mouse_delta.x + mouse_delta.y) * 0.002 * options.click_zoom_speed;
                mouse_delta = Vec2::ZERO;
            }
            o.scale += (options.velocity.z * 0.0000005) * o.scale.sqrt();
            o.scale = o.scale.clamp(options.min_zoom, options.max_zoom);
        }
        Projection::Perspective(_) => (),
    }

    if mouse_delta != Vec2::ZERO {
        let left = transform.left();
        let up = transform.up();
        let mut translation_delta =
            options.sensitivity * mouse_delta.x * left + options.sensitivity * mouse_delta.y * up;
        if options.lock_y {
            translation_delta *= Vec3::new(1.0, 0.0, 1.0);
        }
        transform.translation += o_scale * translation_delta;
    }
}
