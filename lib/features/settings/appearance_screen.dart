import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/features/settings/theme_controller.dart';
import 'package:reader_app/features/settings/app_themes.dart';

class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Watch current theme
    final currentTheme = context.watch<AppTheme>();
    final controller = context.read<ThemeController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text("Appearance"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 16.0),
            child: Text(
              "Select Theme",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          _ThemeOption(
            title: "Ferrous (Default)",
            description: "Dark mode with Rust orange accents.",
            theme: AppTheme.ferrous,
            currentTheme: currentTheme,
            onTap: () => controller.setTheme(AppTheme.ferrous),
          ),
          _ThemeOption(
            title: "Console",
            description: "Hacker aesthetic. Green on Black. Monospace.",
            theme: AppTheme.console,
            currentTheme: currentTheme,
            onTap: () => controller.setTheme(AppTheme.console),
          ),
          _ThemeOption(
            title: "Sepia",
            description: "Warm tones for comfortable reading.",
            theme: AppTheme.sepia,
            currentTheme: currentTheme,
            onTap: () => controller.setTheme(AppTheme.sepia),
          ),
          _ThemeOption(
            title: "Light",
            description: "Clean, bright interface.",
            theme: AppTheme.light,
            currentTheme: currentTheme,
            onTap: () => controller.setTheme(AppTheme.light),
          ),
          _ThemeOption(
            title: "OLED Midnight",
            description: "Pitch black. Starlight silver & celestial blue for bed.",
            theme: AppTheme.oledMidnight,
            currentTheme: currentTheme,
            onTap: () => controller.setTheme(AppTheme.oledMidnight),
          ),
          _ThemeOption(
            title: "Matcha",
            description: "Botanical sage paper with deep forest moss ink.",
            theme: AppTheme.matcha,
            currentTheme: currentTheme,
            onTap: () => controller.setTheme(AppTheme.matcha),
          ),
          _ThemeOption(
            title: "Nord Arctic",
            description: "Sub-zero polar slates with frostbite cyan.",
            theme: AppTheme.nord,
            currentTheme: currentTheme,
            onTap: () => controller.setTheme(AppTheme.nord),
          ),
          _ThemeOption(
            title: "E-Ink Paper",
            description: "Distraction-free physical e-paper greyscale.",
            theme: AppTheme.eInk,
            currentTheme: currentTheme,
            onTap: () => controller.setTheme(AppTheme.eInk),
          ),
        ],
      ),
    );
  }
}

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

    // Resolve accurate colors from the option's own ThemeData
    final cardBg = themeData.cardTheme.color ?? themeData.colorScheme.surface;
    final primary = themeData.colorScheme.primary;
    final onPrimary = themeData.colorScheme.onPrimary;
    final onSurface = themeData.colorScheme.onSurface;

    // Authentic card background with a subtle primary tint when selected
    final effectiveCardColor = isSelected
        ? Color.alphaBlend(primary.withValues(alpha: 0.08), cardBg)
        : cardBg;

    // Theme-matched border: accent border when selected, subtle theme border when unselected
    final unselectedBorderColor = _resolveUnselectedBorderColor(theme);
    final effectiveBorderSide = BorderSide(
      color: isSelected ? primary : unselectedBorderColor,
      width: isSelected ? 2.0 : 1.0,
    );

    return Theme(
      data: themeData,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: effectiveBorderSide,
        ),
        color: effectiveCardColor,
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
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
                        style: themeData.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: onSurface,
                        ) ?? TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: onSurface,
                        ),
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
                      shape: BoxShape.circle,
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
        return const Color(0xFFD0D0D0);
    }
  }

  Widget _buildConcentricPreview(ThemeData themeData, AppTheme theme) {
    final bg = themeData.scaffoldBackgroundColor;
    final primary = themeData.colorScheme.primary;
    final onSurface = themeData.colorScheme.onSurface;

    // Use distinct surface/container color for the middle ring so all 3 rings contrast clearly
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
        middleRingColor = const Color(0xFFEAEAEA);
        break;
    }

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(
          color: onSurface.withValues(alpha: 0.2),
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
            boxShadow: [
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
