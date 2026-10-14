"""A film of scenes, end to end, without the simulator.

tests/test_e2e.py's synthetic take — a tap answered at 3.000–3.167 s, the
app's own bar at 6.000–6.083 s, a caret, a drag that scrolls the list up
exactly 15 px a picture for a second — becomes a film of two scenes:

  S1  the tap, the declared dissolve over the caret's stretch, the drag —
      with a mask over a line of words in the list, tracking the scroll;
  S2  the tap again, kept by times (2.5–6.5 s of the take);

then the end card. Built twice, in the two frames. The tests read what the
builds left, and break the written film on purpose."""

from __future__ import annotations

import copy
import json
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

import film
import scenes
import swifttools
import verify
from tests.support import TOOL
from tests.test_e2e import E2E_LOG, synthetic_take

WORK: Path
TAKE: Path
BUILT: dict[str, Path] = {}
SAID: dict[str, str] = {}

# a line of words on the list's fourth card (tests/test_e2e.py `rest_screen`): y 1230–1254 px at rest
WORDS = [100, 1222, 900, 40]
DOC = {
    "version": 2,
    "film": {"fps": 30, "width": 886, "height": 1920, "frame": "framed", "poster": {"scene": "S1", "at_s": 7.6}},
    "motion": {"join": "base", "dissolve": "base", "end_card": "base", "touch_in": "fast", "touch_out": "base"},
    "touch": {"diameter_pt": 48, "ring_pt": 1.5, "fill_opacity": 0.12, "ring_opacity": 0.45, "tap_lead": "fast",
              "tap_dwell": "base", "light_below_luminance": 0.35},
    "timing": {"rest_s": 0.5, "tail_s": 0.3, "key_tail_s": 0.1, "sync_tolerance_s": 0.5, "lead_in_s": 0.6},
    "band": {"top_pt": 62, "bottom_pt": 34},
    "end_card": {"title": "MyWeli Pro", "line": "Un compte MyWeli Pro est nécessaire.", "duration_s": 2.2},
    "scenes": [
        {"id": "S1", "take": "take/take.mov", "gestures": "gestures.json", "budget_s": 8.0,
         "headline": ["Une cliente arrive ?", "Un geste suffit."],
         "keep": [{"gesture": "tap-a", "rest_after_s": 0.6}, {"dissolve": "base", "lead_in_s": 0.6},
                  {"gesture": "drag-b", "rest_after_s": 1.0}],
         "masks": [{"rect_px": WORDS, "style": "fill", "track": {"scroll_px": [330, 2622]}}]},
        {"id": "S2", "take": "take/take.mov", "gestures": "gestures.json",
         "headline": ["Un créneau libre ?", "Ajoutez un rendez-vous."],
         "keep": [{"from_s": 2.5, "to_s": 6.5, "rest_after_s": 1.0}]},
    ],
}


def tool(*args) -> subprocess.CompletedProcess:
    return subprocess.run(["python3", str(TOOL / "preview.py"), *map(str, args)], capture_output=True, text=True)


def build(name: str, doc: dict, *extra: str) -> subprocess.CompletedProcess:
    (WORK / f"{name}.json").write_text(json.dumps(doc, ensure_ascii=False))
    return tool("film", "--storyboard", WORK / f"{name}.json", "--takes", WORK, "--out", WORK / name, *extra)


def setUpModule():
    global WORK, TAKE
    WORK = Path(tempfile.mkdtemp(prefix="preview-film-"))
    TAKE, _ = synthetic_take(WORK / "take")
    (WORK / "gestures.json").write_text(json.dumps(E2E_LOG))
    for frame in ("framed", "full-bleed"):
        r = build(frame, DOC, "--frame", frame)
        SAID[frame] = r.stdout + r.stderr
        if r.returncode != 0:
            print(SAID[frame][-2500:], file=sys.stderr)
            raise RuntimeError(f"the {frame} build failed")
        BUILT[frame] = WORK / frame


def tearDownModule():
    shutil.rmtree(WORK, ignore_errors=True)


def read(frame: str, name: str):
    return json.loads((BUILT[frame] / name).read_text())


class Built(unittest.TestCase):
    def test_both_frames_pass_every_check_masked_regions_included(self):
        for frame in BUILT:
            report = (BUILT[frame] / "verify.txt").read_text()
            self.assertIn("PASS — 25 checks — the film, sha256", report, frame)
            self.assertIn("ok    masked regions", report, frame)
            self.assertNotIn("FAIL", report, frame)
            record = read(frame, "build.json")
            self.assertEqual((record["version"], record["frame"], record["rehearsal"]), (2, frame, False))

    def test_the_plan_is_the_one_the_take_dictates(self):
        """S1: lead-in, the tap from `fast` before its answer to 0.3 s after
        the bar (the app's own, in the tap's window), its rest; the
        dissolve; the drag from `fast` before the list first moves to 0.3 s
        after its last frame. S2: 2.5–6.5 s by times."""
        plan = read("framed", "film.json")
        s1, s2 = plan["scenes"]
        self.assertEqual([[(s["kind"], s.get("src_in", s.get("src_at")), s.get("src_out", s.get("frames")))
                           for s in run["segments"]] for run in s1["runs"]],
                         [[("hold", 1740, 18), ("live", 1740, 3860), ("hold", 3840, 18)],
                          [("hold", 5940, 18), ("live", 5940, 6800), ("hold", 6780, 30)]])
        self.assertEqual(s1["dissolves"], [{"token": "base", "frames": 5}])
        self.assertEqual([(s["kind"], s.get("src_in", s.get("src_at")), s.get("src_out", s.get("frames")))
                          for s in s2["runs"][0]["segments"]],
                         [("hold", 1500, 18), ("live", 1500, 3900), ("hold", 3880, 30)])
        self.assertEqual([t["gesture"] for t in s1["touches"] + s2["touches"]], ["S1/tap-a", "S1/drag-b", "S2/tap-a"])
        self.assertEqual(scenes.places(plan)[3], 482)
        self.assertEqual(plan, read("full-bleed", "film.json") | {"frame": "framed"})

    def test_the_log_says_what_was_skipped_joined_and_masked(self):
        cuts = (BUILT["framed"] / "cuts.txt").read_text()
        self.assertIn("DISSOLVE base  5 frames from the picture at take   6.400 s to the picture at take   9.900 s: "
                      "the take's   6.400 s –   9.900 s is skipped, declared (no gesture in it)", cuts)
        self.assertIn("  S1   film  0.000 –  7.933 s   7.93 s  budget 8 s, -0.07 s", cuts)
        self.assertIn("join film  7.933 –  8.100 s  base: 5 frames between the last picture of S1 and the first of S2",
                      cuts)
        # the mask followed the list to the pixel: 15 px a picture, 61 pictures
        self.assertRegex(cuts, r"scene S1, mask 0: fill \(255, 255, 255\), tracking the scroll, reference 0\.500 s, "
                               r"on 43 of 43 pictures, moved -915 to \+0 px, worst match 0\.\d levels")
        self.assertIn("frame: framed — the card 711 x 1546 at (87, 293), 64.6% of the frame", cuts)
        self.assertIn("frame: full-bleed — caption bands", (BUILT["full-bleed"] / "cuts.txt").read_text())

    def test_the_masked_line_is_covered_wherever_the_list_has_scrolled(self):
        """In every masked frame of S1 — its dissolve included, both its
        pictures masked — the region the build checked is white, the card
        under the words, and the original there has the words. (The join
        into S2 blends S1's masked picture with S2's, which has no mask:
        verify holds those frames to its own rule.) In both frames: the box
        the build maps the mask to is where the words are — what verify's
        check relies on and cannot see for itself."""
        # in the full-bleed frame the caption band is over the top of the list: a line scrolled up
        # under it is hidden by the band, in both compositions — only the rows below the band count
        band_bottom = {"framed": 0, "full-bleed": int(re.search(r"S1 \(\d+, \d+, \d+, (\d+)\)",
                                                                 (BUILT["full-bleed"] / "cuts.txt").read_text())[1])}
        for frame in BUILT:
            regions = read(frame, "masks.json")["regions"]
            self.assertGreater(len(regions), 60, frame)
            inside = [reg for reg in regions if reg["frame"] < 238]
            self.assertEqual({142, 143, 144, 145, 146} - {reg["frame"] for reg in inside}, set())   # the dissolve
            seen = 0
            for reg in inside[::5]:
                below = max(0, band_bottom[frame] + 1 - reg["box"][1])
                if reg["box"][3] - reg["box"][1] - below < 8:
                    continue
                seen += 1
                with Image.open(BUILT[frame] / reg["masked"]) as m, Image.open(BUILT[frame] / reg["original"]) as o:
                    masked, original = np.asarray(m).astype(int)[below:], np.asarray(o).astype(int)[below:]
                self.assertLess(np.abs(masked - 255).mean(), 12, (frame, reg))   # white, but for a passing touch point
                self.assertGreater(np.abs(original - masked).max(), 150, (frame, reg))
                # and the words are inside the box, not cut by it: the box's own rows of ink
                ink = (original.mean(axis=2) < 100).any(axis=1)
                self.assertGreater(int(ink.sum()), 3, (frame, reg))
            self.assertGreater(seen, 5, frame)

    def test_the_frames_are_the_plan(self):
        names = read("framed", "frames/frames.json")["frames"]
        self.assertEqual(len(names), 482)
        self.assertEqual(len(set(names[-60:])), 1)                     # the end card, one picture
        end = np.asarray(Image.open(BUILT["framed"] / "frames" / names[-1])).astype(int)
        self.assertEqual(tuple(end[5, 5]), (250, 250, 250))

    def test_a_film_whose_masked_rectangle_shows_the_original_fails_verify(self):
        """The built frames, with the original pixels put back where the
        mask was, encoded: verify names the masked regions."""
        frames_dir = WORK / "leak" / "frames"
        shutil.copytree(BUILT["framed"] / "frames", frames_dir)
        names = read("framed", "frames/frames.json")["frames"]
        regions = read("framed", "masks.json")["regions"]
        touched: dict[str, Image.Image] = {}
        for reg in regions:
            name = names[reg["frame"]]
            fresh = f"leak_{reg['frame']:06d}.png"
            im = touched.get(fresh) or Image.open(frames_dir / name).convert("RGB")
            with Image.open(BUILT["framed"] / reg["original"]) as o:
                im.paste(o.convert("RGB"), tuple(reg["box"][:2]))
            touched[fresh] = im
            names[reg["frame"]] = fresh
        for fresh, im in touched.items():
            im.save(frames_dir / fresh)
        manifest = read("framed", "frames/frames.json") | {"frames": names}
        (frames_dir / "frames.json").write_text(json.dumps(manifest))
        movie = WORK / "leak" / "preview.mp4"
        swifttools.run("encode", frames_dir, "--out", movie)
        checks = verify.verify(movie, film.film_storyboard(read("framed", "film.json")), BUILT["framed"] / "poster.png",
                               {"regions": regions, "base": BUILT["framed"]})
        failed = {c.name: c.seen for c in checks if not c.ok}
        self.assertEqual(set(failed) - {"poster frame"}, {"masked regions"})
        self.assertIn("THE ORIGINAL SHOWS in frame(s)", failed["masked regions"])

    def test_the_command_checks_a_built_film_again_and_knows_it_by_its_record(self):
        movie = BUILT["full-bleed"] / "preview.mp4"
        r = tool("film-verify", movie)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        sha = read("full-bleed", "build.json")["sha256"]
        self.assertTrue(r.stdout.endswith(f"PASS — 25 checks — the film, sha256 {sha[:16]}…\n"), r.stdout[-300:])
        # copied out with what it needs, but not its record: every check, then not identified
        away = WORK / "away"
        away.mkdir()
        for name in ("preview.mp4", "film.json", "masks.json", "poster.png"):
            shutil.copyfile(BUILT["full-bleed"] / name, away / name)
        shutil.copytree(BUILT["full-bleed"] / "frames" / "masks", away / "frames" / "masks")
        r = tool("film-verify", away / "preview.mp4")
        self.assertEqual(r.returncode, 1)
        self.assertIn("PASS — 25 checks\nNOT IDENTIFIED — no build.json beside preview.mp4", r.stdout)
        # without what its build left beside it, it is not checked at all
        (away / "film.json").unlink()
        r = tool("film-verify", away / "preview.mp4")
        self.assertEqual((r.returncode, r.stdout), (1, ""))
        self.assertIn("film.json is not beside preview.mp4", r.stderr)


class Refused(unittest.TestCase):
    def earlier(self, name: str) -> Path:
        folder = WORK / name
        folder.mkdir()
        for result in ("preview.mp4", "verify.txt", "film.json", "cuts.txt", "masks.json", "build.json",
                       "poster.png", "contact-sheet.png"):
            (folder / result).write_text("an earlier build's")
        return folder

    def test_a_refused_plan_stops_the_build_and_leaves_no_earlier_result(self):
        folder = self.earlier("too-short")
        doc = copy.deepcopy(DOC)
        doc["scenes"][1]["keep"][0]["rest_after_s"] = 0.1          # 428 frames: 14.3 s
        doc["scenes"][0]["keep"][2]["rest_after_s"] = 0.1
        r = build("too-short", doc)
        self.assertEqual(r.returncode, 1)
        self.assertIn("plan refused [E_LENGTH]", r.stderr)
        self.assertEqual(sorted(p.name for p in folder.iterdir() if p.is_file()), [])
        self.assertTrue((folder / "takes").is_dir())               # what the takes were read as stays

    def test_a_mask_that_hides_nothing_stops_the_build(self):
        doc = copy.deepcopy(DOC)
        doc["scenes"][0]["masks"][0]["rect_px"] = [10, 2560, 40, 40]    # the ground under the list
        doc["scenes"][0]["masks"][0]["track"] = {"scroll_px": [330, 2622]}
        r = build("hides-nothing", doc)
        self.assertEqual(r.returncode, 1)
        self.assertIn("mask refused [E_MASK] scene S1, mask 0: the rectangle shows nothing to hide", r.stderr)
        self.assertFalse((WORK / "hides-nothing" / "preview.mp4").exists())

    def test_a_storyboard_that_is_not_one_of_scenes_is_refused(self):
        r = tool("film", "--storyboard", TOOL / "storyboard.json", "--out", WORK / "v1")
        self.assertEqual(r.returncode, 1)
        self.assertIn("storyboard refused [E_STORYBOARD] a storyboard of scenes says \"version\": 2", r.stderr)

    def test_a_take_that_is_not_there_stops_the_build(self):
        doc = copy.deepcopy(DOC)
        doc["scenes"][1]["take"] = "take/nothing.mov"
        r = build("no-take", doc)
        self.assertEqual(r.returncode, 1)
        self.assertIn("scene S2: no such take", r.stderr)


if __name__ == "__main__":
    unittest.main()
