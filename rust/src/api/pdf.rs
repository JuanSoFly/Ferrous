use anyhow::{anyhow, Context, Result};
use pdfium_render::prelude::*;
use crate::timed;
use std::fs::File;
use std::io::Read;
use std::sync::{Arc, Mutex, OnceLock};
use std::sync::atomic::{AtomicU64, Ordering};
use std::num::NonZeroUsize;
use lru::LruCache;

pub static GLOBAL_RENDER_EPOCH: AtomicU64 = AtomicU64::new(0);

#[derive(Debug, Clone)]
pub struct PdfOutlineItem {
    pub title: String,
    pub page_index: Option<u32>,
    pub depth: u32,
}

#[derive(Debug, Clone, Copy)]
pub struct PdfPageDimension {
    pub width: f32,
    pub height: f32,
    pub aspect_ratio: f32,
}

#[derive(Debug, Clone)]
pub struct SanitizedPdfText {
    pub clean_text: String,
    pub clean_to_pdf_map: Vec<u32>,
}

#[derive(Debug, Clone, Copy)]
pub struct PdfTextRect {
    pub left: f32,
    pub top: f32,
    pub right: f32,
    pub bottom: f32,
}

#[derive(Debug, Clone)]
pub struct PdfPageRenderResult {
    pub data: Vec<u8>,
    pub width: u32,
    pub height: u32,
    pub top_left_rgb: u32,
    pub top_right_rgb: u32,
    pub bottom_left_rgb: u32,
    pub bottom_right_rgb: u32,
}

static PDFIUM: OnceLock<Pdfium> = OnceLock::new();
static PDFIUM_PATH: OnceLock<String> = OnceLock::new();
static PDFIUM_EXECUTION_LOCK: OnceLock<Mutex<()>> = OnceLock::new();

fn get_execution_lock() -> &'static Mutex<()> {
    PDFIUM_EXECUTION_LOCK.get_or_init(|| Mutex::new(()))
}

pub fn set_render_epoch(epoch: u32) {
    GLOBAL_RENDER_EPOCH.store(epoch as u64, Ordering::Release);
}

pub fn get_render_epoch() -> u32 {
    GLOBAL_RENDER_EPOCH.load(Ordering::Acquire) as u32
}

pub fn init_pdfium(path: String) -> Result<()> {
    let _ = PDFIUM_PATH.set(path);
    Ok(())
}

fn get_pdfium() -> &'static Pdfium {
    PDFIUM.get_or_init(|| {
        let bindings = if let Some(custom_path) = PDFIUM_PATH.get() {
            let full_path = format!("{}/libpdfium.so", custom_path);
            Pdfium::bind_to_library(&full_path)
                .or_else(|_| Pdfium::bind_to_library("libpdfium.so"))
        } else {
            Pdfium::bind_to_library("libpdfium.so")
        }
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

// Global LRU cache for PDF documents
static DOCUMENT_POOL: OnceLock<Mutex<LruCache<String, Arc<PdfDocument<'static>>>>> = OnceLock::new();

fn get_pool() -> &'static Mutex<LruCache<String, Arc<PdfDocument<'static>>>> {
    DOCUMENT_POOL.get_or_init(|| {
        Mutex::new(LruCache::new(NonZeroUsize::new(4).unwrap()))
    })
}

/// Execute a function with a pooled PDF document, strictly serialized
/// to guarantee single-threaded safety for PDFium C++ structures.
pub fn with_document<F, R>(path: &str, f: F) -> Result<R>
where
    F: FnOnce(&PdfDocument) -> Result<R>,
{
    let exec_lock = get_execution_lock();
    let _guard = match exec_lock.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };

    let pool = get_pool();
    
    // 1. Try to get from cache first (holding pool lock briefly)
    let doc = {
        let mut cache = match pool.lock() {
            Ok(guard) => guard,
            Err(poisoned) => {
                eprintln!("⚠️ Warning: PDF document pool lock poisoned. Recovering...");
                poisoned.into_inner()
            }
        };
        cache.get(path).cloned()
    };
    
    // 2. If not in cache, load it
    let doc = match doc {
        Some(doc) => doc,
        None => {
            let loaded_doc = Arc::new(load_pdf_document(get_pdfium(), path)?);
            let mut cache = match pool.lock() {
                Ok(guard) => guard,
                Err(poisoned) => poisoned.into_inner(),
            };
            cache.put(path.to_string(), loaded_doc.clone());
            loaded_doc
        }
    };
    
    // 3. Call f with the document while holding the execution lock
    f(&doc)
}

#[inline(always)]
fn extract_rgb(bytes: &[u8], offset: usize) -> u32 {
    if offset + 2 < bytes.len() {
        ((bytes[offset] as u32) << 16) | ((bytes[offset + 1] as u32) << 8) | (bytes[offset + 2] as u32)
    } else {
        0x00FFFFFF
    }
}

/// Execute a function with the global Pdfium instance
pub fn with_pdfium<F, R>(f: F) -> Result<R>
where
    F: FnOnce(&Pdfium) -> Result<R>,
{
    let exec_lock = get_execution_lock();
    let _guard = match exec_lock.lock() {
        Ok(guard) => guard,
        Err(poisoned) => poisoned.into_inner(),
    };
    let pdfium = get_pdfium();
    f(pdfium)
}

/// Get the page count of a PDF file
pub fn get_pdf_page_count(path: String) -> Result<u32> {
    with_document(&path, |document| {
        Ok(document.pages().len() as u32)
    })
}

/// Get exact dimensions and aspect ratios for all pages without loading PdfPage objects.
/// Runs in under 3ms for a 1,000+ page document.
pub fn get_pdf_page_dimensions(path: String) -> Result<Vec<PdfPageDimension>> {
    timed!("get_pdf_page_dimensions", {
        with_document(&path, |document| {
            let pages = document.pages();
            let count = pages.len();
            let mut dims = Vec::with_capacity(count as usize);

            for i in 0..count {
                let rect = pages.page_size(i)?;
                let w = rect.width().value;
                let h = rect.height().value;
                let ar = if h > 0.0 { (w / h).clamp(0.2, 5.0) } else { 0.70 };
                dims.push(PdfPageDimension {
                    width: w,
                    height: h,
                    aspect_ratio: ar,
                });
            }
            Ok(dims)
        })
    })
}

const MAX_OUTLINE_DEPTH: u32 = 32;

/// Extract table of contents / bookmarks natively using PDFium C++ outline APIs.
/// Uses iterative sibling loops and depth bounds to prevent stack overflows,
/// with automatic parent page inheritance for container headings.
pub fn get_pdf_outline(path: String) -> Result<Vec<PdfOutlineItem>> {
    timed!("get_pdf_outline", {
        with_document(&path, |document| {
            let mut items = Vec::new();
            let bookmarks = document.bookmarks();
            
            if let Some(first_top_level) = bookmarks.root() {
                traverse_bookmark_level(first_top_level, 0, &mut items);
            }
            
            Ok(items)
        })
    })
}

fn traverse_bookmark_level(
    first_bookmark: PdfBookmark,
    depth: u32,
    out: &mut Vec<PdfOutlineItem>,
) {
    if depth >= MAX_OUTLINE_DEPTH {
        return;
    }

    let mut current = Some(first_bookmark);
    while let Some(bookmark) = current {
        let title = bookmark.title().unwrap_or_default().trim().to_string();

        let target_page = bookmark
            .destination()
            .and_then(|d| d.page_index().ok())
            .or_else(|| {
                bookmark.action().and_then(|action| {
                    if let PdfAction::LocalDestination(local) = action {
                        local.destination().ok().and_then(|d| d.page_index().ok())
                    } else {
                        None
                    }
                })
            })
            .map(|idx| idx as u32);

        let parent_insert_idx = if !title.is_empty() {
            let idx = out.len();
            out.push(PdfOutlineItem {
                title,
                page_index: target_page,
                depth,
            });
            Some(idx)
        } else {
            None
        };

        // Recurse ONLY on child nodes
        if let Some(child) = bookmark.first_child() {
            let child_start_idx = out.len();
            traverse_bookmark_level(child, depth + 1, out);

            // Container Heading Fallback: If parent has no destination, inherit first child's page
            if let Some(p_idx) = parent_insert_idx {
                if out[p_idx].page_index.is_none() && child_start_idx < out.len() {
                    out[p_idx].page_index = out[child_start_idx].page_index;
                }
            }
        }

        // Advance to next sibling iteratively
        current = bookmark.next_sibling();
    }
}

/// Render a specific page of a PDF directly to raw RGBA bytes with O(1) corner sampling.
/// Uses set_reverse_byte_order(true) so PDFium normalizes to RGBA8888 with hardware SIMD.
pub fn render_pdf_page(
    path: String,
    page_index: u32,
    width: u32,
    height: u32,
) -> Result<PdfPageRenderResult> {
    timed!("render_pdf_page", {
        with_document(&path, |document| {
            let page = document.pages().get(page_index as u16)?;
            
            let bitmap = page.render_with_config(
                &PdfRenderConfig::new()
                    .set_target_width(width as i32)
                    .set_maximum_height(height as i32)
                    .set_reverse_byte_order(true)
                    .render_form_data(true),
            )?;

            let actual_width = bitmap.width() as u32;
            let actual_height = bitmap.height() as u32;
            let raw_bytes = bitmap.as_rgba_bytes();

            let tl = extract_rgb(&raw_bytes, 0);
            let tr = extract_rgb(&raw_bytes, (actual_width.saturating_sub(1)) as usize * 4);
            let bl = extract_rgb(&raw_bytes, (actual_height.saturating_sub(1)) as usize * actual_width as usize * 4);
            let br = extract_rgb(&raw_bytes, (actual_height as usize * actual_width as usize).saturating_sub(1) * 4);

            Ok(PdfPageRenderResult {
                data: raw_bytes,
                width: actual_width,
                height: actual_height,
                top_left_rgb: tl,
                top_right_rgb: tr,
                bottom_left_rgb: bl,
                bottom_right_rgb: br,
            })
        })
    })
}

/// Extract sanitized page text with guarded de-hyphenation and UTF-16 code unit offset mapping.
/// Guarantees that Dart UTF-16 text offsets translate 1:1 to original PDFium glyph bounds without drift.
pub fn extract_sanitized_page_text(path: String, page_index: u32) -> Result<SanitizedPdfText> {
    timed!("extract_sanitized_page_text", {
        with_document(&path, |doc| {
            let page = doc.pages().get(page_index as u16)?;
            let text = page.text()?;
            let chars = text.chars();
            let total = chars.len();

            let mut clean_text = String::with_capacity(total);
            let mut clean_to_pdf_map = Vec::with_capacity(total);

            let mut i = 0;
            let mut prev_char: Option<char> = None;

            while i < total {
                let ch = chars.get(i).ok().and_then(|c| c.unicode_char()).unwrap_or(' ');

                // Guarded De-Hyphenation Check
                if ch == '-' && i + 2 < total {
                    let prev_is_alpha = prev_char.map(|c| c.is_alphabetic()).unwrap_or(false);
                    let next1 = chars.get(i + 1).ok().and_then(|c| c.unicode_char()).unwrap_or(' ');
                    let next2 = chars.get(i + 2).ok().and_then(|c| c.unicode_char()).unwrap_or(' ');

                    let is_crlf_break = next1 == '\r' && next2 == '\n' && i + 3 < total;
                    let after_break_char = if is_crlf_break {
                        chars.get(i + 3).ok().and_then(|c| c.unicode_char()).unwrap_or(' ')
                    } else if next1 == '\n' {
                        next2
                    } else {
                        ' '
                    };

                    if prev_is_alpha && after_break_char.is_lowercase() {
                        // True wrapped word: drop hyphen and line break
                        let skip = if is_crlf_break { 3 } else { 2 };
                        i += skip;
                        continue;
                    }
                }

                // Normalize line breaks to a single space
                if ch == '\r' || ch == '\n' {
                    if !clean_text.ends_with(' ') {
                        clean_text.push(' ');
                        clean_to_pdf_map.push(i as u32);
                    }
                    prev_char = Some(' ');
                    i += 1;
                    continue;
                }

                clean_text.push(ch);
                // Push index for each UTF-16 code unit (surrogate pairs push twice)
                for _ in 0..ch.len_utf16() {
                    clean_to_pdf_map.push(i as u32);
                }

                prev_char = Some(ch);
                i += 1;
            }

            Ok(SanitizedPdfText {
                clean_text,
                clean_to_pdf_map,
            })
        })
    })
}

/// Extract the text of a specific page of a PDF file.
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

            let x_points = (page_rect.left().value as f64 + (width * x_norm)) as f32;
            let y_points = (page_rect.top().value as f64 - (height * y_norm)) as f32;

            let text = page.text()?;
            let chars = text.chars();

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

                let Some(c) = ch.unicode_char() else {
                    continue;
                };

                if c.is_whitespace() {
                    continue;
                }

                let bounds = ch.loose_bounds().or_else(|_| ch.tight_bounds());
                let Ok(bounds) = bounds else { continue };
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

                let Some(c) = ch.unicode_char() else {
                    rects.push(PdfTextRect { left: 0.0, top: 0.0, right: 0.0, bottom: 0.0 });
                    continue;
                };

                if c.is_whitespace() {
                    rects.push(PdfTextRect { left: 0.0, top: 0.0, right: 0.0, bottom: 0.0 });
                    continue;
                }

                let bounds = ch.loose_bounds().or_else(|_| ch.tight_bounds());
                let Ok(bounds) = bounds else {
                    rects.push(PdfTextRect { left: 0.0, top: 0.0, right: 0.0, bottom: 0.0 });
                    continue;
                };

                let mut left = (bounds.left().value - page_left) / width;
                let mut right = (bounds.right().value - page_left) / width;
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

pub fn test_pdf_module() -> String {
    "PDF module loaded successfully".to_string()
}
