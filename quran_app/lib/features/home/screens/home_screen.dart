import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/theme/app_colors.dart';
import '../../quran/providers/quran_provider.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  Map<String, dynamic>? _lastRead;

  @override
  void initState() {
    super.initState();
    _loadLastRead();
  }

  Future<void> _loadLastRead() async {
    final position = await DatabaseHelper.instance.getLastReadingPosition();
    if (mounted) setState(() => _lastRead = position);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context, isDark),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildLastReadCard(context, theme),
                const SizedBox(height: 16),
                _buildQuickActions(context, theme),
                const SizedBox(height: 24),
                _buildSurahGrid(context, theme),
                const SizedBox(height: 80),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  SliverAppBar _buildAppBar(BuildContext context, bool isDark) {
    return SliverAppBar(
      floating: true,
      pinned: false,
      expandedHeight: 160,
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AppColors.primary, AppColors.primaryDark],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            AppConstants.appName,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => context.push('/search'),
                        icon: const Icon(Icons.search, color: Colors.white, size: 26),
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Text(
                    'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontFamily: AppConstants.fontUthmanic,
                      height: 1.8,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLastReadCard(BuildContext context, ThemeData theme) {
    if (_lastRead == null) return const SizedBox.shrink();
    final surahName = _lastRead!['surah_name'] as String? ?? '';
    final verseKey = _lastRead!['verse_key'] as String? ?? '';
    final surahId = _lastRead!['surah_id'] as int? ?? 1;

    return GestureDetector(
      onTap: () {
        final parts = verseKey.split(':');
        context.push('/quran/$surahId?verse=${parts.lastOrNull}');
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF1A7F64), Color(0xFF2AAF8A)],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_stories, color: Colors.white, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Continue Reading',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    surahName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Verse $verseKey',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context, ThemeData theme) {
    final actions = [
      (icon: Icons.menu_book, label: 'Surahs', color: AppColors.primary, route: '/quran'),
      (icon: Icons.search, label: 'Search', color: AppColors.info, route: '/search'),
      (icon: Icons.access_time, label: 'Prayer', color: AppColors.fajrColor, route: '/prayer'),
      (icon: Icons.explore, label: 'Qibla', color: AppColors.gold, route: '/qibla'),
    ];

    final aiActions = [
      (icon: Icons.auto_awesome, label: 'AI Search', color: AppColors.primaryLight, route: '/semantic-search'),
      (icon: Icons.psychology, label: 'Hifz', color: AppColors.gold, route: '/hifz'),
      (icon: Icons.mic, label: 'Recite', color: const Color(0xFF8B5CF6), route: '/recitation/1:1'),
      (icon: Icons.camera_alt_outlined, label: 'Scanner', color: AppColors.info, route: '/scanner'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Core actions row
        Row(
          children: actions.map((action) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => context.go(action.route),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: action.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: action.color.withOpacity(0.2)),
                    ),
                    child: Column(
                      children: [
                        Icon(action.icon, color: action.color, size: 24),
                        const SizedBox(height: 6),
                        Text(
                          action.label,
                          style: TextStyle(
                            color: action.color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 10),

        // AI features row
        Row(
          children: aiActions.map((action) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: GestureDetector(
                  onTap: () => context.push(action.route),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          action.color.withOpacity(0.12),
                          action.color.withOpacity(0.06),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: action.color.withOpacity(0.25)),
                    ),
                    child: Column(
                      children: [
                        Stack(
                          alignment: Alignment.topRight,
                          children: [
                            Icon(action.icon, color: action.color, size: 22),
                            Positioned(
                              top: -2,
                              right: -2,
                              child: Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.primaryLight,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(
                          action.label,
                          style: TextStyle(
                            color: action.color,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildSurahGrid(BuildContext context, ThemeData theme) {
    final surahsAsync = ref.watch(surahListProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Surahs', style: theme.textTheme.headlineSmall),
            TextButton(
              onPressed: () => context.go('/quran'),
              child: const Text('View All'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        surahsAsync.when(
          data: (surahs) => ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: surahs.take(10).length,
            itemBuilder: (context, index) {
              final surah = surahs[index];
              return _SurahListTile(surah: surah);
            },
          ),
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Center(
            child: Text('Error loading surahs: $e',
                style: theme.textTheme.bodyMedium),
          ),
        ),
      ],
    );
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }
}

class _SurahListTile extends StatelessWidget {
  const _SurahListTile({required this.surah});
  final surah;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => context.push('/quran/${surah.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: theme.colorScheme.outline.withOpacity(0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${surah.id}',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(surah.nameSimple,
                      style: theme.textTheme.titleMedium),
                  Text(
                    '${surah.versesCount} verses • ${surah.revelationType}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              surah.nameArabic,
              style: TextStyle(
                fontFamily: AppConstants.fontUthmanic,
                fontSize: 18,
                color: AppColors.primary,
              ),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
      ),
    );
  }
}
