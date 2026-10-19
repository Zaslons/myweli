"""Measures read off the WRITTEN film's pixels (verify's (f), (g), (h)).

Everything here works on frames decoded from reel.mp4 — what a viewer gets,
after the encoder — never on what the renderer says it drew. Where a measure
needs to know WHERE to look (a disc's centre, the old 13:15 row's place, a
caption's lines) it takes that from the storyboard's geometry; whether the
thing is THERE is decided by the pixels.

  stream_frames(mp4, wanted)     one ffmpeg decode, the wanted frames handed
                                 over in order (RGB, BT.709 limited range as
                                 sheets.pull_frames converts them)
  ring_contrast(L, cx, cy, R)    the touch disc's own signature: its 1.5-pt
                                 ring at radius R against the pixels just
                                 inside and outside it (camera moves and UI
                                 texture average out; the ring does not)
  box_change(prev, cur, box)     mean absolute luminance change in a box
  ink_box(rgb, region, ink)      the bounding box of the ink of one colour
                                 (dark on paper, white on black, …) in a
                                 region, ignoring isolated specks
  row_showing(L, template, …)    how much of a known row of app pixels shows
                                 at a place, searched along x: the slope of
                                 the frame's pixels against the row's (1 =
                                 the row itself, 0 = none of it)
  row_fraction(L, template, …)   the share of the row's text blocks found at
                                 (or near) a place
  ncc_map(R, part)               normalised cross-correlation of a block at
                                 every place of a region (FFT; flat → 0)
  row_parts / distinctive        the row's text blocks, and which of them
                                 identify it (found nowhere else on the
                                 take's pictures)
  row_anywhere(L, parts, region) the share of those blocks found ANYWHERE in
                                 a region, at one common placement
"""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Iterable, Iterator

import numpy as np

from .media import tools

LUMA = np.array([0.2126, 0.7152, 0.0722])


def stream_frames(mp4: Path | str, wanted: Iterable[int], width: int, height: int) -> Iterator[tuple[int, np.ndarray]]:
    """(frame, RGB uint8 array) for each wanted frame, in order, from ONE
    sequential decode of the file (the same colour conversion as
    media.sheets.pull_frames)."""
    want = sorted(set(int(f) for f in wanted))
    if not want:
        return
    cmd = [tools.ffmpeg(), "-v", "error", "-nostdin", "-i", str(mp4), "-map", "0:v:0",
           "-vf", "scale=in_color_matrix=bt709:in_range=tv:flags=accurate_rnd+full_chroma_int,format=rgb24",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
    size = width * height * 3
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        k, f = 0, 0
        while k < len(want):
            buf = proc.stdout.read(size)
            if len(buf) < size:
                raise RuntimeError(f"{mp4}: the film ended at frame {f}; frame {want[k]} was asked for")
            if f == want[k]:
                yield f, np.frombuffer(buf, np.uint8).reshape(height, width, 3)
                k += 1
            f += 1
    finally:
        proc.stdout.close()
        proc.kill()
        proc.wait()


def luminance(rgb: np.ndarray) -> np.ndarray:
    return rgb[..., :3].astype(np.float64) @ LUMA


def _sample(L: np.ndarray, xs: np.ndarray, ys: np.ndarray) -> np.ndarray:
    from scipy.ndimage import map_coordinates
    return map_coordinates(L, [ys, xs], order=1, mode="nearest")


def ring_contrast(L: np.ndarray, cx: float, cy: float, R: float, ring_px: float = 2.7) -> float:
    """Mean luminance ON the disc's ring (drawn at radius R − ring/2) minus
    the mean of the circles 2.5 ring-widths inside and outside it: about −100
    for the black disc's first frame on a white card, + for the white one,
    near 0 where there is no disc (text and edges cross all three circles
    alike)."""
    th = np.linspace(0, 2 * np.pi, 240, endpoint=False)
    c, s = np.cos(th), np.sin(th)
    r_ring = R - ring_px / 2
    on = _sample(L, cx + r_ring * c, cy + r_ring * s)
    inner = _sample(L, cx + (r_ring - 2.5 * ring_px) * c, cy + (r_ring - 2.5 * ring_px) * s)
    outer = _sample(L, cx + (r_ring + 2.5 * ring_px) * c, cy + (r_ring + 2.5 * ring_px) * s)
    return float(np.mean(on) - 0.5 * (np.mean(inner) + np.mean(outer)))


def box_change(prev: np.ndarray, cur: np.ndarray, box, block: int = 8) -> float:
    """The strongest change inside box (x0, y0, x1, y1) between two
    luminance frames: the largest mean |ΔL| of its `block`×`block` tiles (a
    typed « . » is a few pixels; the encoder's noise on a still area is
    under 1)."""
    h, w = cur.shape[:2]
    x0, y0 = max(0, int(np.floor(box[0]))), max(0, int(np.floor(box[1])))
    x1, y1 = min(w, int(np.ceil(box[2]))), min(h, int(np.ceil(box[3])))
    if x1 <= x0 or y1 <= y0:
        return 0.0
    d = np.abs(cur[y0:y1, x0:x1] - prev[y0:y1, x0:x1])
    ph, pw = (-d.shape[0]) % block, (-d.shape[1]) % block
    d = np.pad(d, ((0, ph), (0, pw)))
    tiles = d.reshape(d.shape[0] // block, block, d.shape[1] // block, block).mean(axis=(1, 3))
    return float(tiles.max())


def ink_mask(rgb: np.ndarray, ink: str) -> np.ndarray:
    """Pixels of an ink: 'dark' (#1A1A1A / #4A4A4A type on paper: luminance
    under 140), 'deep' (under 100), 'white' (white type on black: bright AND
    neutral, so warm paper or a coloured UI is not ink)."""
    x = rgb[..., :3].astype(np.int16)
    L = luminance(rgb)
    if ink == "dark":
        return L < 140
    if ink == "deep":                     # the app's own dark pixels on a lifted card: under the 55 % veil the
        return L < 100                    # phone (bezel included, L ≈ 137) is never this dark
    if ink == "white":
        chroma = x.max(axis=-1) - x.min(axis=-1)
        return (L > 185) & (chroma < 24)
    raise ValueError(f"ink is 'dark', 'deep' or 'white', not {ink!r}")


def ink_box(rgb: np.ndarray, region, ink: str, min_run: int = 2) -> tuple[float, float, float, float] | None:
    """The bounding box (frame px) of `ink` inside `region` (x0, y0, x1,
    y1): the rows and columns holding at least `min_run` ink pixels (a lone
    speck of noise does not stretch it). None when there is no ink."""
    h, w = rgb.shape[:2]
    x0, y0 = max(0, int(region[0])), max(0, int(region[1]))
    x1, y1 = min(w, int(region[2])), min(h, int(region[3]))
    m = ink_mask(rgb[y0:y1, x0:x1], ink)
    cols = np.flatnonzero(m.sum(axis=0) >= min_run)
    rows = np.flatnonzero(m.sum(axis=1) >= min_run)
    if not len(cols) or not len(rows):
        return None
    return (float(x0 + cols[0]), float(y0 + rows[0]), float(x0 + cols[-1] + 1), float(y0 + rows[-1] + 1))


def row_showing(L: np.ndarray, template: np.ndarray, x0: float, y0: float, shifts: Iterable[int],
                dys: Iterable[int] = (-2, -1, 0, 1, 2), strip: int = 8) -> tuple[float, int, int]:
    """How much of `template` (a row of app pixels, luminance, already at
    the frame's scale) shows when placed with its top-left near (x0, y0):
    the largest least-squares slope b of the frame's pixels on the
    template's (P ≈ a + b·T) over horizontal shifts and small vertical ones,
    taken per horizontal strip of `strip` rows (a row half in the band's
    fade shows on its lower strips only). b ≈ 1: the row is there as
    recorded; b ≈ 0: none of it. Off the frame counts as flat paper.
    Returns (b, shift, dy)."""
    from numpy.lib.stride_tricks import sliding_window_view
    th, tw = template.shape
    H, W = L.shape
    shifts = np.asarray(list(shifts), dtype=int)
    pad = int(max(abs(shifts.min()), abs(shifts.max()))) + 2
    best = (0.0, 0, 0)
    for dy in dys:
        top = int(round(y0)) + dy
        for s0 in range(0, th, strip):
            t = template[s0:s0 + strip]
            r0, r1 = top + s0, top + s0 + t.shape[0]
            if r0 < 0 or r1 > H or float(t.std()) < 4.0:          # off the frame, or a flat strip of the row
                continue
            tc = t - t.mean()
            v = float(np.sum(tc * tc))
            band = L[r0:r1]
            band = np.pad(band, ((0, 0), (pad, pad)), mode="constant", constant_values=float(np.median(band)))
            c0 = int(round(x0)) + pad + shifts
            ok = (c0 >= 0) & (c0 + tw <= band.shape[1])
            win = sliding_window_view(band, tw, axis=1)[:, c0[ok], :]       # (rows, shifts, tw)
            slope = np.einsum("rsw,rw->s", win, tc) / v
            k = int(np.argmax(slope))
            if slope[k] > best[0]:
                best = (float(slope[k]), int(shifts[ok][k]), dy)
    return best


def row_fraction(L: np.ndarray, template: np.ndarray, x0: float, y0: float, shifts: Iterable[int],
                 dys: Iterable[int] = (0,), block: int = 64, match: float = 0.8,
                 min_std: float = 6.0) -> tuple[float, int, int]:
    """The fraction of a known row of app pixels (`template`, luminance at
    the picture's scale) that `L` shows as it is: the template is cut into
    `block`-px-wide columns; those with texture (std ≥ `min_std`) are the
    row's readable parts, and a part counts as showing when it matches the
    picture at the same place with a correlation ≥ `match` — all parts at
    one common horizontal shift (the outgoing page of a push slides left;
    the incoming one covers it from the right). 1: the whole row is there;
    0: none of it (a different row of text correlates loosely, never at
    0.8 block by block). Returns (fraction, shift, dy)."""
    from numpy.lib.stride_tricks import sliding_window_view
    th, tw = template.shape
    H, W = L.shape
    shifts = np.asarray(list(shifts), dtype=int)
    pad = int(np.abs(shifts).max()) + block + 2
    parts = []
    for b0 in range(0, tw - block // 2, block):
        t = template[:, b0:b0 + block]
        if t.shape[1] >= block // 2 and float(t.std()) >= min_std:
            parts.append((b0, t - t.mean()))
    if not parts:
        return 0.0, 0, 0
    best = (0.0, 0, 0)
    for dy in dys:
        r0 = int(round(y0)) + dy
        if r0 < 0 or r0 + th > H:
            continue
        band = np.pad(L[r0:r0 + th], ((0, 0), (pad, pad)), mode="edge")
        hits = np.zeros(len(shifts))
        for b0, tc in parts:
            bw = tc.shape[1]
            c0 = int(round(x0)) + pad + b0 + shifts
            win = sliding_window_view(band, bw, axis=1)[:, c0, :]           # (rows, shifts, bw)
            wm = win.mean(axis=(0, 2), keepdims=True)
            wc = win - wm
            num = np.einsum("rsw,rw->s", wc, tc)
            den = np.sqrt(np.einsum("rsw,rsw->s", wc, wc) * float(np.sum(tc * tc))) + 1e-9
            hits += (num / den) >= match
        k = int(np.argmax(hits))
        frac = float(hits[k] / len(parts))
        if frac > best[0]:
            best = (frac, int(shifts[k]), dy)
    return best


def closer_to(L: np.ndarray, box, old: np.ndarray, new: np.ndarray) -> float:
    """How much closer the frame's pixels in `box` are to `new` than to
    `old` (two pictures of the same place, luminance, resampled to the box),
    on the pixels where the two pictures differ: mean |L − old| − mean
    |L − new| there. Positive: the frame shows `new`."""
    from PIL import Image
    h, w = L.shape
    x0, y0 = max(0, int(round(box[0]))), max(0, int(round(box[1])))
    x1, y1 = min(w, int(round(box[2]))), min(h, int(round(box[3])))
    if x1 - x0 < 2 or y1 - y0 < 2:
        return 0.0
    size = (x1 - x0, y1 - y0)
    o = np.asarray(Image.fromarray(old.astype(np.float32)).resize(size, Image.LANCZOS), dtype=np.float64)
    n = np.asarray(Image.fromarray(new.astype(np.float32)).resize(size, Image.LANCZOS), dtype=np.float64)
    p = L[y0:y1, x0:x1]
    m = np.abs(n - o) > 24
    if not m.any():
        return 0.0
    return float(np.mean(np.abs(p - o)[m]) - np.mean(np.abs(p - n)[m]))


# ---- the hidden row, searched anywhere in the window ----------------------------------------------

def ncc_map(R: np.ndarray, part: np.ndarray, min_std: float = 2.0) -> np.ndarray:
    """The normalised cross-correlation of `part` (h × w, luminance) with
    every h × w window of `R`, top-left indexed: shape (H − h + 1, W − w + 1),
    by FFT. A window flatter than `min_std` levels matches nothing (0): an
    encoder's noise on paper never correlates with text."""
    from scipy.signal import fftconvolve
    h, w = part.shape
    if R.shape[0] < h or R.shape[1] < w:
        return np.zeros((max(0, R.shape[0] - h + 1), max(0, R.shape[1] - w + 1)))
    tc = part - part.mean()
    num = fftconvolve(R, tc[::-1, ::-1], mode="valid")
    c1 = np.pad(R, ((1, 0), (1, 0))).cumsum(0).cumsum(1)
    c2 = np.pad(R * R, ((1, 0), (1, 0))).cumsum(0).cumsum(1)

    def box(c: np.ndarray) -> np.ndarray:
        return c[h:, w:] - c[:-h, w:] - c[h:, :-w] + c[:-h, :-w]

    n = h * w
    s1, s2 = box(c1), box(c2)
    var = np.maximum(s2 - s1 * s1 / n, 0.0)
    out = num / (np.sqrt(var * float(np.sum(tc * tc))) + 1e-9)
    out[var < (min_std ** 2) * n] = 0.0
    return out


def _resized(a: np.ndarray, scale: float) -> np.ndarray:
    from PIL import Image
    if abs(scale - 1.0) < 1e-9:
        return np.asarray(a, dtype=np.float64)
    size = (max(1, round(a.shape[1] * scale)), max(1, round(a.shape[0] * scale)))
    return np.asarray(Image.fromarray(np.asarray(a, dtype=np.float32)).resize(size, Image.LANCZOS), dtype=np.float64)


def row_parts(template: np.ndarray, block: int = 96, min_std: float = 6.0) -> list[tuple[int, np.ndarray]]:
    """The row's readable parts, as row_fraction cuts them: `block`-px-wide
    columns (at the template's own scale) with texture. [(x offset, part)]."""
    th, tw = template.shape
    out = []
    for b0 in range(0, tw - block // 2, block):
        t = template[:, b0:b0 + block]
        if t.shape[1] >= block // 2 and float(t.std()) >= min_std:
            out.append((b0, np.asarray(t, dtype=np.float64)))
    return out


def distinctive(parts: list[tuple[int, np.ndarray]], pictures: Iterable[np.ndarray], own_y: float,
                scale: float = 1.0, match: float = 0.8, tol: float = 4.0) -> list[bool]:
    """Which parts IDENTIFY the row: a part found (≥ `match`) on any of
    `pictures` (luminance, the parts' scale) at a height other than the
    row's own (`own_y` ± `tol` px at the working `scale` — a push slides the
    row sideways, never up or down) is text the pictures show elsewhere — the
    new booking of the same client, every card's « Confirmé » — so finding
    it in a frame says nothing about the row. Worked at `scale` (pictures
    and parts resized alike)."""
    ps = [_resized(t, scale) for _, t in parts]
    shared = [False] * len(parts)
    y_own = own_y * scale
    for pic in pictures:
        P = _resized(pic, scale)
        for i, t in enumerate(ps):
            if shared[i]:
                continue
            ys, _ = np.nonzero(ncc_map(P, t) >= match)
            if np.any(np.abs(ys - y_own) > tol):
                shared[i] = True
        if all(shared):
            break
    return [not x for x in shared]


def row_anywhere(L: np.ndarray, parts: list[tuple[int, np.ndarray]], region, scale: float = 1.0,
                 match: float = 0.8) -> tuple[float, float, float]:
    """The share of `parts` (the row's blocks at their own scale, offsets
    included) found together ANYWHERE in `region` (x0, y0, x1, y1) of `L`,
    at `scale`: every part at one common placement of the row (its blocks
    keep their offsets; a row pushed half out of the region shows only some
    of them). Returns (share, x, y) — the row's top-left at the best
    placement (frame px)."""
    if not parts:
        return 0.0, 0.0, 0.0
    H, W = L.shape
    x0, y0 = max(0, int(region[0])), max(0, int(region[1]))
    x1, y1 = min(W, int(region[2])), min(H, int(region[3]))
    R = L[y0:y1, x0:x1]
    scaled = [(int(round(b0 * scale)), _resized(t, scale)) for b0, t in parts]
    th = scaled[0][1].shape[0]
    tw = max(b + t.shape[1] for b, t in scaled)
    ny = R.shape[0] - th + 1
    if ny <= 0:
        return 0.0, 0.0, 0.0
    Xs = np.arange(x0 - tw, x1)                       # the row's left edge, any overlap with the region
    hits = np.zeros((ny, len(Xs)))
    score = np.zeros((ny, len(Xs)))
    for b, t in scaled:
        c = ncc_map(R, t)[:ny]                         # (ny, nx): the part's top-left at (x0 + j, y0 + i)
        j = Xs + b - x0
        ok = (j >= 0) & (j < c.shape[1])
        hits[:, ok] += c[:, j[ok]] >= match
        score[:, ok] += np.clip(c[:, j[ok]], 0.0, 1.0)
    # most parts found; among equals, the placement they match best (a row one pixel off still passes 0.8)
    k = np.unravel_index(int(np.argmax(hits + 1e-3 * score / len(parts))), hits.shape)
    return float(hits[k] / len(parts)), float(Xs[k[1]]), float(y0 + k[0])
