import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
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

  static List<EpubChapter> parseChapters(
    List<int> bytes, {
    String? cacheDirectory,
  }) {
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

      final processedHtml = _resolveChapterImages(
        html: html,
        chapterPath: resolvedPath,
        contentDir: contentDir,
        manifest: manifest,
        filesByLowerPath: filesByLowerPath,
        cacheDirectory: cacheDirectory,
      );

      final hasImage = _hasImageElement(processedHtml);

      // Deduplicate: avoid duplicate identical chapter contents, but never drop image-bearing chapters
      if (!hasImage && seenContents.contains(processedHtml)) continue;
      seenContents.add(processedHtml);

      final fallbackTitle = _fallbackTitle(item, index);
      final tocTitle = tocTitles[lowerPath];
      final title = (tocTitle != null && tocTitle.trim().isNotEmpty)
          ? tocTitle.trim()
          : _inferTitle(processedHtml, fallback: fallbackTitle);

      chapters.add(EpubChapter()
        ..Title = title
        ..ContentFileName = resolvedPath
        ..HtmlContent = processedHtml
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

  static bool _hasImageElement(String html) {
    final lower = html.toLowerCase();
    return lower.contains('<img') ||
        lower.contains('<image') ||
        lower.contains('<svg') ||
        lower.contains('<object');
  }

  static String _resolveChapterImages({
    required String html,
    required String chapterPath,
    required String contentDir,
    required Map<String, _ManifestItem> manifest,
    required Map<String, ArchiveFile> filesByLowerPath,
    String? cacheDirectory,
  }) {
    if (html.isEmpty) return html;

    try {
      final doc = html_parser.parse(html);
      final chapterDir = _directoryOf(chapterPath);
      bool modified = false;

      // 1. Process img elements
      for (final img in doc.querySelectorAll('img')) {
        final src = img.attributes['src'];
        if (src == null || src.trim().isEmpty) continue;
        final resolvedUri = _resolveAndStoreImageUri(
          rawUri: src,
          chapterDir: chapterDir,
          contentDir: contentDir,
          manifest: manifest,
          filesByLowerPath: filesByLowerPath,
          cacheDirectory: cacheDirectory,
        );
        if (resolvedUri != null) {
          img.attributes['src'] = resolvedUri;
          modified = true;
        }
      }

      // 2. Process image elements (inside or outside svg)
      for (final image in doc.querySelectorAll('image')) {
        String? rawUri;
        Object? hrefKey;
        for (final entry in image.attributes.entries) {
          final k = entry.key.toString().toLowerCase();
          if (k.contains('href') || k == 'src') {
            final val = entry.value.trim();
            if (val.isNotEmpty) {
              rawUri = val;
              hrefKey = entry.key;
              break;
            }
          }
        }
        if (rawUri == null || rawUri.isEmpty) continue;

        final resolvedUri = _resolveAndStoreImageUri(
          rawUri: rawUri,
          chapterDir: chapterDir,
          contentDir: contentDir,
          manifest: manifest,
          filesByLowerPath: filesByLowerPath,
          cacheDirectory: cacheDirectory,
        );
        if (resolvedUri != null) {
          if (hrefKey != null) {
            image.attributes[hrefKey] = resolvedUri;
          }
          image.attributes['href'] = resolvedUri;
          image.attributes['xlink:href'] = resolvedUri;
          image.attributes['src'] = resolvedUri;
          modified = true;
        }
      }

      // 3. Process object elements with image data
      for (final obj in doc.querySelectorAll('object')) {
        final data = obj.attributes['data'];
        final type = obj.attributes['type']?.toLowerCase() ?? '';
        if (data == null || data.trim().isEmpty) continue;
        if (type.startsWith('image/') || _isImagePath(data)) {
          final resolvedUri = _resolveAndStoreImageUri(
            rawUri: data,
            chapterDir: chapterDir,
            contentDir: contentDir,
            manifest: manifest,
            filesByLowerPath: filesByLowerPath,
            cacheDirectory: cacheDirectory,
          );
          if (resolvedUri != null) {
            obj.attributes['data'] = resolvedUri;
            modified = true;
          }
        }
      }

      // 4. For any svg elements that wrap an image, also store data-src
      for (final svg in doc.querySelectorAll('svg')) {
        final imageEl = svg.querySelector('image, img');
        if (imageEl != null) {
          final src = imageEl.attributes['src'] ??
              imageEl.attributes['href'] ??
              imageEl.attributes['xlink:href'];
          if (src != null && src.isNotEmpty) {
            svg.attributes['data-src'] = src;
            modified = true;
          }
        }
      }

      if (modified) {
        return doc.body?.innerHtml ?? doc.documentElement?.innerHtml ?? html;
      }
    } catch (e) {
      debugPrint('Error resolving chapter images: $e');
    }

    return html;
  }

  static String? _resolveAndStoreImageUri({
    required String rawUri,
    required String chapterDir,
    required String contentDir,
    required Map<String, _ManifestItem> manifest,
    required Map<String, ArchiveFile> filesByLowerPath,
    String? cacheDirectory,
  }) {
    final trimmed = rawUri.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('data:') ||
        trimmed.startsWith('file://') ||
        trimmed.startsWith('http://') ||
        trimmed.startsWith('https://')) {
      return trimmed;
    }

    var clean = trimmed.split('#').first.split('?').first.trim();
    try {
      clean = Uri.decodeFull(clean);
    } catch (_) {}
    if (clean.isEmpty) return null;

    // 1. Try resolving relative to chapterDir
    String candidatePath = _resolveHref(chapterDir, clean);
    ArchiveFile? file = _findFile(filesByLowerPath, candidatePath);

    // 2. Try resolving relative to contentDir (OPF directory)
    if (file == null) {
      candidatePath = _resolveHref(contentDir, clean);
      file = _findFile(filesByLowerPath, candidatePath);
    }

    // 3. Try matching against manifest items
    if (file == null) {
      for (final item in manifest.values) {
        final itemHref = Uri.decodeFull(item.href.split('#').first.split('?').first);
        if (itemHref.toLowerCase() == clean.toLowerCase() ||
            itemHref.toLowerCase().endsWith('/${clean.toLowerCase()}') ||
            clean.toLowerCase().endsWith('/${itemHref.toLowerCase()}')) {
          candidatePath = _resolveHref(contentDir, item.href);
          file = _findFile(filesByLowerPath, candidatePath);
          if (file != null) break;
        }
      }
    }

    // 4. Try matching by filename in archive files
    if (file == null) {
      final fileName = clean.split('/').last.toLowerCase();
      for (final entry in filesByLowerPath.entries) {
        if (entry.key.endsWith('/$fileName') || entry.key == fileName) {
          candidatePath = entry.key;
          file = entry.value;
          break;
        }
      }
    }

    if (file == null) return null;

    final bytes = _archiveFileBytes(file);
    if (bytes.isEmpty) return null;

    // Determine MIME type
    String mimeType = 'image/jpeg';
    final lower = candidatePath.toLowerCase();
    if (lower.endsWith('.png')) {
      mimeType = 'image/png';
    } else if (lower.endsWith('.webp')) {
      mimeType = 'image/webp';
    } else if (lower.endsWith('.gif')) {
      mimeType = 'image/gif';
    } else if (lower.endsWith('.svg')) {
      mimeType = 'image/svg+xml';
    } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      mimeType = 'image/jpeg';
    }

    // Cache to disk if cacheDirectory is provided
    if (cacheDirectory != null && cacheDirectory.isNotEmpty) {
      try {
        final safeName = _normalizePath(candidatePath).replaceAll('/', '_');
        final outDir = Directory(cacheDirectory);
        if (!outDir.existsSync()) {
          outDir.createSync(recursive: true);
        }
        final outFile = File('${outDir.path}/$safeName');
        if (!outFile.existsSync() || outFile.lengthSync() != bytes.length) {
          outFile.writeAsBytesSync(bytes);
        }
        return outFile.uri.toString();
      } catch (e) {
        debugPrint('Failed to cache image to disk ($e), falling back to base64');
      }
    }

    // Fallback: Base64 data URI
    final b64 = base64Encode(bytes);
    return 'data:$mimeType;base64,$b64';
  }

  static bool _isImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.svg');
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
