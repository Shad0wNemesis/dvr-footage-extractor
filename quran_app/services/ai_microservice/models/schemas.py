"""
Pydantic v2 request/response schemas for all API endpoints.

Every field is strictly typed and documented so the Flutter HTTP client
can generate correct serialization code.
"""

from __future__ import annotations

from typing import List, Optional

from pydantic import BaseModel, Field, field_validator


# ── Shared ────────────────────────────────────────────────────────────────────

class AyahResult(BaseModel):
    """A single Ayah result returned by the search and RAG endpoints."""
    verse_key: str = Field(description="Composite key e.g. '2:255'")
    surah_id: int
    ayah_number: int
    surah_name: str
    text_arabic: str
    translation_en: Optional[str] = None
    tafseer_snippet: Optional[str] = None
    relevance_score: float = Field(ge=0.0, le=1.0)


# ── /api/search ───────────────────────────────────────────────────────────────

class SemanticSearchRequest(BaseModel):
    """Natural-language query sent to the RAG pipeline."""
    query: str = Field(min_length=1, max_length=500)
    top_k: int = Field(default=5, ge=1, le=20)
    language: str = Field(default="en", pattern=r"^[a-z]{2}$")
    include_tafseer: bool = Field(default=False)

    @field_validator("query")
    @classmethod
    def strip_query(cls, v: str) -> str:
        return v.strip()


class SemanticSearchResponse(BaseModel):
    results: List[AyahResult]
    answer: Optional[str] = Field(
        default=None,
        description="LLM-generated answer grounded in the retrieved Ayahs.",
    )
    query_embedding_ms: float
    retrieval_ms: float
    llm_ms: Optional[float] = None
    total_ms: float


# ── /api/recitation ───────────────────────────────────────────────────────────

class RecitationRequest(BaseModel):
    """Audio data + expected verse for Tajweed evaluation."""
    verse_key: str = Field(pattern=r"^\d{1,3}:\d{1,3}$")
    # Base64-encoded audio bytes (WAV or M4A, max 60s)
    audio_base64: str
    audio_format: str = Field(default="wav", pattern=r"^(wav|m4a|mp3|ogg)$")


class TajweedError(BaseModel):
    """A single Tajweed rule violation detected in the recitation."""
    word_position: int = Field(description="1-indexed word position within the verse.")
    rule_name: str = Field(description="e.g. 'ikhfa', 'idgham', 'qalqalah'")
    expected: str = Field(description="What the correct pronunciation should be.")
    detected: str = Field(description="What the STT model transcribed.")
    severity: str = Field(pattern=r"^(minor|major|critical)$")


class RecitationResponse(BaseModel):
    verse_key: str
    transcription: str = Field(description="Raw Arabic text produced by the STT model.")
    accuracy_score: float = Field(ge=0.0, le=1.0)
    passed: bool
    tajweed_errors: List[TajweedError]
    stt_ms: float
    eval_ms: float
    total_ms: float


# ── /api/vision ───────────────────────────────────────────────────────────────

class VisionRequest(BaseModel):
    """A single camera frame for Mus'haf page detection."""
    # Base64-encoded JPEG frame
    image_base64: str
    image_width: int = Field(gt=0)
    image_height: int = Field(gt=0)


class DetectedRegion(BaseModel):
    """A YOLO-detected bounding box in normalised coordinates (0–1)."""
    label: str          # e.g. "page_number", "surah_header", "verse_text"
    confidence: float
    x: float            # top-left x (normalised)
    y: float            # top-left y (normalised)
    width: float        # box width (normalised)
    height: float       # box height (normalised)


class VisionResponse(BaseModel):
    detected_page: Optional[int] = Field(
        default=None,
        description="Detected Mus'haf page number (1–604), or null if not detected.",
    )
    confidence: float
    regions: List[DetectedRegion]
    inference_ms: float
