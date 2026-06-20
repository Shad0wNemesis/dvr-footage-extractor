import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../../../core/api/quran_api_client.dart';
import '../../../core/constants/api_constants.dart';

enum RepeatMode { none, verse, surah }

class AudioState {
  const AudioState({
    this.isPlaying = false,
    this.isLoading = false,
    this.currentVerseKey,
    this.currentSurahId,
    this.currentReciterId = ApiConstants.defaultReciterId,
    this.repeatMode = RepeatMode.none,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.error,
  });

  final bool isPlaying;
  final bool isLoading;
  final String? currentVerseKey;
  final int? currentSurahId;
  final int currentReciterId;
  final RepeatMode repeatMode;
  final Duration position;
  final Duration duration;
  final String? error;

  AudioState copyWith({
    bool? isPlaying,
    bool? isLoading,
    String? currentVerseKey,
    int? currentSurahId,
    int? currentReciterId,
    RepeatMode? repeatMode,
    Duration? position,
    Duration? duration,
    String? error,
  }) {
    return AudioState(
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      currentVerseKey: currentVerseKey ?? this.currentVerseKey,
      currentSurahId: currentSurahId ?? this.currentSurahId,
      currentReciterId: currentReciterId ?? this.currentReciterId,
      repeatMode: repeatMode ?? this.repeatMode,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      error: error,
    );
  }
}

class AudioNotifier extends StateNotifier<AudioState> {
  AudioNotifier(this._ref) : super(const AudioState()) {
    _init();
  }

  final Ref _ref;
  late final AudioPlayer _player;
  List<VerseTiming> _verseTimings = [];

  Future<void> _init() async {
    _player = AudioPlayer();

    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _player.playerStateStream.listen((ps) {
      state = state.copyWith(
        isPlaying: ps.playing,
        isLoading: ps.processingState == ProcessingState.loading ||
            ps.processingState == ProcessingState.buffering,
      );
      if (ps.processingState == ProcessingState.completed) {
        _onComplete();
      }
    });

    _player.positionStream.listen((pos) {
      state = state.copyWith(position: pos);
      _updateCurrentVerse(pos);
    });

    _player.durationStream.listen((dur) {
      if (dur != null) state = state.copyWith(duration: dur);
    });
  }

  void _updateCurrentVerse(Duration position) {
    if (_verseTimings.isEmpty) return;
    final ms = position.inMilliseconds;
    for (final timing in _verseTimings.reversed) {
      if (ms >= timing.timestampFrom) {
        if (state.currentVerseKey != timing.verseKey) {
          state = state.copyWith(currentVerseKey: timing.verseKey);
        }
        break;
      }
    }
  }

  Future<void> playSurah(int surahId, {int reciterId = ApiConstants.defaultReciterId}) async {
    try {
      state = state.copyWith(isLoading: true, currentSurahId: surahId, error: null);
      final api = _ref.read(quranApiClientProvider);
      final chapterAudio = await api.fetchChapterAudio(reciterId, surahId);
      _verseTimings = chapterAudio.verseTimings;

      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(chapterAudio.audioUrl)),
      );
      await _player.play();
      state = state.copyWith(
        isPlaying: true,
        isLoading: false,
        currentSurahId: surahId,
        currentReciterId: reciterId,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> playVerse(String verseKey, {int reciterId = ApiConstants.defaultReciterId}) async {
    try {
      state = state.copyWith(isLoading: true, currentVerseKey: verseKey, error: null);
      final parts = verseKey.split(':');
      final chapter = parts[0].padLeft(3, '0');
      final verse = parts[1].padLeft(3, '0');
      final url = '${ApiConstants.audioBaseUrl}/$reciterId/$chapter$verse.mp3';

      await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
      await _player.play();
      state = state.copyWith(
        isPlaying: true,
        isLoading: false,
        currentVerseKey: verseKey,
        currentReciterId: reciterId,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> pause() async {
    await _player.pause();
    state = state.copyWith(isPlaying: false);
  }

  Future<void> resume() async {
    await _player.play();
    state = state.copyWith(isPlaying: true);
  }

  Future<void> stop() async {
    await _player.stop();
    _verseTimings = [];
    state = const AudioState();
  }

  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  void setRepeatMode(RepeatMode mode) {
    state = state.copyWith(repeatMode: mode);
    switch (mode) {
      case RepeatMode.none:
        _player.setLoopMode(LoopMode.off);
        break;
      case RepeatMode.verse:
        _player.setLoopMode(LoopMode.one);
        break;
      case RepeatMode.surah:
        _player.setLoopMode(LoopMode.all);
        break;
    }
  }

  void _onComplete() {
    if (state.repeatMode == RepeatMode.none) {
      state = state.copyWith(isPlaying: false);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

final audioProvider = StateNotifierProvider<AudioNotifier, AudioState>((ref) {
  return AudioNotifier(ref);
});
