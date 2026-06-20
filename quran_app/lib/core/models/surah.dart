import 'package:equatable/equatable.dart';

class Surah extends Equatable {
  const Surah({
    required this.id,
    required this.revelationOrder,
    required this.revelationType,
    required this.versesCount,
    required this.pagesStart,
    required this.pagesEnd,
    required this.nameSimple,
    required this.nameComplex,
    required this.nameArabic,
    required this.nameTranslation,
    this.bismillahPre = true,
  });

  final int id;
  final int revelationOrder;
  final String revelationType;
  final int versesCount;
  final int pagesStart;
  final int pagesEnd;
  final String nameSimple;
  final String nameComplex;
  final String nameArabic;
  final String nameTranslation;
  final bool bismillahPre;

  bool get isMakki => revelationType == 'Makki';
  bool get isMadani => revelationType == 'Madani';

  factory Surah.fromJson(Map<String, dynamic> json) {
    return Surah(
      id: json['id'] as int,
      revelationOrder: json['revelation_order'] as int,
      revelationType: json['revelation_place'] as String,
      versesCount: json['verses_count'] as int,
      pagesStart: (json['pages'] as List).first as int,
      pagesEnd: (json['pages'] as List).last as int,
      nameSimple: json['name_simple'] as String,
      nameComplex: json['name_complex'] as String,
      nameArabic: json['name_arabic'] as String,
      nameTranslation: (json['translated_name'] as Map?)?['name'] as String? ?? '',
      bismillahPre: json['bismillah_pre'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'revelation_order': revelationOrder,
        'revelation_type': revelationType,
        'verses_count': versesCount,
        'pages_start': pagesStart,
        'pages_end': pagesEnd,
        'name_simple': nameSimple,
        'name_complex': nameComplex,
        'name_arabic': nameArabic,
        'name_translation': nameTranslation,
        'bismillah_pre': bismillahPre ? 1 : 0,
      };

  factory Surah.fromMap(Map<String, dynamic> map) {
    return Surah(
      id: map['id'] as int,
      revelationOrder: map['revelation_order'] as int,
      revelationType: map['revelation_type'] as String,
      versesCount: map['verses_count'] as int,
      pagesStart: map['pages_start'] as int,
      pagesEnd: map['pages_end'] as int,
      nameSimple: map['name_simple'] as String,
      nameComplex: map['name_complex'] as String,
      nameArabic: map['name_arabic'] as String,
      nameTranslation: map['name_translation'] as String,
      bismillahPre: (map['bismillah_pre'] as int?) == 1,
    );
  }

  @override
  List<Object?> get props => [id];
}
