import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Manages per-page and continuous [SelectionArea] state keys, selection tracking,
/// dismissal predicates, and chapter pruning across Ferrous readers.
class ReaderSelectionController {
  final Map<String, GlobalKey<SelectionAreaState>> _keys = {};
  String? _activeKeyId;
  SelectedContent? selectedContent;

  /// Retrieves or creates a memoized [GlobalKey<SelectionAreaState>] for a specific page slice.
  GlobalKey<SelectionAreaState> keyForPage(int chapterIndex, int sliceIdx) {
    final id = '$chapterIndex-$sliceIdx';
    return _keys.putIfAbsent(
      id,
      () => GlobalKey<SelectionAreaState>(debugLabel: 'selection-$id'),
    );
  }

  /// Retrieves or creates a memoized [GlobalKey<SelectionAreaState>] for continuous chapter viewports.
  GlobalKey<SelectionAreaState> keyForContinuous(int chapterIndex) {
    final id = 'continuous-$chapterIndex';
    return _keys.putIfAbsent(
      id,
      () => GlobalKey<SelectionAreaState>(debugLabel: 'selection-$id'),
    );
  }

  /// Whether non-empty text content is currently selected.
  bool get hasSelection =>
      selectedContent != null && selectedContent!.plainText.trim().isNotEmpty;

  /// Updates the active selection, guarding against preloaded inactive pages emitting null.
  void updateSelection(String keyId, SelectedContent? content) {
    final hasText = content != null && content.plainText.trim().isNotEmpty;
    if (hasText) {
      _activeKeyId = keyId;
      selectedContent = content;
    } else if (_activeKeyId == keyId) {
      _activeKeyId = null;
      selectedContent = null;
    }
  }

  /// Programmatically clears the text selection and hides the selection toolbar
  /// across all mounted selection areas.
  void clearSelection() {
    for (final key in _keys.values) {
      final state = key.currentState;
      if (state != null && state.mounted) {
        state.selectableRegion.clearSelection();
        state.selectableRegion.hideToolbar();
      }
    }
    selectedContent = null;
    _activeKeyId = null;
  }

  /// Attempts to dismiss an active selection. Returns `true` if a selection was active
  /// and was dismissed (consuming the tap); returns `false` otherwise.
  bool tryDismissSelection() {
    if (hasSelection) {
      clearSelection();
      return true;
    }
    selectedContent = null;
    _activeKeyId = null;
    return false;
  }

  /// Prunes cached keys outside the active and adjacent sentinel chapters,
  /// preserving mounted keys and continuous mode keys.
  void pruneChapter(int activeChapter) {
    _keys.removeWhere((id, key) {
      // 1. Never evict a GlobalKey that is currently mounted in the active tree or cache
      if (key.currentState != null && key.currentState!.mounted) {
        return false;
      }
      // 2. Retain active continuous key
      if (id == 'continuous-$activeChapter') return false;
      // 3. Retain the adjacent chapter sentinel window (-1, current, +1)
      for (int ch = activeChapter - 1; ch <= activeChapter + 1; ch++) {
        if (id.startsWith('$ch-')) return false;
      }
      return true;
    });
  }

  /// Disposes controller resources and cleans up references.
  void dispose() {
    _keys.clear();
    selectedContent = null;
    _activeKeyId = null;
  }
}
