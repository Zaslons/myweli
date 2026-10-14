"""The frames of a film of scenes: the framed card's size and place, the
full-bleed capture (never stretched) and its band, the end card, the
dissolve, the timeline."""

from __future__ import annotations

import copy
import unittest
from pathlib import Path
from unittest import mock

import numpy as np
from PIL import Image, ImageDraw

import brand
import frames
import scene_frames
import scenes
from tests.support import dies
from tests.test_scenes import BASE, DISSOLVING, SB2, planned

RAW = (1206, 2622)
POINTS = (402.0, 874.0)
SIZE = (886, 1920)


def load(doc: dict | None = None) -> dict:
    return scenes.load(copy.deepcopy(doc or SB2), BASE)


def ruled() -> Image.Image:
    """A capture with a mid-grey ground, a black disc of radius 300 px at
    its centre and a white line on its middle row."""
    im = Image.new("RGB", RAW, (128, 128, 128))
    d = ImageDraw.Draw(im)
    d.ellipse((603 - 300, 1311 - 300, 603 + 300, 1311 + 300), fill=(0, 0, 0))
    d.rectangle((0, 1310, RAW[0], 1311), fill=(255, 255, 255))
    return im


class Tokens(unittest.TestCase):
    def test_the_band_s_sizes_are_read_from_the_app_s_theme(self):
        self.assertEqual((scene_frames.dimension("spacingM"), scene_frames.dimension("spacingSM"),
                          scene_frames.dimension("radiusXXL")), (16.0, 12.0, 24.0))
        self.assertEqual(scene_frames.text_style("headlineSmall"), (24.0, 32.0))
        self.assertEqual(scene_frames.text_style("bodyLarge"), (16.0, 24.0))
        with dies(self, "no dimension token `spacingHuge`"):
            scene_frames.dimension("spacingHuge")
        with dies(self, "no text style `headlineHuge`"):
            scene_frames.text_style("headlineHuge")

    def test_a_text_style_without_its_size_stops_the_tool(self):
        fake = Path(self.id().replace(".", "_") + ".dart")
        fake.write_text("static const TextStyle odd = TextStyle(\n  fontWeight: FontWeight.w500,\n);\n")
        try:
            with mock.patch.object(scene_frames, "TEXT_STYLES", fake), dies(self, "has no fontSize or height"):
                scene_frames.text_style("odd")
        finally:
            fake.unlink()


class Framed(unittest.TestCase):
    def test_the_card_takes_the_sub_lines_place_and_grows_to_the_stills_margin(self):
        """The stills' card is 644 x 1400 at (121, 440): 53.0 % of the
        frame. Without sub-lines the film's is 711 x 1546 at (87, 293) —
        64.6 % — with the stills' 80-px margin under it, kept within one
        pixel."""
        stills = frames.Layout(SIZE, RAW)
        lay = scene_frames.FramedLayout(SIZE, RAW, 0)
        self.assertEqual((stills.card_w, stills.card_h, stills.card_x, stills.card_y), (644, 1400, 121, 440))
        self.assertEqual((lay.card_w, lay.card_h, lay.card_x, lay.card_y), (711, 1546, 87, 293))
        self.assertEqual(round(lay.share(), 3), 0.646)
        self.assertAlmostEqual(stills.card_w * stills.card_h / (886 * 1920), 0.530, places=3)
        self.assertAlmostEqual(lay.card_h / lay.card_w, RAW[1] / RAW[0], delta=1 / lay.card_w)
        self.assertLessEqual(abs((SIZE[1] - lay.card_y - lay.card_h) - (SIZE[1] - stills.card_y - stills.card_h)), 1)
        self.assertEqual(lay.card_y, round(stills.sub_top))          # where the stills' sub-line starts
        self.assertEqual(lay.card_radius, round(118 * 886 / 1320 * 711 / 644))
        # the mark and the headline stay where the stills have them
        self.assertEqual((lay.mark_top, lay.head_top, lay.head_lh), (stills.mark_top, stills.head_top, stills.head_lh))

    def test_a_film_with_sub_lines_starts_the_card_under_the_longest(self):
        """Under the headline, the stills' gap (38.7 px); a sub-line line
        is the stills' 40.3 px: 293, then 372 under one line, 412 under
        two."""
        cards = [scene_frames.FramedLayout(SIZE, RAW, n) for n in (0, 1, 2)]
        self.assertEqual([c.card_y for c in cards], [293, 372, 412])
        self.assertTrue(cards[0].share() > cards[1].share() > cards[2].share() > 0.53)
        two = cards[2]
        doc = copy.deepcopy(SB2)
        doc["scenes"][1]["subline"] = ["une ligne,", "et une autre."]
        composer = scene_frames.framed_composer(load(doc), RAW, POINTS)
        self.assertEqual(composer.lay.card_y, two.card_y)
        for s in load(doc)["scenes"]:
            self.assertLess(composer.text_bottom({"headline": s["headline"], "subline": s["subline"]}),
                            composer.lay.card_y)

    def test_a_card_with_no_room_left_stops_the_tool(self):
        with dies(self, "the framed card has no room under 40 line(s) of sub-line"):
            scene_frames.FramedLayout(SIZE, RAW, 40)

    def test_the_paper_above_the_card_is_the_stills(self):
        """Mark and headline drawn by the stills' own calls: the rows above
        the card's shadow are the stills' frame's, pixel for pixel."""
        sb = load()
        composer = scene_frames.framed_composer(sb, RAW, POINTS)
        raw = Image.new("RGB", RAW, (200, 200, 200))
        film = np.asarray(composer.frame(composer.under("S1"), composer.card(raw)))
        # the stills always have a sub-line; it starts at their row 293 — the film's card's
        caption = {"headline": sb["scenes"][0]["headline"], "subline": ["sous-titre"]}
        still = np.asarray(brand.stills.frame(caption, raw, SIZE, brand.stills.tokens()))
        rows = composer.lay.card_y - 40
        self.assertTrue(np.array_equal(film[:rows], still[:rows]))
        self.assertGreater(int((film[:rows] < 100).sum()), 1000)     # there is ink there to compare

    def test_a_framed_touch_point_scales_with_the_card(self):
        composer = scene_frames.framed_composer(load(), RAW, POINTS)
        self.assertAlmostEqual(composer.pt, 711 / 402)


class FullBleed(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sb = load()
        cls.fb = scene_frames.FullBleed(cls.sb, RAW, POINTS)

    def test_the_capture_fills_the_frame_scaled_alike_both_ways(self):
        """886/1206 in both directions; the 8.5 rows the frame's shape has
        no room for are cut equally from the top and the bottom. The disc
        stays round and the middle row stays in the middle."""
        fb = self.fb
        self.assertAlmostEqual(fb.scale, 886 / 1206)
        self.assertAlmostEqual(fb.rows, 1920 * 1206 / 886)
        self.assertAlmostEqual(fb.y0, (2622 - 1920 * 1206 / 886) / 2)
        self.assertAlmostEqual(fb.y0, 4.273, places=3)
        out = np.asarray(fb.card(ruled()))
        self.assertEqual(out.shape, (1920, 886, 3))
        dark = out.mean(axis=2) < 64
        rows, cols = np.nonzero(dark)
        height, width = rows.max() - rows.min() + 1, cols.max() - cols.min() + 1
        self.assertLessEqual(abs(height - width), 2)                       # round, not stretched
        self.assertLessEqual(abs(width - 600 * 886 / 1206), 2)
        bright = np.nonzero(out[:, 20].mean(axis=1) > 192)[0]
        self.assertTrue(959 <= bright.mean() <= 960.5, bright)            # the middle row, in the middle

    def test_a_touch_point_lands_where_the_finger_did(self):
        """A point at (201, 437) pt — the screen's centre — darkens the
        frame's centre."""
        card = self.fb.card(Image.new("RGB", RAW, (255, 255, 255)))
        before = np.asarray(card).copy()
        self.fb.draw_touch(card, 201, 437, 1.0, "dark")
        after = np.asarray(card)
        changed = np.nonzero((np.abs(after.astype(int) - before).sum(axis=2)) > 0)
        cy, cx = changed[0].mean(), changed[1].mean()
        self.assertLess(abs(cx - 443), 1.0)
        self.assertLess(abs(cy - 960), 1.0)
        radius = (changed[1].max() - changed[1].min()) / 2
        self.assertLess(abs(radius - 24 * 886 / 402), 2.5)

    def test_the_band_is_brand_black_with_white_text_under_the_status_bar(self):
        layer, box = self.fb.band(self.sb["scenes"][0])
        x0, y0, x1, y1 = self.fb.band_points(self.sb["scenes"][0])
        self.assertAlmostEqual(y0, 62, delta=0.5)                           # band.top_pt
        self.assertAlmostEqual(x0, 16, delta=0.5)                           # spacingM
        self.assertAlmostEqual(x1, 402 - 16, delta=0.5)
        a = np.asarray(layer)
        self.assertEqual(tuple(a[box[1] + 5, (box[0] + box[2]) // 2]), (0, 0, 0, 255))   # primary, opaque
        inside = a[box[1]:box[3], box[0]:box[2]]
        self.assertGreater(int(((inside[..., :3] == 255).all(axis=2)).sum()), 300)       # secondary: the words
        self.assertEqual(int(a[:box[1] - 1, :, 3].max()), 0)                # nothing above it
        self.assertEqual(int(a[box[3] + 1:, :, 3].max()), 0)                # nor under it

    def test_a_band_at_the_bottom_sits_above_the_home_indicator(self):
        sb = load(dict(SB2, scenes=[dict(SB2["scenes"][0], band="bottom"), SB2["scenes"][1]]))
        fb = scene_frames.FullBleed(sb, RAW, POINTS)
        _, y0, _, y1 = fb.band_points(sb["scenes"][0])
        self.assertAlmostEqual(y1, 874 - 34, delta=0.5)
        self.assertGreater(y0, 700)

    def test_two_lines_of_headline_and_a_sub_line_fit_or_stop_the_tool(self):
        sb = load(dict(SB2, scenes=[dict(SB2["scenes"][0], headline=["Une cliente arrive ?", "Un geste suffit."],
                                         subline=["Une ligne dessous."]), SB2["scenes"][1]]))
        fb = scene_frames.FullBleed(sb, RAW, POINTS)
        one = scene_frames.FullBleed(load(), RAW, POINTS).band(load()["scenes"][0])[1]
        two = fb.band(sb["scenes"][0])[1]
        self.assertGreater(two[3] - two[1], one[3] - one[1] + 30)
        for scene, words in ((dict(SB2["scenes"][0], headline=["W" * 40, "x"]), "does not fit the band"),
                             (dict(SB2["scenes"][0], subline=["W" * 60]), "a sub-line is wider than the band")):
            sb = load(dict(SB2, scenes=[scene, SB2["scenes"][1]]))
            with dies(self, words):
                scene_frames.FullBleed(sb, RAW, POINTS).band(sb["scenes"][0])

    def test_a_long_headline_is_set_smaller_down_to_title_large(self):
        """« Ajoutez un rendez-vous. » fits at `headlineSmall`; a line a
        little too long for it is set a point smaller — never under
        `titleLarge`."""
        long = "Ajoutez vite un rendez-vous."
        sb = load(dict(SB2, scenes=[dict(SB2["scenes"][0], headline=["Un créneau libre ?", long]),
                                    SB2["scenes"][1]]))
        fb = scene_frames.FullBleed(sb, RAW, POINTS)
        layer, box = fb.band(sb["scenes"][0])
        self.assertLess(box[2] - box[0], 886)

    def test_a_capture_of_another_size_stops_the_tool(self):
        with dies(self, "a capture is 1200x2622"):
            self.fb.card(Image.new("RGB", (1200, 2622)))

    def test_a_capture_too_wide_for_the_frames_shape_stops_the_tool(self):
        """Filled by width, a 1206 x 2000 screen covers 1469 of the frame's
        1920 rows: it would have to be stretched, and is refused."""
        with dies(self, "a 1206x2000 capture is too short to fill 886x1920"):
            scene_frames.FullBleed(self.sb, (1206, 2000), (402.0, 2000 / 3))

    def test_the_bands_in_points_for_the_check(self):
        bands = scene_frames.band_points(self.sb, RAW, POINTS)
        self.assertEqual(sorted(bands), ["S1", "S2"])
        self.assertTrue(all(b[1] < b[3] for b in bands.values()))


class EndCard(unittest.TestCase):
    def test_mark_title_and_disclosure_on_the_paper(self):
        sb = load()
        im = np.asarray(scene_frames.end_card(sb)).astype(int)
        c = brand.colours()
        self.assertEqual(tuple(im[5, 5]), c["surface"])
        self.assertEqual(tuple(im[-5, -5]), c["surface"])
        ink = np.nonzero((np.abs(im - np.array(c["surface"])).sum(axis=2)) > 60)[0]
        top, bottom = ink.min(), ink.max()
        self.assertLess(abs((top + bottom) / 2 - 960), 4)                  # the group is centred
        # the line is in textSecondary: the darkest pixels of its lowest rows are that grey
        line_rows = im[bottom - 20:bottom + 1]
        darkest = line_rows.reshape(-1, 3)[np.argmin(line_rows.reshape(-1, 3).sum(axis=1))]
        self.assertLessEqual(np.abs(darkest - np.array(c["textSecondary"])).max(), 2)
        # the title, above it, is in textPrimary
        title_rows = im[top + 150:bottom - 40]
        darkest = title_rows.reshape(-1, 3)[np.argmin(title_rows.reshape(-1, 3).sum(axis=1))]
        self.assertLessEqual(np.abs(darkest - np.array(c["textPrimary"])).max(), 2)

    def test_a_title_or_line_wider_than_its_column_stops_the_tool(self):
        for change in ({"title": "MyWeli Pro " * 4}, {"line": "Un compte MyWeli Pro est nécessaire. " * 3}):
            with dies(self, "is wider than its column"):
                scene_frames.end_card(load(dict(SB2, end_card={**SB2["end_card"], **change})))


class Dissolve(unittest.TestCase):
    def test_the_ends_are_the_two_pictures_and_the_middle_is_between(self):
        a, b = Image.new("RGB", (4, 4), (0, 0, 0)), Image.new("RGB", (4, 4), (200, 100, 50))
        self.assertIs(scene_frames.blend(a, b, 0), a)
        self.assertIs(scene_frames.blend(a, b, 1), b)
        self.assertEqual(scene_frames.blend(a, b, 0.5).getpixel((1, 1)), (100, 50, 25))

    def test_the_timeline_names_every_frame(self):
        plan, sb, _ = planned(DISSOLVING)
        tl = scene_frames.timeline(plan)
        kinds = [f[0] for f in tl]
        self.assertEqual(len(tl), scenes.places(plan)[3])
        self.assertEqual((kinds.count("pic"), kinds.count("in"), kinds.count("join"), kinds.count("end")),
                         (166 + 239, 5, 5, 66))
        self.assertEqual(tl[166], ("in", 0, 166, 0, 5))
        self.assertEqual(tl[171], ("pic", 0, 171, 166))
        self.assertEqual(tl[410], ("join", 0, 0, 5))
        self.assertEqual(tl[-1], ("end", 65))


class Compose(unittest.TestCase):
    """compose_film on pictures drawn here: S1 a white screen, S2 a grey
    one with a line of words; tests/test_scenes.py's plan (S1 226 frames,
    a join of 5, S2 176, a join of 5, the end card 66)."""

    @classmethod
    def setUpClass(cls):
        import masks
        import tempfile
        cls.work = Path(tempfile.mkdtemp(prefix="preview-compose-"))
        cls.plan, cls.sb, _ = planned()
        white = Image.new("RGB", RAW, (255, 255, 255))
        grey = Image.new("RGB", RAW, (200, 200, 200))
        ImageDraw.Draw(grey).rectangle((100, 1000, 700, 1040), fill=(20, 20, 20))
        cls.data = {}
        for sid, picture, j in (("S1", white, 7), ("S2", grey, 9)):
            src = cls.work / sid
            src.mkdir()
            picture.save(src / f"src_{j:06d}.png")
            count = sum(n for kind, _, n in scenes.scene_layout(next(s for s in cls.plan["scenes"] if s["id"] == sid))
                        if kind == "run")
            cls.data[sid] = {"manifest": {"width": RAW[0], "height": RAW[1], "film": [j] * count,
                                          "sources": {str(j): {"pts": 0, "file": f"src_{j:06d}.png"}}},
                             "src": src, "masks": {}, "take_T": 600}
        cls.data["S2"]["masks"] = {9: [masks.OnPicture((90, 990, 710, 1050), "fill", (200, 200, 200), 0, 0.0)]}
        cls.made = scene_frames.compose_film(cls.sb, cls.plan, cls.data, cls.work / "frames", POINTS)
        cls.names = __import__("json").loads((cls.work / "frames" / "frames.json").read_text())["frames"]

    @classmethod
    def tearDownClass(cls):
        import shutil
        shutil.rmtree(cls.work, ignore_errors=True)

    def frame(self, n: int) -> np.ndarray:
        return np.asarray(Image.open(self.work / "frames" / self.names[n])).astype(int)

    def test_every_frame_of_the_plan_is_written(self):
        self.assertEqual(len(self.names), 478)
        self.assertEqual(self.made["frames"], 478)
        self.assertEqual(self.made["card"], {"x": 87, "y": 293, "w": 711, "h": 1546, "share": 0.6462})
        self.assertEqual(len(set(self.names[412:])), 1)                     # the end card, one picture
        self.assertTrue(np.array_equal(self.frame(477), np.asarray(scene_frames.end_card(self.sb)).astype(int)))

    def test_a_join_is_every_pixel_on_the_tokens_curve(self):
        """Frame 226 + i is the last of S1 and the first of S2, mixed at
        `base` (easeInOut, 200 ms) after (i + 1) / 30 s."""
        a, b = self.frame(225).astype(float), self.frame(231).astype(float)
        base = brand.motion("base")
        for i in range(5):
            k = base.at((i + 1) / 30)
            self.assertLessEqual(np.abs(self.frame(226 + i) - np.rint(a + (b - a) * k)).max(), 1, i)
        self.assertNotEqual(self.names[226], self.names[225])

    def test_the_mask_covers_its_box_on_every_frame_of_its_picture(self):
        regions = self.made["regions"]
        frames_masked = sorted({r["frame"] for r in regions})
        # S2's 176 frames and the two joins that blend with it
        self.assertEqual(frames_masked, list(range(226, 231)) + list(range(231, 407)) + list(range(407, 412)))
        lay = scene_frames.framed_composer(self.sb, RAW, POINTS).lay
        on = self.frame(300)
        y = lay.card_y + round(1020 * lay.card_h / RAW[1])
        x = lay.card_x + round(400 * lay.card_w / RAW[0])
        self.assertEqual(tuple(on[y, x]), (200, 200, 200))                  # the words are gone
        with Image.open(self.work / "frames" / regions[10]["original"]) as o:
            self.assertLess(np.asarray(o).min(), 60)                        # they were there

    def test_a_touch_that_lands_on_the_wrong_ground_stops_the_tool(self):
        doc = copy.deepcopy(SB2)
        doc["scenes"][0]["keep"][0]["ground"] = "dark"
        plan, sb, _ = planned(doc)
        with dies(self, "the touch of `S1/tap-a` lands on a light ground at (100, 300) pt"):
            scene_frames.compose_film(sb, plan, self.data, self.work / "wrong", POINTS)


if __name__ == "__main__":
    unittest.main()
