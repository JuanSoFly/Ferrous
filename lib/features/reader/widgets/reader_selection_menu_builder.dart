import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:ferrous/features/reader/hyphenation_helper.dart';

/// Reusable helper that constructs the adaptive text selection toolbar
/// with standardized 'Annotate' and sanitized 'Copy' actions.
class ReaderSelectionMenuBuilder {
  static Widget build({
    required BuildContext context,
    required SelectableRegionState selectableRegionState,
    required SelectedContent? selectedContent,
    required void Function(String cleanText) onAnnotate,
    required VoidCallback onSelectionCleared,
  }) {
    final buttonItems = selectableRegionState.contextMenuButtonItems.map((item) {
      if (item.type == ContextMenuButtonType.copy) {
        return ContextMenuButtonItem(
          type: ContextMenuButtonType.copy,
          onPressed: () {
            final raw = selectedContent?.plainText ?? '';
            final clean = HyphenationHelper.sanitizeForCopy(raw);
            Clipboard.setData(ClipboardData(text: clean));
            selectableRegionState.clearSelection();
            selectableRegionState.hideToolbar();
            onSelectionCleared();
          },
        );
      }
      return item;
    }).toList();

    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: [
        ContextMenuButtonItem(
          label: 'Annotate',
          onPressed: () {
            final raw = selectedContent?.plainText ?? '';
            final clean = HyphenationHelper.sanitizeForAnnotation(raw);
            selectableRegionState.clearSelection();
            selectableRegionState.hideToolbar();
            onSelectionCleared();
            if (clean.isNotEmpty) {
              onAnnotate(clean);
            }
          },
        ),
        ...buttonItems,
      ],
    );
  }
}
