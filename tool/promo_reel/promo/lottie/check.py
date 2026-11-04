"""Acceptance: our render against the app's own Flutter goldens, and a filmstrip.

The goldens (mobile/test/golden/pro_splash_golden_test.dart) photograph the
Pro splash on Flutter's test surface at the two frames that carry meaning:

* ``pro_splash_wordmark`` — reduced motion's still: the middle of the
  ``wordmark`` marker, controller (12 + 38) / 2 / 142 → comp 25 (drawn 24.998);
* ``pro_splash_end`` — the end of the first pass, controller 1.0 → comp 142
  (drawn 141.990, the finished mark).

The surface is reproduced exactly: 390 × 844 logical px at 1.0 device pixel
ratio (test/support/golden.dart:68, surface.dart:37-38), ``AppColors.surface``
#FAFAFA (core/theme/colors.dart:35), the Lottie 220 px wide
(``SplashScreen.animationWidth``, splash/splash_screen.dart:33) at its
aspect ratio and centred (pro_splash_screen.dart:201-219).

Goldens are Flutter renders on Linux: anti-aliasing differs at the edges, so
we report error statistics and the overlap of the ink masks, not equality.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Sequence

import numpy as np
import skia

from . import REPO
from .player import Player

GOLDENS_DIR = REPO / 'mobile' / 'test' / 'golden' / 'goldens'
GOLDEN_SURFACE = (390, 844)  # kGoldenPhone, device pixel ratio 1.0
GOLDEN_BACKGROUND = 0xFFFAFAFA  # AppColors.surface
SPLASH_WIDTH = 220.0  # SplashScreen.animationWidth
INK = 17  # #111111, the file's colour (0.0667 × 255, truncated to a byte)
FONT = REPO / 'tool' / 'app_store_screenshots' / 'fonts' / 'Inter-Variable.ttf'


@dataclass(frozen=True)
class GoldenCase:
    name: str
    comp_frame: float  # the frame the golden names
    controller_value: float  # what the golden test's controller holds


def golden_cases(player: Player) -> tuple[GoldenCase, ...]:
    """The two goldens, with the controller values the golden test reaches."""
    start, end = player.markers['wordmark']
    first, last = player.frames
    duration = last - first
    middle = (start + end) / 2.0
    return (
        GoldenCase('pro_splash_wordmark', middle, (middle - first) / duration),
        GoldenCase('pro_splash_end', last, 1.0),
    )


def golden_dst_rect(player: Player) -> skia.Rect:
    """Where the app lays the Lottie out on the golden surface."""
    width, height = GOLDEN_SURFACE
    return player.dst_rect((width / 2.0, height / 2.0), SPLASH_WIDTH)


def render_surface(
    player: Player,
    comp_frame: float,
    size: Sequence[int] = GOLDEN_SURFACE,
    background: int = GOLDEN_BACKGROUND,
    dst_rect: skia.Rect | None = None,
    color: int | str | None = None,
) -> np.ndarray:
    """Render one frame on a plain background; returns an RGBA ``uint8`` array (H, W, 4)."""
    width, height = (int(v) for v in size)
    surface = skia.Surface(width, height)
    canvas = surface.getCanvas()
    canvas.clear(background)
    player.render(canvas, comp_frame, dst_rect or golden_dst_rect(player), color)
    image = surface.makeImageSnapshot()
    return image.toarray(colorType=skia.kRGBA_8888_ColorType, alphaType=skia.kUnpremul_AlphaType)


def load_png(path: str | Path) -> np.ndarray:
    """A PNG as an RGBA ``uint8`` array."""
    image = skia.Image.open(str(path))
    return image.toarray(colorType=skia.kRGBA_8888_ColorType, alphaType=skia.kUnpremul_AlphaType)


def save_png(array: np.ndarray, path: str | Path) -> None:
    """Write an RGBA (or RGB / grey) ``uint8`` array as PNG."""
    array = np.ascontiguousarray(array)
    if array.ndim == 2:
        array = np.repeat(array[..., None], 3, axis=2)
    if array.shape[2] == 3:
        alpha = np.full(array.shape[:2] + (1,), 255, np.uint8)
        array = np.concatenate([array, alpha], axis=2)
    image = skia.Image.fromarray(
        np.ascontiguousarray(array, dtype=np.uint8), colorType=skia.kRGBA_8888_ColorType
    )
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    image.save(str(path), skia.kPNG)


def coverage(rgba: np.ndarray, background: int = 250, ink: int = INK) -> np.ndarray:
    """Per-pixel ink coverage in [0, 1] of a grey-on-paper picture."""
    grey = rgba[..., :3].astype(np.float64).mean(axis=2)
    return np.clip((background - grey) / (background - ink), 0.0, 1.0)


@dataclass(frozen=True)
class Comparison:
    """How far our render is from a golden. Errors are in 8-bit levels (0–255)."""

    mean_abs_error: float  # over the whole surface
    roi_mean_abs_error: float  # over the ink's bounding box (both pictures, +2 px)
    max_abs_error: int
    iou: float  # ink masks (coverage ≥ 0.5): intersection / union
    soft_iou: float  # Σ min(coverage) / Σ max(coverage)
    ink_ratio: float  # our ink mass / the golden's
    centroid_shift: tuple[float, float]  # (dx, dy) px, ours − golden
    bbox_ours: tuple[int, int, int, int]  # x0, y0, x1, y1 (inclusive), coverage ≥ 0.5
    bbox_golden: tuple[int, int, int, int]
    pixels_off_by_more_than_64: int

    def as_dict(self) -> dict:
        return asdict(self)


def _bbox(mask: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.nonzero(mask)
    if not len(xs):
        return (0, 0, -1, -1)
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def compare(ours: np.ndarray, golden: np.ndarray) -> Comparison:
    """Compare two same-size RGBA pictures of grey ink on #FAFAFA."""
    if ours.shape != golden.shape:
        raise ValueError(f'size mismatch: ours {ours.shape}, golden {golden.shape}')
    diff = np.abs(ours[..., :3].astype(np.int16) - golden[..., :3].astype(np.int16))
    cov_ours, cov_golden = coverage(ours), coverage(golden)
    mask_ours, mask_golden = cov_ours >= 0.5, cov_golden >= 0.5
    union = np.logical_or(mask_ours, mask_golden).sum()
    inter = np.logical_and(mask_ours, mask_golden).sum()
    any_ink = (cov_ours > 0) | (cov_golden > 0)
    x0, y0, x1, y1 = _bbox(any_ink)
    height, width = ours.shape[:2]
    roi = diff[max(y0 - 2, 0) : min(y1 + 3, height), max(x0 - 2, 0) : min(x1 + 3, width)]
    ys, xs = np.mgrid[0:height, 0:width]

    def centroid(cov: np.ndarray) -> tuple[float, float]:
        mass = cov.sum()
        return float((xs * cov).sum() / mass), float((ys * cov).sum() / mass)

    (ox, oy), (gx, gy) = centroid(cov_ours), centroid(cov_golden)
    return Comparison(
        mean_abs_error=float(diff.mean()),
        roi_mean_abs_error=float(roi.mean()) if roi.size else 0.0,
        max_abs_error=int(diff.max()),
        iou=float(inter / union) if union else 1.0,
        soft_iou=float(np.minimum(cov_ours, cov_golden).sum() / np.maximum(cov_ours, cov_golden).sum()),
        ink_ratio=float(cov_ours.sum() / cov_golden.sum()),
        centroid_shift=(ox - gx, oy - gy),
        bbox_ours=_bbox(mask_ours),
        bbox_golden=_bbox(mask_golden),
        pixels_off_by_more_than_64=int((diff.max(axis=2) > 64).sum()),
    )


def diff_sheet(ours: np.ndarray, golden: np.ndarray, zoom: int = 4, pad: int = 12) -> np.ndarray:
    """golden | ours | |difference| × 4, cropped to the ink and magnified, for looking at."""
    any_ink = (coverage(ours) > 0) | (coverage(golden) > 0)
    x0, y0, x1, y1 = _bbox(any_ink)
    height, width = ours.shape[:2]
    box = (slice(max(y0 - pad, 0), min(y1 + pad + 1, height)), slice(max(x0 - pad, 0), min(x1 + pad + 1, width)))
    g = golden[box][..., :3]
    o = ours[box][..., :3]
    d = np.abs(o.astype(np.int16) - g.astype(np.int16)).max(axis=2)
    d = 255 - np.clip(d * 4, 0, 255).astype(np.uint8)
    d = np.repeat(d[..., None], 3, axis=2)
    gap = np.full((g.shape[0], 4, 3), 200, np.uint8)
    sheet = np.concatenate([g, gap, o, gap, d], axis=1)
    return np.kron(sheet, np.ones((zoom, zoom, 1), np.uint8))


def acceptance(player: Player, goldens_dir: Path = GOLDENS_DIR) -> dict[str, tuple[GoldenCase, float, Comparison]]:
    """Render each golden's frame as the app draws it and compare.

    Returns ``{name: (case, drawn comp time, comparison)}``.
    """
    results = {}
    for case in golden_cases(player):
        drawn = player.device_frame(case.controller_value)
        ours = render_surface(player, drawn)
        golden = load_png(Path(goldens_dir) / f'{case.name}.png')
        results[case.name] = (case, drawn, compare(ours, golden))
    return results


def _label(canvas: skia.Canvas, text: str, x: float, y: float, size: float = 18.0) -> None:
    typeface = skia.Typeface.MakeFromFile(str(FONT)) if FONT.exists() else skia.Typeface()
    font = skia.Font(typeface, size)
    paint = skia.Paint(AntiAlias=True, Color=0xFF6B6B6B)
    canvas.drawString(text, x, y, font, paint)


def filmstrip(
    player: Player,
    frames: Sequence[float],
    cell_width: int = 360,
    columns: int = 4,
    background: int = GOLDEN_BACKGROUND,
) -> np.ndarray:
    """A grid of frames, each labelled with its composition frame; RGBA ``uint8``."""
    comp_w, comp_h = player.size
    cell_h = int(round(cell_width * comp_h / comp_w))
    label_h = 30
    rows = (len(frames) + columns - 1) // columns
    surface = skia.Surface(columns * cell_width, rows * (cell_h + label_h))
    canvas = surface.getCanvas()
    canvas.clear(background)
    rule = skia.Paint(Color=0xFFE2E2E2, StrokeWidth=1, Style=skia.Paint.kStroke_Style)
    for n, frame in enumerate(frames):
        col, row = n % columns, n // columns
        left, top = col * cell_width, row * (cell_h + label_h)
        canvas.drawRect(skia.Rect.MakeXYWH(left + 0.5, top + 0.5, cell_width - 1, cell_h + label_h - 1), rule)
        player.render(canvas, frame, skia.Rect.MakeXYWH(left, top + label_h, cell_width, cell_h))
        _label(canvas, f'comp {frame:g}', left + 10, top + 22)
    image = surface.makeImageSnapshot()
    return image.toarray(colorType=skia.kRGBA_8888_ColorType, alphaType=skia.kUnpremul_AlphaType)
