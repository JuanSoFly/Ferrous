import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/constants/app_constants.dart';
import 'package:reader_app/core/services/update_service.dart';
import 'package:reader_app/core/widgets/update_dialog.dart';
import 'package:reader_app/features/settings/appearance_screen.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'package:reader_app/features/settings/library_locations/library_locations_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Future<PackageInfo> _packageInfoFuture;
  bool _isCheckingForUpdates = false;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  Future<void> _handleCheckForUpdates() async {
    if (_isCheckingForUpdates) return;

    setState(() {
      _isCheckingForUpdates = true;
    });

    try {
      final updateInfo = await UpdateService.checkForUpdate();
      if (!mounted) return;

      if (updateInfo == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Unable to check for updates. Please try again later.'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      } else if (updateInfo.isUpdateAvailable) {
        showUpdateDialog(context, updateInfo);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ferrous is up to date (v${updateInfo.currentVersion})'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('An error occurred while checking for updates.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme?>();
    final isEInk = currentTheme == AppTheme.eInk;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [
            _buildSectionHeader(theme, 'Aesthetics & Layout', isEInk: isEInk),
            const SizedBox(height: 8),
            _buildInsetGroup(
              theme: theme,
              isEInk: isEInk,
              children: [
                _buildSettingsTile(
                  context: context,
                  theme: theme,
                  isEInk: isEInk,
                  icon: Icons.palette_outlined,
                  title: 'Appearance & Dimensions',
                  subtitle: 'Customize layouts, themes, dynamic dock, and typography',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AppearanceScreen()),
                    );
                  },
                  showChevron: true,
                ),
                _buildDivider(theme, isEInk: isEInk),
                _buildSettingsTile(
                  context: context,
                  theme: theme,
                  isEInk: isEInk,
                  icon: Icons.folder_open_outlined,
                  title: 'Library Locations',
                  subtitle: 'Configure book scan directories',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LibraryLocationsScreen(),
                      ),
                    );
                  },
                  showChevron: true,
                ),
              ],
            ),
            const SizedBox(height: 24),
            _buildSectionHeader(theme, 'Application Info', isEInk: isEInk),
            const SizedBox(height: 8),
            FutureBuilder<PackageInfo>(
              future: _packageInfoFuture,
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '1.1.0';
                return _buildInsetGroup(
                  theme: theme,
                  isEInk: isEInk,
                  children: [
                    _buildSettingsTile(
                      context: context,
                      theme: theme,
                      isEInk: isEInk,
                      icon: Icons.info_outline,
                      title: 'About Ferrous',
                      subtitle: 'Version $version',
                      showChevron: false,
                    ),
                    _buildDivider(theme, isEInk: isEInk),
                    _buildSettingsTile(
                      context: context,
                      theme: theme,
                      isEInk: isEInk,
                      icon: Icons.system_update_outlined,
                      title: 'Check for Updates',
                      subtitle: _isCheckingForUpdates
                          ? 'Checking for updates...'
                          : 'Check for the latest release',
                      trailing: _isCheckingForUpdates
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
                              ),
                            )
                          : null,
                      showChevron: !_isCheckingForUpdates,
                      onTap: _isCheckingForUpdates ? null : _handleCheckForUpdates,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title, {bool isEInk = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: isEInk ? FontWeight.w700 : FontWeight.w600,
          color: isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _buildInsetGroup({
    required ThemeData theme,
    required List<Widget> children,
    bool isEInk = false,
  }) {
    if (isEInk) {
      return Container(
        decoration: BoxDecoration(
          color: const Color(0xFFE0DCD3),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: const Color(0xFF1A1A18), width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Column(
            children: children,
          ),
        ),
      );
    }

    final borderColor = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.04);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: borderColor, width: 1),
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildDivider(ThemeData theme, {bool isEInk = false}) {
    if (isEInk) {
      return const Divider(
        height: 1,
        thickness: 1,
        indent: 64,
        endIndent: 0,
        color: Color(0xFF9E9A90),
      );
    }

    return Divider(
      height: 1,
      thickness: 0.5,
      indent: 64,
      endIndent: 0,
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
    Widget? trailing,
    bool isEInk = false,
  }) {
    final leadingWidget = isEInk
        ? Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEAE6DF),
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: const Color(0xFF1A1A18), width: 1),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF1A1A18),
              size: 20,
            ),
          )
        : Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              icon,
              color: theme.colorScheme.primary,
              size: 20,
            ),
          );

    return ListTile(
      minTileHeight: 60,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: leadingWidget,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: isEInk ? FontWeight.w700 : FontWeight.w600,
          fontSize: 15,
          letterSpacing: -0.2,
          color: isEInk ? const Color(0xFF1A1A18) : null,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isEInk
              ? const Color(0xFF4A4945)
              : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.72),
          fontSize: 12,
        ),
      ),
      trailing: trailing ??
          (showChevron
              ? Icon(
                  Icons.chevron_right,
                  color: isEInk
                      ? const Color(0xFF1A1A18)
                      : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
                  size: 20,
                )
              : null),
      onTap: onTap,
    );
  }
}
