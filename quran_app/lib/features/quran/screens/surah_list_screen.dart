import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/surah.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../providers/quran_provider.dart';

enum SurahListView { list, grid }
enum SurahFilter { all, makki, madani }

final _viewProvider = StateProvider<SurahListView>((ref) => SurahListView.list);
final _filterProvider = StateProvider<SurahFilter>((ref) => SurahFilter.all);
final _searchProvider = StateProvider<String>((ref) => '');

class SurahListScreen extends ConsumerWidget {
  const SurahListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final surahsAsync = ref.watch(surahListProvider);
    final view = ref.watch(_viewProvider);
    final filter = ref.watch(_filterProvider);
    final searchQuery = ref.watch(_searchProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('The Noble Quran'),
        actions: [
          IconButton(
            icon: Icon(view == SurahListView.list ? Icons.grid_view : Icons.list),
            onPressed: () => ref.read(_viewProvider.notifier).state =
                view == SurahListView.list ? SurahListView.grid : SurahListView.list,
          ),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => context.push('/search'),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  onChanged: (v) => ref.read(_searchProvider.notifier).state = v,
                  decoration: InputDecoration(
                    hintText: 'Search surah name...',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: SurahFilter.values.map((f) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_filterLabel(f)),
                        selected: filter == f,
                        onSelected: (_) =>
                            ref.read(_filterProvider.notifier).state = f,
                        selectedColor: AppColors.primary.withOpacity(0.15),
                        checkmarkColor: AppColors.primary,
                      ),
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      body: surahsAsync.when(
        data: (surahs) {
          final filtered = surahs.where((s) {
            final matchesFilter = filter == SurahFilter.all ||
                (filter == SurahFilter.makki && s.isMakki) ||
                (filter == SurahFilter.madani && s.isMadani);
            final matchesSearch = searchQuery.isEmpty ||
                s.nameSimple.toLowerCase().contains(searchQuery.toLowerCase()) ||
                s.nameTranslation.toLowerCase().contains(searchQuery.toLowerCase()) ||
                s.nameArabic.contains(searchQuery) ||
                s.id.toString() == searchQuery;
            return matchesFilter && matchesSearch;
          }).toList();

          if (view == SurahListView.list) {
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: filtered.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 68),
              itemBuilder: (context, index) =>
                  _SurahTile(surah: filtered[index]),
            );
          } else {
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) =>
                  _SurahCard(surah: filtered[index]),
            );
          }
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text('Failed to load surahs', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(surahListProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _filterLabel(SurahFilter f) {
    switch (f) {
      case SurahFilter.all: return 'All (114)';
      case SurahFilter.makki: return 'Makki';
      case SurahFilter.madani: return 'Madani';
    }
  }
}

class _SurahTile extends StatelessWidget {
  const _SurahTile({required this.surah});
  final Surah surah;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => context.push('/quran/${surah.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            _NumberBadge(number: surah.id),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(surah.nameSimple,
                      style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    '${surah.nameTranslation} • ${surah.versesCount} verses',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  surah.nameArabic,
                  style: TextStyle(
                    fontFamily: AppConstants.fontUthmanic,
                    fontSize: 20,
                    color: theme.colorScheme.primary,
                  ),
                  textDirection: TextDirection.rtl,
                ),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: surah.isMakki
                        ? AppColors.fajrColor.withOpacity(0.1)
                        : AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    surah.revelationType,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: surah.isMakki ? AppColors.fajrColor : AppColors.success,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SurahCard extends StatelessWidget {
  const _SurahCard({required this.surah});
  final Surah surah;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => context.push('/quran/${surah.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NumberBadge(number: surah.id, small: true),
                Text(
                  surah.nameArabic,
                  style: TextStyle(
                    fontFamily: AppConstants.fontUthmanic,
                    fontSize: 18,
                    color: theme.colorScheme.primary,
                  ),
                  textDirection: TextDirection.rtl,
                ),
              ],
            ),
            const Spacer(),
            Text(surah.nameSimple,
                style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600)),
            Text('${surah.versesCount} verses',
                style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.number, this.small = false});
  final int number;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final size = small ? 32.0 : 42.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$number',
          style: TextStyle(
            color: AppColors.primary,
            fontSize: small ? 12 : 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
