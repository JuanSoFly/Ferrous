import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/utils/sentence_utils.dart';
import 'package:reader_app/utils/normalized_text_map.dart';
import 'package:reader_app/utils/text_normalization.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
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
  int _ttsNormalizedBaseOffset = 0;
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

    if (_lastTtsSentenceStart >= 0 &&
        _lastTtsSection >= 0 &&
        _lastTtsSection != chapterController.currentChapterIndex) {
      await chapterController.loadChapter(_lastTtsSection, userInitiated: false);
    }

    final text = resolveTtsText(modeController: modeController);
    if (text.isNotEmpty) {
      await _ttsService.speak(text);
    }
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

    final baseOffset = _ttsNormalizedBaseOffset.clamp(0, chapterController.currentPlainText.length);
    final highlightStart = baseOffset + wordStart;
    final highlightEnd = baseOffset + wordEnd;

    if (highlightStart == _lastHighlightStart && highlightEnd == _lastHighlightEnd) {
      return;
    }

    _lastHighlightStart = highlightStart;
    _lastHighlightEnd = highlightEnd;
    
    // Save reading progress (debounced via repository)
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

    notifyListeners();
  }

  Future<void> advanceToNextReadableChapterAndSpeak() async {
    if (chapterController.chapters == null) return;

    final startIndex = chapterController.currentChapterIndex + 1;
    if (startIndex >= chapterController.chapters!.length) return;

    final requestId = ++_ttsAdvanceRequestId;

    for (var index = startIndex; index < chapterController.chapters!.length; index++) {
      await chapterController.loadChapter(index, userInitiated: false);
      if (requestId != _ttsAdvanceRequestId) return;

      final text = chapterController.currentPlainText.trim();
      if (text.isEmpty) continue;

      _ttsNormalizedBaseOffset = 0;
      await _ttsService.speak(text);
      return;
    }
  }

  String buildTtsHighlightedHtml(String html) {
    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart == null || wordEnd == null) return html;

    final baseOffset = _ttsNormalizedBaseOffset.clamp(0, chapterController.currentPlainText.length);
    final highlightStart = baseOffset + wordStart;
    final highlightEnd = baseOffset + wordEnd;

    if (_cachedHighlightedHtml != null &&
        highlightStart == _lastHighlightStart &&
        highlightEnd == _lastHighlightEnd) {
      return _cachedHighlightedHtml!;
    }

    final highlighted = _buildHighlightedHtmlAround(html, highlightStart, highlightEnd);
    _cachedHighlightedHtml = highlighted;
    return highlighted;
  }

  String _buildHighlightedHtmlAround(String html, int start, int end) {
    if (start < 0 || end <= start) return html;

    final document = html_parser.parse(html);
    final root = document.body ?? document.documentElement;
    if (root == null) return html;

    final textNodes = <dom.Text>[];
    _collectTextNodes(root, textNodes);
    if (textNodes.isEmpty) return html;

    final rawBuffer = StringBuffer();
    for (final node in textNodes) {
      rawBuffer.write(node.data);
    }

    final rawText = rawBuffer.toString();
    final map = buildNormalizedTextMap(rawText);
    if (map.normalizedToRaw.isEmpty) return html;

    final maxIndex = map.normalizedToRaw.length - 1;
    if (maxIndex < 0) return html;

    final clampedStart = start.clamp(0, maxIndex);
    final clampedEnd = end.clamp(0, map.normalizedToRaw.length);
    if (clampedEnd <= clampedStart) return html;

    final rawStart = map.normalizedToRaw[clampedStart];
    final rawEnd = map.normalizedToRaw[clampedEnd - 1] + 1;

    var offset = 0;
    for (final node in textNodes) {
      final nodeText = node.data;
      final nodeStart = offset;
      final nodeEnd = offset + nodeText.length;
      offset = nodeEnd;

      if (rawEnd <= nodeStart || rawStart >= nodeEnd) continue;

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
    }

    return root.outerHtml;
  }

  void _collectTextNodes(dom.Node node, List<dom.Text> out) {
    if (node is dom.Text) {
      out.add(node);
      return;
    }
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase();
      if (tag == 'script' || tag == 'style' || tag == 'noscript') return;
    }
    for (final child in node.nodes) {
      _collectTextNodes(child, out);
    }
  }

  String resolveTtsText({required ReaderModeController modeController}) {
    final text = chapterController.currentPlainText;
    if (text.trim().isEmpty) return '';

    if (_lastTtsSentenceStart >= 0 &&
        _lastTtsSentenceEnd > _lastTtsSentenceStart &&
        _lastTtsSection == chapterController.currentChapterIndex) {
      final start = _lastTtsSentenceStart.clamp(0, text.length);
      _ttsNormalizedBaseOffset = start;
      return text.substring(start);
    }

    return _ttsTextFromScrollPosition(modeController: modeController);
  }

  String _ttsTextFromScrollPosition({required ReaderModeController modeController}) {
    final text = chapterController.currentPlainText;
    if (text.trim().isEmpty) return '';

    if (modeController.isPagedMode) {
      _ttsNormalizedBaseOffset = 0;
      return text;
    }

    final scrollController = chapterController.scrollController;
    if (!scrollController.hasClients) {
      _ttsNormalizedBaseOffset = 0;
      return text;
    }

    final maxExtent = scrollController.position.maxScrollExtent;
    final offset = scrollController.offset.clamp(0.0, maxExtent);
    final fraction = maxExtent <= 0 ? 0.0 : (offset / maxExtent);
    final maxIndex = text.length - 1;
    final approxIndex = maxIndex <= 0 ? 0 : (fraction * maxIndex).floor().clamp(0, maxIndex);
    
    final start = findSentenceStart(text, approxIndex);
    _ttsNormalizedBaseOffset = start;
    return text.substring(start);
  }

  Future<void> startTtsFromTap(TapUpDetails details, {required ReaderModeController modeController, required BuildContext context}) async {
    if (!_showTtsControls || !_tapToStartEnabled) return;
    if (chapterController.allChapterPlainTexts.isEmpty) return;

    final tap = details.globalPosition;
    final chapterIndex = _findChapterIndexAtTap(tap, modeController: modeController, context: context) ?? 
                         chapterController.currentChapterIndex.clamp(0, chapterController.allChapterPlainTexts.length - 1);
    
    final chapterText = chapterController.allChapterPlainTexts[chapterIndex];
    if (chapterText.trim().isEmpty) return;

    final hit = _hitTestTextAt(tap, context: context);
    int? absoluteOffset;

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
          }
        }
      }
    }

    if (chapterIndex != chapterController.currentChapterIndex) {
      await chapterController.loadChapter(chapterIndex, userInitiated: false);
    }

    if (absoluteOffset != null) {
      final startText = chapterText.substring(absoluteOffset);
      await _speakFromHere(startText, baseOffset: absoluteOffset);
    } else {
      // Fallback
      final text = resolveTtsText(modeController: modeController);
      await _speakFromHere(text);
    }
  }

  Future<void> _speakFromHere(String startText, {int? baseOffset}) async {
    final normalized = normalizePlainText(startText);
    if (normalized.isEmpty) return;

    if (baseOffset != null && baseOffset >= 0) {
      _ttsNormalizedBaseOffset = baseOffset;
    } else {
      final index = chapterController.currentPlainText.indexOf(normalized);
      _ttsNormalizedBaseOffset = index >= 0 ? index : 0;
    }

    _ttsAdvanceRequestId++;

    _showTtsControls = true;
    notifyListeners();

    await _ttsService.speak(normalized);
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
    final start = _ttsService.currentWordStart;
    if (start == null) return;
    if (chapterController.currentPlainText.trim().isEmpty) return;

    final baseOffset = _ttsNormalizedBaseOffset.clamp(0, chapterController.currentPlainText.length);
    final absoluteOffset = baseOffset + start;
    final spans = chapterController.sentenceSpans;
    final span = sentenceForOffset(spans, absoluteOffset);
    if (span == null) return;

    _lastTtsSentenceStart = span.start;
    _lastTtsSentenceEnd = span.end;
    _lastTtsSection = chapterController.currentChapterIndex;

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: chapterController.currentChapterIndex,
      totalPages: chapterController.chapters?.length ?? 0,
      lastTtsSentenceStart: span.start,
      lastTtsSentenceEnd: span.end,
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
    super.dispose();
  }
}
