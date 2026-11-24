import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/data/repositories/book_repository.dart';
import 'package:ferrous/data/services/tts_service.dart';
import 'package:ferrous/core/utils/sentence_utils.dart';
import 'package:ferrous/core/utils/normalized_text_map.dart';
import 'package:ferrous/core/utils/text_offset_resolver.dart';
import 'package:ferrous/features/reader/html_tts_highlight_helper.dart';
import 'epub_chapter_controller.dart';
import 'reader_mode_controller.dart';

class EpubTtsController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;
  final TtsService _ttsService;
  final EpubChapterController chapterController;

  EpubTtsController({
    required this.book,
    required this.repository,
    required TtsService ttsService,
    required this.chapterController,
  }) : _ttsService = ttsService {
    _ttsService.setOnFinished(_handleTtsFinished);
    _ttsService.addListener(_handleTtsProgress);

    _lastTtsSentenceStart = book.lastTtsSentenceStart;
    _lastTtsSentenceEnd = book.lastTtsSentenceEnd;
    _lastTtsSection = book.lastTtsSection;
  }

  bool _showTtsControls = false;
  bool _ttsContinuous = true;
  bool _ttsFollowMode = true;
  bool _tapToStartEnabled = true;

  int _ttsAdvanceRequestId = 0;
  bool _isStartingSpeech = false;
  // Raw text offset where TTS text starts in currentPlainText
  int _ttsRawBaseOffset = 0;
  // Map to convert TTS normalized positions back to raw text positions
  NormalizedTextMap? _ttsNormalizationMap;
  final GlobalKey _ttsHighlightKey = GlobalKey();
  bool highlightKeyAssigned = false;

  int? _speakingChapterIndex;
  int? _lastHighlightStart;
  int? _lastHighlightEnd;
  int? _lastEnsuredStart;
  int? _lastEnsuredEnd;
  String? _cachedHighlightedHtml;
  String? _lastHighlightedSourceHtml;
  int? _lastMatchedDomOffset;
  int? _lastMatchedSourceHash;
  int? _lastMatchedChapterIndex;
  int? _lastMatchedSliceOffset;
  int? _lastMatchedSentenceStart;
  int? _lastMatchedChapterRawStart;
  List<SentenceSpan>? _cachedChapterSentences;
  int? _cachedChapterSentencesIndex;

  late int _lastTtsSentenceStart;
  late int _lastTtsSentenceEnd;
  late int _lastTtsSection;

  // Getters
  TtsService get ttsService => _ttsService;
  bool get showTtsControls => _showTtsControls;
  bool get ttsContinuous => _ttsContinuous;
  bool get ttsFollowMode => _ttsFollowMode;
  bool get tapToStartEnabled => _tapToStartEnabled;
  GlobalKey get ttsHighlightKey => _ttsHighlightKey;
  int? get speakingChapterIndex => _speakingChapterIndex;
  int? get lastHighlightStart => _lastHighlightStart;
  int? get lastHighlightEnd => _lastHighlightEnd;
  int? get lastMatchedDomOffset => _lastMatchedDomOffset;

  void resetDomCursor() {
    _lastMatchedDomOffset = null;
    _lastMatchedSourceHash = null;
    _lastMatchedChapterIndex = null;
    _lastMatchedSliceOffset = null;
    _lastMatchedSentenceStart = null;
    _lastMatchedChapterRawStart = null;
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

  /// Set TTS controls visibility without stopping playback.
  /// Use this for hiding UI while TTS continues in background.
  void setTtsControlsVisible(bool visible) {
    if (_showTtsControls == visible) return;
    _showTtsControls = visible;
    notifyListeners();
  }

  Future<void> toggleTts({required ReaderModeController modeController}) async {
    final next = !_showTtsControls;
    _showTtsControls = next;
    notifyListeners();

    if (!next) {
      saveCurrentTtsSentence();
      _isStartingSpeech = false;
      _ttsAdvanceRequestId++;
      _cachedHighlightedHtml = null;
      _lastHighlightStart = null;
      _lastHighlightEnd = null;
      _speakingChapterIndex = null;
      resetDomCursor();
      unawaited(_ttsService.stop());
      return;
    }

    // Jump to saved TTS position if available (only when starting from stopped)
    if (_ttsService.state == TtsState.stopped &&
        _lastTtsSentenceStart >= 0 &&
        _lastTtsSection >= 0 &&
        _lastTtsSection != chapterController.currentChapterIndex) {
      await chapterController.loadChapter(_lastTtsSection, userInitiated: false);
    }

    // Only prepare TTS state, don't auto-play
    // User must explicitly click play button to start
  }

  void _handleTtsFinished() {
    if (!_ttsContinuous) return;
    unawaited(advanceToNextReadableChapterAndSpeak());
  }

  void _handleTtsProgress() {
    if (_ttsService.state == TtsState.stopped) {
      // Ignore transient stop events while a new speech session is initializing
      if (_isStartingSpeech) return;
      _cachedHighlightedHtml = null;
      _lastHighlightStart = null;
      _lastHighlightEnd = null;
      _speakingChapterIndex = null;
      resetDomCursor();
      notifyListeners();
      return;
    }

    if (_ttsService.state == TtsState.playing) {
      _isStartingSpeech = false;
    }

    if (_ttsService.state != TtsState.playing) {
      return;
    }

    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart == null || wordEnd == null) return;
    _isStartingSpeech = false;

    // Convert TTS normalized positions to raw text positions for highlighting
    final map = _ttsNormalizationMap;
    if (map == null || map.normalizedToRaw.isEmpty) return;

    // Clamp to valid range
    final maxIdx = map.normalizedToRaw.length;
    final clampedStart = wordStart.clamp(0, maxIdx - 1);
    final clampedEnd = wordEnd.clamp(0, maxIdx);
    if (clampedEnd <= clampedStart) return;

    // Convert to raw positions and add base offset
    final rawWordStart = map.normalizedToRaw[clampedStart];
    final rawWordEnd = clampedEnd < map.normalizedToRaw.length
        ? map.normalizedToRaw[clampedEnd]
        : map.normalizedToRaw[clampedEnd - 1] + 1;
    
    final highlightStart = _ttsRawBaseOffset + rawWordStart;
    final highlightEnd = _ttsRawBaseOffset + rawWordEnd;

    if (highlightStart == _lastHighlightStart && highlightEnd == _lastHighlightEnd) {
      return;
    }

    _lastHighlightStart = highlightStart;
    _lastHighlightEnd = highlightEnd;
    
    // Clear cached HTML to force regeneration with new highlight
    _cachedHighlightedHtml = null;
    
    // Save reading progress (RAW positions for persistence)
    _lastTtsSentenceStart = highlightStart;
    _lastTtsSentenceEnd = highlightEnd;
    _lastTtsSection = chapterController.currentChapterIndex;

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: chapterController.currentChapterIndex,
      totalPages: chapterController.chapters?.length ?? 0,
      lastTtsSentenceStart: highlightStart,
      lastTtsSentenceEnd: highlightEnd,
      lastTtsSection: chapterController.currentChapterIndex,
    ));

    // Always notify listeners for UI update
    notifyListeners();
    
    // Ensure highlight is visible if follow mode is enabled
    maybeEnsureHighlightVisible();
  }

  Future<void> advanceToNextReadableChapterAndSpeak() async {
    if (chapterController.chapters == null) return;

    final startIndex = chapterController.currentChapterIndex + 1;
    if (startIndex >= chapterController.chapters!.length) return;

    final requestId = ++_ttsAdvanceRequestId;

    for (var index = startIndex; index < chapterController.chapters!.length; index++) {
      await chapterController.loadChapter(index, userInitiated: false);
      if (requestId != _ttsAdvanceRequestId) return;

      final rawText = chapterController.currentPlainText;
      if (rawText.trim().isEmpty) continue;

      // Set up for TTS with raw text starting from beginning
      _speakingChapterIndex = index;
      _ttsRawBaseOffset = 0;
      resetDomCursor();
      _ttsNormalizationMap = buildNormalizedTextMap(rawText);
      
      await _ttsService.speak(_ttsNormalizationMap!.normalized);
      return;
    }
  }

  List<SentenceSpan> _getChapterSentences(int chapterIndex, String chapterText) {
    if (_cachedChapterSentencesIndex == chapterIndex && _cachedChapterSentences != null) {
      return _cachedChapterSentences!;
    }
    final sentences = splitIntoSentences(chapterText);
    _cachedChapterSentences = sentences;
    _cachedChapterSentencesIndex = chapterIndex;
    return sentences;
  }

  String buildTtsHighlightedHtml(
    String html, {
    int? overrideStart,
    int? overrideEnd,
    int? chapterRawStart,
    int? chapterRawEnd,
  }) {
    final highlightStart = overrideStart ?? _lastHighlightStart;
    final highlightEnd = overrideEnd ?? _lastHighlightEnd;
    if (highlightStart == null || highlightEnd == null) return html;

    if (_cachedHighlightedHtml != null && _lastHighlightedSourceHtml == html) {
      return _cachedHighlightedHtml!;
    }

    final effectiveChapter = _speakingChapterIndex ?? chapterController.currentChapterIndex;
    final chapterText = (effectiveChapter >= 0 && effectiveChapter < chapterController.allChapterPlainTexts.length)
        ? chapterController.allChapterPlainTexts[effectiveChapter]
        : chapterController.currentPlainText;

    final rawWordStart = chapterRawStart ?? _lastHighlightStart ?? highlightStart;
    final rawWordEnd = chapterRawEnd ?? _lastHighlightEnd ?? highlightEnd;

    final sliceStartOffset = (chapterRawStart != null && overrideStart != null)
        ? (chapterRawStart - overrideStart)
        : 0;

    final sentences = _getChapterSentences(effectiveChapter, chapterText);
    final sentenceSpan = sentenceForOffset(sentences, rawWordStart);

    String? sentenceText;
    int? sentenceLocalStart;
    int? sentenceLocalEnd;
    int? wordOffsetInSentence;

    if (sentenceSpan != null) {
      final safeStart = sentenceSpan.start.clamp(0, chapterText.length);
      final safeEnd = sentenceSpan.end.clamp(safeStart, chapterText.length);
      sentenceText = chapterText.substring(safeStart, safeEnd);
      sentenceLocalStart = sentenceSpan.start - sliceStartOffset;
      sentenceLocalEnd = sentenceSpan.end - sliceStartOffset;
      wordOffsetInSentence = (rawWordStart - sentenceSpan.start).clamp(0, sentenceSpan.end - sentenceSpan.start);
    }

    final sourceHash = html.hashCode;
    final chapterChanged = _lastMatchedChapterIndex != effectiveChapter;
    final sliceChanged = _lastMatchedSliceOffset != sliceStartOffset;
    final hashChanged = _lastMatchedSourceHash != sourceHash;
    final backwardSeek = (_lastMatchedChapterRawStart != null && rawWordStart < _lastMatchedChapterRawStart!) ||
        (_lastMatchedSentenceStart != null && sentenceSpan != null && sentenceSpan.start < _lastMatchedSentenceStart!);

    if (chapterChanged || sliceChanged || hashChanged || backwardSeek) {
      _lastMatchedDomOffset = null;
      _lastMatchedSourceHash = sourceHash;
      _lastMatchedChapterIndex = effectiveChapter;
      _lastMatchedSliceOffset = sliceStartOffset;
      _lastMatchedChapterRawStart = rawWordStart;
      _lastMatchedSentenceStart = sentenceSpan?.start;
    }

    int? minForwardDomOffset;
    if (_lastMatchedDomOffset != null) {
      if (_lastMatchedChapterRawStart != null && rawWordStart > _lastMatchedChapterRawStart!) {
        minForwardDomOffset = _lastMatchedDomOffset! + 1;
      } else {
        minForwardDomOffset = _lastMatchedDomOffset;
      }
    }

    final targetWord = HtmlTtsHighlightHelper.resolveExpectedWord(
      ttsServiceWord: _ttsService.currentWord,
      chapterPlainText: chapterText,
      chapterRawStart: rawWordStart,
      chapterRawEnd: rawWordEnd,
    );

    final prevWord = HtmlTtsHighlightHelper.extractPrevWord(
      chapterText,
      rawWordStart,
      sentenceStart: sentenceSpan?.start,
    );
    final nextWord = HtmlTtsHighlightHelper.extractNextWord(
      chapterText,
      rawWordEnd,
      sentenceEnd: sentenceSpan?.end,
    );

    final highlighted = HtmlTtsHighlightHelper.buildHighlightedHtml(
      html: html,
      rawStart: highlightStart,
      rawEnd: highlightEnd,
      expectedWord: targetWord,
      prevWord: prevWord,
      nextWord: nextWord,
      minForwardDomOffset: minForwardDomOffset,
      sentenceText: sentenceText,
      sentenceLocalStart: sentenceLocalStart,
      sentenceLocalEnd: sentenceLocalEnd,
      wordOffsetInSentence: wordOffsetInSentence,
      onMatchedDomOffset: (offset) {
        if (_lastMatchedDomOffset == null || offset >= _lastMatchedDomOffset!) {
          _lastMatchedDomOffset = offset;
          _lastMatchedChapterRawStart = rawWordStart;
          _lastMatchedChapterIndex = effectiveChapter;
          _lastMatchedSliceOffset = sliceStartOffset;
          _lastMatchedSentenceStart = sentenceSpan?.start;
        }
      },
    );

    _lastHighlightedSourceHtml = html;
    _cachedHighlightedHtml = highlighted;
    return highlighted;
  }

  String resolveTtsText({required ReaderModeController modeController}) {
    final rawText = chapterController.currentPlainText;
    if (rawText.trim().isEmpty) return '';

    // Check if we have a saved position in raw text space
    if (_lastTtsSentenceStart >= 0 &&
        _lastTtsSentenceEnd > _lastTtsSentenceStart &&
        _lastTtsSection == chapterController.currentChapterIndex) {
      // Resume from saved raw position
      final start = _lastTtsSentenceStart.clamp(0, rawText.length);
      _ttsRawBaseOffset = start;
      
      final textToSpeak = rawText.substring(start);
      _ttsNormalizationMap = buildNormalizedTextMap(textToSpeak);
      return _ttsNormalizationMap!.normalized;
    }

    return _ttsTextFromScrollPosition(modeController: modeController);
  }

  String _ttsTextFromScrollPosition({required ReaderModeController modeController}) {
    final rawText = chapterController.currentPlainText;
    if (rawText.trim().isEmpty) return '';

    if (modeController.isPagedMode) {
      final rawStart = chapterController.activePageStartCharOffset >= 0
          ? chapterController.activePageStartCharOffset
          : (chapterController.lastReadingSentenceStart >= 0 ? chapterController.lastReadingSentenceStart : 0);
      final start = rawStart.clamp(0, rawText.length);
      _ttsRawBaseOffset = start;
      final textToSpeak = rawText.substring(start);
      _ttsNormalizationMap = buildNormalizedTextMap(textToSpeak);
      return _ttsNormalizationMap!.normalized;
    }

    final scrollController = chapterController.scrollController;
    if (!scrollController.hasClients) {
      _ttsRawBaseOffset = 0;
      _ttsNormalizationMap = buildNormalizedTextMap(rawText);
      return _ttsNormalizationMap!.normalized;
    }

    final maxExtent = scrollController.position.maxScrollExtent;
    final offset = scrollController.offset.clamp(0.0, maxExtent);
    final fraction = maxExtent <= 0 ? 0.0 : (offset / maxExtent);
    final maxIndex = rawText.length - 1;
    final approxIndex = maxIndex <= 0 ? 0 : (fraction * maxIndex).floor().clamp(0, maxIndex);
    
    // Find sentence start in raw text
    final start = findSentenceStart(rawText, approxIndex);
    _ttsRawBaseOffset = start;
    
    final textToSpeak = rawText.substring(start);
    _ttsNormalizationMap = buildNormalizedTextMap(textToSpeak);
    return _ttsNormalizationMap!.normalized;
  }

  /// Result of detecting a word at a tap position.
  /// Used for the tap-to-start confirmation flow.
  TapDetectionResult? detectWordAtTap({
    TapUpDetails? details,
    Offset? position,
    required ReaderModeController modeController,
    required BuildContext context,
  }) {
    if (!_tapToStartEnabled) return null;
    if (chapterController.allChapterPlainTexts.isEmpty) return null;

    final tap = position ?? details?.globalPosition;
    if (tap == null) return null;

    final chapterIndex = _findChapterIndexAtTap(tap, modeController: modeController, context: context) ?? 
                         chapterController.currentChapterIndex.clamp(0, chapterController.allChapterPlainTexts.length - 1);
    
    final chapterText = chapterController.allChapterPlainTexts[chapterIndex];
    if (chapterText.trim().isEmpty) return null;

    final hit = _hitTestTextAt(tap, context: context);
    if (hit == null || hit.rawText.trim().isEmpty) return null;

    final bounds = chapterController.getReadingBoundsForTap(
      tapDy: tap.dy,
      viewportHeight: MediaQuery.sizeOf(context).height,
      modeController: modeController,
      chapterLength: chapterText.length,
      tappedChapterIndex: chapterIndex,
    );

    final resolved = TextOffsetResolver.resolveExactOffset(
      chapterText: chapterText,
      rawParagraphFragment: hit.rawText,
      rawHitOffset: hit.rawOffset,
      windowStart: bounds.start,
      windowEnd: bounds.end,
      expectedOffset: bounds.expected,
      strictWindow: modeController.isPagedMode,
    );

    if (resolved != null) {
      return TapDetectionResult(
        word: resolved.word,
        chapterIndex: chapterIndex,
        offset: resolved.offset,
        tapPosition: tap,
      );
    }
    return null;
  }

  /// Find the end of a word starting at [start].
  int _findWordEnd(String text, int start) {
    return HtmlTtsHighlightHelper.findWordEnd(text, start);
  }

  /// Speak from a confirmed location (called after user confirms tap selection).
  Future<void> speakFromLocation({
    required int chapterIndex,
    required int offset,
  }) async {
    _speakingChapterIndex = chapterIndex;
    resetDomCursor();
    if (chapterIndex != chapterController.currentChapterIndex) {
      await chapterController.loadChapter(chapterIndex, userInitiated: false);
    }

    final chapterText = chapterController.allChapterPlainTexts[chapterIndex];
    if (offset >= 0 && offset < chapterText.length) {
      final startText = chapterText.substring(offset);
      await _speakFromHere(startText, baseOffset: offset);
    }
  }

  /// Legacy method for backward compatibility - immediately starts TTS from tap.
  Future<void> startTtsFromTap(TapUpDetails details, {required ReaderModeController modeController, required BuildContext context}) async {
    final result = detectWordAtTap(details: details, modeController: modeController, context: context);
    if (result != null) {
      await speakFromLocation(chapterIndex: result.chapterIndex, offset: result.offset);
    } else {
      // Fallback
      final text = resolveTtsText(modeController: modeController);
      await _speakFromHere(text);
    }
  }

  Future<void> startPlayback({required ReaderModeController modeController}) async {
    _speakingChapterIndex = chapterController.currentChapterIndex;
    resetDomCursor();
    final text = resolveTtsText(modeController: modeController);
    if (text.trim().isEmpty) return;

    final wordEnd = _findWordEnd(chapterController.currentPlainText, _ttsRawBaseOffset);
    _lastHighlightStart = _ttsRawBaseOffset;
    _lastHighlightEnd = wordEnd > _ttsRawBaseOffset ? wordEnd : _ttsRawBaseOffset + 1;
    _cachedHighlightedHtml = null;

    _isStartingSpeech = true;
    _showTtsControls = true;
    notifyListeners();

    await _ttsService.speak(text);
  }

  Future<void> _speakFromHere(String startText, {int? baseOffset}) async {
    if (startText.trim().isEmpty) return;
    _speakingChapterIndex ??= chapterController.currentChapterIndex;
    resetDomCursor();

    // Build normalization map from the text we're going to speak
    final map = buildNormalizedTextMap(startText);
    if (map.normalized.isEmpty) return;

    // Set the raw base offset
    if (baseOffset != null && baseOffset >= 0) {
      _ttsRawBaseOffset = baseOffset;
    } else {
      // Find raw offset by searching for the text in full chapter
      final fullRaw = chapterController.currentPlainText;
      final index = fullRaw.indexOf(startText);
      _ttsRawBaseOffset = index >= 0 ? index : 0;
    }
    
    // Store the normalization map for converting TTS positions back to raw
    _ttsNormalizationMap = map;

    _ttsAdvanceRequestId++;

    // Pre-seed highlight immediately on the initial word
    final wordEnd = _findWordEnd(chapterController.currentPlainText, _ttsRawBaseOffset);
    _lastHighlightStart = _ttsRawBaseOffset;
    _lastHighlightEnd = wordEnd > _ttsRawBaseOffset ? wordEnd : _ttsRawBaseOffset + 1;
    _cachedHighlightedHtml = null;

    _isStartingSpeech = true;
    _showTtsControls = true;
    notifyListeners();

    await _ttsService.speak(map.normalized);
  }

  int? _findChapterIndexAtTap(Offset globalPosition, {required ReaderModeController modeController, required BuildContext context}) {
    if (modeController.isPagedMode) return chapterController.currentChapterIndex;
    if (chapterController.chapterKeys.isEmpty) return null;

    for (var i = 0; i < chapterController.chapterKeys.length; i++) {
      final ctx = chapterController.chapterKeys[i].currentContext;
      final box = ctx?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final rect = topLeft & box.size;
      if (rect.contains(globalPosition)) return i;
    }
    return null;
  }

  ({String rawText, int rawOffset})? _hitTestTextAt(Offset globalPosition, {required BuildContext context}) {
    final viewId = View.of(context).viewId;
    const offsets = [
      Offset.zero,
      Offset(0, -6),
      Offset(0, 6),
      Offset(-6, 0),
      Offset(6, 0),
      Offset(0, -12),
      Offset(0, 12),
    ];

    for (final delta in offsets) {
      final result = HitTestResult();
      WidgetsBinding.instance.hitTestInView(result, globalPosition + delta, viewId);

      for (final entry in result.path) {
        final target = entry.target;
        if (target is RenderParagraph) {
          final local = target.globalToLocal(globalPosition + delta);
          final position = target.getPositionForOffset(local);
          return (rawText: target.text.toPlainText(), rawOffset: position.offset);
        }
      }
    }
    return null;
  }

  void maybeEnsureHighlightVisible() {
    if (!_ttsFollowMode) return;
    if (_lastHighlightStart == null || _lastHighlightEnd == null) return;
    if (_lastEnsuredStart == _lastHighlightStart && _lastEnsuredEnd == _lastHighlightEnd) return;

    final context = _ttsHighlightKey.currentContext;
    if (context == null) {
      Future.delayed(const Duration(milliseconds: 50), _retryEnsureVisible);
      return;
    }

    _performEnsureVisible(context);
  }

  void _retryEnsureVisible() {
    if (!_ttsFollowMode) return;
    final retryContext = _ttsHighlightKey.currentContext;
    if (retryContext == null) return;
    _performEnsureVisible(retryContext);
  }

  void _performEnsureVisible(BuildContext context) {
    _lastEnsuredStart = _lastHighlightStart;
    _lastEnsuredEnd = _lastHighlightEnd;

    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      alignment: 0.5,
    );
  }

  void saveCurrentTtsSentence() {
    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart == null || wordEnd == null) return;
    if (chapterController.currentPlainText.trim().isEmpty) return;

    // Convert TTS positions to raw text positions using stored map
    final map = _ttsNormalizationMap;
    if (map == null || map.normalizedToRaw.isEmpty) return;

    final maxIdx = map.normalizedToRaw.length;
    final clampedStart = wordStart.clamp(0, maxIdx - 1);
    final clampedEnd = wordEnd.clamp(0, maxIdx);
    if (clampedEnd <= clampedStart) return;

    // Convert to raw positions and add base offset
    final rawWordStart = map.normalizedToRaw[clampedStart];
    final rawWordEnd = map.normalizedToRaw[clampedEnd - 1] + 1;
    
    final absoluteStart = _ttsRawBaseOffset + rawWordStart;
    final absoluteEnd = _ttsRawBaseOffset + rawWordEnd;

    _lastTtsSentenceStart = absoluteStart;
    _lastTtsSentenceEnd = absoluteEnd;
    _lastTtsSection = chapterController.currentChapterIndex;

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: chapterController.currentChapterIndex,
      totalPages: chapterController.chapters?.length ?? 0,
      lastTtsSentenceStart: absoluteStart,
      lastTtsSentenceEnd: absoluteEnd,
      lastTtsSection: chapterController.currentChapterIndex,
    ));
  }

  void clearHighlight() {
    _cachedHighlightedHtml = null;
    _lastHighlightStart = null;
    _lastHighlightEnd = null;
    _speakingChapterIndex = null;
    resetDomCursor();
    notifyListeners();
  }

  void closeTtsControls() {
    _ttsAdvanceRequestId++;
    _isStartingSpeech = false;
    _showTtsControls = false;
    _cachedHighlightedHtml = null;
    _lastHighlightStart = null;
    _lastHighlightEnd = null;
    _speakingChapterIndex = null;
    resetDomCursor();
    notifyListeners();
  }

  @override
  void dispose() {
    _ttsService.setOnFinished(null);
    _ttsService.removeListener(_handleTtsProgress);
    // CRITICAL: Stop TTS when leaving reader screen
    unawaited(_ttsService.stop());
    super.dispose();
  }
}

/// Result of tap detection for confirmation flow.
class TapDetectionResult {
  final String word;
  final int chapterIndex;
  final int offset;
  final Offset tapPosition;

  const TapDetectionResult({
    required this.word,
    required this.chapterIndex,
    required this.offset,
    required this.tapPosition,
  });
}
