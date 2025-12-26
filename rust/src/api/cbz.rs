use std::fs::File;
use std::io::{Read, BufReader};
use crate::timed;
use zip::ZipArchive;
use image::GenericImageView;
use anyhow::{Result, Context, anyhow};

/// Struct to hold extracted page data
#[derive(Debug)]
pub struct CbzPageData {
    pub width: i32,
    pub height: i32,
    pub rgba_bytes: Vec<u8>,
}

/// Check if a filename is a supported image format
fn is_image_file(name: &str) -> bool {
    let lower = name.to_lowercase();
    lower.ends_with(".jpg") ||
    lower.ends_with(".jpeg") ||
    lower.ends_with(".png") ||
    lower.ends_with(".gif") ||
    lower.ends_with(".webp")
}

/// Get sorted list of image entries from archive
fn get_image_entries(archive: &mut ZipArchive<BufReader<File>>) -> Vec<String> {
    let mut entries: Vec<String> = (0..archive.len())
        .filter_map(|i| {
            archive.by_index(i).ok().and_then(|entry| {
                let name = entry.name().to_string();
                if !entry.is_dir() && is_image_file(&name) {
                    Some(name)
                } else {
                    None
                }
            })
        })
        .collect();
    entries.sort();
    entries
}

/// Get total number of image pages in a CBZ archive
#[flutter_rust_bridge::frb]
pub fn get_cbz_page_count(path: String) -> Result<i32> {
    let file = File::open(&path)
        .with_context(|| format!("Failed to open CBZ file: {}", path))?;
    let reader = BufReader::new(file);
    let mut archive = ZipArchive::new(reader)
        .with_context(|| "Failed to read ZIP archive")?;
    
    let _entries = get_image_entries(&mut archive);
    timed!("get_cbz_page_count", {
        let file = File::open(&path)?;
        let reader = BufReader::new(file);
        let mut archive = ZipArchive::new(reader)?;
        
        let entries = get_image_entries(&mut archive);
        Ok(entries.len() as i32)
    })
}

/// Get list of page names (sorted) for chapter detection etc
#[flutter_rust_bridge::frb]
#[hotpath::measure]
pub fn get_cbz_page_names(path: String) -> Result<Vec<String>> {
    timed!("get_cbz_page_names", {
        let file = File::open(&path)?;
        let reader = BufReader::new(file);
        let mut archive = ZipArchive::new(reader)?;
        
        Ok(get_image_entries(&mut archive))
    })
}

/// Extract and optionally resize a single page
/// Returns raw RGBA bytes for memory efficiency
/// Extract and optionally resize a single page by its known entry name.
/// This avoids the O(n) scan of the archive when page names are already cached in Dart.
#[flutter_rust_bridge::frb]
#[hotpath::measure]
pub fn get_cbz_page_by_name(
    path: String,
    entry_name: String,
    max_width: Option<i32>,
) -> Result<CbzPageData> {
    timed!("get_cbz_page_by_name", {
        let file = File::open(&path)?;
        let reader = BufReader::new(file);
        let mut archive = ZipArchive::new(reader)?;

        // Read the image data directly by name
        let mut entry = archive.by_name(&entry_name)
            .with_context(|| format!("Failed to read entry: {}", entry_name))?;

        let mut buffer = Vec::new();
        entry.read_to_end(&mut buffer)
            .with_context(|| "Failed to read image data")?;

        // Decode the image
        let img = image::load_from_memory(&buffer)
            .with_context(|| "Failed to decode image")?;

        // Optionally resize to limit memory usage
        let img = if let Some(max_w) = max_width {
            let (w, h) = img.dimensions();
            if w > max_w as u32 {
                let scale = max_w as f32 / w as f32;
                let new_h = (h as f32 * scale) as u32;
                img.resize(max_w as u32, new_h, image::imageops::FilterType::Triangle)
            } else {
                img
            }
        } else {
            img
        };

        // Convert to RGBA bytes
        let rgba = img.to_rgba8();
        let (width, height) = rgba.dimensions();

        Ok(CbzPageData {
            width: width as i32,
            height: height as i32,
            rgba_bytes: rgba.into_raw(),
        })
    })
}

/// Extract and optionally resize a single page by index.
/// Note: This is O(n) as it must scan the archive to find the stable sorted image at 'index'.
/// Prefer get_cbz_page_by_name if the list of names has already been retrieved.
#[flutter_rust_bridge::frb]
#[hotpath::measure]
pub fn get_cbz_page(
    path: String,
    index: i32,
    max_width: Option<i32>,
) -> Result<CbzPageData> {
    timed!("get_cbz_page", {
        let file = File::open(&path)?;
        let reader = BufReader::new(file);
        let mut archive = ZipArchive::new(reader)?;
        
        // Get sorted image entries (O(n))
        let entries = get_image_entries(&mut archive);
        
        if index < 0 || index as usize >= entries.len() {
            return Err(anyhow!("Page index {} out of range (0-{})", index, entries.len() - 1));
        }
        
        let entry_name = entries[index as usize].clone();
        
        let mut entry = archive.by_name(&entry_name)
            .with_context(|| format!("Failed to read entry: {}", entry_name))?;
        
        let mut buffer = Vec::new();
        entry.read_to_end(&mut buffer)
            .with_context(|| "Failed to read image data")?;
        
        let img = image::load_from_memory(&buffer)
            .with_context(|| "Failed to decode image")?;
        
        let img = if let Some(max_w) = max_width {
            let (w, h) = img.dimensions();
            if w > max_w as u32 {
                let scale = max_w as f32 / w as f32;
                let new_h = (h as f32 * scale) as u32;
                img.resize(max_w as u32, new_h, image::imageops::FilterType::Triangle)
            } else {
                img
            }
        } else {
            img
        };
        
        let rgba = img.to_rgba8();
        let (width, height) = rgba.dimensions();
        
        Ok(CbzPageData {
            width: width as i32,
            height: height as i32,
            rgba_bytes: rgba.into_raw(),
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_is_image_file() {
        assert!(is_image_file("page.jpg"));
        assert!(is_image_file("PAGE.PNG"));
        assert!(is_image_file("test.webp"));
        assert!(!is_image_file("readme.txt"));
        assert!(!is_image_file("folder/"));
    }
}
