class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'https://api.quran.com/api/v4';
  static const String audioBaseUrl = 'https://verses.quran.com';
  static const String cdnBaseUrl = 'https://cdn.qurancdn.com';

  // Chapter endpoints
  static const String chapters = '/chapters';
  static String chapterInfo(int number) => '/chapters/$number';

  // Verse endpoints
  static String versesByChapter(int chapter) => '/verses/by_chapter/$chapter';
  static String versesByPage(int page) => '/verses/by_page/$page';
  static String versesByJuz(int juz) => '/verses/by_juz/$juz';
  static String verseByKey(String key) => '/verses/by_key/$key';

  // Translation endpoints
  static const String translations = '/resources/translations';
  static const String translationLanguages = '/resources/translation_languages';

  // Tafsir endpoints
  static const String tafsirs = '/resources/tafsirs';

  // Recitation endpoints
  static const String reciters = '/resources/recitations';
  static String chapterRecitations(int reciterId, int chapterId) =>
      '/recitations/$reciterId/by_chapter/$chapterId';

  // Search
  static const String search = '/search';

  // Juz
  static const String juzs = '/juzs';

  // Default IDs
  static const int defaultTranslationId = 131; // Dr. Mustafa Khattab
  static const int defaultTafsirId = 169; // Ibn Kathir
  static const int defaultReciterId = 7; // Mishary Rashid Al-Afasy

  static const int connectTimeoutMs = 15000;
  static const int receiveTimeoutMs = 30000;
}
