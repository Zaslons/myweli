"""The logo, from the repository's vectors only — never typed text.
Design: docs/design/pro-marketing-reel.md §3.

  the mark       `myweli_mark_black.svg`: one closed polyline, stroke 28.85,
                 round caps and joins. Its draw-on takes the PATH ORDER and
                 the TIMING of the fast loader Lottie
                 (`myweli_mark_loader_fast.json`): from the middle of the
                 right stem, down, the W, the left stem up, the M, back down
                 to the start; trim end 0 -> 100 % over its frames 0-15 at
                 25 fps (0.6 s) on (0.4, 0, 0.2, 1). The loader's vertices
                 are mapped onto the SVG's geometry and must land on the
                 SVG's own vertices.
  « MyWeli Pro »  the wordmark SVG (M and W strokes, y e l i outlines) plus
                 the « Pro » glyph outlines of the Pro app-open Lottie
                 (`myweli_loader_mixed_pro.json`), placed as that file
                 places them in its frames 12-38 and recoloured #000. The
                 Lottie's « MyWeli » is the wordmark SVG scaled: the
                 transform between them is fitted on the M and W strokes'
                 ten vertices and must fit to a hundredth of a unit, so
                 « Pro » sits where the animation sets it. Rendered by
                 `rsvg-convert`.
  the Pro icon   `AppIcon-pro …/Icon-1024.png`: its mark's box is measured
                 on the picture and must be the box the storyboard gives.
"""

from __future__ import annotations

import json
import math
import re
import subprocess
from functools import lru_cache
from io import BytesIO

import numpy as np
from PIL import Image

import reel_plan as plan

# ---- the mark -------------------------------------------------------------------------


def _svg_polyline(path: str) -> tuple[list[tuple[float, float]], float]:
    src = path
    d = re.search(r'd="([^"]+)"', src).group(1)
    pts = [(float(x), float(y)) for x, y in re.findall(r"[ML]\s*([\d.]+)\s+([\d.]+)", d)]
    width = float(re.search(r'stroke-width="([\d.]+)"', src).group(1))
    if 'stroke-linecap="round"' not in src or 'stroke-linejoin="round"' not in src:
        plan.die(f"{plan.MARK_SVG} is no longer a round-capped, round-joined stroke")
    return pts, width


@lru_cache(maxsize=None)
def mark_geometry() -> dict:
    """The mark in the SVG's units: the draw path (closed, in the loader's
    order), the stroke width, the outer box, and the loader's timing."""
    svg_pts, width = _svg_polyline(plan.MARK_SVG.read_text(encoding="utf-8"))
    lottie = json.loads(plan.LOADER_FAST.read_text(encoding="utf-8"))
    layer = lottie["layers"][0]
    group = layer["shapes"][0]["it"]
    shape = next(i for i in group if i["ty"] == "sh")["ks"]["k"]
    tm = next(i for i in group if i["ty"] == "tm")
    if not shape["c"] or any(any(v) for v in shape["i"] + shape["o"]):
        plan.die(f"{plan.LOADER_FAST}: the mark is no longer a closed polyline")
    lv = shape["v"]
    lx = [v[0] for v in lv]
    ly = [v[1] for v in lv]
    sx = [p[0] for p in svg_pts]
    sy = [p[1] for p in svg_pts]
    kx = (max(sx) - min(sx)) / (max(lx) - min(lx))
    ky = (max(sy) - min(sy)) / (max(ly) - min(ly))
    if abs(kx - ky) > 1e-3:
        plan.die(f"the loader's mark is not the SVG's mark scaled ({kx:.5f} x, {ky:.5f} y)")
    mapped = [((x - min(lx)) * kx + min(sx), (y - min(ly)) * kx + min(sy)) for x, y in lv]
    # The loader's first vertex is the middle of the right stem (its start
    # point); every other one is a vertex of the SVG — snapped onto it, so
    # the drawn mark is the SVG's to the hundredth.
    start = (max(sx), (min(sy) + max(sy)) / 2)
    if math.dist(mapped[0], start) > 0.1:
        plan.die(f"the loader no longer starts at the middle of the right stem: {mapped[0]}")
    order = [start]
    for q in mapped[1:]:
        p = min(svg_pts, key=lambda v: math.dist(v, q))
        if math.dist(p, q) > 0.1:
            plan.die(f"the loader's vertex {q} is not a vertex of the SVG's mark")
        order.append(p)
    if sorted(set(order[1:])) != sorted(set(svg_pts)):
        plan.die("the loader's path does not visit every vertex of the SVG's mark")
    path = order + [order[0]]

    # timing: trim end 0 -> 100 over the loader's first keyframes, on its easing
    fr = lottie["fr"]
    keys = tm["e"]["k"]
    k0, k1 = keys[0], keys[1]
    if k0["s"] != [0] or k1["s"] != [100]:
        plan.die(f"{plan.LOADER_FAST}: the trim end no longer runs 0 -> 100 first")
    easing = (k0["o"]["x"][0], k0["o"]["y"][0], k0["i"]["x"][0], k0["i"]["y"][0])
    if tuple(float(v) for v in easing) != plan.brand.CUBICS["fastOutSlowIn"]:
        plan.die(f"the loader's easing is {easing}, not fastOutSlowIn")
    return {
        "path": path, "width": width,
        "outer": (min(sx) - width / 2, min(sy) - width / 2, max(sx) + width / 2, max(sy) + width / 2),
        "draw_s": (k1["t"] - k0["t"]) / fr,
    }


def mark_points(centre: tuple[float, float], height: float) -> tuple[list[tuple[float, float]], float]:
    """The draw path in frame pixels for a mark `height` px tall outside
    (stroke included), centred at `centre`; and the stroke width."""
    g = mark_geometry()
    x0, y0, x1, y1 = g["outer"]
    k = height / (y1 - y0)
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    pts = [(centre[0] + (x - cx) * k, centre[1] + (y - cy) * k) for x, y in g["path"]]
    return pts, g["width"] * k


def mark_box(centre: tuple[float, float], height: float) -> tuple[float, float, float, float]:
    g = mark_geometry()
    x0, y0, x1, y1 = g["outer"]
    k = height / (y1 - y0)
    return (centre[0] - (x1 - x0) * k / 2, centre[1] - height / 2, centre[0] + (x1 - x0) * k / 2, centre[1] + height / 2)


@lru_cache(maxsize=None)
def icon_mark() -> tuple[tuple[float, float], float]:
    """The mark's centre and outer height inside the Pro app icon tile, from
    Icon-1024.png measured (its ink's half-coverage box), checked against
    the storyboard's « 319–704 × 178–845 of 1024 »."""
    a = np.asarray(Image.open(plan.ICON_PRO).convert("L"), dtype=np.float32)
    bg = float(np.median(a[:40, :40]))
    ink = (bg - a) / bg >= 0.5                # at least half covered: the mark's outer edge
    cols = np.nonzero(ink.any(axis=0))[0]
    rows = np.nonzero(ink.any(axis=1))[0]
    box = (int(cols.min()), int(cols.max()) + 1, int(rows.min()), int(rows.max()) + 1)
    (sx0, sx1), (sy0, sy1) = plan.S8["icon_box_of_1024"]
    if any(abs(a_ - b_) > 2 for a_, b_ in zip(box, (sx0, sx1, sy0, sy1))):
        plan.die(f"Icon-1024.png's mark is at {box}, the storyboard says {sx0}–{sx1} × {sy0}–{sy1}")
    x, y, side = plan.S8["tile"]
    k = side / a.shape[0]
    centre = (x + (box[0] + box[1]) / 2 * k, y + (box[2] + box[3]) / 2 * k)
    return centre, (box[3] - box[2]) * k


# ---- « MyWeli Pro » -------------------------------------------------------------------------


def _lottie_path(shape: dict, f) -> str:
    """A Lottie bezier shape as SVG path data, through the point map `f`."""
    v, i, o = shape["v"], shape["i"], shape["o"]
    n = len(v)
    pts = [f(p) for p in v]

    def rel(base, d):
        q = f((base[0] + d[0], base[1] + d[1]))
        return q

    out = [f"M{pts[0][0]:.4f} {pts[0][1]:.4f}"]
    segs = n if shape["c"] else n - 1
    for k in range(segs):
        a, b = v[k], v[(k + 1) % n]
        c1, c2 = rel(a, o[k]), rel(b, i[(k + 1) % n])
        p = pts[(k + 1) % n]
        out.append(f"C{c1[0]:.4f} {c1[1]:.4f} {c2[0]:.4f} {c2[1]:.4f} {p[0]:.4f} {p[1]:.4f}")
    if shape["c"]:
        out.append("Z")
    return " ".join(out)


@lru_cache(maxsize=None)
def unit_svg() -> tuple[str, tuple[float, float, float, float]]:
    """The « MyWeli Pro » unit as SVG elements in the wordmark's units, and
    its cap box (x0, y0, x1, y1): the M's left edge to the « o »'s right
    edge, the M's top to the strokes' bottom. The « y » hangs below it."""
    wm = plan.WORDMARK_SVG.read_text(encoding="utf-8")
    paths = re.findall(r"<path [^>]*/>", wm)
    strokes = [p for p in paths if 'stroke-width' in p]
    if len(strokes) != 2:
        plan.die(f"{plan.WORDMARK_SVG}: expected the M and W strokes, found {len(strokes)}")
    sw = float(re.search(r'stroke-width="([\d.]+)"', strokes[0]).group(1))
    svg_mw = [[(float(x), float(y)) for x, y in re.findall(r"[ML]\s*([\d.]+)\s+([\d.]+)",
                                                           re.search(r'd="([^"]+)"', p).group(1))]
              for p in strokes]

    lottie = json.loads(plan.PRO_OPEN.read_text(encoding="utf-8"))
    layers = {L["nm"]: L for L in lottie["layers"]}

    def static_shapes(name: str) -> list[dict]:
        group = layers[name]["shapes"][0]["it"]
        return [i["ks"]["k"] for i in group if i["ty"] == "sh"]

    def first_key(name: str) -> list[tuple[float, float]]:
        ks = layers[name]["shapes"][0]["it"][0]["ks"]
        k = ks["k"][0]["s"][0] if ks["a"] else ks["k"]
        return [tuple(v) for v in k["v"]]

    lot_mw = [first_key("M"), first_key("W")]
    # a similarity (scale + translation) from the Lottie's units to the SVG's
    src = np.array([p for s in lot_mw for p in s])
    dst = np.array([p for s in svg_mw for p in s])
    if src.shape != dst.shape:
        plan.die("the Lottie's M and W are not the wordmark's (vertex counts differ)")
    sc, dc = src.mean(axis=0), dst.mean(axis=0)
    k = float(((src - sc) * (dst - dc)).sum() / ((src - sc) ** 2).sum())
    t = dc - k * sc
    err = float(np.abs(src * k + t - dst).max())
    if err > 0.05 * k:      # a twentieth of a Lottie unit
        plan.die(f"the Pro app-open Lottie's « MyWeli » is not the wordmark SVG scaled (off by {err:.3f} units)")

    def f(p):
        return (p[0] * k + t[0], p[1] * k + t[1])

    pro = []
    for name in ("L_P", "L_r", "L_o"):
        ds = " ".join(_lottie_path(s, f) for s in static_shapes(name))
        pro.append(f'<path d="{ds}" fill="#000000" fill-rule="nonzero"/>')

    # the cap box and the ink's extents, in SVG units
    left = min(x for s in svg_mw for x, _ in s) - sw / 2
    top = min(y for s in svg_mw for _, y in s) - sw / 2
    bottom = max(y for s in svg_mw for _, y in s) + sw / 2
    o_shape = static_shapes("L_o")[0]
    right = max(f(v)[0] for v in o_shape["v"])
    # the wordmark's own colour is already #000000; the Lottie's « Pro » was
    # #111111 and is recoloured above
    body = "".join(paths) + "".join(pro)
    return body, (left, top, right, bottom)


@lru_cache(maxsize=None)
def unit_sprite(width_px: int) -> tuple[np.ndarray, tuple[int, int], tuple[float, float, float, float]]:
    """The unit rendered with its cap box `width_px` wide: its coverage
    (0..1), the sprite pixel that is the cap box's top-left corner, and the
    box of all its ink relative to that corner (measured on the render, the
    « y »'s descender included)."""
    body, (x0, y0, x1, y1) = unit_svg()
    k = width_px / (x1 - x0)
    pad_px = 8
    pad = pad_px / k
    # room below the cap box for the descender: half the cap height is ample
    vb = (x0 - pad, y0 - pad, (x1 - x0) + 2 * pad, (y1 - y0) * 1.5 + 2 * pad)
    wpx, hpx = round(vb[2] * k), round(vb[3] * k)
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{vb[0]:.4f} {vb[1]:.4f} {vb[2]:.4f} {vb[3]:.4f}" '
           f'width="{wpx}" height="{hpx}">{body}</svg>')
    png = subprocess.run(["rsvg-convert", "-w", str(wpx), "-h", str(hpx)], input=svg.encode(),
                         check=True, capture_output=True).stdout
    cover = np.asarray(Image.open(BytesIO(png)).convert("RGBA").getchannel("A"), dtype=np.float32) / 255
    if cover[-2:].max() > 0 or cover[:, -2:].max() > 0:
        plan.die("the « MyWeli Pro » unit does not fit the box it was rendered in")
    rows = np.nonzero(cover.max(axis=1) > 0.5)[0]
    cols = np.nonzero(cover.max(axis=0) > 0.5)[0]
    ink = (float(cols.min() - pad_px), float(rows.min() - pad_px),
           float(cols.max() + 1 - pad_px), float(rows.max() + 1 - pad_px))
    return cover, (pad_px, pad_px), ink


def unit_cap_height(width_px: int) -> float:
    _, (x0, y0, x1, y1) = unit_svg()
    return (y1 - y0) * width_px / (x1 - x0)
