"""Rows 6–22: the phone scenes — real pictures of a take in a 2.5D slab, seen
through the camera window, with the storyboard's touches, lifts, stacked
tiles, the counter and the map credit drawn over them.

Per frame t (a float: motion-blur subframes are fractional):
  * the picture is the take's picture at the timeline's take time (masked);
  * the camera puts screen point W(t) on the window's top edge (the band
    edge: y 600 in 9:16, 388 in 1:1, 84 in 16:9 under its top fade — or
    lower in 16:9, where the phone stands on the floor: `band`), zooms
    about its anchor (px_per_pt ÷ 1.791), and the slam / tilt / fall /
    parallax keys turn and move the slab (promo/fx/phone.py, projection.py);
  * ONE storyboard, every format: the W keys are measured in the reference
    format's window (9:16) and each says what it keeps — a point on the
    window's top edge (`top`: a row hidden under the band stays hidden), in
    its middle (`centre`: the active form row) or on its floor (`floor`:
    Fatou B.'s card, the page's last line) — so a format's own window
    re-frames by that rule (`keep_offset`), never showing the screen's top
    edge where the reference did not; a tilt turns about the format's
    `tilt_axis` (16:9: a yaw of at most `tilt_max_deg`); lifts, tiles, the
    counter and the map credit land where the format's layout puts them;
  * touch discs sit in screen points under the same matrix, from the
    measured touch-down (never from a typed time): the YAML's ``at`` is
    checked to be the frame the touch-down lands on, and its ``tone`` to be
    what the ground under the finger asks for (frames.py tone());
  * lifts and stacked tiles are the take's own (masked) pixels, magnified;
  * a declared dissolve (sources.Timeline) blends two pictures, each through
    the camera it is framed by: the one it leaves at W(dissolve start), the
    one it reaches at W(dissolve end) — so the camera can re-frame across it
    and the fields that are on both stay in place (the 15-s cut's form,
    32.998 → 130.262, scrolled 145 pt between the two).

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
from .keys import Key, Track
from .sources import SourceError, Timeline

#: A tap's disc stays at least this long (take seconds) when the log says it
#: was not held — the App Store film's taps showed 0.3 s.
MIN_PRESS_S = 0.2


def window_for(fmt) -> Window:
    """The camera window of a format: W sits on its top edge — the band's
    edge (9:16, 1:1: the phone fades in under the band's fade, above it), or,
    with no band (16:9), the end of the window's own top fade (`top_fade`,
    inside the window: the phone is gone above the safe edge)."""
    z, lay = fmt.zones, fmt.layout
    pw = z["phone_window"]
    if "top_fade" in z:
        top, band_fade = float(z["top_fade"].y1), float(z["top_fade"].height)
    else:
        top, band_fade = float(pw.y0), float(pw.y0 - z["caption_fade"].y0) if "caption_fade" in z else 30.0
    floor_fade = z["floor_fade"].height if "floor_fade" in z else 24.0
    # 16:9 (`phone_anchor: floor`, the owner's « Re-lay it », 2026-10-19): the slab stands on the floor — the
    # screen's bottom edge never above floor − bezel; where W would lift it, the band edge comes down instead
    anchor = None
    if lay.get("phone_anchor") == "floor":
        anchor = float(pw.y1) - float(lay["phone_bezel_px"])
    return Window(screen_x=float(lay["phone_screen_x"][0]), top=top, band_fade=band_fade,
                  floor=float(pw.y1), floor_fade=float(floor_fade), px_per_pt=float(lay["px_per_pt"]),
                  anchor_bottom=anchor)


#: What a camera W key keeps when a format re-frames it (storyboard.yaml « CAMERA »).
KEEPS = ("top", "centre", "floor")


def keep_offset(keep: str, window: Window, reference: Window) -> float:
    """Points to add to a W measured in the `reference` window so the point
    it keeps sits in the same place of `window`: on the top edge (0), in the
    middle, or on the floor."""
    h, h_ref = window.floor - window.top, reference.floor - reference.top
    k = window.px_per_pt
    try:
        return {"top": 0.0, "centre": (h_ref - h) / (2 * k), "floor": (h_ref - h) / k}[keep]
    except KeyError:
        raise ValueError(f"keep is one of {', '.join(KEEPS)}, not {keep!r}") from None


def camera_W_keys(specs: list | None, window: Window, reference: Window, crop_top_pt: float,
                  where: str) -> list[dict]:
    """The W keys in a format's window: each reference value moved by what it
    keeps (`keep`, else the key before it's; the first key: `top`) — never
    below the screen's top (`crop_top_pt`) where the reference value was not."""
    out, keep = [], "top"
    for i, k in enumerate(specs or []):
        if not isinstance(k, dict) or "value" not in k:
            out.append(k)                                  # base.track says what is wrong with it
            continue
        keep = k.get("keep", keep)
        try:
            v = float(k["value"])
            w = v + keep_offset(keep, window, reference)
        except (TypeError, ValueError) as e:
            raise SceneError(f"{where}[{i}].keep: {e}") from None
        if keep != "top":
            w = max(w, min(v, crop_top_pt))
        out.append({**{n: x for n, x in k.items() if n != "keep"}, "value": w})
    return out


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
        self.reference_window = window_for(ctx.reference_fmt)
        lay = ctx.layout
        self.tilt_axis, self.tilt_max = lay["tilt_axis"], lay["tilt_max_deg"]
        self.band_rows = (0, int(self.window.top - self.window.band_fade), ctx.fmt.width,
                          int(math.ceil(self.window.floor + self.window.floor_fade)))
        try:
            self.source = ctx.source(spec["take"])
            self.source.add_masks(spec.get("masks") or [], where)
            self.timeline = Timeline(self.source, spec.get("timeline") or [], ctx.clock, ctx.fps, where)
        except (KeyError, SourceError) as e:
            raise SceneError(f"{where}: {e}") from None
        cam = spec.get("camera") or {}
        self.W = track(ctx, camera_W_keys(cam.get("W"), self.window, self.reference_window,
                                          float(lay["screen_crop_top_pt"]), f"{where}.camera.W"), f"{where}.camera.W")
        if not self.W:
            raise SceneError(f"{where}.camera.W: a phone scene needs its camera window")
        self.band = self._band_track()
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
        for seg in self.dissolves:
            # a dissolve blends two pictures at rest (the App Store film's rule): no disc or ripple on its frames
            for tp in self.touches:
                if tp.down_f < seg.end and seg.start < tp.gone_f:
                    raise SceneError(f"{seg.where}: the {tp.gesture} disc shows f{tp.down_f:g}–f{tp.gone_f:g}, on the "
                                     f"dissolve's frames (f{seg.start:g}–f{seg.end:g}): a dissolve blends two pictures "
                                     f"at rest, no touch on either")
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

    # ---- the window a frame shows -----------------------------------------------------------

    def _band_track(self) -> Track | None:
        """Where the band edge is (16:9: the phone stands on the floor), keyed
        like W: each W key's band edge is `Window.top_for` its value — the
        highest that leaves no floating screen — moved on the W key's own
        curve (the screen's bottom moves linearly between two keys that never
        float, so it never floats in between). A declared dissolve shows each
        of its pictures through the window of its own end, as it does with W
        (`camera_band`): each stands on the floor — in 16:9 the 15-s form's
        dissolve re-frames (its fields move), where a shared window would put
        « Créer », the next tap, under the floor. None: the band edge is fixed
        (9:16, 1:1)."""
        win = self.window
        if win.anchor_bottom is None:
            return None
        return Track([Key(k.frame, win.top_for(k.value), k.curve, None, {}) for k in self.W.keys], win.top)

    def band_at(self, t: float) -> float:
        """The band edge keyed at t (between keys, on their curve)."""
        return self.window.top if self.band is None else self.band(t)

    def camera_band(self, t: float) -> float:
        """The band edge of the picture that dominates frame t: inside a
        dissolve each picture has its own (the keys at its ends), as W."""
        d = self.timeline.dissolve_at(t)
        if d is None:
            return self.band_at(t)
        seg, _, _, u = d
        return self.band_at(seg.start) if u < 0.5 else self.band_at(seg.end)

    def band_top(self, t: float) -> float:
        """The band edge on frame t (the window's top, where W sits)."""
        return self.camera_band(t)

    def win(self, t: float) -> Window:
        """The window frame t shows (the fixed one, or 16:9's on its band edge)."""
        return self.window if self.band is None else self.window.at_top(self.camera_band(t))

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
        x0, x1 = map(float, self.ctx.layout["lift_x"])
        target = liftmod.fit_width(src, x0, x1, **self._place((l.get("target") or {}).get("y"), f"{where}.target.y"))
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
        x0, x1 = map(float, self.ctx.layout["lift_x"])
        gap = float(lay.get("gap", 16))
        place = self._place(lay.get("y"), f"{where}.layout.y")
        if set(place) != {"centre_y"}:
            raise SceneError(f"{where}.layout.y: a row of tiles is placed by its centre (`centre_y`), not {place}")
        if lay.get("axis", "vertical") == "horizontal":
            ratio = sum((r[2] - r[0]) / (r[3] - r[1]) for r in srcs)
            h = (x1 - x0 - gap * (len(srcs) - 1)) / ratio
            targets = stackmod.stack_rects(srcs, x0=x0, gap=gap, axis="horizontal",
                                           y0=place["centre_y"] - h / 2, height=h)
        else:
            targets = stackmod.stack_rects(srcs, x0=x0, width=x1 - x0, gap=gap, centre_y=place["centre_y"])
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
        veil = float(s.get("veil", self.ctx.layout["lift_veil"]))
        if veil <= 0:
            # the panel hides the VEILED originals between cards that lift over the phone; where the format
            # lifts beside the phone with no veil (16:9) the cards sit on the stage and the phone stays whole
            backdrop = None
        return {"index": idx, "tiles_pt": tiles, "srcs": srcs, "targets": targets, "ups": ups,
                "veil": veil, "backdrop": backdrop}

    def _place(self, name, where: str) -> dict[str, float]:
        """A lift's vertical placement: one of the format's `lift_y` places."""
        places = self.ctx.layout["lift_y"]
        if name not in places:
            raise SceneError(f"{where}: one of the format's lift_y places ({', '.join(places)}), not {name!r}")
        return {k: float(v) for k, v in places[name].items()}

    def _counter(self, c: dict, where: str) -> dict:
        F = self.ctx.clock.frame
        lay = self.ctx.layout
        tp = lay["type_px"]
        if "label_baseline" in c or "figure_baseline" in c:
            raise SceneError(f"{where}: the counter's baselines are the format's (layout.counter_baselines)")
        roll = c["roll"]
        out = {"start": int(c["start"]), "end": int(c["end"]), "labels": list(c["labels"]),
               "switch": float(F(c["label_switch"])), "from": float(F(roll["from"])), "land": float(F(roll["to"])),
               "punch_at": float(F(c["punch"]["at"])), "punch_start": float(c["punch"].get("start", 1.08)),
               "punch_frames": float(c["punch"].get("frames", 5)),
               "exit": float(F(c["exit"]["at"])) if c.get("exit") else None,
               "exit_frames": float(c["exit"].get("frames", 6)) if c.get("exit") else 6.0,
               "label_baseline": float(lay["counter_baselines"][0]), "figure_baseline": float(lay["counter_baselines"][1]),
               "align": lay["caption_align"],
               "x": float(lay["caption_centre_x"] if lay["caption_align"] == "centre" else lay["caption_column_x"][0]),
               "cite": c.get("cite")}
        out["odo"] = Odometer(out["start"], out["end"], poppins(tp["counter"]), PALETTE.INK)
        out["label_font"] = inter(tp["counter_label"])
        # left-aligned (16:9): a label whose first glyph overhangs its origin (« A ») moves in by that much,
        # so its ink starts on the column's edge, never past it
        out["label_inset"] = 0.0 if out["align"] == "centre" else max(
            0.0, *(-ty.ink_bounds(lab, out["label_font"])[0] for lab in out["labels"]))
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
        if "x" in c or "baseline" in c:
            raise SceneError(f"{where}: the credit's place is the format's (layout.map_credit)")
        place = self.ctx.layout["map_credit"]
        return {"text": c["text"], "map": tuple(map(float, c["map_rect_pt"])), "x": float(place["x"]),
                "baseline": float(place["baseline"]), "align": place["align"],
                "font": inter(self.ctx.layout["type_px"]["credit"]),
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
            if anchor_y == "top":
                y = self.band_top(t)                         # the window's top edge (the band edge)
            elif anchor_y is not None:
                y = float(anchor_y)
            else:
                y = self.win(t).y_of(float(anchor_pt), W)
            sx = self.ctx.layout["phone_screen_x"]
            px = self.ctx.layout.get("zoom_pivot_x")
            # about the phone's own axis, or the format's pivot (16:9: the screen's right edge, on the safe edge)
            pivot = ((float(sx[0]) + float(sx[1])) / 2 if px is None else float(px), y)
        dy, _ = self.parallax_dy(t)
        tilt = self.slam_rot(t)
        if self.tilt_max is not None:
            tilt = max(-float(self.tilt_max), min(float(self.tilt_max), tilt))
        if self.tilt_axis == "y":
            return Pose(rot_y=tilt, scale=scale, dy=dy, pivot=pivot)
        return Pose(rot_x=tilt, scale=scale, dy=dy, pivot=pivot)

    def where(self, t: float) -> dict:
        return {"W": self.camera_W(t), "window": self.win(t)}

    def camera_W(self, t: float) -> float:
        """The camera's W for the picture that dominates frame t: inside a
        dissolve each picture has its own (the W keys at its ends), never the
        keys' in-between."""
        d = self.timeline.dissolve_at(t)
        if d is None:
            return self.W(t)
        seg, _, _, u = d
        return self.W(seg.start) if u < 0.5 else self.W(seg.end)

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
        sampling = SAMPLING_CUBIC if fast else None
        d = self.timeline.dissolve_at(pic_t)
        if d is None:
            self.phone.set_screen(self.source.picture(self.timeline.index(pic_t)))
            self.phone.draw(canvas, self.pose(t), W=self.W(t), window=self.win(t), opacity=opacity,
                            overlay=self._touch_overlay(t), sampling=sampling)
            return
        # a declared dissolve: the picture it leaves through the camera that framed it, then the one it
        # reaches through its own, the whole stage in a layer at the blend's opacity (an exact cross-fade)
        seg, i_from, i_to, u = d
        pose = self.pose(t)
        self.phone.set_screen(self.source.picture(i_from))
        win_a = self.window if self.band is None else self.window.at_top(self.band_at(seg.start))
        win_b = self.window if self.band is None else self.window.at_top(self.band_at(seg.end))
        self.phone.draw(canvas, pose, W=self.W(seg.start), window=win_a, opacity=opacity, sampling=sampling)
        if u > 0:
            paint = skia.Paint()
            paint.setAlphaf(u)
            canvas.saveLayer(None, paint)
            self.stage.draw(canvas, self.size, self.seconds(t), offset=(0.0, pdy))
            self.phone.set_screen(self.source.picture(i_to))
            self.phone.draw(canvas, pose, W=self.W(seg.end), window=win_b, opacity=opacity, sampling=sampling)
            canvas.restore()

    def blur_at(self, f: int) -> Blur | None:
        px = self.window.px_per_pt * self.zoom(f)
        b = blur_for_track(self.W, f, px, region=self.band_rows)
        n = self.timeline.blur_at(f)
        if n:
            b = Blur(max(n, b.samples if b else 0), b.shutter if b else 0.5, self.band_rows, ui=True)
        return b

    def _veil_rect(self, t: float) -> tuple[float, float, float, float]:
        w = self.win(t)
        return (0.0, w.top - w.band_fade, float(self.ctx.fmt.width), w.floor + w.floor_fade)

    def draw_overlays(self, canvas: skia.Canvas, f: int, rec: dict) -> None:
        t = float(f)
        pose, W, win = self.pose(t), self.W(t), self.win(t)
        boxes = rec.setdefault("boxes", [])
        # lifts
        for L in self.lifts:
            p = liftmod.pop_progress(t, L["up"], 6.0, L["down"], 5.0)
            if p <= 0:
                continue
            origin = self.phone.map_rect(L["rect_pt"], pose, W=W, window=win)
            lf = liftmod.Lift(self.source.picture(L["index"]), L["src"], origin, L["target"],
                              liftmod.LiftStyle(veil_opacity=L["veil"]))
            lf.draw(canvas, p, veil_rect=self._veil_rect(t) if L["veil"] > 0 else None)
            # `rest`: landed (or not yet settling back) — a card on its way out of the phone or back into it is
            # the app's pixels in motion (9:16: from Fatou B.'s card on the owner's floor, below y 1248)
            boxes.append({"kind": "lift", "label": L["id"], "rect": [round(v, 1) for v in lf.rect(p)],
                          "rest": bool(p >= 1.0)})
        # stacked tiles
        if self.stack:
            S = self.stack
            if t >= min(S["ups"]) - 1:
                origins = [self.phone.map_rect(r, pose, W=W, window=win) for r in S["tiles_pt"]]
                st = stackmod.Stack(self.source.picture(S["index"]), S["srcs"], origins, S["targets"], S["ups"],
                                    style=liftmod.LiftStyle(veil_opacity=S["veil"]))
                st.draw(canvas, t, veil_rect=self._veil_rect(t), backdrop=S["backdrop"][:3] if S["backdrop"] else None)
                for i, lf in enumerate(st.lifts):
                    p = st.progress(i, t)
                    if p > 0:
                        boxes.append({"kind": "lift", "label": f"tile{i + 1}", "rect": [round(v, 1) for v in lf.rect(p)],
                                      "rest": bool(p >= 1.0)})
        # the counter, alone in the band
        if self.counter:
            self._draw_counter(canvas, t, boxes)
        # the map credit on the floor
        if self.credit:
            a = self._credit_alpha(t)
            if a > 0:
                c = self.credit
                left = self._credit_left()
                ty.draw_text(canvas, c["text"], c["font"], left, c["baseline"], PALETTE.INK_TERTIARY, alpha=a)
                x0, y0, x1, y1 = ty.ink_bounds(c["text"], c["font"], left, c["baseline"])
                boxes.append({"kind": "credit", "label": "map credit", "rect": [round(x0, 1), round(y0, 1),
                                                                                round(x1, 1), round(y1, 1)]})
        # the touch discs, in frame px, for the safe-zone check
        for tp in self.touches:
            if tp.down_f - 1 <= t < tp.gone_f:
                x, y = self.finger(tp, t)
                fx, fy = self.phone.map_point(x, y, pose, W=W, window=win)
                d = tp.style.diameter_pt
                if tp.kind == "tap":
                    st = touchmod.ripple_state(t, tp.down_f, tp.style)
                    if st:
                        d = max(d, st[0])
                r = d / 2 * win.px_per_pt * pose.scale
                # the disc rides the phone layer: under the band and the floor it does not show
                top = win.top - win.band_fade
                bottom = win.floor + win.floor_fade
                y0, y1 = max(fy - r, top), min(fy + r, bottom)
                if y1 <= y0 or max(win.alpha_at(y) for y in np.linspace(y0, y1, 9)) < 0.05:
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
        cx, align = c["x"], c["align"]                   # the centre (centred captions) or the left edge
        lx = cx + c["label_inset"]                       # left-aligned: the labels' ink starts on the edge
        q = easing.EASE_IN_OUT(easing.progress(t, c["switch"] - 1, 6.0))
        with_alpha_layer = alpha < 1.0
        # alone in the band: where the format has one, the roll never reaches past it onto the phone (1:1: the
        # band ends at y 300 — the rolling band fades out ON it, by its edge, `floor`; the clip is a backstop)
        band = self.ctx.fmt.zones.get("caption_band")
        floor = self.band_top(t) - self.window.band_fade if band is not None else None
        canvas.save()
        if floor is not None:
            canvas.clipRect(skia.Rect.MakeLTRB(0, 0, self.ctx.fmt.width, floor))
        if with_alpha_layer:
            p_ = skia.Paint()
            p_.setAlphaf(alpha)
            canvas.saveLayer(None, p_)
        draw_label_switch(canvas, c["labels"][0], c["labels"][1], q, c["label_font"], lx, c["label_baseline"] + dy,
                          PALETTE.INK_SECONDARY, align=align)
        p = self._roll(t)
        scale = punch.settle(t, c["punch_at"], start=c["punch_start"], frames=c["punch_frames"])
        c["odo"].draw(canvas, p, cx, c["figure_baseline"] + dy, scale=scale, align=align, floor=floor)
        if with_alpha_layer:
            canvas.restore()
        canvas.restore()
        w0 = c["odo"].width(p)
        w = w0 * scale
        cap = ty.cap_height(c["odo"].font) * scale
        # the punch scales about the figure's centre (centred) or holds its left edge (left-aligned)
        fx0 = cx - w / 2 if align == "centre" else cx
        boxes.append({"kind": "counter", "label": c["odo"].text_at(p),
                      "rect": [round(fx0, 1), round(c["figure_baseline"] + dy - cap, 1),
                               round(fx0 + w, 1), round(c["figure_baseline"] + dy + 0.05 * cap, 1)]})
        lab = c["labels"][1] if q >= 0.5 else c["labels"][0]
        x0, y0, x1, y1 = ty.ink_bounds(lab, c["label_font"], 0, c["label_baseline"] + dy)
        lw = x1 - x0
        lx0 = cx - lw / 2 if align == "centre" else lx + x0
        boxes.append({"kind": "counter", "label": lab, "rect": [round(lx0, 1), round(y0, 1),
                                                                 round(lx0 + lw, 1), round(y1, 1)]})

    def _credit_left(self) -> float:
        """Where the credit's text starts so its INK sits on its place: from
        `x` (align left; a first glyph overhanging its origin moves in) or
        ending on `x` (align right; the last glyph's overshoot included — the
        1:1 credit ends on the safe edge, x 1026)."""
        c = self.credit
        x0, _, x1, _ = ty.ink_bounds(c["text"], c["font"])
        return c["x"] - min(0.0, x0) if c["align"] == "left" else c["x"] - x1

    def _credit_alpha(self, t: float) -> float:
        """How much of the map the window shows (fades the credit in and out)."""
        c = self.credit
        idx = self.timeline.index(t)
        scroll = c["track"].at_ticks(self.source.take.pts[idx]) if c["track"] else 0.0
        x0, y0, x1, y1 = c["map"]
        y0, y1 = y0 - scroll, min(y1, 740.0 + scroll) - scroll     # cut by the opaque bar (740 pt)
        W, win = self.W(t), self.win(t)
        vis_top = max(y0, W)
        vis_bot = min(y1, W + (win.floor - win.top) / win.px_per_pt)
        px = (vis_bot - vis_top) * win.px_per_pt
        _, opacity = self.fall_state(t)
        return max(0.0, min(1.0, (px - 40.0) / 40.0)) * opacity      # a sliver of tiles is not « the map on screen »

    # ---- the record ------------------------------------------------------------------------------

    def record(self, f: int, rec: dict) -> None:
        t = float(f)
        idx = self.timeline.index(t)
        rec.update(take=self.source.name, picture=idx, picture_s=round(self.source.take.time_s(idx), 5),
                   src_s=round(self.timeline.src(t), 5), W=round(self.camera_W(t), 3), zoom=round(self.zoom(t), 5),
                   window_top=round(self.band_top(t), 3))
        d = self.timeline.dissolve_at(t)
        if d is not None:
            seg, i_from, i_to, u = d
            rec["dissolve"] = {"pictures": [i_from, i_to], "blend": round(u, 4),
                               "W": [round(self.W(seg.start), 3), round(self.W(seg.end), 3)]}
        downs = [{"take": self.source.name, "gesture": tp.gesture, "src_s": round(self.timeline.src(t), 5),
                  "tone": tp.tone, "kind": tp.kind}
                 for tp in self.touches if abs(tp.down_f - t) < 1e-6]
        if downs:
            rec["touch_downs"] = downs
        if self.hidden:
            pose, W, win = self.pose(t), self.camera_W(t), self.win(t)
            whip = (k := self.W.key_into(t)) is not None and k.blur == "whip"
            _, opacity = self.fall_state(t)
            out = []
            for label, rect, _shown in self.hidden:
                x0, y0, x1, y1 = self.phone.map_rect(rect, pose, W=W, window=win)
                ys = np.linspace(y0, y1, 24)
                # how much of the row's PLACE the window shows (band, floor, fall); verify multiplies it by
                # how much of the row the take's picture itself shows there (a push covers it)
                alpha = max(win.alpha_at(float(y)) for y in ys) * opacity
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
        ev += [(int(math.ceil(s.start)), "dissolve") for s in self.dissolves]
        return ev

    @property
    def dissolves(self) -> list:
        return [s for s in self.timeline.segments if s.kind == "dissolve"]

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
        take = self.source.take
        for s in self.dissolves:
            out.append({"element": f"declared dissolve (an edit, no pixel drawn) on {self.source.name}: picture "
                                   f"#{take.index_at(s.src0)} ({s.src0:.3f} s) → #{take.index_at(s.to)} "
                                   f"({s.to:.3f} s) over f{s.start:g}–f{s.end:g}, the footage between skipped",
                        "scene": self.id, "cite": s.cite})
        return out
