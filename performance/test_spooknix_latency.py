"""
Performance: Spooknix STT latency SLO
Transcription completes in < 30s per minute of audio (ROADMAP 7.3)
"""

import io
import time
import wave
import struct
import math
import pytest
import httpx

pytestmark = [pytest.mark.performance, pytest.mark.slow]

SPOOKNIX_URL = "http://localhost:8000"
LATENCY_RATIO_MAX = 0.5  # must complete in < 50% of audio duration


def _generate_wav(duration_seconds: float, sample_rate: int = 16000) -> bytes:
    """Generate a synthetic sine-wave WAV for testing."""
    num_samples = int(duration_seconds * sample_rate)
    frequency = 440.0  # A4 tone
    buf = io.BytesIO()
    with wave.open(buf, "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(sample_rate)
        samples = [
            int(32767 * math.sin(2 * math.pi * frequency * i / sample_rate))
            for i in range(num_samples)
        ]
        wf.writeframes(struct.pack(f"<{num_samples}h", *samples))
    return buf.getvalue()


def _spooknix_healthy() -> bool:
    try:
        resp = httpx.get(f"{SPOOKNIX_URL}/health", timeout=3.0)
        return resp.status_code == 200
    except Exception:
        return False


def test_spooknix_available():
    """Spooknix health check passes (skip if GPU profile not active)."""
    if not _spooknix_healthy():
        pytest.skip("spooknix not running (start with --profile gpu)")


def test_transcribe_10s_audio():
    """10s audio transcribes in < 5s (ratio ≤ 0.5)."""
    if not _spooknix_healthy():
        pytest.skip("spooknix not running")

    audio_duration = 10.0
    wav_data = _generate_wav(audio_duration)

    start = time.perf_counter()
    resp = httpx.post(
        f"{SPOOKNIX_URL}/transcribe",
        files={"file": ("test.wav", io.BytesIO(wav_data), "audio/wav")},
        timeout=60.0,
    )
    elapsed = time.perf_counter() - start

    assert resp.status_code in (200, 201), f"Transcription failed: {resp.status_code}"
    ratio = elapsed / audio_duration
    assert ratio < LATENCY_RATIO_MAX, (
        f"Transcription too slow: {elapsed:.1f}s for {audio_duration}s audio "
        f"(ratio {ratio:.2f} > {LATENCY_RATIO_MAX})"
    )


def test_transcribe_60s_audio_under_30s():
    """1 minute of audio transcribes in < 30s (ROADMAP SLO)."""
    if not _spooknix_healthy():
        pytest.skip("spooknix not running")

    audio_duration = 60.0
    wav_data = _generate_wav(audio_duration)

    start = time.perf_counter()
    resp = httpx.post(
        f"{SPOOKNIX_URL}/transcribe",
        files={"file": ("test_1min.wav", io.BytesIO(wav_data), "audio/wav")},
        timeout=60.0,
    )
    elapsed = time.perf_counter() - start

    assert resp.status_code in (200, 201), f"Transcription failed: {resp.status_code}"
    assert elapsed < 30.0, (
        f"Transcription SLO violated: {elapsed:.1f}s > 30s for 60s audio"
    )
