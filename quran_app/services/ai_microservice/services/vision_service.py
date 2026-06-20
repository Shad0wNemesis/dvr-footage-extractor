"""
Computer Vision service for Mus'haf page detection.

Pipeline
--------
1. Decode JPEG frame from the Flutter camera
2. Run YOLOv8n inference to detect regions: page_number, surah_header, verse_text
3. OCR the page_number bounding box using EasyOCR
4. Return the detected page number + all bounding boxes

Model: mushaf_yolov8n.pt
  Custom-trained YOLOv8 nano on a dataset of standard Hafs Mus'haf pages.
  The model must be trained separately — see the AI roadmap doc.
  Fallback: if no custom model exists, we use OCR-only (EasyOCR on full frame).
"""

from __future__ import annotations

import asyncio
import base64
import io
import time
from concurrent.futures import ThreadPoolExecutor
from functools import partial
from typing import List, Optional, Tuple

import numpy as np

from config import Settings


class VisionService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._yolo = None
        self._ocr = None
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="vision")
        self.is_loaded = False

    async def load(self) -> None:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(self._executor, self._load_sync)

    def _load_sync(self) -> None:
        # EasyOCR is always available as fallback.
        import easyocr  # type: ignore
        self._ocr = easyocr.Reader(["ar"], gpu=False, verbose=False)

        # YOLO model is optional — skip if not available.
        if self._settings.yolo_model_path.exists():
            from ultralytics import YOLO  # type: ignore
            self._yolo = YOLO(str(self._settings.yolo_model_path))
            print(f"✅ VisionService: YOLO model loaded + EasyOCR ready")
        else:
            print(
                "⚠️  VisionService: No YOLO model found — using OCR-only mode. "
                "Train mushaf_yolov8n.pt to enable layout detection."
            )
        self.is_loaded = True

    async def detect_page(
        self,
        image_bytes: bytes,
    ) -> Tuple[Optional[int], float, List[dict]]:
        """
        Detect the Mus'haf page number from a camera frame.

        Returns
        -------
        (page_number, confidence, regions)
        """
        if not self.is_loaded:
            return None, 0.0, []
        loop = asyncio.get_event_loop()
        fn = partial(self._detect_sync, image_bytes)
        return await loop.run_in_executor(self._executor, fn)

    def _detect_sync(
        self,
        image_bytes: bytes,
    ) -> Tuple[Optional[int], float, List[dict]]:
        from PIL import Image  # type: ignore

        img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        img_np = np.array(img)
        regions: List[dict] = []
        page_num: Optional[int] = None
        confidence = 0.0

        # ── YOLO layout detection ────────────────────────────────────────
        if self._yolo is not None:
            results = self._yolo(img_np, conf=self._settings.vision_confidence_threshold)
            for r in results:
                for box in r.boxes:
                    label = r.names[int(box.cls)]
                    x, y, w, h = box.xywhn[0].tolist()
                    conf = float(box.conf)
                    regions.append({
                        "label": label,
                        "confidence": conf,
                        "x": x - w / 2,
                        "y": y - h / 2,
                        "width": w,
                        "height": h,
                    })

            # Find the page_number region and OCR it.
            page_region = next(
                (r for r in regions if r["label"] == "page_number"), None
            )
            if page_region:
                crop = self._crop_region(img_np, page_region)
                page_num, confidence = self._ocr_number(crop)

        else:
            # Fallback: run OCR on the bottom-center strip of the image
            # (common position for page numbers in most Mus'haf prints).
            h, w = img_np.shape[:2]
            strip = img_np[int(h * 0.90):h, int(w * 0.35):int(w * 0.65)]
            page_num, confidence = self._ocr_number(strip)

        return page_num, confidence, regions

    def _crop_region(self, img: np.ndarray, region: dict) -> np.ndarray:
        """Crop a normalised bounding box region from the image."""
        h, w = img.shape[:2]
        x1 = int(region["x"] * w)
        y1 = int(region["y"] * h)
        x2 = int((region["x"] + region["width"]) * w)
        y2 = int((region["y"] + region["height"]) * h)
        return img[max(0, y1):min(h, y2), max(0, x1):min(w, x2)]

    def _ocr_number(self, img: np.ndarray) -> Tuple[Optional[int], float]:
        """OCR a cropped image region and extract an integer page number."""
        if self._ocr is None or img.size == 0:
            return None, 0.0

        results = self._ocr.readtext(img, detail=1, paragraph=False)
        for _, text, conf in results:
            # Strip Arabic-Indic numerals and convert to ASCII digits.
            clean = _arabic_to_ascii(text.strip())
            try:
                num = int(clean)
                if 1 <= num <= 604:  # Valid Mus'haf page range
                    return num, float(conf)
            except ValueError:
                continue
        return None, 0.0

    async def unload(self) -> None:
        self._yolo = None
        self._ocr = None
        self.is_loaded = False
        self._executor.shutdown(wait=False)


def _arabic_to_ascii(text: str) -> str:
    """Convert Arabic-Indic digit characters (٠١٢…٩) to ASCII (0-9)."""
    mapping = str.maketrans("٠١٢٣٤٥٦٧٨٩", "0123456789")
    return text.translate(mapping)
