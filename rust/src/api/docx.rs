use anyhow::{Context, Result};
use docx_rs::{
    read_docx, Bold, DocumentChild, Italic, Paragraph, ParagraphChild, RunChild, Table,
    TableCellContent, TableChild, TableRowChild,
};
use regex::Regex;
use std::collections::HashMap;
use std::fs::{self, File};
use std::io::Read;
use std::path::Path;
use std::sync::OnceLock;

static RID_REGEX: OnceLock<Regex> = OnceLock::new();

fn get_rid_regex() -> &'static Regex {
    RID_REGEX.get_or_init(|| Regex::new(r#"rId\d+"#).unwrap())
}

fn escape_html(text: &str) -> String {
    text.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#x27;")
}

fn extract_docx_media(path: &str, media_dir: &str) -> Result<()> {
    let file = File::open(path)?;
    let mut archive = zip::ZipArchive::new(file)?;

    for i in 0..archive.len() {
        let mut file = archive.by_index(i)?;
        let outpath = match file.enclosed_name() {
            Some(path) => path.to_owned(),
            None => continue,
        };

        let outpath_str = outpath.to_string_lossy();
        if outpath_str.starts_with("word/media/") {
            let dest_path = Path::new(media_dir).join(&outpath);
            if let Some(parent) = dest_path.parent() {
                fs::create_dir_all(parent)?;
            }
            let mut outfile = File::create(&dest_path)?;
            std::io::copy(&mut file, &mut outfile)?;
        }
    }
    Ok(())
}

fn parse_docx_relationships(path: &str) -> Result<HashMap<String, String>> {
    let file = File::open(path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    let mut rels = HashMap::new();

    if let Ok(mut rels_file) = archive.by_name("word/_rels/document.xml.rels") {
        let mut content = String::new();
        rels_file.read_to_string(&mut content)?;

        // Primary: Robust XML parsing via roxmltree
        if let Ok(doc) = roxmltree::Document::parse(&content) {
            for node in doc.descendants() {
                if node.has_tag_name("Relationship") {
                    if let (Some(id), Some(target)) = (node.attribute("Id"), node.attribute("Target")) {
                        rels.insert(id.to_string(), target.to_string());
                    }
                }
            }
        }

        // Fallback: Regex parsing if roxmltree was empty
        if rels.is_empty() {
            let re = Regex::new(r#"Relationship\s+[^>]*?Id="([^"]+)"[^>]*?Target="([^"]+)""#)?;
            for cap in re.captures_iter(&content) {
                rels.insert(cap[1].to_string(), cap[2].to_string());
            }
            if rels.is_empty() {
                let re_rev = Regex::new(r#"Relationship\s+[^>]*?Target="([^"]+)"[^>]*?Id="([^"]+)""#)?;
                for cap in re_rev.captures_iter(&content) {
                    rels.insert(cap[2].to_string(), cap[1].to_string());
                }
            }
        }
    }

    Ok(rels)
}

fn parse_run_json_to_html(
    run_val: &serde_json::Value,
    media_dir: &str,
    rels_map: &HashMap<String, String>,
) -> String {
    let mut text_content = String::new();
    let data = run_val.get("data").unwrap_or(run_val);

    if let Some(children) = data.get("children").and_then(|c| c.as_array()) {
        for child in children {
            let c_type = child.get("type").and_then(|t| t.as_str()).unwrap_or("");
            let c_data = child.get("data").unwrap_or(child);

            match c_type {
                "text" => {
                    if let Some(text) = c_data.get("text").and_then(|t| t.as_str()) {
                        text_content.push_str(&escape_html(text));
                    }
                }
                "tab" => {
                    text_content.push_str("&nbsp;&nbsp;&nbsp;&nbsp;");
                }
                "break" | "carriageReturn" => {
                    text_content.push_str("<br/>");
                }
                "noBreakHyphen" => {
                    text_content.push_str("&#8209;");
                }
                "softHyphen" => {
                    text_content.push_str("&shy;");
                }
                "drawing" => {
                    let drawing_str = child.to_string();
                    if let Some(mat) = get_rid_regex().find(&drawing_str) {
                        let rid = mat.as_str();
                        if let Some(target) = rels_map.get(rid) {
                            let clean_target = target.trim_start_matches('/');
                            let img_path = if clean_target.starts_with("word/") {
                                format!("{}/{}", media_dir, clean_target)
                            } else {
                                format!("{}/word/{}", media_dir, clean_target)
                            };
                            text_content.push_str(&format!(
                                "<img src=\"file://{}\" style=\"max-width: 100%; display: block; margin: 16px auto;\" />",
                                img_path
                            ));
                        }
                    }
                }
                _ => {
                    // Check if drawing is nested under other keys
                    if child.get("drawing").is_some() || c_data.get("drawing").is_some() {
                        let drawing_str = child.to_string();
                        if let Some(mat) = get_rid_regex().find(&drawing_str) {
                            let rid = mat.as_str();
                            if let Some(target) = rels_map.get(rid) {
                                let clean_target = target.trim_start_matches('/');
                                let img_path = if clean_target.starts_with("word/") {
                                    format!("{}/{}", media_dir, clean_target)
                                } else {
                                    format!("{}/word/{}", media_dir, clean_target)
                                };
                                text_content.push_str(&format!(
                                    "<img src=\"file://{}\" style=\"max-width: 100%; display: block; margin: 16px auto;\" />",
                                    img_path
                                ));
                            }
                        }
                    }
                }
            }
        }
    }

    if text_content.is_empty() {
        return String::new();
    }

    // Formatting inspection from runProperty / property
    let prop = data.get("runProperty").or_else(|| data.get("property"));
    let mut open_tags = String::new();
    let mut close_tags = String::new();

    if let Some(p) = prop {
        if p.get("bold").is_some() {
            open_tags.push_str("<b>");
            close_tags.insert_str(0, "</b>");
        }
        if p.get("italic").is_some() {
            open_tags.push_str("<i>");
            close_tags.insert_str(0, "</i>");
        }
        if p.get("underline").is_some() {
            open_tags.push_str("<u>");
            close_tags.insert_str(0, "</u>");
        }
        if p.get("strike").is_some() {
            open_tags.push_str("<s>");
            close_tags.insert_str(0, "</s>");
        }
    }

    format!("{}{}{}", open_tags, text_content, close_tags)
}

fn parse_paragraph_to_html(
    paragraph: &Paragraph,
    media_dir: &str,
    rels_map: &HashMap<String, String>,
) -> String {
    let mut html = String::new();

    for p_child in &paragraph.children {
        match p_child {
            ParagraphChild::Run(run) => {
                let mut text_content = String::new();

                for run_child in &run.children {
                    match run_child {
                        RunChild::Text(text) => {
                            text_content.push_str(&escape_html(&text.text));
                        }
                        RunChild::Tab(_tab) => {
                            text_content.push_str("&nbsp;&nbsp;&nbsp;&nbsp;");
                        }
                        RunChild::Break(_br) => {
                            text_content.push_str("<br/>");
                        }
                        RunChild::Drawing(drawing) => {
                            let drawing_debug = format!("{:?}", drawing);
                            if let Some(mat) = get_rid_regex().find(&drawing_debug) {
                                let rid = mat.as_str();
                                if let Some(target) = rels_map.get(rid) {
                                    let clean_target = target.trim_start_matches('/');
                                    let img_path = if clean_target.starts_with("word/") {
                                        format!("{}/{}", media_dir, clean_target)
                                    } else {
                                        format!("{}/word/{}", media_dir, clean_target)
                                    };
                                    text_content.push_str(&format!(
                                        "<img src=\"file://{}\" style=\"max-width: 100%; display: block; margin: 16px auto;\" />",
                                        img_path
                                    ));
                                }
                            }
                        }
                        _ => {
                            // Serialize fallback for softHyphen, carriageReturn, noBreakHyphen
                            if let Ok(val) = serde_json::to_value(run_child) {
                                let t = val.get("type").and_then(|v| v.as_str()).unwrap_or("");
                                match t {
                                    "carriageReturn" => text_content.push_str("<br/>"),
                                    "noBreakHyphen" => text_content.push_str("&#8209;"),
                                    "softHyphen" => text_content.push_str("&shy;"),
                                    _ => {}
                                }
                            }
                        }
                    }
                }

                let mut open_tags = String::new();
                let mut close_tags = String::new();
                let props = &run.run_property;

                if props.bold.as_ref().is_some_and(|bold| *bold == Bold::new()) {
                    open_tags.push_str("<b>");
                    close_tags.insert_str(0, "</b>");
                }
                if props.italic.as_ref().is_some_and(|italic| *italic == Italic::new()) {
                    open_tags.push_str("<i>");
                    close_tags.insert_str(0, "</i>");
                }

                // Check underline / strike via serde serialization
                if let Ok(prop_val) = serde_json::to_value(props) {
                    if prop_val.get("underline").is_some() {
                        open_tags.push_str("<u>");
                        close_tags.insert_str(0, "</u>");
                    }
                    if prop_val.get("strike").is_some() {
                        open_tags.push_str("<s>");
                        close_tags.insert_str(0, "</s>");
                    }
                }

                html.push_str(&open_tags);
                html.push_str(&text_content);
                html.push_str(&close_tags);
            }
            _ => {
                // Non-run inline elements: Hyperlink, BookmarkStart, StructuredDataTag, Insert
                if let Ok(val) = serde_json::to_value(p_child) {
                    let child_type = val.get("type").and_then(|t| t.as_str()).unwrap_or("");
                    let data = val.get("data").unwrap_or(&val);

                    match child_type {
                        "hyperlink" => {
                            let anchor = data.get("anchor").and_then(|a| a.as_str());
                            let target = data.get("target").and_then(|t| t.as_str());
                            let rid = data.get("id").and_then(|id| id.as_str());

                            let resolved_target = target.or_else(|| rid.and_then(|id| rels_map.get(id).map(|s| s.as_str())));

                            let mut inner_html = String::new();
                            if let Some(runs) = data.get("children").and_then(|c| c.as_array()) {
                                for run_val in runs {
                                    inner_html.push_str(&parse_run_json_to_html(run_val, media_dir, rels_map));
                                }
                            }

                            if let Some(anc) = anchor {
                                html.push_str(&format!(
                                    "<a href=\"#{}\" class=\"toc-link\" style=\"text-decoration: none; color: inherit;\">{}</a>",
                                    escape_html(anc),
                                    inner_html
                                ));
                            } else if let Some(href) = resolved_target {
                                html.push_str(&format!(
                                    "<a href=\"{}\" class=\"external-link\">{}</a>",
                                    escape_html(href),
                                    inner_html
                                ));
                            } else {
                                html.push_str(&inner_html);
                            }
                        }
                        "bookmarkStart" => {
                            if let Some(name) = data.get("name").and_then(|n| n.as_str()) {
                                html.push_str(&format!("<a id=\"{}\"></a>", escape_html(name)));
                            }
                        }
                        "insert" => {
                            if let Some(runs) = data.get("children").and_then(|c| c.as_array()) {
                                for run_val in runs {
                                    html.push_str(&parse_run_json_to_html(run_val, media_dir, rels_map));
                                }
                            }
                        }
                        "structuredDataTag" => {
                            if let Some(children) = data.get("children").and_then(|c| c.as_array()) {
                                for c in children {
                                    html.push_str(&parse_run_json_to_html(c, media_dir, rels_map));
                                }
                            }
                        }
                        _ => {}
                    }
                }
            }
        }
    }

    html
}

fn convert_paragraph_to_html_block(
    paragraph: &Paragraph,
    media_dir: &str,
    rels_map: &HashMap<String, String>,
) -> String {
    let mut tag = "p";
    let mut extra_class = String::new();
    let mut extra_style = String::new();
    let mut is_list = false;

    // Detect heading & TOC styles
    if let Some(style) = &paragraph.property.style {
        let style_lower = style.val.to_lowercase();
        if style_lower.contains("heading 1") || style_lower == "heading1" {
            tag = "h1";
        } else if style_lower.contains("heading 2") || style_lower == "heading2" {
            tag = "h2";
        } else if style_lower.contains("heading 3") || style_lower == "heading3" {
            tag = "h3";
        } else if style_lower.contains("heading 4") || style_lower == "heading4" {
            tag = "h4";
        } else if style_lower.contains("heading 5") || style_lower == "heading5" {
            tag = "h5";
        } else if style_lower.contains("heading 6") || style_lower == "heading6" {
            tag = "h6";
        } else if style_lower == "title" {
            tag = "h1";
            extra_class.push_str(" doc-title");
        } else if style_lower == "subtitle" {
            tag = "h2";
            extra_class.push_str(" doc-subtitle");
        } else if style_lower.contains("tocheading") || style_lower.contains("toc heading") {
            tag = "h2";
            extra_class.push_str(" toc-heading");
        } else if style_lower.contains("toc 1") || style_lower == "toc1" {
            extra_class.push_str(" toc-entry toc-level-1");
            extra_style.push_str(" margin: 4px 0; padding-left: 0px;");
        } else if style_lower.contains("toc 2") || style_lower == "toc2" {
            extra_class.push_str(" toc-entry toc-level-2");
            extra_style.push_str(" margin: 4px 0; padding-left: 16px;");
        } else if style_lower.contains("toc 3") || style_lower == "toc3" {
            extra_class.push_str(" toc-entry toc-level-3");
            extra_style.push_str(" margin: 4px 0; padding-left: 32px;");
        } else if style_lower.contains("toc 4") || style_lower == "toc4" {
            extra_class.push_str(" toc-entry toc-level-4");
            extra_style.push_str(" margin: 4px 0; padding-left: 48px;");
        } else if style_lower.contains("toc") {
            extra_class.push_str(" toc-entry");
            extra_style.push_str(" margin: 4px 0;");
        }
    }

    // Detect bullet or numbered list styles
    if let Some(num_prop) = &paragraph.property.numbering_property {
        is_list = true;
        extra_class.push_str(" list-item");
        let level = num_prop.level.as_ref().map_or(0, |l| l.val);
        let indent = 24 * (level + 1);
        extra_style.push_str(&format!(
            " margin-left: {}px; text-indent: -16px; padding-left: 16px; margin-top: 4px; margin-bottom: 4px;",
            indent
        ));
    }

    // Check alignment via serde serialization
    if let Ok(para_val) = serde_json::to_value(paragraph) {
        let prop = para_val.get("property").or_else(|| para_val.get("paragraphProperty"));
        if let Some(align) = prop
            .and_then(|p| p.get("alignment").or_else(|| p.get("align")))
            .and_then(|a| a.get("val").or(Some(a)))
            .and_then(|v| v.as_str())
        {
            match align {
                "center" => extra_style.push_str(" text-align: center;"),
                "right" => extra_style.push_str(" text-align: right;"),
                "both" | "justify" => extra_style.push_str(" text-align: justify;"),
                _ => {}
            }
        }
    }

    let para_content = parse_paragraph_to_html(paragraph, media_dir, rels_map);

    // Skip empty paragraphs or render as vertical spacing
    if para_content.trim().is_empty() && !is_list {
        return "<div style='height: 12px;'></div>".to_string();
    }

    let class_attr = if extra_class.is_empty() {
        String::new()
    } else {
        format!(" class='{}'", extra_class.trim())
    };

    let style_attr = if extra_style.is_empty() {
        String::new()
    } else {
        format!(" style='{}'", extra_style.trim())
    };

    let mut output = format!("<{}{}{}>", tag, class_attr, style_attr);
    if is_list {
        output.push_str("• &nbsp;");
    }
    output.push_str(&para_content);
    output.push_str(&format!("</{}>", tag));
    output
}

fn parse_table_to_html(
    table: &Table,
    media_dir: &str,
    rels_map: &HashMap<String, String>,
) -> String {
    let mut html = String::new();
    html.push_str("<div class='table-container' style='overflow-x: auto; margin: 16px 0; -webkit-overflow-scrolling: touch;'>");
    html.push_str("<table style='border-collapse: collapse; width: 100%; border: 1px solid rgba(128,128,128,0.3);'>");

    for (row_idx, table_child) in table.rows.iter().enumerate() {
        let TableChild::TableRow(row) = table_child;
        let is_header_row = row_idx == 0;

        html.push_str("<tr>");

        for cell_child in &row.cells {
            let TableRowChild::TableCell(cell) = cell_child;

            // Extract colspan (gridSpan) from cell properties
            let mut colspan_attr = String::new();
            if let Ok(cell_val) = serde_json::to_value(&cell.property) {
                if let Some(grid_span) = cell_val
                    .get("gridSpan")
                    .and_then(|g| g.get("val").or(Some(g)))
                    .and_then(|v| v.as_u64())
                {
                    if grid_span > 1 {
                        colspan_attr = format!(" colspan='{}'", grid_span);
                    }
                }
            }

            let cell_tag = if is_header_row { "th" } else { "td" };
            let cell_style = if is_header_row {
                "border: 1px solid rgba(128,128,128,0.3); padding: 8px 12px; font-weight: bold; text-align: left; background-color: rgba(128,128,128,0.1);"
            } else {
                "border: 1px solid rgba(128,128,128,0.3); padding: 8px 12px; vertical-align: top;"
            };

            html.push_str(&format!("<{} style='{}'{}>", cell_tag, cell_style, colspan_attr));

            for cell_content in &cell.children {
                match cell_content {
                    TableCellContent::Paragraph(para) => {
                        html.push_str(&convert_paragraph_to_html_block(para, media_dir, rels_map));
                    }
                    TableCellContent::Table(nested_table) => {
                        html.push_str(&parse_table_to_html(nested_table, media_dir, rels_map));
                    }
                    _ => {
                        // TableCellContent::StructuredDataTag, etc.
                        if let Ok(content_val) = serde_json::to_value(cell_content) {
                            html.push_str(&process_json_node(&content_val, media_dir, rels_map));
                        }
                    }
                }
            }

            html.push_str(&format!("</{}>", cell_tag));
        }

        html.push_str("</tr>");
    }

    html.push_str("</table></div>");
    html
}

fn process_json_node(
    node: &serde_json::Value,
    media_dir: &str,
    rels_map: &HashMap<String, String>,
) -> String {
    let mut html = String::new();
    let n_type = node.get("type").and_then(|t| t.as_str()).unwrap_or("");
    let data = node.get("data").unwrap_or(node);

    match n_type {
        "paragraph" => {
            let mut text = String::new();
            if let Some(children) = data.get("children").and_then(|c| c.as_array()) {
                for c in children {
                    let c_type = c.get("type").and_then(|t| t.as_str()).unwrap_or("");
                    if c_type == "run" {
                        text.push_str(&parse_run_json_to_html(c, media_dir, rels_map));
                    } else if c_type == "hyperlink" {
                        let c_data = c.get("data").unwrap_or(c);
                        let anchor = c_data.get("anchor").and_then(|a| a.as_str());
                        let target = c_data.get("target").and_then(|t| t.as_str());
                        let rid = c_data.get("id").and_then(|id| id.as_str());
                        let resolved_target = target.or_else(|| rid.and_then(|id| rels_map.get(id).map(|s| s.as_str())));

                        let mut inner_html = String::new();
                        if let Some(runs) = c_data.get("children").and_then(|ch| ch.as_array()) {
                            for r in runs {
                                inner_html.push_str(&parse_run_json_to_html(r, media_dir, rels_map));
                            }
                        }

                        if let Some(anc) = anchor {
                            text.push_str(&format!(
                                "<a href=\"#{}\" class=\"toc-link\" style=\"text-decoration: none; color: inherit;\">{}</a>",
                                escape_html(anc),
                                inner_html
                            ));
                        } else if let Some(href) = resolved_target {
                            text.push_str(&format!(
                                "<a href=\"{}\" class=\"external-link\">{}</a>",
                                escape_html(href),
                                inner_html
                            ));
                        } else {
                            text.push_str(&inner_html);
                        }
                    } else if c_type == "bookmarkStart" {
                        let c_data = c.get("data").unwrap_or(c);
                        if let Some(name) = c_data.get("name").and_then(|n| n.as_str()) {
                            text.push_str(&format!("<a id=\"{}\"></a>", escape_html(name)));
                        }
                    }
                }
            }

            if text.trim().is_empty() {
                html.push_str("<div style='height: 12px;'></div>");
            } else {
                html.push_str(&format!("<p>{}</p>", text));
            }
        }
        "table" => {
            html.push_str("<div class='table-container' style='overflow-x: auto; margin: 16px 0; -webkit-overflow-scrolling: touch;'>");
            html.push_str("<table style='border-collapse: collapse; width: 100%; border: 1px solid rgba(128,128,128,0.3);'>");
            if let Some(rows) = data.get("rows").and_then(|r| r.as_array()) {
                for (row_idx, row) in rows.iter().enumerate() {
                    let is_header = row_idx == 0;
                    let row_data = row.get("data").unwrap_or(row);
                    html.push_str("<tr>");
                    if let Some(cells) = row_data.get("cells").and_then(|c| c.as_array()) {
                        for cell in cells {
                            let cell_data = cell.get("data").unwrap_or(cell);
                            let cell_prop = cell_data.get("property").or_else(|| cell_data.get("tableCellProperty"));
                            let grid_span = cell_prop
                                .and_then(|p| p.get("gridSpan"))
                                .and_then(|g| g.get("val").or(Some(g)))
                                .and_then(|v| v.as_u64())
                                .unwrap_or(1);
                            let colspan_attr = if grid_span > 1 {
                                format!(" colspan='{}'", grid_span)
                            } else {
                                String::new()
                            };

                            let cell_tag = if is_header { "th" } else { "td" };
                            let cell_style = if is_header {
                                "border: 1px solid rgba(128,128,128,0.3); padding: 8px 12px; font-weight: bold; text-align: left; background-color: rgba(128,128,128,0.1);"
                            } else {
                                "border: 1px solid rgba(128,128,128,0.3); padding: 8px 12px; vertical-align: top;"
                            };

                            html.push_str(&format!("<{} style='{}'{}>", cell_tag, cell_style, colspan_attr));
                            if let Some(children) = cell_data.get("children").and_then(|c| c.as_array()) {
                                for child in children {
                                    html.push_str(&process_json_node(child, media_dir, rels_map));
                                }
                            }
                            html.push_str(&format!("</{}>", cell_tag));
                        }
                    }
                    html.push_str("</tr>");
                }
            }
            html.push_str("</table></div>");
        }
        "structuredDataTag" | "tableOfContents" | "section" => {
            if let Some(children) = data.get("children").and_then(|c| c.as_array()) {
                for child in children {
                    html.push_str(&process_json_node(child, media_dir, rels_map));
                }
            }
        }
        _ => {
            // General children traversal
            if let Some(children) = data.get("children").and_then(|c| c.as_array()) {
                for child in children {
                    html.push_str(&process_json_node(child, media_dir, rels_map));
                }
            }
        }
    }

    html
}

pub fn read_docx_to_html(path: String) -> Result<String> {
    let mut file = File::open(&path).context("Failed to open DOCX file")?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).context("Failed to read DOCX file")?;

    let docx = read_docx(&buffer).map_err(|e| anyhow::anyhow!("Failed to parse DOCX: {:?}", e))?;

    // Derive media cache directory from resolved DOCX path
    let media_dir = format!("{}_media", path);
    let _ = extract_docx_media(&path, &media_dir);
    let rels_map = parse_docx_relationships(&path).unwrap_or_default();

    // Check for multi-column section styling
    let mut container_style = String::new();
    if let Ok(sec_val) = serde_json::to_value(&docx.document.section_property) {
        if let Some(cols) = sec_val
            .get("columns")
            .or_else(|| sec_val.get("cols"))
            .and_then(|c| c.get("val").or_else(|| c.get("num")).or(Some(c)))
            .and_then(|v| v.as_u64())
        {
            if cols > 1 {
                container_style = format!(" style='column-count: {}; column-gap: 24px;'", cols);
            }
        }
    }

    let mut html_output = String::new();
    html_output.push_str(&format!("<div class='docx-content'{}>", container_style));

    for child in docx.document.children {
        match child {
            DocumentChild::Paragraph(paragraph) => {
                html_output.push_str(&convert_paragraph_to_html_block(&paragraph, &media_dir, &rels_map));
            }
            DocumentChild::Table(table) => {
                html_output.push_str(&parse_table_to_html(&table, &media_dir, &rels_map));
            }
            _ => {
                // StructuredDataTag, TableOfContents, Section, etc.
                if let Ok(child_val) = serde_json::to_value(&child) {
                    html_output.push_str(&process_json_node(&child_val, &media_dir, &rels_map));
                }
            }
        }
    }

    html_output.push_str("</div>");
    Ok(html_output)
}
