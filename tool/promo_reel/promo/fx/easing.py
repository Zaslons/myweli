"""Easing curves — the app's, evaluated precisely — and frame-time helpers.

The control points come from tool/app_store_preview/brand.py `CUBICS`
(Flutter's own, flutter/lib/src/animation/curves.dart); the two curves that
table does not carry are added here with the same citation:

  easeIn          (0.42, 0, 1, 1)          Curves.easeIn
  easeOut         (0, 0, 0.58, 1)          Curves.easeOut
  easeInOut       (0.42, 0, 0.58, 1)       Curves.easeInOut
  easeOutCubic    (0.215, 0.61, 0.355, 1)  Curves.easeOutCubic   — AppMotion.emphasis
  easeInOutCubic  (0.645, 0.045, 0.355, 1) Curves.easeInOutCubic — AppMotion.slow
  easeInCubic     (0.55, 0.055, 0.675, 0.19) Curves.easeInCubic
  fastOutSlowIn   (0.4, 0, 0.2, 1)         Curves.fastOutSlowIn  — the counter, the slam

Flutter solves a cubic by bisection until x is within 0.001 of t
(`Cubic._cubicErrorBound`); a film needs more: at 30 fps with 8 motion-blur
subframes, a 0.001 error in x is visible as a sub-pixel jitter on a 700-px
move. `Cubic` solves to 1e-9 with Newton steps guarded by bisection — the
same curve, evaluated exactly (tests/test_fx.py checks it against the
preview's Flutter-faithful `cubic()`). Every curve maps 0 → 0 and 1 → 1
EXACTLY, so a value animated with it lands exactly on its target.

Frame helpers take frames as floats, so a motion-blur subframe (frame 12.375)
is just another time: `progress(t, start, frames)` is the linear 0..1 of an
animation that starts at `start` and lasts `frames`.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Sequence

Curve = Callable[[float], float]


def clamp01(x: float) -> float:
    return 0.0 if x <= 0.0 else 1.0 if x >= 1.0 else x


def lerp(a: float, b: float, t: float) -> float:
    """a at t = 0, b at t = 1 — exactly b at 1 (no a + (b − a)·t rounding)."""
    return a * (1.0 - t) + b * t if t != 1.0 else b


class Cubic:
    """A unit cubic Bézier from (0, 0) to (1, 1) with control points
    (a, b) and (c, d) — Flutter's `Cubic(a, b, c, d)`."""

    __slots__ = ("a", "b", "c", "d", "name")

    def __init__(self, a: float, b: float, c: float, d: float, name: str = ""):
        if not (0.0 <= a <= 1.0 and 0.0 <= c <= 1.0):
            raise ValueError("a cubic easing's x control points must lie in [0, 1]")
        self.a, self.b, self.c, self.d, self.name = a, b, c, d, name

    @staticmethod
    def _bez(p1: float, p2: float, s: float) -> float:
        return 3 * p1 * (1 - s) * (1 - s) * s + 3 * p2 * (1 - s) * s * s + s * s * s

    @staticmethod
    def _dbez(p1: float, p2: float, s: float) -> float:
        return 3 * p1 * (1 - s) * (1 - s) + 6 * (p2 - p1) * (1 - s) * s + 3 * (1 - p2) * s * s

    def parameter(self, t: float) -> float:
        """The curve parameter s whose x is t (x is monotone for x controls in
        [0, 1]): Newton from s = t, kept inside a shrinking bisection bracket."""
        lo, hi, s = 0.0, 1.0, t
        for _ in range(64):
            x = self._bez(self.a, self.c, s) - t
            if abs(x) < 1e-9:
                return s
            if x > 0:
                hi = s
            else:
                lo = s
            dx = self._dbez(self.a, self.c, s)
            s_next = s - x / dx if dx > 1e-12 else (lo + hi) / 2
            s = s_next if lo < s_next < hi else (lo + hi) / 2
        return s

    def __call__(self, t: float) -> float:
        if t <= 0.0:
            return 0.0
        if t >= 1.0:
            return 1.0
        return self._bez(self.b, self.d, self.parameter(t))

    transform = __call__

    def __repr__(self) -> str:
        return f"Cubic({self.a}, {self.b}, {self.c}, {self.d}{', ' + repr(self.name) if self.name else ''})"


def linear(t: float) -> float:
    return clamp01(t)


def _preview_cubics() -> dict[str, tuple[float, float, float, float]]:
    from . import brand
    return dict(brand.preview_brand().CUBICS)


_P = _preview_cubics()
EASE_IN = Cubic(*_P["easeIn"], name="easeIn")
EASE_OUT = Cubic(*_P["easeOut"], name="easeOut")
EASE_IN_OUT = Cubic(*_P["easeInOut"], name="easeInOut")
EASE_OUT_CUBIC = Cubic(*_P["easeOutCubic"], name="easeOutCubic")
EASE_IN_OUT_CUBIC = Cubic(*_P["easeInOutCubic"], name="easeInOutCubic")
# Not in the preview's table (no motion token names them); Flutter's values.
EASE_IN_CUBIC = Cubic(0.55, 0.055, 0.675, 0.19, name="easeInCubic")
FAST_OUT_SLOW_IN = Cubic(0.4, 0.0, 0.2, 1.0, name="fastOutSlowIn")

CURVES: dict[str, Curve] = {
    "linear": linear,
    "easeIn": EASE_IN,
    "easeOut": EASE_OUT,
    "easeInOut": EASE_IN_OUT,
    "easeOutCubic": EASE_OUT_CUBIC,
    "easeInOutCubic": EASE_IN_OUT_CUBIC,
    "easeInCubic": EASE_IN_CUBIC,
    "fastOutSlowIn": FAST_OUT_SLOW_IN,
}


def curve(name: str) -> Curve:
    """A curve by its Flutter name (`easeOutCubic`, `fastOutSlowIn`, …)."""
    try:
        return CURVES[name]
    except KeyError:
        raise KeyError(f"unknown curve `{name}` (have: {', '.join(sorted(CURVES))})") from None


def flipped(c: Curve) -> Curve:
    """Flutter's `curve.flipped`: 1 − c(1 − t). easeOut ⇄ easeIn."""
    return lambda t: 1.0 - c(1.0 - clamp01(t))


# ---- frame time -------------------------------------------------------------------

def progress(t: float, start: float, frames: float) -> float:
    """Linear progress 0..1 of an animation starting at frame `start` and
    lasting `frames` frames, at (possibly fractional) frame `t`."""
    if frames <= 0:
        return 1.0 if t >= start else 0.0
    return clamp01((t - start) / frames)


def ease(t: float, start: float, frames: float, c: Curve = EASE_OUT_CUBIC) -> float:
    """`c` applied to `progress(t, start, frames)`."""
    return c(progress(t, start, frames))


def tween(t: float, start: float, frames: float, a: float, b: float, c: Curve = EASE_OUT_CUBIC) -> float:
    """a before `start`, b from `start + frames` on, eased between."""
    return lerp(a, b, ease(t, start, frames, c))


def motion(name: str) -> tuple[int, Curve]:
    """An AppMotion token at 30 fps: (frames, curve). fast = (3, easeOut),
    base = (6, easeInOut), emphasis = (9, easeOutCubic), slow = (12,
    easeInOutCubic) — read from motion.dart."""
    from . import brand
    tok = brand.motion_tokens()[name]
    return tok.frames, curve(tok.curve)


@dataclass(frozen=True)
class Key:
    """A keyframe: `value` at frame `frame`, reached on `curve` from the key
    before."""

    frame: float
    value: float
    curve: Curve = linear


class Keyframes:
    """A piecewise-eased property: holds the first value before the first key
    and the last after the last, and lands EXACTLY on every key's value at its
    frame. E.g. the drop's phone scale:
    Keyframes([Key(128, 1.10), Key(136, 1.00, FAST_OUT_SLOW_IN)])."""

    def __init__(self, keys: Sequence[Key]):
        if not keys:
            raise ValueError("Keyframes needs at least one key")
        frames = [k.frame for k in keys]
        if any(b <= a for a, b in zip(frames, frames[1:])):
            raise ValueError(f"keyframes must be strictly increasing in frame: {frames}")
        self.keys = list(keys)

    def __call__(self, t: float) -> float:
        ks = self.keys
        if t <= ks[0].frame:
            return ks[0].value
        for a, b in zip(ks, ks[1:]):
            if t < b.frame:
                return lerp(a.value, b.value, b.curve(progress(t, a.frame, b.frame - a.frame)))
        return ks[-1].value

    value_at = __call__


def smoothstep(e0: float, e1: float, x: float) -> float:
    """Hermite 0..1 between e0 and e1 (for spatial feathers, not motion)."""
    if e1 == e0:
        return 1.0 if x >= e1 else 0.0
    t = clamp01((x - e0) / (e1 - e0))
    return t * t * (3 - 2 * t)
