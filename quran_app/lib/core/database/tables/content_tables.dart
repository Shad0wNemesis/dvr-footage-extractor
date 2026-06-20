/// Content enrichment tables: Tafseer, Translations, Reciters, Audio timestamps.
///
/// These are also seeded at startup but may be updated independently
/// (e.g., downloading a new translation pack) — hence they live in a
/// separate file from the immutable Quran core.
library content_tables;

import 'package:drift/drift.dart';
import 'quran_tables.dart';

// ────────────────────────────────────────────────────────────────────────────
// TAFSEER  (Exegesis)
// ────────────────────────────────────────────────────────────────────────────

/// Registry of available Tafseer books.
class TafseerSources extends Table {
  /// quran.com resource ID for this source.
  IntColumn get id => integer()();

  /// Machine-readable slug (e.g. "en-tafsir-ibn-kathir").
  TextColumn get slug => text().unique()();

  /// Human-readable name.
  TextColumn get name => text()();

  /// Author / translator name.
  TextColumn get authorName => text()();

  /// BCP-47 language code: "ar", "en", "ur", "tr", …
  TextColumn get languageCode => text().withLength(min: 2, max: 8)();

  /// True if this source is bundled in the app's initial DB seed.
  /// False means it must be downloaded on demand.
  BoolColumn get isBundled =>
      boolean().withDefault(const Constant(false))();

  /// Brief description shown in the settings picker.
  TextColumn get description => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Actual Tafseer text, keyed by Ayah.
///
/// Rows are inserted lazily (bundled sources at init, others on download).
/// The composite index on (verseKey, sourceId) is the primary access pattern.
class TafseerTexts extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// "surahId:ayahNumber" foreign reference.
  TextColumn get verseKey => text()();

  /// Foreign key → [TafseerSources.id].
  IntColumn get sourceId => integer()
      .references(TafseerSources, #id, onDelete: KeyAction.cascade)();

  /// Full Tafseer text (may contain HTML for rich display).
  TextColumn get text => text()();

  /// First ~300 characters, HTML-stripped — for list previews.
  /// Stored denormalized to avoid string processing on the main thread.
  TextColumn get shortText => text().nullable()();
}

// ────────────────────────────────────────────────────────────────────────────
// TRANSLATIONS
// ────────────────────────────────────────────────────────────────────────────

/// Registry of available translation packs.
class TranslationSources extends Table {
  IntColumn get id => integer()();
  TextColumn get slug => text().unique()();
  TextColumn get name => text()();
  TextColumn get authorName => text()();

  /// BCP-47 language code.
  TextColumn get languageCode => text().withLength(min: 2, max: 8)();

  TextColumn get languageName => text()();

  /// True if bundled in the seed DB; false = download on demand.
  BoolColumn get isBundled =>
      boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Translation text per Ayah.
class TranslationTexts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get verseKey => text()();
  IntColumn get translationId => integer()
      .references(TranslationSources, #id, onDelete: KeyAction.cascade)();

  /// Translation text (may contain HTML footnotes).
  TextColumn get text => text()();

  /// HTML-stripped short form for quick display.
  TextColumn get shortText => text().nullable()();
}

// ────────────────────────────────────────────────────────────────────────────
// RECITERS
// ────────────────────────────────────────────────────────────────────────────

/// Registry of audio reciters available from the Quran.com CDN.
class Reciters extends Table {
  IntColumn get id => integer()();

  /// reciter_id used in quran.com audio API paths.
  IntColumn get reciterId => integer()();

  TextColumn get name => text()();
  TextColumn get arabicName => text().nullable()();

  /// "Hafs" | "Warsh" | "Qaloon" | etc.
  TextColumn get style => text().nullable()();

  /// e.g. "Mishary Rashid Al-Afasy"
  TextColumn get displayName => text()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// AUDIO TIMESTAMPS  (Verse-level sync data)
// ────────────────────────────────────────────────────────────────────────────

/// Maps each Ayah to its start/end timestamp within a full-Surah audio file.
///
/// Used to:
///   - Scroll the reader in sync with audio playback
///   - Highlight the currently recited Ayah
///   - Seek directly to a specific Ayah in the audio
class AudioTimestamps extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get verseKey => text()();

  /// Foreign key → [Reciters.id].
  IntColumn get recitationId => integer()
      .references(Reciters, #id, onDelete: KeyAction.cascade)();

  /// Milliseconds from the start of the full-Surah audio file.
  IntColumn get timestampFrom => integer()();
  IntColumn get timestampTo => integer()();

  /// Duration in milliseconds.
  IntColumn get durationMs => integer()();
}
