// API modules
pub mod library;
pub mod pdf;
pub mod docx;
pub mod covers;
pub mod crop;
pub mod mobi;
pub mod cbz;
pub mod tts_text;

pub use library::*;
pub use pdf::*;
pub use docx::*;
pub use covers::*;
pub use crop::*;
pub use mobi::*;
pub use cbz::*;
pub use tts_text::*;

pub fn hello_world() -> String {
    "Hello from Rust!".to_string()
}
