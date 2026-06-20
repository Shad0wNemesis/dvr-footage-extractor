#!/usr/bin/env bash
# Download all required assets: fonts + full Quran seed data.
# Run once before `flutter run` / `flutter build`.
#
# Usage:
#   chmod +x scripts/download_assets.sh
#   ./scripts/download_assets.sh
#
# Requirements: curl, python3

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
FONTS_DIR="$APP_DIR/assets/fonts"
JSON_DIR="$APP_DIR/assets/json"

echo "=== Noor Al-Quran asset downloader ==="
echo "App directory: $APP_DIR"
echo ""

mkdir -p "$FONTS_DIR" "$JSON_DIR"

# ── Fonts ────────────────────────────────────────────────────────────────────
# Amiri (Google Fonts — SIL Open Font License)
download_font() {
  local name="$1" url="$2" dest="$FONTS_DIR/$3"
  if [[ -f "$dest" ]]; then
    echo "  ✓ $name (cached)"
    return
  fi
  echo "  ↓ $name…"
  curl -fsSL --retry 3 -o "$dest" "$url"
  echo "  ✓ $name"
}

echo "[1/3] Downloading Arabic fonts…"

download_font "Amiri-Regular" \
  "https://github.com/aliftype/amiri/releases/download/1.000/Amiri-Regular.ttf" \
  "Amiri-Regular.ttf"

download_font "Amiri-Bold" \
  "https://github.com/aliftype/amiri/releases/download/1.000/Amiri-Bold.ttf" \
  "Amiri-Bold.ttf"

download_font "NotoNaskhArabic-Regular" \
  "https://github.com/notofonts/arabic/releases/download/NotoNaskhArabic-v2.014/NotoNaskhArabic-Regular.ttf" \
  "NotoNaskhArabic-Regular.ttf"

download_font "NotoNaskhArabic-Bold" \
  "https://github.com/notofonts/arabic/releases/download/NotoNaskhArabic-v2.014/NotoNaskhArabic-Bold.ttf" \
  "NotoNaskhArabic-Bold.ttf"

# UthmanicHafs V22 — KFGQPC font, freely distributed for Quran applications.
# Source: King Fahd Complex for the Printing of the Holy Quran (qurancomplex.gov.sa)
# Mirrored at several open-source Quran projects on GitHub.
download_font "UthmanicHafs_V22" \
  "https://github.com/quran/quran-ios/raw/main/Quran/Assets.xcassets/Fonts/KFGQPC-Uthmanic-Script-Hafs-Regular.ttf" \
  "UthmanicHafs_V22.ttf"

echo ""

# ── Quran seed data ──────────────────────────────────────────────────────────
echo "[2/3] Downloading full Quran seed data (surahs + 6,236 ayahs)…"
echo "      This takes ~3–5 min (polite API rate limiting)."
echo ""

if ! command -v python3 &>/dev/null; then
  echo "ERROR: python3 not found. Install Python 3 and retry."
  exit 1
fi

python3 "$SCRIPT_DIR/prepare_seed_data.py" --output "$JSON_DIR"

echo ""
echo "[3/3] Done!"
echo ""
echo "All assets are ready. You can now run:"
echo "  flutter pub run build_runner build --delete-conflicting-outputs"
echo "  flutter run"
