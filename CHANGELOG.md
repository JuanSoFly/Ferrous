# Changelog

## [1.1.0] - 2026-06-01

### Added
- Native MOBI and AZW reader support, extracting chapters, text content, and embedded images dynamically.
- Native TXT reader support, converting plaintext to HTML with support for indentations, headers, checkbox items, bullet points, and Mermaid flowcharts.
- Advanced library sorting (by Name, File Name, Format, Size, Modified Time, Date Read) and sort order settings.
- Advanced library filters (format-specific filters, unread books, books without authors, books not in any collections).
- Native DOCX table support, rendering structured tables to HTML for document reading.
- Animated BookCoverShimmer placeholder to provide smooth loading for book covers.
- Method channel option to retrieve the Android native library directory dynamically.

### Changed
- Refactored PDF TTS system using PdfDocumentText mapping to support continuous reading and sentence highlight across page boundaries.
- Refactored PDF rendering pool in Rust using Arc to handle document loading asynchronously outside locks, preventing concurrency bottlenecks.
- Switched PDF page rendering format from PNG to JPEG to resolve alpha channel rendering issues.
- Modernized TTS controls interface with compact parameter toggles and customized sliders.
- Overhauled theme selection UI with concentric circle color previews, refined border outlines, and dynamic decoration themes.
- Updated setup_env.sh to support local cargo and SDK paths dynamically.

## [1.0.0] - 2026-01-25

### Added
- Initial stable release of Ferrous Reader.
- Hybrid architecture combining Flutter frontend with Rust backend for high performance.
- Fast, thread-safe PDF rendering using `pdfium-render`.
- Native EPUB rendering with customizable typography using `epubx` and `flutter_html`.
- Support for CBZ/ZIP comic book archives.
- High-speed device storage scanning powered by Rust's `walkdir`.
- Modern Material 3 user interface.

---