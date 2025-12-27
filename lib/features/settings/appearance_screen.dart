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

    return Card(
      elevation: isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            children: [
              // Preview Circle
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: themeData.scaffoldBackgroundColor,
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    "Ag",
                    style: themeData.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.color
                              ?.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle,
                    color: Theme.of(context).colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
