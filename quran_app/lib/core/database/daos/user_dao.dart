/// DAO for all user-generated content: bookmarks, notes, SRS, history.
library user_dao;

import 'package:drift/drift.dart';

import '../quran_database.dart';
import '../tables/user_tables.dart';

part 'user_dao.g.dart';

@DriftAccessor(
  tables: [
    UserBookmarks,
    UserNotes,
    ReadingHistory,
    ReadingSessions,
    MemorizationItems,
    RecitationAttempts,
    SearchHistory,
  ],
)
class UserDao extends DatabaseAccessor<QuranDatabase> with _$UserDaoMixin {
  UserDao(super.db);

  // ── Bookmarks ────────────────────────────────────────────────────────────

  Stream<List<UserBookmark>> watchAllBookmarks() =>
      (select(userBookmarks)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  Future<List<UserBookmark>> allBookmarks() =>
      (select(userBookmarks)
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<UserBookmark?> bookmarkForVerse(String verseKey) =>
      (select(userBookmarks)
            ..where((t) => t.verseKey.equals(verseKey)))
          .getSingleOrNull();

  Future<bool> isBookmarked(String verseKey) async {
    final result = await bookmarkForVerse(verseKey);
    return result != null;
  }

  Future<void> addBookmark(UserBookmarksCompanion bookmark) =>
      into(userBookmarks).insert(bookmark, mode: InsertMode.insertOrIgnore);

  Future<bool> removeBookmark(String verseKey) async {
    final count = await (delete(userBookmarks)
          ..where((t) => t.verseKey.equals(verseKey)))
        .go();
    return count > 0;
  }

  Future<void> updateBookmarkNote(String verseKey, String note) =>
      (update(userBookmarks)..where((t) => t.verseKey.equals(verseKey)))
          .write(UserBookmarksCompanion(
            note: Value(note),
            updatedAt: Value(DateTime.now()),
          ));

  // ── Notes ─────────────────────────────────────────────────────────────────

  Future<UserNote?> noteForVerse(String verseKey) =>
      (select(userNotes)..where((t) => t.verseKey.equals(verseKey)))
          .getSingleOrNull();

  Stream<List<UserNote>> watchAllNotes() =>
      (select(userNotes)
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch();

  Future<void> upsertNote(UserNotesCompanion note) =>
      into(userNotes).insertOnConflictUpdate(note);

  Future<void> deleteNote(String id) async =>
      (delete(userNotes)..where((t) => t.id.equals(id))).go();

  // ── Reading History ───────────────────────────────────────────────────────

  /// Inserts a reading history entry and trims the table to 100 rows.
  Future<void> recordReading({
    required String verseKey,
    required int surahId,
    required String surahName,
    required int ayahNumber,
    required int pageNumber,
  }) async {
    await into(readingHistory).insert(ReadingHistoryCompanion(
      verseKey: Value(verseKey),
      surahId: Value(surahId),
      surahName: Value(surahName),
      ayahNumber: Value(ayahNumber),
      pageNumber: Value(pageNumber),
      accessedAt: Value(DateTime.now()),
    ));

    // Keep the table lean — only the most recent 100 entries.
    await customStatement('''
      DELETE FROM reading_history
      WHERE id NOT IN (
        SELECT id FROM reading_history
        ORDER BY accessed_at DESC
        LIMIT 100
      )
    ''');
  }

  /// Returns the most recent reading history entry (for "Continue Reading").
  Future<ReadingHistoryData?> lastReadingPosition() =>
      (select(readingHistory)
            ..orderBy([(t) => OrderingTerm.desc(t.accessedAt)])
            ..limit(1))
          .getSingleOrNull();

  // ── Reading Sessions ──────────────────────────────────────────────────────

  Future<int> startSession(String startVerseKey) =>
      into(readingSessions).insert(ReadingSessionsCompanion(
        startVerseKey: Value(startVerseKey),
        sessionStart: Value(DateTime.now()),
        ayahsRead: const Value(0),
        durationSeconds: const Value(0),
      ));

  Future<void> endSession({
    required int sessionId,
    required String endVerseKey,
    required int ayahsRead,
    required int durationSeconds,
  }) =>
      (update(readingSessions)..where((t) => t.id.equals(sessionId))).write(
        ReadingSessionsCompanion(
          endVerseKey: Value(endVerseKey),
          sessionEnd: Value(DateTime.now()),
          ayahsRead: Value(ayahsRead),
          durationSeconds: Value(durationSeconds),
        ),
      );

  /// Total reading time in seconds across all sessions.
  Future<int> totalReadingSeconds() async {
    final result = await customSelect(
      'SELECT COALESCE(SUM(duration_seconds), 0) AS total FROM reading_sessions',
    ).getSingle();
    return result.read<int>('total');
  }

  // ── Memorization (SRS) ───────────────────────────────────────────────────

  /// All memorization items due today or earlier, ordered by priority.
  Future<List<MemorizationItem>> dueTodayItems() {
    final now = DateTime.now();
    return (select(memorizationItems)
          ..where((t) =>
              t.nextReview.isSmallerOrEqualValue(now) &
              t.status.isNotIn(['suspended']))
          ..orderBy([
            // Overdue first
            (t) => OrderingTerm.asc(t.nextReview),
            // Within same due date, highest mistake count gets priority
            (t) => OrderingTerm.desc(t.consecutiveMistakes),
          ]))
        .get();
  }

  Stream<List<MemorizationItem>> watchDueTodayItems() {
    final now = DateTime.now();
    return (select(memorizationItems)
          ..where((t) =>
              t.nextReview.isSmallerOrEqualValue(now) &
              t.status.isNotIn(['suspended']))
          ..orderBy([(t) => OrderingTerm.asc(t.nextReview)]))
        .watch();
  }

  Future<List<MemorizationItem>> allMemorizationItems() =>
      (select(memorizationItems)
            ..orderBy([(t) => OrderingTerm.asc(t.surahId)]))
          .get();

  Future<MemorizationItem?> memorizationItemForVerse(String verseKey) =>
      (select(memorizationItems)
            ..where((t) => t.verseKey.equals(verseKey)))
          .getSingleOrNull();

  Future<void> addToMemorization({
    required String verseKey,
    required int surahId,
    required int ayahNumber,
  }) async {
    await into(memorizationItems).insertOnConflictUpdate(
      MemorizationItemsCompanion(
        verseKey: Value(verseKey),
        surahId: Value(surahId),
        ayahNumber: Value(ayahNumber),
        nextReview: Value(DateTime.now()),
        addedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Update the SRS item after a review using SM-2 algorithm.
  ///
  /// [grade]: 0–5 quality score (0–2 = fail, 3–5 = pass).
  Future<void> recordReview({
    required String verseKey,
    required int grade,
  }) async {
    final item = await memorizationItemForVerse(verseKey);
    if (item == null) return;

    // ── SM-2 calculation ───────────────────────────────────────────────────
    double easeFactor = item.easeFactor;
    int interval = item.intervalDays;
    int reps = item.repetitions;
    String status;
    int consecutiveMistakes;

    if (grade >= 3) {
      // Correct response
      if (reps == 0) {
        interval = 1;
      } else if (reps == 1) {
        interval = 6;
      } else {
        interval = (interval * easeFactor).round();
      }
      // Clamp interval to reasonable maximum (365 days)
      interval = interval.clamp(1, 365);
      easeFactor =
          (easeFactor + 0.1 - (5 - grade) * 0.08).clamp(1.3, 4.0);
      reps += 1;
      consecutiveMistakes = 0;
      status = interval >= 21 ? 'mature' : 'review';
    } else {
      // Incorrect response — reset
      reps = 0;
      interval = 1;
      consecutiveMistakes = item.consecutiveMistakes + 1;
      status = 'learning';
    }

    final nextReview =
        DateTime.now().add(Duration(days: interval));

    await (update(memorizationItems)
          ..where((t) => t.verseKey.equals(verseKey)))
        .write(MemorizationItemsCompanion(
      easeFactor: Value(easeFactor),
      intervalDays: Value(interval),
      repetitions: Value(reps),
      nextReview: Value(nextReview),
      lastReview: Value(DateTime.now()),
      totalReviews: Value(item.totalReviews + 1),
      correctReviews:
          Value(grade >= 3 ? item.correctReviews + 1 : item.correctReviews),
      consecutiveMistakes: Value(consecutiveMistakes),
      status: Value(status),
    ));
  }

  // ── Recitation Attempts ───────────────────────────────────────────────────

  Future<void> saveRecitationAttempt(RecitationAttemptsCompanion attempt) =>
      into(recitationAttempts).insert(attempt);

  Future<List<RecitationAttempt>> attemptsForVerse(String verseKey) =>
      (select(recitationAttempts)
            ..where((t) => t.verseKey.equals(verseKey))
            ..orderBy([(t) => OrderingTerm.desc(t.attemptedAt)]))
          .get();

  /// Average accuracy score across the last [n] attempts for a verse.
  Future<double> averageAccuracy(String verseKey, {int last = 5}) async {
    final rows = await (select(recitationAttempts)
          ..where((t) => t.verseKey.equals(verseKey))
          ..orderBy([(t) => OrderingTerm.desc(t.attemptedAt)])
          ..limit(last))
        .get();
    if (rows.isEmpty) return 0.0;
    final sum = rows.fold<double>(0.0, (s, r) => s + r.accuracyScore);
    return sum / rows.length;
  }

  // ── Search History ────────────────────────────────────────────────────────

  Future<void> recordSearch({
    required String query,
    required String searchType,
    required int resultsCount,
  }) async {
    await into(searchHistory).insert(SearchHistoryCompanion(
      query: Value(query),
      searchType: Value(searchType),
      resultsCount: Value(resultsCount),
      searchedAt: Value(DateTime.now()),
    ));

    // Trim to last 50 searches.
    await customStatement('''
      DELETE FROM search_history
      WHERE id NOT IN (
        SELECT id FROM search_history
        ORDER BY searched_at DESC
        LIMIT 50
      )
    ''');
  }

  Future<List<SearchHistoryData>> recentSearches({int limit = 10}) =>
      (select(searchHistory)
            ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
            ..limit(limit))
          .get();
}
