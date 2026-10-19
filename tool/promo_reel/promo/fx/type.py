"""Type: French typography, exact measuring, captions revealed word by word,
mask reveals, and the strike-through.

FRENCH TYPOGRAPHY. `french()` puts a narrow no-break space (U+202F) before
« ? ! ; : » and inside « … », and turns ' into ’. Poppins Medium has no
U+202F glyph (its cmap sends it to .notdef — a box), so text is never drawn
as a plain string: `shape()` maps every character to a glyph itself and
gives U+202F an advance and NO glyph. Its width is half the font's word
space — 0.13 em in Poppins, the width the storyboard measured with
(« 77 000 FCFA » = 712 px at 120 px). Inter has the glyph and keeps its own.

MEASURING. Widths are the fonts' advances, unkerned. That is not a shortcut:
this Poppins build has no kerning at all (no `kern` table, and its GPOS holds
only Devanagari mark positioning), so the app's own Poppins text is unkerned
too, and the storyboard's line widths (« Votre carnet » 601 px at 96 px) are
exactly these advances.

REVEAL. A caption is lines of `Word(text, at)`. Each word rises 24 px and
fades in over 4 frames on the app's entering curves (rise on easeOutCubic,
fade on easeOut). Its cue frame `at` is its FIRST VISIBLE frame — the reveal
runs over the continuous interval [at − 1, at + 3], so the frame the beat
lands on already moves (the hook « moves from f0 »). A word's position is
its place in the finished line: nothing reflows as later words arrive —
unless the caption asks `recentre` (frames): then a centred line still
waiting for words sits centred on the words it shows and, before each new
word, glides over those frames (easeOutCubic) to make room for it — the
word rises in on its own frame, in its place — for a line that waits long
for its last word (« Créneau libre » … « rempli. », 2.67 s in the 15-s
cut: 136 px off centre while every other line is centred; review round 3).
The finished line is exactly where it would be.

STRIKE. The mark's recipe — one weight, round cap — drawn left to right. Its
visible length starts at 4× its width on the cue frame (a dot would read as
nothing) and grows to full length over 4 frames. On a caption its width is
the font's stem (the « l »), so the strike reads as the same pen as the
letters.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from itertools import combinations
from typing import Sequence

import numpy as np
import skia

from . import easing
from .surface import Rect, layer, skrect

NNBSP = " "           # narrow no-break space
NBSP = " "
_SPACES = "    "

# Words a French line should not end on (articles, prepositions, conjunctions,
# possessives): « Ils réservent dès la / mise en ligne » is a bad break.
WEAK_LINE_ENDS = frozenset("""
à a au aux de du des d’ la le les l’ un une et ou en pour par sur sous dans
avec sans dès chez ce ces cet cette son sa ses vos votre nos notre mon ma mes
ton ta tes leur leurs qui que qu’ ne n’ se s’ y
""".split())


# ---- French typography --------------------------------------------------------------

def french(text: str) -> str:
    """French spacing and quotes, idempotent:
      « déborde ? » → U+202F before ? ! ; : (whatever space was there, or none);
      « x » → U+202F inside the guillemets; ' → ’.
    A colon between digits (10:45) and in a URL (https://) is left alone."""
    s = text.replace("'", "’")
    # inside guillemets
    s = re.sub(rf"«[{_SPACES}]*", "«" + NNBSP, s)
    s = re.sub(rf"[{_SPACES}]*»", NNBSP + "»", s)
    # before ? ! ; — after anything but a space, a line start or another mark of the set
    s = re.sub(rf"[{_SPACES}]*([?!;]+)", lambda m: (NNBSP + m.group(1)) if m.start() > 0 else m.group(1), s)
    # before : — but not 10:45, nor scheme://
    s = re.sub(rf"(?<=[^\d{_SPACES}])[{_SPACES}]*:(?![\d/])|(?<=\d)[{_SPACES}]+:(?![\d/])",
               NNBSP + ":", s)
    return s


def group_thousands(n: int) -> str:
    """« 77 000 »: French grouping with U+202F, as NumberFormat('#,##0',
    'fr_FR') prints (mobile/lib/core/utils/formatters.dart:83-93)."""
    sign = "−" if n < 0 else ""
    digits = str(abs(int(n)))
    groups = []
    while digits:
        groups.insert(0, digits[-3:])
        digits = digits[:-3]
    return sign + NNBSP.join(groups)


def fcfa(n: int) -> str:
    """« 77 000 FCFA »: grouped with U+202F, then ONE plain space and the unit
    (formatters.dart `formatCurrency`: the plain space is the only place an
    amount may break)."""
    return f"{group_thousands(n)} FCFA"


# ---- shaping ----------------------------------------------------------------------

@dataclass(frozen=True)
class Shaped:
    """A run of glyphs and their x offsets from the run's origin."""

    glyphs: tuple[int, ...]
    xs: tuple[float, ...]
    width: float                     # the run's advance


def _glyph(font: skia.Font, ch: str) -> int:
    return font.unicharToGlyph(ord(ch))


def nnbsp_advance(font: skia.Font) -> float:
    """U+202F's advance: the font's own when it has the glyph, else half its
    word space."""
    g = _glyph(font, NNBSP)
    if g:
        return font.getWidths([g])[0]
    return font.getWidths([_glyph(font, " ")])[0] / 2


def shape(text: str, font: skia.Font) -> Shaped:
    """Glyphs and pen positions for `text` — U+202F becomes an advance with no
    glyph when the font lacks it. Raises ValueError for any other character
    the font cannot draw (a box on screen is never acceptable)."""
    glyphs: list[int] = []
    xs: list[float] = []
    x = 0.0
    narrow = None
    for ch in text:
        g = _glyph(font, ch)
        if ch == NNBSP and not g:
            narrow = nnbsp_advance(font) if narrow is None else narrow
            x += narrow
            continue
        if not g:
            raise ValueError(f"{font.getTypeface().getFamilyName()} has no glyph for {ch!r} (U+{ord(ch):04X}) in {text!r}")
        w = font.getWidths([g])[0]
        glyphs.append(g)
        xs.append(x)
        x += w
    return Shaped(tuple(glyphs), tuple(xs), x)


def measure(text: str, font: skia.Font) -> float:
    """The advance width of `text` in `font` (px)."""
    return shape(text, font).width


def blob(text: str, font: skia.Font, x: float = 0.0, y: float = 0.0) -> skia.TextBlob | None:
    """A positioned text blob of `text` with its origin at (x, y)."""
    s = shape(text, font)
    if not s.glyphs:
        return None
    b = skia.TextBlobBuilder()
    b.allocRunPosH(font, list(s.glyphs), [x + v for v in s.xs], y)
    return b.make()


def text_paint(colour: int, alpha: float = 1.0) -> skia.Paint:
    p = skia.Paint(AntiAlias=True, Color=colour)
    if alpha < 1.0:
        p.setAlphaf(p.getAlphaf() * max(0.0, alpha))
    return p


def draw_text(canvas: skia.Canvas, text: str, font: skia.Font, x: float, baseline: float,
              colour: int, alpha: float = 1.0, align: str = "left") -> float:
    """Draw `text` with its baseline at `baseline`; `x` is its left edge,
    centre or right edge by `align`. Returns the left edge used."""
    w = measure(text, font)
    x0 = {"left": x, "centre": x - w / 2, "center": x - w / 2, "right": x - w}[align]
    b = blob(text, font, x0, baseline)
    if b is not None and alpha > 0:
        canvas.drawTextBlob(b, 0, 0, text_paint(colour, alpha))
    return x0


def cap_height(font: skia.Font) -> float:
    return font.getMetrics().fCapHeight


def x_height(font: skia.Font) -> float:
    return font.getMetrics().fXHeight


def stem_width(font: skia.Font) -> float:
    """The font's vertical stem at this size: the ink width of « l »."""
    g = _glyph(font, "l")
    return font.getBounds([g])[0].width()


def ink_bounds(text: str, font: skia.Font, x: float = 0.0, baseline: float = 0.0) -> Rect:
    """The ink box of `text` drawn at (x, baseline)."""
    s = shape(text, font)
    if not s.glyphs:
        return (x, baseline, x, baseline)
    rects = font.getBounds(list(s.glyphs))
    x0 = min(r.left() + gx for r, gx in zip(rects, s.xs))
    x1 = max(r.right() + gx for r, gx in zip(rects, s.xs))
    y0 = min(r.top() for r in rects)
    y1 = max(r.bottom() for r in rects)
    return (x + x0, baseline + y0, x + x1, baseline + y1)


# ---- line breaking --------------------------------------------------------------------

def break_lines(text: str, font: skia.Font, max_width: float, max_lines: int = 2) -> list[str]:
    """Break `text` at its plain spaces into at most `max_lines` lines, each
    measured ≤ `max_width`. One line when it fits. Otherwise the break that
    (1) never ends a line on a weak word (« de », « la », « pour »…),
    (2) never leaves one word alone on the last line, and
    (3) balances the line widths best (centred captions).
    Raises ValueError when no break fits."""
    words = text.split(" ")
    if any(not w for w in words):
        raise ValueError(f"break_lines: empty word in {text!r} (double space?)")
    space = measure(" ", font)
    widths = [measure(w, font) for w in words]

    def line_width(i: int, j: int) -> float:
        return sum(widths[i:j]) + space * (j - i - 1)

    if line_width(0, len(words)) <= max_width:
        return [text]
    best, best_score = None, None
    n = len(words)
    for k in range(2, max_lines + 1):
        for cuts in combinations(range(1, n), k - 1):
            bounds = (0, *cuts, n)
            spans = list(zip(bounds, bounds[1:]))
            ws = [line_width(i, j) for i, j in spans]
            if max(ws) > max_width:
                continue
            score = float(np.var(ws))
            score += sum(1e7 for i, j in spans[:-1] if words[j - 1].lower() in WEAK_LINE_ENDS)
            if n >= 3 and spans[-1][1] - spans[-1][0] == 1:
                score += 1e6
            score += (k - 2) * 1e5            # fewer lines first
            if best_score is None or score < best_score:
                best, best_score = spans, score
        if best is not None and best_score < 1e5 * (k - 1):
            break
    if best is None:
        raise ValueError(f"{text!r} does not fit {max_lines} lines of {max_width:.0f} px")
    return [" ".join(words[i:j]) for i, j in best]


# ---- captions -------------------------------------------------------------------------

@dataclass(frozen=True)
class Word:
    """A word (or a group of words) and the frame it appears on."""

    text: str
    at: float


@dataclass(frozen=True)
class Reveal:
    """How a word enters: rise + fade (« rise »), or a left→right mask
    (« mask », the tagline's word groups)."""

    kind: str = "rise"
    frames: float = 4.0
    rise: float = 24.0
    lead: float = 1.0                      # the cue frame already shows step 1 of `frames`
    rise_curve: easing.Curve = easing.EASE_OUT_CUBIC
    fade_curve: easing.Curve = easing.EASE_OUT
    feather_em: float = 0.6                # mask: the soft edge's width, in em

    def progress(self, t: float, at: float) -> float:
        return easing.progress(t, at - self.lead, self.frames)


RISE = Reveal()
MASK = Reveal(kind="mask", frames=6.0, rise=0.0, lead=1.0, rise_curve=easing.EASE_OUT_CUBIC)


@dataclass
class PlacedWord:
    word: Word
    x: float                  # left edge of the advance box
    baseline: float
    width: float
    line: int


@dataclass
class Caption:
    """Lines of words, centred on `centre_x`, revealed on their cue frames.

    Vertical placement: `cap_top` puts the first line's capitals' top there
    (the storyboard's « words at y 300–540 », « cap top at y 712 »); or give
    `baseline` for the first line directly. Lines are `line_height` px apart
    (default 1.15 em, the stills' headline leading). Every line is measured
    and must fit `max_width` (default 771 px, the 9:16 safe column), or
    ValueError says which.

    Text is passed through `french()` unless `typography=False`."""

    lines: Sequence[Sequence[Word]]
    font: skia.Font
    colour: int
    centre_x: float = 540.0
    cap_top: float | None = None
    baseline: float | None = None
    line_height: float | None = None
    max_width: float = 771.0
    reveal: Reveal = RISE
    align: str = "centre"
    typography: bool = True
    recentre: float | None = None          # frames: partial centred lines sit centred, gliding as words arrive
    placed: list[PlacedWord] = field(init=False, default_factory=list)

    def __post_init__(self):
        if (self.cap_top is None) == (self.baseline is None):
            raise ValueError("Caption: give exactly one of cap_top or baseline")
        if self.typography:
            self.lines = [[Word(french(w.text), w.at) for w in line] for line in self.lines]
        px = self.font.getSize()
        lh = self.line_height if self.line_height is not None else 1.15 * px
        b0 = self.baseline if self.baseline is not None else self.cap_top + cap_height(self.font)
        space = measure(" ", self.font)
        self.placed = []
        for i, line in enumerate(self.lines):
            widths = [measure(w.text, self.font) for w in line]
            total = sum(widths) + space * (len(line) - 1)
            if total > self.max_width + 1e-6:
                text = " ".join(w.text for w in line)
                raise ValueError(f"caption line {text!r} is {total:.1f} px, wider than {self.max_width:.0f} px")
            x = {"centre": self.centre_x - total / 2, "left": self.centre_x, "right": self.centre_x - total}[self.align]
            for w, wd in zip(line, widths):
                self.placed.append(PlacedWord(w, x, b0 + i * lh, wd, i))
                x += wd + space

    def line_dx(self, line: int, t: float) -> float:
        """How far line `line` sits right of its finished place at frame t: 0
        unless the caption `recentre`s a centred line still waiting for
        words — then it is centred on the words it shows (advance widths)
        and, before each next word, glides over `recentre` frames to the
        centre with that word, MAKING ROOM: the glide ends on the frame the
        word starts to rise in, so the word lands in its place, never beside
        a line still moving (nor past the column's edge)."""
        if not self.recentre or self.align != "centre":
            return 0.0
        ws = [p for p in self.placed if p.line == line]
        full = ws[-1].x + ws[-1].width - ws[0].x
        dx = [(full - (q.x + q.width - ws[0].x)) / 2 for q in ws]       # centred on the first k words
        out = dx[0]
        for i in range(1, len(ws)):
            arrive = ws[i].word.at - self.reveal.lead
            out += (dx[i] - dx[i - 1]) * easing.EASE_OUT_CUBIC(easing.progress(t, arrive - self.recentre,
                                                                               self.recentre))
        return out

    def x_at(self, p: PlacedWord, t: float) -> float:
        """A placed word's left edge at frame t (its place, or a partial line's)."""
        return p.x + self.line_dx(p.line, t)

    def line_widths(self) -> list[float]:
        out = []
        for i in range(len(self.lines)):
            ws = [p for p in self.placed if p.line == i]
            out.append(ws[-1].x + ws[-1].width - ws[0].x)
        return out

    def find(self, text: str) -> PlacedWord:
        """The placed word whose text is `text` (after French typography)."""
        t = french(text) if self.typography else text
        for p in self.placed:
            if p.word.text == t:
                return p
        raise KeyError(f"no word {text!r} in the caption")

    def word_state(self, p: PlacedWord, t: float) -> tuple[float, float]:
        """(alpha, dy) of a placed word at frame t."""
        q = self.reveal.progress(t, p.word.at)
        return self.reveal.fade_curve(q), self.reveal.rise * (1.0 - self.reveal.rise_curve(q))

    def draw(self, canvas: skia.Canvas, t: float, alpha: float = 1.0, dy: float = 0.0) -> None:
        """Draw the caption at frame t. `alpha` and `dy` move it as a whole
        (an exit, a parallax)."""
        if alpha <= 0:
            return
        for p in self.placed:
            q = self.reveal.progress(t, p.word.at)
            if q <= 0:
                continue
            x = self.x_at(p, t)
            if self.reveal.kind == "mask":
                draw_mask_reveal(canvas, p.word.text, self.font, x, p.baseline + dy, self.colour,
                                 self.reveal.rise_curve(q), alpha=alpha, feather_em=self.reveal.feather_em)
            else:
                a, rise = self.word_state(p, t)
                draw_text(canvas, p.word.text, self.font, x, p.baseline + dy + rise, self.colour, a * alpha)


def draw_mask_reveal(canvas: skia.Canvas, text: str, font: skia.Font, x: float, baseline: float,
                     colour: int, progress: float, alpha: float = 1.0, feather_em: float = 0.6) -> None:
    """`text` uncovered left to right by a soft-edged mask: at 0 nothing, at 1
    all of it. The edge travels from one feather left of the ink to the ink's
    right end, so the first and last letters get the same soft entry."""
    if progress <= 0 or alpha <= 0:
        return
    x0, y0, x1, y1 = ink_bounds(text, font, x, baseline)
    if progress >= 1:
        draw_text(canvas, text, font, x, baseline, colour, alpha)
        return
    feather = max(1.0, feather_em * font.getSize())
    edge = (x0 - feather) + (x1 - x0 + feather) * progress          # the fully hidden side starts here
    pad = 4
    with layer(canvas, alpha, (x0 - pad, y0 - pad, x1 + pad, y1 + pad)):
        draw_text(canvas, text, font, x, baseline, colour)
        shader = skia.GradientShader.MakeLinear([skia.Point(edge, 0), skia.Point(edge + feather, 0)],
                                                [0xFF000000, 0x00000000])
        p = skia.Paint(Shader=shader, BlendMode=skia.BlendMode.kDstIn)
        p.setDither(True)
        canvas.drawRect(skrect((x0 - pad, y0 - pad, x1 + pad, y1 + pad)), p)


# ---- the strike -------------------------------------------------------------------------

def strike_length(full: float, width: float, progress: float, curve: easing.Curve = easing.EASE_OUT_CUBIC,
                  start_factor: float = 4.0) -> float:
    """The visible length (caps included) of a strike `width` wide that is
    `full` long when done: start_factor × width at progress 0, full at 1."""
    start = min(full, start_factor * width)
    return start + (full - start) * curve(easing.clamp01(progress))


def draw_strike(canvas: skia.Canvas, p0: tuple[float, float], p1: tuple[float, float], width: float,
                progress: float, colour: int, alpha: float = 1.0, start_factor: float = 4.0,
                curve: easing.Curve = easing.EASE_OUT_CUBIC) -> None:
    """A round-cap stroke from p0 toward p1, its visible extent (caps
    included) growing from `start_factor`·width to |p1 − p0|. `progress` < 0
    draws nothing (the strike has not happened yet)."""
    if progress < 0 or alpha <= 0:
        return
    (ax, ay), (bx, by) = p0, p1
    full = float(np.hypot(bx - ax, by - ay))
    if full <= 0:
        return
    vis = strike_length(full, width, progress, curve, start_factor)
    ux, uy = (bx - ax) / full, (by - ay) / full
    # the cap adds width/2 at each end: the centre line is vis − width long
    a = (ax + ux * width / 2, ay + uy * width / 2)
    b = (ax + ux * (vis - width / 2), ay + uy * (vis - width / 2))
    paint = skia.Paint(AntiAlias=True, Color=colour, Style=skia.Paint.kStroke_Style, StrokeWidth=width)
    paint.setStrokeCap(skia.Paint.kRound_Cap)
    if alpha < 1:
        paint.setAlphaf(paint.getAlphaf() * alpha)
    path = skia.Path()
    path.moveTo(*a)
    path.lineTo(*b)
    canvas.drawPath(path, paint)


def strike_word(canvas: skia.Canvas, caption: Caption, text: str, t: float, at: float, colour: int,
                frames: float = 4.0, width: float | None = None, overshoot_em: float = 0.06,
                alpha: float = 1.0) -> None:
    """Strike a caption word through at mid x-height, starting on frame `at`
    and done at `at + frames` (« Créneau ~~libre~~ rempli. »)."""
    p = caption.find(text)
    if t < at:
        return
    font = caption.font
    w = width if width is not None else stem_width(font)
    x0, _, x1, _ = ink_bounds(p.word.text, font, caption.x_at(p, t), p.baseline)
    over = overshoot_em * font.getSize()
    y = p.baseline - x_height(font) / 2
    draw_strike(canvas, (x0 - over, y), (x1 + over, y), w, easing.progress(t, at, frames), colour, alpha)
