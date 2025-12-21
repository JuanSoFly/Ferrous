import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/services/book_file_resolver.dart';
import 'package:reader_app/src/rust/api/docx.dart';
import 'package:reader_app/features/reader/reading_mode_sheet.dart';
import 'package:reader_app/utils/sentence_utils.dart';

class DocxReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const DocxReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<DocxReaderScreen> createState() => _DocxReaderScreenState();
}

class _DocxReaderScreenState extends State<DocxReaderScreen>
    with WidgetsBindingObserver {
  String? _htmlContent;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();
  ResolvedBookFile? _resolvedFile;
  String _plainText = '';
  List<SentenceSpan> _sentenceSpans = const [];
  bool _showChrome = false;
  bool _lockMode = false;
  Offset? _lastDoubleTapDown;
  late ReadingMode _readingMode;
  late double _lastScrollPosition;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _readingMode = widget.book.readingMode;
    _lastScrollPosition = widget.book.scrollPosition;
    _loadDocx();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateSystemUiMode();
    });
  }

  @override
  void dispose() {
    _cleanupTempFile();
    _scrollController.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadDocx() async {
    try {
      final resolver = BookFileResolver();
      final resolved = await resolver.resolve(widget.book);
      _resolvedFile = resolved;
      final html = await readDocxToHtml(path: resolved.path);
      final plainText = _htmlToPlainText(html);
      setState(() {
        _htmlContent = html;
        _plainText = plainText;
        _sentenceSpans = splitIntoSentences(plainText);
        _isLoading = false;
      });

      // Restore scroll position (basic implementation)
      // Note: precise scroll restoration for HTML is tricky because height isn't known until render.
      // For now, we just save progress as "opened"
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreScrollPosition();
      });

    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _cleanupTempFile() {
    final resolved = _resolvedFile;
    if (resolved == null || !resolved.isTemp) return;
    try {
      File(resolved.path).deleteSync();
    } catch (_) {
      // Ignore cleanup failures
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveScrollProgress();
    }
  }

  void _updateSystemUiMode() {
    if (_showChrome && !_lockMode) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
  }

  void _toggleChrome() {
    if (_lockMode) return;
    setState(() => _showChrome = !_showChrome);
    _updateSystemUiMode();
  }

  void _toggleLockMode() {
    setState(() {
      _lockMode = !_lockMode;
      if (_lockMode) {
        _showChrome = false;
      } else {
        _showChrome = true;
      }
    });
    _updateSystemUiMode();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _lockMode
                ? 'Lock mode on. Double-tap center to unlock.'
                : 'Lock mode off.',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  bool _isCenterTap(Offset globalPosition) {
    final size = MediaQuery.of(context).size;
    if (size.isEmpty) return false;
    final centerWidth = size.width * 0.45;
    final centerHeight = size.height * 0.35;
    final left = (size.width - centerWidth) / 2;
    final top = (size.height - centerHeight) / 2;
    final rect = Rect.fromLTWH(left, top, centerWidth, centerHeight);
    return rect.contains(globalPosition);
  }

  void _handleTapUp(TapUpDetails details) {
    if (_isCenterTap(details.globalPosition)) {
      _toggleChrome();
    }
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _lastDoubleTapDown = details.globalPosition;
  }

  void _handleDoubleTap() {
    if (!_lockMode) return;
    final position = _lastDoubleTapDown;
    if (position == null) return;
    if (_isCenterTap(position)) {
      _toggleLockMode();
    }
  }

  ReadingMode get _effectiveReadingMode {
    if (_readingMode == ReadingMode.webtoon) return ReadingMode.webtoon;
    if (_readingMode == ReadingMode.verticalContinuous) {
      return ReadingMode.verticalContinuous;
    }
    return ReadingMode.verticalContinuous;
  }

  Future<void> _showReadingModePicker() async {
    final selected = await showReadingModeSheet(
      context,
      current: _readingMode,
      formatType: ReaderFormatType.text,
    );
    if (selected == null || selected == _readingMode) return;
    setState(() => _readingMode = selected);
    widget.repository.updateReadingProgress(
      widget.book.id,
      readingMode: selected,
    );
  }

  void _restoreScrollPosition() {
    if (!_scrollController.hasClients) return;
    if (_lastScrollPosition <= 0) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    final clamped = _lastScrollPosition.clamp(0.0, maxExtent);
    _scrollController.jumpTo(clamped);
  }

  void _saveScrollProgress() {
    if (!_scrollController.hasClients) return;
    final currentScroll = _scrollController.offset;
    _lastScrollPosition = currentScroll;
    final text = _plainText;
    if (text.trim().isNotEmpty) {
      final maxExtent = _scrollController.position.maxScrollExtent;
      final fraction = maxExtent <= 0 ? 0.0 : (currentScroll / maxExtent);
      final maxIndex = text.length - 1;
      final approxIndex =
          maxIndex <= 0 ? 0 : (fraction * maxIndex).floor().clamp(0, maxIndex);
      final span =
          sentenceForOffset(_sentenceSpans, approxIndex) ?? SentenceSpan(0, text.length);
      widget.repository.updateReadingProgress(
        widget.book.id,
        currentPage: 1,
        totalPages: 1,
        scrollPosition: currentScroll,
        lastReadingSentenceStart: span.start,
        lastReadingSentenceEnd: span.end,
      );
      return;
    }
    widget.repository.updateReadingProgress(
      widget.book.id,
      currentPage: 1,
      totalPages: 1,
      scrollPosition: currentScroll,
    );
  }

  String _htmlToPlainText(String html) {
    if (html.trim().isEmpty) return '';
    final document = html_parser.parse(html);
    document
        .querySelectorAll('script,style,noscript')
        .forEach((e) => e.remove());
    final rawText = document.body?.text ??
        document.documentElement?.text ??
        document.text ??
        '';
    return rawText
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u200B', '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    final showChrome = _showChrome && !_lockMode;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: _handleTapUp,
              onDoubleTapDown: _handleDoubleTapDown,
              onDoubleTap: _handleDoubleTap,
              child: _buildBody(),
            ),
          ),
          if (showChrome) _buildTopBar(),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text("Error loading DOCX: $_error"),
            ],
          ),
        ),
      );
    }

    final isWebtoon = _effectiveReadingMode == ReadingMode.webtoon;
    final paragraphSpacing = isWebtoon ? 28.0 : 12.0;

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
          if (scrollNotification is ScrollEndNotification) {
               _saveScrollProgress();
          }
          return true;
      },
      child: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16.0),
        child: Html(
          data: _htmlContent,
          style: {
            "body": Style(
             fontSize: FontSize(16.0),
             lineHeight: LineHeight(1.5),
             color: Theme.of(context).textTheme.bodyLarge?.color,
           ),
             "p": Style(
                 margin: Margins.only(bottom: paragraphSpacing),
                 textAlign: TextAlign.justify,
             ),
          },
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
                Expanded(
                  child: Text(
                    widget.book.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: Icon(_lockMode ? Icons.lock : Icons.lock_open),
                  tooltip: _lockMode ? 'Unlock' : 'Lock',
                  onPressed: _toggleLockMode,
                ),
                IconButton(
                  icon: const Icon(Icons.view_carousel),
                  tooltip: 'Reading mode',
                  onPressed: _showReadingModePicker,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
