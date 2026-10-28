"""What a score may say: the grid instruments, the cue kinds and their parameters.

This table is the vocabulary of SCORE.md. ``score.py`` validates a score
against it (unknown names, wrong types and missing values are refused with
the cue's id) and ``arrange.py`` renders from it.
"""

from __future__ import annotations

from dataclasses import dataclass, field

# Buses — what the mix treats together (mix.py).
LOG, DRUMS, KEYS, FX, UI = "log", "drums", "keys", "fx", "ui"
BUSES = (LOG, DRUMS, KEYS, FX, UI)

REQUIRED = object()          # a parameter with no default


@dataclass(frozen=True)
class Param:
    types: tuple[type, ...]
    default: object = None
    choices: tuple | None = None

    def check(self, value: object) -> str | None:
        """None when ``value`` is acceptable, else the reason."""
        if bool in self.types and isinstance(value, bool):
            pass
        elif isinstance(value, bool) or not isinstance(value, self.types):
            names = " or ".join(t.__name__ for t in self.types)
            return f"must be {names}, got {value!r}"
        if self.choices is not None and value not in self.choices:
            return f"must be one of {', '.join(map(str, self.choices))}, got {value!r}"
        return None


NUM = (int, float)
STR = (str,)
INT = (int,)
BOOL = (bool,)
LIST = (list,)


def P(types, default=None, choices=None) -> Param:
    return Param(types, default, choices)


# ── grid instruments ───────────────────────────────────────────────────────
# family -> the symbols its 16-step grids may use (see SCORE.md « Grids »)
DRUM_TOKENS = frozenset(".xXg")
HAT_TOKENS = frozenset(".xXgoO")
CONGA_TOKENS = frozenset(".hHlLsSmM")
CHORD_TOKENS = frozenset(".xXg-")


@dataclass(frozen=True)
class Instrument:
    name: str
    family: str                          # drum | hat | conga | log | melody | chord
    bus: str
    params: dict[str, Param] = field(default_factory=dict)
    swingable: bool = False              # the storyboard swings shakers and hats only


INSTRUMENTS: dict[str, Instrument] = {i.name: i for i in (
    Instrument("log", "log", LOG, {
        "decay": P(NUM, 0.2), "drive": P(NUM, 3.0), "index": P(NUM, 3.0), "sub_db": P(NUM, -2.0),
        "wood_db": P(NUM, -6.0), "lp": P(NUM)}),
    Instrument("kick", "drum", DRUMS, {"decay": P(NUM, 0.20), "f_start": P(NUM, 165.0), "f_end": P(NUM, 45.0)}),
    Instrument("clap", "drum", DRUMS, {"tail": P(NUM, 0.09)}),
    Instrument("rim", "drum", DRUMS),
    Instrument("shaker", "drum", DRUMS, {"tau": P(NUM, 0.020), "accents": P(LIST, [0.75, 0.5, 1.0, 0.6])},
               swingable=True),
    Instrument("hat", "hat", DRUMS, swingable=True),
    Instrument("conga", "conga", DRUMS),
    Instrument("rhodes", "chord", KEYS, {"release": P(NUM, 0.16), "tremolo_hz": P(NUM, 4.2),
                                         "tremolo": P(NUM, 0.35)}),
    Instrument("organ", "chord", KEYS, {"drawbars": P(STR, "888400000"), "percussion": P(BOOL, True),
                                        "leslie_hz": P(NUM, 6.0)}),
    Instrument("whistle", "melody", KEYS, {"vibrato_hz": P(NUM, 5.6), "vibrato_cents": P(NUM, 28.0)}),
    Instrument("pad", "chord", KEYS, {"cutoff": P(NUM, 1300.0), "attack": P(NUM, 0.35), "release": P(NUM, 0.6)}),
    Instrument("sub", "chord", KEYS, {"attack": P(NUM, 0.12), "release": P(NUM, 0.5)}),
)}

# Keys every track may carry, besides its instrument's own ``params``.
TRACK_KEYS = {"instrument", "gain", "pan", "swing", "humanise", "reverb", "wet", "automation", "bars", "params"}
AUTOMATABLE = {"lp", "gain"}            # automation lanes: lp (Hz) and gain (dB)


# ── cue kinds ──────────────────────────────────────────────────────────────

@dataclass(frozen=True)
class Kind:
    name: str
    bus: str
    span: str = "none"                   # none | optional | required: needs end/dur
    params: dict[str, Param] = field(default_factory=dict)
    instrument: str | None = None        # a hit of a grid instrument: replaces that instrument's grid hit
    doc: str = ""


# Keys every cue may carry, besides its kind's own parameters.
CUE_KEYS = {"id", "kind", "pos", "offset", "end", "end_offset", "dur", "gain", "pan", "reverb", "wet"}

KINDS: dict[str, Kind] = {k.name: k for k in (
    Kind("log", LOG, params={"note": P(STR, REQUIRED), "glide_from": P(STR), "vel": P(NUM, 0.9),
                             "decay": P(NUM), "lp": P(NUM), "octave": P(BOOL, False), "index": P(NUM)},
         instrument="log", doc="a log-drum hit on a named note (G1, C2, E♭2…), optional glide and low-pass"),
    Kind("kick", DRUMS, params={"vel": P(NUM, 0.95)}, instrument="kick", doc="a kick off the grid pattern"),
    Kind("clap", DRUMS, params={"vel": P(NUM, 0.95)}, instrument="clap", doc="a clap"),
    Kind("rim", DRUMS, params={"vel": P(NUM, 0.8)}, instrument="rim", doc="a dry rim tick"),
    Kind("conga", DRUMS, params={"vel": P(NUM, 0.8), "stroke": P(STR, "h", tuple("hlms"))}, instrument="conga"),
    Kind("rhodes", KEYS, params={"vel": P(NUM, 0.9), "gate": P(INT, 3)}, instrument="rhodes",
         doc="a Rhodes stab of the bar's chord, gate in 16ths"),
    Kind("clap_roll", DRUMS, span="required", params={"rate": P(INT, 16, (16, 32)), "vel_from": P(NUM, 0.45),
                                                     "vel_to": P(NUM, 1.0)},
         doc="claps on every 16th (or 32nd) from pos up to end, crescendo"),
    Kind("impact", FX, params={"f_start": P(NUM, 80.0), "f_end": P(NUM, 30.0), "tau": P(NUM, 0.8),
                               "rt60": P(NUM, 2.5), "sub": P(BOOL, True), "noise_db": P(NUM, -4.0),
                               "wet_db": P(NUM, -6.0), "sub_db": P(NUM, 0.0)},
         doc="sub sweep + low-passed noise + synthetic reverb"),
    Kind("whoosh", FX, span="optional", params={
        "style": P(STR, REQUIRED, ("whip", "swipe", "swish", "close", "drag", "tape", "air")),
        "peak": P(INT)}, doc="peak = frames from the start to the crest (whip: 3)"),
    Kind("riser", FX, span="required", params={"gates": P(LIST), "f_lo": P(NUM, 200.0), "f_hi": P(NUM, 8000.0),
                                               "saw_from": P(STR, "A2"), "saw_to": P(STR, "A5")},
         doc="gates = [[pos, 8|16], ...]: 8ths, then 16ths from a position"),
    Kind("reverse", FX, span="required", doc="reverse cymbal swelling from pos into end"),
    Kind("pen_scratch", FX, span="optional", doc="pen on paper (180 ms without end/dur)"),
    Kind("pen_slash", FX, params={"length_ms": P(NUM, 120.0)}, doc="pen striking a line out"),
    Kind("click", UI, params={"f": P(NUM, 3200.0)}, doc="the touch-down click: 3.2 kHz, 8 ms, ±3 % per tap"),
    Kind("key", UI, params={"f": P(NUM, 2400.0)}, doc="a typing key"),
    Kind("tick", UI, params={"f": P(NUM, 5200.0)}, doc="the counter's odometer tick"),
    Kind("pop", FX, params={"f": P(NUM, 520.0)}, doc="the lift's soft pop (520 Hz, 40 ms)"),
    Kind("thock", FX, params={"f": P(NUM, 900.0)}, doc="a wood thock"),
    Kind("cardpop", FX, doc="a card landing: wood thock + low thump"),
    Kind("chime", FX, params={"note": P(STR, "G5"), "interval": P(INT, 7), "gap_ms": P(NUM, 90.0)},
         doc="the original two-note chime, a rising fifth"),
    Kind("glint", FX, params={"note": P(STR, "D6")}, doc="a small soft bell"),
    Kind("kalimba", FX, params={"note": P(STR, "C6")}, doc="a kalimba ding"),
    Kind("shimmer", FX, doc="a soft high shimmer"),
    Kind("glide", FX, span="required", params={"from": P(STR, "G3"), "to": P(STR, "C5")},
         doc="a rising FM glide from pos to end"),
)}
