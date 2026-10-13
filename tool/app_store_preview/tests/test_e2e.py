"""End to end, without the simulator.

A synthetic take is written with the recorder's shape — .mov, H.264, frames
only when the picture changes, no sound — from pictures drawn here, so the
time of every change is known before the tool looks. The whole chain then
runs on it once: scan, propose, check, export, compose, encode, sheet,
verify. The tests read what it left.
"""

from __future__ import annotations

import contextlib
import copy
import hashlib
import io
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import edit
import mp4
import preview
import swifttools
import verify
from tests.support import TOOL
from tests.test_edit import LOG, SB

RAW = (1206, 2622)
PX = 3            # raw pixels per point
SCROLL_PX = 15    # the synthetic drag moves the list this far a frame: 5 pt
T = 600
WORK: Path
TAKE: Path
TAKE_PTS: list[int]
FILM: Path        # the build's output folder

# tests/test_edit.py's gesture log, the tap moved onto a clear part of its row
E2E_LOG = copy.deepcopy(LOG)
E2E_LOG["gestures"][0]["at"] = [100, 260]


def rest_screen() -> Image.Image:
    """Something like a screen: a light ground, a title bar, rows of "text"."""
    rng = np.random.default_rng(11)
    im = Image.new("RGB", RAW, (246, 247, 249))
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, RAW[0], 330), fill=(250, 250, 250))
    for row in range(8):
        y = 420 + row * 250
        d.rounded_rectangle((60, y, RAW[0] - 60, y + 200), radius=24, fill=(255, 255, 255),
                            outline=(208, 208, 208), width=3)
        for word in range(6):
            x = 110 + word * 150
            d.rectangle((x, y + 60, x + int(rng.integers(60, 130)), y + 84), fill=(26, 26, 26))
            d.rectangle((x, y + 120, x + int(rng.integers(40, 110)), y + 136), fill=(110, 110, 110))
    return im


def synthetic_take(folder: Path) -> tuple[Path, list[int]]:
    """The take of tests/test_edit.py, as pictures:
       0.0 s   the screen at rest; 0.5 s the same picture again
       3.0 s   the tapped row turns green, in 11 frames (3.000–3.167 s)
       6.0 s   a bar appears at the bottom on its own (6.000–6.083 s)
       7–8 s   a caret blinks on, off, on — on the bar that has just appeared
      10.0 s   the list follows the finger up, 5 pt a frame for a second (10.000–11.000 s):
               300 pt in all, the length of the logged drag, and one frame more on its own
      11.7 s   the last picture again, and again at 15.48 s"""
    folder.mkdir(parents=True, exist_ok=True)
    frames: list[dict] = []

    def put(pts: int, im: Image.Image, name: str) -> None:
        path = folder / f"{name}.png"
        if not path.exists():
            im.save(path)
        frames.append({"pts": pts, "file": path.name})

    base = rest_screen()
    put(0, base, "rest")
    put(300, base, "rest")
    cur = base
    for k in range(11):                                  # the tap's answer, around (100, 260) pt
        cur = base.copy()
        ImageDraw.Draw(cur).rounded_rectangle((60, 670, 60 + 100 * (k + 1), 870), radius=24, fill=(45, 80, 22))
        put(1800 + 10 * k, cur, f"tap{k}")
    tapped = cur
    for k in range(6):                                   # the app on its own
        cur = tapped.copy()
        ImageDraw.Draw(cur).rectangle((90, 2500 - 30 * (k + 1), RAW[0] - 90, 2500), fill=(26, 26, 26))
        put(3600 + 10 * k, cur, f"bar{k}")
    barred = cur
    caret = barred.copy()
    ImageDraw.Draw(caret).rectangle((1000, 2380, 1005, 2439), fill=(255, 255, 255))   # 2 x 20 pt, on the bar
    put(4200, caret, "caret")
    put(4500, barred, "bar5")
    put(4800, caret, "caret")
    for k in range(61):                                  # the drag: everything under the title bar moves up
        cur = Image.new("RGB", RAW, (246, 247, 249))
        cur.paste(caret.crop((0, 0, RAW[0], 330)), (0, 0))
        up = SCROLL_PX * (k + 1)
        cur.paste(caret.crop((0, 330 + up, RAW[0], RAW[1])), (0, 330))
        put(6000 + 10 * k, cur, f"drag{k}")
    put(7000, cur, "drag60")
    put(9290, cur, "drag60")

    clip = {"width": RAW[0], "height": RAW[1], "timescale": T, "end": 9300, "bitrate": 8_000_000,
            "profile": "high", "frames": frames}
    (folder / "clip.json").write_text(json.dumps(clip))
    take = folder / "take.mov"
    swifttools.run("testclip", folder / "clip.json", "--out", take)
    return take, [f["pts"] for f in frames]


def setUpModule():
    global WORK, TAKE, TAKE_PTS, FILM
    WORK = Path(tempfile.mkdtemp(prefix="preview-e2e-"))
    TAKE, TAKE_PTS = synthetic_take(WORK / "take")
    (WORK / "storyboard.json").write_text(json.dumps(SB))
    (WORK / "gestures.json").write_text(json.dumps(E2E_LOG))
    FILM = WORK / "film"
    said = io.StringIO()
    try:
        with contextlib.redirect_stdout(said):
            preview.cmd_build(preview.argparse.Namespace(
                storyboard=WORK / "storyboard.json", gestures=WORK / "gestures.json", take=TAKE, out=FILM,
                edit=None, rehearsal=False))
    except SystemExit:
        # the build stopped: say why, the last line is what failed
        print(said.getvalue().rstrip()[-1500:], file=sys.stderr)
        raise


def tearDownModule():
    shutil.rmtree(WORK, ignore_errors=True)


def read(name: str) -> dict:
    return json.loads((FILM / name).read_text())


def tool(*args) -> subprocess.CompletedProcess:
    """The command line, as a person runs it."""
    return subprocess.run(["python3", str(TOOL / "preview.py"), *map(str, args)], capture_output=True, text=True)


class Scan(unittest.TestCase):
    def test_the_take_has_the_recorders_shape(self):
        box = mp4.read(TAKE)
        self.assertEqual(box["ftyp"]["major"], "qt  ")
        self.assertEqual([t["handler"] for t in box["tracks"]], ["vide"])        # no sound
        self.assertGreater(len({d for _, d in box["tracks"][0]["stts"]}), 3)     # variable frame times

    def test_every_frame_and_its_time_is_found(self):
        scan = read("scan.json")
        self.assertEqual([f["pts"] for f in scan["frames"]], TAKE_PTS)
        self.assertEqual((scan["video"]["width"], scan["video"]["height"], scan["video"]["timescale"]),
                         (1206, 2622, T))
        self.assertEqual(scan["video"]["audio_tracks"], 0)
        self.assertEqual(scan["video"]["duration_ticks"], 9300)
        self.assertEqual(scan["take"], {"file": "take.mov", "bytes": TAKE.stat().st_size,
                                        "sha256": hashlib.sha256(TAKE.read_bytes()).hexdigest()})

    def test_changes_stills_and_the_caret_are_told_apart(self):
        scan = read("scan.json")
        kinds = dict(zip(TAKE_PTS, edit.frame_kinds(scan, PX, 300)))
        self.assertEqual(kinds[300], "quiet")                       # the same picture, sent again
        self.assertEqual(kinds[7000], "quiet")
        self.assertEqual([kinds[p] for p in (4200, 4500, 4800)], ["caret"] * 3)
        moving = [p for p, k in kinds.items() if k == "change"]
        self.assertEqual(moving, [0] + list(range(1800, 1901, 10)) + list(range(3600, 3651, 10))
                         + list(range(6000, 6601, 10)))
        caret = next(f for f in scan["frames"] if f["pts"] == 4200)
        self.assertEqual(caret["strong"], 360)                      # 6 x 60 pixels: exactly the caret drawn
        self.assertEqual(caret["box"], [1000, 2380, 1006, 2440])
        still = next(f for f in scan["frames"] if f["pts"] == 300)
        self.assertLess(still["strong"], edit.STRONG_MIN)
        self.assertLess(still["soft"], edit.SOFT_MIN)

    def test_bursts_start_and_end_where_the_pictures_changed(self):
        scan = read("scan.json")
        bursts = edit.find_bursts(scan, edit.frame_kinds(scan, PX, 300), 300)
        self.assertEqual([(b.start, b.end) for b in bursts], [(0, 0), (1800, 1900), (3600, 3650), (6000, 6600)])


class Build(unittest.TestCase):
    def test_the_film_passes_every_check(self):
        report = (FILM / "verify.txt").read_text()
        self.assertIn("PASS — 24 checks", report)
        self.assertNotIn("FAIL", report)
        self.assertNotIn("REHEARSAL", report)
        self.assertEqual({c.name for c in verify.verify(FILM / "preview.mp4", SB, FILM / "poster.png") if not c.ok},
                         set())

    def test_the_edit_list_is_the_one_the_data_dictates(self):
        e = read("edit.json")
        self.assertEqual([(s["kind"], s.get("src_in", s.get("src_at")), s.get("src_out", s.get("frames")))
                          for s in e["segments"]],
                         [("hold", 1740, 30), ("live", 1740, 3860), ("hold", 3840, 30),
                          # the drag: from `fast` (60 ticks) before the list first moves — the touch point
                          # whole by then — to 0.3 s after its last frame: 5940 + 43 frames
                          ("live", 5940, 6800), ("hold", 6780, 15), ("hold", 6780, 226)])
        cuts = (FILM / "cuts.txt").read_text()
        self.assertIn("removed, lands on film  5.533 s: 0 quiet frames, 3 caret-only frames in the box "
                      "[1000, 2380, 1006, 2440]; frame 18 against frame 21:", cuts)
        self.assertIn("(caret)", cuts)
        self.assertIn("followed in the picture on 60 frames, from 5.0 to 300.0 pt of the 300 pt logged", cuts)
        # the take has a picture every 1/60 s: the film shows every other one, none twice
        self.assertIn("(43 frames, 1:1)  shows 31 of the take's 61 changed pictures, 0 twice while it moved", cuts)
        self.assertIn("drags, film frame by film frame (points the picture moved under the finger)\n"
                      "  drag-b           5 10 10 10 10", cuts)
        self.assertIn("first step 5 pt; 0 film frames did not move", cuts)

    def test_the_log_says_what_each_touch_point_landed_on(self):
        """Written after the frames are composed: read on the picture each
        touch lands on."""
        cuts = (FILM / "cuts.txt").read_text()
        self.assertIn("touch points on the picture (white on a dark or green fill: luminance under 0.35; else the "
                      "brand's black)\n"
                      "  tap-a            black point on a light ground at (100, 260) pt: luminance 1.00 under the "
                      "finger,", cuts)
        self.assertIn("  drag-b           black point on a light ground at (200, 600) pt:", cuts)

    def test_the_build_leaves_a_record_of_what_it_made(self):
        record = read("build.json")
        movie = FILM / "preview.mp4"
        self.assertEqual(record, {
            "file": "preview.mp4", "bytes": movie.stat().st_size,
            "sha256": hashlib.sha256(movie.read_bytes()).hexdigest(), "rehearsal": False, "variant": None,
            "poster_sha256": hashlib.sha256((FILM / "poster.png").read_bytes()).hexdigest(),
            "take": read("scan.json")["take"]})
        self.assertIn(f"PASS — 24 checks — the film, sha256 {record['sha256'][:16]}…\n", (FILM / "verify.txt").read_text())
        # and the command, run by hand on that file, says the same
        r = tool("verify", movie, "--storyboard", WORK / "storyboard.json", "--poster", FILM / "poster.png")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(r.stdout.endswith(f"PASS — 24 checks — the film, sha256 {record['sha256'][:16]}…\n"))

    def test_the_drag_is_followed_in_the_picture(self):
        """track.json: what the pictures say, frame by frame — the list is
        5 pt further up in each, and the 61st frame goes past the finger."""
        track = read("track.json")["drag-b"]
        self.assertEqual((track["axis"], track["sign"], track["turn"]), ("y", -1, None))
        self.assertEqual(track["frames"], [[6000 + 10 * k, 5.0 * (k + 1)] for k in range(61)])
        self.assertLess(track["error"], 3.0)
        self.assertNotIn("why", track)
        touch = read("edit.json")["touches"][1]
        # film tick 3380 is take tick 6000: the live range starts at 5940, film frame 166
        self.assertEqual(touch["down"], 166 * 20)
        self.assertEqual(touch["step"], [3380, 3380 + 590])            # frames 6000 … 6590: 300 pt, the whole log
        self.assertEqual(touch["path"][:3], [[3320.0, 200, 600], [3376.0, 200, 600], [3380.0, 200.0, 595.0]])
        self.assertEqual(touch["path"][-1], [3970.0, 200.0, 300.0])
        self.assertEqual(touch["up"], 3970)

    def test_the_touch_point_rides_on_what_it_drags(self):
        """In the composed frames: the disc stays on the piece of the list
        the finger took — the same pixel of content under its centre all the
        way up, 12 % darker for the disc on it."""
        names = read("frames/frames.json")["frames"]
        pt = 644 / 402

        def at(n: int, y_pt: float) -> int:
            with Image.open(FILM / "frames" / names[n]) as im:
                return int(np.asarray(im)[440 + round(y_pt * pt), 121 + round(200 * pt)].astype(int).sum())

        bare = at(165, 600)                    # the frame before the touch-down: what the finger lands on
        self.assertGreater(bare, 300)          # light enough for a 12 % disc to show
        veiled = bare * (1 - SB["touch"]["fill_opacity"])
        # film frame 169 + 3k shows take tick 6000 + 60k: the list is 5 + 30k pt up, and so is the finger
        for k in (0, 3, 6, 9):
            n, y = 169 + 3 * k, 600 - (5 + 30 * k)
            self.assertLess(abs(at(n, y) - veiled), 0.04 * bare, (n, y, at(n, y), bare))

    def test_the_log_says_how_each_drag_was_timed(self):
        self.assertEqual(read("edit.json")["variant"], None)
        self.assertNotIn("NOT followed", (FILM / "cuts.txt").read_text())

    def test_the_two_frame_hold_computations_agree(self):
        manifest = json.loads((FILM / "src" / "manifest.json").read_text())
        self.assertEqual(manifest["film"], edit.film_sources(read("edit.json"), read("scan.json"), 30))
        self.assertEqual(len(manifest["film"]), 450)
        self.assertEqual(manifest["film"][30:36], [1, 1, 1, 2, 4, 6])   # 60 pictures a second, every other one

    def test_exported_frames_are_the_take_s_pictures(self):
        manifest = json.loads((FILM / "src" / "manifest.json").read_text())
        j = manifest["film"][read("edit.json")["poster_frame"]]
        self.assertEqual(manifest["sources"][str(j)]["pts"], 6600)              # the last change, held
        with Image.open(FILM / "src" / manifest["sources"][str(j)]["file"]) as im:
            got = np.asarray(im.convert("RGB")).astype(int)
        with Image.open(WORK / "take" / "drag60.png") as im:
            want = np.asarray(im).astype(int)
        self.assertEqual(got.shape, want.shape)
        self.assertLess(np.abs(got - want).mean(), 1.0)                         # the recording is lossy, not wrong

    def test_the_touch_point_is_on_the_frames_it_should_be(self):
        names = read("frames/frames.json")["frames"]
        self.assertEqual(len(names), 450)
        self.assertEqual(len(set(names[:30])), 1)                               # the lead-in is one picture
        self.assertEqual(len(set(names[235:])), 1)                              # and so is the final hold

        def pixel(n: int) -> np.ndarray:
            pt = 644 / 402
            with Image.open(FILM / "frames" / names[n]) as im:
                return np.asarray(im)[440 + round(260 * pt), 121 + round(100 * pt)].astype(int)  # (100, 260) pt
        self.assertLess(pixel(32).sum(), pixel(29).sum() - 30)                  # the disc darkens the white row
        self.assertTrue((np.abs(pixel(60) - np.array([45, 80, 22])) < 8).all())  # the row is green, the disc gone

    def test_the_sheet_and_the_poster_are_written(self):
        with Image.open(FILM / "contact-sheet.png") as sheet:
            self.assertEqual(sheet.size, (10 * 222 + 11 * 16, 3 * (481 + 30 + 16) + 16))   # 30 frames, 2 a second
        with Image.open(FILM / "poster.png") as poster:
            self.assertEqual(poster.size, (886, 1920))
        psnr, block = verify.compare_images(FILM / "poster-decoded.png", FILM / "poster.png")
        self.assertGreater(psnr, verify.POSTER_MIN_PSNR)
        self.assertLess(block, verify.POSTER_MAX_BLOCK)
        self.assertEqual(sorted(p.name for p in FILM.glob("*.mp4*")), ["preview.mp4"])   # no scratch file left

    def test_a_hand_written_cut_inside_a_response_stops_the_build(self):
        """The refusal, seen from the command line."""
        e = read("edit.json")
        e["segments"][1:2] = [{"kind": "live", "src_in": 1740, "src_out": 2040},
                              {"kind": "live", "src_in": 3540, "src_out": 3860}]
        bad = WORK / "bad-edit.json"
        bad.write_text(json.dumps(e))
        (WORK / "refused").mkdir(exist_ok=True)
        for earlier in ("preview.mp4", "verify.txt", "edit.json"):       # an earlier, good build's results
            shutil.copyfile(FILM / earlier, WORK / "refused" / earlier)
        r = subprocess.run(
            ["python3", str(TOOL / "preview.py"), "build", "--storyboard", str(WORK / "storyboard.json"),
             "--take", str(TAKE), "--gestures", str(WORK / "gestures.json"), "--edit", str(bad),
             "--out", str(WORK / "refused")], capture_output=True, text=True)
        self.assertEqual(r.returncode, 1)
        self.assertIn("edit list refused [E_PROTECTED] gesture `tap-a`", r.stderr)
        # nothing is left that could pass for this run's result
        # (what the take was read as stays: scan.json, track.json — neither is a result)
        self.assertEqual(sorted(p.name for p in (WORK / "refused").iterdir()), ["scan.json", "track.json"])

    def build(self, name: str, *args: str, gestures: Path | None = None) -> subprocess.CompletedProcess:
        return subprocess.run(
            ["python3", str(TOOL / "preview.py"), "build", "--storyboard", str(WORK / "storyboard.json"),
             "--take", str(TAKE), "--gestures", str(gestures or WORK / "gestures.json"),
             "--out", str(WORK / name), *args], capture_output=True, text=True)

    def test_the_bursts_command_lists_where_the_screen_changes(self):
        """What a person reads `near_s` from."""
        r = tool("bursts", FILM / "scan.json", "--storyboard", WORK / "storyboard.json")
        self.assertEqual(r.returncode, 0, r.stderr)
        lines = r.stdout.splitlines()
        self.assertEqual(lines[0], "85 frames: 79 change, 3 quiet, 3 caret-only; first picture at 0.000 s")
        self.assertEqual([line.split()[:3] for line in lines[2:]],
                         [["0.000", "0.000", "1"], ["3.000", "3.167", "11"], ["6.000", "6.083", "6"],
                          ["10.000", "11.000", "61"]])
        self.assertIn("20, 223 – 387, 290", lines[3])          # the tapped row, in points

    def test_the_check_command_needs_the_reading_of_the_picture_the_edit_list_was_made_with(self):
        base = ["check", "--storyboard", WORK / "storyboard.json", "--scan", FILM / "scan.json",
                "--gestures", WORK / "gestures.json", "--edit", FILM / "edit.json", "--take", TAKE]
        with_tracks = tool(*base, "--tracks", FILM / "track.json")
        self.assertEqual(with_tracks.returncode, 0, with_tracks.stderr)
        self.assertTrue(with_tracks.stdout.endswith("edit list accepted\n"))
        self.assertIn("followed in the picture on 60 frames", with_tracks.stdout)
        without = tool(*base)
        self.assertEqual(without.returncode, 1)
        self.assertIn("edit list refused [E_TOUCH]", without.stderr)

    def test_a_film_that_fails_a_check_fails_the_build(self):
        from unittest import mock
        miss = [verify.Check("size", False, "885 x 1920")]
        args = preview.argparse.Namespace(
            storyboard=WORK / "storyboard.json", gestures=WORK / "gestures.json", take=TAKE,
            out=WORK / "missed", edit=None, rehearsal=False)
        with mock.patch.object(preview.verifying, "verify", return_value=miss), \
                contextlib.redirect_stdout(io.StringIO()) as said, self.assertRaises(SystemExit) as cm:
            preview.cmd_build(args)
        self.assertEqual(cm.exception.code, 1)
        self.assertIn("FAIL — 1 of 1 checks: size", said.getvalue())
        self.assertIn("FAIL — 1 of 1 checks: size", (WORK / "missed" / "verify.txt").read_text())

    def test_a_rehearsal_s_edit_list_cannot_make_the_film(self):
        """A rehearsal may leave gestures out. Its edit list must not get
        through a build that was not asked for a rehearsal."""
        e = read("edit.json")
        e["rehearsal"] = True
        (WORK / "rehearsal-edit.json").write_text(json.dumps(e))
        r = self.build("mislabelled", "--edit", str(WORK / "rehearsal-edit.json"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("the edit list and --rehearsal disagree", r.stderr)
        self.assertEqual(sorted(p.name for p in (WORK / "mislabelled").iterdir()), ["scan.json", "track.json"])

    def test_a_gesture_the_take_does_not_show_stops_the_build(self):
        log = copy.deepcopy(E2E_LOG)
        log["gestures"][1]["near_s"] = 13.0
        (WORK / "wrong-gestures.json").write_text(json.dumps(log))
        r = self.build("unmatched", gestures=WORK / "wrong-gestures.json")
        self.assertEqual(r.returncode, 1)
        self.assertIn("cannot find the gestures in the take [E_MATCH] gesture `drag-b`: nothing starts changing "
                      "within ±0.5 s of 13.0 s", r.stderr)
        self.assertEqual(sorted(p.name for p in (WORK / "unmatched").iterdir()), ["scan.json"])

    def test_a_take_longer_than_the_storyboard_allows_stops_the_build(self):
        """Nothing is squeezed to fit: the gestures are found, the drag is
        followed, and no edit list can be proposed."""
        short = copy.deepcopy(SB)
        short["film"].update(duration_s=7.0, poster_s=6.9)
        (WORK / "storyboard-short.json").write_text(json.dumps(short))
        r = tool("build", "--storyboard", WORK / "storyboard-short.json", "--take", TAKE,
                 "--gestures", WORK / "gestures.json", "--out", WORK / "too-long")
        self.assertEqual(r.returncode, 1)
        self.assertIn("cannot propose an edit list [E_LENGTH] the film is already 7.47 s before its final hold",
                      r.stderr)
        self.assertEqual(sorted(p.name for p in (WORK / "too-long").iterdir()), ["scan.json", "track.json"])

    def test_the_two_sides_of_a_cut_are_compared_on_the_decoded_frames(self):
        e, scan, log = read("edit.json"), read("scan.json"), json.loads((WORK / "gestures.json").read_text())
        tracks = read("track.json")
        pairs = edit.cut_pairs(e, scan, 30)
        self.assertEqual(pairs, [(18, 21)])                    # the bar's last frame, the caret's last blink
        diffs = preview.pair_diffs(TAKE, pairs, WORK)
        self.assertEqual(diffs[(18, 21)]["box"], [1000, 2380, 1006, 2440])
        tm = edit.check(e, scan, log, SB, diffs, tracks)
        self.assertEqual(edit.pair_kind(diffs[(18, 21)], tm, 21), "caret")
        # had the film resumed on a picture from the middle of the drag:
        moved = preview.pair_diffs(TAKE, [(18, 30)], WORK)[(18, 30)]
        self.assertEqual(edit.pair_kind(moved, tm, 21), "change")
        with self.assertRaises(edit.Refusal) as cm:
            edit.check(e, scan, log, SB, {(18, 21): moved}, tracks)
        self.assertEqual(cm.exception.code, "E_ENDPOINT")


class Variant(unittest.TestCase):
    """A variant of the storyboard — a rehearsal on other gestures — built
    from the same take: the tap, and nothing of the drag."""

    @classmethod
    def setUpClass(cls):
        doc = copy.deepcopy(SB)
        doc["variants"] = {"dry": {
            "_what": "the tap alone",
            "shots": [{"id": "A", "caption": "one", "gestures": [{"id": "tap-a", "kind": "tap", "rest_after_s": 1.0}]},
                      {"id": "C", "caption": "three", "caption_after": {"gesture": "tap-a", "delay_s": 0.5},
                       "gestures": []}]}}
        (WORK / "storyboard-variants.json").write_text(json.dumps(doc))
        log = copy.deepcopy(E2E_LOG)
        log["gestures"][1] = {"kind": "drag", "near_s": 10.0, "film": False}     # done, and not in this film
        (WORK / "gestures-dry.json").write_text(json.dumps(log))
        cls.out = WORK / "dry"
        cls.built = tool("build", "--storyboard", WORK / "storyboard-variants.json", "--variant", "dry",
                         "--take", TAKE, "--gestures", WORK / "gestures-dry.json", "--out", cls.out)

    def test_it_is_built_as_a_rehearsal_and_says_so_everywhere(self):
        self.assertEqual(self.built.returncode, 0, self.built.stderr)
        # never under the film's name
        self.assertEqual(sorted(p.name for p in self.out.glob("*.mp4")), ["preview-rehearsal.mp4"])
        report = (self.out / "verify.txt").read_text()
        self.assertIn("PASS — 24 checks — REHEARSAL, not the film: the storyboard's variant `dry`", report)
        self.assertIn("REHEARSAL — the storyboard's variant `dry`; this is not the film.",
                      (self.out / "cuts.txt").read_text())
        e = json.loads((self.out / "edit.json").read_text())
        self.assertEqual((e["rehearsal"], e["variant"]), (True, "dry"))

    def test_it_is_the_variants_film(self):
        e = json.loads((self.out / "edit.json").read_text())
        self.assertEqual([c["caption"] for c in e["captions"]], ["one", "three"])
        self.assertEqual([t["gesture"] for t in e["touches"]], ["tap-a"])
        # the tap's answer ends on the last change before the drag that is not
        # filmed (the bar, at 3650 — the caret after it is no change), and the
        # film ends there: 30 + 106 + 30 frames, then the final hold
        self.assertEqual([(s["kind"], s.get("src_in", s.get("src_at")), s.get("src_out", s.get("frames")))
                          for s in e["segments"]],
                         [("hold", 1740, 30), ("live", 1740, 3860), ("hold", 3840, 30), ("hold", 3840, 284)])
        self.assertEqual(json.loads((self.out / "track.json").read_text()), {})      # no drag in it to follow

    def test_the_checker_knows_a_rehearsal_by_its_record_not_by_its_name(self):
        """The film's own storyboard is the same length here, so a rehearsal
        passes every one of its checks. It is never called the film: the
        record the build left names its bytes, wherever they are copied."""
        movie = self.out / "preview-rehearsal.mp4"
        record = json.loads((self.out / "build.json").read_text())
        self.assertEqual((record["file"], record["rehearsal"], record["variant"]), ("preview-rehearsal.mp4", True, "dry"))
        self.assertEqual(record["sha256"], hashlib.sha256(movie.read_bytes()).hexdigest())
        base = ["--storyboard", WORK / "storyboard-variants.json", "--poster", self.out / "poster.png"]
        told = tool("verify", movie, *base, "--variant", "dry")
        self.assertEqual(told.returncode, 0, told.stdout + told.stderr)
        self.assertTrue(told.stdout.endswith(
            "PASS — 24 checks — REHEARSAL, not the film: the storyboard's variant `dry`\n"), told.stdout[-200:])
        # checked as the film — under its own name, or renamed preview.mp4 where it was built
        renamed = self.out / "preview.mp4"
        shutil.copyfile(movie, renamed)
        try:
            for path in (movie, renamed):
                untold = tool("verify", path, *base)
                self.assertEqual((untold.returncode, untold.stdout), (1, ""), path.name)
                self.assertIn(f"{path.name} was built as the storyboard's variant `dry` (build.json beside it names "
                              f"these bytes) and is being checked as the film: add --variant dry", untold.stderr)
        finally:
            renamed.unlink()
        # copied out of its folder and renamed: every check passes, and it is not called the film
        away = WORK / "away"
        away.mkdir(exist_ok=True)
        shutil.copyfile(movie, away / "preview.mp4")
        stray = tool("verify", away / "preview.mp4", *base)
        self.assertEqual(stray.returncode, 1)
        self.assertIn("PASS — 24 checks\nNOT IDENTIFIED — no build.json beside preview.mp4 names these bytes",
                      stray.stdout)
        # and the film is not a rehearsal either
        film = tool("verify", FILM / "preview.mp4", *base[:2], "--poster", FILM / "poster.png", "--variant", "dry")
        self.assertEqual(film.returncode, 1)
        self.assertIn("preview.mp4 was built as the film (build.json beside it names these bytes) and is being "
                      "checked as the storyboard's variant `dry`: drop --variant", film.stderr)

    def test_a_variant_the_storyboard_does_not_have_stops_the_build(self):
        r = tool("build", "--storyboard", WORK / "storyboard-variants.json", "--variant", "wet", "--take", TAKE,
                 "--gestures", WORK / "gestures-dry.json", "--out", WORK / "wet")
        self.assertEqual(r.returncode, 1)
        self.assertIn("[E_STORYBOARD] the storyboard has no variant `wet` (it has: dry)", r.stderr)
        self.assertFalse((WORK / "wet").exists())

    def test_the_films_edit_list_cannot_be_built_as_the_variant(self):
        crossed = ["build", "--storyboard", WORK / "storyboard-variants.json", "--variant", "dry", "--take", TAKE,
                   "--gestures", WORK / "gestures-dry.json", "--out", WORK / "crossed"]
        r = tool(*crossed, "--edit", FILM / "edit.json", "--rehearsal")
        self.assertEqual(r.returncode, 1)
        self.assertIn("the edit list and --rehearsal disagree", r.stderr)
        e = read("edit.json")
        e["rehearsal"] = True
        (WORK / "crossed-edit.json").write_text(json.dumps(e))
        r = tool(*crossed, "--edit", WORK / "crossed-edit.json")
        self.assertEqual(r.returncode, 1)
        self.assertIn("edit list refused [E_VARIANT] the edit list was made for the film itself, this storyboard "
                      "is the variant `dry`", r.stderr)
        self.assertEqual(sorted(p.name for p in (WORK / "crossed").iterdir()), ["scan.json", "track.json"])


if __name__ == "__main__":
    unittest.main()
