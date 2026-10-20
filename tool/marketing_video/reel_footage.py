"""The real app in the card: the takes, conformed, masked, framed.
Design: docs/design/pro-marketing-reel.md §3 and §5.

  takes      take1b (S3, S7) and take5b (S5), the production recordings of
             2026-10-14, read from the main checkout's build/ folder (never
             copied into git). Each kept range is exported by the App
             Preview's own `conform export` (tool/app_store_preview/swift/
             Conform.swift): film frame n shows the last picture the take
             presented at or before its instant — frame-hold, never a blend,
             never a change of speed. The one blend is S7's declared
             dissolve, between two held pictures; and one held frame stands
             in for S7's black-button picture before the push (R3: a
             declared `skip`). take5b (A2, R3): every picture of its one
             drag is exported, and S5 shows the page at rest on its top,
             the drag chosen BY SCROLL POSITION (R3's declared departure
             from 1:1), the page at rest after.
  the scroll take5b's drag was recorded at the simulator's own cadence:
             about 44 distinct positions a second, 43 of its 145 pictures
             repeating the position before, so a 30-fps frame-hold steps
             4 or 8 pt — a judder — after a 4-pt touch-slop jump. R3 takes
             for each film frame the picture whose scroll is nearest a
             smooth target s*(t), the gesture's own cosine eased in from
             rest (its length fitted to the take's scroll map), and moves
             it by the sub-pixel remainder in capture space, before the
             camera transform. The page's
             cover is anchored to its bar and scrolls with the content (no
             parallax), so within the card's window that shift is the page's
             own motion; the cover's fade (84–168 pt of scroll) is off by at
             most the remainder's 1.9 pt of 84.
  the mask   take5b's salon phone row is painted (255, 255, 255) in capture
             space, before any scaling or camera move, so it is hidden on
             every frame by construction — on the rest picture at the
             storyboard's rectangle, and on each picture of the drag at that
             rectangle moved by the picture's scroll (the take's own map,
             phone_rect_per_frame.csv) and cut at the opaque bottom bar.
             Each rectangle must hold the rest picture's row, pixel for
             pixel, and sit on pure white all round, or the build stops. It
             is painted before the sub-pixel shift, so it moves with the
             picture.
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

import csv
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
            "scroll5b": v2 / "takes/take5b/phone_rect_per_frame.csv", "film": v2 / "final/film.json"}


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


# ---- which picture of which take each film frame shows ----------------------------------

# take1b, exported once: the S3 ranges, then the S7 ranges. (kind, ticks, …)
# R2: S7's first live range ends where the take stops changing (32.765 s,
# the unfilled form at rest), not at 33.032 s.
# R3: S7's « Créer » range is cut around one film frame. The take shows the
# loading button (f689), then for one picture the black « Créer le rendez-
# vous » again (130.985 s), then the push: a 33-ms black flash. A `skip`
# holds the picture the range before it ends on for that one frame, and the
# next range resumes 1:1 at the following instant.
TAKE1B_SEGMENTS = [
    ("hold", 6397), ("live", 6397, 6977), ("hold", 6957),            # S3: rest, the swipe, the open pane
    ("hold", 19299), ("live", 19299, 19679), ("hold", 19659),        # S7: rest, « Libre » → « Réservation »
    ("hold", 78157), ("live", 78157, 78597), ("skip", 78577),        # S7: the filled form → « Créer » → loading
    ("live", 78617, 79317), ("hold", 79297),                         # S7: the form closes → the day
]


def segments_json(segments: list[tuple]) -> dict:
    out = []
    for s in segments:
        if s[0] in ("hold", "skip"):
            out.append({"kind": "hold", "src_at": s[1], "frames": 1})
        else:
            out.append({"kind": "live", "src_in": s[1], "src_out": s[2]})
    return {"fps": 30, "segments": out}


def segment_starts(segments: list[tuple]) -> list[int]:
    """Where each segment starts in the exported list."""
    starts, k = [], 0
    for s in segments:
        starts.append(k)
        k += 1 if s[0] in ("hold", "skip") else (s[2] - s[1]) // FILM_TICKS
    return starts + [k]


# S7's runs (plan.S7["runs"]), each with the take1b segment it shows; the
# declared dissolve blends the holds on either side of it
S7_SEGMENT = {0: 3, 1: 4, 2: 5, 4: 6, 5: 7, 6: 8, 7: 9, 8: 10}


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
    for r, run in enumerate(plan.S7["runs"]):
        kind, a, b, what = run[:4]
        if a <= n <= b:
            if kind == "dissolve":
                # on its token: frame a-1 is the clean last picture of A; the
                # run ends on B whole (k = 1)
                k = plan.tokens()[run[4]].at((n - (a - 1)) / 30)
                return (st[S7_SEGMENT[r - 1]], st[S7_SEGMENT[r + 1]], k)
            i = S7_SEGMENT[r]
            seg = TAKE1B_SEGMENTS[i]
            if seg[0] != kind or seg[1] != what or (kind == "live" and b - a + 1 != (seg[2] - seg[1]) // FILM_TICKS):
                plan.die(f"S7's run {run[:4]} is not take1b's segment {seg}")
            return st[i] + (n - a if kind == "live" else 0)
    plan.die(f"film frame {n} shows no picture of take1b")


# take5b (A2, R3): every picture the take presents in its drag's window, at
# the take's own rate (one exported entry a tick): entry 0 is the picture
# held at the window's start (the top of the page at rest), entry
# hold_after - src_in the picture held at the rest after the drag.
def take5b_export() -> dict:
    _, a, b = plan.S5["live"]
    return {"fps": TAKE_TIMESCALE, "segments": [{"kind": "live", "src_in": a, "src_out": b}]}


S5_LIVE_FIRST = plan.S5["live"][0]
S5_LIVE_LAST = S5_LIVE_FIRST + math.ceil(plan.S5["scroll_s"] * 30 - 1e-9) - 1   # the last frame short of the rest


def s5_target_px(n: int) -> float:
    """S5's smooth target at film frame n (R3), in capture px from the top
    of the page at rest: rise x (1 - cos pi u) / 2, u = (t - t0) / scroll_s,
    eased in from rest at the live range's first frame."""
    u = min(1.0, max(0.0, (n - S5_LIVE_FIRST) / 30 / plan.S5["scroll_s"]))
    return plan.S5["rise_px"] * (1 - math.cos(math.pi * u)) / 2


def s5_phase(n: int) -> str:
    """« before » the drag (the top of the page), « live », or « after » (at rest)."""
    if n < S5_LIVE_FIRST:
        return "before"
    return "live" if n <= S5_LIVE_LAST else "after"


def take5b_holds(manifest: dict) -> tuple[int, int]:
    """The pictures the two holds show: held at the window's start, and at
    the rest after the drag."""
    _, a, _ = plan.S5["live"]
    film = manifest["film"]
    return film[0], film[plan.S5["hold_after"] - a]


def fit_scroll_s(samples: list[tuple[float, float]]) -> float:
    """The length (s) of the cosine s(t) = rise x (1 - cos pi u) / 2,
    u = (t - t0) / D, that fits the drag's samples (seconds, px) best in
    least squares, t0 the window's start (the rest). 0.1-ms grid."""
    t0 = plan.S5["live"][1] / TAKE_TIMESCALE
    rise = plan.S5["rise_px"]
    t = np.array([s[0] for s in samples], np.float64)
    y = np.array([s[1] for s in samples], np.float64)
    D = np.arange(1.0, 3.5, 1e-4)[:, None]
    u = np.clip((t[None, :] - t0) / D, 0, 1)
    err = ((rise * (1 - np.cos(np.pi * u)) / 2 - y[None, :]) ** 2).sum(axis=1)
    return float(D[int(np.argmin(err)), 0])


def take5b_choice(pos: dict[int, int], order: list[int], j_before: int, j_after: int) -> list[dict]:
    """For each frame of S5's live range, the picture whose scroll is
    nearest the target (one picture per distinct position: the first the
    take presents at it, the holds' own at the two rests) and the
    remainder (capture px) it is moved by: target = pos + shift."""
    cand: dict[int, int] = {}
    for j in order:
        cand.setdefault(pos[j], j)
    cand[pos[j_before]] = j_before
    cand[pos[j_after]] = j_after
    keys = sorted(cand)
    out = []
    for n in range(S5_LIVE_FIRST, S5_LIVE_LAST + 1):
        target = s5_target_px(n)
        p = min(keys, key=lambda q: (abs(q - target), q))
        out.append({"n": n, "j": cand[p], "pos": p, "target": target, "shift": target - p})
    return out


def check_take5b(manifest: dict, survey: dict, choice: list[dict]) -> list[str]:
    """take5b's export and S5's choice by scroll position, against the take:
    every picture of the window exported; the holds the pictures held at
    their instants; the scroll never going back in the take; each live
    frame the picture nearest the plan's target, moved by exactly the
    remainder, never back from the frame before. Returns the faults."""
    faults = []
    src = {int(k): v for k, v in manifest["sources"].items()}
    _, a, b = plan.S5["live"]
    idx = sorted(src)
    if idx != list(range(idx[0], idx[-1] + 1)):
        faults.append("take5b: a picture of the drag's window is missing from the export")
    film = manifest["film"]
    if len(film) != b - a:
        faults.append(f"take5b: {len(film)} exported entries, the window is {b - a} ticks")
        return faults
    for k in (0, plan.S5["hold_after"] - a):
        later = [j for j in idx if src[j]["pts"] <= a + k]
        if not later or film[k] != max(later):
            faults.append(f"take5b: the hold at {a + k} ticks is not the picture the take shows then")
    j_before, j_after = take5b_holds(manifest)
    pos = {int(k): v["pos"] for k, v in survey.items()}
    if set(pos) != set(idx):
        faults.append("take5b: the survey does not cover every exported picture")
        return faults
    if any(pos[y] < pos[x] for x, y in zip(idx, idx[1:])):
        faults.append("take5b: the scroll goes back in the take")
    if pos[j_before] != 0 or pos[j_after] != plan.S5["rise_px"]:
        faults.append(f"take5b: the page rises {pos[j_after] - pos[j_before]} px, the plan says {plan.S5['rise_px']}")
    frames = [c["n"] for c in choice]
    if frames != list(range(S5_LIVE_FIRST, S5_LIVE_LAST + 1)):
        faults.append(f"take5b: the choice covers frames {frames[:1]}…{frames[-1:]}, the live range is "
                      f"{S5_LIVE_FIRST}–{S5_LIVE_LAST}")
        return faults
    if choice[0]["j"] != j_before or abs(choice[0]["shift"]) > 1e-9:
        faults.append("take5b: the live range does not start on the picture the hold shows")
    positions = sorted(set(pos.values()))
    last = None
    for c in choice:
        target = s5_target_px(c["n"])
        if c["j"] not in pos or c["pos"] != pos[c["j"]]:
            faults.append(f"take5b: frame {c['n']} shows a picture at another scroll than the survey's")
            break
        if abs(c["target"] - target) > 1e-6 or abs(c["pos"] + c["shift"] - target) > 1e-6:
            faults.append(f"take5b: frame {c['n']} is not moved to the plan's target ({target:.2f} px)")
            break
        if min(abs(q - target) for q in positions) < abs(c["pos"] - target) - 1e-9:
            faults.append(f"take5b: frame {c['n']} does not show the picture nearest its target")
            break
        if last is not None and c["pos"] < last:
            faults.append(f"take5b: frame {c['n']} goes back in the scroll")
            break
        last = c["pos"]
    return faults


def check_take_map(manifest: dict, segments: list[tuple] = TAKE1B_SEGMENTS) -> list[str]:
    """Each LIVE and HOLD range against the take's own map: a hold before a
    live range shows the picture the range starts on, the hold after it the
    picture it ends on, a live range never goes back, and every picture is
    the last one presented at or before its instant. Returns the faults."""
    film = manifest["film"]
    pts = {int(k): v["pts"] for k, v in manifest["sources"].items()}
    faults = []
    st = segment_starts(segments)
    if len(film) != st[-1]:
        faults.append(f"{len(film)} exported pictures, the plan needs {st[-1]}")
        return faults
    for i, s in enumerate(segments):
        a = st[i]
        if s[0] == "skip":
            # one film frame held on the picture the live range before it
            # ends on, the live range after it resuming at the next instant
            before = segments[i - 1] if i > 0 else None
            after = segments[i + 1] if i + 1 < len(segments) else None
            if not before or before[0] != "live" or not after or after[0] != "live":
                faults.append(f"the skip at {s[1]} ticks is not between two live ranges")
                continue
            if s[1] != before[2] - FILM_TICKS or after[1] != before[2] + FILM_TICKS:
                faults.append(f"the skip at {s[1]} ticks stands for more or less than one film frame "
                              f"({before[1]}–{before[2]}, then {after[1]}–{after[2]})")
            if film[a] != film[a - 1]:
                faults.append(f"the skip at {s[1]} ticks is not the picture the range before it ends on")
            if film[a + 1] <= film[a]:
                faults.append(f"the range after the skip at {s[1]} ticks does not move on in the take")
            continue
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
            if i > 0 and segments[i - 1][0] == "hold" and film[a - 1] != run[0]:
                faults.append(f"the hold before {s[1]}–{s[2]} is not the picture the range starts on")
            if i + 1 < len(segments) and segments[i + 1][0] == "hold" and film[st[i + 1]] != run[-1]:
                faults.append(f"the hold after {s[1]}–{s[2]} is not the picture the range ends on")
    return faults


def conform(take: Path, segments: list[tuple] | dict, out: Path) -> dict:
    """`segments`: the Reel's (kind, ticks, …) at 30 fps, or a Conform spec."""
    out.mkdir(parents=True, exist_ok=True)
    seg = out / "segments.json"
    spec = segments if isinstance(segments, dict) else segments_json(segments)
    seg.write_text(json.dumps(spec, indent=1), encoding="utf-8")
    swifttools.run("conform", "export", take, "--segments", seg, "--out", out)
    return json.loads((out / "manifest.json").read_text(encoding="utf-8"))


# ---- the mask ---------------------------------------------------------------------------

def check_rest_mask(im: Image.Image) -> None:
    """The storyboard's rectangle on the rest picture — refused unless it
    holds the row's ink and is ringed by pure white."""
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


ROW_MATCH = 100          # the row, found again: no pixel more than this off the rest picture's
ROW_MISS = 150           # a rectangle 1–3 px off: some pixel at least this far (the row is found to the pixel)
BAR_SAME = 48            # the bar, opaque: never more than the encoder's noise off the rest picture's
BAND_ROWS = 120          # the page just above the bar, against the rest picture moved by the scroll
BAND_MEAN = 3.0          # … within this mean difference (the map's labels move a little), best within 1 px


def scroll_map(csv_path: Path) -> list[tuple[float, float]]:
    """take5b's own map of its scroll, (seconds, points), measured per picture."""
    rows = list(csv.DictReader(csv_path.read_text(encoding="utf-8").splitlines()))
    return [(float(r["seconds"]), float(r["scroll_pt"])) for r in rows]


def take5b_survey(manifest: dict, folder: Path, scroll: list[tuple[float, float]],
                  rest: int | None = None) -> dict[int, dict]:
    """Each exported picture of take5b, once: where its page is and the
    rectangle to paint on it. `rest`: the picture at rest after the drag
    (the list's last by default).

    The scroll: the map's value, checked on the picture — the page just
    above the bar must be the rest picture's moved by that scroll, best
    within 1 px — and taken to the capture pixel where the picture puts it
    (`pos`, capture px, 0 on the first picture of the list). The
    rectangle: the storyboard's on the rest picture, moved by the
    picture's scroll and cut at the bar — None where the row is under the
    opaque bar. Every rectangle that shows any of the row must hold the
    rest picture's row pixel for pixel (and no rectangle 1–3 px off may),
    and be ringed by white; under the bar, the bar must be the rest
    picture's. The map itself is checked, not only trusted."""
    x, y, w, h = plan.S5["mask"]
    bar = plan.S5["bar_top"]

    def grey(j: int) -> np.ndarray:
        return np.asarray(Image.open(folder / manifest["sources"][str(j)]["file"]).convert("L"), dtype=np.int16)

    def scroll_at(j: int) -> float:
        t = manifest["sources"][str(j)]["pts"] / TAKE_TIMESCALE
        seconds, s = min(scroll, key=lambda r: abs(r[0] - t))
        if abs(seconds - t) > 0.002:
            plan.die(f"take5b's scroll map has no picture at {t:.3f} s (nearest {seconds:.3f} s)")
        return s

    film = manifest["film"]
    j_rest = film[-1] if rest is None else rest
    rest_px = grey(j_rest)
    check_rest_mask(Image.fromarray(rest_px.astype(np.uint8), "L"))
    s_rest = scroll_at(j_rest)
    out: dict[int, dict] = {}
    for j in dict.fromkeys(film):                              # each picture once, in the list's order
        a = grey(j)
        off = round((s_rest - scroll_at(j)) * 3)               # 3 capture px a point
        # the map itself, checked on every picture: the page just above the
        # bar is the rest picture's moved by `off` (best within 1 px)
        band = a[bar - BAND_ROWS:bar, 60:a.shape[1] - 60]
        diff = {d: float(np.abs(band - rest_px[bar - BAND_ROWS - off - d:bar - off - d, 60:a.shape[1] - 60]).mean())
                for d in range(-3, 4)}
        near = min(diff[-1], diff[0], diff[1])
        if near > BAND_MEAN or near > min(diff.values()) + 1e-9:
            plan.die(f"take5b's picture {j}: its page is not where the scroll map ({scroll_at(j)} pt) puts it")
        off += min((-1, 0, 1), key=lambda d: (diff[d], abs(d)))   # where the picture puts it, to the pixel
        out[j] = {"off": off, "mask": None}
        y0 = y + off
        if y0 - 1 >= bar:
            if np.abs(a[bar:] - rest_px[bar:]).max() > BAR_SAME:
                plan.die(f"take5b's picture {j}: the bar is not the rest picture's — something shows through it")
            continue
        if y0 >= bar:
            plan.die(f"take5b's picture {j}: the phone row sits at the bar's edge — not decided to the pixel")
        y1 = min(y + h + off, bar)
        vis = y1 - y0
        tmpl = rest_px[y:y + vis, x:x + w]
        if tmpl.min() < 128:                                  # some of the row's ink is above the bar
            if np.abs(a[y0:y1, x:x + w] - tmpl).max() > ROW_MATCH:
                plan.die(f"take5b's picture {j}: the phone row is not where its scroll ({scroll_at(j)} pt) puts it")
            for d in (-3, -2, -1, 1, 2, 3):
                if y0 + d + vis <= bar and np.abs(a[y0 + d:y0 + d + vis, x:x + w] - tmpl).max() < ROW_MISS:
                    plan.die(f"take5b's picture {j}: the row matches {d} px off as well — not found to the pixel")
        ring = [a[y0 - 3:y0, x - 3:x + w + 3], a[y0:y1, x - 3:x], a[y0:y1, x + w:x + w + 3]]
        if y1 < bar:
            ring.append(a[y1:y1 + 3, x - 3:x + w + 3])
        darkest = min(int(r.min()) for r in ring)
        if darkest < 250:
            plan.die(f"take5b's picture {j}: the mask rectangle is not ringed by white (darkest {darkest})")
        out[j]["mask"] = [x, y0, w, vis]
    top = out[film[0]]["off"]
    for v in out.values():
        v["pos"] = top - v["off"]                              # how far the page has scrolled, capture px
    return out


def take5b_masks(manifest: dict, folder: Path, scroll: list[tuple[float, float]]) -> list[list[int] | None]:
    """The rectangle to paint on each picture of the export's list (see
    `take5b_survey`)."""
    survey = take5b_survey(manifest, folder, scroll)
    return [survey[j]["mask"] for j in manifest["film"]]


def mask_take5b(im: Image.Image, rect: list[int] | None) -> Image.Image:
    """The salon phone row, filled white in capture space."""
    if rect is None:
        return im
    x, y, w, h = rect
    out = im.copy()
    ImageDraw.Draw(out).rectangle((x, y, x + w - 1, y + h - 1), fill=plan.S5["mask_fill"])
    return out


def mask_box_in_frame(W: float, offset: float = 0.0, rect: list[int] | None = None,
                      shift: float = 0.0) -> tuple[float, float, float, float]:
    """Where S5's mask (`rect`, the rest picture's by default) lands in the
    frame at camera W, its picture moved up by `shift` capture px (R3)."""
    x, y, w, h = rect or plan.S5["mask"]
    k = plan.PX_PER_PT / 3                    # frame px per capture px
    top = card_top(W, offset)
    y0 = top + (y - shift - plan.ANSWER["card_top_pt"] * 3) * k
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
             touches: list[tuple[float, float, tuple, float]] = (), shift: float = 0.0) -> None:
        """`picture`: a padded capture. `offset`: how far below its resting
        place the card is (an entrance). `touches`: (x, y, colour, opacity)
        where the card rests, drawn on the card and clipped by it. `shift`:
        how far (capture px, sub-pixel) the picture's content is moved up
        inside the card — S5's remainder to its scroll target (R3).

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
            s0 = cap_top + (ca - top) / self.k + shift
            s1 = cap_top + (cb - top) / self.k + shift
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
        self.survey5 = {int(k): v for k, v in
                        json.loads((work / "take5b/survey.json").read_text(encoding="utf-8")).items()}
        self.choice5 = {c["n"]: c for c in json.loads((work / "take5b/choice.json").read_text(encoding="utf-8"))}
        self.holds5 = take5b_holds(self.m5)
        self.drag = Drag(**json.loads((work / "drag.json").read_text(encoding="utf-8")))
        self._cache: dict[str, Image.Image] = {}

    def _load(self, folder: str, name: str, rect: list[int] | None = None) -> Image.Image:
        key = f"{folder}/{name}/{rect}"
        if key not in self._cache:
            im = Image.open(self.work / folder / name).convert("RGB")
            if folder == "take5b":
                im = mask_take5b(im, rect)
            self._cache[key] = padded(im)
        return self._cache[key]

    def take1b(self, n: int) -> Image.Image:
        def load(i: int) -> Image.Image:
            return self._load("take1b", self.m1["sources"][str(self.m1["film"][i])]["file"])
        i = take1b_index(n)
        if isinstance(i, tuple):
            a, b, k = i
            return Image.blend(load(a), load(b), k)
        return load(i)

    def take5b_at(self, n: int) -> tuple[int, float]:
        """The take5b picture (its take index) film frame n shows, and the
        capture px it is moved up by: the top of the page, the drag by
        scroll position (R3), the page at rest."""
        phase = s5_phase(n)
        if phase == "live":
            c = self.choice5[n]
            return c["j"], c["shift"]
        return (self.holds5[0] if phase == "before" else self.holds5[1]), 0.0

    def scroll5(self, n: int) -> float:
        """How far (capture px) the page film frame n shows has scrolled."""
        j, shift = self.take5b_at(n)
        return self.survey5[j]["pos"] + shift

    def mask5(self, n: int) -> tuple[list[int] | None, float]:
        """The capture-space rectangle painted on the take5b picture film
        frame n shows (None: the row is under the bar), and its shift."""
        j, shift = self.take5b_at(n)
        return self.survey5[j]["mask"], shift

    def take5b(self, n: int) -> Image.Image:
        j, _ = self.take5b_at(n)
        return self._load("take5b", self.m5["sources"][str(j)]["file"], self.survey5[j]["mask"])

    def photo(self, key: str) -> Image.Image:
        """One of A1's pictures, decoded by `reel_photo.prepare`."""
        if key not in self.photos:
            self.photos[key] = reel_photo.load(self.work, key)
        return self.photos[key]


def prepare(assets: Path, work: Path) -> dict:
    """Conform the takes into `work`, choose S5's pictures by scroll
    position and record the drag. Returns facts for the build record."""
    p = take_paths(assets)
    for k in ("take1b", "take5b", "scroll5b", "film"):
        if not p[k].exists():
            plan.die(f"missing {p[k]} — --assets is the main checkout's build/app-store/pro")
    m1 = conform(p["take1b"], TAKE1B_SEGMENTS, work / "take1b")
    faults = check_take_map(m1)
    if faults:
        plan.die("take1b's ranges: " + "; ".join(faults))
    m5 = conform(p["take5b"], take5b_export(), work / "take5b")
    j_before, j_after = take5b_holds(m5)
    order = sorted(int(k) for k in m5["sources"])             # the take's own order
    # every picture once, from the top of the page (pos 0) to the rest after the drag
    survey = take5b_survey({"film": [j_before] + [j for j in order if j != j_before], "sources": m5["sources"]},
                           work / "take5b", scroll_map(p["scroll5b"]), rest=j_after)
    # the target's length, fitted to the drag's distinct positions (R3)
    seen, samples = set(), []
    for j in order:
        pts = m5["sources"][str(j)]["pts"]
        if pts >= plan.S5["live"][1] and survey[j]["pos"] not in seen:
            seen.add(survey[j]["pos"])
            samples.append((pts / TAKE_TIMESCALE, survey[j]["pos"]))
    fitted = fit_scroll_s(samples)
    if round(fitted, 3) != plan.S5["scroll_s"]:
        plan.die(f"take5b's scroll fits a {fitted:.4f}-s cosine, the plan says {plan.S5['scroll_s']} s")
    choice = take5b_choice({j: v["pos"] for j, v in survey.items()}, order, j_before, j_after)
    faults = check_take5b(m5, survey, choice)
    if faults:
        plan.die("take5b: " + "; ".join(faults))
    (work / "take5b/survey.json").write_text(json.dumps({str(j): v for j, v in survey.items()}), encoding="utf-8")
    (work / "take5b/choice.json").write_text(json.dumps(choice), encoding="utf-8")
    for m, name in ((m1, "take1b"), (m5, "take5b")):
        if (m["width"], m["height"]) != tuple(plan.ANSWER["capture"]):
            plan.die(f"{name} is {m['width']}x{m['height']}, the card is drawn for {plan.ANSWER['capture']}")
    drag = app_store_drag(p["film"], p["take1b"])
    (work / "drag.json").write_text(json.dumps(drag.__dict__), encoding="utf-8")
    shown = {c["j"] for c in choice} | {j_before, j_after}
    return {"take1b": {"sha256": sha256(p["take1b"]), "pictures": len(m1["sources"])},
            "take5b": {"sha256": sha256(p["take5b"]), "pictures": len(m5["sources"]),
                       "scroll_map_sha256": sha256(p["scroll5b"]),
                       "distinct_positions": len({v["pos"] for v in survey.values()}),
                       "scroll_fit_s": round(fitted, 4),
                       "pictures_shown": len(shown),
                       "largest_shift_px": round(max(abs(c["shift"]) for c in choice), 2),
                       "masked_pictures": sum(1 for v in survey.values() if v["mask"] is not None)}}
