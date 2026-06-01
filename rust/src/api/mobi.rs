use std::fs::{self, File};
use std::io::Write;
use std::path::Path;
use anyhow::Result;
use mobi::Mobi;
use regex::Regex;

#[flutter_rust_bridge::frb]
pub struct MobiChapter {
    pub title: String,
    pub html_content: String,
}

fn prepare_mobi_content(path: &str) -> Result<(String, usize)> {
    let mobi = Mobi::from_path(path)?;
    let content = mobi.content_as_string_lossy();
    
    // Extract image records
    let images = mobi.image_records();
    let img_count = images.len();
    
    if img_count > 0 {
        let media_dir = format!("{}_media", path);
        let _ = fs::create_dir_all(&media_dir);
        
        for (i, image) in images.iter().enumerate() {
            let img_filename = format!("image_{}.png", i);
            let img_dest_path = Path::new(&media_dir).join(&img_filename);
            
            if !img_dest_path.exists() {
                if let Ok(mut outfile) = File::create(&img_dest_path) {
                    let _ = outfile.write_all(image.content);
                }
            }
        }
        
        // Single-pass replacement using regex
        let re = Regex::new(r#"recindex="([0-9]+)""#)?;
        let result = re.replace_all(&content, |caps: &regex::Captures| {
            if let Some(idx_match) = caps.get(1) {
                if let Ok(rec_idx) = idx_match.as_str().parse::<usize>() {
                    if rec_idx > 0 && rec_idx <= img_count {
                        let i = rec_idx - 1;
                        let img_filename = format!("image_{}.png", i);
                        return format!(r#"src="file://{}/{}"#, media_dir, img_filename);
                    }
                }
            }
            caps.get(0).unwrap().as_str().to_string()
        });
        
        return Ok((result.into_owned(), img_count));
    }
    
    Ok((content, 0))
}

fn split_large_html(html: &str, target_chunk_size: usize) -> Vec<String> {
    if html.len() <= target_chunk_size {
        return vec![html.to_string()];
    }

    let mut chunks = Vec::new();
    let mut current_start = 0;
    
    // Scan for closing block-level tags or lines as safe split points
    let split_point_re = Regex::new(r"(?i)</p>|</div>|</section>|</h[1-6]>|<br\s*/?>").unwrap();
    
    while current_start < html.len() {
        let remaining = &html[current_start..];
        if remaining.len() <= target_chunk_size {
            chunks.push(remaining.to_string());
            break;
        }
        
        let search_start = target_chunk_size;
        let mut split_index = None;
        
        if let Some(m) = split_point_re.find(&remaining[search_start..]) {
            split_index = Some(search_start + m.end());
        }
        
        if let Some(idx) = split_index {
            chunks.push(remaining[..idx].to_string());
            current_start += idx;
        } else {
            if let Some(space_idx) = remaining[search_start..].find(' ') {
                let idx = search_start + space_idx + 1;
                chunks.push(remaining[..idx].to_string());
                current_start += idx;
            } else {
                chunks.push(remaining.to_string());
                break;
            }
        }
    }
    
    chunks
}

fn extract_title(html: &str, default_title: &str) -> String {
    let header_re = Regex::new(r"(?i)<h[1-6][^>]*>(.*?)</h[1-6]>").unwrap();
    let strip_html_re = Regex::new(r"<[^>]*>").unwrap();
    
    if let Some(caps) = header_re.captures(html) {
        if let Some(content_match) = caps.get(1) {
            let clean = strip_html_re.replace_all(content_match.as_str(), "");
            let trimmed = clean.trim();
            if !trimmed.is_empty() {
                if trimmed.len() > 60 {
                    return format!("{}...", &trimmed[..60]);
                }
                return trimmed.to_string();
            }
        }
    }
    
    default_title.to_string()
}

#[flutter_rust_bridge::frb]
pub fn get_mobi_content(path: String) -> Result<String> {
    let (content, _) = prepare_mobi_content(&path)?;
    Ok(content)
}

#[flutter_rust_bridge::frb]
pub fn get_mobi_chapters(path: String) -> Result<Vec<MobiChapter>> {
    let (content, _) = prepare_mobi_content(&path)?;
    
    // Split by pagebreaks first
    let pagebreak_re = Regex::new(r"(?i)<mbp:pagebreak\s*/?>|<pagebreak\s*/?>|<pb\s*/?>")?;
    let raw_sections: Vec<&str> = pagebreak_re.split(&content).collect();
    
    let mut final_sections = Vec::new();
    for section in raw_sections {
        let trimmed = section.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed.len() > 50000 {
            let sub_chunks = split_large_html(trimmed, 40000);
            final_sections.extend(sub_chunks);
        } else {
            final_sections.push(trimmed.to_string());
        }
    }
    
    let mut chapters = Vec::new();
    for (i, section_content) in final_sections.into_iter().enumerate() {
        let default_title = format!("Section {}", i + 1);
        let title = extract_title(&section_content, &default_title);
        chapters.push(MobiChapter {
            title,
            html_content: section_content,
        });
    }
    
    if chapters.is_empty() {
        chapters.push(MobiChapter {
            title: "Beginning".to_string(),
            html_content: content,
        });
    }
    
    Ok(chapters)
}

#[flutter_rust_bridge::frb]
pub fn get_mobi_title(path: String) -> Result<String> {
    let mobi = Mobi::from_path(&path)?;
    Ok(mobi.title().to_string())
}

#[flutter_rust_bridge::frb]
pub fn get_mobi_author(path: String) -> Result<String> {
    let mobi = Mobi::from_path(&path)?;
    let author = mobi
        .author()
        .unwrap_or_else(|| "Unknown Author".to_string());
    Ok(author)
}

