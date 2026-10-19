"""Scale punches: the small, fast size accents that land visuals on beats.

Two shapes, both returning a scale factor (1.0 = at rest):

  punch   out and back: 1 → peak over `out` frames, peak → 1 over `back`
          (the hook's page on each strike: 1.00 → 1.025, 3 frames out, 5
          back). Out decelerates (easeOutCubic), back eases in and out.
  settle  arrives big and settles: `start` on the cue frame → 1 over
          `frames` (the counter landing: 1.08 → 1.00 over 5 frames,
          easeOutCubic).

`Punches` multiplies several envelopes (overlapping strikes compound,
they never reset each other). `surface.scaled_about(canvas, s, cx, cy)`
applies a factor about a point.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

from . import easing


def punch(t: float, at: float, peak: float = 1.025, out: float = 3.0, back: float = 5.0,
          out_curve: easing.Curve = easing.EASE_OUT_CUBIC,
          back_curve: easing.Curve = easing.EASE_IN_OUT) -> float:
    """1 before `at`; `peak` exactly at `at + out`; 1 again from `at + out + back`."""
    if t <= at or t >= at + out + back:
        return 1.0
    if t <= at + out:
        return easing.lerp(1.0, peak, out_curve(easing.progress(t, at, out)))
    return easing.lerp(peak, 1.0, back_curve(easing.progress(t, at + out, back)))


def settle(t: float, at: float, start: float = 1.08, frames: float = 5.0,
           c: easing.Curve = easing.EASE_OUT_CUBIC, before: float = 1.0) -> float:
    """`before` until `at`; `start` on frame `at`; 1 from `at + frames`."""
    if t < at:
        return before
    return easing.lerp(start, 1.0, c(easing.progress(t, at, frames)))


@dataclass(frozen=True)
class Punch:
    at: float
    peak: float = 1.025
    out: float = 3.0
    back: float = 5.0

    def __call__(self, t: float) -> float:
        return punch(t, self.at, self.peak, self.out, self.back)


class Punches:
    """The product of several punch envelopes."""

    def __init__(self, envelopes: Sequence):
        self.envelopes = list(envelopes)

    def __call__(self, t: float) -> float:
        s = 1.0
        for e in self.envelopes:
            s *= e(t)
        return s
