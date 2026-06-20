/// Pure data-parsing utilities for the Quran JSON seed.
///
/// All functions here are pure / free of Flutter dependencies so they can
/// safely execute inside a Dart `Isolate` without context issues.
library seed_parser;

import 'dart:convert';

// ── Intermediate data classes (not Drift rows) ───────────────────────────────
// These lightweight structs are passed across isolate boundaries via
// SendPort. They must be JSON-serializable primitives (no Drift types).

/// Minimal representation of a Surah for cross-isolate transfer.
class SurahSeed {
  const SurahSeed({
    required this.id,
    required this.revelationOrder,
    required this.revelationType,
    required this.versesCount,
    required this.pageStart,
    required this.pageEnd,
    required this.juzStart,
    required this.hizbStart,
    required this.nameArabic,
    required this.nameTransliteration,
    required this.nameTranslation,
    required this.hasBismillah,
  });

  final int id;
  final int revelationOrder;
  final String revelationType;
  final int versesCount;
  final int pageStart;
  final int pageEnd;
  final int juzStart;
  final int hizbStart;
  final String nameArabic;
  final String nameTransliteration;
  final String nameTranslation;
  final bool hasBismillah;

  factory SurahSeed.fromJson(Map<String, dynamic> j) {
    return SurahSeed(
      id: j['id'] as int,
      revelationOrder: j['revelation_order'] as int,
      revelationType: j['revelation_place'] as String,
      versesCount: j['verses_count'] as int,
      pageStart: (j['pages'] as List<dynamic>).first as int,
      pageEnd: (j['pages'] as List<dynamic>).last as int,
      juzStart: j['juz_start'] as int? ?? 1,
      hizbStart: j['hizb_start'] as int? ?? 1,
      nameArabic: j['name_arabic'] as String,
      nameTransliteration: j['name_simple'] as String,
      nameTranslation:
          (j['translated_name'] as Map<String, dynamic>?)?['name'] as String? ??
              '',
      hasBismillah: (j['bismillah_pre'] as bool?) ?? (j['id'] != 9),
    );
  }
}

/// Minimal representation of an Ayah for cross-isolate transfer.
class AyahSeed {
  const AyahSeed({
    required this.id,
    required this.surahId,
    required this.ayahNumber,
    required this.verseKey,
    required this.textUthmani,
    required this.textIndopak,
    required this.textSimpleClean,
    required this.juzNumber,
    required this.hizbNumber,
    required this.rubElHizbNumber,
    required this.pageNumber,
    required this.rukukNumber,
    required this.manzilNumber,
    required this.sajdahRequired,
    required this.sajdahType,
  });

  final int id;
  final int surahId;
  final int ayahNumber;
  final String verseKey;
  final String textUthmani;
  final String? textIndopak;
  final String textSimpleClean;
  final int juzNumber;
  final int hizbNumber;
  final int rubElHizbNumber;
  final int pageNumber;
  final int rukukNumber;
  final int manzilNumber;
  final bool sajdahRequired;
  final String? sajdahType;

  factory AyahSeed.fromJson(Map<String, dynamic> j) {
    final sajdah = j['sajdah_type'] as String?;
    return AyahSeed(
      id: j['id'] as int,
      surahId: j['chapter_id'] as int? ??
          int.parse((j['verse_key'] as String).split(':').first),
      ayahNumber: j['verse_number'] as int,
      verseKey: j['verse_key'] as String,
      textUthmani: j['text_uthmani'] as String? ?? '',
      textIndopak: j['text_indopak'] as String?,
      textSimpleClean: _stripDiacritics(j['text_simple'] as String? ?? ''),
      juzNumber: j['juz_number'] as int? ?? 0,
      hizbNumber: j['hizb_number'] as int? ?? 0,
      rubElHizbNumber: j['rub_el_hizb_number'] as int? ?? 0,
      pageNumber: j['page_number'] as int? ?? 0,
      rukukNumber: j['ruku_number'] as int? ?? 0,
      manzilNumber: j['manzil_number'] as int? ?? 0,
      sajdahRequired: sajdah != null,
      sajdahType: sajdah,
    );
  }
}

/// Minimal word morphology record.
class WordSeed {
  const WordSeed({
    required this.verseKey,
    required this.wordPosition,
    required this.isEnd,
    required this.textUthmani,
    required this.textClean,
    this.transliteration,
    this.translationEn,
    this.morphologyCode,
    this.partOfSpeech,
    this.root,
    this.lemma,
    this.audioUrl,
  });

  final String verseKey;
  final int wordPosition;
  final bool isEnd;
  final String textUthmani;
  final String textClean;
  final String? transliteration;
  final String? translationEn;
  final String? morphologyCode;
  final String? partOfSpeech;
  final String? root;
  final String? lemma;
  final String? audioUrl;

  factory WordSeed.fromJson(String verseKey, Map<String, dynamic> j) {
    final charType = j['char_type_name'] as String? ?? '';
    return WordSeed(
      verseKey: verseKey,
      wordPosition: j['position'] as int,
      isEnd: charType == 'end',
      textUthmani: j['text_uthmani'] as String? ?? j['code_v1'] as String? ?? '',
      textClean: _stripDiacritics(j['text'] as String? ?? ''),
      transliteration:
          (j['transliteration'] as Map<String, dynamic>?)?['text'] as String?,
      translationEn:
          (j['translation'] as Map<String, dynamic>?)?['text'] as String?,
      morphologyCode: null, // Populated from a separate morphology dataset
      partOfSpeech: j['char_type_name'] as String?,
      root: null,
      lemma: null,
      audioUrl: j['audio_url'] as String?,
    );
  }
}

// ── Parsers ───────────────────────────────────────────────────────────────────

/// Parses a JSON string containing the full Surah list from quran.com's
/// /chapters endpoint format or a locally bundled equivalent.
///
/// Returns an empty list (not throws) on malformed input so the caller
/// can detect the failure via the empty list and report a seed error.
List<SurahSeed> parseSurahsJson(String jsonString) {
  try {
    final decoded = json.decode(jsonString) as Map<String, dynamic>;
    final chapters = decoded['chapters'] as List<dynamic>? ?? [];
    return chapters
        .map((c) => SurahSeed.fromJson(c as Map<String, dynamic>))
        .toList();
  } catch (e) {
    // Return empty — caller handles the error state.
    return const [];
  }
}

/// Parses a JSON string containing the Ayah list for one or all Surahs.
///
/// The format expected is either:
///   { "verses": [ ... ] }          ← quran.com API response
///   { "quran": { "surahs": [ { "ayahs": [...] } ] } }  ← offline bundle
List<AyahSeed> parseAyahsJson(String jsonString) {
  try {
    final decoded = json.decode(jsonString) as Map<String, dynamic>;

    // Format A: flat verse list (quran.com batch export)
    if (decoded.containsKey('verses')) {
      final verses = decoded['verses'] as List<dynamic>;
      return verses.map((v) => AyahSeed.fromJson(v as Map<String, dynamic>)).toList();
    }

    // Format B: nested Quran structure
    if (decoded.containsKey('quran')) {
      final result = <AyahSeed>[];
      final surahList =
          (decoded['quran'] as Map<String, dynamic>)['surahs'] as List<dynamic>;
      for (final surahData in surahList) {
        final surahMap = surahData as Map<String, dynamic>;
        final ayahs = surahMap['ayahs'] as List<dynamic>? ?? [];
        result.addAll(ayahs.map((a) => AyahSeed.fromJson(a as Map<String, dynamic>)));
      }
      return result;
    }

    return const [];
  } catch (_) {
    return const [];
  }
}

/// Parses word-by-word data from a JSON string.
///
/// Expected format: { "verse_key": "1:1", "words": [ ... ] }
/// or a list of such objects: [ { ... }, { ... } ]
List<WordSeed> parseWordsJson(String jsonString) {
  try {
    final decoded = json.decode(jsonString);

    // Single verse response
    if (decoded is Map<String, dynamic>) {
      final verseKey = decoded['verse_key'] as String? ?? '';
      final words = decoded['words'] as List<dynamic>? ?? [];
      return words
          .map((w) => WordSeed.fromJson(verseKey, w as Map<String, dynamic>))
          .toList();
    }

    // Array of verse objects
    if (decoded is List<dynamic>) {
      final result = <WordSeed>[];
      for (final item in decoded) {
        final obj = item as Map<String, dynamic>;
        final verseKey = obj['verse_key'] as String? ?? '';
        final words = obj['words'] as List<dynamic>? ?? [];
        result.addAll(
          words.map((w) => WordSeed.fromJson(verseKey, w as Map<String, dynamic>)),
        );
      }
      return result;
    }

    return const [];
  } catch (_) {
    return const [];
  }
}

// ── String utilities (used in isolate — no Flutter dependency) ────────────────

/// Removes Arabic diacritical marks (harakat) from a string.
///
/// Used to produce a clean version of Arabic text for keyword search
/// so users can find verses without typing exact diacritics.
String _stripDiacritics(String text) {
  // Unicode ranges for Arabic diacritics:
  // U+064B–U+065F  Fathah, Dammah, Kasrah, Sukun, Shadda, Maddah, …
  // U+0610–U+061A  Extended Arabic marks
  // U+06D6–U+06DC  Quran-specific marks
  return text.replaceAll(
    RegExp(r'[ؐ-ًؚ-ٟۖ-ۜ۟-۪ۨ-ۭ]'),
    '',
  );
}

/// Chunks a list into sub-lists of [size] for batch DB operations.
/// This avoids SQLite's 999-parameter SQLITE_LIMIT_VARIABLE_NUMBER limit.
List<List<T>> chunk<T>(List<T> list, int size) {
  final chunks = <List<T>>[];
  for (var i = 0; i < list.length; i += size) {
    chunks.add(list.sublist(i, (i + size).clamp(0, list.length)));
  }
  return chunks;
}
