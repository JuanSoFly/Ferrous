use anyhow::{Context, Result};
use crate::timed;
use image::{imageops::FilterType, GenericImageView, ImageFormat};
use std::fs::File;
use std::io::{BufReader, Read, Seek, Write};
use std::path::Path;
use zip::ZipArchive;

use crate::api::pdf::{load_pdf_document, with_pdfium};

fn percent_decode_to_string(input: &str) -> String {
    let bytes = input.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(hex) = std::str::from_utf8(&bytes[i + 1..i + 3]) {
                if let Ok(value) = u8::from_str_radix(hex, 16) {
                    out.push(value);
                    i += 3;
                    continue;
                }
            }
        }
        if bytes[i] == b'+' {
            out.push(b' ');
        } else {
            out.push(bytes[i]);
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

fn normalize_zip_path(path: &str) -> String {
    let mut parts: Vec<&str> = Vec::new();
    let normalized = path.replace('\\', "/");
    for segment in normalized.split('/') {
        if segment.is_empty() || segment == "." {
            continue;
        }
        if segment == ".." {
            parts.pop();
            continue;
        }
        parts.push(segment);
    }
    parts.join("/")
}

fn strip_fragment_and_query(href: &str) -> &str {
    href.split('#')
        .next()
        .unwrap_or(href)
        .split('?')
        .next()
        .unwrap_or(href)
}

fn resolve_epub_href(base_file: &str, href: &str) -> String {
    let cleaned = percent_decode_to_string(strip_fragment_and_query(href).trim());
    if cleaned.starts_with("http://") || cleaned.starts_with("https://") {
        return cleaned;
    }

    let joined = if cleaned.starts_with('/') {
        cleaned.trim_start_matches('/').to_string()
    } else {
        let base_dir = Path::new(base_file)
            .parent()
            .and_then(|p| p.to_str())
            .unwrap_or("");
        if base_dir.is_empty() {
            cleaned
        } else {
            format!("{base_dir}/{cleaned}")
        }
    };

    normalize_zip_path(&joined)
}

fn is_supported_image_path(path: &str) -> bool {
    let name = path.to_lowercase();
    name.ends_with(".jpg")
        || name.ends_with(".jpeg")
        || name.ends_with(".png")
        || name.ends_with(".webp")
        || name.ends_with(".gif")
}

fn find_zip_entry_case_insensitive<R: Read + Seek>(
    archive: &mut ZipArchive<R>,
    wanted: &str,
) -> Option<String> {
    let wanted_lower = wanted.to_lowercase();
    for i in 0..archive.len() {
        let entry = match archive.by_index(i) {
            Ok(entry) => entry,
            Err(_) => continue,
        };
        let name = entry.name().to_string();
        if name.to_lowercase() == wanted_lower {
            return Some(name);
        }
    }
    None
}

fn read_zip_bytes<R: Read + Seek>(archive: &mut ZipArchive<R>, name: &str) -> Result<Vec<u8>> {
    if let Ok(mut file) = archive.by_name(name) {
        let mut buffer = Vec::new();
        file.read_to_end(&mut buffer)
            .with_context(|| format!("Failed to read zip entry: {}", file.name()))?;
        return Ok(buffer);
    }

    if let Some(actual) = find_zip_entry_case_insensitive(archive, name) {
        let mut file = archive
            .by_name(&actual)
            .with_context(|| format!("Failed to open zip entry: {actual}"))?;
        let mut buffer = Vec::new();
        file.read_to_end(&mut buffer)
            .with_context(|| format!("Failed to read zip entry: {}", file.name()))?;
        return Ok(buffer);
    }

    Err(anyhow::anyhow!("Zip entry not found: {}", name))
}

fn read_zip_string<R: Read + Seek>(archive: &mut ZipArchive<R>, name: &str) -> Result<String> {
    let bytes = read_zip_bytes(archive, name)?;
    Ok(String::from_utf8_lossy(&bytes).to_string())
}

fn extract_first_image_ref_from_html(html: &str) -> Option<String> {
    let doc = scraper::Html::parse_document(html);

    if let Ok(selector) = scraper::Selector::parse("img") {
        if let Some(img) = doc.select(&selector).next() {
            if let Some(src) = img.value().attr("src") {
                if !src.trim().is_empty() {
                    return Some(src.to_string());
                }
            }
        }
    }

    // Some EPUBs use inline SVG with <image href="...">.
    if let Ok(selector) = scraper::Selector::parse("image") {
        if let Some(img) = doc.select(&selector).next() {
            if let Some(href) = img.value().attr("href").or_else(|| img.value().attr("xlink:href")) {
                if !href.trim().is_empty() {
                    return Some(href.to_string());
                }
            }
        }
    }

    None
}

/// Extract cover from a book file and save it to the specified path.
/// Returns the saved path on success.
#[hotpath::measure]
pub fn extract_cover(book_path: String, save_path: String) -> Result<String> {
    timed!("extract_cover", {
        let format = book_path.split('.').last().unwrap_or("").to_lowercase();
        match format.as_str() {
            "pdf" => extract_pdf_cover(&book_path, &save_path),
            "epub" => extract_epub_cover(&book_path, &save_path),
            "cbz" | "cbr" => extract_cbz_cover(&book_path, &save_path),
            // TODO: Implement MOBI cover extraction
            // "mobi" | "azw3" => extract_mobi_cover(&book_path, &save_path),
            _ => Err(anyhow::anyhow!("Unsupported format for cover extraction: {}", format)),
        }
    })
}

fn extract_pdf_cover(book_path: &str, save_path: &str) -> Result<String> {
    with_pdfium(|pdfium| {
        let doc = load_pdf_document(pdfium, book_path)?;

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

    // Prefer OPF-based cover detection (EPUB2/EPUB3).
    if let Ok(saved) = extract_epub_cover_from_opf(&mut archive, save_path) {
        return Ok(saved);
    }

    // Common cover image paths in EPUB
    let possible_cover_paths = [
        "cover.jpg",
        "cover.jpeg",
        "cover.png",
        "cover.webp",
        "cover.gif",
        "OEBPS/cover.jpg",
        "OEBPS/cover.jpeg",
        "OEBPS/cover.png",
        "OEBPS/cover.webp",
        "OEBPS/cover.gif",
        "OEBPS/images/cover.jpg",
        "OEBPS/images/cover.jpeg",
        "OEBPS/images/cover.png",
        "OEBPS/images/cover.webp",
        "OEBPS/images/cover.gif",
        "OPS/cover.jpg",
        "OPS/cover.jpeg",
        "OPS/cover.png",
        "OPS/cover.webp",
        "OPS/cover.gif",
        "Images/cover.jpg",
        "Images/cover.jpeg",
        "Images/cover.png",
        "Images/cover.webp",
        "Images/cover.gif",
    ];

    // Try common paths first
    for cover_path in &possible_cover_paths {
        if let Ok(mut entry) = archive.by_name(cover_path) {
            let mut buffer = Vec::new();
            entry.read_to_end(&mut buffer)?;
            if let Ok(saved) = save_cover_thumbnail(&buffer, save_path) {
                return Ok(saved);
            }
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
            && (name.ends_with(".jpg")
                || name.ends_with(".jpeg")
                || name.ends_with(".png")
                || name.ends_with(".webp")
                || name.ends_with(".gif"))
        {
            let mut buffer = Vec::new();
            entry.read_to_end(&mut buffer)?;
            if let Ok(saved) = save_cover_thumbnail(&buffer, save_path) {
                return Ok(saved);
            }
            let mut out_file = File::create(save_path).context("Failed to create cover file")?;
            out_file.write_all(&buffer)?;
            return Ok(save_path.to_string());
        }
    }

    Err(anyhow::anyhow!("No cover image found in EPUB"))
}

fn extract_epub_cover_from_opf<R: Read + Seek>(
    archive: &mut ZipArchive<R>,
    save_path: &str,
) -> Result<String> {
    let container_xml = read_zip_string(archive, "META-INF/container.xml")
        .context("Missing META-INF/container.xml")?;
    let container_doc = roxmltree::Document::parse(&container_xml)
        .context("Failed to parse META-INF/container.xml")?;

    let mut opf_path: Option<String> = None;
    for node in container_doc.descendants().filter(|n| n.is_element()) {
        if node.tag_name().name() != "rootfile" {
            continue;
        }
        if let Some(full) = node.attribute("full-path") {
            if !full.trim().is_empty() {
                opf_path = Some(normalize_zip_path(full.trim()));
                break;
            }
        }
    }

    let opf_path = opf_path.context("No OPF rootfile found in container.xml")?;
    let opf_xml = read_zip_string(archive, &opf_path)
        .with_context(|| format!("Failed to read OPF: {opf_path}"))?;
    let opf_doc = roxmltree::Document::parse(&opf_xml).context("Failed to parse OPF")?;

    #[derive(Clone, Debug)]
    struct ManifestItem {
        id: String,
        href: String,
        media_type: Option<String>,
        properties: Option<String>,
    }

    let mut manifest: Vec<ManifestItem> = Vec::new();
    for node in opf_doc.descendants().filter(|n| n.is_element()) {
        if node.tag_name().name() != "item" {
            continue;
        }
        let id = node.attribute("id").unwrap_or("").trim();
        let href = node.attribute("href").unwrap_or("").trim();
        if id.is_empty() || href.is_empty() {
            continue;
        }
        manifest.push(ManifestItem {
            id: id.to_string(),
            href: href.to_string(),
            media_type: node.attribute("media-type").map(|s| s.trim().to_string()),
            properties: node.attribute("properties").map(|s| s.trim().to_string()),
        });
    }

    let is_image_item = |item: &ManifestItem| -> bool {
        if let Some(mt) = &item.media_type {
            if mt.to_lowercase().starts_with("image/") {
                return true;
            }
        }
        is_supported_image_path(&item.href)
    };

    let save_from_href = |archive: &mut ZipArchive<R>, base: &str, href: &str| -> Result<String> {
        let resolved = resolve_epub_href(base, href);
        if resolved.starts_with("http://") || resolved.starts_with("https://") {
            return Err(anyhow::anyhow!("External cover ref not supported: {}", resolved));
        }
        let bytes = read_zip_bytes(archive, &resolved)
            .with_context(|| format!("Failed to read cover bytes: {resolved}"))?;
        save_cover_thumbnail(&bytes, save_path).or_else(|_| {
            let mut out_file =
                File::create(save_path).context("Failed to create cover file")?;
            out_file.write_all(&bytes)?;
            Ok(save_path.to_string())
        })
    };

    // 1) EPUB3: <item properties="cover-image" ... />
    if let Some(item) = manifest.iter().find(|item| {
        is_image_item(item)
            && item
                .properties
                .as_deref()
                .unwrap_or("")
                .split_whitespace()
                .any(|p| p.eq_ignore_ascii_case("cover-image"))
    }) {
        return save_from_href(archive, &opf_path, &item.href);
    }

    // 2) EPUB2: <meta name="cover" content="cover-image-id" />
    let mut cover_id: Option<String> = None;
    for node in opf_doc.descendants().filter(|n| n.is_element()) {
        if node.tag_name().name() != "meta" {
            continue;
        }
        let name = node.attribute("name").unwrap_or("").trim();
        if !name.eq_ignore_ascii_case("cover") {
            continue;
        }
        if let Some(content) = node.attribute("content") {
            let content = content.trim();
            if !content.is_empty() {
                cover_id = Some(content.to_string());
                break;
            }
        }
    }

    if let Some(cover_id) = cover_id {
        if let Some(item) = manifest
            .iter()
            .find(|item| item.id == cover_id && is_image_item(item))
        {
            return save_from_href(archive, &opf_path, &item.href);
        }
    }

    // 3) Guide reference to cover page or cover image.
    for node in opf_doc.descendants().filter(|n| n.is_element()) {
        if node.tag_name().name() != "reference" {
            continue;
        }
        let typ = node.attribute("type").unwrap_or("").trim();
        if !(typ.eq_ignore_ascii_case("cover") || typ.eq_ignore_ascii_case("title-page")) {
            continue;
        }
        let href = node.attribute("href").unwrap_or("").trim();
        if href.is_empty() {
            continue;
        }

        let resolved = resolve_epub_href(&opf_path, href);
        if resolved.starts_with("http://") || resolved.starts_with("https://") {
            continue;
        }

        if is_supported_image_path(&resolved) {
            if let Ok(saved) = save_from_href(archive, &opf_path, href) {
                return Ok(saved);
            }
        }

        let html = read_zip_string(archive, &resolved).ok();
        let Some(html) = html else {
            continue;
        };

        if let Some(img_href) = extract_first_image_ref_from_html(&html) {
            let cover_img_path = resolve_epub_href(&resolved, &img_href);
            if cover_img_path.starts_with("http://") || cover_img_path.starts_with("https://") {
                continue;
            }
            if let Ok(bytes) = read_zip_bytes(archive, &cover_img_path) {
                if let Ok(saved) = save_cover_thumbnail(&bytes, save_path) {
                    return Ok(saved);
                }
                let mut out_file =
                    File::create(save_path).context("Failed to create cover file")?;
                out_file.write_all(&bytes)?;
                return Ok(save_path.to_string());
            }
        }
    }

    // 4) Heuristic: any manifest image item whose id/href suggests cover.
    if let Some(item) = manifest.iter().find(|item| {
        if !is_image_item(item) {
            return false;
        }
        let id = item.id.to_lowercase();
        let href = item.href.to_lowercase();
        id.contains("cover") || href.contains("cover") || href.contains("title")
    }) {
        return save_from_href(archive, &opf_path, &item.href);
    }

    Err(anyhow::anyhow!("No cover image found via OPF metadata"))
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
        if let Ok(saved) = save_cover_thumbnail(&buffer, save_path) {
            return Ok(saved);
        }
        let mut out_file = File::create(save_path).context("Failed to create cover file")?;
        out_file.write_all(&buffer)?;
        return Ok(save_path.to_string());
    }

    Err(anyhow::anyhow!("No image found in CBZ"))
}

fn save_cover_thumbnail(bytes: &[u8], save_path: &str) -> Result<String> {
    let image = image::load_from_memory(bytes)
        .map_err(|e| anyhow::anyhow!("Failed to decode cover image: {:?}", e))?;
    let (width, height) = image.dimensions();
    let max_dim = 360u32;
    let resized = if width > max_dim || height > max_dim {
        let scale = if width >= height {
            max_dim as f32 / width as f32
        } else {
            max_dim as f32 / height as f32
        };
        let new_width = (width as f32 * scale).round().max(1.0) as u32;
        let new_height = (height as f32 * scale).round().max(1.0) as u32;
        image.resize(new_width, new_height, FilterType::Triangle)
    } else {
        image
    };

    resized
        .save_with_format(save_path, ImageFormat::Png)
        .context("Failed to save cover thumbnail")?;
    Ok(save_path.to_string())
}
