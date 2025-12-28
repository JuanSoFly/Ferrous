import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/core/utils/sentence_utils.dart';
import 'package:reader_app/core/utils/normalized_text_map.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:reader_app/core/utils/dom_text_utils.dart';
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
  // Raw text offset where TTS text starts in currentPlainText
  int _ttsRawBaseOffset = 0;
  // Map to convert TTS normalized positions back to raw text positions
  NormalizedTextMap? _ttsNormalizationMap;
  final GlobalKey _ttsHighlightKey = GlobalKey();
  bool highlightKeyAssigned = false;

  int? _lastHighlightStart;
  int? _lastHighlightEnd;
  int? _lastEnsuredStart;
  int? _lastEnsuredEnd;
  String? _cachedHighlightedHtml;

  late int _lastTtsSentenceStart;
  late int _lastTtsSentenceEnd;
  late int _lastTtsSection;

  static const String _ttsHighlightTag = 'tts-highlight';

  // Getters
  TtsService get ttsService => _ttsService;
  bool get showTtsControls => _showTtsControls;
  bool get ttsContinuous => _ttsContinuous;
  bool get ttsFollowMode => _ttsFollowMode;
  bool get tapToStartEnabled => _tapToStartEnabled;
  GlobalKey get ttsHighlightKey => _ttsHighlightKey;
  int? get lastHighlightStart => _lastHighlightStart;
  int? get lastHighlightEnd => _lastHighlightEnd;

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
      _ttsAdvanceRequestId++;
      _cachedHighlightedHtml = null;
      _lastHighlightStart = null;
      _lastHighlightEnd = null;
      unawaited(_ttsService.stop());
      return;
    }

    // Jump to saved TTS position if available
    if (_lastTtsSentenceStart >= 0 &&
        _lastTtsSection >= 0 &&
        _lastTtsSection != chapterController.currentChapterIndex) {
      await chapterController.loadChapter(_lastTtsSection, userInitiated: false);
    }

    // Only prepare TTS state, don't auto-play
    // User must explicitly click play button to start
  }

  void _handleTtsFinished() {
    if (!_showTtsControls || !_ttsContinuous) return;
    unawaited(advanceToNextReadableChapterAndSpeak());
  }

  void _handleTtsProgress() {
    if (!_showTtsControls || _ttsService.state != TtsState.playing) {
      _cachedHighlightedHtml = null;
      _lastHighlightStart = null;
      _lastHighlightEnd = null;
      notifyListeners();
      return;
    }

    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart == null || wordEnd == null) return;

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
    final rawWordEnd = map.normalizedToRaw[clampedEnd - 1] + 1;
    
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
      _ttsRawBaseOffset = 0;
      _ttsNormalizationMap = buildNormalizedTextMap(rawText);
      
      await _ttsService.speak(_ttsNormalizationMap!.normalized);
      return;
    }
  }

  String buildTtsHighlightedHtml(String html) {
    // Use the raw positions already computed in _handleTtsProgress
    final highlightStart = _lastHighlightStart;
    final highlightEnd = _lastHighlightEnd;
    if (highlightStart == null || highlightEnd == null) return html;

    if (_cachedHighlightedHtml != null) {
      return _cachedHighlightedHtml!;
    }

    final highlighted = _buildHighlightedHtmlAround(html, highlightStart, highlightEnd);
    _cachedHighlightedHtml = highlighted;
    return highlighted;
  }

  String _buildHighlightedHtmlAround(String html, int rawStart, int rawEnd) {
    if (rawStart < 0 || rawEnd <= rawStart) return html;

    final document = html_parser.parse(html);
    final root = document.body ?? document.documentElement;
    if (root == null) return html;

    // Use DomTextUtils for consistent text extraction with block spacing
    final textNodes = DomTextUtils.collectTextNodes(root);
    if (textNodes.isEmpty) return html;

    // Iterate through text nodes and find which node contains the highlight range.
    // Positions are already in raw text space (matching currentPlainText).
    var offset = 0;
    for (final node in textNodes) {
      final nodeText = node.data;
      final nodeStart = offset;
      final nodeEnd = offset + nodeText.length;
      offset = nodeEnd;

      // Skip nodes that don't overlap with highlight range
      if (rawEnd <= nodeStart || rawStart >= nodeEnd) continue;

      // Skip synthetic nodes (block separators) - they can't be modified in DOM
      if (node.parent == null) continue;

      // Calculate local positions within this node
      final localStart = (rawStart - nodeStart).clamp(0, nodeText.length);
      final localEnd = (rawEnd - nodeStart).clamp(0, nodeText.length);

      if (localStart >= localEnd) continue;

      final before = nodeText.substring(0, localStart);
      final mid = nodeText.substring(localStart, localEnd);
      final after = nodeText.substring(localEnd);

      final parent = node.parent;
      if (parent == null) continue;

      final index = parent.nodes.indexOf(node);
      if (index < 0) continue;

      final newNodes = <dom.Node>[];
      if (before.isNotEmpty) newNodes.add(dom.Text(before));
      if (mid.isNotEmpty) {
        final mark = dom.Element.tag(_ttsHighlightTag);
        mark.append(dom.Text(mid));
        newNodes.add(mark);
      }
      if (after.isNotEmpty) newNodes.add(dom.Text(after));

      parent.nodes.removeAt(index);
      parent.nodes.insertAll(index, newNodes);
      
      // Break after first match for simplicity
      break;
    }

    return root.outerHtml;
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
      _ttsRawBaseOffset = 0;
      _ttsNormalizationMap = buildNormalizedTextMap(rawText);
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
  TapDetectionResult? detectWordAtTap(TapUpDetails details, {required ReaderModeController modeController, required BuildContext context}) {
    if (!_showTtsControls || !_tapToStartEnabled) return null;
    if (chapterController.allChapterPlainTexts.isEmpty) return null;

    final tap = details.globalPosition;
    final chapterIndex = _findChapterIndexAtTap(tap, modeController: modeController, context: context) ?? 
                         chapterController.currentChapterIndex.clamp(0, chapterController.allChapterPlainTexts.length - 1);
    
    final chapterText = chapterController.allChapterPlainTexts[chapterIndex];
    if (chapterText.trim().isEmpty) return null;

    final hit = _hitTestTextAt(tap, context: context);
    int? absoluteOffset;
    String? detectedWord;

    if (hit != null) {
      final rawFragment = hit.rawText;
      if (rawFragment.trim().isNotEmpty) {
        final fragmentMap = buildNormalizedTextMap(rawFragment);
        final fragment = fragmentMap.normalized;

        if (fragment.isNotEmpty) {
          var approxIndex = 0;
          if (modeController.isContinuousMode) {
            final ctx = chapterController.chapterKeys[chapterIndex].currentContext;
            final chapterBox = ctx?.findRenderObject() as RenderBox?;
            if (chapterBox != null && chapterBox.hasSize) {
              final topLeft = chapterBox.localToGlobal(Offset.zero);
              final dy = (tap.dy - topLeft.dy).clamp(0.0, chapterBox.size.height);
              final frac = chapterBox.size.height <= 0 ? 0.0 : (dy / chapterBox.size.height).clamp(0.0, 1.0);
              approxIndex = (frac * (chapterText.length - 1)).floor().clamp(0, chapterText.length - 1);
            }
          }

          final startFrom = approxIndex.clamp(0, chapterText.length);
          final forward = chapterText.indexOf(fragment, startFrom);
          final backward = chapterText.lastIndexOf(fragment, startFrom);

          final fragmentStart = switch ((forward, backward)) {
            (int f, int b) when f >= 0 && b >= 0 => (f - startFrom).abs() < (b - startFrom).abs() ? f : b,
            (int f, _) when f >= 0 => f,
            (_, int b) when b >= 0 => b,
            _ => null,
          };

          if (fragmentStart != null) {
            final fragmentOffset = _normalizedOffsetForRawOffset(fragmentMap, hit.rawOffset);
            absoluteOffset = _wordStartForOffset(chapterText, fragmentStart + fragmentOffset);
            
            // Extract the detected word for display
            if (absoluteOffset < chapterText.length) {
              final wordEnd = _findWordEnd(chapterText, absoluteOffset);
              detectedWord = chapterText.substring(absoluteOffset, wordEnd).trim();
            }
          }
        }
      }
    }

    if (absoluteOffset != null && detectedWord != null && detectedWord.isNotEmpty) {
      return TapDetectionResult(
        word: detectedWord,
        chapterIndex: chapterIndex,
        offset: absoluteOffset,
        tapPosition: tap,
      );
    }
    return null;
  }

  /// Find the end of a word starting at [start].
  int _findWordEnd(String text, int start) {
    var end = start;
    while (end < text.length && text[end].trim().isNotEmpty) {
      end++;
    }
    return end;
  }

  /// Speak from a confirmed location (called after user confirms tap selection).
  Future<void> speakFromLocation({
    required int chapterIndex,
    required int offset,
  }) async {
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
    final result = detectWordAtTap(details, modeController: modeController, context: context);
    if (result != null) {
      await speakFromLocation(chapterIndex: result.chapterIndex, offset: result.offset);
    } else {
      // Fallback
      final text = resolveTtsText(modeController: modeController);
      await _speakFromHere(text);
    }
  }

  Future<void> _speakFromHere(String startText, {int? baseOffset}) async {
    if (startText.trim().isEmpty) return;

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
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, globalPosition, View.of(context).viewId);

    for (final entry in result.path) {
      final target = entry.target;
      if (target is RenderParagraph) {
        final local = target.globalToLocal(globalPosition);
        final position = target.getPositionForOffset(local);
        return (rawText: target.text.toPlainText(), rawOffset: position.offset);
      }
    }
    return null;
  }

  int _normalizedOffsetForRawOffset(NormalizedTextMap map, int rawOffset) {
    if (map.normalizedToRaw.isEmpty) return 0;
    if (rawOffset <= 0) return 0;
    if (rawOffset > map.normalizedToRaw.last) return map.normalizedToRaw.length;

    var lo = 0;
    var hi = map.normalizedToRaw.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (map.normalizedToRaw[mid] <= rawOffset) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return (lo - 1).clamp(0, map.normalizedToRaw.length);
  }

  int _wordStartForOffset(String text, int offset) {
    if (text.isEmpty) return 0;
    var i = offset.clamp(0, text.length);
    if (i >= text.length) return text.length;
    while (i < text.length && text[i].trim().isEmpty) { i++; }
    if (i >= text.length) return text.length;
    var start = i;
    while (start > 0 && text[start - 1].trim().isNotEmpty) { start--; }
    return start;
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
      alignment: 0.3,
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

  void closeTtsControls() {
    _ttsAdvanceRequestId++;
    _showTtsControls = false;
    _cachedHighlightedHtml = null;
    _lastHighlightStart = null;
    _lastHighlightEnd = null;
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
