"""Masks: content of the capture that must not be legible — a client's
phone number — hidden in every picture a scene shows.

A mask is a rectangle in pixels of the capture (1206 x 2622), drawn on one
picture of the scene, its reference. It is either

  fixed     the content under it does not move (checked: the rows around it
            are matched against the reference in every picture, and must be
            where they were — a number that scrolls out from under a fixed
            mask would be shown), or
  tracking  it follows the vertical scroll of the content under it: in each
            picture, how far the content around it has moved since the
            reference, inside the band that scrolls (`scroll_px`), is
            measured, and the rectangle moves with it, clipped to the band
            (what scrolls under a toolbar is hidden by the toolbar).

How far the content moved is found by matching: the rows around the
rectangle (`WINDOW` times its height above and below) in the reference
against the picture, shift by shift, on pictures three times smaller first
(one pixel a point), then to the pixel. Only those rows: a change elsewhere
on the screen — a card turning green — is not the content under the mask
moving. A picture whose best match is still poor (`MAX_TRACK_ERROR`) is not
a scroll of the reference — a page pushed sideways, a sheet over it — and
the tool stops: a mask that cannot say where the content is cannot hide it.

What covers the rectangle (`style`):
  fill   the colour of what is around it, sampled once on the reference (the
         median of a thin ring outside the rectangle): on a plain card the
         number is simply not there, and nothing reads as an edit;
  blur   a Gaussian blur as wide as the rectangle is tall.
Either way the tool measures what is left (`detail`) and refuses a mask
that leaves the content legible, or that hides nothing on its reference —
a rectangle in the wrong place.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

from edit import Refusal

MAX_TRACK_ERROR = 6.0   # mean grey levels between the band and the reference's, moved: over it, not a scroll
SEARCH_PT = 40.0        # how far content may move between two pictures the scene shows, either way
REANCHOR = 0.5          # past this share of the band, the picture becomes the reference the next is matched on
COARSE = 3              # the first search runs on pictures this many times smaller
MIN_ROWS = 24           # a shift that leaves fewer rows of the band to compare is not considered
FLAT = 12.0             # detail (grey levels) under which a rectangle shows nothing to hide
LEGIBLE = 0.15          # the mask may leave at most this share of the content's detail
RING_PX = 3             # the fill's colour is sampled on a ring this wide around the rectangle
WINDOW = 4              # the content matched: this many times the rectangle's height above it and below it


def grey(image: Image.Image) -> np.ndarray:
    return np.asarray(image.convert("L"), dtype=np.float32)


def detail(a: np.ndarray) -> float:
    """How much there is to read in a grey picture: the 95th percentile of
    how far its pixels are from its median. Text on a plain card: tens of
    levels; a plain fill: 0."""
    if a.size == 0:
        return 0.0
    return float(np.percentile(np.abs(a - np.median(a)), 95))


def _small(a: np.ndarray) -> np.ndarray:
    h, w = a.shape[0] // COARSE * COARSE, a.shape[1] // COARSE * COARSE
    return a[:h, :w].reshape(h // COARSE, COARSE, w // COARSE, COARSE).mean(axis=(1, 3))


def _error(a: np.ndarray, b: np.ndarray, window: tuple[int, int], band: tuple[int, int], s: int) -> float:
    """Mean difference between the rows of `window` in `a` and the same rows
    of `b` moved by `s`, on the rows whose move stays inside the band."""
    lo, hi = max(window[0], band[0] - s), min(window[1], band[1] - s)
    if hi - lo < MIN_ROWS:
        return math.inf
    return float(np.abs(a[lo:hi] - b[lo + s:hi + s]).mean())


def shift_between(a: np.ndarray, b: np.ndarray, band: tuple[int, int], guess: int, search: int,
                  window: tuple[int, int] | None = None) -> tuple[int, float]:
    """How many rows the content of `window` (by default the whole band)
    moved from `a` to `b` inside `band` (negative: up — b[y + shift] is
    a[y]), looked for within `search` of `guess`; with the mean difference
    at that shift. Coarse first, then to the pixel; of equal matches, the
    one nearest the guess."""
    window = window or band
    sa, sb = _small(a), _small(b)
    cw, cb = (window[0] // COARSE, window[1] // COARSE), (band[0] // COARSE, band[1] // COARSE)
    lo, hi = math.floor((guess - search) / COARSE), math.ceil((guess + search) / COARSE)
    coarse = min(range(lo, hi + 1), key=lambda s: (_error(sa, sb, cw, cb, s), abs(s * COARSE - guess)))
    fine = range(coarse * COARSE - COARSE, coarse * COARSE + COARSE + 1)
    best = min(fine, key=lambda s: (_error(a, b, window, band, s), abs(s - guess)))
    return best, _error(a, b, window, band, best)


@dataclass
class OnPicture:
    """A mask on one picture: the box it covers (x0, y0, x1, y1 in capture
    pixels), how it covers it, and how far the content had moved."""
    box: tuple[int, int, int, int]
    style: str
    colour: tuple[int, int, int]
    shift: int
    error: float


def ring_colour(image: Image.Image, rect: list[int]) -> tuple[int, int, int]:
    x, y, w, h = rect
    a = np.asarray(image.convert("RGB"), dtype=np.int32)
    H, W = a.shape[:2]
    x0, y0, x1, y1 = max(0, x - RING_PX), max(0, y - RING_PX), min(W, x + w + RING_PX), min(H, y + h + RING_PX)
    outer = a[y0:y1, x0:x1].reshape(-1, 3)
    inside = np.zeros((y1 - y0, x1 - x0), dtype=bool)
    inside[y - y0:y - y0 + h, x - x0:x - x0 + w] = True
    ring = outer[~inside.reshape(-1)]
    return tuple(int(v) for v in np.median(ring, axis=0))


def cover(image: Image.Image, box: tuple[int, int, int, int], style: str,
          colour: tuple[int, int, int]) -> Image.Image:
    """`image` with `box` hidden. A new picture; the take's is not touched."""
    out = image.convert("RGB").copy()
    x0, y0, x1, y1 = box
    if x1 <= x0 or y1 <= y0:
        return out
    if style == "fill":
        out.paste(colour, (x0, y0, x1, y1))
    else:
        radius = y1 - y0
        pad = 3 * radius
        W, H = out.size
        wide = (max(0, x0 - pad), max(0, y0 - pad), min(W, x1 + pad), min(H, y1 + pad))
        blurred = out.crop(wide).filter(ImageFilter.GaussianBlur(radius))
        out.paste(blurred.crop((x0 - wide[0], y0 - wide[1], x1 - wide[0], y1 - wide[1])), (x0, y0))
    return out


def legibility(original: Image.Image, covered: Image.Image, box: tuple[int, int, int, int]) -> tuple[float, float]:
    """(detail of the content under `box`, detail left once covered)."""
    return detail(grey(original.crop(box))), detail(grey(covered.crop(box)))


def place(mask: dict, shown: list[tuple[int, int, Path]], T: int, what: str) -> tuple[dict[int, OnPicture], dict]:
    """Where `mask` sits on every picture the scene shows. `shown`: (picture
    number in the take, its time in ticks, its file), in the take's order.
    Returns the mask on each picture it applies to, and what the log says."""
    if not shown:
        raise Refusal("E_MASK", f"{what}: the scene shows no picture")
    x, y, w, h = mask["rect_px"]
    style = mask.get("style", "fill")
    lo = round(mask["from_s"] * T) if mask.get("from_s") is not None else shown[0][1]
    hi = round(mask["to_s"] * T) if mask.get("to_s") is not None else shown[-1][1]
    span = [p for p in shown if lo <= p[1] <= hi]
    if not span:
        raise Refusal("E_MASK", f"{what}: no picture of the scene falls between {lo / T:.3f} and {hi / T:.3f} s")
    if mask.get("ref_s") is not None:
        at = round(mask["ref_s"] * T)
        before = [p for p in shown if p[1] <= at]
        if not before or before[-1] not in span:
            raise Refusal("E_MASK", f"{what}: the reference picture ({mask['ref_s']} s of the take) is not one the "
                                    f"scene shows while the mask is on")
        ref = before[-1]
    else:
        ref = span[0]
    with Image.open(ref[2]) as im:
        ref_image = im.convert("RGB")
    W, H = ref_image.size
    if x + w > W or y + h > H:
        raise Refusal("E_MASK", f"{what}: the rectangle {mask['rect_px']} leaves the {W} x {H} capture")
    colour = ring_colour(ref_image, mask["rect_px"])
    box0 = (x, y, x + w, y + h)
    before_d, after_d = legibility(ref_image, cover(ref_image, box0, style, colour), box0)
    if before_d < FLAT:
        raise Refusal("E_MASK", f"{what}: the rectangle shows nothing to hide on its reference picture "
                                f"({ref[1] / T:.3f} s of the take; detail {before_d:.1f}) — it is not on the content")
    if after_d > LEGIBLE * before_d:
        raise Refusal("E_MASK", f"{what}: covered by `{style}`, the content keeps {after_d / before_d:.0%} of its "
                                f"detail ({after_d:.1f} of {before_d:.1f}) — still legible")
    track = mask.get("track")
    band = tuple(track["scroll_px"]) if track else (0, H)

    def window(top: int) -> tuple[int, int]:
        """What is matched: the rows around the rectangle, where it is in
        the picture matched against — not the whole band, so that a change
        elsewhere on the screen (a card turning green) is not taken for the
        content under the mask moving. Slid into the band when the
        rectangle is near its edge or has scrolled out of it: what is
        matched is then the content nearest to where it went."""
        height = min((2 * WINDOW + 1) * h, band[1] - band[0])
        lo = min(max(top - WINDOW * h, band[0]), band[1] - height)
        return lo, lo + height

    search = round(SEARCH_PT * W / 402)
    ref_grey = grey(ref_image)
    shifts: dict[int, tuple[int, float]] = {ref[0]: (0, 0.0)}
    k = span.index(ref)
    for order in (span[k + 1:], list(reversed(span[:k]))):
        anchor, anchor_shift, last = ref_grey, 0, 0
        for j, pts, path in order:
            with Image.open(path) as im:
                cur = grey(im)
            seen = window(y + anchor_shift)
            s, e = shift_between(anchor, cur, band, last - anchor_shift, search, seen)
            total = anchor_shift + s
            if e > MAX_TRACK_ERROR:
                raise Refusal("E_MASK", f"{what}: at {pts / T:.3f} s of the take the content under the mask is not "
                                        f"the reference's, scrolled (best match {e:.1f} grey levels off, at most "
                                        f"{MAX_TRACK_ERROR:g}) — end the mask before it, or the scene")
            if not track and total != 0:
                raise Refusal("E_MASK", f"{what}: the content under this fixed mask moves {total:+d} px at "
                                        f"{pts / T:.3f} s of the take — it would leave the mask; make it track the "
                                        f"scroll")
            shifts[j] = (total, e)
            last = total
            if abs(s) > REANCHOR * (seen[1] - seen[0]):
                anchor, anchor_shift = cur, total
    out: dict[int, OnPicture] = {}
    for j, pts, path in span:
        s, e = shifts[j]
        box = (x, max(y + s, band[0]), x + w, min(y + h + s, band[1]))
        if box[3] > box[1]:
            out[j] = OnPicture(box, style, colour, s, round(e, 2))
    errors = [e for _, e in shifts.values()]
    summary = {"what": what, "style": style, "colour": colour, "tracking": bool(track),
               "reference_s": round(ref[1] / T, 3), "pictures": len(span), "covered": len(out),
               "shift_px": [min(s for s, _ in shifts.values()), max(s for s, _ in shifts.values())],
               "worst_match": round(max(errors), 2), "detail": [round(before_d, 1), round(after_d, 1)]}
    return out, summary
