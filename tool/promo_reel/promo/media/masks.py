"""Blurs on the source pictures: what must not be legible (a phone number) is
blurred in every picture of the take it is in, before anything else.

A ``Blur`` is a rectangle in POINTS of the take (402 × 874; 3 px a point),
with a margin, a Gaussian σ in pixels of the take, the stretch of the take it
is on, an optional band it is cut to, and — for content that scrolls — a
``ScrollTrack``: how far the content has scrolled in each picture.

  * static     the content does not move: the rectangle is where it is
               (take2b's Fiche: Awa K.'s number);
  * tracked    the rectangle moves up with the content, ``y − scroll``
               (take5b's public page: the salon number, from
               ``phone_rect_per_frame.csv``), cut to the band the content is
               visible in (above the opaque bottom bar, y ≤ 740 pt): blurring
               the bar would blur the app's own pixels.

Blurs are attached to the ``Take`` (``take.set_masks([...])``) and applied by
it: ``Take.picture()`` only hands out masked pictures, so every scene, lift,
push-in and motion-blur subframe is made from the blurred picture. A blur is
on every picture that is ON SCREEN at any instant of its stretch — the one
already showing at ``from_s`` included.

``MaskSet.verify()`` measures what each blur leaves (the App Store tool's
measure, ``tool/app_store_preview/masks.py``: the 95th percentile of the
grey's distance to its median) and refuses a blur that leaves more than 15 %
of the content's detail, or that sits on nothing (a rectangle in the wrong
place).
"""

from __future__ import annotations

import bisect
import csv
import math
from dataclasses import dataclass, field
from pathlib import Path
from typing import TYPE_CHECKING, Iterable, Sequence

import numpy as np
from scipy import ndimage

if TYPE_CHECKING:  # pragma: no cover
    from .takes import Take

#: The blur may leave at most this share of the content's detail (App Store tool: LEGIBLE).
LEGIBLE = 0.15
#: Under this detail (grey levels) a rectangle shows nothing to hide (App Store tool: FLAT).
FLAT = 12.0
#: The Gaussian is computed this many σ out (scipy's default truncate).
TRUNCATE = 4.0
#: A CSV row and a picture are the same instant within this (the CSV's times are rounded to the ms).
CSV_TOLERANCE_S = 0.002


class MaskError(RuntimeError):
    """A blur that cannot be placed, or that leaves the content legible."""


@dataclass(frozen=True)
class ScrollTrack:
    """How far the content has scrolled, in points (up = positive), in each
    picture of a take — one value per picture, at the picture's own time."""

    ticks: tuple[int, ...]
    scroll_pt: tuple[float, ...]
    source: str = ""

    @classmethod
    def from_csv(cls, path: Path | str, take: "Take", column: str = "scroll_pt",
                 time_column: str = "seconds") -> "ScrollTrack":
        """Read a per-picture table (take5b's ``phone_rect_per_frame.csv``):
        one row per picture of ``take``, in order. Each row is matched to its
        picture — same count, each time within 2 ms — so a value is never
        applied to the neighbouring picture."""
        path = Path(path)
        with open(path, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        if not rows or column not in rows[0] or time_column not in rows[0]:
            raise MaskError(f"{path}: needs the columns {time_column!r} and {column!r}")
        if len(rows) != take.count:
            raise MaskError(f"{path}: {len(rows)} rows for the {take.count} pictures of {take.name}")
        values = []
        for i, row in enumerate(rows):
            t = float(row[time_column])
            if abs(t - take.time_s(i)) > CSV_TOLERANCE_S:
                raise MaskError(f"{path}: row {i + 2} is at {t:.3f} s, picture {i} of {take.name} at "
                                f"{take.time_s(i):.4f} s — the table is not this take's")
            values.append(float(row[column]))
        return cls(tuple(take.pts), tuple(values), str(path))

    def at_ticks(self, ticks: int) -> float:
        """The scroll of the picture shown at ``ticks``."""
        j = bisect.bisect_right(self.ticks, ticks) - 1
        if j < 0:
            raise MaskError(f"{ticks} ticks is before the scroll track starts")
        return self.scroll_pt[j]


@dataclass(frozen=True)
class Blur:
    """A rectangle of the take to blur. ``rect_pt`` is (x0, y0, x1, y1) in
    points of the take; for a tracked blur, where the content is at scroll 0.
    ``from_s``/``to_s`` (seconds of the take, inclusive, None = open) bound
    the stretch it is on; ``clip_y_pt`` (y0, y1) is the band it is cut to."""

    label: str
    rect_pt: tuple[float, float, float, float]
    sigma_px: float = 14.0
    margin_pt: float = 0.0
    from_s: float | None = None
    to_s: float | None = None
    clip_y_pt: tuple[float, float] | None = None
    track: ScrollTrack | None = field(default=None, repr=False)

    def __post_init__(self) -> None:
        x0, y0, x1, y1 = self.rect_pt
        if not (x0 < x1 and y0 < y1):
            raise MaskError(f"blur {self.label!r}: rect_pt {self.rect_pt} is empty")
        if self.sigma_px <= 0 or self.margin_pt < 0:
            raise MaskError(f"blur {self.label!r}: σ must be > 0 and the margin ≥ 0")
        if self.from_s is not None and self.to_s is not None and self.to_s < self.from_s:
            raise MaskError(f"blur {self.label!r}: ends ({self.to_s}) before it starts ({self.from_s})")
        if self.clip_y_pt is not None and not self.clip_y_pt[0] < self.clip_y_pt[1]:
            raise MaskError(f"blur {self.label!r}: clip_y_pt {self.clip_y_pt} is empty")

    def box_pt(self, ticks: int) -> tuple[float, float, float, float] | None:
        """Where the blur is (points) on the picture at ``ticks``: moved by
        the scroll, grown by the margin, cut to the band; None if nothing is left."""
        x0, y0, x1, y1 = self.rect_pt
        if self.track is not None:
            s = self.track.at_ticks(ticks)
            y0, y1 = y0 - s, y1 - s
        m = self.margin_pt
        x0, y0, x1, y1 = x0 - m, y0 - m, x1 + m, y1 + m
        if self.clip_y_pt is not None:
            y0, y1 = max(y0, self.clip_y_pt[0]), min(y1, self.clip_y_pt[1])
        return (x0, y0, x1, y1) if y1 > y0 and x1 > x0 else None


@dataclass(frozen=True)
class Placed:
    """A blur on one picture: the box it covers, in pixels of the take, and
    the rows the blur may read (its band: what is outside is another layer,
    e.g. the opaque bar the content scrolls under)."""

    label: str
    index: int
    ticks: int
    box_px: tuple[int, int, int, int]
    sigma_px: float
    rows_px: tuple[int, int] | None = None


@dataclass(frozen=True)
class Coverage:
    """What a blur leaves on one picture: the content's detail before and after."""

    label: str
    index: int
    time_s: float
    box_px: tuple[int, int, int, int]
    detail_before: float
    detail_after: float

    @property
    def share_left(self) -> float:
        return self.detail_after / self.detail_before if self.detail_before else 0.0


class MaskSet:
    """The blurs of one take, placed with the take's scale and its pictures'
    times. Built by ``Take.set_masks``."""

    def __init__(self, blurs: Iterable[Blur], take: "Take"):
        self.blurs = tuple(blurs)
        labels = [b.label for b in self.blurs]
        if len(set(labels)) != len(labels):
            raise MaskError(f"two blurs share a label: {labels}")
        self.take = take
        self.px_per_pt = take.px_per_pt
        self.size = (take.width, take.height)

    def _on(self, blur: Blur, ticks: int) -> bool:
        """Whether the picture shown at ``ticks`` is on screen during the
        blur's stretch: its display interval [pts, next pts) meets [from, to]."""
        t = self.take
        i = t.index_at_ticks(ticks)
        start = t.pts[i] / t.timescale
        end = t.pts[i + 1] / t.timescale if i + 1 < t.count else math.inf
        if blur.from_s is not None and end <= blur.from_s:
            return False
        if blur.to_s is not None and start > blur.to_s:
            return False
        return True

    def placed(self, ticks: int) -> list[Placed]:
        """Every blur on the picture at ``ticks``, with its box in pixels."""
        out = []
        i = self.take.index_at_ticks(ticks)
        for b in self.blurs:
            if not self._on(b, ticks):
                continue
            box = b.box_pt(self.take.pts[i])
            if box is None:
                continue
            px = self._to_px(box)
            if px is not None:
                rows = None
                if b.clip_y_pt is not None:
                    k, h = self.px_per_pt, self.size[1]
                    rows = (max(0, math.floor(b.clip_y_pt[0] * k)), min(h, math.ceil(b.clip_y_pt[1] * k)))
                out.append(Placed(b.label, i, self.take.pts[i], px, b.sigma_px, rows))
        return out

    def active(self, ticks: int) -> bool:
        return bool(self.placed(ticks))

    def apply(self, rgba: np.ndarray, ticks: int) -> np.ndarray:
        """A new picture: ``rgba`` with every blur on it at ``ticks`` applied."""
        out = np.array(rgba, copy=True)
        for p in self.placed(ticks):
            blur_box(out, p.box_px, p.sigma_px, p.rows_px)
        return out

    def verify(self, indices: Sequence[int] | None = None) -> list[Coverage]:
        """Measure every blur on every picture it is on (or on ``indices``)
        and refuse one that leaves the content legible. A blur must sit on
        something in at least one picture (else it is in the wrong place)."""
        t = self.take
        idx = [i for i in range(t.count) if self.placed(t.pts[i])] if indices is None else indices
        out: list[Coverage] = []
        problems = []
        for i in idx:
            raw = t.raw_picture(i)
            masked = t.picture(i) if t.masks is self else self.apply(raw, t.pts[i])
            for p in self.placed(t.pts[i]):
                before, after = legibility(raw, masked, p.box_px)
                cov = Coverage(p.label, i, t.pts[i] / t.timescale, p.box_px, round(before, 2), round(after, 2))
                out.append(cov)
                if before >= FLAT and after > LEGIBLE * before:
                    problems.append(f"{p.label} at {cov.time_s:.3f} s (picture {i}): leaves "
                                    f"{after / before:.0%} of the detail ({after:.1f} of {before:.1f}), "
                                    f"at most {LEGIBLE:.0%}")
        for b in self.blurs:
            mine = [c for c in out if c.label == b.label]
            if mine and max(c.detail_before for c in mine) < FLAT:
                problems.append(f"{b.label}: sits on nothing in any picture (detail under {FLAT:g}) — wrong place?")
        if problems:
            raise MaskError("; ".join(problems))
        return out

    def report(self) -> list[dict]:
        """Every picture a blur is on, and where (pixels) — for the build record."""
        rows = []
        for i, ticks in enumerate(self.take.pts):
            for p in self.placed(ticks):
                rows.append({"picture": i, "time_s": round(ticks / self.take.timescale, 4), "blur": p.label,
                             "box_px": list(p.box_px), "sigma_px": p.sigma_px})
        return rows

    def _to_px(self, box_pt: tuple[float, float, float, float]) -> tuple[int, int, int, int] | None:
        """Points → whole pixels, rounded OUTWARD (never a pixel less), cut to the picture."""
        k = self.px_per_pt
        w, h = self.size
        x0 = max(0, math.floor(box_pt[0] * k))
        y0 = max(0, math.floor(box_pt[1] * k))
        x1 = min(w, math.ceil(box_pt[2] * k))
        y1 = min(h, math.ceil(box_pt[3] * k))
        return (x0, y0, x1, y1) if x1 > x0 and y1 > y0 else None


def blur_box(rgba: np.ndarray, box: tuple[int, int, int, int], sigma: float,
             rows: tuple[int, int] | None = None) -> None:
    """Gaussian-blur ``box`` (x0, y0, x1, y1 px) of ``rgba`` in place. The
    blur reads the pixels around the box (as far as the kernel reaches, and
    only within ``rows`` when given — the edge row is repeated beyond) and
    writes inside it only; alpha is left as it is."""
    x0, y0, x1, y1 = box
    h, w = rgba.shape[:2]
    top, bottom = rows if rows is not None else (0, h)
    if not (top <= y0 and y1 <= bottom):
        raise MaskError(f"blur box rows {y0}–{y1} leave the rows it may read, {top}–{bottom}")
    pad = int(math.ceil(TRUNCATE * sigma))
    ax0, ay0, ax1, ay1 = max(0, x0 - pad), max(top, y0 - pad), min(w, x1 + pad), min(bottom, y1 + pad)
    region = rgba[ay0:ay1, ax0:ax1, :3].astype(np.float32)
    blurred = ndimage.gaussian_filter(region, sigma=(sigma, sigma, 0), mode="nearest", truncate=TRUNCATE)
    inner = blurred[y0 - ay0:y1 - ay0, x0 - ax0:x1 - ax0]
    rgba[y0:y1, x0:x1, :3] = np.clip(np.rint(inner), 0, 255).astype(np.uint8)


def grey(rgba: np.ndarray) -> np.ndarray:
    """Luma (BT.709 weights) of an RGBA/RGB array, as float32."""
    rgb = rgba[..., :3].astype(np.float32)
    return rgb[..., 0] * 0.2126 + rgb[..., 1] * 0.7152 + rgb[..., 2] * 0.0722


def detail(g: np.ndarray) -> float:
    """How much there is to read in a grey picture: the 95th percentile of
    how far its pixels are from its median (App Store tool, masks.detail).
    Text on a plain card: tens of levels; a plain fill: 0."""
    if g.size == 0:
        return 0.0
    return float(np.percentile(np.abs(g - np.median(g)), 95))


def legibility(raw: np.ndarray, masked: np.ndarray, box: tuple[int, int, int, int]) -> tuple[float, float]:
    """(detail of the content under ``box``, detail left once blurred)."""
    x0, y0, x1, y1 = box
    return detail(grey(raw[y0:y1, x0:x1])), detail(grey(masked[y0:y1, x0:x1]))
