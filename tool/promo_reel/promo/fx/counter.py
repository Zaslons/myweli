"""The counter: an odometer that rolls from the figure the app shows to the
figure the app lands on, and lands on it EXACTLY.

FORMAT. The app's own (mobile/lib/core/utils/formatters.dart:83-93):
NumberFormat('#,##0', 'fr_FR') — groups joined by U+202F — then ONE plain
space and « FCFA »: « 77 000 FCFA ». `type.fcfa()` builds it; Poppins has no
U+202F glyph, so the separator is an advance of half a word space (type.py).

THE ROLL. Each digit column scrolls a strip of digits upward (downward when
counting down) by `steps` digits, all columns on the same curve —
fastOutSlowIn (0.4, 0, 0.2, 1) by default — so they all stop on the same
frame. A column's steps are its TRUE travel (how many times that column
ticks between the two values) while that is small — so the leading digits
count honestly, 0 → 7 — and capped for the fast columns (the units of
0 → 77 000 would tick 77 000 times) to one more lap per place to the right
(at most `max_laps`), so the figure still spins faster toward the units:
0 → 77 000 rolls 7, 17, 20, 30, 40 digits. The cap keeps the travel's value
mod 10, so the strip always ends on the right digit. A rolling digit fades
with its distance from home (opacity 1 − |offset| / pitch), so two digits
passing cross-dissolve as they slide. At progress 1
every column sits on its final digit with no offset, every width is that
digit's advance, and the drawn figure is the typeset string, pixel for
pixel (tests/test_fx.py checks it).

LEADING COLUMNS. A column the start value does not have (0 → 77 000 has one
column, the end five) appears as it rolls its first step: its width and
opacity grow 0 → 1 with it, so « 0 FCFA » widens smoothly into
« 77 000 FCFA » and the figure stays centred. A column the end does not
have leaves the same way on its last step.

The figure scrolls inside a band whose middle — the glyphs' own box, cap
height to baseline plus the round letters' 0.05-em overshoot — is opaque,
and which fades over m = 0.45 em beyond it on either side (a backstop to the
digits' own fade): the landed figure and the static glyphs (« FCFA ») are
never touched by it. Motion blur, when wanted, comes from blur.accumulate
over subframes (the counter is cheap to draw).
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import skia

from . import easing
from .surface import layer, scaled_about, skrect
from .type import NNBSP, cap_height, draw_text, fcfa, measure, nnbsp_advance, shape, text_paint


@dataclass(frozen=True)
class Column:
    k: int                 # 10^k place (0 = units)
    start: int             # digit shown at progress 0
    steps: int             # signed digits scrolled by progress 1
    appears: bool          # absent at 0 (a leading place the start lacks)
    leaves: bool           # absent at 1 (a leading place the end lacks)


def _steps(travel: int, laps: int) -> int:
    """Digits a column scrolls for a true travel of `travel` ticks: the travel
    itself when within `laps` laps (+9), else the largest count ≤ that cap
    with the same value mod 10 — never 0 when the column must change."""
    n = abs(travel)
    cap = 10 * laps + 9
    if n > cap:
        n = n % 10 + 10 * ((cap - n % 10) // 10)
    if n == 0 and travel != 0:
        n = 10
    return n if travel >= 0 else -n


class Odometer:
    """Rolls from `start` to `end` (non-negative integers)."""

    def __init__(self, start: int, end: int, font: skia.Font, colour: int, *, suffix: str = " FCFA",
                 curve: easing.Curve = easing.FAST_OUT_SLOW_IN, max_laps: int = 4, band_em: float = 0.45,
                 pitch_caps: float = 1.15):
        if start < 0 or end < 0:
            raise ValueError("Odometer counts non-negative integers")
        self.start, self.end, self.font, self.colour = int(start), int(end), font, colour
        self.suffix, self.curve, self.band_em, self.pitch_caps = suffix, curve, band_em, pitch_caps
        ls, le = len(str(self.start)), len(str(self.end))
        n = max(ls, le)
        cols = []
        for k in range(n):
            travel = self.end // 10 ** k - self.start // 10 ** k
            laps = min(max_laps, n - 1 - k)                # one more lap per place to the right
            cols.append(Column(k, (self.start // 10 ** k) % 10, _steps(travel, laps), k >= ls, k >= le))
        self.columns = cols[::-1]                         # left to right
        glyphs = [font.unicharToGlyph(ord(c)) for c in "0123456789"]
        self._glyphs = glyphs
        self._adv = font.getWidths(glyphs)
        self._sep = nnbsp_advance(font)
        self._suffix_w = measure(suffix, font) if suffix else 0.0
        self.cap = cap_height(font)
        self.margin = band_em * font.getSize()
        self.overshoot = 0.05 * font.getSize()            # round glyphs pass cap height and baseline

    # ---- state at progress p -------------------------------------------------------

    def _roll(self, col: Column, p: float) -> tuple[int, int, float]:
        """(digit leaving, digit arriving, fraction rolled) of a column."""
        pos = abs(col.steps) * self.curve(easing.clamp01(p))
        done = math.floor(pos)
        frac = pos - done
        sign = 1 if col.steps >= 0 else -1
        a = (col.start + sign * done) % 10
        return a, (a + sign) % 10, frac

    def _presence(self, col: Column, p: float) -> float:
        pos = abs(col.steps) * self.curve(easing.clamp01(p))
        if col.appears and not col.leaves:
            return easing.smoothstep(0.0, 1.0, pos)
        if col.leaves and not col.appears:
            return easing.smoothstep(0.0, 1.0, abs(col.steps) - pos)
        if col.appears and col.leaves:
            return 0.0
        return 1.0

    def digits_at(self, p: float) -> str:
        """The digits (nearest each column's roll, present columns only) read
        at progress p. Exactly str(start) at 0 and str(end) at 1."""
        out = []
        for col in self.columns:
            if self._presence(col, p) <= 0:
                continue
            a, b, frac = self._roll(col, p)
            out.append(str(b if frac >= 0.5 else a))
        return "".join(out).lstrip("0") or "0"

    def text_at(self, p: float) -> str:
        """The figure read at progress p, formatted as the app formats it."""
        return fcfa(int(self.digits_at(p))) if self.suffix == " FCFA" else self.digits_at(p) + self.suffix

    def layout(self, p: float) -> list[tuple[str, float, float, dict]]:
        """Items left to right: (kind, x, width, info) with x from the figure's
        left edge. kind ∈ digit, sep, suffix."""
        items = []
        x = 0.0
        for i, col in enumerate(self.columns):
            pres = self._presence(col, p)
            a, b, frac = self._roll(col, p)
            w = easing.lerp(self._adv[a], self._adv[b], frac) * pres
            items.append(("digit", x, w, {"a": a, "b": b, "frac": frac, "presence": pres,
                                          "down": col.steps < 0}))
            x += w
            if col.k > 0 and col.k % 3 == 0:
                sw = self._sep * pres
                items.append(("sep", x, sw, {"presence": pres}))
                x += sw
        if self.suffix:
            items.append(("suffix", x, self._suffix_w, {}))
            x += self._suffix_w
        return items

    def width(self, p: float) -> float:
        it = self.layout(p)
        return it[-1][1] + it[-1][2] if it else 0.0

    def band(self, baseline: float) -> tuple[float, float]:
        """The rolling band's (top, bottom) for a figure on `baseline`: the
        glyphs' box (cap height, plus the round letters' overshoot) is opaque,
        and the band fades over `margin` beyond it on either side."""
        o = self.overshoot
        return baseline - self.cap - o - self.margin, baseline + o + self.margin

    # ---- drawing --------------------------------------------------------------------

    def draw(self, canvas: skia.Canvas, p: float, x: float, baseline: float, *, align: str = "centre",
             alpha: float = 1.0, scale: float = 1.0) -> None:
        """Draw at progress p (0..1). `x` is the figure's centre (align
        'centre') or left edge ('left'); `scale` is a punch about the
        figure's centre."""
        if alpha <= 0:
            return
        items = self.layout(p)
        w = items[-1][1] + items[-1][2]
        x0 = x - w / 2 if align == "centre" else x
        top, bottom = self.band(baseline)
        m = self.margin
        L = self.cap * self.pitch_caps                     # the strip's digit pitch
        with scaled_about(canvas, scale, x0 + w / 2, baseline - self.cap / 2):
            with layer(canvas, alpha, (x0 - m, top, x0 + w + m, bottom)):
                paint = text_paint(self.colour)
                for kind, ix, iw, info in items:
                    if kind == "suffix":
                        draw_text(canvas, self.suffix, self.font, x0 + ix, baseline, self.colour)
                    elif kind == "digit" and info["presence"] > 0:
                        self._draw_digit(canvas, x0 + ix, iw, baseline, info, L, paint)
                # soft edges of the band
                fade = skia.GradientShader.MakeLinear(
                    [skia.Point(0, top), skia.Point(0, bottom)],
                    [0x00000000, 0xFF000000, 0xFF000000, 0x00000000],
                    [0.0, m / (bottom - top), 1 - m / (bottom - top), 1.0])
                fp = skia.Paint(Shader=fade, BlendMode=skia.BlendMode.kDstIn)
                fp.setDither(True)
                canvas.drawRect(skrect((x0 - m, top, x0 + w + m, bottom)), fp)

    def _draw_digit(self, canvas: skia.Canvas, cx0: float, cw: float, baseline: float, info: dict,
                    L: float, paint: skia.Paint) -> None:
        a, b, frac, pres = info["a"], info["b"], info["frac"], info["presence"]
        d = -1.0 if info["down"] else 1.0                   # counting up: digits move up
        for which, digit, dy in (("a", a, -d * frac * L), ("b", b, d * (1 - frac) * L)):
            if which == "b" and frac == 0.0:
                continue                                    # `a` sits exactly in place; `b` is a whole step out
            p = skia.Paint(paint)
            fade = 1.0 - abs(dy) / L                       # 1 at home, 0 a whole step away
            if pres < 1 or fade < 1:
                p.setAlphaf(p.getAlphaf() * pres * fade)
            gx = cx0 + (cw - self._adv[digit]) / 2          # centred in its (interpolated) cell
            bld = skia.TextBlobBuilder()
            bld.allocRunPosH(self.font, [self._glyphs[digit]], [gx], baseline + dy)
            canvas.drawTextBlob(bld.make(), 0, 0, p)


def draw_label_switch(canvas: skia.Canvas, old: str, new: str, p: float, font: skia.Font, x: float,
                      baseline: float, colour: int, *, rise: float = 12.0, align: str = "centre") -> None:
    """A label changing from `old` to `new` (« Aujourd’hui » → « Mois »):
    the old one fades out rising, the new one fades in from below, crossing
    at p = 0.5 (drive p with the base token: 6 frames, easeInOut)."""
    p = easing.clamp01(p)
    if p < 1:
        draw_text(canvas, old, font, x, baseline - rise * p, colour, 1 - p, align)
    if p > 0:
        draw_text(canvas, new, font, x, baseline + rise * (1 - p), colour, p, align)


def static_width(value: int, font: skia.Font, suffix: str = " FCFA") -> float:
    """The width of the formatted figure as typeset (what the counter
    measures when it has landed)."""
    s = fcfa(value) if suffix == " FCFA" else str(value) + suffix
    return shape(s, font).width


__all__ = ["Odometer", "Column", "draw_label_switch", "static_width", "fcfa", "NNBSP"]
