use anyhow::Result;
use regex::Regex;
use scraper::{Html, Selector};
use std::sync::OnceLock;
use unicode_segmentation::UnicodeSegmentation;
use crate::timed;

/// A word span with character offsets
#[derive(Debug, Clone)]
pub struct WordSpan {
    pub start: u32,
    pub end: u32,
    pub text: String,
}

/// A sentence span with character offsets
#[derive(Debug, Clone)]
pub struct SentenceSpan {
    pub start: u32,
    pub end: u32,
}

/// Pre-computed text highlight data for fast TTS highlighting
#[derive(Debug, Clone)]
pub struct TextHighlightData {
    pub words: Vec<WordSpan>,
    pub sentences: Vec<SentenceSpan>,
    pub normalized_text: String,
}

// Pre-compiled regex for whitespace normalization
static WHITESPACE_REGEX: OnceLock<Regex> = OnceLock::new();

fn get_whitespace_regex() -> &'static Regex {
    WHITESPACE_REGEX.get_or_init(|| Regex::new(r"\s+").unwrap())
}

/// Normalize text for TTS (collapse whitespace, trim)
fn normalize_text(text: &str) -> String {
    let regex = get_whitespace_regex();
    regex
        .replace_all(text.trim(), " ")
        .replace('\u{00A0}', " ")
        .replace('\u{200B}', "")
        .to_string()
}

/// Pre-compute all word and sentence boundaries for TTS highlighting.
/// This eliminates per-word computation during TTS playback.
pub fn precompute_text_highlights(text: String) -> TextHighlightData {
    timed!("precompute_text_highlights", {
        let normalized = normalize_text(&text);
        
        if normalized.is_empty() {
            return TextHighlightData {
                words: Vec::new(),
                sentences: Vec::new(),
                normalized_text: normalized,
            };
        }
        
        // Extract words using Unicode word boundaries
        let mut words = Vec::new();
        let mut char_offset = 0u32;
        
        for word in normalized.split_word_bounds() {
            let word_len = word.chars().count() as u32;
            
            // Only include non-whitespace words
            if !word.trim().is_empty() {
                words.push(WordSpan {
                    start: char_offset,
                    end: char_offset + word_len,
                    text: word.to_string(),
                });
            }
            
            char_offset += word_len;
        }
        
        // Extract sentences using Unicode sentence boundaries
        let mut sentences = Vec::new();
        char_offset = 0;
        
        for sentence in normalized.split_sentence_bounds() {
            let sentence_len = sentence.chars().count() as u32;
            let trimmed = sentence.trim();
            
            if !trimmed.is_empty() {
                // Find actual start (skip leading whitespace)
                let leading_ws = sentence.len() - sentence.trim_start().len();
                let leading_chars = sentence[..leading_ws].chars().count() as u32;
                
                // Find actual end (skip trailing whitespace)
                let trailing_ws = sentence.len() - sentence.trim_end().len();
                let trailing_chars = sentence[sentence.len() - trailing_ws..].chars().count() as u32;
                
                sentences.push(SentenceSpan {
                    start: char_offset + leading_chars,
                    end: char_offset + sentence_len - trailing_chars,
                });
            }
            
            char_offset += sentence_len;
        }
        
        TextHighlightData {
            words,
            sentences,
            normalized_text: normalized,
        }
    })
}

/// Find the sentence containing a given character offset
pub fn find_sentence_for_offset(
    sentences: &[SentenceSpan],
    offset: u32,
) -> Option<SentenceSpan> {
    for sentence in sentences {
        if offset >= sentence.start && offset < sentence.end {
            return Some(sentence.clone());
        }
    }
    // If offset is past all sentences, return the last one
    sentences.last().cloned()
}

/// Insert TTS highlight tags into HTML at the specified character range.
/// Uses the scraper crate for fast HTML parsing.
pub fn insert_html_highlight(
    html: String,
    highlight_start: u32,
    highlight_end: u32,
    tag_name: String,
) -> Result<String> {
    if highlight_start >= highlight_end {
        return Ok(html);
    }
    
    let _document = Html::parse_document(&html);
    
    // Extract text content to build character mapping
    let _body_selector = Selector::parse("body").unwrap_or_else(|_| Selector::parse("*").unwrap());
    
    // For speed, we'll use a simpler approach: find text, wrap in string manipulation
    // This avoids full DOM reconstruction which scraper doesn't support well
    let text_content = extract_text_from_html(&html);
    let normalized = normalize_text(&text_content);
    
    if normalized.is_empty() {
        return Ok(html);
    }
    
    // Build mapping from normalized offset to raw offset
    let _text_regex = get_whitespace_regex();
    let _raw_text = extract_text_from_html(&html);
    
    // For now, use a simplified approach: find the text range and wrap it
    // This is a fallback until we implement full DOM manipulation
    let start = highlight_start as usize;
    let end = highlight_end.min(normalized.len() as u32) as usize;
    
    if start >= normalized.len() || end <= start {
        return Ok(html);
    }
    
    let highlight_text = &normalized[start..end];
    
    // Try to find this text in the original HTML and wrap it
    // This is an approximation - full solution would track DOM nodes
    if let Some(pos) = html.find(highlight_text) {
        let mut result = String::with_capacity(html.len() + tag_name.len() * 2 + 10);
        result.push_str(&html[..pos]);
        result.push('<');
        result.push_str(&tag_name);
        result.push('>');
        result.push_str(highlight_text);
        result.push_str("</");
        result.push_str(&tag_name);
        result.push('>');
        result.push_str(&html[pos + highlight_text.len()..]);
        return Ok(result);
    }
    
    // Fallback: return original HTML
    Ok(html)
}

/// Extract plain text from HTML (fast version using scraper)
fn extract_text_from_html(html: &str) -> String {
    let document = Html::parse_document(html);
    let selector = Selector::parse("body").ok();
    
    let mut text = String::new();
    
    if let Some(sel) = selector {
        for element in document.select(&sel) {
            text.push_str(&element.text().collect::<String>());
        }
    } else {
        // Fallback: extract all text
        for node in document.root_element().descendants() {
            if let Some(text_node) = node.value().as_text() {
                text.push_str(text_node);
            }
        }
    }
    
    text
}

/// Test function for TTS text module
pub fn test_tts_text_module() -> String {
    let test_text = "Hello world. This is a test.";
    let data = precompute_text_highlights(test_text.to_string());
    format!(
        "Words: {}, Sentences: {}, Normalized: '{}'",
        data.words.len(),
        data.sentences.len(),
        data.normalized_text
    )
}
