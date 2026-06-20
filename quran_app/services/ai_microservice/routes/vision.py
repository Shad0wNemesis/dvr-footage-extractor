"""
/api/vision  — Mus'haf page detection via YOLO + OCR.

Pipeline
--------
1. Decode base64 JPEG frame from the Flutter camera feed
2. Pass raw bytes to VisionService.detect_page()
   - If mushaf_yolov8n.pt is present: run YOLO layout detection + OCR on
     the detected page-number bounding box
   - Fallback: run EasyOCR on the bottom-centre strip of the frame
3. Return the detected page number (1–604), confidence, and all bounding boxes
"""

from __future__ import annotations

import base64
import time

from fastapi import APIRouter, HTTPException, Request

from models.schemas import DetectedRegion, VisionRequest, VisionResponse

router = APIRouter()


@router.post("", response_model=VisionResponse)
async def detect_mushaf_page(
    request: Request,
    body: VisionRequest,
) -> VisionResponse:
    """
    Detect the Mus'haf page number from a base64-encoded JPEG camera frame.

    Returns the detected page number (1–604), the OCR confidence score,
    and a list of all YOLO-detected layout bounding boxes in normalised
    coordinates [0, 1].

    When the custom YOLO model is not loaded the service falls back to
    EasyOCR-only mode and returns an empty regions list.
    """
    vision_service = request.app.state.vision

    if not vision_service.is_loaded:
        raise HTTPException(
            status_code=503,
            detail="Vision service is not ready yet. Retry in a moment.",
        )

    # ── Decode the incoming image ─────────────────────────────────────────────
    try:
        image_bytes = base64.b64decode(body.image_base64)
    except Exception as exc:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid base64 payload: {exc}",
        )

    # ── Run inference on a thread pool to avoid blocking the event loop ───────
    t_start = time.perf_counter()
    page_number, confidence, raw_regions = await vision_service.detect_page(image_bytes)
    inference_ms = (time.perf_counter() - t_start) * 1000

    # ── Map raw dicts to typed DetectedRegion models ──────────────────────────
    regions = [
        DetectedRegion(
            label=r["label"],
            confidence=r["confidence"],
            x=r["x"],
            y=r["y"],
            width=r["width"],
            height=r["height"],
        )
        for r in raw_regions
    ]

    return VisionResponse(
        detected_page=page_number,
        confidence=confidence,
        regions=regions,
        inference_ms=inference_ms,
    )
