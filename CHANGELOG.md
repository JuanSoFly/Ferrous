## [1.3.0-alpha.7] - 2026-11-09

### Added
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

### Changed
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