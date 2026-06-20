"""
FAISS-backed vector store for semantic Ayah retrieval.

Index structure
---------------
We use a FAISS IndexFlatIP (inner product / cosine similarity after L2-norm)
because:
  - Corpus size is small (6,236 Ayahs + ~50k tafseer chunks) — no IVF needed.
  - Inner product on L2-normalised vectors == cosine similarity.
  - Exact search gives perfect recall — no approximate trade-off.

The index is built once by `scripts/build_faiss_index.py` and loaded here
on every service startup. Searches complete in <5ms for the full Quran corpus.

Metadata
--------
Parallel to the FAISS index we store a JSON metadata file with one entry per
indexed vector containing: verse_key, surah_id, ayah_number, surah_name,
text_arabic, translation_en, tafseer_snippet.
"""

from __future__ import annotations

import json
import time
from pathlib import Path
from typing import List, Tuple

import numpy as np

from config import Settings
from services.embedding_service import EmbeddingService


class VectorStore:
    """
    Wraps a FAISS index with verse metadata for semantic search.

    Usage:
        store = VectorStore(settings, embedding_service)
        await store.load()
        results = await store.search("patience during hardship", top_k=5)
    """

    def __init__(self, settings: Settings, embedding: EmbeddingService) -> None:
        self._settings = settings
        self._embedding = embedding
        self._index = None           # faiss.Index, loaded lazily
        self._metadata: List[dict] = []
        self.is_loaded = False

    async def load(self) -> None:
        """Load the FAISS index and metadata from disk."""
        import faiss  # Lazy import — not installed until needed.

        index_path = self._settings.faiss_index_path / "index.faiss"
        meta_path = self._settings.verse_metadata_path

        if not index_path.exists():
            print(
                f"⚠️  FAISS index not found at {index_path}. "
                "Run scripts/build_faiss_index.py to build it."
            )
            self.is_loaded = False
            return

        self._index = faiss.read_index(str(index_path))

        if meta_path.exists():
            with open(meta_path, "r", encoding="utf-8") as f:
                self._metadata = json.load(f)
        else:
            print(f"⚠️  Verse metadata not found at {meta_path}.")
            self._metadata = []

        self.is_loaded = True
        print(
            f"✅ FAISS index loaded: {self._index.ntotal} vectors, "
            f"{len(self._metadata)} metadata entries."
        )

    async def search(
        self,
        query: str,
        top_k: int = 5,
    ) -> Tuple[List[dict], float, float]:
        """
        Embed the query and retrieve the top-k most semantically similar Ayahs.

        Returns
        -------
        (results, embedding_ms, retrieval_ms)
            results       — list of metadata dicts with added "score" key
            embedding_ms  — time spent embedding the query
            retrieval_ms  — time spent searching the FAISS index
        """
        if not self.is_loaded or self._index is None:
            return [], 0.0, 0.0

        # ── Embed the query ──────────────────────────────────────────────
        t0 = time.perf_counter()
        query_vector = await self._embedding.embed(query)
        # Normalise to unit length for cosine similarity via inner product.
        query_vector = query_vector / np.linalg.norm(query_vector)
        query_vector = query_vector.reshape(1, -1).astype(np.float32)
        embedding_ms = (time.perf_counter() - t0) * 1000

        # ── Search the FAISS index ────────────────────────────────────────
        t1 = time.perf_counter()
        scores, indices = self._index.search(query_vector, top_k)
        retrieval_ms = (time.perf_counter() - t1) * 1000

        results = []
        for score, idx in zip(scores[0], indices[0]):
            if idx < 0 or idx >= len(self._metadata):
                continue
            entry = dict(self._metadata[idx])
            entry["relevance_score"] = float(score)
            results.append(entry)

        return results, embedding_ms, retrieval_ms

    async def unload(self) -> None:
        self._index = None
        self._metadata = []
        self.is_loaded = False
