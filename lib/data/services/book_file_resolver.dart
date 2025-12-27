import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/services/saf_service.dart';

class ResolvedBookFile {
  final String path;
  final bool isTemp;

  const ResolvedBookFile({
    required this.path,
    required this.isTemp,
  });
}

class BookFileResolver {
  final SafService _safService;

  BookFileResolver({SafService? safService})
      : _safService = safService ?? SafService();

  Future<ResolvedBookFile> resolve(
    Book book, {
    bool forceRefresh = false,
  }) async {
    if (book.sourceType == BookSourceType.imported ||
        (book.sourceUri == null || book.sourceUri!.isEmpty)) {
      if (book.filePath.isEmpty) {
        throw StateError('Imported book has no file path.');
      }
      return ResolvedBookFile(path: book.filePath, isTemp: false);
    }

    final uri = book.sourceUri;
    if (uri == null || uri.isEmpty) {
      throw StateError('Linked book has no source URI.');
    }

    final suggestedName = _buildSuggestedName(book);
    final tempPath = await _safService.copyUriToCache(
      uri: uri,
      suggestedName: suggestedName,
      force: forceRefresh,
    );
    return ResolvedBookFile(path: tempPath, isTemp: true);
  }

  String _buildSuggestedName(Book book) {
    var base = book.title.trim();
    if (base.isEmpty) {
      base = 'book_${book.id.substring(0, 8)}';
    }
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    final ext = book.format.trim().toLowerCase();
    if (ext.isEmpty) return base;
    if (base.toLowerCase().endsWith('.$ext')) return base;
    return '$base.$ext';
  }
}
