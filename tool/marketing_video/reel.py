#!/usr/bin/env python3
"""The MyWeli Pro marketing Reel « Le trait ». Design: docs/design/pro-marketing-reel.md.

  python3 tool/marketing_video/reel.py build --assets <main checkout>/build/app-store/pro \\
      [--photos <main checkout>/build/marketing/photos] --out <folder> [--work <folder>] [--jobs 4]
  python3 tool/marketing_video/reel.py verify <folder>/reel.mp4 [--work <folder>]
  python3 tool/marketing_video/reel.py sheet <folder>/reel.mp4 --out contact-sheet.png
  python3 tool/marketing_video/reel.py selftest

See README.md.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import multiprocessing as mp
import os
import shutil
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import reel_plan as plan           # noqa: E402  (puts tool/app_store_preview on the path)
import reel_draw as rd             # noqa: E402
import reel_footage as rf          # noqa: E402
import reel_photo as rp            # noqa: E402
import reel_scenes as rs           # noqa: E402
import reel_verify as rv           # noqa: E402
import swifttools                  # noqa: E402  (tool/app_store_preview)
from PIL import Image, ImageDraw   # noqa: E402

# The encoder: the App Preview's Common.swift and Writer.swift, with this
# tool's ReelEncode.swift (MovieSpec.social). Compiled into that tool's
# build/bin like its own helpers, rebuilt when a source changes.
swifttools.SOURCES.setdefault("reel-encode", ["Common.swift", "Writer.swift", str(HERE / "swift/ReelEncode.swift")])

# R3 adds S5's scroll (13.9–16.3), S7's frame 690 and its neighbours (22.9–23.1);
# R4 S7b's push-in late in the beat (26.5)
KEY_TIMES = [0.0, 1.5, 3.5, 6.1, 6.2, 10.4, 11.0, 12.9, 13.5, 13.9, 14.1, 14.5, 15.0, 15.5, 16.0, 16.3, 17.0,
             21.0, 22.9, 23.0, 23.1, 24.0, 24.5, 25.5, 26.5, 26.9, 27.5, 29.5]
OUTPUTS = ("reel.mp4", "contact-sheet.png", "poster-hook.png", "poster-end.png", "cover.png", "cover-4x5.png",
           "verify.txt", "build.json")


def sha256(path: Path) -> str:
    return rf.sha256(path)


# ---- rendering (one process per --jobs) ----------------------------------------------

_W: dict = {}


def _init(work: str) -> None:
    P = plan.load()
    _W["P"] = P
    _W["comp"] = rs.Composer(P, rf.Footage(Path(work)))
    _W["dir"] = Path(work) / "frames"


def _render(n: int) -> tuple[int, str]:
    fr = _W["comp"].frame(n)
    data = fr.im.tobytes()
    name = hashlib.sha1(data).hexdigest()[:16] + ".png"
    path = _W["dir"] / name
    if not path.exists():
        tmp = path.with_suffix(f".{os.getpid()}.tmp")
        fr.im.save(tmp, "PNG", compress_level=1)
        os.replace(tmp, path)
    return n, name


def render(P: plan.Plan, work: Path, jobs: int) -> list[str]:
    frames_dir = work / "frames"
    if frames_dir.exists():
        shutil.rmtree(frames_dir)
    frames_dir.mkdir(parents=True)
    names = [""] * P.frames
    ctx = mp.get_context("spawn")
    with ctx.Pool(jobs, initializer=_init, initargs=(str(work),)) as pool:
        for n, name in pool.imap_unordered(_render, range(P.frames), chunksize=6):
            names[n] = name
    (frames_dir / "frames.json").write_text(json.dumps(
        {"fps": P.fps, "width": P.width, "height": P.height, "frames": names}), encoding="utf-8")
    return names


# ---- reading the written file back -----------------------------------------------------

def decode(movie: Path, indices: list[int], out: Path) -> dict[int, Path]:
    out.mkdir(parents=True, exist_ok=True)
    swifttools.run("inspect", "frames", movie, "--indices", ",".join(map(str, sorted(set(indices)))), "--out", out)
    return {n: out / f"frame_{n:06d}.png" for n in indices}


def contact_sheet(movie: Path, P: plan.Plan, out: Path, work: Path) -> None:
    """A frame every 0.5 s, decoded from the written file, labelled."""
    step = P.fps // 2
    indices = list(range(0, P.frames, step))
    files = decode(movie, indices, work / "sheet")
    c = plan.colours()
    cols, tw, gap, label = 10, 180, 14, 30
    th = round(tw * P.height / P.width)
    rows = (len(indices) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw + (cols + 1) * gap, rows * (th + label + gap) + gap), c["secondary"])
    draw = ImageDraw.Draw(sheet)
    font = rd.inter(17)
    for k, n in enumerate(indices):
        x = gap + (k % cols) * (tw + gap)
        y = gap + (k // cols) * (th + label + gap)
        sheet.paste(Image.open(files[n]).convert("RGB").resize((tw, th), Image.LANCZOS), (x, y))
        cut = n in P.cuts or n == 0
        draw.rectangle((x - 1, y - 1, x + tw, y + th), outline=c["primary"] if cut else c["border"], width=1)
        draw.text((x, y + th + 6), f"{n / P.fps:.1f} s  {P.scene_at(n)}" + ("  cut" if cut and n else ""),
                  font=font, fill=c["textPrimary"])
    sheet.save(out, "PNG")


def key_frames(P: plan.Plan) -> dict[float, int]:
    return {t: round(t * P.fps) for t in KEY_TIMES}


# ---- commands --------------------------------------------------------------------------

def cmd_build(a: argparse.Namespace) -> None:
    started = time.monotonic()
    P = plan.load()
    out: Path = a.out
    out.mkdir(parents=True, exist_ok=True)
    for name in OUTPUTS:
        (out / name).unlink(missing_ok=True)
    for f in out.glob("frame-*.png"):
        f.unlink()
    work: Path = a.work or out / "work"
    work.mkdir(parents=True, exist_ok=True)

    print("reel: conforming the takes …", flush=True)
    facts = rf.prepare(a.assets, work)
    photos = a.photos or a.assets.parents[1] / "marketing/photos"
    facts["photos"] = rp.prepare(photos, work)
    t_prep = time.monotonic()
    print(f"reel: composing {P.frames} frames on {a.jobs} process(es) …", flush=True)
    names = render(P, work, a.jobs)
    t_render = time.monotonic()
    print(f"reel: {len(set(names))} distinct pictures in {t_render - t_prep:.0f} s; encoding …", flush=True)
    movie = out / "reel.mp4"
    r = swifttools.run("reel-encode", work / "frames", "--frames", P.frames, "--out", movie)
    print(r.stdout.strip(), flush=True)
    t_encode = time.monotonic()

    frames_dir = work / "frames"
    shutil.copyfile(frames_dir / names[0], out / "poster-hook.png")
    shutil.copyfile(frames_dir / names[-1], out / "poster-end.png")
    # R3: the cover is composed apart (its headline 30 px lower) and uploaded
    # apart; cover-4x5.png is it cut to the 4:5 feed crop
    cover = rs.Composer(P, rf.Footage(work)).cover().im
    cover.save(out / "cover.png", "PNG")
    cover.crop((0, P.crop_feed[0], P.width, P.crop_feed[1])).save(out / "cover-4x5.png", "PNG")
    keys = key_frames(P)
    files = decode(movie, list(keys.values()), work / "keys")
    for t, n in keys.items():
        shutil.copyfile(files[n], out / f"frame-{t:.1f}.png")
    contact_sheet(movie, P, out / "contact-sheet.png", work)

    print("reel: verifying the written file …", flush=True)
    checks = rv.verify(movie, P, work, sorted(set(keys.values())))
    digest = sha256(movie)
    text, ok = rv.report(checks, movie, f" — reel.mp4 sha256 {digest[:16]}…")
    (out / "verify.txt").write_text(text, encoding="utf-8")
    done = time.monotonic()
    record = {
        "file": "reel.mp4", "sha256": digest, "bytes": movie.stat().st_size,
        "storyboard_sha256": sha256(plan.STORYBOARD),
        "takes": {k: v for k, v in facts.items() if k != "photos"}, "photos": facts["photos"],
        "frames": P.frames, "distinct_pictures": len(set(names)),
        "seconds": {"conform": round(t_prep - started, 1), "compose": round(t_render - t_prep, 1),
                    "encode": round(t_encode - t_render, 1), "covers_sheet_verify": round(done - t_encode, 1),
                    "total": round(done - started, 1)},
        "jobs": a.jobs, "verified": ok,
    }
    (out / "build.json").write_text(json.dumps(record, indent=1) + "\n", encoding="utf-8")
    print(text, end="")
    print(f"reel: {done - started:.0f} s in all (compose {t_render - t_prep:.0f} s, encode {t_encode - t_render:.0f} s)")
    if not ok:
        sys.exit(1)


def cmd_verify(a: argparse.Namespace) -> None:
    P = plan.load()
    keys = sorted(set(key_frames(P).values())) if a.work else None
    checks = rv.verify(a.movie, P, a.work, keys)
    text, ok = rv.report(checks, a.movie)
    print(text, end="")
    if not ok:
        sys.exit(1)


def cmd_sheet(a: argparse.Namespace) -> None:
    P = plan.load()
    with tempfile.TemporaryDirectory() as tmp:
        contact_sheet(a.movie, P, a.out, Path(tmp))


def cmd_selftest(a: argparse.Namespace) -> None:
    suite = unittest.defaultTestLoader.discover(str(HERE / "tests"), top_level_dir=str(HERE))
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    if not result.wasSuccessful():
        sys.exit(1)


def main() -> None:
    ap = argparse.ArgumentParser(description="The MyWeli Pro marketing Reel « Le trait ».")
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="compose, encode, cover, sheet and verify the Reel")
    b.add_argument("--assets", type=Path, required=True,
                   help="the main checkout's build/app-store/pro (holds preview/v2/takes and final)")
    b.add_argument("--photos", type=Path,
                   help="A1's pictures (default: build/marketing/photos beside --assets' build/app-store)")
    b.add_argument("--out", type=Path, required=True)
    b.add_argument("--work", type=Path, help="intermediate files (default: <out>/work)")
    b.add_argument("--jobs", type=int, default=4)
    b.set_defaults(fn=cmd_build)
    v = sub.add_parser("verify", help="check a written reel.mp4 (and, with --work, its build)")
    v.add_argument("movie", type=Path)
    v.add_argument("--work", type=Path)
    v.set_defaults(fn=cmd_verify)
    s = sub.add_parser("sheet", help="a contact sheet of a written reel.mp4")
    s.add_argument("movie", type=Path)
    s.add_argument("--out", type=Path, required=True)
    s.set_defaults(fn=cmd_sheet)
    t = sub.add_parser("selftest", help="the tool's own tests")
    t.set_defaults(fn=cmd_selftest)
    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
