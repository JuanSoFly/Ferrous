# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Ferrous Reader** is a hybrid Flutter + Rust mobile document reader for Android. It uses flutter_rust_bridge (FRB) 2.0 for seamless Dart-Rust interop, with Rust handling performance-critical operations (PDF rendering, file scanning) and Flutter managing the UI.

## Common Commands

### Development & Build
```bash
# Install dependencies
flutter pub get

# Generate bridge code (required after Rust API changes)
flutter_rust_bridge_codegen generate

# Setup PDFium (required for PDF support)
bash scripts/setup-pdfium-android.sh
# For emulator support: PDFIUM_ABIS="arm64-v8a,x86_64" bash scripts/setup-pdfium-android.sh

# Run on Android
flutter run

# Build APK
flutter build apk --release

# Run tests
flutter test

# Run a single test
flutter test test/path/to/test_file.dart

# Analyze code
flutter analyze

# Format code
dart format .
```

### Rust Development
```bash
cd rust
cargo check
cargo build --release
cargo test
```

## Architecture

### High-Level Structure

```
lib/
├── main.dart                    # App entry point, Hive initialization, Rust lib init
├── app/
│   └── app_shell.dart          # Main navigation (Library, Annotations, Settings)
├── core/
│   └── models/                 # Data models (Book, Annotation, Collection)
├── data/
│   ├── repositories/          # Hive-based storage (BookRepository, etc.)
│   └── services/              # Platform services (TTS, SAF, FileResolver)
├── features/
│   ├── library/               # Library screen with book discovery & scanning
│   ├── reader/                # Reader implementations (PDF, EPUB, CBZ, DOCX, MOBI)
│   ├── annotations/           # Highlighting & notes
│   ├── collections/           # Book collections
│   ├── settings/              # App settings & themes
│   └── dictionary/            # Dictionary lookup
└── src/rust/                  # Auto-generated FRB bindings

rust/
├── src/
│   ├── api/
│   │   ├── pdf.rs            # PDF rendering via pdfium-render
│   │   ├── covers.rs         # Cover extraction/generation
│   │   ├── library.rs        # File scanning via walkdir
│   │   ├── docx.rs           # DOCX parsing
│   │   ├── mobi.rs           # MOBI/AZW3 parsing
│   │   ├── cbz.rs            # CBZ/ZIP extraction
│   │   ├── tts_text.rs       # TTS text extraction & highlighting
│   │   └── crop.rs           # PDF auto-cropping
│   ├── lib.rs                # Rust entry, timed! macro, global state
│   └── frb_generated.rs      # Auto-generated FRB code (DO NOT EDIT)
```

### Key Architectural Patterns

#### 1. **Hybrid Bridge Architecture**
- **Rust Backend**: Heavy computation, I/O, concurrency
  - `pdfium-render` for PDF rendering (zero-copy bitmaps → Dart)
  - `walkdir` for fast file system scanning
  - `tokio` thread pool for async operations
  - Global `OnceLock` caches for PDFium instance & document pool

- **Dart Frontend**: UI, state management, persistence
  - `StateNotifier` + `Provider` for state
  - `Hive` for NoSQL metadata storage
  - `flutter_html` + `epubx` for EPUB rendering

#### 2. **PDF Rendering Pipeline**
```
Dart: PdfPageController
  ↓ (FRB call)
Rust: render_pdf_page() → pdfium → bitmap
  ↓ (zero-copy)
Dart: Uint8List → Image widget
```

**Performance Optimizations:**
- LRU cache: 5 pages in memory (`_pageRenderCache`)
- Prefetch: ±2 pages ahead/behind
- Semaphore: Max 2 concurrent renders
- Texture limit: 4096×4096 max

#### 3. **Library Scanning Flow**
```
User picks folder (SAF)
  ↓
SafService persists URI
  ↓
LibraryController.rescanFolders()
  ↓
Rust: walkdir recursive scan
  ↓
Filter by format (pdf, epub, cbz, docx, mobi)
  ↓
BookRepository.addBooks()
  ↓
Background cover generation (Rust: covers.rs)
```

#### 4. **State Management**
- **Library**: `StateNotifier<LibraryState>` with memoized filtering
- **Reader**: Multiple controllers per format:
  - `PdfPageController` - page rendering & caching
  - `PdfTtsController` - TTS coordination & highlighting
  - `ReaderChromeController` - UI visibility (immersive mode)
  - `ReaderModeController` - reading mode (vertical, horizontal, etc.)

#### 5. **Data Models**
- `Book` (Hive type 0): All metadata, progress, reading mode
- `Annotation` (Hive type 1): Highlights & notes
- `Collection` (Hive type 2): Book groupings
- `ReaderThemeConfig` (Hive type 3): Custom themes

### File Format Support

| Format | Engine | Implementation | Notes |
|--------|--------|----------------|-------|
| PDF | Rust (`pdfium-render`) | `rust/src/api/pdf.rs` | Requires libpdfium.so |
| EPUB | Dart (`epubx` + `flutter_html`) | `lib/features/reader/epub_reader.dart` | Native widgets |
| CBZ/ZIP | Rust (`zip`) + Dart | `rust/src/api/cbz.rs` | Stream decompression |
| DOCX | Rust (`docx-rs`) | `rust/src/api/docx.rs` | HTML conversion |
| MOBI/AZW3 | Rust (`mobi`) | `rust/src/api/mobi.rs` | Basic parsing |

### TTS (Text-to-Speech) Architecture

1. **Text Extraction**: Rust extracts text from PDF/EPUB
2. **Sentence Tracking**: Offsets stored in `Book` model
3. **Highlight Sync**: `PdfTtsController` maps TTS progress → character bounds
4. **Follow Mode**: Auto-scrolls PDF to current sentence
5. **Persistence**: Saves position on pause/exit

### Key Rust APIs (FRB Exposed)

```rust
// PDF
get_pdf_page_count(path: String) -> i32
render_pdf_page(path: String, pageIndex: i32, width: i32, height: i32) -> Vec<u8>
extract_pdf_page_text(path: String, pageIndex: i32) -> String
extract_pdf_page_text_bounds(...) -> Vec<PdfTextRect>

// Library
scan_directory(path: String) -> Vec<FileMeta>  // via walkdir

// Covers
generate_book_cover(path: String, outDir: String) -> String

// TTS
extract_tts_text_epub(path: String) -> String
extract_tts_text_pdf(path: String, pageIndex: i32) -> String
```

### Performance Considerations

- **Main Thread**: All UI updates, no heavy computation
- **Rust Thread Pool**: `tokio` handles I/O and rendering
- **Memory**: PDFium docs cached (max 4), page bitmaps cached (max 5)
- **Prefetch**: Aggressive ±2 page prefetch for smooth scrolling
- **Timed Macro**: `rust/src/lib.rs:timed!()` logs >10ms operations

### Testing

- **Unit**: `test/` directory (Dart only)
- **Integration**: `integration_test/` directory
- **Rust**: `rust/` - `cargo test`

### Environment Requirements

- Flutter: 3.24+
- Dart: 3.5+
- Rust: 1.80+
- Android NDK: r26b recommended
- PDFium: Must be installed via `setup-pdfium-android.sh`

### Common Issues & Solutions

**"Failed to bind to pdfium library"**
→ Run `bash scripts/setup-pdfium-android.sh`

**"Rust library init error"**
→ Check NDK setup, ensure `rust_builder` builds correctly

**Bridge code out of sync**
→ Run `flutter_rust_bridge_codegen generate`

**Slow PDF rendering**
→ Check PDFium version, verify texture size limits

### Important Files

- `flutter_rust_bridge.yaml` - FRB configuration
- `rust/Cargo.toml` - Rust dependencies
- `pubspec.yaml` - Dart dependencies
- `setup_env.sh` - Environment setup script
- `docs/pdfium-setup.md` - Detailed PDFium setup (if exists)

### Code Style

- **Dart**: Follow Flutter conventions, `flutter_lints`
- **Rust**: Standard formatting (`cargo fmt`), `clippy` warnings
- **Naming**: `snake_case` for Rust, `camelCase` for Dart
- **Error Handling**: `anyhow::Result` in Rust, exceptions in Dart

### Git Hooks

The project uses standard git workflow. Check `.gitignore` for build artifacts.

### Agent Configuration

The `.agent/` directory contains custom rules for AI agents:
- `.agent/rules/architecture_rules.md` - Architecture guidelines
- `.agent/workflows/technical_workflows.md` - Development workflows

### Next Steps for New Contributors

1. Run `flutter pub get`
2. Setup PDFium: `bash scripts/setup-pdfium-android.sh`
3. Generate bindings: `flutter_rust_bridge_codegen generate`
4. Run `flutter run` to verify setup
5. Read `lib/features/library/library_state.dart` for scanning flow
6. Read `rust/src/api/pdf.rs` for PDF rendering internals
