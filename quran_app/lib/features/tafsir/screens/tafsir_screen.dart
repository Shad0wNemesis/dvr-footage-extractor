import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/quran_api_client.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';

final _tafsirDataProvider =
    FutureProvider.family<List<dynamic>, String>((ref, verseKey) async {
  final api = ref.read(quranApiClientProvider);
  final settings = ref.read(settingsProvider);
  final verses = await api.fetchVersesByChapter(
    int.parse(verseKey.split(':')[0]),
    tafsirId: settings.tafsirId,
    includeWords: false,
    perPage: 1,
  );
  final verse = verses.firstWhere(
    (v) => v.verseKey == verseKey,
    orElse: () => verses.first,
  );
  return verse.tafsirs;
});

class TafsirScreen extends ConsumerWidget {
  const TafsirScreen({super.key, required this.verseKey});
  final String verseKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tafsirAsync = ref.watch(_tafsirDataProvider(verseKey));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tafsir'),
            Text(
              'Verse $verseKey',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.appBarTheme.foregroundColor?.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
      body: tafsirAsync.when(
        data: (tafsirs) {
          if (tafsirs.isEmpty) {
            return const Center(child: Text('No tafsir available for this verse.'));
          }
          final tafsir = tafsirs.first;
          final cleanText = (tafsir.text as String).replaceAll(RegExp(r'<[^>]*>'), '');
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Verse key badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.library_books, size: 16, color: AppColors.primary),
                      const SizedBox(width: 6),
                      Text(
                        tafsir.resourceName as String,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Tafsir text
                Text(
                  cleanText,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.8),
                ),
                const SizedBox(height: 40),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              const Text('Failed to load tafsir'),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(_tafsirDataProvider(verseKey)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
