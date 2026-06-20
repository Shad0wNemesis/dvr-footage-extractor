import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../constants/app_constants.dart';
import '../models/surah.dart';
import '../models/verse.dart';
import '../models/bookmark.dart';

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, AppConstants.dbName);
    return openDatabase(
      path,
      version: AppConstants.dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE surahs (
        id INTEGER PRIMARY KEY,
        revelation_order INTEGER NOT NULL,
        revelation_type TEXT NOT NULL,
        verses_count INTEGER NOT NULL,
        pages_start INTEGER NOT NULL,
        pages_end INTEGER NOT NULL,
        name_simple TEXT NOT NULL,
        name_complex TEXT NOT NULL,
        name_arabic TEXT NOT NULL,
        name_translation TEXT NOT NULL,
        bismillah_pre INTEGER NOT NULL DEFAULT 1
      )
    ''');

    await db.execute('''
      CREATE TABLE verses (
        id INTEGER PRIMARY KEY,
        verse_number INTEGER NOT NULL,
        verse_key TEXT NOT NULL UNIQUE,
        chapter_id INTEGER NOT NULL,
        hizb_number INTEGER DEFAULT 0,
        rub_el_hizb_number INTEGER DEFAULT 0,
        ruku_number INTEGER DEFAULT 0,
        manzil_number INTEGER DEFAULT 0,
        sajdah_number INTEGER DEFAULT 0,
        page_number INTEGER DEFAULT 0,
        juz_number INTEGER DEFAULT 0,
        text_uthmani TEXT NOT NULL,
        text_indopak TEXT DEFAULT '',
        text_simple TEXT DEFAULT '',
        FOREIGN KEY (chapter_id) REFERENCES surahs(id)
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_verses_chapter ON verses(chapter_id)
    ''');

    await db.execute('''
      CREATE TABLE cached_translations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        verse_key TEXT NOT NULL,
        resource_id INTEGER NOT NULL,
        text TEXT NOT NULL,
        UNIQUE(verse_key, resource_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE bookmarks (
        id TEXT PRIMARY KEY,
        verse_key TEXT NOT NULL,
        surah_id INTEGER NOT NULL,
        verse_number INTEGER NOT NULL,
        page_number INTEGER NOT NULL,
        surah_name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        note TEXT,
        color TEXT,
        type TEXT DEFAULT 'verse'
      )
    ''');

    await db.execute('''
      CREATE TABLE reading_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        verse_key TEXT NOT NULL,
        surah_id INTEGER NOT NULL,
        surah_name TEXT NOT NULL,
        verse_number INTEGER NOT NULL,
        accessed_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE notes (
        id TEXT PRIMARY KEY,
        verse_key TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {}

  // Surah operations
  Future<void> cacheSurahs(List<Surah> surahs) async {
    final db = await database;
    final batch = db.batch();
    for (final s in surahs) {
      batch.insert('surahs', s.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<List<Surah>> getCachedSurahs() async {
    final db = await database;
    final maps = await db.query('surahs', orderBy: 'id ASC');
    return maps.map(Surah.fromMap).toList();
  }

  Future<bool> hasCachedSurahs() async {
    final db = await database;
    final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM surahs'));
    return (count ?? 0) > 0;
  }

  // Verse operations
  Future<void> cacheVerses(List<Verse> verses) async {
    final db = await database;
    final batch = db.batch();
    for (final v in verses) {
      batch.insert(
        'verses',
        {
          'id': v.id,
          'verse_number': v.verseNumber,
          'verse_key': v.verseKey,
          'chapter_id': v.chapterNumber,
          'hizb_number': v.hizbNumber,
          'rub_el_hizb_number': v.rubElHizbNumber,
          'ruku_number': v.rukukNumber,
          'manzil_number': v.manzilNumber,
          'sajdah_number': v.sajdahNumber,
          'page_number': v.pageNumber,
          'juz_number': v.juzNumber,
          'text_uthmani': v.textUthmani,
          'text_indopak': v.textIndopak,
          'text_simple': v.textSimple,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final t in v.translations) {
        batch.insert(
          'cached_translations',
          {
            'verse_key': v.verseKey,
            'resource_id': t.resourceId,
            'text': t.text,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
    await batch.commit(noResult: true);
  }

  Future<List<Verse>> getCachedVersesByChapter(int chapterId, {int? translationId}) async {
    final db = await database;
    final maps = await db.query(
      'verses',
      where: 'chapter_id = ?',
      whereArgs: [chapterId],
      orderBy: 'verse_number ASC',
    );
    if (maps.isEmpty) return [];

    final verses = <Verse>[];
    for (final map in maps) {
      final verseKey = map['verse_key'] as String;
      final translations = translationId != null
          ? await db.query(
              'cached_translations',
              where: 'verse_key = ? AND resource_id = ?',
              whereArgs: [verseKey, translationId],
            )
          : <Map<String, dynamic>>[];

      verses.add(Verse(
        id: map['id'] as int,
        verseNumber: map['verse_number'] as int,
        verseKey: verseKey,
        hizbNumber: map['hizb_number'] as int? ?? 0,
        rubElHizbNumber: map['rub_el_hizb_number'] as int? ?? 0,
        rukukNumber: map['ruku_number'] as int? ?? 0,
        manzilNumber: map['manzil_number'] as int? ?? 0,
        sajdahNumber: map['sajdah_number'] as int? ?? 0,
        pageNumber: map['page_number'] as int? ?? 0,
        juzNumber: map['juz_number'] as int? ?? 0,
        textUthmani: map['text_uthmani'] as String,
        textIndopak: map['text_indopak'] as String? ?? '',
        textSimple: map['text_simple'] as String? ?? '',
        translations: translations
            .map((t) => Translation(
                  id: 0,
                  resourceId: t['resource_id'] as int,
                  resourceName: '',
                  text: t['text'] as String,
                ))
            .toList(),
      ));
    }
    return verses;
  }

  Future<bool> hasChapterCached(int chapterId) async {
    final db = await database;
    final count = Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM verses WHERE chapter_id = ?', [chapterId]));
    return (count ?? 0) > 0;
  }

  // Bookmark operations
  Future<void> addBookmark(Bookmark bookmark) async {
    final db = await database;
    await db.insert('bookmarks', bookmark.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> removeBookmark(String id) async {
    final db = await database;
    await db.delete('bookmarks', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Bookmark>> getAllBookmarks() async {
    final db = await database;
    final maps = await db.query('bookmarks', orderBy: 'created_at DESC');
    return maps.map(Bookmark.fromMap).toList();
  }

  Future<bool> isBookmarked(String verseKey) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery(
        'SELECT COUNT(*) FROM bookmarks WHERE verse_key = ?', [verseKey]));
    return (count ?? 0) > 0;
  }

  Future<void> updateBookmarkNote(String id, String note) async {
    final db = await database;
    await db.update('bookmarks', {'note': note},
        where: 'id = ?', whereArgs: [id]);
  }

  // Reading history
  Future<void> saveReadingPosition(
      String verseKey, int surahId, String surahName, int verseNumber) async {
    final db = await database;
    await db.insert(
      'reading_history',
      {
        'verse_key': verseKey,
        'surah_id': surahId,
        'surah_name': surahName,
        'verse_number': verseNumber,
        'accessed_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    // Keep only last 50 entries
    await db.rawDelete('''
      DELETE FROM reading_history WHERE id NOT IN (
        SELECT id FROM reading_history ORDER BY accessed_at DESC LIMIT 50
      )
    ''');
  }

  Future<Map<String, dynamic>?> getLastReadingPosition() async {
    final db = await database;
    final maps = await db.query('reading_history',
        orderBy: 'accessed_at DESC', limit: 1);
    return maps.isEmpty ? null : maps.first;
  }

  // Notes
  Future<void> saveNote(String id, String verseKey, String content) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'notes',
      {
        'id': id,
        'verse_key': verseKey,
        'content': content,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getNoteForVerse(String verseKey) async {
    final db = await database;
    final maps = await db.query('notes',
        where: 'verse_key = ?', whereArgs: [verseKey], limit: 1);
    return maps.isEmpty ? null : maps.first['content'] as String?;
  }
}
