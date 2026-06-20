import 'package:equatable/equatable.dart';

class WordTranslation {
  const WordTranslation({required this.text, required this.position});
  final String text;
  final int position;

  factory WordTranslation.fromJson(Map<String, dynamic> json) =>
      WordTranslation(
        text: json['text'] as String? ?? '',
        position: json['position'] as int? ?? 0,
      );
}

class Word {
  const Word({
    required this.id,
    required this.position,
    required this.audioUrl,
    required this.charTypeName,
    required this.codeV1,
    required this.codeV2,
    this.transliteration,
    this.translation,
  });

  final int id;
  final int position;
  final String audioUrl;
  final String charTypeName;
  final String codeV1;
  final String codeV2;
  final String? transliteration;
  final WordTranslation? translation;

  bool get isEnd => charTypeName == 'end';

  factory Word.fromJson(Map<String, dynamic> json) {
    return Word(
      id: json['id'] as int,
      position: json['position'] as int,
      audioUrl: json['audio_url'] as String? ?? '',
      charTypeName: json['char_type_name'] as String? ?? '',
      codeV1: json['code_v1'] as String? ?? '',
      codeV2: json['code_v2'] as String? ?? '',
      transliteration: (json['transliteration'] as Map?)?['text'] as String?,
      translation: json['translation'] != null
          ? WordTranslation.fromJson(json['translation'] as Map<String, dynamic>)
          : null,
    );
  }
}

class Translation {
  const Translation({
    required this.id,
    required this.resourceId,
    required this.resourceName,
    required this.text,
  });

  final int id;
  final int resourceId;
  final String resourceName;
  final String text;

  factory Translation.fromJson(Map<String, dynamic> json) {
    return Translation(
      id: json['id'] as int? ?? 0,
      resourceId: json['resource_id'] as int? ?? 0,
      resourceName: json['resource_name'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}

class TafsirEntry {
  const TafsirEntry({
    required this.id,
    required this.resourceId,
    required this.resourceName,
    required this.text,
  });

  final int id;
  final int resourceId;
  final String resourceName;
  final String text;

  factory TafsirEntry.fromJson(Map<String, dynamic> json) {
    return TafsirEntry(
      id: json['id'] as int? ?? 0,
      resourceId: json['resource_id'] as int? ?? 0,
      resourceName: json['resource_name'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}

class Verse extends Equatable {
  const Verse({
    required this.id,
    required this.verseNumber,
    required this.verseKey,
    required this.hizbNumber,
    required this.rubElHizbNumber,
    required this.rukukNumber,
    required this.manzilNumber,
    required this.sajdahNumber,
    required this.pageNumber,
    required this.juzNumber,
    required this.textUthmani,
    required this.textIndopak,
    required this.textSimple,
    this.words = const [],
    this.translations = const [],
    this.tafsirs = const [],
    this.audioUrl,
  });

  final int id;
  final int verseNumber;
  final String verseKey;
  final int hizbNumber;
  final int rubElHizbNumber;
  final int rukukNumber;
  final int manzilNumber;
  final int sajdahNumber;
  final int pageNumber;
  final int juzNumber;
  final String textUthmani;
  final String textIndopak;
  final String textSimple;
  final List<Word> words;
  final List<Translation> translations;
  final List<TafsirEntry> tafsirs;
  final String? audioUrl;

  int get chapterNumber => int.parse(verseKey.split(':').first);

  String get audioPath {
    final parts = verseKey.split(':');
    final chapter = parts[0].padLeft(3, '0');
    final verse = parts[1].padLeft(3, '0');
    return '$chapter$verse';
  }

  factory Verse.fromJson(Map<String, dynamic> json) {
    return Verse(
      id: json['id'] as int,
      verseNumber: json['verse_number'] as int,
      verseKey: json['verse_key'] as String,
      hizbNumber: json['hizb_number'] as int? ?? 0,
      rubElHizbNumber: json['rub_el_hizb_number'] as int? ?? 0,
      rukukNumber: json['ruku_number'] as int? ?? 0,
      manzilNumber: json['manzil_number'] as int? ?? 0,
      sajdahNumber: json['sajdah_number'] as int? ?? 0,
      pageNumber: json['page_number'] as int? ?? 0,
      juzNumber: json['juz_number'] as int? ?? 0,
      textUthmani: json['text_uthmani'] as String? ?? '',
      textIndopak: json['text_indopak'] as String? ?? '',
      textSimple: json['text_simple'] as String? ?? '',
      words: (json['words'] as List<dynamic>?)
              ?.map((w) => Word.fromJson(w as Map<String, dynamic>))
              .toList() ??
          [],
      translations: (json['translations'] as List<dynamic>?)
              ?.map((t) => Translation.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      tafsirs: (json['tafsirs'] as List<dynamic>?)
              ?.map((t) => TafsirEntry.fromJson(t as Map<String, dynamic>))
              .toList() ??
          [],
      audioUrl: json['audio'] != null
          ? (json['audio'] as Map)['url'] as String?
          : null,
    );
  }

  Verse copyWith({
    List<Translation>? translations,
    List<TafsirEntry>? tafsirs,
    String? audioUrl,
  }) {
    return Verse(
      id: id,
      verseNumber: verseNumber,
      verseKey: verseKey,
      hizbNumber: hizbNumber,
      rubElHizbNumber: rubElHizbNumber,
      rukukNumber: rukukNumber,
      manzilNumber: manzilNumber,
      sajdahNumber: sajdahNumber,
      pageNumber: pageNumber,
      juzNumber: juzNumber,
      textUthmani: textUthmani,
      textIndopak: textIndopak,
      textSimple: textSimple,
      words: words,
      translations: translations ?? this.translations,
      tafsirs: tafsirs ?? this.tafsirs,
      audioUrl: audioUrl ?? this.audioUrl,
    );
  }

  @override
  List<Object?> get props => [id, verseKey];
}
