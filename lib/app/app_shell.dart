import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      extendBody: false,
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_screens.length, (i) {
          if (_activated[i]) return _screens[i];
          return const SizedBox.shrink();
        }),
      ),
      bottomNavigationBar: Container(
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
                    _buildNavItem(0, Icons.book_outlined, Icons.auto_stories, 'Library', theme),
                    _buildNavItem(1, Icons.mode_comment_outlined, Icons.comment, 'Annotations', theme),
                    _buildNavItem(2, Icons.settings_outlined, Icons.settings, 'Settings', theme),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData outlineIcon, IconData filledIcon, String label, ThemeData theme) {
    final isSelected = _currentIndex == index;
    final activeColor = theme.colorScheme.primary;
    final inactiveColor = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6);

    return Expanded(
      child: Semantics(
        label: label,
        selected: isSelected,
        button: true,
        child: InkResponse(
          containedInkWell: true,
          highlightShape: BoxShape.rectangle,
          onTap: () {
            if (_currentIndex == index) {
              HapticFeedback.lightImpact();
              return;
            }
            HapticFeedback.selectionClick();
            setState(() {
              _currentIndex = index;
              _activated[index] = true;
            });
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 200),
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
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
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
