"""Load and validate a score (YAML) — the format is documented in SCORE.md.

A score is refused as a whole, with every problem listed and located
(``cues[12] 'drop1.impact': pos '15.1.0' is past the cut's 14 bars``), never
half-loaded. What comes out is plain data: positions resolved, grids split
into 16 tokens per bar, patterns substituted, chords parsed.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from . import _time as tb
from .harmony import Chord, HarmonyError, parse_chord, parse_note
from .kinds import (AUTOMATABLE, CHORD_TOKENS, CONGA_TOKENS, CUE_KEYS, DRUM_TOKENS, HAT_TOKENS, INSTRUMENTS,
                    KINDS, REQUIRED, TRACK_KEYS)

FORMAT_VERSION = 1
_ID = re.compile(r"^[a-z0-9_]+(\.[a-z0-9_]+)*$")
_LOG_TOKEN = re.compile(r"^(?P<pitch>[135789][,']*|[A-G][#b♯♭]?-?\d)(?:>(?P<to>[135789][,']*|[A-G][#b♯♭]?-?\d))?(?P<vel>[!?]?)$")
_DEGREE = re.compile(r"(?<![A-Gb#♭♯-])[135789][,']*")
_MELODY_TOKEN = re.compile(r"^(?P<pitch>[A-G][#b♯♭]?-?\d)(?P<vel>[!?]?)$")


class ScoreError(ValueError):
    """A score that cannot be rendered; ``problems`` lists every reason."""

    def __init__(self, source: str, problems: list[str]):
        self.source = source
        self.problems = problems
        lines = "\n".join(f"  - {p}" for p in problems)
        super().__init__(f"{source}: {len(problems)} problem(s):\n{lines}")


@dataclass(frozen=True)
class Section:
    name: str
    first_bar: int
    last_bar: int

    @property
    def frame(self) -> int:
        return tb.frame_of(self.first_bar)

    @property
    def end_frame(self) -> int:
        return tb.frame_of(self.last_bar + 1)


@dataclass(frozen=True)
class ChordChange:
    pos: tb.Pos
    chord: Chord

    @property
    def sample(self) -> int:
        return self.pos.sample


@dataclass
class Track:
    name: str
    instrument: str
    bars: dict[int, list[str]]                 # bar -> 16 tokens
    gain: float = 0.0
    pan: float = 0.0
    swing: bool = False
    humanise: float = 0.0                      # ms, uniform ±
    reverb: float | None = None                # RT60 s of a send
    wet: float = -14.0
    params: dict = field(default_factory=dict)
    automation: dict[str, list[tuple[tb.Pos, float]]] = field(default_factory=dict)


@dataclass
class Cue:
    id: str
    kind: str
    pos: tb.Pos
    offset: int = 0                            # frames off the grid (real UI timings only)
    end: tb.Pos | None = None
    end_offset: int = 0
    dur: int | None = None                     # frames, instead of end
    gain: float = 0.0
    pan: float | None = None
    reverb: float | None = None
    wet: float = -14.0
    params: dict = field(default_factory=dict)

    @property
    def frame(self) -> int:
        return self.pos.frame + self.offset

    @property
    def sample(self) -> int:
        return tb.sample_of_frame(self.frame)

    @property
    def end_frame(self) -> int | None:
        if self.end is not None:
            return self.end.frame + self.end_offset
        if self.dur is not None:
            return self.frame + self.dur
        return None

    @property
    def end_sample(self) -> int | None:
        f = self.end_frame
        return None if f is None else tb.sample_of_frame(f)


@dataclass
class Score:
    source: str
    name: str
    cut: str
    bars: int
    tempo: float
    key: str
    swing: float
    sections: list[Section]
    chords: list[ChordChange]
    tracks: list[Track]
    cues: list[Cue]
    patterns: dict[str, list[str]]

    @property
    def frames(self) -> int:
        return self.bars * tb.FRAMES_PER_BAR

    @property
    def samples(self) -> int:
        return tb.sample_of_frame(self.frames)

    def chord_at(self, sample: int) -> Chord:
        current = self.chords[0].chord
        for change in self.chords:
            if change.sample <= sample:
                current = change.chord
            else:
                break
        return current

    def cue(self, cue_id: str) -> Cue:
        for c in self.cues:
            if c.id == cue_id:
                return c
        raise KeyError(cue_id)


# ── parsing helpers ────────────────────────────────────────────────────────

def split_grid(grid: object) -> list[str]:
    """A grid -> its tokens. A list is taken as tokens; a string with spaces
    is split on whitespace; a string without is one token per character.
    ``|`` is a visual separator everywhere and is dropped."""
    if isinstance(grid, list):
        return [str(t) for t in grid if str(t) != "|"]
    text = str(grid).strip()
    if any(ch.isspace() for ch in text):
        return text.replace("|", " ").split()
    return [c for c in text if c != "|"]


def parse_bars(key: object, n_bars: int) -> list[int]:
    """``3`` / ``"3-6"`` / ``"1-2, 5"`` -> [bars]."""
    out: list[int] = []
    for part in str(key).split(","):
        part = part.strip()
        m = re.match(r"^(\d+)(?:\s*-\s*(\d+))?$", part)
        if not m:
            raise ValueError(f"bars {key!r}: write 3, 3-6 or 1-2, 5")
        a = int(m.group(1))
        b = int(m.group(2) or a)
        if a > b:
            raise ValueError(f"bars {key!r}: {a}-{b} runs backwards")
        out.extend(range(a, b + 1))
    bad = [b for b in out if not 1 <= b <= n_bars]
    if bad:
        raise ValueError(f"bars {key!r}: bar {bad[0]} is outside 1-{n_bars}")
    return out


def check_token(family: str, token: str) -> str | None:
    """None if ``token`` is allowed in a grid of this instrument family."""
    allowed = {"drum": DRUM_TOKENS, "hat": HAT_TOKENS, "conga": CONGA_TOKENS, "chord": CHORD_TOKENS}.get(family)
    if allowed is not None:
        return None if token in allowed else f"{token!r} (allowed: {' '.join(sorted(allowed))})"
    if token in (".", "-"):
        return None
    pattern = _LOG_TOKEN if family == "log" else _MELODY_TOKEN
    m = pattern.match(token)
    if not m:
        what = "a degree (1 3 5 7 8 9, , or ') or a note, optional >target and ! or ?" if family == "log" \
            else "a note (e.g. G5, Bb5), optional ! or ?"
        return f"{token!r} is not {what}"
    for g in ("pitch", "to"):
        v = m.groupdict().get(g)
        if v and v[0].isalpha():
            try:
                parse_note(v)
            except HarmonyError as e:
                return str(e)
    return None


# ── loading ────────────────────────────────────────────────────────────────

def load(path: str | Path) -> Score:
    path = Path(path)
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
    except yaml.YAMLError as e:
        raise ScoreError(path.name, [f"not valid YAML: {e}"]) from None
    return parse(data, source=path.name, name=path.stem)


def parse(data: object, *, source: str = "<score>", name: str = "score") -> Score:
    problems: list[str] = []
    say = problems.append
    if not isinstance(data, dict):
        raise ScoreError(source, ["the file must be a mapping (score:, cut:, bars:, …)"])

    known = {"score", "cut", "bars", "tempo", "key", "swing", "sections", "chords", "patterns", "tracks", "cues"}
    for k in data:
        if k not in known:
            say(f"unknown top-level key {k!r} (known: {', '.join(sorted(known))})")
    if data.get("score") != FORMAT_VERSION:
        say(f"score: must be {FORMAT_VERSION} (the format version), got {data.get('score')!r}")
    cut = str(data.get("cut", ""))
    if not cut:
        say("cut: missing (e.g. 30s)")
    bars = data.get("bars")
    if not isinstance(bars, int) or isinstance(bars, bool) or bars < 1:
        say(f"bars: must be a whole number of bars >= 1, got {bars!r}")
        raise ScoreError(source, problems)
    tempo = data.get("tempo", tb.BPM)
    if tempo != tb.BPM:
        say(f"tempo: the promo's clock is fixed at {tb.BPM} BPM (beat = 16 frames), got {tempo!r}")
    swing = data.get("swing", 0.5)
    if not isinstance(swing, (int, float)) or not 0.5 <= swing < 0.75:
        say(f"swing: must be 0.50-0.75 (the off-16th's place in its 8th), got {swing!r}")
        swing = 0.5

    def pos_of(text: object, where: str, *, allow_end: bool = False) -> tb.Pos | None:
        try:
            p = tb.parse_pos(text)
        except tb.PositionError as e:
            say(f"{where}: {e}")
            return None
        limit = tb.Pos(bars + 1, 1, 0)
        if p > limit or (p == limit and not allow_end):
            say(f"{where}: {p} is past the cut's {bars} bars")
            return None
        return p

    # sections — contiguous, covering every bar once
    sections: list[Section] = []
    covered: list[int] = []
    for i, s in enumerate(data.get("sections") or []):
        where = f"sections[{i}]"
        if not isinstance(s, dict) or "name" not in s or "bars" not in s:
            say(f"{where}: needs name and bars")
            continue
        try:
            span = parse_bars(s["bars"], bars)
        except ValueError as e:
            say(f"{where} {s.get('name')!r}: {e}")
            continue
        if span != list(range(span[0], span[-1] + 1)):
            say(f"{where} {s['name']!r}: a section is one run of bars")
        sections.append(Section(str(s["name"]), span[0], span[-1]))
        covered.extend(span)
    if sorted(covered) != list(range(1, bars + 1)):
        say(f"sections: must cover bars 1-{bars} exactly once each, in order")
    elif covered != sorted(covered):
        say("sections: list them in bar order")

    # chords — one on bar 1; later ones at bars or bar.beat.step
    chords: list[ChordChange] = []
    for key, symbol in (data.get("chords") or {}).items():
        where = f"chords[{key}]"
        text = f"{key}.1.0" if (isinstance(key, int) and not isinstance(key, bool)) or str(key).isdigit() \
            else str(key)
        p = pos_of(text, where)
        if p is None:
            continue
        try:
            chords.append(ChordChange(p, parse_chord(symbol)))
        except HarmonyError as e:
            say(f"{where}: {e}")
    chords.sort(key=lambda c: c.pos)
    if not chords or chords[0].pos != tb.Pos(1, 1, 0):
        say("chords: bar 1 needs a chord")
    for a, b in zip(chords, chords[1:]):
        if a.pos == b.pos:
            say(f"chords: two chords at {a.pos}")

    # patterns
    patterns: dict[str, list[str]] = {}
    for pname, grid in (data.get("patterns") or {}).items():
        tokens = split_grid(grid)
        if len(tokens) != tb.STEPS_PER_BAR:
            say(f"patterns.{pname}: {len(tokens)} steps, a bar has {tb.STEPS_PER_BAR}")
        patterns[str(pname)] = tokens

    # tracks
    tracks: list[Track] = []
    for tname, t in (data.get("tracks") or {}).items():
        where = f"tracks.{tname}"
        if not isinstance(t, dict):
            say(f"{where}: must be a mapping")
            continue
        for k in t:
            if k not in TRACK_KEYS:
                say(f"{where}: unknown key {k!r} (known: {', '.join(sorted(TRACK_KEYS))})")
        inst = INSTRUMENTS.get(str(t.get("instrument", "")))
        if inst is None:
            say(f"{where}: instrument {t.get('instrument')!r} is not one of {', '.join(INSTRUMENTS)}")
            continue
        params = dict(t.get("params") or {})
        for k, v in params.items():
            spec = inst.params.get(k)
            if spec is None:
                say(f"{where}.params: {inst.name} has no parameter {k!r} (has: {', '.join(inst.params) or 'none'})")
            elif (why := spec.check(v)) is not None:
                say(f"{where}.params.{k}: {why}")
        for k, spec in inst.params.items():
            params.setdefault(k, spec.default)
        swing_on = bool(t.get("swing", False))
        if swing_on and not inst.swingable:
            say(f"{where}: swing applies to shakers and hats only (storyboard « Music plan »), not {inst.name}")
        humanise = t.get("humanise", 0.0)
        if humanise and not inst.swingable:
            say(f"{where}: only shakers and hats are humanised; {inst.name} stays on the grid")
        if not isinstance(humanise, (int, float)) or not 0 <= humanise <= 6:
            say(f"{where}: humanise is ±0-6 ms, got {humanise!r}")
            humanise = 0.0
        grid_bars: dict[int, list[str]] = {}
        for key, grid in (t.get("bars") or {}).items():
            try:
                which = parse_bars(key, bars)
            except ValueError as e:
                say(f"{where}.bars: {e}")
                continue
            tokens = patterns.get(grid) if isinstance(grid, str) and grid in patterns else split_grid(grid)
            if len(tokens) != tb.STEPS_PER_BAR:
                say(f"{where}.bars[{key}]: {len(tokens)} steps, a bar has {tb.STEPS_PER_BAR}"
                    + ("" if isinstance(grid, list) or " " in str(grid) else f" (or {grid!r} is not a pattern name)"))
                continue
            for tok in tokens:
                if (why := check_token(inst.family, tok)) is not None:
                    say(f"{where}.bars[{key}]: {why}")
                    break
            else:
                if inst.family == "log" and chords:          # each degree must exist in the chord it falls on
                    for b in which:
                        for step, tok in enumerate(tokens):
                            for degree in _DEGREE.findall(tok):
                                at = tb.pos_of_step(b, step)
                                chord = next(c.chord for c in reversed(chords) if c.pos <= at)
                                try:
                                    chord.degree_note(degree)
                                except HarmonyError as e:
                                    say(f"{where}.bars[{key}] at {at}: {e}")
            for b in which:
                if b in grid_bars:
                    say(f"{where}.bars: bar {b} is given twice")
                grid_bars[b] = tokens
        automation: dict[str, list[tuple[tb.Pos, float]]] = {}
        for lane, points in (t.get("automation") or {}).items():
            if lane not in AUTOMATABLE:
                say(f"{where}.automation: unknown lane {lane!r} (known: {', '.join(sorted(AUTOMATABLE))})")
                continue
            pts = []
            for j, pt in enumerate(points or []):
                if not (isinstance(pt, list) and len(pt) == 2 and isinstance(pt[1], (int, float))):
                    say(f"{where}.automation.{lane}[{j}]: write [bar.beat.step, value]")
                    continue
                p = pos_of(pt[0], f"{where}.automation.{lane}[{j}]", allow_end=True)
                if p is not None:
                    pts.append((p, float(pt[1])))
            if [p for p, _ in pts] != sorted(p for p, _ in pts):
                say(f"{where}.automation.{lane}: points must be in time order")
            automation[lane] = pts
        reverb_rt = t.get("reverb")
        if reverb_rt is not None and (not isinstance(reverb_rt, (int, float)) or not 0.1 <= reverb_rt <= 6):
            say(f"{where}: reverb is an RT60 in seconds (0.1-6), got {reverb_rt!r}")
            reverb_rt = None
        tracks.append(Track(str(tname), inst.name, grid_bars, float(t.get("gain", 0.0)), float(t.get("pan", 0.0)),
                            swing_on, float(humanise), reverb_rt, float(t.get("wet", -14.0)), params, automation))

    # cues
    cues: list[Cue] = []
    seen: set[str] = set()
    for i, c in enumerate(data.get("cues") or []):
        if not isinstance(c, dict):
            say(f"cues[{i}]: must be a mapping")
            continue
        cid = str(c.get("id", ""))
        where = f"cues[{i}] {cid!r}"
        if not _ID.match(cid):
            say(f"{where}: id must be lower-case dotted words (e.g. drop1.impact)")
        if cid in seen:
            say(f"{where}: id used twice")
        seen.add(cid)
        kind = KINDS.get(str(c.get("kind", "")))
        if kind is None:
            say(f"{where}: kind {c.get('kind')!r} is not one of {', '.join(KINDS)}")
            continue
        params: dict = {}
        for k, v in c.items():
            if k in CUE_KEYS:
                continue
            spec = kind.params.get(k)
            if spec is None:
                say(f"{where}: {kind.name} has no parameter {k!r} (has: {', '.join(kind.params) or 'none'})")
            elif (why := spec.check(v)) is not None:
                say(f"{where}.{k}: {why}")
            else:
                params[k] = v
        for k, spec in kind.params.items():
            if k not in params:
                if spec.default is REQUIRED:
                    say(f"{where}: {kind.name} needs {k!r}")
                else:
                    params[k] = spec.default
        for k in ("note", "glide_from", "from", "to", "saw_from", "saw_to"):
            if isinstance(params.get(k), str):
                try:
                    parse_note(params[k])
                except HarmonyError as e:
                    say(f"{where}.{k}: {e}")
        p = pos_of(c.get("pos"), f"{where}.pos")
        if p is None:
            continue
        offset = c.get("offset", 0)
        if not isinstance(offset, int) or isinstance(offset, bool) or abs(offset) >= tb.FRAMES_PER_BEAT:
            say(f"{where}.offset: whole frames off the grid, |offset| < {tb.FRAMES_PER_BEAT}, got {offset!r}")
            offset = 0
        end = None
        if "end" in c:
            end = pos_of(c["end"], f"{where}.end", allow_end=True)
        dur = c.get("dur")
        if dur is not None and (not isinstance(dur, int) or isinstance(dur, bool) or dur <= 0):
            say(f"{where}.dur: a positive whole number of frames, got {dur!r}")
            dur = None
        end_offset = c.get("end_offset", 0)
        if not isinstance(end_offset, int) or isinstance(end_offset, bool):
            say(f"{where}.end_offset: whole frames, got {end_offset!r}")
            end_offset = 0
        has_span = end is not None or dur is not None
        if end is not None and dur is not None:
            say(f"{where}: give end or dur, not both")
        if kind.span == "required" and not has_span and "end" not in c:
            say(f"{where}: {kind.name} spans time: give end (bar.beat.step) or dur (frames)")
        if kind.span == "none" and has_span:
            say(f"{where}: {kind.name} is a hit; it takes no end or dur")
        cue = Cue(cid, kind.name, p, offset, end, end_offset, dur, float(c.get("gain", 0.0)),
                  c.get("pan"), c.get("reverb"), float(c.get("wet", -14.0)), params)
        if cue.frame < 0 or cue.frame >= bars * tb.FRAMES_PER_BAR:
            say(f"{where}: frame {cue.frame} is outside the cut (0-{bars * tb.FRAMES_PER_BAR - 1})")
        if cue.end_frame is not None:
            if cue.end_frame <= cue.frame:
                say(f"{where}: ends (frame {cue.end_frame}) before it starts (frame {cue.frame})")
            if cue.end_frame > bars * tb.FRAMES_PER_BAR:
                say(f"{where}: ends at frame {cue.end_frame}, past the cut's last frame")
        if kind.name == "riser":
            gates = params.get("gates") or [[str(p), 8]]
            parsed = []
            for j, g in enumerate(gates):
                if not (isinstance(g, list) and len(g) == 2 and g[1] in (8, 16)):
                    say(f"{where}.gates[{j}]: write [bar.beat.step, 8 or 16]")
                    continue
                gp = pos_of(g[0], f"{where}.gates[{j}]")
                if gp is not None:
                    parsed.append((gp, int(g[1])))
            if parsed and parsed[0][0] != p:
                say(f"{where}.gates: the first gate starts at pos ({p})")
            if [g[0] for g in parsed] != sorted(g[0] for g in parsed):
                say(f"{where}.gates: in time order")
            cue.params["gates"] = parsed
        if cue.pan is not None and (not isinstance(cue.pan, (int, float)) or not -1 <= cue.pan <= 1):
            say(f"{where}.pan: -1 (left) .. 1 (right), got {cue.pan!r}")
            cue.pan = None
        cues.append(cue)

    if problems:
        raise ScoreError(source, problems)
    cues.sort(key=lambda c: (c.frame, c.id))
    return Score(source, name, cut, bars, float(tempo), str(data.get("key", "")), float(swing), sections, chords,
                 tracks, cues, patterns)
