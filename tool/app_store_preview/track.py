"""Where the finger is during a drag — read from the picture.

A gesture log says where a drag went. It cannot say when: its times are the
ones the driver ASKED for. On the rehearsal take of 2026-10-13 drags logged
at 16 ms a sample reached the app at 25 to 29 ms a sample, and the first
frame of one came late. Timed by the log alone, the touch point trailed the
card it was dragging.

The picture knows better. While a finger drags something, what was under it
moves with it. So for every frame of a drag this module measures how far the
content that was under the finger at rest has moved along the drag's axis: a
patch of the resting picture around the touch-down point is looked for, shift
by shift, in the frame. `edit.followed_path` then places the logged path on
those frames.

Measured on that take: in every frame, the card under the swipe was as far
along as one of the logged samples to a third of a point, and the form under
the scroll to four points — the picture follows the finger with nothing lost
at the start. Where the picture stops following (a pane that is fully open, a
list at its end) or cannot be recognised, the log's own times take over, and
cuts.txt says so.

Nothing here touches the footage. It only decides where the touch point —
an overlay — is drawn.
"""

from __future__ import annotations

import json
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

import edit as editlist
import swifttools

PATCH_PT = (60.0, 24.0)   # half the patch looked for: along the drag, across it
MIN_TEXTURE = 6.0         # grey levels (standard deviation): under it there is nothing to recognise
MAX_ERROR = 6.0           # mean difference, in grey levels, between the patch and where it was found
BEYOND_PT = 40.0          # looked for this far past the end of the logged path
TURN_PT = 1.0             # the picture has turned back once it is this far behind its furthest
MAX_SECONDS = 3.0         # frames later than this after the first change are not looked at


def follow(ref: np.ndarray, frames, start_px: tuple[float, float], axis: str, sign: int,
           reach_px: float, px_per_pt: float) -> tuple[list[tuple[float, float]], str]:
    """How far the content under `start_px` has moved along `axis` in each
    frame, in pixels, with the match's error — and why the reading stops
    short, when it does. `ref` and each of `frames` (any iterable: they are
    large, one is held at a time) are grey pictures (float32)."""
    along, across = PATCH_PT[0] * px_per_pt, PATCH_PT[1] * px_per_pt
    half = (along, across) if axis == "x" else (across, along)
    h, w = ref.shape
    x0, x1 = max(0, round(start_px[0] - half[0])), min(w, round(start_px[0] + half[0]))
    y0, y1 = max(0, round(start_px[1] - half[1])), min(h, round(start_px[1] + half[1]))
    patch = ref[y0:y1, x0:x1]
    if patch.size == 0 or float(patch.std()) < MIN_TEXTURE:
        return [], "nothing to recognise under the finger: the picture there is flat"
    out: list[tuple[float, float]] = []
    limit = round(reach_px + BEYOND_PT * px_per_pt)
    for n, frame in enumerate(frames):
        best: tuple[float, int] | None = None
        for s in range(0, limit + 1):
            dx, dy = (sign * s, 0) if axis == "x" else (0, sign * s)
            if x0 + dx < 0 or y0 + dy < 0 or x1 + dx > w or y1 + dy > h:
                break
            error = float(np.abs(frame[y0 + dy:y1 + dy, x0 + dx:x1 + dx] - patch).mean())
            if best is None or error < best[0]:
                best = (error, s)
        if best is None or best[0] > MAX_ERROR:
            return out, f"lost after {n} frame{'' if n == 1 else 's'}: what was under the finger is not in the picture"
        out.append((float(best[1]), best[0]))
    return out, ""


def turned(frames: list[list[float]]) -> int | None:
    """When the picture turns back — the first frame clearly behind the
    furthest it had gone: a list springing back from its end, a card let go.
    The finger has left by then."""
    furthest = 0.0
    for pts, s in frames:
        if s < furthest - TURN_PT:
            return pts
        furthest = max(furthest, s)
    return None


def _grey(path: Path) -> np.ndarray:
    with Image.open(path) as im:
        return np.asarray(im.convert("L"), dtype=np.float32)


def read_drags(take: Path, scan: dict, log: dict, sb: dict, work: Path, rehearsal: bool = False) -> dict:
    """track.json: for each logged drag, how far the picture has followed in
    each frame of its burst of changes."""
    tm = editlist.locate(scan, log, sb, rehearsal)
    T, px = tm.timescale, tm.px_per_pt
    frames = scan["frames"]
    logged = {g["id"]: g for g in log.get("gestures", []) if g.get("film", True)}
    out: dict = {}
    for g in tm.gestures:
        if g.kind != "drag":
            continue
        path = logged[g.id]["path"]
        dx, dy = path[-1][0] - path[0][0], path[-1][1] - path[0][1]
        axis = "x" if abs(dx) >= abs(dy) else "y"
        sign = 1 if (dx if axis == "x" else dy) >= 0 else -1
        entry: dict = {"axis": axis, "sign": sign, "frames": [], "turn": None}
        out[g.id] = entry
        burst = tm.bursts[g.burst]
        # The picture at rest: the last one before the drag's first change.
        # There is one — `locate` refuses a take that begins on a gesture's
        # answer (E_NO_REST) — and the burst has at least its first frame.
        ref = editlist.held(tm.pts, burst.start - 1)
        wanted = [f["i"] for f, k in zip(frames, tm.kinds)
                  if k == "change" and burst.start <= f["pts"] <= min(burst.end, burst.start + MAX_SECONDS * T)]
        reach = abs(dx if axis == "x" else dy)
        # The pictures are only needed to measure: they are gone when this
        # returns, however it returns.
        with tempfile.TemporaryDirectory(prefix="follow-", dir=work) as tmp:
            folder = Path(tmp)
            segments = {"fps": sb["film"]["fps"], "segments": [
                {"kind": "hold", "src_at": frames[i]["pts"], "frames": 1} for i in [ref] + wanted]}
            (folder / "segments.json").write_text(json.dumps(segments), encoding="utf-8")
            swifttools.run("conform", "export", take, "--segments", folder / "segments.json", "--out", folder)
            manifest = json.loads((folder / "manifest.json").read_text(encoding="utf-8"))

            def picture(i: int) -> np.ndarray:
                return _grey(folder / manifest["sources"][str(i)]["file"])

            shifts, why = follow(picture(ref), (picture(i) for i in wanted),
                                 (path[0][0] * px, path[0][1] * px), axis, sign, reach * px, px)
        entry["ref"] = ref
        entry["frames"] = [[frames[i]["pts"], round(s / px, 3)] for i, (s, _) in zip(wanted, shifts)]
        entry["error"] = round(max((e for _, e in shifts), default=0.0), 2)
        if why:
            entry["why"] = why
        entry["turn"] = turned(entry["frames"])
    return out
