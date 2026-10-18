"""The film, frame by frame: « Le trait ». Design: docs/design/pro-marketing-reel.md §2.

`Composer.frame(n)` draws film frame n (t = n / 30 s) from the plan, the
brand art and the footage. Every word comes from the storyboard through
`reel_plan` (by scene and index); every number from the plan's tables;
every duration and curve from `motion.dart`'s tokens, except the strokes'
own timing (the storyboard's, on the Lottie curve) and S5's camera moves
(« 600 ms easeInOutCubic, not UI motion »).

Two choices the storyboard leaves open, taken the calmer way (README,
« Deviations »):
  - a card enters with its TOP EDGE rising from y 1920, as S3 says (« from
    top y 1920 to 600 »): for S5 (rest W 100) and S7 (rest W 553) a fixed
    +1320 offset would have started the card already on screen and popped
    it in, so the travel is 1920 minus the rest top;
  - where S8's pen dot (26.55–26.65) overlaps the start of the draw
    (26.60), the stroke's width follows the dot's growth until the dot is
    whole, so the pen never jumps.
"""

from __future__ import annotations

import math
from functools import lru_cache

import numpy as np
from PIL import Image

import reel_brand as rb
import reel_draw as rd
import reel_footage as rf
import reel_plan as plan

P92 = ("poppins", plan.PAIN["head_px"])
P84 = ("poppins", plan.ANSWER["head_px"])
P52 = ("poppins", plan.S2["tag_px"])
I48M = ("inter", plan.NOTEBOOK["entry_px"], plan.NOTEBOOK["entry_wght"])
I48 = ("inter", plan.S4["text_px"], 400)
I34 = ("inter", plan.S4["ts_px"], 400)
CTA = ("inter", plan.S8["cta_px"], plan.S8["cta_wght"])


def capsule_width(t: float, spec: tuple) -> float:
    """The « trait » thickening into the page: 8 px → 2400 px on `slow`."""
    _, t0, _, w0, w1 = spec
    return w0 + (w1 - w0) * plan.tokens()["slow"].at(t - t0)


def covered_at(spec: tuple, box: tuple[float, float, float, float], fps: int) -> float:
    """The first frame time at which the thickening « trait » `spec` covers
    `box` whole — when the words under it are gone."""
    y, t0, t1, _, _ = spec
    x0, x1 = plan.NOTEBOOK["stroke_x"]
    far = 0.0
    for bx in (box[0], box[2]):
        for by in (box[1], box[3]):
            dx = max(x0 - bx, 0, bx - x1)
            far = max(far, math.hypot(dx, by - y))
    n = math.floor(t0 * fps)
    while n / fps <= t1 + 1:
        if capsule_width(n / fps, spec) / 2 >= far:
            return n / fps
        n += 1
    plan.die(f"the trait at y {y} never covers {box}")


class Composer:
    def __init__(self, P: plan.Plan, footage: rf.Footage | None = None):
        self.P = P
        self.c = plan.colours()
        self.T = plan.tokens()
        self.exit = plan.exit_motion()
        self.stagger = plan.stagger_s()
        self.fx = footage
        self.card = rf.Card() if footage is not None else None
        self.mark_s2 = rb.mark_points(plan.S2["mark_centre"], plan.S2["mark_h"])
        centre, height = rb.icon_mark()
        self.mark_s8 = rb.mark_points(centre, height)
        self.mark_s8_box = rb.mark_box(centre, height)
        self.draw_s = rb.mark_geometry()["draw_s"]
        S = P.scenes
        self.words = {
            "S1": [S["S1"].text(i) for i in range(len(S["S1"].texts))],
            "S2": [S["S2"].text(i) for i in range(len(S["S2"].texts))],
            "S3": [S["S3"].text(i) for i in range(2)],
            "S4": [S["S4"].text(i) for i in range(len(S["S4"].texts))],
            "S5": [S["S5"].text(i) for i in range(2)],
            "S6": [S["S6"].text(i) for i in range(len(S["S6"].texts))],
            "S7": [S["S7"].text(i) for i in range(2)],
            "S8": [S["S8"].text(i) for i in range(2)],
        }
        for key in ("S2", "S8"):
            if self.words[key][0] != "MyWeli Pro":
                plan.die(f"{key}'s first word is {self.words[key][0]!r}: the vector unit spells « MyWeli Pro »")

    # ---- small motions ------------------------------------------------------------

    def at(self, token: str, t: float, t0: float) -> float:
        """Progress 0..1 of a token's motion started at t0 (0 before it)."""
        return 0.0 if t < t0 else self.T[token].at(t - t0)

    def stroke_progress(self, t: float, t0: float, t1: float) -> float | None:
        if t < t0:
            return None
        return plan.stroke_curve(min(1.0, (t - t0) / (t1 - t0)))

    # ---- grounds -------------------------------------------------------------------

    @lru_cache(maxsize=None)
    def notebook(self) -> Image.Image:
        """Black, and the Seyès field: major rules every 96 px on the
        baselines, minor every 24, the margin rule — feathered 80 px top and
        bottom. Rules sit on whole pixels: a 2-px rule on the two rows
        around its baseline, a 1-px rule on the row under its line."""
        N = plan.NOTEBOOK
        W, H = self.P.size
        im = Image.new("RGB", (W, H), self.c["primary"])
        ys = np.arange(H, dtype=np.float32) + 0.5
        feather = np.clip(np.minimum(ys - N["top"], N["bottom"] - ys) / N["feather"], 0, 1)
        major = np.zeros((H, W), np.float32)
        minor = np.zeros((H, W), np.float32)
        first = N["major"][0] - ((N["major"][0] - N["top"]) // N["minor_step"]) * N["minor_step"]
        for y in range(first, N["bottom"] + 1, N["minor_step"]):
            if y in N["major"]:
                major[y - N["major_w"] // 2:y - N["major_w"] // 2 + N["major_w"], :] = 1
            else:
                minor[y:y + N["minor_w"], :] = 1
        mx = N["margin_x"]
        major[:, mx - N["margin_w"] // 2:mx - N["margin_w"] // 2 + N["margin_w"]] = 1
        minor = np.where(major > 0, 0, minor)
        fr = rd.Frame((W, H), self.c["primary"])
        fr.im = im
        fr.put(self.c["ruleMinor"], minor * feather[:, None], 0, 0)
        fr.put(self.c["ruleMajor"], major * feather[:, None], 0, 0)
        return fr.im

    def ground(self, colour: tuple, dry: bool, base: Image.Image | None = None) -> rd.Frame:
        fr = rd.Frame(self.P.size, colour, dry)
        if base is not None and not dry:
            fr.im = base.copy()
        return fr

    # ---- shared pieces ----------------------------------------------------------

    def headline(self, fr: rd.Frame, lines: list[str], spec: tuple, top: float, lh: float, colour,
                 alphas=(1.0, 1.0), dys=(0.0, 0.0), scale: float = 1.0, label: str = "") -> None:
        cy = top + lh * len(lines) / 2
        for i, s in enumerate(lines):
            box_top = top + i * lh
            base = rd.baseline_in(box_top, lh, spec)
            sp = spec
            b, lt, lb = base, box_top, box_top + lh
            if scale != 1.0:
                sp = rd.scaled(spec, scale)
                b, lt, lb = (cy + (v - cy) * scale for v in (base, box_top, box_top + lh))
            fr.centred(s, sp, 540, b + dys[i], colour, alphas[i], f"{label} line {i + 1}",
                       line_box=(lt + dys[i], lb + dys[i]))

    def answer_headline(self, fr: rd.Frame, key: str, t: float, t_in: float, fade: float = 1.0) -> None:
        A = plan.ANSWER
        alphas, dys = [], []
        for i in range(2):
            p = self.at("emphasis", t, t_in + i * self.stagger)
            alphas.append(p * fade)
            dys.append(24 * (1 - p))
        self.headline(fr, self.words[key], P84, A["head_top"], A["head_lh"], self.c["textPrimary"],
                      alphas, dys, label=f"{key} headline")

    def pain_headline(self, fr: rd.Frame, key: str, t: float, t_in: float) -> None:
        settle = plan.PAIN["settle_from"] - (plan.PAIN["settle_from"] - 1) * self.at("fast", t, t_in)
        self.headline(fr, self.words[key][:2], P92, plan.PAIN["head_top"], plan.PAIN["head_lh"],
                      self.c["secondary"], scale=settle, label=f"{key} headline")

    def entry(self, fr: rd.Frame, s: str, x: float, baseline: float, t: float, t_pop: float | None,
              label: str, pop_scale: bool = False) -> None:
        N = plan.NOTEBOOK
        p = 1.0 if t_pop is None else self.at("fast", t, t_pop)
        if p <= 0:
            return
        if pop_scale:   # « scale 0.96 → 1 plus a fade to 85% », about the line's left end
            k = 0.96 + 0.04 * p
            fr.text(s, rd.scaled(I48M, k), x, baseline, self.c["secondary"], N["entry_alpha"] * p, label)
        else:           # « opacity 0 → 85% plus a 6 px rise »
            fr.text(s, I48M, x, baseline + N["pop_rise"] * (1 - p), self.c["secondary"], N["entry_alpha"] * p, label)

    def strike(self, fr: rd.Frame, x: tuple[float, float], y: float, t: float, t0: float, t1: float,
               width: float) -> None:
        f = self.stroke_progress(t, t0, t1)
        if f is not None:
            rd.stroke(fr, rd.drawn_line(x[0], x[1], y, f), width, self.c["surface"])

    def trait(self, fr: rd.Frame, y: float, t: float, t0: float, t1: float) -> None:
        """The full-width « trait »: 8 px, round caps, left to right."""
        self.strike(fr, plan.NOTEBOOK["stroke_x"], y, t, t0, t1, plan.NOTEBOOK["stroke_w"])

    def thicken(self, fr: rd.Frame, spec: tuple, t: float) -> None:
        y = spec[0]
        x0, x1 = plan.NOTEBOOK["stroke_x"]
        rd.stroke(fr, [(x0, y), (x1, y)], capsule_width(t, spec), self.c["surface"])

    def mark(self, fr: rd.Frame, pts_w, t: float, dot: tuple[float, float], draw: float, alpha: float = 1.0,
             dy: float = 0.0, label: str = "mark", box=None) -> None:
        pts, width = pts_w
        if t < dot[0] or alpha <= 0:
            return
        grow = self.at("fast", t, dot[0])
        pts = [(x, y + dy) for x, y in pts]
        if t < draw:
            rd.disc(fr, pts[0][0], pts[0][1], width * grow, self.c["primary"], alpha)
            shown = (pts[0][0] - width / 2, pts[0][1] - width / 2, pts[0][0] + width / 2, pts[0][1] + width / 2)
        else:
            f = plan.stroke_curve(min(1.0, (t - draw) / self.draw_s))
            rd.stroke(fr, rd.trim(pts, f), width * min(1.0, grow), self.c["primary"], alpha)
            shown = box
        if shown is not None:
            fr.note("logo", label, (shown[0], shown[1] + (dy if shown is box else 0), shown[2],
                                    shown[3] + (dy if shown is box else 0)), alpha)

    def unit(self, fr: rd.Frame, width_px: int, top: float, alpha: float, label: str) -> None:
        cover, corner, ink = rb.unit_sprite(width_px)
        left = (self.P.width - width_px) / 2
        x0, y0 = round(left) - corner[0], round(top) - corner[1]
        fr.note("logo", label, (left + ink[0], top + ink[1], left + ink[2], top + ink[3]), alpha)
        if alpha > 0:
            fr.put(self.c["primary"], cover * alpha, x0, y0)

    # ---- the scenes -----------------------------------------------------------------

    def s1(self, fr: rd.Frame, t: float) -> None:
        N, S = plan.NOTEBOOK, plan.S1
        w = self.words["S1"]
        self.pain_headline(fr, "S1", t, 0.0)
        for i, b in enumerate(S["baselines"]):
            self.entry(fr, w[2 + i], N["entry_x"], b, t, S["pops"].get(i), f"S1 entry {i + 1}")
        for k, (x, b, t_pop) in enumerate(S["arrows"]):
            self.entry(fr, w[7 + k], x, b, t, t_pop, f"S1 arrow {k + 1}")
        for xs, y, t0, t1 in S["strikes"]:
            self.strike(fr, xs, y, t, t0, t1, N["strike_w"])
        y, t0, t1 = S["full"]
        self.trait(fr, y, t, t0, t1)

    def s2_elements(self, fr: rd.Frame, t: float) -> None:
        S = plan.S2
        e = self.exit.at(t - S["exit"]) if t >= S["exit"] else 0.0
        fade, dy = 1 - e, -S["exit_rise"] * e
        if fade <= 0:
            return
        box = rb.mark_box(S["mark_centre"], S["mark_h"])
        self.mark(fr, self.mark_s2, t, S["dot"], S["draw"], fade, dy, "S2 mark", box)
        p = self.at("emphasis", t, S["unit_in"])
        self.unit(fr, S["unit_w"], S["unit_top"] + S["rise"] * (1 - p) + dy, p * fade, "S2 « MyWeli Pro »")
        p = self.at("emphasis", t, S["tag_in"])
        top = S["tag_box"][0] + S["rise"] * (1 - p) + dy
        lh = S["tag_box"][1] - S["tag_box"][0]
        fr.centred(self.words["S2"][1], P52, 540, rd.baseline_in(top, lh, P52), self.c["g700"], p * fade,
                   "S2 tagline", line_box=(top, top + lh))

    def s2(self, fr: rd.Frame, t: float, dry: bool) -> rd.Frame:
        spec = plan.S2["thicken"]
        if t < spec[2]:
            fr = self.ground(self.c["primary"], dry, self.notebook())
            self.s1(fr, plan.S1["full"][2])            # S1 as it ends: every strike drawn
            self.thicken(fr, spec, t)
        self.s2_elements(fr, t)
        return fr

    def s3(self, fr: rd.Frame, t: float, n: int) -> None:
        S = plan.S3
        self.s2_elements(fr, t)
        W0, W1 = S["W"]
        t_move, token = S["move"]
        W = W0 + (W1 - W0) * self.at(token, t, t_move)
        start = 1920 - rf.card_top(W0)
        offset = start * (1 - self.at("emphasis", t, S["enter"]))
        touches = []
        if t >= S["disc_in"] and self.fx is not None:
            a = self.at("fast", t, S["disc_in"]) * (1 - self.at("base", t, S["disc_out"]))
            x_pt, y_pt = self.fx.drag.at(t)
            x, y = rf.to_frame(W, x_pt, y_pt, offset)
            touches.append((x, y, self.c["primary"], a))
        if self.card is not None and not fr.dry:
            self.card.draw(fr, self.fx.take1b(n), W, offset, 1.0, touches)
        self.answer_headline(fr, "S3", t, S["head_in"])

    def bubble(self, fr: rd.Frame, k: int, top: float, scale: float, alpha: float) -> None:
        B = plan.S4
        w = self.words["S4"]
        text, ts = w[2 + 2 * k], w[3 + 2 * k]
        tw = rd.font_of(I48).getlength(text)
        sw = rd.font_of(I34).getlength(ts)
        width = B["pad_h"] + tw + B["ts_gap"] + sw + B["pad_h"]
        ox, oy = B["bubble_x"], top + B["bubble_h"] / 2           # scale about the left-centre
        x0, y0 = ox, oy + (top - oy) * scale
        x1, y1 = ox + width * scale, oy + (top + B["bubble_h"] - oy) * scale
        fr.note("shape", f"S4 bubble {k + 1}", (x0, y0, x1, y1), alpha)
        if alpha > 0 and not fr.dry:
            box = (math.floor(x0) - 1, math.floor(y0) - 1, math.ceil(x1) + 1, math.ceil(y1) + 1)
            cov = rd.rrect_coverage((x0, y0, x1, y1), B["radius"] * scale, box)
            fr.put(self.c["bubble"], cov * alpha, box[0], box[1])
        line_top = top + B["pad_v"]
        lh = B["bubble_h"] - 2 * B["pad_v"]
        base = rd.baseline_in(line_top, lh, I48)
        b = oy + (base - oy) * scale
        tx = ox + B["pad_h"] * scale
        fr.text(text, rd.scaled(I48, scale), tx, b, self.c["secondary"], alpha, f"S4 bubble {k + 1}",
                line_box=(oy + (line_top - oy) * scale, oy + (line_top + lh - oy) * scale))
        sx = ox + (B["pad_h"] + tw + B["ts_gap"]) * scale
        fr.text(ts, rd.scaled(I34, scale), sx, b, self.c["borderStrong"], alpha, f"S4 time {k + 1}")

    def s4(self, fr: rd.Frame, t: float) -> None:
        B = plan.S4
        self.pain_headline(fr, "S4", t, B["arrive"][0])
        # Newest first, so an older bubble still moving up (`base`, 200 ms)
        # passes OVER the one arriving under it (`fast`, 100 ms): drawn the
        # other way, the new message's words were printed across the old
        # one's for two frames (seen at 11.00 s, the first render).
        for k in reversed(range(len(B["arrive"]))):
            t_k = B["arrive"][k]
            if t < t_k:
                continue
            moved = sum(self.at("base", t, t_j) for t_j in B["arrive"][k + 1:])
            top = B["slots"][-1] - (B["bubble_h"] + B["gap"]) * moved
            p = 1.0 if k == 0 else self.at("fast", t, t_k)
            self.bubble(fr, k, top, 0.96 + 0.04 * p, p)
        y, t0, t1 = B["stroke"]
        self.trait(fr, y, t, t0, t1)

    def s5(self, fr: rd.Frame, t: float, dry: bool) -> rd.Frame:
        S = plan.S5
        spec = S["thicken"]
        if t < spec[2]:
            fr = self.ground(self.c["primary"], dry)
            self.s4(fr, plan.S4["stroke"][2])
            self.thicken(fr, spec, t)
        W = S["W"][0][0]
        for (w_from, _), (w_to, span) in zip(S["W"], S["W"][1:]):
            if t >= span[0]:
                W = w_from + (w_to - w_from) * plan.eased(S["camera_curve"], (t - span[0]) / (span[1] - span[0]))
        start = 1920 - rf.card_top(S["W"][0][0])
        offset = start * (1 - self.at("emphasis", t, S["enter"]))
        if self.card is not None and not fr.dry and t >= S["enter"]:
            self.card.draw(fr, self.fx.take5b(), W, offset)
        fr.note("mask", "S5 phone row", rf.mask_box_in_frame(W, offset), 1.0 if t >= S["enter"] else 0.0)
        self.answer_headline(fr, "S5", t, S["head_in"])
        return fr

    def s6(self, fr: rd.Frame, t: float) -> None:
        N, S = plan.NOTEBOOK, plan.S6
        w = self.words["S6"]
        t0 = self.P.scenes["S6"].start
        self.pain_headline(fr, "S6", t, t0)
        for i, b in enumerate(S["baselines"]):
            self.entry(fr, w[2 + i], N["entry_x"], b, t, S["pops"].get(i), f"S6 entry {i + 1}")
        x, b, t_pop = S["squeezed"]
        self.entry(fr, w[7], x, b, t, t_pop, "S6 walk-in", pop_scale=True)
        xs, y, a, z = S["strike"]
        self.strike(fr, xs, y, t, a, z, N["strike_w"])
        y, a, z = S["full"]
        self.trait(fr, y, t, a, z)

    def s7(self, fr: rd.Frame, t: float, n: int, dry: bool) -> rd.Frame:
        S = plan.S7
        spec = S["thicken"]
        if t < spec[2]:
            fr = self.ground(self.c["primary"], dry, self.notebook())
            self.s6(fr, plan.S6["full"][2])
            self.thicken(fr, spec, t)
        e = self.exit.at(t - S["exit"]) if t >= S["exit"] else 0.0
        if t >= S["enter"] and e < 1 and self.card is not None and not fr.dry:
            start = 1920 - rf.card_top(S["W"])
            offset = start * (1 - self.at("emphasis", t, S["enter"])) + S["exit_drop"] * e
            touches = []
            for (x, y), colour, t_in, t_out in S["taps"]:
                a = self.at("fast", t, t_in) * (1 - self.at("base", t, t_out))
                if a > 0:
                    touches.append((x, y, self.c[colour], a))
            self.card.draw(fr, self.fx.take1b(n), S["W"], offset, 1 - e, touches)
        self.answer_headline(fr, "S7", t, S["head_in"], fade=1 - e)
        return fr

    def pattern(self, t: float) -> np.ndarray:
        """The light brand pattern's coverage: the mark's outline 72 px tall
        on a brick grid, drifting up, kept out of the clear zone.

        The 80-px feather fades each mark WHOLE, by the distance from its own
        box to the clear zone: no mark's ink ever enters the zone, a mark
        80 px or more away is at full strength, and none is cut in half. (A
        feather on the pixels, as first built, left half-marks — « [ »
        shapes — along the zone's edge: seen on the first render's end
        card.)"""
        S = plan.S8
        W, H = self.P.size
        col, row = S["pattern_pitch"]
        drift = S["pattern_drift"] * (t - S["pattern_in"])
        Y = (np.arange(H, dtype=np.float32) + 0.5)[:, None]
        ys = Y + drift
        xs = (np.arange(W, dtype=np.float32) + 0.5)[None, :]
        r = np.floor((ys - H / 2) / row + 0.5)                   # row index, a row centred on the frame
        ly = ys - (H / 2 + r * row)
        shift = np.where(np.mod(r, 2) == 1, S["pattern_shift"], 0)
        lx = np.mod(xs - W / 2 - shift + col / 2, col) - col / 2
        pts, width = rb.mark_points((0, 0), S["pattern_h"])
        d = rd.polyline_distance(lx, ly, pts)
        cov = np.clip(width / 2 - d + 0.5, 0, 1)
        # each mark's box, in the frame, against the clear zone
        bx0, by0, bx1, by1 = rb.mark_box((0, 0), S["pattern_h"])
        cx, cy = xs - lx, Y - ly
        x0, x1, y0, y1 = S["clear"]
        gx = np.maximum(np.maximum(x0 - (cx + bx1), (cx + bx0) - x1), 0)
        gy = np.maximum(np.maximum(y0 - (cy + by1), (cy + by0) - y1), 0)
        keep = np.clip(np.sqrt(gx * gx + gy * gy) / S["feather"], 0, 1)
        return cov * keep

    @lru_cache(maxsize=None)
    def tile(self) -> tuple[np.ndarray, np.ndarray, np.ndarray, tuple[int, int], int]:
        S = plan.S8
        x, y, side = S["tile"]
        # a superellipse whose diagonal meets a « radius about 63 px » corner's
        r = S["tile_radius"]
        half = side / 2
        corner = half - r + r / math.sqrt(2)                     # the rounded square's corner point
        n = math.log(2) / math.log(half / corner)
        box = (x - 2, y - 2, x + side + 2, y + side + 2)
        cx, cy = x + half, y + half
        fill = rd.superellipse_coverage(cx, cy, half, n, box)
        inner = rd.superellipse_coverage(cx, cy, half, n, box, inset=S["tile_hairline"])
        shadow, pad = rd.soft_shadow(fill, plan.ANSWER["shadows"], S["shadow_strength"])
        return fill, fill - inner, shadow, (box[0], box[1]), pad

    def s8(self, fr: rd.Frame, t: float) -> None:
        S = plan.S8
        a = self.at("base", t, S["pattern_in"])
        if a > 0 and not fr.dry:
            fr.put(self.c["pattern"], self.pattern(t) * a, 0, 0)
        p = self.at("emphasis", t, S["tile_in"])
        x, y, side = S["tile"]
        if p > 0:
            fill, hair, shadow, (bx, by), pad = self.tile()
            fr.note("shape", "S8 icon tile", (x, y, x + side, y + side), p)
            if not fr.dry:
                fr.put(self.c["primary"], shadow * p, bx - pad, by - pad)
                fr.put(self.c["surface"], fill * p, bx, by)
                fr.put(self.c["border"], hair * p, bx, by)
        self.mark(fr, self.mark_s8, t, S["dot"], S["draw"], 1.0, 0.0, "S8 mark", self.mark_s8_box)
        p = self.at("emphasis", t, S["unit_in"])
        self.unit(fr, S["unit_w"], S["unit_top"] + S["rise"] * (1 - p), p, "S8 « MyWeli Pro »")
        p = self.at("emphasis", t, S["cta_in"])
        if p > 0:
            x0, y0, x1, y1 = S["pill"]
            dy = S["cta_rise"] * (1 - p)
            fr.note("shape", "S8 pill", (x0, y0 + dy, x1, y1 + dy), p)
            if not fr.dry:
                box = (x0 - 1, math.floor(y0 + dy) - 1, x1 + 1, math.ceil(y1 + dy) + 1)
                cov = rd.rrect_coverage((x0, y0 + dy, x1, y1 + dy), (y1 - y0) / 2, box)
                fr.put(self.c["primary"], cov * p, box[0], box[1])
            fr.centred(self.words["S8"][1], CTA, 540, rd.baseline_in(y0 + dy, y1 - y0, CTA), self.c["secondary"], p,
                       "S8 CTA", line_box=(y0 + dy, y1 + dy))

    # ---- one frame -------------------------------------------------------------------

    def frame(self, n: int, dry: bool = False) -> rd.Frame:
        t = n / self.P.fps
        key = self.P.scene_at(n)
        if key == "S1":
            fr = self.ground(self.c["primary"], dry, self.notebook())
            self.s1(fr, t)
        elif key == "S2":
            fr = self.s2(self.ground(self.c["surface"], dry), t, dry)
        elif key == "S3":
            fr = self.ground(self.c["surface"], dry)
            self.s3(fr, t, n)
        elif key == "S4":
            fr = self.ground(self.c["primary"], dry)
            self.s4(fr, t)
        elif key == "S5":
            fr = self.s5(self.ground(self.c["surface"], dry), t, dry)
        elif key == "S6":
            fr = self.ground(self.c["primary"], dry, self.notebook())
            self.s6(fr, t)
        elif key == "S7":
            fr = self.s7(self.ground(self.c["surface"], dry), t, n, dry)
        else:
            fr = self.ground(self.c["surface"], dry)
            self.s8(fr, t)
        return fr

    # ---- what the checks need -----------------------------------------------------------

    def reading_windows(self) -> list[dict]:
        """Each line the storyboard times: on screen from the start of its
        entrance to the start of its exit — or until the thickening « trait »
        covers it — against max(1.5 s, characters / 15 + 0.5 s)."""
        P, fps = self.P, self.P.fps

        def block(top, lh, lines, spec):
            f = rd.font_of(spec)
            wmax = max(f.getlength(s) for s in lines)
            return (540 - wmax / 2, top, 540 + wmax / 2, top + lh * len(lines))

        pain = (plan.PAIN["head_top"], plan.PAIN["head_lh"])
        rows = [
            ("S1 headline", self.words["S1"][:2], 0.0,
             covered_at(plan.S2["thicken"], block(*pain, self.words["S1"][:2], P92), fps)),
            ("S2 tagline", [self.words["S2"][1]], plan.S2["tag_in"], plan.S2["exit"]),
            ("S3 headline", self.words["S3"], plan.S3["head_in"], P.scenes["S3"].end),
            ("S4 headline", self.words["S4"][:2], P.scenes["S4"].start,
             covered_at(plan.S5["thicken"], block(*pain, self.words["S4"][:2], P92), fps)),
            ("S5 headline", self.words["S5"], plan.S5["head_in"], P.scenes["S5"].end),
            ("S6 headline", self.words["S6"][:2], P.scenes["S6"].start,
             covered_at(plan.S7["thicken"], block(*pain, self.words["S6"][:2], P92), fps)),
            ("S7 headline", self.words["S7"], plan.S7["head_in"], plan.S7["exit"]),
            ("S8 CTA", [self.words["S8"][1]], plan.S8["cta_in"], P.duration),
        ]
        out = []
        for label, lines, a, b in rows:
            chars = len(" ".join(lines))
            need = max(1.5, chars / 15 + 0.5)
            out.append({"label": label, "chars": chars, "in": a, "out": b, "on": b - a, "need": need})
        return out
