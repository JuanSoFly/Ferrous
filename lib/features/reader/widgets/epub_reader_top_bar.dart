import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:reader_app/core/models/book.dart';
import 'package:reader_app/features/settings/app_themes.dart';
import 'kindle_popup_menu.dart';

class EpubReaderTopBar extends StatelessWidget {
  final Book book;
  final bool lockMode;
  final bool showTtsControls;
  final VoidCallback onBack;
  final VoidCallback onToggleLock;
  final VoidCallback onShowSettings;
  final VoidCallback onShowReadingMode;
  final VoidCallback onToggleTts;
  final VoidCallback onShowSearch;
  final VoidCallback onShowChapters;

  const EpubReaderTopBar({
    super.key,
    required this.book,
    required this.lockMode,
    required this.showTtsControls,
    required this.onBack,
    required this.onToggleLock,
    required this.onShowSettings,
    required this.onShowReadingMode,
    required this.onToggleTts,
    required this.onShowSearch,
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
                      // Leading: Back button (Apple HIG 20pt chevron with 48x48 touch target)
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                        tooltip: 'Back',
                        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onBack();
                        },
                      ),

                      // Center: Expanded title (maxLines 1, ellipsis, clean typography)
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

                      // Trailing prominent actions: Search and Chapters
                      IconButton(
                        icon: const Icon(Icons.search, size: 22),
                        tooltip: 'Find in chapter',
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onShowSearch();
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

                      // Overflow / Controls Menu
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
                        color: isEInk ? Colors.transparent : theme.colorScheme.surfaceContainer,
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
                        itemBuilder: (BuildContext context) => isEInk
                            ? <PopupMenuEntry<String>>[
                                const PopupMenuItem<String>(
                                  value: 'settings',
                                  padding: EdgeInsets.zero,
                                  height: 42,
                                  child: KindlePopupItem(
                                    icon: Icons.text_format,
                                    label: 'Appearance & Settings',
                                  ),
                                ),
                                const PopupMenuItem<String>(
                                  value: 'reading_mode',
                                  padding: EdgeInsets.zero,
                                  height: 42,
                                  child: KindlePopupItem(
                                    icon: Icons.view_carousel,
                                    label: 'Reading Mode',
                                  ),
                                ),
                                const KindlePopupDivider(),
                                PopupMenuItem<String>(
                                  value: 'tts',
                                  padding: EdgeInsets.zero,
                                  height: 42,
                                  child: KindlePopupItem(
                                    icon: showTtsControls ? Icons.volume_off : Icons.volume_up,
                                    label: showTtsControls ? 'Stop Listening' : 'Listen (Text-to-Speech)',
                                    isHighlighted: showTtsControls,
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'lock',
                                  padding: EdgeInsets.zero,
                                  height: 42,
                                  child: KindlePopupItem(
                                    icon: lockMode ? Icons.lock_open : Icons.lock_outline,
                                    label: lockMode ? 'Unlock Controls' : 'Lock Reader',
                                    isHighlighted: lockMode,
                                  ),
                                ),
                              ]
                            : <PopupMenuEntry<String>>[
                                PopupMenuItem<String>(
                                  value: 'settings',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.text_format, size: 20, color: theme.colorScheme.onSurface),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Appearance & Settings',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'reading_mode',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.view_carousel, size: 20, color: theme.colorScheme.onSurface),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Reading Mode',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const PopupMenuDivider(height: 1),
                                PopupMenuItem<String>(
                                  value: 'tts',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        showTtsControls ? Icons.volume_off : Icons.volume_up,
                                        size: 20,
                                        color: showTtsControls ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        showTtsControls ? 'Stop Listening' : 'Listen (Text-to-Speech)',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: showTtsControls ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuItem<String>(
                                  value: 'lock',
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        lockMode ? Icons.lock_open : Icons.lock_outline,
                                        size: 20,
                                        color: lockMode ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        lockMode ? 'Unlock Controls' : 'Lock Reader',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: lockMode ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
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
              height: isEInk ? 1.5 : 0.5,
              thickness: isEInk ? 1.5 : 0.5,
              color: isEInk
                  ? const Color(0xFF1A1A18)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ],
        ),
      ),
    );
  }
}
