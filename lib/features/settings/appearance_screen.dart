import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/core/models/app_dimension.dart';
import 'package:ferrous/features/settings/dimension_controller.dart';
import 'package:ferrous/features/settings/theme_controller.dart';
import 'package:ferrous/features/settings/app_themes.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentTheme = context.watch<AppTheme>();
    final themeController = context.read<ThemeController>();
    final dimensionState = context.watch<DimensionState>();
    final dimensionController = context.read<DimensionController>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Appearance & Style"),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ==========================================
          // 1. APP DIMENSIONS SECTION
          // ==========================================
          Row(
            children: [
              Icon(Icons.layers_outlined, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                "Layout Dimensions",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Change the spatial structure, navigation placement, icon pack, and card geometry.",
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 12),

          // Auto-Sync Switch Card
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(currentTheme == AppTheme.eInk ? 2 : 14),
              side: BorderSide(
                color: currentTheme == AppTheme.eInk
                    ? const Color(0xFF1A1A18)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
                width: currentTheme == AppTheme.eInk ? 1.5 : 1.0,
              ),
            ),
            color: currentTheme == AppTheme.eInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surfaceContainerLow,
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              title: Text(
                "Auto-Sync Dimension with Theme",
                style: currentTheme == AppTheme.eInk
                    ? GoogleFonts.robotoSlab(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A18))
                    : const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                dimensionState.autoSyncWithTheme
                    ? "Themes automatically trigger their matching layout style."
                    : "Independent: mix and match any color theme with any layout style.",
                style: TextStyle(
                  fontSize: 11,
                  color: currentTheme == AppTheme.eInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
              value: dimensionState.autoSyncWithTheme,
              activeTrackColor: currentTheme == AppTheme.eInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary.withValues(alpha: 0.5),
              activeThumbColor: currentTheme == AppTheme.eInk ? const Color(0xFFEAE6DF) : theme.colorScheme.primary,
              onChanged: (enabled) {
                HapticFeedback.lightImpact();
                dimensionController.setAutoSync(enabled);
                if (enabled) {
                  dimensionController.onThemeChanged(currentTheme);
                }
              },
            ),
          ),
          const SizedBox(height: 12),

          // Dimension Options
          ...AppDimension.values.map((dim) {
            final config = DimensionConfig.forDimension(dim);
            return _DimensionOption(
              dimension: dim,
              config: config,
              currentDimension: dimensionState.dimension,
              onTap: () {
                HapticFeedback.selectionClick();
                dimensionController.setDimension(dim);
              },
            );
          }),

          const SizedBox(height: 24),
          const Divider(height: 1),
          const SizedBox(height: 20),

          // ==========================================
          // 2. THEMES SECTION
          // ==========================================
          Row(
            children: [
              Icon(Icons.palette_outlined, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                "Color Palette & Ambiance",
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            "Select the color scheme and ambient tones for comfortable reading.",
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 14),

          _ThemeOption(
            title: "Ferrous (Default)",
            description: "Dark mode with Rust orange accents.",
            theme: AppTheme.ferrous,
            currentTheme: currentTheme,
            onTap: () => themeController.setTheme(AppTheme.ferrous),
          ),
          _ThemeOption(
            title: "Console",
            description: "Hacker aesthetic. Green on Black. Monospace.",
            theme: AppTheme.console,
            currentTheme: currentTheme,
            onTap: () => themeController.setTheme(AppTheme.console),
          ),
          _ThemeOption(
            title: "Sepia",
            description: "Warm tones for comfortable reading.",
            theme: AppTheme.sepia,
            currentTheme: currentTheme,
            onTap: () => themeController.setTheme(AppTheme.sepia),
          ),
          _ThemeOption(
            title: "Light",
            description: "Clean, bright interface.",
            theme: AppTheme.light,
            currentTheme: currentTheme,
            onTap: () => themeController.setTheme(AppTheme.light),
          ),
          _ThemeOption(
            title: "OLED Midnight",
            description: "Pitch black. Starlight silver & celestial blue for bed.",
            theme: AppTheme.oledMidnight,
            currentTheme: currentTheme,
            onTap: () => themeController.setTheme(AppTheme.oledMidnight),
          ),
          _ThemeOption(
            title: "Matcha",
            description: "Botanical sage paper with deep forest moss ink.",
            theme: AppTheme.matcha,
            currentTheme: currentTheme,
            onTap: () => themeController.setTheme(AppTheme.matcha),
          ),
          _ThemeOption(
            title: "Nord Arctic",
            description: "Sub-zero polar slates with frostbite cyan.",
            theme: AppTheme.nord,
            currentTheme: currentTheme,
            onTap: () => themeController.setTheme(AppTheme.nord),
          ),
          _ThemeOption(
            title: "E-Ink Paper",
            description: "Distraction-free physical e-paper greyscale.",
            theme: AppTheme.eInk,
            currentTheme: currentTheme,
            onTap: () => themeController.setTheme(AppTheme.eInk),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ==========================================
// DIMENSION OPTION WIDGET
// ==========================================
class _DimensionOption extends StatelessWidget {
  final AppDimension dimension;
  final DimensionConfig config;
  final AppDimension currentDimension;
  final VoidCallback onTap;

  const _DimensionOption({
    required this.dimension,
    required this.config,
    required this.currentDimension,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = dimension == currentDimension;
    final primary = theme.colorScheme.primary;
    AppTheme? currentTheme;
    try {
      currentTheme = context.watch<AppTheme?>();
    } catch (_) {}
    final isEInk = currentTheme == AppTheme.eInk;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
        side: BorderSide(
          color: isEInk
              ? (isSelected ? const Color(0xFF1A1A18) : const Color(0xFF9E9A90))
              : (isSelected ? primary : theme.colorScheme.outlineVariant.withValues(alpha: 0.25)),
          width: isSelected ? 2.0 : 1.0,
        ),
      ),
      color: isEInk
          ? (isSelected ? const Color(0xFFE0DCD3) : const Color(0xFFEAE6DF))
          : (isSelected ? primary.withValues(alpha: 0.08) : theme.colorScheme.surfaceContainerLow),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(isEInk ? 2 : 16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildSpatialPreview(theme, config, isSelected),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          config.name,
                          style: isEInk
                              ? GoogleFonts.robotoSlab(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF1A1A18),
                                )
                              : TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: config.isMonospace ? 'monospace' : (config.isSerif ? 'serif' : null),
                                ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isEInk
                                ? Colors.transparent
                                : (isSelected ? primary.withValues(alpha: 0.2) : theme.colorScheme.surfaceContainerHigh),
                            borderRadius: BorderRadius.circular(isEInk ? 2 : 6),
                            border: isEInk ? Border.all(color: const Color(0xFF1A1A18), width: 1.0) : null,
                          ),
                          child: Text(
                            config.badge,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: isEInk ? 0.5 : 0,
                              color: isEInk ? const Color(0xFF1A1A18) : (isSelected ? primary : theme.colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      config.subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isEInk ? const Color(0xFF3D3C38) : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isSelected)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isEInk ? const Color(0xFF1A1A18) : primary,
                    shape: isEInk ? BoxShape.rectangle : BoxShape.circle,
                    borderRadius: isEInk ? BorderRadius.circular(2) : null,
                  ),
                  child: Icon(
                    Icons.check,
                    color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.onPrimary,
                    size: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Miniature spatial diagram representing navigation position and card shape.
  Widget _buildSpatialPreview(ThemeData theme, DimensionConfig config, bool isSelected) {
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Container(
      width: 44,
      height: 58,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? primary : onSurface.withValues(alpha: 0.2),
          width: 1.0,
        ),
      ),
      padding: const EdgeInsets.all(3),
      child: Column(
        children: [
          // Top HUD indicator if top nav
          if (config.navStyle == DimensionNavStyle.topTerminalHud)
            Container(
              height: 6,
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 3),
              color: primary,
            )
          else
            Container(
              height: 4,
              width: 18,
              margin: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                color: onSurface.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

          // Content simulation blocks
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? primary.withValues(alpha: 0.25) : onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(config.cardRadius <= 0 ? 0 : 3),
                      border: config.cardBorderWidth > 1
                          ? Border.all(color: primary.withValues(alpha: 0.4), width: 0.8)
                          : null,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? primary.withValues(alpha: 0.25) : onSurface.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(config.cardRadius <= 0 ? 0 : 3),
                      border: config.cardBorderWidth > 1
                          ? Border.all(color: primary.withValues(alpha: 0.4), width: 0.8)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Bottom nav indicators
          if (config.navStyle == DimensionNavStyle.floatingIslandDock)
            Container(
              height: 6,
              width: 32,
              margin: const EdgeInsets.only(top: 3, bottom: 1),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(4),
              ),
            )
          else if (config.navStyle == DimensionNavStyle.bottomStandard)
            Container(
              height: 5,
              width: double.infinity,
              margin: const EdgeInsets.only(top: 3),
              color: primary,
            )
          else if (config.navStyle == DimensionNavStyle.compactRibbon)
            Container(
              height: 3,
              width: double.infinity,
              margin: const EdgeInsets.only(top: 3),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// THEME OPTION WIDGET
// ==========================================
class _ThemeOption extends StatelessWidget {
  final String title;
  final String description;
  final AppTheme theme;
  final AppTheme currentTheme;
  final VoidCallback onTap;

  const _ThemeOption({
    required this.title,
    required this.description,
    required this.theme,
    required this.currentTheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = theme == currentTheme;
    final themeData = AppThemes.themeData[theme]!;

    final cardBg = themeData.cardTheme.color ?? themeData.colorScheme.surface;
    final primary = themeData.colorScheme.primary;
    final onPrimary = themeData.colorScheme.onPrimary;
    final onSurface = themeData.colorScheme.onSurface;

    final effectiveCardColor = isSelected
        ? Color.alphaBlend(primary.withValues(alpha: 0.08), cardBg)
        : cardBg;

    final unselectedBorderColor = _resolveUnselectedBorderColor(theme);
    final effectiveBorderSide = BorderSide(
      color: isSelected ? primary : unselectedBorderColor,
      width: isSelected ? 2.0 : 1.0,
    );

    final isCurrentEInk = currentTheme == AppTheme.eInk;

    return Theme(
      data: themeData,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(isCurrentEInk ? 2 : 16),
          side: effectiveBorderSide,
        ),
        color: effectiveCardColor,
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(isCurrentEInk ? 2 : 16),
          splashColor: primary.withValues(alpha: 0.12),
          highlightColor: primary.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(14.0),
            child: Row(
              children: [
                _buildConcentricPreview(themeData, theme),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: isCurrentEInk
                            ? GoogleFonts.robotoSlab(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: onSurface,
                              )
                            : (themeData.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: onSurface,
                              ) ?? TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: onSurface,
                              )),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        style: themeData.textTheme.bodyMedium?.copyWith(
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.72),
                        ) ?? TextStyle(
                          fontSize: 12,
                          color: onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (isSelected)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: primary,
                      shape: isCurrentEInk ? BoxShape.rectangle : BoxShape.circle,
                      borderRadius: isCurrentEInk ? BorderRadius.circular(2) : null,
                    ),
                    child: Icon(
                      Icons.check,
                      color: onPrimary,
                      size: 14,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _resolveUnselectedBorderColor(AppTheme theme) {
    switch (theme) {
      case AppTheme.ferrous:
        return const Color(0xFF2B2824);
      case AppTheme.console:
        return const Color(0xFF00FF41).withValues(alpha: 0.35);
      case AppTheme.sepia:
        return const Color(0xFFDFD4B7);
      case AppTheme.light:
        return const Color(0xFFE2E7ED);
      case AppTheme.oledMidnight:
        return const Color(0xFF24242A);
      case AppTheme.matcha:
        return const Color(0xFFCBD8C5);
      case AppTheme.nord:
        return const Color(0xFF434C5E);
      case AppTheme.eInk:
        return const Color(0xFF9E9A90);
    }
  }

  Widget _buildConcentricPreview(ThemeData themeData, AppTheme theme) {
    final bg = themeData.scaffoldBackgroundColor;
    final primary = themeData.colorScheme.primary;
    final onSurface = themeData.colorScheme.onSurface;

    final Color middleRingColor;
    switch (theme) {
      case AppTheme.ferrous:
        middleRingColor = const Color(0xFF1E1C19);
        break;
      case AppTheme.console:
        middleRingColor = const Color(0xFF1B0A16);
        break;
      case AppTheme.sepia:
        middleRingColor = const Color(0xFFE9E0C9);
        break;
      case AppTheme.light:
        middleRingColor = const Color(0xFFEDF1F5);
        break;
      case AppTheme.oledMidnight:
        middleRingColor = const Color(0xFF121214);
        break;
      case AppTheme.matcha:
        middleRingColor = const Color(0xFFE5ECE1);
        break;
      case AppTheme.nord:
        middleRingColor = const Color(0xFF3B4252);
        break;
      case AppTheme.eInk:
        middleRingColor = const Color(0xFFE0DCD3);
        break;
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(
          color: theme == AppTheme.eInk ? const Color(0xFF1A1A18) : onSurface.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: middleRingColor,
            border: theme == AppTheme.eInk ? Border.all(color: const Color(0xFF9E9A90), width: 1) : null,
            boxShadow: theme == AppTheme.eInk
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
          ),
          child: Center(
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
