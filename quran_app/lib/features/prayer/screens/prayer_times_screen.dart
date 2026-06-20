import 'package:adhan/adhan.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../providers/prayer_provider.dart';

class PrayerTimesScreen extends ConsumerWidget {
  const PrayerTimesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayerAsync = ref.watch(prayerTimesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer Times'),
        actions: [
          IconButton(
            icon: const Icon(Icons.explore_outlined),
            onPressed: () => context.push('/qibla'),
            tooltip: 'Qibla',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(prayerTimesProvider),
          ),
        ],
      ),
      body: prayerAsync.when(
        data: (data) {
          if (data == null) {
            return _NoLocationWidget(onRetry: () => ref.invalidate(prayerTimesProvider));
          }
          return _PrayerTimesView(data: data);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text('Could not get prayer times', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () => ref.invalidate(prayerTimesProvider),
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrayerTimesView extends StatelessWidget {
  const _PrayerTimesView({required this.data});
  final PrayerData data;

  static const _prayers = [
    (prayer: Prayer.fajr, label: 'Fajr', icon: Icons.brightness_3, color: AppColors.fajrColor),
    (prayer: Prayer.sunrise, label: 'Sunrise', icon: Icons.wb_sunny_outlined, color: AppColors.sunriseColor),
    (prayer: Prayer.dhuhr, label: 'Dhuhr', icon: Icons.wb_sunny, color: AppColors.dhuhrColor),
    (prayer: Prayer.asr, label: 'Asr', icon: Icons.wb_twilight, color: AppColors.asrColor),
    (prayer: Prayer.maghrib, label: 'Maghrib', icon: Icons.bedtime_outlined, color: AppColors.maghribColor),
    (prayer: Prayer.isha, label: 'Isha', icon: Icons.dark_mode_outlined, color: AppColors.ishaColor),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = data.nextPrayer;
    final timeFormat = DateFormat('hh:mm a');

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _NextPrayerBanner(data: data, timeFormat: timeFormat),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14),
                const SizedBox(width: 4),
                Text(data.city, style: theme.textTheme.bodySmall),
                const Spacer(),
                Text(
                  DateFormat('EEEE, MMMM d').format(data.date),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final p = _prayers[index];
                final time = data.times.timeForPrayer(p.prayer);
                final isNext = next == p.prayer;
                return _PrayerCard(
                  label: p.label,
                  icon: p.icon,
                  color: p.color,
                  time: time != null ? timeFormat.format(time) : '--:--',
                  isNext: isNext,
                );
              },
              childCount: _prayers.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

class _NextPrayerBanner extends StatelessWidget {
  const _NextPrayerBanner({required this.data, required this.timeFormat});
  final PrayerData data;
  final DateFormat timeFormat;

  @override
  Widget build(BuildContext context) {
    final next = data.nextPrayer;
    final nextTime = data.nextPrayerTime;
    final remaining = nextTime != null
        ? nextTime.difference(DateTime.now())
        : Duration.zero;
    final h = remaining.inHours;
    final m = remaining.inMinutes.remainder(60);

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary, AppColors.primaryDark],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Next Prayer',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            _prayerName(next),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (nextTime != null) ...[
            Text(
              timeFormat.format(nextTime),
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
            const SizedBox(height: 12),
            Text(
              'In ${h}h ${m}m',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _prayerName(Prayer p) {
    switch (p) {
      case Prayer.fajr: return 'Fajr';
      case Prayer.sunrise: return 'Sunrise';
      case Prayer.dhuhr: return 'Dhuhr';
      case Prayer.asr: return 'Asr';
      case Prayer.maghrib: return 'Maghrib';
      case Prayer.isha: return 'Isha';
      default: return 'Unknown';
    }
  }
}

class _PrayerCard extends StatelessWidget {
  const _PrayerCard({
    required this.label,
    required this.icon,
    required this.color,
    required this.time,
    required this.isNext,
  });

  final String label;
  final IconData icon;
  final Color color;
  final String time;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isNext
            ? color.withOpacity(0.12)
            : theme.cardTheme.color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isNext ? color.withOpacity(0.4) : theme.colorScheme.outline.withOpacity(0.3),
          width: isNext ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: isNext ? FontWeight.w700 : FontWeight.w500,
                color: isNext ? color : null,
              ),
            ),
          ),
          if (isNext)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('Next',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: color)),
            ),
          const SizedBox(width: 8),
          Text(
            time,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: isNext ? color : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoLocationWidget extends StatelessWidget {
  const _NoLocationWidget({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, size: 64, color: AppColors.primary),
            const SizedBox(height: 16),
            const Text('Location Access Needed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Prayer times require your location. Please grant location permission.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.lightTextSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.location_on),
              label: const Text('Grant Location'),
            ),
          ],
        ),
      ),
    );
  }
}
