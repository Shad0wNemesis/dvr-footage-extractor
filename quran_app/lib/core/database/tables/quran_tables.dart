/// Quran core content tables.
///
/// These tables are READ-ONLY after seeding — they are sourced from the
/// bundled SQLite asset and never mutated at runtime. Drift generates
/// fully-typed row classes and query helpers for each table.
library quran_tables;

import 'package:drift/drift.dart';

// ────────────────────────────────────────────────────────────────────────────
// SURAHS
// ────────────────────────────────────────────────────────────────────────────

/// Metadata for all 114 Surahs.
///
/// Primary key is the canonical Surah number (1–114).
class Surahs extends Table {
  /// Canonical Surah number (1–114).
  IntColumn get id => integer()();

  /// Order in which this Surah was revealed (1–114, different from id).
  IntColumn get revelationOrder => integer()();

  /// 'Makki' or 'Madani'.
  TextColumn get revelationType => text().withLength(min: 4, max: 6)();

  /// Total number of Ayahs in this Surah.
  IntColumn get versesCount => integer()();

  /// Mus'haf page where this Surah begins.
  IntColumn get pageStart => integer()();

  /// Mus'haf page where this Surah ends.
  IntColumn get pageEnd => integer()();

  /// Juz number where this Surah begins.
  IntColumn get juzStart => integer()();

  /// Hizb number where this Surah begins.
  IntColumn get hizbStart => integer()();

  /// Arabic name as it appears in the Mus'haf (e.g. "الفاتحة").
  TextColumn get nameArabic => text()();

  /// Latin transliteration of the Arabic name (e.g. "Al-Faatiha").
  TextColumn get nameTransliteration => text()();

  /// English meaning of the name (e.g. "The Opening").
  TextColumn get nameTranslation => text()();

  /// Whether Bismillah is recited before this Surah.
  /// False only for Surah 9 (At-Tawbah).
  BoolColumn get hasBismillah =>
      boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// AYAHS  (Verses)
// ────────────────────────────────────────────────────────────────────────────

/// Every Ayah (verse) in the Quran — 6,236 rows.
///
/// Stores multiple Arabic script variants so the app can switch fonts
/// without an extra network call.
class Ayahs extends Table {
  /// Global Ayah id (1–6236), matching quran.com's internal ordering.
  IntColumn get id => integer().autoIncrement()();

  /// Foreign key → [Surahs.id].
  IntColumn get surahId =>
      integer().references(Surahs, #id, onDelete: KeyAction.restrict)();

  /// Position of this Ayah within its Surah (1-indexed).
  IntColumn get ayahNumber => integer()();

  /// Composite key string used across the system: "surahId:ayahNumber"
  /// (e.g. "2:255"). Unique across the entire table.
  TextColumn get verseKey => text().unique()();

  /// Uthmani script — canonical Mus'haf representation.
  TextColumn get textUthmani => text()();

  /// Uthmani script WITH full Tajweed color markers encoded as tagged spans.
  /// Null if not yet available in the seed.
  TextColumn get textUthmaniTajweed => text().nullable()();

  /// Indopak (Indo-Pakistani) nastaliq script variant.
  TextColumn get textIndopak => text().nullable()();

  /// Simplified clean text (no diacritics) — used for full-text search.
  TextColumn get textSimpleClean => text()();

  /// Juz number (1–30).
  IntColumn get juzNumber => integer()();

  /// Hizb number (1–60).
  IntColumn get hizbNumber => integer()();

  /// Rub' el-Hizb number (1–240).
  IntColumn get rubElHizbNumber => integer()();

  /// Mus'haf page number (1–604).
  IntColumn get pageNumber => integer()();

  /// Ruku' number within the Surah.
  IntColumn get rukukNumber => integer()();

  /// Manzil number (1–7, for completing Quran in a week).
  IntColumn get manzilNumber => integer()();

  /// Whether a Sajdah (prostration) is required after this Ayah.
  BoolColumn get sajdahRequired =>
      boolean().withDefault(const Constant(false))();

  /// 'tilawah' | 'shukr' | null
  TextColumn get sajdahType => text().nullable()();
}

// ────────────────────────────────────────────────────────────────────────────
// WORD MORPHOLOGY
// ────────────────────────────────────────────────────────────────────────────

/// Word-by-word breakdown of every Ayah.
///
/// Enables the word-by-word display mode and powers the AI recitation
/// checker by providing individual word audio timestamps.
class WordMorphology extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Foreign key via verse_key string — avoids a join through Ayahs
  /// when the caller already has the verse_key.
  TextColumn get verseKey => text()();

  /// 1-indexed position of this word within the Ayah.
  IntColumn get wordPosition => integer()();

  /// Whether this token is the Ayah-end marker (◌) rather than a word.
  BoolColumn get isEnd => boolean().withDefault(const Constant(false))();

  /// Uthmani script for this word.
  TextColumn get textUthmani => text()();

  /// Simplified form used for morphological lookup.
  TextColumn get textClean => text()();

  /// Buckwalter/Latin transliteration.
  TextColumn get transliteration => text().nullable()();

  /// English gloss / translation of this individual word.
  TextColumn get translationEn => text().nullable()();

  /// Arabic morphological code (e.g. "V:PERF:ACT" from Quranic Arabic Corpus).
  TextColumn get morphologyCode => text().nullable()();

  /// Simplified part of speech: "N" | "V" | "P" | "CONJ" | …
  TextColumn get partOfSpeech => text().nullable()();

  /// Trilateral Arabic root (e.g. "ر ح م").
  TextColumn get root => text().nullable()();

  /// Dictionary lemma.
  TextColumn get lemma => text().nullable()();

  /// CDN URL for isolated word audio (used in word-by-word recitation).
  TextColumn get audioUrl => text().nullable()();
}

// ────────────────────────────────────────────────────────────────────────────
// JUZ  (Para) BOUNDARIES
// ────────────────────────────────────────────────────────────────────────────

/// Stores the starting Ayah for each of the 30 Juz.
class Juzs extends Table {
  /// Juz number (1–30).
  IntColumn get id => integer()();

  /// verse_key of the first Ayah in this Juz (e.g. "2:142").
  TextColumn get firstVerseKey => text()();

  /// verse_key of the last Ayah in this Juz.
  TextColumn get lastVerseKey => text()();

  /// Total Ayahs in this Juz.
  IntColumn get versesCount => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// QURAN FULL-TEXT SEARCH (FTS5 virtual table — declared separately)
// ────────────────────────────────────────────────────────────────────────────
// NOTE: Drift does not natively manage FTS5 virtual tables via table classes.
// We create it manually inside DatabaseInitializer._createFtsTable() using
// customStatement(). The table name is `ayahs_fts` with columns:
//   - verse_key TEXT
//   - text_simple_clean TEXT
//   - transliteration TEXT (combined from WordMorphology)
// This enables blazing-fast Arabic keyword search without the AI backend.
