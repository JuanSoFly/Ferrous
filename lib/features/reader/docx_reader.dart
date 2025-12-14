import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/src/rust/api/docx.dart';

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

class _DocxReaderScreenState extends State<DocxReaderScreen> {
  String? _htmlContent;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadDocx();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDocx() async {
    try {
      final html = await readDocxToHtml(path: widget.book.path);
      setState(() {
        _htmlContent = html;
        _isLoading = false;
      });

      // Restore scroll position (basic implementation)
      // Note: precise scroll restoration for HTML is tricky because height isn't known until render.
      // For now, we just save progress as "opened"
      WidgetsBinding.instance.addPostFrameCallback((_) {
         if (_scrollController.hasClients && widget.book.scrollPosition > 0) {
             _scrollController.jumpTo(widget.book.scrollPosition);
         }
      });

    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _onScroll() {
      if (_scrollController.hasClients) {
          // Update progress roughly based on scroll percentage?
          // Or just save offset. DOCX is one long page usually.
          // Update progress roughly based on scroll percentage?
          // Or just save offset. DOCX is one long page usually.
          double currentScroll = _scrollController.offset;
          
          // Don't spam updates
          // Throttle needed ideally, but for now relying on user stoppage/navigation
          widget.repository.updateReadingProgress(
              widget.book.id,
              currentPage: 1, // Treat as single page docs for now
              totalPages: 1,
              scrollPosition: currentScroll,
          );
      }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.book.title),
      ),
      body: _buildBody(),
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

    return NotificationListener<ScrollNotification>(
      onNotification: (scrollNotification) {
          if (scrollNotification is ScrollEndNotification) {
               _onScroll();
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
                 margin: Margins.only(bottom: 12),
                 textAlign: TextAlign.justify,
             ),
          },
        ),
      ),
    );
  }
}
