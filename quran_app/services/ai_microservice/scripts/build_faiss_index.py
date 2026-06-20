"""
One-time script: build FAISS vector index from the Quran corpus.

Usage
-----
    cd services/ai_microservice
    pip install -r requirements.txt
    python scripts/build_faiss_index.py \
        --input  data/ayahs_with_translations.json \
        --output data/faiss_index

Input JSON format (one object per Ayah):
    [
        {
            "verse_key":    "1:1",
            "surah_id":     1,
            "ayah_number":  1,
            "surah_name":   "Al-Fatihah",
            "text_arabic":  "بِسۡمِ ٱللَّهِ...",
            "translation_en": "In the name of Allah...",
            "tafseer_snippet": "Ibn Kathir: ..."
        },
        ...
    ]

The script embeds a concatenation of:
    translation_en + " | " + transliteration (if available)

so that English queries ("patience", "mercy") map to the correct Ayahs.
For best results, also index the Arabic transliteration.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import numpy as np


def main() -> None:
    parser = argparse.ArgumentParser(description="Build FAISS index for Quran corpus.")
    parser.add_argument("--input",  type=Path, required=True, help="Path to ayahs JSON file.")
    parser.add_argument("--output", type=Path, required=True, help="Directory to save the index.")
    parser.add_argument("--model",  type=str,
                        default="sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2")
    parser.add_argument("--batch",  type=int, default=256)
    args = parser.parse_args()

    try:
        import faiss
        from sentence_transformers import SentenceTransformer
    except ImportError:
        print("Install: pip install faiss-cpu sentence-transformers")
        sys.exit(1)

    print(f"Loading corpus from {args.input}…")
    with open(args.input, "r", encoding="utf-8") as f:
        corpus = json.load(f)

    print(f"Loaded {len(corpus)} entries. Building embeddings with '{args.model}'…")
    model = SentenceTransformer(args.model)

    # Build the text to embed: combine translation + Arabic for multilingual retrieval.
    texts = []
    for entry in corpus:
        parts = []
        if entry.get("translation_en"):
            parts.append(entry["translation_en"])
        if entry.get("text_arabic"):
            parts.append(entry["text_arabic"])
        texts.append(" | ".join(parts))

    # Encode in batches.
    embeddings = model.encode(
        texts,
        batch_size=args.batch,
        show_progress_bar=True,
        convert_to_numpy=True,
        normalize_embeddings=True,   # L2-normalise for cosine via inner product
    )

    print(f"Embeddings shape: {embeddings.shape}")

    # Build FAISS index (IndexFlatIP = exact inner product search).
    dim = embeddings.shape[1]
    index = faiss.IndexFlatIP(dim)
    index.add(embeddings.astype(np.float32))

    print(f"FAISS index built: {index.ntotal} vectors, dim={dim}")

    # Persist index and metadata.
    args.output.mkdir(parents=True, exist_ok=True)
    faiss.write_index(index, str(args.output / "index.faiss"))
    with open(args.output / "metadata.json", "w", encoding="utf-8") as f:
        json.dump(corpus, f, ensure_ascii=False, indent=2)

    print(f"✅ Index saved to {args.output}/")
    print(f"   index.faiss  ({index.ntotal} vectors)")
    print(f"   metadata.json ({len(corpus)} entries)")


if __name__ == "__main__":
    main()
