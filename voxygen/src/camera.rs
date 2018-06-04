use nalgebra::{Vector3, Vector2, Matrix4, Translation3, Perspective3};
use std::f32::consts::PI;

pub struct Camera {
    focus: Vector3<f32>,
    ori: Vector2<f32>,
    zoom: f32,
}

impl Camera {
    pub fn new() -> Camera {
        Camera {
            focus: Vector3::<f32>::new(100.0, 100.0, 20.0),
            ori: Vector2::<f32>::zeros(),
            zoom: 10.0,
        }
    }

    pub fn get_mats(&self) -> (Matrix4<f32>, Matrix4<f32>) {
        let mut mat = Matrix4::<f32>::identity();

        mat *= Translation3::<f32>::from_vector(Vector3::<f32>::new(0.0, 0.0, -self.zoom)).to_homogeneous();
        mat *= Matrix4::from_scaled_axis(&Vector3::x() * self.ori.y) * Matrix4::from_scaled_axis(&Vector3::y() * self.ori.x);

        // Apply anti-OpenGL correction
        mat *= Matrix4::from_scaled_axis(-&Vector3::x() * PI / 2.0);

        mat *= Translation3::<f32>::from_vector(-self.focus).to_homogeneous();

        (mat, *Perspective3::<f32>::new(1.6, 1.5, 0.1, 1000.0).as_matrix())
    }

    pub fn rotate_by(&mut self, dangle: Vector2<f32>) {
        //self.focus += Vector3::new(dangle.x * 0.05, dangle.y * 0.05, 0.0);
        self.ori += dangle;
    }
}
