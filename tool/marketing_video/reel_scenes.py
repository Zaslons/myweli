"""The film, frame by frame: « Le trait ». Design: docs/design/pro-marketing-reel.md §2.

`Composer.frame(n)` draws film frame n (t = n / 30 s) from the plan, the
brand art and the footage. Every word comes from the storyboard through
`reel_plan` (by scene and index); every number from the plan's tables;
every duration and curve from `motion.dart`'s tokens, except the strokes'
own timing (the storyboard's, on the Lottie curve) and S5's camera moves
(« 600 ms easeInOutCubic, not UI motion »).

Amendment A1 (owner, 2026-10-18) puts the owner's pictures in the hook (S1)
and in a people beat (S7b), through `reel_photo`. The review's fixes (R1):
every card enters as S3's does — the card as it rests, clipped by the band,
rises 1320 px; S4's bubbles move as one column; S2's exiting logo is drawn
over S3's card; every strike starts at a short visible length.

One choice the storyboard leaves open, taken the calmer way (README,
« Deviations »): where S8's pen dot overlaps the start of the draw, the
stroke's width follows the dot's growth until the dot is whole, so the pen
never jumps.
"""

from __future__ import annotations

import math
from functools import lru_cache

import numpy as np
from PIL import Image, ImageFilter

import reel_brand as rb
import reel_draw as rd
import reel_footage as rf
import reel_photo as rp
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


def far_from(xs: tuple[float, float], y: float, box: tuple[float, float, float, float]) -> float:
    """The farthest corner of `box` from the segment xs at y."""
    x0, x1 = xs
    far = 0.0
    for bx in (box[0], box[2]):
        for by in (box[1], box[3]):
            dx = max(x0 - bx, 0, bx - x1)
            far = max(far, math.hypot(dx, by - y))
    return far


def covered_at(spec: tuple, xs: tuple[float, float], box: tuple[float, float, float, float], fps: int) -> float:
    """The first frame time at which the thickening « trait » `spec` about
    the segment `xs` covers `box` whole — when the words under it are gone."""
    y, t0, t1, _, _ = spec
    x0, x1 = xs
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
        self.card_art = rf.Card() if footage is not None else None
        self.mark_s2 = rb.mark_points(plan.S2["mark_centre"], plan.S2["mark_h"])
        centre, height = rb.icon_mark()
        self.mark_s8 = rb.mark_points(centre, height)
        self.mark_s8_box = rb.mark_box(centre, height)
        self.draw_s = rb.mark_geometry()["draw_s"]
        # the S1 stroke runs from the picture's anchor (the pen tip) to the page's edge
        self.s1_x = (plan.S1["anchor_src"][0] * rp.base_scale(plan.S1, P.size), plan.S1["stroke"][0])
        if round(self.s1_x[0], 1) != 246.8:
            plan.die(f"the S1 stroke starts at x {self.s1_x[0]:.2f}, the storyboard says 246.8")
        self.thickens = {"S2": (plan.S2["thicken"], self.s1_x),
                         "S5": (plan.S5["thicken"], plan.NOTEBOOK["stroke_x"]),
                         "S7": (plan.S7["thicken"], plan.NOTEBOOK["stroke_x"])}
        for key, (spec, xs) in self.thickens.items():     # the « trait » ends as the whole page
            corners = (0, 0, P.width, P.height)
            if spec[4] / 2 < far_from(xs, spec[0], corners):
                plan.die(f"{key}'s trait ends {spec[4]} px wide: it leaves a corner of the frame uncovered")
        S = P.scenes
        self.words = {
            "S1": [S["S1"].text(i) for i in range(len(S["S1"].texts))],
            "S2": [S["S2"].text(i) for i in range(len(S["S2"].texts))],
            "S3": [S["S3"].text(i) for i in range(2)],
            "S4": [S["S4"].text(i) for i in range(len(S["S4"].texts))],
            "S5": [S["S5"].text(i) for i in range(2)],
            "S6": [S["S6"].text(i) for i in range(len(S["S6"].texts))],
            "S7": [S["S7"].text(i) for i in range(2)],
            "S7b": [S["S7b"].text(i) for i in range(2)],
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
            rd.stroke(fr, rd.drawn_line(x[0], x[1], y, f, plan.STRIKE_MIN * width), width, self.c["surface"])

    def trait(self, fr: rd.Frame, y: float, t: float, t0: float, t1: float) -> None:
        """The full-width « trait »: 8 px, round caps, left to right."""
        self.strike(fr, plan.NOTEBOOK["stroke_x"], y, t, t0, t1, plan.NOTEBOOK["stroke_w"])

    def thicken(self, fr: rd.Frame, key: str, t: float, shadow: tuple | None = None) -> None:
        spec, (x0, x1) = self.thickens[key]
        y = spec[0]
        pts = [(x0, y), (x1, y)]
        width = capsule_width(t, spec)
        if shadow is not None:
            rd.stroke_shadow(fr, pts, width, shadow)
        rd.stroke(fr, pts, width, self.c["surface"])

    # ---- the pictures (A1) and the card ------------------------------------------------

    def photo_ground(self, key: str, spec: dict, t: float, dry: bool) -> rd.Frame:
        """One of A1's pictures as the ground, with its gradient."""
        fr = rd.Frame(self.P.size, self.c["primary"], dry)
        pl = rp.placement(spec, t, self.P.size)
        fr.note("photo", f"{key} picture", pl.box(), 1.0,
                {"scale": pl.scale, "base": pl.base, "push": spec["push"][0], "fill": spec["fill"]})
        if not dry and self.fx is not None:
            arr = rp.render(self.fx.photo(spec["photo"]), pl, spec, self.P.size)
            fr.im = Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGB")
        return fr

    def enter_offset(self, t: float, t_in: float) -> float:
        """How far below its resting place a card is: 1320 px when it starts
        to enter, 0 at rest (`emphasis`)."""
        return plan.ANSWER["enter_travel"] * (1 - self.at("emphasis", t, t_in))

    def card(self, fr: rd.Frame, key: str, picture, W: float, offset: float, touches=()) -> None:
        top = rf.card_top(W, offset)
        fr.note("card", f"{key} card", (plan.ANSWER["card_x"], top, plan.ANSWER["card_x"] + plan.ANSWER["card_w"],
                                         top + rf.card_height()), 1.0, {"W": W, "offset": offset})
        if self.card_art is not None and not fr.dry:
            self.card_art.draw(fr, picture(), W, offset, 1.0, touches)

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
        """A1: the picture (the ground), the question, and the stroke that
        leaves her pen and crosses out her page."""
        S = plan.S1
        self.pain_headline(fr, "S1", t, 0.0)
        x0, x1 = self.s1_x
        _, y, t0, t1 = S["stroke"]
        w = plan.NOTEBOOK["stroke_w"]
        f = self.stroke_progress(t, t0, t1)
        if f is not None:
            pts = rd.drawn_line(x0, x1, y, f, plan.STRIKE_MIN * w)
            rd.stroke_shadow(fr, pts, w, S["stroke_shadow"])
            rd.stroke(fr, pts, w, self.c["surface"])
            fr.note("shape", "S1 stroke", (pts[0][0] - w / 2, y - w / 2, pts[-1][0] + w / 2, y + w / 2), 1.0)

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
            fr = self.photo_ground("S1", plan.S1, t, dry)
            self.s1(fr, plan.S1["stroke"][3])           # S1 as it ends: the stroke drawn
            self.thicken(fr, "S2", t, plan.S1["stroke_shadow"])
        self.s2_elements(fr, t)
        return fr

    def s3(self, fr: rd.Frame, t: float, n: int) -> None:
        S = plan.S3
        W0, W1 = S["W"]
        t_move, token = S["move"]
        W = W0 + (W1 - W0) * self.at(token, t, t_move)
        offset = self.enter_offset(t, S["enter"])
        touches = []
        if t >= S["disc_in"] and self.fx is not None:
            a = self.at("fast", t, S["disc_in"]) * (1 - self.at("base", t, S["disc_out"]))
            x_pt, y_pt = self.fx.drag.at(t)
            x, y = rf.to_frame(W, x_pt, y_pt)             # where the card rests
            touches.append((x, y, self.c["primary"], a))
        self.card(fr, "S3", lambda: self.fx.take1b(n), W, offset, touches)
        # S2's lockup leaves OVER the rising card (R1), on its own clear space
        # of paper at its own opacity: the card dissolves in under the logo,
        # never printed across it nor it across the card's words
        e = self.exit.at(t - plan.S2["exit"]) if t >= plan.S2["exit"] else 0.0
        if e < 1 and not fr.dry:
            plate, x0, y0 = self.s2_plate()
            fr.put(self.c["surface"], plate * (1 - e), x0, round(y0 - plan.S2["exit_rise"] * e))
        self.s2_elements(fr, t)
        self.answer_headline(fr, "S3", t, S["head_in"])

    @lru_cache(maxsize=None)
    def s2_plate(self) -> tuple[np.ndarray, int, int]:
        """The lockup's clear space — the mark and the « MyWeli Pro » unit
        with half the mark's height all round, and the tagline's line with a
        margin — as a soft-edged coverage of paper."""
        fr = rd.Frame(self.P.size, self.c["surface"], dry=True)
        self.s2_elements(fr, plan.S2["exit"])
        logo = [b.ink for b in fr.boxes if b.kind == "logo"]
        lines = [b.line or b.ink for b in fr.boxes if b.kind == "text"]
        clear = plan.S2["mark_h"] / 2
        boxes = [(min(b[0] for b in logo) - clear, min(b[1] for b in logo) - clear,
                  max(b[2] for b in logo) + clear, max(b[3] for b in logo) + clear)]
        boxes += [(b[0] - 24, b[1] - 24, b[2] + 24, b[3] + 24) for b in lines]
        feather = 24
        x0 = max(0, math.floor(min(b[0] for b in boxes)) - 2 * feather)
        y0 = max(0, math.floor(min(b[1] for b in boxes)) - 2 * feather)
        x1 = min(self.P.width, math.ceil(max(b[2] for b in boxes)) + 2 * feather)
        y1 = min(self.P.height, math.ceil(max(b[3] for b in boxes)) + 2 * feather)
        cov = np.zeros((y1 - y0, x1 - x0), np.float32)
        for b in boxes:
            cov = np.maximum(cov, rd.rrect_coverage(b, feather, (x0, y0, x1, y1)))
        im = Image.fromarray(np.clip(cov * 255 + 0.5, 0, 255).astype(np.uint8), "L")
        im = im.filter(ImageFilter.GaussianBlur(feather / 2))
        return np.asarray(im, np.float32) / 255, x0, y0

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
        """The chat column (R1): a new bubble enters one slot below the
        bottom slot and rises into it WITH the older bubbles — one column,
        moving together on `base` — while it fades and scales in on `fast`.
        Nothing below the column's bottom edge (y 1152) is drawn, so it
        rises into view; no two bubbles ever overlap (verify checks it)."""
        B = plan.S4
        self.pain_headline(fr, "S4", t, B["arrive"][0])
        pitch = B["bubble_h"] + B["gap"]
        fr.clip_bottom = B["column_bottom"]
        for k, t_k in enumerate(B["arrive"]):
            if t < t_k:
                continue
            lift = sum(self.at("base", t, t_j) for t_j in B["arrive"][k + 1:])
            rise = 0.0 if k == 0 else 1 - self.at("base", t, t_k)
            top = B["slots"][-1] + pitch * (rise - lift)
            p = 1.0 if k == 0 else self.at("fast", t, t_k)
            self.bubble(fr, k, top, 0.96 + 0.04 * p, p)
        fr.clip_bottom = None
        y, t0, t1 = B["stroke"]
        self.trait(fr, y, t, t0, t1)

    def s5(self, fr: rd.Frame, t: float, dry: bool) -> rd.Frame:
        S = plan.S5
        spec = S["thicken"]
        if t < spec[2]:
            fr = self.ground(self.c["primary"], dry)
            self.s4(fr, plan.S4["stroke"][2])
            self.thicken(fr, "S5", t)
        W = S["W"][0][0]
        for (w_from, _), (w_to, span) in zip(S["W"], S["W"][1:]):
            if t >= span[0]:
                W = w_from + (w_to - w_from) * plan.eased(S["camera_curve"], (t - span[0]) / (span[1] - span[0]))
        offset = self.enter_offset(t, S["enter"])
        if t >= S["enter"]:
            self.card(fr, "S5", lambda: self.fx.take5b(), W, offset)
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

    def s7_window(self, t: float) -> float:
        """W 553, then the pan to 682 as « Ma journée » comes back (R1): the
        old 13:15 « Yao K. » row slides under the band."""
        S = plan.S7
        n0, w1, token = S["pan"]
        return S["W"] + (w1 - S["W"]) * self.at(token, t, n0 / self.P.fps)

    def s7(self, fr: rd.Frame, t: float, n: int, dry: bool) -> rd.Frame:
        S = plan.S7
        spec = S["thicken"]
        if t < spec[2]:
            fr = self.ground(self.c["primary"], dry, self.notebook())
            self.s6(fr, plan.S6["full"][2])
            self.thicken(fr, "S7", t)
        if t >= S["enter"]:
            W = self.s7_window(t)
            touches = []
            for (x, y), colour, t_in, t_out in S["taps"]:
                a = self.at("fast", t, t_in) * (1 - self.at("base", t, t_out))
                if a > 0:            # the tap's point moves with the content
                    touches.append((x, y - (W - S["W"]) * plan.PX_PER_PT, self.c[colour], a))
            self.card(fr, "S7", lambda: self.fx.take1b(n), W, self.enter_offset(t, S["enter"]), touches)
        fade = 1 - self.exit.at(t - S["head_out"]) if t >= S["head_out"] else 1.0
        self.answer_headline(fr, "S7", t, S["head_in"], fade=fade)
        return fr

    def s7b(self, t: float, dry: bool) -> rd.Frame:
        """A1's people beat: the picture, its gradient and the caption."""
        S = plan.S7B
        fr = self.photo_ground("S7b", S, t, dry)
        alphas, dys = [], []
        for i in range(2):
            p = self.at("emphasis", t, S["in"] + i * self.stagger)
            alphas.append(p)
            dys.append(24 * (1 - p))
        self.headline(fr, self.words["S7b"], ("poppins", S["head_px"]), S["head_top"], S["head_lh"],
                      self.c["secondary"], alphas, dys, label="S7b caption")
        return fr

    def dissolve_in(self, n: int, cut: int, token: str) -> float:
        """How far a dissolve that starts on the cut frame has gone: frame
        cut-1 is the last whole picture of the scene before."""
        return self.T[token].at((n - (cut - 1)) / self.P.fps)

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
            fr = self.photo_ground("S1", plan.S1, t, dry)
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
        elif key == "S7b":
            fr = self.s7b(t, dry)
            cut = round(plan.S7B["in"] * self.P.fps)
            k = self.dissolve_in(n, cut, plan.S7B["dissolve"])
            if k < 1:            # the S7 page, as it ends, dissolves into the picture
                fr = rd.blend(self.s7(self.ground(self.c["surface"], dry), plan.S7B["in"], cut - 1, dry), fr, k)
        else:
            fr = self.ground(self.c["surface"], dry)
            self.s8(fr, t)
            cut = round(plan.S7B["out"] * self.P.fps)
            k = self.dissolve_in(n, cut, plan.S7B["dissolve"])
            if k < 1:            # the picture and its caption dissolve into the end card
                fr = rd.blend(self.s7b(t, dry), fr, k)
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
        th = self.thickens
        rows = [
            ("S1 headline", self.words["S1"][:2], 0.0,
             covered_at(*th["S2"], block(*pain, self.words["S1"][:2], P92), fps)),
            ("S2 tagline", [self.words["S2"][1]], plan.S2["tag_in"], plan.S2["exit"]),
            ("S3 headline", self.words["S3"], plan.S3["head_in"], P.scenes["S3"].end),
            ("S4 headline", self.words["S4"][:2], P.scenes["S4"].start,
             covered_at(*th["S5"], block(*pain, self.words["S4"][:2], P92), fps)),
            ("S5 headline", self.words["S5"], plan.S5["head_in"], P.scenes["S5"].end),
            ("S6 headline", self.words["S6"][:2], P.scenes["S6"].start,
             covered_at(*th["S7"], block(*pain, self.words["S6"][:2], P92), fps)),
            ("S7 headline", self.words["S7"], plan.S7["head_in"], plan.S7["head_out"]),
            ("S7b caption", self.words["S7b"], plan.S7B["in"], plan.S7B["out"]),
            ("S8 CTA", [self.words["S8"][1]], plan.S8["cta_in"], P.duration),
        ]
        out = []
        for label, lines, a, b in rows:
            chars = len(" ".join(lines))
            need = max(1.5, chars / 15 + 0.5)
            row = {"label": label, "chars": chars, "in": a, "out": b, "on": b - a, "need": need, "floor": need}
            if label == "S7b caption":
                # A1 gives the caption its whole 2.0-s beat, short of the rule:
                # the storyboard says so, the report shows both, and the beat
                # itself is the floor (a caption cut shorter still fails)
                row["floor"] = min(need, plan.S7B["reading_allowance"])
            out.append(row)
        return out
