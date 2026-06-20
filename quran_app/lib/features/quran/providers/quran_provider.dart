import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/quran_api_client.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/models/surah.dart';
import '../../../core/models/verse.dart';
import '../../../core/providers/connectivity_provider.dart';
import '../../../core/providers/settings_provider.dart';

final surahListProvider = FutureProvider<List<Surah>>((ref) async {
  final db = DatabaseHelper.instance;
  final isOnline = ref.watch(isOnlineProvider);

  if (await db.hasCachedSurahs()) {
    final cached = await db.getCachedSurahs();
    if (cached.isNotEmpty) {
      if (isOnline) {
        // Refresh in background
        final api = ref.read(quranApiClientProvider);
        api.fetchChapters().then(db.cacheSurahs).ignore();
      }
      return cached;
    }
  }

  final api = ref.read(quranApiClientProvider);
  final surahs = await api.fetchChapters();
  await db.cacheSurahs(surahs);
  return surahs;
});

class ChapterVersesNotifier extends StateNotifier<AsyncValue<List<Verse>>> {
  ChapterVersesNotifier(this._ref, this._chapterId) : super(const AsyncValue.loading()) {
    load();
  }

  final Ref _ref;
  final int _chapterId;

  Future<void> load() async {
    state = const AsyncValue.loading();
    try {
      final db = DatabaseHelper.instance;
      final settings = _ref.read(settingsProvider);
      final isOnline = _ref.read(isOnlineProvider);

      if (isOnline) {
        final api = _ref.read(quranApiClientProvider);
        final verses = await api.fetchVersesByChapter(
          _chapterId,
          translationId: settings.translationId,
          tafsirId: settings.showTafsir ? settings.tafsirId : null,
          includeWords: settings.showWordByWord,
        );
        await db.cacheVerses(verses);
        state = AsyncValue.data(verses);
      } else {
        final cached = await db.getCachedVersesByChapter(
          _chapterId,
          translationId: settings.translationId,
        );
        state = AsyncValue.data(cached);
      }
    } catch (e, st) {
      // Try offline fallback
      try {
        final db = DatabaseHelper.instance;
        final settings = _ref.read(settingsProvider);
        final cached = await db.getCachedVersesByChapter(
          _chapterId,
          translationId: settings.translationId,
        );
        if (cached.isNotEmpty) {
          state = AsyncValue.data(cached);
          return;
        }
      } catch (_) {}
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => load();
}

final chapterVersesProvider = StateNotifierProvider.family<
    ChapterVersesNotifier, AsyncValue<List<Verse>>, int>((ref, chapterId) {
  return ChapterVersesNotifier(ref, chapterId);
});

final searchQueryProvider = StateProvider<String>((ref) => '');

final searchResultsProvider = FutureProvider.autoDispose<List<SearchResult>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.trim().isEmpty) return [];
  final api = ref.read(quranApiClientProvider);
  return api.search(query.trim());
});

final currentPlayingVerseProvider = StateProvider<String?>((ref) => null);
