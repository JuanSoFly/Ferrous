# Changelog

## [1.2.0] - 2026-11-06

### Added
- Manual "Check for Updates" tile in Settings to check for new releases on demand.
- Realistic Apple Books style page curl animation and interactive gesture navigation.
- Customizable book background textures (parchment, paper grain) and reader themes.
- Custom library storage locations management with automated folder scanning.
- Native HTML and EPUB table rendering powered by flutter_html_table and flutter_layout_grid.
- First-line paragraph indentation injection across EPUB and MOBI content.
- Annotation details bottom sheet with highlight management and notes editing.
- Delete book confirmation dialog with optional physical storage cleanup.
- Configured Android ProGuard optimization rules for release APK builds.

### Changed
- Refactored page curl rendering with ListenableBuilder and cached repaints for smooth 120Hz performance.
- Improved chapter scroll navigation and character-based offset estimation in EPUB and MOBI controllers.
- Overhauled reader TTS controllers and sentence boundary tracking.
- Added automated Rust (Clippy) and Flutter static analysis lint checks to the release CI pipeline.

## [1.2.0-alpha.3] - 2026-11-06

### Added
- Native paragraph first-line indentation injection for EPUB and MOBI content via HyphenationHelper.
- Integrated `flutter_html_table` and `flutter_layout_grid` for styled HTML table rendering.

### Changed
- Refactored `RealisticPageTurn` using `ListenableBuilder` and cached page rendering to optimize animation performance.
- Improved chapter scroll navigation and character-based offset estimation in EPUB/MOBI controllers.
- Added `build/**` and `android/**` paths to analyzer exclusion list in `analysis_options.yaml`.

## [1.2.0-alpha.2] - 2026-11-06

### Fixed
- Fixed Matrix4 `scaleByDouble` argument signature in `TableFullScreenViewer` for proper 2D zoom transformation.
- Streamlined chapter scroll controller lookups with early returns in EPUB and MOBI chapter controllers.
- Resolved Dart analyzer warnings and clippy lints across cover extraction and TXT parser.

## [1.2.0-alpha.1] - 2026-11-06

### Added
- Experimental Apple Books style page curl animation and gesture interaction.
- Custom book background textures and reader themes.
- Library locations management with custom folder scanning.
- Annotation details bottom sheet with highlight management and notes.
- Delete book confirmation dialog with optional physical storage cleanup.
- Configured ProGuard rules for optimized Android release APK builds.

### Changed
- Improved reader TTS controllers and sentence boundary tracking.
- Optimized library state management and book repository operations.

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