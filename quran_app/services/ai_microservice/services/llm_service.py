"""
Local LLM service using llama.cpp (via llama-cpp-python).

Model: Llama-3.2-3B-Instruct Q4_K_M (GGUF)
  - ~2GB on disk, ~2.5GB RAM when loaded
  - Runs fully on CPU at 10–15 tok/s on a modern laptop
  - Sufficient for generating concise, grounded Quranic answers

The LLM is used ONLY for the optional grounded-answer generation in the
RAG pipeline. The retrieval step (FAISS) works without the LLM.
"""

from __future__ import annotations

import asyncio
from concurrent.futures import ThreadPoolExecutor
from functools import partial

from config import Settings


class LLMService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._llm = None
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="llm")
        self.is_loaded = False

    async def load(self) -> None:
        if not self._settings.llm_model_path.exists():
            print(
                f"⚠️  LLM model not found at {self._settings.llm_model_path}. "
                "RAG answers will be disabled. Download a GGUF model to enable."
            )
            return
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(self._executor, self._load_sync)

    def _load_sync(self) -> None:
        from llama_cpp import Llama  # type: ignore
        self._llm = Llama(
            model_path=str(self._settings.llm_model_path),
            n_ctx=self._settings.llm_context_size,
            n_threads=self._settings.llm_threads,
            n_gpu_layers=0,           # Set >0 if CUDA/Metal available
            verbose=False,
        )
        self.is_loaded = True
        print(f"✅ LLMService: loaded {self._settings.llm_model_path.name}")

    async def generate(self, prompt: str) -> str:
        """Generate text from the given prompt."""
        if not self.is_loaded or self._llm is None:
            return ""
        loop = asyncio.get_event_loop()
        fn = partial(self._generate_sync, prompt)
        return await loop.run_in_executor(self._executor, fn)

    def _generate_sync(self, prompt: str) -> str:
        output = self._llm(
            prompt,
            max_tokens=self._settings.llm_max_tokens,
            temperature=self._settings.llm_temperature,
            stop=["USER:", "QUESTION:"],
            echo=False,
        )
        return output["choices"][0]["text"].strip()

    async def unload(self) -> None:
        self._llm = None
        self.is_loaded = False
        self._executor.shutdown(wait=False)
