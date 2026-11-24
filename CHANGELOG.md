## [1.4.5] - 2026-11-24

### Added
- **Centralized temporary cache management (`AppCacheService`).** Added an automated cache manager that calculates, budgets, and safely prunes temporary storage (`saf_cache`, `epub_media`, `mobi_media`, and `.tmp_*` files) without touching books, covers, or database records.
- **In-app storage and cache cleaner in settings.** Added a dedicated "Storage & Cache" section in `SettingsScreen` displaying real-time cache consumption with one-tap safe cleanup.
- **Reference-counted book and media resolution (`BookFileResolver`).** Added active reference tracking (`_activeRefs`, `retainMedia`, `releaseMedia`) to prevent active books or unpacked media from being pruned while open in a reader.
- **Unified HTML TTS highlighting engine (`HtmlTtsHighlightHelper`).** Unified TTS word highlighting across EPUB, MOBI, and TXT readers with multi-stage alignment, contextual n-gram disambiguation (`extractPrevWord`, `extractNextWord`), and strict sentence window bounds.
- **Layout-invariant TTS word styling (`TtsHighlightExtension`).** Replaced container wrappers and font weight changes with inline `TextStyle` decorations, preventing text shifting, glyph advance inflation, and layout jitter during speech playback.
- **Zero-geometry auto-scroll anchor.** Added a zero-dimension anchor span (`SizedBox(width: 0, height: 1)`) during continuous TTS playback, ensuring smooth automatic scrolling without line height expansion.
- **Connector-aware word boundary matching.** Added internal punctuation handling for apostrophes and hyphens, maintaining complete highlights across contractions and hyphenated words.

### Changed
- **Preserved document envelope and metadata in HTML viewers.** Updated `AnnotationHighlightHelper` and `HtmlTtsHighlightHelper` to return full `outerHtml`, preventing loss of embedded `<style>`, `<link>`, and `<head>` metadata during highlight injection.
- **Debounced reader settings sliders.** Added a 300ms debounce threshold to font size, font weight, line spacing, and paragraph spacing adjustments in `ReaderSettingsSheet` to prevent repeated reflows while dragging sliders.
- **Pre-warmed Google Fonts cache.** Added background font style pre-warming to prevent UI micro-stutters when opening typography settings.
- **Debounced theme persistence and compacted Hive boxes.** Added a 300ms write queue to `ReaderThemeRepository` and enabled box compaction on `books`, `annotations`, `settings`, and `dimensions`.
- **Scoped reader subtree rebuilds.** Isolated reader layout rebuilds with scoped `context.select` queries and `RepaintBoundary` barriers in `EpubReaderScreen`, `MobiReaderScreen`, `TxtReaderScreen`, and `HtmlReaderScreen`.
- **Tighter SAF storage budget.** Reduced default SAF cache storage in `SafHandler.kt` from 500 MB / 7 days to 50 MB / 24 hours with immediate cleanup of orphaned atomic temp files.

## [1.4.5-alpha.5] - 2026-11-24

### Added
- **Centralized Temporary Cache Management (`AppCacheService`)**: Created a dedicated service to calculate, prune, and budget temporary cache directories (`saf_cache`, `epub_media`, `mobi_media`, and atomic `.tmp_*` files) with strict safeguards preventing deletion of user books, covers, or databases.
- **Reference-Counted Temporary File & Media Resolution (`BookFileResolver`)**: Introduced static reference counting (`_activeRefs`, `_activeMediaRefs`, `retainMedia`, `releaseMedia`) ensuring temporary book files and unpacked media are never deleted while in active use by open readers or tasks.
- **Contextual Neighbor N-Gram TTS Disambiguation**: Enhanced `HtmlTtsHighlightHelper` with preceding and following word context extraction (`extractPrevWord`, `extractNextWord`) and proximity scoring to accurately disambiguate identical words across sentences and paragraphs.
- **Strict Sentence Boundary Clamping**: Bound TTS highlight matching within explicit sentence windows (`sentenceFloor`, `sentenceCeil`) across EPUB, MOBI, and TXT readers to eliminate runaway offsets and cross-sentence highlight drift.
- **In-App Cache Cleaner in Settings**: Added a "Storage & Cache" section in `SettingsScreen` showing real-time cache usage with one-tap safe cache clearing.

### Changed
- **Optimized Reader Settings Interaction & Debounced Reflows**: Debounced font size, font weight, line spacing, and paragraph spacing slider changes in `ReaderSettingsSheet` with 300ms thresholds, preventing expensive full-document re-paginations while dragging.
- **Pre-Warmed Font Style Cache**: Added background Google Fonts cache pre-warming to eliminate micro-stutters when opening text settings tabs.
- **Debounced Theme Persistence & Hive Compaction**: Added debounced write queues (300ms) to `ReaderThemeRepository` and enabled compaction strategies (`deletedEntries > 50`) across Hive boxes (`books`, `annotations`, `settings`, `dimensions`).
- **Selective Reader Subtree Rebuilds**: Replaced full repository watchers with scoped `context.select` and isolated `RepaintBoundary` barriers in `EpubReaderScreen`, `MobiReaderScreen`, `TxtReaderScreen`, and `HtmlReaderScreen`.
- **Tighter SAF Cache Quotas**: Reduced default SAF cache budget in `SafHandler.kt` from 500 MB / 7 days to 50 MB / 24 hours with immediate cleanup of orphaned atomic temp files.

## [1.4.5-alpha.4] - 2026-11-23

### Added
- **Full Document Envelope & Head Preservation**: Added detection for `<!doctype>`, `<html>`, and `<head>` tags in both `AnnotationHighlightHelper` and `HtmlTtsHighlightHelper`, returning `document.outerHtml` instead of truncating to `root.outerHtml`.

### Changed
- **Preserved Reader Stylesheet & Metadata**: Ensured injected annotation spans and TTS word highlights retain embedded `<style>`, `<link>`, and `<meta>` elements across HTML reader documents.
- **Updated Release Download Metrics**: Refreshed the E-Ink halftone trajectory chart to reflect recent milestone downloads.

## [1.4.5-alpha.3] - 2026-11-22

### Added
- **Layout-Metrics Invariant TTS Highlighting (`TtsHighlightExtension`)**: Created a centralized inline `TagExtension` builder for `tts-highlight` tags across EPUB, MOBI, TXT, and DOCX readers that styles words exclusively via `TextStyle` properties (`backgroundColor`, `color`, `decoration`).
- **Zero-Geometry Auto-Scroll Anchor**: Integrated a zero-dimension anchor `WidgetSpan` (`SizedBox(width: 0, height: 1)`) exclusively during continuous-mode playback to maintain `Scrollable.ensureVisible` auto-scrolling without introducing line-height dilation or paragraph reflow.
- **Single-Key Frame Attachment Guard**: Added per-frame attachment tracking to prevent duplicate `GlobalKey` assertions when multiple highlight instances occur within a single render pass.

### Changed
- **Eliminated Layout Jitter & Text Shifting**: Replaced `Container`-based highlight wrappers and font-weight alterations with pure inline text styling, preventing glyph advance inflation and word jitter during TTS speech.
- **Unified Formatting Pipeline Extraction**: Standardized chunk HTML formatting across `EpubContentViewer`, `MobiContentViewer`, and `TxtContentViewer` with unified `_formatContinuousChunkHtml` and `_formatPageSliceHtml` methods.
- **Cleaned Redundant Highlight Widgets**: Removed obsolete `_TtsHighlightSpan`, `_EpubTtsHighlightSpan`, `_MobiTtsHighlightSpan`, and `_TxtTtsHighlightSpan` implementations across all content viewers.

## [1.4.5-alpha.2] - 2026-11-22

### Added
- **Paging-Strict TTS Offset Resolution**: Added `strictWindow` mode to `TextOffsetResolver` to enforce tighter page-boundary n-gram matching and prevent whole-chapter fallback jumps when reading in paged mode.
- **Active Page Slice Bounds Seeding in TXT Paged Mode**: Linked `TxtPagedViewer` to `ChapterController.setActivePageBounds` to provide accurate slice character bounds during paginated TXT reading.
- **Connector-Aware Word Boundary Snapping**: Enhanced `HtmlTtsHighlightHelper` to treat apostrophes (`'`, `’`, `‘`) and hyphens (`-`, `\u2011`) as internal word connectors, preventing clipped or fragmented highlights on contractions and compound words.

### Changed
- **Speaking Chapter Key Alignment**: Updated `EpubContentViewer`, `MobiContentViewer`, and `TxtContentViewer` to assign the TTS highlight scroll key strictly to `speakingChapterIndex`, preventing false scroll targets during chapter transitions.
- **Dynamic Live Extensions in Content Viewers**: Extracted `_buildExtensions` in HTML content viewers to ensure live reader themes and highlight styles update immediately during active TTS playback.
- **Race-Free Speech Rate Restarts**: Added monotonic `_rateRestartId` tracking and comprehensive debounce timer cleanup in `TtsService` to eliminate duplicate audio speech loops and race conditions during rapid speech rate adjustments.
- **Paginator Plain Text Measurement Alignment**: Aligned `SafeScreenPaginator` plain text extraction with standard DOM length to maintain consistent slice measurement.

## [1.4.5-alpha.1] - 2026-11-22

### Added
- **Centralized HTML TTS Highlighting Engine**: Created `HtmlTtsHighlightHelper` to unify TTS highlight injection across EPUB, MOBI, and TXT readers with resilient multi-stage word alignment (exact, local search window, whole-node distance, and word boundary snapping).
- **Dynamic TXT Reader TTS Highlighting**: Implemented reactive TTS word highlighting in `TxtContentViewer` for both continuous scrolling and discrete paged reading modes.
- **Debounced Speech Rate Adjustment & Instant Resume**: Added debounced rate updates during slider drag with seamless in-place chunk audio restarting upon release, avoiding speech cancellation or restarts from beginning.

### Changed
- **Cross-Chapter TTS Sync Guard**: Introduced `speakingChapterIndex` across EPUB, MOBI, and TXT TTS controllers to prevent false page jumps and phantom highlight rendering across chapter boundaries.
- **Accurate Paged Slice Offset Clamping**: Updated slice character offset clamping in content viewers to use explicit slice character length rather than raw HTML length.
- **Paginator Soft-Hyphen Text Length Preservation**: Fixed `SafeScreenPaginator` block part character length measurement to preserve soft hyphens, ensuring 1:1 character index parity between paginated slices and TTS highlighting.

## [1.4.4] - 2026-11-21

### Added
- **Fast Binary Image Header Probing**: Implemented sub-microsecond binary header probing in `SafeScreenPaginator` for PNG, GIF, JPEG, and WebP images, extracting dimensions without decoding full bitmaps into memory.
- **Dominant Gesture Recognizer for Page Turns**: Implemented `_DominantHorizontalDragGestureRecognizer` with responsive touch slop (~4.0px) in `RealisticPageTurn`, winning the gesture arena over child `SelectableRegion` gestures on touchscreen devices.
- **Selection-Aware Swipe Guard**: Added `canSwipe` guard to `EpubPagedViewer`, `MobiPagedViewer`, and `TxtPagedViewer` to yield horizontal gestures when active text selection is present, ensuring text handles can be dragged freely.
- **MOBI & EPUB Explicit Page Break Normalization**: Added Rust-level regex normalization and Dart DOM sanitization for `<mbp:pagebreak>`, `<pagebreak>`, and `<pb>` tags into `.ferrous-pagebreak` elements, forcing discrete chapter page flushes in `SafeScreenPaginator`.
- **Pre-Warmed Slot Layering for Realistic Page Turn**: Overhauled `RealisticPageTurn` with deferred offscreen element mounting, eliminating drag tracking frame drops and transparent page bleed-through during 120Hz turns.

### Changed
- **Paged Viewer Slicing Architecture**: Replaced `SingleChildScrollView` with `ClipRect` + `OverflowBox` in `EpubPagedViewer`, `MobiPagedViewer`, and `TxtPagedViewer` to eliminate scroll artifacts and guarantee exact vertical slice rendering.
- **Gesture Disambiguation & Debounced Chrome**: Implemented a 280ms toggle timer and tap margin isolation across EPUB, MOBI, and TXT readers to cleanly separate margin page turns, center chrome toggling, and double-tap actions.
- **Adaptive Canvas Headroom for Publisher Styles**: Expanded reserve headroom calculation in `SafeScreenPaginator` to double line height when publisher CSS is present, preventing outer margin accumulation overflow.
- **Publisher Style Font-Size Normalization**: Normalized relative `em`, `rem`, `%`, and `pt` units within embedded `<style>` sheets directly against user base font size in EPUB and MOBI content viewers.
- **Default Publisher Styles Preference**: Set default `usePublisherStyles` configuration to `false` in `ReaderThemeConfig` to favor clean user typography out-of-the-box.
- **Page Turn Velocity Curve & Quick-Flick Recovery**: Added fast-path fling recovery and velocity-weighted animation duration scaling in `RealisticPageTurn` for fluid page turns on fast swipes.
- **Swipe Initiation Sensitivity**: Lowered initial drag detection threshold from 2.0px to 1.5px and incremental delta from 1.0px to 0.5px for immediate curl feedback.
- **Realistic Page Turn Gesture Responsiveness**: Added explicit mounted state synchronization during drag transitions and optimized offscreen slot visibility to discard inactive animation tickers.
- **Paged Viewer Slice Null Safety**: Added defensive null slice checks in `EpubPagedViewer` and `MobiPagedViewer` page builders.

## [1.4.3] - 2026-11-20

### Highlights
- **Publisher Styles & Advanced Layout Engine (EPUB & MOBI)**: Comprehensive CSS rule resolver with unit-aware font scaling, lateral box model parsing, line-snapped canvas bounds, and split-tail justification.
- **PDF Visual Render Preemption (120Hz Scrolling)**: Atomic `ActiveVisualRenderGuard` in Rust prioritizes visual page renders over background text parsing for butter-smooth scrolling.
- **Direct Single & Multi-File Document Import**: Instant file import via `ACTION_OPEN_DOCUMENT` with auto-launch, SAF quota management, and deduplication.
- **Bookshelf Contextual Multi-Select & Batch Operations**: High-performance batch deletion and bulk collection assignment across all 8 bookshelf views.
- **Theme & Contrast Polish**: Standardized text colors across EPUB, MOBI, TXT, and HTML viewers with active theme `onSurface` and paper texture support.

<details>
<summary><b>Detailed Changes & Architectural Refinements</b></summary>

#### EPUB & MOBI Layout & Pagination
- **CSS Font-Size Scale Parsing**: Extended `CssRuleResolver` with unit-aware `font-size` parsing (`%`, `em`, `rem`, `px`, `pt`), resolving dynamic `fontSizeScale` (clamped 0.5x–3.0x) on `ResolvedCssRule`.
- **Preformatted Code `<pre>` Monospace Support**: Added monospace font family fallback and proportional text scaling for `<pre>` elements in `SafeScreenPaginator`, `EpubContentViewer`, and `MobiContentViewer`.
- **Semantic Container Margin Neutralization**: Zeroed out external margins and paddings (`!important`) on `<article>`, `<section>`, and `<main>` tags in `SafeScreenPaginator` to prevent unwanted outer margin offset accumulation.
- **Ancestor Margin Reset Across Page Slices**: Enforced zero margins and paddings with `!important` on open ancestor tags across page breaks to maintain strict vertical alignment continuity.
- **Reader Font-Family & Line-Height Priority**: Stripped publisher `body` `font-family` and `line-height` declarations in `EpubContentViewer` and `MobiContentViewer` to ensure user typography choices take full precedence.
- **Typography Cache Invalidation**: Added `fontFamily` and `lineHeight` parameters to HTML formatting and chunk cache key signatures across EPUB and MOBI viewers to prevent stale typography renders.
- **List Item Spacing & Structure**: Added standard left padding (24px) for `<ul>` / `<ol>` and bottom margins (4px) on `<li>` in EPUB and MOBI content viewers.
- **Vertical Box Model & Typography Parsing**: Extended `CssRuleResolver` with 1-4 value box shorthand parsing (`_resolveBoxTerms`), resolving `marginTop`, `marginBottom`, `paddingTop`, and `paddingBottom` (in both `px` and `em`), alongside AST-level `font-weight` and `font-style` inheritance.
- **Intrinsic Font Line Height & Safety Headroom**: Added `TextPainter` line-box probing in `SafeScreenPaginator` to measure true intrinsic font metrics, snapping canvas bounds with a `singleLineHeight + 4.0` headroom reserve to eliminate subpixel bottom overflow.
- **Split Tail Justification (`<page-split-tail>`)**: Implemented dynamic inline `<page-split-tail>` tag extensions across EPUB, MOBI, and TXT viewers with computed word spacing to seamlessly expand broken lines to 100% block width when text is justified.
- **Unified Viewer Text Styles**: Wrapped rendered HTML chunks in `Theme` and `DefaultTextStyle` inheriting `resolvedTextStyle` to ensure 1:1 metric parity between paginator measurements and screen rendering.
- **Relative Font-Size Normalization**: Normalized relative `em` and `%` font sizes in publisher stylesheets directly against base `fontSize` (in px) across `EpubContentViewer` and `MobiContentViewer`, preventing nested inheritance double-scaling in `flutter_html`, and added `fontSize` to chunk cache keys.
- **CSS AST Term & Expression Unpacking**: Enhanced `CssRuleResolver` to unpack compound expressions and resolve `PercentageTerm`, `EmTerm`, `RemTerm`, and `LengthTerm` (`pt`/`px`) directly for accurate margins, padding, and font scaling.
- **Orphan Page Content Preservation**: Updated `SafeScreenPaginator` to merge trailing near-empty chapter slice HTML directly into the preceding page instead of dropping it, eliminating content loss.
- **Paginator Budget & Strut Cleanups**: Removed restrictive `StrutStyle` overrides and synthetic budget height inflation, measuring exact block heights and snapping splits to visible hyphens (`-`, `‐`, `—`).
- **Soft Hyphen Stripping & Word Severing Fix**: Simplified `smartHyphenateText` to sanitize soft hyphens (`\u00AD`) without aggressive algorithmic word breaking, preventing words from severing mid-syllable without visible hyphens.
- **Relative Em Margin & Padding Resolution**: Added support for `em` units in `CssRuleResolver` for lateral margins and padding, dynamically computing insets against `effectiveFontSize` for responsive publisher formatting.
- **Honorific Abbreviation Protection**: Integrated `_abbreviationEndingRegex` in `HtmlDefragmenter` for honorifics (`Mr.`, `Mrs.`, `Dr.`, `Prof.`, etc.) to prevent improper sentence splitting and merging.
- **System Text Scaling Isolation**: Enforced `TextScaler.noScaling` across `SafeScreenPaginator`, `EpubContentViewer`, and `MobiContentViewer`, preventing double-scaling discrepancies from device OS text size settings.
- **Bottom Glyph Slicing Safety Reserve**: Snapped `SafeScreenPaginator` canvas bounds with a single-line safety reserve to completely eliminate half-glyph bottom clipping.
- **Document Metadata & Style Preservation**: Maintained `<head>`, `<style>`, and DOCTYPE structure in `HyphenationHelper` to ensure publisher stylesheets remain intact after hyphenation.
- **CSS Rule Resolver**: Integrated `csslib` and built `CssRuleResolver` AST parser to extract chapter stylesheet rules, supporting element tags, classes, and combined selectors.
- **Lateral Insets & Ancestor Propagation**: Accurately computes horizontal margins and paddings with recursive ancestor summation for nested elements like blockquotes, epigraphs, and poetry.
- **Dynamic Text Width & Paginator Layout**: Adapted `SafeScreenPaginator` to measure text height against effective block width (`availableWidth - lateralInsets`), preventing overflow in indented publisher layouts.
- **Publisher Styles Toggle**: Added a user toggle under Reader Settings (Layout tab) to switch between strict publisher formatting and clean user-defined typography.
- **Hyphenation & Indent Preservation**: Updated `HyphenationHelper` to honor publisher CSS text indentation and alignment rules dynamically.
- **Font-Size Normalization**: Normalized CSS keyword and fixed `px`/`pt` font sizes into clamped relative `em` multipliers (0.70em–2.0em) to prevent extreme text sizing from publisher stylesheets.
- **Line-Snapped Canvas Bounds**: Snapped `SafeScreenPaginator` canvas heights to integer line multiples (`wholeLineCount * singleLineHeight`), eliminating bottom half-line glyph slices across EPUB and MOBI layouts.
- **Orphan Page Elimination**: Automatically merges or drops trailing near-empty chapter slices (< 25 characters without media) to avoid single-line orphan final pages.
- **Narrative Prose Detection**: Added `_stampProseMarkers` to distinguish standard body paragraphs from non-narrative elements (headings, epigraphs, blockquotes, media), ensuring reader justification and indent settings apply cleanly without distorting publisher formatting.
- **Line Height Sanitization & UI Polish**: Added `sanitizeLineHeight` (clamped between 1.0x and 2.2x, default 1.4x), modernized reader settings slider with multiplier labels (`1.40x`), and wrapped settings sheet in `SafeArea` with responsive constraints.

#### PDF Engine & Concurrency
- **Active Visual Render Priority**: Implemented an atomic `ActiveVisualRenderGuard` pipeline in the Rust PDF engine. Background text sanitization and bounds extraction jobs yield every 50 characters and abort (`PREEMPTED_BY_VISUAL_RENDER`) during user scrolling, eliminating lock contention and ensuring rock-solid 120Hz rendering.
- **Resilient TTS Preemption Recovery**: Integrated automatic backoff retries in `PdfTtsController` when text extraction yields to interactive visual page renders.
- **Single-Concurrency Native Render Queue**: Serialized native PDF page rendering to `_maxConcurrentNativeRenders = 1` in `PdfPageController`, preventing GPU memory pressure and raster contention.
- **32ms Deferred GPU Image Disposal**: Replaced post-frame callbacks in `PdfGpuImageCache` with 32ms deferred disposal, preventing texture invalidation during active frame rasterization.
- **Inner Page Image Hit Testing**: Added `pageImageKeys` per-page image GlobalKeys for pixel-perfect tap detection and viewport coordinate translation.
- **Tight Character Bounds**: Switched PDF glyph boundaries to native PDFium `tight_bounds()` for pinpoint text highlight and selection alignment.
- **Memory-Tuned Texture Dimension**: Capped texture generation to 1600px, reducing memory consumption while maintaining razor-sharp rendering on high-DPI devices.

#### Storage Import & Bookshelf Management
- **Dedicated Import Flows**: Split generic add dialog into distinct, purpose-built workflows for adding individual books versus configuring monitored folders.
- **Theme-Aware Storage Mode Dialog**: Created `StorageModeDialog` with full support for Light, Dark, Console, and authentic E-Ink themes (Roboto Slab, sharp 2px radii, high-contrast borders, hard drop shadows).
- **Streamlined Dialog Layout**: Positioned Cancel and confirmation buttons side-by-side with responsive action cards and tactile haptic feedback.
- **Single & Multi-File Direct Document Import**: Added ability to pick and import individual ebook files via `ACTION_OPEN_DOCUMENT` rather than requiring whole-directory grants.
- **Immediate Reader Launch**: Opening a single file automatically transitions into `ReaderScreen` without manual shelf navigation, while multi-file selections batch import with progress summaries.
- **SAF Running Quota & Permission Management**: Dynamically monitors Android 128/512 persisted URI grant limits during multi-file selection with automated fallback to internal storage copying, and releases document-level grants upon deletion.
- **Import Deduplication & Orphan File Prevention**: Reuses existing book entities for repeated imports and cleans up redundant temporary internal storage copies.
- **Contextual Selection Mode**: Added multi-select mode across all 8 bookshelf view modes and high-contrast E-Ink themes, accessible via long-press or the library menu.
- **Selection Action Bar & Back Navigation**: Integrated contextual app bar with Select All / Deselect All, dynamic selection counts, `PopScope` hardware back gesture handling, and single-book "More Options" menu access for compact grid cards.
- **Atomic Batch Deletion Pipeline**: Implemented bulk deletions in `BookRepository`, `CollectionRepository`, and `AnnotationRepository` with sequenced external document deletion, grant release, and a single UI notification pass.
- **Bulk Collection Assignment**: Added ability in library selection mode to assign or remove multiple selected books to/from collections simultaneously.
- **Inline Collection Creation**: Implemented quick collection creation directly within the assignment sheet without navigating away.
- **Zero-Latency Storage Mode Selection**: Eliminated micro-stutters and tap latency across storage mode option cards.
- **F-Droid Recipe Synchronization**: Synchronized `fdroid/com.juansofly.ferrous.yml` and Fastlane release changelog tracking stable build metadata.

</details>

## [1.4.2] - 2026-11-17

### Continuous PDF Scrolling & Viewport Anchoring
- **Precision Page Anchoring & Scroll Restoration**: Replaced naive scroll restoration with a multi-frame retry mechanism (`_anchorToContinuousPage`) that deterministically aligns the target page's top edge to the viewport top upon opening a document or toggling reading modes.
- **RenderBox & Aspect-Ratio Jump Navigation**: Upgraded `jumpToPage` in continuous modes to compute exact pixel offsets via mounted RenderBox coordinates or cumulative aspect-ratio extents, eliminating inaccurate fixed-extent approximations.
- **Bounded Active Page Search**: Restricted `_updateActivePageFromScroll` to a localized window around the estimated page index (`[searchStart, searchEnd]`) rather than iterating every document page on every scroll tick.
- **Aspect-Ratio Locked Vertical Continuous List**: Wrapped vertical continuous pages in `AspectRatio` constraints within `ListView.separated` with increased cache extent (`2x viewport height`), preventing layout jumps during dynamic bitmap loading.
- **Jitter-Free Continuous Rendering**: Suppressed redundant `setState` and controller syncs during continuous scrolling in `_onPageControllerChanged`, and unified `RepaintBoundary` and `KeyedSubtree` handling across placeholder and rendered page layers.
- **Expanded Continuous GPU Cache**: Tuned resident continuous GPU texture cache to 12 pages for smooth, uninterrupted fast scrolling.

### Modular Plain Text (TXT) Reader Engine
- **Native Encoding Auto-Detection**: Integrated `chardetng` and `encoding_rs` in the Rust backend to automatically detect legacy character encodings (Shift-JIS, GBK, Windows-1252, ISO-8859, etc.) and losslessly transcode text into clean UTF-8.
- **Dynamic Chapter Splitting & Markdown Parsing**: Segmented plain text into discrete chapters using natural heading patterns and size thresholds, with rich rendering support for markdown headings, blockquotes, code blocks, checklists, and Mermaid diagram embeds.
- **Dedicated TXT Reader Architecture**: Added `TxtReaderScreen` with paged and continuous viewers (`TxtPagedViewer`, `TxtContinuousViewer`, `TxtContentViewer`), page-curl animations, tap navigation, text selection, and typography customization.
- **Synchronized TXT TTS Engine**: Implemented `TxtTtsController` with word- and sentence-level highlight tracking, continuous cross-chapter audio playback, and tap-to-speak interaction.

### Native PDFium Outline & Table of Contents
- **Native C++ Bookmark Extraction**: Implemented `getPdfOutline` in Rust using native PDFium outline APIs, running in < 3ms with full support for compressed object streams (`/ObjStm`), hierarchical bookmark trees, and parent page inheritance.
- **Interactive PDF Table of Contents Sheet**: Added `PdfTableOfContentsSheet` modal with hierarchical indentation, active chapter tracking, auto-scrolling to the current chapter, and one-tap jump navigation.

### High-Performance PDF Render Pipeline & Viewport Stability
- **Raw RGBA Direct GPU Textures**: Switched PDF page rendering in Rust to raw RGBA bytebuffers directly from PDFium under granular per-document locks, eliminating encoding bottlenecks.
- **Distance-Prioritized Render Queue**: Replaced naive prefetching in `PdfPageController` with an asynchronous render queue that prioritizes pages closest to the viewport.
- **Epoch-Guarded Render Cancellation**: Implemented atomic render epochs in Rust and Dart to immediately abort obsolete background renders during rapid page navigation while preserving adjacent page renders.
- **Layout Aspect-Ratio Locking**: Constrained horizontal and vertical page items with exact PDF point dimensions extracted from Rust, eliminating viewport jitter and layout shifts during scrolling.
- **Resident GPU Image Cache**: Integrated LRU `PdfGpuImageCache` with post-frame deferred disposal, preventing flickering and frame drops.

### Synchronized Word & Sentence PDF TTS
- **Word-Level Glyph Tracking**: Added live TTS word boundary tracking in `PdfTtsController` synchronized with sanitized Rust text offsets (`clean_to_pdf_map`), delivering drift-free highlighting across multi-column PDF layouts.
- **Lazy Text Extraction**: Deferred PDF sentence extraction to trigger strictly on demand when audio controls are opened.

### HTML/EPUB DOM Normalization & Reader Stability
- **In-Place DOM Text Normalization**: Overhauled `SafeScreenPaginator` with anonymous inline run aggregation and text measurement, preventing whitespace collapse across inline formatting boundaries (e.g. `<i>...</i>`).
- **Anchor & Media Preservation**: Retained standalone media tags (`img`, `svg`, `video`), bookmark anchor targets (`<a id="...">`), and spacer lines without generating blank page slices.
- **Atomic SAF File Staging**: Staged Android SAF caching via temporary files (`.tmp_<timestamp>`) in `SafHandler` with atomic renaming to protect against partial reads.
- **Unified Text Selection**: Standardized `ReaderSelectionController` and `ReaderSelectionMenuBuilder` across EPUB, MOBI, TXT, and HTML readers.

## [1.4.2-alpha.4] - 2026-11-16

### Continuous PDF Scrolling & Viewport Anchoring
- **Precision Page Anchoring & Scroll Restoration**: Replaced naive scroll restoration with a multi-frame retry mechanism (`_anchorToContinuousPage`) that deterministically aligns the target page's top edge to the viewport top upon opening a document or toggling reading modes.
- **RenderBox & Aspect-Ratio Jump Navigation**: Upgraded `jumpToPage` in continuous modes to compute exact pixel offsets via mounted RenderBox coordinates or cumulative aspect-ratio extents, eliminating inaccurate fixed-extent approximations.
- **Bounded Active Page Search**: Restricted `_updateActivePageFromScroll` to a localized window around the estimated page index (`[searchStart, searchEnd]`) rather than iterating every document page on every scroll tick.
- **Aspect-Ratio Locked Vertical Continuous List**: Wrapped vertical continuous pages in `AspectRatio` constraints within `ListView.separated` with increased cache extent (`2x viewport height`), preventing layout jumps during dynamic bitmap loading.
- **Jitter-Free Continuous Rendering**: Suppressed redundant `setState` and controller syncs during continuous scrolling in `_onPageControllerChanged`, and unified `RepaintBoundary` and `KeyedSubtree` handling across placeholder and rendered page layers.
- **Expanded Continuous GPU Cache**: Tuned resident continuous GPU texture cache to 12 pages for smooth, uninterrupted fast scrolling.

### Modular TXT Reader Engine & Encoding Auto-Detection
- **Native Encoding Detection**: Integrated `chardetng` and `encoding_rs` in the Rust backend to automatically detect legacy character sets (Shift-JIS, GBK, Windows-1252, ISO-8859, etc.) and losslessly transcode plain text documents into clean UTF-8.
- **Dynamic Chapter Splitting & Markdown Parsing**: Overhauled `read_txt` in Rust to segment plain text into discrete chapters based on natural chapter heading patterns, roman numerals, or size thresholds. Added support for markdown headings, blockquotes, code fences, Mermaid diagram embeds, checkboxes, and lists.
- **Dedicated TXT Reader Architecture**: Refactored `TxtReaderScreen` into a full-featured modular reader with `TxtChapterController` for asynchronous chapter paging and reading progress tracking.
- **Synchronized TXT TTS Engine**: Implemented `TxtTtsController` with sentence and word-level highlight tracking, continuous cross-chapter audio flow, and tap-to-speak interaction.
- **Paged & Continuous Viewers**: Added `TxtContentViewer`, `TxtContinuousViewer`, and `TxtPagedViewer` supporting page flip animations, page curls, margin tuning, and reading themes.

### Prioritized PDF Render Queue & Viewport Stability
- **Distance-Prioritized Render Queue**: Replaced naive eager page prefetching in `PdfPageController` with an asynchronous render queue (`_drainRenderQueue`) that dynamically sorts pending page requests by proximity to the active viewport, ensuring visible pages render first.
- **Intelligent Epoch Cancellation**: Guarded epoch aborts in `requestPageRender` so rapid adjacent page turns (within 1 page) preserve active rendering jobs while immediately cancelling distant obsolete renders.
- **Dynamic GPU Cache Sizing**: Expanded resident `PdfGpuImageCache` capacity to 16 pages for continuous scroll modes and 8 pages for paged modes, with post-frame deferred disposal preventing frame drops.
- **Layout Aspect Ratio Locking**: Wrapped horizontal page items in `PdfPageViewer` with exact aspect-ratio constraints derived from Rust-extracted PDF point dimensions, eliminating viewport shifts during scroll gestures.

### Per-Document PDF Concurrency & PDFium Safety
- **Granular Per-Document Execution Locks**: Replaced the global PDFium execution lock in Rust with per-document serialization (`DocumentEntry`), allowing multi-document operations and global concurrency without thread blocking.
- **Pathological Outline Traversal Bounds**: Added `MAX_SIBLINGS_PER_LEVEL` (500) and `MAX_TOTAL_OUTLINE_ITEMS` (2000) caps to native PDFium bookmark parsing to prevent infinite loops and memory spikes.
- **Zero-Copy Raw Byte Rendering**: Switched bitmap byte retrieval to raw bytes for optimal texture upload performance.

### SAF Caching Atomicity & File Integrity
- **Atomic File Streaming**: Implemented temporary file staging (`.tmp_<timestamp>`) in `SafHandler` for Android SAF caching, verifying non-zero stream writes before atomic renaming to prevent concurrent readers from accessing partial or 0-byte cache files.

### Reading Progress Guards & Controller Optimizations
- **Progress Corruption Protection**: Guarded `BookRepository` and `PdfPageController` against resetting `totalPages` to 0, clamping `currentPage` within valid page ranges.
- **Event-Driven Page Render Completers**: Replaced polling intervals with `Completer<void>` render listeners for deterministic, zero-latency page transitions.
- **Tuned GPU Texture Caching**: Adjusted resident GPU cache limits to 8 (continuous) and 4 (paged) to prevent memory pressure on constrained devices.
- **Lazy PDF TTS Sentence Extraction**: Deferred TTS sentence loading to trigger strictly when audio playback or controls are active.
- **Robust Realistic Page Turn Clamping**: Added zero-page guards in `RealisticPageTurn` to eliminate negative bounds crashes on empty documents.

## [1.4.2-alpha.3] - 2026-11-16

### Native PDFium Outline & Bookmarks Engine
- **Native C++ Bookmark Extraction**: Implemented `getPdfOutline` in Rust using native PDFium outline APIs, replacing Dart-side regex parsing. Runs in < 3ms with full support for compressed object streams (`/ObjStm`), hierarchical bookmark trees, and automatic parent page inheritance.
- **Service Integration**: Updated `PdfOutlineService` to delegate directly to the Rust backend, delivering instant bookmark extraction without isolate serialization overhead.

### Direct GPU Texture Pipeline & Zero-Copy PDF Rendering
- **Raw RGBA GPU Textures**: Updated PDF page renderer to output raw RGBA bytebuffers and corner color profiles directly from PDFium under a strict execution lock and global render epoch guard.
- **Epoch-Guarded Render Cancellation**: Added `expected_epoch` to `render_pdf_page` in Rust with atomic `increment_render_epoch`, instantly aborting obsolete background renders during rapid page navigation.
- **Page Geometry & Aspect Ratio Propagation**: Expanded `PdfPageRenderResult` with point dimensions and aspect ratios (`aspect_ratio`, `page_width_pt`, `page_height_pt`), enabling layout sizing without reading delays.
- **PdfGpuImageCache**: Added LRU resident GPU `ui.Image` cache with post-frame deferred disposal in `PdfPageController`, eliminating JPEG/PNG encoding overhead and flickering on cache hits.
- **Modular PdfPageViewItem**: Extracted `PdfPageViewItem` in `PdfPageViewer` with aspect-ratio-locked placeholder geometry and corner-color placeholders, preventing viewport shifts and render tree detachment.
- **Viewport Jitter Debouncing**: Added threshold checks in `updateViewportSize` to ignore minor layout resize events (<10%) and clamped device pixel ratio to prevent redundant re-renders.

### Real-Time Word & Sentence PDF TTS Synchronization
- **Sanitized Text Extraction with Offset Mapping**: Implemented `extract_sanitized_page_text` in Rust with guarded de-hyphenation and UTF-16 code unit mapping (`clean_to_pdf_map`).
- **Word-Level Highlight Tracking**: Added active `_ttsService` word boundary listener in `PdfTtsController`, translating live spoken word offsets directly to PDFium glyph bounds with zero visual drift.

### DOM Pagination Normalization & Inline Style Preservation
- **In-Place DOM Text Normalization**: Added `_normalizeBlockTextNodes` and `_measureNormalizedNodeLength` in `SafeScreenPaginator`, preventing whitespace collapse across inline formatting boundaries (e.g. `<i>...</i>`).
- **Orphan Line & Indent Protection**: Enhanced block splitting to prevent 1-line orphan splits and preserved `<p-indent>` and `<br>` elements during pagination slicing.

## [1.4.2-alpha.2] - 2026-11-16

### HTML & EPUB Pagination Engine Overhaul
- **Inline Run Aggregation**: Re-architected `SafeScreenPaginator` to measure and group contiguous inline text nodes and elements into anonymous container blocks, preventing fragmentation of styled inline text and eliminating erroneous page overflows.
- **Replaced Element & Anchor Preservation**: Added detection for standalone media tags (`img`, `svg`, `canvas`, `video`) and preserved empty anchor bookmarks (`<a id="...">`) and `<br>` spacer line metrics without discarding them during pagination.

### PDF Continuous Scroll & Navigation Synchronization
- **Scroll Restore Locking**: Added `_isRestoringScroll` lifecycle guard in `PdfPageController` to suppress redundant scroll listeners and prevent progress saves from corrupting stored offsets during restoration.
- **Direct Jump Navigation**: Implemented `jumpToPage` across both paged and continuous (vertical, horizontal, webtoon) modes with layout-aware offset calculations.
- **E-Ink Adaptive Background Optimization**: Enhanced `CbzAdaptiveBackground` with static fallback rendering for E-Ink themes, reducing redraw costs.

### Reactive Table of Contents & Outline Integration
- **Dynamic Controller Binding**: Bound `PdfTableOfContentsSheet` directly to `PdfPageController` to reactively render bookmarks as they finish loading asynchronously in the background.
- **Loading & Empty State Feedback**: Added dedicated progress spinners and empty outline messaging, along with auto-scrolling to active chapters with E-Ink color tokens.

### Text Selection & Page Turn Stability
- **Stable Continuous Selection Key**: Added memoized `'continuous-viewport'` selection key to `ReaderSelectionController` for continuous EPUB and MOBI reading, preventing state thrashing when crossing chapter boundaries.
- **RealisticPageTurn Chapter Synchronization**: Added `chapterIndex` tracking and deferred page change notification in `RealisticPageTurn` to eliminate cache desync and render tree detachment during rapid chapter flips.
- **TTS Concurrency & Cleanup**: Eagerly loaded page text and character bounds in parallel within `PdfTtsController` while deduplicating in-flight sentence segmentation requests and ensuring listener cleanup on disposal.

## [1.4.2-alpha.1] - 2026-11-16

### PDF Outline Extraction & Table of Contents
- **PdfOutlineService Engine**: Implemented `PdfOutlineService` to parse document bookmarks, chapter titles, and destination page indices directly from PDF file bytes with regex matching, offloading files larger than 500KB to a background isolate via `compute`.
- **Interactive PDF Table of Contents Sheet**: Added `PdfTableOfContentsSheet` draggable modal with hierarchical indentation, active chapter tracking, auto-scrolling to the current chapter, and jump-to-page navigation with dedicated E-Ink styling.
- **Top Bar Integration**: Replaced the legacy snippet text picker sheet with a prominent Table of Contents action in `PdfReaderTopBar`.

### Dedicated Sentence-Level PDF TTS Controller
- **Precomputed Sentence Geometry**: Introduced `PdfSentence` data model mapping character ranges, clean normalized text, and precomputed `PdfTextRect` bounding boxes per page.
- **Line-by-Line Multi-Column Highlighting**: Refactored `PdfTtsController` for gutter-safe sentence highlighting across complex multi-column PDF layouts without canvas jitter.
- **Zero-Drift Position Tracking**: Eliminated aggressive viewport auto-zooming during speech playback and guaranteed rock-solid reading position persistence across page transitions.

### Unified Text Selection Architecture
- **ReaderSelectionController**: Introduced a unified `ReaderSelectionController` managing memoized per-page and continuous `SelectionArea` state keys, active selection state tracking, and programmatic selection clearing.
- **ReaderSelectionMenuBuilder**: Extracted a standardized `ReaderSelectionMenuBuilder` constructing adaptive text selection toolbars with sanitized 'Copy' and 'Annotate' actions across EPUB, MOBI, and HTML readers.
- **Component Decoupling**: Streamlined selection state across `EpubReaderScreen`, `MobiReaderScreen`, `HtmlReaderScreen`, and viewer widgets, eliminating redundant selection code.

### Gesture, Zooming & Reader Viewport Improvements
- **Floating Unlock Control**: Added a timed floating unlock button with 3.5s fade-out in `PdfReaderScreen` when tapping a locked screen, preventing accidental navigation.
- **Multi-Touch Pinch-to-Zoom Tracking**: Enhanced `PdfPageViewer` pointer event tracking for smooth zooming, panning, and interaction stability.
- **RealisticPageTurn Isolation**: Added `canSwipe` predicate to `RealisticPageTurn` and wrapped active page layers with `IgnorePointer` during curls to isolate pointer events and prevent accidental gesture triggers.
- **Memory & GPU Cache Eviction**: Added active `ImageProvider` tracking with explicit `.evict()` calls in `PdfPageController` to guarantee immediate GPU texture deallocation upon cache eviction.

## [1.4.1] - 2026-11-16

### Text Selection Lifecycle & Gesture Conflict Resolution
- **Tap-to-Dismiss Selection**: Added `onTryDismissSelection` handlers across `EpubPagedViewer`, `MobiPagedViewer`, `RealisticPageTurn`, and continuous scroll viewers so tapping anywhere on the screen dismisses active text highlights and hides the contextual toolbar without accidentally flipping pages or toggling reader chrome.
- **Synchronous Selection Cleanup**: Integrated `onClearSelection` callbacks to synchronously clear text selections before starting page curl drags, animated page turns, chapter swaps, or scroll movements, eliminating ghost selection overlays and render tree detachment exceptions.
- **Reader Sheet & Navigation Selection Dismissal**: Added `_clearTextSelection()` across `EpubReaderScreen`, `MobiReaderScreen`, and `HtmlReaderScreen` to cleanly hide selections and floating toolbars when opening the reading mode picker, settings sheet, search dialog, or chapter list drawer.
- **Sanitized Copy & Annotation Export**: Introduced `HyphenationHelper.sanitizeForCopy()` and `sanitizeForAnnotation()` to cleanly strip soft hyphens (`\u00AD`), zero-width spaces (`\u200B`), non-breaking hyphens (`\u2010`), and `&shy;` entities before copying to clipboard or saving annotations.
- **Immediate Context Menu Dismissal**: Ensured text selections and toolbar menus are immediately cleared upon executing Copy, Annotate, Define, or Read Aloud actions.

### XHTML/XML Self-Closing Tag Normalization & Paginator Polish
- **XmlHtmlNormalizer Utility**: Added `XmlHtmlNormalizer` to safely convert self-closing XHTML/XML tags (e.g. `<a id="..."/>`, `<div/>`) into canonical HTML5 paired tags before parsing with `package:html`, preventing DOM tree corruption and runaway element nesting in EPUB chapters.
- **Empty Page Slice Elimination**: Added `hasSubstantiveContent` checks in `SafeScreenPaginator.flushPage()` to prevent generating blank or phantom pages caused by empty structural containers or isolated anchor targets.
- **End-of-Chapter Anchor Preservation**: Spliced non-visual anchor elements at chapter boundaries directly into preceding page slices rather than emitting trailing empty pages, preserving internal link and bookmark targets.
- **Enhanced Structural Element Traversal**: Refactored container node inspection in `SafeScreenPaginator` to dynamically detect block-level children across all standard HTML block tags (`_blockTags`) rather than relying on a restricted tag whitelist.
- **Global XML Parsing Alignment**: Integrated `XmlHtmlNormalizer` across `DomChunker`, `EpubChapterController`, and `EpubFallbackParser` to ensure consistent DOM handling across all EPUB loading pipelines.

## [1.4.0] - 2026-11-15

### Screen-Fitted Paging & Safe Screen Paginator
- **SafeScreenPaginator Engine**: Introduced `SafeScreenPaginator` to accurately partition reflowable EPUB and MOBI/AZW chapters into screen-fitted `PageSlice` units using paragraph budgeting, DOM hierarchy traversal, and `TextPainter` text layout measurement.
- **True Screen-Fitted PageView**: Overhauled `EpubPagedViewer` and `MobiPagedViewer` to use pure screen-sized `PageView.builder` widgets for both horizontal page-turn and vertical paged reading modes, replacing monolithic scroll containers.
- **Bounded Typography & Layout Cache**: Built an LRU page slice cache keyed on viewport dimensions, typography settings (font size, family, line height, paragraph indentation/spacing), hyphenation, and active annotations for instant pagination lookups.
- **Seamless Chapter Boundary Swapping**: Added adjacent chapter edge slots (leading and trailing chapter previews) allowing continuous swiping across chapter boundaries with automatic chapter transition handling.
- **Binary Word-Boundary Page Splitting**: Replaced sentence-based paragraph splitting with binary-search over word boundaries for precise text fitting, with sentence-boundary preference heuristics for clean page breaks.
- **TextScaler & Safe-Area Aware**: Integrated `MediaQuery.textScalerOf` and inner constraints subtracting safe area padding, ensuring system font scaling and edge-to-edge/notched display geometry are respected.

### Typography Parity & Text Offset Resolution
- **TextOffsetResolver**: Implemented a pure, stateless `TextOffsetResolver` using a multi-tiered resolution pipeline (N-gram context window matching, strict Unicode word boundaries, and fallback window anchoring) to precisely map screen taps on rendered text fragments back to exact character offsets in raw chapter text, resilient against soft hyphens and invisible formatting artifacts.
- **ReaderTypographyMetrics**: Extracted centralized typography calculation formulas (`ReaderTypographyMetrics`) to guarantee mathematical parity between `SafeScreenPaginator` measurements and `FlutterHtml` rendering for headings, block margins, and indentation widths.
- **TTS Highlight Precision**: Refactored `EpubTtsController` and `MobiTtsController` to utilize offset resolution and unified typography metrics for reliable sentence highlighting and progress tracking across paged and continuous reader views.

### Hyphenation Engine & Layout Polish
- **Dynamic Language Pattern Loading**: Refactored `HyphenationHelper` to asynchronously load language pattern files on demand via `Hyphenator.loadAsyncByAbbr()`, replacing monolithic static Dart language classes and slashing memory overhead.
- **Soft-Hyphen Strip-Only Mode**: Simplified `HyphenationHelper.smartHyphenateText` to unconditionally strip `\u00AD` and `&shy;` characters, resolving Android SkParagraph rendering artifacts where words broke across lines without visible hyphen glyphs.
- **Paged Reader Margin Fixes**: Applied `Margins.only(top: 0.0)` to block elements in paged mode to prevent double vertical spacing, and corrected available width calculations for symmetric horizontal margins.
- **Gradle Asset Stripping**: Added a Gradle packaging filter in `android/app/build.gradle` to exclude upstream test fixtures and unused language JSON dictionaries from the final APK assets.

### APK Size & Rust Binary Optimization
- **Rust Crate Feature Trimming**: Stripped default features from `image` (retaining only `png`, `jpeg`, and `webp`) and `zip` (retaining `deflate` and `time`), shedding unneeded compression codecs like bzip2 and zstd.
- **Pure-Rust Unrar Crypto**: Configured `unrar-rs` to use pure Rust crypto (`crypto-rust`), eliminating native C dependencies on BoringSSL (`aws-lc-sys`) and accelerating Android NDK builds.
- **Fat Link-Time Optimization**: Configured `lto = "fat"` and `panic = "abort"` in Rust release profile for aggressive dead-code elimination and minimal native library binary footprint.
- **Direct JPEG Decoder Bypass**: Added `jpeg-decoder` in the Rust backend (`rust/src/api/cbz.rs`) to decode JPEG comic pages directly, eliminating `zune-jpeg` decoding errors and reducing allocation overhead.
- **Broad Color Space Support**: Implemented direct conversion to 32-bit RGBA for `RGB24`, `L8` grayscale, `L16`, and `CMYK32` JPEG streams before transferring pixel buffers over FFI to Flutter.
- **Zero-Cost Pixel Conversion**: Optimized JPEG decoding loops using const-generic `as_chunks` with pattern destructuring, eliminating slice indexing and bounds checks.
- **Dependency Clean Up**: Removed unused `mobi` dependency from `rust/Cargo.toml` to streamline Rust compilation.

### Reading Position & State Synchronization
- **Slice-Granular Position Tracking**: Implemented `savePagedReadingPosition` in `EpubChapterController` and `MobiChapterController` to synchronize book progress to exact sentence spans and character offsets per page slice.
- **Streamlined Paged Position Restoration**: Optimized mode switching between continuous scroll and paged reading, instantly resolving reading location via slice offsets without post-frame scroll client retries.

### Core Package & Crate Rebranding
- **Unified Branding**: Renamed the root Dart package to `ferrous` and the Rust native bridge library crate to `rust_lib_ferrous`, aligning the internal module identity with the app's official name.
- **Cross-Platform Bridge Synchronization**: Updated build scripts, Android Gradle configs, CMake files (Linux/Windows), and macOS/iOS CocoaPods podspecs to bind against `rust_lib_ferrous`.
- **Global Import Migration**: Updated all imports across the entire codebase to reference `package:ferrous/...`.

### Android Adaptive Launcher Icon
- **Updated Icon Assets**: Refreshed adaptive launcher icons across all Android display densities (`mdpi`, `hdpi`, `xhdpi`, `xxhdpi`, `xxxhdpi`) with refined vector foreground assets.
- **Dark Theme Background**: Updated adaptive icon background color in `colors.xml` to match the reader's dark theme aesthetic.

### Release Hardening, Debug Symbols & CI
- **Obfuscation & Tree-Shaking**: Configured production APK builds with `--obfuscate`, `--split-debug-info`, and `--tree-shake-icons`.
- **Debug Symbol Artifacts**: Added automated CI artifact upload for Dart debug symbols with 90-day retention for production stack trace de-obfuscation.
- **Streamlined CI Pipeline**: Optimized `.github/workflows/ci.yml` and release workflows to focus strictly on fast, reliable Flutter and Rust lint verification.
- **Analysis Options Tuning**: Updated `analysis_options.yaml` to exclude generated source files from static analysis, eliminating false positives in CI.

## [1.3.4-alpha.1] - 2026-11-12

### DOM Chunking & Reader View Performance
- **DOM Chunking Pipeline**: Introduced `DomChunker` to decompose monolithic HTML chapters (>15,000 characters) into ~18-paragraph standalone DOM chunks, unwrapping oversized containers while preserving ancestor classes, CSS hierarchy, and anchor jump targets.
- **Chunk-Level Rendering & LRU Cache**: Overhauled `EpubContentViewer` and `MobiContentViewer` with a chunk-level static LRU cache (`_chunkCache`), rendering individual DOM fragments to eliminate rendering lag, reflow bottlenecks, and memory spikes on long chapters.
- **Offset-Mapped TTS Highlights**: Integrated dynamic chapter-to-chunk offset translation into `EpubContentViewer` and `MobiContentViewer`, enabling accurate word/sentence highlighting across arbitrary DOM chunks.

### Continuous Scroll & Typography Invalidation
- **Continuous Scroll Bounds Tracking**: Converted `EpubContinuousViewer` and `MobiContinuousViewer` to stateful observers that automatically detect typography changes (font size, line height, margins, spacing) and viewport resizing, clearing cached chapter heights and bounds to prevent scroll position drift.
- **Dynamic Scroll Boundary Invalidation**: Added `invalidateScrollBounds()` and `clearRecordedChapterHeights()` in chapter controllers to ensure immediate chapter index snapping when switching reading configurations.

### Smart Hyphenation & Text Selection Polish
- **Proper Noun Preservation in Hyphenation**: Refined `smartHyphenateText` in `HyphenationHelper` to bypass capitalized proper nouns, enforce a minimum word length threshold (>=7 characters), and ignore symbols/numeric words.
- **Clean Text Copy & Annotation Export**: Stripped invisible formatting artifacts (`\u00AD`, `\u200B`, `&shy;`) from user selections during text copy and annotation creation in EPUB and MOBI reader screens.
- **TTS Zero-Width Space Normalization**: Updated sentence boundary tokenization in TTS controllers to safely ignore `\u200B` alongside soft hyphens.

### Rust RAR Decompression & SIMD Codegen
- **Pre-Allocated RAR Decompression**: Enhanced `cbz` and `covers` Rust modules to query unpacked entry sizes prior to extraction, pre-allocating buffer memory to prevent iterative reallocation overhead.
- **Decompression Integrity Checks**: Added size validation and FNV-1a 64-bit diagnostic logging to ensure verified, intact image extraction from CBR archives.
- **Targeted SIMD Optimization**: Configured release profile with `lto = "thin"` and isolated `opt-level = 3` for `unrar-rs`, `image`, `zune-jpeg`, and `jpeg-decoder` crates to guarantee optimal NEON SIMD codegen on AArch64.
- **Pinned `unrar-rs` Dependency**: Strictly pinned `unrar-rs = "=0.15.0"` to avoid upstream compilation failures in `link_anchor.rs` introduced in `0.15.1+`.

## [1.3.3] - 2026-11-11

### CBR / RAR Comic Extraction & Robustness
- **3-Tier RAR Member Resolution**: Replaced fragile name lookups with 3-tier index-based matching (`find_member_sanitized`, `find_member`, and path-normalized fallback with pre-computed targets) in Rust `cbz` and `covers` modules.
- **Index-Based Archive Decompression**: Transitioned entry access from `by_name` to `by_index` for CBR files, eliminating decompression failures on non-standard entry paths and separator encodings.
- **Archive Extraction Error Pipeline**: Introduced `ArchiveExtractionException` and granular error tracking in `CbzCacheController` to surface specific failure causes (corrupted data, password protection, unsupported compression) in `CbzPageImage`.
- **Fault-Tolerant Pre-Warming**: Protected comic reader initialization by catching individual neighbor pre-warm failures without crashing the entire viewer.

### Reading Progress & Library Filters
- **Accurate Section-Based Progress**: Updated `Book.progress` calculation to distinguish section-based reflowable formats (EPUB, MOBI, AZW, AZW3) from fixed-page documents, resolving reading progress discrepancies on early chapters.
- **In-Progress Filter Precision**: Added `isInProgress` helper to accurately identify books that have been started but not finished, refining the "Continue Reading" shelf logic.

### Typography & Paragraph Defragmentation
- **Contextual Mojibake & Replacement Character Healing**: Implemented `healReplacementCharacters` in `HtmlDefragmenter` to intelligently heal Unicode replacement characters (`\uFFFD`), substitute control chars (`\u001A`), and raw mojibake (`ï¿½`) into authentic curly apostrophes, smart quotation marks, and em-dashes across contractions, possessives, elisions, and speech boundaries.
- **Cross-Tag Element Boundary Healing**: Added `_healElementBoundaryNodes` to repair replacement characters and smart punctuation split across inline markup boundaries (e.g., `<em>` and `<strong>` tags).
- **Harmonized Search & TTS Normalization**: Integrated typographic replacement healing into `normalizePlainText` to preserve character offset alignment for search and clean TTS pronunciation.
- **Rust MOBI CP-1252 Decoder Refinement**: Updated `decode_mobi_text` to route undefined CP-1252 bytes (`0x81`, `0x8D`, `0x8F`, `0x90`, `0x9D`) as `\u{FFFD}` instead of literal `?`, enabling downstream contextual typographic healing in Dart.
- **Advanced Defragmentation Regex**: Expanded `HtmlDefragmenter` with specialized heuristics for parenthetical citations, capitalized continuation phrases, attribution em-dashes, and trailing punctuation (ellipses, colons, em-dashes, commas).
- **Proactive Soft-Hyphen Cleanup**: Unconditionally stripped soft-hyphens (`\u00AD`, `&shy;`) during text tree traversal in `HyphenationHelper` to prevent rendering artifacts and broken hyphenation line breaks in Flutter's text engine.
- **Experimental Hyphenation Setting**: Tagged the reader hyphenation toggle with an experimental notice in the layout settings sheet.

## [1.3.2] - 2026-11-11

### HTML Paragraph Defragmentation & Reader Typography
- **HTML Paragraph Defragmenter**: Implemented `HtmlDefragmenter` to scan and stitch together artificially split paragraphs in converted EPUB and MOBI files while preserving formatting, styling, and navigation anchors.
- **Soft-Hyphen Stripping & Whitespace Normalization**: Stripped rogue soft-hyphens (`\u00AD`) and condensed redundant whitespace and tabs across text nodes when hyphenation is disabled.
- **Hyphenation Default Update**: Switched default `hyphenation` setting in `ReaderThemeConfig` from `true` to `false` for cleaner baseline typography across reflowable reader views.
- **Chapter Controller Integration**: Integrated DOM defragmentation into `EpubChapterController`, `MobiChapterController`, and `HyphenationHelper` pipeline prior to sentence tokenization and indentation tagging.

### CBZ & Comic Reader Adaptive Canvas
- **Multi-Stop Edge Color Profiles**: Extracted 8-stop horizontal and vertical edge gradients (`topProfile`, `bottomProfile`) from raw RGBA buffers to support split-tone, dual-colored, and graphic border pages without letterbox banding.
- **Manga White-Paper Detection**: Added heuristic monochrome paper classification to preserve clean off-white margins and eliminate harsh dark letterboxing during manga reading.
- **3-Depth Band Sampling & Clustering**: Implemented 3-depth sampling bands (3px, 7px, 12px) with exact-sum clustering to eliminate scanner crop borders, panel margins, and screentone noise while accurately sampling full-bleed artwork.
- **Dynamic Gutter Separator Bridge**: Added intelligent canvas bridging in continuous and webtoon reading modes, matching background colors across page boundaries and preventing dark gutter flashing between light pages.
- **Nearby Page Color Pre-warming**: Expanded `notifyCornerColorsAvailable` notification radius to ±3 adjacent pages, pre-warming background gradients ahead of user scroll gestures.


### MOBI Reader Architecture & Metadata
- **Byte-Exact Chapter Slicing via NCX Targets**: Refactored Rust MOBI engine to slice raw document bytes directly using NCX table of contents byte offsets (`filepos`) with safe UTF-8 boundary snapping and target deduplication.
- **Front Matter & Title Page Extraction**: Added automatic front matter boundary detection to extract cover and title pages located prior to the first chapter target.
- **Dynamic Image Path Normalization**: Converted MOBI `recindex` image references directly to local filesystem URIs (`file://`) with automatic format fallback detection (.jpg / .png).
- **Metadata Extraction in Library Scanner**: Integrated `getMobiTitle` and `getMobiAuthor` FFI bindings into storage scanning to automatically extract real MOBI and AZW titles and authors.

### Reader Navigation & Anchor Resolution
- **In-Book Footnote & Anchor Navigation**: Implemented anchor target mapping (`#anchor` and file-prefixed fragments) across EPUB and MOBI chapter controllers.
- **Interactive Link Tapping**: Wired link handlers across paged and continuous reader modes to smoothly jump to anchor positions, chapters, and footnotes without corrupting reading state.
- **EPUB Fallback Parser Anchors**: Added anchor collection and source file tracking to the EPUB fallback parser.

## [1.3.1] - 2026-11-10

### Performance & GPU Optimization
- **O(1) GPU Halftone Scrim Shader**: Replaced 25,000+ per-frame `Canvas.drawCircle` calls with a GPU-cached repeating `ImageShader` tile, eliminating GPU command buffer exhaustion, frame drops, and driver crashes on low-end devices.
- **RepaintBoundary & Zero-Latency E-Ink Modal**: Isolated halftone scrim rendering behind a `RepaintBoundary` and set modal transition duration to `Duration.zero` for true instant e-paper responsiveness.
- **Compositor & Blur Optimization**: Replaced heavy `BackdropFilter` real-time blurs in navigation bars and floating islands with high-performance opaque surface styling, cutting GPU overdraw and eliminating scroll stutter.
- **Async Cover Decode & UI Thread I/O Removal**: Removed synchronous `File.existsSync()` blocking calls on the UI thread and added dynamic device-pixel-ratio-aware image decode sizing (`cacheWidth`/`cacheHeight`) for book covers.
- **RepaintBoundary Isolation**: Isolated `EInkPaperNoiseOverlay` and E-Ink book cover color filters behind `RepaintBoundary` widgets to prevent unneeded ancestor repaints.
- **Font Instantiation Caching**: Replaced repetitive per-widget `GoogleFonts` lookups across library views and cards with cached styles and theme typography.

### Reader & TTS Enhancements
- **Static DOM Tree Caching**: Optimized HTML reader viewers (EPUB, MOBI, TXT) with `ListenableBuilder` static child caching to bypass full HTML re-parsing and re-rendering when TTS is inactive or unchanged.
- **Transient TTS Stop Event Guards**: Added `_isStartingSpeech` flags across all TTS controllers to prevent highlight flicker and premature stops during speech engine initialization.
- **Instant Highlight Pre-seeding**: Added `startPlayback()` to pre-seed the initial word highlight immediately before the speech engine's first progress callback.

### UI & Material 3 Refinement
- **Material 3 Library Action Sheet**: Migrated the library book long-press modal from `CupertinoActionSheet` to an adaptive Material 3 `showModalBottomSheet` with drag handles, themed typography, and proper action styling.

## [1.3.0] - 2026-11-10

### Spatial Dimensions & UI Architecture
- **5 Spatial Layout Dimensions (`AppDimension`)**: Modernist (docked frosted glass), Floating Island (pill capsule navigation), Cyber Terminal (command HUD & telemetry with ASCII meters), Athenaeum (classical serif with ribbon bookmark), and Compact Slate (high-density E-paper).
- **Dynamic Semantic Icon Packs**: Dedicated icon sets matching Cupertino, ASCII Terminal, Classical Serif, Hairline, and Modernist styles.
- **Persistent Dimension Controller**: Real-time switching and preview of spatial archetypes in Appearance settings.

### Themes & Paper Textures
- **4 New Themes**: OLED Midnight (0-nit pitch black), Matcha (calming organic tea tones), Nord Arctic (cool frosty slate), and Kindle E-Ink Paper.
- **3 Tactile Paper Textures**: Japanese Washi (mulberry tea paper), Deckle Rag Folio (cotton rag), and Obsidian Velvet (tactile dark paper) with custom vignette shaders and fiber stippling.
- **Kindle Carta 1300 E-Ink Mode**: Dedicated high-contrast e-paper architecture with physical halftone scrims, carbon ink borders, 0ms instant page turns, zero-blur drop shadows, and automatic grayscale/contrast matrix cover filtering.

### Comic & Manga Reader (CBZ & CBR)
- **Native CBR Decompression**: Rust backend engine using `unrar_rs` for streaming RAR page and cover extraction without external dependencies.
- **Adaptive Color Letterboxing**: Real-time noise-filtered edge and corner color sampling (`PageCornerColors`) to seamlessly blend comic borders into screen edges.
- **Interactive Scrubber & Page Select Sheet**: Tappable page badges, interactive scrubbing slider with floating counter preview, and visual thumbnail jumping grid (`CbzPageSelectSheet`).
- **Priority-Aware Extraction Queue**: In-flight request deduplication, serialized priority loading, and pre-warming of neighbor pages for zero-latency page turns.
- **Sub-Page Offset Syncing**: Flawless reading position persistence in continuous and webtoon modes.

### Reader Engines & Typography (EPUB, MOBI, PDF)
- **Multi-Tier Cover Extraction**: Comprehensive Rust + Dart fallback chain for EPUB covers (SVG/object resolution, spine probing, archive-wide fallbacks).
- **Mode Transition Guards & Smooth Gestures**: Eliminated page jumping and race conditions when switching between paged, continuous, and webtoon modes.
- **Unicode-Normalized Annotations**: Cross-node HTML highlight matching with soft hyphen, zero-width space, and smart quote normalization.

### Diagnostics, Stability & Hardened Error Handling
- **In-Memory Ring Buffer `DiagnosticLogger`**: Zero I/O contention logger with automatic PII and storage path sanitization, wired into Flutter and platform error handlers.
- **In-App Feedback & GitHub Bug Reporter**: `FeedbackOptionsSheet` and `DiagnosticLogSheet` in Settings to export sanitized debug traces or open pre-filled GitHub issues.
- **Hardened Fullscreen `ReaderErrorView`**: Safe error boundary fallback with clipboard copying, format context, and a one-click return-to-library escape button across all readers.
- **Performance Optimizations**: Conditional GPU blur bypass in bottom nav, `RepaintBoundary` isolation on reader layers, and removed procedural noise on low-power devices.

### CI/CD, Build Security & Brand Identity
- **Cryptographic Provenance**: Automated Sigstore attestation and `SHA256SUMS.txt` generation in GitHub release builds.
- **Automated CI Lints**: Strict Rust (Clippy) and Flutter static analysis checks prior to release packaging.
- **Refreshed Branding**: Modernized high-resolution adaptive app icons and official SVG brand vector assets.

## [1.3.0-alpha.7] - 2026-11-09

### Added
- Adaptive background color matching and gradient letterboxing for CBZ/CBR comics (`CbzAdaptiveBackground`, `CbzPageLetterboxContainer`).
- Noise-filtered edge and corner color sampling (`PageCornerColors`) with cached color detection in `CbzCacheController`.
- Native CBR comic book decompression in Rust using `unrar_rs` to extract pages and cover thumbnails directly from RAR archives.
- Native pure-Dart `EpubCoverExtractor` fallback service to reliably extract EPUB cover art when native extraction fails.
- Multi-tier EPUB cover extraction fallbacks in Rust (`covers.rs`), including case-insensitive image attributes, SVG/object data resolution, spine item probing, and archive-wide fallback.
- Added `.cbr` comic archive format support to library scanning and Android SAF directory handlers.
- `CbzThumbnailService` with LRU in-memory caching and bounded task queue for asynchronous comic page thumbnail generation.
- `CbzPageSelectSheet` modal with direct numeric page jump and visual thumbnail grid with E-Ink high-contrast support.
- Upgraded `CbzPageControls` with interactive page scrubber slider, floating counter preview, stepping buttons, and tappable page badge.
- `_KindleSheetOptionRow` with 0ms instantaneous physical ledger inversion for library view mode and sort bottom sheets on E-Ink.
- Pre-warming CBZ target page and immediate neighbor pages before rendering for instant comic and manga reading.
- Synchronous scroll position syncing (`_syncCurrentPageFromScrollSynchronous`) and sub-page offset anchoring for CBZ webtoon and continuous modes.
- Page boundary drag gesture handling with top and bottom scroll boundary guards in paged EPUB and MOBI viewers.
- Animation lock (`_isPageAnimating`) in paged EPUB and MOBI viewers to prevent race conditions during rapid page turns.
- `KindleBookActionSheet` with `HalftoneScrimPainter` for Carta e-paper displays, featuring subtle halftone dots, zero-blur hard offset shadows, and 0ms instant inversion.
- `KindlePopupShape` and `KindlePopupItem` delivering crisp physical popup menus and action sheets with tactile borders and high-contrast carbon styling.
- `_KindleSliderTrackShape` with mechanical slider thumbs, tactile segmented font size steppers, line spacing selectors, and carbon borders in Reader Settings.
- E-Ink high-contrast support for `CollectionDetailScreen`, `CollectionsTab`, and `_showAddToCollectionDialog` with physical checkboxes and Roboto Slab typography.
- E-Ink mechanical styling for `LibraryLocationsScreen` and `LocationCard` with high-contrast cards, custom action popups, and instant feedback.
- Dedicated E-Ink paperwhite dialog styling for `DeleteBookDialog` with physical hairline dividers and alert styling.
- Serialized, priority-aware CBZ/CBR extraction queue in `CbzCacheController` with in-flight request sharing and automatic retry backoff.
- Archive-level thread safety and concurrency locks in Rust (`cbz.rs`) to prevent race conditions during parallel ZIP and RAR extractions.

### Fixed
- Fixed `RarArchive` type signature in Rust (`cbz.rs`) by removing invalid generic type argument.
- Fixed ZIP and RAR entry resolution in Rust (`cbz.rs`) to reliably match paths with mixed slash separators.
- Streamlined CBR cover image lookup in Rust (`covers.rs`).
- Fixed HTML attribute resolution for `<img>` and `<image>` tags in Rust EPUB cover extraction (`covers.rs`).
- Fixed chapter scroll offsets and paged indexing in EPUB and MOBI readers by removing artificial cover height and page padding shifts.
- Refined comic page selection and scrubber interactions in `CbzPageControls` and `CbzPageSelectSheet`.
- Fixed stuck page turn curl in `RealisticPageTurn` by resetting turn direction on drag cancel and animation completion.
- Guarded comic page image decoding in Rust (`cbz.rs`) against empty or truncated archive buffers.

### Changed
- Added mode transition guards (`isTransitioningMode`) and scroll epoch tracking to `EpubChapterController` and `MobiChapterController` to prevent race conditions and out-of-order page jumps during reading mode changes.
- Enhanced `EpubPagedViewer` and `MobiPagedViewer` gesture detection with velocity damping, boundary overscroll guards, and keyed `PageView` instances.
- Disambiguated `ReaderModeController` horizontal and vertical swipe flags to prevent gesture interference during continuous and webtoon reading.
- Refined vertical paged gesture navigation in `EpubPagedViewer` and `MobiPagedViewer` with velocity and scroll boundary guards.
- Ensured bottom HUD controls remain accessible in continuous and webtoon CBZ comic modes.
- Re-ordered reading mode sheet options for text formats to prioritize vertical scroll.
- Overhauled library sort and view mode sheets with tactile E-Ink mechanical styling, clamping scroll physics, and sharp square ink frames.
- Enabled realistic page curl and book spine rendering across reader themes with consistent physics.
- Fine-tuned CBZ sliver layout settled geometry and aspect ratio estimation fallbacks across all orientation modes.
- Adapted reader top bars and bottom controls (`cbz_reader_top_bar`, `epub_reader_top_bar`, `mobi_reader_top_bar`, `pdf_reader_top_bar`) with `KindlePopupShape`.
- Enhanced `BookViewItems` with automatic theme detection to route book actions to either Kindle action sheets or Cupertino sheets.
- Updated reader settings sheets and reading mode sheets with high-contrast E-Ink themes and mechanical controls.

## [1.3.0-alpha.6] - 2026-11-08

### Added
- Kindle Carta 1300 E-Ink Paper mode architecture with dedicated design tokens, palette curves, and physical e-paper physics (`EInkTokens`).
- Grayscale (100%), contrast (125%), and brightness (95%) matrix color filter for book covers to eliminate RGB color leakage in E-Ink mode.
- Editorial fallback book cover layout with high-contrast typography, carbon borders, and format markers.
- `RepaintBoundary` isolation around paged EPUB and MOBI content viewers to prevent unnecessary layer repaints during page transitions.

### Changed
- Refactored `AppThemes.eInk` with instant page transitions (`_eInkPageTransitionsTheme`), Kindle typography (Roboto Slab), and carbon hairline borders.
- Optimized `RealisticPageTurn` to instantly flip pages in E-Ink mode without drop shadows or curvature lighting shaders to prevent e-paper ghosting.
- Adapted `HtmlReaderScreen`, `EpubReader`, and `MobiReader` with halftone highlight surfaces, boxed carbon borders, and zero RGB text color leaks.
- Streamlined E-Ink typography and highlights by removing artificial ink bleed text shadows and underline text decorations.
- Removed procedural noise overlay from root app builder to eliminate rendering overhead on low-power devices.
- Enhanced annotation detail sheets, annotation dialogs, and the Annotations Hub with dedicated E-Ink high-contrast styling and carbon ink palettes.
- Upgraded library screen and dimension book views with editorial leader lines, high-contrast badges, and instant cover rendering.

## [1.3.0-alpha.5] - 2026-11-08

### Added
- Cryptographic Sigstore build provenance attestation and automatic `SHA256SUMS.txt` generation in release CI.
- Sub-page scroll offset tracking (`_inPageScrollOffset`) for accurate position restoration in CBZ continuous/webtoon reading.
- Synchronous cached image cloning in CBZ reader widgets to eliminate flashing during re-renders.

### Fixed
- Convert HTML annotation highlights to inline `TextSpan` extensions to prevent line-breaking and layout shifts in EPUB and MOBI.
- Resolve cross-node annotation text matching with comprehensive Unicode normalization (soft hyphens, zero-width spaces, typographer quotes).
- Fix CBZ continuous scroll anchor jumps and aspect ratio estimation fallbacks during lazy loading.

### Changed
- Refined library filter pill badges with theme-aware alpha blending.
- Updated documentation with APK integrity verification and attestation guides.

## [1.3.0-alpha.4] - 2026-11-08

### Added
- Initialize continuous reader `ScrollController` directly with saved offset to eliminate initial scroll flicker on launch.
- Encapsulate cover page navigation state via `onNavigatedToCover()` in chapter controllers.

### Fixed
- Prevent transient layout crashes by verifying `RenderBox` attachment and dimension bounds before coordinate calculations.
- Fix continuous scroll restoration overshooting past target chapter during lazy sliver layouts.
- Resolve cover page index synchronization issues when switching between paged and continuous reader modes.

### Changed
- Optimize EPUB and MOBI chapter navigation with instant jumping and zero animation delay.
- Streamline continuous reader position restoration by directly calculating target offsets instead of incremental stepped jumps.

## [1.3.0-alpha.3] - 2026-11-07

### Added
- 5 spatial Layout Dimensions (`AppDimension`): Modernist, Floating Island, Cyber Terminal, Athenaeum, and Compact Slate.
- Adaptive navigation archetypes (`DimensionNavStyle`): floating capsule dock, top command HUD, classical bookmark ribbon, and docked frosted glass.
- Specialized library card presentations (`DimensionCardStyle`): Magazine Bento showcase, Terminal telemetry rows with ASCII meters, embossed Index Spines, and high-density Compact rows.
- Dynamic semantic icon pack resolver (`DimensionIcons`) matching Cupertino, ASCII Terminal, Classical Serif, Hairline, and Modern styles.
- Hive-backed `DimensionController` for persistent spatial configuration.
- Interactive Dimension selector cards with live preview in Appearance settings.

## [1.3.0-alpha.2] - 2026-11-07

### Added
- 4 new application themes: OLED Midnight, Matcha, Nord Arctic, and distraction-free E-Ink Paper.
- 3 new reading background textures: Japanese Washi (mulberry tea paper), Deckle Rag Folio (cotton rag), and Obsidian Velvet (pitch black 0-nit tactile night paper).
- Custom vignette gradient shaders and fiber stippling canvas painters for all new textures.
- Dedicated concentric ring color previews and styling cards in the Appearance settings screen.

## [1.3.0-alpha.1] - 2026-11-07

### Added
- Centralized `AppRadius` and `AppSpacing` design system tokens for consistent layouts.

### Changed
- Redesigned bottom navigation bar with a docked, translucent frosted-glass aesthetic.
- Overhauled Settings screen with grouped inset card sections and refined iconography.
- Unified EPUB, MOBI, and PDF reader top bars with standardized blur and action layouts.
- Polished delete book dialog, annotations hub, and collections tab styling.

## [1.2.1] - 2026-11-06

### Documentation
- Add 1-click Obtainium installation badge and update release asset links.

### Maintenance
- Configure Fastlane Android store metadata (title, descriptions, icon, changelog) for F-Droid and IzzyOnDroid.
- Disable Google encrypted dependency metadata in release APK builds for FOSS compliance.
- Add official F-Droid build recipe template.

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