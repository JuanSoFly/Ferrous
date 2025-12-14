use anyhow::{Context, Result};
use image::ImageFormat;
use std::fs::File;
use std::io::{BufReader, Read, Write};
use std::path::Path;
use zip::ZipArchive;

use crate::api::pdf::with_pdfium;

/// Extract cover from a book file and save it to the specified path.
/// Returns the saved path on success.
pub fn extract_cover(book_path: String, save_path: String) -> Result<String> {
    let path = Path::new(&book_path);
    let extension = path
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .unwrap_or_default();

    match extension.as_str() {
        "pdf" => extract_pdf_cover(&book_path, &save_path),
        "epub" => extract_epub_cover(&book_path, &save_path),
        "cbz" | "cbr" => extract_cbz_cover(&book_path, &save_path),
        _ => Err(anyhow::anyhow!("Unsupported format for cover extraction: {}", extension)),
    }
}

fn extract_pdf_cover(book_path: &str, save_path: &str) -> Result<String> {
    with_pdfium(|pdfium| {
        let doc = pdfium
            .load_pdf_from_file(book_path, None)
            .map_err(|e| anyhow::anyhow!("Failed to load PDF: {:?}", e))?;

        let page = doc
            .pages()
            .get(0)
            .map_err(|e| anyhow::anyhow!("Failed to get first page: {:?}", e))?;

        // Render at a reasonable thumbnail size (300px width)
        let width = 300;
        let scale = width as f32 / page.width().value;
        let height = (page.height().value * scale) as i32;

        let bitmap = page
            .render_with_config(
                &pdfium_render::prelude::PdfRenderConfig::new()
                    .set_target_width(width)
                    .set_target_height(height),
            )
            .map_err(|e| anyhow::anyhow!("Failed to render page: {:?}", e))?;

        let img = bitmap.as_image();
        img.save_with_format(save_path, ImageFormat::Png)
            .context("Failed to save PDF cover")?;

        Ok(save_path.to_string())
    })
}

fn extract_epub_cover(book_path: &str, save_path: &str) -> Result<String> {
    let file = File::open(book_path).context("Failed to open EPUB file")?;
    let reader = BufReader::new(file);
    let mut archive = ZipArchive::new(reader).context("Failed to read EPUB archive")?;

    // Common cover image paths in EPUB
    let possible_cover_paths = [
        "cover.jpg",
        "cover.jpeg",
        "cover.png",
        "OEBPS/cover.jpg",
        "OEBPS/cover.jpeg",
        "OEBPS/cover.png",
        "OEBPS/images/cover.jpg",
        "OEBPS/images/cover.jpeg",
        "OEBPS/images/cover.png",
        "OPS/cover.jpg",
        "OPS/cover.jpeg",
        "OPS/cover.png",
        "Images/cover.jpg",
        "Images/cover.jpeg",
        "Images/cover.png",
    ];

    // Try common paths first
    for cover_path in &possible_cover_paths {
        if let Ok(mut entry) = archive.by_name(cover_path) {
            let mut buffer = Vec::new();
            entry.read_to_end(&mut buffer)?;

            let mut out_file = File::create(save_path).context("Failed to create cover file")?;
            out_file.write_all(&buffer)?;
            return Ok(save_path.to_string());
        }
    }

    // Fallback: find any image file that might be a cover
    for i in 0..archive.len() {
        let mut entry = archive.by_index(i)?;
        let name = entry.name().to_lowercase();

        if (name.contains("cover") || name.contains("title"))
            && (name.ends_with(".jpg") || name.ends_with(".jpeg") || name.ends_with(".png"))
        {
            let mut buffer = Vec::new();
            entry.read_to_end(&mut buffer)?;

            let mut out_file = File::create(save_path).context("Failed to create cover file")?;
            out_file.write_all(&buffer)?;
            return Ok(save_path.to_string());
        }
    }

    Err(anyhow::anyhow!("No cover image found in EPUB"))
}

fn extract_cbz_cover(book_path: &str, save_path: &str) -> Result<String> {
    let file = File::open(book_path).context("Failed to open CBZ file")?;
    let reader = BufReader::new(file);
    let mut archive = ZipArchive::new(reader).context("Failed to read CBZ archive")?;

    // Get first image in archive (sorted by name)
    let mut image_names: Vec<String> = Vec::new();
    for i in 0..archive.len() {
        let entry = archive.by_index(i)?;
        let name = entry.name().to_lowercase();
        if name.ends_with(".jpg") || name.ends_with(".jpeg") || name.ends_with(".png") || name.ends_with(".webp") {
            image_names.push(entry.name().to_string());
        }
    }

    image_names.sort();

    if let Some(first_image) = image_names.first() {
        let mut entry = archive.by_name(first_image)?;
        let mut buffer = Vec::new();
        entry.read_to_end(&mut buffer)?;

        let mut out_file = File::create(save_path).context("Failed to create cover file")?;
        out_file.write_all(&buffer)?;
        return Ok(save_path.to_string());
    }

    Err(anyhow::anyhow!("No image found in CBZ"))
}
