# نور القرآن — Noor Al-Quran

**Free. No Ads. Open-Source Spirit.**

A next-generation Quran application for iOS and Android built with Flutter.
All AI features run fully on-device or on a self-hosted local server — no data
ever leaves your control.

---

## Features

| Feature | Technology |
|---------|-----------|
| Quran reading (Uthmanic font) | Flutter + Drift SQLite (offline-first) |
| 6,236-verse full-text search | SQLite FTS5 |
| **Semantic AI search** | FAISS vector index + Llama-3.2 RAG |
| **Tajweed recitation checker** | faster-whisper STT |
| **Hifz memorization (SRS)** | SM-2 spaced-repetition algorithm |
| **AR Mus'haf scanner** | YOLOv8n + EasyOCR |
| Prayer times (10 methods) | adhan-dart |
| Qibla compass | flutter_qiblah + sensors_plus |
| Bookmarks & notes | Drift SQLite |
| Audio recitation | just_audio + just_audio_background |
| Tafsir | quran.com API v4 / offline cache |

---

## Quick Start

### Prerequisites

- Flutter 3.22+ (`flutter --version`)
- Dart 3.2+
- Java 17 (for Android builds)
- Xcode 15+ (for iOS builds, macOS only)
- Docker 24+ (for the AI microservice)

### 1 — Clone and install

```bash
git clone https://github.com/Shad0wNemesis/noor-al-quran.git
cd noor-al-quran
flutter pub get
```

### 2 — Generate Drift + Riverpod code

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

This creates the `*.g.dart` files required by the Drift ORM and Riverpod
code-generation annotations.

### 3 — Run the Flutter app

```bash
# Android (with emulator or device connected)
flutter run

# iOS (macOS only)
flutter run -d "iPhone 15 Pro"
```

On first launch the splash screen seeds the local database from bundled JSON
assets. This takes ~5 s and only happens once.

---

## AI Microservice

The AI features (semantic search, recitation checker, AR scanner) require the
local FastAPI backend. The Flutter app gracefully degrades — all non-AI
features work without it.

### Start with Docker (recommended)

```bash
cd services
docker compose up -d
docker compose logs -f ai    # watch startup logs
```

The service starts at **http://localhost:8765**. It takes ~90 s on first start
as models load into RAM.

### Model Downloads

Download models and place them in `services/models/` and `services/data/`:

```
services/
├── models/
│   ├── llm/
│   │   └── model.gguf          ← Llama-3.2-3B-Instruct-Q4_K_M.gguf
│   └── vision/
│       └── mushaf_yolov8n.pt   ← custom YOLO model (see Training section)
└── data/
    └── faiss_index/
        ├── index.faiss         ← built by build_faiss_index.py
        └── metadata.json       ← built by build_faiss_index.py
```

**Llama-3.2-3B-Instruct (Q4_K_M GGUF)**

```bash
# ~2 GB download
wget -O services/models/llm/model.gguf \
  "https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf"
```

**Build the FAISS vector index**

```bash
# Requires: pip install faiss-cpu sentence-transformers
cd services/ai_microservice
python scripts/build_faiss_index.py \
  --input  ../../assets/json/ayahs_with_translations.json \
  --output ../data/faiss_index
```

### Run without Docker (development)

```bash
cd services/ai_microservice
pip install -r requirements.txt
python main.py
```

---

## Android — Release Signing

### Generate a keystore (one-time)

```bash
keytool -genkey -v \
  -keystore android/app/release.keystore \
  -alias noor \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

### Create `android/key.properties`

```properties
storeFile=release.keystore
storePassword=your_store_password
keyAlias=noor
keyPassword=your_key_password
```

> **Never commit** `key.properties` or `release.keystore` — they're in `.gitignore`.

---

## Automated Releases (GitHub Actions)

Two workflows run automatically when you push a semver tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

| Workflow | Runner | Output |
|----------|--------|--------|
| `android-release.yml` | Ubuntu | Universal APK + Play Store AAB |
| `ios-release.yml` | macOS-14 (M1) | Signed IPA |

Both artifacts are attached to the GitHub Release created automatically.

### Required GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

**Android**

| Secret | Value |
|--------|-------|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i release.keystore \| pbcopy` |
| `ANDROID_STORE_PASSWORD` | keystore `storePassword` |
| `ANDROID_KEY_ALIAS` | key alias (`noor`) |
| `ANDROID_KEY_PASSWORD` | key password |

**iOS**

| Secret | Value |
|--------|-------|
| `IOS_CERTIFICATE_BASE64` | `base64 -i cert.p12 \| pbcopy` |
| `IOS_CERTIFICATE_PASSWORD` | P12 export password |
| `IOS_PROVISIONING_PROFILE_BASE64` | `base64 -i profile.mobileprovision \| pbcopy` |
| `IOS_KEYCHAIN_PASSWORD` | any secure random string |
| `IOS_TEAM_ID` | 10-character Apple Team ID |

---

## Project Structure

```
quran_app/
├── lib/
│   ├── main.dart
│   ├── app.dart
│   ├── core/
│   │   ├── ai/                       # AI HTTP client
│   │   ├── database/                 # Drift ORM — tables, DAOs, initializer
│   │   ├── providers/                # Riverpod providers
│   │   ├── router/                   # go_router
│   │   ├── theme/                    # Material 3 design tokens
│   │   └── constants/
│   └── features/
│       ├── home/                     # Home screen
│       ├── quran/                    # Surah list + reader + keyword search
│       ├── semantic_search/          # AI semantic search (FAISS + LLM)
│       ├── hifz/                     # Memorization SRS (SM-2)
│       ├── recitation_checker/       # Tajweed checker (Whisper STT)
│       ├── ar_scanner/               # Mus'haf camera scanner (YOLO)
│       ├── audio/                    # just_audio player
│       ├── prayer/                   # Prayer times (adhan)
│       ├── qibla/                    # Qibla compass
│       ├── bookmarks/                # Bookmarks & notes
│       ├── tafsir/                   # Tafsir reader
│       ├── settings/                 # App settings
│       └── splash/                   # First-launch DB initializer screen
├── services/
│   ├── docker-compose.yml
│   └── ai_microservice/             # FastAPI Python backend
│       ├── main.py
│       ├── config.py
│       ├── models/schemas.py
│       ├── routes/                   # search.py, recitation.py, vision.py
│       ├── services/                 # embedding, vector_store, llm, stt, vision
│       ├── scripts/build_faiss_index.py
│       ├── requirements.txt
│       └── Dockerfile
├── android/
├── ios/
├── assets/
│   ├── fonts/                        # UthmanicHafs, Amiri, NotoNaskhArabic
│   └── json/                         # Seed data (surahs.json, ayahs.json)
└── CHANGELOG.md
```

---

## Training the YOLO Model

The AR scanner works in OCR-only mode without a trained model. To enable
full layout detection (page numbers, surah headers, verse text):

```bash
# 1. Collect and label Mus'haf page images with Roboflow or CVAT
#    Classes: page_number, surah_header, verse_text, bismillah

# 2. Train YOLOv8n
pip install ultralytics
yolo train model=yolov8n.pt data=mushaf.yaml epochs=100 imgsz=640 batch=16

# 3. Copy the best weights
cp runs/detect/train/weights/best.pt services/models/vision/mushaf_yolov8n.pt
```

---

## Contributing

This project is a Sadaqah Jariyah (صدقة جارية) — a perpetual charity.
Pull requests are welcome. Please follow the existing code style and add tests
for any new DAO methods.

## License

MIT License — free for personal and commercial use.
