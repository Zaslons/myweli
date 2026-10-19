"""UI lift: a real region of a real picture rises out of the phone as a
magnified card — the same pixels, resampled, nothing redrawn.

The card: the region `src` of the picture (capture px) drawn into a rounded
rectangle that travels from where the region sits on the phone (`origin`,
frame px) to where it is shown big (`target`); the app's card corner
(AppTheme.radiusLarge, 12 pt) scaled with it; a 1-px outline in `border`
(#D0D0D0); and the stills' card shadow (compose.py, at 1080: opacity 0.10,
blur 37, dy 25 — blur as CSS, sigma = blur / 2), whose strength grows with
the lift, so the card visibly leaves the surface.

The veil: behind the card the phone recedes under paper at 55 %
(`draw_veil`), as the card rises. Draw order for a scene: stage, phone,
veil, card(s), captions.

Timing (storyboard): z-pop over 6 frames on easeOutCubic; the settle-back
accelerates (easeIn, 5 frames). `pop_progress()` gives that envelope.

Resampling: when the frame maps straight to pixels the card is resampled
with Lanczos from a fractional box (surface.draw_exact) at every size of
the pop — what the App Store stills did — else skia's cubic.
"""

from __future__ import annotations

from dataclasses import dataclass

import skia

from . import easing
from .brand import PALETTE
from .surface import Picture, Rect, draw_exact, skrect

CARD_SHADOW: tuple[tuple[float, float, float], ...] = ((0.10, 37.0, 25.0),)


@dataclass(frozen=True)
class LiftStyle:
    radius_src: float = 36.0                 # corner in SOURCE px: 12 pt × 3 px/pt (AppTheme.radiusLarge)
    outline: float = 1.0                     # px
    outline_colour: int | None = None        # default: AppColors.border
    shadows: tuple[tuple[float, float, float], ...] = CARD_SHADOW
    veil_opacity: float = 0.55
    veil_colour: int | None = None           # default: AppColors.surface (paper)


STYLE = LiftStyle()


def pop_progress(t: float, up: float, frames: float = 6.0, down: float | None = None,
                 down_frames: float = 5.0) -> float:
    """0 → 1 from frame `up` over `frames` (easeOutCubic); back to 0 from
    `down` over `down_frames`, accelerating (easeIn). The cue frame already
    shows the first step."""
    p = easing.EASE_OUT_CUBIC(easing.progress(t, up - 1, frames))
    if down is not None and t >= down:
        p *= 1.0 - easing.EASE_IN(easing.progress(t, down, down_frames))
    return p


def lerp_rect(a: Rect, b: Rect, t: float) -> Rect:
    return tuple(easing.lerp(x, y, t) for x, y in zip(a, b))       # type: ignore[return-value]


def fit_width(src: Rect, x0: float, x1: float, *, top: float | None = None, centre_y: float | None = None,
              bottom: float | None = None) -> Rect:
    """The rect `src` scaled to span x0..x1, placed by its top, centre or bottom."""
    w = x1 - x0
    h = w * (src[3] - src[1]) / (src[2] - src[0])
    if top is not None:
        y0 = top
    elif centre_y is not None:
        y0 = centre_y - h / 2
    elif bottom is not None:
        y0 = bottom - h
    else:
        raise ValueError("fit_width: give top, centre_y or bottom")
    return (x0, y0, x1, y0 + h)


def draw_veil(canvas: skia.Canvas, rect: Rect, amount: float, style: LiftStyle = STYLE) -> None:
    """Paper over `rect` at 55 % × amount (0..1): the phone recedes."""
    if amount <= 0:
        return
    p = skia.Paint(Color=style.veil_colour if style.veil_colour is not None else PALETTE.PAPER)
    p.setAlphaf(style.veil_opacity * min(1.0, amount))
    canvas.drawRect(skrect(rect), p)


def draw_card(canvas: skia.Canvas, picture: Picture, src: Rect, dst: Rect, *, lift: float = 1.0,
              alpha: float = 1.0, style: LiftStyle = STYLE) -> None:
    """The region `src` of `picture` as a card filling `dst`, its shadow at
    `lift` (0 = flat on the phone, 1 = fully lifted) strength."""
    if alpha <= 0:
        return
    k = (dst[2] - dst[0]) / (src[2] - src[0])
    r = style.radius_src * k
    rr = skia.RRect.MakeRectXY(skrect(dst), r, r)
    group = alpha < 1.0
    if group:
        p = skia.Paint()
        p.setAlphaf(alpha)
        canvas.saveLayer(None, p)
    for opacity, blur, dy in style.shadows:
        if lift <= 0:
            break
        sp = skia.Paint(AntiAlias=True, Color=PALETTE.BLACK)
        sp.setAlphaf(opacity * min(1.0, lift))
        sp.setMaskFilter(skia.MaskFilter.MakeBlur(skia.kNormal_BlurStyle, max(0.01, blur / 2 * lift)))
        canvas.save()
        canvas.translate(0, dy * lift)
        canvas.drawRRect(rr, sp)
        canvas.restore()
    canvas.save()
    canvas.clipRRect(rr, skia.ClipOp.kIntersect, True)
    draw_exact(canvas, picture, src, dst)
    canvas.restore()
    if style.outline > 0:
        inset = style.outline / 2
        ring = skia.RRect.MakeRectXY(skrect((dst[0] + inset, dst[1] + inset, dst[2] - inset, dst[3] - inset)),
                                     max(0.0, r - inset), max(0.0, r - inset))
        colour = style.outline_colour if style.outline_colour is not None else PALETTE.BORDER
        canvas.drawRRect(ring, skia.Paint(AntiAlias=True, Color=colour, Style=skia.Paint.kStroke_Style,
                                          StrokeWidth=style.outline))
    if group:
        canvas.restore()


class Lift:
    """One lifted card: `src` of `picture` (capture px) travels from `origin`
    (where it sits on the phone, frame px) to `target`."""

    def __init__(self, picture, src: Rect, origin: Rect, target: Rect, style: LiftStyle = STYLE):
        self.picture = picture if isinstance(picture, Picture) else Picture(picture)
        self.src, self.origin, self.target, self.style = src, origin, target, style

    def rect(self, p: float) -> Rect:
        return lerp_rect(self.origin, self.target, p)

    def draw(self, canvas: skia.Canvas, p: float, *, veil_rect: Rect | None = None, alpha: float = 1.0) -> None:
        """At lift progress p (0..1; see `pop_progress`). With `veil_rect`,
        the veil is drawn first, at the same progress."""
        if p <= 0:
            return
        if veil_rect is not None:
            draw_veil(canvas, veil_rect, p, self.style)
        draw_card(canvas, self.picture, self.src, self.rect(p), lift=p, alpha=alpha, style=self.style)
