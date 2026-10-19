"""events.json — the clock SCENES animates to, written from what was RENDERED.

The architecture contract's shape, plus a few fields SCENES may use::

    {"cut": "30s", "fps": 30, "bpm": 112.5, "sample_rate": 48000,
     "frames": 896, "samples": 1433600, "score": "score_30s.yaml", "key": "C minor",
     "bars":  [{"bar": 1, "frame": 0, "sample": 0}, ...],
     "beats": [{"pos": "1.1.0", "frame": 0, "sample": 0}, ...],
     "sections": [{"name": "hook", "bars": [1, 2], "frame": 0, "end_frame": 128}, ...],
     "chords": [{"pos": "1.1.0", "frame": 0, "chord": "Cm9"}, ...],
     "cues": [{"id": "hook.stab", "kind": "log", "pos": "1.1.0", "frame": 0, "sample": 0}, ...]}

A cue's ``frame`` and ``sample`` are read from the arranger's placement log:
the sample its sound's first sample was written at. They are checked against
the score — on a whole frame, at the score's ``pos`` (+ ``offset``) — and
any disagreement is an error, never a silent correction. Off-grid cues (real
UI timings) carry ``offset_frames``; spans carry ``end_frame``/``end_sample``
(and ``end_pos`` when written as a position).
"""

from __future__ import annotations

import json
from pathlib import Path

from . import _time as tb
from .arrange import Render


class EventsError(RuntimeError):
    pass


def build(render: Render) -> dict:
    score = render.score
    n = render.samples
    if n % tb.SAMPLES_PER_FRAME:
        raise EventsError(f"the render is {n} samples, not a whole number of frames")
    frames = n // tb.SAMPLES_PER_FRAME
    if frames != score.frames:
        raise EventsError(f"the render is {frames} frames, the score {score.frames}")

    bars = [{"bar": b, "frame": tb.frame_of(b), "sample": tb.sample_of_frame(tb.frame_of(b))}
            for b in range(1, score.bars + 1)]
    beats = []
    for b in range(1, score.bars + 1):
        for k in range(1, tb.BEATS_PER_BAR + 1):
            p = tb.Pos(b, k, 0)
            beats.append({"pos": str(p), "frame": p.frame, "sample": p.sample})

    placed = {p.label: p for p in render.cue_placements()}
    cues = []
    for cue in score.cues:
        p = placed.get(cue.id)
        if p is None:
            raise EventsError(f"cue {cue.id!r} was not rendered")
        if p.sample % tb.SAMPLES_PER_FRAME:
            raise EventsError(f"cue {cue.id!r} landed on sample {p.sample}, between frames")
        frame = p.sample // tb.SAMPLES_PER_FRAME
        if frame != cue.frame:
            raise EventsError(f"cue {cue.id!r} landed on frame {frame}; the score puts it on {cue.frame}")
        entry = {"id": cue.id, "kind": cue.kind, "pos": str(cue.pos), "frame": frame, "sample": p.sample}
        if cue.offset:
            entry["offset_frames"] = cue.offset
        if p.end_sample is not None:
            if p.end_sample % tb.SAMPLES_PER_FRAME:
                raise EventsError(f"cue {cue.id!r} ends between frames")
            if cue.end is not None:
                entry["end_pos"] = str(cue.end)
            entry["end_frame"] = p.end_sample // tb.SAMPLES_PER_FRAME
            entry["end_sample"] = p.end_sample
        if p.length == 0:
            raise EventsError(f"cue {cue.id!r} wrote no audio (is it past the end?)")
        cues.append(entry)

    return {
        "cut": score.cut,
        "fps": tb.FPS,
        "bpm": tb.BPM,
        "sample_rate": tb.SAMPLE_RATE,
        "frames": frames,
        "samples": n,
        "score": score.source,
        "key": score.key,
        "bars": bars,
        "beats": beats,
        "sections": [{"name": s.name, "bars": [s.first_bar, s.last_bar], "frame": s.frame, "end_frame": s.end_frame}
                     for s in score.sections],
        "chords": [{"pos": str(c.pos), "frame": c.pos.frame, "chord": c.chord.symbol} for c in score.chords],
        "cues": cues,
    }


def write(path: str | Path, events: dict) -> None:
    Path(path).write_text(json.dumps(events, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
