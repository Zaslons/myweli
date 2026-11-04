"""Every sound of the promo, synthesised (storyboard « Music plan »).

Each function returns a NumPy array at 48 kHz — mono ``(n,)`` or stereo
``(n, 2)`` — whose FIRST sample is the sound's onset: the arranger puts that
sample exactly on the cue's grid sample, so what SCENES reads in events.json is
where the sound starts. Nothing here knows about bars or positions; lengths
are in seconds or samples, pitches in Hz, levels in dB, ``vel`` 0..1.

All randomness comes from ``seed`` (any hashable text), so a render is
reproducible to the bit.

Drums       log_drum, kick, clap, shaker, hat, conga, rim
Keys        rhodes_note, organ_note, leslie, whistle_note, pad_chord, sub_note
Effects     riser, impact, whoosh, reverse_cymbal, pen_scratch, pen_slash
Interface   ui_click, key_click, tick, pop, thock, card_pop, chime, glint,
            kalimba, shimmer, fm_glide

Every sound is original: no sample, no OS sound, no copied melody.
"""

from __future__ import annotations

from functools import lru_cache

import numpy as np

from .dsp import (SR, TWO_PI, amp, decay, exp_curve, filt, gate_release, n_of, noise, pan, phase,
                  ramp, reverb, rng, saw, seconds, square, sweep)


def _vel(v: float) -> float:
    """Velocity -> amplitude (a gentle curve: 0.5 is about -7 dB)."""
    return float(np.clip(v, 0.0, 1.0)) ** 1.2


def _tail(x: np.ndarray, ms: float = 2.0) -> np.ndarray:
    """Fade the last ``ms`` so a cut-off sound never clicks."""
    k = min(len(x), n_of(ms / 1000))
    w = 0.5 + 0.5 * np.cos(np.pi * (np.arange(k) + 1) / k)
    x[len(x) - k:] = (x[len(x) - k:].T * w).T
    return x


# ══ drums ══════════════════════════════════════════════════════════════════

def log_drum(freq: float, vel: float = 0.85, *, length: float | None = None, decay_s: float = 0.20,
             glide_from: float | None = None, glide_s: float = 0.07, index: float = 3.0,
             index_tau: float = 0.015, index_floor: float = 0.8, pitch_amount: float = 2.0, pitch_tau: float = 0.012,
             wood_ratio: float = 2.4, wood_db: float = -6.0, wood_tau: float = 0.030, drive: float = 3.0,
             sub_db: float = -2.0, lp: float | None = None, octave_db: float | None = None) -> np.ndarray:
    """The amapiano log drum (mono).

    A two-operator FM voice at ratio 1 — the modulator IS the carrier's own
    phase, so the spectrum stays harmonic — whose index starts at ``index``
    (2-4) and decays with ``index_tau`` (gone within 30-60 ms) down to
    ``index_floor``: a bright, woody attack that settles into a round, slightly
    nasal tone (2nd and 3rd harmonics) that a phone speaker can still carry.
    The pitch starts high and drops (f(t) = f0 (1 + A e^(-t/tau)), A ~ 2,
    tau 8-20 ms), a wood partial at ~2.4 f0 knocks for ~30 ms, and the body
    goes through a tanh drive of 3 AFTER the amplitude envelope, so the hit
    is gritty and the tail clean.

    The sub is a pure sine on the SAME running phase as the carrier — pitch
    drop included — so it can never cancel the body's fundamental. It is not
    driven and not low-passed: on a phone the log is heard through its
    harmonics, on a system through the sub.

    ``glide_from`` slides the base pitch from another note (G1 -> C2 on the
    third strike); ``lp`` low-passes the driven body (the hook's 600 Hz
    stab); ``octave_db`` adds the octave above (the end card's « C2 + octave »).
    """
    length = length if length is not None else min(7.0 * decay_s + 0.02, 3.5)
    n = n_of(length)
    t = seconds(n)
    if glide_from:
        u = np.clip(t / glide_s, 0.0, 1.0)
        u = u * u * (3.0 - 2.0 * u)
        base = glide_from * (freq / glide_from) ** u
    else:
        base = np.full(n, float(freq))
    f = base * (1.0 + pitch_amount * np.exp(-t / pitch_tau))
    ph = phase(f)
    v = float(np.clip(vel, 0.0, 1.0))
    index_t = index_floor + (index - index_floor) * (0.55 + 0.45 * v) * np.exp(-t / index_tau)
    body = np.sin(ph + index_t * np.sin(ph))
    body += amp(wood_db) * np.exp(-t / wood_tau) * np.sin(wood_ratio * ph)
    if octave_db is not None:
        body += amp(octave_db) * np.sin(2.0 * ph + 0.5 * index_t * np.sin(2.0 * ph))
    env = decay(n, decay_s, attack=0.0008)
    driven = np.tanh(drive * env * body) / np.tanh(drive)
    if lp:
        driven = filt(driven, "lowpass", lp, order=2)
    sub = amp(sub_db) * env * np.sin(ph)
    return _tail((driven + sub) * _vel(v))


def kick(vel: float = 0.85, *, f_start: float = 165.0, f_end: float = 45.0, tau: float = 0.030,
         decay_s: float = 0.20, click_db: float = -12.0, drive: float = 1.5, seed: object = 0) -> np.ndarray:
    """909-style kick (mono): a sine swept 165 -> 45 Hz (tau 30 ms) plus a 1-ms click."""
    n = n_of(min(7 * decay_s, 1.2))
    t = seconds(n)
    f = f_end + (f_start - f_end) * np.exp(-t / tau)
    body = np.sin(phase(f)) * decay(n, decay_s, attack=0.0003)
    body = np.tanh(drive * body) / np.tanh(drive)
    k = n_of(0.001)
    click = np.zeros(n)
    click[:k] = filt(noise(k, "kick-click", seed), "highpass", 1500.0) * np.linspace(1.0, 0.0, k)
    return _tail((body + amp(click_db) * 4.0 * click) * _vel(vel))


def clap(vel: float = 0.85, *, seed: object = 0, bursts: int = 3, spacing: float = 0.010,
         tail: float = 0.09, band: tuple[float, float] = (1000.0, 2500.0)) -> np.ndarray:
    """Clap (mono): three noise bursts 10 ms apart and a 60-120 ms tail, band-passed 1-2.5 kHz."""
    n = n_of(spacing * (bursts - 1) + 4.0 * tail)
    t = seconds(n)
    env = np.zeros(n)
    for k in range(bursts):
        t0 = k * spacing
        on = t >= t0
        env[on] += np.exp(-(t[on] - t0) / 0.0028)
    t_last = spacing * (bursts - 1)
    on = t >= t_last
    env[on] += 0.85 * np.exp(-(t[on] - t_last) / (tail / 3.0))
    y = filt(noise(n, "clap", seed), "bandpass", band, order=2) * env
    y += 0.2 * filt(noise(n, "clap-air", seed), "bandpass", (3000.0, 8000.0)) * env   # a little air on top
    return _tail(y * 1.6 * _vel(vel))


def shaker(vel: float = 0.8, *, seed: object = 0, attack: float = 0.004, tau: float = 0.020,
           band: tuple[float, float] = (4000.0, 12000.0)) -> np.ndarray:
    """Shaker (mono): noise band-passed 4-12 kHz with a soft 4-ms attack."""
    n = n_of(attack + 6 * tau)
    t = seconds(n)
    env = np.where(t < attack, t / attack, np.exp(-(t - attack) / tau))
    return _tail(filt(noise(n, "shaker", seed), "bandpass", band, order=2) * env * 1.8 * _vel(vel))


_808_METAL = (205.3, 304.4, 369.6, 522.7, 540.0, 800.0)     # the six square oscillators


@lru_cache(maxsize=4)
def _metal(n: int) -> np.ndarray:
    starts = rng("808-metal").uniform(0, TWO_PI, len(_808_METAL))
    y = sum(square(f, n, s) for f, s in zip(_808_METAL, starts)) / len(_808_METAL)
    y = filt(y, "bandpass", (6500.0, 13000.0), order=2)
    y.flags.writeable = False
    return y


def hat(vel: float = 0.8, *, open_: bool = True, seed: object = 0) -> np.ndarray:
    """808-style hat (mono): six square waves at the 808's metal frequencies,
    band-passed, plus high-passed noise. Open: ~110-ms decay; closed: ~18 ms."""
    tau = 0.11 if open_ else 0.018
    n = n_of(min(6 * tau, 0.7))
    env = decay(n, tau, attack=0.0005)
    metal = _metal(n_of(0.7))[:n]
    hiss = filt(noise(n, "hat", seed), "bandpass", (7000.0, 12000.0))
    return _tail((0.9 * metal + 0.45 * hiss) * env * _vel(vel))


def conga(vel: float = 0.8, *, stroke: str = "h", seed: object = 0) -> np.ndarray:
    """Conga (mono): two modal sines with a small pitch drop, and a slap.

    ``h`` high open (quinto, ~330 Hz), ``l`` low open (~220 Hz), ``m`` muted
    high, ``s`` slap (a damped body under a bright 6-ms noise crack).
    """
    stroke = stroke.lower()
    f0 = {"h": 330.0, "l": 220.0, "m": 330.0, "s": 345.0}[stroke]
    tau1 = {"h": 0.09, "l": 0.11, "m": 0.030, "s": 0.040}[stroke]
    n = n_of(min(6 * tau1, 1.0))
    t = seconds(n)
    bend = 1.0 + 0.07 * np.exp(-t / 0.012)
    ph = phase(f0 * bend)
    y = np.sin(ph) * np.exp(-t / tau1) + 0.35 * np.sin(1.52 * ph) * np.exp(-t / (tau1 * 0.35))
    y *= ramp(n, n_of(0.0006))
    if stroke == "s":
        crack = filt(noise(n, "slap", seed), "bandpass", (1500.0, 6000.0)) * np.exp(-t / 0.006)
        y = 0.6 * y + 1.4 * crack
    return _tail(y * _vel(vel))


def rim(vel: float = 0.8, *, seed: object = 0) -> np.ndarray:
    """Dry rim tick (mono): 1.67 kHz and 455 Hz tones, 7-ms decay, a noise click."""
    n = n_of(0.05)
    t = seconds(n)
    tone = (0.65 * np.sin(TWO_PI * 1667.0 * t) + 0.45 * np.sin(TWO_PI * 455.0 * t)) * np.exp(-t / 0.007)
    click = filt(noise(n, "rim", seed), "highpass", 3000.0) * np.exp(-t / 0.0008)
    y = filt(tone + 0.8 * click, "bandpass", (500.0, 7000.0))
    return _tail(np.tanh(2.0 * y) * _vel(vel))


# ══ keys ═══════════════════════════════════════════════════════════════════

def rhodes_note(freq: float, vel: float, gate: int, *, release: float = 0.16) -> np.ndarray:
    """FM electric piano note (mono), DX-style: a ratio-1 pair whose index
    falls with time (the bark), plus a ratio-14 tine for the bell attack.
    The note rings with a pitch-dependent decay while held (``gate``
    samples), then releases."""
    tau = float(np.clip(2.2 * (196.0 / freq) ** 0.6, 0.6, 3.0))
    n = gate + n_of(5 * release)
    t = seconds(n)
    v = float(np.clip(vel, 0.0, 1.0))
    ph = phase(freq, n)
    index_t = (0.5 + 2.0 * v) * np.exp(-t / 0.5) + 0.35
    tone = np.sin(ph + index_t * np.sin(ph))
    tine = np.sin(ph + 1.4 * np.exp(-t / 0.010) * np.sin(14.0 * ph)) * np.exp(-t / 0.030) * 0.16 * v
    env = np.exp(-t / tau) * gate_release(n, gate, release, attack=0.0015)
    y = (tone + tine) * env
    return _tail(np.tanh(1.3 * y) / np.tanh(1.3) * _vel(v))


_FOOTAGE = (0.5, 1.5, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0)          # 16' 5⅓' 8' 4' 2⅔' 2' 1⅗' 1⅓' 1'


def organ_note(freq: float, vel: float, gate: int, *, drawbars: str = "888400000",
               percussion: bool = True, seed: object = 0) -> np.ndarray:
    """Tonewheel-style organ note (mono): nine drawbar sines (each drawbar step
    is 3 dB), a decaying 3rd-harmonic percussion and a key click. Feed the
    track through ``leslie`` for the rotor."""
    n = gate + n_of(0.03)
    t = seconds(n)
    g = rng("organ", seed)
    y = np.zeros(n)
    for ratio, level in zip(_FOOTAGE, drawbars):
        lv = int(level)
        if lv and freq * ratio < 16000:
            y += amp(-3.0 * (8 - lv)) * np.sin(TWO_PI * freq * ratio * t + g.uniform(0, TWO_PI))
    if percussion:
        y += 0.6 * np.sin(TWO_PI * 3.0 * freq * t) * np.exp(-t / 0.18)
    y /= 3.5
    click = filt(noise(n_of(0.004), "organ-click", seed), "bandpass", (1200.0, 5000.0))
    y[: len(click)] += 0.25 * click * np.exp(-seconds(len(click)) / 0.0015)
    env = gate_release(n, gate, 0.012, attack=0.002)
    return _tail(y * env * _vel(vel))


def leslie(x: np.ndarray, rate: float = 6.0, depth_ms: float = 0.35, am: float = 0.22) -> np.ndarray:
    """A Leslie-style rotor (mono -> stereo): a 6-Hz modulated delay (Doppler)
    and amplitude, the two channels in quadrature."""
    n = len(x)
    t = seconds(n)
    idx = np.arange(n, dtype=float)
    out = np.empty((n, 2))
    for ch, offset in enumerate((0.0, np.pi / 2)):
        lfo = np.sin(TWO_PI * rate * t + offset)
        delay = (depth_ms / 1000.0) * SR * (1.0 + lfo)
        out[:, ch] = np.interp(idx - delay, idx, x, left=0.0) * (1.0 - am / 2 + (am / 2) * lfo)
    return out


def whistle_note(freq: float, vel: float, gate: int, *, vibrato_hz: float = 5.6, vibrato_cents: float = 28.0,
                 scoop_cents: float = -60.0, seed: object = 0) -> np.ndarray:
    """Synth whistle (mono): a sine that scoops up into pitch, with a vibrato
    that arrives after ~90 ms, a breath of band-passed noise, soft attack."""
    n = gate + n_of(0.25)
    t = seconds(n)
    cents = scoop_cents * np.exp(-t / 0.035)
    cents += vibrato_cents * np.sin(TWO_PI * vibrato_hz * t) * np.clip((t - 0.09) / 0.12, 0.0, 1.0)
    ph = phase(freq * 2.0 ** (cents / 1200.0))
    tone = np.sin(ph) + 0.05 * np.sin(2.0 * ph)
    breath = filt(noise(n, "whistle", seed), "bandpass", (0.85 * freq, 1.6 * freq)) * 0.07
    env = gate_release(n, gate, 0.05, attack=0.025)
    return _tail((tone + breath) * env * _vel(vel))


def pad_chord(freqs: list[float], vel: float, gate: int, *, cutoff: float = 1300.0, attack: float = 0.35,
              release: float = 0.6, detune_cents: tuple[float, ...] = (-11.0, -4.0, 4.0, 11.0),
              seed: object = 0) -> np.ndarray:
    """Detuned-saw pad (stereo): four PolyBLEP saws per note, spread left and
    right, low-passed at ``cutoff``; slow attack and release."""
    n = gate + n_of(4 * release)
    g = rng("pad", seed)
    out = np.zeros((n, 2))
    for f in freqs:
        for k, cents in enumerate(detune_cents):
            s = saw(f * 2.0 ** (cents / 1200.0), n, start=g.uniform())
            out += pan(s, -0.6 if k % 2 == 0 else 0.6)
    out = filt(out, "lowpass", cutoff, order=2)
    env = gate_release(n, gate, release, attack=attack)
    out *= (env / (len(freqs) * len(detune_cents)) ** 0.5 * 0.5 * _vel(vel))[:, None]
    return _tail(out)


def sub_note(freq: float, vel: float, gate: int, *, attack: float = 0.12, release: float = 0.5) -> np.ndarray:
    """A held sine sub (mono)."""
    n = gate + n_of(5 * release)
    env = gate_release(n, gate, release, attack=attack)
    return _tail(np.sin(phase(freq, n)) * env * _vel(vel))


# ══ effects ════════════════════════════════════════════════════════════════

def _gate_curve(n: int, cells: list[tuple[int, int]], duty: float = 0.55, edge: float = 0.002) -> np.ndarray:
    """A rhythmic on/off gate. ``cells`` = [(from_sample, cell_samples), ...]:
    from each start the gate opens at the start of every cell for ``duty`` of it."""
    out = np.zeros(n)
    bounds = [c[0] for c in cells[1:]] + [n]
    e = max(1, n_of(edge))
    for (start, cell), stop in zip(cells, bounds):
        for k in range(start, stop, cell):
            on = min(stop, k + int(duty * cell))
            seg = on - k
            if seg <= 0:
                continue
            w = np.ones(seg)
            r = min(e, seg // 2)
            if r:
                w[:r] = np.linspace(0.0, 1.0, r)
                w[-r:] = np.linspace(1.0, 0.0, r)
            out[k:on] = w
    return out


def riser(n: int, *, cells: list[tuple[int, int]], f_lo: float = 200.0, f_hi: float = 8000.0, q: float = 1.6,
          saw_from: float = 110.0, saw_to: float = 880.0, saw_db: float = -10.0, seed: object = 0) -> np.ndarray:
    """Riser (stereo): noise band-passed on an exponential sweep 200 Hz -> 8 kHz
    with t² gain, a rising band-limited saw underneath, both chopped by a
    rhythmic gate (8ths, then 16ths: ``cells``). Stops dead at ``n``."""
    t = seconds(n)
    u = t / (n / SR)
    fc = f_lo * (f_hi / f_lo) ** u
    nz = np.stack([noise(n, "riser", seed, c) for c in range(2)], axis=1)
    hiss = sweep(nz, "bandpass", fc, q=q) * 1.6
    tone = saw(exp_curve(saw_from, saw_to, n), n)
    tone = sweep(tone, "lowpass", np.minimum(fc * 1.5, 16000.0), q=0.9)
    y = hiss + amp(saw_db) * pan(tone)
    y *= (u ** 2 * _gate_curve(n, cells))[:, None]
    return _tail(y, 4.0)


def impact(*, f_start: float = 80.0, f_end: float = 30.0, tau: float = 0.8, rt60: float = 2.5,
           sub_db: float = 0.0, noise_db: float = -4.0, wet_db: float = -6.0, sub: bool = True,
           seed: object = 0) -> np.ndarray:
    """Impact (stereo): a sub sweep f_start -> f_end (pitch time constant
    ``tau``), a low-passed noise burst with a crack on top, and the burst sent
    into the synthetic reverb (RT60 ``rt60``). ``sub=False`` gives the soft
    hit (no sub)."""
    length = max(3.2 * tau + 0.5, 1.5) if sub else 1.0
    n = n_of(length)
    t = seconds(n)
    out = np.zeros((n, 2))
    if sub:
        f = f_end + (f_start - f_end) * np.exp(-t / tau)
        boom = np.sin(phase(f)) * decay(n, 1.1 * tau, attack=0.002)
        out += pan(amp(sub_db) * boom)
    burst = filt(noise(n, "impact", seed), "lowpass", 1400.0) * decay(n, 0.16, attack=0.001)
    crack = filt(noise(n, "impact-crack", seed), "bandpass", (2000.0, 8000.0)) * np.exp(-t / 0.012)
    body = np.sin(phase(f_start * 1.8 * (1.0 + 0.6 * np.exp(-t / 0.01)))) * np.exp(-t / 0.09)
    hit = amp(noise_db) * (burst + 0.35 * crack) + 0.5 * body
    out += pan(hit)
    wet = reverb(hit, rt60, wet_db, seed=f"impact-{rt60}")
    total = np.zeros((max(n, len(wet)), 2))
    total[:n] += out
    total[: len(wet)] += wet
    return _tail(total, 30.0)


WHOOSH_STYLES: dict[str, dict] = {
    # f: (start, peak, end) Hz of the band; peak: where the swell crests (fraction of the length)
    "whip": dict(length=0.30, f=(350.0, 5000.0, 700.0), q=0.9, peak=None, rise=2.0, fall=1.4, pan=(0.0, 0.0)),
    "swipe": dict(length=0.37, f=(500.0, 3200.0, 1500.0), q=1.0, peak=0.70, rise=2.0, fall=1.2, pan=(-0.7, 0.7)),
    "swish": dict(length=0.20, f=(1200.0, 6000.0, 2500.0), q=1.2, peak=0.40, rise=1.6, fall=1.6, pan=(-0.2, 0.2)),
    "close": dict(length=0.20, f=(3500.0, 2600.0, 900.0), q=1.1, peak=0.30, rise=1.5, fall=1.8, pan=(0.2, -0.2)),
    "drag": dict(length=1.40, f=(120.0, 700.0, 250.0), q=0.7, peak=0.35, rise=1.6, fall=1.3, pan=(0.0, 0.0)),
    "tape": dict(length=0.40, f=(200.0, 4000.0, 4000.0), q=1.0, peak=0.92, rise=2.4, fall=1.0, pan=(0.0, 0.0)),
    "air": dict(length=0.20, f=(900.0, 7000.0, 7000.0), q=0.8, peak=1.0, rise=3.0, fall=1.0, pan=(0.0, 0.0)),
}


def whoosh(style: str, n: int | None = None, *, peak_samples: int | None = None, seed: object = 0) -> np.ndarray:
    """Whoosh (stereo): band-passed noise whose band sweeps up to a crest and
    back, under a swelling envelope; optionally panned across. Styles:
    whip (6-frame camera whip, crest at +3 frames), swipe (left -> right),
    swish, close, drag (long and low), tape (speeding up, with a rising tone),
    air (a reverse swell that stops dead at its end, into a downbeat)."""
    s = WHOOSH_STYLES[style]
    n = n if n is not None else n_of(s["length"])
    p = peak_samples if peak_samples is not None else int((s["peak"] if s["peak"] is not None else 0.33) * n)
    p = int(np.clip(p, 1, n))
    t = np.arange(n, dtype=float)
    up = np.clip(t / p, 0.0, 1.0)
    down = np.clip((n - t) / max(1, n - p), 0.0, 1.0)
    env = np.where(t < p, up ** s["rise"], down ** s["fall"])
    f0, f1, f2 = s["f"]
    fc = np.where(t < p, f0 * (f1 / f0) ** up, f2 * (f1 / f2) ** down)
    common = noise(n, "whoosh", seed)
    nz = np.stack([0.75 * common + 0.66 * noise(n, "whoosh", seed, c) for c in range(2)], axis=1)
    y = sweep(nz, "bandpass", fc, q=s["q"]) * env[:, None] * 2.2
    if style == "tape":
        y += pan(0.25 * np.sin(phase(exp_curve(80.0, 1600.0, n, shape=1.6))) * env)
    p0, p1 = s["pan"]
    if p0 != p1:
        position = np.linspace(p0, p1, n)
        theta = (position + 1.0) * (np.pi / 4.0)
        y[:, 0] *= np.cos(theta) * np.sqrt(2.0)
        y[:, 1] *= np.sin(theta) * np.sqrt(2.0)
    return _tail(y, 3.0)


def reverse_cymbal(n: int, *, seed: object = 0) -> np.ndarray:
    """Reverse cymbal (stereo): a synthesized crash (808 metal + noise,
    exponential decay) played backwards, so it swells over ``n`` samples and
    ends on its attack — the downbeat it leads into."""
    t = seconds(n)
    tau = max(n / SR / 3.2, 0.05)
    metal = _metal(n_of(0.7))
    metal = np.resize(metal, n)
    out = np.zeros((n, 2))
    for c in range(2):
        hiss = filt(noise(n, "cymbal", seed, c), "highpass", 5500.0)
        crash = (0.5 * metal + hiss) * np.exp(-t / tau) * ramp(n, n_of(0.001))
        out[:, c] = crash[::-1]
    return _tail(out * 0.9, 1.5)


def pen_scratch(n: int, *, seed: object = 0, band: tuple[float, float] = (2000.0, 6000.0),
                grain_rate: float = 55.0) -> np.ndarray:
    """Pen on paper (stereo, nearly centred): noise band-passed 2-6 kHz under a
    random granular tremor (the nib catching the paper's tooth)."""
    g = rng("pen", seed)
    nz = filt(noise(n, "pen", seed), "bandpass", band, order=2)
    grains = np.zeros(n)
    k = 0
    while k < n:
        grains[k] = g.uniform(0.3, 1.0)
        k += max(1, int(g.exponential(SR / grain_rate)))
    bump = np.hanning(n_of(0.007))
    tremor = 0.25 + np.convolve(grains, bump, mode="same")
    env = gate_release(n, n - n_of(0.03), 0.01, attack=0.015)
    return _tail(pan(nz * tremor * env * 1.4, g.uniform(-0.15, 0.15)), 5.0)


def pen_slash(*, length: float = 0.12, f_from: float = 1000.0, f_to: float = 5000.0, seed: object = 0) -> np.ndarray:
    """A pen striking a line out (stereo): noise whose band sweeps 1 -> 5 kHz
    in 120 ms, moving left to right with the stroke."""
    n = n_of(length)
    u = np.linspace(0.0, 1.0, n)
    fc = f_from * (f_to / f_from) ** u
    y = sweep(noise(n, "slash", seed), "bandpass", fc, q=1.3)
    env = np.minimum(u / 0.08, 1.0) * (1.0 - u) ** 1.5
    return _tail(pan(y * env * 2.5, np.linspace(-0.35, 0.35, n)))


# ══ interface sounds (all original) ════════════════════════════════════════

def _blip(f: float, length: float, tau: float, noise_db: float, seed: object, hp: float = 4000.0) -> np.ndarray:
    n = n_of(length)
    t = seconds(n)
    env = ramp(n, n_of(0.0003)) * np.exp(-t / tau)
    tick = filt(noise(n, "blip", seed), "highpass", hp) * np.exp(-t / 0.0004)
    return _tail(np.sin(phase(f, n)) * env + amp(noise_db) * tick, 1.0)


def detuned(f: float, spread: float, seed: object) -> float:
    """``f`` moved by a uniform ±``spread`` (fraction), from ``seed``."""
    return f * (1.0 + rng("detune", seed).uniform(-spread, spread))


def ui_click(*, f: float = 3200.0, spread: float = 0.03, seed: object = 0) -> np.ndarray:
    """The touch-down click (mono): an original 3.2 kHz, 8-ms blip, its pitch
    moved ±3 % per tap (seeded by the cue), with a hair of noise on the edge."""
    return _blip(detuned(f, spread, ("click", seed)), 0.008, 0.0018, -20.0, seed)


def key_click(*, f: float = 2400.0, spread: float = 0.03, seed: object = 0) -> np.ndarray:
    """A typing key (mono): a softer, lower 6-ms blip with more noise."""
    return _blip(detuned(f, spread, ("key", seed)), 0.006, 0.0012, -10.0, seed, hp=3000.0) * 0.8


def tick(*, f: float = 5200.0, spread: float = 0.03, seed: object = 0) -> np.ndarray:
    """The counter's odometer tick (mono): 4 ms, high and small."""
    return _blip(detuned(f, spread, ("tick", seed)), 0.004, 0.0008, -14.0, seed) * 0.7


def pop(*, f: float = 520.0, length: float = 0.040) -> np.ndarray:
    """The lift's soft pop (mono): a 520-Hz sine, 40 ms, with a tiny upward start."""
    n = n_of(length)
    t = seconds(n)
    y = np.sin(phase(f * (1.0 + 0.25 * np.exp(-t / 0.004)))) * ramp(n, n_of(0.0007)) * np.exp(-t / 0.012)
    return _tail(y)


def thock(*, f: float = 900.0, seed: object = 0) -> np.ndarray:
    """A wood thock (mono): a short pitched knock with a 2.3x mode and a noise tap."""
    n = n_of(0.08)
    t = seconds(n)
    ph = phase(f * (1.0 + 0.35 * np.exp(-t / 0.003)))
    y = np.sin(ph) * np.exp(-t / 0.016) + 0.35 * np.sin(2.3 * ph) * np.exp(-t / 0.008)
    y += 0.5 * filt(noise(n, "thock", seed), "bandpass", (1500.0, 4000.0)) * np.exp(-t / 0.002)
    return _tail(y * ramp(n, n_of(0.0004)))


def card_pop(*, seed: object = 0) -> np.ndarray:
    """A card landing (mono): wood thock + a low thump (85 Hz)."""
    n = n_of(0.16)
    t = seconds(n)
    thump = np.sin(phase(85.0 * (1.0 + 0.5 * np.exp(-t / 0.008)))) * decay(n, 0.045, attack=0.0008)
    y = 0.9 * thump
    th = thock(f=1000.0, seed=seed)
    y[: len(th)] += 0.8 * th
    return _tail(y)


def _bell(f: float, n: int, *, index: float, ratio: float, tau: float, attack: float = 0.0015) -> np.ndarray:
    t = seconds(n)
    ph = phase(f, n)
    index_t = index * np.exp(-t / 0.08) + 0.12
    y = np.sin(ph + index_t * np.sin(ratio * ph)) + 0.10 * np.sin(4.0 * ph) * np.exp(-t / 0.15)
    return y * ramp(n, n_of(attack)) * np.exp(-t / tau)


def chime(*, f: float = 783.99, interval: int = 7, gap: float = 0.09) -> np.ndarray:
    """The original two-note chime (stereo): a rising fifth, sine + soft FM,
    the second note ``gap`` seconds after the first. Not an OS sound."""
    n = n_of(gap + 1.6)
    out = np.zeros((n, 2))
    for k, (freq, side) in enumerate(((f, -0.15), (f * 2.0 ** (interval / 12.0), 0.15))):
        start = n_of(gap) * k
        out[start:] += pan(_bell(freq, n - start, index=0.8, ratio=2.0, tau=0.45), side) * (0.85 if k else 1.0)
    return _tail(out * 0.6)


def glint(*, f: float = 1174.66) -> np.ndarray:
    """A small, soft single bell (stereo) — the end card's lines under the
    tagline arriving (« Sur l’App Store et Google Play », « myweli.com »).
    Quieter and slower than the chime."""
    n = n_of(1.4)
    return _tail(pan(_bell(f, n, index=0.4, ratio=2.0, tau=0.55, attack=0.004) * 0.45, 0.1))


def kalimba(*, f: float = 1046.5, seed: object = 0) -> np.ndarray:
    """A kalimba ding (mono): a tine's inharmonic partials and a thumb thump."""
    n = n_of(1.6)
    t = seconds(n)
    y = np.zeros(n)
    for ratio, level, tau in ((1.0, 1.0, 0.75), (5.95, 0.22, 0.09), (16.4, 0.06, 0.025)):
        if f * ratio < 18000:
            y += level * np.sin(phase(f * ratio, n)) * np.exp(-t / tau)
    y *= ramp(n, n_of(0.0006))
    y += 0.25 * filt(noise(n, "kalimba", seed), "lowpass", 2000.0) * np.exp(-t / 0.003)
    return _tail(y * 0.7)


def shimmer(*, freqs: tuple[float, ...] = (1567.98, 1864.66, 2349.32, 2489.02, 3135.96), seed: object = 0) -> np.ndarray:
    """A soft shimmer (stereo): a staggered cluster of high Cm9 tones, each with
    its own fast tremolo, over a breath of high noise."""
    n = n_of(2.4)
    t = seconds(n)
    g = rng("shimmer", seed)
    out = np.zeros((n, 2))
    for i, f in enumerate(freqs):
        start = n_of(0.012 * i)
        tt = t[: n - start]
        trem = 0.6 + 0.4 * np.sin(TWO_PI * (6.0 + 0.7 * i) * tt + g.uniform(0, TWO_PI))
        tone = np.sin(TWO_PI * f * tt) * trem * ramp(len(tt), n_of(0.04)) * np.exp(-tt / 0.9)
        out[start:] += pan(tone, -0.5 + i / max(1, len(freqs) - 1))
    air = filt(noise(n, "shimmer-air", seed), "highpass", 9000.0) * decay(n, 0.3, attack=0.03) * 0.15
    out += pan(air)
    return _tail(out * 0.25)


def fm_glide(n: int, *, f_from: float = 196.0, f_to: float = 523.25, seed: object = 0) -> np.ndarray:
    """A rising FM glide (stereo) over ``n`` samples: the pitch eases from
    ``f_from`` to ``f_to`` while the FM index (ratio 1) opens, the level
    swells, then a short release on arrival."""
    m = n + n_of(0.35)                                   # the glide, then a short ring on arrival
    k = np.arange(m, dtype=float)
    u = np.clip(k / max(1, n - 1), 0.0, 1.0)
    ease = u * u * (3.0 - 2.0 * u)
    ph = phase(f_from * (f_to / f_from) ** ease)
    index_t = 0.4 + 2.0 * u
    env = np.where(k < n, u ** 1.5, np.exp(-(k - n) / (0.08 * SR)))
    y = (np.sin(ph + index_t * np.sin(ph)) + 0.4 * np.sin(0.5 * ph)) * env
    return _tail(pan(y * 0.35), 4.0)
