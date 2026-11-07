import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:reader_app/core/models/app_dimension.dart';
import 'package:reader_app/core/constants/dimension_tokens.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'package:reader_app/features/settings/dimension_controller.dart';
import 'package:reader_app/features/library/library_screen.dart';
import 'package:reader_app/features/settings/settings_screen.dart';
import 'package:reader_app/features/annotations/annotations_hub_screen.dart';
import 'package:reader_app/core/services/update_service.dart';
import 'package:reader_app/core/widgets/update_dialog.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    LibraryScreen(),
    AnnotationsHubScreen(),
    SettingsScreen(),
  ];

  final List<bool> _activated = [true, false, false];

  @override
  void initState() {
    super.initState();
    // Check for updates after the first frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
    });
  }

  Future<void> _checkForUpdates() async {
    final updateInfo = await UpdateService.checkForUpdate();
    if (updateInfo != null && updateInfo.isUpdateAvailable && mounted) {
      showUpdateDialog(context, updateInfo);
    }
  }

  void _onTabSelected(int index) {
    if (_currentIndex == index) {
      HapticFeedback.lightImpact();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _currentIndex = index;
      _activated[index] = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dimensionState = context.watch<DimensionState>();
    final config = dimensionState.config;

    final isTopHud = config.navStyle == DimensionNavStyle.topTerminalHud;
    final isFloating = config.navStyle == DimensionNavStyle.floatingIslandDock;

    final currentTheme = context.watch<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;

    return Scaffold(
      extendBody: isFloating,
      body: SafeArea(
        top: isTopHud,
        bottom: false,
        child: Column(
          children: [
            if (isTopHud) _buildTopTerminalHud(theme, config),
            Expanded(
              child: IndexedStack(
                index: _currentIndex,
                children: List.generate(_screens.length, (i) {
                  if (_activated[i]) return _screens[i];
                  return const SizedBox.shrink();
                }),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: isTopHud
          ? null
          : _buildBottomNavigation(theme, config, isEInk: isEInk),
    );
  }

  // ==========================================
  // 1. TOP TERMINAL HUD (Cyber Terminal Mode)
  // ==========================================
  Widget _buildTopTerminalHud(ThemeData theme, DimensionConfig config) {
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;
    final monoStyle = GoogleFonts.firaCode(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: primary.withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: primary,
                      shape: BoxShape.rectangle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'SYS.HUD // FERROUS',
                    style: monoStyle.copyWith(
                      color: primary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text(
                'MODE: TERMINAL_EXEC',
                style: monoStyle.copyWith(
                  color: onSurface.withValues(alpha: 0.5),
                  fontSize: 9,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildHudNavItem(0, '01:LIB', 'LIBRARY', theme, config),
              const SizedBox(width: 8),
              _buildHudNavItem(1, '02:NOT', 'NOTES', theme, config),
              const SizedBox(width: 8),
              _buildHudNavItem(2, '03:SET', 'CONFIG', theme, config),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHudNavItem(int index, String tag, String label, ThemeData theme, DimensionConfig config) {
    final isSelected = _currentIndex == index;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Expanded(
      child: InkWell(
        onTap: () => _onTabSelected(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? primary.withValues(alpha: 0.15) : Colors.transparent,
            border: Border.all(
              color: isSelected ? primary : onSurface.withValues(alpha: 0.2),
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Text(
                isSelected ? '[$tag]' : ' $tag ',
                style: GoogleFonts.firaCode(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? primary : onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: GoogleFonts.firaCode(
                  fontSize: 8,
                  letterSpacing: 1.0,
                  color: isSelected ? primary : onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 2. BOTTOM NAVIGATION RESOLVER
  // ==========================================
  Widget _buildBottomNavigation(ThemeData theme, DimensionConfig config, {bool isEInk = false}) {
    switch (config.navStyle) {
      case DimensionNavStyle.floatingIslandDock:
        return _buildFloatingIslandDock(theme, config);
      case DimensionNavStyle.compactRibbon:
        return _buildAthenaeumRibbon(theme, config);
      case DimensionNavStyle.bottomStandard:
      default:
        return _buildStandardBottomNav(theme, config, isEInk: isEInk);
    }
  }

  // ==========================================
  // 3. FLOATING ISLAND CAPSULE DOCK
  // ==========================================
  Widget _buildFloatingIslandDock(ThemeData theme, DimensionConfig config) {
    final isDark = theme.brightness == Brightness.dark;

    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.45)
                    : Colors.black.withValues(alpha: 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildIslandNavItem(0, 'Library', theme, config),
                    _buildIslandNavItem(1, 'Notes', theme, config),
                    _buildIslandNavItem(2, 'Settings', theme, config),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIslandNavItem(int index, String label, ThemeData theme, DimensionConfig config) {
    final isSelected = _currentIndex == index;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    final icon = index == 0
        ? DimensionIcons.navLibrary(config.iconStyle, isSelected)
        : index == 1
            ? DimensionIcons.navAnnotations(config.iconStyle, isSelected)
            : DimensionIcons.navSettings(config.iconStyle, isSelected);

    return Expanded(
      child: GestureDetector(
        onTap: () => _onTabSelected(index),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? primary.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.08 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  icon,
                  size: 20,
                  color: isSelected ? primary : onSurface.withValues(alpha: 0.5),
                ),
              ),
              if (isSelected) ...[
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: primary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 4. ATHENAEUM LITERARY RIBBON
  // ==========================================
  Widget _buildAthenaeumRibbon(ThemeData theme, DimensionConfig config) {
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: primary.withValues(alpha: 0.25),
            width: 1.0,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 54,
          child: Row(
            children: [
              _buildRibbonItem(0, 'I', 'Books', theme, config),
              VerticalDivider(
                color: onSurface.withValues(alpha: 0.1),
                indent: 12,
                endIndent: 12,
                width: 1,
              ),
              _buildRibbonItem(1, 'II', 'Notes', theme, config),
              VerticalDivider(
                color: onSurface.withValues(alpha: 0.1),
                indent: 12,
                endIndent: 12,
                width: 1,
              ),
              _buildRibbonItem(2, 'III', 'Settings', theme, config),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRibbonItem(int index, String roman, String title, ThemeData theme, DimensionConfig config) {
    final isSelected = _currentIndex == index;
    final primary = theme.colorScheme.primary;
    final onSurface = theme.colorScheme.onSurface;

    final icon = index == 0
        ? DimensionIcons.navLibrary(config.iconStyle, isSelected)
        : index == 1
            ? DimensionIcons.navAnnotations(config.iconStyle, isSelected)
            : DimensionIcons.navSettings(config.iconStyle, isSelected);

    return Expanded(
      child: InkWell(
        onTap: () => _onTabSelected(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: isSelected ? primary : onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  '$roman. $title',
                  style: TextStyle(
                    fontFamily: 'serif',
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected ? primary : onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            if (isSelected)
              Container(
                margin: const EdgeInsets.only(top: 4),
                height: 2,
                width: 24,
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 5. STANDARD MODERNIST BOTTOM NAV
  // ==========================================
  Widget _buildStandardBottomNav(ThemeData theme, DimensionConfig config, {bool isEInk = false}) {
    final bool eInkMode = isEInk || config.dimension == AppDimension.compactSlate;
    if (eInkMode) {
      return Container(
        decoration: const BoxDecoration(
          color: Color(0xFFEAE6DF),
          border: Border(
            top: BorderSide(
              color: Color(0xFF1A1A18),
              width: 1.5,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 52,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStandardNavItem(0, 'Library', theme, config, isEInk: true),
                _buildStandardNavItem(1, 'Annotations', theme, config, isEInk: true),
                _buildStandardNavItem(2, 'Settings', theme, config, isEInk: true),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.92),
        border: Border(
          top: BorderSide(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.06),
            width: 0.5,
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: SafeArea(
            top: false,
            child: SizedBox(
              height: 52,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStandardNavItem(0, 'Library', theme, config),
                  _buildStandardNavItem(1, 'Annotations', theme, config),
                  _buildStandardNavItem(2, 'Settings', theme, config),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStandardNavItem(int index, String label, ThemeData theme, DimensionConfig config, {bool isEInk = false}) {
    final isSelected = _currentIndex == index;
    final activeColor = isEInk ? const Color(0xFF1A1A18) : theme.colorScheme.primary;
    final inactiveColor = isEInk
        ? const Color(0xFF4A4945)
        : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    final outlineIcon = index == 0
        ? DimensionIcons.navLibrary(config.iconStyle, false)
        : index == 1
            ? DimensionIcons.navAnnotations(config.iconStyle, false)
            : DimensionIcons.navSettings(config.iconStyle, false);

    final filledIcon = index == 0
        ? DimensionIcons.navLibrary(config.iconStyle, true)
        : index == 1
            ? DimensionIcons.navAnnotations(config.iconStyle, true)
            : DimensionIcons.navSettings(config.iconStyle, true);

    return Expanded(
      child: Semantics(
        label: label,
        selected: isSelected,
        button: true,
        child: InkResponse(
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          onTap: () => _onTabSelected(index),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isEInk && isSelected)
                Container(
                  height: 2,
                  width: 28,
                  margin: const EdgeInsets.only(bottom: 2),
                  color: const Color(0xFF1A1A18),
                )
              else if (isEInk)
                const SizedBox(height: 4),
              AnimatedScale(
                scale: isSelected && !isEInk ? 1.05 : 1.0,
                duration: isEInk ? Duration.zero : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Icon(
                  isSelected ? filledIcon : outlineIcon,
                  color: isSelected ? activeColor : inactiveColor,
                  size: 24,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? activeColor : inactiveColor,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
