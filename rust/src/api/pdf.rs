use anyhow::{anyhow, Context, Result};
use pdfium_render::prelude::*;
use crate::timed;
use std::fs::File;
use std::io::Read;
use std::sync::{OnceLock, Mutex};
use std::num::NonZeroUsize;
use lru::LruCache;

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

const PDF_OPEN_ERROR_PREFIX: &str = "PDF_OPEN_ERROR";

fn ensure_pdf_header(path: &str) -> Result<()> {
    let metadata = std::fs::metadata(path)
        .with_context(|| format!("{PDF_OPEN_ERROR_PREFIX}::FILE: Missing PDF file at {path}"))?;
    if metadata.len() == 0 {
        return Err(anyhow!(
            "{PDF_OPEN_ERROR_PREFIX}::EMPTY: PDF file is empty at {path}"
        ));
    }

    let mut file = File::open(path)
        .with_context(|| format!("{PDF_OPEN_ERROR_PREFIX}::FILE: Unable to open PDF at {path}"))?;
    let mut buf = [0u8; 1024];
    let read = file
        .read(&mut buf)
        .with_context(|| format!("{PDF_OPEN_ERROR_PREFIX}::FILE: Unable to read PDF at {path}"))?;
    if read == 0 {
        return Err(anyhow!(
            "{PDF_OPEN_ERROR_PREFIX}::EMPTY: PDF file is empty at {path}"
        ));
    }

    let header_found = buf[..read].windows(5).any(|window| window == b"%PDF-");
    if !header_found {
        return Err(anyhow!(
            "{PDF_OPEN_ERROR_PREFIX}::HEADER: File does not look like a valid PDF at {path}"
        ));
    }

    Ok(())
}

fn map_pdfium_load_error(path: &str, error: PdfiumError) -> anyhow::Error {
    match error {
        PdfiumError::PdfiumLibraryInternalError(PdfiumInternalError::FormatError) => anyhow!(
            "{PDF_OPEN_ERROR_PREFIX}::FORMAT: PDF format error at {path}. The file may be corrupted or not a PDF."
        ),
        PdfiumError::PdfiumLibraryInternalError(PdfiumInternalError::PasswordError) => anyhow!(
            "{PDF_OPEN_ERROR_PREFIX}::PASSWORD: PDF is password-protected at {path}."
        ),
        PdfiumError::PdfiumLibraryInternalError(PdfiumInternalError::FileError) => anyhow!(
            "{PDF_OPEN_ERROR_PREFIX}::FILE: Unable to read PDF file at {path}."
        ),
        PdfiumError::PdfiumLibraryInternalError(PdfiumInternalError::SecurityError) => anyhow!(
            "{PDF_OPEN_ERROR_PREFIX}::SECURITY: PDF security settings prevent opening {path}."
        ),
        PdfiumError::PdfiumLibraryInternalError(PdfiumInternalError::PageError) => anyhow!(
            "{PDF_OPEN_ERROR_PREFIX}::PAGE: PDF page error while opening {path}."
        ),
        other => anyhow!("Failed to load PDF at {path}: {other:?}"),
    }
}

pub(crate) fn load_pdf_document<'a>(pdfium: &'a Pdfium, path: &str) -> Result<PdfDocument<'a>> {
    ensure_pdf_header(path)?;
    pdfium
        .load_pdf_from_file(path, None)
        .map_err(|e| map_pdfium_load_error(path, e))
}

// Global LRU cache for PDF documents (R3)
// We keep 4 documents open at once - enough for split screen + preloading
static DOCUMENT_POOL: OnceLock<Mutex<LruCache<String, PdfDocument<'static>>>> = OnceLock::new();

fn get_pool() -> &'static Mutex<LruCache<String, PdfDocument<'static>>> {
    DOCUMENT_POOL.get_or_init(|| {
        Mutex::new(LruCache::new(NonZeroUsize::new(4).unwrap()))
    })
}

/// Execute a function with a pooled PDF document
pub fn with_document<F, R>(path: &str, f: F) -> Result<R>
where
    F: FnOnce(&PdfDocument) -> Result<R>,
{
    let pool = get_pool();
    let mut cache = pool.lock().map_err(|_| anyhow!("Failed to lock document pool"))?;
    
    if let Some(doc) = cache.get(path) {
        return f(doc);
    }
    
    // Load and add to cache
    let doc = load_pdf_document(get_pdfium(), path)?;
    // We add to cache - this might evict an old one
    cache.put(path.to_string(), doc);
    
    // Get it back as it's now in the cache
    let doc = cache.get(path).ok_or_else(|| anyhow!("Failed to retrieve document after caching"))?;
    f(doc)
}

#[derive(Debug, Clone, Copy)]
pub struct PdfTextRect {
    pub left: f32,
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
}

/// Result of rendering a PDF page, including actual dimensions.
/// The dimensions may differ from requested due to aspect ratio preservation.
#[derive(Debug, Clone)]
pub struct PdfPageRenderResult {
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
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
    with_document(&path, |document| {
        Ok(document.pages().len() as u32)
    })
}

/// Render a specific page of a PDF to PNG bytes with actual dimensions.
/// Returns PdfPageRenderResult containing the image data and actual rendered size.
#[hotpath::measure]
pub fn render_pdf_page(path: String, page_index: u32, width: u32, height: u32) -> Result<PdfPageRenderResult> {
    timed!("render_pdf_page", {
        with_document(&path, |document| {
            let page = document.pages().get(page_index as u16)?;
            
            // Render to bitmap with high-quality settings
            let bitmap = page
                .render_with_config(&PdfRenderConfig::new()
                    .set_target_width(width as i32)
                    .set_maximum_height(height as i32)
                    // Enable high-quality rendering options
                    .use_lcd_text_rendering(true)    // Sharper text on LCD screens
                    .use_print_quality(true)         // Higher quality output
                    .set_text_smoothing(true)        // Enable text anti-aliasing
                    .set_image_smoothing(true)       // Enable image anti-aliasing
                    .set_path_smoothing(true)        // Enable path anti-aliasing
                    .render_form_data(true))?;       // Render form elements
            
            // Convert to PNG bytes and get actual dimensions
            let dynamic_image = bitmap.as_image();
            let actual_width = dynamic_image.width();
            let actual_height = dynamic_image.height();
            
            let mut png_bytes = Vec::new();
            dynamic_image.write_to(
                &mut std::io::Cursor::new(&mut png_bytes),
                image::ImageFormat::Png,
            )?;
            
            Ok(PdfPageRenderResult {
                data: png_bytes,
                width: actual_width,
                height: actual_height,
            })
        })
    })
}

/// Extract the text of a specific page of a PDF file.
#[hotpath::measure]
pub fn extract_pdf_page_text(path: String, page_index: u32) -> Result<String> {
    timed!("extract_pdf_page_text", {
        with_document(&path, |document| {
            let page = document.pages().get(page_index as u16)?;
            let text = page.text()?;
            Ok(text.all())
        })
    })
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
    timed!("extract_pdf_page_text_from_point", {
        with_document(&path, |document| {
            let page = document.pages().get(page_index as u16)?;

            let page_rect = page.page_size();
            let width = page_rect.width().value as f64;
            let height = page_rect.height().value as f64;

            let x_norm = x_norm.clamp(0.0, 1.0);
            let y_norm = y_norm.clamp(0.0, 1.0);

            // Convert from top-left normalized coordinates to Pdfium user space coordinates
            let x_points = (page_rect.left().value as f64 + (width * x_norm)) as f32;
            let y_points = (page_rect.top().value as f64 - (height * y_norm)) as f32;

            let text = page.text()?;
            let chars = text.chars();

            // Try a few tolerance levels
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

            // Snap back to a word boundary
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
        })
    })
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
    timed!("extract_pdf_page_text_bounds", {
        with_document(&path, |document| {
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
            let page_left = page_rect.left().value;
            let page_bottom = page_rect.bottom().value;
            let width = page_rect.width().value;
            let height = page_rect.height().value;

            if width <= 0.0 || height <= 0.0 {
                return Ok(Vec::new());
            }

            let mut rects = Vec::new();
            for i in start..end {
                let ch = match chars.get(i) {
                    Ok(ch) => ch,
                    Err(_) => continue,
                };

                // Skip characters without unicode representation (invisible/control chars)
                let Some(c) = ch.unicode_char() else {
                    continue;
                };

                // Skip whitespace characters
                if c.is_whitespace() {
                    continue;
                }

                let bounds = ch.loose_bounds().or_else(|_| ch.tight_bounds());
                let Ok(bounds) = bounds else { continue };

                // PDF coordinates: origin at bottom-left, Y increases upward
                // Flutter coordinates: origin at top-left, Y increases downward
                let mut left = (bounds.left().value - page_left) / width;
                let mut right = (bounds.right().value - page_left) / width;
                let mut top = 1.0 - ((bounds.top().value - page_bottom) / height);
                let mut bottom = 1.0 - ((bounds.bottom().value - page_bottom) / height);

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
        })
    })
}

/// Pre-compute ALL character bounds for a page.
/// Call this once when loading a page, then use the cached data for TTS highlighting.
/// This eliminates per-word FFI calls during TTS playback.
#[hotpath::measure]
pub fn extract_all_page_character_bounds(
    path: String,
    page_index: u32,
) -> Result<Vec<PdfTextRect>> {
    timed!("extract_all_page_character_bounds", {
        with_document(&path, |document| {
            let page = document.pages().get(page_index as u16)?;
            let text = page.text()?;
            let chars = text.chars();

            let total = text.len().max(0) as usize;
            if total == 0 {
                return Ok(Vec::new());
            }

            let page_rect = page.page_size();
            let page_left = page_rect.left().value;
            let page_bottom = page_rect.bottom().value;
            let width = page_rect.width().value;
            let height = page_rect.height().value;

            if width <= 0.0 || height <= 0.0 {
                return Ok(Vec::new());
            }

            let mut rects = Vec::with_capacity(total);
            
            for i in 0..total {
                let ch = match chars.get(i) {
                    Ok(ch) => ch,
                    Err(_) => {
                        rects.push(PdfTextRect { left: 0.0, top: 0.0, right: 0.0, bottom: 0.0 });
                        continue;
                    }
                };

                // Skip characters without unicode representation (invisible/control chars)
                let Some(c) = ch.unicode_char() else {
                    rects.push(PdfTextRect { left: 0.0, top: 0.0, right: 0.0, bottom: 0.0 });
                    continue;
                };

                // Skip whitespace characters
                if c.is_whitespace() {
                    rects.push(PdfTextRect { left: 0.0, top: 0.0, right: 0.0, bottom: 0.0 });
                    continue;
                }

                let bounds = ch.loose_bounds().or_else(|_| ch.tight_bounds());
                let Ok(bounds) = bounds else {
                    rects.push(PdfTextRect { left: 0.0, top: 0.0, right: 0.0, bottom: 0.0 });
                    continue;
                };

                // PDF coordinates: origin at bottom-left, Y increases upward
                // Flutter coordinates: origin at top-left, Y increases downward
                // bounds.left/right/top/bottom are in page user space (points from page origin)
                
                // Normalize X: (bounds.x - page_left) / width -> [0.0, 1.0]
                let mut left = (bounds.left().value - page_left) / width;
                let mut right = (bounds.right().value - page_left) / width;
                
                // Normalize Y with flip: PDF top is higher Y value, Flutter top is lower Y value
                // In PDF: bounds.top > bounds.bottom (top is higher Y)
                // After flip: flutter_top < flutter_bottom
                let mut top = 1.0 - ((bounds.top().value - page_bottom) / height);
                let mut bottom = 1.0 - ((bounds.bottom().value - page_bottom) / height);

                if left > right { std::mem::swap(&mut left, &mut right); }
                if top > bottom { std::mem::swap(&mut top, &mut bottom); }

                rects.push(PdfTextRect {
                    left: left.clamp(0.0, 1.0),
                    top: top.clamp(0.0, 1.0),
                    right: right.clamp(0.0, 1.0),
                    bottom: bottom.clamp(0.0, 1.0),
                });
            }

            Ok(rects)
        })
    })
}

/// Test function to verify PDF module is working
pub fn test_pdf_module() -> String {
    "PDF module loaded successfully".to_string()
}
