/// Central Drift database definition for Noor Al-Quran.
///
/// Design decisions:
/// - Single database file containing both Quran content and user data.
///   The two "partitions" are logically separated by DAO layer contracts —
///   content DAOs are read-only, user DAOs are read-write.
/// - We use a *single* Drift [LazyDatabase] opened once at app startup via
///   the Riverpod [databaseProvider]. Drift internally uses a connection pool
///   so all queries are safe from multiple isolates.
/// - FTS5 virtual table (`ayahs_fts`) is created via [onCreate] custom SQL
///   because Drift does not manage virtual tables as first-class entities.
///
/// Code generation: run `flutter pub run build_runner build --delete-conflicting-outputs`
/// to regenerate `quran_database.g.dart`.
library quran_database;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'daos/content_dao.dart';
import 'daos/quran_dao.dart';
import 'daos/user_dao.dart';
import 'tables/content_tables.dart';
import 'tables/quran_tables.dart';
import 'tables/user_tables.dart';

part 'quran_database.g.dart';

// ────────────────────────────────────────────────────────────────────────────
// DATABASE CLASS
// ────────────────────────────────────────────────────────────────────────────

@DriftDatabase(
  tables: [
    // ── Core Quran content (read-only after seed) ──
    Surahs,
    Ayahs,
    WordMorphology,
    Juzs,
    // ── Enrichment content ──
    TafseerSources,
    TafseerTexts,
    TranslationSources,
    TranslationTexts,
    Reciters,
    AudioTimestamps,
    // ── User data (read-write) ──
    UserBookmarks,
    UserNotes,
    ReadingHistory,
    ReadingSessions,
    MemorizationItems,
    RecitationAttempts,
    SearchHistory,
  ],
  daos: [
    QuranDao,
    ContentDao,
    UserDao,
  ],
)
class QuranDatabase extends _$QuranDatabase {
  QuranDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  /// Drift schema version. Increment when adding/altering tables and add a
  /// migration case in [migration].
  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (m) async {
        // Create all Drift-managed tables.
        await m.createAll();

        // ── FTS5 virtual table ──────────────────────────────────────────
        // Allows blazing-fast Arabic keyword search (~1ms for 6,236 rows).
        // Drift does not manage virtual tables; we create it manually here.
        await customStatement('''
          CREATE VIRTUAL TABLE IF NOT EXISTS ayahs_fts
          USING fts5(
            verse_key      UNINDEXED,
            text_uthmani,
            text_simple_clean,
            transliteration,
            content        = 'ayahs',
            content_rowid  = 'id',
            tokenize       = "unicode61 remove_diacritics 1"
          )
        ''');

        // Populate the FTS table from the newly created ayahs table.
        // At init time the ayahs table is empty; DatabaseInitializer will
        // call _rebuildFtsIndex() after bulk-inserting the seed data.
      },

      onUpgrade: (m, from, to) async {
        // Future migration cases go here as the schema evolves.
        // Example for a hypothetical v2:
        // if (from < 2) {
        //   await m.addColumn(userBookmarks, userBookmarks.colorHex);
        // }
      },

      beforeOpen: (details) async {
        // Enable WAL mode for concurrent read performance.
        await customStatement('PRAGMA journal_mode = WAL');
        // Enable foreign-key enforcement (SQLite disables it by default).
        await customStatement('PRAGMA foreign_keys = ON');
        // Tune page cache for a content-heavy DB.
        await customStatement('PRAGMA cache_size = -8000'); // 8 MB
        await customStatement('PRAGMA temp_store = MEMORY');
      },
    );
  }

  // ── FTS index maintenance ─────────────────────────────────────────────────

  /// Rebuilds the FTS5 index from the current `ayahs` table contents.
  ///
  /// Call this once after [DatabaseInitializer] finishes seeding all Ayahs.
  /// The operation is fast (~200ms for 6,236 rows) but must run off the
  /// main thread — the caller is responsible for wrapping in an isolate.
  Future<void> rebuildFtsIndex() async {
    await customStatement("INSERT INTO ayahs_fts(ayahs_fts) VALUES('rebuild')");
  }

  /// Full-text keyword search across Arabic text and transliteration.
  ///
  /// Returns a list of [verse_key] strings ranked by BM25 relevance.
  /// Caller should then fetch full [Ayah] rows using [QuranDao.ayahsByKeys].
  Future<List<String>> searchFts(String query, {int limit = 30}) async {
    // Sanitize: strip double-quotes and wildcard characters to prevent
    // FTS5 query syntax errors from untrusted user input.
    final sanitized = query
        .replaceAll('"', ' ')
        .replaceAll('*', ' ')
        .trim();

    if (sanitized.isEmpty) return const [];

    // Append '*' wildcard to match prefix (e.g. "rahim" matches "rahmaan").
    final ftsQuery = '$sanitized*';

    final rows = await customSelect(
      '''
      SELECT verse_key
      FROM   ayahs_fts
      WHERE  ayahs_fts MATCH ?
      ORDER  BY rank
      LIMIT  ?
      ''',
      variables: [Variable.withString(ftsQuery), Variable.withInt(limit)],
      readsFrom: {ayahs},
    ).get();

    return rows.map((r) => r.read<String>('verse_key')).toList();
  }
}

// ────────────────────────────────────────────────────────────────────────────
// CONNECTION FACTORY
// ────────────────────────────────────────────────────────────────────────────

/// Opens the SQLite connection using drift_flutter's platform-aware adapter.
///
/// On Android/iOS this resolves to the app's Documents directory.
/// On desktop (for development) it resolves to the current directory.
QueryExecutor _openConnection() {
  return driftDatabase(name: 'noor_al_quran');
}

/// Returns the absolute path to the database file.
/// Exposed for diagnostic / backup purposes only.
Future<String> databaseFilePath() async {
  final dir = await getApplicationDocumentsDirectory();
  return p.join(dir.path, 'noor_al_quran.sqlite');
}
