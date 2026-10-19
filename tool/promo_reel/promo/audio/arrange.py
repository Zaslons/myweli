"""Render a score into five stereo buses — and log where every sound landed.

The arranger turns the score's grids and cues into events, synthesises each
one with ``instruments``, and adds it into its track at an exact sample:

* a grid hit lands on its 16th — plus the swing (56 %: the off-16th of each
  8th is late by 0.06 of an 8th, 768 samples) and the humanise (seeded,
  uniform ±ms), on shakers and hats only;
* a cue lands on ``frame * 1600`` exactly, its first sample being the sound's
  onset. A cue of a grid instrument (a hero log hit, a kick punch) REPLACES
  that instrument's grid hit on the same 16th: the score is written around
  the hero frames and the pattern fills the rest.

The log drum is one voice: each hit is cut (with a 6-ms fade) where the next
one starts, so a fast phrase never smears. Every placement is recorded in
``Render.placed`` — events.py writes events.json from that record, not from
the score.
"""

from __future__ import annotations

import bisect
from dataclasses import dataclass, field

import numpy as np

from . import _time as tb
from . import instruments as ins
from .dsp import SR, amp, fade, midi_hz, n_of, pan, reverb, rng, sweep
from .harmony import (KEYS_WINDOW, LEFT_HAND_WINDOW, LOG_WINDOW, ORGAN_WINDOW, PAD_ROOT_WINDOW, SUB_WINDOW,
                      parse_note)
from .kinds import BUSES, INSTRUMENTS, KINDS
from .score import Cue, Score, Track

VELOCITY = {"X": 1.0, "x": 0.8, "g": 0.5, "!": 1.0, "?": 0.5, "": 0.8}


@dataclass
class Event:
    """One sound to place: a grid hit or a cue of a grid instrument."""

    instrument: str
    label: str
    grid_sample: int
    sample: int
    vel: float
    gate: int = 0                                 # samples held (keys)
    notes: tuple[int, ...] = ()                   # MIDI
    glide_from: int | None = None
    token: str = ""
    params: dict = field(default_factory=dict)
    cue: Cue | None = None


@dataclass
class Placed:
    """Where a sound actually went."""

    label: str                  # cue id, or "track@bar.beat.step"
    kind: str                   # the cue kind, or the grid instrument
    source: str                 # "cue" | "grid"
    bus: str
    grid_sample: int            # where the grid / the cue says
    sample: int                 # where its first sample was written
    length: int                 # samples of audio written
    end_sample: int | None = None


@dataclass
class Render:
    score: Score
    stems: dict[str, np.ndarray]                  # bus -> (n, 2)
    placed: list[Placed]
    parts: dict[str, np.ndarray] = field(default_factory=dict)

    @property
    def samples(self) -> int:
        return self.score.samples

    def onsets(self, *kinds: str) -> list[int]:
        """Samples where sounds of these kinds/instruments started."""
        return sorted(p.sample for p in self.placed if p.kind in kinds)

    def cue_placements(self) -> list[Placed]:
        return [p for p in self.placed if p.source == "cue"]


# ── grid -> events ─────────────────────────────────────────────────────────

def _split_vel(token: str) -> tuple[str, float]:
    if token and token[-1] in "!?":
        return token[:-1], VELOCITY[token[-1]]
    return token, VELOCITY[""]


def _pitch(text: str, chord) -> int:
    return parse_note(text) if text[0].isalpha() else chord.degree_note(text, LOG_WINDOW)


def _chord_notes(instrument: str, chord) -> tuple[int, ...]:
    if instrument == "rhodes":
        return (chord.root(LEFT_HAND_WINDOW), *chord.voicing(KEYS_WINDOW))
    if instrument == "organ":
        return tuple(chord.voicing(ORGAN_WINDOW))
    if instrument == "pad":
        return (chord.root(PAD_ROOT_WINDOW), *chord.voicing(KEYS_WINDOW))
    if instrument == "sub":
        return (chord.root(SUB_WINDOW),)
    raise ValueError(instrument)


def expand_track(track: Track, score: Score) -> list[Event]:
    """A track's grids -> events, in time order. ``-`` holds the previous note
    for another 16th (across a bar line too); a bar the track does not name is
    silent and ends any held note."""
    inst = INSTRUMENTS[track.instrument]
    events: list[Event] = []
    held: Event | None = None
    swing_delay = int(round((score.swing - 0.5) * 2 * tb.SAMPLES_PER_STEP))
    accents = track.params.get("accents") or [1.0] * 4
    for bar in range(1, score.bars + 1):
        tokens = track.bars.get(bar)
        if tokens is None:
            held = None
            continue
        for step, tok in enumerate(tokens):
            pos = tb.pos_of_step(bar, step)
            grid = pos.sample
            if tok == ".":
                held = None
                continue
            if tok == "-":
                if held is not None:
                    held.gate += tb.SAMPLES_PER_STEP
                continue
            sample = grid
            if track.swing and step % 2 == 1:
                sample += swing_delay
            if track.humanise:
                ms = rng(score.name, track.name, bar, step).uniform(-track.humanise, track.humanise)
                sample += int(round(ms * SR / 1000))
            label = f"{track.name}@{pos}"
            chord = score.chord_at(grid)
            ev = Event(track.instrument, label, grid, sample, 0.8, tb.SAMPLES_PER_STEP, token=tok)
            if inst.family in ("drum", "hat", "conga", "chord"):
                ev.vel = VELOCITY.get(tok, 1.0 if tok.isupper() else 0.8)
                if inst.family == "chord":
                    ev.notes = _chord_notes(track.instrument, chord)
            elif inst.family == "log":
                body, ev.vel = _split_vel(tok)
                if ">" in body:
                    a, b = body.split(">")
                    ev.glide_from, ev.notes = _pitch(a, chord), (_pitch(b, chord),)
                else:
                    ev.notes = (_pitch(body, chord),)
            elif inst.family == "melody":
                body, ev.vel = _split_vel(tok)
                ev.notes = (parse_note(body),)
            if track.instrument == "shaker":
                ev.vel *= float(accents[step % 4])
            events.append(ev)
            held = ev
    return events


def cue_event(cue: Cue, score: Score) -> Event:
    """A cue of a grid instrument -> its event (placed exactly on the cue)."""
    p = cue.params
    ev = Event(KINDS[cue.kind].instrument, cue.id, cue.sample, cue.sample, float(p.get("vel", 0.9)),
               tb.SAMPLES_PER_STEP, params=p, cue=cue)
    if cue.kind == "log":
        ev.notes = (parse_note(p["note"]),)
        ev.glide_from = parse_note(p["glide_from"]) if p.get("glide_from") else None
    elif cue.kind == "rhodes":
        ev.notes = _chord_notes("rhodes", score.chord_at(cue.sample))
        ev.gate = int(p.get("gate", 3)) * tb.SAMPLES_PER_STEP
    elif cue.kind == "conga":
        ev.token = p.get("stroke", "h")
    return ev


# ── synthesis of one event ─────────────────────────────────────────────────

def default_track(instrument: str) -> Track:
    """The track a cue of a grid instrument plays through when the score has
    no track of that instrument: unity gain, centred, default parameters."""
    params = {k: spec.default for k, spec in INSTRUMENTS[instrument].params.items()}
    return Track(f"{instrument} (cues)", instrument, {}, params=params)


def synth(ev: Event, track: Track, seed: str) -> np.ndarray:
    """The sound of one event (mono or stereo), onset at index 0."""
    tp = track.params
    v = ev.vel
    name = ev.instrument
    if name == "log":
        p = ev.params
        return ins.log_drum(midi_hz(ev.notes[0]), v,
                            decay_s=p.get("decay") or tp.get("decay", 0.2),
                            glide_from=midi_hz(ev.glide_from) if ev.glide_from is not None else None,
                            index=p.get("index") or tp.get("index", 3.0), drive=tp.get("drive", 3.0),
                            sub_db=tp.get("sub_db", -2.0), wood_db=tp.get("wood_db", -6.0),
                            lp=p.get("lp") or tp.get("lp"), octave_db=-5.0 if p.get("octave") else None)
    if name == "kick":
        return ins.kick(v, decay_s=tp.get("decay", 0.2), f_start=tp.get("f_start", 165.0),
                        f_end=tp.get("f_end", 45.0), seed=seed)
    if name == "clap":
        return ins.clap(v, seed=seed, tail=tp.get("tail", 0.09))
    if name == "rim":
        return ins.rim(v, seed=seed)
    if name == "shaker":
        return ins.shaker(v, seed=seed, tau=tp.get("tau", 0.02))
    if name == "hat":
        return ins.hat(v, open_=ev.token in ("o", "O"), seed=seed)
    if name == "conga":
        return ins.conga(v, stroke=ev.token or "h", seed=seed)
    if name == "rhodes":
        return sum(ins.rhodes_note(midi_hz(m), v * (0.85 if k == 0 else 0.7), ev.gate,
                                   release=tp.get("release", 0.16)) for k, m in enumerate(ev.notes))
    if name == "organ":
        return sum(ins.organ_note(midi_hz(m), v, ev.gate, drawbars=tp.get("drawbars", "888400000"),
                                  percussion=tp.get("percussion", True), seed=(seed, m)) for m in ev.notes) * 0.6
    if name == "whistle":
        return ins.whistle_note(midi_hz(ev.notes[0]), v, ev.gate, vibrato_hz=tp.get("vibrato_hz", 5.6),
                                vibrato_cents=tp.get("vibrato_cents", 28.0), seed=seed)
    if name == "pad":
        return ins.pad_chord([midi_hz(m) for m in ev.notes], v, ev.gate, cutoff=tp.get("cutoff", 1300.0),
                             attack=tp.get("attack", 0.35), release=tp.get("release", 0.6), seed=seed)
    if name == "sub":
        return ins.sub_note(midi_hz(ev.notes[0]), v, ev.gate, attack=tp.get("attack", 0.12),
                            release=tp.get("release", 0.5))
    raise ValueError(f"no synth for {name}")


def synth_cue(cue: Cue) -> np.ndarray:
    """The sound of an effect cue (mono or stereo), onset at index 0."""
    p = cue.params
    k = cue.kind
    span = (cue.end_sample - cue.sample) if cue.end_sample is not None else None
    if k == "impact":
        return ins.impact(f_start=p["f_start"], f_end=p["f_end"], tau=p["tau"], rt60=p["rt60"], sub=p["sub"],
                          noise_db=p["noise_db"], wet_db=p["wet_db"], sub_db=p["sub_db"], seed=cue.id)
    if k == "whoosh":
        peak = p["peak"] * tb.SAMPLES_PER_FRAME if p.get("peak") is not None else None
        return ins.whoosh(p["style"], span, peak_samples=peak, seed=cue.id)
    if k == "riser":
        cells = [(gp.sample - cue.sample, tb.SAMPLES_PER_STEP * (16 // div)) for gp, div in p["gates"]]
        return ins.riser(span, cells=cells, f_lo=p["f_lo"], f_hi=p["f_hi"],
                         saw_from=midi_hz(parse_note(p["saw_from"])), saw_to=midi_hz(parse_note(p["saw_to"])),
                         seed=cue.id)
    if k == "reverse":
        return ins.reverse_cymbal(span, seed=cue.id)
    if k == "pen_scratch":
        return ins.pen_scratch(span or n_of(0.18), seed=cue.id)
    if k == "pen_slash":
        return ins.pen_slash(length=p["length_ms"] / 1000.0, seed=cue.id)
    if k == "click":
        return ins.ui_click(f=p["f"], seed=cue.id)
    if k == "key":
        return ins.key_click(f=p["f"], seed=cue.id)
    if k == "tick":
        return ins.tick(f=p["f"], seed=cue.id)
    if k == "pop":
        return ins.pop(f=p["f"])
    if k == "thock":
        return ins.thock(f=p["f"], seed=cue.id)
    if k == "cardpop":
        return ins.card_pop(seed=cue.id)
    if k == "chime":
        return ins.chime(f=midi_hz(parse_note(p["note"])), interval=p["interval"], gap=p["gap_ms"] / 1000.0)
    if k == "glint":
        return ins.glint(f=midi_hz(parse_note(p["note"])))
    if k == "kalimba":
        return ins.kalimba(f=midi_hz(parse_note(p["note"])), seed=cue.id)
    if k == "shimmer":
        return ins.shimmer(seed=cue.id)
    if k == "glide":
        return ins.fm_glide(span, f_from=midi_hz(parse_note(p["from"])), f_to=midi_hz(parse_note(p["to"])),
                            seed=cue.id)
    raise ValueError(f"no synth for cue kind {k}")


# ── placement ──────────────────────────────────────────────────────────────

def add_at(buf: np.ndarray, x: np.ndarray, at: int) -> int:
    """Add ``x`` into ``buf`` starting at sample ``at`` (clipped to the
    buffer). Returns the number of samples written."""
    n = len(buf)
    if at >= n:
        return 0
    lo = max(0, -at)
    hi = min(len(x), n - at)
    if hi <= lo:
        return 0
    if buf.ndim == 2 and x.ndim == 1:
        buf[at + lo: at + hi] += x[lo:hi, None]
    else:
        buf[at + lo: at + hi] += x[lo:hi]
    return hi - lo


def _automation_curve(points: list[tuple[tb.Pos, float]], n: int, geometric: bool) -> np.ndarray:
    xs = np.array([p.sample for p, _ in points], dtype=float)
    ys = np.array([v for _, v in points], dtype=float)
    t = np.arange(n, dtype=float)
    if geometric:
        return np.exp(np.interp(t, xs, np.log(ys)))
    return np.interp(t, xs, ys)


def render(score: Score, *, keep_parts: bool = False) -> Render:
    """Render every track and cue of ``score`` into the five buses."""
    n = score.samples
    stems = {b: np.zeros((n, 2)) for b in BUSES}
    placed: list[Placed] = []
    parts: dict[str, np.ndarray] = {}

    # events per track; a cue of a grid instrument joins the first track of
    # that instrument (or a default one) and replaces any grid hit on the same 16th
    tracks = list(score.tracks)
    per_track: dict[str, list[Event]] = {t.name: expand_track(t, score) for t in tracks}
    home: dict[str, Track] = {}
    for t in tracks:
        home.setdefault(t.instrument, t)
    for cue in score.cues:
        instrument = "clap" if cue.kind == "clap_roll" else KINDS[cue.kind].instrument
        if instrument is None:
            continue
        evs = clap_roll_events(cue) if cue.kind == "clap_roll" else [cue_event(cue, score)]
        taken = {e.grid_sample for e in evs}
        for t in tracks:
            if t.instrument == instrument:
                per_track[t.name] = [e for e in per_track[t.name] if e.grid_sample not in taken]
        if instrument not in home:
            home[instrument] = default_track(instrument)
            tracks.append(home[instrument])
            per_track[home[instrument].name] = []
        per_track[home[instrument].name].extend(evs)
        if cue.kind == "clap_roll":
            placed.append(Placed(cue.id, cue.kind, "cue", KINDS[cue.kind].bus, cue.sample, cue.sample,
                                 cue.end_sample - cue.sample, cue.end_sample))

    # the log drum is one voice across all its tracks: cut each hit at the next
    log_onsets = sorted({e.sample for t in tracks if t.instrument == "log" for e in per_track[t.name]})

    def place_events(track: Track, events: list[Event]) -> None:
        instrument = track.instrument
        mono = np.zeros(n)
        wide = np.zeros((n, 2))
        for ev in sorted(events, key=lambda e: e.sample):
            x = synth(ev, track, seed=f"{score.name}:{ev.label}")
            if instrument == "log":
                k = bisect.bisect_right(log_onsets, ev.sample)
                if k < len(log_onsets) and log_onsets[k] - ev.sample < len(x):
                    x = fade(x[: log_onsets[k] - ev.sample], fade_out=n_of(0.006))
            if ev.cue is not None:
                x = x * amp(ev.cue.gain)
                if ev.cue.reverb:
                    add_at(wide, reverb(x, ev.cue.reverb, ev.cue.wet, seed=ev.cue.id), ev.sample)
            written = add_at(mono if x.ndim == 1 else wide, x, ev.sample)
            source = "cue" if ev.cue is not None else "grid"
            if ev.cue is None or ev.cue.kind != "clap_roll":
                placed.append(Placed(ev.label, ev.cue.kind if ev.cue is not None else instrument, source,
                                     INSTRUMENTS[instrument].bus, ev.grid_sample, ev.sample, written,
                                     ev.cue.end_sample if ev.cue is not None else None))
        out = finish_track(track, mono, wide)
        stems[INSTRUMENTS[instrument].bus] += out
        if keep_parts:
            parts[track.name] = out

    for t in tracks:
        place_events(t, per_track[t.name])

    # effect and interface cues
    fx_parts: dict[str, np.ndarray] = {}
    for cue in score.cues:
        kind = KINDS[cue.kind]
        if kind.instrument is not None or cue.kind == "clap_roll":
            continue
        x = synth_cue(cue) * amp(cue.gain)
        if x.ndim == 1:
            x = pan(x, cue.pan or 0.0)
        if cue.reverb:
            x = reverb(x, cue.reverb, cue.wet, seed=cue.id, dry=True)
        written = add_at(stems[kind.bus], x, cue.sample)
        placed.append(Placed(cue.id, cue.kind, "cue", kind.bus, cue.pos.sample, cue.sample, written, cue.end_sample))
        if keep_parts:
            buf = fx_parts.setdefault(f"cues:{kind.bus}", np.zeros((n, 2)))
            add_at(buf, x, cue.sample)
    parts.update(fx_parts)
    placed.sort(key=lambda p: (p.sample, p.label))
    return Render(score, stems, placed, parts)


def clap_roll_events(cue: Cue) -> list[Event]:
    """A clap roll -> one clap per 16th (or 32nd) from pos to end, crescendo."""
    step = tb.SAMPLES_PER_STEP * 16 // int(cue.params["rate"])
    starts = list(range(cue.sample, cue.end_sample, step))
    v0, v1 = cue.params["vel_from"], cue.params["vel_to"]
    vels = np.linspace(v0, v1, len(starts)) if len(starts) > 1 else [v1]
    return [Event("clap", f"{cue.id}#{k}", s, s, float(v), params={}, cue=cue) for k, (s, v) in
            enumerate(zip(starts, vels))]


def finish_track(track: Track, mono: np.ndarray, wide: np.ndarray) -> np.ndarray:
    """A track's mono and stereo sums -> its stereo output: automation,
    instrument effects (Rhodes tremolo, organ rotor), pan, send, gain."""
    n = len(mono)
    params, automation = track.params, track.automation
    if automation.get("lp"):
        cutoff = _automation_curve(automation["lp"], n, geometric=True)
        mono = sweep(mono, "lowpass", cutoff, q=0.7071, block=64)
        wide = sweep(wide, "lowpass", cutoff, q=0.7071, block=64)
    if track.instrument == "rhodes":                  # suitcase auto-pan
        lfo = np.sin(2 * np.pi * params.get("tremolo_hz", 4.2) * np.arange(n) / SR)
        out = pan(mono, np.clip(track.pan + params.get("tremolo", 0.35) * lfo, -1, 1)) + wide
    elif track.instrument == "organ":                 # the rotor
        out = ins.leslie(mono, rate=params.get("leslie_hz", 6.0)) + wide
    else:
        out = pan(mono, track.pan) + wide
    if automation.get("gain"):
        out *= amp(_automation_curve(automation["gain"], n, geometric=False))[:, None]
    if track.reverb:
        out = out + reverb(out, track.reverb, track.wet, seed=f"track-{track.name}")[:n]
    return out * amp(track.gain)
