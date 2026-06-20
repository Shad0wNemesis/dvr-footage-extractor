/// State providers for the Hifz (memorization) feature.
library hifz_provider;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/daos/user_dao.dart';
import '../../../core/providers/database_provider.dart';

// ── Stream providers backed by the Drift DB ───────────────────────────────────

/// Streams memorization items whose [nextReview] <= now, ordered by priority.
/// This is the source of truth for the Hifz review session.
final hifzDueTodayProvider = StreamProvider.autoDispose<List<MemorizationItem>>(
  (ref) => ref.watch(userDaoProvider).watchDueTodayItems(),
  name: 'hifzDueTodayProvider',
);

/// Future of ALL memorization items (for the Hifz library / stats screen).
final hifzAllItemsProvider = FutureProvider.autoDispose<List<MemorizationItem>>(
  (ref) => ref.watch(userDaoProvider).allMemorizationItems(),
  name: 'hifzAllItemsProvider',
);

// ── Review session state ──────────────────────────────────────────────────────

/// Tracks the index of the currently displayed card within a review session.
///
/// Resets to 0 when the user starts a new session from [HifzScreen].
final hifzSessionIndexProvider = StateProvider.autoDispose<int>(
  (ref) => 0,
  name: 'hifzSessionIndexProvider',
);

/// Whether the current card is "flipped" (Arabic + translation revealed).
final hifzCardRevealedProvider = StateProvider.autoDispose<bool>(
  (ref) => false,
  name: 'hifzCardRevealedProvider',
);

// ── Actions ───────────────────────────────────────────────────────────────────

/// Records an SM-2 review result and advances to the next card.
///
/// [grade] must be 0–5:
///   0 = complete blank / again
///   2 = incorrect but familiar
///   4 = correct with effort
///   5 = instant recall
Future<void> submitHifzReview(
  WidgetRef ref, {
  required String verseKey,
  required int grade,
}) async {
  final userDao = ref.read(userDaoProvider);
  await userDao.recordReview(verseKey: verseKey, grade: grade);

  // Advance card and un-reveal for the next one.
  ref.read(hifzSessionIndexProvider.notifier).state++;
  ref.read(hifzCardRevealedProvider.notifier).state = false;
}
