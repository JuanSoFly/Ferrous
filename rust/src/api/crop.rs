use anyhow::Result;
use image::{GenericImageView, Pixel};
use pdfium_render::prelude::*;

use crate::api::pdf::with_pdfium;

#[derive(Debug, Clone, Copy)]
pub struct CropMargins {
    pub top: f32,
    pub bottom: f32,
    pub left: f32,
    pub right: f32,
}

/// Analyze a PDF page to detect whitespace margins.
/// Returns relative margins (0.0 to 1.0).
pub fn detect_pdf_whitespace(path: String, page_index: u32) -> Result<CropMargins> {
    with_pdfium(|pdfium| {
        let doc = pdfium
            .load_pdf_from_file(&path, None)
            .map_err(|e| anyhow::anyhow!("Failed to load PDF: {:?}", e))?;

        let page = doc
            .pages()
            .get(page_index as u16)
            .map_err(|e| anyhow::anyhow!("Failed to get page: {:?}", e))?;

        // Render at a fixed width for analysis (500px is enough for layout detection)
        let width = 500;
        let scale = width as f32 / page.width().value;
        let height = (page.height().value * scale) as i32;

        let bitmap = page
            .render_with_config(
                &PdfRenderConfig::new()
                    .set_target_width(width)
                    .set_target_height(height),
            )
            .map_err(|e| anyhow::anyhow!("Failed to render page: {:?}", e))?;

        let img = bitmap.as_image();
        let (w, h) = img.dimensions();

        let mut top = 0;
        let mut bottom = h - 1;
        let mut left = 0;
        let mut right = w - 1;
        
        let threshold: u8 = 5; // Tolerance for "white" (0-255).
        let white_cutoff = 255u8.saturating_sub(threshold);
        let is_white = |p: image::Rgba<u8>| {
            let ch = p.channels();
            ch[0] > white_cutoff && ch[1] > white_cutoff && ch[2] > white_cutoff
        };

        // Find Top
        'top_loop: for y in 0..h {
            for x in 0..w {
                if !is_white(img.get_pixel(x, y)) {
                    top = y;
                    break 'top_loop;
                }
            }
        }

        // Find Bottom
        'bottom_loop: for y in (0..h).rev() {
            for x in 0..w {
                if !is_white(img.get_pixel(x, y)) {
                    bottom = y;
                    break 'bottom_loop;
                }
            }
        }

        // Find Left
        'left_loop: for x in 0..w {
            for y in top..=bottom {
                if !is_white(img.get_pixel(x, y)) {
                    left = x;
                    break 'left_loop;
                }
            }
        }

        // Find Right
        'right_loop: for x in (0..w).rev() {
            for y in top..=bottom {
                if !is_white(img.get_pixel(x, y)) {
                    right = x;
                    break 'right_loop;
                }
            }
        }

        // Add a small padding (e.g. 5px scaled)
        let padding = 5;
        top = top.saturating_sub(padding);
        bottom = (bottom + padding).min(h - 1);
        left = left.saturating_sub(padding);
        right = (right + padding).min(w - 1);

        // Convert to relative
        Ok(CropMargins {
            top: top as f32 / h as f32,
            bottom: 1.0 - (bottom as f32 / h as f32),
            left: left as f32 / w as f32,
            right: 1.0 - (right as f32 / w as f32),
        })
    })
}
