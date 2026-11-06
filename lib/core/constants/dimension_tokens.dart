import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:reader_app/core/models/app_dimension.dart';

/// Semantic iconography pack resolver corresponding to each App Dimension.
class DimensionIcons {
  DimensionIcons._();

  static IconData navLibrary(DimensionIconStyle style, bool active) {
    switch (style) {
      case DimensionIconStyle.cupertinoLinear:
        return active ? CupertinoIcons.book_fill : CupertinoIcons.book;
      case DimensionIconStyle.terminalAscii:
        return Icons.terminal_rounded;
      case DimensionIconStyle.classicalSerif:
        return active ? Icons.menu_book : Icons.menu_book_outlined;
      case DimensionIconStyle.hairlineMinimal:
        return Icons.view_headline_rounded;
      case DimensionIconStyle.modernRounded:
        return active ? Icons.auto_stories : Icons.book_outlined;
    }
  }

  static IconData navAnnotations(DimensionIconStyle style, bool active) {
    switch (style) {
      case DimensionIconStyle.cupertinoLinear:
        return active ? CupertinoIcons.chat_bubble_fill : CupertinoIcons.chat_bubble;
      case DimensionIconStyle.terminalAscii:
        return Icons.data_object_rounded;
      case DimensionIconStyle.classicalSerif:
        return active ? Icons.rate_review : Icons.rate_review_outlined;
      case DimensionIconStyle.hairlineMinimal:
        return Icons.notes_rounded;
      case DimensionIconStyle.modernRounded:
        return active ? Icons.comment : Icons.mode_comment_outlined;
    }
  }

  static IconData navSettings(DimensionIconStyle style, bool active) {
    switch (style) {
      case DimensionIconStyle.cupertinoLinear:
        return active ? CupertinoIcons.gear_alt_fill : CupertinoIcons.gear_alt;
      case DimensionIconStyle.terminalAscii:
        return Icons.memory_rounded;
      case DimensionIconStyle.classicalSerif:
        return active ? Icons.tune : Icons.tune_outlined;
      case DimensionIconStyle.hairlineMinimal:
        return Icons.more_horiz_rounded;
      case DimensionIconStyle.modernRounded:
        return active ? Icons.settings : Icons.settings_outlined;
    }
  }

  static IconData search(DimensionIconStyle style) {
    switch (style) {
      case DimensionIconStyle.cupertinoLinear:
        return CupertinoIcons.search;
      case DimensionIconStyle.terminalAscii:
        return Icons.manage_search_rounded;
      case DimensionIconStyle.classicalSerif:
        return Icons.find_in_page_outlined;
      case DimensionIconStyle.hairlineMinimal:
      case DimensionIconStyle.modernRounded:
        return CupertinoIcons.search;
    }
  }

  static IconData filter(DimensionIconStyle style) {
    switch (style) {
      case DimensionIconStyle.cupertinoLinear:
        return CupertinoIcons.slider_horizontal_3;
      case DimensionIconStyle.terminalAscii:
        return Icons.filter_list_alt;
      case DimensionIconStyle.classicalSerif:
        return Icons.filter_alt_outlined;
      case DimensionIconStyle.hairlineMinimal:
      case DimensionIconStyle.modernRounded:
        return Icons.filter_alt_rounded;
    }
  }

  static IconData sort(DimensionIconStyle style) {
    switch (style) {
      case DimensionIconStyle.cupertinoLinear:
        return CupertinoIcons.arrow_up_arrow_down;
      case DimensionIconStyle.terminalAscii:
        return Icons.unfold_more_rounded;
      case DimensionIconStyle.classicalSerif:
        return Icons.sort_by_alpha_rounded;
      case DimensionIconStyle.hairlineMinimal:
      case DimensionIconStyle.modernRounded:
        return Icons.sort_rounded;
    }
  }

  static IconData addFolder(DimensionIconStyle style) {
    switch (style) {
      case DimensionIconStyle.cupertinoLinear:
        return CupertinoIcons.folder_badge_plus;
      case DimensionIconStyle.terminalAscii:
        return Icons.add_to_queue_rounded;
      case DimensionIconStyle.classicalSerif:
        return Icons.create_new_folder_outlined;
      case DimensionIconStyle.hairlineMinimal:
      case DimensionIconStyle.modernRounded:
        return Icons.create_new_folder_outlined;
    }
  }

  static IconData refresh(DimensionIconStyle style) {
    switch (style) {
      case DimensionIconStyle.cupertinoLinear:
        return CupertinoIcons.arrow_clockwise;
      case DimensionIconStyle.terminalAscii:
        return Icons.sync_alt_rounded;
      case DimensionIconStyle.classicalSerif:
        return Icons.cached_rounded;
      case DimensionIconStyle.hairlineMinimal:
      case DimensionIconStyle.modernRounded:
        return Icons.refresh_rounded;
    }
  }
}

/// Helper for resolving shape and styling based on active DimensionConfig.
class DimensionDecorations {
  DimensionDecorations._();

  static ShapeBorder cardShape(DimensionConfig config, {BorderSide side = BorderSide.none}) {
    if (config.cardRadius <= 0) {
      return RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: side);
    }
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(config.cardRadius),
      side: side,
    );
  }

  static BorderRadius borderRadius(DimensionConfig config) {
    if (config.cardRadius <= 0) {
      return BorderRadius.zero;
    }
    return BorderRadius.circular(config.cardRadius);
  }
}
