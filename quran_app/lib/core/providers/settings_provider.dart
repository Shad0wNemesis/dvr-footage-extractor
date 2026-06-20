import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';
import '../constants/api_constants.dart';

class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.arabicFontFamily = AppConstants.fontUthmanic,
    this.arabicFontSize = AppConstants.defaultArabicFontSize,
    this.translationFontSize = AppConstants.defaultTranslationFontSize,
    this.translationId = ApiConstants.defaultTranslationId,
    this.tafsirId = ApiConstants.defaultTafsirId,
    this.reciterId = ApiConstants.defaultReciterId,
    this.showTranslation = true,
    this.showTafsir = false,
    this.showWordByWord = false,
    this.autoPlayNextSurah = false,
    this.repeatMode = 0,
    this.calculationMethod = 2,
    this.locationLat,
    this.locationLng,
    this.locationCity,
  });

  final ThemeMode themeMode;
  final String arabicFontFamily;
  final double arabicFontSize;
  final double translationFontSize;
  final int translationId;
  final int tafsirId;
  final int reciterId;
  final bool showTranslation;
  final bool showTafsir;
  final bool showWordByWord;
  final bool autoPlayNextSurah;
  final int repeatMode;
  final int calculationMethod;
  final double? locationLat;
  final double? locationLng;
  final String? locationCity;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? arabicFontFamily,
    double? arabicFontSize,
    double? translationFontSize,
    int? translationId,
    int? tafsirId,
    int? reciterId,
    bool? showTranslation,
    bool? showTafsir,
    bool? showWordByWord,
    bool? autoPlayNextSurah,
    int? repeatMode,
    int? calculationMethod,
    double? locationLat,
    double? locationLng,
    String? locationCity,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      arabicFontFamily: arabicFontFamily ?? this.arabicFontFamily,
      arabicFontSize: arabicFontSize ?? this.arabicFontSize,
      translationFontSize: translationFontSize ?? this.translationFontSize,
      translationId: translationId ?? this.translationId,
      tafsirId: tafsirId ?? this.tafsirId,
      reciterId: reciterId ?? this.reciterId,
      showTranslation: showTranslation ?? this.showTranslation,
      showTafsir: showTafsir ?? this.showTafsir,
      showWordByWord: showWordByWord ?? this.showWordByWord,
      autoPlayNextSurah: autoPlayNextSurah ?? this.autoPlayNextSurah,
      repeatMode: repeatMode ?? this.repeatMode,
      calculationMethod: calculationMethod ?? this.calculationMethod,
      locationLat: locationLat ?? this.locationLat,
      locationLng: locationLng ?? this.locationLng,
      locationCity: locationCity ?? this.locationCity,
    );
  }
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  SettingsNotifier(this._prefs) : super(const AppSettings()) {
    _load();
  }

  final SharedPreferences _prefs;

  void _load() {
    final themeModeIndex = _prefs.getInt(AppConstants.keyThemeMode) ?? 0;
    state = AppSettings(
      themeMode: ThemeMode.values[themeModeIndex],
      arabicFontFamily:
          _prefs.getString(AppConstants.keyArabicFont) ?? AppConstants.fontUthmanic,
      arabicFontSize:
          _prefs.getDouble(AppConstants.keyFontSize) ?? AppConstants.defaultArabicFontSize,
      translationFontSize: AppConstants.defaultTranslationFontSize,
      translationId: _prefs.getInt(AppConstants.keyTranslationId) ??
          ApiConstants.defaultTranslationId,
      tafsirId:
          _prefs.getInt(AppConstants.keyTafsirId) ?? ApiConstants.defaultTafsirId,
      reciterId: _prefs.getInt(AppConstants.keyReciterId) ??
          ApiConstants.defaultReciterId,
      showTranslation: _prefs.getBool(AppConstants.keyShowTranslation) ?? true,
      showTafsir: _prefs.getBool(AppConstants.keyShowTafsir) ?? false,
      showWordByWord: _prefs.getBool(AppConstants.keyShowWordByWord) ?? false,
      autoPlayNextSurah: _prefs.getBool(AppConstants.keyAutoPlayNextSurah) ?? false,
      repeatMode: _prefs.getInt(AppConstants.keyRepeatMode) ?? 0,
      calculationMethod: _prefs.getInt(AppConstants.keyCalculationMethod) ?? 2,
      locationLat: _prefs.getDouble(AppConstants.keyLocationLat),
      locationLng: _prefs.getDouble(AppConstants.keyLocationLng),
      locationCity: _prefs.getString(AppConstants.keyLocationCity),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt(AppConstants.keyThemeMode, mode.index);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setArabicFont(String font) async {
    await _prefs.setString(AppConstants.keyArabicFont, font);
    state = state.copyWith(arabicFontFamily: font);
  }

  Future<void> setArabicFontSize(double size) async {
    await _prefs.setDouble(AppConstants.keyFontSize, size);
    state = state.copyWith(arabicFontSize: size);
  }

  Future<void> setTranslationId(int id) async {
    await _prefs.setInt(AppConstants.keyTranslationId, id);
    state = state.copyWith(translationId: id);
  }

  Future<void> setTafsirId(int id) async {
    await _prefs.setInt(AppConstants.keyTafsirId, id);
    state = state.copyWith(tafsirId: id);
  }

  Future<void> setReciterId(int id) async {
    await _prefs.setInt(AppConstants.keyReciterId, id);
    state = state.copyWith(reciterId: id);
  }

  Future<void> toggleTranslation() async {
    final newVal = !state.showTranslation;
    await _prefs.setBool(AppConstants.keyShowTranslation, newVal);
    state = state.copyWith(showTranslation: newVal);
  }

  Future<void> toggleTafsir() async {
    final newVal = !state.showTafsir;
    await _prefs.setBool(AppConstants.keyShowTafsir, newVal);
    state = state.copyWith(showTafsir: newVal);
  }

  Future<void> toggleWordByWord() async {
    final newVal = !state.showWordByWord;
    await _prefs.setBool(AppConstants.keyShowWordByWord, newVal);
    state = state.copyWith(showWordByWord: newVal);
  }

  Future<void> setCalculationMethod(int method) async {
    await _prefs.setInt(AppConstants.keyCalculationMethod, method);
    state = state.copyWith(calculationMethod: method);
  }

  Future<void> setLocation(double lat, double lng, String city) async {
    await _prefs.setDouble(AppConstants.keyLocationLat, lat);
    await _prefs.setDouble(AppConstants.keyLocationLng, lng);
    await _prefs.setString(AppConstants.keyLocationCity, city);
    state = state.copyWith(locationLat: lat, locationLng: lng, locationCity: city);
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('SharedPreferences must be overridden at app startup');
});

final settingsProvider = StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  return SettingsNotifier(prefs);
});
