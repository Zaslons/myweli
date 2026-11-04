"""Film grain and dithering — on the finished frame, in numpy.

GRAIN (the hook only, storyboard: « Grain only in the hook »). Monochrome
Gaussian noise, softened to a grain size and renormalised, added to the
encoded values with a midtone-weighted amplitude (film grain shows most in
the mids, least in deep black and paper white), so black stays black-ish
and the paper's highlights stay clean. It is SEEDED PER FRAME — frame n
always gets the same grain (a re-render is byte-identical), and consecutive
frames differ (the grain lives).

DITHER. Every float → 8-bit conversion goes through `quantize()`:
triangular (TPDF) noise of ±1 level before rounding, which turns the
staircase of a slow gradient (a veil, a shadow, the band's fade, a 0.4-α
pattern on black) into invisible noise instead of bands — and survives the
platforms' re-encodes better than bands do. Also seeded per frame.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
from scipy.ndimage import gaussian_filter


def _rng(seed: int, frame: int, stream: int) -> np.random.Generator:
    return np.random.default_rng([int(seed) & 0xFFFFFFFF, int(frame) & 0xFFFFFFFF, stream])


def tpdf(shape: tuple[int, ...], seed: int, frame: int) -> np.ndarray:
    """Triangular noise in [-1, 1) levels, float32."""
    g = _rng(seed, frame, 1)
    return (g.random(shape, dtype=np.float32) - g.random(shape, dtype=np.float32))


def quantize(values: np.ndarray, seed: int = 0, frame: int = 0) -> np.ndarray:
    """Float values on the 0..255 scale → uint8 with TPDF dither."""
    v = np.asarray(values, dtype=np.float32)
    return np.clip(np.floor(v + 0.5 + tpdf(v.shape, seed, frame)), 0, 255).astype(np.uint8)


@dataclass(frozen=True)
class GrainSpec:
    strength: float = 6.0          # std of the grain in 8-bit levels at mid-grey
    size: float = 0.9              # Gaussian sigma (px) softening the noise: the grain's size
    floor: float = 0.35            # share of the amplitude left at black and white


SPEC = GrainSpec()


def grain_field(height: int, width: int, seed: int, frame: int, spec: GrainSpec = SPEC) -> np.ndarray:
    """(h, w) float32 noise with unit standard deviation and grain `size`."""
    n = _rng(seed, frame, 2).standard_normal((height, width), dtype=np.float32)
    if spec.size > 0:
        n = gaussian_filter(n, spec.size, mode="wrap")
        std = float(n.std())
        if std > 0:
            n /= std
    return n


def apply_grain(rgba: np.ndarray, frame: int, seed: int = 0, spec: GrainSpec = SPEC,
                amount: float = 1.0) -> np.ndarray:
    """A new (h, w, 4) uint8 frame: `rgba` with grain for `frame` (alpha
    kept). `amount` scales it (fade grain in or out)."""
    if amount <= 0:
        return rgba.copy()
    h, w = rgba.shape[:2]
    rgb = rgba[..., :3].astype(np.float32)
    luma = (rgb @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)) / 255.0
    weight = spec.floor + (1.0 - spec.floor) * (4.0 * luma * (1.0 - luma))
    noise = grain_field(h, w, seed, frame, spec) * (spec.strength * amount) * weight
    out = rgba.copy()
    out[..., :3] = quantize(rgb + noise[..., None], seed, frame)
    return out
