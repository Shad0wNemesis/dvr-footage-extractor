/// AR Mus'haf Scanner screen.
///
/// Uses the device camera to detect the current Mus'haf page number in
/// real-time and overlays an interactive panel showing the page number.
/// The user can tap "Open in Reader" to jump directly to that page in the
/// Quran reader screen.
///
/// Vision pipeline:
///   Camera frame → JPEG encode → base64 → POST /api/vision
///   → DetectedPage + YOLO bounding boxes → overlay UI
///
/// Frames are sampled every 2 s to avoid overloading the AI service.
library ar_scanner_screen;

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_service_client.dart';
import '../../../core/providers/ai_service_provider.dart';
import '../../../core/theme/app_colors.dart';

class ARScannerScreen extends ConsumerStatefulWidget {
  const ARScannerScreen({super.key});

  @override
  ConsumerState<ARScannerScreen> createState() => _ARScannerScreenState();
}

class _ARScannerScreenState extends ConsumerState<ARScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];

  bool _cameraInitialized = false;
  bool _isProcessingFrame = false;

  AiVisionResponse? _lastResult;
  String? _cameraError;

  Timer? _frameSampleTimer;

  static const _kSampleInterval = Duration(seconds: 2);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _frameSampleTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;

    if (state == AppLifecycleState.inactive) {
      _frameSampleTimer?.cancel();
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _cameraError = 'No cameras found on this device.');
        return;
      }

      final controller = CameraController(
        _cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      if (!mounted) return;

      setState(() {
        _cameraController = controller;
        _cameraInitialized = true;
        _cameraError = null;
      });

      // Start periodic frame sampling.
      _frameSampleTimer = Timer.periodic(_kSampleInterval, (_) => _captureAndAnalyse());
    } catch (e) {
      setState(() => _cameraError = 'Camera error: $e');
    }
  }

  Future<void> _captureAndAnalyse() async {
    final controller = _cameraController;
    if (controller == null ||
        !controller.value.isInitialized ||
        _isProcessingFrame) return;

    _isProcessingFrame = true;

    try {
      final xFile = await controller.takePicture();
      final bytes = await xFile.readAsBytes();

      final previewSize = controller.value.previewSize;
      final width = previewSize?.width.round() ?? 640;
      final height = previewSize?.height.round() ?? 480;

      final client = ref.read(aiServiceClientProvider);
      final result = await client.detectMushaafPage(
        imageBytes: Uint8List.fromList(bytes),
        imageWidth: width,
        imageHeight: height,
      );

      if (mounted && result.detectedPage != null) {
        setState(() => _lastResult = result);
      }
    } catch (_) {
      // Silently swallow per-frame errors — the next sample will retry.
    } finally {
      _isProcessingFrame = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAiOnline = ref.watch(aiServiceHealthProvider).valueOrNull ?? false;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // ── Camera preview ──────────────────────────────────────────────
            if (_cameraError != null)
              _CameraErrorOverlay(message: _cameraError!)
            else if (!_cameraInitialized)
              const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 12),
                    Text('Initialising camera…',
                        style: TextStyle(color: Colors.white70)),
                  ],
                ),
              )
            else
              Positioned.fill(
                child: CameraPreview(_cameraController!),
              ),

            // ── Top bar ─────────────────────────────────────────────────────
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopBar(
                isAiOnline: isAiOnline,
                onClose: () => context.pop(),
              ),
            ),

            // ── Page detection overlay ───────────────────────────────────────
            if (_lastResult?.detectedPage != null)
              Positioned(
                bottom: 40,
                left: 20,
                right: 20,
                child: _DetectionBanner(
                  result: _lastResult!,
                  onNavigate: () => _navigateToPage(_lastResult!.detectedPage!),
                ),
              ),

            // ── Scanning indicator ───────────────────────────────────────────
            if (_cameraInitialized && _lastResult == null)
              const Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: _ScanningHint(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToPage(int pageNumber) {
    // Navigate to the Quran reader at the given page.
    // Page → Surah/Verse mapping requires a DB lookup; for now we pass
    // the page number as a query parameter and let the reader resolve it.
    context.push('/quran/page/$pageNumber');
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.isAiOnline, required this.onClose});
  final bool isAiOnline;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black.withOpacity(0.8), Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: onClose,
          ),
          const Expanded(
            child: Text(
              'Mus\'haf Scanner',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          // AI status indicator
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (isAiOnline ? AppColors.success : AppColors.error)
                  .withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isAiOnline ? AppColors.success : AppColors.error)
                    .withOpacity(0.5),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isAiOnline ? Icons.memory : Icons.wifi_off,
                  size: 12,
                  color: isAiOnline ? AppColors.success : AppColors.error,
                ),
                const SizedBox(width: 4),
                Text(
                  isAiOnline ? 'AI Online' : 'AI Offline',
                  style: TextStyle(
                    color: isAiOnline ? AppColors.success : AppColors.error,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Detection banner ──────────────────────────────────────────────────────────

class _DetectionBanner extends StatelessWidget {
  const _DetectionBanner({required this.result, required this.onNavigate});
  final AiVisionResponse result;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final confidencePct = (result.confidence * 100).round();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.85),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.6)),
      ),
      child: Row(
        children: [
          // Page number display
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.2),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: Center(
              child: Text(
                '${result.detectedPage}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),

          const SizedBox(width: 14),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Page Detected',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'Mus\'haf Page ${result.detectedPage}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Confidence: $confidencePct%  •  ${result.inferenceMs.toStringAsFixed(0)} ms',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          FilledButton(
            onPressed: onNavigate,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            child: const Text('Open', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _ScanningHint extends StatelessWidget {
  const _ScanningHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.primaryLight,
            ),
          ),
          SizedBox(width: 10),
          Text(
            'Point at a Mus\'haf page to scan',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _CameraErrorOverlay extends StatelessWidget {
  const _CameraErrorOverlay({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.camera_alt, size: 56, color: Colors.white38),
            const SizedBox(height: 16),
            const Text('Camera Unavailable',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}
