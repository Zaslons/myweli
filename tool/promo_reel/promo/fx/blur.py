"""Motion blur by subframe accumulation, and the whip pan.

A frame with motion blur is what a shutter sees: the scene integrated over
the time the shutter is open. `accumulate()` renders the caller's
draw(canvas, t) at N instants spread over the shutter interval centred on
the frame (t − shutter/2 … t + shutter/2, in frames) and averages them.

WHERE THE AVERAGE IS TAKEN — LINEAR LIGHT. A camera integrates photons,
which add linearly; sRGB-encoded values do not. Averaging encoded values
makes every smear too dark: half white paper and half black ink averages to
level 128 encoded (« 22 % » grey to the eye) where the light really averages
to level 188 (50 % of the light). On a whip across white cards with black
type that is the difference between a bright, photographic streak and a
muddy grey one, and black text would visibly « thicken » in motion. So each
subframe is decoded to linear light, weighted by its alpha (premultiplied,
so transparent subframes add no colour), summed in float32, and the mean is
re-encoded to sRGB once, with TPDF dither (grain.quantize) so the long, soft
gradients of a smear never band. Premultiplied ENCODED averaging is offered
(`linear=False`) for parity checks only.

HOW MANY SUBFRAMES. The storyboard asks for 8. Eight copies of something
moving 120 px per frame sit 7.5 px apart — on 3-px text strokes that is a
row of ghosts, not a blur. `samples_for(speed)` gives the count that keeps
copies ≤ `max_gap` px apart (never fewer than 8); `WhipPan` uses it.

THE WHIP. Six frames starting on the beat (storyboard), the move on
easeInOutCubic so its peak speed — and the whoosh — falls at +3 frames.
`WhipPan.offset(t)` is the camera offset at any (sub)frame; for a cut
between two scenes `draw_transition()` slides both like one strip of film.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

import numpy as np
import skia

from . import easing
from .grain import quantize
from .surface import new_surface, to_array

Render = Callable[[skia.Canvas, float], None]

# sRGB transfer (IEC 61966-2-1)
def _srgb_to_linear(c: np.ndarray) -> np.ndarray:
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _linear_to_srgb(x: np.ndarray) -> np.ndarray:
    return np.where(x <= 0.0031308, 12.92 * x, 1.055 * np.power(x, 1 / 2.4) - 0.055)


_LUT_TO_LINEAR = _srgb_to_linear(np.arange(256) / 255.0).astype(np.float32)
# linear → encoded levels, 16 384 steps: under 0.2 of a level of error where
# the curve is steepest (at black), far below the ±1-level dither on top
_ENC_STEPS = 16383
_LUT_TO_ENCODED = (_linear_to_srgb(np.arange(_ENC_STEPS + 1) / _ENC_STEPS) * 255.0).astype(np.float32)


def to_linear(encoded: np.ndarray) -> np.ndarray:
    """uint8 sRGB → float32 linear 0..1."""
    return _LUT_TO_LINEAR[encoded]


def to_encoded(linear: np.ndarray) -> np.ndarray:
    """float32 linear 0..1 → float32 sRGB on the 0..255 scale (not rounded)."""
    idx = np.clip(linear, 0.0, 1.0) * _ENC_STEPS + 0.5
    return _LUT_TO_ENCODED[idx.astype(np.int32)]


def subframe_times(t: float, samples: int, shutter: float = 1.0) -> list[float]:
    """`samples` instants evenly inside the shutter interval centred on t."""
    if samples < 1:
        raise ValueError("samples must be ≥ 1")
    return [t + shutter * ((i + 0.5) / samples - 0.5) for i in range(samples)]


def samples_for(speed_px_per_frame: float, shutter: float = 1.0, max_gap: float = 2.0,
                minimum: int = 8, maximum: int = 64) -> int:
    """Subframes so that consecutive copies of something moving at `speed`
    are at most `max_gap` px apart."""
    need = int(np.ceil(abs(speed_px_per_frame) * shutter / max_gap))
    return int(min(maximum, max(minimum, need)))


class Accumulator:
    """Sums RGBA frames in linear light (or encoded), premultiplied."""

    def __init__(self, width: int, height: int, linear: bool = True):
        self.w, self.h, self.linear = width, height, linear
        self.rgb = np.zeros((height, width, 3), np.float32)
        self.alpha = np.zeros((height, width), np.float32)
        self._buf = np.empty((height, width, 3), np.float32)
        self._lut = _LUT_TO_LINEAR if linear else (np.arange(256, dtype=np.float32) / 255.0)
        self.n = 0

    def add(self, rgba: np.ndarray) -> None:
        """Add one unpremultiplied uint8 RGBA frame."""
        np.take(self._lut, rgba[..., :3], out=self._buf)
        alpha = rgba[..., 3]
        if alpha.min() == 255:                       # the usual case: an opaque frame
            self.rgb += self._buf
            self.alpha += 1.0
        else:
            a = alpha.astype(np.float32) / 255.0
            self._buf *= a[..., None]
            self.rgb += self._buf
            self.alpha += a
        self.n += 1

    def result(self, seed: int = 0, frame: int = 0) -> np.ndarray:
        """The mean as unpremultiplied uint8 RGBA, dithered."""
        if self.n == 0:
            raise ValueError("nothing accumulated")
        with np.errstate(invalid="ignore", divide="ignore"):
            c = np.where(self.alpha[..., None] > 0, self.rgb / self.alpha[..., None], 0.0)
        enc = to_encoded(c) if self.linear else np.clip(c, 0, 1) * 255.0
        out = np.empty((self.h, self.w, 4), np.uint8)
        out[..., :3] = quantize(enc, seed, frame)
        out[..., 3] = quantize(self.alpha / self.n * 255.0, seed + 1, frame)
        opaque = self.alpha >= self.n - 1e-4
        out[..., 3][opaque] = 255                    # never dither a solid frame's alpha
        return out


def accumulate(render: Render, size: tuple[int, int], t: float, *, samples: int = 8, shutter: float = 1.0,
               linear: bool = True, seed: int = 0, region: tuple[int, int, int, int] | None = None) -> np.ndarray:
    """Motion-blurred frame t: `render(canvas, ti)` drawn on a cleared
    (transparent) canvas at each subframe time ti, averaged. Returns
    unpremultiplied uint8 RGBA (h, w, 4). With samples == 1 it is the plain
    render at t.

    `region` (x0, y0, x1, y1), when given, is the only part that moves: it
    is averaged, and the rest of the frame is the plain render at t (a whip
    inside the phone window leaves the band and the floor still)."""
    w, h = size
    surf = new_surface(w, h)
    canvas = surf.getCanvas()

    def snap(ti: float, box=None) -> np.ndarray:
        canvas.clear(skia.ColorTRANSPARENT)
        canvas.save()
        render(canvas, ti)
        canvas.restore()
        img = surf.makeImageSnapshot()
        if box is not None:
            img = img.makeSubset(skia.IRect.MakeLTRB(*box))
        return to_array(img)

    if samples == 1:
        return snap(t)
    box = None
    if region is not None:
        x0, y0, x1, y1 = (int(v) for v in region)
        box = (max(0, x0), max(0, y0), min(w, x1), min(h, y1))
        if box[2] <= box[0] or box[3] <= box[1]:
            return snap(t)
    bw, bh = (box[2] - box[0], box[3] - box[1]) if box else (w, h)
    acc = Accumulator(bw, bh, linear)
    for ti in subframe_times(t, samples, shutter):
        acc.add(snap(ti, box))
    blurred = acc.result(seed, int(np.floor(t)))
    if box is None:
        return blurred
    out = snap(t)
    out[box[1]:box[3], box[0]:box[2]] = blurred
    return out


@dataclass(frozen=True)
class WhipPan:
    """A whip: `distance` px (or points — any unit the caller maps) covered
    over `frames` frames from `start`, on `curve`."""

    start: float
    distance: float
    frames: float = 6.0
    curve: easing.Curve = easing.EASE_IN_OUT_CUBIC

    def offset(self, t: float) -> float:
        """0 before the whip, `distance` after, eased between (any subframe)."""
        return self.distance * self.curve(easing.progress(t, self.start, self.frames))

    def speed(self, t: float, h: float = 1e-3) -> float:
        """|d offset / d frame| at t (units per frame)."""
        return abs(self.offset(t + h) - self.offset(t - h)) / (2 * h)

    def peak_frame(self) -> float:
        """The frame of the fastest motion — where the whoosh peaks."""
        ts = np.linspace(self.start, self.start + self.frames, 241)
        return float(ts[int(np.argmax([self.speed(x) for x in ts]))])

    def samples(self, t: float, px_per_unit: float = 1.0, shutter: float = 1.0, max_gap: float = 2.0) -> int:
        """Subframes for frame t: enough for the fastest instant inside its
        shutter interval."""
        ts = subframe_times(t, 9, shutter)
        fastest = max(self.speed(x) for x in ts) * px_per_unit
        return samples_for(fastest, shutter, max_gap)

    def draw_transition(self, canvas: skia.Canvas, t: float, draw_out: Callable[[skia.Canvas], None],
                        draw_in: Callable[[skia.Canvas], None], axis: str = "x") -> None:
        """Scene-to-scene whip: the outgoing scene leaves by `distance` while
        the incoming one arrives from `distance` away — one strip of film.
        Positive distance moves content toward −axis (a pan to the right /
        down). Wrap in `accumulate` for the blur."""
        if axis not in ("x", "y"):
            raise ValueError(f"axis is 'x' or 'y', not {axis!r}")
        d = self.offset(t)
        parts = []
        if d != self.distance:
            parts.append((draw_out, -d))                  # still on screen
        if d != 0:
            parts.append((draw_in, self.distance - d))    # already arriving
        for draw, shift in parts:
            canvas.save()
            if axis == "x":
                canvas.translate(shift, 0)
            else:
                canvas.translate(0, shift)
            draw(canvas)
            canvas.restore()
