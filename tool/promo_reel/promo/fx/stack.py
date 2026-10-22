"""Stacked lifts: several real tiles lifted one by one into a column (or a
row), one per beat — the Fiche's « 2 » Visites, « 17 000 FCFA » Dépensé,
« 13 oct. 2026 » Dernière (storyboard bar 8: x 330–690, 360 px wide, 16-px
gaps, a 6-frame z-pop each on easeOutCubic).

Each tile is a `lift.Lift` (same pixels, same card, same shadow); the veil
rises with the first tile and stays while any tile is up. Later tiles draw
over earlier ones.

The panel (`backdrop`) grows WITH the lifts, one piece per lifted tile:
the tile's card where it is now and its place on the phone (their hull),
grown by `pad`, cut back where it would reach a tile still waiting for its
beat — the waiting tile stays on the phone, veiled, with its texture, until
it lifts itself (review round 2: a panel put up whole on the first lift
blanked the other tiles' places and they popped out of nothing). So:

  * it never pulls back: each piece only grows (a card moves out from its
    place on one curve), and its cut is fixed while the tile it spares
    waits (review round 4: the 1:1's right edge, already out at « 13 oct. »'s
    place, was pulled back when « 17 000 » lifted — `reach` took its pace
    from the NEWEST lift);
  * it never runs ahead of a card by more than `pad`: what lies between the
    tiles — the Fiche's « 0 Absences », never lifted — goes under the card
    as it grows over it (review round 4: the panel's edge ran 80 px ahead
    of the « 17 000 » card on f480 and wiped the tile out from under
    nothing); the strip no card ever reaches — between a lifted tile's
    piece at rest and its neighbour's place — FADES under the panel with
    that tile's own pop, in place (no wipe, no letters left standing);
  * once the lifted cards are side by side their pieces meet (the pads
    overlap): no veiled original shows between them;
  * its pieces sit on WHOLE pixels, snapped outward, and a strip overlaps
    the piece it continues by a pixel: two pieces meeting on a fractional
    edge each covered part of that column and the tile under it showed
    through as a dotted 1-px seam (review round 5, 9:16 f484–f511);
  * a strip runs only over the tiles' own row (the places' height), not
    over its piece's padded height: round 5's ran 24 px above and below
    the row, across the next card's top border (1:1, a pale rectangle);
  * a `floor` (a frame y: the next row on the phone) stops every piece:
    the Fiche's panel stops 2 px above « PROCHAIN RENDEZ-VOUS »'s cap line
    (review round 5: its bottom pad sliced the label's top third in 1:1
    and hid it whole in 9:16).
"""

from __future__ import annotations

import math
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
                 down_frames: float = 5.0, style: LiftStyle = STYLE, path: str = "straight"):
        if not (len(sources) == len(origins) == len(targets) == len(ups)):
            raise ValueError("Stack: sources, origins, targets and ups must have the same length")
        pic = picture if isinstance(picture, Picture) else Picture(picture)
        self.lifts = [Lift(pic, s, o, t, style, path=path) for s, o, t in zip(sources, origins, targets)]
        self.ups, self.frames, self.down, self.down_frames, self.style = list(ups), frames, down, down_frames, style

    def progress(self, i: int, t: float) -> float:
        return pop_progress(t, self.ups[i], self.frames, self.down, self.down_frames)

    def _piece(self, i: int, p: float, pad: float, waiting: list[Rect]) -> Rect:
        """Tile i's piece at progress p: the hull of its card and its place,
        grown by `pad` and snapped OUTWARD to whole pixels, cut back to the
        places of the `waiting` tiles it would reach (on the side that faces
        each, from its own place) — snapped INWARD there, never over them."""
        lf = self.lifts[i]
        card, place = lf.rect(p), lf.origin
        x0, y0 = math.floor(min(card[0], place[0]) - pad), math.floor(min(card[1], place[1]) - pad)
        x1, y1 = math.ceil(max(card[2], place[2]) + pad), math.ceil(max(card[3], place[3]) + pad)
        for o in waiting:
            if not (o[0] < x1 and x0 < o[2] and o[1] < y1 and y0 < o[3]):
                continue                                      # clear of it
            if o[0] >= place[2]:
                x1 = min(x1, math.floor(o[0]))
            elif o[2] <= place[0]:
                x0 = max(x0, math.ceil(o[2]))
            elif o[1] >= place[3]:
                y1 = min(y1, math.floor(o[1]))
            elif o[3] <= place[1]:
                y0 = max(y0, math.ceil(o[3]))
        return float(x0), float(y0), float(x1), float(y1)

    def _neighbours(self, i: int) -> list[tuple[int, str]]:
        """The tiles next to tile i in its row (or column): (j, side), with no
        other tile's place between their places."""
        o = [lf.origin for lf in self.lifts]
        a, out = o[i], []
        for j, b in enumerate(o):
            if j == i:
                continue
            rows = b[1] < a[3] and a[1] < b[3]
            cols = b[0] < a[2] and a[0] < b[2]
            if rows and b[0] >= a[2]:
                side, lo, hi = "right", a[2], b[0]
            elif rows and b[2] <= a[0]:
                side, lo, hi = "left", b[2], a[0]
            elif cols and b[1] >= a[3]:
                side, lo, hi = "below", a[3], b[1]
            elif cols and b[3] <= a[1]:
                side, lo, hi = "above", b[3], a[1]
            else:
                continue
            between = any(k not in (i, j) and ((side in ("right", "left") and c[1] < a[3] and a[1] < c[3]
                                                and lo <= c[0] < hi)
                                               or (side in ("below", "above") and c[0] < a[2] and a[0] < c[2]
                                                   and lo <= c[1] < hi))
                          for k, c in enumerate(o))
            if not between:
                out.append((j, side))
        return out

    def backdrop_pieces(self, t: float, pad: float, floor: float | None = None) -> list[tuple[Rect, float, bool]]:
        """The panel at frame t as (rect, opacity) pieces, one per LIFTED
        tile — the hull of its card (where it is now) and its place, grown by
        `pad`, cut back to the place of any tile still waiting (never over
        it), opaque — and, beside it, the strip its piece will never reach at
        rest up to a neighbour's place (what lies between: « 0 Absences »),
        at that tile's pop. Each is (rect, opacity, is_strip). Empty before
        the first lift. Nothing ever pulls back: a card moves out from its
        place on one curve, a cut stays put while its tile waits, a strip
        only grows more opaque."""
        ps = [self.progress(i, t) for i in range(len(self.lifts))]
        waiting = [lf.origin for i, lf in enumerate(self.lifts) if ps[i] <= 0]
        out: list[tuple[Rect, float, bool]] = []

        def floored(r: Rect) -> Rect:
            return r if floor is None else (r[0], r[1], r[2], min(r[3], float(math.floor(floor))))

        for i in range(len(self.lifts)):
            if ps[i] <= 0:
                continue
            out.append((floored(self._piece(i, ps[i], pad, waiting)), 1.0, False))
            rest = self._piece(i, 1.0, pad, [self.lifts[j].origin for j in range(len(self.lifts)) if j != i])
            a = self.lifts[i].origin
            for j, side in self._neighbours(i):
                b = self.lifts[j].origin
                # over the tiles' own row (or column) only; a pixel into the piece it continues, never past the
                # neighbour's place (a tile waiting there keeps its own)
                y0, y1 = math.floor(min(a[1], b[1])), math.ceil(max(a[3], b[3]))
                x0, x1 = math.floor(min(a[0], b[0])), math.ceil(max(a[2], b[2]))
                strip = {"right": (rest[2] - 1, y0, math.floor(b[0]), y1),
                         "left": (math.ceil(b[2]), y0, rest[0] + 1, y1),
                         "below": (x0, rest[3] - 1, x1, math.floor(b[1])),
                         "above": (x0, math.ceil(b[3]), x1, rest[1] + 1)}[side]
                strip = floored(tuple(float(v) for v in strip))
                if strip[2] > strip[0] and strip[3] > strip[1]:
                    out.append((strip, min(1.0, ps[i]), True))
        return out

    def backdrop_rects(self, t: float, pad: float, floor: float | None = None) -> list[Rect]:
        """The panel's pieces at frame t (`backdrop_pieces`), whatever their opacity."""
        return [r for r, a, _ in self.backdrop_pieces(t, pad, floor) if a > 0]

    def backdrop_rect(self, t: float, pad: float, floor: float | None = None) -> Rect | None:
        """The panel's bounds at frame t (None before the first lift)."""
        rs = self.backdrop_rects(t, pad, floor)
        if not rs:
            return None
        return (min(r[0] for r in rs), min(r[1] for r in rs), max(r[2] for r in rs), max(r[3] for r in rs))

    def draw(self, canvas: skia.Canvas, t: float, *, veil_rect: Rect | None = None,
             backdrop: tuple | None = None) -> None:
        """The veil, then (`backdrop` = (colour, pad, radius[, floor])) an
        opaque panel behind the lifted tiles (`backdrop_rects`: it grows with
        each card), so no veiled original shows between or around them
        while every tile still to lift keeps its place; it fades in with the
        first tile, and stops at `floor`. Then the tiles."""
        ps = [self.progress(i, t) for i in range(len(self.lifts))]
        if veil_rect is not None:
            draw_veil(canvas, veil_rect, max(ps), self.style)
        floor = backdrop[3] if backdrop is not None and len(backdrop) > 3 else None
        pieces = self.backdrop_pieces(t, backdrop[1], floor) if backdrop is not None else []
        if pieces:
            # one panel: its pieces drawn in one layer at the panel's alpha (no darker overlaps); the cards' own
            # pieces opaque and rounded, the strips between square (they join two pieces) at their pop
            colour, pad, radius = backdrop[:3]
            layer = skia.Paint()
            layer.setAlphaf(min(1.0, max(ps)))
            canvas.saveLayer(None, layer)
            for rect, alpha, strip in sorted(pieces, key=lambda q: q[1]):
                p = skia.Paint(AntiAlias=True, Color=colour)
                p.setAlphaf(alpha)
                if strip:
                    canvas.drawRect(skia.Rect.MakeLTRB(*rect), p)
                else:
                    canvas.drawRRect(skia.RRect.MakeRectXY(skia.Rect.MakeLTRB(*rect), radius, radius), p)
            canvas.restore()
        for lift, p in zip(self.lifts, ps):
            lift.draw(canvas, p)
