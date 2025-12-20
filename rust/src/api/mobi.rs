use anyhow::Result;
use mobi::Mobi;

/// Extracts content from a MOBI file as HTML.
#[flutter_rust_bridge::frb(sync)]
pub fn get_mobi_content(path: String) -> Result<String> {
    let mobi = Mobi::from_path(&path)?;
    Ok(mobi.content_as_string())
}

/// Returns the title of a MOBI file.
#[flutter_rust_bridge::frb(sync)]
pub fn get_mobi_title(path: String) -> Result<String> {
    let mobi = Mobi::from_path(&path)?;
    Ok(mobi.title().to_string())
}

/// Returns the author of a MOBI file.
#[flutter_rust_bridge::frb(sync)]
pub fn get_mobi_author(path: String) -> Result<String> {
    let mobi = Mobi::from_path(&path)?;
    Ok(mobi.author().unwrap_or("Unknown Author").to_string())
}
