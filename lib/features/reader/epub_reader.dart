import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/models/annotation.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/data/repositories/annotation_repository.dart';
import 'package:reader_app/features/annotations/annotation_dialog.dart';

class EpubReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const EpubReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends State<EpubReaderScreen> {
  List<EpubChapter>? _chapters;
  int _currentChapterIndex = 0;
  String? _currentContent;
  SelectedContent? _selectedContent;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.book.sectionIndex;
    _loadEpub();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEpub() async {
    try {
      final bytes = await File(widget.book.path).readAsBytes();
      final book = await EpubReader.readBook(bytes);

      // Flatten chapters
      final chapters = _flattenChapters(book.Chapters ?? []);

      setState(() {
        _chapters = chapters;
      });

      if (chapters.isNotEmpty) {
        // Validation of index
        if (_currentChapterIndex >= chapters.length) {
          _currentChapterIndex = 0;
        }
        await _loadChapter(_currentChapterIndex);
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

    // Save progress
    widget.repository.updateReadingProgress(
      widget.book.id,
      sectionIndex: index,
      totalPages: _chapters!.length,
    );

    try {
      final chapter = _chapters![index];
      String content = chapter.HtmlContent ?? '';

      setState(() {
        _currentContent = content;
        _isLoading = false;
      });

      // Reset scroll for now (TODO: Restore scroll position)
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(0);
      }
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
        title: Text(widget.book.title),
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
      return SelectionArea(
        onSelectionChanged: (content) {
          _selectedContent = content;
        },
        contextMenuBuilder: (context, selectableRegionState) {
          return AdaptiveTextSelectionToolbar.buttonItems(
            anchors: selectableRegionState.contextMenuAnchors,
            buttonItems: [
              ...selectableRegionState.contextMenuButtonItems,
              ContextMenuButtonItem(
                onPressed: () {
                  if (_selectedContent != null && _selectedContent!.plainText.isNotEmpty) {
                    _showAnnotationDialog(_selectedContent!.plainText);
                    selectableRegionState.hideToolbar();
                  }
                },
                label: 'Highlight',
              ),
            ],
          );
        },
        child: SingleChildScrollView(
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

  Future<void> _showAnnotationDialog(String selectedText) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => AnnotationDialog(selectedText: selectedText),
    );

    if (result != null && mounted) {
      final note = result['note'] as String;
      final color = result['color'] as int;

      final annotation = Annotation(
        id: const Uuid().v4(),
        bookId: widget.book.id,
        selectedText: selectedText,
        note: note,
        chapterIndex: _currentChapterIndex,
        startOffset: 0, // Not precise yet
        endOffset: 0, // Not precise yet
        color: color,
        createdAt: DateTime.now(),
      );

      await context.read<AnnotationRepository>().addAnnotation(annotation);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Annotation saved')),
        );
      }
    }
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
