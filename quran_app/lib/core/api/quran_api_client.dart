import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../models/surah.dart';
import '../models/verse.dart';
import '../models/reciter.dart';

class QuranApiClient {
  QuranApiClient() {
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConstants.baseUrl,
        connectTimeout: const Duration(milliseconds: ApiConstants.connectTimeoutMs),
        receiveTimeout: const Duration(milliseconds: ApiConstants.receiveTimeoutMs),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
        },
      ),
    );

    _dio.interceptors.addAll([
      LogInterceptor(requestBody: false, responseBody: false),
      _RetryInterceptor(_dio),
    ]);
  }

  late final Dio _dio;

  Future<List<Surah>> fetchChapters({String language = 'en'}) async {
    final response = await _dio.get(
      ApiConstants.chapters,
      queryParameters: {'language': language},
    );
    final chapters = response.data['chapters'] as List;
    return chapters.map((c) => Surah.fromJson(c as Map<String, dynamic>)).toList();
  }

  Future<List<Verse>> fetchVersesByChapter(
    int chapterNumber, {
    int? translationId,
    int? tafsirId,
    bool includeWords = true,
    int page = 1,
    int perPage = 50,
  }) async {
    final queryParams = <String, dynamic>{
      'words': includeWords,
      'translations': translationId ?? ApiConstants.defaultTranslationId,
      'audio': ApiConstants.defaultReciterId,
      'word_fields': 'text_uthmani,text_indopak,code_v1,code_v2,transliteration,translation',
      'translation_fields': 'resource_name,language_name',
      'fields': 'text_uthmani,text_indopak,text_simple,juz_number,hizb_number,rub_el_hizb_number,ruku_number,manzil_number,sajdah_number,page_number',
      'page': page,
      'per_page': perPage,
    };

    if (tafsirId != null) {
      queryParams['tafsirs'] = tafsirId;
    }

    final response = await _dio.get(
      ApiConstants.versesByChapter(chapterNumber),
      queryParameters: queryParams,
    );
    final verses = response.data['verses'] as List;
    return verses.map((v) => Verse.fromJson(v as Map<String, dynamic>)).toList();
  }

  Future<List<Verse>> fetchVersesByPage(
    int pageNumber, {
    int? translationId,
  }) async {
    final response = await _dio.get(
      ApiConstants.versesByPage(pageNumber),
      queryParameters: {
        'words': true,
        'translations': translationId ?? ApiConstants.defaultTranslationId,
        'word_fields': 'text_uthmani,code_v1,transliteration,translation',
        'fields': 'text_uthmani,text_simple,juz_number,page_number,verse_key',
      },
    );
    final verses = response.data['verses'] as List;
    return verses.map((v) => Verse.fromJson(v as Map<String, dynamic>)).toList();
  }

  Future<List<TranslationResource>> fetchTranslations({String language = 'en'}) async {
    final response = await _dio.get(
      ApiConstants.translations,
      queryParameters: {'language': language},
    );
    final items = response.data['translations'] as List;
    return items
        .map((t) => TranslationResource.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<List<TafsirResource>> fetchTafsirs({String language = 'en'}) async {
    final response = await _dio.get(
      ApiConstants.tafsirs,
      queryParameters: {'language': language},
    );
    final items = response.data['tafsirs'] as List;
    return items.map((t) => TafsirResource.fromJson(t as Map<String, dynamic>)).toList();
  }

  Future<List<Reciter>> fetchReciters({String language = 'en'}) async {
    final response = await _dio.get(
      ApiConstants.reciters,
      queryParameters: {'language': language},
    );
    final items = response.data['recitations'] as List;
    return items.map((r) => Reciter.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<ChapterAudio> fetchChapterAudio(int reciterId, int chapterId) async {
    final response = await _dio.get(
      ApiConstants.chapterRecitations(reciterId, chapterId),
    );
    return ChapterAudio.fromJson(
        response.data['audio_file'] as Map<String, dynamic>);
  }

  Future<List<SearchResult>> search(String query, {int page = 1, String language = 'en'}) async {
    final response = await _dio.get(
      ApiConstants.search,
      queryParameters: {
        'q': query,
        'page': page,
        'size': 20,
        'language': language,
      },
    );
    final results = response.data['search']['results'] as List? ?? [];
    return results.map((r) => SearchResult.fromJson(r as Map<String, dynamic>)).toList();
  }

  Future<List<Juz>> fetchJuzs() async {
    final response = await _dio.get(ApiConstants.juzs);
    final items = response.data['juzs'] as List;
    return items.map((j) => Juz.fromJson(j as Map<String, dynamic>)).toList();
  }
}

class _RetryInterceptor extends Interceptor {
  _RetryInterceptor(this._dio);
  final Dio _dio;
  static const int maxRetries = 3;

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    final retryCount = err.requestOptions.extra['retry_count'] as int? ?? 0;
    if (retryCount < maxRetries &&
        (err.type == DioExceptionType.connectionTimeout ||
            err.type == DioExceptionType.receiveTimeout ||
            err.type == DioExceptionType.connectionError)) {
      await Future.delayed(Duration(seconds: (retryCount + 1) * 2));
      err.requestOptions.extra['retry_count'] = retryCount + 1;
      try {
        final response = await _dio.fetch(err.requestOptions);
        handler.resolve(response);
        return;
      } catch (_) {}
    }
    handler.next(err);
  }
}

class TranslationResource {
  const TranslationResource({
    required this.id,
    required this.name,
    required this.authorName,
    required this.language,
    required this.slug,
  });

  final int id;
  final String name;
  final String authorName;
  final String language;
  final String slug;

  factory TranslationResource.fromJson(Map<String, dynamic> json) {
    return TranslationResource(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      authorName: json['author_name'] as String? ?? '',
      language: (json['language_name'] as String? ?? '').toLowerCase(),
      slug: json['slug'] as String? ?? '',
    );
  }
}

class TafsirResource {
  const TafsirResource({
    required this.id,
    required this.name,
    required this.authorName,
    required this.language,
    required this.slug,
  });

  final int id;
  final String name;
  final String authorName;
  final String language;
  final String slug;

  factory TafsirResource.fromJson(Map<String, dynamic> json) {
    return TafsirResource(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      authorName: json['author_name'] as String? ?? '',
      language: (json['language_name'] as String? ?? '').toLowerCase(),
      slug: json['slug'] as String? ?? '',
    );
  }
}

class SearchResult {
  const SearchResult({
    required this.verseKey,
    required this.verseNumber,
    required this.chapterId,
    required this.text,
    this.translation,
    this.chapterNameSimple,
  });

  final String verseKey;
  final int verseNumber;
  final int chapterId;
  final String text;
  final String? translation;
  final String? chapterNameSimple;

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      verseKey: json['verse_key'] as String? ?? '',
      verseNumber: json['verse_number'] as int? ?? 0,
      chapterId: json['chapter_id'] as int? ?? 0,
      text: json['text'] as String? ?? '',
      translation: json['translations']?.first?['text'] as String?,
      chapterNameSimple: json['chapter_name_simple'] as String?,
    );
  }
}

class Juz {
  const Juz({
    required this.id,
    required this.juzNumber,
    required this.versesCount,
    required this.firstVerseId,
    required this.lastVerseId,
  });

  final int id;
  final int juzNumber;
  final int versesCount;
  final int firstVerseId;
  final int lastVerseId;

  factory Juz.fromJson(Map<String, dynamic> json) {
    return Juz(
      id: json['id'] as int? ?? 0,
      juzNumber: json['juz_number'] as int? ?? 0,
      versesCount: json['verses_count'] as int? ?? 0,
      firstVerseId: json['first_verse_id'] as int? ?? 0,
      lastVerseId: json['last_verse_id'] as int? ?? 0,
    );
  }
}

final quranApiClientProvider = Provider<QuranApiClient>((ref) => QuranApiClient());
