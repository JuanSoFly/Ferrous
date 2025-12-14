// API modules
pub mod library;
pub mod pdf;

pub use library::*;
pub use pdf::*;

pub fn hello_world() -> String {
    "Hello from Rust!".to_string()
}
