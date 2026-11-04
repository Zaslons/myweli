"""The clock of the promo: the music.

At 112.5 BPM and 30 frames a second every line of the musical grid falls on a
whole frame, and every frame on a whole number of samples:

    beat = 30 × 60 / 112.5 = 16 frames        16th = 4 frames, 8th = 8
    bar  = 4 beats         = 64 frames        = 2.1333 s
    1 frame                = 48 000 / 30      = 1 600 samples

Musical positions are written ``bar.beat.step`` — 1-based bar and beat, step
0–3 the 16th inside the beat — and are relative to the start of a cut:

    frame(bar, beat, step) = (bar − 1)·64 + (beat − 1)·16 + step·4
    sample(frame)          = frame · 1600

The storyboard's shorthand is accepted when reading a position: ``5.2`` is
``5.2.0``, and the 16ths after a beat are ``e``, ``&`` and ``a`` — ``5.2&`` is
``5.2.2``. Positions are always written back in the canonical form.

Everything is exact integer (or ``Fraction``) arithmetic: no frame, sample or
grid line is ever rounded. A frame that is not on the 16th grid has no
position; asking for one is an error, never a silent snap
(``split_frame`` says how far off the grid it is).

The module-level functions use the contract's time base (``DEFAULT``);
``TimeBase`` exists so that a time base can be checked (``storyboard.py``
builds one from ``meta`` and refuses a tempo whose grid is not whole frames).
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from fractions import Fraction
from typing import NamedTuple, Union


class TimeBaseError(ValueError):
    """A time base whose grid is not whole frames, or a position, frame or
    sample that does not exist on it."""


#: The audio engine's name for the same error (a position that is not on the
#: grid); one class, so ``except tb.PositionError`` catches every refusal.
PositionError = TimeBaseError


class Pos(NamedTuple):
    """A musical position: 1-based ``bar`` and ``beat``, ``step`` 0–3 (the
    16th inside the beat). ``str(pos)`` is the canonical ``bar.beat.step``.

    Positions order like the music (bar, then beat, then step). ``frame``,
    ``sample`` and ``step_in_bar`` read the position on the contract's grid
    (``DEFAULT``); a checked ``TimeBase`` gives them for any other grid."""

    bar: int
    beat: int
    step: int = 0

    def __str__(self) -> str:
        return f"{self.bar}.{self.beat}.{self.step}"

    @property
    def frame(self) -> int:
        """The frame this position starts on (contract grid)."""
        return DEFAULT.frame(self)

    @property
    def sample(self) -> int:
        """The first audio sample of this position (contract grid)."""
        return DEFAULT.sample(DEFAULT.frame(self))

    @property
    def step_in_bar(self) -> int:
        """0–15: the 16th inside the bar."""
        DEFAULT.check_pos(self)
        return (self.beat - 1) * DEFAULT.steps_per_beat + self.step


#: A frame number, a ``Pos``, ``"f144"`` or a position string (``"3.2.0"``).
FrameLike = Union[int, Pos, str]

_SHORTHAND = {"e": 1, "&": 2, "a": 3}
_POS_RE = re.compile(r"^\s*(\d+)\.(\d+)(?:\.(\d+)|([e&a]))?\s*$")
_FRAME_RE = re.compile(r"^\s*f(\d+)\s*$")


def _fraction(value: Union[int, float, str, Fraction], what: str) -> Fraction:
    """An exact number. Floats go through their shortest repr, so 112.5 is
    225/2 and 112.3 is 1123/10 (not the binary approximation)."""
    if isinstance(value, bool):
        raise TimeBaseError(f"{what} must be a number, not {value!r}")
    if isinstance(value, Fraction):
        return value
    if isinstance(value, int):
        return Fraction(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise TimeBaseError(f"{what} must be finite, not {value!r}")
        return Fraction(repr(value))
    if isinstance(value, str):
        try:
            return Fraction(value.strip())
        except ValueError:
            raise TimeBaseError(f"{what} must be a number, not {value!r}") from None
    raise TimeBaseError(f"{what} must be a number, not {value!r}")


def _whole(value: Fraction, what: str) -> int:
    if value.denominator != 1:
        raise TimeBaseError(f"{what} is {float(value):g}, not a whole number")
    return int(value)


@dataclass(frozen=True)
class TimeBase:
    """A musical grid laid on video frames and audio samples. Construction
    refuses any combination whose 16th, beat or bar is not a whole number of
    frames, or whose frame is not a whole number of samples."""

    fps: int = 30
    bpm: Fraction = Fraction(225, 2)
    sample_rate: int = 48_000
    beats_per_bar: int = 4
    steps_per_beat: int = 4

    def __post_init__(self) -> None:
        for name in ("fps", "sample_rate", "beats_per_bar", "steps_per_beat"):
            value = getattr(self, name)
            if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
                raise TimeBaseError(f"{name} must be a positive whole number, not {value!r}")
        bpm = _fraction(self.bpm, "bpm")
        if bpm <= 0:
            raise TimeBaseError(f"bpm must be positive, not {float(bpm):g}")
        object.__setattr__(self, "bpm", bpm)
        beat = Fraction(self.fps * 60) / bpm
        _whole(beat, f"a beat at {float(bpm):g} BPM and {self.fps} fps ({beat} frames)")
        _whole(beat / self.steps_per_beat,
               f"a step (1/{self.steps_per_beat} beat) at {float(bpm):g} BPM and {self.fps} fps")
        _whole(Fraction(self.sample_rate, self.fps), f"a frame at {self.sample_rate} Hz and {self.fps} fps, in samples")

    # ---- the grid, in frames and samples ---------------------------------

    @property
    def frames_per_beat(self) -> int:
        return int(Fraction(self.fps * 60) / self.bpm)

    @property
    def frames_per_step(self) -> int:
        return self.frames_per_beat // self.steps_per_beat

    @property
    def frames_per_bar(self) -> int:
        return self.frames_per_beat * self.beats_per_bar

    @property
    def samples_per_frame(self) -> int:
        return self.sample_rate // self.fps

    # ---- positions ---------------------------------------------------------

    def check_pos(self, pos: Pos) -> Pos:
        """``pos`` itself, or an error saying which part is out of range."""
        bar, beat, step = pos
        for name, value in (("bar", bar), ("beat", beat), ("step", step)):
            if isinstance(value, bool) or not isinstance(value, int):
                raise TimeBaseError(f"position {tuple(pos)}: {name} must be a whole number")
        if bar < 1:
            raise TimeBaseError(f"position {pos}: bars count from 1")
        if not 1 <= beat <= self.beats_per_bar:
            raise TimeBaseError(f"position {pos}: beat must be 1–{self.beats_per_bar}")
        if not 0 <= step < self.steps_per_beat:
            raise TimeBaseError(f"position {pos}: step must be 0–{self.steps_per_beat - 1}")
        return Pos(bar, beat, step)

    def parse_pos(self, text: str) -> Pos:
        """``"3.2.0"`` → ``Pos(3, 2, 0)``; also the shorthand ``"3.2"``,
        ``"3.2e"``, ``"3.2&"``, ``"3.2a"`` (16ths 1, 2, 3 after the beat)."""
        if not isinstance(text, str):
            raise TimeBaseError(f"a position is a string like '3.2.0', not {text!r}")
        m = _POS_RE.match(text)
        if not m:
            raise TimeBaseError(f"{text!r} is not a position: write bar.beat.step, e.g. '3.2.0' "
                                f"(or the shorthand '3.2', '3.2e', '3.2&', '3.2a')")
        bar, beat = int(m.group(1)), int(m.group(2))
        if m.group(3) is not None:
            step = int(m.group(3))
        elif m.group(4) is not None:
            if self.steps_per_beat != 4:
                raise TimeBaseError(f"{text!r}: the e/&/a shorthand needs 4 steps a beat")
            step = _SHORTHAND[m.group(4)]
        else:
            step = 0
        return self.check_pos(Pos(bar, beat, step))

    def frame(self, pos: Union[Pos, str]) -> int:
        """The frame a position starts on, from the cut's start."""
        p = self.parse_pos(pos) if isinstance(pos, str) else self.check_pos(Pos(*pos))
        return ((p.bar - 1) * self.frames_per_bar + (p.beat - 1) * self.frames_per_beat
                + p.step * self.frames_per_step)

    def split_frame(self, frame: int) -> tuple[Pos, int]:
        """The last grid position at or before ``frame`` and how many frames
        past it ``frame`` is (0 when ``frame`` is on the 16th grid)."""
        frame = self._frame_number(frame)
        bar, rest = divmod(frame, self.frames_per_bar)
        beat, rest = divmod(rest, self.frames_per_beat)
        step, extra = divmod(rest, self.frames_per_step)
        return Pos(bar + 1, beat + 1, step), extra

    def pos(self, frame: int) -> Pos:
        """The position a frame is on. Only frames on the 16th grid have one."""
        p, extra = self.split_frame(frame)
        if extra:
            raise TimeBaseError(f"frame {frame} is not on the 16th grid ({self.frames_per_step} frames a step): "
                                f"it is {p} + {extra} frame{'s' if extra > 1 else ''}")
        return p

    def to_frame(self, value: FrameLike) -> int:
        """A frame number from an ``int``, a ``Pos``, ``"f144"`` or a
        position string — the forms the storyboard uses."""
        if isinstance(value, bool):
            raise TimeBaseError(f"{value!r} is not a frame")
        if isinstance(value, int):
            return self._frame_number(value)
        if isinstance(value, Pos) or isinstance(value, tuple):
            return self.frame(Pos(*value))
        if isinstance(value, str):
            m = _FRAME_RE.match(value)
            if m:
                return int(m.group(1))
            return self.frame(value)
        raise TimeBaseError(f"{value!r} is not a frame: give a frame number, 'f144' or a position '3.2.0'")

    # ---- samples and seconds -------------------------------------------------

    def sample(self, frame: int) -> int:
        """The first audio sample of a frame."""
        return self._frame_number(frame) * self.samples_per_frame

    def frame_of_sample(self, sample: int) -> int:
        """The frame that starts exactly on ``sample``; an error when the
        sample is inside a frame (use ``frame_at_sample``)."""
        sample = self._sample_number(sample)
        frame, rest = divmod(sample, self.samples_per_frame)
        if rest:
            raise TimeBaseError(f"sample {sample} is {rest} samples into frame {frame}, not on a frame boundary")
        return frame

    def frame_at_sample(self, sample: int) -> int:
        """The frame on screen while ``sample`` plays."""
        return self._sample_number(sample) // self.samples_per_frame

    def seconds(self, frame: int) -> Fraction:
        """When a frame starts, in seconds from the cut's start (exact)."""
        return Fraction(self._frame_number(frame), self.fps)

    def frame_at_seconds(self, seconds: Union[int, float, str, Fraction]) -> int:
        """The frame on screen at ``seconds`` (the last one started by then)."""
        s = _fraction(seconds, "seconds")
        if s < 0:
            raise TimeBaseError(f"{float(s):g} s is before the cut starts")
        return math.floor(s * self.fps)

    def bar_frame(self, bar: int) -> int:
        """The frame bar ``bar`` (1-based) starts on."""
        return self.frame(Pos(bar, 1, 0))

    def grid(self, frames: int, unit: str = "beat") -> list[Pos]:
        """Every ``bar``, ``beat`` or ``step`` position that starts inside the
        first ``frames`` frames, in order."""
        every = {"bar": self.frames_per_bar, "beat": self.frames_per_beat, "step": self.frames_per_step}
        if unit not in every:
            raise TimeBaseError(f"unit must be one of {', '.join(every)}, not {unit!r}")
        return [self.pos(f) for f in range(0, self._frame_number(frames), every[unit])]

    # ---- checks ----------------------------------------------------------------

    @staticmethod
    def _frame_number(frame: int) -> int:
        if isinstance(frame, bool) or not isinstance(frame, int):
            raise TimeBaseError(f"a frame is a whole number, not {frame!r}")
        if frame < 0:
            raise TimeBaseError(f"frame {frame} is before the cut starts")
        return frame

    @staticmethod
    def _sample_number(sample: int) -> int:
        if isinstance(sample, bool) or not isinstance(sample, int):
            raise TimeBaseError(f"a sample is a whole number, not {sample!r}")
        if sample < 0:
            raise TimeBaseError(f"sample {sample} is before the cut starts")
        return sample


#: The contract's time base: 30 fps, 112.5 BPM, 48 kHz, 4/4, 16ths.
DEFAULT = TimeBase()

FPS: int = DEFAULT.fps
BPM: Fraction = DEFAULT.bpm
SAMPLE_RATE: int = DEFAULT.sample_rate
BEATS_PER_BAR: int = DEFAULT.beats_per_bar
STEPS_PER_BEAT: int = DEFAULT.steps_per_beat
FRAMES_PER_STEP: int = DEFAULT.frames_per_step      # 4
FRAMES_PER_BEAT: int = DEFAULT.frames_per_beat      # 16
FRAMES_PER_BAR: int = DEFAULT.frames_per_bar        # 64
SAMPLES_PER_FRAME: int = DEFAULT.samples_per_frame  # 1600
STEPS_PER_BAR: int = STEPS_PER_BEAT * BEATS_PER_BAR                 # 16
SAMPLES_PER_STEP: int = SAMPLES_PER_FRAME * FRAMES_PER_STEP         # 6 400
SAMPLES_PER_BEAT: int = SAMPLES_PER_FRAME * FRAMES_PER_BEAT         # 25 600
SAMPLES_PER_BAR: int = SAMPLES_PER_FRAME * FRAMES_PER_BAR           # 102 400


def frame_of(bar: int, beat: int = 1, step: int = 0) -> int:
    """frame(bar, beat, step) = (bar − 1)·64 + (beat − 1)·16 + step·4 — the
    audio engine's spelling of ``pos_to_frame(Pos(bar, beat, step))``."""
    return DEFAULT.frame(Pos(bar, beat, step))


def sample_of_frame(frame: int) -> int:
    """sample = frame · 1600 (the audio engine's spelling of ``frame_to_sample``)."""
    return DEFAULT.sample(frame)


def pos_of_frame(frame: int) -> Pos:
    """The position of a frame on the 16th grid (an error off the grid)."""
    return DEFAULT.pos(frame)


def pos_of_step(bar: int, step_in_bar: int) -> Pos:
    """Bar and 16th inside it (0–15) → ``Pos``."""
    if isinstance(step_in_bar, bool) or not isinstance(step_in_bar, int) or not 0 <= step_in_bar < STEPS_PER_BAR:
        raise TimeBaseError(f"the 16th inside a bar is 0–{STEPS_PER_BAR - 1}, not {step_in_bar!r}")
    return DEFAULT.check_pos(Pos(bar, step_in_bar // STEPS_PER_BEAT + 1, step_in_bar % STEPS_PER_BEAT))


def parse_pos(text: str) -> Pos:
    """``"3.2.0"`` (or ``"3.2&"``) → ``Pos``, on the contract's grid."""
    return DEFAULT.parse_pos(text)


def format_pos(pos: Pos) -> str:
    """The canonical ``bar.beat.step`` text of a position."""
    return str(DEFAULT.check_pos(Pos(*pos)))


def pos_to_frame(pos: Union[Pos, str]) -> int:
    """frame = (bar − 1)·64 + (beat − 1)·16 + step·4."""
    return DEFAULT.frame(pos)


def frame_to_pos(frame: int) -> Pos:
    """The position of a frame on the 16th grid (an error off the grid)."""
    return DEFAULT.pos(frame)


def split_frame(frame: int) -> tuple[Pos, int]:
    """The grid position at or before ``frame`` and the frames past it."""
    return DEFAULT.split_frame(frame)


def to_frame(value: FrameLike) -> int:
    """A frame from an int, a ``Pos``, ``"f144"`` or ``"3.2.0"``."""
    return DEFAULT.to_frame(value)


def frame_to_sample(frame: int) -> int:
    """sample = frame · 1600."""
    return DEFAULT.sample(frame)


def sample_to_frame(sample: int) -> int:
    """The frame starting exactly on ``sample`` (an error inside a frame)."""
    return DEFAULT.frame_of_sample(sample)


def frame_at_sample(sample: int) -> int:
    """The frame on screen while ``sample`` plays."""
    return DEFAULT.frame_at_sample(sample)


def pos_to_sample(pos: Union[Pos, str]) -> int:
    """The first sample of a position."""
    return DEFAULT.sample(DEFAULT.frame(pos))


def sample_to_pos(sample: int) -> Pos:
    """The position starting exactly on ``sample`` (16th grid only)."""
    return DEFAULT.pos(DEFAULT.frame_of_sample(sample))


def frame_to_seconds(frame: int) -> Fraction:
    """When a frame starts, in seconds (exact)."""
    return DEFAULT.seconds(frame)


def seconds_to_frame(seconds: Union[int, float, str, Fraction]) -> int:
    """The frame on screen at ``seconds``."""
    return DEFAULT.frame_at_seconds(seconds)
