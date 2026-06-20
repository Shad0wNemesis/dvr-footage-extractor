import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/surah.dart';
import '../../../core/models/verse.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/database/database_helper.dart';
import '../providers/quran_provider.dart';
import '../../audio/providers/audio_provider.dart';
import '../../audio/widgets/mini_player_widget.dart';
import '../widgets/verse_widget.dart';

class QuranReaderScreen extends ConsumerStatefulWidget {
  const QuranReaderScreen({
    super.key,
    required this.surahId,
    this.initialVerse,
  });

  final int surahId;
  final int? initialVerse;

  @override
  ConsumerState<QuranReaderScreen> createState() => _QuranReaderScreenState();
}

class _QuranReaderScreenState extends ConsumerState<QuranReaderScreen> {
  final _scrollController = ScrollController();
  final _itemKeys = <int, GlobalKey>{};
  bool _showOptions = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.initialVerse != null) {
        _scrollToVerse(widget.initialVerse!);
      }
    });
  }

  void _scrollToVerse(int verseNumber) {
    final key = _itemKeys[verseNumber];
    if (key?.currentContext != null) {
      Scrollable.ensureVisible(key!.currentContext!,
          duration: const Duration(milliseconds: 500), curve: Curves.easeInOut);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final versesAsync = ref.watch(chapterVersesProvider(widget.surahId));
    final surahsAsync = ref.watch(surahListProvider);
    final settings = ref.watch(settingsProvider);
    final audio = ref.watch(audioProvider);
    final theme = Theme.of(context);

    final surah = surahsAsync.valueOrNull
        ?.firstWhere((s) => s.id == widget.surahId, orElse: () => _emptySurah());

    return Scaffold(
      body: NestedScrollView(
        controller: _scrollController,
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            pinned: true,
            floating: false,
            expandedHeight: surah != null ? 140 : 60,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.headphones_outlined),
                onPressed: () => _showReciterSheet(context),
                tooltip: 'Play Surah',
              ),
              IconButton(
                icon: Icon(_showOptions ? Icons.close : Icons.more_vert),
                onPressed: () => setState(() => _showOptions = !_showOptions),
              ),
            ],
            flexibleSpace: surah != null
                ? FlexibleSpaceBar(
                    background: _SurahHeader(surah: surah),
                  )
                : null,
            title: surah != null
                ? Text(surah.nameSimple,
                    style: const TextStyle(fontWeight: FontWeight.w700))
                : null,
          ),
          if (_showOptions)
            SliverToBoxAdapter(child: _OptionsBar(settings: settings)),
        ],
        body: Stack(
          children: [
            versesAsync.when(
              data: (verses) {
                _saveReadingPosition(surah, verses);
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: verses.length + (surah?.bismillahPre == true && widget.surahId != 1 && widget.surahId != 9 ? 1 : 0),
                  itemBuilder: (context, index) {
                    final hasBismillah = surah?.bismillahPre == true &&
                        widget.surahId != 1 &&
                        widget.surahId != 9;
                    if (hasBismillah && index == 0) {
                      return _BismillahWidget();
                    }
                    final verseIndex = hasBismillah ? index - 1 : index;
                    final verse = verses[verseIndex];
                    _itemKeys[verse.verseNumber] = GlobalKey();
                    return VerseWidget(
                      key: _itemKeys[verse.verseNumber],
                      verse: verse,
                      settings: settings,
                      isPlaying: audio.currentVerseKey == verse.verseKey && audio.isPlaying,
                      onPlayTap: () => ref
                          .read(audioProvider.notifier)
                          .playVerse(verse.verseKey,
                              reciterId: settings.reciterId),
                      onBookmarkTap: () => _toggleBookmark(verse, surah),
                      onTafsirTap: () =>
                          context.push('/tafsir/${verse.verseKey}'),
                      onShareTap: () => _shareVerse(verse, surah),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                    const SizedBox(height: 12),
                    Text('Failed to load verses', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () => ref.read(chapterVersesProvider(widget.surahId).notifier).refresh(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            ),
            if (audio.currentSurahId == widget.surahId || audio.currentVerseKey != null)
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: MiniPlayerWidget(),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveReadingPosition(surah, List<Verse> verses) async {
    if (surah == null || verses.isEmpty) return;
    await DatabaseHelper.instance.saveReadingPosition(
      verses.first.verseKey,
      widget.surahId,
      surah.nameSimple,
      1,
    );
  }

  Future<void> _toggleBookmark(Verse verse, surah) async {
    final db = DatabaseHelper.instance;
    final isBookmarked = await db.isBookmarked(verse.verseKey);
    if (isBookmarked) {
      await db.removeBookmark(verse.verseKey);
    } else {
      await db.addBookmark(
        // ignore: invalid_use_of_internal_member
        _buildBookmark(verse, surah),
      );
    }
  }

  dynamic _buildBookmark(Verse verse, surah) {
    return null; // Implemented via DatabaseHelper directly in bookmark feature
  }

  void _shareVerse(Verse verse, surah) {
    // Share implementation
  }

  void _showReciterSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _ReciterSheet(surahId: widget.surahId),
    );
  }

  Surah _emptySurah() => const Surah(
        id: 1, revelationOrder: 1, revelationType: 'Makki',
        versesCount: 7, pagesStart: 1, pagesEnd: 1,
        nameSimple: '', nameComplex: '', nameArabic: '',
        nameTranslation: '',
      );
}

class _SurahHeader extends StatelessWidget {
  const _SurahHeader({required this.surah});
  final Surah surah;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    surah.nameSimple,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${surah.nameTranslation} • ${surah.versesCount} Verses',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      surah.revelationType,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              Text(
                surah.nameArabic,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontFamily: AppConstants.fontUthmanic,
                ),
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BismillahWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      alignment: Alignment.center,
      child: const Text(
        'بِسۡمِ ٱللَّهِ ٱلرَّحۡمَٰنِ ٱلرَّحِيمِ',
        style: TextStyle(
          fontFamily: AppConstants.fontUthmanic,
          fontSize: 26,
          color: AppColors.primary,
          height: 2.0,
        ),
        textDirection: TextDirection.rtl,
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _OptionsBar extends ConsumerWidget {
  const _OptionsBar({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(settingsProvider.notifier);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardTheme.color,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          _OptionChip(
            label: 'Translation',
            isActive: settings.showTranslation,
            onTap: notifier.toggleTranslation,
          ),
          const SizedBox(width: 8),
          _OptionChip(
            label: 'Tafsir',
            isActive: settings.showTafsir,
            onTap: notifier.toggleTafsir,
          ),
          const SizedBox(width: 8),
          _OptionChip(
            label: 'Word-by-Word',
            isActive: settings.showWordByWord,
            onTap: notifier.toggleWordByWord,
          ),
        ],
      ),
    );
  }
}

class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.primary.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive ? AppColors.primary : Colors.grey.withOpacity(0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isActive ? AppColors.primary : Colors.grey,
          ),
        ),
      ),
    );
  }
}

class _ReciterSheet extends ConsumerWidget {
  const _ReciterSheet({required this.surahId});
  final int surahId;

  static const _reciters = [
    (id: 7, name: 'Mishary Rashid Al-Afasy'),
    (id: 1, name: 'AbdurRahmaan As-Sudais'),
    (id: 2, name: 'Abu Bakr Al-Shatri'),
    (id: 3, name: 'Nasser Al-Qatami'),
    (id: 4, name: 'Yasser Ad-Dossari'),
    (id: 5, name: 'Hani Ar-Rifai'),
    (id: 6, name: 'Maher Al-Muaiqly'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.watch(audioProvider);
    return Container(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose Reciter',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          ..._reciters.map((r) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                  child: const Icon(Icons.mic, color: AppColors.primary, size: 18),
                ),
                title: Text(r.name, style: const TextStyle(fontSize: 14)),
                trailing: audio.currentSurahId == surahId &&
                        audio.currentReciterId == r.id &&
                        audio.isPlaying
                    ? const Icon(Icons.equalizer, color: AppColors.primary)
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  ref.read(audioProvider.notifier).playSurah(surahId, reciterId: r.id);
                },
              )),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
