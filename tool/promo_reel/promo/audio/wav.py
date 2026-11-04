"""24-bit PCM WAV, written with TPDF dither and read back exactly.

The standard library's ``wave`` module does the container; NumPy packs the
samples as little-endian 3-byte integers.
"""

from __future__ import annotations

import wave
from pathlib import Path

import numpy as np

from .dsp import rng

FULL_SCALE = 2 ** 23 - 1


def write(path: str | Path, audio: np.ndarray, sample_rate: int = 48_000, *, dither: bool = True) -> None:
    """``audio``: float (n, channels) in -1..1."""
    x = np.asarray(audio, dtype=float)
    if x.ndim == 1:
        x = x[:, None]
    scaled = x * FULL_SCALE
    if dither:                                    # TPDF, ±1 LSB, seeded: the file is reproducible
        g = rng("tpdf", x.shape)
        scaled = scaled + g.uniform(-0.5, 0.5, x.shape) + g.uniform(-0.5, 0.5, x.shape)
    ints = np.clip(np.round(scaled), -FULL_SCALE - 1, FULL_SCALE).astype("<i4")
    raw = ints.reshape(-1).view(np.uint8).reshape(-1, 4)[:, :3].tobytes()
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(3)
        w.setframerate(sample_rate)
        w.writeframes(raw)


def read(path: str | Path) -> tuple[np.ndarray, int]:
    """-> (float (n, channels), sample_rate) from a 16- or 24-bit PCM WAV."""
    with wave.open(str(path), "rb") as w:
        channels, width, rate, frames = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(frames)
    if width == 3:
        b = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3)
        ints = (b[:, 0].astype(np.int32) | (b[:, 1].astype(np.int32) << 8) | (b[:, 2].astype(np.int32) << 16))
        ints = np.where(ints & 0x800000, ints - (1 << 24), ints)
        x = ints / float(FULL_SCALE)
    elif width == 2:
        x = np.frombuffer(raw, dtype="<i2") / 32768.0
    else:
        raise ValueError(f"{path}: {8 * width}-bit WAV is not supported")
    return x.reshape(-1, channels), rate
