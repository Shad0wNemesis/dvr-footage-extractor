"""
Noor Al-Quran — Local AI Microservice
======================================
FastAPI application that exposes AI capabilities to the Flutter app via
HTTP REST. Designed to run on-device (via Termux/flutter_background_exec)
or on a self-hosted local server (Raspberry Pi, home PC, Docker).

Endpoints
---------
POST /api/search      — Semantic RAG search over the Quran corpus
POST /api/recitation  — Arabic Tajweed STT evaluation
POST /api/vision      — Mus'haf page detection (YOLO + OCR)
GET  /health          — Liveness probe for the Flutter AI client
"""

from __future__ import annotations

import asyncio
import time
from contextlib import asynccontextmanager
from typing import AsyncGenerator

import uvicorn
from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from config import Settings
from routes.recitation import router as recitation_router
from routes.search import router as search_router
from routes.vision import router as vision_router
from services.embedding_service import EmbeddingService
from services.llm_service import LLMService
from services.stt_service import STTService
from services.vector_store import VectorStore
from services.vision_service import VisionService

# ── Application settings ──────────────────────────────────────────────────────

settings = Settings()


# ── Lifespan: load all heavyweight models once at startup ─────────────────────

@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """
    Load AI models during startup, release during shutdown.

    Models are loaded in parallel using asyncio.gather() to minimise
    startup latency on multi-core hardware.
    """
    print("⚡ Noor Al-Quran AI Service starting…")
    start = time.perf_counter()

    # Initialise all services concurrently.
    embedding_service = EmbeddingService(settings)
    vector_store = VectorStore(settings, embedding_service)
    llm_service = LLMService(settings)
    stt_service = STTService(settings)
    vision_service = VisionService(settings)

    await asyncio.gather(
        embedding_service.load(),
        vector_store.load(),
        llm_service.load(),
        stt_service.load(),
        vision_service.load(),
    )

    # Attach services to app state so routers can access them via request.app.state.
    app.state.embedding = embedding_service
    app.state.vector_store = vector_store
    app.state.llm = llm_service
    app.state.stt = stt_service
    app.state.vision = vision_service

    elapsed = time.perf_counter() - start
    print(f"✅ All models loaded in {elapsed:.2f}s — ready to serve requests.")

    yield  # Application runs here.

    # Graceful shutdown: release GPU/CPU memory.
    print("🛑 Shutting down AI services…")
    await asyncio.gather(
        embedding_service.unload(),
        llm_service.unload(),
        stt_service.unload(),
        vision_service.unload(),
    )


# ── FastAPI application ───────────────────────────────────────────────────────

app = FastAPI(
    title="Noor Al-Quran AI Microservice",
    description="Local AI backend for semantic search, Tajweed evaluation, and page detection.",
    version="1.0.0",
    lifespan=lifespan,
    docs_url="/docs" if settings.debug else None,   # Disable Swagger in prod.
    redoc_url=None,
)

# Allow the Flutter app to reach this service from any origin on the LAN.
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)


# ── Request timing middleware ──────────────────────────────────────────────────

@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start = time.perf_counter()
    response = await call_next(request)
    elapsed_ms = (time.perf_counter() - start) * 1000
    response.headers["X-Process-Time-Ms"] = f"{elapsed_ms:.1f}"
    return response


# ── Routers ───────────────────────────────────────────────────────────────────

app.include_router(search_router,     prefix="/api/search",     tags=["Search"])
app.include_router(recitation_router, prefix="/api/recitation", tags=["Recitation"])
app.include_router(vision_router,     prefix="/api/vision",     tags=["Vision"])


# ── Health check ──────────────────────────────────────────────────────────────

@app.get("/health", tags=["System"])
async def health() -> dict:
    """Liveness probe. Flutter AI client polls this before sending requests."""
    return {
        "status": "ok",
        "models": {
            "embedding": app.state.embedding.is_loaded,
            "llm":       app.state.llm.is_loaded,
            "stt":       app.state.stt.is_loaded,
            "vision":    app.state.vision.is_loaded,
        },
    }


# ── Global exception handler ──────────────────────────────────────────────────

@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(
        status_code=500,
        content={"detail": str(exc), "path": str(request.url)},
    )


# ── Entrypoint ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host=settings.host,
        port=settings.port,
        reload=settings.debug,
        workers=1,          # Single worker — models are not fork-safe.
        log_level="info",
    )
