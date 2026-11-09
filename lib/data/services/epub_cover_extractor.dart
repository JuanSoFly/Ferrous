import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;

class EpubCoverExtractor {
  static const Set<String> _imageExtensions = {
    '.jpg',
    '.jpeg',
    '.png',
    '.webp',
    '.gif',
  };

  static bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return _imageExtensions.any((ext) => lower.endsWith(ext));
  }

  static String _normalizePath(String path) {
    var normalized = path.replaceAll('\\', '/');
    normalized = normalized.replaceFirst(RegExp(r'^/+'), '');
    final parts = normalized.split('/');
    final output = <String>[];
    for (final part in parts) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (output.isNotEmpty) output.removeLast();
        continue;
      }
      output.add(part);
    }
    return output.join('/');
  }

  static String _resolveHref(String baseDir, String href) {
    var cleanHref = href.split('#').first.split('?').first.trim();
    try {
      cleanHref = Uri.decodeFull(cleanHref);
    } catch (_) {}
    if (cleanHref.startsWith('/')) {
      cleanHref = cleanHref.substring(1);
    }
    if (baseDir.isEmpty) {
      return _normalizePath(cleanHref);
    }
    return _normalizePath('$baseDir$cleanHref');
  }

  static String _directoryOf(String path) {
    final normalized = _normalizePath(path);
    final index = normalized.lastIndexOf('/');
    if (index == -1) return '';
    return normalized.substring(0, index + 1);
  }

  static Uint8List? _archiveFileBytes(ArchiveFile? file) {
    if (file == null) return null;
    final content = file.content;
    if (content is Uint8List) return content;
    if (content is List<int>) return Uint8List.fromList(content);
    if (content is String) return Uint8List.fromList(utf8.encode(content));
    return null;
  }

  static ArchiveFile? _findFile(
    Map<String, ArchiveFile> filesByLowerPath,
    String path,
  ) {
    final normalized = _normalizePath(path).toLowerCase();
    return filesByLowerPath[normalized];
  }

  static String? _extractFirstImageRefFromHtml(String html) {
    try {
      final doc = html_parser.parse(html);

      for (final img in doc.querySelectorAll('img')) {
        final src = img.attributes['src']?.trim();
        if (src != null && src.isNotEmpty) return src;
      }

      for (final image in doc.querySelectorAll('image')) {
        for (final entry in image.attributes.entries) {
          final keyStr = entry.key.toString().toLowerCase();
          if (keyStr.contains('href') || keyStr == 'src') {
            final val = entry.value.trim();
            if (val.isNotEmpty) return val;
          }
        }
      }

      for (final obj in doc.querySelectorAll('object')) {
        final data = obj.attributes['data']?.trim();
        if (data != null && data.isNotEmpty && _isImagePath(data)) {
          return data;
        }
      }
    } catch (_) {}

    final re = RegExp(
      r'''<(?:img|image)\s+[^>]*?(?:src|href|xlink:href)\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    );
    final match = re.firstMatch(html);
    if (match != null) {
      final val = match.group(1)?.trim();
      if (val != null && val.isNotEmpty) return val;
    }

    return null;
  }

  static Future<String?> extractCover(String bookPath, String savePath) async {
    try {
      final file = File(bookPath);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      return await extractCoverFromBytes(bytes, savePath);
    } catch (e) {
      debugPrint('EpubCoverExtractor error for $bookPath: $e');
      return null;
    }
  }

  static Future<String?> extractCoverFromBytes(
    List<int> bytes,
    String savePath,
  ) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final filesByLowerPath = <String, ArchiveFile>{};
      for (final f in archive.files) {
        if (!f.isFile) continue;
        filesByLowerPath[_normalizePath(f.name).toLowerCase()] = f;
      }

      Uint8List? coverBytes = _findCoverBytes(filesByLowerPath);
      if (coverBytes == null || coverBytes.isEmpty) {
        // Fallback: scan archive for any image
        for (final f in archive.files) {
          if (!f.isFile) continue;
          if (_isImagePath(f.name)) {
            coverBytes = _archiveFileBytes(f);
            if (coverBytes != null && coverBytes.isNotEmpty) break;
          }
        }
      }

      if (coverBytes == null || coverBytes.isEmpty) return null;

      return _saveCoverThumbnail(coverBytes, savePath);
    } catch (e) {
      debugPrint('EpubCoverExtractor.extractCoverFromBytes error: $e');
      return null;
    }
  }

  static Uint8List? _findCoverBytes(Map<String, ArchiveFile> files) {
    // 1. Read container.xml
    final containerFile = _findFile(files, 'META-INF/container.xml');
    if (containerFile == null) return null;
    final containerXml = utf8.decode(
      _archiveFileBytes(containerFile) ?? const [],
      allowMalformed: true,
    );
    final containerDoc = xml.XmlDocument.parse(containerXml);

    String? rootfilePath;
    for (final el in containerDoc.findAllElements('rootfile')) {
      final fp = el.getAttribute('full-path') ?? el.getAttribute('fullpath');
      if (fp != null && fp.trim().isNotEmpty) {
        rootfilePath = fp.trim();
        break;
      }
    }
    if (rootfilePath == null) return null;

    final opfPath = _normalizePath(Uri.decodeFull(rootfilePath));
    final opfFile = _findFile(files, opfPath);
    if (opfFile == null) return null;
    final opfXml = utf8.decode(
      _archiveFileBytes(opfFile) ?? const [],
      allowMalformed: true,
    );
    final opfDoc = xml.XmlDocument.parse(opfXml);
    final contentDir = _directoryOf(opfPath);

    final manifest = <String, ({String id, String href, String? mediaType, String? properties})>{};
    for (final item in opfDoc.findAllElements('item')) {
      final id = item.getAttribute('id')?.trim();
      final href = item.getAttribute('href')?.trim();
      if (id == null || href == null || id.isEmpty || href.isEmpty) continue;
      manifest[id] = (
        id: id,
        href: href,
        mediaType: item.getAttribute('media-type') ?? item.getAttribute('mediaType'),
        properties: item.getAttribute('properties'),
      );
    }

    bool isImageItem(({String id, String href, String? mediaType, String? properties}) item) {
      final mt = item.mediaType?.toLowerCase() ?? '';
      if (mt.startsWith('image/')) return true;
      return _isImagePath(item.href);
    }

    Uint8List? getBytesFromHref(String baseDir, String href) {
      final resolved = _resolveHref(baseDir, href);
      final f = _findFile(files, resolved);
      return _archiveFileBytes(f);
    }

    // A. EPUB 3 properties="cover-image"
    for (final item in manifest.values) {
      final props = item.properties?.toLowerCase().split(RegExp(r'\s+')) ?? [];
      if (props.contains('cover-image') && isImageItem(item)) {
        final b = getBytesFromHref(contentDir, item.href);
        if (b != null && b.isNotEmpty) return b;
      }
    }

    // B. EPUB 2 <meta name="cover" content="..."/>
    String? metaCoverId;
    for (final meta in opfDoc.findAllElements('meta')) {
      final name = meta.getAttribute('name')?.trim().toLowerCase();
      if (name == 'cover') {
        final content = meta.getAttribute('content')?.trim();
        if (content != null && content.isNotEmpty) {
          metaCoverId = content;
          break;
        }
      }
    }
    if (metaCoverId != null) {
      final item = manifest[metaCoverId];
      if (item != null) {
        if (isImageItem(item)) {
          final b = getBytesFromHref(contentDir, item.href);
          if (b != null && b.isNotEmpty) return b;
        } else {
          // XHTML wrapper
          final htmlBytes = getBytesFromHref(contentDir, item.href);
          if (htmlBytes != null) {
            final html = utf8.decode(htmlBytes, allowMalformed: true);
            final imgRef = _extractFirstImageRefFromHtml(html);
            if (imgRef != null) {
              final chapterDir = _directoryOf(_resolveHref(contentDir, item.href));
              final b = getBytesFromHref(chapterDir, imgRef);
              if (b != null && b.isNotEmpty) return b;
            }
          }
        }
      } else {
        // In case metaCoverId was directly an href
        final b = getBytesFromHref(contentDir, metaCoverId);
        if (b != null && b.isNotEmpty) return b;
      }
    }

    // C. <guide><reference type="cover|title-page">
    for (final ref in opfDoc.findAllElements('reference')) {
      final typ = ref.getAttribute('type')?.trim().toLowerCase();
      if (typ == 'cover' || typ == 'title-page') {
        final href = ref.getAttribute('href')?.trim();
        if (href != null && href.isNotEmpty) {
          if (_isImagePath(href)) {
            final b = getBytesFromHref(contentDir, href);
            if (b != null && b.isNotEmpty) return b;
          }
          final htmlBytes = getBytesFromHref(contentDir, href);
          if (htmlBytes != null) {
            final html = utf8.decode(htmlBytes, allowMalformed: true);
            final imgRef = _extractFirstImageRefFromHtml(html);
            if (imgRef != null) {
              final refDir = _directoryOf(_resolveHref(contentDir, href));
              final b = getBytesFromHref(refDir, imgRef);
              if (b != null && b.isNotEmpty) return b;
            }
          }
        }
      }
    }

    // D. Manifest item with "cover" or "title" in id or href
    for (final item in manifest.values) {
      if (!isImageItem(item)) continue;
      final lowerId = item.id.toLowerCase();
      final lowerHref = item.href.toLowerCase();
      if (lowerId.contains('cover') || lowerHref.contains('cover') || lowerHref.contains('title')) {
        final b = getBytesFromHref(contentDir, item.href);
        if (b != null && b.isNotEmpty) return b;
      }
    }

    // E. Spine fallback: First 3 spine items
    final spineIdRefs = <String>[];
    for (final spine in opfDoc.findAllElements('spine')) {
      for (final itemref in spine.findAllElements('itemref')) {
        final idref = itemref.getAttribute('idref')?.trim();
        if (idref != null && idref.isNotEmpty) {
          spineIdRefs.add(idref);
        }
      }
    }

    for (final idref in spineIdRefs.take(3)) {
      final item = manifest[idref];
      if (item == null) continue;
      if (isImageItem(item)) {
        final b = getBytesFromHref(contentDir, item.href);
        if (b != null && b.isNotEmpty) return b;
      } else {
        final htmlBytes = getBytesFromHref(contentDir, item.href);
        if (htmlBytes != null) {
          final html = utf8.decode(htmlBytes, allowMalformed: true);
          final imgRef = _extractFirstImageRefFromHtml(html);
          if (imgRef != null) {
            final chapterDir = _directoryOf(_resolveHref(contentDir, item.href));
            final b = getBytesFromHref(chapterDir, imgRef);
            if (b != null && b.isNotEmpty) return b;
          }
        }
      }
    }

    // F. First image item in manifest
    for (final item in manifest.values) {
      if (isImageItem(item)) {
        final b = getBytesFromHref(contentDir, item.href);
        if (b != null && b.isNotEmpty) return b;
      }
    }

    return null;
  }

  static String _saveCoverThumbnail(Uint8List bytes, String savePath) {
    final outFile = File(savePath);
    outFile.parent.createSync(recursive: true);
    outFile.writeAsBytesSync(bytes);
    return savePath;
  }
}
