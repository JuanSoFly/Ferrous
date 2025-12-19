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
  final bool isTapToStart;
  final ValueChanged<bool>? onTapToStartChanged;
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
    this.isTapToStart = true,
    this.onTapToStartChanged,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ttsService,
      builder: (context, _) {
        final isPlaying = ttsService.state == TtsState.playing;

        return Material(
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Play/Pause Button
                    IconButton(
                      icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
                      iconSize: 40,
                      onPressed: () async {
                        final speakText =
                            (resolveTextToSpeak?.call() ?? textToSpeak).trim();
                        final canSpeak = speakText.isNotEmpty;

                        if (isTextLoading) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Preparing text for TTS...'),
                            ),
                          );
                          return;
                        }

                        if (!canSpeak) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(emptyTextMessage)),
                          );
                          return;
                        }

                        if (isPlaying) {
                          await ttsService.pause();
                        } else {
                          await ttsService.speak(speakText);
                        }
                      },
                    ),
                    if (isTextLoading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    // Stop Button
                    IconButton(
                      icon: const Icon(Icons.stop),
                      iconSize: 40,
                      onPressed: () async {
                        await ttsService.stop();
                      },
                    ),
                    // Speed Control
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${ttsService.rate.toStringAsFixed(1)}x'),
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
                      ],
                    ),
                    // Close Button
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        await ttsService.stop();
                        onClose();
                      },
                    ),
                  ],
                ),
                if (onContinuousChanged != null || onTapToStartChanged != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 24,
                      runSpacing: 8,
                      children: [
                        if (onContinuousChanged != null)
                          _buildToggle(
                            icon: Icons.repeat,
                            label: 'Continuous',
                            value: isContinuous,
                            onChanged: onContinuousChanged!,
                          ),
                        if (onTapToStartChanged != null)
                          _buildToggle(
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

  Widget _buildToggle({
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
        const SizedBox(width: 8),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
