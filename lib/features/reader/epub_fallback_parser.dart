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

      throw Exception('EPUB fallback parsing failed: ${e.toString()}');
    }

    final opfDoc = xml.XmlDocument.parse(_decodeText(opfFile));
    final manifest = _readManifest(opfDoc);
    final spineIdRefs = _readSpineIdRefs(opfDoc);
    final contentDir = _directoryOf(opfPath);

    final tocTitles = _readTocTitles(
      opfDoc: opfDoc,
      manifest: manifest,
      contentDir: contentDir,
      filesByLowerPath: filesByLowerPath,
    );

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
    final seenPaths = <String>{};
    final seenContents = <String>{};
    var index = 1;

    for (final item in orderedItems) {
      final resolvedPath = _resolveHref(contentDir, item.href);
      final lowerPath = resolvedPath.toLowerCase();

      // Deduplicate: avoid reading the same spine document twice
      if (seenPaths.contains(lowerPath)) continue;
      seenPaths.add(lowerPath);

      final file = _findFile(filesByLowerPath, resolvedPath);
      if (file == null) continue;

      final html = _decodeText(file);
      final trimmedHtml = html.trim();
      if (trimmedHtml.isEmpty) continue;

      // Deduplicate: avoid duplicate or identical chapter contents
      if (seenContents.contains(trimmedHtml)) continue;
      seenContents.add(trimmedHtml);

      final fallbackTitle = _fallbackTitle(item, index);
      final tocTitle = tocTitles[lowerPath];
      final title = (tocTitle != null && tocTitle.trim().isNotEmpty)
          ? tocTitle.trim()
          : _inferTitle(html, fallback: fallbackTitle);

      chapters.add(EpubChapter()
        ..Title = title
        ..ContentFileName = resolvedPath
        ..HtmlContent = html
        ..SubChapters = const <EpubChapter>[]);
      index++;
    }

    return chapters;
  }

  static Map<String, String> _readTocTitles({
    required xml.XmlDocument opfDoc,
    required Map<String, _ManifestItem> manifest,
    required String contentDir,
    required Map<String, ArchiveFile> filesByLowerPath,
  }) {
    final tocTitles = <String, String>{};

    // 1. Try NCX document (EPUB 2 / EPUB 3 backwards-compatibility)
    String? ncxHref;
    for (final spine in opfDoc.findAllElements('spine')) {
      final tocId = spine.getAttribute('toc');
      if (tocId != null && manifest.containsKey(tocId)) {
        ncxHref = manifest[tocId]?.href;
        break;
      }
    }

    if (ncxHref == null) {
      for (final item in manifest.values) {
        final media = item.mediaType?.toLowerCase().trim();
        final href = item.href.toLowerCase().trim();
        if (media == 'application/x-dtbncx+xml' ||
            href.endsWith('.ncx') ||
            item.id.toLowerCase() == 'ncx') {
          ncxHref = item.href;
          break;
        }
      }
    }

    if (ncxHref != null) {
      final resolvedNcxPath = _resolveHref(contentDir, ncxHref);
      final ncxFile = _findFile(filesByLowerPath, resolvedNcxPath);
      if (ncxFile != null) {
        try {
          final ncxDoc = xml.XmlDocument.parse(_decodeText(ncxFile));
          final ncxDir = _directoryOf(resolvedNcxPath);

          for (final navPoint in ncxDoc.findAllElements('navPoint')) {
            String? title;
            for (final navLabel in navPoint.findElements('navLabel')) {
              for (final textEl in navLabel.findElements('text')) {
                final t = textEl.innerText.trim();
                if (t.isNotEmpty) {
                  title = t;
                  break;
                }
              }
              if (title != null) break;
            }

            final contentEls = navPoint.findElements('content');
            final contentEl = contentEls.isNotEmpty ? contentEls.first : null;
            final src = contentEl?.getAttribute('src');

            if (title != null &&
                title.isNotEmpty &&
                src != null &&
                src.trim().isNotEmpty) {
              final resolvedSrc = _resolveHref(ncxDir, src).toLowerCase();
              tocTitles.putIfAbsent(resolvedSrc, () => title!);
            }
          }
        } catch (_) {}
      }
    }

    // 2. Try EPUB 3 Navigation Document (nav.xhtml / properties="nav")
    String? navHref;
    for (final item in manifest.values) {
      final props = item.properties?.toLowerCase().trim() ?? '';
      if (props.contains('nav') ||
          item.id.toLowerCase() == 'nav' ||
          item.href.toLowerCase().endsWith('nav.xhtml') ||
          item.href.toLowerCase().endsWith('toc.xhtml')) {
        navHref = item.href;
        break;
      }
    }

    if (navHref != null) {
      final resolvedNavPath = _resolveHref(contentDir, navHref);
      final navFile = _findFile(filesByLowerPath, resolvedNavPath);
      if (navFile != null) {
        try {
          final navHtml = _decodeText(navFile);
          final navDoc = html_parser.parse(navHtml);
          final navDir = _directoryOf(resolvedNavPath);

          var tocNav = navDoc.querySelector('nav[type="toc"], nav#toc');
          if (tocNav == null) {
            for (final nav in navDoc.querySelectorAll('nav')) {
              final epubType = nav.attributes['epub:type']?.toLowerCase().trim();
              final type = nav.attributes['type']?.toLowerCase().trim();
              final id = nav.id.toLowerCase().trim();
              final className = nav.className.toLowerCase().trim();
              if (epubType == 'toc' ||
                  type == 'toc' ||
                  id == 'toc' ||
                  className.contains('toc')) {
                tocNav = nav;
                break;
              }
            }
          }
          tocNav ??= navDoc.querySelector('nav');

          final container = tocNav ?? navDoc.body ?? navDoc.documentElement;
          if (container != null) {
            for (final a in container.querySelectorAll('a')) {
              final href = a.attributes['href'];
              final title = a.text.trim();
              if (href != null && href.trim().isNotEmpty && title.isNotEmpty) {
                final resolved = _resolveHref(navDir, href).toLowerCase();
                tocTitles.putIfAbsent(resolved, () => title);
              }
            }
          }
        } catch (_) {}
      }
    }

    return tocTitles;
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
      final properties = item.getAttribute('properties');

      items[id] = _ManifestItem(
        id: id,
        href: href,
        mediaType: mediaType,
        properties: properties,
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

    final href = Uri.decodeFull(item.href);
    final parts = href.split('/');
    final fileName = parts.isEmpty ? '' : parts.last;
    
    if (fileName.isNotEmpty) {
      
      var cleanName = fileName.replaceAll(RegExp(r'\.(x?html?|htm)$', caseSensitive: false), '');
      
      cleanName = cleanName.replaceAll(RegExp(r'[-_]'), ' ').trim();
      
      if (cleanName.isNotEmpty && 
          !RegExp(r'^[\d\s]+$').hasMatch(cleanName) &&
          !RegExp(r'^[a-z]{3,5}-?\d+$', caseSensitive: false).hasMatch(cleanName)) {
        
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
  final String? properties;

  const _ManifestItem({
    required this.id,
    required this.href,
    required this.mediaType,
    this.properties,
  });
}
