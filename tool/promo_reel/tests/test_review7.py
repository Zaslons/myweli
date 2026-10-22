"""Round 7's review (2026-10-20) — the findings that are not the owner's call:

  * 30s-16x9 f264–320: the camera breathed. The push about the floor (in
    f264–280, out f284–304) and then the micro push the other formats share
    (in f304–314, out f314–320) turned four times in 56 frames, right after
    the whip. In 16:9 the micro push holds 1.0, and the push settles once, on
    f304. A film whose push turns three times within a bar is refused.
  * the 30-s MP4's true peak: the AAC rose 0.51 dB over the master and left
    0.29 dB under −1.0 dBTP. The master is limited to ≈ −2.0 dBTP now
    (render.AAC_HEADROOM_DB 0.7), and verify (d) warns when the MP4 keeps
    less than 0.5 dB under the ceiling.
  * verify (a) on a films-only copy (no renderer stills) said « 0 of 60 beats
    on the sheet; MP4 vs renderer PSNR min 0.0 dB », which reads as the MP4
    not matching its frames. It now says that the stills are missing."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo import render as rmod  # noqa: E402
from promo import storyboard as sbmod  # noqa: E402
from promo import verify as vmod  # noqa: E402
from promo.scenes import SceneError  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_owner_r5 import CLOCKS, SB, film, scene  # noqa: E402
import test_round5  # noqa: E402  (the module: its TestCase classes are not collected twice)

#: round 7's storyboard: the micro push on the push about the floor in 16:9 too
BREATHING = "scenes.30s.2.camera.zoom.1.formats={16x9: {value: 1.0385}}"


def push(sc, f: int) -> float:
    """The phone's push on frame f as render.json records it (`zoom`)."""
    return sc.zoom(float(f)) * sc.fill(float(f))


class TestTheCameraNeverBreathes(unittest.TestCase):
    def test_no_film_turns_its_push_three_times_in_a_bar(self):
        for cut in ("30s", "15s"):
            for fid in SB.formats:
                self.assertEqual(film(cut, fid).breathing_pushes(), [], (cut, fid))

    def test_16x9_settles_once_on_f304(self):
        """The push about the floor comes back to 1.0 on f304 (5.4.0) and the
        16:9 camera holds it to « Coupe homme » (f320). 9:16 and 1:1 have no
        push about the floor and keep their micro push (1.0385 on f314)."""
        j = scene(film("30s", "16x9"), "journal")
        self.assertAlmostEqual(push(j, 280), 1.23)
        self.assertEqual([round(push(j, f), 6) for f in range(304, 321)], [1.0] * 17)
        self.assertTrue(all(push(j, f) >= push(j, f + 1) - 1e-9 for f in range(284, 320)))   # out, then still
        for fid in ("9x16", "1x1"):
            j = scene(film("30s", fid), "journal")
            self.assertAlmostEqual(push(j, 314), 1.0385, msg=fid)
            self.assertAlmostEqual(push(j, 304), 1.0, msg=fid)
            self.assertAlmostEqual(push(j, 320), 1.0, msg=fid)

    def test_breathing_is_found_and_refused(self):
        bad = film("30s", "16x9", BREATHING).breathing_pushes()
        self.assertEqual(bad[0], {"scene": "journal", "frames": [264, 284, 304], "moves": ["in", "out", "in"]})
        with tempfile.TemporaryDirectory() as d, \
                mock.patch("promo.render.render_audio", lambda sb, cut, out: CLOCKS[cut]):
            with self.assertRaisesRegex(SceneError, r"30s/16x9: the push turns three times within a bar"):
                rmod.build_one(sbmod.load(overrides=[BREATHING]), "30s", "16x9", Path(d))


class TestCodecHeadroom(unittest.TestCase):
    def test_the_master_leaves_the_aac_room(self):
        """The master's own ceiling: −1.0 − 0.7 = −1.7 dBTP (the limiter then
        sits 0.3 dB under it: ≈ −2.0 measured; round 6: −1.5, −1.8)."""
        self.assertEqual(rmod.FILM_CEILING_DBTP - rmod.AAC_HEADROOM_DB, -1.7)

    def test_a_thin_margin_is_seen(self):
        thin = vmod.codec_headroom(-1.29, -1.80)                  # round 6's 30-s MP4 and its master
        self.assertEqual((thin["codec_rise_db"], thin["margin_db"], thin["thin"]), (0.51, 0.29, True))
        ok = vmod.codec_headroom(-1.79, -2.00)
        self.assertEqual((ok["codec_rise_db"], ok["margin_db"], ok["thin"]), (0.21, 0.79, False))
        self.assertFalse(vmod.codec_headroom(-1.5, -2.0)["thin"])   # 0.5 dB left: not thin

    def test_d_says_so_and_still_passes(self):
        """A warning, not a FAIL: the MP4 under −1.0 dBTP is the rule. The
        verdict harness (test_round5) measures the MP4 and the master alike,
        so the measure is given here as the films measured."""
        real = vmod.codec_headroom
        for mp4_tp, master_tp, warned in ((-1.29, -1.80, True), (-1.79, -2.00, False)):
            got = {}
            verify_film = vmod.verify_film

            def spy(*a, **k):
                got["res"] = verify_film(*a, **k)
                return got["res"]

            with mock.patch.object(vmod, "verify_film", spy), \
                    mock.patch.object(vmod, "codec_headroom", lambda mp4, master: real(mp4_tp, master_tp)):
                statuses = test_round5.TestVerdicts("test_the_harness_passes_what_should_pass").run_film()
            d = got["res"].sections["d"]
            with self.subTest(mp4=mp4_tp, master=master_tp):
                self.assertEqual(statuses["d"], "PASS")
                self.assertEqual(d["headroom"]["thin"], warned)
                self.assertEqual("WARNING" in d["summary"], warned, d["summary"])
                self.assertIn(f"{-1.0 - mp4_tp:.2f} dB under {vmod.TP_CEILING}", d["summary"])


class TestBeatSheetSaysWhatIsMissing(unittest.TestCase):
    def test_a_films_only_copy(self):
        """No renderer stills (a copy of the films without verify/renderer/):
        (a) fails, saying the stills are missing, with no PSNR."""
        ok, summary = vmod.beat_sheet_verdict(60, 0, list(range(0, 960, 16)), {})
        self.assertFalse(ok)
        self.assertIn("renderer stills missing (verify/renderer/, written by build): 60 of 60", summary)
        self.assertNotIn("0.0 dB", summary)
        self.assertNotIn("PSNR", summary)

    def test_some_missing(self):
        ok, summary = vmod.beat_sheet_verdict(60, 58, [16, 32], {f: 41.0 for f in range(0, 960, 16) if f not in (16, 32)})
        self.assertFalse(ok)
        self.assertIn("renderer stills missing (verify/renderer/, written by build): 2 of 60 (f16, f32)", summary)
        self.assertIn("PSNR min 41.0 dB on the 58 there", summary)

    def test_all_there(self):
        ok, summary = vmod.beat_sheet_verdict(60, 60, [], {f: 41.0 for f in range(0, 960, 16)})
        self.assertTrue(ok)
        self.assertEqual(summary, f"60 of 60 beats on the sheet; MP4 vs renderer PSNR min 41.0 dB "
                                  f"(≥ {vmod.BEAT_PSNR_DB} dB: same frames, same order)")
        self.assertFalse(vmod.beat_sheet_verdict(60, 60, [], {0: 20.0})[0])


if __name__ == "__main__":
    unittest.main()
