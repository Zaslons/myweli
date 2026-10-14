"""Masks: the content under them hidden, fixed or following the scroll —
proved on pictures drawn here, whose scroll is known to the pixel."""

from __future__ import annotations

import atexit
import shutil
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

import masks
from edit import Refusal

WORK = Path(tempfile.mkdtemp(prefix="preview-masks-"))
atexit.register(shutil.rmtree, WORK, ignore_errors=True)
W, H = 603, 1311          # half the capture: 201 x 437 points at 3 px a point
BAR = 165                 # a title bar that does not scroll; the band below it does
GROUND = (246, 247, 249)


def strip(height: int = 4000, seed: int = 3) -> Image.Image:
    """A long list of cards with words on them: what scrolls."""
    rng = np.random.default_rng(seed)
    im = Image.new("RGB", (W, height), GROUND)
    d = ImageDraw.Draw(im)
    for y in range(20, height - 120, 125):
        d.rounded_rectangle((30, y, W - 30, y + 100), radius=12, fill=(255, 255, 255), outline=(208, 208, 208), width=2)
        x = 55
        while x < W - 120:
            w = int(rng.integers(30, 90))
            d.rectangle((x, y + 30, x + w, y + 42), fill=(26, 26, 26))
            d.rectangle((x, y + 60, x + int(w * 0.7), y + 68), fill=(110, 110, 110))
            x += w + int(rng.integers(12, 30))
    return im


STRIP = strip()


def screen(scrolled: int, content: Image.Image = STRIP) -> Image.Image:
    """The screen with the list scrolled up by `scrolled` pixels."""
    im = Image.new("RGB", (W, H), (250, 250, 250))
    ImageDraw.Draw(im).rectangle((0, 0, W, BAR - 1), fill=(250, 250, 250))
    ImageDraw.Draw(im).text((20, 60), "Fiche client", fill=(26, 26, 26))
    im.paste(content.crop((0, scrolled, W, scrolled + H - BAR)), (0, BAR))
    return im


def pictures(offsets: list[int], name: str, content: Image.Image = STRIP, T: int = 600) -> list[tuple[int, int, Path]]:
    folder = WORK / name
    folder.mkdir(exist_ok=True)
    out = []
    for k, off in enumerate(offsets):
        path = folder / f"p{k:03d}.png"
        screen(off, content).save(path)
        out.append((100 + k, 3000 + 20 * k, path))
    return out


# a card's first line of words, at rest: y 165 + 20 + 125 * 4 + 30 = 715
WORDS = [40, 705, 500, 50]


class Shift(unittest.TestCase):
    def test_how_far_the_band_moved_is_found_to_the_pixel(self):
        ref = masks.grey(screen(400))
        for moved in (0, 1, -1, 15, -37, 52, -60):
            got, error = masks.shift_between(ref, masks.grey(screen(400 - moved)), (BAR, H), 0, 60)
            self.assertEqual(got, moved, moved)
            self.assertLess(error, 0.01)

    def test_the_guess_widens_the_reach(self):
        ref = masks.grey(screen(400))
        far = masks.grey(screen(400 + 130))           # 130 px up: past a search of 60 from 0
        self.assertNotEqual(masks.shift_between(ref, far, (BAR, H), 0, 60)[0], -130)
        self.assertEqual(masks.shift_between(ref, far, (BAR, H), -100, 60)[0], -130)

    def test_detail_is_what_there_is_to_read(self):
        self.assertEqual(masks.detail(np.full((20, 40), 200.0)), 0.0)
        half = np.zeros((20, 40))
        half[:, 20:] = 255
        self.assertEqual(masks.detail(half), 127.5)
        self.assertEqual(masks.detail(np.zeros((0, 3))), 0.0)


class Cover(unittest.TestCase):
    def test_fill_takes_the_colour_around_the_rectangle(self):
        im = screen(0)
        x, y, w, h = WORDS
        colour = masks.ring_colour(im, WORDS)
        self.assertEqual(colour, (255, 255, 255))          # the card the words are on
        out = masks.cover(im, (x, y, x + w, y + h), "fill", colour)
        a = np.asarray(out)
        self.assertTrue((a[y:y + h, x:x + w] == 255).all())
        self.assertTrue(np.array_equal(np.asarray(im)[:y], a[:y]))      # nothing else is touched
        self.assertEqual(masks.legibility(im, out, (x, y, x + w, y + h))[1], 0.0)

    def test_a_blur_as_wide_as_the_rectangle_is_tall_leaves_words_unreadable(self):
        im = screen(0)
        x, y, w, h = WORDS
        box = (x, y, x + w, y + h)
        before, after = masks.legibility(im, masks.cover(im, box, "blur", (0, 0, 0)), box)
        self.assertGreater(before, masks.FLAT)
        self.assertLess(after, masks.LEGIBLE * before)

    def test_the_take_s_picture_is_not_changed(self):
        im = screen(0)
        kept = np.asarray(im).copy()
        masks.cover(im, (40, 705, 540, 755), "fill", (1, 2, 3))
        self.assertTrue(np.array_equal(np.asarray(im), kept))


class Place(unittest.TestCase):
    def test_a_tracking_mask_follows_a_scroll_whose_every_step_is_known(self):
        """The list scrolls up 50 px a picture, 900 px in all — further than
        half the band, so the reference is renewed on the way. Every box is
        the rectangle moved by exactly that much, clipped to the band."""
        offsets = [50 * k for k in range(19)]
        shown = pictures(offsets, "up")
        on, summary = masks.place({"rect_px": WORDS, "track": {"scroll_px": [BAR, H]}}, shown, 600, "test")
        x, y, w, h = WORDS
        for (j, _, _), off in zip(shown, offsets):
            if y + h - off <= BAR:
                self.assertNotIn(j, on, off)                # scrolled under the title bar: nothing to cover
                continue
            self.assertEqual(on[j].shift, -off, off)
            self.assertEqual(on[j].box, (x, max(y - off, BAR), x + w, y + h - off), off)
        self.assertEqual(summary["shift_px"], [-900, 0])
        self.assertEqual((summary["pictures"], summary["tracking"]), (19, True))
        self.assertLess(summary["worst_match"], 0.5)

    def test_it_follows_both_ways_from_a_reference_in_the_middle(self):
        offsets = [0, 40, 80, 120, 160, 200]
        shown = pictures(offsets, "middle")
        mask = {"rect_px": [40, WORDS[1] - 120, 500, 50], "track": {"scroll_px": [BAR, H]}, "ref_s": (3000 + 60) / 600}
        on, summary = masks.place(mask, shown, 600, "test")
        self.assertEqual([on[j].shift for j, _, _ in shown], [120, 80, 40, 0, -40, -80])
        self.assertEqual(summary["reference_s"], 5.1)

    def test_a_fixed_mask_over_content_that_moves_is_refused(self):
        shown = pictures([0, 0, 30], "fixed")
        with self.assertRaises(Refusal) as cm:
            masks.place({"rect_px": WORDS}, shown, 600, "test")
        self.assertEqual(cm.exception.code, "E_MASK")
        self.assertIn("the content under this fixed mask moves -30 px at 5.067 s of the take", cm.exception.message)
        on, summary = masks.place({"rect_px": WORDS}, shown[:2], 600, "test")
        self.assertEqual(on[shown[1][0]].box, (40, 705, 540, 755))
        self.assertFalse(summary["tracking"])

    def test_a_change_elsewhere_on_the_screen_does_not_lose_the_mask(self):
        """While the list scrolls, a block far from the mask turns dark (a
        card turning green, a snackbar): the content around the mask is
        what is matched, and the scroll is still found to the pixel."""
        folder = WORK / "elsewhere"
        folder.mkdir(exist_ok=True)
        shown = []
        for k, off in enumerate((0, 30, 60, 90)):
            im = screen(off)
            if k >= 2:
                ImageDraw.Draw(im).rectangle((0, 1100, W, 1300), fill=(45, 80, 22))
            im.save(folder / f"p{k}.png")
            shown.append((k, 3000 + 20 * k, folder / f"p{k}.png"))
        on, summary = masks.place({"rect_px": WORDS, "track": {"scroll_px": [BAR, H]}}, shown, 600, "test")
        self.assertEqual([on[j].shift for j, _, _ in shown], [0, -30, -60, -90])
        # matched on the whole band instead, the same pictures are not a scroll
        a, b = masks.grey(Image.open(shown[0][2])), masks.grey(Image.open(shown[3][2]))
        self.assertGreater(masks.shift_between(a, b, (BAR, H), -60, 60)[1], masks.MAX_TRACK_ERROR)
        self.assertLess(masks.shift_between(a, b, (BAR, H), -60, 60, (WORDS[1] - 200, WORDS[1] + 250))[1], 0.5)

    def test_content_that_does_not_scroll_stops_the_mask(self):
        """A picture whose band is another page — pushed in, or a sheet
        over it: no shift matches it."""
        shown = pictures([0, 20], "push") + pictures([0], "other", content=strip(seed=9))
        shown[-1] = (shown[-1][0] + 10, shown[-1][1] + 100, shown[-1][2])
        with self.assertRaises(Refusal) as cm:
            masks.place({"rect_px": WORDS, "track": {"scroll_px": [BAR, H]}}, shown, 600, "test")
        self.assertIn("is not the reference's, scrolled", cm.exception.message)

    def test_a_rectangle_on_nothing_is_refused(self):
        shown = pictures([0], "flat")
        with self.assertRaises(Refusal) as cm:
            masks.place({"rect_px": [5, 1250, 20, 20]}, shown, 600, "test")
        self.assertIn("shows nothing to hide on its reference picture", cm.exception.message)

    def test_a_blur_that_leaves_the_content_legible_is_refused(self):
        """Large dark and light halves: a blur only softens the edge."""
        content = Image.new("RGB", (W, 4000), (255, 255, 255))
        ImageDraw.Draw(content).rectangle((0, 0, W // 2, 4000), fill=(0, 0, 0))
        shown = pictures([0], "halves", content=content)
        with self.assertRaises(Refusal) as cm:
            masks.place({"rect_px": [100, 700, 400, 40], "style": "blur"}, shown, 600, "test")
        self.assertIn("covered by `blur`, the content keeps", cm.exception.message)
        self.assertIn("still legible", cm.exception.message)
        masks.place({"rect_px": [100, 700, 400, 40], "style": "fill"}, shown, 600, "test")

    def test_the_span_and_the_reference_must_be_shown(self):
        shown = pictures([0, 0, 0], "span")
        for mask, words in (({"rect_px": WORDS, "from_s": 9.0}, "no picture of the scene falls between"),
                            ({"rect_px": WORDS, "ref_s": 1.0}, "the reference picture (1.0 s of the take) is not one"),
                            ({"rect_px": WORDS, "from_s": 5.04, "ref_s": 5.0}, "is not one the scene shows"),
                            ({"rect_px": [500, 700, 200, 40]}, "leaves the 603 x 1311 capture")):
            with self.subTest(mask), self.assertRaises(Refusal) as cm:
                masks.place(mask, shown, 600, "test")
            self.assertEqual(cm.exception.code, "E_MASK")
            self.assertIn(words, cm.exception.message)
        with self.assertRaises(Refusal):
            masks.place({"rect_px": WORDS}, [], 600, "test")

    def test_a_mask_applies_only_to_the_pictures_of_its_span(self):
        shown = pictures([0, 0, 0, 0], "partial")
        on, summary = masks.place({"rect_px": WORDS, "from_s": 5.03, "to_s": 5.07}, shown, 600, "test")
        self.assertEqual(sorted(on), [shown[1][0], shown[2][0]])
        self.assertEqual(summary["pictures"], 2)


if __name__ == "__main__":
    unittest.main()
