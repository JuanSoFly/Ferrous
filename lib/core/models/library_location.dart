import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/data/services/saf_service.dart';

/// Represents a configured book scan directory or storage location in Ferrous.
class LibraryLocation {
  final String id;
  final String uri;
  final String displayName;
  final String readablePath;
  final SafStorageMode storageMode;
  final bool isValid;
  final int bookCount;
  final int totalSizeBytes;
  final DateTime? lastScanned;
  final bool isScanning;

  const LibraryLocation({
    required this.id,
    required this.uri,
    required this.displayName,
    required this.readablePath,
    required this.storageMode,
    this.isValid = true,
    this.bookCount = 0,
    this.totalSizeBytes = 0,
    this.lastScanned,
    this.isScanning = false,
  });

  LibraryLocation copyWith({
    String? id,
    String? uri,
    String? displayName,
    String? readablePath,
    SafStorageMode? storageMode,
    bool? isValid,
    int? bookCount,
    int? totalSizeBytes,
    DateTime? lastScanned,
    bool? isScanning,
  }) {
    return LibraryLocation(
      id: id ?? this.id,
      uri: uri ?? this.uri,
      displayName: displayName ?? this.displayName,
      readablePath: readablePath ?? this.readablePath,
      storageMode: storageMode ?? this.storageMode,
      isValid: isValid ?? this.isValid,
      bookCount: bookCount ?? this.bookCount,
      totalSizeBytes: totalSizeBytes ?? this.totalSizeBytes,
      lastScanned: lastScanned ?? this.lastScanned,
      isScanning: isScanning ?? this.isScanning,
    );
  }

  /// Formats byte sizes into human-readable strings (e.g. 14.2 MB).
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double dBytes = bytes.toDouble();
    while (dBytes >= 1024 && i < suffixes.length - 1) {
      dBytes /= 1024;
      i++;
    }
    return '${dBytes.toStringAsFixed(dBytes >= 10 || i == 0 ? 0 : 1)} ${suffixes[i]}';
  }

  /// Extracts a human-readable folder name from a SAF URI or file path.
  static String extractNameFromUri(String uriString) {
    if (uriString.isEmpty) return 'Unnamed Location';
    try {
      final decoded = Uri.decodeFull(uriString);
      if (decoded.contains('tree/')) {
        final treePart = decoded.split('tree/').last;
        final cleanPart = treePart.split('/document/').first;
        final colonIndex = cleanPart.indexOf(':');
        final pathAfterColon = colonIndex != -1 ? cleanPart.substring(colonIndex + 1) : cleanPart;
        final segments = pathAfterColon.split('/').where((s) => s.isNotEmpty).toList();
        if (segments.isNotEmpty) {
          return segments.last;
        }
      }
      final parsed = Uri.tryParse(uriString);
      if (parsed != null && parsed.pathSegments.isNotEmpty) {
        final last = parsed.pathSegments.last;
        final colonIndex = last.indexOf(':');
        if (colonIndex != -1 && colonIndex < last.length - 1) {
          final after = last.substring(colonIndex + 1);
          final segments = after.split('/').where((s) => s.isNotEmpty).toList();
          if (segments.isNotEmpty) return segments.last;
        }
        return last;
      }
      final normalized = uriString.replaceAll('\\', '/');
      final segs = normalized.split('/').where((s) => s.isNotEmpty).toList();
      if (segs.isNotEmpty) return segs.last;
    } catch (_) {}
    return 'Folder';
  }

  /// Extracts a readable directory path for display from a SAF URI or file path.
  static String extractReadablePath(String uriString) {
    if (uriString.isEmpty) return '';
    try {
      final decoded = Uri.decodeFull(uriString);
      if (decoded.contains('primary:')) {
        final sub = decoded.split('primary:').last.split('/document/').first;
        return sub.isEmpty ? 'Internal Storage' : 'Internal Storage / $sub';
      }
      if (decoded.contains('tree/')) {
        final treePart = decoded.split('tree/').last.split('/document/').first;
        final colonIndex = treePart.indexOf(':');
        if (colonIndex != -1) {
          final storage = treePart.substring(0, colonIndex);
          final sub = treePart.substring(colonIndex + 1);
          final storageLabel = storage.contains('-') ? 'SD Card ($storage)' : storage;
          return sub.isEmpty ? storageLabel : '$storageLabel / $sub';
        }
        return treePart;
      }
      return uriString.replaceAll('\\', '/');
    } catch (_) {}
    return uriString;
  }

  /// Determines whether a book belongs to or originates from a given location.
  static bool bookBelongsToLocation(Book book, String locationUri) {
    if (locationUri.isEmpty) return false;

    // 1. Check sourceUri (Storage Access Framework URI)
    final sourceUri = book.sourceUri;
    if (sourceUri != null && sourceUri.isNotEmpty) {
      if (sourceUri.startsWith(locationUri)) return true;
      try {
        final decodedSource = Uri.decodeFull(sourceUri);
        final decodedLocation = Uri.decodeFull(locationUri);
        if (decodedSource.startsWith(decodedLocation) || decodedSource.contains(decodedLocation)) {
          return true;
        }
        final locParsed = Uri.tryParse(locationUri);
        final locSegment = locParsed != null && locParsed.pathSegments.isNotEmpty
            ? locParsed.pathSegments.last
            : '';
        if (locSegment.isNotEmpty) {
          final decodedLocSegment = Uri.decodeComponent(locSegment);
          if (sourceUri.contains(locSegment) || decodedSource.contains(decodedLocSegment)) {
            return true;
          }
        }
      } catch (_) {}
    }

    // 2. Check direct file system path (Desktop or internal files)
    if (book.filePath.isNotEmpty) {
      final normPath = book.filePath.replaceAll('\\', '/').toLowerCase();
      final normLoc = locationUri.replaceAll('\\', '/').toLowerCase();
      if (normPath.startsWith(normLoc)) return true;
    }

    return false;
  }
}
