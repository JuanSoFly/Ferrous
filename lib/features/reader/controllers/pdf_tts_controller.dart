import 'dart:async';
import 'package:flutter/material.dart';
import 'package:reader_app/src/rust/api/pdf.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/core/utils/sentence_utils.dart';
import 'package:reader_app/core/utils/text_normalization.dart';
import 'pdf_page_controller.dart';
import 'pdf_document_text.dart';

class PdfTtsController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;
  final TtsService _ttsService;
  final PdfPageController pageController;

  PdfTtsController({
    required this.book,
    required this.repository,
    required TtsService ttsService,
    required this.pageController,
  }) : _ttsService = ttsService {
    _ttsService.setOnFinished(_handleTtsFinished);
    _ttsService.addListener(_handleTtsProgress);

    _lastTtsSentenceStart = book.lastTtsSentenceStart;
    _lastTtsSentenceEnd = book.lastTtsSentenceEnd;
    _lastTtsPage = book.lastTtsPage;
  }

  bool _disposed = false;
  bool _showTtsControls = false;
  bool _ttsContinuous = true;
  bool _ttsFollowMode = true;
  bool _tapToStartEnabled = true;

  String? _ttsStartOverrideText;

  // When speaking override text (from tap or text picker), this is the offset
  // in the normalized document text where the override begins. This allows
  // _handleTtsProgress to map override-relative word offsets to document-level
  // positions for correct highlighting.
  int _overrideNormalizedBaseOffset = 0;

  // Document-level text (replaces per-page text for TTS)
  PdfDocumentText? _documentText;
  bool _documentTextLoading = false;
  int _documentTextRequestId = 0;

  // Highlight state — tracks which page the current word is on
  int _highlightPageIndex = -1;
  List<PdfTextRect> _ttsHighlightRects = const [];

  int? _lastHighlightStart;
  int? _lastHighlightEnd;
  DateTime _lastAutoPanAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _highlightRequestId = 0;
  int _tapToStartRequestId = 0;

  late int _lastTtsSentenceStart;
  late int _lastTtsSentenceEnd;
  late int _lastTtsPage;

  TransformationController? pdfTransformController;
  TtsService get ttsService => _ttsService;
  bool get showTtsControls => _showTtsControls;
  bool get ttsContinuous => _ttsContinuous;
  bool get ttsFollowMode => _ttsFollowMode;
  bool get tapToStartEnabled => _tapToStartEnabled;
  List<PdfTextRect> get ttsHighlightRects => _ttsHighlightRects;
  int get highlightPageIndex => _highlightPageIndex;
  String? get ttsStartOverrideText => _ttsStartOverrideText;
  PdfDocumentText? get documentText => _documentText;
  bool get documentTextLoading => _documentTextLoading;

  // ---------------------------------------------------------------------------
  // Document text assembly
  // ---------------------------------------------------------------------------

  /// Build the full document text from all pages. Called once when TTS is
  /// first activated. Caches the result.
  Future<void> _buildDocumentText() async {
    if (_documentText != null) return;
    if (_disposed) return;

    final requestId = ++_documentTextRequestId;
    _documentTextLoading = true;
    notifyListeners();

    try {
      final path = pageController.resolvedFile?.path;
      if (path == null) return;

      final pageCount = pageController.pageCount;
      if (pageCount <= 0) return;

      // Extract text from all pages. Use existing cached texts where available,
      // load the rest.
      final pageTexts = <int, String>{};
      for (var i = 0; i < pageCount; i++) {
        if (_disposed || requestId != _documentTextRequestId) return;

        // Check cache first
        final cached = pageController.pageTextCache[i];
        if (cached != null) {
          pageTexts[i] = cached;
          continue;
        }

        // Load from Rust FFI
        await pageController.loadPageText(i);
        if (_disposed || requestId != _documentTextRequestId) return;
        pageTexts[i] = pageController.pageTextCache[i] ?? '';
      }

      if (_disposed || requestId != _documentTextRequestId) return;

      _documentText = buildPdfDocumentText(pageTexts, pageCount);
      _documentTextLoading = false;
      notifyListeners();

      // Precompute character bounds for the first few pages in the background
      _preloadCharacterBounds(pageCount);
    } catch (e) {
      if (_disposed || requestId != _documentTextRequestId) return;
      _documentTextLoading = false;
      notifyListeners();
    }
  }

  /// Precompute character bounds for pages near the current position.
  void _preloadCharacterBounds(int pageCount) {
    final current = pageController.pageIndex;
    for (var i = current; i < pageCount && i < current + 3; i++) {
      unawaited(pageController.ensureCharacterBoundsLoaded(i));
    }
  }

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  Future<void> startSpeakingOverride(String text) async {

    _ttsStartOverrideText = text;
    // Ensure document text is built so we can map override offsets
    await _buildDocumentText();
    // Find where this override text appears in the document for highlight mapping
    _computeOverrideBaseOffset(text);
    unawaited(_ttsService.speak(text));
    notifyListeners();
  }

  /// Compute where [text] begins in the normalized document text so that
  /// TTS word offsets (relative to [text]) can be mapped to document-level
  /// positions for highlighting.
  void _computeOverrideBaseOffset(String text) {
    final doc = _documentText;
    if (doc == null || doc.isEmpty) {
      _overrideNormalizedBaseOffset = 0;
      return;
    }
    final normalized = normalizePlainText(text);
    if (normalized.isEmpty) {
      _overrideNormalizedBaseOffset = 0;
      return;
    }
    var index = doc.normalizedText.indexOf(normalized);
    if (index < 0 && normalized.length > 10) {
      final prefixLen = normalized.length > 50 ? 50 : normalized.length;
      index = doc.normalizedText.indexOf(normalized.substring(0, prefixLen));
    }
    _overrideNormalizedBaseOffset = index >= 0 ? index : 0;
  }

  void setTtsContinuous(bool value) {

    _ttsContinuous = value;
    notifyListeners();
  }

  void setTtsFollowMode(bool value) {
    _ttsFollowMode = value;
    notifyListeners();
  }

  void setTapToStartEnabled(bool value) {
    _tapToStartEnabled = value;
    notifyListeners();
  }

  Future<void> toggleTts() async {
    final next = !_showTtsControls;
    _showTtsControls = next;
    notifyListeners();

    if (!next) {
      saveCurrentTtsSentence();
  
      _ttsStartOverrideText = null;
      _overrideNormalizedBaseOffset = 0;
      _ttsHighlightRects = const [];
      _highlightPageIndex = -1;
      unawaited(_ttsService.stop());
      return;
    }

    // Jump to saved TTS position if available
    if (_lastTtsSentenceStart >= 0 &&
        pageController.pageCount > 0 &&
        _lastTtsPage >= 0 &&
        _lastTtsPage < pageController.pageCount &&
        _lastTtsPage != pageController.pageIndex) {
      await pageController.renderPage(_lastTtsPage, userInitiated: false);
    }

    // Build document-level text for continuous TTS
    await _buildDocumentText();

    // Ensure character bounds for the current page
    await pageController.ensureCharacterBoundsLoaded(pageController.pageIndex);
  }

  // ---------------------------------------------------------------------------
  // TTS progress — highlight the current word
  // ---------------------------------------------------------------------------

  void _handleTtsProgress() {
    if (_disposed) return;
    if (_ttsService.state == TtsState.stopped) {
      if (_ttsHighlightRects.isNotEmpty) {
        _ttsHighlightRects = const [];
        _highlightPageIndex = -1;
        notifyListeners();
      }
      return;
    }

    if (_ttsService.state != TtsState.playing) return;

    // Need document text for offset resolution
    if (_documentText == null && !_documentTextLoading) {
      unawaited(_buildDocumentText().then((_) => _handleTtsProgress()));
      return;
    }
    if (_documentText == null) return;

    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart == null || wordEnd == null) return;

    // When speaking the full document text, word offsets are document-relative
    // (base = 0). When speaking override text (tap/text picker), word offsets
    // are relative to the override, so we add the override's base offset.
    final base = _ttsStartOverrideText != null ? _overrideNormalizedBaseOffset : 0;
    final highlightStart = base + wordStart;
    final highlightEnd = base + wordEnd;

    if (highlightStart == _lastHighlightStart &&
        highlightEnd == _lastHighlightEnd) {
      return;
    }

    _lastHighlightStart = highlightStart;
    _lastHighlightEnd = highlightEnd;

    unawaited(_updateHighlightForNormalizedRange(highlightStart, highlightEnd));
  }

  // ---------------------------------------------------------------------------
  // Highlight computation
  // ---------------------------------------------------------------------------

  Future<void> _updateHighlightForNormalizedRange(
      int normStart, int normEnd) async {
    if (_disposed) return;
    final doc = _documentText;
    if (doc == null || doc.normalizedMap.normalizedToRaw.isEmpty) return;
    if (normStart < 0 || normEnd <= normStart) return;
    if (normStart >= doc.normalizedMap.normalizedToRaw.length) return;

    final map = doc.normalizedMap;
    final clampedEnd = normEnd.clamp(0, map.normalizedToRaw.length);
    final rawStart = map.normalizedToRaw[normStart];
    final rawEnd = clampedEnd < map.normalizedToRaw.length
        ? map.normalizedToRaw[clampedEnd]
        : map.normalizedToRaw[clampedEnd - 1] + 1;

    // Find which page this word is on
    final targetPage = doc.pageForDocumentOffset(rawStart);
    if (targetPage < 0) return;

    // Convert to page-local offsets
    final localStart = doc.localOffset(rawStart, targetPage);
    final localEnd = doc.localOffset(rawEnd, targetPage);
    if (localStart < 0 || localEnd < 0) return;

    // Ensure the target page is rendered and its character bounds are loaded
    if (targetPage != pageController.pageIndex) {
      // Word is on a different page than the currently rendered one
      unawaited(_ensurePageReadyForHighlight(targetPage));
    }

    // Look up character bounds for the target page
    final cachedBounds = pageController.pageCharBoundsCache[targetPage];
    if (cachedBounds != null && cachedBounds.isNotEmpty) {
      _applyHighlightFromBounds(cachedBounds, localStart, localEnd, targetPage);
      return;
    }

    // Bounds not cached — load them and retry
    final requestId = ++_highlightRequestId;
    await pageController.ensureCharacterBoundsLoaded(targetPage);
    if (_disposed || requestId != _highlightRequestId) return;

    final bounds = pageController.pageCharBoundsCache[targetPage];
    if (bounds != null && bounds.isNotEmpty) {
      _applyHighlightFromBounds(bounds, localStart, localEnd, targetPage);
    } else {
      // Fallback: use Rust FFI to get bounds for just this range
      try {
        final resolvedPath = pageController.resolvedFile?.path;
        if (resolvedPath == null) return;
        final rects = await extractPdfPageTextBounds(
          path: resolvedPath,
          pageIndex: targetPage,
          startIndex: localStart,
          endIndex: localEnd,
        );
        if (_disposed || requestId != _highlightRequestId) return;
        _ttsHighlightRects = rects;
        _highlightPageIndex = targetPage;
        notifyListeners();
        _maybeAutoPanToHighlight(rects);
      } catch (_) {
        if (_disposed || requestId != _highlightRequestId) return;
        _ttsHighlightRects = const [];
        notifyListeners();
      }
    }
  }

  void _applyHighlightFromBounds(
      List<PdfTextRect> cachedBounds, int localStart, int localEnd, int pageIndex) {
    final clampedEnd = localEnd.clamp(0, cachedBounds.length);
    final clampedStart = localStart.clamp(0, clampedEnd);

    double? left, top, right, bottom;
    for (var i = clampedStart; i < clampedEnd; i++) {
      final rect = cachedBounds[i];
      if (rect.left == 0 &&
          rect.top == 0 &&
          rect.right == 0 &&
          rect.bottom == 0) {
        continue;
      }

      if (left == null) {
        left = rect.left;
        top = rect.top;
        right = rect.right;
        bottom = rect.bottom;
      } else {
        if (rect.left < left) left = rect.left;
        if (rect.top < top!) top = rect.top;
        if (rect.right > right!) right = rect.right;
        if (rect.bottom > bottom!) bottom = rect.bottom;
      }
    }

    if (left != null) {
      _ttsHighlightRects = [
        PdfTextRect(left: left, top: top!, right: right!, bottom: bottom!)
      ];
    } else {
      _ttsHighlightRects = const [];
    }
    _highlightPageIndex = pageIndex;
    notifyListeners();
    _maybeAutoPanToHighlight(_ttsHighlightRects);
  }

  /// Ensure a page is rendered and ready for highlight display.
  /// In paged mode, renders the page. In continuous mode, the page is already
  /// visible so we just need character bounds.
  Future<void> _ensurePageReadyForHighlight(int pageIndex) async {
    if (pageController.isContinuousMode) {
      // In continuous mode, pages are already laid out — just need bounds
      unawaited(pageController.ensureCharacterBoundsLoaded(pageIndex));
    } else {
      // In paged mode, render the page so it becomes visible
      await pageController.renderPage(pageIndex, userInitiated: false);
      unawaited(pageController.ensureCharacterBoundsLoaded(pageIndex));
    }
  }

  // ---------------------------------------------------------------------------
  // TTS finished — no more page-by-page advancement
  // ---------------------------------------------------------------------------

  void _handleTtsFinished() {
    // TTS spoke the entire document text. Nothing to advance.
    // Just clear the highlight.
    _ttsHighlightRects = const [];
    _highlightPageIndex = -1;
    _lastHighlightStart = null;
    _lastHighlightEnd = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Tap-to-start
  // ---------------------------------------------------------------------------

  Future<void> startTtsFromTap(Offset localOffset, Size imageSize) async {
    if (_disposed) return;
    if (!_showTtsControls || !_tapToStartEnabled) return;
    final resolvedPath = pageController.resolvedFile?.path;
    if (resolvedPath == null) return;

    final xNormVisible = localOffset.dx / imageSize.width;
    final yNormVisible = localOffset.dy / imageSize.height;

    if (xNormVisible < 0 ||
        xNormVisible > 1 ||
        yNormVisible < 0 ||
        yNormVisible > 1) {
      return;
    }

    var xNorm = xNormVisible;
    var yNorm = yNormVisible;

    final margins = pageController.currentMargins;
    if (pageController.autoCrop && margins != null) {
      final visibleWidth = 1.0 - margins.left - margins.right;
      final visibleHeight = 1.0 - margins.top - margins.bottom;
      if (visibleWidth > 0) xNorm = margins.left + xNormVisible * visibleWidth;
      if (visibleHeight > 0) {
        yNorm = margins.top + yNormVisible * visibleHeight;
      }
    }


    await _ttsService.stop();

    final requestId = ++_tapToStartRequestId;
    _ttsStartOverrideText = null;
    _ttsHighlightRects = const [];
    _highlightPageIndex = -1;
    notifyListeners();

    try {
      // Get text from the tap point
      final pageText = await extractPdfPageTextFromPoint(
        path: resolvedPath,
        pageIndex: pageController.pageIndex,
        xNorm: xNorm,
        yNorm: yNorm,
      );

      if (_disposed || requestId != _tapToStartRequestId) return;

      final trimmed = pageText.trim();
      if (trimmed.isEmpty) return;

      // Ensure document text is built so we can find the sentence boundary
      await _buildDocumentText();
      if (_disposed || requestId != _tapToStartRequestId) return;

      final doc = _documentText;
      if (doc == null || doc.isEmpty) return;

      // Find where the tapped text appears in the document text, then
      // snap to the nearest sentence start.
      final normalizedTap = normalizePlainText(trimmed);
      var docOffset = doc.normalizedText.indexOf(normalizedTap);

      if (docOffset < 0 && normalizedTap.length > 10) {
        // Fallback: try a prefix match
        final prefixLen =
            normalizedTap.length > 50 ? 50 : normalizedTap.length;
        docOffset =
            doc.normalizedText.indexOf(normalizedTap.substring(0, prefixLen));
      }

      if (docOffset < 0) docOffset = 0;

      // Snap to sentence start
      final sentenceStart = findSentenceStart(doc.normalizedText, docOffset);
      final speakText = doc.normalizedText.substring(sentenceStart).trim();

      if (speakText.isEmpty) return;

      _ttsStartOverrideText = speakText;
      // The TTS word offsets will be relative to speakText, which starts at
      // sentenceStart in the normalized document text.
      _overrideNormalizedBaseOffset = sentenceStart;
      await pageController.ensureCharacterBoundsLoaded(pageController.pageIndex);
      if (_disposed || requestId != _tapToStartRequestId) return;

      unawaited(_ttsService.speak(speakText));
      notifyListeners();
    } catch (e) {
      if (_disposed || requestId != _tapToStartRequestId) return;
      _ttsStartOverrideText = null;
      _ttsHighlightRects = const [];
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Text resolution
  // ---------------------------------------------------------------------------

  /// Returns the text to speak. With document-level assembly, this is always
  /// the full document text (or a sentence-sliced portion from saved position).
  String resolveTtsText() {
    final doc = _documentText;
    if (doc == null || doc.isEmpty) {
      // Fallback to current page text if document text isn't built yet
      final pageText = pageController.currentPageText;
      if (pageText.trim().isEmpty) return '';
      return pageText;
    }

    // Resume from saved sentence position
    if (_lastTtsSentenceStart >= 0 &&
        _lastTtsSentenceEnd > _lastTtsSentenceStart &&
        _lastTtsPage >= 0 &&
        _lastTtsPage < doc.pageCount) {
      final pageOffset = doc.pageOffsets[_lastTtsPage];
      // Convert the saved sentence start (which is page-local code-unit offset)
      // to a document-level offset.
      final docStart = pageOffset.documentCharStart + _lastTtsSentenceStart;
      if (docStart < doc.fullText.length) {
        return doc.fullText.substring(docStart);
      }
    }

    // Override from tap or text picker
    final override = _ttsStartOverrideText;
    if (override != null && override.trim().isNotEmpty) {
      return override;
    }

    return doc.fullText;
  }

  // ---------------------------------------------------------------------------
  // Position persistence
  // ---------------------------------------------------------------------------

  void saveCurrentTtsSentence() {
    final doc = _documentText;
    if (doc == null || doc.isEmpty) return;

    final wordStart = _ttsService.currentWordStart;
    if (wordStart == null) return;

    // wordStart is relative to what's being spoken (document or override text).
    // Add the override base offset to get the document-level position.
    final base = _ttsStartOverrideText != null ? _overrideNormalizedBaseOffset : 0;
    final normOffset = base + wordStart;
    if (normOffset < 0 || normOffset >= doc.normalizedMap.normalizedToRaw.length) {
      return;
    }

    // Convert to raw document offset
    final rawDocOffset = doc.normalizedMap.normalizedToRaw[normOffset];

    // Find which page this is on
    final pageIndex = doc.pageForDocumentOffset(rawDocOffset);
    if (pageIndex < 0) return;

    // Convert to page-local raw offset
    final localRaw = doc.localOffset(rawDocOffset, pageIndex);
    if (localRaw < 0) return;

    // Find the sentence in the document's normalized text
    final codeUnitOffset = doc.normalizedMap.runeToCodeUnit(normOffset);
    final span = sentenceForOffset(doc.sentences, codeUnitOffset);

    _lastTtsSentenceStart = span?.start ?? localRaw;
    _lastTtsSentenceEnd = span?.end ?? localRaw;
    _lastTtsPage = pageIndex;

    unawaited(repository.updateReadingProgress(
      book.id,
      currentPage: pageController.pageIndex,
      totalPages: pageController.pageCount,
      lastTtsSentenceStart: _lastTtsSentenceStart,
      lastTtsSentenceEnd: _lastTtsSentenceEnd,
      lastTtsPage: _lastTtsPage,
    ));
  }

  // ---------------------------------------------------------------------------
  // Auto-pan (follow mode)
  // ---------------------------------------------------------------------------

  void _maybeAutoPanToHighlight(List<PdfTextRect> rects) {
    if (!_ttsFollowMode || rects.isEmpty || pdfTransformController == null) {
      return;
    }
    final viewerSize = pageController.viewerSize;
    final layoutSize = pageController.logicalPageSize.isEmpty
        ? pageController.renderedPageSize
        : pageController.logicalPageSize;
    if (viewerSize.isEmpty || layoutSize.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_lastAutoPanAt) < const Duration(milliseconds: 80)) {
      return;
    }

    final bounds = _unionHighlightRects(rects);
    final highlightRect = Rect.fromLTRB(
      bounds.left * layoutSize.width,
      bounds.top * layoutSize.height,
      bounds.right * layoutSize.width,
      bounds.bottom * layoutSize.height,
    );

    final wordWidth = highlightRect.width;
    final desiredWordWidth = viewerSize.width * 0.35;
    var targetScale = (desiredWordWidth / wordWidth).clamp(1.5, 3.0);

    final center = highlightRect.center;
    final viewportCenter = Offset(viewerSize.width / 2, viewerSize.height / 2);
    final translation = Offset(
      viewportCenter.dx - center.dx * targetScale,
      viewportCenter.dy - center.dy * targetScale,
    );

    final pageWidth = layoutSize.width * targetScale;
    final pageHeight = layoutSize.height * targetScale;
    final clampedTx = translation.dx.clamp(viewerSize.width - pageWidth, 0.0);
    final clampedTy = translation.dy.clamp(viewerSize.height - pageHeight, 0.0);

    _lastAutoPanAt = now;
    pdfTransformController!.value = Matrix4.identity()
      ..translateByDouble(clampedTx, clampedTy, 0.0, 1.0)
      ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
  }

  PdfTextRect _unionHighlightRects(List<PdfTextRect> rects) {
    var left = rects.first.left;
    var right = rects.first.right;
    var top = rects.first.top;
    var bottom = rects.first.bottom;
    for (final rect in rects.skip(1)) {
      if (rect.left < left) left = rect.left;
      if (rect.right > right) right = rect.right;
      if (rect.top < top) top = rect.top;
      if (rect.bottom > bottom) bottom = rect.bottom;
    }
    return PdfTextRect(left: left, top: top, right: right, bottom: bottom);
  }

  // ---------------------------------------------------------------------------
  // Viewport prime (for pre-setting TTS text from viewport center)
  // ---------------------------------------------------------------------------

  Future<void> primeTtsFromViewport() async {
    if (_disposed) return;
    if (pageController.viewerSize.isEmpty ||
        pageController.renderedPageSize.isEmpty ||
        pdfTransformController == null) {
      return;
    }
    final resolvedPath = pageController.resolvedFile?.path;
    if (resolvedPath == null) return;

    final inverse = Matrix4.inverted(pdfTransformController!.value);
    final viewportCenter = Offset(
      pageController.viewerSize.width / 2,
      pageController.viewerSize.height / 2,
    );
    final scenePoint = MatrixUtils.transformPoint(inverse, viewportCenter);

    var xNorm = scenePoint.dx / pageController.renderedPageSize.width;
    var yNorm = scenePoint.dy / pageController.renderedPageSize.height;

    final margins = pageController.currentMargins;
    if (pageController.autoCrop && margins != null) {
      final visibleWidth = 1.0 - margins.left - margins.right;
      final visibleHeight = 1.0 - margins.top - margins.bottom;
      if (visibleWidth > 0) xNorm = margins.left + xNorm * visibleWidth;
      if (visibleHeight > 0) {
        yNorm = margins.top + yNorm * visibleHeight;
      }
    }

    try {
      final text = await extractPdfPageTextFromPoint(
        path: resolvedPath,
        pageIndex: pageController.pageIndex,
        xNorm: xNorm,
        yNorm: yNorm,
      );
      if (_disposed) return;
      final trimmed = text.trim();
      if (trimmed.isNotEmpty) {
        _ttsStartOverrideText = trimmed;
        notifyListeners();
      }
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Cleanup
  // ---------------------------------------------------------------------------

  void closeTtsControls() {

    _ttsStartOverrideText = null;
    _overrideNormalizedBaseOffset = 0;
    _ttsHighlightRects = const [];
    _highlightPageIndex = -1;
    _showTtsControls = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ttsService.setOnFinished(null);
    _ttsService.removeListener(_handleTtsProgress);
    unawaited(_ttsService.stop());
    super.dispose();
  }
}
