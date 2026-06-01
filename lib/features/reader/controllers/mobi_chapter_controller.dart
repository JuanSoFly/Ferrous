import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/core/utils/performance.dart';
import 'package:reader_app/core/utils/sentence_utils.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:reader_app/core/utils/dom_text_utils.dart';
import 'package:reader_app/src/rust/api/mobi.dart' as rust_mobi;

class MobiChapterInfo {
  final String? title;
  MobiChapterInfo({this.title});
  // ignore: non_constant_identifier_names
  String? get Title => title;
}

class ParsedMobiBook {
  final List<MobiChapterInfo> chapters;
  final List<String> contents;
  final List<String> plainTexts;
  final List<List<SentenceSpan>> sentenceSpans;

  ParsedMobiBook({
    required this.chapters,
    required this.contents,
    required this.plainTexts,
    required this.sentenceSpans,
  });
}

class MobiChapterController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;

  MobiChapterController({
    required this.book,
    required this.repository,
  });

  List<MobiChapterInfo>? _chapters;
  List<String> _allChapterContents = const [];
  List<String> _allChapterPlainTexts = const [];
  List<List<SentenceSpan>> _allChapterSentenceSpans = const [];
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
  bool _isProgrammaticScroll = false;

  // Trackers from book model
  late int _lastReadingSentenceStart;
  late int _lastReadingSentenceEnd;
  late double _lastScrollPosition;

  // Getters
  List<MobiChapterInfo>? get chapters => _chapters;
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
    unawaited(loadMobi());
  }

  Future<void> loadMobi() async {
    await measureAsync('mobi_load_document', () async {
      try {
        final resolver = BookFileResolver();
        final resolved = await resolver.resolve(book);
        _resolvedFile = resolved;
        
        // Fetch chapters from Rust backend
        final rustChapters = await rust_mobi.getMobiChapters(path: resolved.path);

        if (rustChapters.isEmpty) {
          _error = "No sections found in MOBI";
          _isLoading = false;
          notifyListeners();
          return;
        }

        // Run CPU-intensive HTML/sentence parsing in isolate
        final parsedBook = await compute(_parseMobiIsolated, rustChapters);

        final allKeys = List.generate(parsedBook.chapters.length, (_) => GlobalKey());

        if (_currentChapterIndex >= parsedBook.chapters.length) {
          _currentChapterIndex = 0;
        }

        _chapters = parsedBook.chapters;
        _allChapterContents = parsedBook.contents;
        _allChapterPlainTexts = parsedBook.plainTexts;
        _allChapterSentenceSpans = parsedBook.sentenceSpans;
        _chapterKeys = allKeys;
        _currentContent = parsedBook.contents[_currentChapterIndex];
        _currentPlainText = parsedBook.plainTexts[_currentChapterIndex];
        _sentenceSpans = parsedBook.sentenceSpans[_currentChapterIndex];
        _isLoading = false;
        notifyListeners();
      } catch (e) {
        _error = e.toString();
        _isLoading = false;
        notifyListeners();
      }
    }, metadata: {'book_id': book.id});
  }

  static ParsedMobiBook _parseMobiIsolated(List<rust_mobi.MobiChapter> rawChapters) {
    final chapters = <MobiChapterInfo>[];
    final contents = <String>[];
    final plainTexts = <String>[];
    final sentenceSpans = <List<SentenceSpan>>[];

    for (final rawChapter in rawChapters) {
      final title = rawChapter.title;
      final content = rawChapter.htmlContent;
      
      final doc = html_parser.parse(content);
      final plainText = DomTextUtils.extractPlainText(doc.body ?? doc.documentElement);
      final spans = splitIntoSentences(plainText);

      chapters.add(MobiChapterInfo(title: title));
      contents.add(content);
      plainTexts.add(plainText);
      sentenceSpans.add(spans);
    }

    return ParsedMobiBook(
      chapters: chapters,
      contents: contents,
      plainTexts: plainTexts,
      sentenceSpans: sentenceSpans,
    );
  }

  Future<void> loadChapter(int index, {bool userInitiated = false, VoidCallback? onBeforeLoad}) async {
    if (_chapters == null || index < 0 || index >= _chapters!.length) return;
    if (_allChapterContents.isEmpty) return;

    onBeforeLoad?.call();

    _currentChapterIndex = index;
    _currentContent = _allChapterContents[index];
    _currentPlainText = _allChapterPlainTexts[index];
    _sentenceSpans = _allChapterSentenceSpans[index];
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
      _scrollToChapter(index);
    }
  }

  double _getCharacterBasedEstimate(int index) {
    if (_allChapterPlainTexts.isEmpty) return 0.0;
    if (index <= 0) return 0.0;
    if (index >= _allChapterPlainTexts.length) {
      if (_scrollController.hasClients) {
        return _scrollController.position.maxScrollExtent;
      }
      return 0.0;
    }

    double totalChars = 0;
    for (final text in _allChapterPlainTexts) {
      totalChars += text.length;
    }
    if (totalChars == 0) return 0.0;

    double charsBefore = 0;
    for (int i = 0; i < index; i++) {
      charsBefore += _allChapterPlainTexts[i].length;
    }

    final maxExtent = _scrollController.hasClients ? _scrollController.position.maxScrollExtent : 0.0;
    return (charsBefore / totalChars) * maxExtent;
  }

  void _scrollToChapter(int index, {int attempt = 0}) {
    if (!_scrollController.hasClients) return;
    if (attempt == 0) {
      _isProgrammaticScroll = true;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        _isProgrammaticScroll = false;
        return;
      }
      final key = _chapterKeys[index];
      final context = key.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignment: 0.0,
        ).then((_) {
          _isProgrammaticScroll = false;
          if (_scrollController.hasClients) {
            final currentContext = key.currentContext;
            if (currentContext != null && currentContext.mounted) {
              updateCurrentChapterFromScroll(currentContext);
            }
          }
        });
      } else if (attempt < 5) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final estimated = _getCharacterBasedEstimate(index);
        _scrollController.jumpTo(estimated.clamp(0.0, maxExtent));
        _scrollToChapter(index, attempt: attempt + 1);
      } else {
        _isProgrammaticScroll = false;
        _currentChapterIndex = index;
        if (index < _allChapterContents.length) {
          _currentContent = _allChapterContents[index];
          _currentPlainText = _allChapterPlainTexts[index];
          _sentenceSpans = _allChapterSentenceSpans[index];
        }
        notifyListeners();
        unawaited(repository.updateReadingProgress(
          book.id,
          sectionIndex: index,
          totalPages: _chapters?.length ?? 0,
        ));
      }
    });
  }

  void updateCurrentChapterFromScroll(BuildContext context) {
    if (_isProgrammaticScroll || _isRestoringPosition) return;
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
      _sentenceSpans = _allChapterSentenceSpans[visibleChapter];
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
    if (_isRestoringPosition || _isProgrammaticScroll) return;
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
    final spans = _allChapterSentenceSpans[chapterIndex];
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
          final estimated = _getCharacterBasedEstimate(chapterIndex);
          _markRestoringPosition();
          _scrollController.jumpTo(estimated.clamp(0.0, maxExtent));
          _restoreContinuousPosition(attempt: attempt + 1);
        } else if (_lastScrollPosition > 0) {
          _markRestoringPosition();
          _scrollController.jumpTo(_lastScrollPosition.clamp(0.0, maxExtent));
        } else if (attempt < 2) {
          final estimated = _getCharacterBasedEstimate(chapterIndex);
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
        unawaited(File(_resolvedFile!.path).delete());
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
