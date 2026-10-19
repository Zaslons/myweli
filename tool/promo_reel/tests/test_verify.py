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
from promo.verify import (_bandpass, _psnr, caption_reading, click_lag, click_onset, event_gaps,  # noqa: E402
                          outside_safe, verify)

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


class TestNothingUnverifiedPasses(unittest.TestCase):
    def test_missing_and_unbuilt(self):
        self.assertIsNone(not_built(SB, "30s", "9x16"))
        self.assertIn("no scenes", not_built(SB, "15s", "9x16"))
        self.assertIn("laid out", not_built(SB, "30s", "1x1"))
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertFalse(verify(SB, ["15s"], ["9x16"], Path(tmp)))
            self.assertFalse(verify(SB, ["30s"], ["9x16"], Path(tmp)))
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
