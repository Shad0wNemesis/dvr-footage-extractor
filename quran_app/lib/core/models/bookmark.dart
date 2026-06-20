import 'package:equatable/equatable.dart';

enum BookmarkType { verse, surah, page }

class Bookmark extends Equatable {
  const Bookmark({
    required this.id,
    required this.verseKey,
    required this.surahId,
    required this.verseNumber,
    required this.pageNumber,
    required this.surahName,
    required this.createdAt,
    this.note,
    this.color,
    this.type = BookmarkType.verse,
  });

  final String id;
  final String verseKey;
  final int surahId;
  final int verseNumber;
  final int pageNumber;
  final String surahName;
  final DateTime createdAt;
  final String? note;
  final String? color;
  final BookmarkType type;

  Map<String, dynamic> toMap() => {
        'id': id,
        'verse_key': verseKey,
        'surah_id': surahId,
        'verse_number': verseNumber,
        'page_number': pageNumber,
        'surah_name': surahName,
        'created_at': createdAt.toIso8601String(),
        'note': note,
        'color': color,
        'type': type.name,
      };

  factory Bookmark.fromMap(Map<String, dynamic> map) {
    return Bookmark(
      id: map['id'] as String,
      verseKey: map['verse_key'] as String,
      surahId: map['surah_id'] as int,
      verseNumber: map['verse_number'] as int,
      pageNumber: map['page_number'] as int,
      surahName: map['surah_name'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      note: map['note'] as String?,
      color: map['color'] as String?,
      type: BookmarkType.values.firstWhere(
        (t) => t.name == (map['type'] as String? ?? 'verse'),
        orElse: () => BookmarkType.verse,
      ),
    );
  }

  Bookmark copyWith({String? note, String? color}) {
    return Bookmark(
      id: id,
      verseKey: verseKey,
      surahId: surahId,
      verseNumber: verseNumber,
      pageNumber: pageNumber,
      surahName: surahName,
      createdAt: createdAt,
      note: note ?? this.note,
      color: color ?? this.color,
      type: type,
    );
  }

  @override
  List<Object?> get props => [id, verseKey];
}
