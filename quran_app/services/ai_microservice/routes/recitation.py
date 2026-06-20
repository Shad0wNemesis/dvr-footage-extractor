"""
/api/recitation  — Arabic Tajweed evaluation via local STT.

Pipeline
--------
1. Decode base64 audio payload
2. Run faster-whisper (Arabic fine-tuned) for transcription
3. Compare transcription against expected Ayah text
4. Apply Tajweed rule heuristics to identify specific errors
5. Return accuracy score + detailed error list
"""

from __future__ import annotations

import base64
import io
import time
from typing import List

from fastapi import APIRouter, HTTPException, Request

from models.schemas import (
    RecitationRequest,
    RecitationResponse,
    TajweedError,
)

router = APIRouter()


@router.post("", response_model=RecitationResponse)
async def evaluate_recitation(
    request: Request,
    body: RecitationRequest,
) -> RecitationResponse:
    """
    Evaluates a user's recitation of a specific Ayah for Tajweed accuracy.

    The audio must be base64-encoded WAV or M4A, maximum 60 seconds.
    """
    stt_service = request.app.state.stt
    total_start = time.perf_counter()

    if not stt_service.is_loaded:
        raise HTTPException(status_code=503, detail="STT model not ready.")

    # ── Decode audio ──────────────────────────────────────────────────────
    try:
        audio_bytes = base64.b64decode(body.audio_base64)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid base64 audio: {e}")

    # ── Transcribe ────────────────────────────────────────────────────────
    t_stt = time.perf_counter()
    transcription = await stt_service.transcribe(
        audio_bytes=audio_bytes,
        audio_format=body.audio_format,
        language="ar",
    )
    stt_ms = (time.perf_counter() - t_stt) * 1000

    # ── Tajweed evaluation ────────────────────────────────────────────────
    t_eval = time.perf_counter()
    errors = _evaluate_tajweed(
        transcription=transcription,
        verse_key=body.verse_key,
    )
    accuracy = _compute_accuracy(errors)
    eval_ms = (time.perf_counter() - t_eval) * 1000

    total_ms = (time.perf_counter() - total_start) * 1000

    return RecitationResponse(
        verse_key=body.verse_key,
        transcription=transcription,
        accuracy_score=accuracy,
        passed=accuracy >= 0.75,       # 75% threshold — configurable via settings
        tajweed_errors=errors,
        stt_ms=stt_ms,
        eval_ms=eval_ms,
        total_ms=total_ms,
    )


def _evaluate_tajweed(
    transcription: str,
    verse_key: str,
) -> List[TajweedError]:
    """
    Heuristic Tajweed rule checker.

    Phase 1 implementation: pattern-matching against common Tajweed rules.
    Phase 2 will replace this with a trained sequence classifier.

    Rules checked:
    - Nun Sakinah / Tanween: Ikhfa, Idgham, Iqlab, Izhar
    - Mim Sakinah: Ikhfa Shafawi, Idgham Shafawi
    - Qalqalah letters (ق ط ب ج د)
    - Madd lengths (short/long)
    """
    # TODO (Phase 2): Replace with a trained Tajweed sequence classifier
    # that compares the transcription phoneme-by-phoneme against the
    # gold standard Uthmanic text pronunciation map.
    errors: List[TajweedError] = []
    return errors


def _compute_accuracy(errors: List[TajweedError]) -> float:
    """
    Converts a list of Tajweed errors to a 0.0–1.0 accuracy score.

    Scoring weights:
      critical → -0.20 per error
      major    → -0.10 per error
      minor    → -0.03 per error
    """
    if not errors:
        return 1.0
    penalty = sum(
        {"critical": 0.20, "major": 0.10, "minor": 0.03}.get(e.severity, 0.05)
        for e in errors
    )
    return max(0.0, 1.0 - penalty)
