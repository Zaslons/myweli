"""The mix: from the arranger's five buses to the master.

    keys   x sidechain   — the pads and keys duck 5 dB on every kick and 3 dB
                           on every log hit (never more than 6 dB in all),
                           computed from the KNOWN onset times the arranger
                           logged, a few ms ahead of each hit;
    log    x duck        — the log drum drops 3 dB for 40 ms under each UI
                           click, key and tick, so the clicks sit above it;
    drums + log -> glue compressor (2:1, slow attack: punch kept);
    + keys + fx + ui -> master: everything under 150 Hz folded to mono, a
                           gentle bus compressor, a 20-Hz high-pass, a 60-ms
                           fade to digital silence on the last frame;
    -> loudness loop     — gain into a true-peak limiter, re-measured with
                           BS.1770-4 until the integrated loudness is the
                           target (-14 LUFS) within 0.02 LU; the limiter's
                           ceiling sits a margin under -1.0 dBTP and the
                           margin grows until the MEASURED true peak is under
                           the ceiling.

The limiter's gain is provably never above what each sample's true peak
allows: a minimum over ±2L samples, a release that only ever recovers
towards 1, then a moving average over ±L — every value averaged is at or
under the requirement of the sample in the middle.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import numpy as np
from scipy import ndimage, signal

from . import loudness
from .arrange import Render
from .dsp import SR, amp, db, fade, filt, n_of
from .kinds import DRUMS, FX, KEYS, LOG, UI


@dataclass
class MixSettings:
    target_lufs: float = -14.0
    ceiling_dbtp: float = -1.0
    limiter_margin_db: float = 0.3
    sidechain_kick_db: float = 5.0
    sidechain_log_db: float = 3.0
    sidechain_floor_db: float = -6.0
    sidechain_release_ms: float = 150.0
    duck_db: float = 3.0
    duck_ms: float = 40.0
    mono_below_hz: float = 150.0
    end_fade_ms: float = 60.0
    bus_db: dict[str, float] = field(default_factory=lambda: {LOG: 0.0, DRUMS: 0.0, KEYS: 0.0, FX: 0.0, UI: 0.0})


@dataclass
class Master:
    audio: np.ndarray
    measured: loudness.Loudness
    gain_db: float
    limiter_ceiling_dbtp: float
    limiter_max_reduction_db: float
    limiter_reduction_seconds: float          # how long the limiter works harder than 1 dB
    glue_max_reduction_db: float
    bus_max_reduction_db: float
    iterations: int
    settings: MixSettings

    def as_dict(self) -> dict:
        return {
            "target_lufs": self.settings.target_lufs,
            "ceiling_dbtp": self.settings.ceiling_dbtp,
            "makeup_gain_db": round(self.gain_db, 2),
            "limiter_ceiling_dbtp": round(self.limiter_ceiling_dbtp, 2),
            "limiter_max_reduction_db": round(self.limiter_max_reduction_db, 2),
            "limiter_over_1db_seconds": round(self.limiter_reduction_seconds, 3),
            "glue_max_reduction_db": round(self.glue_max_reduction_db, 2),
            "bus_max_reduction_db": round(self.bus_max_reduction_db, 2),
            "loudness_iterations": self.iterations,
        }


# ── gain curves from known times ───────────────────────────────────────────

def pump_envelope(n: int, onsets: list[int], *, attack_ms: float = 4.0, release_ms: float = 150.0) -> np.ndarray:
    """0..1: rises over ``attack_ms`` to reach 1 ON each onset (the times are
    known, so the duck can start before the hit), then recovers exponentially.
    Overlapping hits take the maximum, never the sum."""
    env = np.zeros(n)
    a = max(1, n_of(attack_ms / 1000))
    r = release_ms / 1000 * SR
    length = int(5 * r)
    rise = np.linspace(0.0, 1.0, a, endpoint=False)
    fall = np.exp(-np.arange(length) / r)
    shape = np.concatenate([rise, fall])
    for s in onsets:
        start = s - a
        lo, hi = max(0, start), min(n, start + len(shape))
        if hi > lo:
            np.maximum(env[lo:hi], shape[lo - start: hi - start], out=env[lo:hi])
    return env


def sidechain_gain(n: int, kicks: list[int], logs: list[int], s: MixSettings) -> np.ndarray:
    """Linear gain for the keys bus."""
    reduction = (s.sidechain_kick_db * pump_envelope(n, kicks, release_ms=s.sidechain_release_ms)
                 + s.sidechain_log_db * pump_envelope(n, logs, release_ms=0.8 * s.sidechain_release_ms))
    return amp(-np.minimum(reduction, -s.sidechain_floor_db))


def duck_gain(n: int, clicks: list[int], *, depth_db: float = 3.0, hold_ms: float = 40.0,
              ramp_ms: float = 3.0) -> np.ndarray:
    """Linear gain: ``-depth_db`` for ``hold_ms`` from each click, ramped."""
    depth = np.zeros(n)
    hold = n_of(hold_ms / 1000)
    r = max(1, n_of(ramp_ms / 1000))
    shape = np.concatenate([np.linspace(0, 1, r, endpoint=False), np.ones(hold), np.linspace(1, 0, r)])
    for c in clicks:
        start = c - r
        lo, hi = max(0, start), min(n, start + len(shape))
        if hi > lo:
            np.maximum(depth[lo:hi], shape[lo - start: hi - start], out=depth[lo:hi])
    return amp(-depth_db * depth)


# ── dynamics ───────────────────────────────────────────────────────────────

def compress(x: np.ndarray, *, threshold_db: float, ratio: float, attack_ms: float, release_ms: float,
             knee_db: float = 6.0, block: int = 32) -> tuple[np.ndarray, float]:
    """Stereo-linked feed-forward compressor (RMS detector per 32-sample
    block, soft knee, attack/release smoothing in dB). Returns the output and
    the largest gain reduction in dB."""
    n = len(x)
    nb = -(-n // block)
    padded = np.zeros((nb * block, x.shape[1]))
    padded[:n] = x
    level = db(np.sqrt((padded.reshape(nb, block, -1) ** 2).mean(axis=1).max(axis=1)))
    over = level - threshold_db
    slope = 1.0 - 1.0 / ratio
    want = np.where(over <= -knee_db / 2, 0.0,
                    np.where(over >= knee_db / 2, -slope * over, -slope * (over + knee_db / 2) ** 2 / (2 * knee_db)))
    att = np.exp(-block / (attack_ms / 1000 * SR))
    rel = np.exp(-block / (release_ms / 1000 * SR))
    smooth = np.empty(nb)
    g = 0.0
    for k in range(nb):
        target = want[k]
        coef = att if target < g else rel
        g = target + (g - target) * coef
        smooth[k] = g
    centres = np.arange(nb) * block + block / 2
    gain_db = np.interp(np.arange(n), centres, smooth)
    return x * amp(gain_db)[:, None], float(-smooth.min()) if nb else 0.0


def loudest_block_db(x: np.ndarray, window: float = 0.4) -> float:
    """RMS level (dBFS) of the loudest ``window``-second stretch."""
    w = n_of(window)
    p = (x ** 2).mean(axis=1)
    c = np.concatenate([[0.0], np.cumsum(p)])
    if len(p) <= w:
        return float(db(np.sqrt(p.mean())))
    return float(db(np.sqrt(((c[w:] - c[:-w]) / w).max())))


def mono_bass(x: np.ndarray, below_hz: float) -> np.ndarray:
    """Fold everything under ``below_hz`` to mono: the side signal's lows are
    removed by a zero-phase low-pass (so side_high = side - side_low exactly,
    no phase shift between the bands). The low-pass is a 4th-order
    Butterworth at 1.3 x ``below_hz`` run forwards and backwards: the side is
    down 19 dB at 150 Hz, 34 dB at 120 Hz and 80+ dB at 60 Hz, and within
    1 dB from 250 Hz up."""
    mid = 0.5 * (x[:, 0] + x[:, 1])
    side = 0.5 * (x[:, 0] - x[:, 1])
    sos = signal.butter(4, 1.3 * below_hz, btype="lowpass", fs=SR, output="sos")
    side_high = side - signal.sosfiltfilt(sos, side)
    return np.stack([mid + side_high, mid - side_high], axis=1)


def limit(x: np.ndarray, ceiling_dbtp: float, *, lookahead_ms: float = 1.0, release_ms: float = 60.0,
          block: int = 16) -> tuple[np.ndarray, np.ndarray]:
    """True-peak limiter. Returns the output and the gain curve (linear)."""
    n = len(x)
    c = float(amp(ceiling_dbtp))
    tp = loudness.true_peak_envelope(x)
    need = np.minimum(1.0, c / np.maximum(tp, 1e-12))
    half = max(1, n_of(lookahead_ms / 1000))
    held = ndimage.minimum_filter1d(need, size=4 * half + 1, mode="nearest")
    nb = -(-n // block)
    padded = np.ones(nb * block)
    padded[:n] = held
    per_block = padded.reshape(nb, block).min(axis=1)
    recover = np.exp(-block / (release_ms / 1000 * SR))
    released = np.empty(nb)
    g = 1.0
    for k in range(nb):
        g = min(per_block[k], 1.0 - (1.0 - g) * recover)
        released[k] = g
    stepped = np.repeat(released, block)[:n]
    gain = ndimage.uniform_filter1d(stepped, size=2 * half + 1, mode="nearest")
    gain = np.minimum(gain, need)          # equal by construction; makes it explicit
    return x * gain[:, None], gain


# ── the master ─────────────────────────────────────────────────────────────

def premaster(render: Render, s: MixSettings | None = None) -> tuple[np.ndarray, dict]:
    """The buses summed and processed, before loudness and limiting."""
    s = s or MixSettings()
    st = {k: v * amp(s.bus_db.get(k, 0.0)) for k, v in render.stems.items()}
    n = render.samples
    kicks = render.onsets("kick")
    logs = render.onsets("log")
    clicks = render.onsets("click", "key", "tick")
    keys = st[KEYS] * sidechain_gain(n, kicks, logs, s)[:, None]
    log = st[LOG] * duck_gain(n, clicks, depth_db=s.duck_db, hold_ms=s.duck_ms)[:, None]
    drums = st[DRUMS] + log
    glue_threshold = loudest_block_db(drums) - 5.0
    drums, glue_gr = compress(drums, threshold_db=glue_threshold, ratio=2.0, attack_ms=12.0, release_ms=120.0)
    mix = drums + keys + st[FX] + st[UI]
    mix = mono_bass(mix, s.mono_below_hz)
    bus_threshold = loudest_block_db(mix) - 4.0
    mix, bus_gr = compress(mix, threshold_db=bus_threshold, ratio=1.5, attack_ms=20.0, release_ms=180.0)
    mix = filt(mix, "highpass", 20.0, order=2)
    mix = fade(mix, fade_out=n_of(s.end_fade_ms / 1000))
    return mix, {"glue": glue_gr, "bus": bus_gr}


def master(render: Render, s: MixSettings | None = None) -> Master:
    """Premaster -> loudness-normalised, true-peak-limited stereo master."""
    s = s or MixSettings()
    x, reductions = premaster(render, s)
    base = loudness.integrated(x)
    margin = s.limiter_margin_db
    iterations = 0
    for _ in range(6):
        gain = s.target_lufs - base
        for _ in range(12):
            iterations += 1
            y, g = limit(x * amp(gain), s.ceiling_dbtp - margin)
            measured = loudness.integrated(y)
            if abs(measured - s.target_lufs) <= 0.02:
                break
            gain += s.target_lufs - measured
        tp = loudness.true_peak_db(y)
        if tp <= s.ceiling_dbtp - 0.02:
            break
        margin += tp - s.ceiling_dbtp + 0.05
    reduction_db = -db(g)
    return Master(y, loudness.measure(y), float(gain), s.ceiling_dbtp - margin, float(reduction_db.max()),
                  float((reduction_db > 1.0).sum() / SR), reductions["glue"], reductions["bus"], iterations, s)
