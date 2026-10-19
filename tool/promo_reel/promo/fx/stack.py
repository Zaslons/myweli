"""Stacked lifts: several real tiles lifted one by one into a column (or a
row), one per beat — the Fiche's « 2 » Visites, « 17 000 FCFA » Dépensé,
« 13 oct. 2026 » Dernière (storyboard bar 8: x 330–690, 360 px wide, 16-px
gaps, a 6-frame z-pop each on easeOutCubic).

Each tile is a `lift.Lift` (same pixels, same card, same shadow); the veil
rises with the first tile and stays while any tile is up. Later tiles draw
over earlier ones.

The panel (`backdrop`) grows WITH the lifts: on each frame it covers the
tiles that have lifted — their cards where they are now, their places on
the phone and the gaps between — grown by `pad`; on a side where a tile
still waits for its beat, it reaches exactly to that tile's place (what lies
between — the Fiche's « 0 Absences », never lifted — goes under it with the
neighbour that lifted) and never over it: the waiting tile stays on the
phone, veiled, with its texture, until it lifts itself (review round 2: a
panel put up whole on the first lift blanked the other tiles' places and
they popped out of nothing). An edge that reaches OUT to a waiting tile's
place grows there with the pop of the lift that brought it (its 6 frames,
easeOutCubic), so what lies between is covered as the card grows over it,
never blanked on one frame (review round 3: « 0 Absences » blinked out on
f480).
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

    def backdrop_rect(self, t: float, pad: float) -> Rect | None:
        """The panel at frame t: the union of the LIFTED tiles' cards (where
        they are now) and their places on the phone — the gaps between them
        included — grown by `pad`; a side facing a tile still waiting for its
        lift reaches exactly to that tile's place, never over it. None before
        the first lift."""
        ps = [self.progress(i, t) for i in range(len(self.lifts))]
        up = [i for i, p in enumerate(ps) if p > 0]
        if not up:
            return None
        rs = [self.lifts[i].rect(ps[i]) for i in up] + [self.lifts[i].origin for i in up]
        core = (min(r[0] for r in rs), min(r[1] for r in rs), max(r[2] for r in rs), max(r[3] for r in rs))
        edges = [core[0] - pad, core[1] - pad, core[2] + pad, core[3] + pad]
        waiting = [lf.origin for i, lf in enumerate(self.lifts) if ps[i] <= 0]
        right = [o[0] for o in waiting if o[0] >= core[2]]
        left = [o[2] for o in waiting if o[2] <= core[0]]
        below = [o[1] for o in waiting if o[0] < core[2] and o[2] > core[0] and o[1] >= core[3]]
        above = [o[3] for o in waiting if o[0] < core[2] and o[2] > core[0] and o[3] <= core[1]]
        # an edge pulled back to a waiting tile's place applies at once (never over it); an edge that must
        # REACH OUT to it — over what lies between, never lifted (the Fiche's « 0 Absences ») — grows with the
        # pop of the tile whose lift brought the panel next to it, so that place is covered as the card
        # grows over it, never blanked in one frame (review round 3: f479 → f480, 381 → 718 px)
        q = ps[max(up, key=lambda i: self.ups[i])]

        def reach(edge: float, place: float, outward: float) -> float:
            return place if (place - edge) * outward <= 0 or q >= 1.0 else edge + (place - edge) * q

        if right:
            edges[2] = reach(edges[2], min(right), 1.0)  # up to the next tile waiting on the right
        if left:
            edges[0] = reach(edges[0], max(left), -1.0)
        if below:
            edges[3] = reach(edges[3], min(below), 1.0)
        if above:
            edges[1] = reach(edges[1], max(above), -1.0)
        return tuple(edges)

    def draw(self, canvas: skia.Canvas, t: float, *, veil_rect: Rect | None = None,
             backdrop: tuple[int, float, float] | None = None) -> None:
        """The veil, then (`backdrop` = (colour, pad, radius)) an opaque
        panel behind the lifted tiles (`backdrop_rect`: it grows with each
        lift), so no veiled original shows between or around them while
        every tile still to lift keeps its place; it fades in with the first
        tile. Then the tiles."""
        ps = [self.progress(i, t) for i in range(len(self.lifts))]
        if veil_rect is not None:
            draw_veil(canvas, veil_rect, max(ps), self.style)
        rect = self.backdrop_rect(t, backdrop[1]) if backdrop is not None else None
        if rect is not None:
            colour, pad, radius = backdrop
            p = skia.Paint(AntiAlias=True, Color=colour)
            p.setAlphaf(min(1.0, max(ps)))
            canvas.drawRRect(skia.RRect.MakeRectXY(skia.Rect.MakeLTRB(*rect), radius, radius), p)
        for lift, p in zip(self.lifts, ps):
            lift.draw(canvas, p)
