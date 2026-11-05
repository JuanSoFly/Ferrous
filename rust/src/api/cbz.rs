use std::fs::File;
use std::io::{Read, BufReader};
use std::sync::{Arc, Mutex, OnceLock};
use std::num::NonZeroUsize;
use lru::LruCache;
use crate::timed;
use zip::ZipArchive;
use image::GenericImageView;
use anyhow::{Result, Context, anyhow};

static CBZ_ENTRIES_CACHE: OnceLock<Mutex<LruCache<String, Arc<Vec<String>>>>> = OnceLock::new();

fn get_entries_cache() -> &'static Mutex<LruCache<String, Arc<Vec<String>>>> {
    CBZ_ENTRIES_CACHE.get_or_init(|| {
        Mutex::new(LruCache::new(NonZeroUsize::new(8).unwrap()))
    })
}

fn get_cached_or_read_entries(path: &str, archive: &mut ZipArchive<BufReader<File>>) -> Arc<Vec<String>> {
    let cache = get_entries_cache();
    {
        let mut lock = match cache.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        if let Some(entries) = lock.get(path) {
            return entries.clone();
        }
    }

    let entries = Arc::new(get_image_entries(archive));
    let mut lock = match cache.lock() {
        Ok(g) => g,
        Err(p) => p.into_inner(),
    };
    lock.put(path.to_string(), entries.clone());
    entries
}

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
    timed!("get_cbz_page_count", {
        let file = File::open(&path)
            .with_context(|| format!("Failed to open CBZ file: {}", path))?;
        let reader = BufReader::new(file);
        let mut archive = ZipArchive::new(reader)
            .with_context(|| "Failed to read ZIP archive")?;
        
        let entries = get_cached_or_read_entries(&path, &mut archive);
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
        
        let entries = get_cached_or_read_entries(&path, &mut archive);
        Ok((*entries).clone())
    })
}

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

        // Preserve 100% full original resolution quality.
        // Only downscale if the image exceeds safe GPU hardware limits (> 2560px)
        // to prevent OOM while keeping native sharpness with zero blur.
        let img = if let Some(max_w) = max_width {
            let (w, h) = img.dimensions();
            let threshold = (max_w as f32 * 1.5).max(2048.0) as u32;
            if w > threshold {
                let target_w = threshold.min(2560);
                let scale = target_w as f32 / w as f32;
                let new_h = (h as f32 * scale) as u32;
                img.resize(target_w, new_h, image::imageops::FilterType::Triangle)
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
        
        let entries = get_cached_or_read_entries(&path, &mut archive);
        
        if index < 0 || index as usize >= entries.len() {
            return Err(anyhow!("Page index {} out of range (0-{})", index, entries.len() - 1));
        }
        
        let entry_name = &entries[index as usize];
        
        let mut entry = archive.by_name(entry_name)
            .with_context(|| format!("Failed to read entry: {}", entry_name))?;
        
        let mut buffer = Vec::new();
        entry.read_to_end(&mut buffer)
            .with_context(|| "Failed to read image data")?;
        
        let img = image::load_from_memory(&buffer)
            .with_context(|| "Failed to decode image")?;
        
        // Preserve 100% full original resolution quality.
        // Only downscale if the image exceeds safe GPU hardware limits (> 2560px)
        // to prevent OOM while keeping native sharpness with zero blur.
        let img = if let Some(max_w) = max_width {
            let (w, h) = img.dimensions();
            let threshold = (max_w as f32 * 1.5).max(2048.0) as u32;
            if w > threshold {
                let target_w = threshold.min(2560);
                let scale = target_w as f32 / w as f32;
                let new_h = (h as f32 * scale) as u32;
                img.resize(target_w, new_h, image::imageops::FilterType::Triangle)
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
