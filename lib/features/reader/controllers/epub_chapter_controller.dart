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
import 'package:reader_app/core/utils/dom_text_utils.dart';
import 'package:reader_app/features/reader/hyphenation_helper.dart';

class EpubChapterInfo {
  final String? title;
  EpubChapterInfo({this.title});
  // ignore: non_constant_identifier_names
  String? get Title => title;
}

class ParsedEpubBook {
  final List<EpubChapterInfo> chapters;
  final List<String> contents;
  final List<String> plainTexts;
  final List<List<SentenceSpan>> sentenceSpans;

  ParsedEpubBook({
    required this.chapters,
    required this.contents,
    required this.plainTexts,
    required this.sentenceSpans,
  });
}

class EpubChapterController extends ChangeNotifier {
  final Book book;
  final BookRepository repository;

  EpubChapterController({
    required this.book,
    required this.repository,
  }) : _scrollController = ScrollController(
         initialScrollOffset: (book.readingMode == ReadingMode.verticalContinuous &&
                 book.scrollPosition.isFinite &&
                 book.scrollPosition > 0)
             ? book.scrollPosition
             : 0.0,
       );

  List<EpubChapterInfo>? _chapters;
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

  final ScrollController _scrollController;
  final Map<int, ScrollController> _chapterScrollControllers = {};
  final Map<int, double> _chapterScrollOffsets = {};
  ResolvedBookFile? _resolvedFile;

  bool _isRestoringPosition = false;
  int _restoreGeneration = 0;
  bool _isProgrammaticScroll = false;
  DateTime _lastScrollCheckTime = DateTime.fromMillisecondsSinceEpoch(0);

  // Trackers from book model
  late int _lastReadingSentenceStart;
  late int _lastReadingSentenceEnd;
  late double _lastScrollPosition;

  // Getters
  List<EpubChapterInfo>? get chapters => _chapters;
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
  int get lastReadingSentenceStart => _lastReadingSentenceStart;
  int get lastReadingSentenceEnd => _lastReadingSentenceEnd;
  double get lastScrollPosition => _lastScrollPosition;

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
        final parsedBook = await _readChaptersWithFallback(bytes);

        if (parsedBook.chapters.isEmpty) {
          _error = "No chapters found in EPUB";
          _isLoading = false;
          notifyListeners();
          return;
        }

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

  static Future<ParsedEpubBook> _parseEpubIsolated(List<int> bytes) async {
    List<EpubChapter> rawChapters = [];

    // 1. Primary: Use the spine-based parser which strictly follows the EPUB
    // reading order and eliminates duplicate chapters from TOC subchapters.
    try {
      rawChapters = EpubFallbackParser.parseChapters(bytes);
    } catch (e) {
      debugPrint('Spine parser failed: $e. Falling back to epubx...');
    }

    // 2. Fallback: If spine parsing failed or produced no chapters, try epubx with deduplication.
    if (rawChapters.isEmpty) {
      try {
        final book = await EpubReader.readBook(bytes);
        rawChapters = _flattenAndDeduplicateChapters(book.Chapters ?? []);
      } catch (fallbackError) {
        throw Exception('EPUB parsing failed. Fallback also failed: $fallbackError');
      }
    }

    if (rawChapters.isEmpty) {
      throw Exception('No chapters found in EPUB');
    }

    // 3. Final deduplication safety pass: ensure no consecutive chapters have identical content.
    final deduplicatedChapters = <EpubChapter>[];
    String? lastContent;
    for (final ch in rawChapters) {
      final content = ch.HtmlContent?.trim() ?? '';
      if (content.isEmpty) continue;
      if (content == lastContent) continue;
      lastContent = content;
      deduplicatedChapters.add(ch);
    }

    final finalChapters = deduplicatedChapters.isNotEmpty ? deduplicatedChapters : rawChapters;

    final chapters = <EpubChapterInfo>[];
    final contents = <String>[];
    final plainTexts = <String>[];
    final sentenceSpans = <List<SentenceSpan>>[];

    for (var i = 0; i < finalChapters.length; i++) {
      final rawChapter = finalChapters[i];
      var title = rawChapter.Title?.trim();
      final content = rawChapter.HtmlContent ?? '';
      
      final doc = html_parser.parse(content);
      if (title == null || title.isEmpty) {
        final heading = doc.querySelector('h1, h2, h3, h4, title')?.text.trim();
        if (heading != null && heading.isNotEmpty) {
          title = heading;
        } else {
          title = 'Chapter ${i + 1}';
        }
      }

      final plainText = DomTextUtils.extractPlainText(doc.body ?? doc.documentElement);
      final spans = splitIntoSentences(plainText);
      final contentWithIndent = HyphenationHelper.injectIndentTags(content);

      chapters.add(EpubChapterInfo(title: title));
      contents.add(contentWithIndent);
      plainTexts.add(plainText);
      sentenceSpans.add(spans);
    }

    return ParsedEpubBook(
      chapters: chapters,
      contents: contents,
      plainTexts: plainTexts,
      sentenceSpans: sentenceSpans,
    );
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

  static List<EpubChapter> _flattenAndDeduplicateChapters(List<EpubChapter> chapters) {
    final flattened = _flattenChaptersStatic(chapters);
    final result = <EpubChapter>[];
    final seenPaths = <String>{};
    final seenContents = <String>{};

    for (final chapter in flattened) {
      final fileName = (chapter.ContentFileName ?? '')
          .toLowerCase()
          .split('#')
          .first
          .trim();
      final content = chapter.HtmlContent?.trim() ?? '';
      if (content.isEmpty) continue;

      if (fileName.isNotEmpty && seenPaths.contains(fileName)) {
        continue;
      }
      if (seenContents.contains(content)) {
        continue;
      }

      if (fileName.isNotEmpty) seenPaths.add(fileName);
      seenContents.add(content);
      result.add(chapter);
    }

    return result;
  }

  Future<ParsedEpubBook> _readChaptersWithFallback(List<int> bytes) async {
    return await compute(_parseEpubIsolated, bytes);
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
    if (userInitiated) {
      _lastScrollPosition = 0.0;
    }

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: index,
      totalPages: _chapters!.length,
      scrollPosition: userInitiated ? 0.0 : null,
      lastReadingSentenceStart: resetSpan?.start ?? -1,
      lastReadingSentenceEnd: resetSpan?.end ?? -1,
    ));

    if (userInitiated && _chapterKeys.isNotEmpty) {
      _scrollToChapter(index);
    }
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
      final box = context?.findRenderObject() as RenderBox?;
      if (context != null && box != null && box.attached && box.hasSize) {
        Scrollable.ensureVisible(
          context,
          duration: Duration.zero,
          alignment: 0.0,
        ).then((_) {
          _isProgrammaticScroll = false;
          if (_scrollController.hasClients) {
            final currentContext = key.currentContext;
            if (currentContext != null && currentContext.mounted) {
              updateCurrentChapterFromScroll(currentContext, force: true);
            }
          }
        }).catchError((_) {
          _isProgrammaticScroll = false;
        });
      } else {
        final currentOffset = _scrollController.offset;
        final maxExtent = _scrollController.position.maxScrollExtent;

        double charsBefore = 0;
        for (int i = 0; i < index && i < _allChapterPlainTexts.length; i++) {
          charsBefore += _allChapterPlainTexts[i].length;
        }
        final estimatedPixelTarget = 500.0 + charsBefore * 0.35;

        final targetJump = (maxExtent > 0 && estimatedPixelTarget > maxExtent)
            ? maxExtent
            : estimatedPixelTarget.clamp(0.0, maxExtent);

        if ((currentOffset - targetJump).abs() > 1.0) {
          _scrollController.jumpTo(targetJump);
        }

        if (attempt < 25) {
          _scrollToChapter(index, attempt: attempt + 1);
        } else {
          _isProgrammaticScroll = false;
          // Fallback: update state to target index directly
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
      }
    });
  }

  void updateCurrentChapterFromScroll(BuildContext context, {bool force = false}) {
    if (_isProgrammaticScroll || _isRestoringPosition) return;
    if (_chapterKeys.isEmpty || !_scrollController.hasClients) return;

    final now = DateTime.now();
    if (!force && now.difference(_lastScrollCheckTime).inMilliseconds < 150) {
      return;
    }
    _lastScrollCheckTime = now;

    int? visibleChapter;

    try {
      final scrollableBox = _scrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;
      final scrollableTop = (scrollableBox != null && scrollableBox.attached && scrollableBox.hasSize)
          ? scrollableBox.localToGlobal(Offset.zero).dy
          : 0.0;

      final viewportTop = _scrollController.offset;
      final viewportHeight = _scrollController.position.viewportDimension;
      final viewportMiddle = viewportTop + viewportHeight / 2;

      for (int i = 0; i < _chapterKeys.length; i++) {
        final key = _chapterKeys[i];
        final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.attached || !renderBox.hasSize) continue;

        final position = renderBox.localToGlobal(Offset.zero);
        final chapterTop = (position.dy - scrollableTop) + viewportTop;
        final chapterBottom = chapterTop + renderBox.size.height;

        if (viewportMiddle >= chapterTop && viewportMiddle < chapterBottom) {
          visibleChapter = i;
          break;
        }
        if (chapterTop > viewportMiddle) {
          visibleChapter ??= (i > 0) ? i - 1 : 0;
          break;
        }
        visibleChapter = i;
      }
    } catch (_) {
      // Safe guard against coordinate calculation during transient layout states
      return;
    }

    if (visibleChapter != null &&
        visibleChapter >= 0 &&
        visibleChapter < _allChapterContents.length &&
        visibleChapter != _currentChapterIndex) {
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

  double getChapterScrollOffset(int index) => _chapterScrollOffsets[index] ?? 0.0;

  void setChapterScrollOffset(int index, double offset) {
    _chapterScrollOffsets[index] = offset;
  }

  ScrollController chapterScrollController(int index) {
    final existing = _chapterScrollControllers[index];
    if (existing != null) {
      return existing;
    }
    final initialOffset = _chapterScrollOffsets[index] ?? 0.0;
    final controller = ScrollController(initialScrollOffset: initialOffset);
    controller.addListener(() {
      if (controller.hasClients) {
        _chapterScrollOffsets[index] = controller.offset;
      }
    });
    _chapterScrollControllers[index] = controller;
    return controller;
  }

  void saveReadingPositionForMode(ReadingMode mode, {bool refreshChapter = false, BuildContext? context}) {
    final isPaged = mode == ReadingMode.vertical || mode == ReadingMode.leftToRight;
    if (isPaged) {
      _saveReadingPositionFromPagedController(_currentChapterIndex);
    } else {
      if (refreshChapter && context != null) {
        updateCurrentChapterFromScroll(context, force: true);
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
      book.sectionIndex = _currentChapterIndex;
      book.scrollPosition = _lastScrollPosition;
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
    book.sectionIndex = _currentChapterIndex;
    book.scrollPosition = _lastScrollPosition;
    book.lastReadingSentenceStart = span.start;
    book.lastReadingSentenceEnd = span.end;

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: _currentChapterIndex,
      totalPages: _chapters?.length ?? 0,
      scrollPosition: _lastScrollPosition,
      lastReadingSentenceStart: span.start,
      lastReadingSentenceEnd: span.end,
    ));
  }

  void onNavigatedToCover() {
    _currentChapterIndex = 0;
    _lastReadingSentenceStart = -1;
    _lastReadingSentenceEnd = -1;
    _lastScrollPosition = 0.0;
    book.sectionIndex = 0;
    book.lastReadingSentenceStart = -1;
    book.lastReadingSentenceEnd = -1;
    book.scrollPosition = 0.0;
    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: 0,
      scrollPosition: 0.0,
      lastReadingSentenceStart: -1,
      lastReadingSentenceEnd: -1,
    ));
    notifyListeners();
  }

  void _saveReadingPositionFromPagedController(int chapterIndex) {
    if (chapterIndex < 0 || chapterIndex >= _allChapterPlainTexts.length) return;
    final controller = _chapterScrollControllers[chapterIndex];
    
    double fraction = 0.0;
    if (controller != null && controller.hasClients) {
      final metrics = controller.position;
      final contentHeight = metrics.maxScrollExtent + metrics.viewportDimension;
      final anchorY = metrics.pixels + metrics.viewportDimension * 0.5;
      fraction = contentHeight <= 0 ? 0.0 : (anchorY / contentHeight).clamp(0.0, 1.0);
      final span = _sentenceSpanForFraction(chapterIndex, fraction);

      _lastReadingSentenceStart = span.start;
      _lastReadingSentenceEnd = span.end;
    }

    // Estimate continuous scroll position corresponding to this chapter and fraction
    double charsBefore = 0;
    for (int i = 0; i < chapterIndex && i < _allChapterPlainTexts.length; i++) {
      charsBefore += _allChapterPlainTexts[i].length;
    }
    if (chapterIndex < _allChapterPlainTexts.length) {
      charsBefore += _allChapterPlainTexts[chapterIndex].length * fraction;
    }
    _lastScrollPosition = 500.0 + charsBefore * 0.35;

    // Keep in-memory book instance synchronized
    book.sectionIndex = chapterIndex;
    book.scrollPosition = _lastScrollPosition;
    book.lastReadingSentenceStart = _lastReadingSentenceStart;
    book.lastReadingSentenceEnd = _lastReadingSentenceEnd;

    unawaited(repository.updateReadingProgress(
      book.id,
      sectionIndex: chapterIndex,
      totalPages: _chapters?.length ?? 0,
      scrollPosition: _lastScrollPosition,
      lastReadingSentenceStart: _lastReadingSentenceStart,
      lastReadingSentenceEnd: _lastReadingSentenceEnd,
    ));
  }

  double? _chapterFractionAtViewportAnchor(int chapterIndex) {
    if (!_scrollController.hasClients) return null;
    if (chapterIndex < 0 || chapterIndex >= _chapterKeys.length) return null;

    final key = _chapterKeys[chapterIndex];
    final renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached || !renderBox.hasSize || renderBox.size.height <= 0) {
      return null;
    }

    try {
      final scrollableBox = _scrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;
      final scrollableTop = (scrollableBox != null && scrollableBox.attached && scrollableBox.hasSize)
          ? scrollableBox.localToGlobal(Offset.zero).dy
          : 0.0;

      final viewportHeight = _scrollController.position.viewportDimension;
      final anchorY = _scrollController.offset + viewportHeight * 0.5;
      final chapterTop = _scrollController.offset + (renderBox.localToGlobal(Offset.zero).dy - scrollableTop);
      final localY = (anchorY - chapterTop).clamp(0.0, renderBox.size.height);
      return localY / renderBox.size.height;
    } catch (_) {
      return null;
    }
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

    if (attempt == 0) {
      _isRestoringPosition = true;
      _restoreGeneration++;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        _isRestoringPosition = false;
        return;
      }
      final chapterIndex = _currentChapterIndex.clamp(0, _chapterKeys.length - 1);
      final anchorOffset = _readingAnchorOffset();

      // If user was viewing the cover page (anchorOffset < 0 && chapterIndex == 0 && _lastScrollPosition <= 0)
      if (anchorOffset < 0 && chapterIndex == 0 && _lastScrollPosition <= 0) {
        _scrollController.jumpTo(0.0);
        _markRestoringPosition();
        return;
      }

      final fraction = anchorOffset >= 0
          ? _fractionForTextOffset(chapterIndex, anchorOffset)
          : 0.0;

      final key = _chapterKeys[chapterIndex];
      final renderBox = key.currentContext?.findRenderObject() as RenderBox?;

      if (renderBox != null && renderBox.attached && renderBox.hasSize && renderBox.size.height > 0) {
        try {
          final scrollableBox = _scrollController.position.context.notificationContext?.findRenderObject() as RenderBox?;
          final scrollableTop = (scrollableBox != null && scrollableBox.attached && scrollableBox.hasSize)
              ? scrollableBox.localToGlobal(Offset.zero).dy
              : 0.0;

          final viewportHeight = _scrollController.position.viewportDimension;
          final chapterTop = _scrollController.offset + (renderBox.localToGlobal(Offset.zero).dy - scrollableTop);
          final anchorY = renderBox.size.height * fraction;
          final idealTarget = chapterTop + anchorY - viewportHeight * 0.5;
          final targetOffset = idealTarget.clamp(0.0, _scrollController.position.maxScrollExtent);

          _scrollController.jumpTo(targetOffset);

          if (attempt < 15 && idealTarget > _scrollController.position.maxScrollExtent) {
            _restoreContinuousPosition(attempt: attempt + 1);
          } else {
            _markRestoringPosition();
          }
          return;
        } catch (_) {
          // If localToGlobal throws during transient layout, fall through to retry
        }
      }

      // If target chapter is not yet laid out in lazy ListView.builder:
      if (attempt < 25) {
        final maxExtent = _scrollController.position.maxScrollExtent;
        final currentOffset = _scrollController.offset;

        double targetJump;
        if (_lastScrollPosition > 0) {
          // Clamp directly to _lastScrollPosition so it advances towards it
          // as slivers build, but NEVER jumps beyond _lastScrollPosition.
          targetJump = _lastScrollPosition.clamp(0.0, maxExtent);
        } else {
          double charsBefore = 0;
          for (int i = 0; i < chapterIndex && i < _allChapterPlainTexts.length; i++) {
            charsBefore += _allChapterPlainTexts[i].length;
          }
          if (chapterIndex < _allChapterPlainTexts.length) {
            charsBefore += _allChapterPlainTexts[chapterIndex].length * fraction;
          }

          // Conservative estimate (0.35 px/char) to avoid overshooting past target chapter
          final estimatedPixelTarget = 500.0 + charsBefore * 0.35;
          targetJump = estimatedPixelTarget.clamp(0.0, maxExtent);
        }

        final delta = (currentOffset - targetJump).abs();
        if (delta > 1.0) {
          _scrollController.jumpTo(targetJump);
          _restoreContinuousPosition(attempt: attempt + 1);
        } else if (attempt < 5) {
          _restoreContinuousPosition(attempt: attempt + 1);
        } else {
          _markRestoringPosition();
        }
      } else {
        // Fallback timeout reached: safely exit restoration without corrupting DB
        _markRestoringPosition();
      }
    });
  }

  void _restorePagedPosition({int attempt = 0}) {
    if (_allChapterContents.isEmpty) return;
    final chapterIndex = _currentChapterIndex.clamp(0, _allChapterContents.length - 1);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = chapterScrollController(chapterIndex);
      if (!controller.hasClients) {
        if (attempt < 10) _restorePagedPosition(attempt: attempt + 1);
        return;
      }

      final anchorOffset = _readingAnchorOffset();
      final fraction = anchorOffset >= 0 ? _fractionForTextOffset(chapterIndex, anchorOffset) : 0.0;
      final viewportHeight = controller.position.viewportDimension;
      final contentHeight = controller.position.maxScrollExtent + viewportHeight;
      final target = contentHeight <= 0
          ? 0.0
          : (contentHeight * fraction - viewportHeight * 0.5).clamp(0.0, controller.position.maxScrollExtent);
      
      _markRestoringPosition();
      controller.jumpTo(target);
      _chapterScrollOffsets[chapterIndex] = target;
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
    _chapterScrollOffsets.clear();
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
}
