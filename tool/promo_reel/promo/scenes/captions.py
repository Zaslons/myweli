"""The caption track: every caption of a cut, word by word on its cue.

A caption (storyboard.yaml, a scene's ``captions``) is lines of words, each
with the time it appears (a cue, or a grid position). It shows from its first
word until ``until`` — the frame before it is the last that shows it, so the
next caption's first word (which rises from that frame on) never overlaps it.
Types follow the storyboard's « Type » rule and the format's ``type_px``:

  hook     Poppins Medium 96 px, white, cap top = layout caption_cap_top.hook
           (9:16: y 300, the hook block)
  app      Poppins Medium 72 px, #1A1A1A, cap top = layout caption_cap_top.app
           (9:16: y 330, the band, y 300–540) — or, null, the block centred
           on caption_centre_y (16:9: the left column's y 440)
  tagline  Poppins Medium 46 px, #1A1A1A, cap top = layout end_tagline_cap_top_y
  store    Inter Medium type_px.store (40) px, #4A4A4A, under the tagline
           (cap top + STORE_DY): « Sur l’App Store et Google Play »
  site     Inter Medium type_px.site (40) px, #1A1A1A, under the store line
           (cap top + SITE_DY): « myweli.com », the card's last line — the
           owner's end card (2026-10-20, « Both stores, post later »)

WHERE (the format's layout): hook and app lines sit in the caption column —
centred on caption_centre_x (`caption_align: centre`, 9:16 and 1:1) or from
the column's left edge (`left`, 16:9); the tagline and the store line are
centred on the mark's axis (lottie_centre's x) — the store and site lines too; `centre: frame` centres a
caption on the canvas (the AIR's « Respirez. »). Boxes say whether their
caption is laid in the column (`column`), which verify (g) holds them to.

``colour: auto`` (the default for app captions) follows the stage the frame is
on: ink on paper, white on black — « Ils réservent dès la mise en ligne. »
turns white as the page falls to black (row 22). Every line is measured with
the repo's fonts and must fit the format's ``caption_line_max_px`` (771).

``recentre: N`` (frames): while a centred line waits for its words it sits
centred on those it shows, and glides over N frames to make room for each
next word, which then rises in on its own frame in its place
(fx.type.Caption.line_dx) — the « Créneau libre » … « rempli. » line, whose
last word comes 2.7 s after the first in the 15-s cut. A left-aligned line
(16:9) is already flush with its column: nothing moves there.

``underline: {text, at, frames}`` draws the brand's single round-cap stroke
(the hook's strikes, fx.type.draw_strike, at the font's stem width) under
``text`` — part of one of the caption's words — from frame ``at``, growing
left to right over ``frames``: the end card's « moins de gestion. » on the
outro's downbeat. It sits under the line's descenders; the track refuses one
that touches any caption's ink while both show.

Every caption is held to the reading limit (verify (i), PASS or FAIL): the
``reading: owner_decision_pending`` marker the end card once carried is
retired — the owner decided (2026-10-19, one more bar) — and refused.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

import skia

from ..fx import easing
from ..fx import type as ty
from ..fx.brand import PALETTE, inter, poppins


@dataclass(frozen=True)
class CaptionStyle:
    font: str
    px: float
    colour: Any            # an ARGB int or "auto"
    cap_top: float | None
    centre_y: float | None
    line_height: float | None


#: the end card's lines under the tagline: their cap tops below the tagline's (px, every format — the lockup keeps
#: one size everywhere). 96: the underline under « moins de gestion. » fits between (verify: 2 px clear, ≥ 20 in
#: fact); 160: « myweli.com » 64 px under the store line (1.6 × its 40 px), clear of its descenders (g, p, y)
STORE_DY = 96.0
SITE_DY = 160.0
#: the caption kinds laid on the mark's axis (the end card), not in the caption column
END_KINDS = ("tagline", "store", "site")


def _styles(layout: dict) -> dict[str, CaptionStyle]:
    tp = layout["type_px"]
    tag_top = layout["end_tagline_cap_top_y"]
    tops = layout["caption_cap_top"]
    centre_y = layout.get("caption_centre_y")

    def place(kind: str) -> tuple[float | None, float | None]:
        return (float(tops[kind]), None) if tops.get(kind) is not None else (None, float(centre_y))

    return {
        "hook": CaptionStyle("poppins", tp["hook"], PALETTE.WHITE, *place("hook"), None),
        "app": CaptionStyle("poppins", tp["app"], "auto", *place("app"), None),
        "tagline": CaptionStyle("poppins", tp["tagline"], PALETTE.INK, float(tag_top), None, None),
        "store": CaptionStyle("inter", float(tp.get("store", 40)), PALETTE.INK_SECONDARY, float(tag_top) + STORE_DY,
                              None, None),
        "site": CaptionStyle("inter", float(tp.get("site", 40)), PALETTE.INK, float(tag_top) + SITE_DY, None, None),
    }


class CaptionItem:
    def __init__(self, spec: dict, owner: str, clock, layout: dict, where: str,
                 size: tuple[int, int] | None = None):
        self.id = spec.get("id", where)
        self.owner = owner
        self.cite = spec.get("cite")
        if "reading" in spec:
            raise ValueError(f"{where}.reading: retired — every caption is held to the reading limit (verify (i) "
                             f"is PASS or FAIL); the owner decided the end card (2026-10-19: one more bar)")
        kind = spec.get("type", "app")
        styles = _styles(layout)
        if kind not in styles:
            raise ValueError(f"{where}.type: one of {', '.join(styles)}, not {kind!r}")
        st = styles[kind]
        self.kind = kind
        px = float(spec.get("px", st.px))
        self.font = poppins(px) if st.font == "poppins" else inter(px)
        colour = spec.get("colour", st.colour)
        self.colour = {"white": PALETTE.WHITE, "ink": PALETTE.INK}.get(colour, colour)
        self.lines_spec = []
        lines = []
        for li, line in enumerate(spec.get("lines") or []):
            words = []
            for wi, w in enumerate(line):
                if not isinstance(w, dict) or "w" not in w or "at" not in w:
                    raise ValueError(f"{where}.lines[{li}][{wi}]: a word is {{w: text, at: time}}")
                words.append(ty.Word(str(w["w"]), float(clock.frame(w["at"]))))
            lines.append(words)
        if not lines:
            raise ValueError(f"{where}: a caption has lines")
        self.until = float(clock.frame(spec["until"]))
        self.first = min(w.at for line in lines for w in line)
        reveal = ty.MASK if spec.get("reveal") == "mask" else ty.RISE
        self.reveal = reveal
        centre_y = spec.get("centre_y", st.centre_y)
        line_height = spec.get("line_height", st.line_height)
        cap_top = spec.get("cap_top", st.cap_top)
        if "cap_top" in spec or "centre_y" in spec:
            cap_top = spec.get("cap_top")
            centre_y = spec.get("centre_y")
        max_w = float(layout["caption_line_max_px"]) if kind in ("hook", "app") else 1e9
        # where the lines sit across: the caption column (centred or from its left edge), the mark's axis
        # (the end card), or the canvas (`centre: frame`)
        self.in_column = kind in ("hook", "app")
        align = "centre"
        if spec.get("centre") is not None:
            if spec["centre"] != "frame":
                raise ValueError(f"{where}.centre: `frame` (centred on the canvas), not {spec['centre']!r}")
            if size is None:
                raise ValueError(f"{where}.centre: frame needs the canvas size")
            centre_x, centre_y, cap_top = size[0] / 2, size[1] / 2, None
            self.in_column = False
        elif kind in END_KINDS:
            centre_x = float(layout["lottie_centre"][0])
        elif layout["caption_align"] == "left":
            centre_x, align = float(layout["caption_column_x"][0]), "left"
        else:
            centre_x = float(layout["caption_centre_x"])
        if centre_y is not None:
            # the block centred on y: cap top of the first line to the baseline of the last
            lh = line_height if line_height is not None else 1.15 * px
            block = ty.cap_height(self.font) + lh * (len(lines) - 1)
            cap_top = float(centre_y) - block / 2
        try:
            recentre = spec.get("recentre")
            if recentre is not None and (isinstance(recentre, bool) or not isinstance(recentre, (int, float))
                                         or recentre <= 0):
                raise ValueError(f"recentre: the glide's frames (a number > 0), not {recentre!r}")
            self.caption = ty.Caption(lines, self.font, PALETTE.INK, centre_x=centre_x,
                                      cap_top=float(cap_top), line_height=line_height, max_width=max_w,
                                      reveal=reveal, align=align, recentre=float(recentre) if recentre else None)
            if align == "left":
                # set from the column's left edge: a first glyph that overhangs its origin moves the lines in
                # by that much, so the ink starts ON the edge, never past it
                ink_x0 = min(ty.ink_bounds(p.word.text, self.font, p.x, p.baseline)[0] for p in self.caption.placed)
                if ink_x0 < centre_x:
                    self.caption = ty.Caption(lines, self.font, PALETTE.INK,
                                              centre_x=centre_x + (centre_x - ink_x0), cap_top=float(cap_top),
                                              line_height=line_height, max_width=max_w, reveal=reveal, align=align)
        except ValueError as e:
            raise ValueError(f"{where}: {e}") from None
        self.strike = None
        if spec.get("strike"):
            s = spec["strike"]
            self.caption.find(s["word"])
            self.strike = (s["word"], float(clock.frame(s["at"])))
        self.text = " ".join(w.text for line in self.caption.lines for w in line)
        self.underline = self._underline(spec["underline"], clock, f"{where}.underline") if spec.get("underline") else None

    #: the underline's clearance under the line's lowest ink (descenders), in px
    UNDERLINE_GAP = 6.0

    def _underline(self, u: dict, clock, where: str) -> dict:
        try:
            text = ty.french(str(u["text"]))
            at = float(clock.frame(u["at"]))
        except KeyError as e:
            raise ValueError(f"{where}: needs {e.args[0]}") from None
        frames = float(u.get("frames", 8))
        p = next((p for p in self.caption.placed if text in p.word.text), None)
        if p is None:
            raise ValueError(f"{where}: « {text} » is in none of the caption's words")
        x = p.x + ty.measure(p.word.text[:p.word.text.index(text)], self.font)
        x0, _, x1, _ = ty.ink_bounds(text, self.font, x, p.baseline)
        line = [q for q in self.caption.placed if q.line == p.line]
        bottom = max(ty.ink_bounds(q.word.text, self.font, q.x, q.baseline)[3] for q in line)
        width = ty.stem_width(self.font)
        y = bottom + self.UNDERLINE_GAP + width / 2
        return {"text": text, "at": at, "frames": frames, "p0": (x0, y), "p1": (x1, y), "width": width,
                "rect": (x0, y - width / 2, x1, y + width / 2)}

    def underline_rect(self, t: float) -> tuple[float, float, float, float] | None:
        """The underline's ink at t (its visible length grows over its frames)."""
        u = self.underline
        if not u or t < u["at"] or not self.visible(t):
            return None
        full = u["p1"][0] - u["p0"][0]
        vis = ty.strike_length(full, u["width"], easing.progress(t, u["at"], u["frames"]))
        x0, y0, _, y1 = u["rect"]
        return (x0, y0, x0 + vis, y1)

    def ink_boxes(self) -> list[tuple[float, float, float, float]]:
        """The ink of every line, whole (for the underline's clearance)."""
        out = []
        for li in range(len(self.caption.lines)):
            bs = [ty.ink_bounds(q.word.text, self.font, q.x, q.baseline) for q in self.caption.placed if q.line == li]
            out.append((min(b[0] for b in bs), min(b[1] for b in bs), max(b[2] for b in bs), max(b[3] for b in bs)))
        return out

    def visible(self, t: float) -> bool:
        return self.first - self.reveal.lead <= t < self.until

    def colour_on(self, dark_stage: bool) -> int:
        if self.colour == "auto":
            return PALETTE.WHITE if dark_stage else PALETTE.INK
        return int(self.colour)

    def draw(self, canvas: skia.Canvas, t: float, dark_stage: bool, alpha: float = 1.0, dy: float = 0.0) -> None:
        if not self.visible(t):
            return
        self.caption.colour = self.colour_on(dark_stage)
        self.caption.draw(canvas, t, alpha=alpha, dy=dy)
        if self.strike:
            word, at = self.strike
            ty.strike_word(canvas, self.caption, word, t, at, self.caption.colour)
        u = self.underline
        if u and t >= u["at"]:
            (ax, ay), (bx, by) = u["p0"], u["p1"]
            ty.draw_strike(canvas, (ax, ay + dy), (bx, by + dy), u["width"], easing.progress(t, u["at"], u["frames"]),
                           self.caption.colour, alpha)

    def boxes(self, t: float) -> list[dict]:
        """Ink boxes of the words showing at t (for the safe-zone check)."""
        if not self.visible(t):
            return []
        out = []
        for p in self.caption.placed:
            q = self.reveal.progress(t, p.word.at)
            if q <= 0:
                continue
            x0, y0, x1, y1 = ty.ink_bounds(p.word.text, self.font, self.caption.x_at(p, t), p.baseline)
            rise = 0.0 if self.reveal.kind == "mask" else self.caption.word_state(p, t)[1]
            out.append({"kind": "caption", "label": f"{self.id}:{p.word.text}", "column": self.in_column,
                        "rect": [round(x0, 1), round(y0 + rise, 1), round(x1, 1), round(y1 + rise, 1)]})
        u = self.underline_rect(t)
        if u is not None:
            out.append({"kind": "caption", "label": f"{self.id}:underline", "column": self.in_column,
                        "rect": [round(v, 1) for v in u]})
        return out

    def line_widths(self) -> list[float]:
        return self.caption.line_widths()


def underline_clashes(items: list[CaptionItem]) -> list[str]:
    """Underlines that touch a caption's ink — their own lines' or any other
    caption's on screen with them (≥ 2 px clear). The stroke never covers
    text."""
    out = []
    for c in items:
        u = c.underline
        if not u:
            continue
        ux0, uy0, ux1, uy1 = u["rect"]
        for o in items:
            if o is not c and (o.until <= u["at"] or o.first - o.reveal.lead >= c.until):
                continue                                         # never on screen together
            for b in o.ink_boxes():
                if ux0 < b[2] + 2 and b[0] - 2 < ux1 and uy0 < b[3] + 2 and b[1] - 2 < uy1:
                    out.append(f"{c.id}'s underline under « {u['text']} » (y {uy0:.1f}–{uy1:.1f}) touches "
                               f"{o.id}'s ink (x {b[0]:.0f}–{b[2]:.0f}, y {b[1]:.1f}–{b[3]:.1f})")
    return out


def arrivals_on_two_lines(items: list[CaptionItem]) -> list[tuple[float, list[str]]]:
    """Frames on which words arrive on more than one line (of one caption or
    of several), with those words: [(frame, ["id[line]: « words »", …])]."""
    by_frame: dict[float, dict[tuple[str, int], list[str]]] = {}
    for c in items:
        for li, line in enumerate(c.caption.lines):
            for w in line:
                by_frame.setdefault(w.at, {}).setdefault((c.id, li), []).append(w.text)
    out = []
    for f in sorted(by_frame):
        lines = by_frame[f]
        if len(lines) > 1:
            out.append((f, [f"{cid}[{li}]: « {' '.join(ws)} »" for (cid, li), ws in lines.items()]))
    return out


class CaptionTrack:
    """Every caption of a cut, drawn in order. Two lines never start on the
    same frame (the end card once brought « moins de gestion. » and « Disponible
    sur l’App Store » in together): a viewer reads one arrival at a time."""

    def __init__(self, items: list[CaptionItem]):
        self.items = items
        same = arrivals_on_two_lines(items)
        if same:
            f, words = same[0]
            raise ValueError(f"two lines receive words on f{f:g}: {'; '.join(words)} — one arrival at a time")
        clash = underline_clashes(items)
        if clash:
            raise ValueError(f"{clash[0]} — an underline never covers text")

    def at(self, t: float) -> list[CaptionItem]:
        return [c for c in self.items if c.visible(t)]

    def draw(self, canvas: skia.Canvas, t: float, dark_stage: bool, owner: str | None = None,
             freeze: float | None = None) -> None:
        for c in self.items:
            if owner is not None and c.owner != owner:
                continue
            tt = t if freeze is None else min(t, freeze)
            c.draw(canvas, tt, dark_stage)

    def boxes(self, t: float) -> list[dict]:
        return [b for c in self.items for b in c.boxes(t)]

    def words(self) -> list[tuple[str, float, str]]:
        """(caption id, frame, word) of every word, for the event list."""
        return [(c.id, w.at, w.text) for c in self.items for line in c.caption.lines for w in line]
