"""The brand pattern: the mark, repeated on a brick grid, tone on tone.

Brand book (Identity p.13 / Brandbook p.22), as the storyboard quotes it:
the mark ≈ 66 px tall on a brick grid of ≈ 110-px pitch — every other row
shifted half a column — in #EDEEEF on paper (#FAFAFA) for the app scenes,
#1E1E1E on black for the hook and the air beats. Each mark is the mark
itself (brand.mark_path: the SVG's polyline, its own stroke weight, round
cap and join), not an icon font or a bitmap: every mark is a vector, drawn
anti-aliased at its sub-pixel place, so the pattern drifts smoothly
(4 px/s in the air beats; parallax 0.4× the phone's drift in bar 11).

The pattern never touches the logo (storyboard): `clear` is a rectangle no
mark may enter; marks near it fade WHOLE with their distance to it over
`feather` px — never cut in half (« Le trait » learnt that a pixel feather
leaves « [ » half-marks along the zone's edge).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import skia

from .brand import PALETTE, mark_paint, mark_path
from .surface import Rect, skrect


@dataclass(frozen=True)
class PatternSpec:
    mark_height: float = 66.0
    pitch_x: float = 110.0
    pitch_y: float = 110.0
    stagger: float = 0.5                  # odd rows shift by this fraction of pitch_x


SPEC = PatternSpec()


def pattern_colour(dark: bool) -> int:
    return PALETTE.PATTERN_ON_BLACK if dark else PALETTE.PATTERN_ON_PAPER


def mark_centres(rect: Rect, offset: tuple[float, float] = (0.0, 0.0), spec: PatternSpec = SPEC,
                 origin: tuple[float, float] = (540.0, 960.0)) -> list[tuple[float, float]]:
    """Centres of every mark touching `rect` for a grid anchored on `origin`
    (a mark sits there at offset 0) and moved by `offset` (the drift)."""
    x0, y0, x1, y1 = rect
    ox, oy = origin[0] + offset[0], origin[1] + offset[1]
    reach = spec.mark_height                    # a mark straddling the edge still counts
    r0 = math.floor((y0 - reach - oy) / spec.pitch_y)
    r1 = math.ceil((y1 + reach - oy) / spec.pitch_y)
    out = []
    for r in range(r0, r1 + 1):
        shift = spec.stagger * spec.pitch_x if r % 2 else 0.0
        cy = oy + r * spec.pitch_y
        c0 = math.floor((x0 - reach - ox - shift) / spec.pitch_x)
        c1 = math.ceil((x1 + reach - ox - shift) / spec.pitch_x)
        for c in range(c0, c1 + 1):
            out.append((ox + shift + c * spec.pitch_x, cy))
    return out


def _clear_weight(cx: float, cy: float, box: tuple[float, float, float, float], clear: Rect, feather: float) -> float:
    """1 for a mark `feather` px or more from the clear zone, 0 touching it."""
    bx0, by0, bx1, by1 = cx + box[0], cy + box[1], cx + box[2], cy + box[3]
    gx = max(clear[0] - bx1, bx0 - clear[2], 0.0)
    gy = max(clear[1] - by1, by0 - clear[3], 0.0)
    d = math.hypot(gx, gy)
    if feather <= 0:
        return 1.0 if d > 0 else 0.0
    return min(1.0, d / feather)


def draw_pattern(canvas: skia.Canvas, rect: Rect, *, dark: bool, alpha: float = 1.0,
                 offset: tuple[float, float] = (0.0, 0.0), spec: PatternSpec = SPEC,
                 origin: tuple[float, float] = (540.0, 960.0), clear: Rect | None = None,
                 feather: float = 80.0, colour: int | None = None) -> None:
    """Draw the pattern over `rect` (clipped to it) — dark (on black) or light
    (on paper) — moved by `offset` px, at `alpha`."""
    if alpha <= 0:
        return
    unit, stroke = mark_path(spec.mark_height)
    b = unit.computeTightBounds()
    half = stroke / 2
    box = (b.left() - half, b.top() - half, b.right() + half, b.bottom() + half)
    paint = mark_paint(colour if colour is not None else pattern_colour(dark), stroke)
    canvas.save()
    canvas.clipRect(skrect(rect), True)
    whole = skia.Path()
    for cx, cy in mark_centres(rect, offset, spec, origin):
        w = 1.0 if clear is None else _clear_weight(cx, cy, box, clear, feather)
        if w <= 0:
            continue
        if w >= 1:
            whole.addPath(unit, cx, cy)
        else:
            p = skia.Paint(paint)
            p.setAlphaf(p.getAlphaf() * w * alpha)
            one = skia.Path()
            one.addPath(unit, cx, cy)
            canvas.drawPath(one, p)
    if alpha < 1:
        paint.setAlphaf(paint.getAlphaf() * alpha)
    canvas.drawPath(whole, paint)
    canvas.restore()
