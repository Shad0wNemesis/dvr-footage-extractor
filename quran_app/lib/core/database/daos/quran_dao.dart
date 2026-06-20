/// Data Access Object for read-only Quran content queries.
///
/// All methods in this DAO are intentionally READ-ONLY. Any attempt to
/// write to the core Quran tables from this DAO is a bug — those tables
/// are owned exclusively by [DatabaseInitializer].
library quran_dao;

import 'package:drift/drift.dart';

import '../quran_database.dart';
import '../tables/quran_tables.dart';

part 'quran_dao.g.dart';

@DriftAccessor(
  tables: [Surahs, Ayahs, WordMorphology, Juzs],
)
class QuranDao extends DatabaseAccessor<QuranDatabase> with _$QuranDaoMixin {
  QuranDao(super.db);

  // ── Surahs ───────────────────────────────────────────────────────────────

  /// Fetch all 114 Surahs ordered by Surah number.
  Future<List<Surah>> allSurahs() =>
      (select(surahs)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  /// Stream that emits the full Surah list and re-emits on any change.
  /// Used by the Surah list screen so the UI stays reactive.
  Stream<List<Surah>> watchAllSurahs() =>
      (select(surahs)..orderBy([(t) => OrderingTerm.asc(t.id)])).watch();

  /// Fetch a single Surah by its canonical number.
  Future<Surah?> surahById(int id) =>
      (select(surahs)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// Fetch all Surahs of a given revelation type.
  Future<List<Surah>> surahsByType(String type) =>
      (select(surahs)..where((t) => t.revelationType.equals(type))).get();

  // ── Ayahs ────────────────────────────────────────────────────────────────

  /// Fetch all Ayahs for a given Surah, ordered by Ayah number.
  Future<List<Ayah>> ayahsByChapter(int surahId) => (select(ayahs)
        ..where((t) => t.surahId.equals(surahId))
        ..orderBy([(t) => OrderingTerm.asc(t.ayahNumber)]))
      .get();

  /// Stream version — auto-updates if the underlying data changes.
  Stream<List<Ayah>> watchAyahsByChapter(int surahId) => (select(ayahs)
        ..where((t) => t.surahId.equals(surahId))
        ..orderBy([(t) => OrderingTerm.asc(t.ayahNumber)]))
      .watch();

  /// Fetch Ayahs belonging to a specific Mus'haf page.
  Future<List<Ayah>> ayahsByPage(int pageNumber) => (select(ayahs)
        ..where((t) => t.pageNumber.equals(pageNumber))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();

  /// Fetch Ayahs belonging to a specific Juz.
  Future<List<Ayah>> ayahsByJuz(int juzNumber) => (select(ayahs)
        ..where((t) => t.juzNumber.equals(juzNumber))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();

  /// Fetch a single Ayah by its composite key (e.g. "2:255").
  Future<Ayah?> ayahByKey(String verseKey) =>
      (select(ayahs)..where((t) => t.verseKey.equals(verseKey)))
          .getSingleOrNull();

  /// Fetch multiple Ayahs by a list of verse_key strings.
  ///
  /// Used after an FTS or vector search returns a ranked list of keys.
  Future<List<Ayah>> ayahsByKeys(List<String> keys) => (select(ayahs)
        ..where((t) => t.verseKey.isIn(keys))
        ..orderBy([(t) => OrderingTerm.asc(t.id)]))
      .get();

  /// Fetch a range of Ayahs (for continuous-scroll reading view).
  Future<List<Ayah>> ayahsInRange({
    required String fromKey,
    required String toKey,
  }) async {
    // Parse keys into (surah, ayah) pairs.
    final from = _parseKey(fromKey);
    final to = _parseKey(toKey);

    return (select(ayahs)
          ..where((t) =>
              t.id.isBiggerOrEqualValue(from.$1 * 1000 + from.$2) &
              t.id.isSmallerOrEqualValue(to.$1 * 1000 + to.$2))
          ..orderBy([(t) => OrderingTerm.asc(t.id)]))
        .get();
  }

  // ── Word Morphology ───────────────────────────────────────────────────────

  /// Fetch all words for a given Ayah, ordered by position.
  Future<List<WordMorphologyData>> wordsForVerse(String verseKey) =>
      (select(wordMorphology)
            ..where((t) => t.verseKey.equals(verseKey))
            ..orderBy([(t) => OrderingTerm.asc(t.wordPosition)]))
          .get();

  // ── Juzs ─────────────────────────────────────────────────────────────────

  Future<List<Juz>> allJuzs() =>
      (select(juzs)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  Future<Juz?> juzById(int id) =>
      (select(juzs)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ── Counts ───────────────────────────────────────────────────────────────

  /// True if the Quran seed has been loaded into the database.
  Future<bool> isSeeded() async {
    final count = await (selectOnly(ayahs)..addColumns([ayahs.id.count()]))
        .map((r) => r.read(ayahs.id.count()))
        .getSingle();
    return (count ?? 0) >= 6236;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Parses "surahId:ayahNumber" into a record.
  (int, int) _parseKey(String key) {
    final parts = key.split(':');
    return (int.parse(parts[0]), int.parse(parts[1]));
  }
}
