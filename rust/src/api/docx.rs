use anyhow::{Context, Result};
use docx_rs::{read_docx, Bold, DocumentChild, Italic, Paragraph, ParagraphChild, RunChild, Table, TableChild, TableCellContent, TableRowChild};
use std::fs::File;
use std::io::Read;
use std::collections::HashMap;
use std::path::Path;
use std::fs;

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
        
        let re = regex::Regex::new(r#"Relationship\s+Id="([^"]+)"[^>]*?Target="([^"]+)""#)?;
        for cap in re.captures_iter(&content) {
            rels.insert(cap[1].to_string(), cap[2].to_string());
        }
    }
    
    Ok(rels)
}

fn parse_paragraph_to_html(
    paragraph: &Paragraph, 
    media_dir: &str, 
    rels_map: &HashMap<String, String>
) -> String {
    let mut html = String::new();
    for p_child in &paragraph.children {
        if let ParagraphChild::Run(run) = p_child {
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
                        let re_rid = regex::Regex::new(r#"rId\d+"#).unwrap();
                        if let Some(mat) = re_rid.find(&drawing_debug) {
                            let rid = mat.as_str();
                            if let Some(target) = rels_map.get(rid) {
                                // target in rels is relative to word/ (e.g. "media/image1.png")
                                let img_path = format!("{}/word/{}", media_dir, target);
                                text_content.push_str(&format!(
                                    "<img src=\"file://{}\" style=\"max-width: 100%; display: block; margin: 16px auto;\" />",
                                    img_path
                                ));
                            }
                        }
                    }
                    _ => {}
                }
            }

            // Apply formatting
            let mut open_tags = String::new();
            let mut close_tags = String::new();

            let props = &run.run_property;

            if props
                .bold
                .as_ref()
                .is_some_and(|bold| bold == &Bold::new())
            {
                open_tags.push_str("<b>");
                close_tags.insert_str(0, "</b>");
            }

            if props
                .italic
                .as_ref()
                .is_some_and(|italic| italic == &Italic::new())
            {
                open_tags.push_str("<i>");
                close_tags.insert_str(0, "</i>");
            }

            html.push_str(&open_tags);
            html.push_str(&text_content);
            html.push_str(&close_tags);
        }
    }
    html
}

fn parse_table_to_html(
    table: &Table, 
    media_dir: &str, 
    rels_map: &HashMap<String, String>
) -> String {
    let mut html = String::new();
    html.push_str("<table>");
    
    for table_child in &table.rows {
        let TableChild::TableRow(row) = table_child;
        html.push_str("<tr>");
        for cell_child in &row.cells {
            let TableRowChild::TableCell(cell) = cell_child;
            html.push_str("<td>");
            for cell_content in &cell.children {
                match cell_content {
                    TableCellContent::Paragraph(para) => {
                        html.push_str("<p>");
                        html.push_str(&parse_paragraph_to_html(para, media_dir, rels_map));
                        html.push_str("</p>");
                    }
                    TableCellContent::Table(nested_table) => {
                        html.push_str(&parse_table_to_html(nested_table, media_dir, rels_map));
                    }
                    _ => {}
                }
            }
            html.push_str("</td>");
        }
        html.push_str("</tr>");
    }
    
    html.push_str("</table>");
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

    let mut html_output = String::new();
    html_output.push_str("<div class='docx-content'>");

    for child in docx.document.children {
        match child {
            DocumentChild::Paragraph(paragraph) => {
                let mut tag = "p";
                let mut extra_style = String::new();
                let mut class_attr = String::new();
                let mut is_list = false;

                // Detect heading styles
                if let Some(style) = &paragraph.property.style {
                    let style_name = &style.val;
                    if style_name.to_lowercase().contains("heading1") {
                        tag = "h1";
                    } else if style_name.to_lowercase().contains("heading2") {
                        tag = "h2";
                    } else if style_name.to_lowercase().contains("heading3") {
                        tag = "h3";
                    } else if style_name.to_lowercase().contains("heading") || style_name.to_lowercase().contains("title") {
                        tag = "h4";
                    }
                }

                // Detect bullet or numbered list styles
                if let Some(num_prop) = &paragraph.property.numbering_property {
                    is_list = true;
                    class_attr = " class='list-item'".to_string();
                    let level = num_prop.level.as_ref().map(|l| l.val).unwrap_or(0);
                    let indent = 24 * (level + 1);
                    extra_style = format!(
                        " style='margin-left: {}px; text-indent: -16px; padding-left: 16px; margin-top: 4px; margin-bottom: 4px;'",
                        indent
                    );
                }

                let para_content = parse_paragraph_to_html(&paragraph, &media_dir, &rels_map);
                
                // Skip empty paragraphs or render as vertical spacing
                if para_content.trim().is_empty() && !is_list {
                    html_output.push_str("<div style='height: 12px;'></div>");
                    continue;
                }

                html_output.push_str(&format!("<{}{}{}>", tag, class_attr, extra_style));
                if is_list {
                    html_output.push_str("• &nbsp;");
                }
                html_output.push_str(&para_content);
                html_output.push_str(&format!("</{}>", tag));
            }
            DocumentChild::Table(table) => {
                html_output.push_str(&parse_table_to_html(&table, &media_dir, &rels_map));
            }
            _ => {}
        }
    }

    html_output.push_str("</div>");
    Ok(html_output)
}
