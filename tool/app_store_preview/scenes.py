"""A film made of scenes — the App Preview, version 2.

Version 1 (`edit.py`, storyboard.json) is one take played as one flow. This
is the film the owner chose on 2026-10-14 (« option 3 »): several scenes,
each cut from its own take, joined by a short cross-dissolve, closed by an
end card. README.md « Version 2 — scenes » has the rules in prose.

  * Inside a scene, version 1's editing rule holds unchanged: from a
    touch-down to the last change before the next touch-down the take plays
    once, in order, at its own speed; only still screens are cut, and a cut
    jumps between two pictures that are the same picture. `edit.check_take`
    is that rule, the very code version 1 runs.
  * A scene names the gestures it shows (by their ids in its take's gesture
    log, in the take's order, with nothing of another gesture between them),
    or keeps a stretch of its take by times; either way, every gesture of
    the take that the scene's footage touches plays whole.
  * A scene may declare ONE dissolve inside itself: from one picture at rest
    to a later picture at rest of the same take (« the form, opened » →
    « the form, filled »). It is the only way a scene skips footage in which
    the screen changes, and the log says what it skipped.
  * Scenes join only by a cross-dissolve of the whole frame, on a motion
    token's duration and curve, and only between two pictures at rest, with
    no touch point on either.
  * The film ends on an end card: the mark, « MyWeli Pro », and the sign-in
    disclosure, 1.5 to 2.5 s, the last scene dissolving into it.
  * The film is 15 to 30 s; each scene's budget is a target the log reports.

`propose` builds the plan (film.json) from the takes and the storyboard;
`check` re-derives everything it can from the same data and refuses a plan
that breaks a rule, whoever wrote it. Times in a take are integer ticks of
its own timescale; times in the film are whole frames.
"""

from __future__ import annotations

import dataclasses
import hashlib
import json
from dataclasses import dataclass
from pathlib import Path

import edit as editlist
from edit import READING_CPS, Refusal, Span, TakeMap, held, spans, whole_frames

FRAMES = ("framed", "full-bleed")
BANDS = ("top", "bottom")
MASK_STYLES = ("fill", "blur")
FILM_S = (15, 30)            # Apple: an App Preview is 15 to 30 s
END_CARD_S = (1.5, 2.5)      # the end card: long enough to read, short enough to stay a sign-off
VERSION = 2


# ---- the storyboard ------------------------------------------------------------

def _need(cond: bool, message: str, code: str = "E_STORYBOARD") -> None:
    if not cond:
        raise Refusal(code, message)


def load(doc: dict, base: Path) -> dict:
    """The storyboard of a film made of scenes, checked for shape, with each
    scene's take and gesture log resolved against `base` (the folder the
    takes are in). Nothing is read from the takes here."""
    _need(doc.get("version") == VERSION, f"a storyboard of scenes says \"version\": {VERSION}")
    sb = json.loads(json.dumps(doc))       # a copy the caller cannot change under us
    film = sb.get("film") or {}
    _need(film.get("fps") == 30 and (film.get("width"), film.get("height")) == (886, 1920),
          "film: 886 x 1920 at 30 fps — the App Preview's size for this iPhone")
    _need(film.get("frame") in FRAMES, f"film.frame is one of {', '.join(FRAMES)}")
    for key in ("join", "dissolve", "end_card", "touch_in", "touch_out"):
        _need(isinstance((sb.get("motion") or {}).get(key), str), f"motion.{key} names a motion token")
    for key in ("rest_s", "tail_s", "sync_tolerance_s", "lead_in_s"):
        _need(isinstance((sb.get("timing") or {}).get(key), (int, float)), f"timing.{key} is a number of seconds")
    band = sb.get("band") or {}
    _need(isinstance(band.get("top_pt"), (int, float)) and isinstance(band.get("bottom_pt"), (int, float)),
          "band: top_pt and bottom_pt — where the screen's own bars end, in points (the full-bleed caption sits "
          "inside them)")
    end = sb.get("end_card") or {}
    _need(isinstance(end.get("title"), str) and isinstance(end.get("line"), str)
          and isinstance(end.get("duration_s"), (int, float)),
          "end_card: a title, the disclosure line, and duration_s")
    scenes = sb.get("scenes")
    _need(isinstance(scenes, list) and scenes, "the storyboard lists its scenes")
    ids = [s.get("id") for s in scenes]
    _need(all(isinstance(i, str) for i in ids) and len(set(ids)) == len(ids), "every scene has its own id")
    for s in scenes:
        sid = s["id"]
        _need(isinstance(s.get("take"), str) and isinstance(s.get("gestures"), str),
              f"scene {sid}: `take` and `gestures` are paths")
        s["take_path"] = str((Path(base) / s["take"]).resolve())
        s["gestures_path"] = str((Path(base) / s["gestures"]).resolve())
        head, sub = s.get("headline"), s.get("subline", [])
        _need(isinstance(head, list) and 1 <= len(head) <= 2 and all(isinstance(t, str) and t for t in head),
              f"scene {sid}: a headline of one or two hand-set lines")
        _need(isinstance(sub, list) and len(sub) <= 2 and all(isinstance(t, str) and t for t in sub),
              f"scene {sid}: a sub-line of zero to two hand-set lines")
        s["subline"] = sub
        _need(s.get("band", "top") in BANDS, f"scene {sid}: band is one of {', '.join(BANDS)}")
        s.setdefault("band", "top")
        keep = s.get("keep")
        _need(isinstance(keep, list) and keep, f"scene {sid}: `keep` lists what the scene shows")
        dissolves = 0
        for n, item in enumerate(keep):
            kinds = [k for k in ("gesture", "dissolve", "from_s") if k in item]
            _need(len(kinds) == 1, f"scene {sid}, keep[{n}]: one of `gesture`, `dissolve`, `from_s`/`to_s`")
            if "dissolve" in item:
                dissolves += 1
                _need(0 < n < len(keep) - 1 and "dissolve" not in keep[n - 1],
                      f"scene {sid}: a dissolve sits between two things the scene shows", "E_DISSOLVE")
            if "from_s" in item:
                _need(isinstance(item.get("to_s"), (int, float)) and item["to_s"] > item["from_s"],
                      f"scene {sid}, keep[{n}]: a stretch by times is `from_s` and a later `to_s`")
            if "ground" in item:
                _need(item["ground"] in ("light", "dark"), f"scene {sid}, keep[{n}]: ground is light or dark")
        _need(dissolves <= 1, f"scene {sid}: one dissolve inside a scene at most — it declares one "
                              f"rested picture becoming another, not a montage", "E_DISSOLVE")
        for m, mask in enumerate(s.get("masks") or []):
            _mask_shape(sid, m, mask)
    poster = film.get("poster") or {}
    _need(poster.get("scene") in ids and isinstance(poster.get("at_s"), (int, float)),
          "film.poster: the scene it is in and `at_s`, seconds into that scene")
    sb["rehearsal"] = bool(sb.get("rehearsal"))
    return sb


def _mask_shape(sid: str, m: int, mask: dict) -> None:
    what = f"scene {sid}, mask {m}"
    rect = mask.get("rect_px")
    _need(isinstance(rect, list) and len(rect) == 4 and all(isinstance(v, int) for v in rect)
          and rect[2] > 0 and rect[3] > 0 and rect[0] >= 0 and rect[1] >= 0,
          f"{what}: `rect_px` is [x, y, width, height] in whole pixels of the capture — read it on the take",
          "E_MASK")
    _need(mask.get("style", "fill") in MASK_STYLES, f"{what}: style is one of {', '.join(MASK_STYLES)}", "E_MASK")
    track = mask.get("track")
    if track is not None:
        band = track.get("scroll_px") if isinstance(track, dict) else None
        _need(isinstance(band, list) and len(band) == 2 and all(isinstance(v, int) for v in band)
              and band[0] < band[1] and band[0] <= rect[1] and rect[1] + rect[3] <= band[1],
              f"{what}: a mask that tracks the scroll names the band that scrolls, `scroll_px`: [top, bottom] in "
              f"pixels, around its rectangle", "E_MASK")
    for key in ("ref_s", "from_s", "to_s"):
        _need(mask.get(key) is None or isinstance(mask[key], (int, float)), f"{what}: {key} is in seconds", "E_MASK")


def storyboard_sha256(doc: dict) -> str:
    return hashlib.sha256(json.dumps(doc, sort_keys=True, ensure_ascii=False).encode()).hexdigest()


def take_storyboard(sb: dict, log: dict) -> dict:
    """What `edit.locate` reads, for one take: every gesture its log films,
    as one shot. Each gesture's window is then bounded by the next one in the
    TAKE, whichever scene shows it."""
    gestures = [{"id": g.get("id"), "kind": g.get("kind")} for g in log.get("gestures", []) if g.get("film", True)]
    return {"film": {"fps": sb["film"]["fps"], "width": sb["film"]["width"], "height": sb["film"]["height"]},
            "timing": sb["timing"], "touch": sb["touch"],
            "motion": {"caption": sb["motion"]["join"], "touch_in": sb["motion"]["touch_in"],
                       "touch_out": sb["motion"]["touch_out"]},
            "shots": [{"id": "take", "caption": None, "gestures": gestures}]}


@dataclass
class Take:
    """One take, read: its scan, its gesture log, where each gesture is, and
    each drag as the picture follows it."""
    key: str
    path: str
    scan: dict
    log: dict
    tracks: dict
    tm: TakeMap
    sb: dict           # take_storyboard


def read_take(sb: dict, key: str, path: str, scan: dict, log: dict, tracks: dict | None) -> Take:
    tsb = take_storyboard(sb, log)
    tm = editlist.locate(scan, log, tsb, False, tracks)
    return Take(key, path, scan, log, tracks or {}, tm, tsb)


def take_key(scene: dict) -> str:
    return scene["take_path"] + "|" + scene["gestures_path"]


# ---- a scene's pieces ----------------------------------------------------------

@dataclass
class Run:
    """A continuous stretch of one take inside a scene: what lies between
    two in-scene dissolves (or the scene's ends)."""
    items: list[dict]
    lead_in_s: float


def runs_of(scene: dict, timing: dict) -> tuple[list[Run], list[dict]]:
    keep = scene["keep"]
    runs: list[Run] = [Run([], scene.get("lead_in_s", timing["lead_in_s"]))]
    dissolves: list[dict] = []
    for item in keep:
        if "dissolve" in item:
            dissolves.append(item)
            runs.append(Run([], item.get("lead_in_s", timing["lead_in_s"])))
        else:
            runs[-1].items.append(item)
    return runs, dissolves


def _ticks(seconds: float, T: int, what: str) -> int:
    t = seconds * T
    if abs(t - round(t)) > 1e-6:
        raise Refusal("E_GRID", f"{what} = {seconds} s is not a whole tick of the take")
    return round(t)


def run_gestures(run: Run, take: Take, sid: str) -> list[editlist.Located]:
    """The located gestures a run shows: the ones it names, and every one a
    stretch by times holds. In the take's order, which must be the
    storyboard's."""
    tm, T = take.tm, take.tm.timescale
    named = [item["gesture"] for item in run.items if "gesture" in item]
    known = {g.gesture for g in tm.gestures}
    for gid in named:
        if gid not in known:
            raise Refusal("E_SCENE", f"scene {sid} names gesture `{gid}`, which its take's log does not have "
                                     f"(it has: {', '.join(dict.fromkeys(g.gesture for g in tm.gestures))})")
    order = list(dict.fromkeys(g.gesture for g in tm.gestures))
    if [g for g in order if g in named] != named:
        raise Refusal("E_SCENE", f"scene {sid} names {named}, not in its take's order")
    ids = set(named)
    for item in run.items:
        if "from_s" in item:
            a, b = _ticks(item["from_s"], T, f"scene {sid}: from_s"), _ticks(item["to_s"], T, f"scene {sid}: to_s")
            ids |= {g.gesture for g in tm.gestures if g.down < b and g.last_change >= a}
    return [g for g in tm.gestures if g.gesture in ids]


def grounds(scene: dict) -> dict[str, str]:
    return {item["gesture"]: item.get("ground", "light") for item in scene["keep"] if "gesture" in item}


# ---- proposing -----------------------------------------------------------------

def propose(sb: dict, takes: dict[str, Take]) -> dict:
    """The plan of the film: for each scene its runs of segments (v1's
    `live` and `hold`), its declared dissolve and its touch points; the
    joins, the end card and the poster frame."""
    from brand import motion
    fps = sb["film"]["fps"]
    plan_scenes = []
    for scene in sb["scenes"]:
        take = takes[take_key(scene)]
        tm, T = take.tm, take.tm.timescale
        step = T // fps
        runs, dissolves = runs_of(scene, sb["timing"])
        out_runs = []
        for k, run in enumerate(runs):
            # (`load` puts a dissolve only between two things shown: no run is empty)
            shown = run_gestures(run, take, scene["id"])
            pieces: list[tuple[int, int, int, str]] = []          # (in, out, rest frames, why)
            named = [g for g in shown if any(i.get("gesture") == g.gesture for i in run.items)]
            if named:
                ranges = editlist.kept_ranges(tm, named, take.sb)
                for r in ranges:
                    last = r["gestures"][-1]
                    item = next(i for i in run.items if i.get("gesture") == last.gesture)
                    rest = whole_frames(item.get("rest_after_s", 0), fps, f"{scene['id']}/{last.gesture}.rest_after_s")
                    pieces.append((r["in"], r["out"], rest if last.last else 0, f"rest after {last.gesture}"))
            for item in run.items:
                if "from_s" in item:
                    a = _ticks(item["from_s"], T, f"scene {scene['id']}: from_s")
                    b = _ticks(item["to_s"], T, f"scene {scene['id']}: to_s")
                    if (b - a) % step:
                        raise Refusal("E_GRID", f"scene {scene['id']}: {item['from_s']}–{item['to_s']} s is not a "
                                                f"whole number of film frames")
                    rest = whole_frames(item.get("rest_after_s", 0), fps, f"{scene['id']}.rest_after_s")
                    pieces.append((a, b, rest, f"rest after the take's {item['from_s']:g}–{item['to_s']:g} s"))
            pieces.sort()
            lead = whole_frames(run.lead_in_s, fps, f"{scene['id']}.lead_in_s")
            segments: list[dict] = []
            if lead:
                segments.append({"kind": "hold", "src_at": pieces[0][0], "frames": lead,
                                 "why": "lead-in: the screen at rest" + (" after the dissolve" if k else "")})
            for a, b, rest, why in pieces:
                segments.append({"kind": "live", "src_in": a, "src_out": b})
                if rest:
                    segments.append({"kind": "hold", "src_at": b - step, "frames": rest, "why": why})
            out_runs.append({"segments": segments})
        plan_scene = {"id": scene["id"], "take": dict(take.scan.get("take", {})), "timescale": T, "fps": fps,
                      "runs": out_runs,
                      "dissolves": [{"token": d.get("dissolve") or sb["motion"]["dissolve"],
                                     "frames": motion(d.get("dissolve") or sb["motion"]["dissolve"]).frames(fps) - 1}
                                    for d in dissolves]}
        plan_scene["touches"] = scene_touches(plan_scene, scene, take)
        plan_scenes.append(plan_scene)
    joins = [{"after": s["id"], "to": nxt, "token": sb["motion"]["join" if nxt != "end" else "end_card"]}
             for s, nxt in zip(sb["scenes"], [x["id"] for x in sb["scenes"][1:]] + ["end"])]
    for j in joins:
        j["frames"] = motion(j["token"]).frames(fps) - 1
    plan = {"version": VERSION, "fps": fps, "rehearsal": sb["rehearsal"], "frame": sb["film"]["frame"],
            "scenes": plan_scenes, "joins": joins,
            "end_card": {"frames": whole_frames(sb["end_card"]["duration_s"], fps, "end_card.duration_s")}}
    plan["poster_frame"] = poster_frame(sb, plan)
    return plan


def run_spans(run: dict, T: int, fps: int) -> list[Span]:
    return spans({"segments": run["segments"]}, T, fps)


def scene_layout(plan_scene: dict) -> list[tuple[str, int, int]]:
    """The scene's frames, in order: ('run', k, frames) and ('dissolve', k,
    frames)."""
    T, fps = plan_scene["timescale"], plan_scene["fps"]
    out = []
    for k, run in enumerate(plan_scene["runs"]):
        if k:
            out.append(("dissolve", k - 1, plan_scene["dissolves"][k - 1]["frames"]))
        out.append(("run", k, sum(s.frames for s in run_spans(run, T, fps))))
    return out


def scene_frames(plan_scene: dict) -> int:
    return sum(n for _, _, n in scene_layout(plan_scene))


def run_starts(plan_scene: dict) -> list[int]:
    """The scene-local frame each run starts on."""
    starts, at = [], 0
    for kind, _, n in scene_layout(plan_scene):
        if kind == "run":
            starts.append(at)
        at += n
    return starts


def scene_touches(plan_scene: dict, scene: dict, take: Take) -> list[dict]:
    """Touch points in scene ticks (from the scene's first frame), run by
    run: version 1's `propose_touches` on the run, moved to where the run
    starts in the scene. A touch is named `scene/gesture`."""
    T, fps = plan_scene["timescale"], plan_scene["fps"]
    step = T // fps
    runs, _ = runs_of(scene, {"lead_in_s": 0})
    out = []
    for run, prun, start in zip(runs, plan_scene["runs"], run_starts(plan_scene)):
        tm_run = dataclasses.replace(take.tm, gestures=run_gestures(run, take, scene["id"]))
        for t in editlist.propose_touches(tm_run, run_spans(prun, T, fps), fps):
            moved = start * step
            t = {**t, "gesture": f"{scene['id']}/{t['gesture']}", "down": t["down"] + moved, "up": t["up"] + moved,
                 "path": [[round(p[0] + moved, 3), p[1], p[2]] for p in t["path"]]}
            if "step" in t:
                t["step"] = [v + moved for v in t["step"]]
            out.append(t)
    return out


# ---- the film's timeline -------------------------------------------------------

@dataclass
class Place:
    """Where a scene lands in the film."""
    id: str
    first: int        # its first film frame
    frames: int


def places(plan: dict) -> tuple[list[Place], list[tuple[int, int]], int, int]:
    """Each scene's place; each join's (first frame, frames); where the end
    card starts; the film's frame count."""
    out, joins, at = [], [], 0
    for s, j in zip(plan["scenes"], plan["joins"]):
        n = scene_frames(s)
        out.append(Place(s["id"], at, n))
        at += n
        joins.append((at, j["frames"]))
        at += j["frames"]
    end = at
    return out, joins, end, end + plan["end_card"]["frames"]


def picture_at(plan_scene: dict, local: int) -> tuple[int, int, int] | None:
    """(run, frame in run, source instant shown) at scene-local frame
    `local`, or None inside the scene's dissolve."""
    T, fps = plan_scene["timescale"], plan_scene["fps"]
    step = T // fps
    at = 0
    for kind, k, n in scene_layout(plan_scene):
        if local < at + n:
            if kind == "dissolve":
                return None
            i = local - at
            for s in run_spans(plan_scene["runs"][k], T, fps):
                if s.film_in <= i < s.film_in + s.frames:
                    return k, i, s.first + ((i - s.film_in) * step if s.kind == "live" else 0)
        at += n
    raise IndexError(local)


def touch_visible(touches: list[dict], local: int, step: int, out_ticks: int) -> list[str]:
    """The touch points on screen at scene-local frame `local`."""
    t = local * step
    return [x["gesture"] for x in touches if x["down"] <= t < x["up"] + out_ticks]


def at_rest(tm: TakeMap, instant: int, tail: int) -> int | None:
    """None when the take has not changed for `tail` up to `instant`; else
    the last change in that time."""
    near = [p for p in tm.changes if instant - tail < p <= instant]
    return near[-1] if near else None


def poster_frame(sb: dict, plan: dict) -> int:
    poster = sb["film"]["poster"]
    where = next(p for p in places(plan)[0] if p.id == poster["scene"])
    return where.first + whole_frames(poster["at_s"], sb["film"]["fps"], "film.poster.at_s")


# ---- checking ------------------------------------------------------------------

def check(plan: dict, sb: dict, takes: dict[str, Take], diffs: dict | None = None,
          bands: dict[str, list[float]] | None = None) -> dict:
    """Refuse a plan that breaks a rule. `diffs`: for each scene and run, the
    comparisons of both sides of every cut (`conform diff`), keyed
    (scene id, run) — without them the cut endpoints are not compared.
    `bands`: in the full-bleed frame, each scene's caption band in device
    points [x0, y0, x1, y1] — the band must not cover a touch. Returns what
    the log needs: each scene's place, the joins, the end card."""
    from brand import motion
    fps = sb["film"]["fps"]
    if plan.get("version") != VERSION:
        raise Refusal("E_PLAN", "a plan of scenes says \"version\": 2")
    if bool(plan.get("rehearsal")) != sb["rehearsal"]:
        raise Refusal("E_PLAN", "the plan and the storyboard disagree on whether this is a rehearsal")
    if plan.get("frame") not in FRAMES:
        raise Refusal("E_PLAN", f"the plan's frame is one of {', '.join(FRAMES)}")
    if [s.get("id") for s in plan.get("scenes", [])] != [s["id"] for s in sb["scenes"]]:
        raise Refusal("E_PLAN", f"the plan's scenes are not the storyboard's: "
                                f"{[s.get('id') for s in plan.get('scenes', [])]}")
    out_ticks_token = motion(sb["motion"]["touch_out"])
    for scene, ps in zip(sb["scenes"], plan["scenes"]):
        _check_scene(scene, ps, takes[take_key(scene)], sb, diffs, out_ticks_token, motion)

    # Joins: one after each scene — the last into the end card — on the
    # storyboard's token, between two pictures at rest, no touch on either.
    want = [(s["id"], nxt, sb["motion"]["join" if nxt != "end" else "end_card"])
            for s, nxt in zip(sb["scenes"], [x["id"] for x in sb["scenes"][1:]] + ["end"])]
    have = [(j.get("after"), j.get("to"), j.get("token")) for j in plan.get("joins", [])]
    if have != want:
        raise Refusal("E_JOIN", f"the joins must be {want}")
    for j in plan["joins"]:
        if j.get("frames") != motion(j["token"]).frames(fps) - 1:
            raise Refusal("E_JOIN", f"the join after {j['after']} is {j.get('frames')} frames between its two "
                                    f"pictures; `{j['token']}` is {motion(j['token']).frames(fps) - 1}")
    for k, (scene, ps) in enumerate(zip(sb["scenes"], plan["scenes"])):
        take = takes[take_key(scene)]
        step = take.tm.timescale // fps
        tail = round(sb["timing"]["tail_s"] * take.tm.timescale)
        out_ticks = out_ticks_token.frames(fps) * step
        n = scene_frames(ps)
        ends = [("ends", n - 1, ps["runs"][-1]["segments"][-1])]
        if k:
            ends.append(("starts", 0, ps["runs"][0]["segments"][0]))
        for side, local, seg in ends:
            what = f"the join {'into' if side == 'starts' else 'after'} scene {ps['id']}"
            if seg.get("kind") != "hold":
                raise Refusal("E_JOIN", f"{what}: the scene {side} on footage that plays — a join is between two "
                                        f"pictures at rest; give the scene a "
                                        f"{'lead_in_s' if side == 'starts' else 'rest_after_s'}")
            pic = picture_at(ps, local)
            moving = at_rest(take.tm, pic[2], tail)
            if moving is not None:
                raise Refusal("E_JOIN", f"{what}: the picture ({pic[2] / take.tm.timescale:.3f} s of the take) is "
                                        f"not at rest — it changed at {moving / take.tm.timescale:.3f} s")
            on = touch_visible(ps["touches"], local, step, out_ticks)
            if on:
                raise Refusal("E_JOIN", f"{what}: the touch point of `{on[0]}` is still on screen — lengthen the "
                                        f"rest before the join")

    # The end card.
    lo, hi = (round(s * fps) for s in END_CARD_S)
    end_frames = plan.get("end_card", {}).get("frames")
    if end_frames != whole_frames(sb["end_card"]["duration_s"], fps, "end_card.duration_s") \
            or not lo <= end_frames <= hi:
        raise Refusal("E_END_CARD", f"the end card is {end_frames} frames; the storyboard says "
                                    f"{sb['end_card']['duration_s']} s, within {END_CARD_S[0]:g}–{END_CARD_S[1]:g} s")

    placed, joins, end_at, total = places(plan)
    # The film's length: Apple's 15 to 30 s.
    if not FILM_S[0] * fps <= total <= FILM_S[1] * fps:
        raise Refusal("E_LENGTH", f"the film is {total} frames ({total / fps:.3f} s); Apple takes "
                                  f"{FILM_S[0]} to {FILM_S[1]} s — " + "; ".join(
                                      f"{p.id} {p.frames / fps:.2f} s" for p in placed))

    # Captions: each is on screen whole for the scene it names, and read at
    # 17 characters a second at most (`caption_load`); one changes only at a
    # join, which is between pictures at rest (above); in the full-bleed
    # frame its band covers no touch.
    for c in caption_load(sb, plan):
        if c["frames"] * READING_CPS < c["characters"] * fps:
            raise Refusal("E_CAPTION", f"{c['what']} brings {c['characters']} characters and is whole for "
                                       f"{c['frames'] / fps:.2f} s: at {READING_CPS:g} characters a second it "
                                       f"needs {c['characters'] / READING_CPS:.2f} s")
    if plan["frame"] == "full-bleed":
        if bands is None:
            raise Refusal("E_CAPTION", "the full-bleed frame: the caption bands were not measured")
        radius = sb["touch"]["diameter_pt"] / 2
        for scene, ps in zip(sb["scenes"], plan["scenes"]):
            box = bands[scene["id"]]
            for t in ps["touches"]:
                for _, x, y in t["path"]:
                    if box[0] - radius < x < box[2] + radius and box[1] - radius < y < box[3] + radius:
                        raise Refusal("E_CAPTION", f"scene {scene['id']}: the caption band "
                                                   f"({box[1]:.0f}–{box[3]:.0f} pt from the top) covers the touch "
                                                   f"of `{t['gesture']}` at ({x:g}, {y:g}) pt — move the band "
                                                   f"(`band`: {', '.join(b for b in BANDS if b != scene['band'])})")

    # The poster: a picture at rest, in a scene, no touch on it.
    poster = plan.get("poster_frame")
    if poster != poster_frame(sb, plan):
        raise Refusal("E_POSTER", "the poster frame is not the storyboard's")
    home = next((p for p in placed if p.first <= poster < p.first + p.frames), None)
    if home is None or home.id != sb["film"]["poster"]["scene"]:
        raise Refusal("E_POSTER", f"the poster frame ({poster / fps:.3f} s) is not in scene "
                                  f"{sb['film']['poster']['scene']} — `at_s` is past its end, and a join or the end "
                                  f"card is not a picture of the app")
    ps = next(s for s in plan["scenes"] if s["id"] == home.id)
    scene = next(s for s in sb["scenes"] if s["id"] == home.id)
    take = takes[take_key(scene)]
    step = take.tm.timescale // fps
    local = poster - home.first
    pic = picture_at(ps, local)
    if pic is None:
        raise Refusal("E_POSTER", f"the poster frame falls in scene {home.id}'s dissolve")
    moving = at_rest(take.tm, pic[2], round(sb["timing"]["tail_s"] * take.tm.timescale))
    on = touch_visible(ps["touches"], local, step, out_ticks_token.frames(fps) * step)
    if moving is not None or on:
        raise Refusal("E_POSTER", f"the poster frame ({poster / fps:.3f} s, scene {home.id}) is not a picture at "
                                  f"rest: " + (f"the touch point of `{on[0]}` is on it" if on else
                                               f"the screen changed at {moving / take.tm.timescale:.3f} s of the take"))
    return {"places": placed, "joins": joins, "end": end_at, "total": total}


def _check_scene(scene: dict, ps: dict, take: Take, sb: dict, diffs: dict | None, touch_out, motion) -> None:
    sid = scene["id"]
    tm, T, fps = take.tm, take.tm.timescale, sb["film"]["fps"]
    step = T // fps
    tail = round(sb["timing"]["tail_s"] * T)
    if ps.get("take") != take.scan.get("take", {}) or ps.get("timescale") != T or ps.get("fps") != fps:
        raise Refusal("E_TAKE", f"scene {sid}: the plan was made for another take (file, size or hash differs)")
    runs, dissolves = runs_of(scene, sb["timing"])
    if len(ps.get("runs", [])) != len(runs) or len(ps.get("dissolves", [])) != len(dissolves):
        raise Refusal("E_DISSOLVE", f"scene {sid}: the storyboard declares {len(dissolves)} dissolve(s) inside the "
                                    f"scene; the plan has {len(ps.get('dissolves', []))} — a scene skips footage only "
                                    f"where the storyboard says so")
    shown_all: list[tuple[int, int]] = []
    names: set[str] = set()
    for k, (run, prun) in enumerate(zip(runs, ps["runs"])):
        mine = run_gestures(run, take, sid)
        ids = {g.gesture for g in mine}
        names |= ids
        edit_like = {"segments": prun.get("segments"), "take": ps["take"], "timescale": ps["timescale"],
                     "fps": ps["fps"]}
        # version 1's rule, on this run: every gesture it shows plays whole
        sp, _ = editlist.check_take(edit_like, take.scan, tm, take.sb,
                                    None if diffs is None else diffs.get((sid, k), {}), ids)
        shown_all += editlist.shown(sp, step)
    # Nothing of a gesture the scene does not name.
    for g in tm.gestures:
        if g.gesture in names:
            continue
        for a, b in shown_all:
            seen = [p for p in tm.changes if a <= p <= b and g.first_change <= p <= g.last_change]
            if seen:
                raise Refusal("E_SCENE", f"scene {sid} shows the answer to `{g.id}` ({seen[0] / T:.3f} s of the "
                                         f"take), a gesture it does not name — name it, or end the scene before it")
    # The declared dissolve: forward in the take, from a picture at rest to a
    # picture at rest, on its token, no touch point on either picture.
    out_ticks = touch_out.frames(fps) * step
    layout = scene_layout(ps)
    at = 0
    for kind, k, n in layout:
        if kind == "dissolve":
            d = ps["dissolves"][k]
            token = dissolves[k].get("dissolve") or sb["motion"]["dissolve"]
            if d.get("token") != token or d.get("frames") != motion(token).frames(fps) - 1:
                raise Refusal("E_DISSOLVE", f"scene {sid}: the dissolve is `{token}`, "
                                            f"{motion(token).frames(fps) - 1} frames between its two pictures")
            before, after = ps["runs"][k]["segments"], ps["runs"][k + 1]["segments"]
            if before[-1].get("kind") != "hold" or after[0].get("kind") != "hold":
                raise Refusal("E_DISSOLVE", f"scene {sid}: a dissolve is between two pictures at rest — the run "
                                            f"before it ends, and the one after it starts, on a hold")
            a, b = picture_at(ps, at - 1)[2], picture_at(ps, at + n)[2]
            if b <= a:
                raise Refusal("E_ORDER", f"scene {sid}: the dissolve goes back in the take ({b / T:.3f} s after "
                                         f"{a / T:.3f} s)")
            for side, instant in (("from", a), ("to", b)):
                moving = at_rest(tm, instant, tail)
                if moving is not None:
                    raise Refusal("E_DISSOLVE", f"scene {sid}: the dissolve's « {side} » picture "
                                                f"({instant / T:.3f} s of the take) is not at rest — it changed at "
                                                f"{moving / T:.3f} s")
            for local in (at - 1, at + n):
                on = touch_visible(ps["touches"], local, step, out_ticks)
                if on:
                    raise Refusal("E_DISSOLVE", f"scene {sid}: the touch point of `{on[0]}` is on a picture of the "
                                                f"dissolve")
        at += n
    # Touch points sit where the data puts them.
    if ps.get("touches") != scene_touches(ps, scene, take):
        raise Refusal("E_TOUCH", f"scene {sid}: the touch points are not where the take and the gesture log put "
                                 f"them")


def caption_load(sb: dict, plan: dict) -> list[dict]:
    """What each caption brings, and for how long it is whole on screen: a
    scene's caption from the end of the join into it (or the film's first
    frame) to the start of the join out of it; the end card's line for the
    end card. The end card's title, « MyWeli Pro », is the product's name
    set beside its mark — a name, not a sentence to read — and is not
    counted."""
    placed, _, end_at, total = places(plan)
    out = []
    for scene, p in zip(sb["scenes"], placed):
        text = " ".join([" ".join(scene["headline"])] + ([" ".join(scene["subline"])] if scene["subline"] else []))
        out.append({"what": f"scene {scene['id']}'s caption", "scene": scene["id"], "characters": len(text),
                    "frames": p.frames})
    out.append({"what": "the end card's line", "scene": "end", "characters": len(sb["end_card"]["line"]),
                "frames": total - end_at})
    return out


# ---- the log a person reads ----------------------------------------------------

def describe(plan: dict, sb: dict, takes: dict[str, Take], diffs: dict | None = None) -> str:
    """cuts.txt: each scene's take, gestures, kept ranges, holds, cuts and
    dissolve; the joins; where each scene lands against its budget; the
    captions' reading speed; the poster."""
    fps = sb["film"]["fps"]
    placed, joins, end_at, total = places(plan)
    lines: list[str] = []
    w = lines.append
    if sb["rehearsal"]:
        w("REHEARSAL — a storyboard marked rehearsal; this is not the film.")
    w(f"film   {total} frames, {total / fps:.3f} s ({FILM_S[0]}–{FILM_S[1]} s); frame: {plan['frame']}; "
      f"{len(plan['scenes'])} scene(s), then the end card")
    w("")
    w("where each scene lands (the storyboard's budget is a target)")
    for scene, p in zip(sb["scenes"], placed):
        budget = scene.get("budget_s")
        diff = "" if budget is None else f"  budget {budget:g} s, {p.frames / fps - budget:+.2f} s"
        w(f"  {p.id:<4} film {p.first / fps:6.3f} – {(p.first + p.frames) / fps:6.3f} s  {p.frames / fps:5.2f} s"
          f"{diff}  {scene.get('what', '')}")
    for (at, n), j in zip(joins, plan["joins"]):
        w(f"  join film {at / fps:6.3f} – {(at + n) / fps:6.3f} s  {j['token']}: {n} frames between the last "
          f"picture of {j['after']} and the first of {j['to'] if j['to'] != 'end' else 'the end card'}")
    w(f"  end  film {end_at / fps:6.3f} – {total / fps:6.3f} s  the end card, {(total - end_at) / fps:.2f} s")
    w("")
    for scene, ps, p in zip(sb["scenes"], plan["scenes"], placed):
        take = takes[take_key(scene)]
        lines.extend(_describe_scene(scene, ps, p, take, sb, (diffs or {}), fps))
        w("")
    w("captions (whole on screen, at most 17 characters a second)")
    for c in caption_load(sb, plan):
        w(f"  {c['what']:<28} {c['characters']:3d} characters, whole for {c['frames'] / fps:5.2f} s "
          f"({c['characters'] * fps / max(c['frames'], 1):.1f} a second)")
    w("  the end card's title, « " + sb["end_card"]["title"] + " », is the name beside the mark: not counted")
    pf = plan["poster_frame"]
    w(f"poster frame: film {pf / fps:.3f} s (frame {pf}), scene {sb['film']['poster']['scene']}, "
      f"{sb['film']['poster']['at_s']:g} s into it")
    return "\n".join(lines) + "\n"


def _describe_scene(scene: dict, ps: dict, p: Place, take: Take, sb: dict, diffs: dict, fps: int) -> list[str]:
    tm, T = take.tm, take.tm.timescale
    step = T // fps
    rest = round(sb["timing"]["rest_s"] * T)
    frames = take.scan["frames"]
    out: list[str] = []
    w = out.append

    def s(t: float) -> str:
        return f"{t / T:7.3f} s"

    meta = take.scan.get("take", {})
    w(f"scene {ps['id']} — « {' '.join(scene['headline'])} »")
    w(f"  take   {meta.get('file', '?')}  sha256 {str(meta.get('sha256', '?'))[:16]}…  {len(frames)} frames, "
      f"{take.scan['video']['duration_ticks'] / T:.3f} s")
    runs, dissolves = runs_of(scene, sb["timing"])
    named = {g.gesture for r in runs for g in run_gestures(r, take, scene["id"])}
    for g in tm.gestures:
        if g.gesture in named:
            d = "" if g.distance_pt is None else f"  first change {g.distance_pt:.0f} pt from the touch"
            w(f"  {g.id:<18} {g.kind:<5} touch-down {s(g.down)}  first change {s(g.first_change)}  last change "
              f"{s(g.last_change)}{d}")
            if g.how:
                w(f"  {'':<18} {g.how}")
    at = p.first
    for kind, k, n in scene_layout(ps):
        if kind == "dissolve":
            a = picture_at(ps, at - p.first - 1)[2]
            b = picture_at(ps, at - p.first + n)[2]
            skipped = [g.id for g in tm.gestures if a < g.first_change <= b]
            w(f"  film {at / fps:6.3f} – {(at + n) / fps:6.3f} s  DISSOLVE {ps['dissolves'][k]['token']}  "
              f"{n} frames from the picture at take {s(a)} to the picture at take {s(b)}: the take's {s(a)} – {s(b)} "
              f"is skipped, declared ({', '.join(skipped) or 'no gesture'} in it)")
            at += n
            continue
        sp = run_spans(ps["runs"][k], T, fps)
        for seg, x in zip(ps["runs"][k]["segments"], sp):
            t0 = (at + x.film_in) / fps
            t1 = (at + x.film_in + x.frames) / fps
            if x.kind == "live":
                repeats, shown_n = editlist.sampling(tm.changes, x.src_in, x.frames, step, rest)
                had = sum(1 for c in tm.changes if x.src_in <= c <= x.last)
                w(f"  film {t0:6.3f} – {t1:6.3f} s  LIVE  take {s(x.src_in)} – {s(x.src_out)}  ({x.frames} frames, "
                  f"1:1)  shows {shown_n} of the take's {had} changed pictures, {repeats} twice while it moved")
            else:
                w(f"  film {t0:6.3f} – {t1:6.3f} s  HOLD  the picture at take {s(x.first)}  ({x.frames} frames)  "
                  f"{seg.get('why', '')}")
        for a, b in zip(sp, sp[1:]):
            if b.first <= a.last:
                continue
            inside = [(f, kk) for f, kk in zip(frames, tm.kinds) if a.last < f["pts"] <= b.first]
            q = sum(1 for _, kk in inside if kk == "quiet")
            c = sum(1 for _, kk in inside if kk == "caret")
            x = sum(1 for _, kk in inside if kk == "change")
            line = f"  cut  take {s(a.last)} – {s(b.first)} removed, lands on film {(at + b.film_in) / fps:6.3f} s: " \
                   f"{q} quiet frames, {c} caret-only" + (f", {x} CHANGE FRAMES" if x else "")
            ja, jb = held(tm.pts, a.last), held(tm.pts, b.first)
            pair = diffs.get((ps["id"], k), {}).get((ja, jb))
            if ja == jb:
                line += "; the same frame on both sides"
            elif pair:
                line += (f"; frame {ja} against frame {jb}: soft {pair.get('soft', 0)}, strong "
                         f"{pair.get('strong', 0)} ({editlist.pair_kind(pair, tm, jb)})")
            w(line)
        at += n
    for t in ps["touches"]:
        w(f"  touch film {(p.first * step + t['down']) / T:6.3f} – {(p.first * step + t['up']) / T:6.3f} s  "
          f"{t['kind']:<5} {t['gesture']}  from ({t['path'][0][1]:g}, {t['path'][0][2]:g}) pt"
          + (f" to ({t['path'][-1][1]:g}, {t['path'][-1][2]:g}) pt" if t["kind"] == "drag" else ""))
    for k, run in enumerate(runs):
        sp = run_spans(ps["runs"][k], T, fps)
        for g in run_gestures(run, take, scene["id"]):
            if g.kind == "drag":
                steps = editlist.drag_steps(g, take.tracks.get(g.gesture), sp, step)
                if steps:
                    w(f"  drag {g.id:<14} " + " ".join(f"{v:g}" for v in steps)
                      + f"  (first step {steps[0]:g} pt; {sum(1 for v in steps if v == 0)} film frame(s) did "
                        f"not move)")
    return out
