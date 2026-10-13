"""The frame: the stills' own, at 886 x 1920; captions in their column and
above the capture; the cross-fade and the touch point, by the tokens."""

from __future__ import annotations

import copy
import unittest

import numpy as np
from PIL import Image

import brand
import frames
from tests.support import STORYBOARD, dies

RAW = (1206, 2622)
POINTS = (402.0, 874.0)
SIZE = (886, 1920)


def capture(seed: int = 7) -> Image.Image:
    """A capture-sized picture with detail right up to its corners, so the
    card's mask and border are exercised."""
    rng = np.random.default_rng(seed)
    a = rng.integers(0, 256, (RAW[1] // 6, RAW[0] // 6, 3), dtype=np.uint8)
    return Image.fromarray(a, "RGB").resize(RAW, Image.NEAREST)


class Frame(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.composer = frames.Composer(STORYBOARD, RAW, POINTS)
        cls.raw = capture()

    def test_the_layout_is_the_stills_table_times_886_over_1320(self):
        lay = self.composer.lay
        self.assertEqual(lay.s, 886 / 1320)
        self.assertEqual((lay.card_x, lay.card_y, lay.card_w, lay.card_h), (121, 440, 644, 1400))
        self.assertEqual((lay.mark_h, lay.mark_top, lay.card_radius, lay.card_border), (43, 48, 79, 2))
        self.assertEqual((lay.sub_px, lay.head_lh), (30, 68))

    def test_a_film_frame_is_the_stills_frame(self):
        """Pixel for pixel: what compose.py of the stills draws at 886 x 1920
        for the same caption and the same capture."""
        for cid in ("comptoir", "agenda"):
            caption = STORYBOARD["captions"][cid]
            still = brand.stills.frame(caption, self.raw, SIZE, brand.stills.tokens())
            film = self.composer.frame(self.composer.under(cid), self.composer.card(self.raw))
            self.assertEqual(film.size, SIZE)
            self.assertEqual(film.mode, "RGB")
            self.assertTrue(np.array_equal(np.asarray(film), np.asarray(still)), cid)

    def test_a_caption_without_a_subline_leaves_its_band_as_paper(self):
        lay, c = self.composer.lay, self.composer.c
        with_sub = np.asarray(self.composer.under("comptoir"))
        without = np.asarray(self.composer.under("creneau"))
        top, bottom = round(lay.sub_top), lay.card_y - 60  # above the card's shadow
        self.assertTrue((without[top:bottom] == np.array(c["surface"])).all())
        self.assertFalse((with_sub[top:bottom] == np.array(c["surface"])).all())
        # same headline, so everything above the sub-line is identical
        self.assertTrue(np.array_equal(with_sub[:top], without[:top]))

    def test_every_caption_fits_its_column_and_stays_above_the_capture(self):
        lay = self.composer.lay
        for cid, caption in STORYBOARD["captions"].items():
            head, sub, lines = self.composer.caption_fonts(caption)
            self.assertEqual(len(caption["headline"]), 2, cid)
            for t in caption["headline"]:
                self.assertLessEqual(head.getlength(t), lay.head_col, f"{cid}: {t}")
            for t in lines:
                self.assertLessEqual(sub.getlength(t), lay.sub_col, f"{cid}: {t}")
            self.assertLess(self.composer.text_bottom(caption), lay.card_y, cid)

    def test_a_headline_too_wide_for_its_column_stops_the_tool(self):
        sb = copy.deepcopy(STORYBOARD)
        sb["captions"]["arrivee"]["headline"][1] = "Un geste suffit, vraiment un seul geste et rien d’autre."
        with dies(self, "headline does not fit"):
            frames.Composer(sb, RAW, POINTS).under("arrivee")

    def test_a_subline_too_wide_for_its_column_stops_the_tool(self):
        sb = copy.deepcopy(STORYBOARD)
        sb["captions"]["agenda"]["subline"] = ["Un compte MyWeli Pro est nécessaire pour utiliser cette application."]
        with dies(self, "subline line wider"):
            frames.Composer(sb, RAW, POINTS).under("agenda")

    def test_a_character_the_font_lacks_stops_the_tool(self):
        sb = copy.deepcopy(STORYBOARD)
        sb["captions"]["arrivee"]["headline"][0] = "Une cliente 到 ?"
        with dies(self, "no glyph for '到'"):
            frames.Composer(sb, RAW, POINTS).under("arrivee")

    def test_the_narrow_space_before_a_question_mark_is_a_real_glyph(self):
        self.assertIn(" ?", STORYBOARD["captions"]["arrivee"]["headline"][0])
        self.composer.under("arrivee")  # would stop on a missing glyph

    def test_an_unknown_caption_stops_the_tool(self):
        with dies(self, "no caption `nope`"):
            self.composer.under("nope")


class Guards(unittest.TestCase):
    def test_a_caption_that_reaches_the_capture_stops_the_tool(self):
        composer = frames.Composer(STORYBOARD, RAW, POINTS)
        composer.lay.card_y = 330          # as if the card sat higher than the stills put it
        with dies(self, "caption `comptoir` reaches the capture"):
            composer.under("comptoir")

    def test_a_capture_that_is_not_the_logged_screen_stops_the_tool(self):
        with dies(self, "a 1206x2622 capture is not 400x874 points"):
            frames.Composer(STORYBOARD, RAW, (400.0, 874.0))

    def test_a_capture_of_another_size_stops_the_tool(self):
        composer = frames.Composer(STORYBOARD, RAW, POINTS)
        with dies(self, "a capture is 1200x2622, expected 1206x2622"):
            composer.card(Image.new("RGB", (1200, 2622)))

    def test_a_missing_font_stops_the_tool(self):
        from pathlib import Path
        from unittest import mock
        with mock.patch.object(brand.stills, "POPPINS", Path("/nowhere/Poppins-Medium.ttf")), \
                dies(self, "missing /nowhere/Poppins-Medium.ttf"):
            frames.Composer(STORYBOARD, RAW, POINTS)

    def test_a_card_that_would_leave_the_canvas_stops_the_tool(self):
        with dies(self, "the card overflows the canvas at 886x1700"):
            frames.Layout((886, 1700), RAW)

    def test_compose_stops_when_the_two_frame_hold_lists_differ(self):
        import json
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as tmp:
            src = Path(tmp)
            (src / "manifest.json").write_text(json.dumps(
                {"film": [0, 0, 1], "width": RAW[0], "height": RAW[1], "sources": {}}))
            with dies(self, "disagree on which source frame each film frame shows"):
                frames.compose(STORYBOARD, {"timescale": 600, "captions": [], "touches": []}, [0, 1, 1],
                               src, src / "out", POINTS)


class CrossFade(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.composer = frames.Composer(STORYBOARD, RAW, POINTS)
        cls.captions = [{"frame": 0, "caption": "creneau"}, {"frame": 90, "caption": "comptoir"}]

    def test_progress_follows_the_token_by_time(self):
        state = self.composer.caption_state
        self.assertEqual(state(self.captions, 0), ("creneau", "creneau", 1.0))
        self.assertEqual(state(self.captions, 89), ("creneau", "creneau", 1.0))
        self.assertEqual(state(self.captions, 90), ("creneau", "comptoir", 0.0))
        # `base` is 200 ms on easeInOut: 3 frames in is half-way in time, and
        # easeInOut(0.5) is exactly 0.5
        self.assertEqual(state(self.captions, 93), ("creneau", "comptoir", 0.5))
        self.assertEqual(state(self.captions, 96), ("creneau", "comptoir", 1.0))
        self.assertEqual(state(self.captions, 400), ("creneau", "comptoir", 1.0))
        early, late = state(self.captions, 91)[2], state(self.captions, 95)[2]
        self.assertAlmostEqual(early + late, 1.0, places=2)  # easeInOut is symmetric
        self.assertLess(early, 1 / 6)                        # …and it eases in

    def test_the_ends_are_the_two_captions_and_the_middle_is_between(self):
        a = np.asarray(self.composer.under("creneau")).astype(int)
        b = np.asarray(self.composer.under("comptoir")).astype(int)
        self.assertIs(self.composer.paper("creneau", "comptoir", 0.0), self.composer.under("creneau"))
        self.assertIs(self.composer.paper("creneau", "comptoir", 1.0), self.composer.under("comptoir"))
        mid = np.asarray(self.composer.paper("creneau", "comptoir", 0.5)).astype(int)
        changed = (a != b).any(axis=2)
        self.assertGreater(int(changed.sum()), 1000)
        self.assertTrue((np.abs(mid - (a + b) / 2) <= 0.5).all())

    def test_what_does_not_change_does_not_flicker(self):
        """The headline is the same in both captions: no pixel of it moves at
        any point of the fade."""
        a = np.asarray(self.composer.under("creneau"))
        b = np.asarray(self.composer.under("comptoir"))
        same = (a == b).all(axis=2)
        for k in (0.07, 0.37, 0.5, 0.93):
            mid = np.asarray(self.composer.paper("creneau", "comptoir", k))
            self.assertTrue(np.array_equal(mid[same], a[same]), k)


class Touch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.composer = frames.Composer(STORYBOARD, RAW, POINTS)
        cls.T = 600

    def test_a_tap_fades_in_holds_and_fades_out_by_the_tokens(self):
        tap = {"gesture": "t", "kind": "tap", "down": 600, "up": 780, "path": [[600, 100.0, 200.0]]}
        state = lambda n: self.composer.touch_state(tap, n, self.T)  # noqa: E731
        self.assertIsNone(state(29))
        self.assertIsNone(state(30))                      # the instant it lands: nothing yet
        x, y, alpha = state(31)                           # 33 ms into `fast` (100 ms, easeOut)
        self.assertEqual((x, y), (100.0, 200.0))
        self.assertEqual(alpha, brand.cubic(brand.CUBICS["easeOut"], 1 / 3))
        self.assertEqual(state(33)[2], 1.0)               # 100 ms: fully there
        self.assertEqual(state(38)[2], 1.0)
        self.assertEqual(state(39)[2], 1.0)               # leaves at 780 ticks = frame 39
        self.assertEqual(state(42)[2], 1 - brand.cubic(brand.CUBICS["easeInOut"], 0.5))  # 100 of 200 ms
        self.assertIsNone(state(45))                      # 200 ms after it left: gone
        self.assertIsNone(state(200))

    def test_a_drag_follows_the_finger_one_to_one(self):
        drag = {"gesture": "d", "kind": "drag", "down": 1200, "up": 1680,
                "path": [[1200, 40.0, 300.0], [1560, 220.0, 300.0], [1680, 220.0, 300.0]]}
        state = lambda n: self.composer.touch_state(drag, n, self.T)  # noqa: E731
        self.assertEqual(state(69)[:2], (130.0, 300.0))   # 300 of 600 ms: half-way
        self.assertEqual(state(63)[:2], (40.0 + 180.0 * 60 / 360, 300.0))
        self.assertEqual(state(78)[:2], (220.0, 300.0))   # arrived
        self.assertEqual(state(83)[:2], (220.0, 300.0))   # resting, still down
        self.assertEqual(state(83)[2], 1.0)
        self.assertLess(state(86)[2], 1.0)                # lifted at frame 84
        self.assertIsNone(state(90))

    def test_the_disc_is_the_brand_black_at_low_opacity_with_a_ring(self):
        c, t = self.composer.c, STORYBOARD["touch"]
        card = Image.new("RGB", (self.composer.lay.card_w, self.composer.lay.card_h), (255, 255, 255))
        self.composer.draw_touch(card, 200.0, 400.0, 1.0, "dark")
        a = np.asarray(card).astype(float)
        pt = self.composer.pt
        cx, cy, r = round(200 * pt), round(400 * pt), t["diameter_pt"] / 2 * pt
        fill = 255 + (c["primary"][0] - 255) * t["fill_opacity"]
        self.assertAlmostEqual(a[cy, cx, 0], fill, delta=1.0)
        ring = a[cy, round(cx + r - t["ring_pt"] * pt / 2), 0]
        self.assertLess(ring, fill - 40)                  # the ring is clearly darker than the fill
        self.assertAlmostEqual(ring, 255 + (c["primary"][0] - 255) * t["ring_opacity"], delta=12)
        yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
        outside = np.hypot(xx - 200 * pt, yy - 400 * pt) > r + 1.5
        self.assertTrue((a[outside] == 255).all())        # nothing beyond the disc
        self.assertEqual(round(2 * r), round(48 * 644 / 402))

    def test_light_on_a_dark_or_green_fill(self):
        lay = self.composer.lay
        green = Image.new("RGB", (lay.card_w, lay.card_h), (0x2D, 0x50, 0x16))   # the app's `success`
        white = Image.new("RGB", (lay.card_w, lay.card_h), (255, 255, 255))
        black = Image.new("RGB", (lay.card_w, lay.card_h), (0, 0, 0))
        self.assertEqual(self.composer.tone(green, 200, 400), "light")
        self.assertEqual(self.composer.tone(black, 200, 400), "light")
        self.assertEqual(self.composer.tone(white, 200, 400), "dark")
        self.composer.draw_touch(green, 200.0, 400.0, 1.0, "light")
        centre = np.asarray(green)[round(400 * self.composer.pt), round(200 * self.composer.pt)]
        self.assertGreater(int(centre[1]), 0x50)          # lighter than the green it sits on

    def test_a_faded_out_touch_draws_nothing(self):
        card = Image.new("RGB", (self.composer.lay.card_w, self.composer.lay.card_h), (255, 255, 255))
        self.composer.draw_touch(card, 200.0, 400.0, 0.0, "dark")
        self.assertEqual(card.getextrema(), ((255, 255), (255, 255), (255, 255)))

    def test_the_card_clips_the_touch_point(self):
        """A touch at the card's very corner does not paint on the paper."""
        lay = self.composer.lay
        white = Image.new("RGB", RAW, (255, 255, 255))
        plain = self.composer.frame(self.composer.under("agenda"), self.composer.card(white))
        card = self.composer.card(white)
        self.composer.draw_touch(card, 2.0, 2.0, 1.0, "dark")
        touched = self.composer.frame(self.composer.under("agenda"), card)
        a, b = np.asarray(plain), np.asarray(touched)
        self.assertTrue(np.array_equal(a[:lay.card_y], b[:lay.card_y]))
        self.assertTrue(np.array_equal(a[:, :lay.card_x], b[:, :lay.card_x]))
        corner = (slice(lay.card_y, lay.card_y + 12), slice(lay.card_x, lay.card_x + 12))
        self.assertTrue(np.array_equal(a[corner], b[corner]))   # outside the rounded corner
        self.assertFalse(np.array_equal(a, b))                  # …but it is drawn inside


if __name__ == "__main__":
    unittest.main()
