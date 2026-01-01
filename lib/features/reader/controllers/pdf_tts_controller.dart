import 'dart:async';
import 'package:flutter/material.dart';
import 'package:reader_app/src/rust/api/pdf.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/core/utils/sentence_utils.dart';
import 'package:reader_app/core/utils/normalized_text_map.dart';
import 'package:reader_app/core/utils/text_normalization.dart';
import 'pdf_page_controller.dart';

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

  bool _showTtsControls = false;
  bool _ttsContinuous = true;
  bool _ttsFollowMode = true;
  bool _tapToStartEnabled = true;

  int _ttsAdvanceRequestId = 0;
  String? _ttsStartOverrideText;
  
  NormalizedTextMap? _pageTextMap;
  List<SentenceSpan> _pageSentenceSpans = const [];
  int _ttsNormalizedBaseOffset = 0;
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
  String? get ttsStartOverrideText => _ttsStartOverrideText;

  void startSpeakingOverride(String text) {
    _ttsAdvanceRequestId++;
    _ttsStartOverrideText = text;
    _setNormalizedBaseOffset(text);
    unawaited(_ttsService.speak(text));
    notifyListeners();
  }

  void setTtsContinuous(bool value) {
    _ttsAdvanceRequestId++;
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
      _ttsAdvanceRequestId++;
      _ttsStartOverrideText = null;
      _ttsHighlightRects = const [];
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

    // Load page text and character bounds for TTS preparation
    await pageController.loadPageText(pageController.pageIndex);
    await pageController.ensureCharacterBoundsLoaded(pageController.pageIndex);
    _updatePageTextState();

    // Only prepare TTS state, don't auto-play
  }

  void _updatePageTextState() {
    final text = pageController.currentPageText;
    _pageTextMap = buildNormalizedTextMap(text);
    _pageSentenceSpans = _pageTextMap == null
        ? const []
        : splitIntoSentences(_pageTextMap!.normalized);
  }

  Future<void> startTtsFromTap(Offset localOffset, Size imageSize) async {
    if (!_showTtsControls || !_tapToStartEnabled) return;
    if (pageController.resolvedFile == null) return;

    final xNormVisible = localOffset.dx / imageSize.width;
    final yNormVisible = localOffset.dy / imageSize.height;

    if (xNormVisible < 0 || xNormVisible > 1 || yNormVisible < 0 || yNormVisible > 1) {
      return;
    }

    var xNorm = xNormVisible;
    var yNorm = yNormVisible;

    final margins = pageController.currentMargins;
    if (pageController.autoCrop && margins != null) {
      final visibleWidth = 1.0 - margins.left - margins.right;
      final visibleHeight = 1.0 - margins.top - margins.bottom;

      if (visibleWidth > 0) xNorm = margins.left + xNormVisible * visibleWidth;
      if (visibleHeight > 0) yNorm = margins.top + yNormVisible * visibleHeight;
    }

    _ttsAdvanceRequestId++;
    await _ttsService.stop();

    final requestId = ++_tapToStartRequestId;
    _ttsStartOverrideText = null;
    _ttsHighlightRects = const [];
    notifyListeners();

    try {
      final text = await extractPdfPageTextFromPoint(
        path: pageController.resolvedFile!.path,
        pageIndex: pageController.pageIndex,
        xNorm: xNorm,
        yNorm: yNorm,
      );

      if (requestId != _tapToStartRequestId) return;

      final trimmed = text.trim();
      _ttsStartOverrideText = trimmed.isEmpty ? null : trimmed;
      
      if (trimmed.isNotEmpty) {
        // Ensure character bounds are loaded for highlighting
        await pageController.ensureCharacterBoundsLoaded(pageController.pageIndex);
        if (requestId != _tapToStartRequestId) return;
        
        _setNormalizedBaseOffset(trimmed);
        unawaited(_ttsService.speak(trimmed));
      }
      notifyListeners();
    } catch (e) {
      if (requestId != _tapToStartRequestId) return;
      _ttsStartOverrideText = null;
      _ttsHighlightRects = const [];
      notifyListeners();
    }
  }

  void _handleTtsFinished() {
    if (!_showTtsControls || !_ttsContinuous) return;
    unawaited(advanceToNextReadablePageAndSpeak());
  }

  void _handleTtsProgress() {
    if (!_showTtsControls || _ttsService.state != TtsState.playing) {
      if (_ttsHighlightRects.isNotEmpty) {
        _ttsHighlightRects = const [];
        notifyListeners();
      }
      return;
    }

    // Ensure page text is loaded
    if (_pageTextMap == null && !pageController.isTextLoading) {
      pageController.loadPageText(pageController.pageIndex).then((_) {
        _updatePageTextState();
        // Retry progress update after text loads
        _handleTtsProgress();
      });
      return;
    }

    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart == null || wordEnd == null) return;

    final highlightStart = _ttsNormalizedBaseOffset + wordStart;
    final highlightEnd = _ttsNormalizedBaseOffset + wordEnd;

    // Skip if same position
    if (highlightStart == _lastHighlightStart && highlightEnd == _lastHighlightEnd) {
      return;
    }

    _lastHighlightStart = highlightStart;
    _lastHighlightEnd = highlightEnd;
    
    // Update highlight rectangles immediately for current word
    unawaited(_updateHighlightForNormalizedRange(highlightStart, highlightEnd));
  }

  Future<void> advanceToNextReadablePageAndSpeak() async {
    if (pageController.pageCount <= 0) return;

    final startIndex = pageController.pageIndex + 1;
    if (startIndex >= pageController.pageCount) return;

    final requestId = ++_ttsAdvanceRequestId;

    for (var index = startIndex; index < pageController.pageCount; index++) {
      _ttsStartOverrideText = null;
      await pageController.renderPage(index, userInitiated: false);
      if (requestId != _ttsAdvanceRequestId) return;

      await pageController.loadPageText(index);
      await pageController.ensureCharacterBoundsLoaded(index);
      _updatePageTextState();
      if (requestId != _ttsAdvanceRequestId) return;

      final text = pageController.currentPageText.trim();
      if (text.isEmpty) continue;

      _setNormalizedBaseOffset(text);
      await _ttsService.speak(text);
      return;
    }
  }

  Future<void> _updateHighlightForNormalizedRange(int start, int end) async {
    final map = _pageTextMap;
    if (map == null || map.normalizedToRaw.isEmpty) return;
    if (start < 0 || end <= start) return;
    if (start >= map.normalizedToRaw.length) return;

    final clampedEnd = end.clamp(0, map.normalizedToRaw.length);
    final rawStart = map.normalizedToRaw[start];
    final rawEnd = map.normalizedToRaw[clampedEnd - 1] + 1;

    final cachedBounds = pageController.pageCharBoundsCache[pageController.pageIndex];
    if (cachedBounds != null && cachedBounds.isNotEmpty) {
      final clampedRawEnd = rawEnd.clamp(0, cachedBounds.length);
      final clampedRawStart = rawStart.clamp(0, clampedRawEnd);

      // Merge all character rects into a single word bounding box
      double? left, top, right, bottom;
      for (var i = clampedRawStart; i < clampedRawEnd; i++) {
        final rect = cachedBounds[i];
        // Skip empty/whitespace rects
        if (rect.left == 0 && rect.top == 0 && rect.right == 0 && rect.bottom == 0) continue;
        
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
        final wordRect = PdfTextRect(left: left, top: top!, right: right!, bottom: bottom!);
        _ttsHighlightRects = [wordRect];
      } else {
        _ttsHighlightRects = const [];
      }
      notifyListeners();
      _maybeAutoPanToHighlight(_ttsHighlightRects);
      return;
    }

    final requestId = ++_highlightRequestId;
    try {
      final rects = await extractPdfPageTextBounds(
        path: pageController.resolvedFile!.path,
        pageIndex: pageController.pageIndex,
        startIndex: rawStart,
        endIndex: rawEnd,
      );

      if (requestId != _highlightRequestId) return;
      _ttsHighlightRects = rects;
      notifyListeners();
      _maybeAutoPanToHighlight(rects);
    } catch (_) {
      if (requestId != _highlightRequestId) return;
      _ttsHighlightRects = const [];
      notifyListeners();
    }
  }

  void _setNormalizedBaseOffset(String ttsText) {
    _updatePageTextState();
    final map = _pageTextMap;
    if (map == null || map.normalized.isEmpty) {
      _ttsNormalizedBaseOffset = 0;
      return;
    }

    final normalized = normalizePlainText(ttsText);
    if (normalized.isEmpty) {
      _ttsNormalizedBaseOffset = 0;
      return;
    }

    final index = map.normalized.indexOf(normalized);
    _ttsNormalizedBaseOffset = index >= 0 ? index : 0;
  }

  void saveCurrentTtsSentence() {
    final start = _ttsService.currentWordStart;
    if (start == null || _pageTextMap == null) return;

    final absoluteOffset = _ttsNormalizedBaseOffset + start;
    final span = sentenceForOffset(_pageSentenceSpans, absoluteOffset);
    if (span == null) return;

    _lastTtsSentenceStart = span.start;
    _lastTtsSentenceEnd = span.end;
    _lastTtsPage = pageController.pageIndex;
    
    unawaited(repository.updateReadingProgress(
      book.id,
      currentPage: pageController.pageIndex,
      totalPages: pageController.pageCount,
      lastTtsSentenceStart: span.start,
      lastTtsSentenceEnd: span.end,
      lastTtsPage: pageController.pageIndex,
    ));
  }

  String resolveTtsText() {
    _updatePageTextState();
    final map = _pageTextMap;
    final text = pageController.currentPageText;
    if (text.trim().isEmpty) return '';

    if (map != null &&
        _lastTtsSentenceStart >= 0 &&
        _lastTtsSentenceEnd > _lastTtsSentenceStart &&
        _lastTtsPage == pageController.pageIndex) {
      final normalized = map.normalized;
      if (normalized.isNotEmpty) {
        final start = _lastTtsSentenceStart.clamp(0, normalized.length);
        _ttsNormalizedBaseOffset = start;
        return normalized.substring(start);
      }
    }

    final override = _ttsStartOverrideText;
    if (override != null && override.trim().isNotEmpty) {
      _setNormalizedBaseOffset(override);
      return override;
    }

    _setNormalizedBaseOffset(text);
    return text;
  }

  void _maybeAutoPanToHighlight(List<PdfTextRect> rects) {
    if (!_ttsFollowMode || rects.isEmpty || pdfTransformController == null) return;
    final viewerSize = pageController.viewerSize;
    // Use logicalPageSize for coordinate mapping
    final layoutSize = pageController.logicalPageSize.isEmpty 
        ? pageController.renderedPageSize 
        : pageController.logicalPageSize;
    if (viewerSize.isEmpty || layoutSize.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_lastAutoPanAt) < const Duration(milliseconds: 80)) return;

    final bounds = _unionHighlightRects(rects);
    // Convert normalized rect (0-1) to layout coordinates
    final highlightRect = Rect.fromLTRB(
      bounds.left * layoutSize.width,
      bounds.top * layoutSize.height,
      bounds.right * layoutSize.width,
      bounds.bottom * layoutSize.height,
    );

    // Calculate a comfortable reading zoom
    final wordWidth = highlightRect.width;
    final desiredWordWidth = viewerSize.width * 0.35;
    var targetScale = (desiredWordWidth / wordWidth).clamp(1.5, 3.0);
    
    final center = highlightRect.center;
    final viewportCenter = Offset(viewerSize.width / 2, viewerSize.height / 2);
    final translation = Offset(
      viewportCenter.dx - center.dx * targetScale,
      viewportCenter.dy - center.dy * targetScale,
    );

    // Ensure we don't pan outside the page bounds
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

  Future<void> primeTtsFromViewport() async {
    if (pageController.viewerSize.isEmpty || pageController.renderedPageSize.isEmpty || pdfTransformController == null) return;
    if (pageController.resolvedFile == null) return;

    final inverse = Matrix4.inverted(pdfTransformController!.value);
    final viewportCenter = Offset(pageController.viewerSize.width / 2, pageController.viewerSize.height / 2);
    final scenePoint = MatrixUtils.transformPoint(inverse, viewportCenter);

    var xNorm = scenePoint.dx / pageController.renderedPageSize.width;
    var yNorm = scenePoint.dy / pageController.renderedPageSize.height;

    final margins = pageController.currentMargins;
    if (pageController.autoCrop && margins != null) {
      final visibleWidth = 1.0 - margins.left - margins.right;
      final visibleHeight = 1.0 - margins.top - margins.bottom;
      if (visibleWidth > 0) xNorm = margins.left + xNorm * visibleWidth;
      if (visibleHeight > 0) yNorm = margins.top + yNorm * visibleHeight;
    }

    try {
      final text = await extractPdfPageTextFromPoint(
        path: pageController.resolvedFile!.path,
        pageIndex: pageController.pageIndex,
        xNorm: xNorm,
        yNorm: yNorm,
      );
      final trimmed = text.trim();
      if (trimmed.isNotEmpty) {
        _ttsStartOverrideText = trimmed;
        _setNormalizedBaseOffset(trimmed);
        notifyListeners();
      }
    } catch (_) {}
  }

  void closeTtsControls() {
    _ttsAdvanceRequestId++;
    _ttsStartOverrideText = null;
    _ttsHighlightRects = const [];
    _showTtsControls = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _ttsService.setOnFinished(null);
    _ttsService.removeListener(_handleTtsProgress);

    unawaited(_ttsService.stop());
    super.dispose();
  }
}
