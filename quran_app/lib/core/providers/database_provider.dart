/// Riverpod providers for the Drift database and its DAOs.
///
/// Single source of truth: every widget/provider in the app accesses the DB
/// through these providers — never by constructing [QuranDatabase] directly.
///
/// The [databaseProvider] is overridden at the [ProviderScope] root with the
/// concrete instance created in [main.dart] after initialization completes.
library database_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../database/daos/content_dao.dart';
import '../database/daos/quran_dao.dart';
import '../database/daos/user_dao.dart';
import '../database/quran_database.dart';

// ── Root provider ──────────────────────────────────────────────────────────

/// The single [QuranDatabase] instance for the lifetime of the app.
///
/// Must be overridden at the [ProviderScope] root:
/// ```dart
/// ProviderScope(
///   overrides: [databaseProvider.overrideWithValue(db)],
///   child: const QuranApp(),
/// )
/// ```
final databaseProvider = Provider<QuranDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider must be overridden at app startup. '
    'See main.dart → ProviderScope overrides.',
  );
});

// ── DAO providers ──────────────────────────────────────────────────────────

/// Provides [QuranDao] — read-only access to core Quran content.
final quranDaoProvider = Provider<QuranDao>((ref) {
  return ref.watch(databaseProvider).quranDao;
});

/// Provides [ContentDao] — Tafseer, Translations, Reciters, Timestamps.
final contentDaoProvider = Provider<ContentDao>((ref) {
  return ref.watch(databaseProvider).contentDao;
});

/// Provides [UserDao] — Bookmarks, Notes, SRS, History.
final userDaoProvider = Provider<UserDao>((ref) {
  return ref.watch(databaseProvider).userDao;
});

// ── Convenience stream providers ───────────────────────────────────────────

/// Reactive stream of all Surahs — auto-updates if the DB changes.
final surahListStreamProvider = StreamProvider((ref) {
  return ref.watch(quranDaoProvider).watchAllSurahs();
});

/// Reactive stream of all user bookmarks.
final bookmarksStreamProvider = StreamProvider((ref) {
  return ref.watch(userDaoProvider).watchAllBookmarks();
});

/// Reactive stream of today's memorization items due for review.
final dueTodayProvider = StreamProvider((ref) {
  return ref.watch(userDaoProvider).watchDueTodayItems();
});
