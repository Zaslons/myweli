"""verify.py's measures, on drawn data: the click finder recovers a known
offset, the safe-zone rule, reading speed, the longest quiet stretch, PSNR,
and that a missing or unbuilt film never passes."""

from __future__ import annotations

import contextlib
import io
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo import storyboard as sbmod  # noqa: E402
from promo.render import not_built  # noqa: E402
from promo import pixels  # noqa: E402
from promo.verify import (FAIL, PASS, PENDING, Result, Verdict, _bandpass, _psnr, air_levels,  # noqa: E402
                          caption_reading, click_lag, click_onset, event_gaps, outside_safe, reading_windows,
                          verify, worst)

SB = sbmod.load()


def click(n: int = 384, f: float = 3200.0) -> np.ndarray:
    t = np.arange(n) / 48000
    return np.sin(2 * np.pi * f * t) * np.hanning(n)


class TestClickLag(unittest.TestCase):
    def test_recovers_a_known_offset_under_music(self):
        rng = np.random.default_rng(3)
        n = 48000
        t = np.arange(n) / 48000
        music = 0.3 * np.sin(2 * np.pi * 110 * t) + 0.05 * rng.standard_normal(n)
        for shift in (0, 37, -12, 800, -1600):
            master = music.copy()
            master[20000:20384] += click()
            written = music.copy()
            written[20000 + shift:20384 + shift] += click()
            with self.subTest(shift=shift):
                self.assertEqual(click_lag(_bandpass(written), _bandpass(master), 20000), shift)
                # read straight off the written audio, searched from the cue: the click's
                # half-height point (2 ms into this 8-ms blip), wherever it moved to
                self.assertLess(abs(click_onset(_bandpass(written), 20000) - (20000 + shift)), 120)

    def test_psnr(self):
        a = np.zeros((8, 8, 3), np.uint8)
        self.assertEqual(_psnr(a, a), float("inf"))
        self.assertAlmostEqual(_psnr(a, a + 1), 48.13, places=2)


class TestSafeZones(unittest.TestCase):
    def test_rules(self):
        fmt = SB.formats["9x16"]
        recs = [{"f": 1, "boxes": [
            {"kind": "caption", "label": "ok", "rect": [200, 330, 880, 380]},
            {"kind": "caption", "label": "past the column", "rect": [140, 330, 600, 380]},
            {"kind": "counter", "label": "above the rail: to x 960", "rect": [150, 400, 950, 500]},
            {"kind": "lift", "label": "below 840 past x 900", "rect": [120, 1000, 910, 1100]},
            {"kind": "touch", "label": "under the platform chrome", "rect": [400, 1240, 480, 1300]},
            {"kind": "mark", "label": "the logo is laid out, not checked", "rect": [0, 0, 1080, 1920]}]}]
        counted, bad = outside_safe(recs, fmt)
        self.assertEqual(counted, 5)
        self.assertEqual(sorted(b["label"] for b in bad),
                         ["below 840 past x 900", "past the column", "under the platform chrome"])


class TestReading(unittest.TestCase):
    def test_cps_and_gaps(self):
        items = [SimpleNamespace(id="a", text="Disponible sur l’App Store", first=864, until=896),
                 SimpleNamespace(id="b", text="Disponible sur l’App Store", first=848, until=896)]
        rows = caption_reading(items, 30)
        self.assertEqual([r["ok"] for r in rows], [False, True])    # 1.07 s is too short, 1.6 s reads
        self.assertAlmostEqual(rows[1]["cps"], 16.25)
        self.assertEqual(event_gaps([0, 10, 70, 80], 100)[0], (60, 10, 70))
        self.assertEqual(event_gaps([], 100), [(100, 0, 100)])


class TestCombinedReading(unittest.TestCase):
    """Review M1 / m3 (i): characters per arrival window across everything
    on screen — each caption alone said 15.9 and 16.3 cps on the end card."""

    @staticmethod
    def item(group, arrive, leave, chars, pending=False):
        return {"what": group, "arrive": float(arrive), "leave": float(leave), "chars": chars, "pending": pending,
                "group": group}

    def test_the_end_card_adds_up(self):
        old = [self.item("tagline", 832, 896, 17), self.item("tagline", 848, 896, 17), self.item("store", 848, 896, 26)]
        w = reading_windows(old, 30)
        self.assertEqual((w[0]["from"], w[0]["to"], w[0]["chars"]), (832, 896, 60))
        self.assertAlmostEqual(w[0]["cps"], 28.125, delta=0.006)           # the review's ≈ 28 cps …
        w848 = next(x for x in w if x["from"] == 848)
        self.assertAlmostEqual(w848["cps"], 26.88, places=2)               # … and ≈ 27 from f848
        now = [self.item("tagline", 827, 896, 34, True), self.item("store", 848, 896, 26, True)]
        w = reading_windows(now, 30)
        self.assertEqual((w[0]["from"], w[0]["chars"]), (827, 60))
        self.assertAlmostEqual(w[0]["cps"], 26.09, places=2)
        self.assertTrue(w[0]["pending"])
        self.assertAlmostEqual(reading_windows(now[1:], 30)[0]["cps"], 16.25)      # the store line alone reads

    def test_a_caption_alone_is_its_own_cps(self):
        w = reading_windows([self.item("a", 0, 30, 10), self.item("a", 8, 30, 7)], 30)
        self.assertAlmostEqual(w[0]["cps"], 17 * 30 / 30)

    def test_statuses(self):
        self.assertEqual(worst([PASS, PASS]), PASS)
        self.assertEqual(worst([PASS, PENDING]), PENDING)
        self.assertEqual(worst([PENDING, FAIL]), FAIL)
        self.assertEqual(worst([]), FAIL)                                   # nothing checked is not a pass
        r = Result()
        r.add("a", "a", True, "")
        r.add("i", "i", False, "", status=PENDING)
        self.assertEqual(r.status, PENDING)
        self.assertFalse(r.ok)
        r.add("b", "b", False, "", status=PASS)                             # a failed check is never a pass
        self.assertEqual(r.sections["b"]["status"], FAIL)
        self.assertFalse(Verdict(PENDING))
        self.assertTrue(Verdict(PASS))


class TestAir(unittest.TestCase):
    """Review M2: an AIR beat is near silence, ≥ 6 LU under the groove."""

    def test_air_against_the_groove(self):
        rng = np.random.default_rng(1)
        n = 64 * 1600
        audio = 0.1 * rng.standard_normal((n, 2))
        events = {"sections": [{"name": "drop1", "frame": 16, "end_frame": 48}, {"name": "hook", "frame": 0,
                                                                                 "end_frame": 16}],
                  "cues": [{"id": "air1.reverse", "kind": "reverse", "frame": 48, "end_frame": 64},
                           {"id": "air2.reverse", "kind": "reverse", "frame": 0, "end_frame": 16}]}
        audio[48 * 1600:] *= 10 ** (-8 / 20)                               # AIR 1: 8 dB down
        audio[:16 * 1600] *= 10 ** (-3 / 20)                               # AIR 2: 3 dB down — the old AIR 2
        a = air_levels(audio, events)
        self.assertEqual(a["groove_sections"], ["drop1"])
        rows = {r["cue"]: r for r in a["air"]}
        self.assertAlmostEqual(rows["air1.reverse"]["under_groove_lu"], 8.0, delta=0.2)
        self.assertTrue(rows["air1.reverse"]["ok"])
        self.assertFalse(rows["air2.reverse"]["ok"])
        self.assertFalse(a["ok"])


class TestPixels(unittest.TestCase):
    """The measures (f), (g), (h) read off the MP4's pixels."""

    def test_the_disc_ring(self):
        import skia
        from promo.fx import touch
        from promo.fx.surface import new_surface, to_array
        def frame(with_disc: bool, tone: str = "dark", ground: int = 0xFFFFFFFF) -> np.ndarray:
            s = new_surface(400, 400)
            c = s.getCanvas()
            c.clear(ground)
            c.drawRect(skia.Rect.MakeXYWH(120, 190, 160, 6), skia.Paint(Color=0xFF1A1A1A))   # a line of « text »
            if with_disc:
                touch.draw_tap(c, 200, 200, 280, 280, 286, tone=tone, scale=1.791)
            return pixels.luminance(to_array(s))
        R = 24 * 1.791
        self.assertLess(abs(pixels.ring_contrast(frame(False), 200, 200, R)), 10)
        self.assertLess(pixels.ring_contrast(frame(True), 200, 200, R), -40)
        self.assertGreater(pixels.ring_contrast(frame(True, "light", 0xFF1E5631), 200, 200, R), 25)

    def test_which_picture_a_box_shows(self):
        old = np.full((20, 20), 250.0)
        new = old.copy()
        new[5:15, 8:12] = 30.0                                              # a typed character
        L = np.full((100, 100), 250.0)
        L[40:60, 40:60] = new
        self.assertGreater(pixels.closer_to(L, (40, 40, 60, 60), old, new), 100)
        L[40:60, 40:60] = old
        self.assertLess(pixels.closer_to(L, (40, 40, 60, 60), old, new), -100)
        self.assertEqual(pixels.box_change(L, L, (0, 0, 100, 100)), 0.0)

    def test_ink_boxes(self):
        rgb = np.full((200, 300, 3), 250, np.uint8)
        rgb[50:70, 40:250] = 26                                             # dark type
        rgb[120, 10] = 0                                                    # a lone speck does not stretch it
        self.assertEqual(pixels.ink_box(rgb, (0, 0, 300, 200), "dark"), (40, 50, 250, 70))
        dark = np.zeros((200, 300, 3), np.uint8)
        dark[80:90, 100:120] = 255
        dark[10:20, 10:20] = (200, 160, 110)                                # warm paper is not white ink
        self.assertEqual(pixels.ink_box(dark, (0, 0, 300, 200), "white"), (100, 80, 120, 90))
        self.assertIsNone(pixels.ink_box(rgb, (0, 100, 300, 200), "dark"))    # no type there

    def test_how_much_of_a_row_shows(self):
        def text_row(seed: int) -> np.ndarray:
            rng = np.random.default_rng(seed)
            r = np.full((30, 400), 240.0)
            x = 6
            while x < 380:                                                  # irregular « glyphs »
                w, top, bot = rng.integers(3, 12), rng.integers(4, 12), rng.integers(16, 26)
                r[top:bot, x:x + w] = rng.uniform(20, 120)
                x += w + rng.integers(2, 9)
            return r
        row = text_row(5)
        L = np.full((200, 800), 245.0)
        L[100:130, 200:600] = row
        full = pixels.row_fraction(L, row, 200, 100, range(-200, 41), block=48)
        self.assertEqual(full[0], 1.0)
        self.assertLessEqual(abs(full[1]), 1)
        slid = L.copy()
        slid[100:130, :] = 245.0
        slid[100:130, 120:520] = row                                         # the outgoing page slid 80 px left …
        slid[100:130, 330:] = 245.0                                          # … and the incoming one covers its right
        frac, shift, _ = pixels.row_fraction(slid, row, 200, 100, range(-200, 41), block=48)
        self.assertEqual(shift, -80)
        self.assertTrue(0.3 < frac < 0.7, frac)
        other = np.full((200, 800), 245.0)
        other[100:130, 200:600] = text_row(6)                              # a different row of « text »
        self.assertLess(pixels.row_fraction(other, row, 200, 100, range(-200, 41), block=48)[0], 0.25)
        band = np.full((200, 800), 245.0)                                    # under the opaque band: paper only
        band[100:130, ::66] = 237.0                                          # (and the pattern's marks)
        self.assertEqual(pixels.row_fraction(band, row, 200, 100, range(-200, 41), block=48)[0], 0.0)
        faint = L.copy()
        faint[100:130, 200:600] = 245.0 + 0.1 * (row - 245.0)               # a faint copy still counts: the
        self.assertEqual(pixels.row_fraction(faint, row, 200, 100, range(-200, 41), block=48)[0], 1.0)  # strength
        # is the window's alpha (the other half of (h)); this half only says whether its pixels are there


class TestNothingUnverifiedPasses(unittest.TestCase):
    def test_missing_and_unbuilt(self):
        self.assertIsNone(not_built(SB, "30s", "9x16"))
        self.assertIn("no scenes", not_built(SB, "15s", "9x16"))
        self.assertIn("laid out", not_built(SB, "30s", "1x1"))
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertFalse(verify(SB, ["15s"], ["9x16"], Path(tmp)))
            self.assertFalse(verify(SB, ["30s"], ["9x16"], Path(tmp)))
            self.assertEqual(verify(SB, ["30s"], ["9x16"], Path(tmp)).status, FAIL)
        self.assertIn("NOT BUILT 15s/9x16", out.getvalue())
        self.assertIn("FAIL 30s/9x16: no film", out.getvalue())


class TestCommand(unittest.TestCase):
    def test_unbuilt_is_never_a_pass(self):
        from promo.__main__ import main
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(main(["verify", "--cut", "15s", "--format", "9x16", "--out", tmp]), 1)
            with self.assertRaisesRegex(SystemExit, "nothing could be built"):
                main(["build", "--cut", "30s", "--format", "1x1", "--out", tmp])
        self.assertIn("NOT BUILT", out.getvalue())


if __name__ == "__main__":
    unittest.main()
