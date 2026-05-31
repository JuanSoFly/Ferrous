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
    final baseTheme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected
              ? baseTheme.colorScheme.primary
              : baseTheme.brightness == Brightness.dark
                  ? const Color(0xFF2B2824)
                  : const Color(0xFFE2E7ED),
          width: isSelected ? 2 : 1,
        ),
      ),
      color: isSelected
          ? baseTheme.colorScheme.primary.withValues(alpha: 0.04)
          : themeData.brightness == Brightness.dark
              ? const Color(0xFF1E1C19)
              : Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              _buildConcentricPreview(themeData),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: baseTheme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
                    color: baseTheme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 14,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildConcentricPreview(ThemeData themeData) {
    final bg = themeData.scaffoldBackgroundColor;
    final primary = themeData.colorScheme.primary;
    final surface = themeData.colorScheme.surface;

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg,
        border: Border.all(
          color: Colors.grey.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Center(
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
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
