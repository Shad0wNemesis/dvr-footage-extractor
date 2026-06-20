# Changelog — Noor Al-Quran

All notable changes to this project are documented here.
Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
Versioning: [Semantic Versioning](https://semver.org/)

---

## [Unreleased]

## [1.0.0] — 2026-06-20

### Added — Phase 2 (AI Feature Screens)
- **Semantic AI Search** (`/semantic-search`) — FAISS vector-index search over
  all 6,236 Ayahs with optional LLM-generated grounded answers
- **Hifz / Memorization** (`/hifz`) — SM-2 spaced-repetition card-flip review
  session with Again / Hard / Good / Easy grading
- **Tajweed Recitation Checker** (`/recitation/:verseKey`) — mic recording →
  faster-whisper STT → accuracy score + per-error Tajweed breakdown
- **AR Mus'haf Scanner** (`/scanner`) — live camera → YOLOv8 + EasyOCR page
  detection → "Open in Reader" deep-link
- **AI Service Client** (`lib/core/ai/ai_service_client.dart`) — typed Dio HTTP
  client matching all Pydantic schemas
- **AI Riverpod providers** — health polling, semantic search family provider
- **FastAPI vision route** (`routes/vision.py`) — completes the AI microservice
- Splash screen wired as `initialLocation` (replaces direct home navigation)
- Home screen AI feature row with dot-badge icons
- Android: `RECORD_AUDIO` + `CAMERA` permissions
- Android: localhost/127.0.0.1/10.0.2.2 cleartext HTTP in network security config
- iOS: `NSMicrophoneUsageDescription` + `NSCameraUsageDescription` + localhost ATS
- CI/CD: GitHub Actions workflows for automated Android APK/AAB and iOS IPA
  builds + GitHub Releases on semver tags

### Added — Phase 1 (Architecture & Foundation)
- Complete Drift ORM database layer (3 table files, 3 DAO files, `QuranDatabase`)
- Isolate-based `DatabaseInitializer` with sealed `InitProgress` class hierarchy
  and real-time progress streaming via `SendPort`
- Pure-Dart `SeedParser` with isolate-safe data classes
- FTS5 virtual table for full-text Quran search
- SM-2 spaced-repetition algorithm in `UserDao.recordReview()`
- Riverpod database providers
- Full FastAPI AI microservice: Embedding, VectorStore, LLM, STT, Vision services
- Multi-stage Docker build for the AI microservice
- FAISS index build script

---

[Unreleased]: https://github.com/Shad0wNemesis/noor-al-quran/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Shad0wNemesis/noor-al-quran/releases/tag/v1.0.0
