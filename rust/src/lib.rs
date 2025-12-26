pub mod api;

mod frb_generated; /* AUTO INJECTED BY flutter_rust_bridge */

#[macro_export]
macro_rules! timed {
    ($name:expr, $body:expr) => {{
        let start = std::time::Instant::now();
        let result = $body;
        let elapsed = start.elapsed().as_millis();
        if elapsed > 10 { // Log if > 10ms for profiling
            // Using eprintln to show in console during debug
            eprintln!("⏱️  Rust: {} took {}ms", $name, elapsed);
        }
        result
    }};
}
