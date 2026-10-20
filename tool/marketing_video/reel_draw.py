"""The compositor's primitives. Design: docs/design/pro-marketing-reel.md §5.

Everything that has an edge is drawn from its signed distance, so an edge
lands on the sub-pixel where the plan puts it and moves smoothly frame to
frame:

  strokes     a polyline thickened by a disc — round caps and round joins,
              exactly the mark's own stroke (`stroke-linecap/linejoin:
              round`); supersampled 4 x 4 below 64 px of half-width, its
              coverage taken analytically above (the page-wide « trait »
              that thickens into paper has no corner a supersample would
              see);
  shapes      rounded rectangles (the card, the bubbles, the pill), discs
              (the pen dot, the touch point), the icon tile's continuous
              corner (a superellipse, supersampled);
  type        Pillow's FreeType rendering at fractional positions, through
              an alpha mask, so a word can fade and rise.

A `Frame` also RECORDS every word it places — its ink box and its line box,
with its opacity — and can run « dry », drawing nothing: the verify step
lays every frame out that way and holds each box to the storyboard's safe
zone, so the boxes it checks are the ones the film draws. A frame may clip
everything below a line (`clip_bottom`, S4's chat column): what is drawn
and what is recorded are both clipped, and each box keeps its whole
geometry in `full` for the checks that need it (no two bubbles overlap).
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

import reel_plan as plan

SS = 4                 # supersampling of thin strokes and small shapes
ANALYTIC_FROM = 64     # half-width from which a stroke's coverage is analytic


# ---- fonts -----------------------------------------------------------------------

@lru_cache(maxsize=None)
def poppins(px: float) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(plan.POPPINS), px)


@lru_cache(maxsize=None)
def inter(px: float, wght: int = 400) -> ImageFont.FreeTypeFont:
    """Inter at opsz 14 (the stills' text cut) and the given weight."""
    f = ImageFont.truetype(str(plan.INTER), px)
    f.set_variation_by_axes([14, wght])
    return f


def font_of(spec: tuple) -> ImageFont.FreeTypeFont:
    family, px, *rest = spec
    return poppins(px) if family == "poppins" else inter(px, *rest)


def scaled(spec: tuple, k: float) -> tuple:
    family, px, *rest = spec
    return (family, round(px * k, 3), *rest)


def baseline_in(box_top: float, box_h: float, spec: tuple) -> float:
    """The baseline of a line set in a line box of `box_h`, as a text engine
    places it: the font's ascent and descent centred in the box (half the
    leading above, half below)."""
    asc, desc = font_of(spec).getmetrics()
    return box_top + (box_h - (asc + desc)) / 2 + asc


# ---- the frame -----------------------------------------------------------------------

@dataclass
class Box:
    kind: str                      # "text", "logo", "shape"; "mask", "card", "photo" are not words
    label: str
    ink: tuple[float, float, float, float]
    line: tuple[float, float, float, float] | None
    alpha: float
    text: str | None = None
    font: tuple | None = None
    full: tuple[float, float, float, float] | None = None     # the ink box before any clip
    data: dict | None = None                                  # facts a check reads (a picture's scale)


NOT_WORDS = ("mask", "card", "photo")


def _clip_box(box, bottom):
    if box is None or bottom is None:
        return box
    if box[1] >= bottom:
        return None
    return (box[0], box[1], box[2], min(box[3], bottom))


class Frame:
    def __init__(self, size: tuple[int, int], ground: tuple[int, int, int], dry: bool = False):
        self.size = size
        self.dry = dry
        self.boxes: list[Box] = []
        self.im = None if dry else Image.new("RGB", size, ground)
        self.clip_bottom: float | None = None     # nothing drawn or recorded at or below this y

    # -- compositing ---------------------------------------------------------------

    def fill(self, colour) -> None:
        if not self.dry:
            self.im.paste(colour, (0, 0, *self.size))

    def put(self, colour, alpha: np.ndarray, x0: int, y0: int) -> None:
        """Lay `colour` through a coverage array (0..1) whose top-left is at
        (x0, y0), clipped to the frame."""
        if self.dry or alpha.size == 0:
            return
        h, w = alpha.shape
        W, H = self.size
        ax0, ay0 = max(0, -x0), max(0, -y0)
        bx0, by0 = max(0, x0), max(0, y0)
        bx1, by1 = min(W, x0 + w), min(H, y0 + h)
        if self.clip_bottom is not None:
            by1 = min(by1, math.floor(self.clip_bottom))
        if bx1 <= bx0 or by1 <= by0:
            return
        a = alpha[ay0:ay0 + (by1 - by0), ax0:ax0 + (bx1 - bx0)]
        mask = Image.fromarray(np.clip(a * 255 + 0.5, 0, 255).astype(np.uint8), "L")
        self.im.paste(colour, (bx0, by0, bx1, by1), mask)

    def put_image(self, image: Image.Image, x0: int, y0: int, alpha: np.ndarray | float = 1.0) -> None:
        """Lay an RGB picture through `alpha` (a number, or an array its size)."""
        if self.dry:
            return
        a = np.full((image.height, image.width), float(alpha), np.float32) if np.isscalar(alpha) else alpha
        W, H = self.size
        ax0, ay0 = max(0, -x0), max(0, -y0)
        bx0, by0 = max(0, x0), max(0, y0)
        bx1, by1 = min(W, x0 + image.width), min(H, y0 + image.height)
        if bx1 <= bx0 or by1 <= by0:
            return
        crop = image.crop((ax0, ay0, ax0 + bx1 - bx0, ay0 + by1 - by0))
        mask = Image.fromarray(np.clip(a[ay0:ay0 + by1 - by0, ax0:ax0 + bx1 - bx0] * 255 + 0.5, 0, 255)
                               .astype(np.uint8), "L")
        self.im.paste(crop, (bx0, by0), mask)

    # -- words -----------------------------------------------------------------------

    def text(self, s: str, spec: tuple, x: float, baseline: float, colour, alpha: float = 1.0,
             label: str = "", line_box: tuple[float, float] | None = None, kind: str = "text") -> None:
        """`s` with its baseline at `baseline` and its left advance edge at x.
        `line_box` (top, bottom) is the line box the plan gives it."""
        font = font_of(spec)
        l, t, r, b = font.getbbox(s, anchor="ls")
        ink = (x + l, baseline + t, x + r, baseline + b)
        line = None
        if line_box is not None:
            line = (x, line_box[0], x + font.getlength(s), line_box[1])
        shown = _clip_box(ink, self.clip_bottom)
        if alpha > 0 and shown is not None:
            self.boxes.append(Box(kind, label or s, shown, _clip_box(line, self.clip_bottom), alpha, s, spec,
                                  full=ink))
        if self.dry or alpha <= 0 or shown is None:
            return
        ox, oy = math.floor(ink[0]) - 2, math.floor(ink[1]) - 2
        w, h = math.ceil(ink[2]) - ox + 2, math.ceil(ink[3]) - oy + 2
        mask = Image.new("L", (w, h), 0)
        ImageDraw.Draw(mask).text((x - ox, baseline - oy), s, font=font, fill=255, anchor="ls")
        a = np.asarray(mask, dtype=np.float32) / 255 * alpha
        self.put(colour, a, ox, oy)

    def centred(self, s: str, spec: tuple, cx: float, baseline: float, colour, alpha: float = 1.0,
                label: str = "", line_box=None) -> None:
        x = cx - font_of(spec).getlength(s) / 2
        self.text(s, spec, x, baseline, colour, alpha, label, line_box)

    def note(self, kind: str, label: str, box: tuple[float, float, float, float], alpha: float,
             data: dict | None = None) -> None:
        """Record a box that is not a word (a logo, a bubble, the pill, the
        card, a picture)."""
        shown = _clip_box(box, self.clip_bottom)
        if alpha > 0 and shown is not None:
            self.boxes.append(Box(kind, label, shown, None, alpha, full=box, data=data))


def blend(a: Frame, b: Frame, k: float) -> Frame:
    """A dissolve: `a` on its way out, `b` on its way in, `k` 0..1. The
    words of each are recorded at their share of the opacity."""
    out = Frame(a.size, (0, 0, 0), a.dry)
    if not a.dry:
        out.im = Image.blend(a.im, b.im, k)
    for bx, share in ((x, 1 - k) for x in a.boxes):
        if bx.alpha * share > 0:
            out.boxes.append(Box(bx.kind, bx.label, bx.ink, bx.line, bx.alpha * share, bx.text, bx.font, bx.full, bx.data))
    for bx in b.boxes:
        if bx.alpha * k > 0:
            out.boxes.append(Box(bx.kind, bx.label, bx.ink, bx.line, bx.alpha * k, bx.text, bx.font, bx.full, bx.data))
    return out


# ---- signed distances ---------------------------------------------------------------

def _grid(x0: int, y0: int, w: int, h: int, ss: int) -> tuple[np.ndarray, np.ndarray]:
    xs = x0 + (np.arange(w * ss, dtype=np.float32) + 0.5) / ss
    ys = y0 + (np.arange(h * ss, dtype=np.float32) + 0.5) / ss
    return xs[None, :], ys[:, None]


def _down(a: np.ndarray, ss: int) -> np.ndarray:
    if ss == 1:
        return a
    h, w = a.shape[0] // ss, a.shape[1] // ss
    return a.reshape(h, ss, w, ss).mean(axis=(1, 3))


def polyline_distance(px: np.ndarray, py: np.ndarray, points: list[tuple[float, float]]) -> np.ndarray:
    """Distance from every (px, py) to the polyline (broadcast arrays)."""
    best = None
    pts = [(float(x), float(y)) for x, y in points]
    if len(pts) == 1:
        pts = pts * 2
    for (ax, ay), (bx, by) in zip(pts, pts[1:]):
        dx, dy = bx - ax, by - ay
        qx, qy = px - ax, py - ay
        ll = dx * dx + dy * dy
        if ll == 0:
            d2 = qx * qx + qy * qy
        else:
            u = np.clip((qx * dx + qy * dy) / ll, 0.0, 1.0)
            ex, ey = qx - u * dx, qy - u * dy
            d2 = ex * ex + ey * ey
        best = d2 if best is None else np.minimum(best, d2)
    return np.sqrt(best)


def stroke_coverage(points, half: float, box: tuple[int, int, int, int], ss: int | None = None) -> np.ndarray:
    """Coverage of the polyline thickened by a disc of radius `half` (round
    caps, round joins) over the pixel box (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = box
    if ss is None:
        ss = 1 if half >= ANALYTIC_FROM else SS
    px, py = _grid(x0, y0, x1 - x0, y1 - y0, ss)
    d = polyline_distance(px, py, points)
    cov = np.clip((half - d) * ss + 0.5, 0.0, 1.0)
    return _down(cov, ss)


def bounds(points, pad: float, size: tuple[int, int]) -> tuple[int, int, int, int]:
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return (max(0, math.floor(min(xs) - pad)), max(0, math.floor(min(ys) - pad)),
            min(size[0], math.ceil(max(xs) + pad)), min(size[1], math.ceil(max(ys) + pad)))


def stroke(fr: Frame, points, width: float, colour, alpha: float = 1.0) -> None:
    if fr.dry or alpha <= 0:
        return
    half = width / 2
    box = bounds(points, half + 2, fr.size)
    if box[2] <= box[0] or box[3] <= box[1]:
        return
    fr.put(colour, stroke_coverage(points, half, box) * alpha, box[0], box[1])


def trim(points: list[tuple[float, float]], f: float) -> list[tuple[float, float]]:
    """The first `f` (0..1) of a polyline's length. At 0 it is its first
    point: a round-capped stroke of no length is a dot as wide as the stroke."""
    if f <= 0:
        return [points[0]]
    lengths = [math.dist(a, b) for a, b in zip(points, points[1:])]
    goal = min(1.0, f) * sum(lengths)
    out = [points[0]]
    for (a, b), l in zip(zip(points, points[1:]), lengths):
        if goal >= l:
            out.append(b)
            goal -= l
            continue
        k = goal / l if l else 0
        out.append((a[0] + (b[0] - a[0]) * k, a[1] + (b[1] - a[1]) * k))
        break
    return out


def drawn_line(x0: float, x1: float, y: float, progress: float, start: float = 0.0) -> list[tuple[float, float]]:
    """A strike or a « trait » drawn left to right, `progress` of the way
    from a first length of `start` px (a short visible stroke, never a lone
    dot: R1) to the whole line."""
    whole = x1 - x0
    first = min(start, whole)
    length = first + (whole - first) * min(1.0, max(0.0, progress))
    return [(x0, y), (x0 + length, y)]


def stroke_shadow(fr: Frame, points, width: float, spec: tuple[float, float, float]) -> None:
    """A soft shadow under a round-capped stroke — (opacity, blur, dy): the
    stroke's distance field moved down `dy`, its edge softened over `blur`
    px (a logistic fall-off, close to a Gaussian's). It lets a white stroke
    read on a white page; on black it disappears."""
    if fr.dry:
        return
    opacity, blur, dy = spec
    half = width / 2
    shifted = [(x, y + dy) for x, y in points]
    box = bounds(shifted, half + 4 * blur + 2, fr.size)
    if box[2] <= box[0] or box[3] <= box[1]:
        return
    px, py = _grid(box[0], box[1], box[2] - box[0], box[3] - box[1], 1)
    d = polyline_distance(px, py, shifted)
    a = opacity / (1 + np.exp(np.clip(1.702 * (d - half) / blur, -50, 50)))
    fr.put((0, 0, 0), a.astype(np.float32), box[0], box[1])


def rrect_coverage(rect: tuple[float, float, float, float], radius: float, box: tuple[int, int, int, int],
                   inset: float = 0.0) -> np.ndarray:
    """Analytic coverage of a rounded rectangle (x0, y0, x1, y1), shrunk by
    `inset`, over the pixel box."""
    x0, y0, x1, y1 = rect
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    hx, hy = (x1 - x0) / 2 - inset, (y1 - y0) / 2 - inset
    r = max(0.0, radius - inset)
    px, py = _grid(box[0], box[1], box[2] - box[0], box[3] - box[1], 1)
    qx = np.abs(px - cx) - (hx - r)
    qy = np.abs(py - cy) - (hy - r)
    outside = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qy, 0) ** 2)
    inside = np.minimum(np.maximum(qx, qy), 0)
    d = outside + inside - r
    return np.clip(0.5 - d, 0.0, 1.0).astype(np.float32)


def disc_coverage(cx: float, cy: float, radius: float, box: tuple[int, int, int, int]) -> np.ndarray:
    px, py = _grid(box[0], box[1], box[2] - box[0], box[3] - box[1], 1)
    d = np.sqrt((px - cx) ** 2 + (py - cy) ** 2)
    return np.clip(radius - d + 0.5, 0.0, 1.0).astype(np.float32)


def disc(fr: Frame, cx: float, cy: float, diameter: float, colour, alpha: float = 1.0) -> None:
    if fr.dry or alpha <= 0 or diameter <= 0:
        return
    r = diameter / 2
    box = (math.floor(cx - r - 2), math.floor(cy - r - 2), math.ceil(cx + r + 2), math.ceil(cy + r + 2))
    fr.put(colour, disc_coverage(cx, cy, r, box) * alpha, box[0], box[1])


def superellipse_coverage(cx: float, cy: float, half: float, n: float, box: tuple[int, int, int, int],
                          inset: float = 0.0) -> np.ndarray:
    """|x/a|^n + |y/a|^n <= 1 — a continuous-corner square — supersampled."""
    px, py = _grid(box[0], box[1], box[2] - box[0], box[3] - box[1], SS)
    a = half - inset
    v = np.abs((px - cx) / a) ** n + np.abs((py - cy) / a) ** n
    return _down((v <= 1.0).astype(np.float32), SS)


def soft_shadow(alpha: np.ndarray, shadows: list[tuple[float, float, float]], strength: float = 1.0
                ) -> tuple[np.ndarray, int]:
    """The stills' shadows (`compose.py`: the shape at `opacity`, moved down
    `dy`, blurred by `blur / 2`), one after the other, as their combined
    coverage — and the padding added on every side."""
    pad = int(max(b for _, b, _ in shadows) * 1.5 + max(d for _, _, d in shadows)) + 4
    h, w = alpha.shape
    total = np.zeros((h + 2 * pad, w + 2 * pad), np.float32)
    for opacity, blur, dy in shadows:
        layer = np.zeros_like(total)
        layer[pad + dy:pad + dy + h, pad:pad + w] = alpha * opacity * strength
        im = Image.fromarray(np.clip(layer * 255 + 0.5, 0, 255).astype(np.uint8), "L")
        im = im.filter(ImageFilter.GaussianBlur(blur / 2))
        a = np.asarray(im, dtype=np.float32) / 255
        total = 1 - (1 - total) * (1 - a)
    return total, pad
