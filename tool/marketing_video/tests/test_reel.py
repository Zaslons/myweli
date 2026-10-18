"""The Reel's checks, watched failing — and passing on a file that is right.

Every file here is written by the App Preview's test writer
(tool/app_store_preview/swift/TestClip.swift), never by the Reel's encoder:
a checker must not be marked by the writer it checks.
"""

from __future__ import annotations

import atexit
import contextlib
import copy
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import reel_draw as rd
import reel_plan as plan
import reel_scenes as rs
import reel_verify as rv
import swifttools

WORK = Path(tempfile.mkdtemp(prefix="reel-tests-"))
atexit.register(shutil.rmtree, WORK, ignore_errors=True)
P = plan.load()


@contextlib.contextmanager
def dies(test: unittest.TestCase, containing: str):
    err = io.StringIO()
    with test.assertRaises(SystemExit) as cm, contextlib.redirect_stderr(err):
        yield
    test.assertEqual(cm.exception.code, 1)
    test.assertIn(containing, err.getvalue())


def clip(name: str, frames: int, every: int = 10, **knobs) -> Path:
    """A 1080 x 1920 film of `frames` frames, a new busy picture every
    `every` frames; right unless a knob says otherwise (TestClip.swift)."""
    folder = WORK / name
    folder.mkdir()
    rng = np.random.default_rng(7)
    files = []
    for k in range(4):
        im = Image.new("RGB", P.size, (250, 250, 250))
        d = ImageDraw.Draw(im)
        for _ in range(300):
            x, y = int(rng.integers(0, 1000)), int(rng.integers(0, 1880))
            d.rectangle((x, y, x + int(rng.integers(8, 80)), y + int(rng.integers(4, 30))), fill=(int(rng.integers(0, 200)),) * 3)
        im.save(folder / f"p{k}.png")
        files.append(f"p{k}.png")
    spec = {"width": P.width, "height": P.height, "timescale": 600, "end": frames * 20,
            # every frame listed (constant rate); the writer re-reads a PNG
            # only when the name changes
            "frames": [{"pts": n * 20, "file": files[(n // every) % 4]} for n in range(frames)],
            "profile": "high41", "bitrate": 3_000_000, "audio": True}
    spec.update(knobs)
    (folder / "clip.json").write_text(json.dumps(spec), encoding="utf-8")
    out = folder / "film.mp4"
    swifttools.run("testclip", folder / "clip.json", "--out", out)
    return out


def failed(checks) -> set[str]:
    return {c.name for c in checks if not c.ok and not c.skipped}


class WrittenFile(unittest.TestCase):
    def test_a_right_file_passes_every_file_check(self):
        checks = rv.file_checks(clip("right", P.frames), P)
        self.assertEqual(failed(checks), set(), "\n".join(c.line() for c in checks))
        self.assertGreaterEqual(len(checks), 20)

    def test_a_short_loud_main_level_file_fails_by_name(self):
        """2 s, a 440 Hz tone, High@4.0: the length, the frame count, the
        silence and the level fail — the size and the frame rate do not."""
        checks = rv.file_checks(clip("wrong", 60, audio={"tone": True}, profile="high40"), P)
        self.assertEqual(failed(checks), {"900 frames", "duration 30.000 s", "sound is silent", "profile and level"})

    def test_a_file_without_a_sound_track_fails(self):
        """What WhatsApp would show as a GIF."""
        checks = rv.file_checks(clip("mute", 60, audio=False), P)
        self.assertIn("tracks", failed(checks))
        self.assertIn("sound track", failed(checks))


class SafeZone(unittest.TestCase):
    FRAMES = (P.cover_frame, 330, 690, P.frames - 1)

    def layout(self) -> dict[int, list]:
        comp = rs.Composer(P)
        return {n: comp.frame(n, dry=True).boxes for n in self.FRAMES}

    def zone(self, layout) -> tuple[bool, bool]:
        checks = {c.name: c for c in rv.plan_checks(P, layout)}
        return checks["text inside the safe zone"].ok, checks["clear of the right-hand rail"].ok

    def test_the_films_own_frames_pass(self):
        self.assertEqual(self.zone(self.layout()), (True, True))

    def test_a_word_moved_below_the_zone_fails(self):
        layout = self.layout()
        box = next(b for b in layout[330] if b.kind == "text")
        moved = copy.copy(box)
        moved.ink = (box.ink[0], 1250.0, box.ink[2], 1290.0)     # y 1250 > the zone's 1248
        layout[330] = layout[330] + [moved]
        self.assertEqual(self.zone(layout)[0], False)

    def test_a_word_in_the_rail_fails(self):
        layout = self.layout()
        box = next(b for b in layout[690] if b.kind == "text")
        moved = copy.copy(box)
        moved.ink, moved.line = (860.0, 1160.0, 1000.0, 1200.0), None   # inside the zone, under the rail
        layout[690] = layout[690] + [moved]
        self.assertEqual(self.zone(layout), (True, False))


class Storyboard(unittest.TestCase):
    def test_a_storyboard_that_no_longer_says_a_transcribed_number_is_refused(self):
        sb = json.loads(plan.STORYBOARD.read_text(encoding="utf-8"))
        s1 = next(s for s in sb["scenes"] if s["id"].startswith("S1-"))
        s1["visual"] = s1["visual"].replace("block top y 316", "block top y 300")
        with dies(self, "block top y 316"):
            plan.Plan(sb)

    def test_the_owners_decisions_stay_out_of_the_tools_copy(self):
        sb = json.loads(plan.STORYBOARD.read_text(encoding="utf-8"))
        sb["_ownerDecisions"] = {"date": "2026-10-18"}
        path = WORK / "sb.json"
        path.write_text(json.dumps(sb), encoding="utf-8")
        with dies(self, "_ownerDecisions"):
            plan.load(path)

    def test_the_words_are_the_storyboards_with_french_spacing(self):
        comp = rs.Composer(P)
        self.assertEqual(comp.words["S1"][1], "encore au carnet ?")
        self.assertEqual(comp.words["S5"][0], "Tarifs, horaires, plan :")
        self.assertEqual(comp.words["S4"][3], "22:41")       # no space before a time's colon

    def test_every_width_the_storyboard_measured_is_the_fonts(self):
        """The storyboard states the widths it measured with the repo's fonts;
        the faces and sizes the tool draws with must give them back (± 1 px).
        A wrong face or weight moves every one of them."""
        comp = rs.Composer(P)
        w = comp.words

        def width(s, spec):
            return rd.font_of(spec).getlength(s)

        cases = [(w["S1"][i], rs.P92, v) for i, v in enumerate(plan.S1["head_widths"])]
        cases += [(w["S1"][2 + i], rs.I48M, v) for i, v in enumerate(plan.S1["widths"])]
        cases += [(w["S6"][2 + i], rs.I48M, v) for i, v in enumerate(plan.S6["widths"])]
        cases += [(w["S6"][7], rs.I48M, plan.S6["squeezed_width"]), (w["S2"][1], rs.P52, plan.S2["tag_width"]),
                  (w["S8"][1], rs.CTA, plan.S8["cta_width"])]
        for key, spec in (("S3", rs.P84), ("S5", rs.P84), ("S7", rs.P84), ("S4", rs.P92), ("S6", rs.P92)):
            cases += [(w[key][i], spec, v) for i, v in enumerate(plan.__dict__[key]["head_widths"])]
        for s, spec, v in cases:
            self.assertAlmostEqual(width(s, spec), v, delta=1.0, msg=s)


if __name__ == "__main__":
    unittest.main()
