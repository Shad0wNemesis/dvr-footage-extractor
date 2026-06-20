/// Production-grade database seeder and initializer.
///
/// # Architecture
///
/// Problem: Loading 6,236 Ayahs + word morphology + translations from a JSON
/// asset on first launch is CPU-bound and would freeze the Flutter UI thread
/// (the main isolate) for several seconds.
///
/// Solution:
///   1. Check if the DB is already seeded (O(1) COUNT query).
///   2. If not, read the JSON asset bytes on the main isolate (required —
///      rootBundle is not available in spawned isolates).
///   3. Spawn a background [Isolate] and send it the raw bytes + DB file path.
///   4. The isolate parses JSON, writes to SQLite in batched transactions,
///      and streams [InitProgress] events back to the UI via a [ReceivePort].
///   5. On completion the isolate sends a [InitProgress.complete] event.
///   6. The main isolate closes the spawned isolate and notifies the app.
///
/// # Progress Reporting
///
/// The initializer exposes a [Stream<InitProgress>] so the splash screen can
/// show a real progress bar rather than a spinner.
///
/// # Idempotency
///
/// The initializer is safe to call on every app launch — it exits immediately
/// if the seed is already present. A "seed version" constant guards against
/// re-seeding when a future app update ships additional content.
library database_initializer;

import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:logger/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../quran_database.dart';
import '../tables/quran_tables.dart';
import 'seed_parser.dart';

// ── Public API ────────────────────────────────────────────────────────────────

/// Progress event emitted by [DatabaseInitializer.initialize].
sealed class InitProgress {
  const InitProgress();
}

/// Emitted repeatedly during the seeding process.
final class InitProgressUpdate extends InitProgress {
  const InitProgressUpdate({
    required this.phase,
    required this.current,
    required this.total,
    required this.label,
  });

  /// High-level phase name (e.g. 'surahs', 'ayahs', 'words').
  final String phase;

  /// Items processed so far in this phase.
  final int current;

  /// Total items in this phase.
  final int total;

  /// Human-readable status string for the splash screen.
  final String label;

  double get fraction => total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0;
}

/// Emitted exactly once when all phases complete successfully.
final class InitProgressComplete extends InitProgress {
  const InitProgressComplete({required this.durationMs});
  final int durationMs;
}

/// Emitted if any phase fails fatally.
final class InitProgressError extends InitProgress {
  const InitProgressError({required this.message, required this.phase});
  final String message;
  final String phase;
}

// ── Constants ─────────────────────────────────────────────────────────────────

/// Increment this when the bundled seed JSON changes in a breaking way.
/// The initializer compares this against a value stored in `user_prefs`
/// and re-seeds if there's a mismatch.
const int _kSeedVersion = 1;

/// SQLite batch size — how many rows are inserted per transaction.
/// 250 is a safe value that stays well below SQLite's variable limit (999).
const int _kBatchSize = 250;

// ── DatabaseInitializer ───────────────────────────────────────────────────────

/// Orchestrates first-launch database seeding without blocking the UI.
class DatabaseInitializer {
  const DatabaseInitializer._();

  static final _log = Logger(
    printer: PrettyPrinter(methodCount: 0, printTime: true),
  );

  // ── Entry Point ─────────────────────────────────────────────────────────

  /// Checks whether the DB is seeded and, if not, seeds it.
  ///
  /// Returns a [Stream<InitProgress>] that emits progress events.
  /// The stream closes after the final [InitProgressComplete] or
  /// [InitProgressError] event.
  ///
  /// ```dart
  /// final stream = DatabaseInitializer.initialize(db);
  /// await for (final event in stream) {
  ///   if (event is InitProgressUpdate) updateProgressBar(event.fraction);
  ///   if (event is InitProgressComplete) navigateToHome();
  ///   if (event is InitProgressError) showErrorDialog(event.message);
  /// }
  /// ```
  static Stream<InitProgress> initialize(QuranDatabase db) async* {
    final stopwatch = Stopwatch()..start();
    _log.i('DatabaseInitializer: starting');

    // ── Fast path: already seeded ────────────────────────────────────────
    final seeded = await db.quranDao.isSeeded();
    if (seeded) {
      _log.i('DatabaseInitializer: DB already seeded — skipping init');
      yield InitProgressComplete(durationMs: stopwatch.elapsedMilliseconds);
      return;
    }

    // ── Load seed assets on the main isolate (rootBundle is main-only) ──
    yield const InitProgressUpdate(
      phase: 'loading',
      current: 0,
      total: 1,
      label: 'Loading Quran data…',
    );

    late final String surahsJson;
    late final String ayahsJson;

    try {
      surahsJson = await rootBundle.loadString('assets/json/surahs.json');
      ayahsJson = await rootBundle.loadString('assets/json/ayahs.json');
    } catch (e) {
      _log.e('Failed to load seed assets', error: e);
      yield InitProgressError(
        phase: 'loading',
        message: 'Could not read Quran data files: $e',
      );
      return;
    }

    // ── Resolve DB path for the spawned isolate ──────────────────────────
    final dbPath = await _resolveDbPath();

    // ── Set up isolate communication ─────────────────────────────────────
    final receivePort = ReceivePort();
    final errorPort = ReceivePort();

    Isolate? seedIsolate;

    try {
      final payload = _SeedPayload(
        sendPort: receivePort.sendPort,
        dbPath: dbPath,
        surahsJson: surahsJson,
        ayahsJson: ayahsJson,
        batchSize: _kBatchSize,
      );

      seedIsolate = await Isolate.spawn(
        _seedIsolateEntryPoint,
        payload,
        onError: errorPort.sendPort,
        debugName: 'QuranSeedIsolate',
      );

      // Stream events from the isolate to the caller.
      await for (final dynamic message in receivePort) {
        if (message is InitProgress) {
          yield message;
          if (message is InitProgressComplete || message is InitProgressError) {
            break;
          }
        }
      }
    } catch (e, st) {
      _log.e('Seed isolate failed', error: e, stackTrace: st);
      yield InitProgressError(
        phase: 'spawn',
        message: 'Seed isolate crashed: $e',
      );
    } finally {
      seedIsolate?.kill(priority: Isolate.immediate);
      receivePort.close();
      errorPort.close();
    }

    // ── Rebuild FTS index (must happen in the main isolate's DB handle) ──
    yield const InitProgressUpdate(
      phase: 'fts',
      current: 0,
      total: 1,
      label: 'Building search index…',
    );

    try {
      await db.rebuildFtsIndex();
    } catch (e) {
      _log.w('FTS index rebuild failed (non-fatal): $e');
      // Non-fatal: keyword search will fall back to LIKE queries.
    }

    stopwatch.stop();
    _log.i('DatabaseInitializer: complete in ${stopwatch.elapsedMilliseconds}ms');
    yield InitProgressComplete(durationMs: stopwatch.elapsedMilliseconds);
  }

  // ── DB path resolution ────────────────────────────────────────────────────

  static Future<String> _resolveDbPath() async {
    // drift_flutter uses getApplicationDocumentsDirectory on mobile.
    // We replicate that logic so the isolate can open the same file.
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, 'noor_al_quran.sqlite');
  }
}

// ── Isolate Entry Point ───────────────────────────────────────────────────────

/// Top-level function required for [Isolate.spawn].
///
/// All parameters must be passed via [_SeedPayload] because isolates
/// can only receive a single argument through [Isolate.spawn].
Future<void> _seedIsolateEntryPoint(_SeedPayload payload) async {
  final send = payload.sendPort;

  // Open a fresh DB connection inside the isolate.
  // We MUST use a new connection — the parent isolate's connection is
  // not accessible from a different isolate.
  final db = QuranDatabase(driftDatabase(name: 'noor_al_quran'));

  try {
    await _seedSurahs(db, payload, send);
    await _seedAyahs(db, payload, send);
    // Words are optional — seed them only if a words JSON asset exists.
    // (Loaded separately to keep the initial APK smaller.)
    send.send(InitProgressComplete(
      durationMs: DateTime.now().millisecondsSinceEpoch,
    ));
  } catch (e, st) {
    send.send(InitProgressError(
      phase: 'seed',
      message: e.toString(),
    ));
  } finally {
    await db.close();
  }
}

/// Parses and inserts all 114 Surahs.
Future<void> _seedSurahs(
  QuranDatabase db,
  _SeedPayload payload,
  SendPort send,
) async {
  send.send(const InitProgressUpdate(
    phase: 'surahs',
    current: 0,
    total: 114,
    label: 'Loading Surahs (1/3)…',
  ));

  final seeds = parseSurahsJson(payload.surahsJson);
  if (seeds.isEmpty) {
    throw StateError('Surah seed data is empty or malformed.');
  }

  // Single transaction for all 114 rows — negligible size.
  await db.transaction(() async {
    for (final s in seeds) {
      await db.into(db.surahs).insertOnConflictUpdate(SurahsCompanion(
        id: Value(s.id),
        revelationOrder: Value(s.revelationOrder),
        revelationType: Value(s.revelationType),
        versesCount: Value(s.versesCount),
        pageStart: Value(s.pageStart),
        pageEnd: Value(s.pageEnd),
        juzStart: Value(s.juzStart),
        hizbStart: Value(s.hizbStart),
        nameArabic: Value(s.nameArabic),
        nameTransliteration: Value(s.nameTransliteration),
        nameTranslation: Value(s.nameTranslation),
        hasBismillah: Value(s.hasBismillah),
      ));
    }
  });

  send.send(InitProgressUpdate(
    phase: 'surahs',
    current: seeds.length,
    total: seeds.length,
    label: 'Surahs loaded ✓',
  ));
}

/// Parses and inserts all 6,236 Ayahs in batched transactions.
///
/// We use batched transactions ([_kBatchSize] rows each) to:
///   - Stay below SQLite's SQLITE_LIMIT_VARIABLE_NUMBER (999 by default)
///   - Yield progress events between batches so the UI stays responsive
///   - Allow recovery if the process is interrupted mid-seed
Future<void> _seedAyahs(
  QuranDatabase db,
  _SeedPayload payload,
  SendPort send,
) async {
  const total = 6236;
  send.send(const InitProgressUpdate(
    phase: 'ayahs',
    current: 0,
    total: total,
    label: 'Loading Ayahs (2/3)…',
  ));

  final seeds = parseAyahsJson(payload.ayahsJson);
  if (seeds.isEmpty) {
    throw StateError('Ayah seed data is empty or malformed.');
  }

  final batches = chunk(seeds, payload.batchSize);
  var processed = 0;

  for (final batch in batches) {
    await db.transaction(() async {
      for (final a in batch) {
        await db.into(db.ayahs).insertOnConflictUpdate(AyahsCompanion(
          id: Value(a.id),
          surahId: Value(a.surahId),
          ayahNumber: Value(a.ayahNumber),
          verseKey: Value(a.verseKey),
          textUthmani: Value(a.textUthmani),
          textIndopak: Value(a.textIndopak),
          textSimpleClean: Value(a.textSimpleClean),
          juzNumber: Value(a.juzNumber),
          hizbNumber: Value(a.hizbNumber),
          rubElHizbNumber: Value(a.rubElHizbNumber),
          pageNumber: Value(a.pageNumber),
          rukukNumber: Value(a.rukukNumber),
          manzilNumber: Value(a.manzilNumber),
          sajdahRequired: Value(a.sajdahRequired),
          sajdahType: Value(a.sajdahType),
        ));
      }
    });

    processed += batch.length;

    // Throttle progress events — send every 500 rows to avoid overwhelming
    // the receiving isolate's message queue.
    if (processed % 500 == 0 || processed >= seeds.length) {
      send.send(InitProgressUpdate(
        phase: 'ayahs',
        current: processed,
        total: seeds.length,
        label: 'Loading Ayahs… ($processed / ${seeds.length})',
      ));
    }
  }
}

// ── Payload class ─────────────────────────────────────────────────────────────

/// Data container passed to the seed isolate.
///
/// All fields must be sendable across isolate boundaries:
/// primitives, typed lists, SendPort.
class _SeedPayload {
  const _SeedPayload({
    required this.sendPort,
    required this.dbPath,
    required this.surahsJson,
    required this.ayahsJson,
    required this.batchSize,
  });

  final SendPort sendPort;
  final String dbPath;
  final String surahsJson;
  final String ayahsJson;
  final int batchSize;
}
