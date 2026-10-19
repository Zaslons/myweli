"""AUDIO — the promo's amapiano soundtrack and its clock, in code.

112.5 BPM, C minor (Cm9 / F9 / A♭maj9 / G7♭9), 48 kHz, synthesised with
NumPy/SciPy from a score (SCORE.md): no sample, no loop, no stock.

    from promo.audio import build_cut
    result = build_cut("score_30s.yaml", "out/30s")      # track.wav, events.json, meter.json, PNGs

or ``python -m promo.audio --score score_30s.yaml --out DIR``.

Modules: dsp, harmony, instruments, kinds (the score's
vocabulary), score (load + validate), arrange (score -> buses + placement
log), mix (sidechain, ducking, compression, true-peak limiter, loudness
loop), loudness (BS.1770-4), events (events.json), analysis (meter.json and
the pictures), wav (24-bit I/O). The clock is promo/timebase.py, shared
with every other module.
"""

from __future__ import annotations

from .build import BuildResult, build_cut, find_score

__all__ = ["BuildResult", "build_cut", "find_score"]
