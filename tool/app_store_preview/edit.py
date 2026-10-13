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
    finger — may be shortened, or lengthened by holding its picture.
  * A cut may only jump between two pictures that are the same picture.

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
# A text caret blinking is a change of a few hundred strong pixels in a box a
# caret's shape — thin, and one text line tall — and nothing else on screen.
# It is treated as nothing changing (README, « The editing rule »). The box,
# in device points: at most CARET_MAX_PT wide and tall, at least
# CARET_MIN_HEIGHT_PT tall. The minimum height matters: on the probe the
# refresh spinner's arrow grew by boxes 5 x 1 to 17 x 15 pixels — small, and
# real; none is 10 points tall.
CARET_MAX_PT = (6.0, 34.0)
CARET_MIN_HEIGHT_PT = 10.0

# Flutter starts a drag once the finger has travelled this far (kTouchSlop,
# flutter/lib/src/gestures/constants.dart): the first frame that moves is that
# late after the touch-down.
DRAG_SLOP_PT = 18.0


class Refusal(Exception):
    """An edit list, a gesture log or a take the tool will not work with."""

    def __init__(self, code: str, message: str):
        super().__init__(f"[{code}] {message}")
        self.code, self.message = code, message


def frame_kind(row: dict, px_per_pt: float) -> str:
    """`change`, `caret` or `quiet` for one scan row (or one pair diff)."""
    soft, strong = row.get("soft", 0), row.get("strong", 0)
    if strong < STRONG_MIN and soft < SOFT_MIN:
        return "quiet"
    box = row.get("box")
    if box and soft < SOFT_MIN:
        w, h = (box[2] - box[0]) / px_per_pt, (box[3] - box[1]) / px_per_pt
        if w <= CARET_MAX_PT[0] and CARET_MIN_HEIGHT_PT <= h <= CARET_MAX_PT[1]:
            return "caret"
    return "change"


def frame_kinds(scan: dict, px_per_pt: float) -> list[str]:
    kinds = [frame_kind(f, px_per_pt) for f in scan["frames"]]
    # The recorder writes a frame when the screen changes, and only then. So a
    # take's first picture is itself a change — the first frame of whatever
    # woke the recorder — though there is nothing before it to measure it by.
    if kinds:
        kinds[0] = "change"
    return kinds


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


# ---- finding each gesture in the take ---------------------------------------

@dataclass
class Located:
    id: str
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


@dataclass
class TakeMap:
    timescale: int
    px_per_pt: float
    pts: list[int]
    kinds: list[str]
    changes: list[int]     # ticks of every change frame
    bursts: list[Burst]
    gestures: list[Located]


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


def locate(scan: dict, log: dict, sb: dict, rehearsal: bool = False) -> TakeMap:
    """Where each logged gesture is in the take: its touch-down and how long
    the app goes on answering it. Found from the data; the log only says
    roughly when (`near_s`) and exactly where."""
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
    lead = _touch_lead_ticks(sb, T)
    pts = [f["pts"] for f in scan["frames"]]
    kinds = frame_kinds(scan, px_per_pt)
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
    first_tail_change = None
    for g in filmed + tail[:1]:
        gid = g.get("id", "(after the film)")
        is_filmed = g.get("film", True)
        if "near_s" not in g:
            raise Refusal("E_LOG", f"gesture `{gid}` needs `near_s`: roughly when, in seconds of the take")
        near = round(g["near_s"] * T)
        tol = round(g.get("tolerance_s", timing["sync_tolerance_s"]) * T)
        cands = [b for b in bursts if abs(b.start - near) <= tol and b.index > used]
        if not cands:
            where = ", ".join(f"{b.start / T:.3f}" for b in bursts) or "none"
            raise Refusal("E_MATCH", f"gesture `{gid}`: nothing starts changing within ±{tol / T:g} s of "
                                     f"{g['near_s']} s (changes start at: {where})")
        if len(cands) > 1:
            raise Refusal("E_MATCH", f"gesture `{gid}`: {len(cands)} changes start within ±{tol / T:g} s of "
                                     f"{g['near_s']} s ({', '.join(f'{b.start / T:.3f}' for b in cands)}) — "
                                     f"set `near_s` on the one meant and a smaller `tolerance_s`")
        b = cands[0]
        used = b.index
        if not is_filmed:
            first_tail_change = b.start
            break

        kind = g.get("kind")
        if kind != kind_of[gid]:
            raise Refusal("E_LOG", f"gesture `{gid}` is a {kind_of[gid]} in the storyboard, a {kind} in the log")
        loc = Located(gid, shot_of[gid], kind, b.index, b.start, b.start, b.start, b.end)
        if kind == "tap":
            at = g.get("at")
            if not (isinstance(at, list) and len(at) == 2):
                raise Refusal("E_LOG", f"tap `{gid}` needs `at`: [x, y] in points")
            loc.down = b.start - lead
            dwell = _token_ticks(sb, sb["touch"]["tap_dwell"], T)
            loc.up = b.start + dwell
            loc.path = [[loc.down, at[0], at[1]]]
            loc.distance_pt = _box_distance_pt(scan["frames"][b.first].get("box"), at[0], at[1], px_per_pt)
        elif kind == "drag":
            path = g.get("path")
            if not (isinstance(path, list) and len(path) >= 2 and all(len(p) == 3 for p in path)):
                raise Refusal("E_LOG", f"drag `{gid}` needs `path`: [[x, y, ms since touch-down], …]")
            if any(pb[2] <= pa[2] for pa, pb in zip(path, path[1:])) or path[0][2] != 0:
                raise Refusal("E_LOG", f"drag `{gid}`: path times start at 0 and increase")
            if "down_s" in g:
                loc.down = round(g["down_s"] * T)
            else:
                loc.down = b.start - round(_slop_time_ms(path) * T / 1000)
            loc.path = [[loc.down + p[2] * T / 1000, p[0], p[1]] for p in path]
            loc.up = loc.down + round(path[-1][2] * T / 1000)
            loc.distance_pt = _box_distance_pt(scan["frames"][b.first].get("box"), path[0][0], path[0][1], px_per_pt)
        elif kind == "type":
            pass  # no touch point: the text appears, that is all
        else:
            raise Refusal("E_LOG", f"gesture `{gid}`: unknown kind `{kind}`")

        if loc.down > loc.first_change:
            raise Refusal("E_MATCH", f"gesture `{gid}`: the touch-down ({loc.down / T:.3f} s) is after the app "
                                     f"already changed ({loc.first_change / T:.3f} s)")
        before = [p for p in changes if p < loc.first_change]
        if before and before[-1] >= loc.down:
            raise Refusal("E_MATCH", f"gesture `{gid}`: the screen is still changing at {before[-1] / T:.3f} s, "
                                     f"after its touch-down at {loc.down / T:.3f} s — the gestures are too close")
        if held(pts, loc.down) is None:
            raise Refusal("E_NO_REST", f"gesture `{gid}`: the take has no picture at its touch-down "
                                       f"({loc.down / T:.3f} s). The recorder writes nothing until the screen "
                                       f"first changes, so the take begins ON the first gesture's answer "
                                       f"(README, runbook step 4).")
        out.append(loc)

    for i, loc in enumerate(out):
        limit = out[i + 1].first_change if i + 1 < len(out) else (
            first_tail_change if first_tail_change is not None else math.inf)
        loc.last_change = max(p for p in changes if loc.first_change <= p < limit)

    return TakeMap(T, px_per_pt, pts, kinds, changes, bursts, out)


def _token_ticks(sb: dict, token: str, T: int) -> int:
    from brand import motion
    return motion(token).ms * T // 1000


def _touch_lead_ticks(sb: dict, T: int) -> int:
    """A tap's point starts to appear this long before the app answers: the
    length of its own fade-in, so it is fully there when the answer starts."""
    return _token_ticks(sb, sb["motion"]["touch_in"], T)


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

def propose(scan: dict, log: dict, sb: dict, rehearsal: bool = False) -> dict:
    """An edit list that obeys the rule, with the storyboard's rests."""
    tm = locate(scan, log, sb, rehearsal)
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
            if g is r["gestures"][-1]:
                hold(rest_after[g.id], f"rest after {g.id}")
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
        elif after and after["gesture"] in range_of:
            g = next(x for x in tm.gestures if x.id == after["gesture"])
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
        "take": dict(scan.get("take", {})),
        "captions": captions, "touches": propose_touches(tm, sp, fps),
        "poster_frame": whole_frames(sb["film"]["poster_s"], fps, "film.poster_s"),
        "final_hold_from": final_start,
    })
    return edit


# ---- checking ----------------------------------------------------------------

def check(edit: dict, scan: dict, log: dict, sb: dict,
          pair_diffs: dict[tuple[int, int], dict] | None = None) -> TakeMap:
    """Refuse (raise Refusal) an edit list that breaks the editing rule, does
    not belong to this take, or does not make the storyboard's film. The
    windows are re-derived here from the scan and the gesture log; nothing the
    edit list says about them is believed."""
    from brand import motion

    rehearsal = bool(edit.get("rehearsal"))
    tm = locate(scan, log, sb, rehearsal)
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
            if frame_kind(d, tm.px_per_pt) == "change":
                raise Refusal("E_ENDPOINT", f"a cut jumps from frame {a} to frame {b} and they are not the same "
                                            f"picture (soft {d.get('soft')}, strong {d.get('strong')})")

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


def propose_touches(tm: TakeMap, sp: list[Span], fps: int) -> list[dict]:
    """Touch points in film time (take ticks from the film's start): where the
    finger lands, the path it follows, when it leaves."""
    T = tm.timescale
    out = []
    for g in tm.gestures:
        if g.kind == "type":
            continue
        down = round(film_tick(sp, g.down, T, fps))
        out.append({
            "gesture": g.id, "kind": g.kind, "down": down, "up": down + (g.up - g.down),
            "path": [[round(film_tick(sp, g.down, T, fps) + (p[0] - g.down), 3), p[1], p[2]] for p in g.path],
        })
    return out


# ---- the log a person reads --------------------------------------------------

def describe(edit: dict, scan: dict, log: dict, sb: dict,
             pair_diffs: dict[tuple[int, int], dict] | None = None) -> str:
    """Every kept range, every hold and every cut, in plain lines."""
    tm = locate(scan, log, sb, bool(edit.get("rehearsal")))
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
    if edit.get("rehearsal"):
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
                     f"({frame_kind(d, tm.px_per_pt)})")
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
          f"from ({t['path'][0][1]:g}, {t['path'][0][2]:g}) pt")
    w(f"poster frame: film {edit['poster_frame'] / fps:g} s (frame {edit['poster_frame']}); "
      f"final hold from {edit['final_hold_from'] / fps:.3f} s; {sum(x.frames for x in sp)} frames, "
      f"{sum(x.frames for x in sp) / fps:.3f} s")
    return "\n".join(lines) + "\n"
