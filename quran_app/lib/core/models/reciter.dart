import 'package:equatable/equatable.dart';

class Reciter extends Equatable {
  const Reciter({
    required this.id,
    required this.reciterId,
    required this.name,
    required this.style,
    required this.translatedName,
  });

  final int id;
  final int reciterId;
  final String name;
  final String style;
  final String translatedName;

  factory Reciter.fromJson(Map<String, dynamic> json) {
    return Reciter(
      id: json['id'] as int,
      reciterId: json['reciter_id'] as int? ?? json['id'] as int,
      name: json['reciter_name'] as String? ?? json['name'] as String? ?? '',
      style: json['style'] as String? ?? '',
      translatedName: (json['translated_name'] as Map?)?['name'] as String? ?? '',
    );
  }

  String get displayName => translatedName.isNotEmpty ? translatedName : name;

  @override
  List<Object?> get props => [id];
}

class ChapterAudio {
  const ChapterAudio({
    required this.id,
    required this.chapterId,
    required this.fileSize,
    required this.format,
    required this.audioUrl,
    required this.duration,
    this.verseTimings = const [],
  });

  final int id;
  final int chapterId;
  final int fileSize;
  final String format;
  final String audioUrl;
  final int duration;
  final List<VerseTiming> verseTimings;

  factory ChapterAudio.fromJson(Map<String, dynamic> json) {
    return ChapterAudio(
      id: json['id'] as int? ?? 0,
      chapterId: json['chapter_id'] as int? ?? 0,
      fileSize: json['file_size'] as int? ?? 0,
      format: json['format'] as String? ?? 'mp3',
      audioUrl: json['audio_url'] as String? ?? '',
      duration: json['duration'] as int? ?? 0,
      verseTimings: (json['verse_timings'] as List<dynamic>?)
              ?.map((v) => VerseTiming.fromJson(v as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class VerseTiming {
  const VerseTiming({
    required this.verseKey,
    required this.timestampFrom,
    required this.timestampTo,
    required this.duration,
  });

  final String verseKey;
  final int timestampFrom;
  final int timestampTo;
  final int duration;

  factory VerseTiming.fromJson(Map<String, dynamic> json) {
    return VerseTiming(
      verseKey: json['verse_key'] as String? ?? '',
      timestampFrom: json['timestamp_from'] as int? ?? 0,
      timestampTo: json['timestamp_to'] as int? ?? 0,
      duration: json['duration'] as int? ?? 0,
    );
  }
}
