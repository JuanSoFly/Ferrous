import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:archive/archive.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';

class CbzReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const CbzReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<CbzReaderScreen> createState() => _CbzReaderScreenState();
}

class _CbzReaderScreenState extends State<CbzReaderScreen> {
  List<Uint8List> _pages = [];
  int _currentPage = 0;
  bool _isLoading = true;
  String? _error;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentPage = widget.book.currentPage;
    _pageController = PageController(initialPage: _currentPage);
    _loadCbz();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadCbz() async {
    try {
      final bytes = await File(widget.book.path).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // Filter and sort image files
      final imageFiles = archive.files.where((file) {
        if (file.isFile) {
          final name = file.name.toLowerCase();
          return name.endsWith('.jpg') ||
              name.endsWith('.jpeg') ||
              name.endsWith('.png') ||
              name.endsWith('.gif') ||
              name.endsWith('.webp');
        }
        return false;
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));

      final pages = <Uint8List>[];
      for (var file in imageFiles) {
        final content = file.content as List<int>;
        pages.add(Uint8List.fromList(content));
      }

      setState(() {
        _pages = pages;
        _isLoading = false;
      });
      
      // Validation of page index
      if (_currentPage >= pages.length) {
         _currentPage = 0;
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _goToPage(int page) {
    if (page >= 0 && page < _pages.length) {
      _pageController.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });

    // Save progress
    widget.repository.updateReadingProgress(
      widget.book.id,
      currentPage: index,
      totalPages: _pages.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
        actions: [
          if (_pages.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text("${_currentPage + 1} / ${_pages.length}"),
              ),
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

    if (_pages.isEmpty) {
      return const Center(child: Text("No images found in archive"));
    }

    return PageView.builder(
      controller: _pageController,
      itemCount: _pages.length,
      onPageChanged: _onPageChanged,
      itemBuilder: (context, index) {
        return InteractiveViewer(
          maxScale: 5.0,
          child: Center(
            child: Image.memory(
              _pages[index],
              fit: BoxFit.contain,
            ),
          ),
        );
      },
    );
  }

  Widget? _buildControls() {
    if (_pages.length <= 1) return null;

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page),
            onPressed: _currentPage > 0 ? () => _goToPage(0) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed:
                _currentPage > 0 ? () => _goToPage(_currentPage - 1) : null,
          ),
          Text("${_currentPage + 1} / ${_pages.length}"),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _currentPage < _pages.length - 1
                ? () => _goToPage(_currentPage + 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            onPressed: _currentPage < _pages.length - 1
                ? () => _goToPage(_pages.length - 1)
                : null,
          ),
        ],
      ),
    );
  }
}
