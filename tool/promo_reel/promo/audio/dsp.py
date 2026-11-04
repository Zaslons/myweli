"""DSP building blocks shared by the instruments, the mix and the meters.

Everything is NumPy/SciPy, mono arrays are shape ``(n,)`` and stereo arrays
``(n, 2)``, at 48 kHz. Randomness is always seeded from a *name* (``rng("hat",
3, 7)``), so a render is bit-for-bit reproducible and two hits never share
the same noise by accident.
"""

from __future__ import annotations

import hashlib
from functools import lru_cache

import numpy as np
from scipy import signal

from ..timebase import SAMPLE_RATE

SR = SAMPLE_RATE
TWO_PI = 2.0 * np.pi
LN_1000 = np.log(1000.0)          # amplitude falls 60 dB over RT60: exp(-ln(1000) t / RT60)


# ── units ──────────────────────────────────────────────────────────────────

def amp(db: float | np.ndarray) -> float | np.ndarray:
    """dB -> linear amplitude."""
    return 10.0 ** (np.asarray(db, dtype=float) / 20.0)


def db(a: float | np.ndarray, floor: float = 1e-12) -> float | np.ndarray:
    """Linear amplitude -> dB (floored, never -inf)."""
    return 20.0 * np.log10(np.maximum(np.abs(np.asarray(a, dtype=float)), floor))


def n_of(seconds: float) -> int:
    """Seconds -> a whole number of samples (at least one)."""
    return max(1, int(round(seconds * SR)))


def seconds(n: int) -> np.ndarray:
    return np.arange(n, dtype=float) / SR


def rng(*key: object) -> np.random.Generator:
    """A generator seeded from a readable key, e.g. ``rng("shaker", bar, step)``."""
    digest = hashlib.sha256("\x1f".join(map(str, key)).encode()).digest()
    return np.random.default_rng(int.from_bytes(digest[:8], "little"))


def noise(n: int, *key: object) -> np.ndarray:
    return rng("noise", *key).standard_normal(n)


# ── envelopes ──────────────────────────────────────────────────────────────

def ramp(n: int, length: int) -> np.ndarray:
    """0 -> 1 over ``length`` samples (raised cosine), then 1."""
    out = np.ones(n)
    k = min(n, max(0, int(length)))
    if k:
        out[:k] = 0.5 - 0.5 * np.cos(np.pi * np.arange(k) / k)
    return out


def decay(n: int, tau: float, attack: float = 0.0005) -> np.ndarray:
    """Attack ramp (seconds) into an exponential decay of time constant ``tau``."""
    return ramp(n, n_of(attack)) * np.exp(-seconds(n) / max(tau, 1e-6))


def gate_release(n: int, gate: int, release: float, attack: float = 0.002) -> np.ndarray:
    """1 until ``gate`` samples, then an exponential release; attack ramp at the start."""
    env = ramp(n, n_of(attack))
    if gate < n:
        tail = np.exp(-np.arange(n - gate) / (release * SR))
        env[gate:] *= tail
    return env


def fade(x: np.ndarray, fade_in: int = 0, fade_out: int = 0) -> np.ndarray:
    """A copy of ``x`` with raised-cosine fades at either end (in samples)."""
    y = np.array(x, dtype=float, copy=True)
    n = len(y)
    if fade_in:
        k = min(n, fade_in)
        w = 0.5 - 0.5 * np.cos(np.pi * np.arange(k) / k)
        y[:k] = (y[:k].T * w).T
    if fade_out:
        k = min(n, fade_out)
        w = 0.5 + 0.5 * np.cos(np.pi * (np.arange(k) + 1) / k)
        y[n - k:] = (y[n - k:].T * w).T
    return y


# ── oscillators ────────────────────────────────────────────────────────────

def phase(freq: float | np.ndarray, n: int | None = None, start: float = 0.0) -> np.ndarray:
    """Running phase in radians of an oscillator at ``freq`` Hz (scalar or per
    sample). ``phase[0] == start`` so a sine starts on its zero crossing."""
    f = np.asarray(freq, dtype=float)
    if f.ndim == 0:
        if n is None:
            raise ValueError("phase(): a constant frequency needs a length n")
        f = np.full(n, float(f))
    steps = TWO_PI * f / SR
    out = np.empty(len(f))
    out[0] = start
    np.cumsum(steps[:-1], out=out[1:])
    out[1:] += start
    return out


def saw(freq: float | np.ndarray, n: int, start: float = 0.0) -> np.ndarray:
    """Band-limited sawtooth (PolyBLEP), -1..1."""
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    dt = np.clip(f / SR, 1e-9, 0.5)
    ph = (start + np.concatenate(([0.0], np.cumsum(dt[:-1])))) % 1.0
    y = 2.0 * ph - 1.0
    lo = ph < dt
    t = ph[lo] / dt[lo]
    y[lo] -= t + t - t * t - 1.0
    hi = ph > 1.0 - dt
    t = (ph[hi] - 1.0) / dt[hi]
    y[hi] -= t * t + t + t + 1.0
    return y


def square(freq: float, n: int, start: float = 0.0, top: float = 18_000.0) -> np.ndarray:
    """Band-limited square wave by additive synthesis (odd harmonics below ``top``)."""
    t = seconds(n)
    y = np.zeros(n)
    k = 1
    while k * freq < top:
        y += np.sin(TWO_PI * k * freq * t + k * start) / k
        k += 2
    return y * (4.0 / np.pi)


# ── filters ────────────────────────────────────────────────────────────────

def _clamp_f(f: float) -> float:
    return float(np.clip(f, 10.0, 0.45 * SR))


def biquad(kind: str, f: float, q: float = 0.7071, gain_db: float = 0.0) -> tuple[np.ndarray, np.ndarray]:
    """RBJ cookbook biquad coefficients (b, a), normalised so a[0] == 1."""
    w0 = TWO_PI * _clamp_f(f) / SR
    cw, sw = np.cos(w0), np.sin(w0)
    alpha = sw / (2.0 * q)
    if kind == "lowpass":
        b = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "highpass":
        b = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "bandpass":                       # 0 dB at the centre
        b = [alpha, 0.0, -alpha]
        a = [1 + alpha, -2 * cw, 1 - alpha]
    elif kind == "peak":
        A = 10 ** (gain_db / 40)
        b = [1 + alpha * A, -2 * cw, 1 - alpha * A]
        a = [1 + alpha / A, -2 * cw, 1 - alpha / A]
    else:
        raise ValueError(f"unknown biquad kind {kind!r}")
    b = np.asarray(b) / a[0]
    a = np.asarray(a) / a[0]
    return b, a


def filt(x: np.ndarray, kind: str, f: float | tuple[float, float], order: int = 2) -> np.ndarray:
    """Butterworth filter along time: ``lowpass``/``highpass`` at ``f`` Hz, or
    ``bandpass`` between ``f = (lo, hi)``."""
    if kind == "bandpass":
        lo, hi = f
        sos = signal.butter(order, [_clamp_f(lo), _clamp_f(hi)], btype="bandpass", fs=SR, output="sos")
    else:
        sos = signal.butter(order, _clamp_f(f), btype=kind, fs=SR, output="sos")
    return signal.sosfilt(sos, x, axis=0)


def sweep(x: np.ndarray, kind: str, freq: np.ndarray | float, q: float = 0.7071, block: int = 32) -> np.ndarray:
    """A biquad whose frequency moves over time (one value per sample, read at
    the centre of each ``block``). The filter state is carried across blocks."""
    x = np.asarray(x, dtype=float)
    n = len(x)
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    y = np.empty_like(x)
    zi = np.zeros((2,) + x.shape[1:])
    for start in range(0, n, block):
        end = min(n, start + block)
        b, a = biquad(kind, f[(start + end) // 2], q)
        y[start:end], zi = signal.lfilter(b, a, x[start:end], axis=0, zi=zi)
    return y


def exp_curve(start: float, end: float, n: int, shape: float = 1.0) -> np.ndarray:
    """``start`` -> ``end`` exponentially (equal ratios per sample) over ``n``
    samples; ``shape`` > 1 lingers near ``start``."""
    u = np.linspace(0.0, 1.0, n) ** shape
    return start * (end / start) ** u


# ── space ──────────────────────────────────────────────────────────────────

def pan(mono: np.ndarray, position: float | np.ndarray = 0.0) -> np.ndarray:
    """Constant-power pan, ``position`` -1 (left) .. +1 (right), scalar or per
    sample, normalised so a centred sound is at unity in each channel (the
    mono fold-down of a centred sound is the sound itself)."""
    theta = (np.clip(position, -1.0, 1.0) + 1.0) * (np.pi / 4.0)
    g = np.sqrt(2.0)
    return np.stack([mono * (g * np.cos(theta)), mono * (g * np.sin(theta))], axis=1)


def as_stereo(x: np.ndarray) -> np.ndarray:
    """Mono -> centred stereo (unity in each channel); stereo passes through."""
    return np.stack([x, x], axis=1) if x.ndim == 1 else x


@lru_cache(maxsize=32)
def reverb_ir(rt60: float, seed: str = "room", predelay: float = 0.012, hf: float = 0.45,
              lf: float = 1.1, length: float | None = None) -> np.ndarray:
    """A synthetic stereo impulse response with the given RT60 (seconds).

    Three bands of decorrelated Gaussian noise decay at their own rates — the
    lows at ``lf`` x RT60, the mids at RT60, the highs at ``hf`` x RT60 (air
    absorbs highs first) — after a diffuse build-up and a few early
    reflections. The tail is high-passed at 120 Hz so the reverb never muddies
    the mono sub. Energy is normalised to 1 per channel, so a send's level is
    its wet gain. The array is cached and read-only.
    """
    length = length if length is not None else min(1.2 * rt60, 6.0)
    n = n_of(length)
    t = seconds(n)
    out = np.zeros((n, 2))
    for ch in range(2):
        g = rng("ir", seed, rt60, ch)
        wn = g.standard_normal(n)
        low = filt(wn, "lowpass", 400.0) * np.exp(-LN_1000 * t / (lf * rt60))
        mid = filt(wn, "bandpass", (400.0, 4000.0)) * np.exp(-LN_1000 * t / rt60)
        high = filt(wn, "highpass", 4000.0) * np.exp(-LN_1000 * t / (hf * rt60))
        tail = (low + mid + high) * ramp(n, n_of(0.018))
        for _ in range(6):                                  # early reflections
            k = int(g.uniform(0.004, 0.060) * SR)
            tail[k] += g.choice([-1.0, 1.0]) * g.uniform(0.6, 1.4) * 4.0 * np.exp(-k / (0.08 * SR))
        out[:, ch] = tail
    out = filt(out, "highpass", 120.0)
    out /= np.sqrt(np.sum(out ** 2, axis=0, keepdims=True))
    out = np.concatenate([np.zeros((n_of(predelay), 2)), out])
    out.flags.writeable = False
    return out


def reverb(x: np.ndarray, rt60: float, wet_db: float, seed: str = "room", dry: bool = False) -> np.ndarray:
    """Stereo reverb return of ``x`` (mono or stereo), ``wet_db`` below unity.
    With ``dry=True`` the dry signal is added (as stereo)."""
    ir = reverb_ir(round(float(rt60), 3), seed)
    xs = as_stereo(x)
    wet = np.stack([signal.fftconvolve(xs[:, c], ir[:, c]) for c in range(2)], axis=1)
    wet *= amp(wet_db)
    if dry:
        wet[: len(xs)] += xs
    return wet


def schroeder_rt60(ir: np.ndarray, top_db: float = -5.0, bottom_db: float = -35.0) -> float:
    """RT60 of an impulse response by Schroeder backward integration (T30 fit)."""
    e = np.asarray(ir, dtype=float)
    if e.ndim == 2:
        e = e.mean(axis=1)
    edc = np.cumsum((e ** 2)[::-1])[::-1]
    edc_db = 10 * np.log10(edc / edc[0] + 1e-30)
    i0 = int(np.argmax(edc_db <= top_db))
    i1 = int(np.argmax(edc_db <= bottom_db))
    t = np.arange(i0, i1) / SR
    slope, _ = np.polyfit(t, edc_db[i0:i1], 1)
    return -60.0 / slope


# ── pitch ──────────────────────────────────────────────────────────────────

def midi_hz(m: float) -> float:
    """MIDI note -> Hz (A4 = 69 = 440 Hz; C2 = 36 = 65.41 Hz)."""
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)
