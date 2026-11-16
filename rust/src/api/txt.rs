use anyhow::{Context, Result};
use std::sync::LazyLock;
use regex::Regex;
use serde::{Deserialize, Serialize};

#[derive(Serialize, Deserialize, Debug, Clone)]
pub struct TxtChapter {
    pub title: String,
    pub html_content: String,
    pub raw_char_length: usize,
}

static WESTERN_CHAPTER_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"(?i)^\s*(?:chapter|book|part|section|volume|act|canto)\s+([0-9]+|[a-z]+)\b\.?[\s:.\-—]*(.*)$").unwrap()
});

static ROMAN_NUMERAL_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^(?i:m{0,4}(?:cm|cd|d?c{0,3})(?:xc|xl|l?x{0,3})(?:ix|iv|v?i{1,3}))$").unwrap()
});

static CJK_CHAPTER_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^\s*(?:第\s*[0-9一二三四五六七八九十百千万零]+\s*[章回节卷集部篇幕]|楔子|序章|序言|前言|尾声|后记|番外\s*\d*)\s*(.*)$").unwrap()
});

static MD_HEADING_RE: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(r"^\s*#{1,3}\s+(.+)$").unwrap()
});

const NUMBER_WORDS: &[&str] = &[
    "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
    "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen",
    "eighteen", "nineteen", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
    "eighty", "ninety", "hundred", "first", "second", "third", "fourth", "fifth",
    "sixth", "seventh", "eighth", "ninth", "tenth",
];

fn is_valid_chapter_identifier(id: &str) -> bool {
    let lower = id.to_lowercase();
    lower.chars().all(|c| c.is_ascii_digit())
        || NUMBER_WORDS.contains(&lower.as_str())
        || ROMAN_NUMERAL_RE.is_match(&lower)
}

fn ends_with_sentence_punct(text: &str) -> bool {
    let trimmed = text.trim_end();
    trimmed.ends_with('.')
        || trimmed.ends_with('?')
        || trimmed.ends_with('!')
        || trimmed.ends_with(',')
        || trimmed.ends_with(';')
        || trimmed.ends_with(':')
        || trimmed.ends_with('"')
}

fn match_chapter_heading(trimmed: &str, preceded_by_empty: bool) -> Option<String> {
    if !preceded_by_empty || trimmed.len() >= 80 {
        return None;
    }

    if let Some(caps) = MD_HEADING_RE.captures(trimmed) {
        let heading_text = caps.get(1).map_or("", |m| m.as_str()).trim();
        if !heading_text.is_empty() {
            return Some(heading_text.to_string());
        }
    }

    if CJK_CHAPTER_RE.is_match(trimmed) {
        return Some(trimmed.to_string());
    }

    if let Some(caps) = WESTERN_CHAPTER_RE.captures(trimmed) {
        let id_part = caps.get(1).map_or("", |m| m.as_str());
        let subtitle = caps.get(2).map_or("", |m| m.as_str()).trim();

        if is_valid_chapter_identifier(id_part)
            && (subtitle.is_empty() || !ends_with_sentence_punct(subtitle))
        {
            return Some(trimmed.to_string());
        }
    }

    None
}

fn decode_txt_bytes(raw_bytes: &[u8]) -> String {
    if raw_bytes.is_empty() {
        return String::new();
    }

    // 1. Check for explicit UTF-8 BOM
    if raw_bytes.starts_with(&[0xEF, 0xBB, 0xBF]) {
        return String::from_utf8_lossy(&raw_bytes[3..]).into_owned();
    }

    // 2. Check for UTF-16LE BOM
    if raw_bytes.starts_with(&[0xFF, 0xFE]) {
        let u16_slice: Vec<u16> = raw_bytes[2..]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|c| u16::from_le_bytes(*c))
            .collect();
        return String::from_utf16_lossy(&u16_slice);
    }

    // 3. Check for UTF-16BE BOM
    if raw_bytes.starts_with(&[0xFE, 0xFF]) {
        let u16_slice: Vec<u16> = raw_bytes[2..]
            .as_chunks::<2>()
            .0
            .iter()
            .map(|c| u16::from_be_bytes(*c))
            .collect();
        return String::from_utf16_lossy(&u16_slice);
    }

    // 4. Sample-bounded charset detection via chardetng (capped at 64 KB)
    let sample_len = raw_bytes.len().min(65_536);
    let sample = &raw_bytes[..sample_len];

    let mut detector = chardetng::EncodingDetector::new();
    detector.feed(sample, raw_bytes.len() <= 65_536);
    let encoding = detector.guess(None, true);

    let (decoded, _, _) = encoding.decode(raw_bytes);
    decoded.into_owned()
}

fn base64_encode(data: &[u8]) -> String {
    const CHARSET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut result = String::with_capacity(data.len().div_ceil(3) * 4);
    for chunk in data.chunks(3) {
        let b = chunk.len();
        let val = match b {
            3 => ((chunk[0] as u32) << 16) | ((chunk[1] as u32) << 8) | (chunk[2] as u32),
            2 => ((chunk[0] as u32) << 16) | ((chunk[1] as u32) << 8),
            1 => (chunk[0] as u32) << 16,
            _ => unreachable!(),
        };
        result.push(CHARSET[((val >> 18) & 63) as usize] as char);
        result.push(CHARSET[((val >> 12) & 63) as usize] as char);
        if b > 1 {
            result.push(CHARSET[((val >> 6) & 63) as usize] as char);
        } else {
            result.push('=');
        }
        if b > 2 {
            result.push(CHARSET[(val & 63) as usize] as char);
        } else {
            result.push('=');
        }
    }
    result
}

fn escape_html(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#x27;")
}

const SOFT_BREAK_BYTES: usize = 45 * 1024; // 45 KB soft limit (splits on blank line)
const HARD_BREAK_BYTES: usize = 60 * 1024; // 60 KB hard limit (splits on newline or char boundary)

fn flush_active_chapter(
    chapters: &mut Vec<TxtChapter>,
    title: &str,
    html: &mut String,
    raw_chars: &mut usize,
    bytes: &mut usize,
) {
    if *raw_chars > 0 || !html.is_empty() {
        html.push_str("</div>");
        chapters.push(TxtChapter {
            title: title.to_string(),
            html_content: std::mem::take(html),
            raw_char_length: *raw_chars,
        });
        *raw_chars = 0;
        *bytes = 0;
        html.push_str("<div class='txt-content'>");
    }
}

#[flutter_rust_bridge::frb]
pub fn read_txt(path: String) -> Result<Vec<TxtChapter>> {
    let raw_bytes = std::fs::read(&path).context("Failed to read TXT file")?;
    let full_text = decode_txt_bytes(&raw_bytes);

    let mut chapters: Vec<TxtChapter> = Vec::new();
    let mut current_title = "Beginning".to_string();
    let mut current_html = String::from("<div class='txt-content'>");
    let mut current_raw_chars: usize = 0;
    let mut current_bytes: usize = 0;

    let mut in_mermaid = false;
    let mut mermaid_content = String::new();
    let mut preceded_by_empty = true;

    for line in full_text.lines() {
        let trimmed = line.trim();

        // 1. Handle Mermaid flowchart parsing
        if trimmed.starts_with("```mermaid") {
            in_mermaid = true;
            mermaid_content.clear();
            preceded_by_empty = false;
            continue;
        }

        if in_mermaid {
            if trimmed.starts_with("```") {
                in_mermaid = false;
                let encoded = base64_encode(mermaid_content.trim().as_bytes());
                current_html.push_str(&format!(
                    "<img src=\"https://mermaid.ink/svg/{}\" style=\"max-width: 100%; display: block; margin: 20px auto;\" />",
                    encoded
                ));
                preceded_by_empty = false;
                continue;
            }
            mermaid_content.push_str(line);
            mermaid_content.push('\n');
            current_raw_chars += line.chars().count() + 1;
            current_bytes += line.len() + 1;
            continue;
        }

        // 2. Chapter heading check (only outside fences)
        if let Some(heading_title) = match_chapter_heading(trimmed, preceded_by_empty) {
            flush_active_chapter(
                &mut chapters,
                &current_title,
                &mut current_html,
                &mut current_raw_chars,
                &mut current_bytes,
            );
            current_html.push_str(&format!(
                "<h3 class='chapter-heading' style='margin-top: 24px; margin-bottom: 16px;'>{}</h3>",
                escape_html(&heading_title)
            ));
            current_title = heading_title;
            current_raw_chars += line.chars().count() + 1;
            current_bytes += line.len() + 1;
            preceded_by_empty = false;
            continue;
        }

        // 3. Two-Tier Virtual Slicing
        // Soft Break: when chapter >= 45 KB and line is empty
        if current_bytes >= SOFT_BREAK_BYTES && trimmed.is_empty() {
            flush_active_chapter(
                &mut chapters,
                &current_title,
                &mut current_html,
                &mut current_raw_chars,
                &mut current_bytes,
            );
            current_title = format!("Section {}", chapters.len() + 1);
            preceded_by_empty = true;
            continue;
        }

        // Hard Break: when chapter >= 60 KB on standard newline
        if current_bytes >= HARD_BREAK_BYTES {
            flush_active_chapter(
                &mut chapters,
                &current_title,
                &mut current_html,
                &mut current_raw_chars,
                &mut current_bytes,
            );
            current_title = format!("Section {}", chapters.len() + 1);
        }

        // 4. Render empty lines
        if trimmed.is_empty() {
            current_html.push_str("<div style='height: 12px;'></div>");
            current_raw_chars += 1;
            current_bytes += 1;
            preceded_by_empty = true;
            continue;
        }

        preceded_by_empty = false;

        // 5. Count leading spaces for indentation
        let leading_spaces = line.len() - line.trim_start().len();
        let indent_px = (leading_spaces * 8).min(160);

        // 6. Check for horizontal separators
        if trimmed.len() >= 3
            && (trimmed.chars().all(|c| c == '-')
                || trimmed.chars().all(|c| c == '_')
                || trimmed.chars().all(|c| c == '='))
        {
            current_html.push_str("<hr />");
            current_raw_chars += line.chars().count() + 1;
            current_bytes += line.len() + 1;
            continue;
        }

        // 7. Check for bullet list items
        if trimmed.starts_with('•')
            || trimmed.starts_with('*')
            || (trimmed.starts_with('-') && !trimmed.starts_with("--"))
        {
            let content_start = trimmed.char_indices().nth(1).map_or(0, |(i, _)| i);
            let content = trimmed[content_start..].trim();
            current_html.push_str(&format!(
                "<p class='list-item' style='margin-left: {}px; text-indent: -16px; padding-left: 16px;'>• &nbsp;{}</p>",
                indent_px + 16,
                escape_html(content)
            ));
            current_raw_chars += line.chars().count() + 1;
            current_bytes += line.len() + 1;
            continue;
        }

        // 8. Check for checkbox choice items
        if trimmed.starts_with("()") {
            let content = trimmed[2..].trim();
            current_html.push_str(&format!(
                "<p class='choice-item' style='margin-left: {}px;'>() &nbsp;{}</p>",
                indent_px + 24,
                escape_html(content)
            ));
            current_raw_chars += line.chars().count() + 1;
            current_bytes += line.len() + 1;
            continue;
        }

        // 9. Check for numbered lists
        let is_numbered = trimmed
            .chars()
            .next()
            .is_some_and(|c| c.is_ascii_digit())
            && trimmed.contains('.');
        if is_numbered {
            if let Some(dot_idx) = trimmed.find('.') {
                let prefix = &trimmed[..=dot_idx];
                let content = trimmed[dot_idx + 1..].trim();
                current_html.push_str(&format!(
                    "<p class='list-item' style='margin-left: {}px; text-indent: -20px; padding-left: 20px;'>{} &nbsp;{}</p>",
                    indent_px + 16,
                    prefix,
                    escape_html(content)
                ));
                current_raw_chars += line.chars().count() + 1;
                current_bytes += line.len() + 1;
                continue;
            }
        }

        // 10. Check for header blocks
        let is_heading = trimmed.len() < 80 && trimmed.ends_with(':');
        if is_heading {
            current_html.push_str(&format!(
                "<h4 style='margin-top: 16px; margin-bottom: 8px; margin-left: {}px;'>{}</h4>",
                indent_px,
                escape_html(trimmed)
            ));
            current_raw_chars += line.chars().count() + 1;
            current_bytes += line.len() + 1;
            continue;
        }

        // 11. Default text paragraph
        if indent_px > 0 {
            current_html.push_str(&format!(
                "<p style='margin-left: {}px;'>{}</p>",
                indent_px,
                escape_html(trimmed)
            ));
        } else {
            current_html.push_str(&format!("<p>{}</p>", escape_html(trimmed)));
        }
        current_raw_chars += line.chars().count() + 1;
        current_bytes += line.len() + 1;
    }

    // Handle unclosed mermaid fence at EOF
    if in_mermaid && !mermaid_content.is_empty() {
        let encoded = base64_encode(mermaid_content.trim().as_bytes());
        current_html.push_str(&format!(
            "<img src=\"https://mermaid.ink/svg/{}\" style=\"max-width: 100%; display: block; margin: 20px auto;\" />",
            encoded
        ));
    }

    // Flush final chapter
    flush_active_chapter(
        &mut chapters,
        &current_title,
        &mut current_html,
        &mut current_raw_chars,
        &mut current_bytes,
    );

    if chapters.is_empty() {
        chapters.push(TxtChapter {
            title: "Beginning".to_string(),
            html_content: "<div class='txt-content'></div>".to_string(),
            raw_char_length: 0,
        });
    }

    Ok(chapters)
}

#[flutter_rust_bridge::frb]
pub fn read_txt_to_html(path: String) -> Result<String> {
    let chapters = read_txt(path)?;
    Ok(serde_json::to_string(&chapters)?)
}
