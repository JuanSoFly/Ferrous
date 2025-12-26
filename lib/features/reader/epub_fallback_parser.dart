import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;

class EpubFallbackParser {
  static const Set<String> _htmlMediaTypes = {
    'application/xhtml+xml',
    'text/html',
    'application/html',
    'application/x-dtbook+xml',
    'text/x-oeb1-document',
  };

  static List<EpubChapter> parseChapters(List<int> bytes) {
    final Archive archive;
    final Map<String, ArchiveFile> filesByLowerPath;
    final String opfPath;
    final ArchiveFile opfFile;

    try {
      archive = ZipDecoder().decodeBytes(bytes);
      filesByLowerPath = <String, ArchiveFile>{};

      for (final file in archive.files) {
        if (!file.isFile) continue;
        final normalized = _normalizePath(file.name).toLowerCase();
        filesByLowerPath[normalized] = file;
      }

      final containerFile = _findFile(filesByLowerPath, 'META-INF/container.xml');
      if (containerFile == null) {
        throw Exception('EPUB parsing error: container.xml not found.');
      }

      final containerDoc = xml.XmlDocument.parse(_decodeText(containerFile));
      final rootfilePath = _readRootfilePath(containerDoc);
      if (rootfilePath == null || rootfilePath.trim().isEmpty) {
        throw Exception('EPUB parsing error: rootfile path not found in container.xml.');
      }

      opfPath = _normalizePath(Uri.decodeFull(rootfilePath));
      final tempOpfFile = _findFile(filesByLowerPath, opfPath);
      if (tempOpfFile == null) {
        throw Exception('EPUB parsing error: OPF file $opfPath not found in archive.');
      }
      opfFile = tempOpfFile;
    } catch (e) {
      // Enhanced error reporting for debugging
      throw Exception('EPUB fallback parsing failed: ${e.toString()}');
    }

    final opfDoc = xml.XmlDocument.parse(_decodeText(opfFile));
    final manifest = _readManifest(opfDoc);
    final spineIdRefs = _readSpineIdRefs(opfDoc);
    final contentDir = _directoryOf(opfPath);

    final orderedItems = <_ManifestItem>[];

    if (spineIdRefs.isNotEmpty) {
      for (final idref in spineIdRefs) {
        final item = manifest[idref];
        if (item == null) continue;
        if (_isHtmlItem(item)) {
          orderedItems.add(item);
        }
      }
    }

    if (orderedItems.isEmpty) {
      for (final item in manifest.values) {
        if (_isHtmlItem(item)) {
          orderedItems.add(item);
        }
      }
    }

    final chapters = <EpubChapter>[];
    var index = 1;

    for (final item in orderedItems) {
      final resolvedPath = _resolveHref(contentDir, item.href);
      final file = _findFile(filesByLowerPath, resolvedPath);
      if (file == null) continue;

      final html = _decodeText(file);
      if (html.trim().isEmpty) continue;

      final fallbackTitle = _fallbackTitle(item, index);
      final title = _inferTitle(html, fallback: fallbackTitle);

      chapters.add(EpubChapter()
        ..Title = title
        ..ContentFileName = resolvedPath
        ..HtmlContent = html
        ..SubChapters = const <EpubChapter>[]);
      index++;
    }

    return chapters;
  }

  static ArchiveFile? _findFile(
    Map<String, ArchiveFile> filesByLowerPath,
    String path,
  ) {
    final normalized = _normalizePath(path).toLowerCase();
    return filesByLowerPath[normalized];
  }

  static String _decodeText(ArchiveFile file) {
    final bytes = _archiveFileBytes(file);
    return utf8.decode(bytes, allowMalformed: true);
  }

  static List<int> _archiveFileBytes(ArchiveFile file) {
    final content = file.content;
    if (content is Uint8List) return content;
    if (content is List<int>) return content;
    if (content is String) return utf8.encode(content);
    return List<int>.from(content as List<dynamic>);
  }

  static String? _readRootfilePath(xml.XmlDocument containerDoc) {
    for (final element in containerDoc.findAllElements('rootfile')) {
      final fullPath =
          element.getAttribute('full-path') ?? element.getAttribute('fullpath');
      if (fullPath != null && fullPath.trim().isNotEmpty) {
        return fullPath.trim();
      }
    }
    return null;
  }

  static Map<String, _ManifestItem> _readManifest(xml.XmlDocument opfDoc) {
    final items = <String, _ManifestItem>{};

    for (final item in opfDoc.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;

      final mediaType =
          item.getAttribute('media-type') ?? item.getAttribute('mediaType');

      items[id] = _ManifestItem(
        id: id,
        href: href,
        mediaType: mediaType,
      );
    }

    return items;
  }

  static List<String> _readSpineIdRefs(xml.XmlDocument opfDoc) {
    final ids = <String>[];

    for (final spine in opfDoc.findAllElements('spine')) {
      for (final itemref in spine.findAllElements('itemref')) {
        final idref = itemref.getAttribute('idref');
        if (idref != null && idref.trim().isNotEmpty) {
          ids.add(idref.trim());
        }
      }
      if (ids.isNotEmpty) break;
    }

    return ids;
  }

  static bool _isHtmlItem(_ManifestItem item) {
    final media = item.mediaType?.toLowerCase().trim();
    if (media != null && _htmlMediaTypes.contains(media)) {
      return true;
    }

    final lowerHref = item.href.toLowerCase();
    return lowerHref.endsWith('.xhtml') ||
        lowerHref.endsWith('.html') ||
        lowerHref.endsWith('.htm');
  }

  static String _resolveHref(String baseDir, String href) {
    var cleanHref = href.split('#').first;
    cleanHref = Uri.decodeFull(cleanHref);
    if (cleanHref.startsWith('/')) {
      cleanHref = cleanHref.substring(1);
    }

    if (baseDir.isEmpty) {
      return _normalizePath(cleanHref);
    }

    return _normalizePath('$baseDir$cleanHref');
  }

  static String _normalizePath(String path) {
    var normalized = path.replaceAll('\\', '/');
    normalized = normalized.replaceFirst(RegExp(r'^/+'), '');

    final parts = normalized.split('/');
    final output = <String>[];

    for (final part in parts) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (output.isNotEmpty) {
          output.removeLast();
        }
        continue;
      }
      output.add(part);
    }

    return output.join('/');
  }

  static String _directoryOf(String path) {
    final normalized = _normalizePath(path);
    final index = normalized.lastIndexOf('/');
    if (index == -1) return '';
    return normalized.substring(0, index + 1);
  }

  static String _fallbackTitle(_ManifestItem item, int index) {
    // Don't use item.id as it often contains internal identifiers like "adca-1"
    // Try to extract a meaningful name from the href (filename without extension)
    final href = Uri.decodeFull(item.href);
    final parts = href.split('/');
    final fileName = parts.isEmpty ? '' : parts.last;
    
    if (fileName.isNotEmpty) {
      // Remove extension and clean up
      var cleanName = fileName.replaceAll(RegExp(r'\.(x?html?|htm)$', caseSensitive: false), '');
      // Capitalize and replace underscores/dashes with spaces
      cleanName = cleanName.replaceAll(RegExp(r'[-_]'), ' ').trim();
      // Don't use if it's just a number or looks like an internal ID
      if (cleanName.isNotEmpty && 
          !RegExp(r'^[\d\s]+$').hasMatch(cleanName) &&
          !RegExp(r'^[a-z]{3,5}-?\d+$', caseSensitive: false).hasMatch(cleanName)) {
        // Capitalize first letter of each word
        return cleanName.split(' ').map((w) => 
          w.isNotEmpty ? '${w[0].toUpperCase()}${w.substring(1)}' : w
        ).join(' ');
      }
    }
    
    return 'Section $index';
  }

  static String _inferTitle(String html, {required String fallback}) {
    final document = html_parser.parse(html);

    final title = document.querySelector('title')?.text.trim();
    if (title != null && title.isNotEmpty) return title;

    final heading =
        document.querySelector('h1, h2, h3, h4, h5, h6')?.text.trim();
    if (heading != null && heading.isNotEmpty) return heading;

    return fallback;
  }
}

class _ManifestItem {
  final String id;
  final String href;
  final String? mediaType;

  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
  });
}
