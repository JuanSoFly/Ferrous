import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:epubx/epubx.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/features/reader/epub_fallback_parser.dart';
import 'package:reader_app/core/utils/performance.dart';
import 'package:reader_app/core/utils/sentence_utils.dart';
import 'package:html/parser.dart' as html_parser;

class EpubChapterController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;

  EpubChapterController({
    required this.book,
    required this.repository,
  });

  List<EpubChapter>? _chapters;
  List<String> _allChapterContents = const [];
  List<String> _allChapterPlainTexts = const [];
  List<GlobalKey> _chapterKeys = const [];
  int _currentChapterIndex = 0;
  String? _currentContent;
  String _currentPlainText = '';
  List<SentenceSpan> _sentenceSpans = const [];
  bool _isLoading = true;
  String? _error;

  final ScrollController _scrollController = ScrollController();
  final Map<int, ScrollController> _chapterScrollControllers = {};
  ResolvedBookFile? _resolvedFile;

  bool _isRestoringPosition = false;
  int _restoreGeneration = 0;

  // Trackers from book model
  late int _lastReadingSentenceStart;
  late int _lastReadingSentenceEnd;
  late double _lastScrollPosition;

  // Getters
  List<EpubChapter>? get chapters => _chapters;
  List<String> get allChapterContents => _allChapterContents;
  List<String> get allChapterPlainTexts => _allChapterPlainTexts;
  List<GlobalKey> get chapterKeys => _chapterKeys;
  int get currentChapterIndex => _currentChapterIndex;
  String? get currentContent => _currentContent;
  String get currentPlainText => _currentPlainText;
  List<SentenceSpan> get sentenceSpans => _sentenceSpans;
  bool get isLoading => _isLoading;
  String? get error => _error;
  ScrollController get scrollController => _scrollController;
  ResolvedBookFile? get resolvedFile => _resolvedFile;

  void init() {
    _currentChapterIndex = book.sectionIndex;
    _lastReadingSentenceStart = book.lastReadingSentenceStart;
    _lastReadingSentenceEnd = book.lastReadingSentenceEnd;
    _lastScrollPosition = book.scrollPosition;
    unawaited(loadEpub());
  }

  Future<void> loadEpub() async {
    await measureAsync('epub_load_document', () async {
      try {
        final resolver = BookFileResolver();
        final resolved = await resolver.resolve(book);
        _resolvedFile = resolved;
        final bytes = await File(resolved.path).readAsBytes();
        final chapters = await _readChaptersWithFallback(bytes);

        if (chapters.isEmpty) {
          _error = "No chapters found in EPUB";
          _isLoading = false;
          notifyListeners();
          return;
        }

        final allContents = <String>[];
        final allPlainTexts = <String>[];
        final allKeys = <GlobalKey>[];

        for (final chapter in chapters) {
          final content = chapter.HtmlContent ?? '';
          allContents.add(content);
          allPlainTexts.add(_htmlToPlainText(content));
          allKeys.add(GlobalKey());
        }

        if (_currentChapterIndex >= chapters.length) {
          _currentChapterIndex = 0;
        }

        _chapters = chapters;
        _allChapterContents = allContents;
        _allChapterPlainTexts = allPlainTexts;
        _chapterKeys = allKeys;
        _currentContent = allContents[_currentChapterIndex];
        _currentPlainText = allPlainTexts[_currentChapterIndex];
        _sentenceSpans = splitIntoSentences(_currentPlainText);
        _isLoading = false;
        notifyListeners();
      } catch (e) {
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      }
    }, metadata: {'book_id': book.id});
  }

  String _htmlToPlainText(String html) {
    if (html.isEmpty) return '';
    final document = html_parser.parse(html);
    return document.body?.text ?? document.documentElement?.text ?? '';
  }

  static Future<List<EpubChapter>> _parseEpubIsolated(List<int> bytes) async {
    try {
      final book = await EpubReader.readBook(bytes);
      return _flattenChaptersStatic(book.Chapters ?? []);
    } catch (e) {
      final message = e.toString().toLowerCase();
      if (message.contains("navigation") || 
          message.contains("ncx") ||
          message.contains("toc") ||
          message.contains("manifest") ||
          message.contains("not found in epub")) {
        try {
          final chapters = EpubFallbackParser.parseChapters(bytes);
          if (chapters.isNotEmpty) return chapters;
        } catch (_) {}
      }
      rethrow;
    }
  }

  static List<EpubChapter> _flattenChaptersStatic(List<EpubChapter> chapters) {
    List<EpubChapter> result = [];
    for (var chapter in chapters) {
      result.add(chapter);
      if (chapter.SubChapters != null && chapter.SubChapters!.isNotEmpty) {
        result.addAll(_flattenChaptersStatic(chapter.SubChapters!));
      }
    }
    return result;
  }

  Future<List<EpubChapter>> _readChaptersWithFallback(List<int> bytes) async {
    return await compute(_parseEpubIsolated, bytes);
  }

  Future<void> loadChapter(int index, {bool userInitiated = false, VoidCallback? onBeforeLoad}) async {
    if (_chapters == null || index < 0 || index >= _chapters!.length) return;
    if (_allChapterContents.isEmpty) return;

    onBeforeLoad?.call();

    _currentChapterIndex = index;
    _currentContent = _allChapterContents[index];
    _currentPlainText = _allChapterPlainTexts[index];
    _sentenceSpans = splitIntoSentences(_currentPlainText);
    notifyListeners();

    SentenceSpan? resetSpan;
    if (userInitiated) {
      if (_currentPlainText.trim().isNotEmpty) {
        resetSpan = _sentenceSpans.isNotEmpty
            ? _sentenceSpans.first
            : SentenceSpan(0, _currentPlainText.length);
        _lastReadingSentenceStart = resetSpan.start;
        _lastReadingSentenceEnd = resetSpan.end;
      } else {
        _lastReadingSentenceStart = -1;
        _lastReadingSentenceEnd = -1;
      }
    }

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: index,
      totalPages: _chapters!.length,
      scrollPosition: userInitiated ? 0.0 : null,
      lastReadingSentenceStart: resetSpan?.start ?? (userInitiated ? -1 : null),
      lastReadingSentenceEnd: resetSpan?.end ?? (userInitiated ? -1 : null),
    ));

    if (userInitiated && _chapterKeys.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final key = _chapterKeys[index];
        final context = key.currentContext;
        if (context != null) {
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            alignment: 0.0,
          );
        }
      });
    }
  }

  void updateCurrentChapterFromScroll(BuildContext context) {
    if (_chapterKeys.isEmpty || !_scrollController.hasClients) return;

    final viewportTop = _scrollController.offset;
    final viewportMiddle = viewportTop + MediaQuery.of(context).size.height / 2;

    int visibleChapter = 0;
    for (int i = 0; i < _chapterKeys.length; i++) {
      final key = _chapterKeys[i];
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox == null) continue;

      final position = renderBox.localToGlobal(Offset.zero);
      final chapterTop = position.dy + viewportTop;
      final chapterBottom = chapterTop + renderBox.size.height;

      if (viewportMiddle >= chapterTop && viewportMiddle < chapterBottom) {
        visibleChapter = i;
        break;
      }
      if (chapterTop > viewportMiddle) {
        visibleChapter = (i > 0) ? i - 1 : 0;
        break;
      }
      visibleChapter = i;
    }

    if (visibleChapter != _currentChapterIndex) {
      _currentChapterIndex = visibleChapter;
      _currentContent = _allChapterContents[visibleChapter];
      _currentPlainText = _allChapterPlainTexts[visibleChapter];
      _sentenceSpans = splitIntoSentences(_currentPlainText);
      notifyListeners();

      unawaited(repository.updateReadingProgress(
        book.id,
        sectionIndex: visibleChapter,
        totalPages: _chapters?.length ?? 0,
      ));
    }
  }

  ScrollController chapterScrollController(int index) {
    return _chapterScrollControllers.putIfAbsent(
      index,
      () => ScrollController(),
    );
  }

  void saveReadingPositionForMode(ReadingMode mode, {bool refreshChapter = true, BuildContext? context}) {
    final isPaged = mode == ReadingMode.vertical || mode == ReadingMode.leftToRight;
    if (isPaged) {
      _saveReadingPositionFromPagedController(_currentChapterIndex);
    } else {
      if (refreshChapter && context != null) {
        updateCurrentChapterFromScroll(context);
      }
      _saveReadingPositionFromScroll();
    }
  }

  void _saveReadingPositionFromScroll() {
    if (_isRestoringPosition) return;
    if (!_scrollController.hasClients) return;
    if (_currentChapterIndex < 0 || _currentChapterIndex >= _allChapterPlainTexts.length) return;
    
    final text = _allChapterPlainTexts[_currentChapterIndex];
    if (text.trim().isEmpty) return;

    final fraction = _chapterFractionAtViewportAnchor(_currentChapterIndex);
    if (fraction == null) {
      _lastScrollPosition = _scrollController.offset;
      unawaited(repository.updateReadingProgress(
        book.id,
        sectionIndex: _currentChapterIndex,
        totalPages: _chapters?.length ?? 0,
        scrollPosition: _lastScrollPosition,
      ));
      return;
    }

    final span = _sentenceSpanForFraction(_currentChapterIndex, fraction);
    _lastScrollPosition = _scrollController.offset;
    _lastReadingSentenceStart = span.start;
    _lastReadingSentenceEnd = span.end;

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: _currentChapterIndex,
      totalPages: _chapters?.length ?? 0,
      scrollPosition: _lastScrollPosition,
      lastReadingSentenceStart: span.start,
      lastReadingSentenceEnd: span.end,
    ));
  }

  void _saveReadingPositionFromPagedController(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _allChapterPlainTexts.length) return;
    final controller = _chapterScrollControllers[chapterIndex];
    if (controller == null || !controller.hasClients) return;
    
    final metrics = controller.position;
    final contentHeight = metrics.maxScrollExtent + metrics.viewportDimension;
    final anchorY = metrics.pixels + metrics.viewportDimension * 0.5;
    final fraction = contentHeight <= 0 ? 0.0 : (anchorY / contentHeight).clamp(0.0, 1.0);
    final span = _sentenceSpanForFraction(chapterIndex, fraction);

    _lastReadingSentenceStart = span.start;
    _lastReadingSentenceEnd = span.end;

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: chapterIndex,
      totalPages: _chapters?.length ?? 0,
      lastReadingSentenceStart: span.start,
      lastReadingSentenceEnd: span.end,
    ));
  }

  double? _chapterFractionAtViewportAnchor(int chapterIndex) {
    if (!_scrollController.hasClients) return null;
    if (chapterIndex < 0 || chapterIndex >= _chapterKeys.length) return null;

    final key = _chapterKeys[chapterIndex];
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || renderBox.size.height <= 0) return null;

    final viewportHeight = _scrollController.position.viewportDimension;
    final anchorY = _scrollController.offset + viewportHeight * 0.5;
    final chapterTop = _scrollController.offset + renderBox.localToGlobal(Offset.zero).dy;
    final localY = (anchorY - chapterTop).clamp(0.0, renderBox.size.height);
    return localY / renderBox.size.height;
  }

  SentenceSpan _sentenceSpanForFraction(int chapterIndex, double fraction) {
    if (chapterIndex < 0 || chapterIndex >= _allChapterPlainTexts.length) return const SentenceSpan(0, 0);
    final text = _allChapterPlainTexts[chapterIndex];
    if (text.trim().isEmpty) return SentenceSpan(0, text.length);
    final maxIndex = text.length - 1;
    final approxIndex = maxIndex <= 0 ? 0 : (fraction * maxIndex).round().clamp(0, maxIndex);
    final spans = chapterIndex == _currentChapterIndex ? _sentenceSpans : splitIntoSentences(text);
    return sentenceForOffset(spans, approxIndex) ?? SentenceSpan(0, text.length);
  }

  void restoreReadingPosition(ReadingMode mode) {
    final isPaged = mode == ReadingMode.vertical || mode == ReadingMode.leftToRight;
    if (isPaged) {
      _restorePagedPosition();
    } else {
      _restoreContinuousPosition();
    }
  }

  void _restoreContinuousPosition({int attempt = 0}) {
    if (!_scrollController.hasClients || _chapterKeys.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final chapterIndex = _currentChapterIndex.clamp(0, _chapterKeys.length - 1);
      final anchorOffset = _readingAnchorOffset();
      final fraction = anchorOffset >= 0 ? _fractionForTextOffset(chapterIndex, anchorOffset) : null;
      final target = fraction == null ? null : _scrollOffsetForChapterFraction(chapterIndex, fraction);

      if (target != null) {
        _markRestoringPosition();
        _scrollController.jumpTo(target);
        return;
      }

      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent > 0) {
        if (fraction != null && attempt < 2) {
          final estimated = _chapterKeys.length <= 1 ? 0.0 : (chapterIndex / (_chapterKeys.length - 1)) * maxExtent;
          _markRestoringPosition();
          _scrollController.jumpTo(estimated.clamp(0.0, maxExtent));
          _restoreContinuousPosition(attempt: attempt + 1);
        } else if (_lastScrollPosition > 0) {
          _markRestoringPosition();
          _scrollController.jumpTo(_lastScrollPosition.clamp(0.0, maxExtent));
        } else if (attempt < 2) {
          final estimated = _chapterKeys.length <= 1 ? 0.0 : (chapterIndex / (_chapterKeys.length - 1)) * maxExtent;
          _markRestoringPosition();
          _scrollController.jumpTo(estimated.clamp(0.0, maxExtent));
          _restoreContinuousPosition(attempt: attempt + 1);
        }
      }
    });
  }

  void _restorePagedPosition({int attempt = 0}) {
    if (_allChapterContents.isEmpty) return;
    final chapterIndex = _currentChapterIndex.clamp(0, _allChapterContents.length - 1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = chapterScrollController(chapterIndex);
      if (!controller.hasClients) {
        if (attempt < 3) _restorePagedPosition(attempt: attempt + 1);
        return;
      }

      final anchorOffset = _readingAnchorOffset();
      final fraction = anchorOffset >= 0 ? _fractionForTextOffset(chapterIndex, anchorOffset) : 0.0;
      final viewportHeight = controller.position.viewportDimension;
      final contentHeight = controller.position.maxScrollExtent + viewportHeight;
      final target = contentHeight <= 0 ? 0.0 : (contentHeight * fraction - viewportHeight * 0.5).clamp(0.0, controller.position.maxScrollExtent);
      
      _markRestoringPosition();
      controller.jumpTo(target);
    });
  }

  int _readingAnchorOffset() {
    if (_lastReadingSentenceStart >= 0) return _lastReadingSentenceStart;
    if (_lastReadingSentenceEnd >= 0) return _lastReadingSentenceEnd;
    return -1;
  }

  double _fractionForTextOffset(int chapterIndex, int offset) {
    if (chapterIndex < 0 || chapterIndex >= _allChapterPlainTexts.length) return 0.0;
    final text = _allChapterPlainTexts[chapterIndex];
    if (text.trim().isEmpty) return 0.0;
    final maxIndex = text.length - 1;
    if (maxIndex <= 0) return 0.0;
    return offset.clamp(0, maxIndex) / maxIndex;
  }

  double? _scrollOffsetForChapterFraction(int chapterIndex, double fraction) {
    if (!_scrollController.hasClients) return null;
    if (chapterIndex < 0 || chapterIndex >= _chapterKeys.length) return null;

    final key = _chapterKeys[chapterIndex];
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || renderBox.size.height <= 0) return null;

    final viewportHeight = _scrollController.position.viewportDimension;
    final chapterTop = _scrollController.offset + renderBox.localToGlobal(Offset.zero).dy;
    final anchorY = renderBox.size.height * fraction;
    final target = chapterTop + anchorY - viewportHeight * 0.5;
    return target.clamp(0.0, _scrollController.position.maxScrollExtent);
  }

  void _markRestoringPosition() {
    _isRestoringPosition = true;
    final generation = ++_restoreGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_restoreGeneration == generation) {
        _isRestoringPosition = false;
      }
    });
  }

  void cleanup() {
    if (_resolvedFile?.isTemp == true) {
      try {
        File(_resolvedFile!.path).deleteSync();
      } catch (_) {}
    }
    _scrollController.dispose();
    for (final controller in _chapterScrollControllers.values) {
      controller.dispose();
    }
    _chapterScrollControllers.clear();
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
