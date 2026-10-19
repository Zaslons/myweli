"""SCENES: the clock read from events.json, keyframes, the film → take time map
(its declared dissolve too), captions, and the 30-s and 15-s storyboards as
data (every scene end to end on its score's own cue frames, every line
measured, every touch on its click). A few frames of each cut are rendered
from the real takes when the material is here."""

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
EVENTS15 = events_from_score("15s")
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


class TestHookInk(unittest.TestCase):
    """Round 3's review: in 1:1 the hook's third strike was drawn below the
    frame (its log hit, whoosh and punch played with nothing on screen); in
    16:9 the f48 margin note wrote itself under the black scrim. The
    renderer refuses a layout that draws the hook's animated ink where it
    cannot be seen; the storyboard as written passes in every cut × format."""

    def scene(self, sb, cut: str, fid: str):
        from promo.scenes.base import Context
        from promo.scenes.carnet import CarnetScene
        ev = EVENTS if cut == "30s" else EVENTS15
        ctx = Context(Clock(ev, sb.cuts[cut].frames), sb.formats[fid], fps=30, reference=sb.reference_format)
        return CarnetScene(sb.cut_scenes(cut)[0], ctx, f"scenes.{cut}[0]")

    def test_the_ink_is_seen_in_every_format(self):
        from promo.scenes.carnet import INK_SCRIM_MAX
        for cut in ("30s", "15s"):
            for fid, fmt in SB.formats.items():
                places = self.scene(SB, cut, fid).ink_places()
                self.assertEqual(sum(p["what"].startswith("strike") for p in places), 3, (cut, fid))
                for p in places:
                    self.assertTrue(p["in_canvas"], (cut, fid, p))
                    self.assertLessEqual(p["scrim"], INK_SCRIM_MAX, (cut, fid, p))
                    if fmt.safe_basis == "ebu_r95_graphics":
                        self.assertTrue(p["in_safe"], (cut, fid, p))
        mine = {p["what"]: p for p in self.scene(SB, "30s", "1x1").ink_places()}
        self.assertLessEqual(mine["strike row 19"]["box"][3], 1026)           # the third strike, in the frame

    def test_the_round_3_layouts_are_refused(self):
        from promo.scenes.base import SceneError
        page = sbmod.load(overrides=["formats.1x1.layout.hook_page.x=[40,1040]",
                                     "formats.1x1.layout.hook_page.top=-40"])
        for cut, f in (("30s", "f88"), ("15s", "f40")):
            with self.assertRaisesRegex(SceneError, rf"strike row 19 \({f}.*runs off the 1080×1080 canvas"):
                self.scene(page, cut, "1x1")
        scrim = sbmod.load(overrides=["formats.16x9.layout.hook_scrim={rect: [0, 0, 820, 1080], fade: [200, 0]}"])
        with self.assertRaisesRegex(SceneError, r"ink « margin » \(f48.*under the stage's black"):
            self.scene(scrim, "30s", "16x9")
        self.scene(scrim, "15s", "16x9")                    # no macro, no margin note: nothing under the black

    def test_the_macro_scrim(self):
        sc = self.scene(SB, "30s", "16x9")
        self.assertEqual(sc.scrim_at(40), sc.macro_scrim)                   # the macro (f32–63)
        self.assertEqual(sc.scrim_at(20), sc.scrim)
        self.assertEqual(sc.scrim_at(64), sc.scrim)
        with self.assertRaisesRegex(sbmod.StoryboardError, r"hook_scrim\.macro\.rect.*hold the hook block"):
            sbmod.load(overrides=["formats.16x9.layout.hook_scrim.macro={rect: [0, 0, 600, 400], fade: [200, 140]}"])


class TestRecentredLine(unittest.TestCase):
    """Round 3's review: in the 15-s cut « Créneau libre » sat 136 px left of
    centre for 80 frames, laid out at the width of « Créneau libre rempli. »
    while every other caption on screen is centred. It now sits centred while
    it waits, makes room for « rempli. » over 4 frames and the word rises
    into its place: the finished line exactly where it was."""

    def item(self, cut: str, fid: str, recentre=True):
        spec = next(c for c in next(s for s in SB.cut_scenes(cut) if s["id"] == "journal")["captions"]
                    if c["id"] == "filled")
        if not recentre:
            spec = {k: v for k, v in spec.items() if k != "recentre"}
        clock = Clock(EVENTS if cut == "30s" else EVENTS15, SB.cuts[cut].frames)
        return CaptionItem(spec, "journal", clock, SB.formats[fid].layout, "filled", size=SB.formats[fid].size)

    @staticmethod
    def span(c, f):
        bs = [b["rect"] for b in c.boxes(float(f))]
        return min(r[0] for r in bs), max(r[2] for r in bs), len(bs)

    def test_the_partial_line_is_centred_and_the_line_lands_in_place(self):
        for cut, (a, b) in (("15s", (168, 240)), ("30s", (408, 448))):
            for fid in ("9x16", "1x1"):
                c, still = self.item(cut, fid), self.item(cut, fid, recentre=False)
                cx = SB.formats[fid].layout["caption_centre_x"]
                for f in range(a + 2, b - 5):                                     # « Créneau libre », waiting
                    x0, x1, n = self.span(c, f)
                    self.assertEqual(n, 2)
                    self.assertAlmostEqual((x0 + x1) / 2, cx, delta=3, msg=(cut, fid, f))
                x0, x1, _ = self.span(still, a + 20)
                self.assertGreater(abs((x0 + x1) / 2 - cx), 100)                 # round 3: 136 px off
                for f in range(b, b + 20):                                       # whole: exactly as approved
                    self.assertEqual(c.boxes(float(f)), still.boxes(float(f)), (cut, fid, f))
                fin = self.span(still, b + 10)
                for f in range(a - 8, b + 10):                                   # never past the finished line
                    x0, x1, _ = self.span(c, f)
                    self.assertGreaterEqual(x0, fin[0] - 0.5, (cut, fid, f))
                    self.assertLessEqual(x1, fin[1] + 0.5, (cut, fid, f))

    def test_left_aligned_lines_do_not_move(self):
        c, still = self.item("15s", "16x9"), self.item("15s", "16x9", recentre=False)
        for f in range(160, 256, 3):
            self.assertEqual(c.boxes(float(f)), still.boxes(float(f)), f)

    def test_the_strike_rides_with_its_word(self):
        from promo.fx import type as ty
        c = self.item("15s", "9x16")
        p = c.caption.find("libre")
        for f in (236, 237, 238, 240):
            self.assertAlmostEqual(c.caption.x_at(p, f) - p.x, c.caption.line_dx(p.line, f))
        self.assertGreater(c.caption.line_dx(p.line, 236), 0)                     # moving under its strike …
        self.assertEqual(c.caption.line_dx(p.line, 240), 0.0)                     # … in place for « rempli. »
        with self.assertRaisesRegex(ValueError, "recentre"):
            CaptionItem({**next(c_ for c_ in next(s for s in SB.cut_scenes("15s") if s["id"] == "journal")["captions"]
                                if c_["id"] == "filled"), "recentre": 0}, "journal", Clock(EVENTS15, 512),
                        SB.formats["9x16"].layout, "x", size=(1080, 1920))


class TestTransitionKinds(unittest.TestCase):
    def test_a_scene_names_how_it_is_joined(self):
        import copy
        from promo.scenes.base import Context, SceneError
        from promo.scenes.lottie import EndCardScene
        spec = copy.deepcopy(next(s for s in SB.cut_scenes("30s") if s["id"] == "end"))
        self.assertEqual(spec["transition"], {"kind": "continuous"})
        ctx = Context(Clock(EVENTS, 960), SB.formats["9x16"], fps=30, reference=SB.reference_format)
        for bad in ({"kind": "dissolve"}, {"kind": "cut"}, "whip"):
            with self.assertRaisesRegex(SceneError, r"transition: \{kind: whip \| continuous\}"):
                EndCardScene({**spec, "transition": bad}, ctx, "end")

    def test_a_join_is_held_to_its_name(self):
        from promo.verify import join_problems
        trans = [{"frame": 64, "kind": "cut", "into": "journal"}, {"frame": 376, "kind": "continuous", "into": "end"},
                 {"frame": 256, "kind": "whip", "into": "revenus"}]
        self.assertEqual(join_problems(trans, {64: 239.5, 376: 0.07, 256: 2.8}), [])
        self.assertTrue(join_problems([{**trans[1], "kind": "cut"}], {376: 0.07}))   # round 3's « cut → end »
        self.assertTrue(join_problems(trans[1:2], {376: 30.0}))                         # « continuous » that cuts
        self.assertTrue(join_problems(trans[:1], {}))                                   # not measured: never a pass


class TestEndMarkPunch(unittest.TestCase):
    """The outro's mark punch keeps its ink at least half its height clear of
    the tagline: a 1.2× punch — the variant round 3 refused by hand — is
    refused by the renderer, in every format."""

    def test_a_punch_that_crowds_the_tagline_is_refused(self):
        import copy
        from promo.scenes.base import Context, SceneError
        from promo.scenes.lottie import EndCardScene
        spec = copy.deepcopy(next(s for s in SB.cut_scenes("30s") if s["id"] == "end"))
        for fid, fmt in SB.formats.items():
            ctx = Context(Clock(EVENTS, 960), fmt, fps=30, reference=SB.reference_format)
            sc = EndCardScene(spec, ctx, "end")                                  # as written: 1.06×
            h = sc.ink_end[3] - sc.ink_end[1]
            self.assertGreaterEqual(fmt.layout["end_tagline_cap_top_y"] - (sc.ink_end[3] + h * 0.03), h / 2, fid)
            big = copy.deepcopy(spec)
            big["mark"]["punch"]["peak"] = 1.2
            with self.assertRaisesRegex(SceneError, "at least half its height", msg=fid):
                EndCardScene(big, ctx, "end")


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

    def test_a_declared_dissolve(self):
        """The 15-s cut's one dissolve (32.998 → 130.262): the picture on
        screen blends into a later one on the app's base easeInOut; the
        footage between is never shown."""
        t = self.tl([{"at": "f0", "hold": 2.0},
                     {"at": "f30", "dissolve": 10.0, "until": "f36", "cite": "test"},
                     {"at": "f36", "src": 10.0, "rate": 1}])
        self.assertIsNone(t.dissolve_at(29.9))
        seg, a, b, u = t.dissolve_at(30)
        self.assertEqual((a, b, u), (120, 600, 0.0))                 # the picture it leaves, whole
        self.assertLess(t.dissolve_at(31)[3], 1 / 6)                 # eases in
        self.assertAlmostEqual(t.dissolve_at(33)[3], 0.5)            # half way
        self.assertIsNone(t.dissolve_at(36))                         # whole on `until`
        self.assertEqual((t.index(31), t.index(34), t.index(36)), (120, 600, 600))   # the picture that dominates
        self.assertIsNone(t.frame_of(8.0))                           # skipped: never shown
        rep = t.report()[1]
        self.assertEqual((rep["kind"], rep["to_s"], rep["pictures"], rep["frames"], rep["cite"]),
                         ("dissolve", 10.0, [120, 600], 6.0, "test"))
        self.assertNotIn("rate", rep)

    def test_a_dissolve_is_declared_and_goes_forward(self):
        """The App Store film's rules (E_DISSOLVE, E_ORDER): a dissolve is
        the only way to skip footage in which the screen changes, so it is
        declared, and it never goes back in the take."""
        with self.assertRaisesRegex(SourceError, "declared"):
            self.tl([{"at": "f0", "hold": 2.0}, {"at": "f30", "dissolve": 10.0, "until": "f36"}])
        with self.assertRaisesRegex(SourceError, "back in the take"):
            self.tl([{"at": "f0", "hold": 12.0}, {"at": "f30", "dissolve": 10.0, "until": "f36", "cite": "x"}])
        with self.assertRaisesRegex(SourceError, "back in the take"):
            self.tl([{"at": "f0", "hold": 10.0}, {"at": "f30", "dissolve": 10.005, "until": "f36", "cite": "x"}])
        with self.assertRaisesRegex(SourceError, "segment before it"):
            self.tl([{"at": "f0", "dissolve": 10.0, "until": "f6", "cite": "x"}])
        with self.assertRaisesRegex(SourceError, "until"):
            self.tl([{"at": "f0", "hold": 2.0}, {"at": "f30", "dissolve": 10.0, "cite": "x"}])


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
        items = [CaptionItem(c, s["id"], self.clock, SB.formats["9x16"].layout, s["id"], size=(1080, 1920))
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


class TestStoryboard15s(unittest.TestCase):
    """The 15-s scenes as data — no material needed: « The 15 s cut » laid
    out on the 15-s score's own frames, the 30-s blocks it shares unchanged."""

    def setUp(self):
        self.clock = Clock(EVENTS15, 512)
        self.scenes = SB.cut_scenes("15s")
        self.by_id = {s["id"]: s for s in self.scenes}
        self.s30 = {s["id"]: s for s in SB.cut_scenes("30s")}

    def test_end_to_end_on_the_scores_frames(self):
        spans = [(s["id"], self.clock.frame(s["from"]), self.clock.frame(s["to"])) for s in self.scenes]
        self.assertEqual(spans, [("hook", 0, 48), ("air1", 48, 64), ("journal", 64, 256), ("revenus", 256, 320),
                                 ("reveal", 320, 376), ("end", 376, 512)])
        self.assertEqual(sorted({r for s in self.scenes for r in s["rows"]}), list(range(1, 9)))   # BAR 1–7 + the outro

    def test_the_shared_blocks_are_the_30s_own(self):
        def but(d, *keys):
            return {k: v for k, v in d.items() if k not in keys}
        for sid in ("air1", "reveal", "end"):
            self.assertEqual(but(self.by_id[sid], "rows"), but(self.s30[sid], "rows"), sid)
        rev, rev30 = self.by_id["revenus"], self.s30["revenus"]
        self.assertEqual(but(rev, "rows", "to", "counter", "lifts", "captions"),
                         but(rev30, "rows", "to", "counter", "lifts", "captions"))
        self.assertEqual(rev["counter"], {**rev30["counter"], "exit": None})          # alone to the cut
        self.assertEqual((rev["lifts"], rev["captions"]), ([], []))
        j, j30 = self.by_id["journal"], self.s30["journal"]
        self.assertEqual(j["hidden"], j30["hidden"])                                  # the same hiding rule
        self.assertEqual(j["lifts"], [{**j30["lifts"][0], "down": "3.2.2+2"}])

    def test_every_caption_measures_and_reads(self):
        from promo.scenes.captions import arrivals_on_two_lines
        from promo.verify import caption_reading
        items = [CaptionItem(c, s["id"], self.clock, SB.formats["9x16"].layout, s["id"], size=(1080, 1920))
                 for s in self.scenes for c in s.get("captions", [])]
        self.assertEqual([c.id for c in items], ["hook-question", "breathe", "arrive", "filled", "tagline", "store"])
        for c in items:
            for w in c.line_widths():
                self.assertLessEqual(w, 771.0 + 1e-6, c.text)
        rows = caption_reading(items, 30)
        self.assertTrue(all(r["ok"] for r in rows), [r for r in rows if not r["ok"]])
        self.assertEqual([(r["chars"], r["seconds"]) for r in rows[2:4]], [(38, 3.2), (21, 3.2)])   # the storyboard's
        self.assertEqual(arrivals_on_two_lines(items), [])

    def test_touches_sit_on_their_clicks(self):
        cues = {c["id"]: c for c in EVENTS15["cues"]}
        touches = self.by_id["journal"]["touches"] + self.by_id["revenus"]["touches"]
        self.assertEqual([self.clock.frame(t["at"]) for t in touches], [64, 88, 168, 196, 272])
        for t in touches:
            self.assertEqual(cues[t["at"][4:]]["kind"], "click", t)

    def test_the_counter_lands_on_its_cue(self):
        c = self.by_id["revenus"]["counter"]
        self.assertEqual((self.clock.frame(c["label_switch"]), self.clock.frame(c["roll"]["to"])), (280, 292))
        self.assertIsNone(c["exit"])

    def test_one_declared_dissolve(self):
        j = self.by_id["journal"]
        d = [s for s in j["timeline"] if "dissolve" in s]
        self.assertEqual(len(d), 1)
        self.assertEqual((self.clock.frame(d[0]["at"]), self.clock.frame(d[0]["until"]), d[0]["dissolve"]),
                         (193, 196, 130.262))
        self.assertIn("storyboard-scenes.json", d[0]["cite"])
        W = {self.clock.frame(k["at"]): k["value"] for k in j["camera"]["W"]}
        self.assertEqual((W[193], W[196]), (667, 521.67))             # re-framed by the fields' measured 145.33 pt


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
        self.assertEqual([(t["frame"], t["into"]) for t in self.film.transitions() if t["kind"] == "continuous"],
                         [(824, "end")])                                       # the mark eases on: no cut

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


@unittest.skipUnless(tools.material_available() and tools.promo_takes_root() is not None,
                     "the recorded takes are not on this machine")
class TestFilmFrames15s(unittest.TestCase):
    """A few real frames of the 15-s cut, timed by its score's frames."""

    @classmethod
    def setUpClass(cls):
        from promo.scenes import Film
        cls.film = Film(SB, "15s", "9x16", Clock(EVENTS15, 512))
        cls.frames = {f: cls.film.frame(f) for f in (192, 193, 194, 196)}

    def test_structure(self):
        self.assertEqual([s.id for s in self.film.scenes], ["hook", "air1", "journal", "revenus", "reveal", "end"])
        tr = {(t["frame"], t["kind"]) for t in self.film.transitions()}
        # the storyboard's JOINS: cuts f48 / f64 / f320, whips f160 / f256, the dissolve f193 — six; the
        # reveal → end handoff on f376 is continuous (the mark keeps easing), not a seventh (review round 3)
        self.assertEqual(tr, {(48, "cut"), (64, "cut"), (160, "whip (in the phone)"), (193, "dissolve (declared)"),
                              (256, "whip"), (320, "cut"), (376, "continuous")})
        self.assertIn((376, "continuous into end"), self.film.events())

    def test_the_dissolve_is_an_exact_cross_fade(self):
        """f194 is (1 − u) × the form on 32.998 through W 667 + u × the form
        on 130.262 through W 521.67 — the frames either side (f193 shows the
        first whole; f196 the second, its disc below the rows compared)."""
        a, b = self.frames[193][0], self.frames[196][0]
        m, rec = self.frames[194]
        u = rec["dissolve"]["blend"]
        self.assertTrue(0.2 < u < 0.8, u)
        self.assertEqual(rec["dissolve"]["W"], [667.0, 521.67])
        rows = slice(600, 1100)
        want = (1 - u) * a[rows, :, :3].astype(float) + u * b[rows, :, :3].astype(float)
        self.assertLessEqual(np.abs(m[rows, :, :3].astype(float) - want).max(), 2.0)
        self.assertEqual(self.frames[193][1]["dissolve"]["blend"], 0.0)      # f193: the first picture alone

    def test_the_fields_stay_in_place(self):
        """The fields both pictures show (« Client sans numéro », the name,
        the note) sit on the same rows before and after: the camera's
        re-frame is the form's measured shift."""
        L = {f: self.frames[f][0][..., :3].astype(float) @ [0.2126, 0.7152, 0.0722] for f in (192, 196)}
        sw = (slice(660, 700), slice(300, 560))            # « Client sans numéro » (its box is ticked only after)
        self.assertLess(float(np.abs(L[192][sw] - L[196][sw]).mean()), 1.0)

        def note(dy: int) -> float:                        # « Note (optionnel) », on rows dy apart
            return float(np.abs(L[192][860 + dy:960 + dy, 200:880] - L[196][860:960, 200:880]).mean())
        self.assertLess(note(0), 2.0)
        self.assertLess(note(0), min(note(-2), note(2)))   # on the same rows, not 2 px off

    def test_no_disc_on_a_dissolve(self):
        """A dissolve blends two pictures at rest: a disc still showing on
        its frames (the « Libre » tap released late) is refused."""
        from promo.scenes import Film, SceneError
        bad = sbmod.load(overrides=["scenes.15s.2.touches.2.release_by=4.1.0+2"])
        with self.assertRaisesRegex(SceneError, "dissolve"):
            Film(bad, "15s", "9x16", Clock(EVENTS15, 512))

    def test_the_end_card_like_the_30s(self):
        ev = dict((f, w) for f, w in self.film.events() if f >= 400)
        self.assertIn("underline « moins de gestion. »", ev.get(448, ""))
        self.assertIn("mark punch", ev.get(480, ""))
        from promo.verify import event_gaps
        self.assertLessEqual(event_gaps([f for f, _ in self.film.events()], 512)[0][0], 60)


if __name__ == "__main__":
    unittest.main()
