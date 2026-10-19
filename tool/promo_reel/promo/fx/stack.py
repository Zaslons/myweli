"""Stacked lifts: several real tiles lifted one by one into a column (or a
row), one per beat — the Fiche's « 2 » Visites, « 17 000 FCFA » Dépensé,
« 13 oct. 2026 » Dernière (storyboard bar 8: x 330–690, 360 px wide, 16-px
gaps, a 6-frame z-pop each on easeOutCubic).

Each tile is a `lift.Lift` (same pixels, same card, same shadow); the veil
rises with the first tile and stays while any tile is up. Later tiles draw
over earlier ones.
"""

from __future__ import annotations

from typing import Sequence

import skia

from .lift import STYLE, Lift, LiftStyle, draw_veil, pop_progress
from .surface import Picture, Rect


def stack_rects(sources: Sequence[Rect], *, x0: float = 330.0, width: float = 360.0, gap: float = 16.0,
                top: float | None = None, centre_y: float | None = None, axis: str = "vertical",
                y0: float | None = None, height: float | None = None) -> list[Rect]:
    """Targets for `sources` (their aspect ratios kept).

    vertical: every tile `width` wide from x0, stacked with `gap`, the stack
    placed by its `top` or `centre_y`.
    horizontal: every tile `height` tall from y0, side by side from x0."""
    out: list[Rect] = []
    if axis == "vertical":
        hs = [width * (s[3] - s[1]) / (s[2] - s[0]) for s in sources]
        total = sum(hs) + gap * (len(hs) - 1)
        if top is None:
            if centre_y is None:
                raise ValueError("stack_rects: give top or centre_y")
            top = centre_y - total / 2
        y = top
        for h in hs:
            out.append((x0, y, x0 + width, y + h))
            y += h + gap
    elif axis == "horizontal":
        if y0 is None or height is None:
            raise ValueError("stack_rects: a horizontal stack needs y0 and height")
        x = x0
        for s in sources:
            w = height * (s[2] - s[0]) / (s[3] - s[1])
            out.append((x, y0, x + w, y0 + height))
            x += w + gap
    else:
        raise ValueError(f"axis is 'vertical' or 'horizontal', not {axis!r}")
    return out


class Stack:
    """Tiles `sources` (capture px) of one picture, lifted from `origins`
    (on the phone) to `targets`, the i-th popping up on frame `ups[i]`."""

    def __init__(self, picture, sources: Sequence[Rect], origins: Sequence[Rect], targets: Sequence[Rect],
                 ups: Sequence[float], *, frames: float = 6.0, down: float | None = None,
                 down_frames: float = 5.0, style: LiftStyle = STYLE):
        if not (len(sources) == len(origins) == len(targets) == len(ups)):
            raise ValueError("Stack: sources, origins, targets and ups must have the same length")
        pic = picture if isinstance(picture, Picture) else Picture(picture)
        self.lifts = [Lift(pic, s, o, t, style) for s, o, t in zip(sources, origins, targets)]
        self.ups, self.frames, self.down, self.down_frames, self.style = list(ups), frames, down, down_frames, style

    def progress(self, i: int, t: float) -> float:
        return pop_progress(t, self.ups[i], self.frames, self.down, self.down_frames)

    def backdrop_rect(self, pad: float) -> Rect:
        """The union of the tiles' targets AND their places on the phone,
        grown by `pad` on every side: under it no veiled original shows,
        between the lifted tiles or beside them."""
        ts = [lf.target for lf in self.lifts] + [lf.origin for lf in self.lifts]
        return (min(r[0] for r in ts) - pad, min(r[1] for r in ts) - pad,
                max(r[2] for r in ts) + pad, max(r[3] for r in ts) + pad)

    def draw(self, canvas: skia.Canvas, t: float, *, veil_rect: Rect | None = None,
             backdrop: tuple[int, float, float] | None = None) -> None:
        """The veil, then (`backdrop` = (colour, pad, radius)) an opaque
        panel behind the row, so the veiled tiles on the phone do not show
        between and around the lifted ones; it comes up with the first tile
        and stays while any is up. Then the tiles."""
        ps = [self.progress(i, t) for i in range(len(self.lifts))]
        if veil_rect is not None:
            draw_veil(canvas, veil_rect, max(ps), self.style)
        if backdrop is not None and max(ps) > 0:
            colour, pad, radius = backdrop
            p = skia.Paint(AntiAlias=True, Color=colour)
            p.setAlphaf(min(1.0, max(ps)))
            canvas.drawRRect(skia.RRect.MakeRectXY(skia.Rect.MakeLTRB(*self.backdrop_rect(pad)), radius, radius), p)
        for lift, p in zip(self.lifts, ps):
            lift.draw(canvas, p)
