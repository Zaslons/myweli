"""Touch-downs: when, in a take, a finger landed — and whether the film's
touch indicators sit on them.

The screen cannot show the instant a finger lands; the earliest evidence is
the first picture the app changes. The App Store tool's rule (its README,
« How a touch-down is found »), applied here to the same data:

  * the gesture log says when the driver asked for each gesture and when its
    call came back (``after_s``, ``before_s``); the gesture is the FIRST
    burst of changes that starts in between, after the previous gesture's;
  * a **tap** lands ``touch.tap_lead`` (motion token ``base``, 200 ms)
    before that burst's first changed picture;
  * a **drag** is timed by the picture: where the App Store tool followed it
    (``track.json``), the log's path re-timed by what the picture did
    (``edit.followed_path``); otherwise the logged path, counted back from
    the first moved picture by the time Flutter's 18-pt slop takes;
  * a **typed key** has no touch point (the key is not on the screen): its
    first changed picture is reported, and no indicator may sit on it. Its
    picture is the first change in its window that is more than a caret
    fragment — one addition to the App Store tool, whose film skipped the
    form fill and never had to find a key: in take1b the caret's foot passes
    the change threshold alone at 85.333 s, while the space lands at 87.548 s
    (the take's notes say the same).

What counts as a change (thresholds, the blinking caret) and how changes
form bursts is the App Store tool's own code — ``tool/app_store_preview/
edit.py`` (``read_frames``, ``find_bursts``, ``followed_path``) is imported,
not copied, and ``rest_s`` / ``tap_lead`` / ``touch_in`` are read from its
storyboard.json and from motion.dart. It needs the take's scan
(``final/takes/take-N/scan.json``): take1b, take2b, take3 and take5b have one.

``cross_check(rendered, touch_downs)`` holds a film's touch indicators to
them: every indicator must sit on an observed touch-down of a tap or a drag
(the honesty rule: « They sit only at observed touch-downs »), each at most
once, on the 16th grid.
"""

from __future__ import annotations

import functools
import importlib.util
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Sequence

from . import tools
from .takes import Take, TakeError, take_files
from ..timebase import DEFAULT as TIMEBASE

APP_STORE_STORYBOARD = tools.APP_STORE_PREVIEW / "storyboard.json"
MOTION_DART = tools.REPO / "mobile/lib/core/theme/motion.dart"


class TouchError(RuntimeError):
    """A gesture log, scan or track that does not give a touch-down."""


@functools.lru_cache(maxsize=None)
def app_store_edit():
    """The App Store tool's ``edit.py``, imported under its own name (it is
    not a package; nothing of it is copied here)."""
    path = tools.APP_STORE_PREVIEW / "edit.py"
    spec = importlib.util.spec_from_file_location("app_store_preview_edit", path)
    if spec is None or spec.loader is None:
        raise TouchError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules["app_store_preview_edit"] = module
    spec.loader.exec_module(module)
    return module


@dataclass(frozen=True)
class Rules:
    """The App Store tool's timing rules, read from where they live."""

    rest_s: float       # no change for this long ends a burst
    tap_lead_s: float   # a tap lands this long before the first changed picture
    touch_in_s: float   # a drag's point is whole this long before the first moved picture


@functools.lru_cache(maxsize=None)
def rules() -> Rules:
    sb = json.loads(APP_STORE_STORYBOARD.read_text(encoding="utf-8"))
    src = MOTION_DART.read_text(encoding="utf-8")
    durations = {k: int(v) for k, v in re.findall(r"static const Duration (\w+) = Duration\(milliseconds: (\d+)\);", src)}

    def token(name: str) -> float:
        if name not in durations:
            raise TouchError(f"motion token {name!r} is not in {MOTION_DART}")
        return durations[name] / 1000

    return Rules(rest_s=float(sb["timing"]["rest_s"]), tap_lead_s=token(sb["touch"]["tap_lead"]),
                 touch_in_s=token(sb["motion"]["touch_in"]))


@dataclass(frozen=True)
class TouchDown:
    """One gesture's touch-down in a take (seconds of the take)."""

    take: str
    gesture: str                 # the log's id; a typed key is `id[n]`
    kind: str                    # tap | drag | key
    down_s: float                # touch-down (a key: its first changed picture)
    first_change_s: float        # the first changed picture of the gesture's burst
    window_s: tuple[float, float]  # the log's (after_s, before_s)
    at_pt: tuple[float, float] | None  # where (a tap's point, a drag's start)
    how: str
    distance_pt: float | None = None   # touch point to the first change's box: large = suspicious

    @property
    def indicator(self) -> bool:
        """Whether a touch indicator may be drawn on it (taps and drags only)."""
        return self.kind in ("tap", "drag")


def load_gestures(take: str, root: Path | None = None) -> dict:
    """A take's gesture log, as gestures.json (the App Store tool's format).
    When only gestures.jsonl exists it is converted the way
    ``takes/convert_logs.py`` did (seconds = clock − t0). When both exist,
    they must agree to the millisecond."""
    files = take_files(take, root)
    from_jsonl = _from_jsonl(files.gestures_jsonl) if files.gestures_jsonl else None
    if files.gestures_json:
        doc = json.loads(files.gestures_json.read_text(encoding="utf-8"))
        if from_jsonl is not None:
            _same_log(doc, from_jsonl, take)
        return doc
    if from_jsonl is None:
        raise TouchError(f"{take}: no gestures.json or gestures.jsonl in {files.folder}")
    return from_jsonl


def _from_jsonl(path: Path) -> dict:
    lines = [l for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    t0 = float(lines[0])
    calls: list[dict] = []
    for line in lines[1:]:
        d = json.loads(line)
        if "t_after" in d:
            calls[-1]["t_after"] = d["t_after"]
        else:
            calls.append(d)
    out: list[dict] = []
    for c in calls:
        after, before = round(c["t"] - t0, 3), round(c["t_after"] - t0, 3)
        if c["kind"] == "key":
            if out and out[-1]["kind"] == "type" and out[-1]["id"] == c["id"]:
                out[-1]["keys"].append({"after_s": after, "before_s": before, "text": c["text"]})
            else:
                out.append({"id": c["id"], "kind": "type",
                            "keys": [{"after_s": after, "before_s": before, "text": c["text"]}]})
        elif c["kind"] == "tap":
            out.append({"id": c["id"], "kind": "tap", "after_s": after, "before_s": before,
                        "at": list(c["points"][0])})
        elif c["kind"] == "drag":
            out.append({"id": c["id"], "kind": "drag", "after_s": after, "before_s": before,
                        "path": [[p[0], p[1], i * c["dt_ms"]] for i, p in enumerate(c["points"])]})
        else:
            raise TouchError(f"{path}: unknown gesture kind {c['kind']!r}")
    return {"device_points": [402, 874], "gestures": out}


def _same_log(a: dict, b: dict, take: str) -> None:
    def times(doc: dict) -> list[tuple[str, float, float]]:
        rows = []
        for g in doc["gestures"]:
            for k in g.get("keys", [g]):
                rows.append((g["id"], round(k["after_s"], 3), round(k["before_s"], 3)))
        return rows
    if times(a) != times(b):
        raise TouchError(f"{take}: gestures.json and gestures.jsonl disagree")


def touch_downs(take: str | Take, root: Path | None = None) -> list[TouchDown]:
    """Every gesture of a take with its touch-down, in the take's order."""
    name = take.name if isinstance(take, Take) else str(take)
    files = take_files(name, root)
    if files.scan is None:
        raise TouchError(f"{name}: no scan of this take (final/takes/take-N/scan.json); "
                         f"the touch-downs are found on the App Store tool's scan")
    tk = take if isinstance(take, Take) else Take(name, root=root)
    scan = tk.scan if tk.scan is not None else json.loads(files.scan.read_text(encoding="utf-8"))
    tracks = json.loads(files.track.read_text(encoding="utf-8")) if files.track else {}
    log = load_gestures(name, root)
    return _locate(name, scan, log, tracks)


def _locate(name: str, scan: dict, log: dict, tracks: dict) -> list[TouchDown]:
    edit = app_store_edit()
    r = rules()
    T = scan["video"]["timescale"]
    points = log.get("device_points") or [402, 874]
    px_per_pt = scan["video"]["width"] / points[0]
    rest = round(r.rest_s * T)
    kinds = edit.read_frames(scan, px_per_pt, rest).kinds
    bursts = edit.find_bursts(scan, kinds, rest)
    used = -1
    out: list[TouchDown] = []
    for g in log.get("gestures", []):
        if not g.get("film", True):
            continue
        gid, kind = g["id"], g["kind"]
        pieces = g["keys"] if kind == "type" else [g]
        for n, piece in enumerate(pieces, 1):
            pid = gid if len(pieces) == 1 else f"{gid}[{n}]"
            lo, hi = round(piece["after_s"] * T), round(piece["before_s"] * T)
            cands = [b for b in bursts if lo <= b.start <= hi and b.index > used]
            if not cands:
                raise TouchError(f"{name} `{pid}`: nothing starts changing between {piece['after_s']} s and "
                                 f"{piece['before_s']} s")
            b = cands[0]
            first_frame = b.first
            skipped = []
            if kind == "type":
                # A key's picture is the first change that is more than a
                # caret fragment: the caret's foot (1 × 1 pt, 5 strong
                # pixels) can pass the change threshold on its own while the
                # caret blinks before the key lands (take1b's space: a
                # fragment at 85.333 s, the caret moving at 87.548 s).
                found = _first_real_change(scan, kinds, cands, px_per_pt, edit)
                if found is None:
                    raise TouchError(f"{name} `{pid}`: only caret fragments change between {piece['after_s']} s "
                                     f"and {piece['before_s']} s")
                b, first_frame = found
                skipped = [round(c.start / T, 3) for c in cands if c.start < scan["frames"][first_frame]["pts"]]
            used = b.index
            first = scan["frames"][first_frame]["pts"]
            box = scan["frames"][first_frame].get("box")
            window = (float(piece["after_s"]), float(piece["before_s"]))
            if kind == "tap":
                at = tuple(g["at"])
                down = first - round(r.tap_lead_s * T)
                out.append(TouchDown(name, pid, "tap", down / T, first / T, window, at,
                                     f"first changed picture {first / T:.3f} s − {r.tap_lead_s * 1000:.0f} ms",
                                     _distance(box, at, px_per_pt)))
            elif kind == "drag":
                path = g["path"]
                at = (float(path[0][0]), float(path[0][1]))
                track = tracks.get(gid)
                seen = (edit.followed_path(path, track, T)
                        if track and track.get("frames") and "down_s" not in g else None)
                if "down_s" in g:
                    down = round(g["down_s"] * T)
                    how = "the log's own `down_s`"
                elif seen:
                    down = min(math.floor(seen["down"]), first - round(r.touch_in_s * T))
                    a, z, reach = seen["reach"]
                    how = (f"followed in the picture on {seen['frames']} pictures ({a:.1f}→{z:.1f} of "
                           f"{reach:.0f} pt): first moved picture {first / T:.3f} s")
                else:
                    slop_ms = edit._slop_time_ms(path)
                    down = first - round(slop_ms * T / 1000)
                    how = (f"NOT followed in the picture: first moved picture {first / T:.3f} s − "
                           f"{slop_ms:.0f} ms (the logged path to Flutter's {edit.DRAG_SLOP_PT:g}-pt slop)")
                out.append(TouchDown(name, pid, "drag", down / T, first / T, window, at, how,
                                     _distance(box, at, px_per_pt)))
            elif kind == "type":
                note = f"; caret fragment{'s' if len(skipped) > 1 else ''} at {', '.join(map(str, skipped))} s skipped" \
                    if skipped else ""
                out.append(TouchDown(name, pid, "key", first / T, first / T, window, None,
                                     f"key {piece.get('text', '?')!r}: first changed picture (no touch point){note}"))
            else:
                raise TouchError(f"{name} `{gid}`: unknown kind {kind!r}")
    return out


def _first_real_change(scan: dict, kinds: list[str], bursts: list, px_per_pt: float, edit) -> tuple | None:
    """(burst, frame number) of the first change in ``bursts`` that is not a
    caret fragment (a caret-sized box with few soft pixels)."""
    frames = scan["frames"]
    for b in bursts:
        for i in range(b.first, b.last + 1):
            if kinds[i] != "change":
                continue
            f = frames[i]
            box = f.get("box")
            fragment = bool(box) and f.get("soft", 0) < edit.SOFT_MIN and edit._caret_sized(box, px_per_pt)
            if not fragment:
                return b, i
    return None


def _distance(box, at, px_per_pt) -> float | None:
    if not box:
        return None
    return app_store_edit()._box_distance_pt(box, at[0], at[1], px_per_pt)


def report(downs: Sequence[TouchDown]) -> str:
    """A table of touch-downs, one per line."""
    lines = [f"{'take':7} {'gesture':22} {'kind':5} {'down s':>9} {'1st chg s':>9}  how"]
    for d in downs:
        lines.append(f"{d.take:7} {d.gesture:22} {d.kind:5} {d.down_s:9.3f} {d.first_change_s:9.3f}  {d.how}"
                     + (f" · {d.distance_pt:.0f} pt from the change" if d.distance_pt else ""))
    return "\n".join(lines)


# ---- cross-check of a film's indicators ----------------------------------------------

@dataclass(frozen=True)
class RenderedTouch:
    """A touch indicator as a film draws it: the film frame its touch-down is
    drawn on, and the take time the film shows on that frame (from the
    renderer's own time map)."""

    take: str
    frame: int
    src_s: float
    gesture: str | None = None   # what the renderer believes it is, if it says


@dataclass(frozen=True)
class Match:
    rendered: RenderedTouch
    touch_down: TouchDown | None
    delta_ms: float | None
    on_grid: bool


@dataclass
class CrossCheck:
    matches: list[Match] = field(default_factory=list)
    problems: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.problems

    def report(self) -> str:
        lines = [f"{'frame':>6} {'take':7} {'src s':>9}  {'touch-down':22} {'Δ ms':>7}  grid"]
        for m in self.matches:
            td = m.touch_down
            lines.append(f"{m.rendered.frame:6d} {m.rendered.take:7} {m.rendered.src_s:9.3f}  "
                         f"{(td.gesture if td else '— none —'):22} "
                         f"{(f'{m.delta_ms:+7.1f}' if m.delta_ms is not None else '      —')}  "
                         f"{'yes' if m.on_grid else 'NO'}")
        lines += [f"PROBLEM: {p}" for p in self.problems] or ["OK: every indicator sits on an observed touch-down"]
        return "\n".join(lines)


def cross_check(rendered: Iterable[RenderedTouch], downs: Iterable[TouchDown], *,
                tolerance_ms: float = 1000 / 60, grid_frames: int | None = TIMEBASE.frames_per_step,
                required: Iterable[tuple[str, str]] = ()) -> CrossCheck:
    """Hold a film's touch indicators to the observed touch-downs.

    * each indicator must sit within ``tolerance_ms`` (default: half a film
      frame at 1×) of a tap's or drag's touch-down in the same take — never
      on a typed key, never between gestures;
    * if the indicator names its gesture, it must be that one;
    * no touch-down carries two indicators;
    * each indicator's frame is on the 16th grid (``grid_frames``; None: unchecked);
    * every ``(take, gesture)`` in ``required`` has an indicator."""
    result = CrossCheck()
    downs = list(downs)
    taken: dict[tuple[str, str], RenderedTouch] = {}
    for r in sorted(rendered, key=lambda r: r.frame):
        on_grid = grid_frames is None or r.frame % grid_frames == 0
        if not on_grid:
            result.problems.append(f"f{r.frame}: the indicator is not on the 16th grid "
                                   f"({r.frame % grid_frames} frame(s) past it)")
        same = [d for d in downs if d.take == r.take]
        if not same:
            result.problems.append(f"f{r.frame}: no touch-down is known in take {r.take!r}")
            result.matches.append(Match(r, None, None, on_grid))
            continue
        nearest = min(same, key=lambda d: abs(d.down_s - r.src_s))
        delta = (r.src_s - nearest.down_s) * 1000
        if abs(delta) > tolerance_ms:
            result.problems.append(f"f{r.frame}: {r.take} {r.src_s:.3f} s has no observed touch-down within "
                                   f"{tolerance_ms:.1f} ms (nearest: {nearest.gesture} at {nearest.down_s:.3f} s, "
                                   f"{delta:+.1f} ms)")
            result.matches.append(Match(r, None, delta, on_grid))
            continue
        if not nearest.indicator:
            result.problems.append(f"f{r.frame}: {nearest.gesture} is a typed key: no touch point may be drawn")
        if r.gesture is not None and r.gesture != nearest.gesture:
            result.problems.append(f"f{r.frame}: drawn as {r.gesture!r}, but the touch-down there is "
                                   f"{nearest.gesture!r}")
        key = (nearest.take, nearest.gesture)
        if key in taken:
            result.problems.append(f"f{r.frame}: {nearest.gesture} already has an indicator at f{taken[key].frame}")
        taken[key] = r
        result.matches.append(Match(r, nearest, delta, on_grid))
    for take, gesture in required:
        if (take, gesture) not in taken:
            result.problems.append(f"{take} {gesture}: no indicator in the film")
    return result


def main(argv: Sequence[str] | None = None) -> int:
    """``python -m promo.media.touches TAKE [TAKE…]`` — the touch-downs of each take."""
    import argparse
    ap = argparse.ArgumentParser(prog="python -m promo.media.touches", description=main.__doc__)
    ap.add_argument("takes", nargs="+")
    args = ap.parse_args(argv)
    rows: list[TouchDown] = []
    for name in args.takes:
        try:
            rows += touch_downs(name)
        except (TouchError, TakeError) as e:
            print(f"{name}: {e}", file=sys.stderr)
            return 1
    print(report(rows))
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
