use anyhow::Result;
use pdfium_render::prelude::*;
use std::sync::OnceLock;

// Global Pdfium instance for thread-safe reuse
static PDFIUM: OnceLock<Pdfium> = OnceLock::new();

fn get_pdfium() -> &'static Pdfium {
    PDFIUM.get_or_init(|| {
        let bindings = Pdfium::bind_to_library("libpdfium.so")
            .or_else(|_| Pdfium::bind_to_system_library())
            .expect("Failed to bind to pdfium library. Make sure libpdfium.so is in jniLibs.");
        Pdfium::new(bindings)
    })
}

#[derive(Debug, Clone, Copy)]
pub struct PdfTextRect {
    pub left: f32,
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
}

/// Execute a function with the global Pdfium instance
pub fn with_pdfium<F, R>(f: F) -> Result<R>
where
    F: FnOnce(&Pdfium) -> Result<R>,
{
    let pdfium = get_pdfium();
    f(pdfium)
}

/// Get the page count of a PDF file
pub fn get_pdf_page_count(path: String) -> Result<u32> {
    let pdfium = get_pdfium();
    let document = pdfium.load_pdf_from_file(&path, None)?;
    Ok(document.pages().len() as u32)
}

/// Render a specific page of a PDF to PNG bytes
pub fn render_pdf_page(path: String, page_index: u32, width: u32, height: u32) -> Result<Vec<u8>> {
    let pdfium = get_pdfium();
    let document = pdfium.load_pdf_from_file(&path, None)?;
    
    let page = document.pages().get(page_index as u16)?;
    
    // Render to bitmap
    let bitmap = page
        .render_with_config(&PdfRenderConfig::new()
            .set_target_width(width as i32)
            .set_maximum_height(height as i32))?;
    
    // Convert to PNG bytes
    let dynamic_image = bitmap.as_image();
    let mut png_bytes = Vec::new();
    dynamic_image.write_to(
        &mut std::io::Cursor::new(&mut png_bytes),
        image::ImageFormat::Png,
    )?;
    
    Ok(png_bytes)
}

/// Extract the text of a specific page of a PDF file.
///
/// Notes:
/// - Many PDFs (especially scanned documents) have no text layer, in which case this returns an
///   empty string.
/// - The extracted character order can differ from visual reading order for complex layouts.
pub fn extract_pdf_page_text(path: String, page_index: u32) -> Result<String> {
    let pdfium = get_pdfium();
    let document = pdfium.load_pdf_from_file(&path, None)?;
    let page = document.pages().get(page_index as u16)?;
    let text = page.text()?;
    Ok(text.all())
}

/// Extract page text starting near a normalized point on the rendered page.
///
/// - `x_norm` / `y_norm` are in the range `[0.0, 1.0]` relative to the full page, with origin
///   at the top-left corner (as in Flutter coordinate space).
/// - If no text is found near the given point (within a tolerance), this returns an empty string.
pub fn extract_pdf_page_text_from_point(
    path: String,
    page_index: u32,
    x_norm: f64,
    y_norm: f64,
) -> Result<String> {
    let pdfium = get_pdfium();
    let document = pdfium.load_pdf_from_file(&path, None)?;
    let page = document.pages().get(page_index as u16)?;

    let page_rect = page.page_size();
    let width = page_rect.width().value as f64;
    let height = page_rect.height().value as f64;

    let x_norm = x_norm.clamp(0.0, 1.0);
    let y_norm = y_norm.clamp(0.0, 1.0);

    // Convert from top-left normalized coordinates to Pdfium user space coordinates
    // (origin bottom-left, y increasing up).
    let x_points = (page_rect.left().value as f64 + (width * x_norm)) as f32;
    let y_points = (page_rect.top().value as f64 - (height * y_norm)) as f32;

    let text = page.text()?;
    let chars = text.chars();

    // Try a few tolerance levels; a user tap is rarely exactly on a character glyph.
    let mut tolerance = PdfPoints::new(6.0);
    let mut picked = None;

    for _ in 0..4 {
        picked = chars.get_char_near_point(
            PdfPoints::new(x_points),
            tolerance,
            PdfPoints::new(y_points),
            tolerance,
        );
        if picked.is_some() {
            break;
        }
        tolerance = tolerance * 2.0;
    }

    let Some(picked_char) = picked else {
        return Ok(String::new());
    };

    let total = text.len().max(0) as usize;
    if total == 0 {
        return Ok(String::new());
    }

    // Snap back to a word boundary (within a short window) to avoid starting mid-word.
    let mut start_index = picked_char.index().min(total.saturating_sub(1));
    for _ in 0..32 {
        if start_index == 0 {
            break;
        }

        let prev = chars.get(start_index - 1);
        let Ok(prev_char) = prev else { break };

        let Some(c) = prev_char.unicode_char() else { break };
        if c.is_whitespace() {
            break;
        }

        start_index -= 1;
    }

    let mut out = String::new();
    for i in start_index..total {
        let Ok(ch) = chars.get(i) else { continue };
        if let Some(c) = ch.unicode_char() {
            out.push(c);
        }
    }

    Ok(out)
}

/// Extract normalized character bounding boxes for a text range on the page.
///
/// The returned rectangles are normalized to the page (0.0-1.0) and use
/// a top-left origin, matching Flutter's coordinate space.
pub fn extract_pdf_page_text_bounds(
    path: String,
    page_index: u32,
    start_index: u32,
    end_index: u32,
) -> Result<Vec<PdfTextRect>> {
    let pdfium = get_pdfium();
    let document = pdfium.load_pdf_from_file(&path, None)?;
    let page = document.pages().get(page_index as u16)?;
    let text = page.text()?;
    let chars = text.chars();

    let total = text.len().max(0) as usize;
    if total == 0 {
        return Ok(Vec::new());
    }

    let start = start_index as usize;
    let end = end_index as usize;
    if start >= end || start >= total {
        return Ok(Vec::new());
    }

    let end = end.min(total);
    let page_rect = page.page_size();
    let width = page_rect.width().value as f32;
    let height = page_rect.height().value as f32;

    if width <= 0.0 || height <= 0.0 {
        return Ok(Vec::new());
    }

    let mut rects = Vec::new();
    for i in start..end {
        let ch = match chars.get(i) {
            Ok(ch) => ch,
            Err(_) => continue,
        };

        if let Some(c) = ch.unicode_char() {
            if c.is_whitespace() {
                continue;
            }
        }

        let bounds = ch.loose_bounds().or_else(|_| ch.tight_bounds());
        let Ok(bounds) = bounds else { continue };

        let mut left = bounds.left().value / width;
        let mut right = bounds.right().value / width;
        let mut top = 1.0 - (bounds.top().value / height);
        let mut bottom = 1.0 - (bounds.bottom().value / height);

        if left > right {
            std::mem::swap(&mut left, &mut right);
        }
        if top > bottom {
            std::mem::swap(&mut top, &mut bottom);
        }

        rects.push(PdfTextRect {
            left: left.clamp(0.0, 1.0),
            top: top.clamp(0.0, 1.0),
            right: right.clamp(0.0, 1.0),
            bottom: bottom.clamp(0.0, 1.0),
        });
    }

    Ok(rects)
}

/// Pre-compute ALL character bounds for a page.
/// Call this once when loading a page, then use the cached data for TTS highlighting.
/// This eliminates per-word FFI calls during TTS playback.
pub fn extract_all_page_character_bounds(
    path: String,
    page_index: u32,
) -> Result<Vec<PdfTextRect>> {
    let pdfium = get_pdfium();
    let document = pdfium.load_pdf_from_file(&path, None)?;
    let page = document.pages().get(page_index as u16)?;
    let text = page.text()?;
    let chars = text.chars();

    let total = text.len().max(0) as usize;
    if total == 0 {
        return Ok(Vec::new());
    }

    let page_rect = page.page_size();
    let width = page_rect.width().value as f32;
    let height = page_rect.height().value as f32;

    if width <= 0.0 || height <= 0.0 {
        return Ok(Vec::new());
    }

    let mut rects = Vec::with_capacity(total);
    
    for i in 0..total {
        let ch = match chars.get(i) {
            Ok(ch) => ch,
            Err(_) => {
                // Push empty rect as placeholder to maintain index alignment
                rects.push(PdfTextRect {
                    left: 0.0,
                    top: 0.0,
                    right: 0.0,
                    bottom: 0.0,
                });
                continue;
            }
        };

        // Skip whitespace but still push placeholder for index alignment
        if let Some(c) = ch.unicode_char() {
            if c.is_whitespace() {
                rects.push(PdfTextRect {
                    left: 0.0,
                    top: 0.0,
                    right: 0.0,
                    bottom: 0.0,
                });
                continue;
            }
        }

        let bounds = ch.loose_bounds().or_else(|_| ch.tight_bounds());
        let Ok(bounds) = bounds else {
            rects.push(PdfTextRect {
                left: 0.0,
                top: 0.0,
                right: 0.0,
                bottom: 0.0,
            });
            continue;
        };

        let mut left = bounds.left().value / width;
        let mut right = bounds.right().value / width;
        let mut top = 1.0 - (bounds.top().value / height);
        let mut bottom = 1.0 - (bounds.bottom().value / height);

        if left > right {
            std::mem::swap(&mut left, &mut right);
        }
        if top > bottom {
            std::mem::swap(&mut top, &mut bottom);
        }

        rects.push(PdfTextRect {
            left: left.clamp(0.0, 1.0),
            top: top.clamp(0.0, 1.0),
            right: right.clamp(0.0, 1.0),
            bottom: bottom.clamp(0.0, 1.0),
        });
    }

    Ok(rects)
}

/// Test function to verify PDF module is working
pub fn test_pdf_module() -> String {
    "PDF module loaded successfully".to_string()
}
