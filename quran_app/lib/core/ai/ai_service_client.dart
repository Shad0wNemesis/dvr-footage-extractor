/// HTTP client for the Noor Al-Quran local AI microservice.
///
/// The microservice runs at [baseUrl] (default: http://127.0.0.1:8765) and
/// exposes three endpoints:
///   POST /api/search      — Semantic RAG search (FAISS + LLM)
///   POST /api/recitation  — Arabic Tajweed STT evaluation
///   POST /api/vision      — Mus'haf page detection (YOLO + OCR)
///   GET  /health          — Liveness probe
///
/// All request/response models in this file mirror the Pydantic schemas in
/// services/ai_microservice/models/schemas.py exactly.
library ai_service_client;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ── /api/search ──────────────────────────────────────────────────────────────

/// One Ayah returned by the semantic search endpoint.
@immutable
class AiAyahResult {
  const AiAyahResult({
    required this.verseKey,
    required this.surahId,
    required this.ayahNumber,
    required this.surahName,
    required this.textArabic,
    this.translationEn,
    this.tafseerSnippet,
    required this.relevanceScore,
  });

  final String verseKey;
  final int surahId;
  final int ayahNumber;
  final String surahName;
  final String textArabic;
  final String? translationEn;
  final String? tafseerSnippet;

  /// FAISS inner-product similarity score (0.0–1.0, higher = more relevant).
  final double relevanceScore;

  factory AiAyahResult.fromJson(Map<String, dynamic> j) => AiAyahResult(
        verseKey: j['verse_key'] as String,
        surahId: j['surah_id'] as int,
        ayahNumber: j['ayah_number'] as int,
        surahName: j['surah_name'] as String? ?? '',
        textArabic: j['text_arabic'] as String? ?? '',
        translationEn: j['translation_en'] as String?,
        tafseerSnippet: j['tafseer_snippet'] as String?,
        relevanceScore: (j['relevance_score'] as num).toDouble(),
      );
}

/// Full response from POST /api/search.
@immutable
class AiSearchResponse {
  const AiSearchResponse({
    required this.results,
    this.answer,
    required this.queryEmbeddingMs,
    required this.retrievalMs,
    this.llmMs,
    required this.totalMs,
  });

  final List<AiAyahResult> results;

  /// LLM-generated grounded answer, or null if the LLM is not loaded.
  final String? answer;

  final double queryEmbeddingMs;
  final double retrievalMs;
  final double? llmMs;
  final double totalMs;

  factory AiSearchResponse.fromJson(Map<String, dynamic> j) => AiSearchResponse(
        results: (j['results'] as List<dynamic>)
            .map((e) => AiAyahResult.fromJson(e as Map<String, dynamic>))
            .toList(),
        answer: j['answer'] as String?,
        queryEmbeddingMs: (j['query_embedding_ms'] as num).toDouble(),
        retrievalMs: (j['retrieval_ms'] as num).toDouble(),
        llmMs: (j['llm_ms'] as num?)?.toDouble(),
        totalMs: (j['total_ms'] as num).toDouble(),
      );
}

// ── /api/recitation ───────────────────────────────────────────────────────────

/// A single Tajweed rule violation.
@immutable
class AiTajweedError {
  const AiTajweedError({
    required this.wordPosition,
    required this.ruleName,
    required this.expected,
    required this.detected,
    required this.severity,
  });

  final int wordPosition;
  final String ruleName;
  final String expected;
  final String detected;

  /// 'minor' | 'major' | 'critical'
  final String severity;

  factory AiTajweedError.fromJson(Map<String, dynamic> j) => AiTajweedError(
        wordPosition: j['word_position'] as int? ?? 0,
        ruleName: j['rule_name'] as String? ?? '',
        expected: j['expected'] as String? ?? '',
        detected: j['detected'] as String? ?? '',
        severity: j['severity'] as String? ?? 'minor',
      );
}

/// Full response from POST /api/recitation.
@immutable
class AiRecitationResponse {
  const AiRecitationResponse({
    required this.verseKey,
    required this.transcription,
    required this.accuracyScore,
    required this.passed,
    required this.tajweedErrors,
    required this.sttMs,
    required this.evalMs,
    required this.totalMs,
  });

  final String verseKey;
  final String transcription;

  /// 0.0–1.0 accuracy score.
  final double accuracyScore;

  /// True when [accuracyScore] >= 0.75 (configurable on the service).
  final bool passed;

  final List<AiTajweedError> tajweedErrors;
  final double sttMs;
  final double evalMs;
  final double totalMs;

  factory AiRecitationResponse.fromJson(Map<String, dynamic> j) =>
      AiRecitationResponse(
        verseKey: j['verse_key'] as String,
        transcription: j['transcription'] as String,
        accuracyScore: (j['accuracy_score'] as num).toDouble(),
        passed: j['passed'] as bool,
        tajweedErrors: (j['tajweed_errors'] as List<dynamic>? ?? [])
            .map((e) => AiTajweedError.fromJson(e as Map<String, dynamic>))
            .toList(),
        sttMs: (j['stt_ms'] as num).toDouble(),
        evalMs: (j['eval_ms'] as num).toDouble(),
        totalMs: (j['total_ms'] as num).toDouble(),
      );
}

// ── /api/vision ───────────────────────────────────────────────────────────────

/// A YOLO-detected bounding box in normalised image coordinates (0–1).
@immutable
class AiDetectedRegion {
  const AiDetectedRegion({
    required this.label,
    required this.confidence,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  /// e.g. 'page_number', 'surah_header', 'verse_text'
  final String label;
  final double confidence;

  /// Top-left x, normalised [0, 1].
  final double x;

  /// Top-left y, normalised [0, 1].
  final double y;

  final double width;
  final double height;

  factory AiDetectedRegion.fromJson(Map<String, dynamic> j) => AiDetectedRegion(
        label: j['label'] as String,
        confidence: (j['confidence'] as num).toDouble(),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
      );
}

/// Full response from POST /api/vision.
@immutable
class AiVisionResponse {
  const AiVisionResponse({
    this.detectedPage,
    required this.confidence,
    required this.regions,
    required this.inferenceMs,
  });

  /// Detected Mus'haf page number (1–604), or null if not detected.
  final int? detectedPage;
  final double confidence;
  final List<AiDetectedRegion> regions;
  final double inferenceMs;

  factory AiVisionResponse.fromJson(Map<String, dynamic> j) => AiVisionResponse(
        detectedPage: j['detected_page'] as int?,
        confidence: (j['confidence'] as num).toDouble(),
        regions: (j['regions'] as List<dynamic>? ?? [])
            .map((e) => AiDetectedRegion.fromJson(e as Map<String, dynamic>))
            .toList(),
        inferenceMs: (j['inference_ms'] as num).toDouble(),
      );
}

// ── Client ────────────────────────────────────────────────────────────────────

/// Typed HTTP client for all AI microservice endpoints.
///
/// Create one instance per [ProviderScope] lifetime (managed by Riverpod).
/// All methods are safe to call from any isolate — Dio is thread-safe.
class AIServiceClient {
  AIServiceClient({required this.baseUrl, Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 5),
                receiveTimeout: const Duration(seconds: 60),
                headers: {'Content-Type': 'application/json'},
              ),
            );

  final String baseUrl;
  final Dio _dio;

  // ── Health ──────────────────────────────────────────────────────────────────

  /// Returns true if the microservice is reachable and all models are loaded.
  Future<bool> checkHealth() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('/health');
      return res.statusCode == 200 &&
          (res.data?['status'] as String?) == 'ok';
    } catch (_) {
      return false;
    }
  }

  // ── Semantic search ─────────────────────────────────────────────────────────

  /// Semantic RAG search over all 6,236 Ayahs.
  ///
  /// [query] is a natural-language English query (e.g. "verses about patience").
  /// [topK] controls how many Ayahs are returned (1–20).
  /// [includeTafseer] adds a Tafseer snippet to each result.
  Future<AiSearchResponse> semanticSearch(
    String query, {
    int topK = 5,
    bool includeTafseer = false,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/search',
      data: {
        'query': query,
        'top_k': topK,
        'language': 'en',
        'include_tafseer': includeTafseer,
      },
    );
    return AiSearchResponse.fromJson(res.data!);
  }

  // ── Recitation evaluation ───────────────────────────────────────────────────

  /// Evaluate a recitation against the expected Ayah text.
  ///
  /// [audioBytes] must be raw PCM WAV or M4A bytes (max 60 seconds).
  /// [audioFormat] must be 'wav', 'm4a', 'mp3', or 'ogg'.
  Future<AiRecitationResponse> evaluateRecitation({
    required String verseKey,
    required Uint8List audioBytes,
    String audioFormat = 'wav',
  }) async {
    final b64 = base64Encode(audioBytes);
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/recitation',
      data: {
        'verse_key': verseKey,
        'audio_base64': b64,
        'audio_format': audioFormat,
      },
    );
    return AiRecitationResponse.fromJson(res.data!);
  }

  // ── Vision / Mus'haf page detection ────────────────────────────────────────

  /// Detect the Mus'haf page number from a JPEG camera frame.
  ///
  /// [imageBytes] must be a JPEG-encoded frame (ideally 640×480).
  /// [imageWidth] and [imageHeight] help the service validate the payload.
  Future<AiVisionResponse> detectMushaafPage({
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
  }) async {
    final b64 = base64Encode(imageBytes);
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/vision',
      data: {
        'image_base64': b64,
        'image_width': imageWidth,
        'image_height': imageHeight,
      },
    );
    return AiVisionResponse.fromJson(res.data!);
  }
}
