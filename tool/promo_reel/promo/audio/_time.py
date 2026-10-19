"""The promo's clock, as the audio engine needs it.

The music is the clock (tool/promo_reel architecture contract, « Time base »):

    30 fps, 112.5 BPM  =>  beat = 16 frames, 16th = 4 frames, bar = 64 frames
    frame(bar, beat, step) = (bar - 1) * 64 + (beat - 1) * 16 + step * 4
    sample(frame)          = frame * 1600            (48 kHz)

Positions are written ``bar.beat.step``: bar and beat 1-based, step 0-3 the
16th inside the beat. ``3.1.0`` is the downbeat of bar 3, frame 128.

This module duplicates the three formulas of ``promo/timebase.py`` (owned by
MEDIA) so the audio package stands on its own until SCENES unifies the two.
Everything here is integer arithmetic: a position, a frame and a sample are
the same instant, never a rounded one.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

FPS = 30
BPM = 112.5
SAMPLE_RATE = 48_000

FRAMES_PER_STEP = 4                      # a 16th
STEPS_PER_BEAT = 4
BEATS_PER_BAR = 4
STEPS_PER_BAR = STEPS_PER_BEAT * BEATS_PER_BAR          # 16
FRAMES_PER_BEAT = FRAMES_PER_STEP * STEPS_PER_BEAT      # 16
FRAMES_PER_BAR = FRAMES_PER_BEAT * BEATS_PER_BAR        # 64
SAMPLES_PER_FRAME = SAMPLE_RATE // FPS                  # 1600
SAMPLES_PER_STEP = SAMPLES_PER_FRAME * FRAMES_PER_STEP  # 6400
SAMPLES_PER_BEAT = SAMPLES_PER_STEP * STEPS_PER_BEAT    # 25600
SAMPLES_PER_BAR = SAMPLES_PER_BEAT * BEATS_PER_BAR      # 102400

# The constants above only hold together at this tempo; say so loudly if
# someone edits one of them.
assert SAMPLE_RATE % FPS == 0
assert abs(60.0 / BPM - FRAMES_PER_BEAT / FPS) < 1e-12, "beat must be 16 frames"

_POS = re.compile(r"^\s*(\d+)\.(\d+)\.(\d+)\s*$")


class PositionError(ValueError):
    """A ``bar.beat.step`` string that does not name a 16th of the grid."""


@dataclass(frozen=True, order=True)
class Pos:
    """A 16th of the grid: bar and beat 1-based, step 0-3."""

    bar: int
    beat: int
    step: int

    def __post_init__(self) -> None:
        if self.bar < 1:
            raise PositionError(f"bar must be >= 1, got {self.bar} in {self}")
        if not 1 <= self.beat <= BEATS_PER_BAR:
            raise PositionError(f"beat must be 1-{BEATS_PER_BAR}, got {self.beat} in {self}")
        if not 0 <= self.step < STEPS_PER_BEAT:
            raise PositionError(f"step must be 0-{STEPS_PER_BEAT - 1}, got {self.step} in {self}")

    def __str__(self) -> str:
        return f"{self.bar}.{self.beat}.{self.step}"

    @property
    def frame(self) -> int:
        return frame_of(self.bar, self.beat, self.step)

    @property
    def sample(self) -> int:
        return sample_of_frame(self.frame)

    @property
    def step_in_bar(self) -> int:
        """0-15: the 16th inside the bar."""
        return (self.beat - 1) * STEPS_PER_BEAT + self.step


def frame_of(bar: int, beat: int = 1, step: int = 0) -> int:
    """frame(bar, beat, step) = (bar-1)*64 + (beat-1)*16 + step*4."""
    return (bar - 1) * FRAMES_PER_BAR + (beat - 1) * FRAMES_PER_BEAT + step * FRAMES_PER_STEP


def sample_of_frame(frame: int) -> int:
    """sample(frame) = frame * 1600, exactly (48 kHz / 30 fps)."""
    return int(frame) * SAMPLES_PER_FRAME


def parse_pos(text: str | Pos) -> Pos:
    """``"3.1.0"`` -> Pos(3, 1, 0). Raises PositionError with the reason."""
    if isinstance(text, Pos):
        return text
    m = _POS.match(str(text))
    if not m:
        raise PositionError(f"{text!r} is not a position: write bar.beat.step, e.g. 3.1.0")
    return Pos(int(m.group(1)), int(m.group(2)), int(m.group(3)))


def pos_of_frame(frame: int) -> Pos:
    """The inverse of ``Pos.frame`` for frames on the 16th grid."""
    if frame < 0 or frame % FRAMES_PER_STEP:
        raise PositionError(f"frame {frame} is not on the 16th grid (a multiple of {FRAMES_PER_STEP})")
    bar, rest = divmod(frame, FRAMES_PER_BAR)
    beat, rest = divmod(rest, FRAMES_PER_BEAT)
    return Pos(bar + 1, beat + 1, rest // FRAMES_PER_STEP)


def pos_of_step(bar: int, step_in_bar: int) -> Pos:
    """Bar and 16th-in-bar (0-15) -> Pos."""
    if not 0 <= step_in_bar < STEPS_PER_BAR:
        raise PositionError(f"step in bar must be 0-15, got {step_in_bar}")
    return Pos(bar, step_in_bar // STEPS_PER_BEAT + 1, step_in_bar % STEPS_PER_BEAT)


def seconds_of_frame(frame: float) -> float:
    return frame / FPS
