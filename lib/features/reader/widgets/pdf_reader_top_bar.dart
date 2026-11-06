import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:reader_app/core/models/book.dart';
import '../controllers/pdf_page_controller.dart';
import '../controllers/pdf_tts_controller.dart';
import '../controllers/reader_chrome_controller.dart';

class PdfReaderTopBar extends StatelessWidget {
  final Book book;
  final PdfPageController pageController;
  final PdfTtsController ttsController;
  final ReaderChromeController chromeController;
  final VoidCallback onShowReadingModePicker;
  final VoidCallback onOpenTextPicker;

  const PdfReaderTopBar({
    super.key,
    required this.book,
    required this.pageController,
    required this.ttsController,
    required this.chromeController,
    required this.onShowReadingModePicker,
    required this.onOpenTextPicker,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
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
                          Navigator.of(context).maybePop();
                        },
                      ),

                      // Center: Expanded title & page count subtitle
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: pageController.pageCount > 0 ? 14 : 16,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              if (pageController.pageCount > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Text(
                                    '${pageController.pageIndex + 1} / ${pageController.pageCount}',
                                    maxLines: 1,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),

                      // Trailing prominent action: Text view picker
                      IconButton(
                        icon: const Icon(Icons.text_snippet, size: 22),
                        tooltip: 'Text view',
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onOpenTextPicker();
                        },
                      ),

                      // Overflow / Controls Menu
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_horiz,
                          size: 22,
                          color: (ttsController.showTtsControls || chromeController.isLocked || pageController.autoCrop)
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                        tooltip: 'More options',
                        constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                        position: PopupMenuPosition.under,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        color: theme.colorScheme.surfaceContainer,
                        surfaceTintColor: Colors.transparent,
                        elevation: 4,
                        onSelected: (value) {
                          HapticFeedback.lightImpact();
                          switch (value) {
                            case 'reading_mode':
                              onShowReadingModePicker();
                              break;
                            case 'crop':
                              pageController.setAutoCrop(!pageController.autoCrop);
                              break;
                            case 'tts':
                              ttsController.toggleTts();
                              break;
                            case 'lock':
                              final isLocked = chromeController.toggleLockMode();
                              if (isLocked) {
                                ttsController.setTtsControlsVisible(false);
                              }
                              break;
                          }
                        },
                        itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
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
                          PopupMenuItem<String>(
                            value: 'crop',
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  pageController.autoCrop ? Icons.crop_free : Icons.crop,
                                  size: 20,
                                  color: pageController.autoCrop ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  pageController.autoCrop ? 'Disable Auto-Crop' : 'Enable Auto-Crop',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: pageController.autoCrop ? theme.colorScheme.primary : theme.colorScheme.onSurface,
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
                                  ttsController.showTtsControls ? Icons.volume_off : Icons.volume_up,
                                  size: 20,
                                  color: ttsController.showTtsControls ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  ttsController.showTtsControls ? 'Stop Listening' : 'Listen (Text-to-Speech)',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: ttsController.showTtsControls ? theme.colorScheme.primary : theme.colorScheme.onSurface,
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
                                  chromeController.isLocked ? Icons.lock_open : Icons.lock_outline,
                                  size: 20,
                                  color: chromeController.isLocked ? theme.colorScheme.primary : theme.colorScheme.onSurface,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  chromeController.isLocked ? 'Unlock Controls' : 'Lock Reader',
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: chromeController.isLocked ? theme.colorScheme.primary : theme.colorScheme.onSurface,
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
              height: 0.5,
              thickness: 0.5,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            ),
          ],
        ),
      ),
    );
  }
}
