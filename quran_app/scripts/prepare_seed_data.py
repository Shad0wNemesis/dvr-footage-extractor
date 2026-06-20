#!/usr/bin/env python3
"""
Download and format the complete Quran dataset from the quran.com API.

Usage:
    python3 scripts/prepare_seed_data.py --output assets/json/

The quran.com API (v4) is free and open; no API key is required for
the public read endpoints used here.

Outputs:
    assets/json/surahs.json   — 114 chapters in the format SurahSeed.fromJson() expects
    assets/json/ayahs.json    — 6,236 verses in the format AyahSeed.fromJson() expects
"""

import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path

BASE_URL = "https://api.quran.com/api/v4"
HEADERS = {"Accept": "application/json"}


def _get(url: str, retries: int = 3) -> dict:
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=HEADERS)
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read())
        except Exception as e:
            if attempt == retries - 1:
                raise
            print(f"  Retry {attempt + 1}/{retries} for {url}: {e}")
            time.sleep(2 ** attempt)


def download_surahs() -> list:
    print("Downloading chapters…")
    data = _get(f"{BASE_URL}/chapters?language=en")
    return data.get("chapters", [])


def download_ayahs_for_chapter(chapter_id: int) -> list:
    """Returns all verses for one chapter across all pages."""
    verses = []
    page = 1
    while True:
        url = (
            f"{BASE_URL}/verses/by_chapter/{chapter_id}"
            f"?language=en&words=false&translations=131"
            f"&fields=text_uthmani,text_indopak,text_imlaei_simple"
            f",juz_number,hizb_number,rub_el_hizb_number"
            f",page_number,ruku_number,manzil_number,sajdah_type"
            f"&per_page=50&page={page}"
        )
        data = _get(url)
        batch = data.get("verses", [])
        if not batch:
            break
        verses.extend(batch)
        meta = data.get("meta", {})
        total_pages = meta.get("total_pages", 1)
        if page >= total_pages:
            break
        page += 1
        time.sleep(0.2)  # be polite to the API
    return verses


def transform_verse(v: dict, chapter_id: int) -> dict:
    """Reshape quran.com v4 verse format to match AyahSeed.fromJson()."""
    translations = v.get("translations", [])
    translation_text = translations[0]["text"] if translations else ""

    # quran.com v4 uses "text_imlaei_simple" for the simple clean text
    text_simple = (
        v.get("text_imlaei_simple")
        or v.get("text_simple")
        or v.get("text_uthmani", "")
    )

    return {
        "id": v["id"],
        "chapter_id": chapter_id,
        "verse_number": v["verse_number"],
        "verse_key": v["verse_key"],
        "text_uthmani": v.get("text_uthmani", ""),
        "text_indopak": v.get("text_indopak"),
        "text_simple": text_simple,
        "juz_number": v.get("juz_number", 0),
        "hizb_number": v.get("hizb_number", 0),
        "rub_el_hizb_number": v.get("rub_el_hizb_number", 0),
        "page_number": v.get("page_number", 0),
        "ruku_number": v.get("ruku_number", 0),
        "manzil_number": v.get("manzil_number", 0),
        "sajdah_type": v.get("sajdah_type"),
        "translation_en": translation_text,
    }


def main():
    parser = argparse.ArgumentParser(description="Download Quran seed data")
    parser.add_argument(
        "--output",
        default="assets/json",
        help="Output directory (default: assets/json)",
    )
    parser.add_argument(
        "--chapters-only",
        action="store_true",
        help="Only download surahs.json, skip verses",
    )
    args = parser.parse_args()

    out_dir = Path(args.output)
    out_dir.mkdir(parents=True, exist_ok=True)

    # ── Surahs ──────────────────────────────────────────────────────────────
    chapters = download_surahs()
    if not chapters:
        print("ERROR: No chapters returned from API", file=sys.stderr)
        sys.exit(1)

    surahs_path = out_dir / "surahs.json"
    surahs_path.write_text(
        json.dumps({"chapters": chapters}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"Wrote {len(chapters)} chapters → {surahs_path}")

    if args.chapters_only:
        return

    # ── Ayahs ───────────────────────────────────────────────────────────────
    all_verses = []
    for ch in chapters:
        cid = ch["id"]
        print(f"  Chapter {cid:3d}/114 — {ch.get('name_simple', '')}…", end=" ", flush=True)
        raw_verses = download_ayahs_for_chapter(cid)
        transformed = [transform_verse(v, cid) for v in raw_verses]
        all_verses.extend(transformed)
        print(f"{len(transformed)} verses")

    ayahs_path = out_dir / "ayahs.json"
    ayahs_path.write_text(
        json.dumps({"verses": all_verses}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(f"\nWrote {len(all_verses)} verses → {ayahs_path}")
    print("Done.")


if __name__ == "__main__":
    main()
