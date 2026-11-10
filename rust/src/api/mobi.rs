use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use anyhow::{Context, Result};
use regex::Regex;

#[flutter_rust_bridge::frb]
pub struct MobiChapter {
    pub title: String,
    pub html_content: String,
}

// Low-level PDB parser helper for zero-panic record access
struct PdbReader<'a> {
    data: &'a [u8],
    num_records: usize,
}

impl<'a> PdbReader<'a> {
    fn new(data: &'a [u8]) -> Option<Self> {
        if data.len() < 78 {
            return None;
        }
        let num_records = u16::from_be_bytes([data[76], data[77]]) as usize;
        if num_records == 0 || data.len() < 78 + num_records * 8 {
            return None;
        }
        Some(Self { data, num_records })
    }

    fn record_count(&self) -> usize {
        self.num_records
    }

    fn get_record(&self, i: usize) -> Option<&'a [u8]> {
        if i >= self.num_records {
            return None;
        }
        let entry_offset = 78 + i * 8;
        let start = u32::from_be_bytes(self.data.get(entry_offset..entry_offset + 4)?.try_into().ok()?) as usize;
        let end = if i + 1 < self.num_records {
            let next_entry = 78 + (i + 1) * 8;
            u32::from_be_bytes(self.data.get(next_entry..next_entry + 4)?.try_into().ok()?) as usize
        } else {
            self.data.len()
        };
        if start <= end && end <= self.data.len() {
            Some(&self.data[start..end])
        } else {
            None
        }
    }
}

// Guardrail 1: Strip PalmDOC extra_data_flags before decompressing each record
fn trim_trailing_data(mut data: &[u8], extra_flags: u16) -> &[u8] {
    for bit in (1..16).rev() {
        if (extra_flags & (1 << bit)) != 0 && !data.is_empty() {
            let mut size = 0usize;
            let mut shift = 0;
            for &b in data.iter().rev() {
                size |= ((b & 0x7F) as usize) << shift;
                shift += 7;
                if (b & 0x80) != 0 || shift > 28 {
                    break;
                }
            }
            if size <= data.len() {
                data = &data[..data.len() - size];
            }
        }
    }
    if (extra_flags & 1) != 0 && !data.is_empty() {
        let size = ((data[data.len() - 1] & 0x03) as usize) + 1;
        if size <= data.len() {
            data = &data[..data.len() - size];
        }
    }
    data
}

// PalmDOC LZ77 decompressor for individual records
fn decompress_palmdoc_record(compressed: &[u8]) -> Vec<u8> {
    let mut out = Vec::with_capacity(4096);
    let mut i = 0;
    while i < compressed.len() {
        let b = compressed[i];
        i += 1;
        if b == 0x00 {
            out.push(0x00);
        } else if b <= 0x08 {
            let count = b as usize;
            let end = (i + count).min(compressed.len());
            out.extend_from_slice(&compressed[i..end]);
            i = end;
        } else if b <= 0x7F {
            out.push(b);
        } else if b >= 0xC0 {
            out.push(b' ');
            out.push(b ^ 0x80);
        } else {
            // 0x80..=0xBF: distance and length
            if i >= compressed.len() {
                break;
            }
            let b2 = compressed[i];
            i += 1;
            let distance = (((b & 0x3F) as usize) << 5) | ((b2 as usize) >> 3);
            let length = ((b2 & 0x07) as usize) + 3;
            if distance == 0 || distance > out.len() {
                continue;
            }
            let src_start = out.len() - distance;
            for k in 0..length {
                let byte = out[src_start + k];
                out.push(byte);
            }
        }
    }
    out
}

// Guardrail 4: Snap raw UTF-8 slice boundaries so slicing never breaks a multibyte sequence
fn snap_utf8_boundary(bytes: &[u8], mut idx: usize) -> usize {
    idx = idx.min(bytes.len());
    while idx > 0 && idx < bytes.len() && (bytes[idx] & 0b1100_0000) == 0b1000_0000 {
        idx -= 1;
    }
    idx
}

// Decodes MOBI text according to the header encoding
fn decode_mobi_text(bytes: &[u8], encoding: u32) -> String {
    if encoding == 1252 {
        // Windows-1252 single-byte decoder
        let mut s = String::with_capacity(bytes.len());
        for &b in bytes {
            match b {
                0x00..=0x7F => s.push(b as char),
                0x80 => s.push('€'),
                0x82 => s.push('‚'),
                0x83 => s.push('ƒ'),
                0x84 => s.push('„'),
                0x85 => s.push('…'),
                0x86 => s.push('†'),
                0x87 => s.push('‡'),
                0x88 => s.push('ˆ'),
                0x89 => s.push('‰'),
                0x8A => s.push('Š'),
                0x8B => s.push('‹'),
                0x8C => s.push('Œ'),
                0x8E => s.push('Ž'),
                0x91 => s.push('‘'),
                0x92 => s.push('’'),
                0x93 => s.push('“'),
                0x94 => s.push('”'),
                0x95 => s.push('•'),
                0x96 => s.push('–'),
                0x97 => s.push('—'),
                0x98 => s.push('˜'),
                0x99 => s.push('™'),
                0x9A => s.push('š'),
                0x9B => s.push('›'),
                0x9C => s.push('œ'),
                0x9E => s.push('ž'),
                0x9F => s.push('Ÿ'),
                0xA0..=0xFF => s.push(b as char),
                _ => s.push('?'),
            }
        }
        s
    } else {
        String::from_utf8_lossy(bytes).into_owned()
    }
}

// App-private media directory resolver to avoid Android Scoped Storage violations
fn get_app_media_dir(book_path: &str) -> PathBuf {
    let hash = format!(
        "{:x}",
        book_path
            .bytes()
            .fold(5381u64, |h, b| (h << 5).wrapping_add(h).wrapping_add(b as u64))
    );

    // On Android, resolve /data/data/<pkg>/cache/mobi_media
    if let Ok(cmdline) = fs::read_to_string("/proc/self/cmdline") {
        let pkg = cmdline.trim_matches('\0').trim();
        if !pkg.is_empty() && pkg.contains('.') {
            let android_cache = PathBuf::from(format!("/data/data/{}/cache/mobi_media/{}", pkg, hash));
            if fs::create_dir_all(&android_cache).is_ok() {
                return android_cache;
            }
        }
    }

    // Fallback on Desktop / other OS
    let temp = std::env::temp_dir().join("ferrous_mobi_media").join(&hash);
    let _ = fs::create_dir_all(&temp);
    temp
}

// Helper to parse EXTH records from Record 0
fn get_exth_string(rec0: &[u8], target_type: u32) -> Option<String> {
    if rec0.len() < 132 || rec0.get(16..20) != Some(b"MOBI") {
        return None;
    }
    let mobi_header_len = u32::from_be_bytes(rec0.get(20..24)?.try_into().ok()?) as usize;
    let exth_flags = u32::from_be_bytes(rec0.get(128..132)?.try_into().ok()?);

    if (exth_flags & 0x40) == 0 || rec0.len() < 16 + mobi_header_len + 12 {
        return None;
    }

    let exth_start = 16 + mobi_header_len;
    if rec0.get(exth_start..exth_start + 4) != Some(b"EXTH") {
        return None;
    }

    let count = u32::from_be_bytes(rec0.get(exth_start + 8..exth_start + 12)?.try_into().ok()?) as usize;
    let mut curr = exth_start + 12;
    for _ in 0..count {
        if curr + 8 > rec0.len() {
            break;
        }
        let rec_type = u32::from_be_bytes(rec0.get(curr..curr + 4)?.try_into().ok()?);
        let rec_len = u32::from_be_bytes(rec0.get(curr + 4..curr + 8)?.try_into().ok()?) as usize;
        if rec_len < 8 || curr + rec_len > rec0.len() {
            break;
        }
        if rec_type == target_type {
            let val_bytes = &rec0[curr + 8..curr + rec_len];
            let s = String::from_utf8_lossy(val_bytes).trim().to_string();
            if !s.is_empty() {
                return Some(s);
            }
        }
        curr += rec_len;
    }
    None
}

// Decompresses all text records and returns (raw_bytes, encoding, first_image_index)
fn decompress_mobi_book(data: &[u8]) -> Result<(Vec<u8>, u32, usize)> {
    let pdb = PdbReader::new(data).context("Invalid MOBI/PDB file format")?;
    let rec0 = pdb.get_record(0).context("Missing Record 0 in MOBI")?;

    if rec0.len() < 132 || rec0.get(16..20) != Some(b"MOBI") {
        return Err(anyhow::anyhow!("Invalid MOBI header in record 0"));
    }

    let compression = u16::from_be_bytes([rec0[0], rec0[1]]);
    let record_count = u16::from_be_bytes([rec0[8], rec0[9]]) as usize;
    let encoding = u32::from_be_bytes(rec0.get(28..32).context("Missing encoding")?.try_into()?);
    let first_image_index = u32::from_be_bytes(rec0.get(108..112).context("Missing first image index")?.try_into()?) as usize;

    let extra_flags = if rec0.len() >= 244 {
        u16::from_be_bytes([rec0[242], rec0[243]])
    } else {
        0
    };

    let mut all_bytes = Vec::new();
    for r in 1..=record_count {
        if let Some(rec) = pdb.get_record(r) {
            let trimmed = trim_trailing_data(rec, extra_flags);
            if compression == 2 {
                let decompressed = decompress_palmdoc_record(trimmed);
                all_bytes.extend(decompressed);
            } else if compression == 1 {
                all_bytes.extend_from_slice(trimmed);
            } else if compression == 17480 {
                return Err(anyhow::anyhow!("Huff/CDIC compression (0x4448) not supported"));
            } else {
                return Err(anyhow::anyhow!("Unsupported MOBI compression type: {}", compression));
            }
        }
    }

    Ok((all_bytes, encoding, first_image_index))
}

#[flutter_rust_bridge::frb]
pub fn get_mobi_content(path: String) -> Result<String> {
    let data = fs::read(&path).context("Failed to read MOBI file")?;
    let (raw_bytes, encoding, _) = decompress_mobi_book(&data)?;
    Ok(decode_mobi_text(&raw_bytes, encoding))
}

#[flutter_rust_bridge::frb]
pub fn get_mobi_title(path: String) -> Result<String> {
    let data = fs::read(&path).context("Failed to read MOBI file")?;
    let pdb = PdbReader::new(&data).context("Invalid MOBI file")?;
    if let Some(rec0) = pdb.get_record(0) {
        // EXTH 503 = Updated Title
        if let Some(title) = get_exth_string(rec0, 503) {
            return Ok(title);
        }
        // PalmDOC title offset
        if rec0.len() >= 92 {
            let title_offset = u32::from_be_bytes(rec0[84..88].try_into().unwrap_or([0; 4])) as usize;
            let title_len = u32::from_be_bytes(rec0[88..92].try_into().unwrap_or([0; 4])) as usize;
            if title_offset > 0 && title_offset + title_len <= rec0.len() {
                let s = String::from_utf8_lossy(&rec0[title_offset..title_offset + title_len]).trim().to_string();
                if !s.is_empty() {
                    return Ok(s);
                }
            }
        }
    }
    // Fallback to filename stem
    let stem = Path::new(&path)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or("Unknown Title")
        .to_string();
    Ok(stem)
}

#[flutter_rust_bridge::frb]
pub fn get_mobi_author(path: String) -> Result<String> {
    let data = fs::read(&path).context("Failed to read MOBI file")?;
    let pdb = PdbReader::new(&data).context("Invalid MOBI file")?;
    if let Some(rec0) = pdb.get_record(0) {
        // EXTH 100 = Author
        if let Some(author) = get_exth_string(rec0, 100) {
            return Ok(author);
        }
    }
    Ok("Unknown Author".to_string())
}

#[flutter_rust_bridge::frb]
pub fn get_mobi_chapters(path: String) -> Result<Vec<MobiChapter>> {
    let data = fs::read(&path).context("Failed to read MOBI file")?;
    let pdb = PdbReader::new(&data).context("Invalid MOBI file")?;
    let (raw_bytes, encoding, first_image_index) = decompress_mobi_book(&data)?;

    if raw_bytes.is_empty() {
        return Ok(vec![MobiChapter {
            title: "Empty Book".to_string(),
            html_content: String::new(),
        }]);
    }

    // Guardrail 2: Scope <a filepos=...> extraction to the TOC region
    let full_text = decode_mobi_text(&raw_bytes, encoding);

    // Look for <reference type="toc" filepos=XXXXX> in <guide> block
    let guide_toc_re = Regex::new(
        r#"(?i)<reference\b[^>]*?(?:\btype\s*=\s*["']?toc["']?[^>]*?\bfilepos\s*=\s*["']?([0-9]+)["']?|\bfilepos\s*=\s*["']?([0-9]+)["']?[^>]*?\btype\s*=\s*["']?toc["']?)"#,
    )?;

    let mut toc_filepos: Option<usize> = None;
    if let Some(caps) = guide_toc_re.captures(&full_text) {
        let val_str = caps.get(1).or_else(|| caps.get(2)).map(|m| m.as_str());
        if let Some(s) = val_str {
            if let Ok(pos) = s.parse::<usize>() {
                toc_filepos = Some(pos);
            }
        }
    }

    // If not in <guide>, search for "Table of Contents" or "Contents" anchor
    if toc_filepos.is_none() {
        let toc_text_re = Regex::new(
            r#"(?i)<(?:a|p|div|h[1-6])[^>]*>(?:table\s+of\s+contents|contents)</(?:a|p|div|h[1-6])>"#,
        )?;
        if let Some(m) = toc_text_re.find(&full_text) {
            toc_filepos = Some(m.start());
        }
    }

    // Extract chapter filepos targets
    let link_re = Regex::new(r#"(?is)<a\b[^>]*?\bfilepos\s*=\s*["']?([0-9]+)["']?[^>]*>(.*?)</a>"#)?;
    let strip_tags_re = Regex::new(r#"<[^>]*>"#)?;

    let mut chapter_targets: Vec<(usize, String)> = Vec::new();

    if let Some(t_pos) = toc_filepos {
        // Scope link extraction to the TOC region (from toc_filepos up to ~25KB or next mbp:pagebreak)
        let toc_slice = if t_pos < full_text.len() {
            let max_len = 25000.min(full_text.len() - t_pos);
            &full_text[t_pos..t_pos + max_len]
        } else {
            ""
        };

        for caps in link_re.captures_iter(toc_slice) {
            if let (Some(pos_m), Some(title_m)) = (caps.get(1), caps.get(2)) {
                if let Ok(pos) = pos_m.as_str().parse::<usize>() {
                    let clean = strip_tags_re.replace_all(title_m.as_str(), "");
                    let title = clean.trim().to_string();
                    // Filter out footnote-like anchors (numbers, asterisks, short strings)
                    if title.len() >= 2 && !title.chars().all(|c| c.is_ascii_digit() || c == '[' || c == ']' || c == '*') {
                        chapter_targets.push((pos, title));
                    }
                }
            }
        }
    }

    // If TOC link extraction found fewer than 2 chapters, scan full text for chapter-like filepos
    if chapter_targets.len() < 2 {
        for caps in link_re.captures_iter(&full_text) {
            if let (Some(pos_m), Some(title_m)) = (caps.get(1), caps.get(2)) {
                if let Ok(pos) = pos_m.as_str().parse::<usize>() {
                    let clean = strip_tags_re.replace_all(title_m.as_str(), "");
                    let title = clean.trim().to_string();
                    if title.len() >= 3 && (title.to_lowercase().contains("chapter") || title.to_lowercase().contains("book") || title.to_lowercase().contains("part")) {
                        chapter_targets.push((pos, title));
                    }
                }
            }
        }
    }

    // Extract embedded images to app-private cache directory
    let media_dir = get_app_media_dir(&path);
    let media_dir_str = media_dir.to_string_lossy().replace('\\', "/");

    let total_records = pdb.record_count();
    if first_image_index < total_records {
        for rec_idx in first_image_index..total_records {
            if let Some(rec_data) = pdb.get_record(rec_idx) {
                if rec_data.len() >= 4 {
                    let (ext, is_image) = if rec_data.starts_with(&[0xFF, 0xD8, 0xFF]) {
                        ("jpg", true)
                    } else if rec_data.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
                        ("png", true)
                    } else if rec_data.starts_with(b"GIF8") {
                        ("gif", true)
                    } else {
                        ("", false)
                    };

                    if is_image {
                        let one_based_recindex = rec_idx - first_image_index + 1;
                        let img_filename = format!("image_{}.{}", one_based_recindex, ext);
                        let img_path = media_dir.join(&img_filename);
                        if !img_path.exists() {
                            if let Ok(mut out) = File::create(&img_path) {
                                let _ = out.write_all(rec_data);
                            }
                        }
                    }
                }
            }
        }
    }

    // Regex to normalize recindex="XXX" -> src="file://media_dir/image_X.ext" with closing quote
    let img_replace_re = Regex::new(r#"(?i)\brecindex\s*=\s*["']?([0-9]+)["']?"#)?;

    let normalize_images = |html: &str| -> String {
        img_replace_re
            .replace_all(html, |caps: &regex::Captures| {
                if let Some(idx_match) = caps.get(1) {
                    if let Ok(rec_idx) = idx_match.as_str().parse::<usize>() {
                        // Check if file exists as .jpg or .png
                        let jpg_file = media_dir.join(format!("image_{}.jpg", rec_idx));
                        let ext = if jpg_file.exists() { "jpg" } else { "png" };
                        let img_filename = format!("image_{}.{}", rec_idx, ext);
                        return format!(r#"src="file://{}/{}""#, media_dir_str, img_filename);
                    }
                }
                caps.get(0).unwrap().as_str().to_string()
            })
            .into_owned()
    };

    let mut chapters = Vec::new();

    if chapter_targets.len() >= 2 {
        // Sort and deduplicate chapter targets
        chapter_targets.sort_by_key(|&(pos, _)| pos);
        let mut deduped_targets: Vec<(usize, String)> = Vec::new();
        for (pos, title) in chapter_targets {
            if let Some(last) = deduped_targets.last() {
                if pos <= last.0 || pos.saturating_sub(last.0) < 64 {
                    continue;
                }
            }
            deduped_targets.push((pos, title));
        }

        // Include leading slice (0..first_pos) as Front Matter / Title Page
        let mut slice_boundaries = Vec::new();
        if let Some(&(first_pos, _)) = deduped_targets.first() {
            if first_pos > 200 {
                slice_boundaries.push((0, "Title Page".to_string()));
            }
        }
        slice_boundaries.extend(deduped_targets);

        // Slice raw uncompressed bytes at boundaries
        for i in 0..slice_boundaries.len() {
            let (start_byte, ref title) = slice_boundaries[i];
            let end_byte = if i + 1 < slice_boundaries.len() {
                slice_boundaries[i + 1].0
            } else {
                raw_bytes.len()
            };

            let safe_start = snap_utf8_boundary(&raw_bytes, start_byte);
            let safe_end = snap_utf8_boundary(&raw_bytes, end_byte.min(raw_bytes.len()));

            if safe_start < safe_end {
                let slice = &raw_bytes[safe_start..safe_end];
                let decoded = decode_mobi_text(slice, encoding);
                let trimmed = decoded.trim();
                if !trimmed.is_empty() {
                    let normalized_html = normalize_images(trimmed);
                    chapters.push(MobiChapter {
                        title: title.clone(),
                        html_content: normalized_html,
                    });
                }
            }
        }
    }

    // Fallback: if no valid TOC targets, split by <mbp:pagebreak>
    if chapters.is_empty() {
        let pagebreak_re = Regex::new(r"(?i)<mbp:pagebreak\s*/?>|<pagebreak\s*/?>|<pb\s*/?>")?;
        let raw_sections: Vec<&str> = pagebreak_re.split(&full_text).collect();

        for (i, section) in raw_sections.into_iter().enumerate() {
            let trimmed = section.trim();
            if trimmed.is_empty() {
                continue;
            }
            let title = format!("Section {}", i + 1);
            let normalized = normalize_images(trimmed);
            chapters.push(MobiChapter {
                title,
                html_content: normalized,
            });
        }
    }

    if chapters.is_empty() {
        chapters.push(MobiChapter {
            title: "Beginning".to_string(),
            html_content: normalize_images(&full_text),
        });
    }

    Ok(chapters)
}
