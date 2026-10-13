#!/usr/bin/env python3
"""Build the MyWeli Pro App Store App Preview from a raw simulator take.

« Geste après geste » — docs/design/pro-app-preview.md. A sibling of
tool/app_store_screenshots: the same frame, the same tokens, the same fonts,
with a live capture in the card. README.md has the editing rule and the
runbook for the final take.

  python3 tool/app_store_preview/preview.py build \
      --take take.mov --gestures gestures.json --out build/app-store/pro/preview/final

    scan      every frame of the take: its time, how much of the screen changed
    propose   the edit list (edit.json) and the log of every cut (cuts.txt)
    check     the edit list against the editing rule — refused if it cuts,
              holds or retimes anything between a touch-down and the end of
              the app's response
    export    the kept ranges at a constant 30 fps, by frame-hold
    compose   each film frame, 886 x 1920
    encode    preview.mp4 — H.264 High 4.0, 30 fps, a silent stereo AAC track
    verify    the written file read back and checked; non-zero exit on a miss
    sheet     contact-sheet.png (2 frames per second) and poster.png

Other commands: `scan`, `bursts`, `check`, `verify`, `sheet`, `selftest`
(see --help of each). Nothing is installed and nothing leaves this Mac.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from PIL import Image, ImageDraw  # noqa: E402

import edit as editlist  # noqa: E402
import frames as framing  # noqa: E402
import swifttools  # noqa: E402
import verify as verifying  # noqa: E402
from brand import colours, die, stills  # noqa: E402

STORYBOARD = HERE / "storyboard.json"


def load(path: Path) -> dict:
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        die(f"cannot read {path}: {e}")


def save(obj: dict, path: Path) -> None:
    path.write_text(json.dumps(obj, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


def scan_take(take: Path, out: Path) -> dict:
    """conform scan, plus the take's fingerprint so an edit list cannot be
    applied to another file."""
    swifttools.run("conform", "scan", take, "--out", out)
    scan = load(out)
    scan["take"] = {"file": take.name, "bytes": take.stat().st_size,
                    "sha256": hashlib.sha256(take.read_bytes()).hexdigest()}
    save(scan, out)
    return scan


def pair_diffs(take: Path, pairs: list[tuple[int, int]], work: Path) -> dict[tuple[int, int], dict]:
    if not pairs:
        return {}
    save({"pairs": [list(p) for p in pairs]}, work / "pairs.json")
    swifttools.run("conform", "diff", take, "--pairs", work / "pairs.json", "--out", work / "pairs-diff.json")
    return {(d["a"], d["b"]): d for d in load(work / "pairs-diff.json")["pairs"]}


def checked(edit: dict, scan: dict, log: dict, sb: dict, take: Path | None, work: Path) -> dict:
    """Run the editing rule; stop with its refusal. Returns the pair diffs."""
    try:
        editlist.check(edit, scan, log, sb)        # every rule the scan alone can settle
        if not take:
            return {}
        # …then the one that needs the pictures: both sides of every cut
        diffs = pair_diffs(take, editlist.cut_pairs(edit, scan, sb["film"]["fps"]), work)
        editlist.check(edit, scan, log, sb, diffs)
    except editlist.Refusal as e:
        die(f"edit list refused {e}")
    return diffs


def clear(folder: Path, patterns: tuple[str, ...]) -> None:
    folder.mkdir(parents=True, exist_ok=True)
    for pattern in patterns:
        for f in folder.glob(pattern):
            f.unlink()


def contact_sheet(movie: Path, out: Path, sb: dict, work: Path) -> None:
    """Two frames per second, decoded from the written file — what Apple
    receives, not what compose intended."""
    fps = sb["film"]["fps"]
    total = round(sb["film"]["duration_s"] * fps)
    poster = round(sb["film"]["poster_s"] * fps)
    indices = list(range(0, total, fps // 2))
    clear(work, ("frame_*.png",))
    swifttools.run("inspect", "frames", movie, "--indices", ",".join(map(str, indices)), "--out", work)
    c = colours()
    tw, cols, gap, label = 222, 10, 16, 30
    th = round(tw * sb["film"]["height"] / sb["film"]["width"])
    rows = (len(indices) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw + (cols + 1) * gap, rows * (th + label + gap) + gap), c["secondary"])
    draw = ImageDraw.Draw(sheet)
    font = stills.inter(18)
    for k, n in enumerate(indices):
        x = gap + (k % cols) * (tw + gap)
        y = gap + (k // cols) * (th + label + gap)
        sheet.paste(Image.open(work / f"frame_{n:06d}.png").resize((tw, th), Image.LANCZOS), (x, y))
        draw.rectangle((x, y, x + tw - 1, y + th - 1), outline=c["primary"] if n == poster else c["border"],
                       width=3 if n == poster else 1)
        draw.text((x, y + th + 5), f"{n / fps:.1f} s" + ("  — poster" if n == poster else ""),
                  font=font, fill=c["textPrimary"] if n == poster else c["textSecondary"])
    sheet.save(out, "PNG")


def cmd_build(a: argparse.Namespace) -> None:
    sb, log = load(a.storyboard), load(a.gestures)
    given = load(a.edit) if a.edit else None
    out: Path = a.out
    if not a.take.exists():
        die(f"no such take: {a.take}")
    name = "preview-rehearsal.mp4" if a.rehearsal else "preview.mp4"
    # An earlier build's results go first: if this one is refused, there is
    # no film, sheet or report left in the folder to mistake for its own.
    clear(out, ("preview*.mp4", "verify.txt", "poster.png", "poster-decoded.png", "contact-sheet.png",
                "edit.json", "cuts.txt"))

    print(f"1/8 scan     {a.take}")
    scan = scan_take(a.take, out / "scan.json")

    print("2/8 propose  the edit list")
    try:
        edit = given if given is not None else editlist.propose(scan, log, sb, rehearsal=a.rehearsal)
    except editlist.Refusal as e:
        die(f"cannot propose an edit list {e}")
    if bool(edit.get("rehearsal")) != bool(a.rehearsal):
        die("the edit list and --rehearsal disagree")

    print("3/8 check    the editing rule")
    diffs = checked(edit, scan, log, sb, a.take, out)
    save(edit, out / "edit.json")
    text = editlist.describe(edit, scan, log, sb, diffs)
    (out / "cuts.txt").write_text(text, encoding="utf-8")
    print("    " + text.replace("\n", "\n    ").rstrip())

    print("4/8 export   the kept ranges at 30 fps, by frame-hold")
    clear(out / "src", ("src_*.png", "manifest.json"))
    save({"fps": sb["film"]["fps"], "segments": [
        {k: v for k, v in s.items() if k != "why"} for s in edit["segments"]]}, out / "segments.json")
    swifttools.run("conform", "export", a.take, "--segments", out / "segments.json", "--out", out / "src")
    sources = editlist.film_sources(edit, scan, sb["film"]["fps"])

    print("5/8 compose  the frames")
    clear(out / "frames", ("f_*.png", "frames.json"))
    made = framing.compose(sb, edit, sources, out / "src", out / "frames", tuple(log["device_points"]))
    print(f"    {made['frames']} frames, {made['pictures']} distinct pictures; touch tones {made['tones']}")

    print(f"6/8 encode   {name}")
    movie = out / name
    print("    " + swifttools.run("encode", out / "frames", "--out", movie).stdout.strip())

    print("7/8 sheet    poster.png, contact-sheet.png")
    names = load(out / "frames" / "frames.json")["frames"]
    shutil.copyfile(out / "frames" / names[edit["poster_frame"]], out / "poster.png")
    contact_sheet(movie, out / "contact-sheet.png", sb, out / "decoded")
    shutil.copyfile(out / "decoded" / f"frame_{edit['poster_frame']:06d}.png", out / "poster-decoded.png")

    print("8/8 verify   the written file")
    note = ""
    if a.rehearsal:
        empty = [s["id"] for s in sb["shots"][:-1]
                 if not any(g["id"] in {t.get("id") for t in log["gestures"]} for g in s["gestures"])]
        note = f" — REHEARSAL, not the film: no footage for {', '.join(empty) or 'some gestures'}"
    text, ok = verifying.report(verifying.verify(movie, sb, out / "poster.png"), movie, note)
    (out / "verify.txt").write_text(text, encoding="utf-8")
    print("    " + text.replace("\n", "\n    ").rstrip())
    if not ok:
        sys.exit(1)


def cmd_scan(a: argparse.Namespace) -> None:
    scan_take(a.take, a.out)
    print(f"scan: {a.out}")


def cmd_bursts(a: argparse.Namespace) -> None:
    """Where the screen changes in a take — what `near_s` is read from."""
    sb, scan = load(a.storyboard), load(a.scan)
    T = scan["video"]["timescale"]
    px_per_pt = scan["video"]["width"] / a.device_points[0]
    kinds = editlist.frame_kinds(scan, px_per_pt)
    bursts = editlist.find_bursts(scan, kinds, round(sb["timing"]["rest_s"] * T))
    print(f"{len(scan['frames'])} frames: {kinds.count('change')} change, {kinds.count('quiet')} quiet, "
          f"{kinds.count('caret')} caret-only; first picture at {scan['frames'][0]['pts'] / T:.3f} s")
    print(" start s    end s  frames  where (points: x0, y0 – x1, y1)")
    for b in bursts:
        box = "" if not b.box else "{:.0f}, {:.0f} – {:.0f}, {:.0f}".format(*(v / px_per_pt for v in b.box))
        print(f"{b.start / T:8.3f} {b.end / T:8.3f} {b.frames:7d}  {box}")


def cmd_check(a: argparse.Namespace) -> None:
    sb, scan, log, edit = load(a.storyboard), load(a.scan), load(a.gestures), load(a.edit)
    work = Path(a.edit).resolve().parent
    diffs = checked(edit, scan, log, sb, a.take, work)
    print(editlist.describe(edit, scan, log, sb, diffs), end="")
    print("edit list accepted" + ("" if a.take else " (cut endpoints not compared: no --take)"))


def cmd_verify(a: argparse.Namespace) -> None:
    text, ok = verifying.report(verifying.verify(a.movie, load(a.storyboard), a.poster), a.movie)
    print(text, end="")
    if not ok:
        sys.exit(1)


def cmd_sheet(a: argparse.Namespace) -> None:
    contact_sheet(a.movie, a.out, load(a.storyboard), a.out.parent / "decoded")
    print(f"sheet: {a.out}")


def cmd_selftest(a: argparse.Namespace) -> None:
    suite = unittest.defaultTestLoader.discover(str(HERE / "tests"), pattern=a.pattern, top_level_dir=str(HERE))
    result = unittest.TextTestRunner(verbosity=2 if a.verbose else 1).run(suite)
    sys.exit(0 if result.wasSuccessful() and result.testsRun else 1)


def points(text: str) -> tuple[float, float]:
    w, _, h = text.partition("x")
    return float(w), float(h)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="command", required=True)

    def command(name: str, fn, **kw) -> argparse.ArgumentParser:
        p = sub.add_parser(name, **kw)
        p.set_defaults(fn=fn)
        p.add_argument("--storyboard", type=Path, default=STORYBOARD)
        return p

    p = command("build", cmd_build, help="take + gesture log -> preview.mp4, verified")
    p.add_argument("--take", type=Path, required=True)
    p.add_argument("--gestures", type=Path, required=True)
    p.add_argument("--out", type=Path, required=True)
    p.add_argument("--edit", type=Path, help="use this edit list instead of proposing one (it is checked)")
    p.add_argument("--rehearsal", action="store_true",
                   help="a take that does not have every storyboard gesture: the others become holds")

    p = command("scan", cmd_scan, help="every frame's time and change measure")
    p.add_argument("take", type=Path)
    p.add_argument("--out", type=Path, required=True)

    p = command("bursts", cmd_bursts, help="where the screen changes in a scanned take")
    p.add_argument("scan", type=Path)
    p.add_argument("--device-points", type=points, default=(402.0, 874.0),
                   help="the screen in points (default 402x874, iPhone 17 Pro)")

    p = command("check", cmd_check, help="check an edit list against the editing rule")
    p.add_argument("--scan", type=Path, required=True)
    p.add_argument("--gestures", type=Path, required=True)
    p.add_argument("--edit", type=Path, required=True)
    p.add_argument("--take", type=Path, help="the take, to compare the pictures on both sides of each cut")

    p = command("verify", cmd_verify, help="check a written file; non-zero exit on any miss")
    p.add_argument("movie", type=Path)
    p.add_argument("--poster", type=Path, help="the composed poster PNG to compare the decoded frame with")

    p = command("sheet", cmd_sheet, help="a contact sheet of a written file, 2 frames per second")
    p.add_argument("movie", type=Path)
    p.add_argument("--out", type=Path, required=True)

    p = command("selftest", cmd_selftest, help="the tests, without the simulator")
    p.add_argument("--pattern", default="test_*.py")
    p.add_argument("-v", "--verbose", action="store_true")

    a = ap.parse_args()
    a.fn(a)


if __name__ == "__main__":
    main()
