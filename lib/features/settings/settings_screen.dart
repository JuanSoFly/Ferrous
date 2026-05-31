import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:reader_app/features/settings/appearance_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100), // Spacing for floating nav bar
        children: [
          _buildSectionHeader(theme, 'Aesthetics & Layout'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _buildSettingsTile(
                  context: context,
                  theme: theme,
                  icon: Icons.palette_outlined,
                  title: 'Appearance',
                  subtitle: 'Customize themes, dark mode, and fonts',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AppearanceScreen()),
                    );
                  },
                  showChevron: true,
                ),
                _buildDivider(theme),
                _buildSettingsTile(
                  context: context,
                  theme: theme,
                  icon: Icons.folder_open_outlined,
                  title: 'Library Locations',
                  subtitle: 'Configure book scan directories',
                  onTap: () {
                    // Can be extended or left placeholder
                  },
                  showChevron: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildSectionHeader(theme, 'Application Info'),
          const SizedBox(height: 8),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '1.1.0';
              return Card(
                child: _buildSettingsTile(
                  context: context,
                  theme: theme,
                  icon: Icons.info_outline,
                  title: 'About Ferrous',
                  subtitle: 'Version $version',
                  showChevron: false,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildDivider(ThemeData theme) {
    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 56,
      endIndent: 16,
      color: theme.brightness == Brightness.dark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.04),
    );
  }

  Widget _buildSettingsTile({
    required BuildContext context,
    required ThemeData theme,
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    bool showChevron = false,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: theme.colorScheme.primary,
          size: 20,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          fontSize: 12,
        ),
      ),
      trailing: showChevron
          ? Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              size: 20,
            )
          : null,
      onTap: onTap,
    );
  }
}
