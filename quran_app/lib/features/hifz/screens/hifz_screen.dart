/// Hifz (Memorization) screen — SM-2 spaced-repetition review session.
///
/// Flow:
/// 1. Load today's due items from the Drift DB via [hifzDueTodayProvider].
/// 2. Show each item as a flip card:
///    - Front: verse key + Arabic text (blurred)
///    - Back: Arabic revealed + English translation
/// 3. After flipping, the user rates recall difficulty (Again / Hard / Good / Easy).
/// 4. [UserDao.recordReview()] updates the SM-2 scheduling fields.
/// 5. Show a session-complete summary when all items are reviewed.
library hifz_screen;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/database/daos/quran_dao.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/hifz_provider.dart';

class HifzScreen extends ConsumerWidget {
  const HifzScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueAsync = ref.watch(hifzDueTodayProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hifz Review'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          dueAsync.whenOrNull(
                data: (items) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${items.length} due',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ) ??
              const SizedBox.shrink(),
        ],
      ),
      body: dueAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const _AllDoneView();
          }

          final sessionIndex = ref.watch(hifzSessionIndexProvider);

          // All items reviewed → show summary
          if (sessionIndex >= items.length) {
            return _SessionSummary(totalReviewed: items.length);
          }

          final currentItem = items[sessionIndex];
          final isRevealed = ref.watch(hifzCardRevealedProvider);

          return Column(
            children: [
              // Progress bar
              LinearProgressIndicator(
                value: sessionIndex / items.length,
                backgroundColor: Colors.transparent,
                color: AppColors.primary,
                minHeight: 3,
              ),

              // Review card
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _ReviewCard(
                    item: currentItem,
                    isRevealed: isRevealed,
                    onReveal: () => ref
                        .read(hifzCardRevealedProvider.notifier)
                        .state = true,
                  ),
                ),
              ),

              // Rating buttons (only visible after reveal)
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 300),
                crossFadeState: isRevealed
                    ? CrossFadeState.showFirst
                    : CrossFadeState.showSecond,
                firstChild: _RatingBar(
                  onRate: (grade) => submitHifzReview(
                    ref,
                    verseKey: currentItem.verseKey,
                    grade: grade,
                  ),
                ),
                secondChild: const SizedBox.shrink(),
              ),

              const SizedBox(height: 16),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
      ),
    );
  }
}

// ── Review card ───────────────────────────────────────────────────────────────

class _ReviewCard extends ConsumerWidget {
  const _ReviewCard({
    required this.item,
    required this.isRevealed,
    required this.onReveal,
  });

  final MemorizationItem item;
  final bool isRevealed;
  final VoidCallback onReveal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final quranDao = ref.watch(quranDaoProvider);

    return FutureBuilder<Ayah?>(
      future: quranDao.ayahByKey(item.verseKey),
      builder: (context, snapshot) {
        final ayah = snapshot.data;

        return GestureDetector(
          onTap: isRevealed ? null : onReveal,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.cardTheme.color,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isRevealed
                    ? AppColors.primary.withOpacity(0.3)
                    : theme.colorScheme.outline.withOpacity(0.2),
                width: isRevealed ? 1.5 : 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Verse key pill
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    item.verseKey,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Arabic text
                if (ayah != null)
                  AnimatedOpacity(
                    opacity: isRevealed ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 400),
                    child: Text(
                      ayah.textUthmani,
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: AppConstants.fontUthmanic,
                        fontSize: 24,
                        height: 2.0,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  )
                else
                  Container(
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),

                if (!isRevealed) ...[
                  const Spacer(),
                  Column(
                    children: [
                      Icon(
                        Icons.touch_app_outlined,
                        size: 36,
                        color: AppColors.primary.withOpacity(0.5),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap to reveal',
                        style: TextStyle(
                          color: AppColors.lightTextSecondary,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                ],

                // Translation (revealed only)
                if (isRevealed && ayah != null) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  Text(
                    ayah.textSimpleClean,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(height: 1.6, color: AppColors.lightTextSecondary),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Rating bar ────────────────────────────────────────────────────────────────

class _RatingBar extends StatelessWidget {
  const _RatingBar({required this.onRate});
  final ValueChanged<int> onRate;

  static const _buttons = [
    (label: 'Again', grade: 0, color: AppColors.error),
    (label: 'Hard', grade: 2, color: AppColors.warning),
    (label: 'Good', grade: 4, color: AppColors.info),
    (label: 'Easy', grade: 5, color: AppColors.success),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: _buttons.map((b) {
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FilledButton(
                onPressed: () => onRate(b.grade),
                style: FilledButton.styleFrom(
                  backgroundColor: b.color.withOpacity(0.15),
                  foregroundColor: b.color,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: b.color.withOpacity(0.3)),
                  ),
                ),
                child: Text(
                  b.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: b.color,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Empty / summary states ────────────────────────────────────────────────────

class _AllDoneView extends StatelessWidget {
  const _AllDoneView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline,
                size: 72, color: AppColors.success),
            const SizedBox(height: 16),
            const Text(
              'Nothing due today!',
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'All your memorization items are up to date.\nCome back tomorrow for your next reviews.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.go('/quran'),
              icon: const Icon(Icons.menu_book),
              label: const Text('Go to Quran'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionSummary extends StatelessWidget {
  const _SessionSummary({required this.totalReviewed});
  final int totalReviewed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, size: 72, color: AppColors.gold),
            const SizedBox(height: 16),
            const Text(
              'Session Complete!',
              style: TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'You reviewed $totalReviewed ${totalReviewed == 1 ? 'verse' : 'verses'}. '
              'Your next reviews are scheduled by the SM-2 algorithm.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () => context.pop(),
              icon: const Icon(Icons.home_outlined),
              label: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}
