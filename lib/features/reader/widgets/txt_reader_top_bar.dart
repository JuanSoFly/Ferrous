import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:ferrous/core/models/book.dart';
import 'package:ferrous/features/settings/app_themes.dart';
import 'kindle_popup_menu.dart';

class TxtReaderTopBar extends StatelessWidget {
  final Book book;
  final bool lockMode;
  final bool showTtsControls;
  final VoidCallback onBack;
  final VoidCallback onToggleLock;
  final VoidCallback onShowSettings;
  final VoidCallback onShowReadingMode;
  final VoidCallback onToggleTts;
  final VoidCallback? onShowSearch;
  final VoidCallback onShowChapters;

  const TxtReaderTopBar({
    super.key,
    required this.book,
    required this.lockMode,
    required this.showTtsControls,
    required this.onBack,
    required this.onToggleLock,
    required this.onShowSettings,
    required this.onShowReadingMode,
    required this.onToggleTts,
    this.onShowSearch,
    required this.onShowChapters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentTheme = context.watch<AppTheme>();
    final isEInk = currentTheme == AppTheme.eInk;

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: isEInk
            ? const Color(0xFFEAE6DF)
            : theme.colorScheme.surface.withValues(alpha: 0.94),
        elevation: 0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SafeArea(
              bottom: false,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 2.0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        tooltip: 'Back',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onBack();
                        },
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Text(
                            book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: isEInk ? const Color(0xFF1A1A18) : null,
                            ),
                          ),
                        ),
                      ),
                      if (onShowSearch != null)
                        IconButton(
                          icon: const Icon(Icons.search, size: 22),
                          tooltip: 'Find in section',
                          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            onShowSearch!();
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.format_list_bulleted, size: 22),
                        tooltip: 'Chapters',
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onShowChapters();
                        },
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_horiz,
                          size: 22,
                          color: isEInk
                              ? const Color(0xFF1A1A18)
                              : ((showTtsControls || lockMode)
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface),
                        ),
                        tooltip: 'More options',
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        position: PopupMenuPosition.under,
                        shape: isEInk
                            ? const KindlePopupShape()
                            : RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                        color: isEInk ? const Color(0xFFEAE6DF) : theme.colorScheme.surfaceContainer,
                        surfaceTintColor: Colors.transparent,
                        elevation: isEInk ? 0 : 4,
                        onSelected: (value) {
                          HapticFeedback.lightImpact();
                          switch (value) {
                            case 'settings':
                              onShowSettings();
                              break;
                            case 'reading_mode':
                              onShowReadingMode();
                              break;
                            case 'tts':
                              onToggleTts();
                              break;
                            case 'lock':
                              onToggleLock();
                              break;
                          }
                        },
                        itemBuilder: (BuildContext context) => [
                          const PopupMenuItem<String>(
                            value: 'settings',
                            child: Row(
                              children: [
                                Icon(Icons.tune_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Settings'),
                              ],
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'reading_mode',
                            child: Row(
                              children: [
                                Icon(Icons.auto_stories_outlined, size: 20),
                                SizedBox(width: 12),
                                Text('Reading Mode'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'tts',
                            child: Row(
                              children: [
                                Icon(
                                  showTtsControls ? Icons.volume_up : Icons.volume_up_outlined,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(showTtsControls ? 'Hide Audio' : 'Read Aloud'),
                              ],
                            ),
                          ),
                          PopupMenuItem<String>(
                            value: 'lock',
                            child: Row(
                              children: [
                                Icon(
                                  lockMode ? Icons.lock : Icons.lock_outline,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Text(lockMode ? 'Unlock Reader' : 'Lock Reader'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Divider(
              height: 1,
              thickness: isEInk ? 1.5 : 1.0,
              color: isEInk
                  ? const Color(0xFF1A1A18)
                  : theme.dividerColor.withValues(alpha: 0.1),
            ),
          ],
        ),
      ),
    );
  }
}
