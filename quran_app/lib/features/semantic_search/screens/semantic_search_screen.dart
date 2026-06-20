/// AI-powered semantic search screen.
///
/// Uses the FAISS vector index + optional LLM RAG pipeline on the local AI
/// microservice to find Ayahs by meaning rather than exact keyword match.
///
/// Example queries:
///   "verses about patience in hardship"
///   "what does the Quran say about forgiveness"
///   "صبر"  (Arabic works too via the multilingual embedding model)
library semantic_search_screen;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/ai/ai_service_client.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/ai_service_provider.dart';
import '../../../core/providers/database_provider.dart';
import '../../../core/theme/app_colors.dart';

class SemanticSearchScreen extends ConsumerStatefulWidget {
  const SemanticSearchScreen({super.key});

  @override
  ConsumerState<SemanticSearchScreen> createState() =>
      _SemanticSearchScreenState();
}

class _SemanticSearchScreenState extends ConsumerState<SemanticSearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final query = value.trim();
    ref.read(semanticSearchQueryProvider.notifier).state = query;

    if (query.isNotEmpty) {
      ref.read(userDaoProvider).recordSearch(
            query: query,
            searchType: 'semantic',
            resultsCount: 0,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(semanticSearchQueryProvider);
    final resultsAsync = ref.watch(semanticSearchProvider(query));
    final healthAsync = ref.watch(aiServiceHealthProvider);
    final isOnline = healthAsync.valueOrNull ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: TextField(
          controller: _controller,
          focusNode: _focusNode,
          onSubmitted: _submit,
          onChanged: (v) {
            Future.delayed(const Duration(milliseconds: 700), () {
              if (_controller.text == v) _submit(v);
            });
          },
          decoration: InputDecoration(
            hintText: 'Search by meaning…',
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            suffixIcon: query.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _controller.clear();
                      _submit('');
                    },
                  )
                : null,
          ),
          textInputAction: TextInputAction.search,
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: _ServiceBadge(isOnline: isOnline),
        ),
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: query.isEmpty
            ? _SuggestionsPanel(
                key: const ValueKey('suggestions'),
                onTap: (s) {
                  _controller.text = s;
                  _submit(s);
                },
              )
            : resultsAsync.when(
                key: ValueKey(query),
                data: (response) {
                  if (response == null || response.results.isEmpty) {
                    return _EmptyState(query: query, isOffline: !isOnline);
                  }
                  return _ResultsView(response: response);
                },
                loading: () => const _SearchingState(),
                error: (e, _) => _ErrorState(error: e, isOffline: !isOnline),
              ),
      ),
    );
  }
}

// ── Service badge ─────────────────────────────────────────────────────────────

class _ServiceBadge extends StatelessWidget {
  const _ServiceBadge({required this.isOnline});
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      color: isOnline
          ? AppColors.success.withOpacity(0.08)
          : AppColors.warning.withOpacity(0.1),
      child: Row(
        children: [
          Icon(
            isOnline ? Icons.memory : Icons.wifi_off,
            size: 12,
            color: isOnline ? AppColors.success : AppColors.warning,
          ),
          const SizedBox(width: 6),
          Text(
            isOnline
                ? 'AI Semantic Search — powered by local FAISS'
                : 'AI service offline — start the AI microservice',
            style: TextStyle(
              fontSize: 11,
              color: isOnline ? AppColors.success : AppColors.warning,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Suggestions ───────────────────────────────────────────────────────────────

class _SuggestionsPanel extends StatelessWidget {
  const _SuggestionsPanel({super.key, required this.onTap});
  final ValueChanged<String> onTap;

  static const _suggestions = [
    'patience in hardship',
    'mercy and forgiveness',
    'Day of Judgement',
    'gratitude to Allah',
    'paradise description',
    'prayer and worship',
    'Prophet Ibrahim story',
    'knowledge and wisdom',
    'charity and giving',
    'صبر',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              const SizedBox(width: 8),
              Text('Try searching by meaning', style: theme.textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Unlike keyword search, semantic search finds verses that share '
            'the same idea even when they use different words.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: AppColors.lightTextSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _suggestions
                .map(
                  (s) => ActionChip(
                    label: Text(s),
                    onPressed: () => onTap(s),
                    avatar: const Icon(Icons.search, size: 14),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Results ───────────────────────────────────────────────────────────────────

class _ResultsView extends StatelessWidget {
  const _ResultsView({required this.response});
  final AiSearchResponse response;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        // LLM-generated grounded answer card (if available)
        if (response.answer != null && response.answer!.isNotEmpty)
          SliverToBoxAdapter(
            child: _AnswerCard(answer: response.answer!),
          ),

        // Timing info
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${response.results.length} results',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.lightTextSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                Text(
                  '${response.totalMs.toStringAsFixed(0)} ms',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Ayah result cards
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) =>
                _AyahCard(result: response.results[index]),
            childCount: response.results.length,
          ),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

// ── LLM answer card ───────────────────────────────────────────────────────────

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.answer});
  final String answer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1A3A2E), Color(0xFF0F2620)],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primary.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome,
                    size: 14, color: AppColors.primaryLight),
                const SizedBox(width: 6),
                Text(
                  'AI Answer',
                  style: TextStyle(
                    color: AppColors.primaryLight,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              answer,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single Ayah result card ───────────────────────────────────────────────────

class _AyahCard extends StatelessWidget {
  const _AyahCard({required this.result});
  final AiAyahResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scorePercent = (result.relevanceScore * 100).round();

    return GestureDetector(
      onTap: () => context.push('/quran/${result.surahId}?verse=${result.ayahNumber}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.cardTheme.color,
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: theme.colorScheme.outline.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    result.verseKey,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (result.surahName.isNotEmpty)
                  Text(
                    result.surahName,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: AppColors.lightTextSecondary),
                  ),
                const Spacer(),
                _RelevanceBadge(score: scorePercent),
              ],
            ),

            const SizedBox(height: 12),

            // Arabic text
            if (result.textArabic.isNotEmpty)
              Text(
                result.textArabic,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: AppConstants.fontUthmanic,
                  fontSize: 20,
                  height: 1.8,
                  color: theme.colorScheme.onSurface,
                ),
              ),

            // English translation
            if (result.translationEn != null &&
                result.translationEn!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                result.translationEn!,
                style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            // Tafseer snippet
            if (result.tafseerSnippet != null &&
                result.tafseerSnippet!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border(
                    left: BorderSide(
                        color: AppColors.primary.withOpacity(0.4), width: 3),
                  ),
                ),
                child: Text(
                  result.tafseerSnippet!,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.lightTextSecondary, height: 1.5),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RelevanceBadge extends StatelessWidget {
  const _RelevanceBadge({required this.score});
  final int score;

  Color get _color {
    if (score >= 80) return AppColors.success;
    if (score >= 60) return AppColors.warning;
    return AppColors.lightTextSecondary;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$score%',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

// ── Empty / error states ──────────────────────────────────────────────────────

class _SearchingState extends StatelessWidget {
  const _SearchingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Searching semantically…',
              style: TextStyle(color: AppColors.lightTextSecondary)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query, required this.isOffline});
  final String query;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isOffline ? Icons.wifi_off : Icons.search_off,
              size: 56,
              color: AppColors.lightTextSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              isOffline ? 'AI Service Offline' : 'No results for "$query"',
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              isOffline
                  ? 'Start the AI microservice (docker compose up) to enable semantic search.'
                  : 'Try rephrasing your query or use different keywords.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.lightTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.isOffline});
  final Object error;
  final bool isOffline;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 48, color: AppColors.error),
            const SizedBox(height: 12),
            const Text('Search failed',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              isOffline
                  ? 'Cannot reach the AI microservice at port 8765.'
                  : error.toString(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: AppColors.lightTextSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
