"""Notes, chords, voicings and the log drum's chord-relative degrees.

The promo is in C minor on four chords — Cm9, F9, A♭maj9, G7♭9 (storyboard,
« Music plan »). Voicings are not typed per chord: every keyboard voicing is
the chord's 3rd, 5th, 7th and 9th, each placed in ONE fixed octave window.
Because the window spans exactly twelve semitones, every pitch class has one
place in it, and the four chords lead into each other by steps:

    Cm9    E♭3 G3  B♭3 D4
    F9     E♭3 G3  A3  C4
    A♭maj9 E♭3 G3  B♭3 C4
    G7♭9   F3  A♭3 B3  D4

The log drum's notes in a pattern are written as degrees of the bar's chord
(``1``, ``3``, ``5``, ``7``, ``8``, ``9``; ``,`` an octave down, ``'`` up), so
one pattern follows every chord change.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

from .dsp import midi_hz

_NOTE = re.compile(r"^([A-Ga-g])([#b♯♭]?)(-?\d)$")
_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
_ACC = {"": 0, "#": 1, "♯": 1, "b": -1, "♭": -1}

# Chord qualities: degree -> semitones above the root.
QUALITIES: dict[str, dict[str, int]] = {
    "m9": {"1": 0, "3": 3, "5": 7, "7": 10, "9": 14},
    "9": {"1": 0, "3": 4, "5": 7, "7": 10, "9": 14},
    "maj9": {"1": 0, "3": 4, "5": 7, "7": 11, "9": 14},
    "7b9": {"1": 0, "3": 4, "5": 7, "7": 10, "9": 13},
    "m7": {"1": 0, "3": 3, "5": 7, "7": 10},
    "7": {"1": 0, "3": 4, "5": 7, "7": 10},
    "maj7": {"1": 0, "3": 4, "5": 7, "7": 11},
    "m": {"1": 0, "3": 3, "5": 7},
    "": {"1": 0, "3": 4, "5": 7},
}

# Octave windows (MIDI, inclusive, 12 semitones each).
KEYS_WINDOW = (51, 62)        # E♭3 .. D4  — Rhodes / pad voicing
ORGAN_WINDOW = (63, 74)       # E♭4 .. D5  — organ stabs, an octave up
LEFT_HAND_WINDOW = (41, 52)   # F2 .. E3   — the Rhodes' root
PAD_ROOT_WINDOW = (43, 54)    # G2 .. F#3  — the pad's root
LOG_WINDOW = (34, 45)         # B♭1 .. A2  — the log drum's degree 1
SUB_WINDOW = (31, 42)         # G1 .. F#2  — a held sub note


class HarmonyError(ValueError):
    pass


def parse_note(name: str) -> int:
    """``"E♭2"`` / ``"Eb2"`` -> 39 (MIDI; C4 = 60)."""
    m = _NOTE.match(str(name).strip())
    if not m:
        raise HarmonyError(f"{name!r} is not a note: write e.g. C2, Eb2, F#1, B♭1")
    letter, acc, octave = m.groups()
    return 12 * (int(octave) + 1) + _PC[letter.upper()] + _ACC[acc]


def note_hz(name: str) -> float:
    return midi_hz(parse_note(name))


def in_window(pc: int, window: tuple[int, int]) -> int:
    """The one MIDI note of pitch class ``pc`` inside a 12-semitone window."""
    lo, hi = window
    m = lo + ((pc - lo) % 12)
    assert lo <= m <= hi
    return m


_CHORD = re.compile(r"^([A-G])([#b♯♭]?)(.*)$")


@dataclass(frozen=True)
class Chord:
    symbol: str
    root_pc: int
    degrees: dict[str, int]

    def __hash__(self) -> int:              # degrees is a dict; the symbol says it all
        return hash(self.symbol)

    def pitch_class(self, degree: str) -> int:
        return (self.root_pc + self.degrees[degree]) % 12

    def voicing(self, window: tuple[int, int] = KEYS_WINDOW) -> list[int]:
        """The chord's 3, 5, 7, 9 (those it has), each in ``window``, sorted."""
        tones = [d for d in ("3", "5", "7", "9") if d in self.degrees]
        return sorted(in_window(self.pitch_class(d), window) for d in tones)

    def root(self, window: tuple[int, int]) -> int:
        return in_window(self.root_pc, window)

    def degree_note(self, token: str, window: tuple[int, int] = LOG_WINDOW) -> int:
        """A degree token -> MIDI. ``1`` is the root in ``window``; ``3 5 7 9``
        sit above it (9 = an octave + a 2nd); ``8`` is the octave; each ``,``
        lowers an octave and each ``'`` raises one."""
        m = re.match(r"^([1-9])([,']*)$", token)
        if not m:
            raise HarmonyError(f"{token!r} is not a degree (1 3 5 7 8 9, with , or ')")
        d, marks = m.groups()
        if d == "8":
            semis = 12
        elif d in self.degrees:
            semis = self.degrees[d]
        else:
            raise HarmonyError(f"{self.symbol} has no degree {d}")
        return self.root(window) + semis + 12 * (marks.count("'") - marks.count(","))


def parse_chord(symbol: str) -> Chord:
    """``"Cm9"``, ``"F9"``, ``"A♭maj9"`` / ``"Abmaj9"``, ``"G7♭9"`` / ``"G7b9"``."""
    s = str(symbol).strip().replace("♭", "b").replace("♯", "#")
    m = _CHORD.match(s)
    if not m:
        raise HarmonyError(f"{symbol!r} is not a chord symbol (e.g. Cm9, F9, Abmaj9, G7b9)")
    letter, acc, quality = m.groups()
    if quality not in QUALITIES:
        raise HarmonyError(f"{symbol!r}: unknown quality {quality!r} (known: {', '.join(q or 'major' for q in QUALITIES)})")
    return Chord(s, (_PC[letter] + _ACC[acc]) % 12, QUALITIES[quality])
