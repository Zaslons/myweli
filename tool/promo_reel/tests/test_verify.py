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
from promo.media import tools  # noqa: E402
from promo.verify import (FAIL, PASS, HiddenRow, Result, Verdict, _bandpass, _psnr, air_levels,  # noqa: E402
                          audio_verdict, outro_tail, blurs_checked, caption_reading, click_lag, click_onset, dissolve_problems, dissolves,
                          end_card_window,
                          event_gaps, look_frames, outside_safe, reading_verdict, reading_windows, verify, worst)

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
    def item(group, arrive, leave, chars, scene="end"):
        return {"what": group, "arrive": float(arrive), "leave": float(leave), "chars": chars, "group": group,
                "scene": scene}

    def test_the_end_card_adds_up(self):
        old = [self.item("tagline", 832, 896, 17), self.item("tagline", 848, 896, 17), self.item("store", 848, 896, 26)]
        w = reading_windows(old, 30)
        self.assertEqual((w[0]["from"], w[0]["to"], w[0]["chars"]), (832, 896, 60))
        self.assertAlmostEqual(w[0]["cps"], 28.125, delta=0.006)           # the review's ≈ 28 cps …
        w848 = next(x for x in w if x["from"] == 848)
        self.assertAlmostEqual(w848["cps"], 26.88, places=2)               # … and ≈ 27 from f848
        r2 = [self.item("tagline", 827, 896, 34), self.item("store", 848, 896, 26)]   # round 2, 14 bars
        w = reading_windows(r2, 30)
        self.assertEqual((w[0]["from"], w[0]["chars"]), (827, 60))
        self.assertAlmostEqual(w[0]["cps"], 26.09, places=2)
        self.assertFalse(reading_verdict(w, [], [], []))                    # a plain FAIL: nothing is « pending »
        self.assertAlmostEqual(reading_windows(r2[1:], 30)[0]["cps"], 16.25)       # the store line alone reads
        r3 = [self.item("tagline", 827, 960, 34), self.item("store", 848, 960, 26)]   # + the owner's outro bar
        w = reading_windows(r3, 30)
        self.assertAlmostEqual(w[0]["cps"], 13.53, places=2)
        self.assertTrue(reading_verdict(w, [], [], []))
        card = end_card_window(r3 + [self.item("page", 640, 752, 30, scene="page")], "end", 30)
        self.assertEqual((card["from"], card["to"], card["chars"], card["cps"]), (827, 960, 60, 13.53))

    def test_the_verdict_is_pass_or_fail(self):
        ok = [{"cps": 16.9}]
        self.assertTrue(reading_verdict(ok, [{"ok": True}], [], [(60, 0, 60)]))
        self.assertFalse(reading_verdict([{"cps": 17.1}], [], [], []))
        self.assertFalse(reading_verdict(ok, [{"ok": False}], [], []))                 # a caption alone too fast
        self.assertFalse(reading_verdict(ok, [], [(848, ["a", "b"])], []))             # two lines on one frame
        self.assertFalse(reading_verdict(ok, [], [], [(64, 896, 960)]))                # 2.13 s without an event

    def test_a_caption_alone_is_its_own_cps(self):
        w = reading_windows([self.item("a", 0, 30, 10), self.item("a", 8, 30, 7)], 30)
        self.assertAlmostEqual(w[0]["cps"], 17 * 30 / 30)

    def test_statuses(self):
        """PASS or FAIL: the « OWNER DECISION PENDING » status is retired (the
        owner added a bar, 2026-10-19)."""
        import promo.verify as v
        self.assertFalse(hasattr(v, "PENDING"))
        self.assertEqual(worst([PASS, PASS]), PASS)
        self.assertEqual(worst([PASS, FAIL]), FAIL)
        self.assertEqual(worst([]), FAIL)                                   # nothing checked is not a pass
        r = Result()
        r.add("a", "a", True, "")
        r.add("i", "i", False, "")
        self.assertEqual(r.status, FAIL)
        self.assertFalse(r.ok)
        r.add("b", "b", False, "", status=PASS)                             # a failed check is never a pass
        self.assertEqual(r.sections["b"]["status"], FAIL)
        self.assertFalse(Verdict(FAIL))
        self.assertTrue(Verdict(PASS))


class TestAir(unittest.TestCase):
    """Review M2: an AIR beat is near silence, ≥ 7 LU under the groove (round
    3: on the master and the MP4 alike)."""

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
        audio[:16 * 1600] *= 10 ** (-3.5 / 20)                             # AIR 2 now 6.5 dB down: still too loud
        rows = {r["cue"]: r for r in air_levels(audio, events)["air"]}
        self.assertAlmostEqual(rows["air2.reverse"]["under_groove_lu"], 6.5, delta=0.2)
        self.assertFalse(rows["air2.reverse"]["ok"])


class TestAudioVerdict(unittest.TestCase):
    """(d)'s verdict is ONE function over every measure — the MP4's loudness,
    its length, the AIR beats on the MP4 AND on the WAV master, the last hit's
    tail on both — so no rule can drop out of it unnoticed (review round 3:
    removing the master's AIR from the verdict left every test green)."""

    N = 64 * 1600
    EVENTS = {"sections": [{"name": "drop1", "frame": 0, "end_frame": 48}],
              "cues": [{"id": "air1.reverse", "kind": "reverse", "frame": 48, "end_frame": 64}]}

    def audio(self, air_db: float) -> np.ndarray:
        x = 0.1 * np.random.default_rng(5).standard_normal((self.N, 2))
        x[48 * 1600:] *= 10 ** (air_db / 20)
        return x

    def verdict(self, *, air_mp4=-9.0, air_master=-9.0, tail=True, tail_master=True, lufs=-14.0, tp=-1.5,
                decoded=None) -> bool:
        m = SimpleNamespace(integrated_lufs=lufs, true_peak_dbtp=tp)
        a = air_levels(self.audio(air_mp4), self.EVENTS)
        am = air_levels(self.audio(air_master), self.EVENTS)
        return audio_verdict(m, self.N if decoded is None else decoded, self.N, a, am, {"ok": tail},
                             {"ok": tail_master})

    def test_every_measure_counts(self):
        self.assertTrue(self.verdict())
        self.assertFalse(self.verdict(air_master=-5.0))           # ONLY the master's AIR under 7 LU: FAIL
        self.assertFalse(self.verdict(air_mp4=-5.0))              # only the MP4's
        self.assertFalse(self.verdict(tail_master=False))         # only the master's tail chopped
        self.assertFalse(self.verdict(tail=False))                # only the MP4's
        self.assertFalse(self.verdict(lufs=-15.0))
        self.assertFalse(self.verdict(tp=-0.8))
        self.assertFalse(self.verdict(decoded=self.N - 1600))

    def test_the_last_hit_rings_out(self):
        """The cut's last log hit must decay ≥ 20 dB within 22 frames and sit
        ≥ 30 dB under itself over the last 100 ms (round 3: the last chord
        held to the last sample, 4.6 dB down by f950, chopped by the end fade)."""
        n = 64 * 1600
        t = np.arange(n - 32 * 1600) / 48000
        tone = np.sin(2 * np.pi * 130.8 * t)
        ev = {"cues": [{"id": "early", "kind": "log", "frame": 4}, {"id": "end.last", "kind": "log", "frame": 32}]}
        rung = np.zeros((n, 2))
        rung[32 * 1600:, 0] = rung[32 * 1600:, 1] = 0.3 * tone * np.exp(-t / 0.08)
        r = outro_tail(rung, ev)
        self.assertEqual((r["cue"], r["frame"], r["at_frame"]), ("end.last", 32, 54))
        self.assertTrue(r["ok"], r)
        held = np.zeros((n, 2))
        held[32 * 1600:, 0] = held[32 * 1600:, 1] = 0.3 * tone * np.exp(-t / 1.5)
        held[-2880:] *= np.linspace(1, 0, 2880)[:, None]                  # a 60-ms end fade chops it
        r = outro_tail(held, ev)
        self.assertFalse(r["ok"], r)
        self.assertLess(r["decay_db"], 20)
        self.assertFalse(outro_tail(rung, {"cues": []})["ok"])            # no last hit: never a pass


class TestPixels(unittest.TestCase):
    """The measures (f), (g), (h) read off the MP4's pixels."""

    def test_a_strike_on_lit_paper(self):
        """(g) reads each hook strike off the MP4: the paper beside the stroke
        minus the stroke; nothing there reads ≈ 0, off the frame reads None."""
        import skia
        from promo.fx.surface import new_surface, to_array
        from promo.fx.type import draw_strike
        s = new_surface(400, 200)
        c = s.getCanvas()
        c.clear(skia.Color(200, 180, 140))
        L0 = pixels.luminance(to_array(s))
        draw_strike(c, (40, 100), (360, 104), 10, 1.0, 0xFF000000)
        L = pixels.luminance(to_array(s))
        self.assertGreater(pixels.line_contrast(L, (40, 100), (360, 104), 10), 100)
        self.assertLess(abs(pixels.line_contrast(L0, (40, 100), (360, 104), 10)), 1)       # no stroke
        self.assertIsNone(pixels.line_contrast(L, (40, 100), (360, 230), 10))              # partly off the frame
        from promo.verify import STRIKE_CONTRAST, hook_ink_problems
        fmt = SB.formats["1x1"]
        ok = {"what": "strike row 10", "box": [0, 0, 1, 1], "scrim": 0.0, "in_canvas": True, "in_safe": True}
        self.assertEqual(hook_ink_problems({"hook": [ok]}, [{"scene": "hook", "what": "strike row 10", "frame": 9,
                                                             "contrast": STRIKE_CONTRAST + 1}], fmt), [])
        self.assertTrue(hook_ink_problems({"hook": [ok]}, [{"scene": "hook", "what": "strike row 10", "frame": 9,
                                                            "contrast": None}], fmt))
        self.assertTrue(hook_ink_problems({"hook": [{**ok, "in_safe": False}]}, [], fmt))      # 1:1: graphics-safe
        self.assertEqual(hook_ink_problems({"hook": [{**ok, "in_safe": False}]}, [], SB.formats["9x16"]), [])
        self.assertTrue(hook_ink_problems({"hook": [{**ok, "scrim": 0.9}]}, [], fmt))

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


class TestHiddenRowSearch(unittest.TestCase):
    """(h) round 3: the hidden row searched over the whole window, by the
    blocks that identify it — on drawn rows."""

    @staticmethod
    def glyphs(seed: int, width: int = 48) -> np.ndarray:
        rng = np.random.default_rng(seed)
        r = np.full((30, width), 240.0)
        x = 3
        while x < width - 6:
            w, top, bot = rng.integers(3, 9), rng.integers(4, 12), rng.integers(16, 26)
            r[top:bot, x:x + w] = rng.uniform(20, 120)
            x += w + rng.integers(2, 6)
        return r

    def setUp(self):
        self.time = self.glyphs(1)                       # « 13:15 »: the old booking's own
        self.name = self.glyphs(2)                       # « Yao K. »: the new booking has it too
        self.row = np.hstack([self.time, self.name])
        self.other = np.hstack([self.glyphs(3), self.name])     # the new booking's row: same client, other time

    def test_ncc_map(self):
        rng = np.random.default_rng(4)
        R = rng.uniform(0, 255, (60, 80))
        t = R[10:40, 20:68].copy()
        m = pixels.ncc_map(R, t)
        self.assertEqual(m.shape, (31, 33))
        self.assertAlmostEqual(m[10, 20], 1.0, places=6)
        a = R[3:33, 7:55]
        want = np.sum((a - a.mean()) * (t - t.mean())) / np.sqrt(np.sum((a - a.mean()) ** 2) * np.sum((t - t.mean()) ** 2))
        self.assertAlmostEqual(m[3, 7], want, places=6)
        flat = np.full((60, 80), 240.0)
        self.assertEqual(float(np.abs(pixels.ncc_map(flat, t)).max()), 0.0)        # paper matches nothing

    def test_only_the_rows_own_blocks_identify_it(self):
        pic = np.full((300, 400), 245.0)
        pic[100:130, 50:146] = self.row
        pic[200:230, 50:146] = self.other
        parts = pixels.row_parts(self.row, block=48)
        self.assertEqual([b for b, _ in parts], [0, 48])
        self.assertEqual(pixels.distinctive(parts, [pic], own_y=100), [True, False])
        pushed = pic.copy()                                   # a push slides the row sideways: still its own height
        pushed[100:130, :] = 245.0
        pushed[100:130, 10:106] = self.row
        self.assertEqual(pixels.distinctive(parts, [pushed], own_y=100), [True, False])

    def test_found_anywhere_in_the_window(self):
        parts = [p for p, keep in zip(pixels.row_parts(self.row, block=48), [True, False]) if keep]
        frame = np.full((900, 700), 245.0)
        frame[300:330, 100:196] = self.other                  # the new booking, where it belongs
        self.assertEqual(pixels.row_anywhere(frame, parts, (0, 100, 700, 800))[0], 0.0)
        frame[611:641, 333:429] = self.row                    # the old row pasted far from any place
        share, x, y = pixels.row_anywhere(frame, parts, (0, 100, 700, 800))
        self.assertEqual((share, x, y), (1.0, 333.0, 611.0))
        half = frame.copy()                                   # pushed half out of the region on the left
        half[611:641, :] = 245.0
        half[611:641, 0:50] = self.row[:, 46:]
        self.assertEqual(pixels.row_anywhere(half, parts, (0, 100, 700, 800))[0], 0.0)   # its time is gone
        from scipy.ndimage import uniform_filter1d
        whip = frame.copy()                                   # in a whip's blur (vertical, 40 px)
        whip[560:700, :] = uniform_filter1d(frame[560:700, :], 40, axis=0)
        self.assertEqual(pixels.row_anywhere(whip, parts, (0, 100, 700, 800))[0], 0.0)

    def test_what_fails(self):
        clean = {"visible": 0.009, "mp4_shows": 0.0, "found_visible": 0.0, "found_at": [0, 0], "found_alpha": 0.0}
        self.assertEqual(HiddenRow.over(clean), [])
        self.assertEqual(HiddenRow.over({**clean, "visible": None}), [])                      # a whip frame
        self.assertTrue(HiddenRow.over({**clean, "visible": None, "found_visible": 1.0, "found_alpha": 1.0}))
        self.assertTrue(HiddenRow.over({**clean, "visible": 0.06}))
        self.assertTrue(HiddenRow.over({**clean, "mp4_shows": 0.34}))
        self.assertEqual(HiddenRow.over({**clean, "found_visible": 0.04}), [])                # in the band's fade


@unittest.skipUnless(tools.material_available(), "the recorded takes are not on this machine")
class TestHiddenRowInTheFilm(unittest.TestCase):
    """Review round 2, finding 3 — (h)'s blind spots, on the film's own
    frames: a sharp 13:15 row pasted into the whip (f259, the renderer's
    rect) and 13 px off the renderer's rect (f301, y 994) passed. Both are
    caught now; the frames as rendered are not."""

    @classmethod
    def setUpClass(cls):
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        from test_scenes import events_from_score
        from promo.scenes import Clock, Film
        film = Film(SB, "30s", "9x16", Clock(events_from_score(), 960))
        cls.journal = next(s for s in film.scenes if s.id == "journal")
        label, rect_pt, shown = cls.journal.hidden[0]
        pics = sorted({cls.journal.timeline.index(float(f)) for f in (128, 200, 259, 301, 380, 440, 463)})
        cls.row = HiddenRow("take1b", label, rect_pt, shown, pics)
        cls.frames = {f: film.frame(f) for f in (259, 301)}

    @classmethod
    def tearDownClass(cls):
        cls.row.close()

    def measure(self, f: int, paste_at=None) -> dict:
        frame, rec = self.frames[f]
        L = frame[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722]
        h = rec["hidden"][0]
        row = {"rect": h["rect"], "alpha": h["alpha"], "zoom": rec["zoom"], "whip": h["whip"], "picture": rec["picture"]}
        if paste_at is not None:
            T = self.row.template_at(self.row.base * rec["zoom"])
            x, y = (int(round(v)) for v in paste_at)
            L[y:y + T.shape[0], x:x + T.shape[1]] = T
        return {**row, **self.row.measure(L, row, self.journal.window, 1080)}

    def test_only_the_old_bookings_times_identify_it(self):
        self.assertEqual(len(self.row.parts), 6)
        self.assertEqual(self.row.distinct_mask, [True, False, False, False, False, False])   # « 13:15 / 13:45 »

    def test_the_film_never_shows_it(self):
        for f in (259, 301):
            m = self.measure(f)
            self.assertEqual(HiddenRow.over(m), [], (f, m))

    def test_a_sharp_row_in_the_whip(self):
        _, rec = self.frames[259]
        self.assertTrue(rec["hidden"][0]["whip"])
        m = self.measure(259, paste_at=rec["hidden"][0]["rect"][:2])
        self.assertIsNone(m["visible"])                                   # the whip's own rule cannot see it …
        self.assertTrue(any("found at" in w for w in HiddenRow.over(m)), m)       # … the window search does

    def test_a_row_off_the_renderers_place(self):
        _, rec = self.frames[301]
        x, y = rec["hidden"][0]["rect"][:2]
        self.assertGreater(y - 994, 12)
        m = self.measure(301, paste_at=(x, 994))
        self.assertLessEqual(m["mp4_shows"], 0.25)                        # ±2 px at its place misses it …
        self.assertTrue(any("found at" in w for w in HiddenRow.over(m)), m)       # … the window search does not


class TestLookFrames(unittest.TestCase):
    def test_derived_from_the_film(self):
        """(b)'s full-size frames come from the film's own transitions and
        events (render.json), for any cut — no frame list typed per cut."""
        doc = {"plan": {"transitions": [{"frame": 48, "kind": "cut", "frames": 0},
                                        {"frame": 160, "kind": "whip (in the phone)", "frames": 6},
                                        {"frame": 193, "kind": "dissolve (declared)", "frames": 3}]},
               "events": [[0, "cut into hook"], [100, "ui change"], [120, "word « Créneau »"],
                          [144, "lift arrive-card"], [510, "mark punch"]]}
        looks = look_frames(doc, 512)
        for f in (0, 47, 48, 49, 159, 160, 161, 163, 166, 192, 193, 194, 196, 144, 147, 510, 511):
            self.assertIn(f, looks)
        for f in (100, 103, 120, 513):
            self.assertNotIn(f, looks)


class TestDissolves(unittest.TestCase):
    TL = {"journal": {"take": "take1b", "segments": [
        {"from_frame": 168, "kind": "run", "src_s": 32.165, "rate": 1.0, "gesture": "tap-libre"},
        {"from_frame": 193, "kind": "dissolve", "src_s": 32.998, "to_s": 130.262, "until_frame": 196, "frames": 3,
         "pictures": [78, 4437], "cite": "the App Store film's own"}]}}

    def test_every_dissolve_is_declared_and_forward(self):
        """(h): a dissolve skips footage; render.json must say where it is
        declared, and it never goes back in the take."""
        import copy
        self.assertEqual([d["scene"] for d in dissolves(self.TL)], ["journal"])
        self.assertEqual(dissolve_problems(self.TL), [])
        bad = copy.deepcopy(self.TL)
        bad["journal"]["segments"][1]["cite"] = None
        self.assertTrue(any("not declared" in p for p in dissolve_problems(bad)), dissolve_problems(bad))
        back = copy.deepcopy(self.TL)
        back["journal"]["segments"][1].update(to_s=30.0, pictures=[78, 70])
        self.assertTrue(any("back in the take" in p for p in dissolve_problems(back)), dissolve_problems(back))


class TestBlursChecked(unittest.TestCase):
    def test_every_declared_blur_is_measured(self):
        """(h): the 30-s rule « some blur was measured » failed the 15-s cut,
        which shows no phone number (take1b's placeholder, N1), and passed a
        film that measured one take of two. Now: every take with a blur is
        measured; a film that declares none has nothing to measure."""
        fiche = {"take": "take2b", "pictures_checked": 1, "blurs": ["awa-number"], "most_detail_left": 0.07}
        page = {"take": "take5b", "pictures_checked": 84, "blurs": ["salon-number"], "most_detail_left": 0.11}
        declared = {"take1b": [], "take2b": [{"label": "awa-number"}], "take5b": [{"label": "salon-number"}]}
        self.assertTrue(blurs_checked(declared, [fiche, page]))
        self.assertFalse(blurs_checked(declared, [fiche]))                   # take5b's never measured
        self.assertFalse(blurs_checked(declared, []))
        self.assertTrue(blurs_checked({"take1b": [], "n1": []}, []))          # the 15-s cut: none declared


class TestNothingUnverifiedPasses(unittest.TestCase):
    def test_missing_and_unbuilt(self):
        self.assertIsNone(not_built(SB, "30s", "9x16"))
        self.assertIsNone(not_built(SB, "15s", "9x16"))
        bare = sbmod.load(overrides=["scenes.15s=[]"])
        self.assertIn("no scenes", not_built(bare, "15s", "9x16"))
        for fmt in ("1x1", "16x9"):                                            # every format is laid out
            self.assertIsNone(not_built(SB, "30s", fmt))
            self.assertIsNone(not_built(SB, "15s", fmt))
        self.assertIn("no format 4x5", not_built(SB, "30s", "4x5"))
        self.assertIn("no scenes", not_built(bare, "15s", "16x9"))
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertFalse(verify(bare, ["15s"], ["9x16"], Path(tmp)))
            self.assertFalse(verify(SB, ["15s"], ["9x16"], Path(tmp)))
            self.assertFalse(verify(SB, ["30s"], ["9x16"], Path(tmp)))
            self.assertEqual(verify(SB, ["30s"], ["9x16"], Path(tmp)).status, FAIL)
        self.assertIn("NOT BUILT 15s/9x16", out.getvalue())
        self.assertIn("FAIL 15s/9x16: no film", out.getvalue())
        self.assertIn("FAIL 30s/9x16: no film", out.getvalue())


class TestCommand(unittest.TestCase):
    def test_unbuilt_is_never_a_pass(self):
        from promo.__main__ import main
        with tempfile.TemporaryDirectory() as tmp, contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(main(["verify", "--cut", "15s", "--format", "9x16", "--out", tmp]), 1)
            with self.assertRaisesRegex(SystemExit, "nothing could be built"):
                main(["build", "--cut", "15s", "--format", "1x1", "--set", "scenes.15s=[]", "--out", tmp])
        self.assertIn("NOT BUILT", out.getvalue())


if __name__ == "__main__":
    unittest.main()
