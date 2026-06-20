"""
Speech-to-Text service for Arabic Quran recitation using faster-whisper.

Model selection guide:
  tiny    →  on-device mobile (Termux), ~1s latency
  base    →  Raspberry Pi 4, ~2s latency
  small   →  mid-range laptop CPU, ~3s latency
  large-v3 → server GPU, best accuracy, ~1-2s on CUDA

Arabic fine-tuning
------------------
The stock Whisper models work acceptably for Modern Standard Arabic but miss
Quranic-specific pronunciation (e.g. pause marks, hamza rules). For Phase 2
we will fine-tune on the Tarteel.ai open recitation dataset.
"""

from __future__ import annotations

import asyncio
import io
import tempfile
from concurrent.futures import ThreadPoolExecutor
from functools import partial

from config import Settings


class STTService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._model = None
        self._executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="stt")
        self.is_loaded = False

    async def load(self) -> None:
        loop = asyncio.get_event_loop()
        await loop.run_in_executor(self._executor, self._load_sync)

    def _load_sync(self) -> None:
        from faster_whisper import WhisperModel  # type: ignore
        self._model = WhisperModel(
            self._settings.whisper_model_size,
            device=self._settings.whisper_device,
            compute_type=self._settings.whisper_compute_type,
        )
        self.is_loaded = True
        print(
            f"✅ STTService: loaded whisper-{self._settings.whisper_model_size} "
            f"on {self._settings.whisper_device}"
        )

    async def transcribe(
        self,
        audio_bytes: bytes,
        audio_format: str = "wav",
        language: str = "ar",
    ) -> str:
        """
        Transcribe audio bytes to Arabic text.

        The audio is written to a temp file because faster-whisper's
        transcribe() expects a file path, not a bytes buffer.
        """
        if not self.is_loaded or self._model is None:
            raise RuntimeError("STTService not loaded.")

        loop = asyncio.get_event_loop()
        fn = partial(self._transcribe_sync, audio_bytes, audio_format, language)
        return await loop.run_in_executor(self._executor, fn)

    def _transcribe_sync(
        self,
        audio_bytes: bytes,
        audio_format: str,
        language: str,
    ) -> str:
        import tempfile, os

        # Write to a temp file with the correct extension.
        suffix = f".{audio_format}"
        with tempfile.NamedTemporaryFile(suffix=suffix, delete=False) as f:
            f.write(audio_bytes)
            tmp_path = f.name

        try:
            segments, _ = self._model.transcribe(
                tmp_path,
                language=language,
                beam_size=5,
                best_of=5,
                temperature=0.0,    # Greedy decoding for most likely transcription
                vad_filter=True,    # Skip silent segments
            )
            return " ".join(seg.text.strip() for seg in segments)
        finally:
            os.unlink(tmp_path)

    async def unload(self) -> None:
        self._model = None
        self.is_loaded = False
        self._executor.shutdown(wait=False)
