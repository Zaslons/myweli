"""Loudness and true peak per ITU-R BS.1770-4 (and EBU Tech 3341 / 3342).

K-weighting
    Two biquads: a high shelf (+4 dB above ~1.5 kHz, the head) and the RLB
    high-pass (~38 Hz). Their 48-kHz coefficients are the ones printed in
    BS.1770-4 Annex 1; for another rate they are re-derived from the same
    analogue prototypes (bilinear transform), and at 48 kHz the derivation
    reproduces the printed values (tests/test_audio.py checks it).

Integrated loudness (gated)
    Mean square of the K-weighted signal over 400-ms blocks overlapping by
    75 %, per channel; block loudness l = -0.691 + 10 log10(sum G_i z_i)
    (G = 1 for left, right and centre). Blocks under -70 LKFS are dropped
    (absolute gate), then blocks under (the mean of what is left) - 10 LU
    (relative gate); the integrated loudness is the loudness of the mean of
    the remaining blocks' powers.

Momentary / short-term
    The same, ungated, over 400-ms / 3-s windows, every 100 ms.

Loudness range (EBU Tech 3342)
    Short-term values, absolute gate -70, relative gate -20 LU; LRA is the
    95th minus the 10th percentile.

True peak
    The signal oversampled 4x (a 193-tap Kaiser-windowed sinc that keeps the
    original samples exactly), the largest absolute value, in dBTP. As
    BS.1770 notes, 4x can under-read a peak lying between the oversampled
    points by a fraction of a dB at the top of the band (0.18 dB for a 16-kHz
    tone at its worst phase); the master's ceiling keeps that margin.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

import numpy as np
from scipy import signal

ABS_GATE = -70.0
REL_GATE = -10.0
LRA_REL_GATE = -20.0
OFFSET = -0.691

# BS.1770-4 Annex 1, Tables 1 and 2: the K filter at 48 kHz.
SHELF_48K = (np.array([1.53512485958697, -2.69169618940638, 1.19839281085285]),
             np.array([1.0, -1.69065929318241, 0.73248077421585]))
RLB_48K = (np.array([1.0, -2.0, 1.0]),
           np.array([1.0, -1.99004745483398, 0.99007225036621]))

# The analogue prototypes behind those tables (as derived in the literature,
# e.g. pyloudnorm / libebur128): shelf gain, Q and frequency; high-pass Q and
# frequency.
_SHELF = dict(gain_db=3.999843853973347, q=0.7071752369554196, f=1681.974450955533)
_RLB = dict(q=0.5003270373238773, f=38.13547087602444)


def k_filter(fs: int = 48_000) -> list[tuple[np.ndarray, np.ndarray]]:
    """The two K-weighting biquads [(b, a), (b, a)] at sample rate ``fs``."""
    if fs == 48_000:
        return [SHELF_48K, RLB_48K]
    return k_filter_derived(fs)


def k_filter_derived(fs: int) -> list[tuple[np.ndarray, np.ndarray]]:
    """K-weighting re-derived for any rate from the analogue prototypes."""
    k = np.tan(np.pi * _SHELF["f"] / fs)
    vh = 10 ** (_SHELF["gain_db"] / 20)
    vb = vh ** 0.4996667741545416
    q = _SHELF["q"]
    a0 = 1 + k / q + k * k
    shelf_b = np.array([(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0])
    shelf_a = np.array([1.0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0])
    k = np.tan(np.pi * _RLB["f"] / fs)
    q = _RLB["q"]
    a0 = 1 + k / q + k * k
    rlb_b = np.array([1.0, -2.0, 1.0])
    rlb_a = np.array([1.0, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0])
    return [(shelf_b, shelf_a), (rlb_b, rlb_a)]


def _channels(x: np.ndarray) -> np.ndarray:
    x = np.asarray(x, dtype=float)
    return x[:, None] if x.ndim == 1 else x


def k_weight(x: np.ndarray, fs: int = 48_000) -> np.ndarray:
    y = _channels(x)
    for b, a in k_filter(fs):
        y = signal.lfilter(b, a, y, axis=0)
    return y


def _window_powers(x: np.ndarray, fs: int, window: float, hop: float) -> np.ndarray:
    """Mean square per channel of K-weighted ``x`` over sliding windows:
    shape (blocks, channels). Only whole windows."""
    y = k_weight(x, fs)
    w = int(round(window * fs))
    h = int(round(hop * fs))
    if len(y) < w:
        return np.zeros((0, y.shape[1]))
    c = np.concatenate([np.zeros((1, y.shape[1])), np.cumsum(y ** 2, axis=0)])
    starts = np.arange(0, len(y) - w + 1, h)
    return (c[starts + w] - c[starts]) / w


def _lufs(power_sum: np.ndarray | float) -> np.ndarray | float:
    return OFFSET + 10 * np.log10(np.maximum(power_sum, 1e-30))


def _weights(channels: int) -> np.ndarray:
    # L, R, C weigh 1; Ls, Rs (channels 4 and 5 of a 5.1 layout) weigh 1.41
    g = np.ones(channels)
    if channels == 6:
        g[4:6] = 1.41
        g[3] = 0.0           # LFE is not measured
    return g


def integrated(x: np.ndarray, fs: int = 48_000) -> float:
    """Integrated loudness in LUFS (gated, BS.1770-4)."""
    z = _window_powers(x, fs, 0.4, 0.1)
    if not len(z):
        return float("-inf")
    g = _weights(z.shape[1])
    lj = _lufs(z @ g)
    keep = lj > ABS_GATE
    if not keep.any():
        return float("-inf")
    gamma_r = _lufs(z[keep].mean(axis=0) @ g) + REL_GATE
    keep &= lj > gamma_r
    if not keep.any():
        return float("-inf")
    return float(_lufs(z[keep].mean(axis=0) @ g))


def momentary(x: np.ndarray, fs: int = 48_000) -> np.ndarray:
    """Momentary loudness (400 ms) every 100 ms, LUFS."""
    z = _window_powers(x, fs, 0.4, 0.1)
    return _lufs(z @ _weights(z.shape[1])) if len(z) else np.zeros(0)


def short_term(x: np.ndarray, fs: int = 48_000) -> np.ndarray:
    """Short-term loudness (3 s) every 100 ms, LUFS."""
    z = _window_powers(x, fs, 3.0, 0.1)
    return _lufs(z @ _weights(z.shape[1])) if len(z) else np.zeros(0)


def loudness_range(x: np.ndarray, fs: int = 48_000) -> float:
    """LRA in LU (EBU Tech 3342)."""
    z = _window_powers(x, fs, 3.0, 0.1)
    if not len(z):
        return 0.0
    g = _weights(z.shape[1])
    st = _lufs(z @ g)
    keep = st > ABS_GATE
    if keep.sum() < 2:
        return 0.0
    rel = _lufs(z[keep].mean(axis=0) @ g) + LRA_REL_GATE
    vals = st[keep & (st > rel)]
    if len(vals) < 2:
        return 0.0
    lo, hi = np.percentile(vals, [10, 95])
    return float(hi - lo)


# ── true peak ──────────────────────────────────────────────────────────────

OVERSAMPLE = 4


def _oversampling_fir(up: int = OVERSAMPLE, taps_per_phase: int = 48) -> np.ndarray:
    """A Kaiser-windowed sinc cut at the original Nyquist: its taps at
    multiples of ``up`` are zero, so the original samples pass unchanged and
    only the samples between them are interpolated (no per-phase gain
    ripple, no over-read). ``resample_poly`` applies the gain of ``up``."""
    numtaps = up * taps_per_phase + 1
    return signal.firwin(numtaps, cutoff=1.0 / up, window=("kaiser", 9.0))


_FIR = _oversampling_fir()


def oversample(x: np.ndarray, up: int = OVERSAMPLE) -> np.ndarray:
    """``x`` at ``up`` times its rate (time axis first)."""
    fir = _FIR if up == OVERSAMPLE else _oversampling_fir(up)
    return signal.resample_poly(_channels(x), up, 1, axis=0, window=fir)


def true_peak_envelope(x: np.ndarray) -> np.ndarray:
    """Per input sample, the largest absolute value of the 4x-oversampled
    signal around it (all channels): shape (n,)."""
    y = np.abs(oversample(x))
    n = len(_channels(x))
    y = y[: n * OVERSAMPLE].reshape(n, OVERSAMPLE, -1)
    return y.max(axis=(1, 2))


def true_peak(x: np.ndarray) -> float:
    """True peak, linear (BS.1770-4 Annex 2, 4x oversampling)."""
    return float(np.max(np.abs(oversample(x)))) if len(x) else 0.0


def true_peak_db(x: np.ndarray) -> float:
    return float(20 * np.log10(max(true_peak(x), 1e-12)))


def sample_peak_db(x: np.ndarray) -> float:
    return float(20 * np.log10(max(float(np.max(np.abs(x))) if len(x) else 0.0, 1e-12)))


@dataclass
class Loudness:
    integrated_lufs: float
    short_term_max_lufs: float
    momentary_max_lufs: float
    true_peak_dbtp: float
    sample_peak_dbfs: float
    lra_lu: float

    def as_dict(self) -> dict:
        return {k: round(v, 2) for k, v in asdict(self).items()}


def measure(x: np.ndarray, fs: int = 48_000) -> Loudness:
    m = momentary(x, fs)
    s = short_term(x, fs)
    return Loudness(integrated(x, fs),
                    float(s.max()) if len(s) else float("-inf"),
                    float(m.max()) if len(m) else float("-inf"),
                    true_peak_db(x), sample_peak_db(x), loudness_range(x, fs))
