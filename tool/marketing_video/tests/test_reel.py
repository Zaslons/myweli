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
import reel_footage as rf
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


class Motion(unittest.TestCase):
    """R1's and A1's checks, watched failing on a layout made wrong on
    purpose — and passing on the film's own."""

    def layout(self, frames) -> dict[int, list]:
        comp = rs.Composer(P)
        return {n: comp.frame(n, dry=True).boxes for n in frames}

    def checks(self, layout) -> dict:
        return {c.name: c for c in rv.motion_checks(P, layout)}

    def test_the_films_own_motion_passes(self):
        layout = self.layout(range(0, P.frames))
        self.assertEqual([c.name for c in self.checks(layout).values() if not c.ok], [])

    def test_two_bubbles_drawn_over_each_other_fail(self):
        """The first render's fault: a new bubble in the slot the older one
        was still leaving."""
        layout = self.layout(range(309, 316))
        bubbles = [b for b in layout[312] if b.kind == "shape" and b.label.startswith("S4 bubble")]
        moved = copy.copy(bubbles[1])
        moved.full = moved.ink = (90.0, bubbles[0].ink[3] - 30, 800.0, bubbles[0].ink[3] + 86)
        layout[312] = layout[312] + [moved]
        self.assertFalse(self.checks(layout)["S4 bubbles never overlap"].ok)

    def test_a_card_that_jumps_fails(self):
        """The first render's S7 entrance: 725 px in one frame."""
        layout = self.layout(range(608, 620))
        card = next(b for b in layout[610] if b.kind == "card")
        jumped = copy.copy(card)
        jumped.full = jumped.ink = (card.ink[0], card.ink[1] + 500, card.ink[2], card.ink[3] + 500)
        layout[610] = [b for b in layout[610] if b.kind != "card"] + [jumped]
        self.assertFalse(self.checks(layout)["cards move at most 410 px a frame"].ok)

    def test_a_picture_enlarged_past_its_push_in_fails(self):
        layout = self.layout(range(0, 3))
        photo = next(b for b in layout[1] if b.kind == "photo")
        big = copy.copy(photo)
        big.data = dict(photo.data, scale=photo.data["base"] * 1.10)
        layout[1] = [b for b in layout[1] if b.kind != "photo"] + [big]
        self.assertFalse(self.checks(layout)["pictures enlarged only as needed"].ok)

    def test_a_picture_that_does_not_fill_the_width_fails(self):
        layout = self.layout(range(0, 3))
        photo = next(b for b in layout[2] if b.kind == "photo")
        narrow = copy.copy(photo)
        narrow.full = narrow.ink = (20.0, photo.ink[1], photo.ink[2], photo.ink[3])
        layout[2] = [b for b in layout[2] if b.kind != "photo"] + [narrow]
        self.assertFalse(self.checks(layout)["pictures enlarged only as needed"].ok)

    def reading(self):
        layout = self.layout((P.cover_frame, P.frames - 1))
        return next(c for c in rv.plan_checks(P, layout) if c.name == "reading time")

    def test_every_line_meets_the_reading_rule_with_no_exception(self):
        """R2: S7b's caption has the 2.63 s its 32 characters need — and
        A1's 2.0-s beat, the second render's, now fails like any short line."""
        cap = next(r for r in rs.Composer(P).reading_windows() if r["label"] == "S7b caption")
        self.assertEqual((cap["chars"], round(cap["on"], 2)), (32, 2.63))
        check = self.reading()
        self.assertTrue(check.ok, check.seen)
        original = plan.S7B["in"]
        try:
            plan.S7B["in"] = 25.0            # A1's beat, 25.00–27.00
            check = self.reading()
            self.assertFalse(check.ok)
            self.assertIn("S7b caption 2.00 s, needs 2.63", check.seen)
        finally:
            plan.S7B["in"] = original

    def test_a_card_in_s2s_clear_space_fails(self):
        """R2: the card waits for the lockup to leave; entering at 6.00 s
        (the second render's timing) it reaches the tagline's line at frame
        183, while the lockup still shows."""
        frames = range(178, 196)
        check = self.checks(self.layout(frames))["S2's clear space kept"]
        self.assertTrue(check.ok, check.seen)
        original = plan.S3["enter"]
        try:
            plan.S3["enter"] = 6.00
            check = self.checks(self.layout(frames))["S2's clear space kept"]
            self.assertFalse(check.ok)
            self.assertIn("first: frame 183", check.seen)
        finally:
            plan.S3["enter"] = original

    def test_an_arriving_bubble_is_never_more_opaque_than_what_shows_of_it(self):
        """R2: a bubble rising out of the column's edge (y 1152) fades with
        the share of it above the edge — no half-sliced line at full white."""
        edge = plan.S4["column_bottom"]
        sliced = 0
        for n, boxes in self.layout(range(309, 336)).items():
            for b in boxes:
                if b.kind == "shape" and b.label.startswith("S4 bubble") and b.full[3] > edge:
                    share = (edge - b.full[1]) / (b.full[3] - b.full[1])
                    self.assertLessEqual(b.alpha, share + 1e-6, (n, b.label))
                    sliced += 1
        self.assertGreater(sliced, 0)

    def test_every_strike_starts_as_a_short_stroke_never_a_dot(self):
        pts = rd.drawn_line(180, 804, 836, 0.0, plan.STRIKE_MIN * 7)
        self.assertAlmostEqual(pts[-1][0] - pts[0][0], 28.0)
        pts = rd.drawn_line(779, 863, 788, 0.0, plan.STRIKE_MIN * 7)
        self.assertAlmostEqual(pts[-1][0] - pts[0][0], 28.0)
        self.assertEqual(rd.drawn_line(65, 1015, 952, 1.0, 32)[-1], (1015, 952))


class PhoneRowMask(unittest.TestCase):
    """A2: take5b's phone row is painted out on every picture of the page's
    own scroll, at the rest picture's rectangle moved by the take's scroll
    map and cut at the bar — refused when the map puts it off the row, or
    puts the page anywhere but where it is."""

    def pictures(self) -> tuple[dict, Path]:
        folder = WORK / "take5b-masks"
        folder.mkdir(exist_ok=True)
        x, y, w, h = plan.S5["mask"]
        bar = plan.S5["bar_top"]
        rng = np.random.default_rng(3)
        page = np.full((3400, 1206), 255, np.uint8)                      # the page, scrolled by each picture
        page[y + 7:y + h - 7, x + 10:x + w - 10] = rng.integers(0, 120, (h - 14, w - 20))   # the phone row
        for top in (1400, 1900):                                         # other content, clear of the row's ring
            page[top:top + 300:6, 80:1120] = rng.integers(0, 200, (50, 1040))
        sources = {}
        # the rest picture, one 10 pt (30 px) lower, one with the row under the bar
        for j, (lower, pts) in enumerate(((0, 17100), (30, 16000), (600, 15000))):
            a = np.full((2622, 1206), 255, np.uint8)
            a[lower:] = page[:2622 - lower]
            a[bar:] = 247                                                # the opaque bar
            Image.fromarray(a, "L").convert("RGB").save(folder / f"p{j}.png")
            sources[str(j)] = {"file": f"p{j}.png", "pts": pts}
        return {"film": [2, 1, 0], "sources": sources}, folder        # the list ends on the rest picture

    MAP = [(15000 / 600, 87.3), (16000 / 600, 277.3), (17100 / 600, 287.3)]

    def test_the_rectangle_follows_the_scroll_and_stops_at_the_bar(self):
        manifest, folder = self.pictures()
        x, y, w, h = plan.S5["mask"]
        self.assertEqual(rf.take5b_masks(manifest, folder, self.MAP), [None, [x, y + 30, w, h], [x, y, w, h]])

    def test_a_rectangle_off_the_row_is_refused(self):
        """A picture whose row is not where its scroll puts it (moved 30 px
        on purpose, the page around it left in place)."""
        manifest, folder = self.pictures()
        x, y, w, h = plan.S5["mask"]
        a = np.asarray(Image.open(folder / "p1.png").convert("L")).copy()
        row = a[y + 30:y + 30 + h].copy()
        a[y + 30:y + 30 + h] = 255
        a[y + 60:y + 60 + h] = row
        Image.fromarray(a, "L").convert("RGB").save(folder / "p1.png")
        with dies(self, "not where its scroll"):
            rf.take5b_masks(manifest, folder, self.MAP)

    def test_a_scroll_map_off_where_the_row_is_under_the_bar_is_refused(self):
        """The map is checked on every picture, not only where the row shows."""
        manifest, folder = self.pictures()
        wrong = [(15000 / 600, 85.3), self.MAP[1], self.MAP[2]]       # 2 pt (6 px) off
        with dies(self, "its page is not where the scroll map"):
            rf.take5b_masks(manifest, folder, wrong)


class Storyboard(unittest.TestCase):
    def test_a_storyboard_that_no_longer_says_a_transcribed_number_is_refused(self):
        sb = json.loads(plan.STORYBOARD.read_text(encoding="utf-8"))
        s1 = next(s for s in sb["scenes"] if s["id"].startswith("S1-"))
        s1["visual"] = s1["visual"].replace("block top y 280", "block top y 300")
        with dies(self, "block top y 280"):
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
        self.assertEqual(comp.words["S5"][0], "Photos, tarifs, horaires :")
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
        cases += [(w["S7b"][i], rs.P92, v) for i, v in enumerate(plan.S7B["head_widths"])]
        cases += [(w["S6"][2 + i], rs.I48M, v) for i, v in enumerate(plan.S6["widths"])]
        cases += [(w["S6"][7], rs.I48M, plan.S6["squeezed_width"]), (w["S2"][1], rs.P52, plan.S2["tag_width"]),
                  (w["S8"][1], rs.CTA, plan.S8["cta_width"])]
        for key, spec in (("S3", rs.P84), ("S5", rs.P78), ("S7", rs.P84), ("S4", rs.P92), ("S6", rs.P92)):
            cases += [(w[key][i], spec, v) for i, v in enumerate(plan.__dict__[key]["head_widths"])]
        for s, spec, v in cases:
            self.assertAlmostEqual(width(s, spec), v, delta=1.0, msg=s)


if __name__ == "__main__":
    unittest.main()
