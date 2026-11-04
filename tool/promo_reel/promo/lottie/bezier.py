"""Keyframe easing: the cubic Bézier timing curve of a Lottie keyframe.

A keyframe eases from its value to the next one along the curve through
(0, 0), its out-handle ``o`` = (x1, y1), the next keyframe's in-handle
``i`` = (x2, y2), and (1, 1) — CSS ``cubic-bezier(x1, y1, x2, y2)``.

lottie-flutter samples this curve into a lookup table every 0.002 of arc
length (``PathInterpolator``); here x(u) = t is solved to 1e-12, so the value
is the curve's own — for the file's (0.4, 0, 0.2, 1) at most 3e-6 away from
the device's table (measured by re-building that table, 768 points).
"""

from __future__ import annotations

from dataclasses import dataclass

_NEWTON_STEPS = 8
_BISECT_STEPS = 60
_EPSILON = 1e-12


@dataclass(frozen=True)
class CubicBezier:
    """y = f(t) for t in [0, 1] along cubic-bezier(x1, y1, x2, y2).

    x1 and x2 must lie in [0, 1]: then x(u) is monotonic and f is a function.
    """

    x1: float
    y1: float
    x2: float
    y2: float

    def __post_init__(self) -> None:
        if not (0.0 <= self.x1 <= 1.0 and 0.0 <= self.x2 <= 1.0):
            raise ValueError(
                f'easing handles x must lie in [0, 1], got x1={self.x1}, x2={self.x2}'
            )

    @staticmethod
    def _axis(u: float, p1: float, p2: float) -> float:
        # B(u) with P0 = 0 and P3 = 1, in Horner form.
        c = 3.0 * p1
        b = 3.0 * (p2 - p1) - c
        a = 1.0 - c - b
        return ((a * u + b) * u + c) * u

    @staticmethod
    def _slope(u: float, p1: float, p2: float) -> float:
        c = 3.0 * p1
        b = 3.0 * (p2 - p1) - c
        a = 1.0 - c - b
        return (3.0 * a * u + 2.0 * b) * u + c

    def _solve_u(self, t: float) -> float:
        """The curve parameter u at which x(u) = t."""
        u = t
        for _ in range(_NEWTON_STEPS):
            err = self._axis(u, self.x1, self.x2) - t
            if abs(err) < _EPSILON:
                return u
            slope = self._slope(u, self.x1, self.x2)
            if abs(slope) < 1e-9:
                break
            u -= err / slope
            if not 0.0 <= u <= 1.0:
                break
        lo, hi = 0.0, 1.0
        u = t
        for _ in range(_BISECT_STEPS):
            x = self._axis(u, self.x1, self.x2)
            if abs(x - t) < _EPSILON:
                return u
            if x < t:
                lo = u
            else:
                hi = u
            u = 0.5 * (lo + hi)
        return u

    def __call__(self, t: float) -> float:
        if t <= 0.0:
            return 0.0
        if t >= 1.0:
            return 1.0
        return self._axis(self._solve_u(t), self.y1, self.y2)
