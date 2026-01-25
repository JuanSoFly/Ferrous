import 'package:flutter/material.dart';
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
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_screens.length, (i) {
          if (_activated[i]) return _screens[i];
          return const SizedBox.shrink();
        }),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
            _activated[index] = true;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.comment),
            label: 'Annotations',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
