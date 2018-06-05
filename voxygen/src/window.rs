use gfx_window_glutin;
use glutin;

use glutin::{EventsLoop, WindowBuilder, ContextBuilder, GlContext, GlRequest, GlWindow, WindowEvent, CursorState};
use glutin::Api::OpenGl;

use renderer::{Renderer, ColorFormat, DepthFormat};

pub enum Event {
    CloseRequest,
    CursorMoved { dx: f64, dy: f64 },
    Resized { w: u32, h: u32 },
}

pub struct RenderWindow {
    events_loop: EventsLoop,
    gl_window: GlWindow,
    renderer: Renderer,
}

impl RenderWindow {
    pub fn new() -> RenderWindow {
        let events_loop = EventsLoop::new();
        let win_builder = WindowBuilder::new()
            .with_title("Verloren (Voxygen)")
            .with_dimensions(800, 500)
            .with_maximized(false);

        let ctx_builder = ContextBuilder::new()
            .with_gl(GlRequest::Specific(OpenGl, (3, 2)))
            .with_vsync(true);

        let (gl_window, device, factory, color_view, depth_view) =
            gfx_window_glutin::init::<ColorFormat, DepthFormat>(win_builder, ctx_builder, &events_loop);

        match gl_window.get_inner_size() {
            Some((x, y)) => {
                let _ = gl_window.set_cursor_position(x as i32 / 2, y as i32 / 2);
            },
            None => {},
        }
        let _ = gl_window.set_cursor_state(CursorState::Hide);

        RenderWindow {
            events_loop,
            gl_window,
            renderer: Renderer::new(device, factory, color_view, depth_view),
        }
    }

    pub fn renderer_mut<'a>(&'a mut self) -> &'a mut Renderer {
        &mut self.renderer
    }

    pub fn handle_events<'a, F: FnMut(Event)>(&mut self, mut func: F) {
        // We need to mutate these inside the closure, so we take a mutable reference
        let gl_window = &mut self.gl_window;
        let events_loop = &mut self.events_loop;
        let renderer = &mut self.renderer;

        events_loop.poll_events(|event| {
            if let glutin::Event::WindowEvent { event, .. } = event {
                match event {
                    WindowEvent::CursorMoved { position, .. } => {
                        match gl_window.get_inner_size() {
                            Some((x, y)) => {
                                func(Event::CursorMoved {
                                    dx: position.0 - x as f64 * 0.5,
                                    dy: position.1 - y as f64 * 0.5,
                                });
                                // TODO: Should we handle this result?
                                let _ = gl_window.set_cursor_position(x as i32 / 2, y as i32 / 2);
                            },
                            None => {},
                        }
                    },
                    WindowEvent::Resized { 0: w, 1: h } => {
                        let mut color_view = renderer.color_view().clone();
                        let mut depth_view = renderer.depth_view().clone();
                        gfx_window_glutin::update_views(
                            &gl_window,
                            &mut color_view,
                            &mut depth_view,
                        );
                        renderer.set_views(color_view, depth_view);
                        func(Event::Resized {
                            w,
                            h,
                        });
                    },
                    WindowEvent::CloseRequested => func(Event::CloseRequest),
                    _ => {},
                }
            }
        });
    }

    pub fn swap_buffers(&mut self) {
        self.gl_window.swap_buffers().expect("Failed to swap window buffers");
    }
}
