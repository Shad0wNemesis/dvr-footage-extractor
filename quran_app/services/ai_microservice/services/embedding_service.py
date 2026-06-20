"""
Sentence embedding service using sentence-transformers.

Model choice: paraphrase-multilingual-MiniLM-L12-v2
  - 117M parameters, 384-dim embeddings
  - Supports Arabic + 50 other languages out-of-the-box
  - ~80ms per query on CPU (Raspberry Pi 4: ~200ms)
  - Semantic quality sufficient for Ayah retrieval tasks

For production on a GPU server, swap for:
  intfloat/multilingual-e5-large  (560M params, 1024-dim, much higher quality)
"""

from __future__ import annotations

import asyncio
from concurrent.futures import ThreadPoolExecutor
from functools import partial

import numpy as np

from config import Settings


class EmbeddingService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._model = None
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="embed")
        self.is_loaded = False

    async def load(self) -> None:
        """Load the sentence-transformer model (blocking I/O → thread pool)."""
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(self._executor, self._load_sync)

    def _load_sync(self) -> None:
        from sentence_transformers import SentenceTransformer  # type: ignore
        self._model = SentenceTransformer(self._settings.embedding_model_name)
        self.is_loaded = True
        print(f"✅ EmbeddingService: loaded '{self._settings.embedding_model_name}'")

    async def embed(self, text: str) -> np.ndarray:
        """Embed a single string and return a float32 numpy array."""
        if not self.is_loaded or self._model is None:
            raise RuntimeError("EmbeddingService not loaded.")
        loop = asyncio.get_event_loop()
        fn = partial(self._model.encode, text, convert_to_numpy=True)
        return await loop.run_in_executor(self._executor, fn)

    async def embed_batch(self, texts: list[str]) -> np.ndarray:
        """Embed a batch of strings. More efficient than calling embed() in a loop."""
        if not self.is_loaded or self._model is None:
            raise RuntimeError("EmbeddingService not loaded.")
        loop = asyncio.get_event_loop()
        fn = partial(
            self._model.encode,
            texts,
            convert_to_numpy=True,
            batch_size=64,
            show_progress_bar=False,
        )
        return await loop.run_in_executor(self._executor, fn)

    async def unload(self) -> None:
        self._model = None
        self.is_loaded = False
        self._executor.shutdown(wait=False)
