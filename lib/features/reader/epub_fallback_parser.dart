import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:xml/xml.dart' as xml;

class EpubTocAnchor {
  final String title;
  final String targetPath;
  final String? anchorId;
  final int playOrder;

  const EpubTocAnchor({
    required this.title,
    required this.targetPath,
    this.anchorId,
    required this.playOrder,
  });
}

class EpubFallbackResult {
  final List<EpubChapter> chapters;
  final Map<String, int> anchorToChapterIndex;
  final List<String> chapterSourceFiles;

  const EpubFallbackResult({
    required this.chapters,
    required this.anchorToChapterIndex,
    required this.chapterSourceFiles,
  });
}

class _HtmlSkeleton {
  final String headPart;
  final String bodyOpenTag;
  final String bodyCloseTag;
  final int bodyContentStart;
  final int bodyContentEnd;

  _HtmlSkeleton({
    required this.headPart,
    required this.bodyOpenTag,
    required this.bodyCloseTag,
    required this.bodyContentStart,
    required this.bodyContentEnd,
  });
}

class _LocatedAnchor {
  final EpubTocAnchor tocAnchor;
  final int attributeMatchIndex;
  final int splitOffset;

  _LocatedAnchor({
    required this.tocAnchor,
    required this.attributeMatchIndex,
    required this.splitOffset,
  });
}

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
    return parseBookResult(bytes, cacheDirectory: cacheDirectory).chapters;
  }

  static EpubFallbackResult parseBookResult(
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

    final tocAnchors = _readTocAnchors(
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
    final anchorToChapterIndex = <String, int>{};
    final chapterSourceFiles = <String>[];
    final seenPaths = <String>{};
    var spineIndex = 1;

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

      final skeleton = _extractSkeleton(processedHtml);

      // Find all TOC anchors pointing into this file
      final fileTocAnchors = tocAnchors.where((a) => a.targetPath == lowerPath).toList();

      // Find positions of anchors in the HTML
      final locatedAnchors = <_LocatedAnchor>[];
      for (final tocAnchor in fileTocAnchors) {
        if (tocAnchor.anchorId != null && tocAnchor.anchorId!.isNotEmpty) {
          final matchIdx = _findIdMatchIndex(processedHtml, tocAnchor.anchorId!);
          if (matchIdx != -1) {
            final splitOffset = _findSafeBlockSplitOffset(processedHtml, matchIdx);
            if (splitOffset > skeleton.bodyContentStart && splitOffset < skeleton.bodyContentEnd) {
              locatedAnchors.add(_LocatedAnchor(
                tocAnchor: tocAnchor,
                attributeMatchIndex: matchIdx,
                splitOffset: splitOffset,
              ));
            }
          }
        }
      }

      // Sort by splitOffset ascending
      locatedAnchors.sort((a, b) => a.splitOffset.compareTo(b.splitOffset));

      // Deduplicate split offsets that are identical or within 30 characters
      final dedupedAnchors = <_LocatedAnchor>[];
      for (final located in locatedAnchors) {
        if (dedupedAnchors.isEmpty) {
          dedupedAnchors.add(located);
        } else {
          final prev = dedupedAnchors.last;
          if ((located.splitOffset - prev.splitOffset).abs() < 30) {
            // Keep the one with the more specific or latter title
            dedupedAnchors.removeLast();
            dedupedAnchors.add(located);
          } else {
            dedupedAnchors.add(located);
          }
        }
      }

      if (dedupedAnchors.isNotEmpty) {
        // We have multiple sub-chapters in this spine file!
        final splitOffsets = dedupedAnchors.map((a) => a.splitOffset).toList();

        // 1. Check content before the first anchor
        final preAnchorRaw = processedHtml.substring(skeleton.bodyContentStart, splitOffsets.first);
        if (_hasSignificantContent(preAnchorRaw)) {
          if (chapters.isNotEmpty) {
            // Guardrail 2: Mid-Chapter Calibre Split!
            // Append leading pre-anchor content onto the preceding chapter.
            final prevIndex = chapters.length - 1;
            final normalizedPre = _normalizeRelativeHrefs(preAnchorRaw, resolvedPath);
            _scanAndRegisterIds(normalizedPre, resolvedPath, prevIndex, anchorToChapterIndex);

            final prevChapter = chapters[prevIndex];
            final prevHtml = prevChapter.HtmlContent ?? '';
            final bodyCloseIdx = prevHtml.toLowerCase().lastIndexOf('</body>');
            if (bodyCloseIdx != -1) {
              prevChapter.HtmlContent =
                  '${prevHtml.substring(0, bodyCloseIdx)}\n$normalizedPre\n${prevHtml.substring(bodyCloseIdx)}';
            } else {
              prevChapter.HtmlContent = '$prevHtml\n$normalizedPre';
            }
          } else {
            // First file in book with leading pre-anchor content: create front matter chapter
            final normalizedPre = _normalizeRelativeHrefs(preAnchorRaw, resolvedPath);
            final frontHtml = _wrapHtmlContent(skeleton, normalizedPre);
            final chapterIndex = chapters.length;
            _scanAndRegisterIds(normalizedPre, resolvedPath, chapterIndex, anchorToChapterIndex);

            final fallbackTitle = _fallbackTitle(item, spineIndex);
            final title = _inferTitle(frontHtml, fallback: fallbackTitle);

            chapters.add(EpubChapter()
              ..Title = title
              ..ContentFileName = resolvedPath
              ..Anchor = null
              ..HtmlContent = frontHtml
              ..SubChapters = const <EpubChapter>[]);
            chapterSourceFiles.add(resolvedPath);
          }
        }

        // 2. Process each anchor chunk
        for (var i = 0; i < dedupedAnchors.length; i++) {
          final anchor = dedupedAnchors[i];
          final startOffset = anchor.splitOffset;
          final endOffset = (i + 1 < dedupedAnchors.length)
              ? dedupedAnchors[i + 1].splitOffset
              : skeleton.bodyContentEnd;

          if (startOffset >= endOffset) continue;
          final sliceRaw = processedHtml.substring(startOffset, endOffset);
          if (!_hasSignificantContent(sliceRaw)) continue;

          final normalizedSlice = _normalizeRelativeHrefs(sliceRaw, resolvedPath);
          final fullChapterHtml = _wrapHtmlContent(skeleton, normalizedSlice);
          final chapterIndex = chapters.length;

          // Scan and register all IDs in this slice
          _scanAndRegisterIds(normalizedSlice, resolvedPath, chapterIndex, anchorToChapterIndex);

          // Register the TOC anchor itself explicitly
          if (anchor.tocAnchor.anchorId != null) {
            final aId = anchor.tocAnchor.anchorId!;
            final baseName = lowerPath.split('/').last;
            anchorToChapterIndex['$lowerPath#$aId'] = chapterIndex;
            anchorToChapterIndex['$baseName#$aId'] = chapterIndex;
            anchorToChapterIndex.putIfAbsent('#$aId', () => chapterIndex);
            anchorToChapterIndex.putIfAbsent(aId, () => chapterIndex);
          }

          final rawTitle = anchor.tocAnchor.title.trim();
          final title = rawTitle.isNotEmpty
              ? rawTitle
              : _inferTitle(fullChapterHtml, fallback: 'Chapter ${chapters.length + 1}');

          chapters.add(EpubChapter()
            ..Title = title
            ..ContentFileName = '$resolvedPath#${anchor.tocAnchor.anchorId ?? ''}'
            ..Anchor = anchor.tocAnchor.anchorId
            ..HtmlContent = fullChapterHtml
            ..SubChapters = const <EpubChapter>[]);
          chapterSourceFiles.add(resolvedPath);
        }
      } else {
        // Standalone spine item (1 file = 1 chapter, or no sub-anchors)
        final bodyRaw = processedHtml.substring(skeleton.bodyContentStart, skeleton.bodyContentEnd);
        if (_hasSignificantContent(bodyRaw)) {
          final normalizedBody = _normalizeRelativeHrefs(bodyRaw, resolvedPath);
          final fullChapterHtml = _wrapHtmlContent(skeleton, normalizedBody);
          final chapterIndex = chapters.length;

          _scanAndRegisterIds(normalizedBody, resolvedPath, chapterIndex, anchorToChapterIndex);

          final fallbackTitle = _fallbackTitle(item, spineIndex);
          final tocTitle = fileTocAnchors.isNotEmpty ? fileTocAnchors.first.title.trim() : null;
          final title = (tocTitle != null && tocTitle.isNotEmpty)
              ? tocTitle
              : _inferTitle(fullChapterHtml, fallback: fallbackTitle);

          chapters.add(EpubChapter()
            ..Title = title
            ..ContentFileName = resolvedPath
            ..Anchor = null
            ..HtmlContent = fullChapterHtml
            ..SubChapters = const <EpubChapter>[]);
          chapterSourceFiles.add(resolvedPath);
        }
      }

      spineIndex++;
    }

    return EpubFallbackResult(
      chapters: chapters,
      anchorToChapterIndex: anchorToChapterIndex,
      chapterSourceFiles: chapterSourceFiles,
    );
  }

  static List<EpubTocAnchor> _readTocAnchors({
    required xml.XmlDocument opfDoc,
    required Map<String, _ManifestItem> manifest,
    required String contentDir,
    required Map<String, ArchiveFile> filesByLowerPath,
  }) {
    final anchors = <EpubTocAnchor>[];

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
          int autoOrder = 0;

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
            final playOrderAttr = int.tryParse(navPoint.getAttribute('playOrder') ?? '');
            final playOrder = playOrderAttr ?? autoOrder++;

            if (title != null &&
                title.isNotEmpty &&
                src != null &&
                src.trim().isNotEmpty) {
              final parts = _resolveHrefParts(ncxDir, src);
              anchors.add(EpubTocAnchor(
                title: title,
                targetPath: parts.targetPath,
                anchorId: parts.anchorId,
                playOrder: playOrder,
              ));
            }
          }
        } catch (_) {}
      }
    }

    // 2. Try EPUB 3 Navigation Document (nav.xhtml / properties="nav")
    if (anchors.isEmpty) {
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
              int autoOrder = 0;
              for (final a in container.querySelectorAll('a')) {
                final href = a.attributes['href'];
                final title = a.text.trim();
                if (href != null && href.trim().isNotEmpty && title.isNotEmpty) {
                  final parts = _resolveHrefParts(navDir, href);
                  anchors.add(EpubTocAnchor(
                    title: title,
                    targetPath: parts.targetPath,
                    anchorId: parts.anchorId,
                    playOrder: autoOrder++,
                  ));
                }
              }
            }
          } catch (_) {}
        }
      }
    }

    return anchors;
  }

  static ({String targetPath, String? anchorId}) _resolveHrefParts(String baseDir, String href) {
    final trimmed = href.trim();
    final hashIndex = trimmed.indexOf('#');
    final pathPart = hashIndex != -1 ? trimmed.substring(0, hashIndex) : trimmed;
    final anchorPart = hashIndex != -1 ? trimmed.substring(hashIndex + 1).trim() : null;
    final resolvedPath = _resolveHref(baseDir, pathPart).toLowerCase();
    return (
      targetPath: resolvedPath,
      anchorId: (anchorPart != null && anchorPart.isNotEmpty) ? anchorPart : null,
    );
  }

  static _HtmlSkeleton _extractSkeleton(String html) {
    final bodyStartMatch = RegExp(r'<body(?:\s+[^>]*)?>', caseSensitive: false).firstMatch(html);
    if (bodyStartMatch == null) {
      return _HtmlSkeleton(
        headPart: '<!DOCTYPE html><html><head><meta charset="utf-8"></head>',
        bodyOpenTag: '<body>',
        bodyCloseTag: '</body></html>',
        bodyContentStart: 0,
        bodyContentEnd: html.length,
      );
    }

    final headPart = html.substring(0, bodyStartMatch.start);
    final bodyOpenTag = bodyStartMatch.group(0)!;
    final bodyContentStart = bodyStartMatch.end;

    final bodyEndMatch = RegExp(r'</body>', caseSensitive: false).firstMatch(html);
    final bodyContentEnd = bodyEndMatch != null ? bodyEndMatch.start : html.length;
    final bodyCloseTag = bodyEndMatch != null ? html.substring(bodyEndMatch.start) : '</body></html>';

    return _HtmlSkeleton(
      headPart: headPart.isNotEmpty ? headPart : '<!DOCTYPE html><html><head><meta charset="utf-8"></head>',
      bodyOpenTag: bodyOpenTag,
      bodyCloseTag: bodyCloseTag.isNotEmpty ? bodyCloseTag : '</body></html>',
      bodyContentStart: bodyContentStart,
      bodyContentEnd: bodyContentEnd,
    );
  }

  static String _wrapHtmlContent(_HtmlSkeleton skeleton, String innerContent) {
    return '${skeleton.headPart}\n${skeleton.bodyOpenTag}\n$innerContent\n${skeleton.bodyCloseTag}';
  }

  static int _findIdMatchIndex(String html, String id) {
    final escapedId = RegExp.escape(id);
    final pattern = RegExp('(?:id|name)=[\'"]$escapedId[\'"]', caseSensitive: false);
    final match = pattern.firstMatch(html);
    return match != null ? match.start : -1;
  }

  static int _findSafeBlockSplitOffset(String html, int attributeMatchIndex) {
    int tagStart = html.lastIndexOf('<', attributeMatchIndex);
    if (tagStart == -1) return attributeMatchIndex;

    final tagMatch = RegExp(r'^<([a-zA-Z0-9]+)').firstMatch(html.substring(tagStart));
    if (tagMatch == null) return tagStart;
    final tagName = tagMatch.group(1)!.toLowerCase();

    const blockTags = {
      'p', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6',
      'blockquote', 'li', 'table', 'section', 'article', 'aside', 'header', 'hr'
    };
    if (blockTags.contains(tagName)) {
      return tagStart;
    }

    // Safe Tag Snapping (Guardrail 1):
    // In Calibre EPUBs, if an anchor ID is on an inline tag, only snap backward
    // to the immediate enclosing <p> or <h1>-<h6> within a small window (~250 chars).
    // NEVER snap backward to an outer <div> or <section> wrapper!
    final searchWindowStart = (tagStart - 250).clamp(0, tagStart);
    final window = html.substring(searchWindowStart, tagStart);

    final blockMatches = RegExp(r'<(p|h[1-6])(?:\s+[^>]*)?>', caseSensitive: false).allMatches(window);
    if (blockMatches.isNotEmpty) {
      final lastMatch = blockMatches.last;
      return searchWindowStart + lastMatch.start;
    }

    return tagStart;
  }

  static bool _hasSignificantContent(String html) {
    final trimmed = html.trim();
    if (trimmed.isEmpty) return false;
    if (_hasImageElement(trimmed)) return true;
    final stripped = trimmed.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return stripped.isNotEmpty;
  }

  static String _normalizeRelativeHrefs(String html, String sourceFile) {
    final baseName = sourceFile.split('/').last;
    return html.replaceAllMapped(
      RegExp(r'''href=(['"])#([^'"]+)['"]''', caseSensitive: false),
      (match) {
        final quote = match.group(1)!;
        final anchor = match.group(2)!;
        return 'href=$quote$baseName#$anchor$quote';
      },
    );
  }

  static void _scanAndRegisterIds(
    String html,
    String sourceFile,
    int chapterIndex,
    Map<String, int> registry,
  ) {
    final lowerSource = sourceFile.toLowerCase();
    final baseName = lowerSource.split('/').last;

    registry.putIfAbsent(lowerSource, () => chapterIndex);
    registry.putIfAbsent(baseName, () => chapterIndex);

    final idMatches = RegExp(r'''(?:id|name)=['"]([^'"]+)['"]''', caseSensitive: false).allMatches(html);
    for (final m in idMatches) {
      final id = m.group(1)?.trim();
      if (id != null && id.isNotEmpty) {
        registry['$lowerSource#$id'] = chapterIndex;
        registry['$baseName#$id'] = chapterIndex;
        registry.putIfAbsent('#$id', () => chapterIndex);
        registry.putIfAbsent(id, () => chapterIndex);
      }
    }
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
        return doc.outerHtml;
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
