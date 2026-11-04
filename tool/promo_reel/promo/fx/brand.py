"""What the FX primitives take from the design system, read from where it lives.

  colours  mobile/lib/core/theme/colors.dart — every app token by name (the
           regex is the App Store stills' own, tool/app_store_screenshots/
           compose.py `tokens()`), plus the brand book's two pattern greys,
           which have no app token and are quoted here with their source.
  type     tool/app_store_screenshots/fonts — Poppins Medium (the only
           Poppins weight in the repo: every headline, caption and counter)
           and Inter (variable; small text, labels, credits).
  the mark mobile/assets/brand/myweli_mark_black.svg — ONE closed polyline
           drawn with ONE round-cap, round-join stroke. Its geometry is parsed
           from the file, never retyped: the brand pattern draws it, and the
           strikes borrow its weight (stroke ÷ outer height) and its cap.
  motion   mobile/lib/core/theme/motion.dart, through the App Preview's
           tool/app_store_preview/brand.py (imported read-only, by path).

Colours are returned as skia ARGB ints (0xAARRGGBB), the type skia.Paint
takes; `rgb()` gives the (r, g, b) tuple for numpy work.
"""

from __future__ import annotations

import importlib.util
import re
import sys
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path

import skia

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]                      # fx → promo → promo_reel → tool → repo
COLORS_DART = ROOT / "mobile/lib/core/theme/colors.dart"
MARK_SVG = ROOT / "mobile/assets/brand/myweli_mark_black.svg"
FONTS = ROOT / "tool/app_store_screenshots/fonts"
POPPINS_MEDIUM = FONTS / "Poppins-Medium.ttf"
INTER_VARIABLE = FONTS / "Inter-Variable.ttf"
PREVIEW_BRAND = ROOT / "tool/app_store_preview/brand.py"

FPS = 30


class BrandError(RuntimeError):
    """A design-system file is missing or no longer says what FX relies on."""


# ---- colours -----------------------------------------------------------------

@lru_cache(maxsize=None)
def _colors_source() -> str:
    if not COLORS_DART.is_file():
        raise BrandError(f"colour tokens not found: {COLORS_DART}")
    return COLORS_DART.read_text(encoding="utf-8")


@lru_cache(maxsize=None)
def token(name: str) -> int:
    """The app colour token `name` (AppColors.<name>) as a skia ARGB int.

    Raises BrandError when the token is missing or not opaque: every FX use
    of a token is an opaque ink or ground."""
    m = re.search(rf"static const Color {re.escape(name)} = Color\(\s*0x([0-9A-Fa-f]{{8}})", _colors_source())
    if not m:
        raise BrandError(f"colour token `{name}` not found in {COLORS_DART}")
    argb = int(m.group(1), 16)
    if argb >> 24 != 0xFF:
        raise BrandError(f"colour token `{name}` is not opaque ({m.group(1)})")
    return argb


def rgb(colour: int) -> tuple[int, int, int]:
    """(r, g, b) of a skia ARGB int."""
    return (colour >> 16) & 0xFF, (colour >> 8) & 0xFF, colour & 0xFF


def with_alpha(colour: int, alpha: float) -> int:
    """`colour` with its alpha replaced by `alpha` (0..1)."""
    a = max(0, min(255, round(alpha * 255)))
    return (a << 24) | (colour & 0x00FFFFFF)


class Palette:
    """The film's named colours. App tokens resolve from colors.dart on first
    use; the brand-book values are constants with their source quoted.

      INK            textPrimary  #1A1A1A — every caption on paper
      INK_SECONDARY  textSecondary #4A4A4A — the counter's label
      INK_TERTIARY   textTertiary #6E6E6E — the map credit
      PAPER          surface      #FAFAFA — the light stage
      BLACK          primary      #000000 — the dark stage, touch on light ground
      WHITE          secondary    #FFFFFF — hook type, touch on dark ground
      BORDER         border       #D0D0D0 — the lift card's 1-px outline
      PATTERN_ON_BLACK  #1E1E1E — brand book (Identity p.13 / Brandbook p.22),
                        the dark pattern's marks
      PATTERN_ON_PAPER  #EDEEEF — brand book, the light pattern's marks
    """

    PATTERN_ON_BLACK = 0xFF1E1E1E
    PATTERN_ON_PAPER = 0xFFEDEEEF

    @property
    def INK(self) -> int: return token("textPrimary")
    @property
    def INK_SECONDARY(self) -> int: return token("textSecondary")
    @property
    def INK_TERTIARY(self) -> int: return token("textTertiary")
    @property
    def PAPER(self) -> int: return token("surface")
    @property
    def BLACK(self) -> int: return token("primary")
    @property
    def WHITE(self) -> int: return token("secondary")
    @property
    def BORDER(self) -> int: return token("border")


PALETTE = Palette()


# ---- type --------------------------------------------------------------------

def _tag(s: str) -> int:
    return int.from_bytes(s.encode("ascii"), "big")


@lru_cache(maxsize=None)
def _typeface(path: str) -> skia.Typeface:
    tf = skia.Typeface.MakeFromFile(path)
    if tf is None:
        raise BrandError(f"font not loadable: {path}")
    return tf


@lru_cache(maxsize=None)
def _inter_typeface(weight: float, opsz: float) -> skia.Typeface:
    C = skia.FontArguments.VariationPosition.Coordinate
    coords = skia.FontArguments.VariationPosition.Coordinates([C(_tag("wght"), float(weight)),
                                                               C(_tag("opsz"), float(opsz))])
    args = skia.FontArguments()
    args.setVariationDesignPosition(skia.FontArguments.VariationPosition(coords))
    return _typeface(str(INTER_VARIABLE)).makeClone(args)


def _film_font(tf: skia.Typeface, px: float) -> skia.Font:
    """A font set up for moving type: no hinting and sub-pixel positions, so a
    word rising 24 px glides instead of stepping from pixel to pixel; linear
    metrics, so a measured width scales exactly with the size."""
    f = skia.Font(tf, float(px))
    f.setEdging(skia.Font.Edging.kAntiAlias)
    f.setHinting(skia.FontHinting.kNone)
    f.setSubpixel(True)
    f.setLinearMetrics(True)
    f.setBaselineSnap(False)
    return f


def poppins(px: float) -> skia.Font:
    """Poppins Medium at `px` — headlines, captions, the counter's figure."""
    return _film_font(_typeface(str(POPPINS_MEDIUM)), px)


def inter(px: float, weight: float = 500, opsz: float | None = None) -> skia.Font:
    """Inter at `px`, weight `weight` (500 = Medium). The optical-size axis
    follows the size as CSS `font-optical-sizing: auto` does (opsz = px,
    clamped to the font's 14–32), unless `opsz` is given."""
    if opsz is None:
        opsz = min(32.0, max(14.0, float(px)))
    return _film_font(_inter_typeface(float(weight), float(opsz)), px)


# ---- the mark ------------------------------------------------------------------

@dataclass(frozen=True)
class MarkGeometry:
    """The mark as its SVG draws it, in the SVG's own units."""

    points: tuple[tuple[float, float], ...]   # the closed polyline, in drawing order
    stroke: float                             # stroke-width
    outer: tuple[float, float, float, float]  # (x0, y0, x1, y1) of the ink, stroke included

    @property
    def outer_height(self) -> float:
        return self.outer[3] - self.outer[1]

    @property
    def outer_width(self) -> float:
        return self.outer[2] - self.outer[0]

    @property
    def weight(self) -> float:
        """The mark's single weight: stroke ÷ outer height (≈ 0.111)."""
        return self.stroke / self.outer_height


@lru_cache(maxsize=None)
def mark_geometry() -> MarkGeometry:
    if not MARK_SVG.is_file():
        raise BrandError(f"mark not found: {MARK_SVG}")
    svg = MARK_SVG.read_text(encoding="utf-8")
    d = re.search(r'\bd="([^"]+)"', svg)
    w = re.search(r'stroke-width="([0-9.]+)"', svg)
    if not d or not w:
        raise BrandError(f"{MARK_SVG} is no longer one stroked path")
    if 'stroke-linecap="round"' not in svg or 'stroke-linejoin="round"' not in svg:
        raise BrandError(f"{MARK_SVG}: the mark's stroke is no longer round-capped and round-joined")
    tokens = re.findall(r"[MLZ]|-?[0-9.]+", d.group(1))
    pts: list[tuple[float, float]] = []
    i = 0
    while i < len(tokens):
        t = tokens[i]
        if t in ("M", "L"):
            pts.append((float(tokens[i + 1]), float(tokens[i + 2])))
            i += 3
        elif t == "Z":
            i += 1
        else:
            raise BrandError(f"{MARK_SVG}: unexpected path command near `{t}`")
    stroke = float(w.group(1))
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    h = stroke / 2
    return MarkGeometry(tuple(pts), stroke, (min(xs) - h, min(ys) - h, max(xs) + h, max(ys) + h))


def mark_path(height: float, centre: tuple[float, float] = (0.0, 0.0)) -> tuple[skia.Path, float]:
    """The mark as a skia path whose INK (stroke included) is `height` px tall,
    centred on `centre`; and the stroke width to draw it with (round cap and
    join, as the SVG)."""
    g = mark_geometry()
    k = height / g.outer_height
    cx, cy = (g.outer[0] + g.outer[2]) / 2, (g.outer[1] + g.outer[3]) / 2
    path = skia.Path()
    for i, (x, y) in enumerate(g.points):
        X, Y = centre[0] + (x - cx) * k, centre[1] + (y - cy) * k
        path.moveTo(X, Y) if i == 0 else path.lineTo(X, Y)
    path.close()
    return path, g.stroke * k


def mark_paint(colour: int, stroke: float) -> skia.Paint:
    """The mark's stroke: one weight, round cap, round join."""
    p = skia.Paint(AntiAlias=True, Color=colour, Style=skia.Paint.kStroke_Style, StrokeWidth=stroke)
    p.setStrokeCap(skia.Paint.kRound_Cap)
    p.setStrokeJoin(skia.Paint.kRound_Join)
    return p


# ---- motion ------------------------------------------------------------------------

@lru_cache(maxsize=None)
def preview_brand():
    """tool/app_store_preview/brand.py, imported read-only by path under a
    private name (it in turn loads the stills' compose.py)."""
    if not PREVIEW_BRAND.is_file():
        raise BrandError(f"not found: {PREVIEW_BRAND}")
    name = "promo_fx_app_store_preview_brand"
    spec = importlib.util.spec_from_file_location(name, PREVIEW_BRAND)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


@dataclass(frozen=True)
class MotionToken:
    """One AppMotion token at the film's frame rate."""

    name: str
    ms: int
    curve: str          # Flutter curve name, a key of easing.CURVES

    @property
    def frames(self) -> int:
        n = self.ms * FPS
        if n % 1000:
            raise BrandError(f"motion token `{self.name}` ({self.ms} ms) is not whole frames at {FPS} fps")
        return n // 1000


@lru_cache(maxsize=None)
def motion_tokens() -> dict[str, MotionToken]:
    """fast 3 f · base 6 f · emphasis 9 f · slow 12 f, each with its curve."""
    toks = preview_brand().motion_tokens()
    return {name: MotionToken(name, t.ms, t.curve) for name, t in toks.items()}
