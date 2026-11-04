"""The carnet: a procedural ruled paper page, written full, in 2.5D, lit warm
and low — the hook's « Votre carnet déborde ? ».

NOTHING HERE IS WRITING. There is no font and no letter: every « word » is a
pen path generated from a seed — a garland of humps and loops of random
widths and heights, the odd ascender loop or descender, a slant, a pen-lift
and sometimes a dot or a crossbar after it — the rhythm of fast handwriting
with nothing to read (storyboard: « deliberately unreadable and use no
handwriting font »; honesty: no names, no numbers, no claim about anyone).

THE PAGE (page px, 1200 × 1560 by default): warm paper with a faint fibre
texture (seeded, baked once), blue rules every 60 px, a rose margin line,
two sheets of the pad peeking out below. Rows are full — the carnet
« déborde »:
  « rowNN »      the entry on row NN (a short first cluster like a time, then
                 a name-like run, sometimes a third cluster);
  « write »      the entry being written in the hook (ink drawing on);
  « squeeze »    an entry squeezed between two rules at 0.62 size …
  « arrow »      … with a hand-drawn arrow to the row it belongs to;
  « margin »     the note that writes itself in the margin (f48);
  « crossNN »    old pen cross-outs on two rows near the squeezed entry;
  « header »     the page's date-like heading, underlined, in the top margin;
  « tickNN »     ticks in the margin beside some done appointments.
Every entry has a total pen length; `ink={id: progress}` draws it on along
the pen's own order (left to right, word by word, the dots last).

THE STRIKES are not the pen: the brand's black round-cap stroke at the
mark's single weight (type.draw_strike), from 4× its width to full length
in 4 frames, one per row via `strikes={row: progress}`.

2.5D AND LIGHT: the page lies flat at `rest` (frame px) and is turned by a
projection.Pose (rot_x 22° in the hook): paper, rules, ink and strikes are
all drawn under ONE projective matrix, as vectors (the fibre texture is the
only bitmap), so a macro at 2.5× stays sharp. A warm key light pools on the
page (radial, multiplied over everything on it) and falls to near black at
its edges: lit low. `light` scales the exposure (1 normal, 0 black — the
page « sinks toward black »).
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
import skia
from scipy.ndimage import gaussian_filter

from . import projection
from .brand import PALETTE, mark_geometry
from .projection import Pose
from .surface import Rect, image_from_array, sampling_for
from .type import draw_strike


@dataclass(frozen=True)
class CarnetStyle:
    page: tuple[int, int] = (1200, 1560)        # page px
    paper: tuple[int, int, int] = (0xF4, 0xEE, 0xE1)
    sheet_shade: float = 0.86                   # the sheets below, darker
    rule: int = 0xFF9DB4CC                      # light blue rules
    rule_width: float = 1.6
    pitch: float = 60.0                         # rule spacing
    first_rule: float = 190.0                   # y of the first rule
    last_rule: float = 1480.0
    margin_x: float = 170.0                     # the margin line
    margin_colour: int = 0xFFDB8E8E
    ink: int = 0xFF232C57                       # ballpoint blue-black
    ink_width: float = 2.7
    x_height: float = 17.0                      # of the scribbles, page px
    slant_deg: float = 14.0
    right_edge: float = 1110.0                  # entries end before this
    corner: float = 10.0
    # warm key light: centre (fraction of the page), radius (fraction of
    # its height), colour at the centre, and what is left at the edge
    light_centre: tuple[float, float] = (0.44, 0.66)
    light_radius: float = 0.80
    light_colour: tuple[float, float, float] = (1.0, 0.91, 0.76)
    light_mid: float = 0.42                     # left at 55 % of the radius
    light_edge: float = 0.05
    # the strikes: black, the mark's single weight relative to a mark one
    # row and a half tall (≈ 10 px for a 60-px pitch), round cap
    strike_colour: int | None = None
    strike_rows_tall: float = 1.5


STYLE = CarnetStyle()


@dataclass
class Stroke:
    """One pen-down: a path, its length, its look."""

    path: skia.Path
    length: float
    width: float
    colour: int
    alpha: float = 1.0


@dataclass
class Entry:
    id: str
    row: float                                    # the rule it sits on (x.5 = between two)
    strokes: list[Stroke] = field(default_factory=list)
    bounds: Rect = (0.0, 0.0, 0.0, 0.0)           # page px, ink box

    @property
    def length(self) -> float:
        return sum(s.length for s in self.strokes)


# ---- the pen ----------------------------------------------------------------------

def _catmull_rom(points: list[tuple[float, float]]) -> skia.Path:
    """A smooth path through `points` (uniform Catmull-Rom as cubics)."""
    path = skia.Path()
    if not points:
        return path
    p = [points[0]] + points + [points[-1]]
    path.moveTo(*points[0])
    for i in range(1, len(p) - 2):
        p0, p1, p2, p3 = p[i - 1], p[i], p[i + 1], p[i + 2]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        path.cubicTo(*c1, *c2, *p2)
    return path


def _length(path: skia.Path) -> float:
    m = skia.PathMeasure(path, False)
    total = 0.0
    while True:
        total += m.getLength()
        if not m.nextContour():
            break
    return total


def _bounds(path: skia.Path, pad: float) -> Rect:
    b = path.computeTightBounds()
    return (b.left() - pad, b.top() - pad, b.right() + pad, b.bottom() + pad)


def scribble_word(rng: np.random.Generator, x: float, baseline: float, h: float, cycles: int,
                  slant_deg: float) -> tuple[list[tuple[float, float]], float]:
    """Key points of one unreadable cursive « word » starting at x on
    `baseline` with x-height h, and the x where it ends. Each cycle rises to
    a random height (now and then an ascender loop or a descender) and comes
    back down, so the result has handwriting's rhythm and no letter's form."""
    pts = [(x - 0.25 * h, baseline - 0.15 * h)]
    k = math.tan(math.radians(slant_deg))
    cx = x
    for _ in range(cycles):
        w = h * rng.uniform(0.55, 1.05)
        kind = rng.choice(["hump", "hump", "hump", "cup", "tall", "low"], p=[0.25, 0.2, 0.15, 0.2, 0.12, 0.08])
        top = h * rng.uniform(0.78, 1.08)
        if kind == "tall":
            top = h * rng.uniform(1.9, 2.4)
            # an ascender loop: up, a hair back, down
            pts += [(cx + 0.45 * w, baseline - top), (cx + 0.2 * w, baseline - top * 0.82),
                    (cx + 0.55 * w, baseline - 0.05 * h)]
        elif kind == "low":
            # a descender loop below the line
            depth = h * rng.uniform(0.9, 1.3)
            pts += [(cx + 0.4 * w, baseline - top * 0.9), (cx + 0.55 * w, baseline + depth),
                    (cx + 0.25 * w, baseline + depth * 0.7), (cx + 0.7 * w, baseline - 0.1 * h)]
        elif kind == "cup":
            pts += [(cx + 0.25 * w, baseline - 0.05 * h), (cx + 0.75 * w, baseline - top)]
        else:
            pts += [(cx + 0.5 * w, baseline - top), (cx + w * rng.uniform(0.85, 1.0), baseline - 0.04 * h)]
        cx += w
    pts.append((cx + 0.3 * h, baseline - 0.35 * h))
    # slant (top leans right) and a little hand tremor
    out = [(px + (baseline - py) * k + rng.normal(0, 0.04 * h), py + rng.normal(0, 0.04 * h)) for px, py in pts]
    return out, cx + 0.3 * h


class Carnet:
    """A written page, generated from `seed` (same seed, same page)."""

    ANIMATED = ("write", "margin")               # not drawn unless their ink is given

    def __init__(self, seed: int = 7, style: CarnetStyle = STYLE):
        self.seed, self.style = seed, style
        self.rng = np.random.default_rng(seed)
        s = style
        self.rows = int(round((s.last_rule - s.first_rule) / s.pitch)) + 1
        self.entries: dict[str, Entry] = {}
        self.write_row = self.rows - 6
        self.squeeze_after = self.rows - 10           # squeezed between this row and the next
        self.crossed_rows = (self.squeeze_after - 1, self.squeeze_after + 2)
        self._build()
        self._paper: skia.Image | None = None

    # ---- geometry -----------------------------------------------------------

    @property
    def size(self) -> tuple[int, int]:
        return self.style.page

    def rule_y(self, row: float) -> float:
        return self.style.first_rule + row * self.style.pitch

    def baseline(self, row: float) -> float:
        """Writing sits just on the rule."""
        return self.rule_y(row) - 0.12 * self.style.x_height

    def strike_width(self) -> float:
        s = self.style
        return mark_geometry().weight * s.pitch * s.strike_rows_tall

    def strike_segment(self, row: int) -> tuple[tuple[float, float], tuple[float, float]]:
        """The strike through row `row`'s entry: from just before its ink to
        just after, through its x-height, a hair off level (page px)."""
        eid = "write" if row == self.write_row else f"row{row:02d}"
        if eid not in self.entries:
            raise KeyError(f"row {row} has no entry to strike (rows 0–{self.rows - 1})")
        e = self.entries[eid]
        x0, _, x1, _ = e.bounds
        y = self.baseline(row) - 0.5 * self.style.x_height
        tilt = math.tan(math.radians(self._tilts[row]))
        pad = 0.6 * self.style.x_height
        return (x0 - pad, y + (x1 - x0) * tilt / 2), (x1 + pad, y - (x1 - x0) * tilt / 2)

    def rest_rect(self, x0: float, x1: float, top: float) -> Rect:
        """Where the page lies flat in the frame: spanning x0..x1 from `top`."""
        w, h = self.size
        return (x0, top, x1, top + (x1 - x0) * h / w)

    def matrix(self, pose: Pose, rest: Rect) -> np.ndarray:
        """3×3 map from page px to frame px."""
        w, h = self.size
        k = (rest[2] - rest[0]) / w
        return projection.homography(pose, rest) @ projection.affine(k, k, rest[0], rest[1])

    def page_point(self, x: float, y: float, pose: Pose, rest: Rect) -> tuple[float, float]:
        """Frame position of page point (x, y)."""
        return projection.apply(self.matrix(pose, rest), x, y)

    def focus(self, pose: Pose, rest: Rect, page_xy: tuple[float, float], frame_xy: tuple[float, float]) -> Pose:
        """`pose` moved so page point `page_xy` lands on frame `frame_xy` (the
        macro on the squeezed entry)."""
        w, _ = self.size
        k = (rest[2] - rest[0]) / w
        return projection.solve_offset(pose, rest, (rest[0] + page_xy[0] * k, rest[1] + page_xy[1] * k), frame_xy)

    def entry_centre(self, entry_id: str) -> tuple[float, float]:
        x0, y0, x1, y1 = self.entries[entry_id].bounds
        return (x0 + x1) / 2, (y0 + y1) / 2

    # ---- generation ---------------------------------------------------------------

    def _pen(self, points, width=None, colour=None, alpha=1.0) -> Stroke:
        path = _catmull_rom(points)
        return Stroke(path, _length(path), width or self.style.ink_width, colour or self.style.ink, alpha)

    def _line(self, points, width=None, colour=None, alpha=1.0) -> Stroke:
        path = skia.Path()
        path.moveTo(*points[0])
        for p in points[1:]:
            path.lineTo(*p)
        return Stroke(path, _length(path), width or self.style.ink_width, colour or self.style.ink, alpha)

    def _word(self, entry: Entry, x: float, baseline: float, h: float, cycles: int, alpha: float,
              slope: float = 0.0, extras: list | None = None) -> float:
        """Write one scribbled word from x; returns where it ends. A dot or a
        crossbar after it, now and then, goes to `extras` (written last, as a
        hand does)."""
        rng, s = self.rng, self.style
        pts, x_end = scribble_word(rng, x, baseline, h, cycles, s.slant_deg)
        if slope:
            pts = [(px, py + (px - x) * slope) for px, py in pts]
        entry.strokes.append(self._pen(pts, alpha=alpha))
        if extras is not None and rng.random() < 0.35:
            fx = rng.uniform(x + 0.25 * (x_end - x), x_end - 0.25 * (x_end - x))
            fy = baseline + (fx - x) * slope
            if rng.random() < 0.5:
                extras.append(self._line([(fx, fy - 1.75 * h), (fx + 0.35 * h, fy - 1.85 * h)], alpha=alpha))
            else:
                extras.append(self._line([(fx - 0.6 * h, fy - 1.15 * h), (fx + 0.7 * h, fy - 1.3 * h)], alpha=alpha))
        return x_end

    def _write(self, entry: Entry, x: float, baseline: float, h: float, clusters: list[int],
               gap: float, alpha: float, slope: float = 0.0) -> float:
        """Write words of `clusters` cycles on `baseline` from x; returns the end x."""
        extras: list[Stroke] = []
        for n in clusters:
            x = self._word(entry, x, baseline, h, n, alpha, slope, extras) + gap
        entry.strokes += extras
        return x - gap

    def _entry(self, eid: str, row: float, baseline: float, scale: float = 1.0, x0: float | None = None,
               max_x: float | None = None) -> Entry:
        """A row's entry: a short first word (the time), then words until a
        random point of the line's last third — a full carnet."""
        rng, s = self.rng, self.style
        h = s.x_height * scale * rng.uniform(0.92, 1.1)
        e = Entry(eid, row)
        x = (x0 if x0 is not None else s.margin_x + 22) + rng.uniform(0, 10)
        limit = max_x if max_x is not None else s.right_edge
        stop = limit - rng.uniform(0.0, 0.32) * (limit - x)
        alpha = float(rng.uniform(0.8, 0.95))
        slope = math.tan(math.radians(rng.uniform(-0.6, 0.6)))
        gap = 1.25 * h * rng.uniform(0.9, 1.25)
        extras: list[Stroke] = []
        first = True
        while True:
            n = int(rng.integers(2, 4)) if first else int(rng.integers(2, 8))
            if not first and x + (n * 0.85 + 0.6) * h > stop:
                break
            x = self._word(e, x, baseline + (x - s.margin_x) * slope, h, n, alpha, slope, extras) + gap
            if first:
                x += 0.8 * h                       # the time stands a little apart
            first = False
        e.strokes += extras
        e.bounds = self._entry_bounds(e)
        return e

    def _entry_bounds(self, e: Entry) -> Rect:
        rects = [_bounds(st.path, st.width / 2) for st in e.strokes]
        return (min(r[0] for r in rects), min(r[1] for r in rects), max(r[2] for r in rects), max(r[3] for r in rects))

    def _build(self) -> None:
        rng, s = self.rng, self.style
        self._tilts = {r: float(rng.uniform(-1.6, 1.6)) for r in range(self.rows)}
        a = self.squeeze_after
        # the page's header: a bigger word and an underline in the top margin
        head = Entry("header", -1)
        hy = s.first_rule - 0.95 * s.pitch
        x_end = self._write(head, s.margin_x + 40, hy, s.x_height * 1.35, [4, 5], 1.6 * s.x_height, 0.95)
        head.strokes.append(self._pen([(s.margin_x + 30, hy + 14), ((s.margin_x + 30 + x_end) / 2, hy + 17),
                                       (x_end + 20, hy + 13)]))
        head.bounds = self._entry_bounds(head)
        self.entries["header"] = head
        for r in range(self.rows):
            eid = "write" if r == self.write_row else f"row{r:02d}"
            self.entries[eid] = self._entry(eid, r, self.baseline(r))
            # done appointments ticked in the margin (not beside the margin note)
            if eid != "write" and not (a + 1 <= r <= a + 4) and rng.random() < 0.35:
                tx, ty = s.margin_x - 52 + rng.uniform(-4, 4), self.baseline(r) - 0.4 * s.x_height
                tick = Entry(f"tick{r:02d}", r)
                tick.strokes.append(self._pen([(tx, ty), (tx + 9, ty + 10), (tx + 30, ty - 16)]))
                tick.bounds = self._entry_bounds(tick)
                self.entries[tick.id] = tick
        # the squeezed entry: small, in the gap just under rule a — below row
        # a's writing, above row a+1's — in the line's right part
        sq_base = self.rule_y(a) + 0.24 * s.pitch
        usable = s.right_edge - s.margin_x
        sq = self._entry("squeeze", a + 0.5, sq_base, scale=0.55,
                         x0=s.margin_x + rng.uniform(0.28, 0.36) * usable, max_x=s.right_edge - 30)
        self.entries["squeeze"] = sq
        # the insertion arrow: from the squeezed entry's start, left along the
        # same gap, then down to point at the start of row a+1
        sx, sy = sq.bounds[0] - 8, sq_base - 0.35 * s.x_height * 0.55
        tx, ty = s.margin_x + 8, self.baseline(a + 1) - 0.45 * s.x_height
        bend = s.margin_x - 26
        pts = [(sx, sy), (sx - 0.45 * (sx - bend), sy - 3), (bend + 18, sy + 2), (bend, (sy + ty) / 2),
               (bend + 6, ty - 4), (tx, ty)]
        arrow = Entry("arrow", a + 0.5)
        arrow.strokes.append(self._pen(pts))
        for side in (-1, 1):                         # the V head, pointing right at the row
            ang = math.radians(180 + side * 28)
            arrow.strokes.append(self._line([(tx, ty), (tx + 15 * math.cos(ang), ty + 15 * math.sin(ang))]))
        arrow.bounds = self._entry_bounds(arrow)
        self.entries["arrow"] = arrow
        # the margin note: small, two lines in the margin below the arrow
        mh = s.x_height * 0.7
        note = Entry("margin", a + 2)
        y = self.baseline(a + 2) - 0.15 * s.pitch
        self._write(note, 16, y, mh, [3, 2], 1.1 * mh, 0.95)
        self._write(note, 24, y + 0.42 * s.pitch, mh, [4], 1.1 * mh, 0.95)
        note.bounds = self._entry_bounds(note)
        self.entries["margin"] = note
        # old pen cross-outs: a wavy double pass through two rows
        for r in self.crossed_rows:
            e = self.entries[f"row{r:02d}"]
            x0, _, x1, _ = e.bounds
            y = self.baseline(r) - 0.55 * s.x_height
            cross = Entry(f"cross{r:02d}", r)
            pts, n = [], max(6, int((x1 - x0) / 38))
            for i in range(n + 1):
                t = i / n
                pts.append((x0 - 6 + (x1 - x0 + 12) * t, y + (4.5 if i % 2 else -4.5) + rng.normal(0, 1.0)))
            back = [(x + rng.normal(0, 2), yy + rng.normal(0, 2.5) + 2.5) for x, yy in pts[::-1]]
            cross.strokes.append(self._pen(pts))
            cross.strokes.append(self._pen(back))
            cross.bounds = self._entry_bounds(cross)
            self.entries[cross.id] = cross

    # ---- paper ------------------------------------------------------------------------

    def paper(self) -> skia.Image:
        """The paper's fibre texture at page resolution (baked once)."""
        if self._paper is None:
            w, h = self.size
            g = np.random.default_rng(self.seed + 1000)
            fine = gaussian_filter(g.standard_normal((h, w)).astype(np.float32), 0.8)
            cloud = gaussian_filter(g.standard_normal((h, w)).astype(np.float32), 24.0)
            fine /= fine.std() or 1
            cloud /= cloud.std() or 1
            # long fibres: noise stretched along x
            fibres = gaussian_filter(g.standard_normal((h, w)).astype(np.float32), (0.6, 6.0))
            fibres /= fibres.std() or 1
            v = 1.6 * fine + 2.2 * cloud + 1.2 * fibres
            base = np.array(self.style.paper, np.float32)
            rgb = np.clip(base[None, None, :] + v[..., None] * np.array([1.0, 0.97, 0.9], np.float32), 0, 255)
            rgba = np.concatenate([rgb.astype(np.uint8), np.full((h, w, 1), 255, np.uint8)], axis=2)
            self._paper = image_from_array(rgba).withDefaultMipmaps()
        return self._paper

    # ---- drawing ------------------------------------------------------------------------

    @staticmethod
    def _draw_stroke(canvas: skia.Canvas, st: Stroke, upto: float | None) -> None:
        paint = skia.Paint(AntiAlias=True, Color=st.colour, Style=skia.Paint.kStroke_Style, StrokeWidth=st.width)
        paint.setStrokeCap(skia.Paint.kRound_Cap)
        paint.setStrokeJoin(skia.Paint.kRound_Join)
        paint.setAlphaf(paint.getAlphaf() * st.alpha)
        if upto is None or upto >= st.length:
            canvas.drawPath(st.path, paint)
            return
        if upto <= 0:
            return
        seg = skia.Path()
        m = skia.PathMeasure(st.path, False)
        left = upto
        while True:
            L = m.getLength()
            if left <= 0:
                break
            m.getSegment(0, min(L, left), seg, True)
            left -= L
            if not m.nextContour():
                break
        canvas.drawPath(seg, paint)

    def draw_entry(self, canvas: skia.Canvas, entry_id: str, progress: float = 1.0) -> None:
        """One entry, drawn on to `progress` of its pen length (page px canvas)."""
        e = self.entries[entry_id]
        budget = e.length * max(0.0, min(1.0, progress))
        for st in e.strokes:
            if budget <= 0:
                break
            self._draw_stroke(canvas, st, budget if budget < st.length else None)
            budget -= st.length

    def draw_page(self, canvas: skia.Canvas, *, ink: dict[str, float] | None = None,
                  strikes: dict[int, float] | None = None, light: float = 1.0,
                  strike_colour: int | None = None) -> None:
        """The page in its own px (0,0)–size: sheets, paper, rules, ink,
        strikes, and the light over all of it."""
        s = self.style
        w, h = self.size
        ink = ink or {}
        page = skia.RRect.MakeRectXY(skia.Rect.MakeWH(w, h), s.corner, s.corner)
        # the pad's sheets peeking out below
        for i, (dx, dy) in enumerate(((3, 9), (1.5, 4.5))):
            shade = s.sheet_shade ** (2 - i)
            c = tuple(int(v * shade) for v in s.paper)
            sheet = skia.RRect.MakeRectXY(skia.Rect.MakeXYWH(dx, dy, w, h), s.corner, s.corner)
            canvas.drawRRect(sheet, skia.Paint(AntiAlias=True, Color=skia.Color(*c)))
        canvas.save()
        canvas.clipRRect(page, skia.ClipOp.kIntersect, True)
        canvas.drawImageRect(self.paper(), skia.Rect.MakeWH(w, h), sampling_for(1.0))
        # rules and the margin line
        rule = skia.Paint(AntiAlias=True, Color=s.rule, Style=skia.Paint.kStroke_Style, StrokeWidth=s.rule_width)
        for r in range(self.rows):
            y = self.rule_y(r)
            canvas.drawLine(0, y, w, y, rule)
        margin = skia.Paint(AntiAlias=True, Color=s.margin_colour, Style=skia.Paint.kStroke_Style,
                            StrokeWidth=s.rule_width)
        canvas.drawLine(s.margin_x, 0, s.margin_x, h, margin)
        # ink
        for eid in self.entries:
            if eid in self.ANIMATED and eid not in ink:
                continue
            self.draw_entry(canvas, eid, ink.get(eid, 1.0))
        # the brand strikes
        sw = self.strike_width()
        colour = strike_colour if strike_colour is not None else (s.strike_colour or PALETTE.BLACK)
        for row, p in sorted((strikes or {}).items()):
            a, b = self.strike_segment(row)
            draw_strike(canvas, a, b, sw, p, colour)
        canvas.restore()
        # the light, multiplied over the page and its sheets
        self._draw_light(canvas, light)

    def _draw_light(self, canvas: skia.Canvas, light: float) -> None:
        s = self.style
        w, h = self.size
        cx, cy = s.light_centre[0] * w, s.light_centre[1] * h
        lr, lg, lb = (min(1.0, c * light) for c in s.light_colour)
        e = s.light_edge * light
        m = s.light_mid * light
        stops = [(lr, lg, lb), (m, m * 0.88, m * 0.74), (e, e * 0.8, e * 0.62)]
        colours = [skia.Color(*(round(255 * max(0.0, min(1.0, v))) for v in c)) for c in stops]
        shader = skia.GradientShader.MakeRadial(skia.Point(cx, cy), s.light_radius * h, colours, [0.0, 0.55, 1.0])
        # modulate, not multiply: it darkens what is drawn and adds nothing
        # where the layer is empty (multiply would paint the light there)
        p = skia.Paint(Shader=shader, BlendMode=skia.BlendMode.kModulate)
        p.setDither(True)
        canvas.drawRect(skia.Rect.MakeLTRB(-20, -20, w + 20, h + 20), p)

    def draw(self, canvas: skia.Canvas, pose: Pose, rest: Rect, **page_state) -> None:
        """The page at `rest` (frame px, flat), turned by `pose`. `page_state`
        goes to `draw_page` (ink, strikes, light)."""
        canvas.save()
        canvas.concat(projection.to_skia(self.matrix(pose, rest)))
        # the light's multiply must only touch the page: draw it in a layer
        w, h = self.size
        canvas.saveLayer(skia.Rect.MakeLTRB(-20, -20, w + 20, h + 20), None)
        self.draw_page(canvas, **page_state)
        canvas.restore()
        canvas.restore()
