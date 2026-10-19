"""What the master measures and looks like: meter.json, spectrogram.png, waveform.png.

meter.json      integrated / short-term max / momentary max loudness, true and
                sample peak, LRA, the target check, per-bar and per-section
                readings, the mono fold-down, and — when ffmpeg is installed —
                ffmpeg's own ebur128 reading of the written WAV as a cross-check.
spectrogram.png the whole cut on one time axis IN BARS: the waveform, a log-
                frequency spectrogram (30 Hz - 20 kHz), and the momentary and
                short-term loudness against the -14 LUFS target; section names
                on top, bar lines and numbers, a tick for every cue.
waveform.png    one row per section, the waveform drawn per beat with every
                cue's id where it lands — to check the arrangement by eye.

Drawn with Pillow (no plotting library), in Inter from the repo's fonts.
"""

from __future__ import annotations

import re
import shutil
import subprocess
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import signal

from . import _time as tb
from . import loudness
from .dsp import SR, filt
from .kinds import KINDS

FONT_PATH = Path(__file__).resolve().parents[3] / "app_store_screenshots/fonts/Inter-Variable.ttf"

INK = (232, 232, 236)
MUTED = (150, 150, 160)
GROUND = (14, 14, 18)
PANEL = (24, 24, 30)
TARGET = (120, 220, 160)
BUS_COLOURS = {"log": (255, 170, 60), "drums": (240, 240, 240), "keys": (140, 190, 255), "fx": (255, 110, 150),
               "ui": (120, 230, 200)}

# magma, sampled (0 = silence .. 1 = loud)
_MAGMA = np.array([(0, 0, 4), (28, 16, 68), (79, 18, 123), (129, 37, 129), (181, 54, 122), (229, 80, 100),
                   (251, 135, 97), (254, 194, 135), (252, 253, 191)], dtype=float)


def _font(size: int) -> ImageFont.ImageFont:
    try:
        return ImageFont.truetype(str(FONT_PATH), size)
    except OSError:
        return ImageFont.load_default()


def _magma(u: np.ndarray) -> np.ndarray:
    u = np.clip(u, 0.0, 1.0) * (len(_MAGMA) - 1)
    i = np.minimum(u.astype(int), len(_MAGMA) - 2)
    f = (u - i)[..., None]
    return (_MAGMA[i] * (1 - f) + _MAGMA[i + 1] * f).astype(np.uint8)


# ── meter ──────────────────────────────────────────────────────────────────

def meter(audio: np.ndarray, *, events: dict | None = None, target_lufs: float = -14.0,
          ceiling_dbtp: float = -1.0) -> dict:
    """The level report of a stereo master."""
    m = loudness.measure(audio)
    out: dict = {"standard": "ITU-R BS.1770-4 (K-weighted, gated); true peak 4x oversampled; LRA per EBU Tech 3342",
                 **m.as_dict()}
    out["target"] = {"integrated_lufs": target_lufs, "ceiling_dbtp": ceiling_dbtp,
                     "integrated_ok": abs(m.integrated_lufs - target_lufs) <= 0.1,
                     "true_peak_ok": m.true_peak_dbtp <= ceiling_dbtp}
    mono = 0.5 * (audio[:, 0] + audio[:, 1])
    out["mono"] = {
        "fold_down_integrated_lufs": round(loudness.integrated(np.stack([mono, mono], axis=1)), 2),
        "correlation": round(float(np.corrcoef(audio[:, 0], audio[:, 1])[0, 1]), 3),
        "side_below_150hz_db": round(_side_low_db(audio), 1),
    }
    mom = loudness.momentary(audio)
    st = loudness.short_term(audio)
    if events:
        hop = int(0.1 * SR)

        def at(curve: np.ndarray, window: float, sample: int) -> int:
            return int(np.clip((sample - int(window * SR)) // hop, 0, len(curve) - 1))

        bars = []
        for b in events["bars"]:
            s0, s1 = b["sample"], b["sample"] + tb.SAMPLES_PER_BAR
            i0, i1 = at(mom, 0.4, s0 + int(0.4 * SR)), at(mom, 0.4, s1)
            bars.append({"bar": b["bar"], "momentary_max_lufs": round(float(mom[i0:i1 + 1].max()), 1),
                         "short_term_at_end_lufs": round(float(st[at(st, 3.0, s1)]), 1) if len(st) else None,
                         "peak_dbfs": round(loudness.sample_peak_db(audio[s0:s1]), 1)})
        out["bars"] = bars
        sections = []
        for s in events["sections"]:
            a, b = s["frame"] * tb.SAMPLES_PER_FRAME, s["end_frame"] * tb.SAMPLES_PER_FRAME
            seg = audio[a:b]
            sections.append({"name": s["name"], "bars": s["bars"],
                             "integrated_lufs": round(loudness.integrated(seg), 1) if len(seg) > 0.4 * SR else None,
                             "true_peak_dbtp": round(loudness.true_peak_db(seg), 1)})
        out["sections"] = sections
    return out


def _side_low_db(audio: np.ndarray, below: float = 150.0) -> float:
    """Energy of the side signal under ``below`` Hz relative to the mid's, dB."""
    mid = filt(0.5 * (audio[:, 0] + audio[:, 1]), "lowpass", below, order=4)
    side = filt(0.5 * (audio[:, 0] - audio[:, 1]), "lowpass", below, order=4)
    return float(10 * np.log10((np.sum(side ** 2) + 1e-30) / (np.sum(mid ** 2) + 1e-30)))


def ffmpeg_ebur128(path: str | Path) -> dict | None:
    """ffmpeg's ebur128 filter on a written file: I, LRA, true peak. None
    when ffmpeg is not installed."""
    exe = shutil.which("ffmpeg") or ("/opt/homebrew/bin/ffmpeg" if Path("/opt/homebrew/bin/ffmpeg").exists() else None)
    if not exe:
        return None
    run = subprocess.run([exe, "-hide_banner", "-nostats", "-i", str(path), "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True)
    text = run.stderr[run.stderr.rfind("Summary:"):]

    def grab(label: str) -> float | None:
        m = re.search(rf"{label}:\s+(-?[\d.]+|-inf)", text)
        return None if m is None else float(m.group(1))

    return {"integrated_lufs": grab("I"), "lra_lu": grab("LRA"), "true_peak_dbfs": grab("Peak")}


# ── drawing helpers ────────────────────────────────────────────────────────

class _Axis:
    """Samples -> x pixels across the plot width."""

    def __init__(self, n: int, left: int, width: int):
        self.n, self.left, self.width = n, left, width

    def x(self, sample: float) -> float:
        return self.left + sample / self.n * self.width


def _bar_grid(d: ImageDraw.ImageDraw, ax: _Axis, events: dict, top: int, bottom: int, beats: bool = True) -> None:
    if beats:
        for b in events["beats"]:
            x = ax.x(b["sample"])
            d.line([(x, top), (x, bottom)], fill=(255, 255, 255, 26))
    for b in events["bars"]:
        x = ax.x(b["sample"])
        d.line([(x, top), (x, bottom)], fill=(255, 255, 255, 90))


def spectrogram_png(audio: np.ndarray, path: str | Path, *, events: dict, meter_report: dict | None = None,
                    title: str = "") -> None:
    n = len(audio)
    W, left, right = 2200, 96, 40
    plot_w = W - left - right
    top = 92
    wave_h, spec_h, loud_h, gap = 150, 600, 190, 26
    H = top + wave_h + gap + spec_h + gap + loud_h + 70
    ax = _Axis(n, left, plot_w)
    img = Image.new("RGB", (W, H), GROUND)
    d = ImageDraw.Draw(img, "RGBA")
    f_small, f_mid, f_big = _font(17), _font(20), _font(26)

    # title + sections
    d.text((left, 18), title, font=f_big, fill=INK)
    if meter_report:
        summary = (f"{meter_report['integrated_lufs']:.1f} LUFS-I   short-term max {meter_report['short_term_max_lufs']:.1f}"
                   f"   momentary max {meter_report['momentary_max_lufs']:.1f}   true peak "
                   f"{meter_report['true_peak_dbtp']:.2f} dBTP   LRA {meter_report['lra_lu']:.1f} LU")
        d.text((W - right, 22), summary, font=f_mid, fill=MUTED, anchor="ra")
    for s in events["sections"]:
        x0 = ax.x(s["frame"] * tb.SAMPLES_PER_FRAME)
        x1 = ax.x(s["end_frame"] * tb.SAMPLES_PER_FRAME)
        d.rectangle([x0 + 1, 60, x1 - 1, 82], fill=(255, 255, 255, 18))
        d.text(((x0 + x1) / 2, 71), s["name"], font=f_small, fill=INK, anchor="mm")

    # waveform (mid and side envelopes per column)
    y0 = top
    d.rectangle([left, y0, left + plot_w, y0 + wave_h], fill=PANEL)
    cols = plot_w
    edges = (np.arange(cols + 1) * n / cols).astype(int)
    mid = 0.5 * (audio[:, 0] + audio[:, 1])
    side = 0.5 * (audio[:, 0] - audio[:, 1])
    centre = y0 + wave_h / 2
    for c in range(cols):
        seg = mid[edges[c]:edges[c + 1]]
        sseg = side[edges[c]:edges[c + 1]]
        if len(seg):
            d.line([(left + c, centre - seg.max() * wave_h / 2), (left + c, centre - seg.min() * wave_h / 2)],
                   fill=(150, 190, 255))
            a = np.abs(sseg).max()
            d.line([(left + c, centre - a * wave_h / 2), (left + c, centre + a * wave_h / 2)], fill=(255, 140, 90, 140))
    for lvl in (-1.0, -6.0):
        a = 10 ** (lvl / 20) * wave_h / 2
        for y in (centre - a, centre + a):
            d.line([(left, y), (left + plot_w, y)], fill=(255, 255, 255, 40))
        d.text((left - 8, centre - a), f"{lvl:.0f}", font=f_small, fill=MUTED, anchor="rm")
    d.text((left - 8, y0 + 4), "dBFS", font=f_small, fill=MUTED, anchor="ra")
    _bar_grid(d, ax, events, y0, y0 + wave_h, beats=False)

    # spectrogram
    y1 = y0 + wave_h + gap
    nper, hop = 4096, 512
    win = signal.windows.hann(nper)
    f, t, z = signal.stft(mid, fs=SR, window=win, nperseg=nper, noverlap=nper - hop, boundary=None, padded=False)
    mag = np.abs(z) * 2.0                       # stft scales by 1/sum(window): a full-scale sine reads 0 dB
    spec_db = 20 * np.log10(mag + 1e-10)
    fmin, fmax = 30.0, 20000.0
    rows = spec_h
    want = fmin * (fmax / fmin) ** (np.arange(rows)[::-1] / (rows - 1))
    times = (t * SR).astype(int)
    col_of = np.clip(((times / n) * cols).astype(int), 0, cols - 1)
    grid = np.full((rows, cols), -120.0)
    for c in range(cols):
        idx = np.nonzero(col_of == c)[0]
        if len(idx) == 0:
            continue
        frame = spec_db[:, idx].max(axis=1)
        grid[:, c] = np.interp(want, f, frame)
    filled = grid > -120
    for c in range(1, cols):          # columns between STFT frames take their neighbour
        if not filled[0, c]:
            grid[:, c] = grid[:, c - 1]
    lo_db, hi_db = -96.0, -12.0
    rgb = _magma((grid - lo_db) / (hi_db - lo_db))
    img.paste(Image.fromarray(rgb, "RGB"), (left, y1))
    d = ImageDraw.Draw(img, "RGBA")
    for hz, label in ((50, "50"), (100, "100"), (200, "200"), (500, "500"), (1000, "1k"), (2000, "2k"),
                      (5000, "5k"), (10000, "10k"), (20000, "20k")):
        y = y1 + (1 - np.log(hz / fmin) / np.log(fmax / fmin)) * (rows - 1)
        d.line([(left - 6, y), (left, y)], fill=MUTED)
        d.line([(left, y), (left + plot_w, y)], fill=(255, 255, 255, 22))
        d.text((left - 10, y), label, font=f_small, fill=MUTED, anchor="rm")
    d.text((left - 10, y1 - 4), "Hz", font=f_small, fill=MUTED, anchor="rb")
    _bar_grid(d, ax, events, y1, y1 + spec_h)
    for cue in events["cues"]:                       # a tick per cue, coloured by bus
        x = ax.x(cue["sample"])
        colour = BUS_COLOURS.get(KINDS[cue["kind"]].bus, INK)
        d.line([(x, y1), (x, y1 + 12)], fill=colour + (255,), width=2)

    # loudness
    y2 = y1 + spec_h + gap
    d.rectangle([left, y2, left + plot_w, y2 + loud_h], fill=PANEL)
    l_lo, l_hi = -42.0, -4.0

    def ly(v: float) -> float:
        return y2 + (1 - (np.clip(v, l_lo, l_hi) - l_lo) / (l_hi - l_lo)) * loud_h

    for v in (-40, -30, -20, -10):
        d.line([(left, ly(v)), (left + plot_w, ly(v))], fill=(255, 255, 255, 30))
        d.text((left - 10, ly(v)), str(v), font=f_small, fill=MUTED, anchor="rm")
    d.line([(left, ly(-14)), (left + plot_w, ly(-14))], fill=TARGET + (200,), width=1)
    d.text((left + plot_w - 4, ly(-14) - 4), "-14 LUFS", font=f_small, fill=TARGET, anchor="rb")
    d.text((left - 10, y2 - 4), "LUFS", font=f_small, fill=MUTED, anchor="rb")
    hop_s = int(0.1 * SR)
    for curve, window, colour, width in ((loudness.momentary(audio), 0.4, (255, 255, 255, 110), 1),
                                         (loudness.short_term(audio), 3.0, (255, 200, 90, 255), 3)):
        pts = [(ax.x(i * hop_s + window * SR), ly(v)) for i, v in enumerate(curve)]
        if len(pts) > 1:
            d.line(pts, fill=colour, width=width)
    _bar_grid(d, ax, events, y2, y2 + loud_h, beats=False)

    # bar numbers
    yb = y2 + loud_h + 12
    for b in events["bars"]:
        x0 = ax.x(b["sample"])
        x1 = ax.x(b["sample"] + tb.SAMPLES_PER_BAR)
        d.text(((x0 + x1) / 2, yb), str(b["bar"]), font=f_mid, fill=INK, anchor="ma")
    d.text((left + plot_w / 2, yb + 30), "bar (112.5 BPM, 64 frames = 2.133 s each)", font=f_small, fill=MUTED,
           anchor="ma")
    img.save(path)


def waveform_png(audio: np.ndarray, path: str | Path, *, events: dict, title: str = "") -> None:
    """One row per section: waveform, beat grid, and each cue's id where it lands."""
    W, left, right = 2200, 70, 30
    row_h, label_h = 230, 110
    sections = events["sections"]
    H = 70 + len(sections) * (row_h + label_h)
    img = Image.new("RGB", (W, H), GROUND)
    d = ImageDraw.Draw(img, "RGBA")
    f_small, f_mid, f_big = _font(15), _font(19), _font(24)
    d.text((left, 20), title, font=f_big, fill=INK)
    mid = 0.5 * (audio[:, 0] + audio[:, 1])
    y = 70
    for s in sections:
        a, b = s["frame"] * tb.SAMPLES_PER_FRAME, s["end_frame"] * tb.SAMPLES_PER_FRAME
        seg = mid[a:b]
        plot_w = W - left - right
        cols = plot_w
        edges = (np.arange(cols + 1) * len(seg) / cols).astype(int)
        top, centre = y + 26, y + 26 + (row_h - 26) / 2
        d.text((left, y), f"{s['name']}  — bars {s['bars'][0]}-{s['bars'][1]}  (frames {s['frame']}-{s['end_frame'] - 1})",
               font=f_mid, fill=INK)
        d.rectangle([left, top, left + plot_w, y + row_h], fill=PANEL)
        half = (row_h - 26) / 2
        for c in range(cols):
            piece = seg[edges[c]:edges[c + 1]]
            if len(piece):
                d.line([(left + c, centre - piece.max() * half), (left + c, centre - piece.min() * half)],
                       fill=(150, 190, 255))

        def x_of(sample: int) -> float:
            return left + (sample - a) / (b - a) * plot_w

        for beat in events["beats"]:
            if a <= beat["sample"] < b:
                x = x_of(beat["sample"])
                major = beat["pos"].endswith(".1.0")
                d.line([(x, top), (x, y + row_h)], fill=(255, 255, 255, 110 if major else 35))
                d.text((x + 3, top + 2), beat["pos"].rsplit(".", 1)[0], font=f_small, fill=MUTED)
        lanes = [-1e9] * 6
        for cue in events["cues"]:
            if a <= cue["sample"] < b:
                x = x_of(cue["sample"])
                colour = BUS_COLOURS.get(KINDS[cue["kind"]].bus, INK)
                d.line([(x, top), (x, y + row_h)], fill=colour + (150,), width=1)
                text = f"{cue['id']} f{cue['frame']}"
                width = d.textlength(text, font=f_small)
                lane = next((k for k, end in enumerate(lanes) if end < x), len(lanes) - 1)
                lanes[lane] = x + width + 6
                ty = y + row_h + 6 + lane * 17
                d.line([(x, y + row_h), (x, ty + 8)], fill=colour + (90,))
                d.text((x + 2, ty), text, font=f_small, fill=colour)
        y += row_h + label_h
    img.save(path)
