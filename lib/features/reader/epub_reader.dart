import 'dart:io';
import 'package:flutter/material.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter_html/flutter_html.dart';

class EpubReaderScreen extends StatefulWidget {
  final String path;
  final String title;

  const EpubReaderScreen({super.key, required this.path, required this.title});

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  EpubBook? _book;
  List<EpubChapter>? _chapters;
  int _currentChapterIndex = 0;
  String? _currentContent;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadEpub();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEpub() async {
    try {
      final bytes = await File(widget.path).readAsBytes();
      final book = await EpubReader.readBook(bytes);

      // Flatten chapters
      final chapters = _flattenChapters(book.Chapters ?? []);

      setState(() {
        _book = book;
        _chapters = chapters;
      });

      if (chapters.isNotEmpty) {
        await _loadChapter(0);
      } else {
        setState(() {
          _error = "No chapters found in EPUB";
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  List<EpubChapter> _flattenChapters(List<EpubChapter> chapters) {
    List<EpubChapter> result = [];
    for (var chapter in chapters) {
      result.add(chapter);
      if (chapter.SubChapters != null && chapter.SubChapters!.isNotEmpty) {
        result.addAll(_flattenChapters(chapter.SubChapters!));
      }
    }
    return result;
  }

  Future<void> _loadChapter(int index) async {
    if (_chapters == null || index < 0 || index >= _chapters!.length) return;

    setState(() {
      _isLoading = true;
      _currentChapterIndex = index;
    });

    try {
      final chapter = _chapters![index];
      String content = chapter.HtmlContent ?? '';

      setState(() {
        _currentContent = content;
        _isLoading = false;
      });

      _scrollController.jumpTo(0);
    } catch (e) {
      setState(() {
        _error = "Chapter load error: $e";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: _showChapterList,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildControls(),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text("Error: $_error", textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentContent != null) {
      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16.0),
        child: Html(
          data: _currentContent!,
          style: {
            "body": Style(
              fontSize: FontSize(18),
              lineHeight: const LineHeight(1.8),
            ),
            "p": Style(margin: Margins.only(bottom: 16)),
            "img": Style(width: Width(100, Unit.percent)),
          },
        ),
      );
    }

    return const Center(child: Text("Loading..."));
  }

  Widget? _buildControls() {
    if (_chapters == null || _chapters!.length <= 1) return null;

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _currentChapterIndex > 0
                ? () => _loadChapter(_currentChapterIndex - 1)
                : null,
          ),
          Text(
            "Chapter ${_currentChapterIndex + 1} / ${_chapters!.length}",
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentChapterIndex < _chapters!.length - 1
                ? () => _loadChapter(_currentChapterIndex + 1)
                : null,
          ),
        ],
      ),
    );
  }

  void _showChapterList() {
    if (_chapters == null) return;

    showModalBottomSheet(
      context: context,
      builder: (context) => ListView.builder(
        itemCount: _chapters!.length,
        itemBuilder: (context, index) {
          final chapter = _chapters![index];
          return ListTile(
            title: Text(chapter.Title ?? 'Chapter ${index + 1}'),
            selected: index == _currentChapterIndex,
            onTap: () {
              Navigator.pop(context);
              _loadChapter(index);
            },
          );
        },
      ),
    );
  }
}
