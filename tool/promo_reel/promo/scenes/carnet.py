"""Rows 1–4: the hook — the code-drawn carnet — and row 5, the AIR beat.

The page (promo/fx/carnet.py) lies at ``rest`` turned by rot_x about
``pivot``. A linear push-in is already under way on frame 0; on the cue
``macro.at`` the film HARD CUTS to a macro of the squeezed entry and cuts back
on ``macro.until``; strikes slash rows on their cues, each giving the page a
scale punch; on ``sink.from`` the camera pushes in (×1.5, easeInCubic) while
the page sinks toward black, motion-blurred. The entry being written inks on
from 30 % at f0, the margin note writes itself on its cue. Grain is added
by the film after the blur (« Grain only in the hook »).
"""

from __future__ import annotations

import skia

from ..fx import easing, punch
from ..fx.carnet import Carnet
from ..fx.projection import Pose
from .base import Blur, Scene, SceneError


class CarnetScene(Scene):
    kind = "carnet"

    def __init__(self, spec: dict, ctx, where: str):
        super().__init__(spec, ctx, where)
        c = spec.get("carnet") or {}
        F = ctx.clock.frame
        try:
            self.carnet = Carnet(seed=int(c.get("seed", 7)))
            r = c["rest"]
            self.rest = self.carnet.rest_rect(float(r["x"][0]), float(r["x"][1]), float(r["top"]))
            self.pivot = tuple(float(v) for v in c.get("pivot", (540, 1250)))
            self.rot_x = float(c.get("rot_x", 22))
            push = c["push"]
            self.push = (F(push["from"]), F(push["to"]), float(push["scale"][0]), float(push["scale"][1]))
            m = c.get("macro")
            self.macro = None
            if m:
                self.macro = dict(at=F(m["at"]), until=F(m["until"]), rot_x=float(m["rot_x"]), scale=float(m["scale"]),
                                  entry=m["focus_entry"], offset=tuple(m["focus_offset"]), to=tuple(m["focus_to"]))
            s = c["sink"]
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
        except (KeyError, TypeError, ValueError) as e:
            raise SceneError(f"{where}.carnet: {e}") from None

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
        if t >= k["at"]:
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
        light = easing.lerp(k["light"][0], k["light"][1], easing.EASE_IN(easing.progress(t, k["at"], k["frames"])))
        return {"ink": ink, "strikes": strikes, "light": light}

    # ---- drawing ------------------------------------------------------------------------

    def draw_picture(self, canvas: skia.Canvas, t: float, fast: bool = False, frame: int | None = None) -> None:
        self.stage.draw(canvas, self.size, self.seconds(t))
        self.carnet.draw(canvas, self.pose(t), self.rest, **self.page_state(t))
        # the caption band: the page goes under the stage's black from y 640 up,
        # so the white words never sit on scribbles (the macro and the push fill the frame)
        band = self.ctx.fmt.zones.get("caption_band")
        if band is not None:
            y1 = band.y1 + 80
            shader = skia.GradientShader.MakeLinear([skia.Point(0, band.y1 - 40), skia.Point(0, y1)],
                                                    [self.stage.colour, self.stage.colour & 0x00FFFFFF])
            canvas.drawRect(skia.Rect.MakeLTRB(0, 0, self.size[0], y1),
                            skia.Paint(Shader=shader, Dither=True))

    def blur_at(self, f: int) -> Blur | None:
        k = self.sink
        if k["at"] <= f < k["at"] + k["frames"]:
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
        ev.append((self.sink["at"], "push-in + sink"))
        return ev

    def generated(self) -> list[dict]:
        return [{"element": "carnet page, scribbles, strikes (rows 1–4)", "scene": self.id, "cite": self.cite}]


class AirScene(Scene):
    """Row 5: pure black, the dark pattern drifting; one word (a caption)."""

    kind = "air"

    def draw_picture(self, canvas: skia.Canvas, t: float, fast: bool = False, frame: int | None = None) -> None:
        self.stage.draw(canvas, self.size, self.seconds(t))

    def generated(self) -> list[dict]:
        return [{"element": "air beat stage (row 5)", "scene": self.id, "cite": self.cite}]
