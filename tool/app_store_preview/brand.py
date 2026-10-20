"""What the film takes from the design system, read from where it lives.

  colours   mobile/lib/core/theme/colors.dart, through the stills' `tokens()`
  motion    mobile/lib/core/theme/motion.dart — durations and their curves
  frame     tool/app_store_screenshots/compose.py — fonts, mark, mask, shadow
            and the layout table `L`

Nothing here is retyped from those files. The one table that is typed in is
`CUBICS`: Flutter's own control points for the curves `motion.dart` may name
(flutter/lib/src/animation/curves.dart), plus `fastOutSlowIn` — the curve
every keyframe of the brand's Lottie files uses, (0.4, 0, 0.2, 1), which the
marketing film (tool/marketing_video) draws its strokes on;
tests/test_brand.py checks the table against the Flutter SDK when there is
one on the machine.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
MOTION_DART = ROOT / "mobile/lib/core/theme/motion.dart"
STILLS_PY = ROOT / "tool/app_store_screenshots/compose.py"


def die(msg: str) -> None:
    print(f"preview: {msg}", file=sys.stderr)
    sys.exit(1)


def _load_stills():
    """The stills' composer, imported under another name than `compose` so the
    two tools cannot shadow each other."""
    spec = importlib.util.spec_from_file_location("app_store_stills", STILLS_PY)
    module = importlib.util.module_from_spec(spec)
    sys.modules["app_store_stills"] = module
    spec.loader.exec_module(module)
    return module


stills = _load_stills()

# The stills' five, plus the two the touch point is drawn in: `primary` (the
# brand black, on light surfaces) and `secondary` (white, on dark or green
# fills).
COLOUR_TOKENS = stills.TOKENS + ("primary", "secondary")


def colours() -> dict[str, tuple[int, int, int]]:
    return stills.tokens(COLOUR_TOKENS)


# ---- motion ----------------------------------------------------------------

# flutter/lib/src/animation/curves.dart — `static const Cubic <name> = Cubic(…)`
CUBICS = {
    "easeIn": (0.42, 0.0, 1.0, 1.0),
    "easeOut": (0.0, 0.0, 0.58, 1.0),
    "easeInOut": (0.42, 0.0, 0.58, 1.0),
    "easeOutCubic": (0.215, 0.61, 0.355, 1.0),
    "easeInOutCubic": (0.645, 0.045, 0.355, 1.0),
    # Not a motion.dart curve: the Lottie files' easing (mobile/assets/lottie),
    # used by tool/marketing_video for every stroke it draws.
    "fastOutSlowIn": (0.4, 0.0, 0.2, 1.0),
}

_CUBIC_ERROR_BOUND = 0.001  # Flutter's own (`_cubicErrorBound`)


def cubic(points: tuple[float, float, float, float], t: float) -> float:
    """Flutter's `Cubic.transformInternal`, step for step: a bisection on the
    curve parameter until x is within 0.001 of t."""
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return 1.0
    a, b, c, d = points

    def bez(p1: float, p2: float, m: float) -> float:
        return 3 * p1 * (1 - m) * (1 - m) * m + 3 * p2 * (1 - m) * m * m + m * m * m

    start, end = 0.0, 1.0
    while True:
        mid = (start + end) / 2
        estimate = bez(a, c, mid)
        if abs(t - estimate) < _CUBIC_ERROR_BOUND:
            return bez(b, d, mid)
        if estimate < t:
            start = mid
        else:
            end = mid


class Motion:
    """One motion token: its duration and the curve motion.dart pairs it with."""

    def __init__(self, name: str, ms: int, curve: str):
        self.name, self.ms, self.curve = name, ms, curve

    @property
    def seconds(self) -> float:
        return self.ms / 1000

    def frames(self, fps: int) -> int:
        n = self.ms * fps
        if n % 1000:
            die(f"motion token `{self.name}` ({self.ms} ms) is not a whole number of frames at {fps} fps")
        return n // 1000

    def at(self, elapsed_s: float) -> float:
        """Progress 0..1 after `elapsed_s` seconds, on the token's curve."""
        return cubic(CUBICS[self.curve], elapsed_s / self.seconds)


def motion_tokens() -> dict[str, Motion]:
    """Every `Duration`/`Curve` pair of AppMotion, by name. `stagger` has no
    curve (it is an offset, not a movement) and is left out."""
    src = MOTION_DART.read_text(encoding="utf-8")
    durations = dict(re.findall(r"static const Duration (\w+) = Duration\(milliseconds: (\d+)\);", src))
    curves = dict(re.findall(r"static const Curve (\w+)Curve = Curves\.(\w+);", src))
    if not curves:
        die(f"no motion tokens found in {MOTION_DART}")
    out = {}
    for name, curve in curves.items():
        if name not in durations:
            die(f"motion token `{name}` has a curve but no duration in {MOTION_DART}")
        if curve not in CUBICS:
            die(f"motion token `{name}` uses Curves.{curve}, which brand.py does not know")
        out[name] = Motion(name, int(durations[name]), curve)
    return out


def motion(name: str) -> Motion:
    tokens = motion_tokens()
    if name not in tokens:
        die(f"`{name}` is not a motion token of motion.dart (have: {', '.join(sorted(tokens))})")
    return tokens[name]
