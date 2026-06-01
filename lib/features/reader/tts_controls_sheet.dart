import 'package:flutter/material.dart';
import 'package:reader_app/data/services/tts_service.dart';
import 'package:reader_app/data/models/tts_highlight_style.dart';

class TtsControlsSheet extends StatelessWidget {
  final TtsService ttsService;
  final String textToSpeak;
  final String Function()? resolveTextToSpeak;
  final bool isTextLoading;
  final String emptyTextMessage;
  final bool isContinuous;
  final ValueChanged<bool>? onContinuousChanged;
  final bool isFollowMode;
  final ValueChanged<bool>? onFollowModeChanged;
  final bool isTapToStart;
  final ValueChanged<bool>? onTapToStartChanged;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onPause;
  final VoidCallback onClose;
  final TtsHighlightStyle highlightStyle;
  final ValueChanged<TtsHighlightStyle>? onHighlightStyleChanged;

  const TtsControlsSheet({
    super.key,
    required this.ttsService,
    required this.textToSpeak,
    this.resolveTextToSpeak,
    this.isTextLoading = false,
    this.emptyTextMessage = 'No readable text to speak.',
    this.isContinuous = true,
    this.onContinuousChanged,
    this.isFollowMode = true,
    this.onFollowModeChanged,
    this.isTapToStart = true,
    this.onTapToStartChanged,
    this.onStart,
    this.onStop,
    this.onPause,
    required this.onClose,
    this.highlightStyle = TtsHighlightStyle.softPill,
    this.onHighlightStyleChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ttsService,
      builder: (context, _) {
        final isPlaying = ttsService.state == TtsState.playing;
        final isPaused = ttsService.state == TtsState.paused;
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Status & Close Row
                  Row(
                    children: [
                      Icon(
                        isPlaying ? Icons.volume_up : (isPaused ? Icons.volume_mute : Icons.volume_off),
                        size: 16,
                        color: isPlaying ? colorScheme.primary : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isPlaying ? 'Reading Aloud' : (isPaused ? 'Reading Paused' : 'Text to Speech'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isPlaying ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (isTextLoading) ...[
                        const SizedBox(width: 8),
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        ),
                      ],
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () async {
                          onStop?.call();
                          await ttsService.stop();
                          onClose();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Playback and Speed Row
                  Row(
                    children: [
                      // Play/Pause
                      IconButton.filled(
                        icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 22),
                        onPressed: () async {
                          if (isTextLoading) return;
                          if (isPlaying) {
                            onPause?.call();
                            await ttsService.pause();
                            return;
                          }
                          if (isPaused && ttsService.canResume) {
                            await ttsService.resume();
                            return;
                          }
                          final speakText = (resolveTextToSpeak?.call() ?? textToSpeak).trim();
                          if (speakText.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(emptyTextMessage)),
                            );
                            return;
                          }
                          if (onStart != null) {
                            onStart!();
                          } else {
                            await ttsService.speak(speakText);
                          }
                        },
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Stop
                      IconButton.filledTonal(
                        icon: const Icon(Icons.stop, size: 20),
                        onPressed: () async {
                          onStop?.call();
                          await ttsService.stop();
                        },
                        style: IconButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: EdgeInsets.zero,
                          backgroundColor: colorScheme.surfaceContainerHigh,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        width: 1,
                        height: 24,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 12),
                      // Speed Label
                      Text(
                        '${ttsService.rate.toStringAsFixed(1)}x',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      // Speed Slider
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor: colorScheme.primary,
                            inactiveTrackColor: colorScheme.primary.withValues(alpha: 0.12),
                            thumbColor: colorScheme.primary,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                          ),
                          child: Slider(
                            value: ttsService.rate,
                            min: 0.5,
                            max: 2.0,
                            divisions: 15,
                            onChanged: (value) {
                              ttsService.setRate(value);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  // Highlight Style Selector Row
                  if (onHighlightStyleChanged != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.brush,
                          size: 13,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Style:',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Row(
                          children: [
                            _buildStyleChip(
                              context,
                              label: 'Pill',
                              style: TtsHighlightStyle.softPill,
                              currentStyle: highlightStyle,
                              onChanged: onHighlightStyleChanged!,
                            ),
                            const SizedBox(width: 8),
                            _buildStyleChip(
                              context,
                              label: 'Line',
                              style: TtsHighlightStyle.underline,
                              currentStyle: highlightStyle,
                              onChanged: onHighlightStyleChanged!,
                            ),
                            const SizedBox(width: 8),
                            _buildStyleChip(
                              context,
                              label: 'Classic',
                              style: TtsHighlightStyle.classicClean,
                              currentStyle: highlightStyle,
                              onChanged: onHighlightStyleChanged!,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],

                  // Toggle Options Row
                  if (onContinuousChanged != null ||
                      onTapToStartChanged != null ||
                      onFollowModeChanged != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (onContinuousChanged != null)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 4.0),
                              child: _buildCompactToggle(
                                context,
                                icon: Icons.repeat,
                                label: 'Auto-Advance',
                                value: isContinuous,
                                onChanged: onContinuousChanged!,
                              ),
                            ),
                          ),
                        if (onFollowModeChanged != null)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2.0),
                              child: _buildCompactToggle(
                                context,
                                icon: Icons.center_focus_strong,
                                label: 'Auto-Scroll',
                                value: isFollowMode,
                                onChanged: onFollowModeChanged!,
                              ),
                            ),
                          ),
                        if (onTapToStartChanged != null)
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4.0),
                              child: _buildCompactToggle(
                                context,
                                icon: Icons.touch_app,
                                label: 'Tap to Speak',
                                value: isTapToStart,
                                onChanged: onTapToStartChanged!,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildCompactToggle(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        decoration: BoxDecoration(
          color: value 
              ? colorScheme.primaryContainer.withValues(alpha: 0.3) 
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: value 
                ? colorScheme.primary 
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 14,
              color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: value ? FontWeight.bold : FontWeight.w600,
                  color: value ? colorScheme.primary : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStyleChip(
    BuildContext context, {
    required String label,
    required TtsHighlightStyle style,
    required TtsHighlightStyle currentStyle,
    required ValueChanged<TtsHighlightStyle> onChanged,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isSelected = style == currentStyle;

    return InkWell(
      onTap: () => onChanged(style),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primaryContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary
                : colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
            color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
