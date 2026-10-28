"""Render a cut × format from storyboard.yaml: the soundtrack FIRST, then every
frame timed by the events.json it wrote, piped to ffmpeg with the track muxed.

    python -m promo build --cut 30s --format 9x16 --out DIR        (promo/__main__.py)
    python -m promo.render --cut 30s --format 9x16 --out DIR --frames 0,128,552
                                         (stills only, full size — for looking)

A film goes to DIR/<cut>-<format>/:

    track.wav        the master (24-bit, 48 kHz, exactly frames × 1600 samples)
    events.json      where every bar, beat and cue landed (the audio engine's)
    meter.json       the master's loudness (BS.1770-4) and spectrogram.png
    reel.mp4         H.264 High yuv420p + AAC-LC 48 kHz stereo, +faststart
    render.json      what each frame shows (scene, take picture, touches, boxes,
                     hidden rows, blur), the film's plan, events, generated
                     elements — what promo/verify.py checks
    verify/renderer/ the renderer's own frame on every beat (for the beat sheet)

Every format is laid out from the same scenes (each format's `layout`), so
every cut × format with scenes and a score is built; one that cannot be is
named, not silently skipped. A cut's soundtrack is rendered ONCE per build
and shared by its formats (the same track.wav and events.json, byte for
byte — render.json records both files' sha256 and where they came from;
verify holds every format of a cut to the same two files).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import time
from pathlib import Path
from typing import Sequence

import numpy as np

from . import storyboard as sbmod
from .audio import build_cut
from .audio.mix import MixSettings
from .media.writer import VideoWriter
from .scenes import Clock, Film, SceneError

#: The renderer's beat frames are kept at this fraction of full size.
BEAT_STILL_SCALE = 0.5
#: The film's true-peak ceiling is −1.0 dBTP ON THE MP4: AAC-LC raises the
#: inter-sample peaks of the 24-bit master, so the master is limited this much
#: lower (its limiter then sits 0.3 dB further down: the master measures
#: ≈ −2.0 dBTP); verify (d) re-measures the MP4 and warns when it keeps less
#: than 0.5 dB under the ceiling. The rise is not stable: measured −1.30 →
#: −0.94 dBTP (round 1); round 7, the 30-s cut's master at −1.80 → −1.29
#: (0.29 dB left at 0.5 dB here), and re-encodes of that score's masters at
#: −2.0 / −2.1 / −2.3 dBTP rose 0.21 / 0.32 / 0.79 dB.
AAC_HEADROOM_DB = 0.7
FILM_CEILING_DBTP = -1.0


def film_dir(out_dir: Path, cut: str, fmt: str) -> Path:
    return Path(out_dir) / f"{cut}-{fmt}"


def not_built(sb, cut: str, fmt: str) -> str | None:
    """Why a cut × format cannot be built yet (None: it can)."""
    if not sb.cut_scenes(cut):
        return f"cut {cut} has no scenes in storyboard.yaml yet"
    if fmt not in sb.formats:
        return f"the storyboard has no format {fmt}"
    if sb.score_path(cut) is None:
        return f"music.scores has no score for {cut}"
    return None


#: The soundtrack's files, as promo.audio.build_cut writes them.
AUDIO_FILES = ("track.wav", "events.json", "meter.json", "spectrogram.png", "waveform.png")


def sha256(path: Path) -> str:
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def share_audio(src: Path, out: Path, frames: int) -> Clock:
    """The cut's soundtrack already rendered in this build (another format's
    folder): the same files, copied byte for byte."""
    out.mkdir(parents=True, exist_ok=True)
    for name in AUDIO_FILES:
        if (src / name).is_file():
            shutil.copyfile(src / name, out / name)
    print(f"  audio: the cut's soundtrack from {src.name}/ (track.wav {sha256(out / 'track.wav')[:12]}, "
          f"events.json {sha256(out / 'events.json')[:12]})", flush=True)
    return Clock.load(out / "events.json", frames)


def render_audio(sb, cut: str, out: Path) -> Clock:
    """The soundtrack first: track.wav, events.json, meter.json, spectrogram.png."""
    result = build_cut(sb.score_path(cut), out, pictures=True,
                       settings=MixSettings(ceiling_dbtp=FILM_CEILING_DBTP - AAC_HEADROOM_DB))
    m = result.meter
    if not (m["target"]["integrated_ok"] and m["target"]["true_peak_ok"]):
        raise SceneError(f"{cut}: the master misses its loudness target ({m['integrated_lufs']:.2f} LUFS, "
                         f"{m['true_peak_dbtp']:.2f} dBTP)")
    print(f"  audio: {m['integrated_lufs']:.2f} LUFS-I, true peak {m['true_peak_dbtp']:.2f} dBTP, "
          f"{len(result.events['cues'])} cues ({result.seconds:.1f} s)", flush=True)
    return Clock.load(out / "events.json", sb.cuts[cut].frames)


def build_one(sb, cut: str, fmt: str, out: Path, audio_from: Path | None = None) -> dict:
    """One film. ``audio_from``: a folder of this build holding the cut's
    soundtrack already (another format's) — shared, not rendered again."""
    out.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    print(f"build {cut}/{fmt} → {out}", flush=True)
    if audio_from is not None and Path(audio_from).resolve() != out.resolve():
        clock = share_audio(Path(audio_from), out, sb.cuts[cut].frames)
    else:
        clock = render_audio(sb, cut, out)
        audio_from = None
    film = Film(sb, cut, fmt, clock)
    crowded = film.crowded_captions()
    if crowded:
        c = crowded[0]
        raise SceneError(f"{cut}/{fmt}: on {len(crowded)} frames a caption comes within the phone's clearance — "
                         f"f{c['frame']}: {c['caption']} {c['caption_rect']}, the phone as posed {c['phone']} (the "
                         f"phone never covers or crowds a caption: verify (g), CAPTION_PHONE_CLEAR_PX)")
    breathing = film.breathing_pushes()
    if breathing:
        b = breathing[0]
        raise SceneError(f"{cut}/{fmt}: the push turns three times within a bar — {b['scene']} "
                         f"{', '.join(f'{m} f{f}' for m, f in zip(b['moves'], b['frames']))} (the camera breathing: "
                         f"Film.breathing_pushes)")
    beats = out / "verify" / "renderer"
    beats.mkdir(parents=True, exist_ok=True)
    records = []
    per_frame = []
    w, h = film.size
    with VideoWriter(out / "reel.mp4", w, h, film.frames, fps=sb.meta.fps, audio=out / "track.wav") as writer:
        for f in range(film.frames):
            t1 = time.time()
            frame, rec = film.frame(f)
            writer.write(frame)
            rec["render_ms"] = round((time.time() - t1) * 1000, 1)
            per_frame.append(rec["render_ms"])
            records.append(rec)
            if f % sb.timebase.frames_per_beat == 0:
                _save_still(frame, beats / f"f{f:04d}.png", BEAT_STILL_SCALE)
            if f % 64 == 0:
                print(f"  f{f:4d}  {rec['scene']:10} {rec['render_ms']:7.0f} ms", flush=True)
    seconds = time.time() - t0
    doc = {"cut": cut, "format": fmt, "frames": film.frames, "size": [w, h], "fps": sb.meta.fps,
           "storyboard": sb.source, "overrides": list(sb.overrides), "render_seconds": round(seconds, 1),
           "audio": {"from": Path(audio_from).name if audio_from is not None else None,
                     "track_wav_sha256": sha256(out / "track.wav"), "events_json_sha256": sha256(out / "events.json")},
           "frame_ms": {"mean": round(float(np.mean(per_frame)), 1), "max": round(float(np.max(per_frame)), 1)},
           "plan": film.plan(), "events": film.events(), "generated": film.generated(),
           "masks": {name: [{"label": b.label, "rect_pt": list(b.rect_pt), "sigma_px": b.sigma_px,
                             "margin_pt": b.margin_pt, "from_s": b.from_s, "to_s": b.to_s,
                             "clip_y_pt": list(b.clip_y_pt) if b.clip_y_pt else None, "tracked": b.track is not None}
                            for b in src.blurs] for name, src in film.ctx.sources.items()},
           "records": records}
    (out / "render.json").write_text(json.dumps(doc, ensure_ascii=False, indent=0) + "\n", encoding="utf-8")
    print(f"  wrote {out / 'reel.mp4'} in {seconds:.0f} s ({np.mean(per_frame):.0f} ms a frame)", flush=True)
    return doc


def _save_still(rgba: np.ndarray, path: Path, scale: float = 1.0) -> None:
    from PIL import Image
    im = Image.fromarray(np.ascontiguousarray(rgba[..., :3]))
    if scale != 1.0:
        im = im.resize((round(im.width * scale), round(im.height * scale)), Image.LANCZOS)
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path)


def build(storyboard, cuts: list[str], formats: list[str], out_dir: Path) -> None:
    """``python -m promo build``: every selected cut × format that can be built."""
    built, skipped = [], []
    t0 = time.time()
    for cut in cuts:
        audio = None                                   # the cut's soundtrack, once per build
        for fmt in formats:
            why = not_built(storyboard, cut, fmt)
            if why:
                skipped.append(f"{cut}/{fmt}: {why}")
                continue
            d = film_dir(out_dir, cut, fmt)
            doc = build_one(storyboard, cut, fmt, d, audio_from=audio)
            audio = audio or d
            built.append(f"{cut}/{fmt} ({doc['render_seconds']:.0f} s)")
    for s in skipped:
        print(f"NOT BUILT {s}")
    if not built:
        raise SystemExit("build: nothing could be built")
    print(f"build: {len(built)} film{'s' if len(built) != 1 else ''} in {time.time() - t0:.0f} s — "
          + ", ".join(built), flush=True)


# ---- stills for looking -------------------------------------------------------------------

def stills(storyboard, cut: str, fmt: str, frames: Sequence[int], out: Path, events: Path | None = None) -> list[Path]:
    """Full-size renderer frames (no encoding). Uses an existing events.json
    when given (or one in ``out``), else renders the soundtrack first."""
    out.mkdir(parents=True, exist_ok=True)
    ev = events or (out / "events.json")
    clock = Clock.load(ev, storyboard.cuts[cut].frames) if ev.is_file() else render_audio(storyboard, cut, out)
    film = Film(storyboard, cut, fmt, clock)
    paths = []
    for f in frames:
        t = time.time()
        frame, rec = film.frame(f)
        p = out / f"still-f{f:04d}.png"
        _save_still(frame, p)
        print(f"{p}  {rec['scene']}  {1000 * (time.time() - t):.0f} ms", flush=True)
        paths.append(p)
    return paths


def main(argv: Sequence[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m promo.render", description="Render stills of a cut (no MP4).")
    ap.add_argument("--cut", default="30s")
    ap.add_argument("--format", default="9x16")
    ap.add_argument("--frames", required=True, help="comma-separated frames, or a:b:step")
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--events", type=Path, default=None, help="an events.json to time by (default: render the audio)")
    ap.add_argument("--set", action="append", default=[], dest="overrides")
    a = ap.parse_args(argv)
    sb = sbmod.load(overrides=a.overrides)
    if ":" in a.frames:
        x, y, *z = (int(v) for v in a.frames.split(":"))
        frames = list(range(x, y, z[0] if z else 1))
    else:
        frames = [int(v) for v in a.frames.split(",") if v.strip()]
    stills(sb, a.cut, a.format, frames, a.out, a.events)
    return 0


if __name__ == "__main__":
    sys.exit(main())
