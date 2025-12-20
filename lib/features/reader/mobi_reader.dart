import 'package:flutter/material.dart';
import 'package:flutter_html/flutter_html.dart';
import 'package:reader_app/data/models/book.dart';
import 'package:reader_app/data/repositories/book_repository.dart';
import 'package:reader_app/src/rust/api/mobi.dart' as rust_mobi;

class MobiReaderScreen extends StatefulWidget {
  final Book book;
  final BookRepository repository;

  const MobiReaderScreen({
    super.key,
    required this.book,
    required this.repository,
  });

  @override
  State<MobiReaderScreen> createState() => _MobiReaderScreenState();
}

class _MobiReaderScreenState extends State<MobiReaderScreen> {
  String? _content;
  bool _isLoading = true;
  String? _error;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadMobi();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMobi() async {
    try {
      final content = rust_mobi.getMobiContent(path: widget.book.path);
      setState(() {
        _content = content;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
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

    if (_content != null) {
      return SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.all(16.0),
        child: Html(
          data: _content!,
          style: {
            "body": Style(
              fontSize: FontSize(18),
              lineHeight: const LineHeight(1.8),
            ),
            "p": Style(margin: Margins.only(bottom: 16)),
          },
        ),
      );
    }

    return const Center(child: Text('No content'));
  }
}
