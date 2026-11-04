"""The film's clock: what the soundtrack actually did, as frames.

The audio engine renders the cut's score first and writes events.json: every
bar, beat and named cue with the frame and sample its sound landed on. A
scene never types a time: it names a cue (``cue:swipe.touch``), a span's end
(``cue:riser1@end``), or a grid position (``3.1.2``, the storyboard's
``5.2&``), each optionally ``+N`` / ``-N`` frames, or ``end`` (the cut's
length). The clock resolves them, and refuses an events.json that is not on
the contract's grid (promo/timebase.py) — a soundtrack at another tempo
would put every word and cut on the wrong frame.
"""

from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any, Union

from .. import timebase as tb


class ClockError(ValueError):
    """An events.json the film cannot be timed by, or a time it cannot read."""


_CUE = re.compile(r"^cue:([^\s@+-][^\s@+]*?)(@end)?([+-]\d+)?$")
_POS = re.compile(r"^(\d+\.\d+(?:\.\d+|[e&a])?)([+-]\d+)?$")
_FRAME = re.compile(r"^f(\d+)$")

TimeRef = Union[int, str]


class Clock:
    """Frames of the cues and positions of one cut, from its events.json."""

    def __init__(self, events: dict, frames: int | None = None, timebase: tb.TimeBase = tb.DEFAULT):
        self.timebase = timebase
        problems = []
        if events.get("fps") != timebase.fps:
            problems.append(f"fps {events.get('fps')!r}, the contract's is {timebase.fps}")
        if float(events.get("bpm", 0)) != float(timebase.bpm):
            problems.append(f"bpm {events.get('bpm')!r}, the contract's is {float(timebase.bpm):g}")
        if events.get("sample_rate") != timebase.sample_rate:
            problems.append(f"sample rate {events.get('sample_rate')!r}, the contract's is {timebase.sample_rate}")
        n = events.get("frames")
        if frames is not None and n != frames:
            problems.append(f"{n!r} frames; the cut has {frames}")
        for b in events.get("beats", []):
            try:
                want = timebase.frame(b["pos"])
            except tb.TimeBaseError as e:
                problems.append(f"beat {b.get('pos')!r}: {e}")
                continue
            if b.get("frame") != want or b.get("sample") != timebase.sample(want):
                problems.append(f"beat {b['pos']} is on frame {b.get('frame')}, sample {b.get('sample')}; "
                                f"the grid says {want}, {timebase.sample(want)}")
        self.cues: dict[str, dict] = {}
        for c in events.get("cues", []):
            if c["id"] in self.cues:
                problems.append(f"cue {c['id']!r} twice")
            if c.get("sample") != timebase.sample(c.get("frame", -1) if c.get("frame", -1) >= 0 else 0) \
                    or c.get("frame", -1) < 0:
                problems.append(f"cue {c['id']!r}: frame {c.get('frame')} and sample {c.get('sample')} disagree")
            self.cues[c["id"]] = c
        if problems:
            raise ClockError("events.json: " + "; ".join(problems))
        self.events = events
        self.frames: int = int(n)
        self.cut: str = events.get("cut", "?")

    @classmethod
    def load(cls, path: Union[str, Path], frames: int | None = None) -> "Clock":
        return cls(json.loads(Path(path).read_text(encoding="utf-8")), frames)

    def cue(self, cue_id: str) -> dict:
        try:
            return self.cues[cue_id]
        except KeyError:
            raise ClockError(f"no cue {cue_id!r} in events.json (the score did not render it)") from None

    def frame(self, ref: TimeRef) -> int:
        """The frame a time reference names (see the module doc)."""
        if isinstance(ref, bool):
            raise ClockError(f"{ref!r} is not a time")
        if isinstance(ref, int):
            return ref
        if not isinstance(ref, str):
            raise ClockError(f"{ref!r} is not a time: write cue:<id>, a position bar.beat.step, or end")
        text = ref.strip()
        if text == "end":
            return self.frames
        m = _CUE.match(text)
        if m:
            c = self.cue(m.group(1))
            if m.group(2):
                if "end_frame" not in c:
                    raise ClockError(f"{text}: cue {m.group(1)!r} is not a span (no end)")
                f = c["end_frame"]
            else:
                f = c["frame"]
            return f + int(m.group(3) or 0)
        m = _POS.match(text)
        if m:
            try:
                return self.timebase.frame(m.group(1)) + int(m.group(2) or 0)
            except tb.TimeBaseError as e:
                raise ClockError(f"{text}: {e}") from None
        m = _FRAME.match(text)
        if m:
            return int(m.group(1))
        raise ClockError(f"{text!r} is not a time: write cue:<id>, cue:<id>@end, a position bar.beat.step "
                         f"(±N frames), or end")

    def label(self, frame: int) -> str:
        """« f144 · 4.800 s · 3.2.0 » (« +1 » past the 16th when off it)."""
        pos, extra = self.timebase.split_frame(frame)
        return f"f{frame} · {frame / self.timebase.fps:.3f} s · {pos}" + (f"+{extra}" if extra else "")

    def cues_of_kind(self, *kinds: str) -> list[dict]:
        return [c for c in self.cues.values() if c.get("kind") in kinds]


def as_list(value: Any) -> list:
    return value if isinstance(value, list) else [value]
