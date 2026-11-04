"""Small skia plumbing shared by the primitives: RGBA surfaces, images to and
from numpy, sampling choices, layer and paint helpers.

Every surface FX makes is RGBA_8888 premultiplied with no colour space
attached: values are sRGB-encoded bytes, drawn and blended as skia does by
default (in the encoded space). The one place light is averaged linearly is
blur.py, which converts explicitly.
"""

from __future__ import annotations

from contextlib import contextmanager
from pathlib import Path
from typing import Iterator, Union

import numpy as np
import skia

RGBA = skia.ColorType.kRGBA_8888_ColorType
Rect = tuple[float, float, float, float]          # (x0, y0, x1, y1)

# Through a perspective matrix (the exact Lanczos path, `draw_exact`, needs a
# plain scale + move). Measured on the agenda capture shown at 1.791 px/pt
# against a Lanczos-3 reference: Mitchell keeps 88 % of its edge contrast,
# trilinear mipmaps 84 % (soft), Catmull-Rom 91 % but rings (p99 error 22 vs
# 17 levels). Mitchell down to half size; mipmaps below, where a fixed-size
# kernel would alias.
SAMPLING_CUBIC = skia.SamplingOptions(skia.CubicResampler.Mitchell())
SAMPLING_MIPMAP = skia.SamplingOptions(skia.FilterMode.kLinear, skia.MipmapMode.kLinear)


def new_surface(width: int, height: int) -> skia.Surface:
    """A transparent RGBA_8888 premultiplied raster surface."""
    info = skia.ImageInfo.Make(int(width), int(height), RGBA, skia.AlphaType.kPremul_AlphaType)
    s = skia.Surface.MakeRaster(info)
    if s is None:
        raise RuntimeError(f"could not allocate a {width}×{height} surface")
    s.getCanvas().clear(skia.ColorTRANSPARENT)
    return s


def to_array(src: Union[skia.Surface, skia.Image], premultiplied: bool = False) -> np.ndarray:
    """(h, w, 4) uint8 RGBA of a surface or image (unpremultiplied unless
    asked; identical for an opaque frame)."""
    image = src.makeImageSnapshot() if isinstance(src, skia.Surface) else src
    at = skia.AlphaType.kPremul_AlphaType if premultiplied else skia.AlphaType.kUnpremul_AlphaType
    return image.toarray(colorType=RGBA, alphaType=at)


def image_from_array(array: np.ndarray, premultiplied: bool = False) -> skia.Image:
    """A skia image of an (h, w, 3|4) uint8 array (RGB is made opaque)."""
    a = np.asarray(array)
    if a.dtype != np.uint8 or a.ndim != 3 or a.shape[2] not in (3, 4):
        raise ValueError(f"expected an (h, w, 3|4) uint8 array, got {a.dtype} {a.shape}")
    if a.shape[2] == 3:
        a = np.concatenate([a, np.full(a.shape[:2] + (1,), 255, np.uint8)], axis=2)
    at = skia.AlphaType.kPremul_AlphaType if premultiplied else skia.AlphaType.kUnpremul_AlphaType
    return skia.Image.fromarray(np.ascontiguousarray(a), colorType=RGBA, alphaType=at)


def as_image(src) -> skia.Image:
    """Accepts a skia.Image, an (h, w, 3|4) uint8 array, a PIL image or a
    path, and returns a skia.Image."""
    if isinstance(src, skia.Image):
        return src
    if isinstance(src, (str, Path)):
        from PIL import Image
        with Image.open(src) as im:
            return image_from_array(np.asarray(im.convert("RGBA")))
    if isinstance(src, np.ndarray):
        return image_from_array(src)
    if hasattr(src, "convert"):            # PIL.Image.Image
        return image_from_array(np.asarray(src.convert("RGBA")))
    raise TypeError(f"cannot make an image of {type(src).__name__}")


def save_png(src, path: Union[str, Path]) -> Path:
    """Writes a surface, image or array as an RGBA PNG."""
    from PIL import Image
    if isinstance(src, (skia.Surface, skia.Image)):
        src = to_array(src)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.asarray(src)).save(path)
    return path


def sampling_for(scale: float) -> skia.SamplingOptions:
    """The resampler for an image drawn at `scale` (destination ÷ source px)."""
    return SAMPLING_CUBIC if scale >= 0.5 else SAMPLING_MIPMAP


class Picture:
    """A real picture (a capture, a take's frame) held for exact resampling:
    as a skia.Image (with mipmaps) for any projective draw, and as an
    edge-padded PIL image for `draw_exact`, the Lanczos path used whenever
    the draw is a plain scale + move — the App Store film's own resampler
    (tool/app_store_preview/frames.py), sampled from a FRACTIONAL source box
    so a camera glide lands on the sub-pixel without a soft frame."""

    PAD = 8

    def __init__(self, src):
        from PIL import Image
        self.image = as_image(src).withDefaultMipmaps()
        rgba = to_array(self.image)
        self.width, self.height = rgba.shape[1], rgba.shape[0]
        padded = np.pad(rgba, ((self.PAD, self.PAD), (self.PAD, self.PAD), (0, 0)), mode="edge")
        self._pil = Image.fromarray(padded, "RGBA")
        self.opaque = bool((rgba[..., 3] == 255).all())

    def lanczos(self, box: Rect, size: tuple[int, int]):
        """The source box (fractional, in source px; may reach PAD px past the
        edges) resampled to `size` with Lanczos-3."""
        from PIL import Image
        P = self.PAD
        x0, y0, x1, y1 = box
        if x0 < -P or y0 < -P or x1 > self.width + P or y1 > self.height + P:
            raise ValueError(f"source box {box} reaches past the picture's padding")
        im = self._pil.resize(size, Image.LANCZOS, box=(x0 + P, y0 + P, x1 + P, y1 + P))
        return image_from_array(np.asarray(im))


def _integer_translation(m: skia.Matrix) -> tuple[int, int] | None:
    """(tx, ty) when `m` only moves by whole pixels, else None."""
    v = [m.get(i) for i in range(9)]
    eps = 1e-6
    if (abs(v[0] - 1) > eps or abs(v[4] - 1) > eps or abs(v[1]) > eps or abs(v[3]) > eps
            or abs(v[6]) > eps or abs(v[7]) > eps or abs(v[8] - 1) > eps):
        return None
    tx, ty = v[2], v[5]
    if abs(tx - round(tx)) > 1e-4 or abs(ty - round(ty)) > 1e-4:
        return None
    return round(tx), round(ty)


def draw_exact(canvas: skia.Canvas, pic: Picture, src: Rect, dst: Rect,
               fallback: skia.SamplingOptions | None = None, paint: skia.Paint | None = None) -> None:
    """Draw the `src` box of a picture into `dst` (frame px, fractional).

    When the canvas maps straight to pixels (identity or an integer move),
    the destination's covering pixels are resampled from the matching
    fractional source box with Lanczos-3 and blitted 1:1 — the sharpest
    honest resampling, identical at every sub-pixel position. Otherwise
    (a pose, a punch's scale) skia resamples through the matrix with
    `fallback` (default: by scale). Pixels the destination only partly
    covers are drawn whole: the caller's clip (a rounded rect) trims them."""
    sx = (src[2] - src[0]) / (dst[2] - dst[0])
    sy = (src[3] - src[1]) / (dst[3] - dst[1])
    t = _integer_translation(canvas.getTotalMatrix())
    if t is None:
        canvas.drawImageRect(pic.image, skrect(src), skrect(dst),
                             fallback or sampling_for(1.0 / max(sx, sy)), paint,
                             skia.Canvas.kFast_SrcRectConstraint)
        return
    tx, ty = t
    clip = canvas.getDeviceClipBounds()
    X0 = max(int(np.floor(dst[0] + tx)), clip.left())
    Y0 = max(int(np.floor(dst[1] + ty)), clip.top())
    X1 = min(int(np.ceil(dst[2] + tx)), clip.right())
    Y1 = min(int(np.ceil(dst[3] + ty)), clip.bottom())
    if X1 <= X0 or Y1 <= Y0:
        return
    box = (src[0] + (X0 - tx - dst[0]) * sx, src[1] + (Y0 - ty - dst[1]) * sy,
           src[0] + (X1 - tx - dst[0]) * sx, src[1] + (Y1 - ty - dst[1]) * sy)
    tile = pic.lanczos(box, (X1 - X0, Y1 - Y0))
    canvas.drawImage(tile, X0 - tx, Y0 - ty, skia.SamplingOptions(), paint)


def skrect(r: Rect) -> skia.Rect:
    return skia.Rect.MakeLTRB(*map(float, r))


def fill_paint(colour: int, alpha: float = 1.0) -> skia.Paint:
    p = skia.Paint(AntiAlias=True, Color=colour)
    if alpha < 1.0:
        p.setAlphaf(max(0.0, alpha) * p.getAlphaf())
    return p


@contextmanager
def layer(canvas: skia.Canvas, alpha: float = 1.0, bounds: Rect | None = None) -> Iterator[skia.Canvas]:
    """Draw a group as one layer and composite it at `alpha` — so overlapping
    parts of the group never show through one another when it fades."""
    paint = None
    if alpha < 1.0:
        paint = skia.Paint()
        paint.setAlphaf(max(0.0, alpha))
    canvas.saveLayer(skrect(bounds) if bounds else None, paint)
    try:
        yield canvas
    finally:
        canvas.restore()


@contextmanager
def saved(canvas: skia.Canvas) -> Iterator[skia.Canvas]:
    """canvas.save() … canvas.restore() as a context."""
    canvas.save()
    try:
        yield canvas
    finally:
        canvas.restore()


@contextmanager
def scaled_about(canvas: skia.Canvas, scale: float, cx: float, cy: float) -> Iterator[skia.Canvas]:
    """Scale everything drawn inside about (cx, cy) — a punch, a push-in.
    At scale 1 the matrix is left untouched (a translate there and back can
    leave a 1e-13 residue that moves glyphs to another sub-pixel bucket)."""
    canvas.save()
    if scale != 1.0:
        canvas.translate(cx, cy)
        canvas.scale(scale, scale)
        canvas.translate(-cx, -cy)
    try:
        yield canvas
    finally:
        canvas.restore()


def vertical_fade(canvas: skia.Canvas, rect: Rect, stops: list[tuple[float, float]]) -> None:
    """Multiply what is already in the current layer by an alpha that varies
    with y: `stops` are (y, alpha) pairs, linear between, clamped outside.
    Used inside a saveLayer to fade a group (the phone under the band)."""
    if not stops:
        return
    ys = [y for y, _ in stops]
    if any(b < a for a, b in zip(ys, ys[1:])):
        raise ValueError(f"fade stops must be sorted by y: {ys}")
    y0, y1 = ys[0], ys[-1]
    span = max(1e-6, y1 - y0)
    colours = [((max(0, min(255, round(a * 255)))) << 24) for _, a in stops]
    positions = [(y - y0) / span for y in ys]
    shader = skia.GradientShader.MakeLinear([skia.Point(0, y0), skia.Point(0, y1)], colours, positions)
    p = skia.Paint(Shader=shader, BlendMode=skia.BlendMode.kDstIn)
    p.setDither(True)
    canvas.drawRect(skrect(rect), p)
