import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/constants/app_constants.dart';
import 'core/database/quran_database.dart';
import 'core/providers/database_provider.dart';
import 'core/providers/settings_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ── System UI ──────────────────────────────────────────────────────────
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  // ── Background Audio ───────────────────────────────────────────────────
  await JustAudioBackground.init(
    androidNotificationChannelId: AppConstants.audioChannelId,
    androidNotificationChannelName: AppConstants.audioChannelName,
    androidNotificationOngoing: true,
    androidStopForegroundOnPause: true,
  );

  // ── Persistent Storage ─────────────────────────────────────────────────
  final prefs = await SharedPreferences.getInstance();

  // ── Drift Database ─────────────────────────────────────────────────────
  // Open the DB connection BEFORE ProviderScope so every provider that
  // reads [databaseProvider] gets the same live connection.
  final db = QuranDatabase();

  runApp(
    ProviderScope(
      overrides: [
        // Override the lazy-placeholder with the real instance.
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
      child: const QuranApp(),
    ),
  );
}
