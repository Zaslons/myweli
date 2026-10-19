"""Rows 1–4: the hook — the code-drawn carnet — and row 5, the AIR beat.

The page (promo/fx/carnet.py) lies at ``rest`` turned by rot_x about
``pivot``. A linear push-in is already under way on frame 0; on the cue
``macro.at`` the film HARD CUTS to a macro of the squeezed entry and cuts back
on ``macro.until``; strikes slash rows on their cues, each giving the page a
scale punch; on ``sink.from`` the camera pushes in (×1.5, easeInCubic) while
the page sinks toward black, motion-blurred. The entry being written inks on
from 30 % at f0, the margin note writes itself on its cue. Grain is added
by the film after the blur (« Grain only in the hook »).

``macro``, ``sink`` and the margin note are optional: the 15-s cut's one-bar
hook (storyboard « The 15 s cut », BAR 1) has no macro cut and no sink — its
three strikes run straight into the AIR.

WHERE the page lies is the format's (layout ``hook_page``: its x span, top,
the pivot of its tilt and push, and where the macro puts the squeezed
entry); the stage's black covers it under the white words (``hook_scrim``:
an opaque rectangle fading out to its right and below; ``hook_scrim.macro``,
when given, is the one the macro shot uses — 16:9: only behind the question,
so the margin note writes itself in view) — 9:16: the page fills y ≈
700–1700 under a band to y 520 (gone by 640); 1:1: the page fills the square
under the band, every strike row inside the graphics-safe area; 16:9: the
page lies across the frame's right, the words top-left on black.

THE INK IS SEEN (review round 3: in 1:1 the third strike was drawn below the
frame; in 16:9 the margin note wrote itself under the black). Every piece of
ink the hook animates — each strike over its 4 frames and its punch, each
inking entry over its frames — is checked where it lands
(``ink_places``): inside the canvas, inside the format's safe area where that
area is graphics-safe (EBU R95: 1:1, 16:9 — 9:16's platform rectangle is the
TEXT area, and the approved page lies at y ≈ 700–1700, below it; reported,
not refused), and never under the scrim (at most ``INK_SCRIM_MAX`` of it
dimmed, on average over its box). A layout that breaks it is refused.
"""

from __future__ import annotations

import math

import numpy as np
import skia

from ..fx import easing, punch
from ..fx.carnet import Carnet
from ..fx.projection import Pose
from .base import Blur, Scene, SceneError

#: the stage's black may dim a piece of animated ink this much at most, on average over its box
INK_SCRIM_MAX = 0.15


def scrim_alpha(scrim, x: float, y: float) -> float:
    """The scrim's opacity at (x, y): 1 over its rectangle, fading to 0 over
    `fade` px to its right and below (both fades multiplied, as drawn)."""
    (x0, y0, x1, y1), (fr, fb) = scrim
    if x < x0 or y < y0:
        return 0.0
    ax = 1.0 if x <= x1 else (max(0.0, 1.0 - (x - x1) / fr) if fr > 0 else 0.0)
    ay = 1.0 if y <= y1 else (max(0.0, 1.0 - (y - y1) / fb) if fb > 0 else 0.0)
    return ax * ay


def _scrim(spec: dict) -> tuple:
    return tuple(float(v) for v in spec["rect"]), tuple(float(v) for v in spec["fade"])


class CarnetScene(Scene):
    kind = "carnet"

    def __init__(self, spec: dict, ctx, where: str):
        super().__init__(spec, ctx, where)
        c = spec.get("carnet") or {}
        F = ctx.clock.frame
        try:
            for key in ("rest", "pivot"):
                if key in c:
                    raise SceneError(f"{where}.carnet.{key}: where the page lies is the format's (layout.hook_page)")
            page = ctx.layout["hook_page"]
            self.carnet = Carnet(seed=int(c.get("seed", 7)))
            self.rest = self.carnet.rest_rect(float(page["x"][0]), float(page["x"][1]), float(page["top"]))
            self.pivot = tuple(float(v) for v in page["pivot"])
            sc = ctx.layout["hook_scrim"]
            self.scrim = _scrim(sc)
            self.macro_scrim = _scrim(sc["macro"]) if sc.get("macro") else None
            self.rot_x = float(c.get("rot_x", 22))
            push = c["push"]
            self.push = (F(push["from"]), F(push["to"]), float(push["scale"][0]), float(push["scale"][1]))
            m = c.get("macro")
            self.macro = None
            if m:
                if "focus_to" in m:
                    raise SceneError(f"{where}.carnet.macro.focus_to: where the macro puts the entry is the "
                                     f"format's (layout.hook_page.macro_to)")
                self.macro = dict(at=F(m["at"]), until=F(m["until"]), rot_x=float(m["rot_x"]), scale=float(m["scale"]),
                                  entry=m["focus_entry"], offset=tuple(m["focus_offset"]),
                                  to=tuple(float(v) for v in page["macro_to"]))
            s = c.get("sink")
            self.sink = None
            if s:
                self.sink = dict(at=F(s["from"]), frames=float(s["frames"]), scale=tuple(s["scale"]),
                                 light=tuple(s["light"]), blur=int(s.get("blur", 8)))
            self.ink = []
            for i, k in enumerate(c.get("ink") or []):
                a = F(k["from"])
                n = (F(k["to"]) - a) if "to" in k else float(k["frames"])
                self.ink.append((k["entry"], a, n, float(k.get("start", 0.0))))
            self.strikes = [(self.carnet.write_row + int(s_["row"]), F(f"cue:{s_['cue']}")) for s_ in c.get("strikes") or []]
            pc = c.get("punch") or {}
            self.punches = punch.Punches([punch.Punch(F(f"cue:{q}"), float(pc.get("peak", 1.025)))
                                          for q in pc.get("cues", [])])
        except SceneError:
            raise
        except (KeyError, TypeError, ValueError) as e:
            raise SceneError(f"{where}.carnet: {e}") from None
        self._check_ink(where)

    # ---- the ink is seen ------------------------------------------------------------------

    def scrim_at(self, t: float):
        """The scrim on frame t: the macro's own while the macro shows, else the layout's."""
        return self.macro_scrim if self.macro_scrim is not None and self.in_macro(t) else self.scrim

    def _box(self, pts, pose, grow: float = 0.0) -> tuple[float, float, float, float]:
        q = [self.carnet.page_point(x, y, pose, self.rest) for x, y in pts]
        return (min(p[0] for p in q) - grow, min(p[1] for p in q) - grow,
                max(p[0] for p in q) + grow, max(p[1] for p in q) + grow)

    def _dimmed(self, box, t: float) -> float:
        """The scrim's mean opacity over `box` on frame t."""
        sc = self.scrim_at(t)
        xs, ys = np.linspace(box[0], box[2], 9), np.linspace(box[1], box[3], 5)
        return float(np.mean([scrim_alpha(sc, x, y) for x in xs for y in ys]))

    def ink_places(self) -> list[dict]:
        """Where each piece of ink the hook ANIMATES lands on the frames it is
        drawn: every strike (its 4 frames and its punch — the full stroke,
        caps included) and every inking entry (`write`, the margin note):
        the union of its ink box over those frames (frame px), the most the
        scrim dims it (mean opacity over the box) and whether it lies inside
        the canvas and the safe area."""
        w, h = self.size
        safe = self.ctx.fmt.safe
        k = (self.rest[2] - self.rest[0]) / self.carnet.size[0]
        items = []
        for row, at in self.strikes:
            a, b = self.carnet.strike_segment(row)
            items.append((f"strike row {row}", int(at), int(at) + 8, [a, b], self.carnet.strike_width() * k / 2))
        for entry, a, n, _start in self.ink:
            x0, y0, x1, y1 = self.carnet.entries[entry].bounds
            items.append((f"ink « {entry} »", int(math.floor(a)), int(math.ceil(a + n)),
                          [(x0, y0), (x1, y0), (x0, y1), (x1, y1)], 0.0))
        out = []
        for what, f0, f1, pts, half in items:
            frames = [f for f in range(f0, f1 + 1) if self.start <= f < self.end]
            boxes, dim = [], 0.0
            for f in frames:
                pose = self.pose(float(f))
                b = self._box(pts, pose, half * pose.scale)
                boxes.append(b)
                dim = max(dim, self._dimmed(b, float(f)))
            u = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
            row = {"what": what, "frames": [frames[0], frames[-1]], "box": [round(v, 1) for v in u],
                   "scrim": round(dim, 3),
                   "in_canvas": u[0] >= 0 and u[1] >= 0 and u[2] <= w and u[3] <= h,
                   "in_safe": u[0] >= safe.x0 and u[1] >= safe.y0 and u[2] <= safe.x1 and u[3] <= safe.y1}
            if what.startswith("strike"):
                # where verify reads the stroke off the MP4: its last frame, drawn whole and the punch settled
                f = frames[-1]
                pose = self.pose(float(f))
                (ax, ay), (bx, by) = (self.carnet.page_point(x, y, pose, self.rest) for x, y in pts)
                row["line"] = {"frame": f, "p0": [round(ax, 1), round(ay, 1)], "p1": [round(bx, 1), round(by, 1)],
                               "width": round(2 * half * pose.scale, 2)}
            out.append(row)
        return out

    def _check_ink(self, where: str) -> None:
        """Refuse a layout that draws the hook's animated ink where it cannot
        be seen: off the canvas, outside a graphics-safe area (EBU R95), or
        under the scrim."""
        fmt = self.ctx.fmt
        graphics_safe = fmt.safe_basis == "ebu_r95_graphics"
        problems = []
        for p in self.ink_places():
            at = f"the hook's {p['what']} (f{p['frames'][0]}–f{p['frames'][1]}, ink x {p['box'][0]:g}–" \
                 f"{p['box'][2]:g}, y {p['box'][1]:g}–{p['box'][3]:g})"
            if not p["in_canvas"]:
                problems.append(f"{at} runs off the {fmt.width}×{fmt.height} canvas: its sound plays with nothing "
                                f"on screen (layout.hook_page)")
            elif graphics_safe and not p["in_safe"]:
                problems.append(f"{at} leaves the graphics-safe area {fmt.safe} (layout.hook_page)")
            if p["scrim"] > INK_SCRIM_MAX:
                problems.append(f"{at} is under the stage's black ({p['scrim']:.0%} of it, at most "
                                f"{INK_SCRIM_MAX:.0%}): layout.hook_scrim (or its `macro`)")
        if problems:
            raise SceneError(f"{where} ({fmt.id}): " + "; ".join(problems) + " — the ink must be seen")

    # ---- state at t -------------------------------------------------------------------

    def in_macro(self, t: float) -> bool:
        return self.macro is not None and self.macro["at"] <= t < self.macro["until"]

    def pose(self, t: float) -> Pose:
        if self.in_macro(t):
            m = self.macro
            p = Pose(rot_x=m["rot_x"], scale=m["scale"], pivot=self.pivot)
            ax0, _, _, _ = self.carnet.entries["arrow"].bounds
            _, sy = self.carnet.entry_centre(m["entry"])
            # a slow drift on the macro: 2 % over the shot
            drift = easing.progress(t, m["at"], m["until"] - m["at"]) * 0.02
            p = p.but(scale=m["scale"] * (1 + drift))
            return self.carnet.focus(p, self.rest, (ax0 + m["offset"][0], sy + m["offset"][1]), m["to"])
        a, b, s0, s1 = self.push
        s = easing.lerp(s0, s1, easing.progress(t, a, b - a))
        k = self.sink
        if k is not None and t >= k["at"]:
            s *= easing.lerp(k["scale"][0], k["scale"][1], easing.EASE_IN_CUBIC(easing.progress(t, k["at"], k["frames"])))
        s *= self.punches(t)
        return Pose(rot_x=self.rot_x, pivot=self.pivot, scale=s)

    def page_state(self, t: float) -> dict:
        ink = {}
        for entry, a, n, start in self.ink:
            if entry == "write":
                ink[entry] = easing.lerp(start, 1.0, easing.progress(t, a, n))
            elif t >= a - 1:
                ink[entry] = easing.EASE_OUT(easing.progress(t, a - 1, n))
            elif self.in_macro(t) or t >= a:
                ink[entry] = 0.0
        strikes = {row: easing.progress(t, at, 4) for row, at in self.strikes if t >= at}
        k = self.sink
        light = 1.0 if k is None else \
            easing.lerp(k["light"][0], k["light"][1], easing.EASE_IN(easing.progress(t, k["at"], k["frames"])))
        return {"ink": ink, "strikes": strikes, "light": light}

    # ---- drawing ------------------------------------------------------------------------

    def draw_picture(self, canvas: skia.Canvas, t: float, fast: bool = False, frame: int | None = None) -> None:
        self.stage.draw(canvas, self.size, self.seconds(t))
        self.carnet.draw(canvas, self.pose(t), self.rest, **self.page_state(t))
        self.draw_scrim(canvas, t)

    def draw_scrim(self, canvas: skia.Canvas, t: float = 0.0) -> None:
        """The stage's black over the page under the white words (the
        format's hook_scrim — the macro's own while the macro shows), so they
        never sit on scribbles — the macro and the push fill the frame:
        opaque over its rectangle, fading to nothing over `fade` px to its
        right and below (9:16: to y 520, gone by 640)."""
        (x0, y0, x1, y1), (fr, fb) = self.scrim_at(t)
        colour, clear = self.stage.colour, self.stage.colour & 0x00FFFFFF
        X1, Y1 = x1 + fr, y1 + fb
        if fr <= 0:
            shader = skia.GradientShader.MakeLinear([skia.Point(0, y1), skia.Point(0, Y1)], [colour, clear])
            canvas.drawRect(skia.Rect.MakeLTRB(x0, y0, X1, Y1), skia.Paint(Shader=shader, Dither=True))
            return
        # fading both ways: the colour, then each edge's fade multiplied in (a soft corner)
        canvas.saveLayer(skia.Rect.MakeLTRB(x0, y0, X1, Y1), None)
        canvas.drawRect(skia.Rect.MakeLTRB(x0, y0, X1, Y1), skia.Paint(Color=colour))
        for a, b in (((x1, 0), (X1, 0)), ((0, y1), (0, Y1))):
            if a == b:
                continue
            fade = skia.GradientShader.MakeLinear([skia.Point(*a), skia.Point(*b)], [0xFF000000, 0x00000000])
            canvas.drawRect(skia.Rect.MakeLTRB(x0, y0, X1, Y1),
                            skia.Paint(Shader=fade, BlendMode=skia.BlendMode.kDstIn, Dither=True))
        canvas.restore()

    def blur_at(self, f: int) -> Blur | None:
        k = self.sink
        if k is not None and k["at"] <= f < k["at"] + k["frames"]:
            return Blur(k["blur"], 1.0, None)
        return None

    def record(self, f: int, rec: dict) -> None:
        rec["view"] = "macro" if self.in_macro(f) else "wide"

    def events(self) -> list[tuple[int, str]]:
        ev = []
        if self.macro:
            ev += [(self.macro["at"], "cut: macro"), (self.macro["until"], "cut: wide")]
        ev += [(at, f"strike row {row}") for row, at in self.strikes]
        ev += [(a, f"ink {entry}") for entry, a, n, s in self.ink]
        if self.sink is not None:
            ev.append((self.sink["at"], "push-in + sink"))
        return ev

    def generated(self) -> list[dict]:
        return [{"element": f"carnet page, scribbles, strikes (the hook, {self.id})", "scene": self.id, "cite": self.cite}]


class AirScene(Scene):
    """Row 5: pure black, the dark pattern drifting; one word (a caption)."""

    kind = "air"

    def draw_picture(self, canvas: skia.Canvas, t: float, fast: bool = False, frame: int | None = None) -> None:
        self.stage.draw(canvas, self.size, self.seconds(t))

    def generated(self) -> list[dict]:
        return [{"element": f"air beat stage (no UI, {self.id})", "scene": self.id, "cite": self.cite}]
