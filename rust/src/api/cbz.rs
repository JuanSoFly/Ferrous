use std::fs::File;
use std::io::{Read, BufReader};
use std::sync::{Arc, Mutex, OnceLock};
use std::num::NonZeroUsize;
use std::collections::HashMap;
use lru::LruCache;
use crate::timed;
use zip::ZipArchive;
use unrar_rs::RarArchive;
use image::GenericImageView;
use anyhow::{Result, Context, anyhow};

static CBZ_ENTRIES_CACHE: OnceLock<Mutex<LruCache<String, Arc<Vec<String>>>>> = OnceLock::new();
static ARCHIVE_LOCKS: OnceLock<Mutex<HashMap<String, Arc<Mutex<()>>>>> = OnceLock::new();

fn get_archive_lock(path: &str) -> Arc<Mutex<()>> {
    let map = ARCHIVE_LOCKS.get_or_init(|| Mutex::new(HashMap::new()));
    let mut lock = match map.lock() {
        Ok(g) => g,
        Err(p) => p.into_inner(),
    };
    lock.entry(path.to_string())
        .or_insert_with(|| Arc::new(Mutex::new(())))
        .clone()
}

fn get_entries_cache() -> &'static Mutex<LruCache<String, Arc<Vec<String>>>> {
    CBZ_ENTRIES_CACHE.get_or_init(|| {
        Mutex::new(LruCache::new(NonZeroUsize::new(8).unwrap()))
    })
}

fn is_rar_file(path: &str) -> bool {
    if let Ok(mut file) = File::open(path) {
        let mut magic = [0u8; 4];
        if file.read_exact(&mut magic).is_ok() {
            return &magic == b"Rar!";
        }
    }
    false
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

fn read_zip_image_entries(path: &str) -> Result<Vec<String>> {
    let file = File::open(path)
        .with_context(|| format!("Failed to open file: {}", path))?;
    let reader = BufReader::new(file);
    let mut archive = ZipArchive::new(reader)
        .with_context(|| "Failed to read ZIP archive")?;

    let mut entries: Vec<String> = (0..archive.len())
        .filter_map(|i| {
            let entry = archive.by_index(i).ok()?;
            let name = entry.name().to_string();
            if !entry.is_dir() && is_image_file(&name) {
                Some(name)
            } else {
                None
            }
        })
        .collect();
    entries.sort();
    Ok(entries)
}

fn read_rar_image_entries(path: &str) -> Result<Vec<String>> {
    let file = File::open(path)
        .with_context(|| format!("Failed to open file: {}", path))?;
    let archive = RarArchive::open(file)
        .with_context(|| "Failed to read RAR archive")?;

    let mut entries: Vec<String> = archive
        .entries()
        .filter_map(|entry| {
            let name = entry.name.clone();
            if is_image_file(&name) {
                Some(name)
            } else {
                None
            }
        })
        .collect();
    entries.sort();
    Ok(entries)
}

fn get_archive_image_entries(path: &str) -> Result<Vec<String>> {
    let archive_lock = get_archive_lock(path);
    let _guard = match archive_lock.lock() {
        Ok(g) => g,
        Err(p) => p.into_inner(),
    };

    if is_rar_file(path) {
        if let Ok(entries) = read_rar_image_entries(path) {
            return Ok(entries);
        }
    }

    match read_zip_image_entries(path) {
        Ok(entries) => Ok(entries),
        Err(zip_err) => {
            read_rar_image_entries(path)
                .with_context(|| format!("Failed to read archive as ZIP ({}) or RAR", zip_err))
        }
    }
}

fn get_cached_or_read_entries(path: &str) -> Result<Arc<Vec<String>>> {
    let cache = get_entries_cache();
    {
        let mut lock = match cache.lock() {
            Ok(g) => g,
            Err(p) => p.into_inner(),
        };
        if let Some(entries) = lock.get(path) {
            return Ok(entries.clone());
        }
    }

    let entries = Arc::new(get_archive_image_entries(path)?);
    let mut lock = match cache.lock() {
        Ok(g) => g,
        Err(p) => p.into_inner(),
    };
    lock.put(path.to_string(), entries.clone());
    Ok(entries)
}

fn find_zip_entry_name(archive: &ZipArchive<BufReader<File>>, target: &str) -> Option<String> {
    for name in archive.file_names() {
        if name == target
            || name.replace('\\', "/") == target
            || name.replace('/', "\\") == target
        {
            return Some(name.to_string());
        }
    }
    None
}

fn read_zip_image_bytes(path: &str, entry_name: &str) -> Result<Vec<u8>> {
    let file = File::open(path)?;
    let reader = BufReader::new(file);
    let mut archive = ZipArchive::new(reader)?;

    let resolved = find_zip_entry_name(&archive, entry_name)
        .unwrap_or_else(|| entry_name.to_string());

    let mut entry = archive.by_name(&resolved)
        .with_context(|| format!("Failed to read ZIP entry: {}", entry_name))?;

    let mut buffer = Vec::new();
    entry.read_to_end(&mut buffer)
        .with_context(|| "Failed to read image data")?;
    Ok(buffer)
}

fn find_rar_member_index(archive: &RarArchive, target: &str) -> Option<usize> {
    // Tier 1: Match against sanitized path (what archive.entries() emits)
    if let Some(idx) = archive.find_member_sanitized(target) {
        return Some(idx);
    }
    // Tier 2: Match against raw file_header name
    if let Some(idx) = archive.find_member(target) {
        return Some(idx);
    }
    // Tier 3: Pre-compute normalized target once (avoids O(N) heap allocations)
    let target_norm = if target.contains('\\') {
        target.replace('\\', "/")
    } else {
        target.to_string()
    };
    for (idx, member) in archive.entries().enumerate() {
        if member.name == target {
            return Some(idx);
        }
        if member.name.contains('\\') {
            if member.name.replace('\\', "/") == target_norm {
                return Some(idx);
            }
        } else if member.name == target_norm {
            return Some(idx);
        }
    }
    None
}

fn read_rar_image_bytes(path: &str, entry_name: &str) -> Result<Vec<u8>> {
    let file = File::open(path)?;
    let mut archive = RarArchive::open(file)
        .with_context(|| format!("Failed to open RAR archive: {}", path))?;

    let index = find_rar_member_index(&archive, entry_name)
        .ok_or_else(|| anyhow!("Member '{}' not found in RAR archive", entry_name))?;

    let entry = archive.by_index(index)
        .with_context(|| format!("Failed to access member at index {} ({})", index, entry_name))?;

    let mut buffer = Vec::new();
    entry.copy_to(&mut buffer)
        .with_context(|| format!("Failed to decompress RAR entry: {}", entry_name))?;
    Ok(buffer)
}

fn read_image_bytes(path: &str, entry_name: &str) -> Result<Vec<u8>> {
    let archive_lock = get_archive_lock(path);
    let _guard = match archive_lock.lock() {
        Ok(g) => g,
        Err(p) => p.into_inner(),
    };

    let buffer = if is_rar_file(path) {
        read_rar_image_bytes(path, entry_name)
            .with_context(|| format!("Failed to read RAR entry: {}", entry_name))?
    } else {
        match read_zip_image_bytes(path, entry_name) {
            Ok(bytes) => bytes,
            Err(zip_err) => {
                read_rar_image_bytes(path, entry_name)
                    .with_context(|| format!("Failed to read entry from ZIP ({}) or RAR", zip_err))?
            }
        }
    };

    if buffer.is_empty() {
        return Err(anyhow!("Empty image data extracted for entry: {}", entry_name));
    }

    Ok(buffer)
}

fn decode_and_process_image(buffer: &[u8], max_width: Option<i32>) -> Result<CbzPageData> {
    if buffer.is_empty() {
        return Err(anyhow!("Cannot decode empty image buffer"));
    }

    let img = image::load_from_memory(buffer)
        .with_context(|| "Failed to decode image")?;

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
}

/// Struct to hold extracted page data
#[derive(Debug)]
pub struct CbzPageData {
    pub width: i32,
    pub height: i32,
    pub rgba_bytes: Vec<u8>,
}

/// Get total number of image pages in a CBZ/CBR archive
#[flutter_rust_bridge::frb]
pub fn get_cbz_page_count(path: String) -> Result<i32> {
    timed!("get_cbz_page_count", {
        let entries = get_cached_or_read_entries(&path)?;
        Ok(entries.len() as i32)
    })
}

/// Get list of page names (sorted) for chapter detection etc
#[flutter_rust_bridge::frb]
#[hotpath::measure]
pub fn get_cbz_page_names(path: String) -> Result<Vec<String>> {
    timed!("get_cbz_page_names", {
        let entries = get_cached_or_read_entries(&path)?;
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
        let buffer = read_image_bytes(&path, &entry_name)?;
        decode_and_process_image(&buffer, max_width)
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
        let entries = get_cached_or_read_entries(&path)?;

        if index < 0 || index as usize >= entries.len() {
            return Err(anyhow!("Page index {} out of range (0-{})", index, entries.len() - 1));
        }

        let entry_name = &entries[index as usize];
        let buffer = read_image_bytes(&path, entry_name)?;
        decode_and_process_image(&buffer, max_width)
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
