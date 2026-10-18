"""Check the WRITTEN Reel, and the plan it was drawn from.
Design: docs/design/pro-marketing-reel.md §6.

Nothing here trusts the encoder's settings. The file is read back by three
readers that must agree — the App Preview's own box parser (`mp4.py`),
AVFoundation (`swift/Inspect.swift`, the only one that decodes) and
`avmediainfo` — reused from tool/app_store_preview, not copied.

  the file    MPEG-4; one video and one sound track; H.264 High Profile
              Level 4.1; exactly 1080 x 1920 everywhere; 8-bit 4:2:0
              (yuv420p), progressive, square pixels, upright; every frame
              exactly 1/30 s (constant frame rate); 900 frames; 30.000 s;
              no reordering; the bit rate (and Level 4.1's 62.5 Mbit in any
              second); AAC-LC, stereo, 48 kHz, the whole film long, decoding
              to digital silence.
  the plan    every word, logo and shape the frames place lies inside the
              storyboard's safe zone (x 65–1015, y 269–1248) on EVERY frame,
              and none reaches into the right-hand rail; the cover frame and
              the end card inside the 4:5 feed crop; no character drawn as
              a missing glyph; every timed line on screen for its reading
              time, with no exception (R2); the brand on screen for at most
              a quarter of the film; no two of S4's bubbles ever overlap; no
              card moves more than 410 px from one frame to the next; no
              card enters S2's lockup's clear space (or the tagline's line)
              while the lockup shows (R2); A1's pictures enlarged no more
              than their fill and push-in need.
  the build   (with the work folder) take1b's and take5b's exported ranges
              against each take's map; S5's phone row white on every
              composed frame where it shows — through the page's own scroll
              (A2) as at the camera stops — and on the decoded file; key
              frames decoded against the frames that were composed; the
              white words over A1's pictures at 4.5:1 or more against what
              lies under them.

`verify()` returns the checks; `reel.py verify` exits non-zero when any
fails.
"""

from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

import reel_draw as rd
import reel_footage as rf
import reel_photo as rp
import reel_plan as plan
import reel_scenes as rs
import swifttools  # noqa: E402  (tool/app_store_preview)
import mp4         # noqa: E402  (tool/app_store_preview)


def _load_app_store_verify():
    """The App Preview's checker, under another name: this tool has its own
    `verify`, and its reader of `avmediainfo`, its `Check` and its report are
    reused as they are."""
    spec = importlib.util.spec_from_file_location("app_store_verify", plan.PREVIEW / "verify.py")
    module = importlib.util.module_from_spec(spec)
    sys.modules["app_store_verify"] = module
    spec.loader.exec_module(module)
    return module


asv = _load_app_store_verify()
Check = asv.Check
report = asv.report

PROFILE_HIGH, LEVEL_4_1 = 100, 41
AUDIO_RATE, AUDIO_CHANNELS, AAC_LC = 48000, 2, 2
VIDEO_BPS = (500_000, 12_000_000)       # the master: ~8–12 Mbit/s, at most 12; under 0.5 is a broken encode
PEAK_BPS = 62_500_000                   # High Profile Level 4.1: MaxBR 50 000 x 1.25 kbit/s (Table A-1)
MAX_BYTES = 100 * 1000 * 1000           # a 30-s Reel; Instagram takes up to 4 GB, WhatsApp Status 16 MB re-encoded
# A decoded key frame against the composed one. 48 dB is one grey level of
# error, root mean square — the App Preview's poster line. Measured on the
# film (2026-10-18): 54.6 dB at the worst key frame with the master's
# quantiser ceiling of 10; 48.8 at a ceiling of 20.
KEY_MIN_PSNR = 48.0
# A key frame whose ground is one of A1's photographs: their grain is what an
# encoder never reproduces exactly — 47.8 dB at the master's ceiling of 12,
# and only a ceiling of 10 reaches 48, at 65 Mbit in a second, over Level
# 4.1. 47 dB is 1.1 grey levels root mean square: still invisible.
KEY_MIN_PSNR_PICTURE = 47.0
MASK_MIN_LEVEL = 245                    # S5's masked row, decoded: white, give or take the encode
WORDS_MIN_CONTRAST = 4.5                # white words over a picture: WCAG AA for any size


# ---- the file -------------------------------------------------------------------------

def file_checks(path: Path, P: plan.Plan) -> list[Check]:
    checks: list[Check] = []

    def add(name: str, ok: bool, seen: str) -> None:
        checks.append(Check(name, bool(ok), seen))

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
    info = asv._avmediainfo(path)

    bv = [t for t in box["tracks"] if t.get("handler") == "vide"]
    ba = [t for t in box["tracks"] if t.get("handler") == "soun"]
    av_v = [t for t in av["tracks"] if t["type"] == "vide"]
    av_a = [t for t in av["tracks"] if t["type"] == "soun"]
    iv = [t for t in info["tracks"] if t["kind"] == "Video"]
    ia = [t for t in info["tracks"] if t["kind"] == "Sound"]

    major = (box["ftyp"] or {}).get("major")
    add("container", path.suffix == ".mp4" and major in ("mp42", "isom", "mp41"),
        f"{path.suffix or '(no extension)'}, brand {major!r}")
    add("file size", box["file_bytes"] < MAX_BYTES, f"{box['file_bytes']:,} bytes (limit {MAX_BYTES / 1e6:g} MB)")
    kinds = sorted(t.get("handler", "?") for t in box["tracks"])
    add("tracks", kinds == ["soun", "vide"] and len(av["tracks"]) == 2 and info["track_count"] == 2,
        f"boxes {kinds}, AVFoundation {len(av['tracks'])}, avmediainfo {info['track_count']} "
        f"(one video and one sound, nothing else)")
    add("avmediainfo reads it", info["ok"], "0 errors" if info["ok"] else "errors, or it could not open the file")

    want = P.frames
    if len(bv) != 1 or len(av_v) != 1 or len(iv) != 1:
        add("video track", False, f"{len(bv)} in the boxes, {len(av_v)} per AVFoundation, {len(iv)} per avmediainfo")
    else:
        v, a_v, i_v = bv[0], av_v[0], iv[0]
        entry = v["entries"][0] if len(v["entries"]) == 1 else {}
        sps = entry.get("sps", {})
        avcc = entry.get("avcC", {})
        add("video enabled", v.get("enabled") and a_v["enabled"] and i_v.get("enabled"),
            f"boxes {v.get('enabled')}, AVFoundation {a_v['enabled']}, avmediainfo {i_v.get('enabled')}")
        add("codec H.264", entry.get("format") == "avc1" and a_v.get("codec") == "avc1",
            f"{entry.get('format')!r} (H.264 is `avc1`), {len(v['entries'])} sample description(s)")
        add("profile and level",
            sps.get("profile_idc") == PROFILE_HIGH and sps.get("level_idc") == LEVEL_4_1
            and avcc.get("profile") == PROFILE_HIGH and avcc.get("level") == LEVEL_4_1,
            f"SPS profile_idc {sps.get('profile_idc')}, level_idc {sps.get('level_idc')}; "
            f"avcC {avcc.get('profile')}/{avcc.get('level')} (High is 100, Level 4.1 is 41)")
        sizes = {
            "SPS": (sps.get("width"), sps.get("height")),
            "stsd": (entry.get("width"), entry.get("height")),
            "tkhd": (v.get("tkhd_width"), v.get("tkhd_height")),
            "AVFoundation": tuple(a_v.get("natural_size", (None, None))),
            "avmediainfo": tuple(i_v.get("dimensions", (None, None))),
            "avmediainfo presentation": tuple(i_v.get("presentation", (None, None))),
        }
        add("size 1080 x 1920", all(s == P.size for s in sizes.values()),
            ", ".join(f"{k} {s[0]} x {s[1]}" for k, s in sizes.items()).replace(".0", ""))
        identity = [65536, 0, 0, 0, 65536, 0, 0, 0, 1073741824]
        square = entry.get("pasp") in (None, [1, 1]) and sps.get("sar") in (None, [1, 1])
        add("upright, square pixels",
            v.get("matrix") == identity and a_v.get("transform") == [1, 0, 0, 1, 0, 0] and square
            and entry.get("clap") is None,
            f"matrix {'identity' if v.get('matrix') == identity else v.get('matrix')}, "
            f"pasp {entry.get('pasp')}, SAR {sps.get('sar')}")
        fiel = entry.get("fiel")
        add("progressive", sps.get("frame_mbs_only_flag") == 1 and (fiel is None or fiel[0] == 1),
            f"SPS frame_mbs_only_flag {sps.get('frame_mbs_only_flag')}, fiel {fiel}")
        add("yuv420p (8-bit 4:2:0, no alpha)",
            entry.get("depth") == 24 and sps.get("chroma_format_idc") == 1
            and sps.get("bit_depth_luma") == 8 and sps.get("bit_depth_chroma") == 8
            and not a_v.get("extensions", {}).get("ContainsAlphaChannel"),
            f"depth {entry.get('depth')}, chroma_format_idc {sps.get('chroma_format_idc')} (4:2:0 is 1), "
            f"{sps.get('bit_depth_luma')}-bit luma, {sps.get('bit_depth_chroma')}-bit chroma")

        scale = v.get("timescale", 0)
        fps = P.fps
        step = scale // fps if scale and scale % fps == 0 else None
        stts = v.get("stts", [])
        count = sum(n for n, _ in stts)
        deltas = sorted({d for _, d in stts})
        samples = a_v.get("samples", {})
        av_durations = samples.get("durations", {})
        pts = samples.get("pts", [])
        on_grid = step is not None and pts == [i * step for i in range(len(pts))]
        add("constant 30 fps",
            step is not None and deltas == [step] and list(av_durations) == [str(step)] and on_grid
            and i_v.get("min_duration") == [step, scale] and i_v.get("fps") == float(fps)
            and abs(a_v.get("nominal_fps", 0) - fps) < 1e-6,
            f"timescale {scale}; every sample {deltas} ticks in the boxes, per AVFoundation "
            f"{dict(sorted(av_durations.items()))}; times {'on' if on_grid else 'OFF'} the 1/30 s grid; "
            f"nominal {a_v.get('nominal_fps')} (AVFoundation), {i_v.get('fps')} (avmediainfo)")
        add("no frame reordering",
            not v.get("ctts") and samples.get("decode_order_is_presentation_order") is True
            and not a_v.get("requires_frame_reordering") and not i_v.get("reordering"),
            f"ctts offsets {v.get('ctts')}, AVFoundation reordering {a_v.get('requires_frame_reordering')}")
        add(f"{want} frames", count == want and samples.get("count") == want,
            f"boxes {count}, AVFoundation {samples.get('count')}; the storyboard's {want}")
        seconds = v["duration"] / scale if scale else 0
        movie = box["movie"]
        edits = v.get("edits")
        plain = edits is None or (len(edits) == 1 and edits[0]["media_time"] == 0 and edits[0]["rate"] == 1.0
                                  and edits[0]["duration"] * scale == v["duration"] * movie["timescale"])
        add(f"duration {P.duration:.3f} s",
            seconds == P.duration and plain and movie["duration"] / movie["timescale"] == P.duration
            and av["duration"][0] / av["duration"][1] == P.duration,
            f"video {seconds:.4f} s, movie {movie['duration'] / movie['timescale']:.4f} s, AVFoundation "
            f"{av['duration'][0] / av['duration'][1]:.4f} s; edit list {'plain' if plain else edits}")
        sizes_ = v.get("sizes", [])
        bps = sum(sizes_) * 8 / seconds if seconds else 0
        peak = max((sum(sizes_[i:i + fps]) * 8 for i in range(0, max(1, len(sizes_) - fps + 1))), default=0)
        add("video bit rate", VIDEO_BPS[0] <= bps <= VIDEO_BPS[1] and peak <= PEAK_BPS,
            f"{bps / 1e6:.2f} Mbit/s on average (accepted {VIDEO_BPS[0] / 1e6:g}–{VIDEO_BPS[1] / 1e6:g}), "
            f"busiest second {peak / 1e6:.2f} Mbit (Level 4.1 allows {PEAK_BPS / 1e6:g})")

    if len(ba) != 1 or len(av_a) != 1 or len(ia) != 1:
        add("sound track", False, f"{len(ba)} in the boxes, {len(av_a)} per AVFoundation, {len(ia)} per "
                                  f"avmediainfo — exactly one silent track is required")
    else:
        s, a_s, i_s = ba[0], av_a[0], ia[0]
        entry = s["entries"][0] if len(s["entries"]) == 1 else {}
        esds = entry.get("esds", {})
        add("sound enabled", s.get("enabled") and a_s["enabled"] and i_s.get("enabled"),
            f"boxes {s.get('enabled')}, AVFoundation {a_s['enabled']}, avmediainfo {i_s.get('enabled')}")
        add("sound is AAC-LC stereo 48 kHz",
            entry.get("format") == "mp4a" and esds.get("audio_object_type") == AAC_LC
            and a_s.get("format_id") == "aac " and esds.get("sample_rate") == AUDIO_RATE
            and esds.get("channel_configuration") == AUDIO_CHANNELS and a_s.get("sample_rate") == AUDIO_RATE
            and a_s.get("channels") == AUDIO_CHANNELS and i_s.get("sample_rate") == AUDIO_RATE
            and i_s.get("channels") == AUDIO_CHANNELS,
            f"{entry.get('format')!r}, audio object type {esds.get('audio_object_type')} (AAC-LC is 2), "
            f"{esds.get('sample_rate')} Hz / {esds.get('channel_configuration')} ch; AVFoundation "
            f"{a_s.get('sample_rate')} / {a_s.get('channels')}; avmediainfo {i_s.get('sample_rate')} / {i_s.get('channels')}")
        seconds = (bv[0]["duration"] / bv[0]["timescale"]) if len(bv) == 1 and bv[0].get("timescale") else 0
        decoded = a_s.get("decoded", {})
        range_ = a_s.get("time_range", [[0, 1], [0, 1]])
        heard = range_[1][0] / range_[1][1]
        add("sound runs the whole film",
            seconds > 0 and heard == seconds and range_[0][0] == 0
            and decoded.get("frames") == round(seconds * AUDIO_RATE),
            f"{heard:.4f} s from {range_[0][0] / range_[0][1]:g} s, {decoded.get('frames')} samples decoded "
            f"(the video's {seconds:.4f} s is {round(seconds * AUDIO_RATE)})")
        add("sound is silent", decoded.get("peak") == 0,
            f"loudest decoded sample {decoded.get('peak')} of 32767 (digital silence is 0)")
    return checks


# ---- the plan ------------------------------------------------------------------------

def inside(box, x0, x1, y0, y1) -> bool:
    return box[0] >= x0 and box[2] <= x1 and box[1] >= y0 and box[3] <= y1


def plan_checks(P: plan.Plan, layout: dict[int, list] | None = None) -> list[Check]:
    """`layout`: the boxes of every frame, as `layout_of` returns them (laid
    out here when not given)."""
    checks: list[Check] = []

    def add(name: str, ok: bool, seen: str) -> None:
        checks.append(Check(name, bool(ok), seen))

    comp = rs.Composer(P)
    if layout is None:
        layout = layout_of(comp, P)
    x0, x1, y0, y1 = P.safe
    rail_x, rail_y = P.rail
    outside, in_rail, worst = [], [], None
    margin = None
    for n, boxes in layout.items():
        for b in boxes:
            if b.kind in rd.NOT_WORDS:
                continue
            for which, bb in (("ink", b.ink), ("line", b.line)):
                if bb is None:
                    continue
                if not inside(bb, x0, x1, y0, y1):
                    outside.append((n, b.label, which, tuple(round(v) for v in bb)))
                if bb[2] > rail_x and bb[3] > rail_y:
                    in_rail.append((n, b.label, which, tuple(round(v) for v in bb)))
                m = min(bb[0] - x0, x1 - bb[2], bb[1] - y0, y1 - bb[3])
                if margin is None or m < margin:
                    margin, worst = m, (n, b.label, which)
    words = sum(1 for boxes in layout.values() for b in boxes if b.kind == "text")
    add("text inside the safe zone",
        not outside and words > 0,
        (f"{len(layout)} frames laid out, {words} placed words, logos and shapes, every ink and line box "
         f"inside x {x0}–{x1}, y {y0}–{y1}; tightest: {worst[1]} ({worst[2]}) at frame {worst[0]}, "
         f"{margin:.1f} px in" if not outside and worst else
         f"{len(outside)} box(es) outside x {x0}–{x1}, y {y0}–{y1}, first: frame {outside[0][0]} "
         f"{outside[0][1]} ({outside[0][2]}) {outside[0][3]}" if outside else "no words laid out"))
    add("clear of the right-hand rail", not in_rail,
        f"nothing in x > {rail_x}, y > {rail_y}" if not in_rail else
        f"{len(in_rail)} box(es) reach the rail, first: frame {in_rail[0][0]} {in_rail[0][1]} {in_rail[0][3]}")

    crop = []
    for n in (P.cover_frame, P.frames - 1):
        for b in layout[n]:
            if b.kind not in rd.NOT_WORDS and not inside(b.ink, 0, P.width, P.crop_feed[0], P.crop_feed[1]):
                crop.append((n, b.label))
    add("cover and end card in the 4:5 crop", not crop,
        f"frames {P.cover_frame} and {P.frames - 1}: everything inside y {P.crop_feed[0]}–{P.crop_feed[1]} "
        f"(the 3:4 grid crop, y {P.crop_grid[0]}–{P.crop_grid[1]}, is wider)" if not crop else
        f"outside the 4:5 crop: {crop[:3]}")

    # glyphs: every word with the font it is drawn in
    import frames as app_frames          # tool/app_store_preview/frames.py: check_glyphs
    seen = set()
    missing = []
    for boxes in layout.values():
        for b in boxes:
            if b.kind == "text":
                # a pop draws the face at a fractional size for a few frames;
                # the glyph set is the face's, checked at a whole size
                family, px, *rest = b.font
                seen.add((b.text, (family, round(px), *rest)))
    for text, spec in seen:
        try:
            app_frames.check_glyphs(text, rd.font_of(spec), "x")
        except SystemExit:
            missing.append(text)
    add("no missing glyph", not missing,
        f"{len(seen)} word/font pairs drawn, each character has its glyph" if not missing else
        f"drawn as a missing glyph: {missing}")

    rows = comp.reading_windows()
    short = [r for r in rows if r["on"] + 1e-9 < r["need"]]
    add("reading time", not short,
        "; ".join(f"{r['label']} {r['on']:.2f} s of {r['need']:.2f}" for r in rows) +
        " — every line, no exception" if not short else
        "too short: " + "; ".join(f"{r['label']} {r['on']:.2f} s, needs {r['need']:.2f}" for r in short))

    brand_frames = sum(1 for boxes in layout.values() if any(b.kind == "logo" for b in boxes))
    share = brand_frames / P.frames
    add("brand time", share <= 0.25,
        f"the logo is on screen {brand_frames / P.fps:.2f} s of {P.duration:g} ({share:.1%}; at most 25 %)")

    checks += motion_checks(P, layout)
    return checks


def _overlap(a, b) -> bool:
    return min(a[2], b[2]) > max(a[0], b[0]) and min(a[3], b[3]) > max(a[1], b[1])


def lockup_clear_space(boxes: list) -> list[tuple[str, tuple]]:
    """The boxes S2's lockup keeps clear while it shows: the mark and the
    « MyWeli Pro » unit with half the mark's height all round (the brand's
    clear space), and the tagline's line."""
    logo = [b for b in boxes if b.kind == "logo" and b.label.startswith("S2 ") and b.alpha > 0]
    out = []
    if logo:
        clear = plan.S2["mark_h"] / 2
        out.append(("the lockup's clear space", (min(b.ink[0] for b in logo) - clear, min(b.ink[1] for b in logo) - clear,
                                                 max(b.ink[2] for b in logo) + clear, max(b.ink[3] for b in logo) + clear)))
    out += [("the tagline's line", b.line or b.ink) for b in boxes
            if b.kind == "text" and b.label == "S2 tagline" and b.alpha > 0]
    return out


def motion_checks(P: plan.Plan, layout: dict[int, list]) -> list[Check]:
    """What R1, A1 and R2 hold the frames to: S4's column, the cards' speed,
    S2's clear space, the pictures' enlargement."""
    checks: list[Check] = []

    def add(name: str, ok: bool, seen: str) -> None:
        checks.append(Check(name, bool(ok), seen))

    # no two of S4's bubbles ever overlap — their whole boxes, clipped or not
    clashes, frames_seen, pairs = [], 0, 0
    for n, boxes in sorted(layout.items()):
        bubbles = [b for b in boxes if b.kind == "shape" and b.label.startswith("S4 bubble")]
        if len(bubbles) > 1:
            frames_seen += 1
        for i, a in enumerate(bubbles):
            for b in bubbles[i + 1:]:
                pairs += 1
                if _overlap(a.full or a.ink, b.full or b.ink):
                    clashes.append((n, a.label, b.label))
    add("S4 bubbles never overlap", frames_seen > 0 and not clashes,
        f"{pairs} bubble pairs on {frames_seen} frames, none intersecting (the column moves as one)"
        if not clashes else f"{len(clashes)} overlapping pair(s), first at frame {clashes[0][0]}: "
                            f"{clashes[0][1]} and {clashes[0][2]}")

    # a card's content never moves more than ANSWER["max_step"] px between frames
    limit = plan.ANSWER["max_step"]
    worst: dict[str, tuple[float, int]] = {}
    last: dict[str, tuple[int, float]] = {}
    for n, boxes in sorted(layout.items()):
        for b in boxes:
            if b.kind != "card":
                continue
            top = (b.full or b.ink)[1]
            if b.label in last and last[b.label][0] == n - 1:
                step = abs(top - last[b.label][1])
                if step > worst.get(b.label, (-1, 0))[0]:
                    worst[b.label] = (step, n)
            last[b.label] = (n, top)
    fast = {k: v for k, v in worst.items() if v[0] > limit}
    add("cards move at most 410 px a frame", worst and not fast,
        "; ".join(f"{k} {v[0]:.1f} px (frame {v[1]})" for k, v in sorted(worst.items())) +
        f" — the most a card moves between two frames (limit {limit})" if not fast else
        "too fast: " + "; ".join(f"{k} {v[0]:.1f} px at frame {v[1]}" for k, v in sorted(fast.items())))

    # R2: no card box enters S2's lockup's clear space (nor the tagline's
    # line) on any frame where the lockup still shows
    shared, entered, nearest = 0, [], None
    for n, boxes in sorted(layout.items()):
        zones = lockup_clear_space(boxes)
        cards = [b for b in boxes if b.kind == "card"]
        if not zones or not cards:
            continue
        shared += 1
        for c in cards:
            box = c.full or c.ink
            for name, z in zones:
                if _overlap(box, z):
                    entered.append((n, c.label, name, round(box[1]), round(z[3])))
                gap = box[1] - z[3]
                if nearest is None or gap < nearest[0]:
                    nearest = (gap, n, name)
    add("S2's clear space kept", shared > 0 and not entered,
        f"{shared} frames show the lockup and a card together; the card stays below its clear space and the "
        f"tagline (closest: {nearest[0]:.0f} px below {nearest[2]}, frame {nearest[1]})" if shared and not entered else
        (f"{len(entered)} frame(s) with a card in it, first: frame {entered[0][0]} {entered[0][1]} top "
         f"y {entered[0][3]} inside {entered[0][2]} (to y {entered[0][4]})" if entered else
         "no frame shows the lockup with a card: nothing checked"))

    # A1's pictures: never smaller than their fill, never larger than fill x push-in
    seen: dict[str, list[float]] = {}
    bad = []
    for n, boxes in sorted(layout.items()):
        for b in boxes:
            if b.kind != "photo":
                continue
            d = b.data
            scale, base = d["scale"], d["base"]
            x0, y0, x1, y1 = b.full or b.ink
            fills = x0 <= 1e-6 and x1 >= P.width - 1e-6 and (d["fill"] == "width" or (y0 <= 1e-6 and y1 >= P.height - 1e-6))
            if scale < base - 1e-9 or scale > base * d["push"] + 1e-9 or not fills:
                bad.append((n, b.label, round(scale, 4)))
            seen.setdefault(b.label, [base, base * d["push"], 0.0])
            seen[b.label][2] = max(seen[b.label][2], scale)
    top_scale = max((v[2] for v in seen.values()), default=0)
    add("pictures enlarged only as needed", seen and not bad,
        "; ".join(f"{k}: base {v[0]:.4f} (the least that fills), at most {v[2]:.4f} = {v[2] / v[0]:.3f} x base "
                  f"(push-in limit {v[1] / v[0]:.2f})" for k, v in sorted(seen.items())) +
        f"; the largest scale of any picture: {top_scale:.4f}" if not bad else
        f"{len(bad)} frame(s) off: first {bad[0]}")
    return checks


def layout_of(comp: rs.Composer, P: plan.Plan) -> dict[int, list]:
    return {n: comp.frame(n, dry=True).boxes for n in range(P.frames)}


# ---- the build -----------------------------------------------------------------------

def mask_rows(box, size) -> tuple[int, int, int, int] | None:
    """The part of S5's mask box that the card shows whole (below the band's
    fade), shrunk by 3 px for the encode's own edge."""
    x0, y0, x1, y1 = box
    top = max(y0, plan.ANSWER["band_clear"]) + 3
    bottom = min(y1, size[1]) - 3
    if bottom <= top:
        return None
    return (round(x0) + 3, round(top), round(x1) - 3, round(bottom))


def build_checks(path: Path, P: plan.Plan, work: Path, layout: dict[int, list] | None = None,
                 key_frames: list[int] | None = None) -> list[Check]:
    checks: list[Check] = []

    def add(name: str, ok: bool, seen: str) -> None:
        checks.append(Check(name, bool(ok), seen))

    m1 = json.loads((work / "take1b/manifest.json").read_text(encoding="utf-8"))
    m5 = json.loads((work / "take5b/manifest.json").read_text(encoding="utf-8"))
    faults = rf.check_take_map(m1) + [f"take5b: {f}" for f in rf.check_take_map(m5, rf.TAKE5B_SEGMENTS)]
    add("take map (LIVE and HOLD)", not faults,
        f"{len(m1['film'])} exported pictures of take1b in {len(rf.TAKE1B_SEGMENTS)} ranges and {len(m5['film'])} "
        f"of take5b in {len(rf.TAKE5B_SEGMENTS)}, each as its take presents it at its instant"
        if not faults else "; ".join(faults))

    if layout is None:
        layout = layout_of(rs.Composer(P, rf.Footage(work)), P)
    manifest = json.loads((work / "frames/frames.json").read_text(encoding="utf-8"))
    names = manifest["frames"]
    shown = {}
    for n, boxes in layout.items():
        for b in boxes:
            if b.kind == "mask" and b.alpha > 0:
                r = mask_rows(b.ink, P.size)
                if r:
                    shown[n] = r
    bad = []
    for n, r in shown.items():
        a = np.asarray(Image.open(work / "frames" / names[n]).convert("L"))[r[1]:r[3], r[0]:r[2]]
        if a.min() < 250:
            bad.append((n, int(a.min())))
    live = plan.S5["live"]
    in_drag = sum(1 for n in shown if live[0] <= n <= live[0] + (live[2] - live[1]) // rf.FILM_TICKS)
    add("S5 phone row hidden (composed)", shown and not bad,
        f"{len(shown)} composed frames show the masked row ({in_drag} of them in the page's own scroll); "
        f"every pixel of it is white (>= 250)" if not bad else
        f"{len(bad)} frame(s) with ink in the masked row, first {bad[0]}")

    sample = sorted(shown)[::max(1, len(shown) // 12)] + ([max(shown)] if shown else [])
    want = sorted(set(sample + (key_frames or [])))
    with tempfile.TemporaryDirectory() as tmp:
        r = swifttools.run("inspect", "frames", path, "--indices", ",".join(map(str, want)), "--out", tmp,
                           check=False)
        if r.returncode != 0:
            add("decoded frames", False, r.stderr.strip())
            return checks
        dark = []
        for n in sample:
            box = shown[n]
            a = np.asarray(Image.open(Path(tmp) / f"frame_{n:06d}.png").convert("L"))[box[1]:box[3], box[0]:box[2]]
            if a.min() < MASK_MIN_LEVEL:
                dark.append((n, int(a.min())))
        add("S5 phone row hidden (decoded)", sample and not dark,
            f"{len(sample)} decoded frames across the scroll, the stop and the camera move: the row is white "
            f"(darkest {MASK_MIN_LEVEL}+)" if not dark else f"ink in the decoded row: {dark[:3]}")
        worst = {}
        for n in key_frames or []:
            psnr, block = asv.compare_images(Path(tmp) / f"frame_{n:06d}.png", work / "frames" / names[n])
            kind = "picture" if any(b.kind == "photo" and b.alpha >= 0.5 for b in layout[n]) else "graphic"
            if kind not in worst or psnr < worst[kind][1]:
                worst[kind] = (n, psnr, block)
        if key_frames:
            floors = {"graphic": KEY_MIN_PSNR, "picture": KEY_MIN_PSNR_PICTURE}
            add("decoded = composed", all(v[1] >= floors[k] for k, v in worst.items()),
                f"{len(key_frames)} key frames decoded from the file against the composed PNGs: " +
                "; ".join(f"worst {k} frame {v[0]} at {v[1]:.1f} dB (at least {floors[k]:g}), its worst 16 x 16 "
                          f"block {v[2]:.1f} levels off" for k, v in sorted(worst.items())))
    checks += words_over_pictures(P, work, layout)
    return checks


def _luminance(rgb: np.ndarray) -> np.ndarray:
    c = rgb / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return lin @ np.array([0.2126, 0.7152, 0.0722])


def words_over_pictures(P: plan.Plan, work: Path, layout: dict[int, list]) -> list[Check]:
    """The white words over A1's pictures, against the picture and its
    gradient as they lie under each line's ink box (words left out), at
    every frame where the words are whole: the 95th percentile of the
    ground's luminance — the bright 5 % (a bottle, the wall) — must still
    give 4.5:1."""
    comp = rs.Composer(P, rf.Footage(work))
    worst = {}
    for n, boxes in sorted(layout.items()):
        lines = [b for b in boxes if b.kind == "text" and b.alpha >= 0.999
                 and (b.label.startswith("S1 headline") or b.label.startswith("S7b caption"))]
        if not lines or n % 3:          # every third frame: the ground moves slowly
            continue
        key = "S1" if lines[0].label.startswith("S1") else "S7b"
        spec = plan.S1 if key == "S1" else plan.S7B
        ground = rp.render(comp.fx.photo(spec["photo"]), rp.placement(spec, n / P.fps, P.size), spec, P.size)
        for b in lines:
            x0, y0, x1, y1 = (int(round(v)) for v in b.ink)
            lum = _luminance(ground[max(0, y0):y1, max(0, x0):x1].reshape(-1, 3))
            bright = float(np.percentile(lum, 95))
            ratio = 1.05 / (bright + 0.05)
            label = b.label.rsplit(" line", 1)[0]
            if label not in worst or ratio < worst[label][0]:
                worst[label] = (ratio, n, b.label)
    low = {k: v for k, v in worst.items() if v[0] < WORDS_MIN_CONTRAST}
    return [Check("white words over the pictures", bool(worst) and not low,
                  "; ".join(f"{k}: at least {v[0]:.1f}:1 (worst {v[2]}, frame {v[1]})" for k, v in sorted(worst.items()))
                  + f" — white against the brightest 5 % of what lies under each line (at least {WORDS_MIN_CONTRAST}:1)"
                  if not low else "too faint: " + "; ".join(f"{k} {v[0]:.1f}:1 at frame {v[1]}" for k, v in low.items()))]


def verify(path: Path, P: plan.Plan, work: Path | None = None, key_frames: list[int] | None = None) -> list[Check]:
    checks = file_checks(path, P)
    # with the work folder, the layout knows where each take5b picture's row
    # was painted out (the masks move with the page's own scroll)
    comp = rs.Composer(P, rf.Footage(work)) if work is not None else rs.Composer(P)
    layout = layout_of(comp, P)
    checks += plan_checks(P, layout)
    if work is not None:
        checks += build_checks(path, P, work, layout, key_frames)
    else:
        checks.append(Check("the build", True, "NOT checked — no --work folder given", skipped=True))
    return checks
