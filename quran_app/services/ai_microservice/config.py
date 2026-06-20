"""
Application configuration via environment variables.

All settings have sensible defaults so the service runs out-of-the-box
without any configuration for local development.

Usage:
    export LLM_MODEL_PATH=/path/to/llama-3.2-3b.Q4_K_M.gguf
    python main.py
"""

from __future__ import annotations

from pathlib import Path
from typing import List

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    # ── Server ──────────────────────────────────────────────────────────────
    host: str = "127.0.0.1"          # Bind to localhost by default (LAN: 0.0.0.0)
    port: int = 8765
    debug: bool = False
    allowed_origins: List[str] = ["*"]

    # ── Model paths ──────────────────────────────────────────────────────────
    # Embedding model (sentence-transformers — runs entirely on CPU)
    embedding_model_name: str = "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2"

    # FAISS vector index path — created by scripts/build_faiss_index.py
    faiss_index_path: Path = Path("data/faiss_index")

    # Verse metadata JSON (parallel to the FAISS index)
    verse_metadata_path: Path = Path("data/verse_metadata.json")

    # LLM (GGUF format — runs via llama.cpp)
    llm_model_path: Path = Path("models/llama-3.2-3b.Q4_K_M.gguf")
    llm_context_size: int = 4096
    llm_max_tokens: int = 512
    llm_temperature: float = 0.1      # Near-deterministic for factual answers
    llm_threads: int = 4              # Adjust to CPU core count

    # STT (faster-whisper — Arabic fine-tuned)
    whisper_model_size: str = "large-v3"   # "tiny" for on-device, "large-v3" for server
    whisper_device: str = "cpu"            # "cuda" if GPU available
    whisper_compute_type: str = "int8"     # Quantization: int8 for CPU, float16 for GPU

    # Vision (YOLOv8)
    yolo_model_path: Path = Path("models/mushaf_yolov8n.pt")
    vision_confidence_threshold: float = 0.6

    # ── RAG settings ─────────────────────────────────────────────────────────
    # Number of candidate Ayahs retrieved from FAISS before re-ranking
    rag_top_k_candidates: int = 20
    # Number of Ayahs returned after LLM re-ranking
    rag_top_k_final: int = 5
    # Whether to include Tafseer context in the LLM prompt
    rag_include_tafseer: bool = True

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"
