"""Looking at a film: frames pulled from the written MP4, and contact sheets.

``pull_frames(mp4, [144, 160])`` decodes exactly those frames of the file
— what a viewer gets, after the encoder. Each is found by an accurate seek
to half a frame before it, with the film's own clock kept (``-copyts``), and
ffmpeg's ``showinfo`` reports the time of the frame it hands over: a frame
whose time is not the one asked for is an error, never its neighbour.

``contact_sheet(tiles, out)`` lays labelled thumbnails on a grid (PNG); a
``label()`` names a frame by its number, its time and its place in the music
(``f144 · 4.800 s · 3.2.0``). ``beat_sheet(mp4, out)`` is the sheet of every
beat of a film — the review the storyboard asks for per cut and format.
"""

from __future__ import annotations

import re
import subprocess
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import Sequence, Union

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from . import tools
from ..timebase import DEFAULT as TIMEBASE, TimeBase

#: Frames pulled at once (one ffmpeg each): two keeps the machine usable.
PULL_WORKERS = 2

PAPER = (250, 250, 250)
INK = (26, 26, 26)
MUTED = (110, 110, 110)


class SheetError(RuntimeError):
    """A frame that could not be pulled, or a sheet that could not be made."""


def label(frame: int, timebase: TimeBase = TIMEBASE) -> str:
    """``f144 · 4.800 s · 3.2.0`` — off the 16th grid: ``3.2.1+1``."""
    pos, extra = timebase.split_frame(frame)
    where = f"{pos}" + (f"+{extra}" if extra else "")
    return f"f{frame} · {float(timebase.seconds(frame)):.3f} s · {where}"


@dataclass(frozen=True)
class Tile:
    """One thumbnail of a sheet: a picture (RGBA/RGB array, or a PNG path) and its label."""

    image: Union[np.ndarray, Path, str]
    label: str


def _font(size: int) -> ImageFont.ImageFont:
    path = tools.FONTS / "Inter-Variable.ttf"
    try:
        return ImageFont.truetype(str(path), size)
    except OSError:
        return ImageFont.load_default()


def _as_image(image: Union[np.ndarray, Path, str]) -> Image.Image:
    if isinstance(image, np.ndarray):
        return Image.fromarray(np.ascontiguousarray(image[..., :3]))
    with Image.open(image) as im:
        return im.convert("RGB")


def contact_sheet(tiles: Sequence[Tile], out: Path | str, *, columns: int = 8, tile_width: int = 200,
                  title: str | None = None) -> Path:
    """A PNG grid of labelled thumbnails, in order, left to right."""
    if not tiles:
        raise SheetError("a contact sheet needs at least one tile")
    images = [_as_image(t.image) for t in tiles]
    aspect = images[0].height / images[0].width
    tile_h = round(tile_width * aspect)
    gap, label_h = 12, 26
    title_h = 44 if title else 0
    columns = max(1, min(columns, len(tiles)))
    rows = -(-len(tiles) // columns)
    sheet = Image.new("RGB", (gap + columns * (tile_width + gap),
                              title_h + gap + rows * (tile_h + label_h + gap)), PAPER)
    draw = ImageDraw.Draw(sheet)
    if title:
        draw.text((gap, 12), title, font=_font(22), fill=INK)
    small = _font(14)
    for k, (tile, im) in enumerate(zip(tiles, images)):
        r, c = divmod(k, columns)
        x = gap + c * (tile_width + gap)
        y = title_h + gap + r * (tile_h + label_h + gap)
        thumb = im.resize((tile_width, round(tile_width * im.height / im.width)), Image.LANCZOS)
        sheet.paste(thumb.crop((0, 0, tile_width, min(tile_h, thumb.height))), (x, y))
        draw.rectangle((x - 1, y - 1, x + tile_width, y + tile_h), outline=(200, 200, 200))
        draw.text((x, y + tile_h + 5), tile.label, font=small, fill=MUTED)
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    return out


@dataclass(frozen=True)
class _Film:
    width: int
    height: int
    fps: Fraction
    frames: int


def _film(mp4: Path) -> _Film:
    from .probe import probe
    v = probe(mp4).get("video")
    if v is None:
        raise SheetError(f"{mp4}: no video stream")
    fps = Fraction(v["r_frame_rate"])
    return _Film(v["width"], v["height"], fps, v["frames"])


_SHOWINFO = re.compile(r"\bn:\s*\d+\s+pts:\s*-?\d+\s+pts_time:\s*(-?[0-9.]+)")


def _pull_one(mp4: Path, film: _Film, frame: int) -> np.ndarray:
    seek = (frame - Fraction(1, 2)) / film.fps
    cmd = [tools.ffmpeg(), "-hide_banner", "-nostdin", "-nostats", "-loglevel", "info", "-copyts"]
    if frame > 0:
        cmd += ["-ss", f"{float(seek):.6f}"]
    cmd += ["-i", str(mp4), "-map", "0:v:0", "-frames:v", "1",
            "-vf", "showinfo,scale=in_color_matrix=bt709:in_range=tv:flags=accurate_rnd+full_chroma_int,format=rgba",
            "-f", "rawvideo", "-pix_fmt", "rgba", "pipe:1"]
    run = subprocess.run(cmd, capture_output=True)
    if run.returncode != 0:
        raise SheetError(f"{mp4}: ffmpeg could not pull frame {frame}: {run.stderr.decode()[-400:]}")
    times = [float(m.group(1)) for m in _SHOWINFO.finditer(run.stderr.decode("utf-8", "replace"))]
    size = film.width * film.height * 4
    if len(run.stdout) != size or not times:
        raise SheetError(f"{mp4}: frame {frame} is not in the film ({film.frames} frames)")
    got = round(Fraction(times[0]).limit_denominator(1_000_000) * film.fps)
    if got != frame:
        raise SheetError(f"{mp4}: asked for frame {frame}, ffmpeg handed over frame {got}")
    return np.frombuffer(run.stdout, dtype=np.uint8).reshape(film.height, film.width, 4).copy()


def pull_frames(mp4: Path | str, frames: Sequence[int]) -> dict[int, np.ndarray]:
    """Exactly these frames of the written film, RGBA, by frame number."""
    mp4 = Path(mp4)
    film = _film(mp4)
    wanted = sorted(set(int(f) for f in frames))
    bad = [f for f in wanted if not 0 <= f < film.frames]
    if bad:
        raise SheetError(f"{mp4} has frames 0–{film.frames - 1}, not {bad}")
    with ThreadPoolExecutor(max_workers=PULL_WORKERS) as pool:
        pulled = list(pool.map(lambda f: _pull_one(mp4, film, f), wanted))
    return dict(zip(wanted, pulled))


def save_frames(mp4: Path | str, frames: Sequence[int], out_dir: Path | str) -> list[Path]:
    """Pull frames and save each as ``f0144.png`` in ``out_dir``."""
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    paths = []
    for f, rgba in pull_frames(mp4, frames).items():
        p = out_dir / f"f{f:04d}.png"
        Image.fromarray(np.ascontiguousarray(rgba[..., :3])).save(p)
        paths.append(p)
    return paths


def beat_sheet(mp4: Path | str, out: Path | str, *, every: int | None = None, timebase: TimeBase = TIMEBASE,
               columns: int = 8, tile_width: int = 200, title: str | None = None) -> Path:
    """The contact sheet of a film on its beats (every ``every`` frames;
    default one beat), each labelled with its frame, time and position."""
    mp4 = Path(mp4)
    film = _film(mp4)
    step = every or timebase.frames_per_beat
    frames = list(range(0, film.frames, step))
    pulled = pull_frames(mp4, frames)
    tiles = [Tile(pulled[f], label(f, timebase)) for f in frames]
    return contact_sheet(tiles, out, columns=columns, tile_width=tile_width,
                         title=title or f"{mp4.name} — {film.frames} frames, one tile every {step}")


def main(argv: Sequence[str] | None = None) -> int:
    """``python -m promo.media.sheets FILM.mp4 OUT.png [--every N]`` — the beat sheet of a film."""
    import argparse
    ap = argparse.ArgumentParser(prog="python -m promo.media.sheets", description=main.__doc__)
    ap.add_argument("film", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--every", type=int)
    args = ap.parse_args(argv)
    print(beat_sheet(args.film, args.out, every=args.every))
    return 0


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
