#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# bootstrap_new_repo.sh
#
# Creates a standalone GitHub repository "noor-al-quran" from the quran_app/
# directory and pushes everything including the CI/CD workflows.
#
# Prerequisites:
#   gh CLI installed and authenticated (gh auth login)
#   Run this script from the quran_app/ directory OR the repo root.
# ─────────────────────────────────────────────────────────────────────────────
set -e

REPO_NAME="noor-al-quran"
DESCRIPTION="Noor Al-Quran (نور القرآن) — Free, AI-powered Quran app for iOS & Android"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Bootstrapping standalone repo: $REPO_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Determine quran_app directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
QURAN_APP_DIR="$(dirname "$SCRIPT_DIR")"
REPO_ROOT="$(dirname "$QURAN_APP_DIR")"

# Create a temporary working directory for the new repo
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT

echo "[1/6] Copying app files to temp dir…"
cp -r "$QURAN_APP_DIR/." "$TMP_DIR/"

echo "[2/6] Copying CI/CD workflows…"
mkdir -p "$TMP_DIR/.github/workflows"
cp "$REPO_ROOT/.github/workflows/quran-android-release.yml" \
   "$TMP_DIR/.github/workflows/android-release.yml"
cp "$REPO_ROOT/.github/workflows/quran-ios-release.yml" \
   "$TMP_DIR/.github/workflows/ios-release.yml"

# Fix the APP_DIR env var in the copied workflows (root of new repo)
sed -i 's/APP_DIR: "quran_app"/APP_DIR: "."/' \
  "$TMP_DIR/.github/workflows/android-release.yml" \
  "$TMP_DIR/.github/workflows/ios-release.yml"
sed -i 's|working-directory: ${{ env.APP_DIR }}/ios|working-directory: ios|' \
  "$TMP_DIR/.github/workflows/ios-release.yml"

echo "[3/6] Initialising git repo…"
cd "$TMP_DIR"
git init
git checkout -b main
git add -A
git commit -m "feat: initial commit — Noor Al-Quran v1.0.0

Full-featured, AI-powered Quran app built with Flutter.

Features:
- Quran reading with Uthmanic font (offline-first, Drift SQLite)
- Semantic AI search via FAISS vector index + local LLM (RAG)
- Tajweed recitation checker (faster-whisper STT)
- Hifz memorization with SM-2 spaced repetition
- AR Mus'haf scanner (YOLOv8 + EasyOCR)
- Prayer times + Qibla compass
- Bookmarks, notes, reading history
- Local FastAPI AI microservice (Docker)"

echo "[4/6] Creating GitHub repository…"
gh repo create "$REPO_NAME" \
  --public \
  --description "$DESCRIPTION" \
  --source . \
  --remote origin \
  --push

echo "[5/6] Pushing to GitHub…"
git push -u origin main

echo "[6/6] Setting up required GitHub Secrets (placeholders)…"
echo ""
echo "  ⚠️  Add the following secrets in:"
echo "  https://github.com/\$(gh api user --jq .login)/$REPO_NAME/settings/secrets/actions"
echo ""
echo "  ANDROID:"
echo "    ANDROID_KEYSTORE_BASE64   — base64(your-release.keystore)"
echo "    ANDROID_STORE_PASSWORD    — keystore storePassword"
echo "    ANDROID_KEY_ALIAS         — key alias"
echo "    ANDROID_KEY_PASSWORD      — key password"
echo ""
echo "  iOS:"
echo "    IOS_CERTIFICATE_BASE64          — base64(your-certificate.p12)"
echo "    IOS_CERTIFICATE_PASSWORD        — P12 password"
echo "    IOS_PROVISIONING_PROFILE_BASE64 — base64(your-profile.mobileprovision)"
echo "    IOS_KEYCHAIN_PASSWORD           — any secure string"
echo "    IOS_TEAM_ID                     — Apple Team ID (10-char string)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Done! Create a release:"
echo "     git tag v1.0.0 && git push origin v1.0.0"
echo "  This triggers the CI/CD to build APK + IPA automatically."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
