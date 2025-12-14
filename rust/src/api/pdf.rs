use anyhow::Result;
use pdfium_render::prelude::*;
use std::sync::OnceLock;

// Global Pdfium instance for thread-safe reuse
static PDFIUM: OnceLock<Pdfium> = OnceLock::new();

fn get_pdfium() -> &'static Pdfium {
    PDFIUM.get_or_init(|| {
        Pdfium::new(
            // On Android, typical pattern is to bind to bundled library or system library
            Pdfium::bind_to_library("libpdfium.so")
                .or_else(|_| Pdfium::bind_to_system_library())
                .expect("Failed to bind to pdfium library"),
        )
    })
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

/// Test function to verify PDF module is working
pub fn test_pdf_module() -> String {
    "PDF module loaded successfully".to_string()
}
