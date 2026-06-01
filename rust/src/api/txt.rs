use anyhow::{Context, Result};
use std::fs::File;
use std::io::{BufRead, BufReader};

fn base64_encode(data: &[u8]) -> String {
    const CHARSET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut result = String::with_capacity((data.len() + 2) / 3 * 4);
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

#[flutter_rust_bridge::frb]
pub fn read_txt_to_html(path: String) -> Result<String> {
    let file = File::open(&path).context("Failed to open TXT file")?;
    let reader = BufReader::new(file);
    let mut html_output = String::new();
    html_output.push_str("<div class='txt-content'>");

    let mut in_mermaid = false;
    let mut mermaid_content = String::new();

    for line in reader.lines() {
        let line = line.context("Failed to read line")?;
        let trimmed = line.trim();

        // Handle Mermaid flowchart parsing
        if trimmed.starts_with("```mermaid") {
            in_mermaid = true;
            mermaid_content.clear();
            continue;
        }

        if in_mermaid {
            if trimmed.starts_with("```") {
                in_mermaid = false;
                let encoded = base64_encode(mermaid_content.trim().as_bytes());
                html_output.push_str(&format!(
                    "<img src=\"https://mermaid.ink/svg/{}\" style=\"max-width: 100%; display: block; margin: 20px auto;\" />",
                    encoded
                ));
                continue;
            }
            mermaid_content.push_str(&line);
            mermaid_content.push('\n');
            continue;
        }

        // Render empty lines as comfortable vertical spacers
        if trimmed.is_empty() {
            html_output.push_str("<div style='height: 12px;'></div>");
            continue;
        }

        // Count leading spaces to determine indent level
        let leading_spaces = line.len() - line.trim_start().len();
        let indent_px = (leading_spaces * 8).min(160); // 8px per space, max 160px

        // Check for horizontal separators (dashes/equals)
        if trimmed.len() >= 3 && (trimmed.chars().all(|c| c == '-') || trimmed.chars().all(|c| c == '_') || trimmed.chars().all(|c| c == '=')) {
            html_output.push_str("<hr />");
            continue;
        }

        // Check for bullet list items
        if trimmed.starts_with('•') || trimmed.starts_with('*') || (trimmed.starts_with('-') && !trimmed.starts_with("--")) {
            let content_start = trimmed.char_indices().nth(1).map(|(i, _)| i).unwrap_or(0);
            let content = trimmed[content_start..].trim();
            html_output.push_str(&format!(
                "<p class='list-item' style='margin-left: {}px; text-indent: -16px; padding-left: 16px;'>• &nbsp;{}</p>",
                indent_px + 16,
                escape_html(content)
            ));
            continue;
        }

        // Check for checkbox choice items
        if trimmed.starts_with("()") {
            let content = trimmed[2..].trim();
            html_output.push_str(&format!(
                "<p class='choice-item' style='margin-left: {}px;'>() &nbsp;{}</p>",
                indent_px + 24,
                escape_html(content)
            ));
            continue;
        }

        // Check for numbered lists
        let is_numbered = trimmed.chars().next().map_or(false, |c| c.is_ascii_digit()) && trimmed.contains('.');
        if is_numbered {
            if let Some(dot_idx) = trimmed.find('.') {
                let prefix = &trimmed[..=dot_idx];
                let content = &trimmed[dot_idx + 1..].trim();
                html_output.push_str(&format!(
                    "<p class='list-item' style='margin-left: {}px; text-indent: -20px; padding-left: 20px;'>{} &nbsp;{}</p>",
                    indent_px + 16,
                    prefix,
                    escape_html(content)
                ));
                continue;
            }
        }

        // Check for header blocks
        let is_heading = trimmed.len() < 80 && trimmed.ends_with(':');
        if is_heading {
            html_output.push_str(&format!(
                "<h4 style='margin-top: 16px; margin-bottom: 8px; margin-left: {}px;'>{}</h4>",
                indent_px,
                escape_html(trimmed)
            ));
            continue;
        }

        // Default text paragraph
        if indent_px > 0 {
            html_output.push_str(&format!(
                "<p style='margin-left: {}px;'>{}</p>",
                indent_px,
                escape_html(trimmed)
            ));
        } else {
            html_output.push_str(&format!(
                "<p>{}</p>",
                escape_html(trimmed)
            ));
        }
    }

    html_output.push_str("</div>");
    Ok(html_output)
}
