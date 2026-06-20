/// Tajweed recitation checker screen.
///
/// Pipeline:
/// 1. Display the target Ayah (Arabic text)
/// 2. User taps the mic button to start recording
/// 3. `record` package captures PCM WAV audio at 16 kHz
/// 4. On stop, WAV bytes are base64-encoded and sent to the AI microservice
/// 5. `faster-whisper` transcribes the audio; heuristic Tajweed evaluator
///    computes an accuracy score
/// 6. Result displayed: accuracy ring, transcription, per-error list
///
/// Requirements:
///   pubspec.yaml → record: ^5.1.0
///   Android: <uses-permission android:name="android.permission.RECORD_AUDIO" />
///   iOS: NSMicrophoneUsageDescription in Info.plist
library recitation_screen;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' as drift;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../../../core/ai/ai_service_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/database/daos/quran_dao.dart';
import '../../../core/database/daos/user_dao.dart';
import '../../../core/database/tables/user_tables.dart';
import '../../../core/providers/ai_service_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_colors.dart';

// ── State enum ────────────────────────────────────────────────────────────────

enum _RecState { idle, recording, evaluating, result, error }

// ── Screen ────────────────────────────────────────────────────────────────────

class RecitationScreen extends ConsumerStatefulWidget {
  const RecitationScreen({super.key, required this.verseKey});
  final String verseKey;

  @override
  ConsumerState<RecitationScreen> createState() => _RecitationScreenState();
}

class _RecitationScreenState extends ConsumerState<RecitationScreen> {
  final _recorder = AudioRecorder();

  _RecState _state = _RecState.idle;
  AiRecitationResponse? _result;
  String? _errorMessage;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  // ── Recording lifecycle ────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Microphone permission required for recitation evaluation.'),
          ),
        );
      }
      return;
    }

    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.wav';

    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000),
      path: path,
    );

    setState(() => _state = _RecState.recording);
  }

  Future<void> _stopAndEvaluate() async {
    final path = await _recorder.stop();
    if (path == null) {
      setState(() {
        _state = _RecState.error;
        _errorMessage = 'Recording failed — no audio was captured.';
      });
      return;
    }

    setState(() => _state = _RecState.evaluating);

    try {
      final bytes = await File(path).readAsBytes();
      final client = ref.read(aiServiceClientProvider);

      final response = await client.evaluateRecitation(
        verseKey: widget.verseKey,
        audioBytes: bytes,
        audioFormat: 'wav',
      );

      // Persist to Drift DB.
      await ref.read(userDaoProvider).saveRecitationAttempt(
            RecitationAttemptsCompanion(
              verseKey: drift.Value(widget.verseKey),
              attemptedAt: drift.Value(DateTime.now()),
              accuracyScore: drift.Value(response.accuracyScore),
              transcription: drift.Value(response.transcription),
              tajweedErrorsJson: drift.Value(_encodeErrors(response.tajweedErrors)),
              durationMs: drift.Value(response.totalMs.round()),
              passed: drift.Value(response.passed),
            ),
          );

      if (mounted) {
        setState(() {
          _result = response;
          _state = _RecState.result;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _RecState.error;
          _errorMessage = e.toString();
        });
      }
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  String _encodeErrors(List<AiTajweedError> errors) {
    final parts = errors.map((e) =>
        '{"word_position":${e.wordPosition},'
        '"rule_name":"${e.ruleName}",'
        '"severity":"${e.severity}"}');
    return '[${parts.join(',')}]';
  }

  void _reset() => setState(() {
        _state = _RecState.idle;
        _result = null;
        _errorMessage = null;
      });

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final quranDao = ref.watch(quranDaoProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Recitation — ${widget.verseKey}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: FutureBuilder<Ayah?>(
        future: quranDao.ayahByKey(widget.verseKey),
        builder: (context, snap) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _VerseCard(ayah: snap.data, verseKey: widget.verseKey),
                const SizedBox(height: 28),
                switch (_state) {
                  _RecState.idle       => _IdlePanel(onStart: _startRecording),
                  _RecState.recording  => _RecordingPanel(onStop: _stopAndEvaluate),
                  _RecState.evaluating => const _EvaluatingPanel(),
                  _RecState.result     => _ResultPanel(result: _result!, onRetry: _reset),
                  _RecState.error      => _ErrorPanel(message: _errorMessage ?? 'Unknown error', onRetry: _reset),
                },
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Verse display card ────────────────────────────────────────────────────────

class _VerseCard extends StatelessWidget {
  const _VerseCard({required this.ayah, required this.verseKey});
  final Ayah? ayah;
  final String verseKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              verseKey,
              style: const TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (ayah != null) ...[
            Text(
              ayah!.textUthmani,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppConstants.fontUthmanic,
                fontSize: 22,
                height: 2.0,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              ayah!.textSimpleClean,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.lightTextSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ] else
            const SizedBox(
              height: 60,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

// ── State panels ──────────────────────────────────────────────────────────────

class _IdlePanel extends StatelessWidget {
  const _IdlePanel({required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Recite the verse above, then tap the microphone.',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.lightTextSecondary),
        ),
        const SizedBox(height: 32),
        _MicButton(isRecording: false, onPressed: onStart),
        const SizedBox(height: 12),
        const Text('Tap to start',
            style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 13)),
      ],
    );
  }
}

class _RecordingPanel extends StatelessWidget {
  const _RecordingPanel({required this.onStop});
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text('Recording… speak clearly.',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 32),
        _MicButton(isRecording: true, onPressed: onStop),
        const SizedBox(height: 12),
        const Text('Tap to stop',
            style: TextStyle(color: AppColors.lightTextSecondary, fontSize: 13)),
      ],
    );
  }
}

class _EvaluatingPanel extends StatelessWidget {
  const _EvaluatingPanel();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        CircularProgressIndicator(),
        SizedBox(height: 16),
        Text('Evaluating Tajweed…',
            style: TextStyle(fontWeight: FontWeight.w600)),
        SizedBox(height: 6),
        Text(
          'Whisper is transcribing and checking Tajweed rules.',
          textAlign: TextAlign.center,
          style:
              TextStyle(color: AppColors.lightTextSecondary, fontSize: 12),
        ),
      ],
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result, required this.onRetry});
  final AiRecitationResponse result;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final pct = (result.accuracyScore * 100).round();
    final color = result.passed ? AppColors.success : AppColors.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Accuracy ring
        Center(
          child: SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: result.accuracyScore,
                  strokeWidth: 10,
                  backgroundColor: color.withOpacity(0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$pct%',
                        style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: color)),
                    Text(result.passed ? 'Passed' : 'Try again',
                        style: TextStyle(fontSize: 11, color: color)),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 20),

        // Transcription
        _InfoRow(
          icon: Icons.mic,
          label: 'Transcription',
          body: result.transcription.isNotEmpty
              ? result.transcription
              : '(no speech detected)',
          rtl: true,
        ),

        const SizedBox(height: 12),

        // Errors
        if (result.tajweedErrors.isNotEmpty) ...[
          const Text('Tajweed Errors',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
          ...result.tajweedErrors
              .map((e) => _TajweedTile(error: e)),
        ] else
          _GreenBanner(text: 'No Tajweed errors detected'),

        const SizedBox(height: 16),

        Text(
          'STT ${result.sttMs.toStringAsFixed(0)} ms  •  '
          'Eval ${result.evalMs.toStringAsFixed(0)} ms',
          textAlign: TextAlign.center,
          style: const TextStyle(
              fontSize: 11, color: AppColors.lightTextSecondary),
        ),

        const SizedBox(height: 20),

        OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Try Again'),
        ),
      ],
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Icon(Icons.error_outline, size: 48, color: AppColors.error),
        const SizedBox(height: 12),
        const Text('Evaluation failed',
            style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: AppColors.lightTextSecondary, fontSize: 12)),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('Retry'),
        ),
      ],
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _MicButton extends StatelessWidget {
  const _MicButton({required this.isRecording, required this.onPressed});
  final bool isRecording;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final color = isRecording ? AppColors.error : AppColors.primary;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: isRecording ? 24 : 10,
              spreadRadius: isRecording ? 4 : 0,
            ),
          ],
        ),
        child: Icon(
          isRecording ? Icons.stop_rounded : Icons.mic,
          color: Colors.white,
          size: 36,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.body,
    this.rtl = false,
  });
  final IconData icon;
  final String label;
  final String body;
  final bool rtl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardTheme.color,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: theme.colorScheme.outline.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppColors.lightTextSecondary),
              const SizedBox(width: 4),
              Text(label,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.lightTextSecondary,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: theme.textTheme.bodyMedium,
            textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          ),
        ],
      ),
    );
  }
}

class _TajweedTile extends StatelessWidget {
  const _TajweedTile({required this.error});
  final AiTajweedError error;

  Color get _color => switch (error.severity) {
        'critical' => AppColors.error,
        'major' => AppColors.warning,
        _ => AppColors.info,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                error.severity,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: _color,
                    letterSpacing: 0.5),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(error.ruleName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  if (error.expected.isNotEmpty)
                    Text(
                      'Expected: ${error.expected}  •  Heard: ${error.detected}',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.lightTextSecondary),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GreenBanner extends StatelessWidget {
  const _GreenBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.success.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline,
              color: AppColors.success, size: 18),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(
                  color: AppColors.success, fontSize: 13)),
        ],
      ),
    );
  }
}
