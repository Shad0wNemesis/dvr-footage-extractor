import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/theme/app_colors.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          _SectionHeader(title: 'Appearance'),
          _ThemeTile(settings: settings, notifier: notifier),
          _FontFamilyTile(settings: settings, notifier: notifier),
          _FontSizeTile(settings: settings, notifier: notifier),

          _SectionHeader(title: 'Reading'),
          _ToggleTile(
            icon: Icons.translate,
            title: 'Show Translation',
            value: settings.showTranslation,
            onChanged: (_) => notifier.toggleTranslation(),
          ),
          _ToggleTile(
            icon: Icons.menu_book,
            title: 'Show Tafsir',
            value: settings.showTafsir,
            onChanged: (_) => notifier.toggleTafsir(),
          ),
          _ToggleTile(
            icon: Icons.text_fields,
            title: 'Word-by-Word Translation',
            value: settings.showWordByWord,
            onChanged: (_) => notifier.toggleWordByWord(),
          ),

          _SectionHeader(title: 'Audio'),
          _ReciterTile(settings: settings, notifier: notifier),
          _ToggleTile(
            icon: Icons.skip_next,
            title: 'Auto-play Next Surah',
            value: settings.autoPlayNextSurah,
            onChanged: (_) {},
          ),

          _SectionHeader(title: 'Prayer Times'),
          _CalculationMethodTile(settings: settings, notifier: notifier),

          _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            trailing: Text(AppConstants.appVersion,
                style: theme.textTheme.bodySmall),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 14),
            onTap: () {},
          ),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
  });
  final IconData icon;
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({required this.settings, required this.notifier});
  final AppSettings settings;
  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.brightness_6_outlined),
      title: const Text('Theme'),
      trailing: SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode, size: 16)),
          ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto, size: 16)),
          ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode, size: 16)),
        ],
        selected: {settings.themeMode},
        onSelectionChanged: (modes) => notifier.setThemeMode(modes.first),
        style: const ButtonStyle(
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

class _FontFamilyTile extends StatelessWidget {
  const _FontFamilyTile({required this.settings, required this.notifier});
  final AppSettings settings;
  final SettingsNotifier notifier;

  static const _fonts = [
    (value: AppConstants.fontUthmanic, label: 'Uthmanic'),
    (value: AppConstants.fontAmiri, label: 'Amiri'),
    (value: AppConstants.fontNotoNaskh, label: 'Noto Naskh'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.font_download_outlined),
      title: const Text('Arabic Font'),
      trailing: DropdownButton<String>(
        value: settings.arabicFontFamily,
        underline: const SizedBox.shrink(),
        items: _fonts.map((f) => DropdownMenuItem(
          value: f.value,
          child: Text(f.label, style: TextStyle(fontFamily: f.value)),
        )).toList(),
        onChanged: (v) { if (v != null) notifier.setArabicFont(v); },
      ),
    );
  }
}

class _FontSizeTile extends StatelessWidget {
  const _FontSizeTile({required this.settings, required this.notifier});
  final AppSettings settings;
  final SettingsNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.format_size),
          title: const Text('Arabic Font Size'),
          trailing: Text(
            settings.arabicFontSize.toStringAsFixed(0),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider.adaptive(
            value: settings.arabicFontSize,
            min: AppConstants.minFontSize,
            max: AppConstants.maxFontSize,
            divisions: 11,
            onChanged: notifier.setArabicFontSize,
            activeColor: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _ReciterTile extends StatelessWidget {
  const _ReciterTile({required this.settings, required this.notifier});
  final AppSettings settings;
  final SettingsNotifier notifier;

  static const _reciters = [
    (id: 7, name: 'Mishary Rashid Al-Afasy'),
    (id: 1, name: 'AbdurRahmaan As-Sudais'),
    (id: 2, name: 'Abu Bakr Al-Shatri'),
    (id: 3, name: 'Nasser Al-Qatami'),
    (id: 4, name: 'Yasser Ad-Dossari'),
    (id: 6, name: 'Maher Al-Muaiqly'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.mic_outlined),
      title: const Text('Default Reciter'),
      trailing: DropdownButton<int>(
        value: settings.reciterId,
        underline: const SizedBox.shrink(),
        items: _reciters.map((r) => DropdownMenuItem(
          value: r.id,
          child: Text(r.name.split(' ').take(2).join(' '), overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: (v) { if (v != null) notifier.setReciterId(v); },
      ),
    );
  }
}

class _CalculationMethodTile extends StatelessWidget {
  const _CalculationMethodTile({required this.settings, required this.notifier});
  final AppSettings settings;
  final SettingsNotifier notifier;

  static const _methods = [
    (id: 0, name: 'Muslim World League'),
    (id: 1, name: 'Egyptian'),
    (id: 2, name: 'Karachi'),
    (id: 3, name: 'Umm Al-Qura'),
    (id: 4, name: 'Dubai'),
    (id: 6, name: 'North America (ISNA)'),
    (id: 7, name: 'Kuwait'),
    (id: 8, name: 'Qatar'),
    (id: 9, name: 'Singapore'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.calculate_outlined),
      title: const Text('Calculation Method'),
      trailing: DropdownButton<int>(
        value: settings.calculationMethod,
        underline: const SizedBox.shrink(),
        items: _methods.map((m) => DropdownMenuItem(
          value: m.id,
          child: Text(m.name, overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: (v) { if (v != null) notifier.setCalculationMethod(v); },
      ),
    );
  }
}
