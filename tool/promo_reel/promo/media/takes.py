"""A recorded take, picture by picture, at the take's own times.

The Simulator's recorder writes a picture only when the screen changes (VFR:
H.264, 1206 × 2622, timescale 600 — one tick = 1/600 s). A take is therefore
a list of pictures, each with its presentation time, and the picture shown at
any instant ``t`` is **the latest picture whose time is ≤ t** — the rule the
App Store film used (``edit.held``) and the one every scene here follows.

  * Every picture's time comes from the container (ffprobe, packet times,
    sorted into presentation order: no decoding needed). When the App Store
    tool has scanned the take (``final/takes/take-N/scan.json``) the scan is
    checked against it — same file (sha256), same pictures, same times.
  * A picture is decoded by ffmpeg, seeking to the picture before it on its
    exact tick (``-copyts`` keeps the take's clock), and ffmpeg's
    ``showinfo`` reports the time of every picture it hands over: each is
    identified by that time, and a picture handed over where another was
    expected is an error, never a silent neighbour. Reading on from an open
    decoder serves the following pictures without a new seek.
  * Decoded pictures are kept in an LRU cache (a byte budget: one picture is
    12.6 MB).
  * Colour: decoded with the stream's own BT.709 matrix, limited range, to
    8-bit RGBA. The recorder tags its files Display P3 with the sRGB curve;
    the values are taken as they are — the App Store tool's rule (its README,
    « Two things the capture brings »: greys within one level of a
    screenshot). Measured here: the scaffold #F6F7F9 decodes to 247/247/249.
  * Masks (masks.py) are attached to the take, so that ``picture()`` only
    ever hands out masked pictures: a blur is on the source picture before
    anything is composited or accumulated from it.

Times written in notes and in the storyboard are picture times ROUNDED TO
THE MILLISECOND (« the snackbar is in at 131.448 » is the picture at
131.44833 s). ``index_at(131.448)`` follows the rule and returns the picture
before it; ``index_named(131.448)`` / ``time_named`` / ``picture_named``
return the picture the note means. Anchor a scene on ``time_named(…)``, then
map film time to take time and use ``index_at``.

Take names are the folders under ``takes/`` (take1b, take2b, take3, take5b…).
The App Store film numbered the four it used: take-1 = take1b, take-2 =
take2b, take-3 = take5b, take-4 = take3.
"""

from __future__ import annotations

import bisect
import collections
import hashlib
import json
import math
import queue
import re
import subprocess
import threading
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import TYPE_CHECKING, Iterable, Sequence

import numpy as np

from . import tools

if TYPE_CHECKING:  # pragma: no cover
    from .masks import Blur, MaskSet

#: The App Store film's own numbering of the takes it scanned
#: (``final/takes/take-N/``: scan.json + track.json).
APP_STORE_TAKES = {"take1b": "take-1", "take2b": "take-2", "take5b": "take-3", "take3": "take-4"}

#: The device the takes were recorded on, in points (gesture logs: ``device_points``).
DEVICE_POINTS = (402, 874)

DEFAULT_CACHE_MB = 768
#: Reading this many pictures on from an open decoder is cheaper than a new
#: seek (which decodes from the key frame before, ~1 s of pictures).
READ_ON_LIMIT = 48
#: ``t`` in seconds → ticks: the float error of e.g. 23.620 × 600 is far
#: below this, a tick (1.7 ms) far above.
_TICK_EPSILON = 1e-6
#: A time written to the millisecond names the picture within this of it.
NAMED_TOLERANCE_S = 0.001


class TakeError(RuntimeError):
    """A take that cannot be read as asked: missing files, a scan that does
    not describe it, a time before its first picture."""


class DecodeError(TakeError):
    """ffmpeg did not hand over the picture asked for."""


@dataclass(frozen=True)
class TakeFiles:
    """Everything recorded for one take (paths that exist, or None)."""

    name: str
    folder: Path
    movie: Path
    gestures_json: Path | None
    gestures_jsonl: Path | None
    notes: Path | None
    scan: Path | None
    track: Path | None
    phone_rect_csv: Path | None


def take_files(name: str, root: Path | None = None) -> TakeFiles:
    """The files of take ``name`` (a folder of ``takes/``) under the material root."""
    root = Path(root) if root is not None else tools.material_root()
    folder = root / "takes" / name
    movie = folder / "take.mov"
    if not movie.is_file():
        have = sorted(p.name for p in (root / "takes").iterdir() if (p / "take.mov").is_file()) \
            if (root / "takes").is_dir() else []
        raise TakeError(f"no take {name!r}: {movie} does not exist (takes: {', '.join(have) or 'none'})")
    final = root / "final" / "takes" / APP_STORE_TAKES[name] if name in APP_STORE_TAKES else None

    def opt(p: Path | None) -> Path | None:
        return p if p is not None and p.is_file() else None

    return TakeFiles(
        name=name, folder=folder, movie=movie,
        gestures_json=opt(folder / "gestures.json"), gestures_jsonl=opt(folder / "gestures.jsonl"),
        notes=opt(folder / "notes.txt"),
        scan=opt(final / "scan.json") if final else None, track=opt(final / "track.json") if final else None,
        phone_rect_csv=opt(folder / "phone_rect_per_frame.csv"))


@dataclass(frozen=True)
class Picture:
    """One picture of a take: its number, its time, its pixels (RGBA, H×W×4, read-only)."""

    index: int
    ticks: int
    time_s: float
    rgba: np.ndarray


@dataclass(frozen=True)
class Shown:
    """A picture on screen during part of a window [t0, t1): from ``start_s``
    to ``end_s``; ``weight`` is that share of the window."""

    index: int
    ticks: int
    start_s: float
    end_s: float
    weight: float


@dataclass(frozen=True)
class StreamInfo:
    width: int
    height: int
    timescale: int
    codec: str
    duration_s: float


def probe_stream(movie: Path) -> tuple[StreamInfo, list[int]]:
    """The video stream of ``movie`` and every picture's presentation time in
    ticks, ascending. From the container's packets: nothing is decoded."""
    out = subprocess.run(
        [tools.ffprobe(), "-v", "error", "-select_streams", "v:0", "-show_entries",
         "stream=width,height,time_base,codec_name,duration:format=duration", "-of", "json", str(movie)],
        check=True, capture_output=True, text=True).stdout
    doc = json.loads(out)
    streams = doc.get("streams") or []
    if not streams:
        raise TakeError(f"{movie}: no video stream")
    s = streams[0]
    tb = Fraction(s["time_base"])
    if tb.numerator != 1:
        raise TakeError(f"{movie}: time base {s['time_base']} is not 1/N")
    info = StreamInfo(int(s["width"]), int(s["height"]), tb.denominator, s.get("codec_name", "?"),
                      float(doc.get("format", {}).get("duration") or s.get("duration") or 0))
    packets = subprocess.run(
        [tools.ffprobe(), "-v", "error", "-select_streams", "v:0", "-show_entries", "packet=pts",
         "-of", "csv=p=0", str(movie)], check=True, capture_output=True, text=True).stdout
    pts = sorted(int(line.split(",")[0]) for line in packets.split() if line.strip() and line.strip() != "N/A")
    if not pts:
        raise TakeError(f"{movie}: the video stream has no pictures")
    if len(set(pts)) != len(pts):
        raise TakeError(f"{movie}: two pictures share a presentation time")
    return info, pts


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


class _Decoder:
    """One ffmpeg process handing over the take's pictures in order, each
    identified by the time ffmpeg reports for it (``showinfo``) — never by
    counting."""

    _SHOWINFO = re.compile(r"\bn:\s*\d+\s+pts:\s*-?\d+\s+pts_time:\s*(-?[0-9.]+)")

    def __init__(self, movie: Path, width: int, height: int, timescale: int, pts: Sequence[int], start: int):
        self.width, self.height, self.timescale = width, height, timescale
        self.pts = pts
        self.index_of = {p: i for i, p in enumerate(pts)}
        self.frame_bytes = width * height * 4
        self._times: "queue.Queue[int | None]" = queue.Queue()
        self._log: collections.deque[str] = collections.deque(maxlen=40)
        cmd = [tools.ffmpeg(), "-hide_banner", "-nostdin", "-nostats", "-loglevel", "info", "-copyts"]
        # Seek to the picture BEFORE the one wanted, on its exact tick: ffmpeg
        # rounds a seek point to the stream's ticks, so a point between two
        # pictures one tick apart may land on either; a picture's own tick is
        # unambiguous. That picture is handed over first and read past.
        self.start = start
        self.next = max(0, start - 1)
        if start > 0:
            cmd += ["-ss", f"{pts[start - 1] / timescale:.6f}"]
        self._first = True
        cmd += ["-i", str(movie), "-map", "0:v:0", "-an", "-sn", "-dn",
                "-vf", ("showinfo,scale=in_color_matrix=bt709:in_range=tv:"
                        "flags=accurate_rnd+full_chroma_int+bitexact,format=rgba"),
                "-fps_mode", "passthrough", "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"]
        self.proc = subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, bufsize=0)
        self._reader = threading.Thread(target=self._read_log, daemon=True)
        self._reader.start()

    def _read_log(self) -> None:
        assert self.proc.stderr is not None
        for raw in iter(self.proc.stderr.readline, b""):
            line = raw.decode("utf-8", "replace").rstrip()
            m = self._SHOWINFO.search(line)
            if m:
                self._times.put(round(float(m.group(1)) * self.timescale))
            else:
                self._log.append(line)
        self._times.put(None)

    def read(self) -> tuple[int, np.ndarray]:
        """The next picture: (its index, its pixels)."""
        assert self.proc.stdout is not None
        if self.next >= len(self.pts):
            raise DecodeError(f"read past the take's last picture ({len(self.pts) - 1})")
        frame = np.empty((self.height, self.width, 4), dtype=np.uint8)
        view = memoryview(frame).cast("B")
        got = 0
        while got < self.frame_bytes:
            n = self.proc.stdout.readinto(view[got:])
            if not n:
                break
            got += n
        if got < self.frame_bytes:
            self.close()
            raise DecodeError(f"ffmpeg stopped before picture {self.next} ({self.pts[self.next]} ticks): "
                              + " | ".join(list(self._log)[-5:]))
        try:
            ticks = self._times.get(timeout=60)
        except queue.Empty:
            ticks = None
        index = self.index_of.get(ticks) if ticks is not None else None
        if index is None:
            self.close()
            raise DecodeError(f"asked for picture {self.next} at {self.pts[self.next]} ticks, ffmpeg handed over "
                              f"a picture at {ticks} ticks, which is not one of the take's")
        # after a seek, the first picture may be any up to the one wanted;
        # from then on every picture follows the one before
        if (self._first and index > self.start) or (not self._first and index != self.next):
            self.close()
            raise DecodeError(f"asked for picture {self.next} at {self.pts[self.next]} ticks, ffmpeg handed over "
                              f"picture {index} at {ticks} ticks")
        self._first = False
        self.next = index + 1
        frame.flags.writeable = False
        return index, frame

    def close(self) -> None:
        if self.proc.poll() is None:
            self.proc.kill()
        self.proc.wait()
        self._reader.join(timeout=5)      # it stops at the pipe's end; then the pipe may be closed
        for pipe in (self.proc.stdout, self.proc.stderr):
            if pipe and not pipe.closed:
                pipe.close()


class Take:
    """One recorded take: every picture's time, and any picture's pixels.

    ``Take("take1b")`` finds the take under the material root;
    ``Take(path_to_take_mov)`` reads that file (its folder name is its name).
    Not thread-safe: one decoder, one cache."""

    def __init__(self, name_or_path: str | Path, *, root: Path | None = None,
                 cache_mb: int = DEFAULT_CACHE_MB, check_scan: bool = True):
        p = Path(name_or_path)
        if p.suffix.lower() in (".mov", ".mp4") or p.is_file():
            if not p.is_file():
                raise TakeError(f"no take file {p}")
            self.files = TakeFiles(p.parent.name, p.parent, p, None, None, None, None, None, None)
        else:
            self.files = take_files(str(name_or_path), root)
        self.name = self.files.name
        self.path = self.files.movie
        info, pts = probe_stream(self.path)
        self.width, self.height, self.timescale = info.width, info.height, info.timescale
        self.codec, self.duration_s = info.codec, info.duration_s
        self.pts: tuple[int, ...] = tuple(pts)
        self.px_per_pt = self.width / DEVICE_POINTS[0]
        if abs(self.height / DEVICE_POINTS[1] - self.px_per_pt) > 0.01:
            raise TakeError(f"{self.path}: {self.width}×{self.height} px is not {DEVICE_POINTS[0]}×"
                            f"{DEVICE_POINTS[1]} pt at one scale")
        self.scan: dict | None = None
        if self.files.scan is not None and check_scan:
            self.scan = self._checked_scan(self.files.scan)
        self._cache: collections.OrderedDict[tuple[int, bool], np.ndarray] = collections.OrderedDict()
        self._cache_budget = cache_mb * 1024 * 1024
        self._cache_bytes = 0
        self._decoder: _Decoder | None = None
        self._masks: "MaskSet | None" = None
        self.decodes = 0          # ffmpeg processes started (for tests and reports)

    # ---- the pictures' times ---------------------------------------------------

    def __len__(self) -> int:
        return len(self.pts)

    @property
    def count(self) -> int:
        return len(self.pts)

    @property
    def last_time_s(self) -> float:
        return self.pts[-1] / self.timescale

    def time_s(self, index: int) -> float:
        """The presentation time of picture ``index``, in seconds of the take."""
        return self.pts[self._index(index)] / self.timescale

    def ticks(self, t: float) -> int:
        """Seconds of the take → the tick on screen at ``t`` (floored)."""
        return math.floor(t * self.timescale + _TICK_EPSILON)

    def index_at(self, t: float) -> int:
        """The picture shown at ``t`` seconds: the latest whose time is ≤ t."""
        return self.index_at_ticks(self.ticks(t))

    def index_at_ticks(self, ticks: int) -> int:
        j = bisect.bisect_right(self.pts, ticks) - 1
        if j < 0:
            raise TakeError(f"{self.name}: {ticks / self.timescale:.4f} s is before the first picture "
                            f"({self.pts[0] / self.timescale:.4f} s)")
        return j

    def index_named(self, t: float) -> int:
        """The picture a note or the storyboard names by its time WRITTEN TO
        THE MILLISECOND: « 131.448 » is the picture at 131.44833 s (78 869
        ticks). ``index_at(131.448)`` is the picture before it — 131.448 s is
        still before that picture. The nearest picture within 1 ms is the one
        (rounded to nearest, or up, as take5b's notes write « 26.174 » for
        26.17333 s); none is an error, and so are two equally near."""
        T = self.timescale
        lo = bisect.bisect_left(self.pts, math.ceil((t - NAMED_TOLERANCE_S) * T - _TICK_EPSILON))
        hi = bisect.bisect_right(self.pts, math.floor((t + NAMED_TOLERANCE_S) * T + _TICK_EPSILON))
        near = sorted(range(lo, hi), key=lambda i: abs(self.pts[i] / T - t))
        if not near:
            shown = self.index_at(max(t, self.pts[0] / T))
            raise TakeError(f"{self.name}: no picture at {t:.3f} s (to the millisecond); the one shown then is "
                            f"picture {shown} at {self.time_s(shown):.4f} s")
        if len(near) > 1 and abs(abs(self.pts[near[1]] / T - t) - abs(self.pts[near[0]] / T - t)) < 1e-4:
            raise TakeError(f"{self.name}: {t:.3f} s names two pictures ({self.time_s(near[0]):.5f} and "
                            f"{self.time_s(near[1]):.5f} s); give the time more precisely")
        return near[0]

    def time_named(self, t: float) -> float:
        """The exact time of the picture named ``t`` (see ``index_named``)."""
        return self.time_s(self.index_named(t))

    def picture_named(self, t: float) -> Picture:
        """The picture named by its millisecond time (see ``index_named``)."""
        i = self.index_named(t)
        return Picture(i, self.pts[i], self.pts[i] / self.timescale, self.picture(i))

    def indices_between(self, t0: float, t1: float) -> list[int]:
        """Every picture on screen at some instant of [t0, t1): the one shown
        at t0 and every one that starts before t1."""
        if t1 <= t0:
            return []
        first = self.index_at(t0)
        last = bisect.bisect_left(self.pts, math.ceil(t1 * self.timescale - _TICK_EPSILON)) - 1
        return list(range(first, max(first, last) + 1))

    def pictures_between(self, t0: float, t1: float) -> list[Shown]:
        """What the screen showed during [t0, t1): each picture with the part
        of the window it was on screen (for accumulating motion blur from the
        take's own pictures, weighted by how long each was shown)."""
        if t1 <= t0:
            return []
        out = []
        idx = self.indices_between(t0, t1)
        for k, i in enumerate(idx):
            start = max(t0, self.pts[i] / self.timescale)
            end = min(t1, self.pts[idx[k + 1]] / self.timescale) if k + 1 < len(idx) else t1
            if end > start:
                out.append(Shown(i, self.pts[i], start, end, (end - start) / (t1 - t0)))
        return out

    # ---- the pictures' pixels -----------------------------------------------------

    def set_masks(self, blurs: "Iterable[Blur] | MaskSet | None") -> None:
        """Attach the blurs every picture is handed out with (None: none)."""
        from .masks import MaskSet
        if blurs is None:
            self._masks = None
        else:
            self._masks = blurs if isinstance(blurs, MaskSet) else MaskSet(blurs, self)
        for key in [k for k in self._cache if k[1]]:
            self._evict(key)

    @property
    def masks(self) -> "MaskSet | None":
        return self._masks

    def picture(self, index: int) -> np.ndarray:
        """Picture ``index``: RGBA, height × width × 4, uint8, read-only —
        with the take's masks applied when it has any."""
        index = self._index(index)
        if self._masks is None or not self._masks.active(self.pts[index]):
            return self.raw_picture(index)
        key = (index, True)
        if key in self._cache:
            self._cache.move_to_end(key)
            return self._cache[key]
        masked = self._masks.apply(self.raw_picture(index), self.pts[index])
        masked.flags.writeable = False
        self._store(key, masked)
        return masked

    def raw_picture(self, index: int) -> np.ndarray:
        """Picture ``index`` as recorded, masks NOT applied. For measuring and
        for checking a mask only: never composite it."""
        index = self._index(index)
        key = (index, False)
        if key in self._cache:
            self._cache.move_to_end(key)
            return self._cache[key]
        frame = self._decode(index)
        self._store(key, frame)
        return frame

    def picture_at(self, t: float) -> Picture:
        """The picture shown at ``t`` seconds of the take."""
        i = self.index_at(t)
        return Picture(i, self.pts[i], self.pts[i] / self.timescale, self.picture(i))

    def skia_image(self, index: int):
        """Picture ``index`` (masked) as a ``skia.Image`` (RGBA 8888, opaque)."""
        import skia
        return skia.Image.fromarray(np.ascontiguousarray(self.picture(index)),
                                    colorType=skia.ColorType.kRGBA_8888_ColorType,
                                    alphaType=skia.AlphaType.kUnpremul_AlphaType)

    def close(self) -> None:
        if self._decoder is not None:
            self._decoder.close()
            self._decoder = None
        self._cache.clear()
        self._cache_bytes = 0

    def __enter__(self) -> "Take":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    def __del__(self) -> None:  # pragma: no cover — best effort
        try:
            if self._decoder is not None:
                self._decoder.close()
        except Exception:  # noqa: BLE001
            pass

    def __repr__(self) -> str:
        return (f"Take({self.name!r}: {self.count} pictures, {self.width}×{self.height}, "
                f"{self.pts[0] / self.timescale:.3f}–{self.last_time_s:.3f} s)")

    # ---- internals ---------------------------------------------------------------

    def _index(self, index: int) -> int:
        if isinstance(index, bool) or not isinstance(index, (int, np.integer)):
            raise TakeError(f"a picture number is a whole number, not {index!r}")
        if not 0 <= index < len(self.pts):
            raise TakeError(f"{self.name} has pictures 0–{len(self.pts) - 1}, not {index}")
        return int(index)

    def _decode(self, index: int) -> np.ndarray:
        d = self._decoder
        if d is None or not (d.next <= index <= d.next + READ_ON_LIMIT):
            if d is not None:
                d.close()
            d = self._decoder = _Decoder(self.path, self.width, self.height, self.timescale, self.pts, index)
            self.decodes += 1
        try:
            while True:
                got, frame = d.read()
                if got == index:
                    return frame
                if got > index:
                    raise DecodeError(f"picture {index} was not handed over (ffmpeg went on to {got})")
        except DecodeError:
            d.close()
            self._decoder = None      # the next picture starts a fresh decoder
            raise

    def _store(self, key: tuple[int, bool], frame: np.ndarray) -> None:
        self._cache[key] = frame
        self._cache_bytes += frame.nbytes
        while self._cache_bytes > self._cache_budget and len(self._cache) > 1:
            self._evict(next(iter(self._cache)))

    def _evict(self, key: tuple[int, bool]) -> None:
        frame = self._cache.pop(key)
        self._cache_bytes -= frame.nbytes

    def _checked_scan(self, path: Path) -> dict:
        scan = json.loads(path.read_text(encoding="utf-8"))
        want = (scan.get("take") or {}).get("sha256")
        have = sha256(self.path)
        if want != have:
            raise TakeError(f"{path} describes another file (sha256 {str(want)[:16]}…, {self.path} is {have[:16]}…)")
        scanned = [f["pts"] for f in scan.get("frames", [])]
        if scanned != list(self.pts):
            raise TakeError(f"{path}: its {len(scanned)} pictures are not the take's {len(self.pts)} "
                            f"(first difference at picture "
                            f"{next((i for i, (a, b) in enumerate(zip(scanned, self.pts)) if a != b), min(len(scanned), len(self.pts)))})")
        video = scan.get("video", {})
        if (video.get("width"), video.get("height"), video.get("timescale")) != (self.width, self.height, self.timescale):
            raise TakeError(f"{path}: scanned {video.get('width')}×{video.get('height')} at 1/{video.get('timescale')}, "
                            f"the take is {self.width}×{self.height} at 1/{self.timescale}")
        return scan


def save_png(rgba: np.ndarray, path: Path) -> Path:
    """Write a picture as PNG (RGB: the takes are opaque)."""
    from PIL import Image
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(np.ascontiguousarray(rgba[..., :3])).save(path)
    return path


def main(argv: Sequence[str] | None = None) -> int:
    """``python -m promo.media.takes TAKE SECONDS [OUT.png]`` — which picture
    is shown at SECONDS, and (with OUT.png) its pixels, unmasked."""
    import argparse
    ap = argparse.ArgumentParser(prog="python -m promo.media.takes", description=main.__doc__)
    ap.add_argument("take")
    ap.add_argument("seconds", type=float, nargs="?")
    ap.add_argument("out", type=Path, nargs="?")
    args = ap.parse_args(argv)
    with Take(args.take) as take:
        print(repr(take))
        if args.seconds is None:
            return 0
        i = take.index_at(args.seconds)
        print(f"at {args.seconds:.3f} s: picture {i}, shown from {take.time_s(i):.4f} s "
              f"({take.pts[i]} ticks)" + (f" until {take.time_s(i + 1):.4f} s" if i + 1 < take.count else " to the end"))
        if args.out:
            print(save_png(take.raw_picture(i), args.out))
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
