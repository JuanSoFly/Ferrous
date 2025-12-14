# **Next-Generation Offline Reading Architecture: A Flutter-Rust Hybrid Approach for Android 7+ (2025)**

## **Executive Summary**

The mobile application development landscape in late 2025 has undergone a paradigm shift. The traditional monolithic approach—relying exclusively on platform-specific languages like Kotlin/Java for Android and Swift for iOS—is increasingly viewed as inefficient for data-heavy applications. For a comprehensive offline reading platform targeting Android 7.0 (Nougat) through Android 15+, the standard Gradle/Kotlin stack imposes significant limitations regarding memory management, binary size, and cross-platform maintainability. The industry has moved toward hybrid architectures that leverage high-level UI frameworks for presentation and systems-level languages for computation.

This report presents a definitive architectural blueprint for constructing an "Always Up-To-Date," lightweight, and reliable reading application. The proposed solution is a **Flutter \+ Rust Hybrid Architecture**. By coupling Flutter’s Impeller rendering engine with a high-performance Rust backend via the flutter\_rust\_bridge (FRB) 2.0 protocol, developers can achieve C++ level performance with memory safety guarantees that the Java Virtual Machine (JVM) cannot provide.

The following analysis details the implementation of a reader supporting PDF, EPUB, DJVU, MOBI, CBZ, and DOCX formats. It explores the implementation of advanced features such as multi-document split-screen views, a "Console" visual theme, background Text-to-Speech (TTS), and intelligent library management. The report prioritizes architectural robustness, outlining strategies to bypass legacy Android limitations (e.g., Storage Access Framework restrictions) while delivering a modern, high-fidelity user experience.

## **1\. The Paradigm Shift: Beyond Standard Native Development**

In the context of late 2025, defining an application as "modern" requires looking beyond the immediate tooling of the Android SDK. While Kotlin remains the standard for general-purpose Android applications, it introduces overhead that is detrimental to high-performance document rendering. The request for a "lighter and reliable" tech stack that is explicitly "NOT standard Gradle/Kotlin" points towards a compiled systems language architecture.

### **1.1 Limitations of the JVM for Document Processing**

The Java Virtual Machine (JVM), even with the optimizations found in the Android Runtime (ART), struggles with the specific workload of a document reader.

* **Memory Pressure and Garbage Collection:** Rendering a high-resolution PDF page or decoding a DJVU layer requires manipulating large byte arrays and bitmaps. In a managed environment like the JVM, these ephemeral allocations trigger frequent Garbage Collection (GC) events. On older devices running Android 7 (which often have 2GB or less of RAM), these GC pauses manifest as visible UI "jank" or dropped frames during scrolling.1  
* **JNI Overhead:** To access efficient C/C++ libraries (like libpdfium or djvulibre), standard Android apps use the Java Native Interface (JNI). JNI is notoriously verbose, difficult to debug, and introduces a marshaling overhead when passing data between Java and C++.  
* **Binary Bloat:** Including multiple native libraries and their Java bindings increases APK size. Kotlin's standard library and Jetpack libraries add further weight.

### **1.2 The Flutter \+ Rust Advantage**

The proposed architecture utilizes Flutter for the UI and Rust for the business logic and rendering core. This combination, often termed the "FRB Stack" (Flutter-Rust Bridge), addresses the limitations of the JVM directly.

| Metric | Standard Kotlin/JVM Architecture | Flutter \+ Rust Hybrid Architecture |
| :---- | :---- | :---- |
| **Rendering Engine** | Android Views / Jetpack Compose (System Dependent) | Impeller (Vulkan/Metal), Consistent across OS versions |
| **Logic Runtime** | ART (Managed, GC-dependent) | Native Machine Code (Manual/RAII Memory Management) |
| **Interop Safety** | JNI (Unsafe, error-prone) | FFI via flutter\_rust\_bridge (Type-safe, Auto-generated) |
| **Thread Management** | Java Threads / Coroutines | Rust Async / Tokio Runtime (Lightweight, efficient) |
| **Binary Size** | High (JVM libs \+ Native libs) | Low (Stripped Native Binary \+ Flutter Engine) |

#### **1.2.1 The Role of Flutter and Impeller**

Flutter serves as the presentation layer. By late 2025, Flutter has fully transitioned to the **Impeller** rendering engine on Android.2 Unlike the previous Skia engine, which compiled shaders at runtime (causing "first-run jank"), Impeller uses pre-compiled shaders. This ensures that the reading interface remains buttery smooth (120Hz capable) even on mid-range devices. Flutter's widget system allows for pixel-perfect layout control that is identical on Android 7 and Android 15, eliminating the fragmentation issues inherent in Android XML layouts.

#### **1.2.2 The Role of Rust**

Rust acts as the application's "brain." It handles all file I/O, format parsing, image processing, and database interactions. Rust’s ownership model guarantees memory safety without a garbage collector. This is crucial for stability; a buffer overflow in a C++ PDF parser could crash the entire app, whereas Rust catches such errors at compile time or handles them gracefully at runtime.3 Furthermore, Rust's ecosystem of "crates" (libraries) for parsing binary formats is robust, modern, and often faster than their C/C++ counterparts due to aggressive compiler optimizations (LLVM).

## **2\. Architectural Core: The Flutter-Rust Bridge**

The success of this hybrid app depends on the communication channel between the Dart (Flutter) frontend and the Rust backend. The flutter\_rust\_bridge (FRB) library is the industry standard for this integration in 2025\.

### **2.1 Bridge Mechanics and Data Flow**

In traditional Android NDK development, passing a complex structure (like a book's metadata or a rendered page image) requires manual serialization and JNI calls. FRB automates this entirely.

1. **Interface Definition (API):** Developers define the desired application functions in a Rust file. For example:  
   Rust  
   pub fn render\_pdf\_page(path: String, page\_index: u16) \-\> Vec\<u8\>;

2. **Code Generation:** The FRB codegen tool analyzes this Rust function and generates:  
   * **Dart bindings:** A Dart class that Flutter code can call (api.renderPdfPage(...)).  
   * **C glue code:** A thin C layer to facilitate the FFI (Foreign Function Interface).  
   * **Rust wire code:** Rust code to handle the incoming data and return the result.  
3. **Zero-Copy Communication:** For large data transfer, such as passing a 5MB rendered bitmap from Rust to Flutter, FRB supports zero-copy transfer. Instead of copying the bytes, Rust passes a pointer to the memory buffer directly to Dart, which wraps it in a Uint8List. This eliminates the serialization overhead that typically plagues hybrid apps.4

### **2.2 Asynchronous Concurrency Model**

A reading app is inherently asynchronous. Opening a large EPUB or rendering a high-DPI PDF page takes time. If this happens on the main UI thread, the app freezes.

The architecture leverages Rust's **Tokio** runtime. When Flutter requests a document load:

1. **Flutter (Main Isolate):** Calls the Rust function asynchronously (await api.loadDocument(...)).  
2. **Bridge:** Offloads the request to the Rust thread pool.  
3. **Rust (Worker Thread):** Performs the heavy parsing using blocking I/O (if necessary) or async I/O.  
4. **Completion:** Rust returns the result. The Flutter Future completes, and the UI updates.

This strict separation ensures the UI thread is *never* blocked by file operations, adhering to the "lighter and reliable" requirement.

### **2.3 Memory Safety and Stability**

Android 7 devices are resource-constrained. A common crash in reading apps occurs when opening multiple large documents (OOM \- Out of Memory).

* **Rust's Advantage:** Rust allows precise control over memory layout. We can implement a strictly capped LRU (Least Recently Used) cache for rendered pages. If the user opens a second document in split-screen mode, Rust can deterministically deallocate the bitmaps from the first document's invisible pages, ensuring the app never exceeds its memory budget. This reliability is hard to guarantee in a JVM environment where GC behavior is non-deterministic.

## **3\. High-Performance Rendering Pipelines**

The core utility of the application is its ability to render diverse formats. "Standard" Android development often relies on system WebViews or intent-based external viewers. To meet the "comprehensive" and "offline" requirements, this architecture implements **internal rendering engines** for all supported formats.

### **3.1 PDF (Portable Document Format)**

PDF is a fixed-layout format requiring a sophisticated rendering engine to interpret PostScript-like drawing commands.

#### **3.1.1 Engine Selection: pdfium-render**

While MuPDF is a common choice, its AGPL license 5 requires open-sourcing the entire application, which may not be desirable for all developers. The recommended engine is **Pdfium** (used by Google Chrome). It is performant, BSD-licensed, and handles broken/malformed PDFs gracefully.

* **Library:** The pdfium-render crate 6 provides high-level Rust bindings to the Pdfium C++ library.

#### **3.1.2 Rendering Strategy**

The rendering pipeline is designed for speed and zoom clarity:

1. **Document Load:** Rust initializes the PdfDocument struct. This loads the cross-reference table but does not decode pages.  
2. **Viewport Calculation:** Flutter calculates the visible area. If the user is zoomed in 300%, Flutter requests only the visible tile (e.g., x: 100, y: 200, width: 500, height: 800).  
3. **Tiled Rendering:** Rust invokes Pdfium to render *only* that specific bitmap region. This is significantly faster than rendering the full page at 300% scale and cropping it.  
4. **Bitmap Transfer:** The raw RGBA pixels are sent to Flutter and displayed on a Texture widget. This avoids the overhead of encoding/decoding PNG/JPG formats; raw bytes are blitted directly to the GPU.

### **3.2 DJVU (DjVu)**

DJVU is a legacy format highly optimized for scanned documents, often using wavelet compression to separate text (foreground) from paper texture (background). Android support is historically poor.

#### **3.2.1 Engine Selection: djvulibre via Custom Wrapper**

There is no pure Rust DJVU parser that is production-ready. The solution is to use the industry-standard **DjVuLibre** C library, wrapped in a custom Rust sys crate.7

* **Implementation:** Use bindgen to create Rust FFI bindings to libdjvu.  
* **Safety Layer:** Write a safe Rust wrapper around the raw C pointers to ensure that ddjvu\_context and ddjvu\_document handles are properly freed when the book is closed, preventing memory leaks.

#### **3.2.2 Layered Decoding**

DJVU files contain separate layers for the background image and the foreground text mask.

* **Optimization:** The Rust backend can decode the black-and-white foreground mask *first*. This data is extremely small and can be sent to Flutter almost instantly, allowing the user to read the text while the high-quality background texture loads in the background. This "progressive rendering" makes the app feel incredibly fast ("lighter") even on slow devices.

### **3.3 EPUB (Electronic Publication)**

Unlike PDF/DJVU, EPUB is reflowable HTML content. Rendering it as a static image defeats the utility of text resizing and themes.

#### **3.3.1 Parsing: epub Crate**

The epub crate in Rust efficiently extracts metadata, the spine (chapter order), and raw HTML content from the underlying ZIP structure.8

#### **3.3.2 Rendering Strategy: The Hybrid View**

There are two approaches to rendering EPUB in Flutter:

1. **WebView Approach:** Inject HTML into a system WebView. This is heavy and inconsistent across Android versions.  
2. **Native Widget Approach (Recommended):** Use a parser to convert HTML tags into Flutter Widgets (Text, RichText, Image).  
   * **Architecture:** Rust parses the HTML using quick-xml or html5ever. It produces a simplified "Render Tree" JSON (e.g., "Paragraph object", "Header object", "Image object").  
   * **Display:** Flutter receives this tree and builds a ListView of native widgets.  
   * **Benefit:** This allows the "Console" or "Night" themes to apply instantly and natively. A WebView would require injecting complex CSS and might flash white during loading. The native approach is lighter and fully offline-safe.

### **3.4 MOBI / AZW3 (Kindle Formats)**

These are proprietary formats based on the old PalmDOC compression.

#### **3.4.1 Engine: libmobi Wrapper**

Similar to DJVU, libmobi is a C library that handles these formats.9

* **Conversion Pipeline:** Since implementing a direct renderer for MOBI is redundant, the Rust backend uses libmobi to convert the document structure into the same HTML intermediate format used for EPUBs.  
* **Unified Pipeline:** This means the Flutter frontend doesn't know (or care) if the source was EPUB, MOBI, or AZW3; it receives the same standardized Render Tree from Rust.

### **3.5 CBZ (Comic Book Archive)**

CBZ files are simply ZIP archives containing images (JPG/PNG).

#### **3.5.1 Engine: zip and image Crates**

Rust is exceptionally fast at stream processing.

1. **Stream Decompression:** The zip crate reads the central directory.  
2. **Image Processing:** The image crate (pure Rust) decodes the pixel data.  
3. **Resizing:** If a comic page is 4000px wide but the phone screen is only 1080px, sending the full image is wasteful. Rust downsamples the image using SIMD-optimized algorithms (Lanczos3) before sending it to Flutter. This reduces memory usage on the Dart side by 70-80%.

### **3.6 DOCX (Microsoft Word)**

#### **3.6.1 Engine: docx-rs**

The docx-rs crate parses the OpenXML structure of .docx files.

* **Conversion:** Similar to MOBI, the Rust backend traverses the XML document. It maps Word styles (Heading 1, Normal, Quote) to the application's internal Render Tree format. This enables a consistent reading experience where a DOCX file looks indistinguishable from an EPUB.

## **4\. Advanced Library Management & Data Persistence**

A "comprehensive" app requires more than just file opening; it needs to manage a library of thousands of books.

### **4.1 High-Speed File System Scanning**

One of the greatest frustrations with Android apps is the slow scanning of large libraries. Java's File.listFiles() is recursive and slow.

* **Rust Implementation:** The walkdir crate in Rust provides a highly optimized directory iterator.  
* **Performance:** Rust can scan a generic storage volume with 10,000 files in under a second on modern hardware, filtering for specific extensions (.epub, .pdf, etc.).  
* **Auto-Detection Logic:**  
  * Rust runs a background thread that monitors the filesystem.  
  * When a new file is found, it calculates a hash (using xxHash, which is faster than MD5/SHA) of the first 4KB of the file.  
  * This hash acts as the unique ID, allowing the app to track the book even if the user moves or renames the file.10

### **4.2 Database Technology: Isar**

For persistence, the architecture eschews the standard SQLite (via sqflite) in favor of **Isar**.

* **Why Isar?**  
  * **Architecture:** Isar is a NoSQL database written in Rust but designed specifically for Flutter. It bridges directly to Dart, bypassing the slow platform channels used by SQLite plugins.11  
  * **Full-Text Search (FTS):** The requirement for "advanced library management" implies searching not just titles but metadata. Isar supports multi-entry indexes and full-text search out of the box.  
  * **Speed:** It is asynchronous and ACID-compliant, capable of querying tens of thousands of records in milliseconds, ensuring the library UI never stutters.

| Feature | SQLite (Standard) | Isar (Recommended) |
| :---- | :---- | :---- |
| **Language** | C (accessed via JNI) | Rust (accessed via FFI) |
| **Data Model** | Relational (Tables) | Object (Documents) |
| **Query Speed** | Moderate | Extremely High |
| **Search** | FTS3/4 (Complex setup) | Built-in FTS |
| **Dart Integration** | Async via Platform Channel | Direct FFI (Sync & Async) |

### **4.3 Collections and Metadata**

Rust's parsing crates extract metadata (Title, Author, Cover Image, Description) during the scan.

* **Tagging System:** The app implements a "smart collection" system.  
  * **Subject Analysis:** Rust analyzes the book's metadata subjects (e.g., "Science Fiction", "History").  
  * **Folder Mapping:** It also maps the folder structure (e.g., Books/Comics/Marvel) to collections.  
  * This metadata is stored in Isar, allowing for instant filtering and sorting.

## **5\. Interactive Features & Background Services**

### **5.1 Background Text-to-Speech (TTS)**

Implementing reliable background TTS on Android 7+ (and especially Android 12/14) is technically demanding due to strict battery optimization policies.

#### **5.1.1 Service Architecture**

Standard Flutter plugins often fail to keep playing when the screen turns off. The solution requires a native **Android Foreground Service**.

* **Service Type:** android.content.pm.ServiceInfo.FOREGROUND\_SERVICE\_TYPE\_MEDIA\_PLAYBACK (Android 14 requirement).12  
* **Implementation:**  
  1. **Kotlin Layer:** A lightweight Kotlin service extends MediaBrowserServiceCompat. It holds a WakeLock to prevent the CPU from sleeping.  
  2. **Communication:** Flutter sends the text chunks to this service via a MethodChannel.  
  3. **Media Session:** The service registers a MediaSession. This allows the user to control playback (Play/Pause/Next Sentence) using Bluetooth headphones or the lock screen media controls.

#### **5.1.2 Intelligent Text Extraction (Rust)**

For PDF/DJVU, simply feeding the raw text to the TTS engine results in reading page numbers, headers, and garbled column flows.

* **Smart Extraction:** The Rust backend performs layout analysis.  
  * **Sorting:** Text objects are sorted by Y-coordinate, then X-coordinate, to reconstruct the logical reading order.  
  * **Filtering:** Objects located in the top/bottom 5% of the page (headers/footers) are excluded from the TTS stream.  
  * **Hyphenation:** Words split across lines (e.g., "con- tinue") are de-hyphenated by the Rust logic before being sent to the TTS service.

### **5.2 Dictionary Lookups**

The app must support offline dictionary lookups without bloat.

#### **5.2.1 Integration with External Apps**

Android has a rich ecosystem of dictionary apps (ColorDict, GoldenDict).

* **Intent Protocol:** When a user selects a word, the app broadcasts an Android Intent.  
  * **Action:** android.intent.action.SEND or specialized actions like colordict.intent.action.SEARCH.  
  * **Data:** The selected word.  
  * **Mode:** Using FLAG\_ACTIVITY\_NEW\_TASK creates a floating window (if supported by the dictionary app) over the reader.14

#### **5.2.2 Internal Offline Dictionary (Rust)**

For a truly self-contained experience, the app can integrate the dict-rs crate.

* **Format:** Support for StarDict (.ifo, .dict, .idx) files.  
* **Mechanism:** Rust performs the binary search in the .idx file to find the word offset, reads the definition from the .dict file, and returns the HTML definition to Flutter. This happens instantly and offline, displayed in a bottom sheet or floating dialog.

### **5.3 Quotes & Notes Hub**

This feature transforms the app from a passive reader to an active study tool.

* **Data Structure:**  
  * **CFI (Canonical Fragment Identifier):** To robustly identify a position in an EPUB (which has no fixed pages), the app uses CFIs (e.g., /6/4\[chap1ref\]\!/4/2/1:0).  
  * **Database:** A Note entity in Isar links the BookID, CFI, SelectedText, UserComment, and Color.  
* **UI \- The Masonry Grid:** The "Hub" screen uses a staggered grid layout (flutter\_staggered\_grid\_view) to present notes as "sticky notes" of varying heights.  
* **Export:** Rust generates a Markdown (.md) file compiling all notes, formatted with headers and bullet points, ready for export to apps like Obsidian or Notion.

## **6\. The "Console" UI & Modern UX Patterns**

The user requested specific visual themes, including a "Console" theme. This is not just a color swap; it is a design language.

### **6.1 Implementing the "Console" Aesthetic**

* **Color Palette:**  
  * **Background:** \#000000 (Pure Black) or \#1E1E1E (VS Code Dark).  
  * **Foreground:** \#00FF00 (Phosphor Green) or \#FFB000 (Amber).  
* **Typography:** The font is critical. The app bundles open-source monospaced fonts like **JetBrains Mono**, **Fira Code**, or **Iosevka**.  
* **UI Components:**  
  * Standard Material buttons are replaced with "retro" components: sharp rectangular borders, no drop shadows, and simple outline styles.  
  * **Cursor:** The reading position indicator can mimic a blinking terminal block cursor.  
* **CSS Injection (EPUB):** For reflowable books, Rust injects a custom CSS stylesheet that overrides publisher defaults:  
  CSS  
  body {  
      background-color: \#000000\!important;  
      color: \#00FF00\!important;  
      font-family: 'JetBrains Mono', monospace\!important;  
  }

### **6.2 Multi-Document Split-Screen**

Split-screen multitasking is a productivity multiplier.

#### **6.2.1 In-App Split Screen (Desktop/Tablet)**

Flutter's widget tree handles this natively without relying on Android's system split-screen (which is clunky).

* **Package:** multi\_split\_view or docking.16  
* **Architecture:**  
  * The root ReaderScreen contains a MultiSplitView widget.  
  * **State Isolation:** Each pane is a generic container that holds a ReaderInstance. Each ReaderInstance has its own Bloc (State Manager) controlling page number, file handle, and zoom.  
  * **Rust Concurrency:** The Rust backend is stateless regarding "current page." It simply accepts requests: render(doc\_id: 1, page: 5\) and render(doc\_id: 2, page: 40). This allows two different files (or the same file at different locations) to be rendered simultaneously without conflict.

### **6.3 Smart Margins (Auto-Crop)**

A "killer feature" for reading A4 PDFs on mobile screens is the removal of whitespace.

* **Algorithm (Rust):**  
  1. **Analysis:** Rust renders the page at low resolution.  
  2. **Edge Detection:** It scans the bitmap from the edges inward to find the first row/column with non-white pixels (thresholding for noise).  
  3. **Cropping:** It calculates the bounding box of the content.  
  4. **Rerendering:** The final high-res render is requested *only* for that bounding box, effectively zooming the content to fit the screen width perfectly.17

## **7\. Performance Optimization & Distribution**

### **7.1 Android Storage Access Framework (SAF)**

On Android 11+, direct file access is restricted. The app must use the **Storage Access Framework**.

* **Challenge:** Rust's standard std::fs cannot open content URIs (content://...).  
* **Solution:**  
  1. **Dart:** Uses the saf package to request the user to pick a folder.  
  2. **MethodChannel:** Dart passes the content URI to the Kotlin layer.  
  3. **File Descriptor:** Kotlin opens a ParcelFileDescriptor (PFD) from the URI and gets the raw File Descriptor (int fd).  
  4. **Rust Bridge:** This fd is passed to Rust. Rust constructs a File from this raw FD (using std::os::unix::io::FromRawFd).  
  5. **Result:** Rust can read/seek the file as if it were a normal filesystem path, completely bypassing the SAF complexity in the core logic.18

### **7.2 Binary Size and "Lighter" Footprint**

To ensure the app remains lightweight:

* **Code Stripping:** The Rust binary is compiled with strip \= true and opt-level \= "z" (optimize for size).  
* **Split APKs:** The build process generates separate APKs for armeabi-v7a (older phones) and arm64-v8a (modern phones). This prevents the user from downloading unused native libraries, saving \~10-15MB of download size.  
* **LTO:** Link Time Optimization is enabled in Cargo.toml to remove dead code across crate boundaries.

## **8\. Conclusion**

The proposed **Flutter \+ Rust Hybrid Architecture** represents the optimal solution for a high-performance, offline reading application in late 2025\. It satisfies the rigorous requirements of supporting legacy Android 7 devices while delivering modern features like 120Hz scrolling, split-screen multitasking, and complex format rendering.

By delegating the heavy computational tasks (parsing PDF/DJVU, scanning filesystems) to a memory-safe Rust backend and utilizing Flutter's Impeller engine for a reactive, consistent UI, this architecture avoids the pitfalls of standard JVM-based development. It is lighter, inherently more reliable due to Rust's safety guarantees, and "always up-to-date" through its cross-platform design. This is not merely an app; it is a portable reading runtime engine.

# ---

**Implementation Appendix: Technical Reference**

## **A. Recommended Crate Manifest (Cargo.toml)**

To implement the architecture described, the Rust backend requires a specific set of high-performance crates.

| Crate | Version (2025) | Purpose |
| :---- | :---- | :---- |
| flutter\_rust\_bridge | 2.0+ | Core communication layer (async/stream support). |
| pdfium-render | 0.9+ | PDF rendering via Google Pdfium. |
| epub | 2.1+ | Parsing EPUB metadata and content. |
| image | 0.25+ | Decoding/encoding bitmaps (PNG/JPG), resizing. |
| walkdir | 2.5+ | High-performance recursive directory scanning. |
| anyhow | 1.0+ | Flexible error handling. |
| rayon | 1.8+ | Parallel processing (for batch library updates). |
| zip | 0.6+ | Handling CBZ and EPUB containers. |
| quick-xml | 0.31+ | Fast XML parsing for DOCX. |
| tokio | 1.35+ | Async runtime for non-blocking I/O. |
| once\_cell | 1.19+ | Global static state management. |

## **B. Database Schema (Isar)**

The following schema supports the "Advanced Library Management" and "Quotes & Notes Hub" features.

| Collection | Fields | Indexing | Purpose |
| :---- | :---- | :---- | :---- |
| **Book** | id, path, title, author, format, size, hash, addedDate | Multi-entry index on title, author (FTS). Unique index on hash. | core metadata storage. |
| **ReadingProgress** | id, bookId, percentage, lastReadCfi, lastReadDate | Index on bookId. | Tracks user progress per book. |
| **Collection** | id, name, bookIds (List) | Index on name. | User-defined or smart collections. |
| **Annotation** | id, bookId, cfi, selectedText, note, color, createdDate | FTS on selectedText, note. | Stores highlights and notes. |

## **C. System Requirements & Compatibility**

| Component | Minimum Version | Notes |
| :---- | :---- | :---- |
| **Android OS** | 7.0 (Nougat) / API 24 | Min SDK version in build.gradle. |
| **Flutter SDK** | 3.24+ | Required for Impeller engine stability on Android. |
| **Rust Toolchain** | 1.82+ | Latest stable Rust. |
| **NDK Version** | r26b | Long Term Support NDK. |
| **Architecture** | ARMv7, ARM64, x86\_64 | Universal support. |

This specification provides a complete roadmap for engineering a market-leading offline reading application that stands apart from standard implementations through superior performance, reliability, and architectural elegance.

#### **Works cited**

1. What is the Performance of Flutter vs. Native vs. React-Native? \- TechAhead, accessed December 14, 2025, [https://www.techaheadcorp.com/blog/what-is-the-performance-of-flutter-vs-native-vs-react-native/](https://www.techaheadcorp.com/blog/what-is-the-performance-of-flutter-vs-native-vs-react-native/)  
2. Flutter architectural overview, accessed December 14, 2025, [https://docs.flutter.dev/resources/architectural-overview](https://docs.flutter.dev/resources/architectural-overview)  
3. Tauri or Flutter for RustDesk desktop? \#533 \- GitHub, accessed December 14, 2025, [https://github.com/rustdesk/rustdesk/discussions/533](https://github.com/rustdesk/rustdesk/discussions/533)  
4. Overview | flutter\_rust\_bridge, accessed December 14, 2025, [https://cjycode.com/flutter\_rust\_bridge/guides/performance/overview](https://cjycode.com/flutter_rust_bridge/guides/performance/overview)  
5. Using with Android \- MuPDF 1.26.3, accessed December 14, 2025, [https://mupdf.readthedocs.io/en/1.26.3/guide/using-with-android.html](https://mupdf.readthedocs.io/en/1.26.3/guide/using-with-android.html)  
6. pdfium\_render \- Rust \- Docs.rs, accessed December 14, 2025, [https://docs.rs/pdfium-render](https://docs.rs/pdfium-render)  
7. dejavu-parser \- crates.io: Rust Package Registry, accessed December 14, 2025, [https://crates.io/crates/dejavu-parser](https://crates.io/crates/dejavu-parser)  
8. Top Flutter ePUB, ePUB Reader, Ebook Reader packages | Flutter Gems, accessed December 14, 2025, [https://fluttergems.dev/epub/](https://fluttergems.dev/epub/)  
9. libmobi bindings for rust. Handles .AWZ3 & .mobi conversion used by Alexandria \- GitHub, accessed December 14, 2025, [https://github.com/btpf/libmobi-rs](https://github.com/btpf/libmobi-rs)  
10. saf | Flutter package \- Pub.dev, accessed December 14, 2025, [https://pub.dev/packages/saf](https://pub.dev/packages/saf)  
11. A Practical Guide to Using Isar Database in Your Flutter App \- DhiWise, accessed December 14, 2025, [https://www.dhiwise.com/post/isar-database-flutter-guide](https://www.dhiwise.com/post/isar-database-flutter-guide)  
12. Using Flutter Background Services: A Comprehensive Guide \- Bugsee, accessed December 14, 2025, [https://bugsee.com/flutter/flutter-background-service/](https://bugsee.com/flutter/flutter-background-service/)  
13. Simple Android foreground service in Flutter using Kotlin for non-native developers | by Ivan Burlakov | Medium, accessed December 14, 2025, [https://medium.com/@burlakovv.ivan/simple-android-foreground-service-in-flutter-for-non-kotlin-developers-31607909a633](https://medium.com/@burlakovv.ivan/simple-android-foreground-service-in-flutter-for-non-kotlin-developers-31607909a633)  
14. ColorDict Dictionary \- Apps on Google Play, accessed December 14, 2025, [https://play.google.com/store/apps/details?id=com.socialnmobile.colordict\&hl=en\_US](https://play.google.com/store/apps/details?id=com.socialnmobile.colordict&hl=en_US)  
15. Flutter for Android developers, accessed December 14, 2025, [https://docs.flutter.dev/get-started/flutter-for/android-devs](https://docs.flutter.dev/get-started/flutter-for/android-devs)  
16. docking \- Flutter package in Layout & Overlay category, accessed December 14, 2025, [https://fluttergems.dev/packages/docking/](https://fluttergems.dev/packages/docking/)  
17. smartcrop \- Rust \- Docs.rs, accessed December 14, 2025, [https://docs.rs/smartcrop2](https://docs.rs/smartcrop2)  
18. How to do file operations (create/write/update/delete files) using the Flutter "saf" Package, accessed December 14, 2025, [https://stackoverflow.com/questions/71629969/how-to-do-file-operations-create-write-update-delete-files-using-the-flutter](https://stackoverflow.com/questions/71629969/how-to-do-file-operations-create-write-update-delete-files-using-the-flutter)