"""The real app in the card: the takes, conformed, masked, framed.
Design: docs/design/pro-marketing-reel.md §3 and §5.

  takes      take1b (S3, S7) and take5b (S5), the production recordings of
             2026-10-14, read from the main checkout's build/ folder (never
             copied into git). Each kept range is exported by the App
             Preview's own `conform export` (tool/app_store_preview/swift/
             Conform.swift): film frame n shows the last picture the take
             presented at or before its instant — frame-hold, never a blend,
             never a change of speed. The one blend is S7's declared
             dissolve, between two held pictures.
  the mask   take5b's salon phone row is painted (255, 255, 255) in capture
             space, before any scaling or camera move, so it is hidden on
             every frame by construction. The rectangle must hold the row's
             ink and sit on pure white all round, or the build stops.
  the drag   S3's touch point follows the App Store film's S1 drag
             (build/app-store/pro/preview/v2/final/film.json): the path
             that film verified frame by frame against the swiped card
             (tool/app_store_preview/track.py), 7.0 s later — the Reel's
             LIVE range starts on the same take instant 7.0 s later than
             that film's. The file must name take1b's bytes.
  the card   the capture from screen point 56 down (no status bar, no
             Dynamic Island), 900 px wide at x 90–990, radius 110, a 3-px
             `border` ring and the stills' two shadows scaled to 1080. A
             camera window W puts screen point p at y = 600 + (p − W) x
             2.2388. Resampled straight from the capture with a fractional
             box, so a camera move lands on the sub-pixel. A band of paper
             covers y 0–552 and fades out over 552–600 above the card: the
             card's layer is clipped by it, what lies under the card is not.
             The card and its shadow are ONE group under the band's fade
             (R1: laid apart, the shadow showed through the half-faded card
             as a grey smear). The band clips the card where it RESTS: an
             entrance moves that clipped layer up from 1320 px lower, so
             every card rises the same 1320 px, whatever its camera window.
"""

from __future__ import annotations

import hashlib
import json
import math
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import reel_draw as rd
import reel_photo
import reel_plan as plan
import swifttools  # tool/app_store_preview/swifttools.py — compiles and runs Conform.swift

TAKE_TIMESCALE = 600
FILM_TICKS = TAKE_TIMESCALE // 30          # one film frame, in the take's ticks
PAD_ROWS = 4                               # rows of edge added above and below a capture


def take_paths(assets: Path) -> dict[str, Path]:
    v2 = assets / "preview/v2"
    return {"take1b": v2 / "takes/take1b/take.mov", "take5b": v2 / "takes/take5b/take.mov",
            "film": v2 / "final/film.json"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


# ---- which picture of which take each film frame shows ----------------------------------

# take1b, exported once: the S3 ranges, then the S7 ranges. (kind, ticks, …)
TAKE1B_SEGMENTS = [
    ("hold", 6397), ("live", 6397, 6977), ("hold", 6957),            # S3: rest, the swipe, the open pane
    ("hold", 19299), ("live", 19299, 19819), ("hold", 19799),        # S7: rest, « Libre » → « Réservation »
    ("hold", 78157), ("live", 78157, 79317), ("hold", 79297),        # S7: the filled form → « Créer » → the day
]


def segments_json(segments: list[tuple]) -> dict:
    out = []
    for s in segments:
        if s[0] == "hold":
            out.append({"kind": "hold", "src_at": s[1], "frames": 1})
        else:
            out.append({"kind": "live", "src_in": s[1], "src_out": s[2]})
    return {"fps": 30, "segments": out}


def segment_starts(segments: list[tuple]) -> list[int]:
    """Where each segment starts in the exported list."""
    starts, k = [], 0
    for s in segments:
        starts.append(k)
        k += 1 if s[0] == "hold" else (s[2] - s[1]) // FILM_TICKS
    return starts + [k]


def take1b_index(n: int) -> int | tuple[int, int, float]:
    """The exported picture film frame n shows — or, in S7's declared
    dissolve, the two it blends and how far (0..1) on `base`."""
    st = segment_starts(TAKE1B_SEGMENTS)
    if 180 <= n <= 227:
        return st[0]
    if 228 <= n <= 256:                    # LIVE 7.600–8.567, 29 frames, 1:1
        return st[1] + (n - 228)
    if 257 <= n <= 299:
        return st[2]
    for run in plan.S7["runs"]:
        kind, a, b, what = run[:4]
        if a <= n <= b:
            if kind == "hold":
                return {19299: st[3], 19799: st[5], 78157: st[6], 79297: st[8]}[what]
            if kind == "live":
                return (st[4] if what == 19299 else st[7]) + (n - a)
            # the declared dissolve, on its token: frame a-1 is the clean last
            # picture of A; the run ends on B whole (k = 1)
            k = plan.tokens()[run[4]].at((n - (a - 1)) / 30)
            return (st[5], st[6], k)
    plan.die(f"film frame {n} shows no picture of take1b")


def check_take_map(manifest: dict) -> list[str]:
    """Each LIVE and HOLD range against the take's own map: a hold before a
    live range shows the picture the range starts on, the hold after it the
    picture it ends on, a live range never goes back, and every picture is
    the last one presented at or before its instant. Returns the faults."""
    film = manifest["film"]
    pts = {int(k): v["pts"] for k, v in manifest["sources"].items()}
    faults = []
    st = segment_starts(TAKE1B_SEGMENTS)
    if len(film) != st[-1]:
        faults.append(f"{len(film)} exported pictures, the plan needs {st[-1]}")
        return faults
    for i, s in enumerate(TAKE1B_SEGMENTS):
        a = st[i]
        if s[0] == "hold":
            if pts[film[a]] > s[1]:
                faults.append(f"the hold at {s[1]} ticks shows a picture from {pts[film[a]]}")
        else:
            run = film[a:st[i + 1]]
            if any(y < x for x, y in zip(run, run[1:])):
                faults.append(f"the live range {s[1]}–{s[2]} goes back in the take")
            for k, j in enumerate(run):
                if pts[j] > s[1] + k * FILM_TICKS:
                    faults.append(f"the live range {s[1]}–{s[2]}: frame {k} shows a later picture")
                    break
            if i > 0 and TAKE1B_SEGMENTS[i - 1][0] == "hold" and film[a - 1] != run[0]:
                faults.append(f"the hold before {s[1]}–{s[2]} is not the picture the range starts on")
            if i + 1 < len(TAKE1B_SEGMENTS) and TAKE1B_SEGMENTS[i + 1][0] == "hold" and film[st[i + 1]] != run[-1]:
                faults.append(f"the hold after {s[1]}–{s[2]} is not the picture the range ends on")
    return faults


def conform(take: Path, segments: list[tuple], out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    seg = out / "segments.json"
    seg.write_text(json.dumps(segments_json(segments), indent=1), encoding="utf-8")
    swifttools.run("conform", "export", take, "--segments", seg, "--out", out)
    return json.loads((out / "manifest.json").read_text(encoding="utf-8"))


# ---- the mask ---------------------------------------------------------------------------

def mask_take5b(im: Image.Image) -> Image.Image:
    """S5's salon phone row, filled white in capture space — refused unless
    the rectangle holds the row's ink and is ringed by pure white."""
    x, y, w, h = plan.S5["mask"]
    a = np.asarray(im.convert("L"), dtype=np.int16)
    inside = a[y:y + h, x:x + w]
    ring = np.concatenate([a[y - 3:y, x - 3:x + w + 3].ravel(), a[y + h:y + h + 3, x - 3:x + w + 3].ravel(),
                           a[y:y + h, x - 3:x].ravel(), a[y:y + h, x + w:x + w + 3].ravel()])
    if inside.min() > 128:
        plan.die(f"take5b's mask rectangle {plan.S5['mask']} holds no ink: it is not on the phone row")
    if ring.min() < 250:
        plan.die(f"take5b's mask rectangle {plan.S5['mask']} is not ringed by white (darkest {ring.min()}): "
                 f"the row's ink crosses its edge")
    out = im.copy()
    ImageDraw.Draw(out).rectangle((x, y, x + w - 1, y + h - 1), fill=plan.S5["mask_fill"])
    return out


def mask_box_in_frame(W: float, offset: float = 0.0) -> tuple[float, float, float, float]:
    """Where S5's mask lands in the frame at camera W."""
    x, y, w, h = plan.S5["mask"]
    k = plan.PX_PER_PT / 3                    # frame px per capture px
    top = card_top(W, offset)
    y0 = top + (y - plan.ANSWER["card_top_pt"] * 3) * k
    return (90 + x * k, y0, 90 + (x + w) * k, y0 + h * k)


# ---- the App Store film's drag ----------------------------------------------------------

@dataclass
class Drag:
    path: list[list[float]]       # [film ticks, x pt, y pt]
    step: tuple[int, int]         # where the point holds per picture
    down: int
    up: int
    shift: int                    # ticks added to reach the Reel's time

    def at(self, t: float) -> tuple[float, float]:
        """The point's position (pt) at Reel time t — the App Store film's
        `frames.Composer.touch_state` path rule, step for step."""
        tt = t * TAKE_TIMESCALE - self.shift
        held_from, held_to = self.step
        x, y = self.path[-1][1], self.path[-1][2]
        if tt <= self.path[0][0]:
            return self.path[0][1], self.path[0][2]
        for (ta, xa, ya), (tb, xb, yb) in zip(self.path, self.path[1:]):
            if tt < tb:
                u = max(0.0, (tt - ta) / (tb - ta))
                if held_from <= ta and tb <= held_to:
                    u = 0.0
                return xa + (xb - xa) * u, ya + (yb - ya) * u
        return x, y


def app_store_drag(film_json: Path, take1b: Path) -> Drag:
    film = json.loads(film_json.read_text(encoding="utf-8"))
    s1 = next(s for s in film["scenes"] if s["id"] == "S1")
    if s1["take"]["sha256"] != sha256(take1b):
        plan.die(f"{film_json} was cut from another take than {take1b}")
    t = next(x for x in s1["touches"] if x["gesture"] == "S1/swipe-arrive")
    live = next(seg for seg in s1["runs"][0]["segments"] if seg["kind"] == "live")
    if (live["src_in"], live["src_out"]) != TAKE1B_SEGMENTS[1][1:]:
        plan.die("the App Store film's S1 live range is not the Reel's S3 range")
    # that film's live range starts after its 18-frame lead-in; the Reel's at 7.600 s
    lead = next(seg for seg in s1["runs"][0]["segments"] if seg["kind"] == "hold")["frames"]
    shift = round(plan.S3["live"][0] * TAKE_TIMESCALE) - lead * FILM_TICKS
    if abs(shift / TAKE_TIMESCALE - plan.S3["drag_shift_s"]) > 1e-9:
        plan.die(f"the drag moves by {shift / TAKE_TIMESCALE} s, the plan says {plan.S3['drag_shift_s']}")
    d = Drag(t["path"], tuple(t.get("step") or (1, 0)), t["down"], t["up"], shift)
    # the storyboard: « Touch-down lands at 7.61 … film 7.61–8.36 », « from 110 to 250 pt »
    if round((d.down + shift) / TAKE_TIMESCALE, 2) != 7.61 or round((d.up + shift) / TAKE_TIMESCALE, 2) != 8.36:
        plan.die("the App Store film's drag no longer lands at 7.61–8.36 s in the Reel")
    if (d.path[0][1], d.path[-1][1]) != (110.0, 250):
        plan.die("the App Store film's drag no longer runs from 110 to 250 pt")
    return d


# ---- the card --------------------------------------------------------------------------

def card_top(W: float, offset: float = 0.0) -> float:
    A = plan.ANSWER
    return A["rest_y"] + (A["card_top_pt"] - W) * plan.PX_PER_PT + offset


def card_height() -> float:
    A = plan.ANSWER
    return (A["screen_pt"][1] - A["card_top_pt"]) * plan.PX_PER_PT


def to_frame(W: float, x_pt: float, y_pt: float, offset: float = 0.0) -> tuple[float, float]:
    A = plan.ANSWER
    return A["card_x"] + x_pt * plan.PX_PER_PT, A["rest_y"] + (y_pt - W) * plan.PX_PER_PT + offset


def padded(im: Image.Image) -> Image.Image:
    """The capture with its first and last rows repeated PAD_ROWS times, so
    a resampling box may reach a fraction of a row past either end."""
    im = im.convert("RGB")
    out = Image.new("RGB", (im.width, im.height + 2 * PAD_ROWS))
    out.paste(im, (0, PAD_ROWS))
    out.paste(im.crop((0, 0, im.width, 1)).resize((im.width, PAD_ROWS)), (0, 0))
    out.paste(im.crop((0, im.height - 1, im.width, im.height)).resize((im.width, PAD_ROWS)),
              (0, im.height + PAD_ROWS))
    return out


class Card:
    def __init__(self):
        A = plan.ANSWER
        self.c = plan.colours()
        self.h = card_height()
        self.w = A["card_w"]
        full = rd.rrect_coverage((0, 0, self.w, self.h), A["radius"], (0, 0, self.w, math.ceil(self.h)))
        self.shadow, self.pad = rd.soft_shadow(full, A["shadows"])
        self.k = A["card_w"] / A["capture"][0]          # frame px per capture px

    @staticmethod
    def band(ys: np.ndarray) -> np.ndarray:
        """1 where the card shows, 0 under the paper band, linear between."""
        A = plan.ANSWER
        return np.clip((ys + 0.5 - A["band_solid"]) / (A["band_clear"] - A["band_solid"]), 0.0, 1.0)

    def draw(self, fr: rd.Frame, picture: Image.Image, W: float, offset: float = 0.0, opacity: float = 1.0,
             touches: list[tuple[float, float, tuple, float]] = ()) -> None:
        """`picture`: a padded capture. `offset`: how far below its resting
        place the card is (an entrance). `touches`: (x, y, colour, opacity)
        where the card rests, drawn on the card and clipped by it.

        The card and its shadow are composed as one group — the card over
        its shadow — and the group is laid on the frame through the band
        (taken where the card rests) and `opacity`: under a half-faded band
        the paper shows through, never the shadow."""
        if fr.dry or opacity <= 0:
            return
        A = plan.ANSWER
        FW, H = fr.size
        top = card_top(W, offset)
        bottom = top + self.h
        x0 = A["card_x"]
        sy0 = round(top) - self.pad                   # the shadow array's first row, in the frame
        gx0 = x0 - self.pad
        ya = max(0, sy0, math.floor(A["band_solid"] + offset))
        yb = min(H, sy0 + self.shadow.shape[0])
        if yb <= ya:
            return
        gw = self.shadow.shape[1]
        shadow = self.shadow[ya - sy0:yb - sy0]
        cov_g = np.zeros((yb - ya, gw), np.float32)                 # the card's coverage in the group
        colour = np.zeros((yb - ya, gw, 3), np.float32)             # premultiplied: the shadow is black
        ca, cb = max(ya, math.floor(top)), min(yb, math.ceil(bottom))
        if cb > ca:
            cap_top = A["card_top_pt"] * 3 + PAD_ROWS                # capture row of the card's top edge, padded
            s0 = cap_top + (ca - top) / self.k
            s1 = cap_top + (cb - top) / self.k
            region = picture.resize((self.w, cb - ca), Image.LANCZOS, box=(0, s0, picture.width, s1))
            rgb = np.asarray(region, dtype=np.float32)
            box = (x0, ca, x0 + self.w, cb)
            cov = rd.rrect_coverage((x0, top, x0 + self.w, bottom), A["radius"], box)
            ring = cov - rd.rrect_coverage((x0, top, x0 + self.w, bottom), A["radius"], box, inset=A["ring"])
            for tx, ty, tc, t_op in touches:
                if t_op <= 0:
                    continue
                t = plan.TOUCH
                r = t["diameter"] / 2
                outer = rd.disc_coverage(tx, ty + offset, r, box)
                inner = rd.disc_coverage(tx, ty + offset, r - t["ring"], box)
                ta = (inner * t["fill"] + (outer - inner) * t["ring_alpha"]) * t_op
                rgb = rgb * (1 - ta[..., None]) + np.array(tc, np.float32) * ta[..., None]
            rgb = rgb * (1 - ring[..., None]) + np.array(self.c["border"], np.float32) * ring[..., None]
            cov_g[ca - ya:cb - ya, self.pad:self.pad + self.w] = cov
            colour[ca - ya:cb - ya, self.pad:self.pad + self.w] = rgb * cov[..., None]
        group = cov_g + shadow * (1 - cov_g)
        rows = np.arange(ya, yb, dtype=np.float32)
        a = (self.band(rows - offset) * opacity)[:, None]
        # clip the group to the frame's width
        cx0, cx1 = max(0, gx0), min(FW, gx0 + gw)
        sl = slice(cx0 - gx0, cx1 - gx0)
        under = np.asarray(fr.im.crop((cx0, ya, cx1, yb)), dtype=np.float32)
        out = under * (1 - (a * group[:, sl])[..., None]) + colour[:, sl] * a[..., None]
        fr.im.paste(Image.fromarray(np.clip(out + 0.5, 0, 255).astype(np.uint8), "RGB"), (cx0, ya))


class Footage:
    """The pictures the card shows, loaded once per process."""

    def __init__(self, work: Path):
        self.work = work
        self.photos: dict[str, Image.Image] = {}
        self.m1 = json.loads((work / "take1b/manifest.json").read_text(encoding="utf-8"))
        self.m5 = json.loads((work / "take5b/manifest.json").read_text(encoding="utf-8"))
        self.drag = Drag(**json.loads((work / "drag.json").read_text(encoding="utf-8")))
        self._cache: dict[str, Image.Image] = {}

    def _load(self, folder: str, manifest: dict, i: int, masked: bool = False) -> Image.Image:
        name = manifest["sources"][str(manifest["film"][i])]["file"]
        key = f"{folder}/{name}"
        if key not in self._cache:
            im = Image.open(self.work / folder / name).convert("RGB")
            if masked:
                im = mask_take5b(im)
            self._cache[key] = padded(im)
        return self._cache[key]

    def take1b(self, n: int) -> Image.Image:
        i = take1b_index(n)
        if isinstance(i, tuple):
            a, b, k = i
            return Image.blend(self._load("take1b", self.m1, a), self._load("take1b", self.m1, b), k)
        return self._load("take1b", self.m1, i)

    def take5b(self) -> Image.Image:
        return self._load("take5b", self.m5, 0, masked=True)

    def photo(self, key: str) -> Image.Image:
        """One of A1's pictures, decoded by `reel_photo.prepare`."""
        if key not in self.photos:
            self.photos[key] = reel_photo.load(self.work, key)
        return self.photos[key]


def prepare(assets: Path, work: Path) -> dict:
    """Conform the takes into `work` and record the drag. Returns facts for
    the build record."""
    p = take_paths(assets)
    for k in ("take1b", "take5b", "film"):
        if not p[k].exists():
            plan.die(f"missing {p[k]} — --assets is the main checkout's build/app-store/pro")
    m1 = conform(p["take1b"], TAKE1B_SEGMENTS, work / "take1b")
    faults = check_take_map(m1)
    if faults:
        plan.die("take1b's ranges: " + "; ".join(faults))
    m5 = conform(p["take5b"], [("hold", plan.S5["take_s"])], work / "take5b")
    if m5["sources"][str(m5["film"][0])]["pts"] > plan.S5["take_s"]:
        plan.die("take5b's held picture is later than 30.000 s")
    for m, name in ((m1, "take1b"), (m5, "take5b")):
        if (m["width"], m["height"]) != tuple(plan.ANSWER["capture"]):
            plan.die(f"{name} is {m['width']}x{m['height']}, the card is drawn for {plan.ANSWER['capture']}")
    drag = app_store_drag(p["film"], p["take1b"])
    (work / "drag.json").write_text(json.dumps(drag.__dict__), encoding="utf-8")
    return {"take1b": {"sha256": sha256(p["take1b"]), "pictures": len(m1["sources"])},
            "take5b": {"sha256": sha256(p["take5b"]),
                       "picture_pts": m5["sources"][str(m5["film"][0])]["pts"]}}
