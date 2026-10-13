"""The edit list — which parts of a raw take the film shows, and when.

The film is real captured footage (App Review 2.3.4). The simulator is driven
one gesture at a time, with seconds between gestures, so the take is mostly
waiting. This module removes the waiting and nothing else:

  * From a touch-down to the last change on screen before the next touch-down,
    the take plays once, in order, at its own speed. No cut, no hold, no
    change of speed inside that window. Time the app spends waiting on ITSELF
    (a loader, a snackbar that leaves after four seconds) is inside the window
    and stays.
  * Only the still stretch that ends at a touch-down — the app waiting for the
    finger — may be shortened, or lengthened by holding its picture. A typed
    key is a touch-down like any other.
  * A cut may only jump between two pictures that are the same picture.
  * A text caret blinking, alone, is nothing changing.

`propose` builds an edit list that obeys this from the scan of the take
(conform scan), the gesture log and the storyboard. `check` re-derives the
windows from the same data and refuses an edit list that breaks any of it —
whoever wrote it. Times in the take are integer ticks of its own timescale;
times in the film are whole frames.
"""

from __future__ import annotations

import bisect
import math
from dataclasses import dataclass, field

# ---- what counts as a change -------------------------------------------------
#
# conform scan gives, for every frame against the one before it, `soft` (pixels
# that moved by more than 16 levels), `strong` (more than 64) and the box that
# holds the strong ones. The recording is lossy: on the probe clip of
# 2026-10-13 a screen that did not change still produced frames with up to 500
# soft and 1 strong pixel (the encoder refining text edges), while the smallest
# real change — the refresh spinner's first dot — was 5 strong pixels. So:
STRONG_MIN = 4      # this many strong pixels, or
SOFT_MIN = 2000     # this many soft ones, is a change.
# A text caret blinking is treated as nothing changing (README, « The editing
# rule »). What a caret is was read on the rehearsal take of 2026-10-13, the
# app's own: 2 points wide, 23 to 26 tall, and it FADES in and out. Most of
# its frames stay under the thresholds above; the ones that pass them show
# the whole caret, or a fragment of it (its last row of pixels, 1 x 1 point),
# always at the same place. So a caret is told by where it is, not only by
# its size:
#   * it is no bigger than CARET_MAX_PT — a typed « . » moves the caret and
#     changes a box 5 points wide: a change;
#   * it is first seen, at least CARET_MIN_HEIGHT_PT tall, INSIDE the last
#     burst of changes — the field that took focus, the character just typed,
#     the form that scrolled. A caret-shaped box anywhere else is the caret
#     arriving somewhere new (a typed space moves nothing else): a change;
#   * from then on, whatever stays within that one column is the caret —
#     fragments included — until the next change.
# The minimum height keeps small real changes out: on the probe clip the
# refresh spinner's arrow grew by boxes 5 x 1 to 17 x 15 pixels inside the
# list that had just moved; none is 10 points tall and none blinks in place.
CARET_MAX_PT = (3.0, 34.0)
CARET_MIN_HEIGHT_PT = 10.0
CARET_SLACK_PT = 1.0

# Flutter starts a drag once the finger has travelled this far (kTouchSlop,
# flutter/lib/src/gestures/constants.dart): the first frame that moves is that
# late after the touch-down.
DRAG_SLOP_PT = 18.0


class Refusal(Exception):
    """An edit list, a gesture log or a take the tool will not work with."""

    def __init__(self, code: str, message: str):
        super().__init__(f"[{code}] {message}")
        self.code, self.message = code, message


Box = list  # [x0, y0, x1, y1] in pixels of the take, x1 and y1 excluded


def _union(a: Box, b: Box) -> Box:
    return [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3])]


def _caret_sized(box: Box, px_per_pt: float) -> bool:
    return ((box[2] - box[0]) / px_per_pt <= CARET_MAX_PT[0]
            and (box[3] - box[1]) / px_per_pt <= CARET_MAX_PT[1])


def _caret_shaped(box: Box, px_per_pt: float) -> bool:
    return _caret_sized(box, px_per_pt) and (box[3] - box[1]) / px_per_pt >= CARET_MIN_HEIGHT_PT


def _inside(box: Box, area: Box, px_per_pt: float) -> bool:
    slack = CARET_SLACK_PT * px_per_pt
    return (box[0] >= area[0] - slack and box[1] >= area[1] - slack
            and box[2] <= area[2] + slack and box[3] <= area[3] + slack)


def frame_kind(row: dict, px_per_pt: float, column: Box | None = None, area: Box | None = None) -> str:
    """`change`, `caret` or `quiet` for one scan row, or for the comparison of
    the two sides of a cut. `column` is where a caret is known to blink;
    `area` is where one may first be seen (the box of the last burst of
    changes). Without either, nothing is a caret."""
    soft, strong = row.get("soft", 0), row.get("strong", 0)
    if strong < STRONG_MIN and soft < SOFT_MIN:
        return "quiet"
    box = row.get("box")
    if box and soft < SOFT_MIN and _caret_sized(box, px_per_pt):
        if column is not None:
            if _caret_sized(_union(column, box), px_per_pt):
                return "caret"
        elif area is not None and _caret_shaped(box, px_per_pt) and _inside(box, area, px_per_pt):
            return "caret"
    return "change"


@dataclass
class Reading:
    """Every frame of a take, told apart. A « stretch » runs from one change
    to the frame before the next: the screen is still, a caret may blink."""
    kinds: list[str]
    columns: list[Box | None]   # per frame: the column the caret blinks in during its stretch
    areas: list[Box | None]     # per frame: the box of the burst of changes its stretch follows


def read_frames(scan: dict, px_per_pt: float, rest_ticks: int) -> Reading:
    frames = scan["frames"]
    kinds: list[str] = ["quiet"] * len(frames)
    whole = [0, 0, scan["video"]["width"], scan["video"]["height"]]
    column: Box | None = None    # where the caret blinks in this stretch, once it has been seen
    area: Box | None = None      # where it may first be seen: the box of the last burst of changes
    burst: Box | None = None     # the box of the burst of changes this stretch follows
    since, last_change = 0, 0    # the change that began this stretch: its frame, its time
    found: dict[int, Box] = {}   # stretch (by the frame that began it) -> its column
    after: dict[int, Box | None] = {}

    def caret_sized(f: dict) -> bool:
        return bool(f.get("box")) and f.get("soft", 0) < SOFT_MIN and _caret_sized(f["box"], px_per_pt)

    def ahead(i: int) -> Box | None:
        """The caret this stretch is going to show, if it shows one: the
        first caret-shaped box inside `area` before anything bigger changes.
        A fragment seen before it is the same caret, a moment earlier."""
        for f in frames[i:]:
            if frame_kind(f, px_per_pt) == "quiet":
                continue
            if not caret_sized(f):
                return None
            if _caret_shaped(f["box"], px_per_pt) and _inside(f["box"], area, px_per_pt):
                return f["box"]
        return None

    for i, f in enumerate(frames):
        if i == 0:
            # The take's first picture counts as a change: it is the first
            # thing the recorder wrote, and there is nothing before it to
            # measure it by.
            kinds[0], last_change = "change", f["pts"]
            after[0] = None
            continue
        if frame_kind(f, px_per_pt) == "quiet":
            continue
        if column is None and area is not None and caret_sized(f):
            column = ahead(i)
        if column is not None and frame_kind(f, px_per_pt, column) == "caret":
            kinds[i] = "caret"
            # seen: from here to the next change, a caret-shaped box anywhere
            # else is a caret that moved — a change — whatever `area` says
            column = found[since] = _union(column, f["box"])
            continue
        kinds[i] = "change"
        box = f.get("box") or whole    # a faint, wide change has no box: it may be anywhere
        joins = burst is not None and f["pts"] - last_change < rest_ticks
        burst = _union(burst, box) if joins else box
        column, area = None, burst
        since, last_change = i, f["pts"]
        after[i] = burst

    columns: list[Box | None] = []
    areas: list[Box | None] = []
    stretch = 0
    for i, kind in enumerate(kinds):
        if kind == "change":
            stretch = i
        columns.append(found.get(stretch))
        areas.append(after[stretch])
    return Reading(kinds, columns, areas)


def frame_kinds(scan: dict, px_per_pt: float, rest_ticks: int) -> list[str]:
    return read_frames(scan, px_per_pt, rest_ticks).kinds


@dataclass
class Burst:
    """Changes that follow one another with less than `rest` between them."""
    index: int
    first: int            # frame number of the first change
    last: int
    start: int            # ticks
    end: int
    frames: int
    box: list[int] | None  # union of the strong boxes


def find_bursts(scan: dict, kinds: list[str], rest_ticks: int) -> list[Burst]:
    out: list[Burst] = []
    for f, kind in zip(scan["frames"], kinds):
        if kind != "change":
            continue
        box = f.get("box")
        if out and f["pts"] - out[-1].end < rest_ticks:
            b = out[-1]
            b.last, b.end, b.frames = f["i"], f["pts"], b.frames + 1
            if box:
                b.box = box if b.box is None else [
                    min(b.box[0], box[0]), min(b.box[1], box[1]),
                    max(b.box[2], box[2]), max(b.box[3], box[3])]
        else:
            out.append(Burst(len(out), f["i"], f["i"], f["pts"], f["pts"], 1,
                             list(box) if box else None))
    return out


def held(pts: list[int], instant: int) -> int | None:
    """Frame-hold: the last frame presented at or before `instant`."""
    j = bisect.bisect_right(pts, instant) - 1
    return j if j >= 0 else None


# ---- the storyboard, in frames ----------------------------------------------

def whole_frames(seconds: float, fps: int, what: str) -> int:
    n = seconds * fps
    if abs(n - round(n)) > 1e-6 or n < 0:
        raise Refusal("E_STORYBOARD", f"{what} = {seconds} s is not a whole number of frames at {fps} fps")
    return round(n)


def catalogue(sb: dict) -> list[tuple[dict, dict]]:
    """(shot, gesture) for every gesture the storyboard names, in order."""
    return [(shot, g) for shot in sb["shots"] for g in shot.get("gestures", [])]


VARIANT_KEYS = {"film", "timing", "shots"}


def storyboard(doc: dict, variant: str | None = None) -> dict:
    """The storyboard a build works from: the film's own, or one of the file's
    `variants` laid over it. A variant is a rehearsal — other gestures on the
    same frame, with the same captions and the same rules — and is never the
    film: the result carries its name, and everything made from it says so.
    A variant may give `shots` (taken whole), and values of `film` and
    `timing` (laid over the film's); it cannot touch the words, the motion or
    the touch point."""
    sb = {k: v for k, v in doc.items() if k != "variants"}
    if variant is None:
        return sb
    variants = doc.get("variants") or {}
    if variant not in variants:
        raise Refusal("E_STORYBOARD", f"the storyboard has no variant `{variant}` "
                                      f"(it has: {', '.join(sorted(variants)) or 'none'})")
    over = {k: v for k, v in variants[variant].items() if not k.startswith("_")}
    if not set(over) <= VARIANT_KEYS:
        raise Refusal("E_STORYBOARD", f"variant `{variant}` may only give {', '.join(sorted(VARIANT_KEYS))} — "
                                      f"it gives {', '.join(sorted(set(over) - VARIANT_KEYS))}")
    for key in ("film", "timing"):
        sb[key] = {**doc[key], **over.get(key, {})}
    if "shots" in over:
        sb["shots"] = over["shots"]
    sb["variant"] = variant
    return sb


# ---- finding each gesture in the take ---------------------------------------

@dataclass
class Located:
    id: str                # the storyboard's gesture id; a typed key is `id[n]`
    gesture: str           # the storyboard's gesture id
    shot: str
    kind: str
    burst: int
    first_change: int      # ticks: the first frame the app changes
    down: int              # ticks: the touch-down
    last_change: int       # ticks: the last change before the next touch-down
    burst_end: int         # ticks: the end of the burst the touch started
    path: list[list[float]] = field(default_factory=list)  # [ticks, x pt, y pt]
    up: int = 0            # ticks: the finger leaves
    distance_pt: float | None = None  # touch point to the first change's box
    step: list[int] | None = None     # ticks: between these the path holds from one point to the next
    how: str = ""          # how the touch point was timed, for the log
    last: bool = True      # the last piece of its storyboard gesture (a typed key is one of several)


@dataclass
class TakeMap:
    timescale: int
    px_per_pt: float
    pts: list[int]
    kinds: list[str]
    changes: list[int]     # ticks of every change frame
    bursts: list[Burst]
    gestures: list[Located]
    reading: Reading | None = None


def _slop_time_ms(path: list[list[float]]) -> float:
    """When, along a logged drag, the finger is DRAG_SLOP_PT from its start."""
    x0, y0, t0 = path[0]
    for (xa, ya, ta), (xb, yb, tb) in zip(path, path[1:]):
        da, db = math.hypot(xa - x0, ya - y0), math.hypot(xb - x0, yb - y0)
        if db >= DRAG_SLOP_PT > da:
            return ta + (tb - ta) * (DRAG_SLOP_PT - da) / (db - da) - t0
    raise Refusal("E_LOG", f"a drag never moves {DRAG_SLOP_PT:g} pt from where it starts: {path}")


def _box_distance_pt(box: list[int] | None, x: float, y: float, px_per_pt: float) -> float | None:
    if not box:
        return None
    px, py = x * px_per_pt, y * px_per_pt
    dx = max(box[0] - px, 0, px - box[2])
    dy = max(box[1] - py, 0, py - box[3])
    return math.hypot(dx, dy) / px_per_pt


# A drag's logged path says where the finger went; its times are the ones the
# driver ASKED for. On the rehearsal take of 2026-10-13 drags logged at 16 ms
# a sample were delivered at 25 to 29 ms a sample, and the first frame of one
# came late — while every frame showed the picture as far along as one of the
# logged samples. So a drag is timed by the picture (track.py measures how
# far the content under the finger has moved in each frame); the log's own
# times are only used before the picture starts to follow and after it stops.
FOLLOW_MIN_PT = 0.5        # the picture has begun to follow
FOLLOW_OVER_PT = 2.0       # further than the finger went: the picture moves on its own


def followed_path(path: list[list[float]], track: dict, T: int) -> dict | None:
    """A logged drag, re-timed by what the picture did. `path` is the log's
    [[x, y, ms], …]; `track` is track.py's reading: along which axis, and for
    each frame how far the content under the finger has moved. Returns the
    touch-down, the lift, the points [ticks, x, y] and the span in which
    every point is a frame of the take — or None when the picture gives
    nothing to go by."""
    axis = 0 if track.get("axis") == "x" else 1
    sign = track.get("sign", 1)
    dist = [sign * (p[axis] - path[0][axis]) for p in path]
    if any(b < a - 0.01 for a, b in zip(dist, dist[1:])):
        return None                       # the finger turns back: one axis cannot say where it is
    reach = max(dist)
    moving = [(pts, s) for pts, s in track.get("frames", []) if s >= FOLLOW_MIN_PT]
    if not moving:
        return None
    top = max(s for _, s in moving)
    seen: list[tuple[int, float]] = []
    for pts, s in moving:
        if s > reach + FOLLOW_OVER_PT or (seen and s < seen[-1][1]):
            break
        seen.append((pts, min(s, reach)))
        if s >= top:
            break
    if len(seen) < 2 or seen[-1][1] <= seen[0][1]:
        return None

    def when(s: float) -> float:
        """Logged time (ms) at which the finger is `s` along."""
        for (pa, da), (pb, db) in zip(zip(path, dist), zip(path[1:], dist[1:])):
            if db > da and da <= s <= db:
                return pa[2] + (pb[2] - pa[2]) * (s - da) / (db - da)
        return next(p[2] for p, d in zip(path, dist) if d >= reach - 1e-9)

    def where(ms: float) -> tuple[float, float]:
        for pa, pb in zip(path, path[1:]):
            if ms <= pb[2]:
                u = max(0.0, (ms - pa[2]) / (pb[2] - pa[2]))
                return pa[0] + (pb[0] - pa[0]) * u, pa[1] + (pb[1] - pa[1]) * u
        return path[-1][0], path[-1][1]

    first, last = when(seen[0][1]), when(seen[-1][1])
    tick = T / 1000
    # before the picture follows: the log's own times, counted back from the first frame that moved
    points: list[list[float]] = [[seen[0][0] - (first - p[2]) * tick, p[0], p[1]] for p in path if p[2] < first]
    # while it follows: one point a frame, where the log has the finger when it is that far along
    points += [[float(pts), *where(when(s))] for pts, s in seen]
    # after it stops (a pane fully open, a list at its end): the log's own times again
    turn = track.get("turn")
    for p in path:
        if p[2] <= last:
            continue
        t = seen[-1][0] + (p[2] - last) * tick
        if turn is not None and t > turn:
            # the picture has turned back: the finger has left by then, from where it was
            points.append([float(turn), *where(last + (turn - seen[-1][0]) / tick)])
            break
        points.append([t, p[0], p[1]])
    clean: list[list[float]] = []
    for p in points:
        if not clean or p[0] > clean[-1][0]:
            clean.append([round(p[0], 3), round(p[1], 3), round(p[2], 3)])
    return {"down": clean[0][0], "up": clean[-1][0], "points": clean,
            "step": [seen[0][0], seen[-1][0]], "frames": len(seen),
            "reach": (seen[0][1], seen[-1][1], reach)}


def _burst_for(g: dict, what: str, bursts: list[Burst], used: int, T: int, timing: dict) -> Burst:
    """The burst of changes a logged gesture started. The log says when in one
    of two ways: `near_s` (read off the take by a person: the burst that
    starts within the tolerance), or `after_s` and `before_s` (written by the
    driver: when it asked for the gesture and when the call came back — the
    first burst that starts in between)."""
    where = ", ".join(f"{b.start / T:.3f}" for b in bursts) or "none"
    if "after_s" in g:
        if "before_s" not in g or not g["after_s"] < g["before_s"]:
            raise Refusal("E_LOG", f"gesture `{what}`: `after_s` needs a later `before_s` — when the driver "
                                   f"asked for the gesture, and when its call came back")
        lo, hi = round(g["after_s"] * T), round(g["before_s"] * T)
        cands = [b for b in bursts if lo <= b.start <= hi and b.index > used]
        if not cands:
            raise Refusal("E_MATCH", f"gesture `{what}`: nothing starts changing between {g['after_s']} s and "
                                     f"{g['before_s']} s (changes start at: {where})")
        return cands[0]      # what follows it in the window is the app's answer going on
    if "near_s" not in g:
        raise Refusal("E_LOG", f"gesture `{what}` needs `near_s`: roughly when, in seconds of the take "
                               f"(or `after_s` and `before_s`)")
    near = round(g["near_s"] * T)
    tol = round(g.get("tolerance_s", timing["sync_tolerance_s"]) * T)
    cands = [b for b in bursts if abs(b.start - near) <= tol and b.index > used]
    if not cands:
        raise Refusal("E_MATCH", f"gesture `{what}`: nothing starts changing within ±{tol / T:g} s of "
                                 f"{g['near_s']} s (changes start at: {where})")
    if len(cands) > 1:
        raise Refusal("E_MATCH", f"gesture `{what}`: {len(cands)} changes start within ±{tol / T:g} s of "
                                 f"{g['near_s']} s ({', '.join(f'{b.start / T:.3f}' for b in cands)}) — "
                                 f"set `near_s` on the one meant and a smaller `tolerance_s`")
    return cands[0]


def locate(scan: dict, log: dict, sb: dict, rehearsal: bool = False, tracks: dict | None = None) -> TakeMap:
    """Where each logged gesture is in the take: its touch-down and how long
    the app goes on answering it. Found from the data; the log only says
    roughly when and exactly where. `tracks` is track.py's reading of each
    drag, when the pictures have been looked at."""
    v = scan["video"]
    T, fps = v["timescale"], sb["film"]["fps"]
    if T % fps:
        raise Refusal("E_TAKE", f"the take's timescale {T} is not a multiple of {fps}")
    points = log.get("device_points")
    if not (isinstance(points, list) and len(points) == 2):
        raise Refusal("E_LOG", "the gesture log needs `device_points`: [width, height] of the screen in points")
    px_per_pt = v["width"] / points[0]
    if abs(v["height"] / points[1] - px_per_pt) > 0.01:
        raise Refusal("E_LOG", f"the take is {v['width']}x{v['height']} px; that is not {points[0]}x{points[1]} points at one scale")

    timing = sb["timing"]
    rest = round(timing["rest_s"] * T)
    lead, tap_lead, tap_dwell = _touch_leads(sb, T)
    pts = [f["pts"] for f in scan["frames"]]
    reading = read_frames(scan, px_per_pt, rest)
    kinds = reading.kinds
    changes = [p for p, k in zip(pts, kinds) if k == "change"]
    bursts = find_bursts(scan, kinds, rest)

    cat = catalogue(sb)
    shot_of = {g["id"]: shot["id"] for shot, g in cat}
    kind_of = {g["id"]: g["kind"] for _, g in cat}
    order = [g["id"] for _, g in cat]
    logged = log.get("gestures", [])
    filmed = [g for g in logged if g.get("film", True)]
    tail = [g for g in logged if not g.get("film", True)]
    if logged[: len(filmed)] != filmed:
        raise Refusal("E_LOG", "a gesture marked `film: false` must come after every filmed gesture")
    if not filmed:
        raise Refusal("E_LOG", "the gesture log has no gesture to film")

    seen = [g.get("id") for g in filmed]
    for gid in seen:
        if gid not in shot_of:
            raise Refusal("E_LOG", f"gesture `{gid}` is not in the storyboard")
    if len(set(seen)) != len(seen):
        raise Refusal("E_LOG", "a gesture id appears twice in the log")
    if [i for i in order if i in seen] != seen:
        raise Refusal("E_LOG", f"the log's gestures are not in the storyboard's order: {seen}")
    if not rehearsal:
        missing = [g["id"] for _, g in cat if g["id"] not in seen and not g.get("optional")]
        if missing:
            raise Refusal("E_LOG", f"the take is missing storyboard gestures: {', '.join(missing)} "
                                   f"(a rehearsal may leave gestures out: --rehearsal)")

    out: list[Located] = []
    used = -1
    for g in filmed:
        gid = g["id"]
        kind = g.get("kind")
        if kind != kind_of[gid]:
            raise Refusal("E_LOG", f"gesture `{gid}` is a {kind_of[gid]} in the storyboard, a {kind} in the log")
        if kind not in ("tap", "drag", "type"):
            raise Refusal("E_LOG", f"gesture `{gid}`: unknown kind `{kind}`")
        # Typed text is one gesture in the storyboard and one key at a time on
        # the screen: each key is found on its own, and the wait before it —
        # a caret blinking, nothing else — may be cut like any other.
        keys = g.get("keys") if kind == "type" else None
        if keys is not None and not (isinstance(keys, list) and keys and all(isinstance(k, dict) for k in keys)):
            raise Refusal("E_LOG", f"typed text `{gid}`: `keys` is a list of when each key was pressed")
        pieces = keys if keys is not None else [g]
        for n, piece in enumerate(pieces, 1):
            pid = gid if len(pieces) == 1 else f"{gid}[{n}]"
            b = _burst_for(piece, pid, bursts, used, T, timing)
            used = b.index
            loc = Located(pid, gid, shot_of[gid], kind, b.index, b.start, b.start - lead, b.start, b.end,
                          last=n == len(pieces))
            first_box = scan["frames"][b.first].get("box")
            if kind == "tap":
                at = g.get("at")
                if not (isinstance(at, list) and len(at) == 2):
                    raise Refusal("E_LOG", f"tap `{gid}` needs `at`: [x, y] in points")
                loc.down = b.start - tap_lead
                loc.up = b.start + tap_dwell
                loc.path = [[loc.down, at[0], at[1]]]
                loc.distance_pt = _box_distance_pt(first_box, at[0], at[1], px_per_pt)
            elif kind == "drag":
                path = g.get("path")
                if not (isinstance(path, list) and len(path) >= 2 and all(len(p) == 3 for p in path)):
                    raise Refusal("E_LOG", f"drag `{gid}` needs `path`: [[x, y, ms since touch-down], …]")
                if any(pb[2] <= pa[2] for pa, pb in zip(path, path[1:])) or path[0][2] != 0:
                    raise Refusal("E_LOG", f"drag `{gid}`: path times start at 0 and increase")
                loc.distance_pt = _box_distance_pt(first_box, path[0][0], path[0][1], px_per_pt)
                track = (tracks or {}).get(gid)
                seen_path = followed_path(path, track, T) if track and "down_s" not in g else None
                if seen_path:
                    # the point is there, whole, by the time the picture moves
                    loc.down = min(math.floor(seen_path["down"]), b.start - lead)
                    loc.path = [p for p in seen_path["points"] if p[0] > loc.down]
                    loc.path.insert(0, [float(loc.down), path[0][0], path[0][1]])
                    loc.up = math.ceil(seen_path["up"])
                    loc.step = list(seen_path["step"])
                    a, z, reach = seen_path["reach"]
                    loc.how = (f"followed in the picture on {seen_path['frames']} frames, from {a:.1f} to {z:.1f} pt "
                               f"of the {reach:.0f} pt logged")
                else:
                    if "down_s" in g:
                        loc.down = round(g["down_s"] * T)
                        loc.how = "timed by the log's own `down_s`"
                    else:
                        loc.down = b.start - round(_slop_time_ms(path) * T / 1000)
                        why = (track or {}).get("why") or ("the picture gave nothing to go by" if track
                                                           else "the pictures were not looked at")
                        loc.how = f"NOT followed in the picture ({why}): timed by the logged path, 1:1"
                    loc.path = [[loc.down + p[2] * T / 1000, p[0], p[1]] for p in path]
                    loc.up = loc.down + round(path[-1][2] * T / 1000)
            # typed text: no touch point — the key is not on the screen; the
            # text appears, that is all

            if loc.down > loc.first_change:
                raise Refusal("E_MATCH", f"gesture `{pid}`: the touch-down ({loc.down / T:.3f} s) is after the app "
                                         f"already changed ({loc.first_change / T:.3f} s)")
            before = [p for p in changes if p < loc.first_change]
            if before and before[-1] >= loc.down:
                raise Refusal("E_MATCH", f"gesture `{pid}`: the screen is still changing at {before[-1] / T:.3f} s, "
                                         f"after its touch-down at {loc.down / T:.3f} s — the gestures are too close")
            if held(pts, loc.down) is None:
                raise Refusal("E_NO_REST", f"gesture `{pid}`: the take has no picture at its touch-down "
                                           f"({loc.down / T:.3f} s): it begins ON the first gesture's answer. "
                                           f"Let the screen rest before the first gesture (README, runbook).")
            out.append(loc)

    first_tail_change = None
    if tail:
        first_tail_change = _burst_for(tail[0], "(after the film)", bursts, used, T, timing).start

    for i, loc in enumerate(out):
        limit = out[i + 1].first_change if i + 1 < len(out) else (
            first_tail_change if first_tail_change is not None else math.inf)
        loc.last_change = max(p for p in changes if loc.first_change <= p < limit)

    return TakeMap(T, px_per_pt, pts, kinds, changes, bursts, out, reading)


def _token_ticks(sb: dict, token: str, T: int) -> int:
    from brand import motion
    return motion(token).ms * T // 1000


def _touch_leads(sb: dict, T: int) -> tuple[int, int, int]:
    """Ticks, from motion tokens the storyboard names. The instant a finger
    lands is not on the screen; the earliest evidence is the first frame the
    app changes, and these count back and forward from it.

      lead       a kept range starts this long before a drag moves or a typed
                 key shows: the touch point's own fade-in (`motion.touch_in`);
      tap lead   a tap's point appears this long before the app answers
                 (`touch.tap_lead`) — long enough to be seen ON the control
                 before the control reacts, never shorter than its fade-in;
      tap dwell  …and starts to leave this long after (`touch.tap_dwell`)."""
    lead = _token_ticks(sb, sb["motion"]["touch_in"], T)
    tap_lead = _token_ticks(sb, sb["touch"]["tap_lead"], T)
    if tap_lead < lead:
        raise Refusal("E_STORYBOARD", f"touch.tap_lead (`{sb['touch']['tap_lead']}`) is shorter than the touch "
                                      f"point's fade-in (`{sb['motion']['touch_in']}`): the point would not be "
                                      f"whole when the app answers")
    return lead, tap_lead, _token_ticks(sb, sb["touch"]["tap_dwell"], T)


# ---- walking an edit list ----------------------------------------------------

LIVE_KEYS = {"kind", "src_in", "src_out"}
HOLD_KEYS = {"kind", "src_at", "frames", "why"}


@dataclass
class Span:
    kind: str
    film_in: int   # first film frame
    frames: int
    first: int     # first source instant shown (ticks)
    last: int      # last source instant shown
    src_in: int = 0
    src_out: int = 0


def spans(edit: dict, T: int, fps: int) -> list[Span]:
    """The segments with their place in the film. Refuses a segment that says
    anything but a kept range (live) or a held instant (hold): there is no way
    to write a speed."""
    step = T // fps
    out: list[Span] = []
    film = 0
    segs = edit.get("segments")
    if not isinstance(segs, list) or not segs:
        raise Refusal("E_SHAPE", "the edit list has no segments")
    for n, seg in enumerate(segs):
        kind = seg.get("kind") if isinstance(seg, dict) else None
        if kind == "live":
            if set(seg) != LIVE_KEYS:
                raise Refusal("E_SHAPE", f"segment {n}: a live segment is exactly kind, src_in, src_out — "
                                         f"got {sorted(seg)}. Footage plays at its own speed.")
            a, b = seg["src_in"], seg["src_out"]
            if not (isinstance(a, int) and isinstance(b, int)) or b <= a or a < 0:
                raise Refusal("E_SHAPE", f"segment {n}: src_in/src_out must be whole ticks, src_out after src_in")
            if (b - a) % step:
                raise Refusal("E_GRID", f"segment {n}: {b - a} ticks is not a whole number of film frames")
            count = (b - a) // step
            out.append(Span("live", film, count, a, b - step, a, b))
        elif kind == "hold":
            if not set(seg) <= HOLD_KEYS or not {"kind", "src_at", "frames"} <= set(seg):
                raise Refusal("E_SHAPE", f"segment {n}: a hold is kind, src_at, frames (and why) — got {sorted(seg)}")
            at, count = seg["src_at"], seg["frames"]
            if not (isinstance(at, int) and isinstance(count, int)) or count <= 0 or at < 0:
                raise Refusal("E_SHAPE", f"segment {n}: src_at must be a tick and frames a positive whole number")
            out.append(Span("hold", film, count, at, at))
        else:
            raise Refusal("E_SHAPE", f"segment {n}: kind must be `live` or `hold`")
        film += out[-1].frames
    return out


def film_sources(edit: dict, scan: dict, fps: int) -> list[int]:
    """The source frame every film frame shows, by the frame-hold rule. conform
    export computes the same list on its own; the build compares the two."""
    T = scan["video"]["timescale"]
    step = T // fps
    pts = [f["pts"] for f in scan["frames"]]
    out: list[int] = []
    for s in spans(edit, T, fps):
        for k in range(s.frames):
            j = held(pts, s.first + (k * step if s.kind == "live" else 0))
            if j is None:
                raise Refusal("E_START", f"the film shows {s.first / T:.3f} s, before the take's first picture")
            out.append(j)
    return out


def shown(sp: list[Span], step: int) -> list[tuple[int, int]]:
    """The stretches of the take the film passes through: from the first
    instant a segment shows to the last, joined when the next segment carries
    on within one film frame."""
    out: list[tuple[int, int]] = []
    for s in sp:
        if out and s.first - out[-1][1] <= step:
            out[-1] = (out[-1][0], max(out[-1][1], s.last))
        else:
            out.append((s.first, s.last))
    return out


def film_tick(sp: list[Span], src: float, T: int, fps: int) -> float:
    """Film time (in take ticks from the film's start) of a source instant
    that is inside a live segment."""
    step = T // fps
    for s in sp:
        if s.kind == "live" and s.src_in <= src < s.src_out:
            return s.film_in * step + (src - s.src_in)
    raise Refusal("E_PROTECTED", f"{src / T:.3f} s of the take is not in the film")


def cut_pairs(edit: dict, scan: dict, fps: int) -> list[tuple[int, int]]:
    """For every jump in the take, the frame held before it and the frame the
    film resumes on — to be compared with `conform diff`."""
    T = scan["video"]["timescale"]
    pts = [f["pts"] for f in scan["frames"]]
    sp = spans(edit, T, fps)
    out = []
    for a, b in zip(sp, sp[1:]):
        if b.first > a.last:
            ja, jb = held(pts, a.last), held(pts, b.first)
            if ja is not None and jb is not None and ja != jb:
                out.append((ja, jb))
    return out


# ---- proposing ---------------------------------------------------------------

def propose(scan: dict, log: dict, sb: dict, rehearsal: bool = False, tracks: dict | None = None) -> dict:
    """An edit list that obeys the rule, with the storyboard's rests."""
    tm = locate(scan, log, sb, rehearsal, tracks)
    T, fps = tm.timescale, sb["film"]["fps"]
    step = T // fps
    timing = sb["timing"]
    total = whole_frames(sb["film"]["duration_s"], fps, "film.duration_s")
    tail = round(timing["tail_s"] * T)
    lead_in = whole_frames(timing["lead_in_s"], fps, "timing.lead_in_s")
    caption_lead = whole_frames(timing["caption_lead_s"], fps, "timing.caption_lead_s")
    r_hold = whole_frames(timing["rehearsal_hold_s"], fps, "timing.rehearsal_hold_s")
    r_delay = whole_frames(timing["rehearsal_caption_delay_s"], fps, "timing.rehearsal_caption_delay_s")
    rest_after = {g["id"]: whole_frames(g.get("rest_after_s", 0), fps, f"{g['id']}.rest_after_s")
                  for _, g in catalogue(sb)}

    # 1. One kept range per gesture — from its touch-down to `tail` after its
    #    last change — merged when two of them touch.
    ranges: list[dict] = []
    for g in tm.gestures:
        a = g.down
        n = math.ceil((g.last_change + tail - a) / step) + 1
        if ranges and a < ranges[-1]["out"]:
            r = ranges[-1]
            n = math.ceil((g.last_change + tail - r["in"]) / step) + 1
            r["out"] = max(r["out"], r["in"] + n * step)
            r["gestures"].append(g)
        else:
            ranges.append({"in": a, "out": a + n * step, "gestures": [g]})
    range_of = {g.id: r for r in ranges for g in r["gestures"]}

    # 2. The film, shot by shot.
    segments: list[dict] = []
    slots: dict[str, int] = {}     # shot id -> first film frame of a gesture-less shot's hold
    film = 0
    cursor = ranges[0]["in"]       # the source instant on screen
    done: set[int] = set()

    def hold(count: int, why: str) -> None:
        nonlocal film
        if count > 0:
            segments.append({"kind": "hold", "src_at": cursor, "frames": count, "why": why})
            film += count

    shots = sb["shots"]
    by_shot = {s["id"]: [g for g in tm.gestures if g.shot == s["id"]] for s in shots}
    for n, shot in enumerate(shots):
        mine = by_shot[shot["id"]]
        if not mine:
            if n == len(shots) - 1:
                break                                  # the final hold, below
            if not rehearsal:
                raise Refusal("E_STORYBOARD", f"shot {shot['id']} has no gesture and is not the last shot")
            slots[shot["id"]] = film
            hold(r_hold, f"rehearsal: shot {shot['id']} has no footage")
            continue
        if film == 0:
            hold(lead_in, "lead-in: the screen at rest before the first touch")
        for g in mine:
            r = range_of[g.id]
            if id(r) not in done:
                done.add(id(r))
                segments.append({"kind": "live", "src_in": r["in"], "src_out": r["out"]})
                film += (r["out"] - r["in"]) // step
                cursor = r["out"] - step
            # a typed key is followed by the next key: the storyboard's rest
            # comes after the last one
            if g is r["gestures"][-1] and g.last:
                hold(rest_after[g.gesture], f"rest after {g.gesture}")
    final_start = film
    if total - film <= 0:
        raise Refusal("E_LENGTH", f"the film is already {film / fps:.2f} s before its final hold; the storyboard "
                                  f"says {total / fps:g} s — shorten rest_after_s values or lengthen duration_s")
    slots[shots[-1]["id"]] = film
    hold(total - film, "final hold")

    edit = {"segments": segments}
    sp = spans(edit, T, fps)

    # 3. Captions: a shot's caption is in place `caption_lead` before its first
    #    touch; a shot without a gesture names the gesture it follows.
    captions = [{"frame": 0, "caption": shots[0]["caption"]}]
    for shot in shots[1:]:
        if shot["caption"] == captions[-1]["caption"]:
            continue
        mine = by_shot[shot["id"]]
        after = shot.get("caption_after")
        if mine:
            at = math.floor(film_tick(sp, mine[0].down, T, fps) / step) - caption_lead
        elif after and any(x.gesture == after["gesture"] for x in tm.gestures):
            g = [x for x in tm.gestures if x.gesture == after["gesture"]][-1]
            at = math.ceil(film_tick(sp, g.burst_end, T, fps) / step) + whole_frames(
                after["delay_s"], fps, f"{shot['id']}.caption_after.delay_s")
        elif rehearsal:
            at = slots[shot["id"]] + r_delay
        else:
            raise Refusal("E_STORYBOARD", f"shot {shot['id']} has no gesture: it needs `caption_after`")
        captions.append({"frame": at, "caption": shot["caption"]})

    # 4. Touch points, in film time.
    edit.update({
        "fps": fps, "timescale": T, "rehearsal": bool(rehearsal),
        "variant": sb.get("variant"),
        "take": dict(scan.get("take", {})),
        "captions": captions, "touches": propose_touches(tm, sp, fps),
        "poster_frame": whole_frames(sb["film"]["poster_s"], fps, "film.poster_s"),
        "final_hold_from": final_start,
    })
    return edit


# ---- checking ----------------------------------------------------------------

def check(edit: dict, scan: dict, log: dict, sb: dict,
          pair_diffs: dict[tuple[int, int], dict] | None = None, tracks: dict | None = None) -> TakeMap:
    """Refuse (raise Refusal) an edit list that breaks the editing rule, does
    not belong to this take, or does not make the storyboard's film. The
    windows are re-derived here from the scan and the gesture log; nothing the
    edit list says about them is believed."""
    from brand import motion

    rehearsal = bool(edit.get("rehearsal"))
    # A variant of the storyboard is a rehearsal, whatever the edit list says
    # of itself; and an edit list made from one cannot pass for the film's.
    def named(variant: str | None) -> str:
        return f"the variant `{variant}`" if variant else "the film itself"

    if edit.get("variant") != sb.get("variant"):
        raise Refusal("E_VARIANT", f"the edit list was made for {named(edit.get('variant'))}, this storyboard is "
                                   f"{named(sb.get('variant'))}")
    if sb.get("variant") and not rehearsal:
        raise Refusal("E_VARIANT", f"{named(sb['variant'])} is a rehearsal: its edit list cannot say it is the film")
    tm = locate(scan, log, sb, rehearsal, tracks)
    T, fps = tm.timescale, sb["film"]["fps"]
    step = T // fps
    take = scan.get("take", {})
    if edit.get("take") != take or edit.get("timescale") != T or edit.get("fps") != fps:
        raise Refusal("E_TAKE", "the edit list was made for another take (file, size or hash differs)")
    sp = spans(edit, T, fps)

    # No reordering: the take is only ever read forwards.
    for n, (a, b) in enumerate(zip(sp, sp[1:])):
        if b.first < a.last:
            raise Refusal("E_ORDER", f"segment {n + 1} goes back in the take: {b.first / T:.3f} s after "
                                     f"{a.last / T:.3f} s")
    first, last = sp[0].first, sp[-1].last
    if held(tm.pts, first) is None:
        raise Refusal("E_START", f"the film starts at {first / T:.3f} s, before the take's first picture")

    # THE RULE. From a touch-down to the last change before the next one, the
    # take is inside one live segment: not cut, not held, not retimed.
    live = [s for s in sp if s.kind == "live"]
    for g in tm.gestures:
        if not any(s.src_in <= g.down and g.last_change <= s.last for s in live):
            raise Refusal("E_PROTECTED",
                          f"gesture `{g.id}`: the take from its touch-down ({g.down / T:.3f} s) to the end of the "
                          f"app's response ({g.last_change / T:.3f} s) must play whole, in one piece — this edit "
                          f"list cuts or holds inside it")

    # A cut only ever removes a still screen.
    tail = round(sb["timing"]["tail_s"] * T)
    passed = shown(sp, step)
    for p in tm.changes:
        if first < p <= last and not any(a <= p <= b for a, b in passed):
            raise Refusal("E_CHANGE_REMOVED", f"the screen changes at {p / T:.3f} s of the take and the edit "
                                              f"list removes it")
        if first - tail < p <= first:
            raise Refusal("E_START", f"the film starts at {first / T:.3f} s while the screen is still changing "
                                     f"({p / T:.3f} s)")

    # …and the picture held before a cut is the picture the film resumes on.
    if pair_diffs is not None:
        for a, b in cut_pairs(edit, scan, fps):
            d = pair_diffs.get((a, b))
            if d is None:
                raise Refusal("E_ENDPOINT", f"no comparison of frames {a} and {b} across a cut")
            if pair_kind(d, tm, b) == "change":
                raise Refusal("E_ENDPOINT", f"a cut jumps from frame {a} to frame {b} and they are not the same "
                                            f"picture (soft {d.get('soft')}, strong {d.get('strong')}, "
                                            f"box {d.get('box')})")

    # The storyboard's film.
    total = sum(s.frames for s in sp)
    want = whole_frames(sb["film"]["duration_s"], fps, "film.duration_s")
    if total != want or not 15 * fps <= total <= 30 * fps:
        raise Refusal("E_LENGTH", f"the film is {total} frames ({total / fps:.3f} s); the storyboard says "
                                  f"{want / fps:g} s and Apple takes 15 to 30 s")
    final = sp[-1]
    if final.kind != "hold" or edit.get("final_hold_from") != final.film_in:
        raise Refusal("E_FINAL_HOLD", "the film does not end on a hold of the resting screen")
    minimum = whole_frames(sb["film"]["final_hold_min_s"], fps, "film.final_hold_min_s")
    if final.frames < minimum:
        raise Refusal("E_FINAL_HOLD", f"the final hold is {final.frames / fps:.2f} s; the storyboard asks for at "
                                      f"least {minimum / fps:g} s")

    # Captions: the storyboard's, in its order, one cross-fade at a time.
    fade = motion(sb["motion"]["caption"]).frames(fps)
    caps = edit.get("captions") or []
    expected = []
    for shot in sb["shots"]:
        if not expected or expected[-1] != shot["caption"]:
            expected.append(shot["caption"])
    if [c.get("caption") for c in caps] != expected or caps[0].get("frame") != 0:
        raise Refusal("E_CAPTION", f"the captions must be {expected}, the first from frame 0")
    for a, b in zip(caps, caps[1:]):
        if not isinstance(b["frame"], int) or b["frame"] < a["frame"] + fade:
            raise Refusal("E_CAPTION", f"caption `{b['caption']}` at frame {b['frame']} starts before "
                                       f"`{a['caption']}` has finished changing")
    if caps[-1]["frame"] + fade > total:
        raise Refusal("E_CAPTION", "the last caption change runs past the end of the film")

    # Touch points sit where the data puts them.
    mine = edit.get("touches") or []
    theirs = propose_touches(tm, sp, fps)
    if mine != theirs:
        raise Refusal("E_TOUCH", "the touch points are not where the take and the gesture log put them")

    # The poster frame: the final hold, nothing in motion.
    poster = edit.get("poster_frame")
    if poster != whole_frames(sb["film"]["poster_s"], fps, "film.poster_s"):
        raise Refusal("E_POSTER", "the poster frame is not the storyboard's")
    out_frames = motion(sb["motion"]["touch_out"]).frames(fps)
    settled = max([final.film_in, caps[-1]["frame"] + fade]
                  + [math.ceil(t["up"] / step) + out_frames for t in mine])
    if not settled <= poster < total:
        raise Refusal("E_POSTER", f"the poster frame ({poster / fps:g} s) must fall in the final hold, after the "
                                  f"last caption and touch point have settled ({settled / fps:.2f} s)")
    return tm


def pair_kind(d: dict, tm: TakeMap, frame: int) -> str:
    """What the two sides of a cut differ by, read as a frame of the still
    stretch the cut is in: the caret of that stretch, where it blinks, is
    nothing changing; anything else is a change."""
    r = tm.reading
    return frame_kind(d, tm.px_per_pt, r.columns[frame], r.areas[frame]) if r else frame_kind(d, tm.px_per_pt)


def propose_touches(tm: TakeMap, sp: list[Span], fps: int) -> list[dict]:
    """Touch points in film time (take ticks from the film's start): where the
    finger lands, the path it follows, when it leaves. `step`, on a drag
    followed in the picture, is the span in which every point of the path is
    a frame of the take: there the point holds until the next frame, as the
    picture does."""
    T = tm.timescale
    out = []
    for g in tm.gestures:
        if g.kind == "type":
            continue
        down = round(film_tick(sp, g.down, T, fps))
        touch = {
            "gesture": g.id, "kind": g.kind, "down": down, "up": down + (g.up - g.down),
            "path": [[round(film_tick(sp, g.down, T, fps) + (p[0] - g.down), 3), p[1], p[2]] for p in g.path],
        }
        if g.step:
            touch["step"] = [down + (t - g.down) for t in g.step]
        out.append(touch)
    return out


# ---- the log a person reads --------------------------------------------------

def describe(edit: dict, scan: dict, log: dict, sb: dict,
             pair_diffs: dict[tuple[int, int], dict] | None = None, tracks: dict | None = None) -> str:
    """Every kept range, every hold and every cut, in plain lines."""
    tm = locate(scan, log, sb, bool(edit.get("rehearsal")), tracks)
    T, fps = tm.timescale, sb["film"]["fps"]
    sp = spans(edit, T, fps)
    frames = scan["frames"]
    take = scan.get("take", {})
    lines = []
    w = lines.append

    def s(t: float) -> str:
        return f"{t / T:7.3f} s"

    w(f"take   {take.get('file', '?')}  sha256 {str(take.get('sha256', '?'))[:16]}…  "
      f"{len(frames)} frames, {scan['video']['duration_ticks'] / T:.3f} s, "
      f"{scan['video']['width']}x{scan['video']['height']}")
    counts = {k: tm.kinds.count(k) for k in ("change", "quiet", "caret")}
    w(f"frames {counts['change']} change, {counts['quiet']} quiet, {counts['caret']} caret-only "
      f"(a change: >= {STRONG_MIN} strong or >= {SOFT_MIN} soft pixels)")
    # How close the take comes to the thresholds, from both sides. The first
    # picture is a change by what the recorder is, not by measure: left out.
    def loudness(f: dict) -> float:
        return max(f.get("strong", 0) / STRONG_MIN, f.get("soft", 0) / SOFT_MIN)

    quiet = [f for f, k in zip(frames, tm.kinds) if k == "quiet"]
    moving = [f for f, k in list(zip(frames, tm.kinds))[1:] if k == "change"]
    if quiet:
        q = max(quiet, key=loudness)
        w(f"       loudest quiet frame:   {s(q['pts'])}  soft {q.get('soft', 0)}, strong {q.get('strong', 0)}")
    if moving:
        m = min(moving, key=loudness)
        w(f"       faintest change frame: {s(m['pts'])}  soft {m.get('soft', 0)}, strong {m.get('strong', 0)}")
    if sb.get("variant"):
        w(f"REHEARSAL — the storyboard's variant `{sb['variant']}`; this is not the film.")
    elif edit.get("rehearsal"):
        w("REHEARSAL — shots without footage are holds; this is not the film.")
    w("")
    w("changes in the take (bursts)")
    for b in tm.bursts:
        who = next((g.id for g in tm.gestures if g.burst == b.index), None)
        w(f"  {s(b.start)} – {s(b.end)}  {b.frames:4d} frames  "
          + (f"<- {who}" if who else "(no gesture: the app on its own, or outside the film)"))
    w("")
    w("gestures")
    for g in tm.gestures:
        d = "" if g.distance_pt is None else f"  first change {g.distance_pt:.0f} pt from the touch"
        w(f"  {g.id:<16} {g.kind:<5} touch-down {s(g.down)}  first change {s(g.first_change)}  "
          f"last change {s(g.last_change)}{d}")
        if g.how:
            w(f"  {'':<16} {g.how}")
    w("")
    w("film (what is kept, and where it lands)")
    for seg, x in zip(edit["segments"], sp):
        t0, t1 = x.film_in / fps, (x.film_in + x.frames) / fps
        if x.kind == "live":
            w(f"  film {t0:6.3f} – {t1:6.3f} s  LIVE  take {s(x.src_in)} – {s(x.src_out)}  "
              f"({x.frames} frames, 1:1)")
        else:
            w(f"  film {t0:6.3f} – {t1:6.3f} s  HOLD  the picture at take {s(x.first)}  "
              f"({x.frames} frames)  {seg.get('why', '')}")
    w("")
    w("cuts (what is removed)")
    n = 0
    first, last = sp[0].first, sp[-1].last
    head = [f for f, k in zip(frames, tm.kinds) if f["pts"] <= first and k == "change"]
    if first > frames[0]["pts"]:
        n += 1
        w(f"  {n}. take {s(frames[0]['pts'])} – {s(first)} removed: before the film starts "
          f"({len(head)} change frame{'' if len(head) == 1 else 's'} in it — nothing of the film)")
    for a, b in zip(sp, sp[1:]):
        if b.first <= a.last:
            continue
        n += 1
        inside = [(f, k) for f, k in zip(frames, tm.kinds) if a.last < f["pts"] <= b.first]
        q = [f for f, k in inside if k == "quiet"]
        c = [f for f, k in inside if k == "caret"]
        x = [f for f, k in inside if k == "change"]
        line = (f"  {n}. take {s(a.last)} – {s(b.first)} removed, lands on film "
                f"{(b.film_in) / fps:6.3f} s: {len(q)} quiet frames")
        if q:
            line += f" (loudest soft {max(f.get('soft', 0) for f in q)}, strong {max(f.get('strong', 0) for f in q)})"
        if c:
            boxes = [f["box"] for f in c if f.get("box")]
            line += (f", {len(c)} caret-only frames in the box "
                     f"{[min(b_[0] for b_ in boxes), min(b_[1] for b_ in boxes), max(b_[2] for b_ in boxes), max(b_[3] for b_ in boxes)]}")
        if x:
            line += f", {len(x)} CHANGE FRAMES"
        ja, jb = held(tm.pts, a.last), held(tm.pts, b.first)
        if ja == jb:
            line += "; the same frame on both sides"
        elif pair_diffs and (ja, jb) in pair_diffs:
            d = pair_diffs[(ja, jb)]
            line += (f"; frame {ja} against frame {jb}: soft {d.get('soft', 0)}, strong {d.get('strong', 0)} "
                     f"({pair_kind(d, tm, jb)})")
        w(line)
    end = scan["video"]["duration_ticks"]
    if last < end:
        n += 1
        after = [f for f, k in zip(frames, tm.kinds) if f["pts"] > last and k == "change"]
        w(f"  {n}. take {s(last)} – {s(end)} removed: after the film ends "
          f"({len(after)} change frame{'' if len(after) == 1 else 's'} in it)")
    w("")
    w("captions")
    for c in edit["captions"]:
        w(f"  film {c['frame'] / fps:6.3f} s  {c['caption']}")
    w("touch points")
    for t in edit["touches"]:
        w(f"  film {t['down'] / T:6.3f} – {t['up'] / T:6.3f} s  {t['kind']:<5} {t['gesture']}  "
          f"from ({t['path'][0][1]:g}, {t['path'][0][2]:g}) pt"
          + (f" to ({t['path'][-1][1]:g}, {t['path'][-1][2]:g}) pt" if t["kind"] == "drag" else ""))
    w(f"poster frame: film {edit['poster_frame'] / fps:g} s (frame {edit['poster_frame']}); "
      f"final hold from {edit['final_hold_from'] / fps:.3f} s; {sum(x.frames for x in sp)} frames, "
      f"{sum(x.frames for x in sp) / fps:.3f} s")
    return "\n".join(lines) + "\n"
