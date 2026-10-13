"""Check the WRITTEN file against what the App Store takes.

Nothing here trusts the encoder's settings: every line is read back from the
file. Three readers, which must agree:

  boxes        mp4.py — this tool's own parse of the file's bytes (track
               headers, sample tables, the H.264 SPS, the AAC descriptor);
  AVFoundation swift/Inspect.swift — the only one that decodes: every video
               sample's time, the poster frame, the whole sound track;
  avmediainfo  Apple's command-line reader, as a second opinion.

Requirements (Apple, « App preview specifications », read on 2026-10-13, and
docs/design/pro-app-preview.md §2): .mp4, H.264 High Profile Level 4.0,
exactly 886 x 1920, progressive, 30 frames per second with every frame
exactly 1/30 s, 15 to 30 s, one enabled stereo AAC track at 48 kHz, under
500 MB, no alpha. The film's own: its length is the storyboard's, and the
frame at the poster time is the composed poster.

`verify()` returns the list of checks; the command exits non-zero when any
of them fails.
"""

from __future__ import annotations

import json
import re
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

import mp4
import swifttools

WIDTH, HEIGHT, FPS = 886, 1920, 30
MIN_S, MAX_S = 15, 30
MAX_BYTES = 500 * 1000 * 1000
PROFILE_HIGH, LEVEL_4_0 = 100, 40
AUDIO_RATE, AUDIO_CHANNELS, AAC_LC = 48000, 2, 2
# The video's average rate. Above: Apple's target tops out at 12 Mbps. Below:
# a film of mostly still screens measured 0.6–1.3 Mbps here; a file under
# 0.15 Mbps at this size would be a blank or broken encode.
VIDEO_BPS = (150_000, 12_000_000)
# High Profile Level 4.0: MaxBR 20 000 x 1.25 kbit/s (H.264 Table A-1, A.3.3)
PEAK_BPS = 25_000_000
AUDIO_MAX_BPS = 256_000
# The decoded poster frame against the composed PNG. Measured on 2026-10-13:
# the rehearsal film's own poster 58.8 dB with its worst 16 x 16 block off by
# 2.4 levels (53.0 dB and 3.9 on the tests' clips, written without the film's
# quantiser ceiling) — and the frame ONE STEP short of the last caption's
# cross-fade, 6 % of the old words still in it, 44.1 dB and 10.8. The limits
# sit between the two, so that frame is not the poster.
POSTER_MIN_PSNR = 48.0
POSTER_MAX_BLOCK = 8.0    # the largest mean difference of any 16 x 16 block


@dataclass
class Check:
    name: str
    ok: bool
    seen: str
    skipped: bool = False     # a check that was not run: it neither passes nor fails, and the report says so

    def line(self) -> str:
        return f"{'skip' if self.skipped else 'ok  ' if self.ok else 'FAIL'}  {self.name:<28} {self.seen}"


def _avmediainfo(path: Path) -> dict:
    """What Apple's `avmediainfo` prints, as far as the checks need it."""
    r = subprocess.run(["xcrun", "avmediainfo", str(path)], capture_output=True, text=True)
    text = r.stdout
    out: dict = {"ok": r.returncode == 0 and "Movie analyzed with 0 error" in text, "tracks": []}
    m = re.search(r"Track count: (\d+)", text)
    out["track_count"] = int(m.group(1)) if m else None
    for block in re.split(r"\nTrack \d+: ", text)[1:]:
        t: dict = {"kind": block.split(" ")[0]}
        for key, pattern, cast in (
            ("enabled", r"Enabled: (\w+)", lambda v: v == "Yes"),
            ("dimensions", r"\bDimensions: (\d+) x (\d+)", None),
            ("presentation", r"Presentation Dimensions: (\d+) x (\d+)", None),
            ("fps", r"Nominal frame rate: ([\d.]+) fps", float),
            ("min_duration", r"Minimum sample duration: (\d+)/(\d+) seconds", None),
            ("sample_rate", r"Sample rate: ([\d.]+)", float),
            ("channels", r"Channels per frame: (\d+)", int),
            ("format", r"Format: (.+)", str),
            ("reordering", r"(Frame reordering required)", bool),
        ):
            m = re.search(pattern, block)
            if not m:
                continue
            t[key] = cast(m.group(1)) if cast else [int(g) for g in m.groups()]
        out["tracks"].append(t)
    return out


def compare_images(a: Path, b: Path) -> tuple[float, float]:
    """(PSNR in dB, largest 16 x 16 block mean difference) of two pictures."""
    ia, ib = Image.open(a).convert("RGB"), Image.open(b).convert("RGB")
    if ia.size != ib.size:
        return 0.0, 255.0
    x = np.asarray(ia, dtype=np.float32)
    y = np.asarray(ib, dtype=np.float32)
    d = np.abs(x - y).max(axis=2)
    mse = float(((x - y) ** 2).mean())
    psnr = 99.0 if mse == 0 else float(10 * np.log10(255 ** 2 / mse))
    h, w = d.shape[0] // 16 * 16, d.shape[1] // 16 * 16
    blocks = d[:h, :w].reshape(h // 16, 16, w // 16, 16).mean(axis=(1, 3))
    return psnr, float(blocks.max())


def verify(path: Path, storyboard: dict, poster_png: Path | None = None) -> list[Check]:
    checks: list[Check] = []

    def add(name: str, ok: bool, seen: str) -> None:
        checks.append(Check(name, bool(ok), seen))

    path = Path(path)
    film = storyboard["film"]
    want_frames = round(film["duration_s"] * FPS)

    # ---- three readings ------------------------------------------------------
    try:
        box = mp4.read(path)
    except (mp4.Mp4Error, OSError) as e:
        add("readable (boxes)", False, str(e))
        return checks
    with tempfile.TemporaryDirectory() as tmp:
        r = swifttools.run("inspect", "facts", path, "--out", Path(tmp) / "facts.json", check=False)
        if r.returncode != 0:
            add("readable (AVFoundation)", False, r.stderr.strip())
            return checks
        av = json.loads((Path(tmp) / "facts.json").read_text())
    info = _avmediainfo(path)

    bv = [t for t in box["tracks"] if t.get("handler") == "vide"]
    ba = [t for t in box["tracks"] if t.get("handler") == "soun"]
    av_v = [t for t in av["tracks"] if t["type"] == "vide"]
    av_a = [t for t in av["tracks"] if t["type"] == "soun"]
    iv = [t for t in info["tracks"] if t["kind"] == "Video"]
    ia = [t for t in info["tracks"] if t["kind"] == "Sound"]

    # ---- container -----------------------------------------------------------
    major = (box["ftyp"] or {}).get("major")
    add("container", path.suffix == ".mp4" and major in ("mp42", "isom", "mp41"),
        f"{path.suffix or '(no extension)'}, brand {major!r}")
    add("file size", box["file_bytes"] < MAX_BYTES, f"{box['file_bytes']:,} bytes (limit 500 MB)")
    kinds = sorted(t.get("handler", "?") for t in box["tracks"])
    add("tracks", kinds == ["soun", "vide"] and len(av["tracks"]) == 2 and info["track_count"] == 2,
        f"boxes {kinds}, AVFoundation {len(av['tracks'])}, avmediainfo {info['track_count']} "
        f"(one video and one sound, nothing else)")
    add("avmediainfo reads it", info["ok"], "0 errors" if info["ok"] else "errors, or it could not open the file")

    # ---- video ---------------------------------------------------------------
    if len(bv) != 1 or len(av_v) != 1 or len(iv) != 1:
        add("video track", False, f"{len(bv)} in the boxes, {len(av_v)} per AVFoundation, {len(iv)} per avmediainfo")
    else:
        v, a_v, i_v = bv[0], av_v[0], iv[0]
        entry = v["entries"][0] if len(v["entries"]) == 1 else {}
        sps = entry.get("sps", {})
        avcc = entry.get("avcC", {})
        add("video enabled", v.get("enabled") and a_v["enabled"] and i_v.get("enabled"),
            f"boxes {v.get('enabled')}, AVFoundation {a_v['enabled']}, avmediainfo {i_v.get('enabled')}")
        add("codec", entry.get("format") == "avc1" and a_v.get("codec") == "avc1",
            f"{entry.get('format')!r} (H.264 is `avc1`), {len(v['entries'])} sample description(s)")
        add("profile and level",
            sps.get("profile_idc") == PROFILE_HIGH and sps.get("level_idc") == LEVEL_4_0
            and avcc.get("profile") == PROFILE_HIGH and avcc.get("level") == LEVEL_4_0,
            f"SPS profile_idc {sps.get('profile_idc')}, level_idc {sps.get('level_idc')}; "
            f"avcC {avcc.get('profile')}/{avcc.get('level')} (High is 100, Level 4.0 is 40)")
        sizes = {
            "SPS": (sps.get("width"), sps.get("height")),
            "stsd": (entry.get("width"), entry.get("height")),
            "tkhd": (v.get("tkhd_width"), v.get("tkhd_height")),
            "AVFoundation": tuple(a_v.get("natural_size", (None, None))),
            "avmediainfo": tuple(i_v.get("dimensions", (None, None))),
            "avmediainfo presentation": tuple(i_v.get("presentation", (None, None))),
        }
        add("size", all(s == (WIDTH, HEIGHT) for s in sizes.values()),
            ", ".join(f"{k} {s[0]} x {s[1]}" for k, s in sizes.items()).replace(".0", ""))
        identity = [65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824]
        square = entry.get("pasp") in (None, [1, 1]) and sps.get("sar") in (None, [1, 1])
        add("upright, square pixels",
            v.get("matrix") == identity and a_v.get("transform") == [1, 0, 0, 1, 0, 0] and square
            and entry.get("clap") is None,
            f"matrix {'identity' if v.get('matrix') == identity else v.get('matrix')}, "
            f"pasp {entry.get('pasp')}, SAR {sps.get('sar')}, clap {entry.get('clap')}")
        fiel = entry.get("fiel")
        add("progressive", sps.get("frame_mbs_only_flag") == 1 and (fiel is None or fiel[0] == 1),
            f"SPS frame_mbs_only_flag {sps.get('frame_mbs_only_flag')}, fiel {fiel}")
        add("no alpha, 8-bit 4:2:0",
            entry.get("depth") == 24 and sps.get("chroma_format_idc") == 1
            and sps.get("bit_depth_luma") == 8 and sps.get("bit_depth_chroma") == 8
            and not a_v.get("extensions", {}).get("ContainsAlphaChannel"),
            f"depth {entry.get('depth')}, chroma_format_idc {sps.get('chroma_format_idc')}, "
            f"{sps.get('bit_depth_luma')}-bit")

        scale = v.get("timescale", 0)
        step = scale // FPS if scale and scale % FPS == 0 else None
        stts = v.get("stts", [])
        count = sum(n for n, _ in stts)
        deltas = sorted({d for _, d in stts})
        samples = a_v.get("samples", {})
        av_durations = samples.get("durations", {})
        pts = samples.get("pts", [])
        on_grid = step is not None and pts == [i * step for i in range(len(pts))]
        add("every frame is 1/30 s",
            step is not None and deltas == [step] and list(av_durations) == [str(step)]
            and on_grid and i_v.get("min_duration") == [step, scale],
            f"timescale {scale}; sample durations in the boxes {deltas}, per AVFoundation "
            f"{dict(sorted(av_durations.items()))}; presentation times {'on' if on_grid else 'OFF'} the 1/30 s "
            f"grid; avmediainfo minimum {i_v.get('min_duration')}")
        add("frame rate", i_v.get("fps") == 30.0 and abs(a_v.get("nominal_fps", 0) - 30) < 1e-6,
            f"AVFoundation {a_v.get('nominal_fps')}, avmediainfo {i_v.get('fps')}")
        add("no frame reordering",
            not v.get("ctts") and samples.get("decode_order_is_presentation_order") is True
            and not a_v.get("requires_frame_reordering") and not i_v.get("reordering"),
            f"ctts offsets {v.get('ctts')}, AVFoundation reordering {a_v.get('requires_frame_reordering')}")
        add("frame count", count == want_frames and samples.get("count") == want_frames,
            f"boxes {count}, AVFoundation {samples.get('count')}; the storyboard's {film['duration_s']:g} s "
            f"is {want_frames}")
        seconds = v["duration"] / scale if scale else 0
        edits = v.get("edits")
        movie = box["movie"]
        plain = edits is None or (len(edits) == 1 and edits[0]["media_time"] == 0 and edits[0]["rate"] == 1.0
                                  and edits[0]["duration"] * scale == v["duration"] * movie["timescale"])
        add("duration",
            MIN_S <= seconds <= MAX_S and seconds == film["duration_s"] and plain
            and movie["duration"] / movie["timescale"] == seconds
            and av["duration"][0] / av["duration"][1] == seconds,
            f"video {seconds:.4f} s, movie {movie['duration'] / movie['timescale']:.4f} s, AVFoundation "
            f"{av['duration'][0] / av['duration'][1]:.4f} s; storyboard {film['duration_s']:g} s; Apple "
            f"{MIN_S}–{MAX_S} s; edit list {'plain' if plain else edits}")
        sizes_ = v.get("sizes", [])
        bps = sum(sizes_) * 8 / seconds if seconds else 0
        peak = max((sum(sizes_[i:i + FPS]) * 8 for i in range(0, max(1, len(sizes_) - FPS + 1))), default=0)
        add("video bit rate", VIDEO_BPS[0] <= bps <= VIDEO_BPS[1] and peak <= PEAK_BPS,
            f"{bps / 1e6:.2f} Mbps on average (accepted {VIDEO_BPS[0] / 1e6:g}–{VIDEO_BPS[1] / 1e6:g}), "
            f"busiest second {peak / 1e6:.2f} Mbps (Level 4.0 allows {PEAK_BPS / 1e6:g})")

        # ---- the poster frame ------------------------------------------------
        if poster_png is not None:
            index = round(film["poster_s"] * FPS)
            with tempfile.TemporaryDirectory() as tmp:
                r = swifttools.run("inspect", "frames", path, "--indices", index, "--out", tmp, check=False)
                decoded = Path(tmp) / f"frame_{index:06d}.png"
                if r.returncode != 0 or not decoded.exists():
                    add("poster frame", False, f"cannot decode frame {index}: {r.stderr.strip()}")
                else:
                    psnr, block = compare_images(decoded, poster_png)
                    add("poster frame", psnr >= POSTER_MIN_PSNR and block <= POSTER_MAX_BLOCK,
                        f"frame {index} ({film['poster_s']:g} s) decoded against {Path(poster_png).name}: "
                        f"{psnr:.1f} dB (at least {POSTER_MIN_PSNR:g}), worst 16 x 16 block off by "
                        f"{block:.1f} levels (at most {POSTER_MAX_BLOCK:g})")
        else:
            checks.append(Check("poster frame", True, "NOT compared — no composed poster was given", skipped=True))

    # ---- sound ---------------------------------------------------------------
    if len(ba) != 1 or len(av_a) != 1 or len(ia) != 1:
        add("sound track", False, f"{len(ba)} in the boxes, {len(av_a)} per AVFoundation, {len(ia)} per "
                                  f"avmediainfo — exactly one is required")
    else:
        s, a_s, i_s = ba[0], av_a[0], ia[0]
        entry = s["entries"][0] if len(s["entries"]) == 1 else {}
        esds = entry.get("esds", {})
        add("sound enabled", s.get("enabled") and a_s["enabled"] and i_s.get("enabled"),
            f"boxes {s.get('enabled')}, AVFoundation {a_s['enabled']}, avmediainfo {i_s.get('enabled')}")
        add("sound is AAC-LC",
            entry.get("format") == "mp4a" and esds.get("object_type_indication") == 0x40
            and esds.get("audio_object_type") == AAC_LC and a_s.get("format_id") == "aac ",
            f"{entry.get('format')!r}, object type indication {esds.get('object_type_indication')}, "
            f"audio object type {esds.get('audio_object_type')} (AAC-LC is 2), AVFoundation "
            f"{a_s.get('format_id')!r}")
        add("sound is stereo at 48 kHz",
            esds.get("sample_rate") == AUDIO_RATE and esds.get("channel_configuration") == AUDIO_CHANNELS
            and a_s.get("sample_rate") == AUDIO_RATE and a_s.get("channels") == AUDIO_CHANNELS
            and i_s.get("sample_rate") == AUDIO_RATE and i_s.get("channels") == AUDIO_CHANNELS,
            f"AAC config {esds.get('sample_rate')} Hz / {esds.get('channel_configuration')} ch, AVFoundation "
            f"{a_s.get('sample_rate')} / {a_s.get('channels')}, avmediainfo {i_s.get('sample_rate')} / "
            f"{i_s.get('channels')}")
        seconds = (bv[0]["duration"] / bv[0]["timescale"]) if len(bv) == 1 and bv[0].get("timescale") else 0
        decoded = a_s.get("decoded", {})
        range_ = a_s.get("time_range", [[0, 1], [0, 1]])
        heard = range_[1][0] / range_[1][1]
        add("sound runs the whole film",
            seconds > 0 and heard == seconds and range_[0][0] == 0
            and decoded.get("frames") == round(seconds * AUDIO_RATE),
            f"{heard:.4f} s from {range_[0][0] / range_[0][1]:g} s, {decoded.get('frames')} samples decoded "
            f"(video {seconds:.4f} s is {round(seconds * AUDIO_RATE)})")
        add("sound is digital silence", decoded.get("peak") == 0,
            f"loudest decoded sample {decoded.get('peak')} of 32767")
        rate = sum(s.get("sizes", [])) * 8 / seconds if seconds else 0
        add("sound bit rate", esds.get("avg_bitrate") == AUDIO_MAX_BPS and rate <= AUDIO_MAX_BPS,
            f"declared {esds.get('avg_bitrate')} bit/s (Apple: 256 kbps); silence takes {rate / 1000:.1f} kbit/s")
    return checks


def report(checks: list[Check], path: Path, note: str = "") -> tuple[str, bool]:
    """The report and whether every check that ran passed. A check that was
    not run is counted apart and named on the last line: 23 checks that pass
    are not 24."""
    ran = [c for c in checks if not c.skipped]
    ok = all(c.ok for c in ran)
    lines = [f"verify {path}"] + ["  " + c.line() for c in checks]
    failed = [c.name for c in ran if not c.ok]
    left_out = [c.name for c in checks if c.skipped]
    apart = f"; NOT RUN: {', '.join(left_out)}" if left_out else ""
    lines.append(f"PASS — {len(ran)} checks{apart}{note}" if ok
                 else f"FAIL — {len(failed)} of {len(ran)} checks: {', '.join(failed)}{apart}")
    return "\n".join(lines) + "\n", ok
