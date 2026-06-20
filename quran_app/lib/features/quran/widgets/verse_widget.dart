import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/verse.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/database/database_helper.dart';

class VerseWidget extends ConsumerStatefulWidget {
  const VerseWidget({
    super.key,
    required this.verse,
    required this.settings,
    required this.isPlaying,
    required this.onPlayTap,
    required this.onBookmarkTap,
    required this.onTafsirTap,
    required this.onShareTap,
  });

  final Verse verse;
  final AppSettings settings;
  final bool isPlaying;
  final VoidCallback onPlayTap;
  final VoidCallback onBookmarkTap;
  final VoidCallback onTafsirTap;
  final VoidCallback onShareTap;

  @override
  ConsumerState<VerseWidget> createState() => _VerseWidgetState();
}

class _VerseWidgetState extends ConsumerState<VerseWidget>
    with SingleTickerProviderStateMixin {
  bool _isBookmarked = false;
  bool _showActions = false;
  late AnimationController _highlightController;
  late Animation<Color?> _highlightAnimation;

  @override
  void initState() {
    super.initState();
    _checkBookmark();
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _highlightAnimation = ColorTween(
      begin: Colors.transparent,
      end: AppColors.verseHighlight,
    ).animate(CurvedAnimation(parent: _highlightController, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(VerseWidget old) {
    super.didUpdateWidget(old);
    if (widget.isPlaying && !old.isPlaying) {
      _highlightController.forward();
    } else if (!widget.isPlaying && old.isPlaying) {
      _highlightController.reverse();
    }
  }

  Future<void> _checkBookmark() async {
    final bookmarked = await DatabaseHelper.instance.isBookmarked(widget.verse.verseKey);
    if (mounted) setState(() => _isBookmarked = bookmarked);
  }

  @override
  void dispose() {
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return AnimatedBuilder(
      animation: _highlightAnimation,
      builder: (context, child) {
        return Container(
          color: _highlightAnimation.value,
          child: child,
        );
      },
      child: GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          setState(() => _showActions = !_showActions);
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Verse header row
              Row(
                children: [
                  _VerseNumberBadge(number: widget.verse.verseNumber),
                  const Spacer(),
                  if (_showActions) ...[
                    _ActionButton(
                      icon: _isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
                      color: _isBookmarked ? AppColors.gold : null,
                      onTap: () async {
                        widget.onBookmarkTap();
                        setState(() => _isBookmarked = !_isBookmarked);
                      },
                    ),
                    _ActionButton(icon: Icons.headphones, onTap: widget.onPlayTap),
                    _ActionButton(icon: Icons.library_books_outlined, onTap: widget.onTafsirTap),
                    _ActionButton(icon: Icons.share_outlined, onTap: widget.onShareTap),
                    _ActionButton(
                      icon: Icons.copy_outlined,
                      onTap: () => Clipboard.setData(
                          ClipboardData(text: widget.verse.textUthmani)),
                    ),
                  ] else ...[
                    IconButton(
                      icon: Icon(
                        widget.isPlaying ? Icons.pause_circle : Icons.play_circle_outline,
                        color: AppColors.primary,
                        size: 28,
                      ),
                      onTap: widget.onPlayTap,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),

              // Arabic text
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.centerRight,
                child: Text(
                  widget.verse.textUthmani,
                  style: TextStyle(
                    fontFamily: widget.settings.arabicFontFamily,
                    fontSize: widget.settings.arabicFontSize,
                    height: 2.2,
                    color: theme.textTheme.bodyLarge?.color,
                    letterSpacing: 0,
                  ),
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                ),
              ),

              // Word-by-word
              if (widget.settings.showWordByWord && widget.verse.words.isNotEmpty)
                _WordByWordRow(words: widget.verse.words, settings: widget.settings),

              // Translation
              if (widget.settings.showTranslation && widget.verse.translations.isNotEmpty)
                _TranslationWidget(
                  text: widget.verse.translations.first.text,
                  fontSize: widget.settings.translationFontSize,
                ),

              // Tafsir (collapsed preview)
              if (widget.settings.showTafsir && widget.verse.tafsirs.isNotEmpty)
                _TafsirPreview(tafsir: widget.verse.tafsirs.first),

              const Divider(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerseNumberBadge extends StatelessWidget {
  const _VerseNumberBadge({required this.number});
  final int number;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          color: AppColors.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.onTap, this.color});
  final IconData icon;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, size: 20, color: color),
      onTap: onTap,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _WordByWordRow extends StatelessWidget {
  const _WordByWordRow({required this.words, required this.settings});
  final List<Word> words;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        alignment: WrapAlignment.end,
        direction: Axis.horizontal,
        textDirection: TextDirection.rtl,
        spacing: 4,
        runSpacing: 8,
        children: words.where((w) => !w.isEnd).map((word) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                word.codeV1,
                style: TextStyle(
                  fontFamily: settings.arabicFontFamily,
                  fontSize: 18,
                  color: AppColors.primary,
                ),
                textDirection: TextDirection.rtl,
              ),
              if (word.translation != null)
                Text(
                  word.translation!.text,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.textTheme.bodySmall?.color,
                  ),
                  textAlign: TextAlign.center,
                ),
            ],
          );
        }).toList(),
      ),
    );
  }
}

class _TranslationWidget extends StatelessWidget {
  const _TranslationWidget({required this.text, required this.fontSize});
  final String text;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Strip HTML tags
    final cleanText = text.replaceAll(RegExp(r'<[^>]*>'), '');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(color: AppColors.primary.withOpacity(0.4), width: 3),
        ),
      ),
      child: Text(
        cleanText,
        style: TextStyle(
          fontSize: fontSize,
          color: theme.textTheme.bodyMedium?.color,
          height: 1.6,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}

class _TafsirPreview extends StatefulWidget {
  const _TafsirPreview({required this.tafsir});
  final TafsirEntry tafsir;

  @override
  State<_TafsirPreview> createState() => _TafsirPreviewState();
}

class _TafsirPreviewState extends State<_TafsirPreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleanText = widget.tafsir.text.replaceAll(RegExp(r'<[^>]*>'), '');
    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: AppColors.gold.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gold.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.library_books, size: 14, color: AppColors.gold),
                const SizedBox(width: 6),
                Text('Tafsir: ${widget.tafsir.resourceName}',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.gold)),
                const Spacer(),
                Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16, color: AppColors.gold),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              cleanText,
              maxLines: _expanded ? null : 3,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: theme.textTheme.bodySmall?.color,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
