"""After round 8 (2026-10-20) — architecture contract, « Owner decisions
after round 8 »:

  * the owner: « Accept 1.23× » (the 16:9 push) and « Accept it » (the 15-s
    16:9 form never seen filled);
  * MY CALL, not the owner's: the 15-s 16:9 hard cut on f192 — 4.1.0, the
    bar-4 downbeat — not f193 (« f193 » was the builder's wording). Every
    hard cut lands on the music's 16th grid, and verify (b) refuses one that
    does not (`join_problems`), however much its picture changes."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo import storyboard as sbmod  # noqa: E402
from promo import timebase as tb  # noqa: E402
from promo import verify as vmod  # noqa: E402
from promo.media import tools  # noqa: E402
from promo.scenes.clock import Clock  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_scenes import EVENTS, EVENTS15  # noqa: E402

SB = sbmod.load()
CLOCKS = {"30s": Clock(EVENTS, 960), "15s": Clock(EVENTS15, 512)}
HAVE_TAKES = tools.material_available() and tools.promo_takes_root() is not None


class TestCutsOnTheGrid(unittest.TestCase):
    """(b)'s rule, strict: a hard cut — a scene's, the macro's, or one
    declared in the phone — falls on the 16th grid (every 4 frames from the
    cut's start). Round 8's review: the 15-s 16:9 form's cut on f193 was one
    frame after the bar-4 downbeat, the only cut in either 16:9 film off the
    grid, and it read as a skipped scroll."""

    def test_an_off_grid_cut_is_refused_however_the_picture_changes(self):
        t = [{"frame": 193, "kind": "cut (declared, in the phone)", "into": "journal"}]
        bad = vmod.join_problems(t, {193: 30.0})
        self.assertEqual(len(bad), 1, bad)
        self.assertRegex(bad[0], r"f193 .*off the 16th grid .*4\.1\.0 \+ 1 frame")
        self.assertEqual(vmod.join_problems([{**t[0], "frame": 192}], {192: 30.0}), [])   # 4.1.0: the downbeat
        for f in (161, 166, 194, 195):                                                    # any frame off a 16th
            self.assertTrue(vmod.join_problems([{**t[0], "frame": f, "kind": "cut"}], {f: 30.0}), f)

    def test_both_rules_are_reported(self):
        bad = vmod.join_problems([{"frame": 193, "kind": "cut", "into": "x"}], {193: 0.5})
        self.assertEqual(len(bad), 2, bad)                       # off the grid AND no picture change

    def test_the_grid_is_the_films_own(self):
        """A time base with another grid holds the cut to it (a step of 8 frames: f196 is off it)."""
        other = tb.TimeBase(fps=30, bpm=56.25)
        t = [{"frame": 196, "kind": "cut", "into": "x"}]
        self.assertEqual(vmod.join_problems(t, {196: 30.0}), [])
        self.assertRegex(vmod.join_problems(t, {196: 30.0}, other)[0], "off the 16th grid")

    def test_dissolves_and_whips_are_not_cuts(self):
        """The 9:16 / 1:1 dissolve starts on 4.1.0+1 (f193) so it is whole on
        the « Créer » tap, f196: its first frame is the picture it leaves — it
        is not a cut, and (b) does not hold it to a cut's grid."""
        t = [{"frame": 193, "kind": "dissolve (declared)", "into": "journal"},
             {"frame": 161, "kind": "whip (in the phone)", "into": "journal"}]
        self.assertEqual(vmod.join_problems(t, {}), [])


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestEveryFilmsCutsOnTheGrid(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from promo.scenes import Film
        cls.films = {(cut, fid): Film(SB, cut, fid, CLOCKS[cut]) for cut in ("30s", "15s")
                     for fid in ("9x16", "1x1", "16x9")}

    def test_every_cut_in_the_six_plans(self):
        for key, film in self.films.items():
            cuts = [t for t in film.transitions() if t["kind"].startswith("cut")]
            self.assertTrue(cuts, key)
            with self.subTest(film=key):
                self.assertEqual(vmod.join_problems(cuts, {int(t["frame"]): 100.0 for t in cuts},
                                                    SB.timebase), [])

    def test_the_15s_16x9_form_cuts_on_the_downbeat(self):
        film = self.films[("15s", "16x9")]
        j = next(s for s in film.scenes if s.id == "journal")
        seg = next(s for s in j.timeline.segments if s.kind == "dissolve")
        self.assertTrue(seg.cut)
        self.assertEqual(seg.start, 192.0)
        self.assertEqual(SB.timebase.pos(192), tb.Pos(4, 1, 0))
        self.assertEqual(seg.end, 196.0)                                             # « Créer », its tap
        self.assertIsNone(j.timeline.dissolve_at(191.0))                             # the empty form at rest …
        self.assertEqual(j.timeline.dissolve_at(192.0)[3], 1.0)                      # … the form's end, whole
        self.assertNotEqual(j.timeline.index(191.0), j.timeline.index(192.0))
        self.assertEqual(j.timeline.index(192.0), j.timeline.index(195.0))
        self.assertIn({"frame": 192, "kind": "cut (declared, in the phone)", "into": "journal", "frames": 0},
                      film.transitions())
        # in the PIXELS: f192 already the filled form's end, the same picture to f195; f191 the empty form
        a, _ = film.frame(191)
        b, _ = film.frame(192)
        c, _ = film.frame(195)
        lum = lambda x: x[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722]   # noqa: E731
        self.assertGreater(float(np.abs(lum(b) - lum(a)).mean()), vmod.CUT_MIN_CHANGE)
        self.assertLess(float(np.abs(lum(c) - lum(b)).mean()), 0.5)

    def test_the_other_formats_still_dissolve_from_f193(self):
        for fid in ("9x16", "1x1"):
            j = next(s for s in self.films[("15s", fid)].scenes if s.id == "journal")
            seg = next(s for s in j.timeline.segments if s.kind == "dissolve")
            with self.subTest(fmt=fid):
                self.assertFalse(seg.cut)
                self.assertEqual((seg.start, seg.end), (193.0, 196.0))



@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestTheArriveCardNeverShowsTwice(unittest.TestCase):
    """The spec's §10.4 nit (round 6's review, still in round 8's MP4s): 9:16's
    « Arrivé » card pops IN PLACE — its copy fades in 200 px above its place
    (it never crosses y 1248) — while the panel that empties its place rose
    with the same envelope: on the pop's first frames and the settle's last
    ones both cards showed, half each (Vision read two « 13:15 », both
    Fatou B.'s, on 30-s f232 and 15-s f144 / f156). The place is now empty on
    EVERY frame the copy shows; 1:1's travelling card (opaque, leaving its
    place) keeps the panel on the envelope."""

    def test_its_place_is_plain_on_every_frame_the_copy_shows(self):
        from promo.fx import lift as liftmod
        from promo.scenes import Film
        for cut in ("30s", "15s"):
            fm = Film(SB, cut, "9x16", CLOCKS[cut])
            j = next(s for s in fm.scenes if s.id == "journal")
            L = next(l for l in j.lifts if l["id"] == "arrive-card")
            self.assertEqual(L["path"], "in_place")
            shows = [f for f in range(int(L["up"]) - 2, int(L["down"]) + 8)
                     if liftmod.pop_progress(float(f), L["up"], 6.0, L["down"], 5.0) > 0]
            edges = [f for f in shows if liftmod.pop_progress(float(f), L["up"], 6.0, L["down"], 5.0) < 0.95]
            self.assertGreaterEqual(len(edges), 4, (cut, shows))                 # the fade's own frames, both ends
            for f in edges:
                frame, _ = fm.frame(f)
                x0, y0, x1, y1 = j.phone.map_rect(L["rect_pt"], j.pose(float(f)), W=j.camera_W(float(f)),
                                                  window=j.win(float(f)))
                inner = (frame[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722])[
                    int(y0) + 10:int(y1) - 10, int(x0) + 10:int(x1) - 10]
                with self.subTest(cut=cut, f=f):
                    self.assertLess(float(inner.std()), 2.0)                     # plain: no text, no badge
            # the frame after the copy has gone: the card back in its place, whole
            after = max(shows) + 1
            frame, _ = fm.frame(after)
            x0, y0, x1, y1 = j.phone.map_rect(L["rect_pt"], j.pose(float(after)), W=j.camera_W(float(after)),
                                              window=j.win(float(after)))
            inner = (frame[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722])[
                int(y0) + 10:int(y1) - 10, int(x0) + 10:int(x1) - 10]
            self.assertGreater(float(inner.std()), 10.0, (cut, after))


if __name__ == "__main__":
    unittest.main()
