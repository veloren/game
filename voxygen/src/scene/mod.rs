pub mod camera;
pub mod figure;
pub mod terrain;

// Library
use vek::*;
use dot_vox;

// Project
use common::figure::Segment;
use client::Client;

// Crate
use crate::{
    render::{
        Consts,
        Globals,
        Model,
        Renderer,
        SkyboxPipeline,
        SkyboxLocals,
        FigureLocals,
        create_skybox_mesh,
    },
    window::Event,
    mesh::Meshable,
    anim::{
        Animation,
        character::{CharacterSkeleton, RunAnimation},
    },
};

// Local
use self::{
    camera::Camera,
    figure::Figure,
    terrain::Terrain,
};

// TODO: Don't hard-code this
const CURSOR_PAN_SCALE: f32 = 0.005;

struct Skybox {
    model: Model<SkyboxPipeline>,
    locals: Consts<SkyboxLocals>,
}

pub struct Scene {
    globals: Consts<Globals>,
    camera: Camera,

    skybox: Skybox,
    terrain: Terrain,

    test_figure: Figure<CharacterSkeleton>,
}

// TODO: Make a proper asset loading system
fn load_segment(filename: &'static str) -> Segment {
    Segment::from(dot_vox::load(&(concat!(env!("CARGO_MANIFEST_DIR"), "/test_assets/").to_string() + filename)).unwrap())
}

impl Scene {
    /// Create a new `Scene` with default parameters.
    pub fn new(renderer: &mut Renderer, client: &Client) -> Self {
        Self {
            globals: renderer
                .create_consts(&[Globals::default()])
                .unwrap(),
            camera: Camera::new(),

            skybox: Skybox {
                model: renderer
                    .create_model(&create_skybox_mesh())
                    .unwrap(),
                locals: renderer
                    .create_consts(&[SkyboxLocals::default()])
                    .unwrap(),
            },
            terrain: Terrain::new(),

            test_figure: Figure::new(
                renderer,
                [
                    Some(load_segment("dragonhead.vox").generate_mesh(Vec3::new(2.0, -12.0, 2.0))),
                    Some(load_segment("dragon_body.vox").generate_mesh(Vec3::new(0.0, 0.0, 0.0))),
                    Some(load_segment("dragon_lfoot.vox").generate_mesh(Vec3::new(10.0, 10.0, -80.0))),
                    Some(load_segment("dragon_rfoot.vox").generate_mesh(Vec3::new(0.0, 10.0, -4.0))),
                    Some(load_segment("dragon_rfoot.vox").generate_mesh(Vec3::new(0.0, -10.0, -4.0))),
                    Some(load_segment("dragon_lfoot.vox").generate_mesh(Vec3::new(0.0, 0.0, 0.0))),
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    None,
                    None, 
                    None,
                    None,
                ],
                CharacterSkeleton::new(),
            )
                .unwrap(),
        }
    }

    /// Get a reference to the scene's camera.
    pub fn camera(&self) -> &Camera { &self.camera }

    /// Get a mutable reference to the scene's camera.
    pub fn camera_mut(&mut self) -> &mut Camera { &mut self.camera }

    /// Handle an incoming user input event (i.e: cursor moved, key pressed, window closed, etc.).
    ///
    /// If the event is handled, return true
    pub fn handle_input_event(&mut self, event: Event) -> bool {
        match event {
            // When the window is resized, change the camera's aspect ratio
            Event::Resize(dims) => {
                self.camera.set_aspect_ratio(dims.x as f32 / dims.y as f32);
                true
            },
            // Panning the cursor makes the camera rotate
            Event::CursorPan(delta) => {
                self.camera.rotate_by(Vec3::from(delta) * CURSOR_PAN_SCALE);
                true
            },
            // Zoom the camera when a zoom event occurs
            Event::Zoom(delta) => {
                self.camera.zoom_by(delta);
                true
            },
            // All other events are unhandled
            _ => false,
        }
    }

    /// Maintain data such as GPU constant buffers, models, etc. To be called once per tick.
    pub fn maintain(&mut self, renderer: &mut Renderer, client: &Client) {
        // Compute camera matrices
        let (view_mat, proj_mat, cam_pos) = self.camera.compute_dependents();

        // Update global constants
        renderer.update_consts(&mut self.globals, &[Globals::new(
            view_mat,
            proj_mat,
            cam_pos,
            self.camera.get_focus_pos(),
            10.0,
            client.state().get_time_of_day(),
            client.state().get_time(),
        )])
            .expect("Failed to update global constants");

        // Maintain the terrain
        self.terrain.maintain(renderer, client);

        // TODO: Don't do this here
        RunAnimation::update_skeleton(
            &mut self.test_figure.skeleton,
            client.state().get_time(),
        );
        self.test_figure.update_locals(renderer, FigureLocals::default()).unwrap();
        self.test_figure.update_skeleton(renderer).unwrap();
    }

    /// Render the scene using the provided `Renderer`
    pub fn render_to(&self, renderer: &mut Renderer) {
        // Render the skybox first (it appears over everything else so must be rendered first)
        renderer.render_skybox(
            &self.skybox.model,
            &self.globals,
            &self.skybox.locals,
        );

        // Render terrain
        self.terrain.render(renderer, &self.globals);

        // Render the test figure
        self.test_figure.render(renderer, &self.globals);
    }
}
