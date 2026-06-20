/// Splash screen shown during first-launch database initialization.
///
/// Displays a real progress bar driven by [DatabaseInitializer]'s event stream.
/// On subsequent launches the DB check is <5ms so this screen is invisible.
library splash_screen;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/initializer/database_initializer.dart';
import '../../core/providers/database_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../core/constants/app_constants.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  double _progress = 0.0;
  String _label = 'Initializing…';
  bool _hasError = false;
  String _errorMessage = '';

  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Start the initialization pipeline after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    final db = ref.read(databaseProvider);

    await for (final event in DatabaseInitializer.initialize(db)) {
      if (!mounted) return;

      switch (event) {
        case InitProgressUpdate(:final fraction, :final label):
          setState(() {
            _progress = fraction;
            _label = label;
          });

        case InitProgressComplete():
          setState(() {
            _progress = 1.0;
            _label = 'Ready!';
          });
          // Brief pause so the user sees the "Ready!" state.
          await Future<void>.delayed(const Duration(milliseconds: 400));
          if (mounted) context.go('/');

        case InitProgressError(:final message):
          setState(() {
            _hasError = true;
            _errorMessage = message;
          });
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo / Arabic name
              FadeTransition(
                opacity: _pulseAnimation,
                child: Column(
                  children: [
                    const Text(
                      'نور القرآن',
                      style: TextStyle(
                        fontFamily: AppConstants.fontUthmanic,
                        fontSize: 42,
                        color: AppColors.gold,
                        letterSpacing: 2,
                      ),
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      AppConstants.appName,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 16,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 64),

              if (_hasError) ...[
                const Icon(Icons.error_outline, color: AppColors.error, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Failed to load Quran data',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _progress = 0;
                      _label = 'Retrying…';
                    });
                    _initialize();
                  },
                  child: const Text('Retry'),
                ),
              ] else ...[
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    backgroundColor: Colors.white12,
                    valueColor:
                        const AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  _label,
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                if (_progress > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${(_progress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
