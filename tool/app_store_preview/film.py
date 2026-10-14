"""A film made of scenes, built — `preview.py film`. README.md « Version 2 ».

    python3 tool/app_store_preview/preview.py film \
        --storyboard tool/app_store_preview/storyboard-scenes.json \
        --takes <folder the storyboard's takes are in> --out <folder>

  1  read     every take once: its frames (conform scan), each drag in the
              picture (track.py), each gesture's window (edit.locate)
  2  plan     film.json: each scene's runs, its declared dissolve, its touch
              points; the joins, the end card, the poster frame
  3  check    the plan against every rule (scenes.check — inside a scene,
              version 1's own `check_take`); refused, nothing is written
  4  export   each scene's kept ranges at 30 fps, by frame-hold
  5  masks    where each mask sits on every picture it applies to
  6  compose  the frames, in the storyboard's frame (or --frame)
  7  encode   preview.mp4 (preview-rehearsal.mp4 for a rehearsal)
  8  sheet    contact-sheet.png, decoded from the written file; poster.png
  9  verify   the written file, its poster frame and every masked region
"""

from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

import edit as editlist
import masks as masking
import preview
import scene_frames
import scenes
import swifttools
import track as tracking
import verify as verifying
from brand import die
from edit import Refusal

RESULTS = ("preview*.mp4", "verify.txt", "poster.png", "poster-decoded.png", "contact-sheet.png", "film.json",
           "cuts.txt", "masks.json", preview.RECORD)


def film_storyboard(plan: dict) -> dict:
    """What verify and the contact sheet read of a film of scenes."""
    total = scenes.places(plan)[3]
    fps = plan["fps"]
    return {"film": {"fps": fps, "width": 886, "height": 1920, "duration_s": total / fps,
                     "poster_s": plan["poster_frame"] / fps}}


def read_takes(sb: dict, out: Path) -> dict[str, scenes.Take]:
    takes: dict[str, scenes.Take] = {}
    for scene in sb["scenes"]:
        key = scenes.take_key(scene)
        if key in takes:
            continue
        path = Path(scene["take_path"])
        if not path.is_file():
            die(f"scene {scene['id']}: no such take: {path}")
        work = out / "takes" / f"take-{len(takes) + 1}"
        work.mkdir(parents=True, exist_ok=True)
        log = preview.load(Path(scene["gestures_path"]))
        scan = preview.scan_take(path, work / "scan.json")
        try:
            tracks = tracking.read_drags(path, scan, log, scenes.take_storyboard(sb, log), work)
            takes[key] = scenes.read_take(sb, key, str(path), scan, log, tracks)
        except Refusal as e:
            die(f"cannot find the gestures of scene {scene['id']} in its take {e}")
        preview.save(tracks, work / "track.json")
    sizes = {(t.scan["video"]["width"], t.scan["video"]["height"], tuple(t.log.get("device_points") or ()))
             for t in takes.values()}
    if len(sizes) != 1:
        die(f"the takes are not all the same screen: {sorted(sizes)}")
    return takes


def build(a: argparse.Namespace) -> None:
    out: Path = a.out
    if out.is_dir():
        preview.clear(out, RESULTS, a.plan)
    doc = preview.load(a.storyboard)
    try:
        sb = scenes.load(doc, a.takes or Path(a.storyboard).resolve().parent)
    except Refusal as e:
        die(f"storyboard refused {e}")
    if a.frame:
        sb["film"]["frame"] = a.frame
    given = preview.load(a.plan) if a.plan else None
    rehearsal = sb["rehearsal"]
    name = "preview-rehearsal.mp4" if rehearsal else "preview.mp4"
    fps = sb["film"]["fps"]
    out.mkdir(parents=True, exist_ok=True)

    print(f"1/9 read     {len({scenes.take_key(s) for s in sb['scenes']})} take(s) for {len(sb['scenes'])} scene(s)")
    takes = read_takes(sb, out)
    any_take = next(iter(takes.values()))
    raw_size = (any_take.scan["video"]["width"], any_take.scan["video"]["height"])
    points = tuple(any_take.log["device_points"])

    print("2/9 plan     film.json")
    try:
        plan = given if given is not None else scenes.propose(sb, takes)
    except Refusal as e:
        die(f"cannot plan the film {e}")
    if plan.get("frame") != sb["film"]["frame"]:
        die(f"the plan is for the {plan.get('frame')} frame, this build the {sb['film']['frame']} one")

    print("3/9 check    every rule, scene by scene")
    diffs: dict = {}
    for scene, ps in zip(sb["scenes"], plan.get("scenes", [])):
        take = takes[scenes.take_key(scene)]
        for k, run in enumerate(ps.get("runs", [])):
            try:
                pairs = editlist.cut_pairs({"segments": run["segments"]}, take.scan, fps)
            except Refusal as e:
                die(f"plan refused {e}")
            diffs[(scene["id"], k)] = preview.pair_diffs(Path(take.path), pairs, out)
    bands = scene_frames.band_points(sb, raw_size, points) if sb["film"]["frame"] == "full-bleed" else None
    try:
        film = scenes.check(plan, sb, takes, diffs, bands)
    except Refusal as e:
        die(f"plan refused {e}")
    preview.save(plan, out / "film.json")
    text = scenes.describe(plan, sb, takes, diffs)
    print("    " + text.replace("\n", "\n    ").rstrip())

    print("4/9 export   each scene's kept ranges at 30 fps, by frame-hold")
    data: dict[str, dict] = {}
    for scene, ps in zip(sb["scenes"], plan["scenes"]):
        take = takes[scenes.take_key(scene)]
        folder = out / "scenes" / scene["id"]
        preview.clear(folder / "src", ("src_*.png", "manifest.json"))
        segments = [{k: v for k, v in s.items() if k != "why"} for run in ps["runs"] for s in run["segments"]]
        preview.save({"fps": fps, "segments": segments}, folder / "segments.json")
        swifttools.run("conform", "export", take.path, "--segments", folder / "segments.json", "--out", folder / "src")
        manifest = preview.load(folder / "src" / "manifest.json")
        if manifest["film"] != editlist.film_sources({"segments": segments}, take.scan, fps):
            die(f"scene {scene['id']}: conform export and edit.py disagree on which source frame each film frame shows")
        data[scene["id"]] = {"manifest": manifest, "src": folder / "src", "masks": {}, "take_T": take.tm.timescale}

    print("5/9 masks    where each mask sits on every picture")
    summaries = []
    for scene in sb["scenes"]:
        d = data[scene["id"]]
        T = d["take_T"]
        shown = sorted(((int(j), v["pts"], d["src"] / v["file"]) for j, v in d["manifest"]["sources"].items()),
                       key=lambda p: p[1])
        for m, mask in enumerate(scene.get("masks") or []):
            try:
                placed, summary = masking.place(mask, shown, T, f"scene {scene['id']}, mask {m}")
            except Refusal as e:
                die(f"mask refused {e}")
            for j, on in placed.items():
                d["masks"].setdefault(j, []).append(on)
            summaries.append(summary)

    print(f"6/9 compose  the frames ({sb['film']['frame']})")
    frames_dir = out / "frames"
    preview.clear(frames_dir, ("f_*.png", "frames.json"))
    preview.clear(frames_dir / "masks", ("*.png",))
    made = scene_frames.compose_film(sb, plan, data, frames_dir, points)
    lines = ["touch points on the picture"]
    for gid, g in made["grounds"].items():
        lines.append(f"  {gid:<24} {'white' if g['ground'] == 'dark' else 'black'} point on a {g['ground']} ground at "
                     f"({g['at'][0]:g}, {g['at'][1]:g}) pt: luminance {g['under']:.2f} under the finger")
    lines.append("masks")
    for s in summaries:
        lines.append(f"  {s['what']}: {s['style']} {tuple(s['colour'])}, {'tracking the scroll' if s['tracking'] else 'fixed'}, "
                     f"reference {s['reference_s']:.3f} s, on {s['covered']} of {s['pictures']} pictures, moved "
                     f"{s['shift_px'][0]:+d} to {s['shift_px'][1]:+d} px, worst match {s['worst_match']:.1f} levels, "
                     f"detail {s['detail'][0]:.1f} -> {s['detail'][1]:.1f}")
    if not summaries:
        lines.append("  none")
    if "card" in made:
        c = made["card"]
        lines.append(f"frame: framed — the card {c['w']} x {c['h']} at ({c['x']}, {c['y']}), {c['share']:.1%} of the "
                     f"frame")
    else:
        lines.append("frame: full-bleed — caption bands (frame px): " + "; ".join(
            f"{sid} {box}" for sid, box in made["bands"].items()))
    text += "\n".join(lines) + "\n"
    (out / "cuts.txt").write_text(text, encoding="utf-8")
    print("    " + "\n".join(lines).replace("\n", "\n    "))
    regions = [{**r, "masked": f"frames/{r['masked']}", "original": f"frames/{r['original']}"} for r in made["regions"]]
    preview.save({"regions": regions}, out / "masks.json")
    print(f"    {made['frames']} frames, {made['pictures']} distinct pictures, {len(regions)} masked region(s)")

    print(f"7/9 encode   {name}")
    movie = out / name
    print("    " + swifttools.run("encode", frames_dir, "--out", movie).stdout.strip())

    print("8/9 sheet    poster.png, contact-sheet.png")
    fsb = film_storyboard(plan)
    names = preview.load(frames_dir / "frames.json")["frames"]
    shutil.copyfile(frames_dir / names[plan["poster_frame"]], out / "poster.png")
    preview.contact_sheet(movie, out / "contact-sheet.png", fsb, out / "decoded")
    # the poster may be any frame at rest, not one of the sheet's two a second
    swifttools.run("inspect", "frames", movie, "--indices", plan["poster_frame"], "--out", out / "decoded")
    shutil.copyfile(out / "decoded" / f"frame_{plan['poster_frame']:06d}.png", out / "poster-decoded.png")

    print("9/9 verify   the written file")
    record = {"version": scenes.VERSION, "file": movie.name, "bytes": movie.stat().st_size,
              "sha256": preview.sha256(movie), "rehearsal": rehearsal, "frame": sb["film"]["frame"],
              "storyboard_sha256": scenes.storyboard_sha256(doc), "poster_sha256": preview.sha256(out / "poster.png"),
              "takes": [t.scan.get("take", {}) for t in takes.values()], "seconds": film["total"] / fps}
    preview.save(record, out / preview.RECORD)
    note = (" — REHEARSAL, not the film: a storyboard marked rehearsal" if rehearsal
            else f" — the film, sha256 {record['sha256'][:16]}…")
    checks = verifying.verify(movie, fsb, out / "poster.png", {"regions": regions, "base": out})
    report, ok = verifying.report(checks, movie, note)
    (out / "verify.txt").write_text(report, encoding="utf-8")
    print("    " + report.replace("\n", "\n    ").rstrip())
    if not ok:
        sys.exit(1)


def verify_built(a: argparse.Namespace) -> None:
    """`preview.py film-verify <movie>`: the written file checked again, with
    what its build left beside it — film.json (length, poster), masks.json
    (the masked regions), poster.png — and named by the record whose sha256
    is its own."""
    movie: Path = a.movie
    if not movie.is_file():
        die(f"no such file: {movie}")
    folder = movie.parent
    for need in ("film.json", "masks.json", "poster.png"):
        if not (folder / need).is_file():
            die(f"{need} is not beside {movie.name}: this command checks a film of scenes where it was built")
    plan = preview.load(folder / "film.json")
    regions = preview.load(folder / "masks.json")["regions"]
    record = preview.built_as(movie)
    note = ""
    if record is not None:
        note = (" — REHEARSAL, not the film: a storyboard marked rehearsal" if record.get("rehearsal")
                else f" — the film, sha256 {record['sha256'][:16]}…")
    checks = verifying.verify(movie, film_storyboard(plan), folder / "poster.png", {"regions": regions, "base": folder})
    text, ok = verifying.report(checks, movie, note)
    print(text, end="")
    if record is None:
        print(f"NOT IDENTIFIED — no {preview.RECORD} beside {movie.name} names these bytes: it may be a rehearsal, a "
              f"copy or another writer's file, and is not known to be the film")
    if not ok or record is None:
        sys.exit(1)
