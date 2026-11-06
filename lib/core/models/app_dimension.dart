import 'package:reader_app/features/settings/app_themes.dart';

/// The 5 core spatial & aesthetic dimensions of Ferrous.
enum AppDimension {
  /// Standard modern experience with frosted bottom navigation and masonry cards.
  modernist,

  /// Floating translucent capsule dock, organic squircles, and magazine bento layout.
  floatingIsland,

  /// Top command HUD, monospace telemetry, ASCII meters, and sharp industrial geometry.
  cyberTerminal,

  /// Book-bound catalog cards, classical ribbon navigation, and scholarly typography.
  athenaeum,

  /// Flat zero-shadow high-density list and micro dock for distraction-free reading.
  compactSlate,
}

/// Navigation bar placement and visual archetype.
enum DimensionNavStyle {
  /// Classic bottom glassmorphic bar docked to bottom edge.
  bottomStandard,

  /// Floating capsule dock detached from screen edges.
  floatingIslandDock,

  /// Top status command HUD bar leaving the bottom completely open.
  topTerminalHud,

  /// Classical bookmark ribbon navigation with Roman numeral markers.
  compactRibbon,
}

/// Library content presentation archetype.
enum DimensionCardStyle {
  /// 2-column staggered masonry grid with soft rounded cards.
  masonryGrid,

  /// Hero "Now Reading" featured banner + spacious visual bento cards.
  bentoShowcase,

  /// High-contrast monospace telemetry data rows with ASCII meters and hex chips.
  terminalTelemetry,

  /// Card catalog index rows with authentic embossed book spines and ribbons.
  indexSpines,

  /// Ultra-compact 1-row item list for maximum books visible per screen.
  compactList,
}

/// Iconography visual language.
enum DimensionIconStyle {
  /// Material 3 rounded glyphs.
  modernRounded,

  /// Apple Cupertino SF-style fine-stroke monoline glyphs.
  cupertinoLinear,

  /// Monospace ASCII and bracketed terminal runes.
  terminalAscii,

  /// Classical scholarly and bookish glyphs.
  classicalSerif,

  /// Ultra-clean 1.5px hairline minimal glyphs.
  hairlineMinimal,
}

/// Complete configuration and styling metrics for an App Dimension.
class DimensionConfig {
  final AppDimension dimension;
  final String name;
  final String subtitle;
  final String badge;
  final DimensionNavStyle navStyle;
  final DimensionCardStyle cardStyle;
  final DimensionIconStyle iconStyle;
  final AppTheme defaultTheme;
  final double cardRadius;
  final double cardBorderWidth;
  final double elevation;
  final bool enableBlur;
  final bool isMonospace;
  final bool isSerif;

  const DimensionConfig({
    required this.dimension,
    required this.name,
    required this.subtitle,
    required this.badge,
    required this.navStyle,
    required this.cardStyle,
    required this.iconStyle,
    required this.defaultTheme,
    required this.cardRadius,
    required this.cardBorderWidth,
    required this.elevation,
    this.enableBlur = true,
    this.isMonospace = false,
    this.isSerif = false,
  });

  /// Factory resolving the complete configuration for any AppDimension.
  static DimensionConfig forDimension(AppDimension dimension) {
    switch (dimension) {
      case AppDimension.modernist:
        return const DimensionConfig(
          dimension: AppDimension.modernist,
          name: 'Modernist',
          subtitle: 'Balanced squircle cards with frosted bottom dock',
          badge: 'Default',
          navStyle: DimensionNavStyle.bottomStandard,
          cardStyle: DimensionCardStyle.masonryGrid,
          iconStyle: DimensionIconStyle.modernRounded,
          defaultTheme: AppTheme.ferrous,
          cardRadius: 16.0,
          cardBorderWidth: 1.0,
          elevation: 0.0,
          enableBlur: true,
        );

      case AppDimension.floatingIsland:
        return const DimensionConfig(
          dimension: AppDimension.floatingIsland,
          name: 'Floating Island',
          subtitle: 'Detached capsule dock with magazine bento showcase',
          badge: 'Dynamic Dock',
          navStyle: DimensionNavStyle.floatingIslandDock,
          cardStyle: DimensionCardStyle.bentoShowcase,
          iconStyle: DimensionIconStyle.cupertinoLinear,
          defaultTheme: AppTheme.nord,
          cardRadius: 24.0,
          cardBorderWidth: 1.2,
          elevation: 8.0,
          enableBlur: true,
        );

      case AppDimension.cyberTerminal:
        return const DimensionConfig(
          dimension: AppDimension.cyberTerminal,
          name: 'Cyber Terminal',
          subtitle: 'Top command HUD, telemetry list, and sharp industrial geometry',
          badge: 'Hacker HUD',
          navStyle: DimensionNavStyle.topTerminalHud,
          cardStyle: DimensionCardStyle.terminalTelemetry,
          iconStyle: DimensionIconStyle.terminalAscii,
          defaultTheme: AppTheme.console,
          cardRadius: 0.0,
          cardBorderWidth: 1.5,
          elevation: 0.0,
          enableBlur: false,
          isMonospace: true,
        );

      case AppDimension.athenaeum:
        return const DimensionConfig(
          dimension: AppDimension.athenaeum,
          name: 'Athenaeum',
          subtitle: 'Book-spine index catalog with classical ribbon navigation',
          badge: 'Literary Shelf',
          navStyle: DimensionNavStyle.compactRibbon,
          cardStyle: DimensionCardStyle.indexSpines,
          iconStyle: DimensionIconStyle.classicalSerif,
          defaultTheme: AppTheme.sepia,
          cardRadius: 6.0,
          cardBorderWidth: 1.0,
          elevation: 2.0,
          enableBlur: false,
          isSerif: true,
        );

      case AppDimension.compactSlate:
        return const DimensionConfig(
          dimension: AppDimension.compactSlate,
          name: 'Compact Slate',
          subtitle: 'Ultra-dense single-row list for rapid skimming & e-ink clarity',
          badge: 'High-Density',
          navStyle: DimensionNavStyle.bottomStandard,
          cardStyle: DimensionCardStyle.compactList,
          iconStyle: DimensionIconStyle.hairlineMinimal,
          defaultTheme: AppTheme.eInk,
          cardRadius: 4.0,
          cardBorderWidth: 1.0,
          elevation: 0.0,
          enableBlur: false,
        );
    }
  }

  /// Maps an AppTheme to its most authentic AppDimension for Auto-Sync.
  static AppDimension dimensionForTheme(AppTheme theme) {
    switch (theme) {
      case AppTheme.ferrous:
        return AppDimension.modernist;
      case AppTheme.console:
        return AppDimension.cyberTerminal;
      case AppTheme.sepia:
        return AppDimension.athenaeum;
      case AppTheme.light:
        return AppDimension.modernist;
      case AppTheme.oledMidnight:
        return AppDimension.floatingIsland;
      case AppTheme.matcha:
        return AppDimension.athenaeum;
      case AppTheme.nord:
        return AppDimension.floatingIsland;
      case AppTheme.eInk:
        return AppDimension.compactSlate;
    }
  }
}
