# Ferrous Reader

**A Next-Generation Offline Reading Architecture: Flutter + Rust Hybrid**

> ⚠️ **Status: Active Development** | 🚧 **Alpha Release**
> 
> *This project is a work in progress. Features and APIs are subject to change.*

> 🚀 **High-Performance** | 🛡️ **Memory Safe** | 📱 **Android 7.0+**

Ferrous Reader is a modern mobile document reader that leverages a hybrid architecture to deliver the best of both worlds: the smooth, reactive UI of **Flutter** and the raw performance and safety of **Rust**.

By delegating computationally intensive tasks like PDF rendering and filesystem scanning to a Rust backend, Ferrous ensures your reading experience remains buttery smooth (120Hz) while maintaining a lightweight memory footprint.

## 🌟 Key Features

### 📖 Supported Formats
*   **PDF**: Powered by the **Rust** `pdfium-render` crate. This bypasses the standard Android PDF renderer, offering high-speed, thread-safe rendering directly to Flutter textures.
*   **EPUB**: Native widget-based rendering via `epubx` and `flutter_html`. This allows for full control over typography and themes without the limitations of a WebView.
*   **CBZ/ZIP**: Direct stream decompression for comic book archives.
*   **File Scanning**: Blisteringly fast scanning of the entire device storage using Rust's `walkdir` crate, capable of filtering thousands of files in seconds.

### ⚡ Hybrid Architecture
Ferrous is built on the **flutter_rust_bridge** (FRB) 2.0 protocol, allowing seamless communication between the Dart frontend and Rust backend.

*   **Rust (Backend)**: Handles heavy lifting:
    *   **PDF Rendering**: `pdfium-render` via FFI.
    *   **I/O**: Efficient recursive directory scanning (`walkdir`) to build your library.
    *   **Concurrency**: All Rust operations run on a `tokio` thread pool, causing zero jank on the main UI thread.
*   **Dart (Frontend)**: Handles the presentation:
    *   **UI**: Material 3 design with `flutter_html` for reflowable content.
    *   **State Management**: `Bloc` / `Provider` pattern.
    *   **Persistence**: **Hive** (NoSQL) for fast, lightweight metadata storage.

## 🏗️ Technical Specifications

| Component | Technology | Implementation Details |
| :--- | :--- | :--- |
| **PDF Engine** | Rust (`pdfium-render`) | Zero-copy rendering. Bitmaps are generated in Rust and passed to Dart as `Uint8List`. |
| **Library Scanner** | Rust (`walkdir`) | Parallelized file walking for instant library updates. |
| **EPUB Engine** | Dart (`epubx`) | Pure Dart parsing. Content is rendered as a tree of native Flutter Widgets. |
| **Database** | Dart (`hive`) | Fast, key-value storage for book metadata and reading progress. |
| **Bridge** | `flutter_rust_bridge` | Automatic generation of Type-safe FFI bindings. |

## 📦 Tech Stack

*   **Languages**: Dart 3.5+, Rust 1.80+
*   **Framework**: Flutter 3.24+
*   **Core Rust Crates**: `pdfium-render`, `walkdir`, `image`, `tokio`, `anyhow`
*   **Core Dart Packages**: `hive`, `epubx`, `flutter_html`, `archive`, `provider`

## 🚀 Getting Started

### Prerequisites
*   Flutter SDK (3.24+)
*   Rust Toolchain (latest stable)
*   Android NDK (r26b recommended)

### Setup & Build
1.  **Install dependencies**:
    ```bash
    flutter pub get
    ```
2.  **Generate Bridge Code**:
    ```bash
    flutter_rust_bridge_codegen generate
    ```
3.  **Install PDFium (required for PDF support)**:
    - Run `bash scripts/setup-pdfium-android.sh`, or follow `docs/pdfium-setup.md`.
    - If you develop on an Android emulator, include `x86_64` when installing PDFium (the script supports this).
4.  **Run on Android**:
    ```bash
    flutter run
    ```
