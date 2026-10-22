"""Writing a film: raw RGBA frames in, an MP4 out.

One ffmpeg process takes the frames on its stdin — 8-bit RGBA, top row
first, exactly the declared width × height — at a constant frame rate, and
muxes the soundtrack WAV with them:

  video  H.264 (libx264) High@4.1, yuv420p, CRF 16, preset slow, a key frame
         every second; tagged BT.709 (primaries, transfer, matrix, limited
         range) and converted with the BT.709 matrix — the frames are sRGB
         values carried as Rec. 709 video, as the App Store film's were
         (tool/app_store_preview/README.md « The file »)
  audio  AAC-LC, 48 kHz, stereo, 256 kb/s
  file   MP4 with ``+faststart`` (the index first: plays while it downloads)

The frame count is exact: the writer is told how many frames the film has,
refuses one more, and on ``close()`` refuses one fewer; the soundtrack must
be exactly as long (frames × 1600 samples at 48 kHz) unless told otherwise.
The file is written as ``<name>.partial.mp4`` and only renamed once ffmpeg
has finished cleanly and the written file holds that many frames — a film
that failed is never left looking finished.

Frames must be opaque (alpha 255 everywhere: ffmpeg drops alpha, it does not
composite it); each frame is checked.
"""

from __future__ import annotations

import collections
import json
import subprocess
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from . import tools
from ..timebase import FPS, SAMPLE_RATE

DEFAULT_CRF = 16
DEFAULT_PRESET = "slow"
DEFAULT_AUDIO_BITRATE_K = 256
AUDIO_CHANNELS = 2


class WriterError(RuntimeError):
    """The film could not be written as specified."""


@dataclass(frozen=True)
class AudioInfo:
    codec: str
    sample_rate: int
    channels: int
    samples: int


def audio_info(path: Path) -> AudioInfo:
    """What a WAV holds, read by ffprobe (any PCM or float WAV)."""
    out = subprocess.run(
        [tools.ffprobe(), "-v", "error", "-select_streams", "a:0", "-show_entries",
         "stream=codec_name,sample_rate,channels,duration_ts,time_base", "-of", "json", str(path)],
        capture_output=True, text=True)
    if out.returncode != 0:
        raise WriterError(f"{path}: not a readable sound file ({out.stderr.strip()})")
    streams = json.loads(out.stdout).get("streams") or []
    if not streams:
        raise WriterError(f"{path}: no audio stream")
    s = streams[0]
    rate = int(s["sample_rate"])
    if s.get("time_base") != f"1/{rate}" or "duration_ts" not in s:
        raise WriterError(f"{path}: cannot count its samples (time base {s.get('time_base')})")
    return AudioInfo(s.get("codec_name", "?"), rate, int(s["channels"]), int(s["duration_ts"]))


class VideoWriter:
    """``with VideoWriter(out, 1080, 1920, frames=896, audio=wav) as w:
    w.write(frame)`` × 896. ``frame`` is an H×W×4 uint8 RGBA array (or bytes
    of that size, or a ``skia.Image``/``skia.Surface``)."""

    def __init__(self, path: Path | str, width: int, height: int, frames: int, *,
                 fps: int = FPS, audio: Path | str | None = None, exact_audio: bool = True,
                 crf: int = DEFAULT_CRF, preset: str = DEFAULT_PRESET,
                 audio_bitrate_k: int = DEFAULT_AUDIO_BITRATE_K, keyint: int | None = None,
                 check_opaque: bool = True):
        if width % 2 or height % 2 or width <= 0 or height <= 0:
            raise WriterError(f"{width}×{height}: yuv420p needs an even width and height")
        if frames <= 0:
            raise WriterError(f"a film has at least one frame, not {frames}")
        self.path = Path(path)
        if self.path.suffix.lower() != ".mp4":
            raise WriterError(f"{self.path}: the film is an .mp4")
        self.width, self.height, self.frames, self.fps = width, height, frames, fps
        self.frame_bytes = width * height * 4
        self.check_opaque = check_opaque
        self.written = 0
        self.audio = Path(audio) if audio is not None else None
        if self.audio is not None:
            info = audio_info(self.audio)
            if info.sample_rate != SAMPLE_RATE:
                raise WriterError(f"{self.audio}: {info.sample_rate} Hz; the soundtrack is {SAMPLE_RATE} Hz")
            want = frames * SAMPLE_RATE // fps
            if frames * SAMPLE_RATE % fps:
                raise WriterError(f"{frames} frames at {fps} fps are not a whole number of samples")
            if exact_audio and info.samples != want:
                raise WriterError(f"{self.audio}: {info.samples} samples; {frames} frames at {fps} fps need "
                                  f"exactly {want} ({want - info.samples:+d})")
            self.audio_info: AudioInfo | None = info
        else:
            self.audio_info = None
        self.partial = self.path.with_name(self.path.stem + ".partial.mp4")
        self.path.parent.mkdir(parents=True, exist_ok=True)
        cmd = [tools.ffmpeg(), "-hide_banner", "-nostdin", "-nostats", "-loglevel", "error", "-y",
               "-f", "rawvideo", "-pix_fmt", "rgba", "-s", f"{width}x{height}", "-framerate", str(fps),
               "-i", "pipe:0"]
        if self.audio is not None:
            cmd += ["-i", str(self.audio)]
        cmd += ["-map", "0:v:0"] + (["-map", "1:a:0"] if self.audio is not None else [])
        # The frames carry no colour description of their own: `setparams`
        # gives them BT.709 so the encoder writes the tags (the -color_* output
        # options alone are overridden by the frames' "unspecified").
        cmd += ["-vf", "scale=out_color_matrix=bt709:out_range=tv:flags=accurate_rnd+full_chroma_int,"
                       "format=yuv420p,"
                       "setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=tv",
                # High@4.1 (1080p30): x264 caps the references to the level's DPB (preset slow's 5 raised it to
                # 5.0 — review round 5), and the VBV holds the stream to 4.1's bit rate and buffer
                "-c:v", "libx264", "-profile:v", "high", "-level:v", "4.1", "-preset", preset, "-crf", str(crf),
                "-maxrate", "50M", "-bufsize", "62500k",
                "-pix_fmt", "yuv420p", "-g", str(keyint or fps),
                "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
                "-color_range", "tv", "-frames:v", str(frames)]
        if self.audio is not None:
            cmd += ["-c:a", "aac", "-b:a", f"{audio_bitrate_k}k", "-ar", str(SAMPLE_RATE),
                    "-ac", str(AUDIO_CHANNELS)]
        cmd += ["-movflags", "+faststart", "-f", "mp4", str(self.partial)]
        self.command = cmd
        self._errors: collections.deque[str] = collections.deque(maxlen=50)
        self.proc = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.PIPE, bufsize=0)
        self._drain = threading.Thread(target=self._read_errors, daemon=True)
        self._drain.start()
        self._closed = False

    def _read_errors(self) -> None:
        assert self.proc.stderr is not None
        for raw in iter(self.proc.stderr.readline, b""):
            self._errors.append(raw.decode("utf-8", "replace").rstrip())

    def _as_bytes(self, frame: Any) -> memoryview:
        if hasattr(frame, "makeImageSnapshot"):          # skia.Surface
            frame = frame.makeImageSnapshot()
        if hasattr(frame, "toarray") and not isinstance(frame, np.ndarray):   # skia.Image
            import skia
            frame = frame.toarray(colorType=skia.ColorType.kRGBA_8888_ColorType,
                                  alphaType=skia.AlphaType.kUnpremul_AlphaType)
        if not isinstance(frame, np.ndarray):
            view = memoryview(frame).cast("B")
            if view.nbytes != self.frame_bytes:
                raise WriterError(f"frame {self.written}: {view.nbytes} bytes, expected {self.frame_bytes}")
            frame = np.frombuffer(view, dtype=np.uint8).reshape(self.height, self.width, 4)
        if frame.shape != (self.height, self.width, 4) or frame.dtype != np.uint8:
            raise WriterError(f"frame {self.written}: {frame.shape} {frame.dtype}, expected "
                              f"({self.height}, {self.width}, 4) uint8 RGBA")
        if self.check_opaque:
            alpha = int(frame[..., 3].min())
            if alpha != 255:
                raise WriterError(f"frame {self.written} is not opaque (alpha down to {alpha}): "
                                  f"composite it onto the stage before writing")
        return memoryview(np.ascontiguousarray(frame)).cast("B")

    def write(self, frame: Any) -> None:
        """Append one frame."""
        if self._closed:
            raise WriterError("the writer is closed")
        if self.written >= self.frames:
            raise WriterError(f"the film has {self.frames} frames; frame {self.written} is one too many")
        data = self._as_bytes(frame)
        try:
            assert self.proc.stdin is not None
            self.proc.stdin.write(data)
        except BrokenPipeError:
            self.abort()
            raise WriterError("ffmpeg stopped taking frames: " + " | ".join(self._errors)) from None
        self.written += 1

    def close(self) -> Path:
        """Finish the file; returns its path. Refuses a film with a frame missing."""
        if self._closed:
            return self.path
        if self.written != self.frames:
            self.abort()
            raise WriterError(f"{self.path}: {self.written} frames written, the film has {self.frames}")
        assert self.proc.stdin is not None
        self.proc.stdin.close()
        code = self.proc.wait()
        self._drain.join(timeout=5)
        self._close_pipes()
        self._closed = True
        if code != 0:
            self.partial.unlink(missing_ok=True)
            raise WriterError(f"ffmpeg failed ({code}): " + " | ".join(self._errors))
        from .probe import count_video_frames
        n = count_video_frames(self.partial)
        if n != self.frames:
            self.partial.unlink(missing_ok=True)
            raise WriterError(f"{self.path}: the written file holds {n} frames, not {self.frames}")
        self.partial.replace(self.path)
        return self.path

    def abort(self) -> None:
        """Stop ffmpeg and remove the partial file."""
        if self._closed:
            return
        self._closed = True
        try:
            if self.proc.stdin:
                self.proc.stdin.close()
        except OSError:
            pass
        if self.proc.poll() is None:
            self.proc.kill()
        self.proc.wait()
        self._drain.join(timeout=5)
        self._close_pipes()
        self.partial.unlink(missing_ok=True)

    def _close_pipes(self) -> None:
        for pipe in (self.proc.stdin, self.proc.stderr):
            try:
                if pipe and not pipe.closed:
                    pipe.close()
            except OSError:
                pass

    def __enter__(self) -> "VideoWriter":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        if exc_type is not None:
            self.abort()
        else:
            self.close()
