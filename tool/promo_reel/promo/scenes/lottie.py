"""Rows 23–24: the brand reveal and the end card.

ROW 23. A hard cut to bare #FAFAFA; the Pro app's own opening animation
(mobile/assets/lottie/open/myweli_loader_mixed_pro.json, drawn by
promo.lottie.Player) plays alone, its comp 900 px wide centred on the
format's ``lottie_centre``. Its moving segments are retimed by the scene's
piecewise-linear ``warp`` (film frame → comp frame); nothing else about it
changes. The M/W morph is motion-blurred (``blur``).

ROW 24. The finished mark — comp 74, the same picture as comp 142 — eases
from where the reveal left it to the end placement and settles on the
``settle`` cue (and, with ``punch``, gives a small punch on that cue — the
last log of the owner's outro bar — scaled about its ink's centre, its ink
kept clear of the tagline by at least half its height): drawn at
``end_mark_scale`` × the composition's own size
(1.2 × 560 px = 672 px: the mark's ink is then 199 px tall, y 400–599 in
9:16 — the storyboard's « scale 1.2 » and « ink ≈ y 400–599 » agree when the
scale is read against the composition's native 560 px, not the 900-px
reveal). It is moved and scaled only. The tagline and « Disponible sur
l’App Store » are captions.
"""

from __future__ import annotations

import skia

from ..fx import easing
from ..fx import punch as punchmod
from ..lottie import Player
from ..media import tools
from .base import Blur, Scene, SceneError
from .keys import curve

_PLAYERS: dict[str, Player] = {}


def player(rel: str) -> Player:
    if rel not in _PLAYERS:
        path = tools.REPO / rel
        if not path.is_file():
            raise SceneError(f"no Lottie file {path}")
        _PLAYERS[rel] = Player(path)
    return _PLAYERS[rel]


class RevealScene(Scene):
    kind = "lottie"

    def __init__(self, spec: dict, ctx, where: str):
        super().__init__(spec, ctx, where)
        lo = spec.get("lottie") or {}
        try:
            self.player = player(lo["file"])
        except KeyError:
            raise SceneError(f"{where}.lottie.file: missing") from None
        self.colour = lo.get("colour")
        lay = ctx.layout
        self.rect = self.player.dst_rect(lay["lottie_centre"], float(lay["lottie_comp_width_px"]))
        self.warp = [(float(ctx.clock.frame(a)), float(c)) for a, c in spec.get("warp") or []]
        if len(self.warp) < 2 or any(b[0] <= a[0] or b[1] < a[1] for a, b in zip(self.warp, self.warp[1:])):
            raise SceneError(f"{where}.warp: at least two points, film frames rising, comp frames not falling")
        b = spec.get("blur")
        self.blur = (float(ctx.clock.frame(b["from"])), float(ctx.clock.frame(b["to"])), int(b.get("samples", 8))) if b else None

    def comp(self, t: float) -> float:
        w = self.warp
        if t <= w[0][0]:
            return w[0][1]
        for (fa, ca), (fb, cb) in zip(w, w[1:]):
            if t <= fb:
                return ca + (cb - ca) * (t - fa) / (fb - fa)
        # past the last point: continue at the last segment's rate (the next scene takes over)
        (fa, ca), (fb, cb) = w[-2], w[-1]
        return cb + (cb - ca) / (fb - fa) * (t - fb)

    def rates(self) -> list[dict]:
        """Each segment's speed against the device's 25 fps."""
        out = []
        for (fa, ca), (fb, cb) in zip(self.warp, self.warp[1:]):
            film_s = (fb - fa) / self.ctx.fps
            comp_s = (cb - ca) / self.player.fps
            out.append({"film": [fa, fb], "comp": [ca, cb], "rate": round(comp_s / film_s, 3) if comp_s else 0.0})
        return out

    def draw_picture(self, canvas: skia.Canvas, t: float, fast: bool = False, frame: int | None = None) -> None:
        self.stage.draw(canvas, self.size, self.seconds(t))
        self.player.render(canvas, self.comp(t), self.rect, self.colour)

    def blur_at(self, f: int) -> Blur | None:
        if self.blur and self.blur[0] <= f < self.blur[1]:
            return Blur(self.blur[2], 0.5, None)
        return None

    def record(self, f: int, rec: dict) -> None:
        rec["comp"] = round(self.comp(float(f)), 3)
        ink = self.player.ink_bounds(self.comp(float(f)))
        if ink is not None:
            s = self.rect.width() / self.player.size[0]
            rec.setdefault("boxes", []).append({"kind": "mark", "label": "lottie", "rect": [
                round(self.rect.left() + ink.left() * s, 1), round(self.rect.top() + ink.top() * s, 1),
                round(self.rect.left() + ink.right() * s, 1), round(self.rect.top() + ink.bottom() * s, 1)]})

    def events(self) -> list[tuple[int, str]]:
        return [(int(f), f"lottie key comp {c:g}") for f, c in self.warp]

    def generated(self) -> list[dict]:
        return [{"element": "the Pro opening Lottie, retimed (" + ", ".join(
            f"comp {r['comp'][0]:g}→{r['comp'][1]:g} at {r['rate']}×" for r in self.rates()) + ")",
                 "scene": self.id, "cite": self.cite}]


class EndCardScene(Scene):
    kind = "end_card"

    def __init__(self, spec: dict, ctx, where: str):
        super().__init__(spec, ctx, where)
        lo = spec.get("lottie") or {}
        self.player = player(lo["file"])
        self.colour = lo.get("colour")
        self.comp_end = float(lo.get("comp", 74))
        lay = ctx.layout
        self.from_rect = self.player.dst_rect(lay["lottie_centre"], float(lay["lottie_comp_width_px"]))
        m = spec.get("mark") or {}
        self.from_comp = float(m.get("from_comp", 72))
        st = m["settle"]
        self.settle_at = float(ctx.clock.frame(st["at"]))
        self.settle_frames = float(st.get("frames", 8))
        self.curve = curve(st.get("curve", "ease_out_cubic"))
        k = float(lay["end_mark_scale"])
        w = k * self.player.size[0]
        ink = self.player.ink_bounds(self.comp_end)
        top = float(lay["end_mark_ink_y"][0]) - ink.top() * k
        cx = float(lay["lottie_centre"][0])
        self.to_rect = skia.Rect.MakeXYWH(cx - w / 2, top, w, w * self.player.size[1] / self.player.size[0])
        self.ink_end = (self.to_rect.left() + ink.left() * k, self.to_rect.top() + ink.top() * k,
                        self.to_rect.left() + ink.right() * k, self.to_rect.top() + ink.bottom() * k)
        self.punch = None
        if m.get("punch"):
            pu = m["punch"]
            self.punch = punchmod.Punch(float(ctx.clock.frame(pu["at"])), float(pu.get("peak", 1.025)),
                                        float(pu.get("out", 3)), float(pu.get("back", 5)))
            if self.punch.at <= self.settle_at:
                raise SceneError(f"{where}.mark.punch: f{self.punch.at:g} is not after the settle (f{self.settle_at:g})")
            h = self.ink_end[3] - self.ink_end[1]
            bottom = (self.ink_end[1] + self.ink_end[3]) / 2 + h / 2 * self.punch.peak
            clear = float(lay["end_tagline_cap_top_y"]) - bottom
            if clear < h / 2:
                raise SceneError(f"{where}.mark.punch: at {self.punch.peak:g}× the mark's ink reaches y {bottom:.1f}, "
                                 f"{clear:.1f} px above the tagline (cap top {lay['end_tagline_cap_top_y']}) — it keeps "
                                 f"at least half its height ({h / 2:.1f} px) clear")

    def comp(self, t: float) -> float:
        # the reveal's last rate (1.44×: 24 comp frames over 20 film frames) carries it to comp 74, then it holds
        return min(self.comp_end, self.from_comp + (t - self.start) * 24.0 / 20.0)

    def rect_at(self, t: float) -> skia.Rect:
        q = self.curve(easing.progress(t, self.settle_at - self.settle_frames, self.settle_frames))
        a, b = self.from_rect, self.to_rect
        lerp = easing.lerp
        r = skia.Rect.MakeLTRB(lerp(a.left(), b.left(), q), lerp(a.top(), b.top(), q),
                               lerp(a.right(), b.right(), q), lerp(a.bottom(), b.bottom(), q))
        s = self.punch(t) if self.punch else 1.0
        if s == 1.0:
            return r
        cx, cy = (self.ink_end[0] + self.ink_end[2]) / 2, (self.ink_end[1] + self.ink_end[3]) / 2
        return skia.Rect.MakeLTRB(cx + (r.left() - cx) * s, cy + (r.top() - cy) * s,
                                  cx + (r.right() - cx) * s, cy + (r.bottom() - cy) * s)

    def draw_picture(self, canvas: skia.Canvas, t: float, fast: bool = False, frame: int | None = None) -> None:
        self.stage.draw(canvas, self.size, self.seconds(t))
        self.player.render(canvas, self.comp(t), self.rect_at(t), self.colour)

    def record(self, f: int, rec: dict) -> None:
        r = self.rect_at(float(f))
        ink = self.player.ink_bounds(self.comp(float(f)))
        s = r.width() / self.player.size[0]
        rec["comp"] = round(self.comp(float(f)), 3)
        rec.setdefault("boxes", []).append({"kind": "mark", "label": "end mark", "rect": [
            round(r.left() + ink.left() * s, 1), round(r.top() + ink.top() * s, 1),
            round(r.left() + ink.right() * s, 1), round(r.top() + ink.bottom() * s, 1)]})

    def events(self) -> list[tuple[int, str]]:
        ev = [(int(self.settle_at - self.settle_frames), "mark eases up"), (int(self.settle_at), "mark settles")]
        if self.punch:
            ev.append((int(self.punch.at), f"mark punch {self.punch.peak:g}× on the last log"))
        return ev

    def generated(self) -> list[dict]:
        return [{"element": "the finished mark (Lottie comp 74), moved and scaled"
                            + (f", a {self.punch.peak:g}× punch on the last log" if self.punch else ""),
                 "scene": self.id, "cite": self.cite}]
