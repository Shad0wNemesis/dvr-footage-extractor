import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/audio_provider.dart';

class MiniPlayerWidget extends ConsumerWidget {
  const MiniPlayerWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioProvider);
    final notifier = ref.read(audioProvider.notifier);
    if (!audio.isPlaying && audio.currentVerseKey == null && !audio.isLoading) {
      return const SizedBox.shrink();
    }

    final progress = audio.duration.inMilliseconds > 0
        ? audio.position.inMilliseconds / audio.duration.inMilliseconds
        : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            backgroundColor: Colors.white.withOpacity(0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            minHeight: 2,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.quran, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        audio.currentSurahId != null
                            ? 'Surah ${audio.currentSurahId}'
                            : audio.currentVerseKey ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${_formatDuration(audio.position)} / ${_formatDuration(audio.duration)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        final newMode = RepeatMode.values[
                            (audio.repeatMode.index + 1) % RepeatMode.values.length];
                        notifier.setRepeatMode(newMode);
                      },
                      icon: Icon(
                        _repeatIcon(audio.repeatMode),
                        color: audio.repeatMode == RepeatMode.none
                            ? Colors.white54
                            : Colors.white,
                        size: 20,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    if (audio.isLoading)
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      IconButton(
                        onPressed: audio.isPlaying
                            ? notifier.pause
                            : notifier.resume,
                        icon: Icon(
                          audio.isPlaying ? Icons.pause_circle : Icons.play_circle,
                          color: Colors.white,
                          size: 36,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                    IconButton(
                      onPressed: notifier.stop,
                      icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _repeatIcon(RepeatMode mode) {
    switch (mode) {
      case RepeatMode.none: return Icons.repeat;
      case RepeatMode.verse: return Icons.repeat_one;
      case RepeatMode.surah: return Icons.repeat_on;
    }
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
