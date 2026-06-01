import 'dart:async';
import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/core/utils/sentence_utils.dart';
import 'package:reader_app/core/utils/normalized_text_map.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;
import 'package:reader_app/core/utils/dom_text_utils.dart';

class HtmlTtsController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;
  final TtsService _ttsService;
  final ScrollController scrollController;
  final String Function() getPlainText;

  HtmlTtsController({
    required this.book,
    required this.repository,
    required TtsService ttsService,
    required this.scrollController,
    required this.getPlainText,
  }) : _ttsService = ttsService {
    _ttsService.setOnFinished(_handleTtsFinished);
    _ttsService.addListener(_handleTtsProgress);

    _lastTtsSentenceStart = book.lastTtsSentenceStart;
    _lastTtsSentenceEnd = book.lastTtsSentenceEnd;
  }

  bool _showTtsControls = false;
  bool _ttsContinuous = true;
  bool _ttsFollowMode = true;
  bool _tapToStartEnabled = true;

  int _ttsRawBaseOffset = 0;
  NormalizedTextMap? _ttsNormalizationMap;
  final GlobalKey _ttsHighlightKey = GlobalKey();
  bool highlightKeyAssigned = false;

  int? _lastHighlightStart;
  int? _lastHighlightEnd;
  int? _lastEnsuredStart;
  int? _lastEnsuredEnd;
  String? _cachedHighlightedHtml;
  String? _lastHighlightedSourceHtml;

  late int _lastTtsSentenceStart;
  late int _lastTtsSentenceEnd;

  static const String _ttsHighlightTag = 'tts-highlight';

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
      saveCurrentTtsSentence();
      _cachedHighlightedHtml = null;
      _lastHighlightStart = null;
      _lastHighlightEnd = null;
      unawaited(_ttsService.stop());
      return;
    }
  }

  void _handleTtsFinished() {
    closeTtsControls();
  }

  void _handleTtsProgress() {
    if (_ttsService.state == TtsState.stopped) {
      _cachedHighlightedHtml = null;
      _lastHighlightStart = null;
      _lastHighlightEnd = null;
      notifyListeners();
      return;
    }

    if (_ttsService.state != TtsState.playing) {
      return;
    }

    final wordStart = _ttsService.currentWordStart;
    final wordEnd = _ttsService.currentWordEnd;
    if (wordStart == null || wordEnd == null) return;

    final map = _ttsNormalizationMap;
    if (map == null || map.normalizedToRaw.isEmpty) return;

    final maxIdx = map.normalizedToRaw.length;
    final clampedStart = wordStart.clamp(0, maxIdx - 1);
    final clampedEnd = wordEnd.clamp(0, maxIdx);
    if (clampedEnd <= clampedStart) return;

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
    
    _cachedHighlightedHtml = null;
    
    _lastTtsSentenceStart = highlightStart;
    _lastTtsSentenceEnd = highlightEnd;

    unawaited(repository.updateReadingProgress(
      book.id,
      lastTtsSentenceStart: highlightStart,
      lastTtsSentenceEnd: highlightEnd,
    ));

    notifyListeners();
    maybeEnsureHighlightVisible();
  }

  String buildTtsHighlightedHtml(String html) {
    final highlightStart = _lastHighlightStart;
    final highlightEnd = _lastHighlightEnd;
    if (highlightStart == null || highlightEnd == null) return html;

    if (_cachedHighlightedHtml != null && _lastHighlightedSourceHtml == html) {
      return _cachedHighlightedHtml!;
    }

    final highlighted = _buildHighlightedHtmlAround(html, highlightStart, highlightEnd);
    _lastHighlightedSourceHtml = html;
    _cachedHighlightedHtml = highlighted;
    return highlighted;
  }

  String _buildHighlightedHtmlAround(String html, int rawStart, int rawEnd) {
    if (rawStart < 0 || rawEnd <= rawStart) return html;

    final document = html_parser.parse(html);
    final root = document.body ?? document.documentElement;
    if (root == null) return html;

    final textNodes = DomTextUtils.collectTextNodes(root);
    if (textNodes.isEmpty) return html;

    var offset = 0;
    for (final node in textNodes) {
      final nodeText = node.data;
      final cleanToProcessed = <int>[];
      int processedIdx = 0;

      if (nodeText.startsWith('\u00A0\u00A0\u00A0\u00A0')) {
        processedIdx = 4;
      }

      while (processedIdx < nodeText.length) {
        final codeUnit = nodeText.codeUnitAt(processedIdx);
        if (codeUnit == 0x00AD) {
          processedIdx++;
          continue;
        }
        cleanToProcessed.add(processedIdx);
        processedIdx++;
      }

      final nodeStart = offset;
      final nodeEnd = offset + cleanToProcessed.length;
      offset = nodeEnd;

      if (rawEnd <= nodeStart || rawStart >= nodeEnd) continue;
      if (node.parent == null) continue;

      final localCleanStart = (rawStart - nodeStart).clamp(0, cleanToProcessed.length);
      final localCleanEnd = (rawEnd - nodeStart).clamp(0, cleanToProcessed.length);

      if (localCleanStart >= localCleanEnd) continue;

      final localStart = localCleanStart < cleanToProcessed.length
          ? cleanToProcessed[localCleanStart]
          : nodeText.length;
      final localEnd = localCleanEnd < cleanToProcessed.length
          ? cleanToProcessed[localCleanEnd]
          : nodeText.length;

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
      break;
    }

    return root.outerHtml;
  }

  String resolveTtsText() {
    final rawText = getPlainText();
    if (rawText.trim().isEmpty) return '';

    if (_lastTtsSentenceStart >= 0 &&
        _lastTtsSentenceEnd > _lastTtsSentenceStart) {
      final start = _lastTtsSentenceStart.clamp(0, rawText.length);
      _ttsRawBaseOffset = start;
      
      final textToSpeak = rawText.substring(start);
      _ttsNormalizationMap = buildNormalizedTextMap(textToSpeak);
      return _ttsNormalizationMap!.normalized;
    }

    return _ttsTextFromScrollPosition();
  }

  String _ttsTextFromScrollPosition() {
    final rawText = getPlainText();
    if (rawText.trim().isEmpty) return '';

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
    
    final start = findSentenceStart(rawText, approxIndex);
    _ttsRawBaseOffset = start;
    
    final textToSpeak = rawText.substring(start);
    _ttsNormalizationMap = buildNormalizedTextMap(textToSpeak);
    return _ttsNormalizationMap!.normalized;
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
    
    final rawText = getPlainText();
    if (rawText.trim().isEmpty) return;

    final map = _ttsNormalizationMap;
    if (map == null || map.normalizedToRaw.isEmpty) return;

    final maxIdx = map.normalizedToRaw.length;
    final clampedStart = wordStart.clamp(0, maxIdx - 1);
    final clampedEnd = wordEnd.clamp(0, maxIdx);
    if (clampedEnd <= clampedStart) return;

    final rawWordStart = map.normalizedToRaw[clampedStart];
    final rawWordEnd = map.normalizedToRaw[clampedEnd - 1] + 1;
    
    final absoluteStart = _ttsRawBaseOffset + rawWordStart;
    final absoluteEnd = _ttsRawBaseOffset + rawWordEnd;

    _lastTtsSentenceStart = absoluteStart;
    _lastTtsSentenceEnd = absoluteEnd;

    unawaited(repository.updateReadingProgress(
      book.id,
      lastTtsSentenceStart: absoluteStart,
      lastTtsSentenceEnd: absoluteEnd,
    ));
  }

  void closeTtsControls() {
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
    unawaited(_ttsService.stop());
    super.dispose();
  }
}
