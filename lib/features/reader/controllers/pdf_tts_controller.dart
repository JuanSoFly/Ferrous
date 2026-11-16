import 'dart:async';
import 'package:flutter/material.dart';
import 'package:ferrous/src/rust/api/pdf.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/data/repositories/book_repository.dart';
import 'package:ferrous/data/services/tts_service.dart';
import 'package:ferrous/core/utils/sentence_utils.dart';
import 'pdf_page_controller.dart';
import 'pdf_document_text.dart';

/// Represents a distinct sentence on a PDF page with precomputed bounding rects.
class PdfSentence {
  final int pageIndex;
  final int sentenceIndex;
  final int charStart;
  final int charEnd;
  final int pageCleanStartOffset;
  final String rawText;
  final String cleanText;
  final List<PdfTextRect> rects;

  const PdfSentence({
    required this.pageIndex,
    required this.sentenceIndex,
    required this.charStart,
    required this.charEnd,
    required this.pageCleanStartOffset,
    required this.rawText,
    required this.cleanText,
    required this.rects,
  });
}

/// Dedicated, high-performance Sentence-Level TTS Controller for PDF.
///
/// Highlights entire sentences line-by-line with gutter-safe multi-column bounding,
/// eliminates aggressive canvas auto-zooming, and guarantees zero-drift position persistence.
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
    _ttsService.addListener(_onTtsServiceUpdated);
    pageController.addListener(_onPageControllerUpdated);

    // Initialize from book persistence: lastTtsPage and lastTtsSentenceStart (index)
    _speakingPage = book.lastTtsPage >= 0 ? book.lastTtsPage : pageController.pageIndex;
    _speakingSentenceIndex = book.lastTtsSentenceStart >= 0 ? book.lastTtsSentenceStart : 0;
  }

  void _onTtsServiceUpdated() {
    if (_disposed || _currentSentence == null) return;
    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart != null && wordEnd != null && wordEnd > wordStart) {
      final sanitized = pageController.sanitizedTextCache[_speakingPage];
      final bounds = pageController.pageCharBoundsCache[_speakingPage];
      if (sanitized != null && bounds != null) {
        final sentenceOffset = _currentSentence!.pageCleanStartOffset;
        final cleanStart = sentenceOffset + wordStart;
        final cleanEnd = sentenceOffset + wordEnd;
        final wordRects = _computeSentenceRectsFromCleanOffsets(bounds, sanitized.cleanToPdfMap, cleanStart, cleanEnd);
        if (wordRects.isNotEmpty) {
          _ttsHighlightRects = wordRects;
          highlightRectsNotifier.value = wordRects;
          return;
        }
      }
    }
    if (_currentSentence != null && _ttsHighlightRects != _currentSentence!.rects) {
      _ttsHighlightRects = _currentSentence!.rects;
      highlightRectsNotifier.value = _currentSentence!.rects;
    }
  }

  void _onPageControllerUpdated() {
    if (_disposed) return;
    final current = pageController.pageIndex;
    if (current >= 0 && current < pageController.pageCount) {
      unawaited(getSentencesForPage(current));
    }
  }

  bool _disposed = false;
  bool _showTtsControls = false;
  bool _ttsContinuous = true;
  bool _ttsFollowMode = true;
  bool _tapToStartEnabled = true;

  int _speakingPage = -1;
  int _speakingSentenceIndex = -1;
  PdfSentence? _currentSentence;
  List<PdfTextRect> _ttsHighlightRects = const [];
  final ValueNotifier<List<PdfTextRect>> highlightRectsNotifier =
      ValueNotifier<List<PdfTextRect>>(const []);

  // Per-page cached sentences
  final Map<int, List<PdfSentence>> _pageSentencesCache = {};
  final Map<int, Future<List<PdfSentence>>> _inFlightSentenceLoads = {};

  DateTime _lastAutoPanAt = DateTime.fromMillisecondsSinceEpoch(0);
  TransformationController? pdfTransformController;

  TtsService get ttsService => _ttsService;
  bool get showTtsControls => _showTtsControls;
  bool get ttsContinuous => _ttsContinuous;
  bool get ttsFollowMode => _ttsFollowMode;
  bool get tapToStartEnabled => _tapToStartEnabled;
  List<PdfTextRect> get ttsHighlightRects => _ttsHighlightRects;
  int get highlightPageIndex => _speakingPage;
  PdfSentence? get currentSentence => _currentSentence;
  String get currentSentenceText => _currentSentence?.cleanText ?? '';

  // Backward-compatible properties
  PdfDocumentText? get documentText => null;
  bool get documentTextLoading => false;
  String? get ttsStartOverrideText => null;

  // ---------------------------------------------------------------------------
  // Sentence Extraction & Bounding Rect Calculation
  // ---------------------------------------------------------------------------

  /// Segment page text into sentences and compute gutter-safe line bounding rects.
  Future<List<PdfSentence>> getSentencesForPage(int pageIndex) {
    if (_pageSentencesCache.containsKey(pageIndex)) {
      return Future.value(_pageSentencesCache[pageIndex]!);
    }

    final inFlight = _inFlightSentenceLoads[pageIndex];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _loadSentencesForPageInternal(pageIndex);
    _inFlightSentenceLoads[pageIndex] = future;
    return future;
  }

  Future<List<PdfSentence>> _loadSentencesForPageInternal(int pageIndex) async {
    try {
      // Eagerly load both page text and character bounds in parallel
      await Future.wait([
        pageController.loadPageText(pageIndex),
        pageController.ensureCharacterBoundsLoaded(pageIndex),
      ]);
      if (_disposed) return const [];

      final sanitized = pageController.sanitizedTextCache[pageIndex] ??
          await pageController.loadSanitizedPageText(pageIndex);
      final bounds = pageController.pageCharBoundsCache[pageIndex] ?? const [];

      if (sanitized == null || sanitized.cleanText.trim().isEmpty || bounds.isEmpty) {
        // Page genuinely has zero readable characters (e.g. blank page or illustration)
        _pageSentencesCache[pageIndex] = const [];
        return const [];
      }

      final cleanText = sanitized.cleanText;
      final map = sanitized.cleanToPdfMap;
      final spans = splitIntoSentences(cleanText);
      final sentences = <PdfSentence>[];

      for (var i = 0; i < spans.length; i++) {
        final span = spans[i];
        if (span.start >= cleanText.length || span.end <= span.start) continue;

        final sentenceClean = cleanText.substring(span.start, span.end.clamp(span.start, cleanText.length)).trim();
        if (sentenceClean.isEmpty) continue;

        final lineRects = _computeSentenceRectsFromCleanOffsets(bounds, map, span.start, span.end);

        sentences.add(PdfSentence(
          pageIndex: pageIndex,
          sentenceIndex: sentences.length,
          charStart: span.start,
          charEnd: span.end,
          pageCleanStartOffset: span.start,
          rawText: sentenceClean,
          cleanText: sentenceClean,
          rects: lineRects,
        ));
      }

      _pageSentencesCache[pageIndex] = sentences;
      return sentences;
    } catch (e) {
      // DO NOT cache transient failures so subsequent attempts can retry!
      debugPrint('PdfTtsController: Error loading sentences for page $pageIndex: $e');
      return const [];
    } finally {
      _inFlightSentenceLoads.remove(pageIndex);
    }
  }

  /// Computes line bounding rects mapped from clean UTF-16 text offsets to PDF glyph bounds.
  List<PdfTextRect> _computeSentenceRectsFromCleanOffsets(
    List<PdfTextRect> charBounds,
    List<int> cleanToPdfMap,
    int cleanStart,
    int cleanEnd,
  ) {
    final validRects = <PdfTextRect>[];
    final mapLen = cleanToPdfMap.length;
    final boundsLen = charBounds.length;

    for (var i = cleanStart; i < cleanEnd && i < mapLen; i++) {
      final pdfIdx = cleanToPdfMap[i];
      if (pdfIdx >= boundsLen) continue;
      final r = charBounds[pdfIdx];
      if (r.left == 0 && r.top == 0 && r.right == 0 && r.bottom == 0) continue;
      if ((r.right - r.left) <= 0 || (r.bottom - r.top) <= 0) continue;
      validRects.add(r);
    }
    if (validRects.isEmpty) return const [];

    return _groupRectsIntoLines(validRects);
  }

  List<PdfTextRect> _groupRectsIntoLines(List<PdfTextRect> validRects) {
    final lineRects = <PdfTextRect>[];

    var lineLeft = validRects[0].left;
    var lineTop = validRects[0].top;
    var lineRight = validRects[0].right;
    var lineBottom = validRects[0].bottom;

    for (var i = 1; i < validRects.length; i++) {
      final r = validRects[i];
      final lineHeight = lineBottom - lineTop;
      final sameLine = (r.top - lineTop).abs() < (lineHeight > 0 ? lineHeight * 0.6 : 0.02);

      final avgCharWidth = (lineRight - lineLeft) / i.clamp(1, 50);
      final gutterThreshold = (avgCharWidth * 2.5).clamp(0.04, 0.15);
      final isGutterJump = sameLine && (r.left - lineRight > gutterThreshold);

      if (sameLine && !isGutterJump) {
        if (r.left < lineLeft) lineLeft = r.left;
        if (r.top < lineTop) lineTop = r.top;
        if (r.right > lineRight) lineRight = r.right;
        if (r.bottom > lineBottom) lineBottom = r.bottom;
      } else {
        lineRects.add(PdfTextRect(
          left: lineLeft,
          top: lineTop,
          right: lineRight,
          bottom: lineBottom,
        ));
        lineLeft = r.left;
        lineTop = r.top;
        lineRight = r.right;
        lineBottom = r.bottom;
      }
    }
    lineRects.add(PdfTextRect(
      left: lineLeft,
      top: lineTop,
      right: lineRight,
      bottom: lineBottom,
    ));

    return lineRects;
  }

  // ---------------------------------------------------------------------------
  // Hit-Testing for Tap Gestures
  // ---------------------------------------------------------------------------

  /// Check whether a normalized (0.0 to 1.0) point on [pageIndex] falls over a sentence.
  Future<PdfSentence?> hitTestSentence(int pageIndex, Offset normalizedPoint) async {
    final sentences = await getSentencesForPage(pageIndex);
    if (sentences.isEmpty) return null;

    for (final sentence in sentences) {
      for (final rect in sentence.rects) {
        final expanded = Rect.fromLTRB(
          rect.left - 0.02,
          rect.top - 0.015,
          rect.right + 0.02,
          rect.bottom + 0.015,
        );
        if (expanded.contains(normalizedPoint)) {
          return sentence;
        }
      }
    }
    return null;
  }

  /// Start speaking immediately from the sentence containing [normalizedPoint].
  Future<bool> startTtsFromPoint(int pageIndex, Offset normalizedPoint) async {
    if (_disposed) return false;
    final sentences = await getSentencesForPage(pageIndex);
    if (sentences.isEmpty) return false;

    PdfSentence? matched;
    for (final sentence in sentences) {
      for (final rect in sentence.rects) {
        final expanded = Rect.fromLTRB(
          rect.left - 0.02,
          rect.top - 0.015,
          rect.right + 0.02,
          rect.bottom + 0.015,
        );
        if (expanded.contains(normalizedPoint)) {
          matched = sentence;
          break;
        }
      }
      if (matched != null) break;
    }

    if (matched == null) {
      // Vertical distance fallback for taps slightly between lines
      double minDistance = double.infinity;
      for (final sentence in sentences) {
        if (sentence.rects.isEmpty) continue;
        final top = sentence.rects.first.top;
        final bottom = sentence.rects.last.bottom;
        final dist = (normalizedPoint.dy < top)
            ? (top - normalizedPoint.dy)
            : (normalizedPoint.dy > bottom ? normalizedPoint.dy - bottom : 0.0);
        if (dist < minDistance && dist < 0.08) {
          minDistance = dist;
          matched = sentence;
        }
      }
    }

    if (matched != null) {
      _showTtsControls = true;
      await _speakSentence(pageIndex, matched.sentenceIndex);
      return true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // Playback Control
  // ---------------------------------------------------------------------------

  Future<void> play() async {
    if (_disposed) return;
    if (_ttsService.state == TtsState.stopped && _speakingPage != pageController.pageIndex) {
      _speakingPage = pageController.pageIndex;
      _speakingSentenceIndex = 0;
    }
    if (_speakingPage < 0 || _speakingPage >= pageController.pageCount) {
      _speakingPage = pageController.pageIndex;
      _speakingSentenceIndex = 0;
    }
    await _speakSentence(_speakingPage, _speakingSentenceIndex);
  }

  Future<void> _speakSentence(int pageIndex, int sentenceIndex) async {
    if (_disposed) return;

    final sentences = await getSentencesForPage(pageIndex);
    if (sentences.isEmpty) {
      // Page has no readable text; advance to next page if continuous
      if (_ttsContinuous && pageIndex + 1 < pageController.pageCount) {
        return _speakSentence(pageIndex + 1, 0);
      } else {
        await stop();
        return;
      }
    }

    final targetIndex = sentenceIndex.clamp(0, sentences.length - 1);
    final sentence = sentences[targetIndex];

    _speakingPage = pageIndex;
    _speakingSentenceIndex = targetIndex;
    _currentSentence = sentence;
    _ttsHighlightRects = sentence.rects;
    highlightRectsNotifier.value = sentence.rects;

    saveCurrentTtsSentence();
    notifyListeners();

    _maybeAutoPanToHighlight(sentence);
    await _ttsService.speak(sentence.cleanText);
  }

  void _handleTtsFinished() {
    if (_disposed) return;
    if (_ttsService.state == TtsState.paused || _ttsService.state == TtsState.stopped) {
      return;
    }

    unawaited(_advanceToNextSentence());
  }

  Future<void> _advanceToNextSentence() async {
    if (_disposed) return;

    final sentences = await getSentencesForPage(_speakingPage);
    if (_speakingSentenceIndex + 1 < sentences.length) {
      await _speakSentence(_speakingPage, _speakingSentenceIndex + 1);
    } else if (_ttsContinuous && _speakingPage + 1 < pageController.pageCount) {
      final nextPage = _speakingPage + 1;
      if (!pageController.isContinuousMode) {
        await pageController.renderPage(nextPage, userInitiated: false);
      }
      await _speakSentence(nextPage, 0);
    } else {
      await stop();
    }
  }

  Future<void> previousSentence() async {
    if (_speakingSentenceIndex > 0) {
      await _speakSentence(_speakingPage, _speakingSentenceIndex - 1);
    } else if (_speakingPage > 0) {
      final prevPage = _speakingPage - 1;
      final prevSentences = await getSentencesForPage(prevPage);
      final lastIdx = (prevSentences.length - 1).clamp(0, 999999);
      if (!pageController.isContinuousMode) {
        await pageController.renderPage(prevPage, userInitiated: false);
      }
      await _speakSentence(prevPage, lastIdx);
    }
  }

  Future<void> nextSentence() async {
    await _advanceToNextSentence();
  }

  Future<void> pause() async {
    saveCurrentTtsSentence();
    await _ttsService.pause();
    notifyListeners();
  }

  Future<void> stop() async {
    saveCurrentTtsSentence();
    _ttsHighlightRects = const [];
    highlightRectsNotifier.value = const [];
    await _ttsService.stop();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Auto-Scroll (Follow Mode) without Canvas Scaling
  // ---------------------------------------------------------------------------

  void _maybeAutoPanToHighlight(PdfSentence sentence) {
    if (!_ttsFollowMode || sentence.rects.isEmpty) return;

    final now = DateTime.now();
    if (now.difference(_lastAutoPanAt) < const Duration(milliseconds: 100)) {
      return;
    }
    _lastAutoPanAt = now;

    if (pageController.isContinuousMode) {
      final sc = pageController.scrollController;
      if (sc.hasClients) {
        final isWebtoon = pageController.readingMode == ReadingMode.webtoon;
        final spacing = isWebtoon ? 1.0 : 12.0;
        final pageOffset = pageController.calculateEstimatedOffsetForPage(sentence.pageIndex, spacing);
        final sentenceTop = sentence.rects.first.top;
        final pageHeight = pageController.renderedPageSize.height > 0
            ? pageController.renderedPageSize.height
            : (pageController.viewerSize.width * 1.4);
        final targetScroll = (pageOffset + (sentenceTop * pageHeight)) - (pageController.viewerSize.height * 0.35);
        sc.animateTo(
          targetScroll.clamp(0.0, sc.position.maxScrollExtent),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    } else {
      if (sentence.pageIndex != pageController.pageIndex) {
        pageController.renderPage(sentence.pageIndex, userInitiated: false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Position Persistence
  // ---------------------------------------------------------------------------

  void saveCurrentTtsSentence() {
    if (_speakingPage < 0) return;

    unawaited(repository.updateReadingProgress(
      book.id,
      currentPage: pageController.pageIndex,
      totalPages: pageController.pageCount,
      lastTtsSentenceStart: _speakingSentenceIndex,
      lastTtsSentenceEnd: _speakingSentenceIndex,
      lastTtsPage: _speakingPage,
    ));
  }

  // ---------------------------------------------------------------------------
  // TtsControlsSheet Integration
  // ---------------------------------------------------------------------------

  String resolveTtsText() {
    if (_currentSentence != null && _currentSentence!.cleanText.isNotEmpty) {
      return _currentSentence!.cleanText;
    }
    return pageController.currentPageText;
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

  void setTtsControlsVisible(bool visible) {
    if (_showTtsControls == visible) return;
    _showTtsControls = visible;
    notifyListeners();
  }

  Future<void> toggleTts() async {
    final next = !_showTtsControls;
    _showTtsControls = next;
    notifyListeners();

    if (!next) {
      await stop();
    } else {
      if (_ttsService.state == TtsState.stopped) {
        await play();
      }
    }
  }

  void closeTtsControls() {
    _showTtsControls = false;
    stop();
  }

  Future<void> startTtsFromTap(Offset localOffset, Size imageSize) async {
    if (_disposed || imageSize.isEmpty) return;
    final xNorm = (localOffset.dx / imageSize.width).clamp(0.0, 1.0);
    final yNorm = (localOffset.dy / imageSize.height).clamp(0.0, 1.0);
    await startTtsFromPoint(pageController.pageIndex, Offset(xNorm, yNorm));
  }

  Future<void> startSpeakingOverride(String text) async {
    _showTtsControls = true;
    notifyListeners();
    await _ttsService.speak(text);
  }

  @override
  void dispose() {
    _disposed = true;
    pageController.removeListener(_onPageControllerUpdated);
    _ttsService.removeListener(_onTtsServiceUpdated);
    _ttsService.setOnFinished(null);
    unawaited(_ttsService.stop());
    highlightRectsNotifier.dispose();
    super.dispose();
  }
}
