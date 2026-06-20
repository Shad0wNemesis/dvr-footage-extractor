/// User-generated data tables.
///
/// These tables are mutable at runtime and belong to the "user partition"
/// of the database. They must never be wiped during a seed/content update.
/// All IDs use UUID v4 strings to support eventual cloud sync.
library user_tables;

import 'package:drift/drift.dart';
import 'quran_tables.dart';

// ────────────────────────────────────────────────────────────────────────────
// BOOKMARKS
// ────────────────────────────────────────────────────────────────────────────

/// User bookmarks on specific Ayahs.
class UserBookmarks extends Table {
  /// UUID v4 string — stable across sync.
  TextColumn get id => text()();

  /// "surahId:ayahNumber".
  TextColumn get verseKey => text()();

  IntColumn get surahId => integer()();
  IntColumn get ayahNumber => integer()();
  IntColumn get pageNumber => integer()();
  TextColumn get surahName => text()();

  /// Optional short annotation the user attached to this bookmark.
  TextColumn get note => text().nullable()();

  /// Hex color string for visual grouping (e.g. "#FF5733").
  TextColumn get colorHex => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// NOTES  (Long-form annotations)
// ────────────────────────────────────────────────────────────────────────────

/// Extended notes a user writes on an Ayah — supports markdown.
class UserNotes extends Table {
  TextColumn get id => text()();
  TextColumn get verseKey => text()();

  /// Markdown content.
  TextColumn get content => text()();

  /// JSON-encoded list of string tags (e.g. ["tafseer", "hifz"]).
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ────────────────────────────────────────────────────────────────────────────
// READING  HISTORY  &  POSITION
// ────────────────────────────────────────────────────────────────────────────

/// Lightweight access log — used to populate "Continue Reading" card.
/// Capped at 100 rows by the DAO after each insert.
class ReadingHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get verseKey => text()();
  IntColumn get surahId => integer()();
  TextColumn get surahName => text()();
  IntColumn get ayahNumber => integer()();
  IntColumn get pageNumber => integer()();
  DateTimeColumn get accessedAt => dateTime()();
}

// ────────────────────────────────────────────────────────────────────────────
// READING  SESSIONS  (Aggregate stats)
// ────────────────────────────────────────────────────────────────────────────

/// One row per active reading session.
/// Powers the "reading streak" and "time spent" statistics screens.
class ReadingSessions extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// verse_key where the session started.
  TextColumn get startVerseKey => text()();

  /// verse_key where the session ended (last verse scrolled past).
  TextColumn get endVerseKey => text().nullable()();

  /// Total unique Ayahs marked as "read" in this session.
  IntColumn get ayahsRead => integer().withDefault(const Constant(0))();

  DateTimeColumn get sessionStart => dateTime()();
  DateTimeColumn get sessionEnd => dateTime().nullable()();

  /// Wall-clock seconds spent in the reader (paused time excluded).
  IntColumn get durationSeconds =>
      integer().withDefault(const Constant(0))();
}

// ────────────────────────────────────────────────────────────────────────────
// MEMORIZATION — Spaced Repetition System (SM-2 variant)
// ────────────────────────────────────────────────────────────────────────────

/// One row per Ayah that the user has added to their Hifz plan.
///
/// Algorithm: SM-2 extended with a "mistake streak" decay factor.
///
/// SM-2 update rules (called after each review):
///   if grade >= 3 (correct):
///     if repetitions == 0 : interval = 1
///     elif repetitions == 1: interval = 6
///     else                : interval = round(interval * easeFactor)
///     easeFactor = max(1.3, easeFactor + 0.1 - (5 - grade) * 0.08)
///     repetitions += 1
///   else (incorrect):
///     repetitions = 0
///     interval = 1
///   nextReview = today + interval (days)
class MemorizationItems extends Table {
  /// verse_key is the natural primary key for this table.
  TextColumn get verseKey => text()();

  IntColumn get surahId => integer()();
  IntColumn get ayahNumber => integer()();

  // ── SM-2 fields ─────────────────────────────────────────────
  /// Ease factor — starts at 2.5, minimum 1.3.
  RealColumn get easeFactor =>
      real().withDefault(const Constant(2.5))();

  /// Review interval in days.
  IntColumn get intervalDays =>
      integer().withDefault(const Constant(1))();

  /// Number of consecutive successful reviews.
  IntColumn get repetitions =>
      integer().withDefault(const Constant(0))();

  // ── Scheduling ──────────────────────────────────────────────
  /// When this item is next due for review.
  DateTimeColumn get nextReview => dateTime()();

  /// When the user last reviewed this item.
  DateTimeColumn get lastReview => dateTime().nullable()();

  // ── Statistics ──────────────────────────────────────────────
  IntColumn get totalReviews =>
      integer().withDefault(const Constant(0))();

  IntColumn get correctReviews =>
      integer().withDefault(const Constant(0))();

  /// Consecutive incorrect count — triggers "at-risk" flag.
  IntColumn get consecutiveMistakes =>
      integer().withDefault(const Constant(0))();

  /// 'new' | 'learning' | 'review' | 'mature' | 'suspended'
  TextColumn get status =>
      text().withDefault(const Constant('new'))();

  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {verseKey};
}

// ────────────────────────────────────────────────────────────────────────────
// RECITATION  ATTEMPTS  (AI Tajweed checker results)
// ────────────────────────────────────────────────────────────────────────────

/// Stores every recitation attempt the user makes against the AI checker.
///
/// The raw audio is NOT stored — only the evaluation result. This preserves
/// storage space while still providing detailed error history.
class RecitationAttempts extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get verseKey => text()();

  DateTimeColumn get attemptedAt => dateTime()();

  /// 0.0–1.0 score from the AI Tajweed evaluation.
  RealColumn get accuracyScore => real()();

  /// What the STT model transcribed (Buckwalter or Arabic).
  TextColumn get transcription => text()();

  /// JSON array of TajweedError objects:
  /// [{"word_pos": 2, "rule": "ikhfa", "severity": "minor"}, …]
  TextColumn get tajweedErrorsJson =>
      text().withDefault(const Constant('[]'))();

  /// Wall-clock milliseconds of the audio clip.
  IntColumn get durationMs => integer()();

  /// True if accuracy >= passing threshold defined in settings.
  BoolColumn get passed => boolean()();
}

// ────────────────────────────────────────────────────────────────────────────
// SEARCH  HISTORY
// ────────────────────────────────────────────────────────────────────────────

/// Stores recent searches for autocomplete and analytics.
/// Capped at 50 rows by the DAO.
class SearchHistory extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get query => text()();

  /// 'text' | 'semantic' | 'arabic'
  TextColumn get searchType => text()();

  IntColumn get resultsCount => integer()();

  DateTimeColumn get searchedAt => dateTime()();
}
