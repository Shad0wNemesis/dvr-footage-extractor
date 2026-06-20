class AppConstants {
  AppConstants._();

  static const String appName = 'Noor Al-Quran';
  static const String appVersion = '1.0.0';

  // Storage keys
  static const String keyThemeMode = 'theme_mode';
  static const String keyFontSize = 'font_size';
  static const String keyArabicFont = 'arabic_font';
  static const String keyTranslationId = 'translation_id';
  static const String keyTafsirId = 'tafsir_id';
  static const String keyReciterId = 'reciter_id';
  static const String keyLastReadSurah = 'last_read_surah';
  static const String keyLastReadVerse = 'last_read_verse';
  static const String keyShowTranslation = 'show_translation';
  static const String keyShowTafsir = 'show_tafsir';
  static const String keyShowWordByWord = 'show_word_by_word';
  static const String keyCalculationMethod = 'calculation_method';
  static const String keyAutoPlayNextSurah = 'auto_play_next';
  static const String keyRepeatMode = 'repeat_mode';
  static const String keyLocationLat = 'location_lat';
  static const String keyLocationLng = 'location_lng';
  static const String keyLocationCity = 'location_city';
  static const String keyOnboardingDone = 'onboarding_done';

  // Font families
  static const String fontUthmanic = 'UthmanicHafs';
  static const String fontAmiri = 'Amiri';
  static const String fontNotoNaskh = 'NotoNaskhArabic';

  // Font size range
  static const double minFontSize = 18.0;
  static const double maxFontSize = 40.0;
  static const double defaultArabicFontSize = 26.0;
  static const double defaultTranslationFontSize = 16.0;

  // Total surah/verse counts
  static const int totalSurahs = 114;
  static const int totalVerses = 6236;
  static const int totalJuzs = 30;
  static const int totalPages = 604;

  // DB name
  static const String dbName = 'quran_offline.db';
  static const int dbVersion = 1;

  // Notification channel
  static const String audioChannelId = 'quran_audio';
  static const String audioChannelName = 'Quran Recitation';
  static const String prayerChannelId = 'prayer_times';
  static const String prayerChannelName = 'Prayer Times';
}
