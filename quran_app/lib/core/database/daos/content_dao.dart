/// DAO for Tafseer, Translations, Reciters, and Audio Timestamp queries.
library content_dao;

import 'package:drift/drift.dart';

import '../quran_database.dart';
import '../tables/content_tables.dart';

part 'content_dao.g.dart';

@DriftAccessor(
  tables: [
    TafseerSources,
    TafseerTexts,
    TranslationSources,
    TranslationTexts,
    Reciters,
    AudioTimestamps,
  ],
)
class ContentDao extends DatabaseAccessor<QuranDatabase>
    with _$ContentDaoMixin {
  ContentDao(super.db);

  // ── Tafseer ──────────────────────────────────────────────────────────────

  Future<List<TafseerSource>> allTafseerSources() =>
      (select(tafseerSources)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<List<TafseerSource>> bundledTafseerSources() =>
      (select(tafseerSources)
            ..where((t) => t.isBundled.equals(true)))
          .get();

  /// Fetch tafseer text for a given verse and source.
  Future<TafseerText?> tafseerForVerse({
    required String verseKey,
    required int sourceId,
  }) =>
      (select(tafseerTexts)
            ..where((t) =>
                t.verseKey.equals(verseKey) & t.sourceId.equals(sourceId)))
          .getSingleOrNull();

  /// Fetch all tafseer texts for a verse across all installed sources.
  Future<List<TafseerText>> allTafseerForVerse(String verseKey) =>
      (select(tafseerTexts)
            ..where((t) => t.verseKey.equals(verseKey)))
          .get();

  /// Upsert a downloaded tafseer text.
  Future<void> upsertTafseer(TafseerTextsCompanion entry) =>
      into(tafseerTexts).insertOnConflictUpdate(entry);

  // ── Translations ──────────────────────────────────────────────────────────

  Future<List<TranslationSource>> allTranslationSources() =>
      (select(translationSources)
            ..orderBy([(t) => OrderingTerm.asc(t.languageName)]))
          .get();

  Future<TranslationText?> translationForVerse({
    required String verseKey,
    required int translationId,
  }) =>
      (select(translationTexts)
            ..where((t) =>
                t.verseKey.equals(verseKey) &
                t.translationId.equals(translationId)))
          .getSingleOrNull();

  /// Fetch multiple translation texts for a list of keys (batch load).
  Future<List<TranslationText>> translationsForVerses({
    required List<String> verseKeys,
    required int translationId,
  }) =>
      (select(translationTexts)
            ..where((t) =>
                t.verseKey.isIn(verseKeys) &
                t.translationId.equals(translationId)))
          .get();

  // ── Reciters ─────────────────────────────────────────────────────────────

  Future<List<Reciter>> allReciters() =>
      (select(reciters)
            ..orderBy([(t) => OrderingTerm.asc(t.displayName)]))
          .get();

  Future<Reciter?> reciterById(int id) =>
      (select(reciters)..where((t) => t.id.equals(id))).getSingleOrNull();

  // ── Audio Timestamps ──────────────────────────────────────────────────────

  /// Fetch all timestamps for a full Surah's audio file.
  ///
  /// The caller uses the returned list to implement synchronized verse
  /// highlighting: given the current playback position in ms, find the
  /// entry where [timestampFrom] ≤ position < [timestampTo].
  Future<List<AudioTimestamp>> timestampsForSurah({
    required int surahId,
    required int recitationId,
  }) async {
    // Build verse_key prefix: all keys for this surah start with "$surahId:".
    return (select(audioTimestamps)
          ..where((t) =>
              t.verseKey.like('$surahId:%') &
              t.recitationId.equals(recitationId))
          ..orderBy([(t) => OrderingTerm.asc(t.timestampFrom)]))
        .get();
  }

  Future<AudioTimestamp?> timestampForVerse({
    required String verseKey,
    required int recitationId,
  }) =>
      (select(audioTimestamps)
            ..where((t) =>
                t.verseKey.equals(verseKey) &
                t.recitationId.equals(recitationId)))
          .getSingleOrNull();
}
