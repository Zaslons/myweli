"""Keyframed values: the camera's W, zoom, tilts, a fall, a parallax.

A key ``{at, value, curve}`` is REACHED at ``at``: between two keys the value
moves from the first to the second on the second key's curve (the app's
curves, promo/fx/easing.py). Before the first key the first value holds,
after the last the last. A key may carry ``blur`` — the move INTO it is
motion-blurred: a number of subframes, or ``whip`` (enough subframes that
copies sit ≤ 2 px apart, the whip's rule in promo/fx/blur.py) — and extra
fields (a zoom's anchor).
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Callable, Sequence

from ..fx import easing

CURVES: dict[str, Callable[[float], float]] = {
    "linear": easing.linear,
    "ease_in": easing.EASE_IN,
    "ease_out": easing.EASE_OUT,
    "ease_in_out": easing.EASE_IN_OUT,
    "ease_out_cubic": easing.EASE_OUT_CUBIC,
    "ease_in_out_cubic": easing.EASE_IN_OUT_CUBIC,
    "ease_in_cubic": easing.EASE_IN_CUBIC,
    "fast_out_slow_in": easing.FAST_OUT_SLOW_IN,
}


def curve(name: str | None) -> Callable[[float], float]:
    if name is None:
        return easing.linear
    try:
        return CURVES[name]
    except KeyError:
        raise ValueError(f"unknown curve {name!r} (have: {', '.join(CURVES)})") from None


@dataclass(frozen=True)
class Key:
    frame: float
    value: float
    curve: Callable[[float], float] = easing.linear
    blur: Any = None
    extra: dict = field(default_factory=dict)


class Track:
    """A value over film time, from its keys (sorted by frame)."""

    def __init__(self, keys: Sequence[Key], default: float = 0.0):
        self.keys = sorted(keys, key=lambda k: k.frame)
        self.default = default
        for a, b in zip(self.keys, self.keys[1:]):
            if a.frame == b.frame and a.value != b.value:
                raise ValueError(f"two keys on frame {a.frame} with different values ({a.value}, {b.value})")

    def __bool__(self) -> bool:
        return bool(self.keys)

    def _bracket(self, t: float) -> tuple[Key | None, Key | None]:
        prev = None
        for k in self.keys:
            if k.frame > t:
                return prev, k
            prev = k
        return prev, None

    def __call__(self, t: float) -> float:
        if not self.keys:
            return self.default
        a, b = self._bracket(t)
        if a is None:
            return b.value
        if b is None:
            return a.value
        span = b.frame - a.frame
        u = (t - a.frame) / span if span > 0 else 1.0
        return a.value + (b.value - a.value) * b.curve(min(1.0, max(0.0, u)))

    def key_into(self, t: float) -> Key | None:
        """The key being moved toward at t (None outside any move)."""
        a, b = self._bracket(t)
        if a is None or b is None or a.value == b.value:
            return None
        return b

    def move(self, t: float) -> tuple[Key, Key] | None:
        a, b = self._bracket(t)
        if a is None or b is None or a.value == b.value:
            return None
        return a, b

    def speed(self, t: float, h: float = 1e-2) -> float:
        """|d value / d frame| at t."""
        return abs(self(t + h) - self(t - h)) / (2 * h)

    def extra_at(self, t: float, name: str, default: Any = None) -> Any:
        """A key field in force at t: the key being moved toward, else the
        last key reached."""
        a, b = self._bracket(t)
        for k in (b, a) if (a is not None and b is not None and a.value != b.value) else (a, b):
            if k is not None and name in k.extra:
                return k.extra[name]
        return default
