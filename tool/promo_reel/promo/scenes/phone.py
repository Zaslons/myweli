"""Rows 6–22: the phone scenes — real pictures of a take in a 2.5D slab, seen
through the camera window, with the storyboard's touches, lifts, stacked
tiles, the counter and the map credit drawn over them.

Per frame t (a float: motion-blur subframes are fractional):
  * the picture is the take's picture at the timeline's take time (masked);
  * the camera puts screen point W(t) on the band edge (y 600), zooms about
    its anchor (px_per_pt ÷ 1.791), and the slam / tilt / fall / parallax
    keys turn and move the slab (promo/fx/phone.py, projection.py);
  * touch discs sit in screen points under the same matrix, from the
    measured touch-down (never from a typed time): the YAML's ``at`` is
    checked to be the frame the touch-down lands on, and its ``tone`` to be
    what the ground under the finger asks for (frames.py tone());
  * lifts and stacked tiles are the take's own (masked) pixels, magnified.

Everything the frame shows that a check needs — the picture, the touch-downs,
every box, how much of a hidden row shows — goes in the frame's record.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
import skia

from ..fx import easing, lift as liftmod, punch, stack as stackmod
from ..fx import touch as touchmod
from ..fx import type as ty
from ..fx.brand import PALETTE, inter, poppins
from ..fx.counter import Odometer, draw_label_switch, landing_overrun, landing_progress
from ..fx.phone import Phone, PhoneSpec, Window
from ..fx.projection import Pose
from ..fx.surface import SAMPLING_CUBIC
from ..media import touches as touches_mod
from .base import Blur, Scene, SceneError, blur_for_track, track
from .sources import SourceError, Timeline

#: A tap's disc stays at least this long (take seconds) when the log says it
#: was not held — the App Store film's taps showed 0.3 s.
MIN_PRESS_S = 0.2


def window_for(fmt) -> Window:
    z, lay = fmt.zones, fmt.layout
    pw = z["phone_window"]
    band_fade = pw.y0 - z["caption_fade"].y0 if "caption_fade" in z else 30.0
    floor_fade = z["floor_fade"].height if "floor_fade" in z else 24.0
    return Window(screen_x=float(lay["phone_screen_x"][0]), top=float(pw.y0), band_fade=float(band_fade),
                  floor=float(pw.y1), floor_fade=float(floor_fade), px_per_pt=float(lay["px_per_pt"]))


def phone_spec(fmt) -> PhoneSpec:
    lay = fmt.layout
    return PhoneSpec(px_per_pt=float(lay["px_per_pt"]), crop_top_pt=float(lay["screen_crop_top_pt"]),
                     bezel=float(lay["phone_bezel_px"]), radius=float(lay["phone_radius_px"]))


@dataclass
class TouchPlan:
    gesture: str
    kind: str                     # tap | drag
    down_s: float
    down_f: float
    up_f: float
    tone: str
    at_pt: tuple[float, float]
    path: list | None             # [(take s, x, y)] for a followed drag
    follow_scroll: bool = False
    first_change_f: float | None = None
    style: touchmod.TouchStyle = touchmod.STYLE

    @property
    def gone_f(self) -> float:
        """The first frame with nothing of the disc or its ripple left."""
        end = self.up_f + self.style.fade_out_frames
        return max(end, self.down_f + self.style.ripple_frames) if self.kind == "tap" else end


class PhoneScene(Scene):
    kind = "phone"

    def __init__(self, spec: dict, ctx, where: str):
        super().__init__(spec, ctx, where)
        F = ctx.clock.frame
        self.window = window_for(ctx.fmt)
        self.band_rows = (0, int(self.window.top - self.window.band_fade), ctx.fmt.width,
                          int(math.ceil(self.window.floor + self.window.floor_fade)))
        try:
            self.source = ctx.source(spec["take"])
            self.source.add_masks(spec.get("masks") or [], where)
            self.timeline = Timeline(self.source, spec.get("timeline") or [], ctx.clock, ctx.fps, where)
        except (KeyError, SourceError) as e:
            raise SceneError(f"{where}: {e}") from None
        cam = spec.get("camera") or {}
        self.W = track(ctx, cam.get("W"), f"{where}.camera.W")
        if not self.W:
            raise SceneError(f"{where}.camera.W: a phone scene needs its camera window")
        self.zoom = track(ctx, cam.get("zoom"), f"{where}.camera.zoom", 1.0)
        slam = cam.get("slam") or {}
        self.slam_scale = track(ctx, slam.get("scale"), f"{where}.camera.slam.scale", 1.0)
        self.slam_rot = track(ctx, slam.get("rot_x"), f"{where}.camera.slam.rot_x", 0.0)
        fall = cam.get("fall")
        self.fall = None
        if fall:
            a = F(fall["at"])
            n = float(fall["frames"])
            self.fall = (a, n, tuple(map(float, fall["scale"])), tuple(map(float, fall["opacity"])))
        par = cam.get("parallax")
        self.parallax = None
        if par:
            self.parallax = (F(par["from"]), F(par["to"]), float(par["phone_dy"]), float(par["pattern"]))
        self.phone = Phone(self.source.picture(self.timeline.index(self.start)), phone_spec(ctx.fmt))
        self.touches = [self._touch(t, f"{where}.touches[{i}]") for i, t in enumerate(spec.get("touches") or [])]
        self.lifts = [self._lift(l, f"{where}.lifts[{i}]") for i, l in enumerate(spec.get("lifts") or [])]
        self.stack = self._stack(spec["stack"], f"{where}.stack") if spec.get("stack") else None
        self.counter = self._counter(spec["counter"], f"{where}.counter") if spec.get("counter") else None
        self.credit = self._credit(spec["credit"], f"{where}.credit") if spec.get("credit") else None
        self.hidden = []
        for i, h in enumerate(spec.get("hidden") or []):
            if "src_s" in h:
                raise SceneError(f"{where}.hidden[{i}]: `src_s` is gone — every frame of the scene is checked; "
                                 f"give `shown_on` (a picture that shows the row) instead")
            try:
                shown = float(self.source.resolve(h["shown_on"], f"{where}.hidden[{i}].shown_on"))
            except (KeyError, SourceError) as e:
                raise SceneError(f"{where}.hidden[{i}]: {e}") from None
            self.hidden.append((h["label"], tuple(map(float, h["rect_pt"])), shown))
        self.figure = None
        if spec.get("figure_picture") is not None:
            fs = self.source.resolve(spec["figure_picture"], f"{where}.figure_picture")
            self.figure = (self.source.take.index_at(fs), self.timeline.frame_of(fs))
            if self.counter and (self.figure[1] is None or abs(self.figure[1] - self.counter["land"]) > 1e-6):
                raise SceneError(f"{where}: the counter lands on f{self.counter['land']}, but the app first shows "
                                 f"its figure on f{self.figure[1]} — they must be the same frame")

    # ---- parsing helpers -----------------------------------------------------------------

    def _touch(self, t: dict, where: str) -> TouchPlan:
        F = self.ctx.clock.frame
        try:
            d = self.source.down(t["gesture"])
        except (KeyError, SourceError) as e:
            raise SceneError(f"{where}: {e}") from None
        if d.kind not in ("tap", "drag"):
            raise SceneError(f"{where}: {t['gesture']} is a typed key: no touch point may be drawn")
        down_f = self.timeline.frame_of(d.down_s)
        want = F(t["at"])
        if down_f is None or abs(down_f - want) > 1e-6:
            raise SceneError(f"{where}: the touch-down of {t['gesture']} ({d.down_s:.4f} s) lands on "
                             f"f{down_f if down_f is None else round(down_f, 3)}, not on {t['at']} (f{want}): "
                             f"the timeline and the touch disagree")
        path = None
        follow_scroll = t.get("follow") == "scroll"
        first_change_f = None
        if d.kind == "tap":
            up_s = d.down_s + max(d.held_s or 0.0, MIN_PRESS_S)
            up_f = self.timeline.frame_of(up_s)
            if up_f is None:
                up_f = down_f + MIN_PRESS_S * self.ctx.fps
        elif follow_scroll:
            first_change_f = self.timeline.frame_of(d.first_change_s)
            seg = next(s for s in self.timeline.segments if s.kind == "scroll")
            up_f = seg.end + 3            # the finger rests ~96 ms at the end (take5b notes)
        else:
            path = touches_mod.finger_path(self.source.name, t["gesture"])
            up_f = self.timeline.frame_of(path[-1][0])
            if up_f is None:
                raise SceneError(f"{where}: the drag's lift ({path[-1][0]:.3f} s) is not in the timeline")
        style = touchmod.STYLE
        if t.get("release_by") is not None:
            # the finger lifted at once (the log says it was not held): the disc and its ripple are gone by
            # this frame — before the page the tap opens moves under them (storyboard row 10, review n1)
            if d.kind != "tap":
                raise SceneError(f"{where}.release_by: only a tap is released early")
            gone = float(F(t["release_by"]))
            span = gone - down_f
            if span < style.fade_in_frames:
                raise SceneError(f"{where}.release_by: f{gone:g} leaves the disc {span:g} frames; it needs "
                                 f"{style.fade_in_frames:g} to appear")
            from dataclasses import replace
            style = replace(style, fade_out_frames=span, ripple_frames=span)
            up_f = down_f
        tone = t.get("tone", "dark")
        rgba = self.source.rgba(self.source.take.index_at(d.down_s))
        k = self.source.take.px_per_pt
        measured = touchmod.tone_at(rgba, d.at_pt[0] * k, d.at_pt[1] * k, touchmod.STYLE.diameter_pt * k)
        if measured != tone:
            raise SceneError(f"{where}: {t['gesture']} lands on a ground that asks for a {measured} disc, "
                             f"the storyboard says {tone}")
        return TouchPlan(t["gesture"], d.kind, d.down_s, down_f, up_f, tone, tuple(map(float, d.at_pt)), path,
                         follow_scroll, first_change_f, style)

    def _lift(self, l: dict, where: str) -> dict:
        F = self.ctx.clock.frame
        s = self.source.resolve(l["picture"], f"{where}.picture")
        idx = self.source.take.index_at(s)
        rect_pt = tuple(map(float, l["rect_pt"]))
        k = self.source.take.px_per_pt
        src = tuple(v * k for v in rect_pt)
        tg = l["target"]
        x0, x1 = map(float, tg["x"])
        kw = {n: float(tg[n]) for n in ("top", "bottom", "centre_y") if n in tg}
        target = liftmod.fit_width(src, x0, x1, **kw)
        if "up" in l:
            up = float(F(l["up"]))
        elif "lands" in l:
            up = float(F(l["lands"])) - 5.0            # a 6-frame pop: [up − 1, up + 5] lands on `lands`
        else:
            raise SceneError(f"{where}: give `up` or `lands`")
        down = float(F(l["down"])) if l.get("down") else None
        return {"id": l.get("id", where), "index": idx, "rect_pt": rect_pt, "src": src, "target": target,
                "up": up, "down": down, "veil": float(l.get("veil", self.ctx.layout["lift_veil"]))}

    def _stack(self, s: dict, where: str) -> dict:
        F = self.ctx.clock.frame
        idx = self.source.take.index_at(self.source.resolve(s["picture"], f"{where}.picture"))
        tiles = [tuple(map(float, r)) for r in s["tiles_pt"]]
        k = self.source.take.px_per_pt
        srcs = [tuple(v * k for v in r) for r in tiles]
        lay = s.get("layout") or {}
        x0, x1 = map(float, lay.get("x", self.ctx.layout["lift_x"]))
        gap = float(lay.get("gap", 16))
        if lay.get("axis", "vertical") == "horizontal":
            ratio = sum((r[2] - r[0]) / (r[3] - r[1]) for r in srcs)
            h = (x1 - x0 - gap * (len(srcs) - 1)) / ratio
            targets = stackmod.stack_rects(srcs, x0=x0, gap=gap, axis="horizontal",
                                           y0=float(lay["centre_y"]) - h / 2, height=h)
        else:
            targets = stackmod.stack_rects(srcs, x0=x0, width=x1 - x0, gap=gap, centre_y=float(lay["centre_y"]))
        ups = [float(F(u)) for u in s["ups"]]
        backdrop = None
        if s.get("backdrop"):
            bd = s["backdrop"]
            from ..fx.brand import BrandError, token
            try:
                colour = token(bd["colour"])
            except (KeyError, ValueError, BrandError) as e:
                raise SceneError(f"{where}.backdrop.colour: an app colour token (colors.dart): {e}") from None
            backdrop = (colour, float(bd.get("pad", 24)), float(bd.get("radius", 24)), bd["colour"], bd.get("cite"))
        return {"index": idx, "tiles_pt": tiles, "srcs": srcs, "targets": targets, "ups": ups,
                "veil": float(s.get("veil", self.ctx.layout["lift_veil"])), "backdrop": backdrop}

    def _counter(self, c: dict, where: str) -> dict:
        F = self.ctx.clock.frame
        tp = self.ctx.layout["type_px"]
        roll = c["roll"]
        out = {"start": int(c["start"]), "end": int(c["end"]), "labels": list(c["labels"]),
               "switch": float(F(c["label_switch"])), "from": float(F(roll["from"])), "land": float(F(roll["to"])),
               "punch_at": float(F(c["punch"]["at"])), "punch_start": float(c["punch"].get("start", 1.08)),
               "punch_frames": float(c["punch"].get("frames", 5)),
               "exit": float(F(c["exit"]["at"])) if c.get("exit") else None,
               "exit_frames": float(c["exit"].get("frames", 6)) if c.get("exit") else 6.0,
               "label_baseline": float(c.get("label_baseline", 360)), "figure_baseline": float(c.get("figure_baseline", 505)),
               "cite": c.get("cite")}
        out["odo"] = Odometer(out["start"], out["end"], poppins(tp["counter"]), PALETTE.INK)
        out["label_font"] = inter(tp["counter_label"])
        # the roll lands with a snap: its curve runs `overrun` frames past the
        # landing, so no frame before it reads the figure (nor more)
        if roll.get("overrun") is not None:
            out["overrun"] = float(roll["overrun"])
        else:
            try:
                out["overrun"] = float(landing_overrun(out["odo"], out["from"] - 1, out["land"]))
            except ValueError as e:
                raise SceneError(f"{where}.roll: {e}") from None
        self.counter = out
        self._check_counter(where)
        return out

    def _roll(self, t: float) -> float:
        c = self.counter
        return landing_progress(t, c["from"] - 1, c["land"], c["overrun"])

    def _check_counter(self, where: str) -> None:
        """The counter never reads the app's figure before the frame the app
        first shows it, and never reads a value above it (an odometer whose
        columns settle one by one can pass 77 099 on its way to 77 000)."""
        c = self.counter
        odo, figure = c["odo"], c["end"]
        text = odo.text_at(1.0)
        for f in range(self.start, self.end):
            p = self._roll(float(f))
            v = odo.value_at(p)
            if v > figure:
                raise SceneError(f"{where}: on f{f} the counter reads « {odo.text_at(p)} », above the app's figure "
                                 f"« {text} »")
            if f < c["land"] and v == figure:
                raise SceneError(f"{where}: on f{f} the counter already reads « {text} »; the app first shows it "
                                 f"on f{c['land']:g}")

    def _credit(self, c: dict, where: str) -> dict:
        return {"text": c["text"], "map": tuple(map(float, c["map_rect_pt"])), "x": float(c["x"]),
                "baseline": float(c["baseline"]), "font": inter(self.ctx.layout["type_px"]["credit"]),
                "cite": c.get("cite"), "track": next((m.track for m in self.source.blurs if m.track), None)}

    # ---- camera ----------------------------------------------------------------------------

    def fall_state(self, t: float) -> tuple[float, float]:
        if not self.fall:
            return 1.0, 1.0
        a, n, (s0, s1), (o0, o1) = self.fall
        q = easing.progress(t, a - 1, n)
        return easing.lerp(s0, s1, easing.EASE_IN(q)), easing.lerp(o0, o1, easing.EASE_IN(q))

    def parallax_dy(self, t: float) -> tuple[float, float]:
        if not self.parallax:
            return 0.0, 0.0
        a, b, dy, k = self.parallax
        d = dy * easing.EASE_IN_OUT(easing.progress(t, a, b - a))
        return d, d * k

    def pose(self, t: float) -> Pose:
        W = self.W(t)
        zoom = self.zoom(t)
        fall_s, _ = self.fall_state(t)
        scale = zoom * self.slam_scale(t) * fall_s
        pivot = None
        if abs(zoom - 1.0) > 1e-9:
            anchor_pt = self.zoom.extra_at(t, "anchor_pt")
            anchor_y = self.zoom.extra_at(t, "anchor_y")
            y = float(anchor_y) if anchor_y is not None else self.window.y_of(float(anchor_pt), W)
            pivot = (self.ctx.fmt.width / 2, y)
        dy, _ = self.parallax_dy(t)
        return Pose(rot_x=self.slam_rot(t), scale=scale, dy=dy, pivot=pivot)

    def where(self, t: float) -> dict:
        return {"W": self.W(t), "window": self.window}

    # ---- touches -----------------------------------------------------------------------------

    def finger(self, tp: TouchPlan, t: float) -> tuple[float, float]:
        if tp.kind == "tap":
            return tp.at_pt
        if tp.follow_scroll:
            x, y0 = tp.at_pt
            slop = 18.0
            if t < tp.first_change_f:
                q = (t - tp.down_f) / max(1e-6, tp.first_change_f - tp.down_f)
                return x, y0 - slop * min(1.0, max(0.0, q))
            u = self.timeline.scroll_progress(t)
            if u is None:
                u = 1.0
            # the logged drag: 370 → 80 pt (290 pt), the content following past the slop
            target = self.timeline.index(t)
            seg = next(s for s in self.timeline.segments if s.kind == "scroll")
            idx, vals, a, b = seg.scroll
            sv = vals[idx.index(target)] if target in idx else b
            frac = (sv - a) / (b - a) if b > a else 1.0
            return x, y0 - slop - (290.0 - slop) * frac
        s = self.timeline.src(t)
        pts = tp.path
        if s <= pts[0][0]:
            return pts[0][1], pts[0][2]
        for (ta, xa, ya), (tb, xb, yb) in zip(pts, pts[1:]):
            if s <= tb:
                u = (s - ta) / (tb - ta) if tb > ta else 1.0
                return xa + (xb - xa) * u, ya + (yb - ya) * u
        return pts[-1][1], pts[-1][2]

    def _touch_overlay(self, t: float):
        def draw(canvas: skia.Canvas) -> None:
            for tp in self.touches:
                if t < tp.down_f - 1 or t > tp.gone_f + 1:
                    continue
                x, y = self.finger(tp, t)
                if tp.kind == "tap":
                    touchmod.draw_tap(canvas, x, y, t, tp.down_f, tp.up_f, tone=tp.tone, style=tp.style)
                else:
                    touchmod.draw_touch(canvas, x, y, tone=tp.tone, style=tp.style,
                                        alpha=touchmod.touch_alpha(t, tp.down_f, tp.up_f, tp.style))
        return draw

    # ---- drawing -------------------------------------------------------------------------------

    def draw_picture(self, canvas: skia.Canvas, t: float, fast: bool = False, frame: int | None = None) -> None:
        _, pdy = self.parallax_dy(t)
        self.stage.draw(canvas, self.size, self.seconds(t), offset=(0.0, pdy))
        _, opacity = self.fall_state(t)
        # a subframe shows its own take picture only where the timeline asks to
        # blend the app's frames; under a camera move the frame's picture holds
        pic_t = t if frame is None or self.timeline.blur_at(frame) else float(frame)
        self.phone.set_screen(self.source.picture(self.timeline.index(pic_t)))
        self.phone.draw(canvas, self.pose(t), W=self.W(t), window=self.window, opacity=opacity,
                        overlay=self._touch_overlay(t), sampling=SAMPLING_CUBIC if fast else None)

    def blur_at(self, f: int) -> Blur | None:
        px = self.window.px_per_pt * self.zoom(f)
        b = blur_for_track(self.W, f, px, region=self.band_rows)
        n = self.timeline.blur_at(f)
        if n:
            b = Blur(max(n, b.samples if b else 0), b.shutter if b else 0.5, self.band_rows, ui=True)
        return b

    def _veil_rect(self) -> tuple[float, float, float, float]:
        return (0.0, self.window.top - self.window.band_fade, float(self.ctx.fmt.width),
                self.window.floor + self.window.floor_fade)

    def draw_overlays(self, canvas: skia.Canvas, f: int, rec: dict) -> None:
        t = float(f)
        pose, W = self.pose(t), self.W(t)
        boxes = rec.setdefault("boxes", [])
        # lifts
        for L in self.lifts:
            p = liftmod.pop_progress(t, L["up"], 6.0, L["down"], 5.0)
            if p <= 0:
                continue
            origin = self.phone.map_rect(L["rect_pt"], pose, W=W, window=self.window)
            lf = liftmod.Lift(self.source.picture(L["index"]), L["src"], origin, L["target"],
                              liftmod.LiftStyle(veil_opacity=L["veil"]))
            lf.draw(canvas, p, veil_rect=self._veil_rect() if L["veil"] > 0 else None)
            boxes.append({"kind": "lift", "label": L["id"], "rect": [round(v, 1) for v in lf.rect(p)]})
        # stacked tiles
        if self.stack:
            S = self.stack
            if t >= min(S["ups"]) - 1:
                origins = [self.phone.map_rect(r, pose, W=W, window=self.window) for r in S["tiles_pt"]]
                st = stackmod.Stack(self.source.picture(S["index"]), S["srcs"], origins, S["targets"], S["ups"],
                                    style=liftmod.LiftStyle(veil_opacity=S["veil"]))
                st.draw(canvas, t, veil_rect=self._veil_rect(), backdrop=S["backdrop"][:3] if S["backdrop"] else None)
                for i, lf in enumerate(st.lifts):
                    p = st.progress(i, t)
                    if p > 0:
                        boxes.append({"kind": "lift", "label": f"tile{i + 1}", "rect": [round(v, 1) for v in lf.rect(p)]})
        # the counter, alone in the band
        if self.counter:
            self._draw_counter(canvas, t, boxes)
        # the map credit on the floor
        if self.credit:
            a = self._credit_alpha(t)
            if a > 0:
                c = self.credit
                ty.draw_text(canvas, c["text"], c["font"], c["x"], c["baseline"], PALETTE.INK_TERTIARY, alpha=a)
                x0, y0, x1, y1 = ty.ink_bounds(c["text"], c["font"], c["x"], c["baseline"])
                boxes.append({"kind": "credit", "label": "map credit", "rect": [round(x0, 1), round(y0, 1),
                                                                                round(x1, 1), round(y1, 1)]})
        # the touch discs, in frame px, for the safe-zone check
        for tp in self.touches:
            if tp.down_f - 1 <= t < tp.gone_f:
                x, y = self.finger(tp, t)
                fx, fy = self.phone.map_point(x, y, pose, W=W, window=self.window)
                d = tp.style.diameter_pt
                if tp.kind == "tap":
                    st = touchmod.ripple_state(t, tp.down_f, tp.style)
                    if st:
                        d = max(d, st[0])
                r = d / 2 * self.window.px_per_pt * pose.scale
                # the disc rides the phone layer: under the band and the floor it does not show
                top = self.window.top - self.window.band_fade
                bottom = self.window.floor + self.window.floor_fade
                y0, y1 = max(fy - r, top), min(fy + r, bottom)
                if y1 <= y0 or max(self.window.alpha_at(y) for y in np.linspace(y0, y1, 9)) < 0.05:
                    continue
                boxes.append({"kind": "touch", "label": tp.gesture,
                              "rect": [round(fx - r, 1), round(y0, 1), round(fx + r, 1), round(y1, 1)]})

    def _draw_counter(self, canvas: skia.Canvas, t: float, boxes: list) -> None:
        c = self.counter
        alpha, dy = 1.0, 0.0
        if c["exit"] is not None and t >= c["exit"] - 1:
            q = easing.progress(t, c["exit"] - 1, c["exit_frames"])
            alpha, dy = 1.0 - easing.EASE_IN(q), -20.0 * easing.EASE_IN(q)      # up and out, inside the safe area
            if alpha <= 0.02:
                return
        cx = self.ctx.fmt.width / 2
        q = easing.EASE_IN_OUT(easing.progress(t, c["switch"] - 1, 6.0))
        with_alpha_layer = alpha < 1.0
        if with_alpha_layer:
            p_ = skia.Paint()
            p_.setAlphaf(alpha)
            canvas.saveLayer(None, p_)
        draw_label_switch(canvas, c["labels"][0], c["labels"][1], q, c["label_font"], cx, c["label_baseline"] + dy,
                          PALETTE.INK_SECONDARY)
        p = self._roll(t)
        scale = punch.settle(t, c["punch_at"], start=c["punch_start"], frames=c["punch_frames"])
        c["odo"].draw(canvas, p, cx, c["figure_baseline"] + dy, scale=scale)
        if with_alpha_layer:
            canvas.restore()
        w = c["odo"].width(p) * scale
        cap = ty.cap_height(c["odo"].font) * scale
        boxes.append({"kind": "counter", "label": c["odo"].text_at(p),
                      "rect": [round(cx - w / 2, 1), round(c["figure_baseline"] + dy - cap, 1),
                               round(cx + w / 2, 1), round(c["figure_baseline"] + dy + 0.05 * cap, 1)]})
        lab = c["labels"][1] if q >= 0.5 else c["labels"][0]
        x0, y0, x1, y1 = ty.ink_bounds(lab, c["label_font"], 0, c["label_baseline"] + dy)
        lw = x1 - x0
        boxes.append({"kind": "counter", "label": lab, "rect": [round(cx - lw / 2, 1), round(y0, 1),
                                                                 round(cx + lw / 2, 1), round(y1, 1)]})

    def _credit_alpha(self, t: float) -> float:
        """How much of the map the window shows (fades the credit in and out)."""
        c = self.credit
        idx = self.timeline.index(t)
        scroll = c["track"].at_ticks(self.source.take.pts[idx]) if c["track"] else 0.0
        x0, y0, x1, y1 = c["map"]
        y0, y1 = y0 - scroll, min(y1, 740.0 + scroll) - scroll     # cut by the opaque bar (740 pt)
        W = self.W(t)
        vis_top = max(y0, W)
        vis_bot = min(y1, W + (self.window.floor - self.window.top) / self.window.px_per_pt)
        px = (vis_bot - vis_top) * self.window.px_per_pt
        _, opacity = self.fall_state(t)
        return max(0.0, min(1.0, (px - 40.0) / 40.0)) * opacity      # a sliver of tiles is not « the map on screen »

    # ---- the record ------------------------------------------------------------------------------

    def record(self, f: int, rec: dict) -> None:
        t = float(f)
        idx = self.timeline.index(t)
        rec.update(take=self.source.name, picture=idx, picture_s=round(self.source.take.time_s(idx), 5),
                   src_s=round(self.timeline.src(t), 5), W=round(self.W(t), 3), zoom=round(self.zoom(t), 5))
        downs = [{"take": self.source.name, "gesture": tp.gesture, "src_s": round(self.timeline.src(t), 5),
                  "tone": tp.tone, "kind": tp.kind}
                 for tp in self.touches if abs(tp.down_f - t) < 1e-6]
        if downs:
            rec["touch_downs"] = downs
        if self.hidden:
            pose, W = self.pose(t), self.W(t)
            whip = (k := self.W.key_into(t)) is not None and k.blur == "whip"
            _, opacity = self.fall_state(t)
            out = []
            for label, rect, _shown in self.hidden:
                x0, y0, x1, y1 = self.phone.map_rect(rect, pose, W=W, window=self.window)
                ys = np.linspace(y0, y1, 24)
                # how much of the row's PLACE the window shows (band, floor, fall); verify multiplies it by
                # how much of the row the take's picture itself shows there (a push covers it)
                alpha = max(self.window.alpha_at(float(y)) for y in ys) * opacity
                out.append({"label": label, "alpha": round(alpha, 4), "rect": [round(v, 1) for v in (x0, y0, x1, y1)],
                            "whip": whip})
            rec["hidden"] = out

    def events(self) -> list[tuple[int, str]]:
        ev = []
        prev = None
        for f in range(self.start, self.end):
            i = self.timeline.index(float(f))
            if prev is not None and i != prev:
                ev.append((f, "ui change"))
            prev = i
        ev += [(int(round(tp.down_f)), f"touch {tp.gesture}") for tp in self.touches]
        ev += [(int(L["up"]), f"lift {L['id']}") for L in self.lifts]
        ev += [(int(L["down"]), f"settle {L['id']}") for L in self.lifts if L["down"] is not None]
        if self.stack:
            ev += [(int(u), f"tile {i + 1}") for i, u in enumerate(self.stack["ups"])]
        if self.counter:
            c = self.counter
            ev += [(int(c["switch"]), "counter label"), (int(c["from"]), "counter roll"),
                   (int(c["land"]), "counter lands")] + ([(int(c["exit"]) - 6, "counter exit")] if c["exit"] else [])
        for tr, name in ((self.W, "camera"), (self.zoom, "zoom"), (self.slam_rot, "tilt"), (self.slam_scale, "slam")):
            for a, b in zip(tr.keys, tr.keys[1:]):
                if a.value != b.value:
                    ev.append((int(math.ceil(a.frame)), f"{name} move"))
        if self.fall:
            ev.append((int(self.fall[0]), "fall"))
        return ev

    def generated(self) -> list[dict]:
        out = []
        for tp in self.touches:
            out.append({"element": f"touch disc{' + ripple' if tp.kind == 'tap' else ''} on {self.source.name} "
                                   f"{tp.gesture} ({tp.tone})", "scene": self.id,
                        "cite": "tool/app_store_preview/frames.py tone()/draw_touch :212-219 (the App Store "
                                "film's style), at the measured touch-down (promo.media.touches)"})
        for L in self.lifts:
            out.append({"element": f"lift {L['id']}: real pixels of {self.source.name} picture #{L['index']} "
                                   f"({self.source.take.time_s(L['index']):.4f} s), magnified", "scene": self.id,
                        "cite": "real app pixels, nothing redrawn (promo/fx/lift.py)"})
        if self.stack:
            out.append({"element": f"stacked tiles: real pixels of {self.source.name} picture #{self.stack['index']}",
                        "scene": self.id, "cite": "real app pixels, nothing redrawn (client_detail_screen.dart:663-676)"})
            if self.stack["backdrop"]:
                bd = self.stack["backdrop"]
                out.append({"element": f"a plain panel behind the lifted tiles ({bd[3]} token, {bd[1]:g}-px margin)",
                            "scene": self.id, "cite": bd[4]})
        if self.counter:
            c = self.counter
            out.append({"element": f"counter « {ty.fcfa(c['start'])} » → « {ty.fcfa(c['end'])} », labels "
                                   f"{' → '.join(c['labels'])}", "scene": self.id, "cite": c["cite"]})
        if self.credit:
            out.append({"element": f"map credit « {self.credit['text']} »", "scene": self.id,
                        "cite": self.credit["cite"]})
        return out
