import 'package:flutter/material.dart';
import 'package:reader_app/data/services/tts_service.dart';

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
  final VoidCallback? onStop;
  final VoidCallback? onPause;
  final VoidCallback onClose;

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
    this.onStop,
    this.onPause,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ttsService,
      builder: (context, _) {
        final isPlaying = ttsService.state == TtsState.playing;
        final isPaused = ttsService.state == TtsState.paused;

        return Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                      tooltip: isPlaying ? 'Pause' : 'Play',
                      onPressed: () async {
                        if (isTextLoading) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Preparing text for TTS...'),
                            ),
                          );
                          return;
                        }

                        if (isPlaying) {
                          onPause?.call();
                          await ttsService.pause();
                          return;
                        }

                        if (isPaused && ttsService.canResume) {
                          await ttsService.resume();
                          return;
                        }

                        final speakText =
                            (resolveTextToSpeak?.call() ?? textToSpeak).trim();
                        if (speakText.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(emptyTextMessage)),
                          );
                          return;
                        }

                        await ttsService.speak(speakText);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.stop),
                      tooltip: 'Stop',
                      onPressed: () async {
                        onStop?.call();
                        await ttsService.stop();
                      },
                    ),
                    if (isTextLoading)
                      const Padding(
                        padding: EdgeInsets.only(left: 4.0),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    const Spacer(),
                    Text('${ttsService.rate.toStringAsFixed(1)}x'),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 120,
                      child: Slider(
                        value: ttsService.rate,
                        min: 0.5,
                        max: 2.0,
                        divisions: 6,
                        onChanged: (value) async {
                          await ttsService.setRate(value);
                        },
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'Close',
                      onPressed: () async {
                        onStop?.call();
                        await ttsService.stop();
                        onClose();
                      },
                    ),
                  ],
                ),
                if (onContinuousChanged != null ||
                    onTapToStartChanged != null ||
                    onFollowModeChanged != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (onContinuousChanged != null)
                          _buildToggleChip(
                            icon: Icons.repeat,
                            label: 'Continuous',
                            value: isContinuous,
                            onChanged: onContinuousChanged!,
                          ),
                        if (onFollowModeChanged != null)
                          _buildToggleChip(
                            icon: Icons.center_focus_strong,
                            label: 'Follow',
                            value: isFollowMode,
                            onChanged: onFollowModeChanged!,
                          ),
                        if (onTapToStartChanged != null)
                          _buildToggleChip(
                            icon: Icons.touch_app,
                            label: 'Tap to start',
                            value: isTapToStart,
                            onChanged: onTapToStartChanged!,
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildToggleChip({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return FilterChip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      selected: value,
      onSelected: onChanged,
    );
  }
}
