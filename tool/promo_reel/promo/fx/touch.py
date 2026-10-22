"""The touch point and its ripple — the App Store film's style, unchanged.

The disc (tool/app_store_preview/storyboard.json « touch », drawn by
frames.py `draw_touch`, :212-219): 48 pt across, filled at 12 %, with a
1.5-pt ring at 45 %. Black on a light ground, white on a dark or green one:
the tone goes by the median luminance under the finger (the middle of the
disc, half its width), against 0.35 (`light_below_luminance`) — the median,
not the mean, because a white glyph on the dark-green « Arrivé » pane pulled
the mean over the line on two thirds of the pane (frames.py `ground()`).

Timing (storyboard): the disc fades in over 3 frames (AppMotion.fast) on the
touch-down and out over 6 (base) after the lift. The tap ripple is a ring
growing 48 → 96 pt over 10 frames on easeOutCubic while it fades out.

Sizes are in POINTS times `scale` (canvas units per point): draw in the
phone's overlay (screen points, scale 1) and the disc rides the phone's
perspective and clip; or in frame px with scale = 1.791.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np
import skia

from . import easing
from .brand import PALETTE


@dataclass(frozen=True)
class TouchStyle:
    diameter_pt: float = 48.0
    ring_pt: float = 1.5
    fill_opacity: float = 0.12
    ring_opacity: float = 0.45
    ripple_to_pt: float = 96.0
    ripple_frames: float = 10.0
    fade_in_frames: float = 3.0                 # AppMotion.fast at 30 fps
    fade_out_frames: float = 6.0                # AppMotion.base
    light_below_luminance: float = 0.35


STYLE = TouchStyle()


def tone_colour(tone: str) -> int:
    """'dark' → the brand black (on light ground); 'light' → white."""
    if tone not in ("dark", "light"):
        raise ValueError(f"tone is 'dark' or 'light', not {tone!r}")
    return PALETTE.BLACK if tone == "dark" else PALETTE.WHITE


def ground_luminance(rgb: np.ndarray, x: float, y: float, diameter: float) -> float | None:
    """The median luminance (0 black … 1 white, Rec. 709 weights on the
    encoded values, as frames.py) of the square half the disc's width centred
    on (x, y) in `rgb` (h, w, 3|4 uint8). None when it is off the picture."""
    half = diameter / 4
    h, w = rgb.shape[:2]
    x0, y0 = max(0, round(x - half)), max(0, round(y - half))
    x1, y1 = min(w, round(x + half)), min(h, round(y + half))
    if x1 <= x0 or y1 <= y0:
        return None
    patch = rgb[y0:y1, x0:x1, :3].astype(np.float32) / 255
    return float(np.median(patch @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)))


def tone_at(rgb: np.ndarray, x: float, y: float, diameter: float, style: TouchStyle = STYLE) -> str:
    """'light' (white disc) where the touch lands on a dark or green fill,
    else 'dark'. Coordinates and diameter in the picture's own pixels."""
    lum = ground_luminance(rgb, x, y, diameter)
    if lum is None:
        return "dark"
    return "light" if lum < style.light_below_luminance else "dark"


def touch_alpha(t: float, down: float, up: float | None = None, style: TouchStyle = STYLE) -> float:
    """The disc's opacity at frame t for a touch down on frame `down` and
    lifted on `up` (None: still down): in over 3 frames, out over 6, both on
    easeOut. The touch-down frame itself already shows the first step."""
    a = easing.EASE_OUT(easing.progress(t, down - 1, style.fade_in_frames))
    if up is not None:
        a *= 1.0 - easing.EASE_OUT(easing.progress(t, up, style.fade_out_frames))
    return a


def draw_touch(canvas: skia.Canvas, x: float, y: float, *, tone: str = "dark", alpha: float = 1.0,
               scale: float = 1.0, style: TouchStyle = STYLE) -> None:
    """The disc at (x, y): a soft fill and a thin ring, anti-aliased at
    sub-pixel positions (a drag glides)."""
    if alpha <= 0:
        return
    colour = tone_colour(tone)
    r = style.diameter_pt / 2 * scale
    fill = skia.Paint(AntiAlias=True, Color=colour)
    fill.setAlphaf(style.fill_opacity * alpha)
    canvas.drawCircle(x, y, r, fill)
    ring_w = style.ring_pt * scale
    ring = skia.Paint(AntiAlias=True, Color=colour, Style=skia.Paint.kStroke_Style, StrokeWidth=ring_w)
    ring.setAlphaf(style.ring_opacity * alpha)
    canvas.drawCircle(x, y, r - ring_w / 2, ring)


def ripple_state(t: float, down: float, style: TouchStyle = STYLE) -> tuple[float, float] | None:
    """(diameter_pt, alpha) of the tap ripple at frame t, or None when it is
    not showing. The ring starts at the disc's 48 pt on the touch-down frame
    and reaches 96 pt as it vanishes 10 frames later."""
    q = easing.progress(t, down, style.ripple_frames)
    if t < down or q >= 1.0:
        return None
    d = easing.lerp(style.diameter_pt, style.ripple_to_pt, easing.EASE_OUT_CUBIC(q))
    return d, 1.0 - easing.EASE_OUT(q)


def draw_ripple(canvas: skia.Canvas, x: float, y: float, t: float, down: float, *, tone: str = "dark",
                scale: float = 1.0, style: TouchStyle = STYLE, alpha: float = 1.0) -> None:
    """The tap ripple at frame t for a touch-down on frame `down`."""
    st = ripple_state(t, down, style)
    if st is None or alpha <= 0:
        return
    d, a = st
    ring_w = style.ring_pt * scale
    ring = skia.Paint(AntiAlias=True, Color=tone_colour(tone), Style=skia.Paint.kStroke_Style, StrokeWidth=ring_w)
    ring.setAlphaf(style.ring_opacity * a * alpha)
    canvas.drawCircle(x, y, d / 2 * scale - ring_w / 2, ring)


def draw_tap(canvas: skia.Canvas, x: float, y: float, t: float, down: float, up: float | None = None, *,
             tone: str = "dark", scale: float = 1.0, style: TouchStyle = STYLE) -> None:
    """A tap: the disc (in on `down`, out after `up`) plus its ripple."""
    draw_ripple(canvas, x, y, t, down, tone=tone, scale=scale, style=style)
    draw_touch(canvas, x, y, tone=tone, alpha=touch_alpha(t, down, up, style), scale=scale, style=style)
