import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:reader_app/src/rust/api/pdf.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';

class PdfReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const PdfReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  Uint8List? _currentPageImage;
  bool _isLoading = true;
  String? _error;
  int _pageIndex = 0;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.book.currentPage;
    _loadDocument();
  }

  Future<void> _loadDocument() async {
    try {
      final count = await getPdfPageCount(path: widget.book.path);
      setState(() {
        _pageCount = count;
      });
      await _renderPage(_pageIndex);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _renderPage(int index) async {
    setState(() {
      _isLoading = true;
      _pageIndex = index;
    });

    // Save progress
    widget.repository.updateReadingProgress(
      widget.book.id,
      currentPage: index,
      totalPages: _pageCount,
    );

    try {
      // Render at 2x screen resolution for sharpness
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final width = (screenWidth * 2).toInt();
      final height = (screenHeight * 2).toInt();

      final bytes = await renderPdfPage(
        path: widget.book.path,
        pageIndex: index,
        width: width,
        height: height,
      );

      setState(() {
        _currentPageImage = bytes;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = "Render Error: $e";
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
          if (_pageCount > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Text("${_pageIndex + 1} / $_pageCount"),
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

    if (_isLoading && _currentPageImage == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_currentPageImage != null) {
      return InteractiveViewer(
        maxScale: 5.0,
        child: Center(
          child: Image.memory(
            _currentPageImage!,
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    return const Center(child: Text("Initializing..."));
  }

  Widget? _buildControls() {
    if (_pageCount <= 1) return null;

    return BottomAppBar(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            icon: const Icon(Icons.first_page),
            onPressed: _pageIndex > 0 ? () => _renderPage(0) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed:
                _pageIndex > 0 ? () => _renderPage(_pageIndex - 1) : null,
          ),
          Text("${_pageIndex + 1} / $_pageCount"),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _pageIndex < _pageCount - 1
                ? () => _renderPage(_pageIndex + 1)
                : null,
          ),
          IconButton(
            icon: const Icon(Icons.last_page),
            onPressed: _pageIndex < _pageCount - 1
                ? () => _renderPage(_pageCount - 1)
                : null,
          ),
        ],
      ),
    );
  }
}
