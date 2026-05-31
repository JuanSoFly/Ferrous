use anyhow::{Context, Result};
use docx_rs::{read_docx, Bold, DocumentChild, Italic, Paragraph, ParagraphChild, RunChild, Table, TableChild, TableCellContent, TableRowChild};
use std::fs::File;
use std::io::Read;

fn parse_paragraph_to_html(paragraph: &Paragraph) -> String {
    let mut html = String::new();
    for p_child in &paragraph.children {
        if let ParagraphChild::Run(run) = p_child {
            let mut text_content = String::new();
            
            for run_child in &run.children {
                if let RunChild::Text(text) = run_child {
                    text_content.push_str(&text.text);
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

fn parse_table_to_html(table: &Table) -> String {
    let mut html = String::new();
    html.push_str("<table border='1' style='border-collapse: collapse; width: 100%; margin: 10px 0;'>");
    
    for table_child in &table.rows {
        if let TableChild::TableRow(row) = table_child {
            html.push_str("<tr>");
            for cell_child in &row.cells {
                if let TableRowChild::TableCell(cell) = cell_child {
                    html.push_str("<td style='padding: 8px; border: 1px solid #ccc;'>");
                    for cell_content in &cell.children {
                        match cell_content {
                            TableCellContent::Paragraph(para) => {
                                html.push_str("<p>");
                                html.push_str(&parse_paragraph_to_html(para));
                                html.push_str("</p>");
                            }
                            TableCellContent::Table(nested_table) => {
                                html.push_str(&parse_table_to_html(nested_table));
                            }
                            _ => {}
                        }
                    }
                    html.push_str("</td>");
                }
            }
            html.push_str("</tr>");
        }
    }
    
    html.push_str("</table>");
    html
}

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
                html_output.push_str(&parse_paragraph_to_html(&paragraph));
                html_output.push_str("</p>");
            }
            DocumentChild::Table(table) => {
                html_output.push_str(&parse_table_to_html(&table));
            }
            _ => {}
        }
    }

    html_output.push_str("</div>");
    Ok(html_output)
}

