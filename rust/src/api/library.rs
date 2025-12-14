use walkdir::WalkDir;

pub struct BookMetadata {
    pub title: String,
    pub author: String,
    pub path: String,
}

pub fn scan_library(root_path: String) -> Vec<BookMetadata> {
    let supported_extensions = vec!["pdf", "epub", "cbz", "docx"];
    
    let mut books = Vec::new();
    
    for entry in WalkDir::new(&root_path)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        let path = entry.path();
        if path.is_file() {
            if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
                if supported_extensions.contains(&ext.to_lowercase().as_str()) {
                    let title = path.file_stem()
                        .and_then(|s| s.to_str())
                        .unwrap_or("Unknown Title")
                        .to_string();
                        
                    books.push(BookMetadata {
                        title,
                        author: "Unknown Author".to_string(),
                        path: path.to_string_lossy().to_string(),
                    });
                }
            }
        }
    }

    books
}
