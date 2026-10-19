"""What a written film is, read back from the file — and whether it is what
it should be.

``probe(path)`` is a JSON-able report from ffprobe and from the file's own
boxes: container, video (codec, profile, size, pixel format, colour tags,
frame rate, frame count, constant frame rate measured on every packet, key
frames), audio (codec, rate, channels, bit rate, duration, encoder delay),
the audio/video duration difference, and whether the index (``moov``) comes
before the media (``mdat``) — ``+faststart``.

``check(report, Expect(...))`` lists every way the film differs from what
was asked; ``assert_film(path, ...)`` raises ``ProbeError`` with that list.
Nothing is assumed from how the film was written: every value is read.
"""

from __future__ import annotations

import hashlib
import json
import subprocess
from dataclasses import asdict, dataclass
from fractions import Fraction
from pathlib import Path
from typing import Any

from . import tools
from ..timebase import FPS, SAMPLE_RATE

#: One AAC frame: the most the audio may differ from the video in length.
AAC_FRAME_SAMPLES = 1024


class ProbeError(AssertionError):
    """A film that is not what it should be. ``problems`` lists each difference."""

    def __init__(self, path: Path | str, problems: list[str]):
        self.path, self.problems = Path(path), problems
        super().__init__(f"{path}:\n" + "\n".join(f"  - {p}" for p in problems))


def _ffprobe_json(args: list[str], path: Path) -> dict:
    out = subprocess.run([tools.ffprobe(), "-v", "error", *args, "-of", "json", str(path)],
                         capture_output=True, text=True)
    if out.returncode != 0:
        raise ProbeError(path, [f"ffprobe cannot read it: {out.stderr.strip()}"])
    return json.loads(out.stdout)


def count_video_frames(path: Path | str) -> int:
    """The number of video packets (= frames) in the file, counted."""
    doc = _ffprobe_json(["-select_streams", "v:0", "-count_packets", "-show_entries",
                         "stream=nb_read_packets"], Path(path))
    streams = doc.get("streams") or []
    return int(streams[0]["nb_read_packets"]) if streams else 0


def top_level_boxes(path: Path | str) -> list[str]:
    """The MP4/MOV top-level box types, in file order (``ftyp``, ``moov``, ``mdat``…)."""
    boxes = []
    with open(path, "rb") as f:
        f.seek(0, 2)
        end = f.tell()
        pos = 0
        while pos + 8 <= end:
            f.seek(pos)
            head = f.read(16)
            size = int.from_bytes(head[:4], "big")
            kind = head[4:8].decode("latin-1")
            if size == 1:
                size = int.from_bytes(head[8:16], "big")
            elif size == 0:
                size = end - pos
            if size < 8:
                boxes.append(f"{kind}?")
                break
            boxes.append(kind)
            pos += size
    return boxes


def _fraction(text: str | None) -> Fraction | None:
    if not text or text in ("0/0", "N/A"):
        return None
    try:
        return Fraction(text)
    except (ValueError, ZeroDivisionError):
        return None


def probe(path: Path | str) -> dict[str, Any]:
    """The report of one film (see the module's docstring)."""
    path = Path(path)
    if not path.is_file():
        raise ProbeError(path, ["no such file"])
    doc = _ffprobe_json(["-show_format", "-show_streams"], path)
    fmt = doc.get("format", {})
    video = next((s for s in doc.get("streams", []) if s.get("codec_type") == "video"), None)
    audio = next((s for s in doc.get("streams", []) if s.get("codec_type") == "audio"), None)
    sha = hashlib.sha256(path.read_bytes()).hexdigest()
    boxes = top_level_boxes(path)
    report: dict[str, Any] = {
        "file": {"path": str(path), "bytes": path.stat().st_size, "sha256": sha},
        "container": {"format": fmt.get("format_name"), "duration_s": float(fmt.get("duration", 0) or 0),
                      "bit_rate": int(fmt.get("bit_rate", 0) or 0), "boxes": boxes,
                      "faststart": "moov" in boxes and "mdat" in boxes and boxes.index("moov") < boxes.index("mdat")},
        "video": None, "audio": None, "av": None,
    }
    if video is not None:
        packets = _ffprobe_json(["-select_streams", "v:0", "-show_entries", "packet=pts,duration,flags"],
                                path).get("packets", [])
        pts = sorted(int(p["pts"]) for p in packets if p.get("pts") not in (None, "N/A"))
        steps = sorted({b - a for a, b in zip(pts, pts[1:])})
        durations = sorted({int(p["duration"]) for p in packets if p.get("duration") not in (None, "N/A")})
        tb = _fraction(video.get("time_base"))
        step = steps[0] if len(steps) == 1 else None
        measured_fps = (1 / (step * tb)) if (step and tb) else None
        report["video"] = {
            "codec": video.get("codec_name"), "profile": video.get("profile"), "level": video.get("level"),
            "width": video.get("width"), "height": video.get("height"), "pix_fmt": video.get("pix_fmt"),
            "color_range": video.get("color_range"), "color_space": video.get("color_space"),
            "color_transfer": video.get("color_transfer"), "color_primaries": video.get("color_primaries"),
            "r_frame_rate": video.get("r_frame_rate"), "avg_frame_rate": video.get("avg_frame_rate"),
            "time_base": video.get("time_base"),
            "frames": len(packets), "declared_frames": int(video["nb_frames"]) if video.get("nb_frames") else None,
            "duration_s": float(video.get("duration", 0) or 0),
            "start_s": float(video.get("start_time", 0) or 0),
            "cfr": len(steps) <= 1 and len(durations) <= 1 and (not steps or not durations or steps[0] == durations[0]),
            "frame_step_ticks": steps if len(steps) <= 4 else steps[:4] + ["…"],
            "measured_fps": float(measured_fps) if measured_fps else None,
            "key_frames": sum(1 for p in packets if "K" in (p.get("flags") or "")),
            "has_b_frames": video.get("has_b_frames"), "bit_rate": int(video.get("bit_rate", 0) or 0),
        }
    if audio is not None:
        report["audio"] = {
            "codec": audio.get("codec_name"), "profile": audio.get("profile"),
            "sample_rate": int(audio.get("sample_rate", 0) or 0), "channels": audio.get("channels"),
            "channel_layout": audio.get("channel_layout"), "bit_rate": int(audio.get("bit_rate", 0) or 0),
            "duration_s": float(audio.get("duration", 0) or 0), "start_s": float(audio.get("start_time", 0) or 0),
            "encoder_delay_samples": audio.get("initial_padding"),
        }
    if video is not None and audio is not None:
        v, a = report["video"]["duration_s"], report["audio"]["duration_s"]
        report["av"] = {"duration_difference_s": round(a - v, 6),
                        "start_difference_s": round(report["audio"]["start_s"] - report["video"]["start_s"], 6)}
    return report


@dataclass(frozen=True)
class Expect:
    """What a film must be. ``None`` leaves a value unchecked."""

    frames: int | None = None
    width: int | None = None
    height: int | None = None
    fps: int = FPS
    video_codec: str = "h264"
    profile: str | None = "High"
    pix_fmt: str = "yuv420p"
    colour: str | None = "bt709"
    audio: bool = True
    audio_codec: str = "aac"
    sample_rate: int = SAMPLE_RATE
    channels: int = 2
    min_audio_bit_rate: int | None = 200_000
    faststart: bool = True
    av_tolerance_s: float = AAC_FRAME_SAMPLES / SAMPLE_RATE


def check(report: dict[str, Any], expect: Expect) -> list[str]:
    """Every way ``report`` differs from ``expect`` (empty: none)."""
    problems: list[str] = []
    v, a = report.get("video"), report.get("audio")

    def want(label: str, got: Any, wanted: Any) -> None:
        if wanted is not None and got != wanted:
            problems.append(f"{label}: {got!r}, expected {wanted!r}")

    if v is None:
        problems.append("no video stream")
    else:
        want("video codec", v["codec"], expect.video_codec)
        want("profile", v["profile"], expect.profile)
        want("pixel format", v["pix_fmt"], expect.pix_fmt)
        want("width", v["width"], expect.width)
        want("height", v["height"], expect.height)
        want("frames", v["frames"], expect.frames)
        if expect.frames is not None and v["declared_frames"] not in (None, expect.frames):
            problems.append(f"declared frames: {v['declared_frames']}, expected {expect.frames}")
        if expect.colour is not None:
            for key in ("color_space", "color_transfer", "color_primaries"):
                want(key.replace("_", " "), v[key], expect.colour)
            want("colour range", v["color_range"], "tv")
        if not v["cfr"]:
            problems.append(f"not constant frame rate (packet steps {v['frame_step_ticks']} ticks of {v['time_base']})")
        if v["measured_fps"] is None or abs(v["measured_fps"] - expect.fps) > 1e-6:
            problems.append(f"frame rate measured {v['measured_fps']}, expected {expect.fps}")
        want("declared frame rate", _fraction(v["r_frame_rate"]), Fraction(expect.fps))
        if expect.frames is not None:
            dur = expect.frames / expect.fps
            if abs(v["duration_s"] - dur) > 0.5 / expect.fps:
                problems.append(f"video duration {v['duration_s']:.4f} s, expected {dur:.4f} s")
    if expect.audio:
        if a is None:
            problems.append("no audio stream")
        else:
            want("audio codec", a["codec"], expect.audio_codec)
            want("sample rate", a["sample_rate"], expect.sample_rate)
            want("channels", a["channels"], expect.channels)
            if expect.min_audio_bit_rate is not None and a["bit_rate"] < expect.min_audio_bit_rate:
                problems.append(f"audio bit rate {a['bit_rate']} b/s, expected at least {expect.min_audio_bit_rate}")
            if report.get("av") and abs(report["av"]["duration_difference_s"]) > expect.av_tolerance_s:
                problems.append(f"audio and video lengths differ by {report['av']['duration_difference_s']:+.4f} s "
                                f"(at most {expect.av_tolerance_s:.4f} s)")
    elif a is not None:
        problems.append("an audio stream, expected none")
    if expect.faststart and not report["container"]["faststart"]:
        problems.append(f"not +faststart: boxes {report['container']['boxes']}")
    return problems


def assert_film(path: Path | str, **expect: Any) -> dict[str, Any]:
    """Probe ``path`` and raise ``ProbeError`` unless it is what ``expect``
    (``Expect``'s fields) says. Returns the report."""
    report = probe(path)
    problems = check(report, Expect(**expect))
    if problems:
        raise ProbeError(path, problems)
    return report


def write_report(report: dict[str, Any], path: Path | str, expect: Expect | None = None) -> Path:
    """Save a report (and, with ``expect``, what was checked and what failed) as JSON."""
    doc = dict(report)
    if expect is not None:
        doc["expected"] = asdict(expect)
        doc["problems"] = check(report, expect)
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(doc, indent=1, ensure_ascii=False, default=str) + "\n", encoding="utf-8")
    return path


def main(argv: list[str] | None = None) -> int:
    """``python -m promo.media.probe FILM.mp4 [--frames N --width W --height H]``:
    print the report, and the problems when expectations are given."""
    import argparse
    ap = argparse.ArgumentParser(prog="python -m promo.media.probe", description=main.__doc__)
    ap.add_argument("film", type=Path)
    ap.add_argument("--frames", type=int)
    ap.add_argument("--width", type=int)
    ap.add_argument("--height", type=int)
    ap.add_argument("--no-audio", action="store_true")
    args = ap.parse_args(argv)
    report = probe(args.film)
    print(json.dumps(report, indent=1, ensure_ascii=False, default=str))
    problems = check(report, Expect(frames=args.frames, width=args.width, height=args.height, audio=not args.no_audio))
    for p in problems:
        print(f"PROBLEM: {p}")
    return 1 if problems else 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
