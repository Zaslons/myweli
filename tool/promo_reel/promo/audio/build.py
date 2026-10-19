"""One cut, end to end: score -> render -> master -> files."""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from pathlib import Path

import numpy as np

from . import analysis, events, wav
from . import score as score_mod
from .arrange import Render, render
from .mix import Master, MixSettings, master

HERE = Path(__file__).resolve().parent


def find_score(name: str | Path) -> Path:
    """A score path as given, else next to this module (``score_30s.yaml``),
    else by cut name (``30s`` -> ``score_30s.yaml``)."""
    p = Path(name)
    for candidate in (p, HERE / p.name, HERE / f"score_{p.name}.yaml"):
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"no score {name!r} (looked in . and {HERE})")


@dataclass
class BuildResult:
    out: Path
    render: Render
    master: Master
    events: dict
    meter: dict
    seconds: float

    @property
    def files(self) -> dict[str, Path]:
        return {k: self.out / v for k, v in (("track", "track.wav"), ("events", "events.json"),
                                              ("meter", "meter.json"), ("spectrogram", "spectrogram.png"),
                                              ("waveform", "waveform.png"))}


def build_cut(score_name: str | Path, out: str | Path, *, settings: MixSettings | None = None,
              pictures: bool = True, ffmpeg_check: bool = True, stems: bool = False) -> BuildResult:
    """Render a score and write track.wav (24-bit stereo, 48 kHz), events.json,
    meter.json and (``pictures``) spectrogram.png + waveform.png into ``out``."""
    t0 = time.time()
    path = find_score(score_name)
    sc = score_mod.load(path)
    out = Path(out)
    out.mkdir(parents=True, exist_ok=True)
    r = render(sc, keep_parts=stems)
    m = master(r, settings)
    ev = events.build(r)
    events.write(out / "events.json", ev)
    wav.write(out / "track.wav", m.audio)
    written, _ = wav.read(out / "track.wav")
    s = m.settings
    report = analysis.meter(written, events=ev, target_lufs=s.target_lufs, ceiling_dbtp=s.ceiling_dbtp)
    report = {"file": "track.wav", "score": sc.source, "cut": sc.cut, "duration_s": round(len(written) / 48000, 4),
              "frames": ev["frames"], **report, "mix": m.as_dict()}
    if ffmpeg_check:
        report["ffmpeg_ebur128"] = analysis.ffmpeg_ebur128(out / "track.wav")
    (out / "meter.json").write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    if pictures:
        title = f"{sc.source} — {sc.cut}, {sc.bars} bars, {ev['frames']} frames, 112.5 BPM, {sc.key}"
        analysis.spectrogram_png(written, out / "spectrogram.png", events=ev, meter_report=report, title=title)
        analysis.waveform_png(written, out / "waveform.png", events=ev, title=title + " — by section")
    if stems:
        sd = out / "stems"
        sd.mkdir(exist_ok=True)
        peak = max(float(np.max(np.abs(v))) for v in r.stems.values()) or 1.0
        for name, buf in {**r.stems, **r.parts}.items():
            wav.write(sd / f"{name.replace(':', '_')}.wav", buf / peak * 0.5)
    return BuildResult(out, r, m, ev, report, time.time() - t0)
