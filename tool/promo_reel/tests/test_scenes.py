"""SCENES: the clock read from events.json, keyframes, the film → take time map,
captions, and the 30-s storyboard as data (every scene end to end on the
score's own cue frames, every line measured, every touch on its click).
A few frames are rendered from the real takes when the material is here."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo import storyboard as sbmod  # noqa: E402
from promo import timebase as tb  # noqa: E402
from promo.audio import find_score  # noqa: E402
from promo.audio import score as score_mod  # noqa: E402
from promo.fx import easing  # noqa: E402
from promo.fx import type as ty  # noqa: E402
from promo.media import tools  # noqa: E402
from promo.scenes.captions import CaptionItem  # noqa: E402
from promo.scenes.clock import Clock, ClockError  # noqa: E402
from promo.scenes.keys import Key, Track, curve  # noqa: E402
from promo.scenes.sources import SourceError, Timeline  # noqa: E402


def events_from_score(cut: str = "30s") -> dict:
    """events.json as the audio engine writes it, from the score's own
    positions (nothing synthesised): bars, beats, cues with frame and sample."""
    sc = score_mod.load(find_score(f"score_{cut}.yaml"))
    beats = [{"pos": f"{b}.{k}.0", "frame": tb.frame_of(b, k), "sample": tb.sample_of_frame(tb.frame_of(b, k))}
             for b in range(1, sc.bars + 1) for k in range(1, 5)]
    cues = []
    for c in sc.cues:
        e = {"id": c.id, "kind": c.kind, "pos": str(c.pos), "frame": c.frame, "sample": c.sample}
        if c.end_frame is not None:
            e["end_frame"], e["end_sample"] = c.end_frame, c.end_sample
        cues.append(e)
    return {"cut": cut, "fps": 30, "bpm": 112.5, "sample_rate": 48000, "frames": sc.frames,
            "bars": [{"bar": b, "frame": tb.frame_of(b), "sample": tb.sample_of_frame(tb.frame_of(b))}
                     for b in range(1, sc.bars + 1)], "beats": beats, "cues": cues}


EVENTS = events_from_score()
SB = sbmod.load()


class TestClock(unittest.TestCase):
    def setUp(self):
        self.clock = Clock(EVENTS, 960)

    def test_times(self):
        F = self.clock.frame
        self.assertEqual(F("cue:drop1.impact"), 128)
        self.assertEqual(F("cue:swipe.open-1"), 159)
        self.assertEqual(F("cue:whip1+6"), 262)
        self.assertEqual(F("cue:reveal.glide@end"), 824)
        self.assertEqual(F("cue:riser1@end"), 108)
        self.assertEqual(F("3.1.2"), 136)
        self.assertEqual(F("5.2&"), 280)
        self.assertEqual(F("2.2.3+3"), 95)
        self.assertEqual(F("end"), 960)                           # 15 bars: the owner's outro bar
        self.assertEqual(F("f149"), 149)
        self.assertEqual(F(17), 17)

    def test_refusals(self):
        F = self.clock.frame
        for bad in ("cue:nope", "cue:hook.stab@end", "3.5.0", "soon", "cue: x"):
            with self.subTest(bad=bad), self.assertRaises(ClockError):
                F(bad)
        with self.assertRaises(ClockError):
            F(True)

    def test_events_must_be_on_the_contract_grid(self):
        with self.assertRaisesRegex(ClockError, "bpm"):
            Clock({**EVENTS, "bpm": 120})
        with self.assertRaisesRegex(ClockError, "frames"):
            Clock(EVENTS, 448)
        beats = [dict(b) for b in EVENTS["beats"]]
        beats[3]["frame"] += 1
        with self.assertRaisesRegex(ClockError, "the grid says"):
            Clock({**EVENTS, "beats": beats})
        cues = [dict(c) for c in EVENTS["cues"]]
        cues[0]["sample"] += 1
        with self.assertRaisesRegex(ClockError, "disagree"):
            Clock({**EVENTS, "cues": cues})

    def test_label(self):
        self.assertEqual(self.clock.label(144), "f144 · 4.800 s · 3.2.0")
        self.assertEqual(self.clock.label(149), "f149 · 4.967 s · 3.2.1+1")


class TestKeysInOrder(unittest.TestCase):
    def test_a_key_written_before_the_one_above_it_is_refused(self):
        """m2's runtime twin of the storyboard check: the renderer sorts nothing."""
        from promo.scenes.base import Context, SceneError, track
        ctx = Context(Clock(EVENTS, 960), SB.formats["9x16"])
        self.assertEqual(track(ctx, [{"at": "5.4.0", "value": 1.0}, {"at": "5.4.2+2", "value": 1.04}], "z")(314), 1.04)
        with self.assertRaisesRegex(SceneError, r"z\[2\]: 5.4.3\+2 is f318, not after the key before it \(f319\)"):
            track(ctx, [{"at": "5.4.0", "value": 1.0}, {"at": "5.4.3+3", "value": 1.04}, {"at": "5.4.3+2", "value": 1.04}], "z")


class TestOneArrivalAtATime(unittest.TestCase):
    def test_two_lines_never_receive_words_on_the_same_frame(self):
        """M1: « moins de gestion. » and « Disponible sur l’App Store » both
        arrived on f848."""
        from promo.scenes.captions import CaptionTrack, arrivals_on_two_lines
        clock = Clock(EVENTS, 960)
        lay = SB.formats["9x16"].layout
        tag = CaptionItem({"type": "tagline", "reveal": "mask", "until": "end",
                           "lines": [[{"w": "Plus de clients,", "at": "cue:end.mark"},
                                      {"w": "moins de gestion.", "at": "cue:end.store"}]]}, "end", clock, lay, "t")
        store = CaptionItem({"type": "store", "reveal": "mask", "until": "end",
                             "lines": [[{"w": "Disponible sur l’App Store", "at": "cue:end.store"}]]}, "end", clock, lay, "s")
        self.assertEqual(arrivals_on_two_lines([tag, store])[0][0], 848)
        with self.assertRaisesRegex(ValueError, "two lines receive words on f848"):
            CaptionTrack([tag, store])
        one = CaptionItem({"type": "tagline", "reveal": "mask", "until": "end",
                           "lines": [[{"w": "Plus de clients, moins de gestion.", "at": "cue:end.mark-5"}]]},
                          "end", clock, lay, "t")
        self.assertEqual(len(CaptionTrack([one, store]).items), 2)            # the card as it is now
        self.assertEqual(store.font.getSize(), 40)


class TestEndCardOutro(unittest.TestCase):
    """Round 3: the owner's outro bar — the end card reads at ≤ 17 cps, and
    two calm events keep the pattern-interrupt rule (≤ 2 s) to the end."""

    def setUp(self):
        self.clock = Clock(EVENTS, 960)
        self.lay = SB.formats["9x16"].layout
        end = next(s for s in SB.cut_scenes("30s") if s["id"] == "end")
        self.specs = {c["id"]: c for c in end["captions"]}

    def items(self, **tagline):
        tag = CaptionItem({**self.specs["tagline"], **tagline}, "end", self.clock, self.lay, "tagline")
        store = CaptionItem(self.specs["store"], "end", self.clock, self.lay, "store")
        return tag, store

    def test_the_marker_is_retired(self):
        with self.assertRaisesRegex(ValueError, "reading: retired"):
            CaptionItem({**self.specs["store"], "reading": "owner_decision_pending"}, "end", self.clock, self.lay, "s")
        self.assertNotIn("reading", self.specs["tagline"])
        self.assertNotIn("reading", self.specs["store"])

    def test_the_end_card_reads_in_time(self):
        from promo.verify import end_card_window, reading_windows
        tag, store = self.items()
        items = [{"what": c.id, "arrive": c.first, "leave": c.until, "chars": len(c.text), "group": c.id,
                  "scene": "end"} for c in (tag, store)]
        w = end_card_window(items, "end", 30)
        self.assertEqual((w["from"], w["to"], w["chars"]), (827, 960, 60))
        self.assertAlmostEqual(w["cps"], 13.53, places=2)                       # was 26.1 cps over f827→f896
        self.assertLessEqual(reading_windows(items, 30)[0]["cps"], 17)

    def test_the_underline(self):
        """The hook's strike comes back as an underline under « moins de
        gestion. » on the outro's downbeat: the font's stem, under the
        descenders, clear of the store line, growing left to right."""
        from promo.scenes.captions import CaptionTrack
        from promo.fx import type as ty
        tag, store = self.items()
        u = tag.underline
        self.assertEqual((u["text"], u["at"], u["frames"]), ("moins de gestion.", 896, 8))
        self.assertAlmostEqual(u["width"], ty.stem_width(tag.font))
        line = tag.ink_boxes()[0]
        self.assertGreaterEqual(u["rect"][1], line[3] + tag.UNDERLINE_GAP - 1e-6)        # under the « g »
        self.assertLess(u["rect"][3], store.ink_boxes()[0][1] - 20)                       # well clear of the store line
        self.assertGreater(u["rect"][0], line[0] + 300)                                   # under the second half only
        self.assertAlmostEqual(u["rect"][2], line[2], delta=1.0)
        self.assertIsNone(tag.underline_rect(895))
        grow = [tag.underline_rect(f)[2] for f in (896, 898, 900, 904, 959)]
        self.assertEqual(grow, sorted(grow))
        self.assertAlmostEqual(grow[-1], u["rect"][2])
        self.assertEqual(len(CaptionTrack([tag, store]).items), 2)

    def test_an_underline_never_covers_text(self):
        """Refused when the stroke would touch a caption's ink — here the store
        line, brought up under the tagline."""
        from promo.scenes.captions import CaptionTrack
        tag, _ = self.items()
        close = CaptionItem({**self.specs["store"], "cap_top": 760}, "end", self.clock, self.lay, "store")
        with self.assertRaisesRegex(ValueError, "underline under « moins de gestion. ».*touches store's ink"):
            CaptionTrack([tag, close])
        with self.assertRaisesRegex(ValueError, "in none of the caption's words"):
            self.items(underline={"text": "plus de gestion", "at": "cue:end.underline"})


class TestTrack(unittest.TestCase):
    def test_interpolation(self):
        tr = Track([Key(10, 0.0), Key(20, 100.0, curve("ease_in_out_cubic"), blur="whip"), Key(30, 100.0)])
        self.assertEqual(tr(0), 0.0)
        self.assertEqual(tr(10), 0.0)
        self.assertAlmostEqual(tr(15), 100 * easing.EASE_IN_OUT_CUBIC(0.5), places=9)   # on the key's curve
        self.assertEqual(tr(20), 100.0)
        self.assertEqual(tr(99), 100.0)
        self.assertEqual(tr.key_into(12).blur, "whip")
        self.assertIsNone(tr.key_into(25))                         # holding: no move, no blur
        self.assertGreater(tr.speed(15), tr.speed(11))
        self.assertAlmostEqual(Track([Key(0, 0), Key(10, 1, curve("ease_out_cubic"))])(5),
                               easing.EASE_OUT_CUBIC(0.5))

    def test_refusals(self):
        with self.assertRaises(ValueError):
            Track([Key(5, 1.0), Key(5, 2.0)])
        with self.assertRaises(ValueError):
            curve("bouncy")


class _Take:
    """Pictures every 1/60 s (10 ticks at 1/600) from 0 to 20 s."""

    timescale = 600

    def __init__(self):
        self.pts = tuple(range(0, 12001, 10))

    @property
    def count(self):
        return len(self.pts)

    def index_at(self, t):
        import bisect
        return bisect.bisect_right(self.pts, int(t * 600 + 1e-6)) - 1

    def time_s(self, i):
        return self.pts[i] / 600


class _Source:
    def __init__(self):
        self.take = _Take()
        self.gestures = {"tap": SimpleNamespace(kind="tap", down_s=5.0),
                         "drag": SimpleNamespace(kind="drag", down_s=8.0)}

    def resolve(self, value, where):
        if isinstance(value, (int, float)):
            return float(value)
        return self.down(value["touch"]).down_s

    def down(self, g):
        return self.gestures[g]


class TestTimeline(unittest.TestCase):
    def setUp(self):
        self.clock = Clock(EVENTS, 960)

    def tl(self, segs):
        return Timeline(_Source(), segs, self.clock, 30, "test")

    def test_hold_run_cap_chain(self):
        t = self.tl([{"at": "f0", "hold": 2.0},
                     {"at": "f30", "src": {"touch": "tap"}, "rate": 1, "src_until": 6.0},
                     {"at": "chain", "src": 6.0, "rate": 0.5, "src_until": 6.5},
                     {"at": "f120", "src": {"touch": "drag"}, "until": "f128", "src_until": 8.73}])
        self.assertEqual(t.src(10), 2.0)
        self.assertEqual(t.src(30), 5.0)
        self.assertAlmostEqual(t.src(45), 5.5)
        self.assertEqual(t.src(59.99), min(6.0, 5.0 + 29.99 / 30))
        self.assertAlmostEqual(t.segments[2].start, 60.0)            # the chain starts where the cap was reached
        self.assertAlmostEqual(t.src(90), 6.5)                      # 0.5× then held at its cap
        self.assertAlmostEqual(t.segments[3].rate, 0.73 / (8 / 30))  # a drag ramp, derived: 2.74×
        self.assertAlmostEqual(t.frame_of(5.0), 30.0)
        self.assertAlmostEqual(t.frame_of(6.25), 75.0)
        self.assertAlmostEqual(t.frame_of(8.0), 120.0)
        self.assertIsNone(t.frame_of(7.0))                           # never shown
        self.assertEqual(t.index(30), 300)                           # the picture at 5.000 s
        self.assertEqual(t.index(30.4), 300)                         # still it (the latest ≤ t) …
        self.assertEqual(t.index(30.5), 301)                         # … until the next, 1/60 s later
        self.assertTrue(t.moving(40) and not t.moving(10))

    def test_a_wait_is_never_sped_up(self):
        with self.assertRaisesRegex(SourceError, "never sped up"):
            self.tl([{"at": "f0", "src": {"touch": "tap"}, "until": "f30", "src_until": 6.5}])   # 1.5×
        self.tl([{"at": "f0", "src": {"touch": "tap"}, "until": "f30", "src_until": 5.95}])      # 0.95× is fine
        with self.assertRaisesRegex(SourceError, "3×"):
            self.tl([{"at": "f0", "src": {"touch": "drag"}, "until": "f8", "src_until": 9.0}])   # 3.75×
        with self.assertRaisesRegex(SourceError, "forward"):
            self.tl([{"at": "f0", "src": 5.0, "rate": -1}])
        with self.assertRaisesRegex(SourceError, "chain"):
            self.tl([{"at": "chain", "src": 1.0}])


class TestCaptions(unittest.TestCase):
    def setUp(self):
        self.clock = Clock(EVENTS, 960)
        self.layout = SB.formats["9x16"].layout

    def test_measured_and_timed(self):
        c = CaptionItem({"until": "cue:whip1", "lines": [[{"w": "Une", "at": "cue:drop1.impact"},
                                                          {"w": "arrive ?", "at": "cue:swipe.touch"}]]},
                        "journal", self.clock, self.layout, "t")
        self.assertFalse(c.visible(126))
        self.assertTrue(c.visible(127))                              # the word's reveal starts one frame early
        self.assertTrue(c.visible(255))
        self.assertFalse(c.visible(256))                             # gone the frame the next caption rises
        self.assertIn(" ?", c.text)                             # French typography
        self.assertEqual(c.colour_on(True), 0xFFFFFFFF)
        self.assertEqual(c.colour_on(False), 0xFF1A1A1A)
        self.assertTrue(c.boxes(150))
        self.assertEqual([b["label"] for b in c.boxes(140)], ["t:Une"])   # « arrive ? » not yet

    def test_a_line_too_wide_is_refused(self):
        with self.assertRaisesRegex(ValueError, "wider than 771"):
            CaptionItem({"until": "end", "lines": [[{"w": "Chaque rendez-vous terminé, compté.", "at": "f0"}]]},
                        "x", self.clock, self.layout, "t")


class TestStoryboard30s(unittest.TestCase):
    """The 30-s scenes as data — no material needed."""

    def setUp(self):
        self.clock = Clock(EVENTS, 960)
        self.scenes = SB.cut_scenes("30s")

    def test_end_to_end_on_the_scores_frames(self):
        spans = [(self.clock.frame(s["from"]), self.clock.frame(s["to"])) for s in self.scenes]
        self.assertEqual(spans[0][0], 0)
        self.assertEqual(spans[-1][1], 960)                     # the end card runs to the new end
        for (a, b), (c, d) in zip(spans, spans[1:]):
            self.assertEqual(b, c)
        self.assertEqual([s["rows"][0] for s in self.scenes], [1, 5, 6, 16, 17, 19, 22, 23, 24])
        self.assertEqual(sorted(r for s in self.scenes for r in s["rows"]), list(range(1, 25)))

    def test_every_caption_measures_and_reads(self):
        from promo.verify import caption_reading
        items = [CaptionItem(c, s["id"], self.clock, SB.formats["9x16"].layout, s["id"])
                 for s in self.scenes for c in s.get("captions", [])]
        self.assertEqual(len(items), 13)
        for c in items:
            for w in c.line_widths():
                self.assertLessEqual(w, 771.0 + 1e-6, c.text)
        rows = caption_reading(items, 30)
        self.assertTrue(all(r["ok"] for r in rows), [r for r in rows if not r["ok"]])

    def test_touches_sit_on_their_clicks(self):
        cues = {c["id"]: c for c in EVENTS["cues"]}
        for s in self.scenes:
            for t in s.get("touches", []):
                at = t["at"]
                if at.startswith("cue:"):
                    cue = cues[at[4:]]
                    kinds = ("click",) if t["gesture"].startswith("tap") or t["gesture"] == "swipe-arrive" \
                        else ("click", "whoosh")
                    self.assertIn(cue["kind"], kinds, t)
                self.assertEqual(self.clock.frame(at) % 4, 0, t)          # on the 16th grid

    def test_the_counter_lands_on_its_cue(self):
        rev = next(s for s in self.scenes if s["id"] == "revenus")
        self.assertEqual(self.clock.frame(rev["counter"]["roll"]["to"]), 548)        # 9.3.1: N1's wait at 0.995×
        self.assertEqual(ty.fcfa(rev["counter"]["end"]), "77 000 FCFA")


class TestEventLogs(unittest.TestCase):
    """N1's gesture log is the recorder's event form (t0 / before / after)."""

    def test_event_form(self):
        import json
        import tempfile
        from promo.media import touches
        rows = [{"event": "t0", "wall": 100.0},
                {"event": "before", "name": "tap-mois", "kind": "tap", "x": 271, "y": 141, "wall": 106.8573},
                {"event": "after", "name": "tap-mois", "wall": 107.3361}]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "gestures.jsonl"
            path.write_text("\n".join(json.dumps(r) for r in rows) + "\n", encoding="utf-8")
            log = touches._from_jsonl(path)
            self.assertEqual(log["gestures"], [{"id": "tap-mois", "kind": "tap", "after_s": 6.857, "at": [271, 141],
                                                "before_s": 7.336}])
            path.write_text("\n".join(json.dumps(r) for r in rows[:2]) + "\n", encoding="utf-8")
            with self.assertRaisesRegex(touches.TouchError, "never came back"):
                touches._from_jsonl(path)
            path.write_text(json.dumps(rows[0]) + "\n" + json.dumps({**rows[1], "kind": "drag"}) + "\n",
                            encoding="utf-8")
            with self.assertRaisesRegex(touches.TouchError, "taps only"):
                touches._from_jsonl(path)

    @unittest.skipUnless(tools.promo_takes_root() is not None, "take N1 is not on this machine")
    def test_n1_touch_downs_from_its_pictures(self):
        from promo.media import touches
        downs = {d.gesture: d for d in touches.touch_downs("n1")}
        self.assertAlmostEqual(downs["tap-mois"].first_change_s, 4411 / 600)      # #1, the tab's ink
        self.assertAlmostEqual(downs["tap-mois"].down_s, 4291 / 600)              # − 200 ms: 7.152 s
        self.assertAlmostEqual(downs["tap-tout"].first_change_s, 8284 / 600)


@unittest.skipUnless(tools.material_available() and tools.promo_takes_root() is not None,
                     "the recorded takes are not on this machine")
class TestFilmFrames(unittest.TestCase):
    """A few real frames, timed by the score's frames (no audio render)."""

    def test_the_end_card_to_the_end(self):
        """The outro's two calm events: the underline drawn f896→f904, the
        mark's punch on the last log (f928), its ink never nearer the tagline
        than half its height; the last frame is the card at rest."""
        end = next(s for s in self.film.scenes if s.id == "end")
        self.assertEqual(end.end, 960)
        ev = dict((f, w) for f, w in self.film.events() if f >= 848)
        self.assertIn("underline « moins de gestion. »", ev.get(896, ""))
        self.assertIn("mark punch", ev.get(928, ""))
        from promo.verify import event_gaps
        self.assertLessEqual(event_gaps([f for f, _ in self.film.events()], 960)[0][0], 60)
        def mark(f):
            _, rec = self.film.frame(f)
            return next(b["rect"] for b in rec["boxes"] if b["kind"] == "mark")
        rest, peak = mark(928), mark(931)
        self.assertGreater(peak[3] - peak[1], (rest[3] - rest[1]) * 1.05)
        self.assertGreaterEqual(712 - peak[3], (rest[3] - rest[1]) / 2)
        self.assertEqual(mark(959), rest)
        _, rec = self.film.frame(904)
        self.assertIn("tagline:underline", [b["label"] for b in rec["boxes"]])

    @classmethod
    def setUpClass(cls):
        from promo.scenes import Film
        cls.film = Film(SB, "30s", "9x16", Clock(EVENTS, 960))

    def test_structure(self):
        self.assertEqual([s.id for s in self.film.scenes],
                         ["hook", "air1", "journal", "fiche", "revenus", "page", "air2", "reveal", "end"])
        kinds = [t["kind"] for t in self.film.transitions()]
        self.assertEqual(kinds.count("whip"), 1)
        self.assertEqual(kinds.count("whip (in the phone)"), 1)

    def test_swipe_touch_down(self):
        frame, rec = self.film.frame(144)
        self.assertEqual(frame.shape, (1920, 1080, 4))
        self.assertEqual([t["gesture"] for t in rec["touch_downs"]], ["swipe-arrive"])
        self.assertAlmostEqual(rec["touch_downs"][0]["src_s"], 10.672, places=2)   # the measured touch-down
        self.assertTrue(all(h["alpha"] < 0.05 for h in rec.get("hidden", [])))   # the 13:15 name under the floor

    def test_the_counter_never_reads_its_figure_early(self):
        """m1: refused when the roll would show « 77 000 FCFA » (or more)
        before the app does."""
        from promo.scenes import Film, SceneError
        rev = next(s for s in self.film.scenes if s.id == "revenus")
        self.assertEqual(rev.counter["overrun"], 4.0)
        bad = sbmod.load(overrides=["scenes.30s.4.counter.roll.overrun=0"])
        with self.assertRaisesRegex(SceneError, r"counter.*on f54[0-7] the counter (already reads|reads .*above)"):
            Film(bad, "30s", "9x16", Clock(EVENTS, 960))

    def test_the_libre_disc_is_gone_before_the_push(self):
        """n1: nothing of the disc on f285 (the push starts on f286)."""
        _, rec = self.film.frame(284)
        self.assertIn("tap-libre", [b["label"] for b in rec["boxes"] if b["kind"] == "touch"])
        _, rec = self.film.frame(285)
        self.assertNotIn("tap-libre", [b["label"] for b in rec["boxes"] if b["kind"] == "touch"])

    def test_the_tiles_wait_in_their_places(self):
        """Round 3 (review: the panel blanked the tiles' places on the first
        lift): every tile still to lift keeps its texture, veiled, in its own
        place until its beat; the panel grows with the lifts."""
        fi = next(s for s in self.film.scenes if s.id == "fiche")
        ups = fi.stack["ups"]
        self.assertEqual(ups, [472.0, 480.0, 488.0])
        for f in (473, 476, 479, 481, 484, 487):
            frame, _ = self.film.frame(f)
            L = frame[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722]
            pose, W = fi.pose(float(f)), fi.W(float(f))
            for i, r in enumerate(fi.stack["tiles_pt"]):
                if f >= ups[i]:
                    continue
                x0, y0, x1, y1 = (int(round(v)) for v in fi.phone.map_rect(r, pose, W=W, window=fi.window))
                self.assertGreater(L[y0 + 4:y1 - 4, x0 + 4:x1 - 4].std(), 20, (f, i))

    def test_the_lifted_tiles_sit_on_a_plain_panel(self):
        """n2: between and around the lifted tiles only the panel shows —
        none of the veiled tiles on the phone."""
        from promo.fx.brand import rgb, token
        frame, rec = self.film.frame(494)
        tiles = sorted((b["rect"] for b in rec["boxes"] if b["label"].startswith("tile")), key=lambda r: r[0])
        self.assertEqual(len(tiles), 3)
        want = np.array(rgb(token("background")))
        # veiled app text would sit ~100 levels off the panel; the cards' own soft shadows stay under 30
        for a, b in zip(tiles, tiles[1:]):                       # the 16-px gaps
            gap = frame[int(a[1]) + 30:int(a[3]) - 30, int(a[2]) + 4:int(b[0]) - 4, :3].astype(int)
            self.assertLess(np.abs(gap - want).max(), 30)
        above = frame[int(tiles[0][1]) - 20:int(tiles[0][1]) - 4, 200:880, :3].astype(int)   # where the
        self.assertLess(np.abs(above - want).max(), 30)                                    # originals were

    def test_the_counter_lands_with_the_app(self):
        _, rec = self.film.frame(548)                               # 9.3.1: N1's wait at 0.995×
        rev = next(s for s in self.film.scenes if s.id == "revenus")
        self.assertEqual(rec["picture"], rev.figure[0])            # the first picture with the figure …
        self.assertIn("77 000 FCFA", [b["label"] for b in rec["boxes"] if b["kind"] == "counter"])
        _, before = self.film.frame(547)
        self.assertNotEqual(before["picture"], rec["picture"])      # … on this frame, not before
        self.assertNotIn(ty.fcfa(77000), [b["label"] for b in before["boxes"] if b["kind"] == "counter"])


if __name__ == "__main__":
    unittest.main()
