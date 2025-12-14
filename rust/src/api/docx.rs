use anyhow::{Context, Result};
use docx_rs::{read_docx, DocumentChild, ParagraphChild, RunChild};
use std::fs::File;
use std::io::Read;

pub fn read_docx_to_html(path: String) -> Result<String> {
    let mut file = File::open(&path).context("Failed to open DOCX file")?;
    let mut buffer = Vec::new();
    file.read_to_end(&mut buffer).context("Failed to read DOCX file")?;

    let docx = read_docx(&buffer).map_err(|e| anyhow::anyhow!("Failed to parse DOCX: {:?}", e))?;

    let mut html_output = String::new();
    html_output.push_str("<div class='docx-content'>");

    for child in docx.document.children {
        match child {
            DocumentChild::Paragraph(paragraph) => {
                html_output.push_str("<p>");
                for p_child in paragraph.children {
                    if let ParagraphChild::Run(run) = p_child {
                        let mut text_content = String::new();
                        
                        for run_child in run.children {
                            if let RunChild::Text(text) = run_child {
                                text_content.push_str(&text.text);
                            }
                        }

                        // Apply formatting
                        let mut open_tags = String::new();
                        let mut close_tags = String::new();

                        if let Some(props) = &run.property {
                            if props.bold.is_some() {
                                open_tags.push_str("<b>");
                                close_tags.insert_str(0, "</b>");
                            }
                            if props.italic.is_some() {
                                open_tags.push_str("<i>");
                                close_tags.insert_str(0, "</i>");
                            }
                            // Add more formatting as needed (underline, color, etc.)
                        }

                        html_output.push_str(&open_tags);
                        html_output.push_str(&text_content);
                        html_output.push_str(&close_tags);
                    }
                }
                html_output.push_str("</p>");
            }
            DocumentChild::Table(_) => {
                html_output.push_str("<p><i>[Table - Not Supported]</i></p>");
            }
            _ => {} // Ignore other elements for now
        }
    }

    html_output.push_str("</div>");
    Ok(html_output)
}
