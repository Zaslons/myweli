"""ONE storyboard → three formats (storyboard « 1:1 and 16:9 »): every
format's layout is checked; the scenes take every place from it (captions,
the counter, lifts, the hook's page, the map credit) and re-frame the camera
from the reference window by each W key's `keep`; the old 13:15 row stays
out of every window; verify's ink regions stay clear of the phone; every
format of a cut holds one soundtrack. A few real frames per format when the
takes are on this machine."""

from __future__ import annotations

import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import yaml  # noqa: E402

from promo import storyboard as sbmod  # noqa: E402
from promo.fx import brand, counter, lift as liftmod  # noqa: E402
from promo.fx import surface  # noqa: E402
from promo.fx import type as ty  # noqa: E402
from promo.media import tools  # noqa: E402
from promo.scenes.captions import CaptionItem  # noqa: E402
from promo.scenes.clock import Clock  # noqa: E402
from promo.scenes.phone import camera_W_keys, keep_offset, window_for  # noqa: E402
from promo.storyboard import Rect, covered_by  # noqa: E402

from test_scenes import EVENTS, EVENTS15  # noqa: E402

SB = sbmod.load()
STARTER = sbmod.DEFAULT_PATH.read_text(encoding="utf-8")
FORMATS = ("9x16", "1x1", "16x9")
CLOCKS = {"30s": Clock(EVENTS, 960), "15s": Clock(EVENTS15, 512)}
REF = window_for(SB.formats["9x16"])
HIDDEN = (36, 612.7, 361.3, 644.0)                       # the old 13:15 « Yao K. » row (take1b, pt)


def problems(*overrides: str, text: str = STARTER) -> list[str]:
    try:
        sbmod.loads(text, overrides=overrides)
    except sbmod.StoryboardError as e:
        return e.problems
    return []


def with_doc(change) -> str:
    doc = yaml.safe_load(STARTER)
    change(doc)
    return yaml.safe_dump(doc, allow_unicode=True, sort_keys=False)


class TestLayoutSchema(unittest.TestCase):
    """storyboard.py: each format says where things go, and is held to it."""

    def assertProblem(self, found: list[str], *parts: str):
        self.assertTrue(any(all(p in f for p in parts) for f in found), f"{parts} not in {found}")

    def test_one_reference_format(self):
        self.assertEqual(SB.reference_format.id, "9x16")
        self.assertProblem(problems("formats.1x1.reference=true"), "formats", "exactly ONE", "have 2")
        self.assertProblem(problems(text=with_doc(lambda d: d["formats"]["9x16"].pop("reference"))),
                           "formats", "exactly ONE", "have 0")
        self.assertProblem(problems("formats.9x16.reference=yes please"), "formats.9x16.reference", "true or false")

    def test_caption_placement(self):
        self.assertProblem(problems("formats.16x9.layout.caption_align=centre"), "16x9.layout.caption_align",
                           "`caption_centre_x`, which is not given")
        self.assertProblem(problems("formats.9x16.layout.caption_align=left"), "9x16.layout.caption_align",
                           "must be null")
        self.assertProblem(problems("formats.9x16.layout.caption_align=right"), "caption_align", "one of centre, left")
        self.assertProblem(problems("formats.1x1.layout.caption_cap_top.app=null"), "1x1.layout.caption_cap_top.app",
                           "`caption_centre_y`, which is not given")
        self.assertProblem(problems(text=with_doc(lambda d: d["formats"]["1x1"]["layout"]["caption_cap_top"].pop("hook"))),
                           "1x1.layout.caption_cap_top", "missing key 'hook'")

    def test_places(self):
        self.assertProblem(problems("formats.16x9.layout.lift_y.tile_row={centre_y: 40}"),
                           "16x9.layout.lift_y.tile_row", "outside the overlays zone")
        self.assertProblem(problems("formats.9x16.layout.lift_y.tile_row={centre_y: 815, bottom: 900}"),
                           "9x16.layout.lift_y.tile_row", "must be ONE of")
        self.assertProblem(problems(text=with_doc(lambda d: d["formats"]["1x1"]["layout"]["lift_y"].pop("tile_row"))),
                           "1x1.layout.lift_y", "missing key 'tile_row'")
        self.assertProblem(problems("formats.1x1.layout.counter_baselines=[284, 110]"),
                           "1x1.layout.counter_baselines", "the label above")
        self.assertProblem(problems("formats.1x1.layout.map_credit.align=centre"), "map_credit.align", "one of left, right")
        self.assertProblem(problems("formats.16x9.layout.hook_scrim.rect=[0, 0, 400, 1080]"),
                           "16x9.layout.hook_scrim.rect", "hook block's columns")
        self.assertProblem(problems("formats.16x9.layout.hook_page.pivot=[2400, 560]"), "hook_page.pivot", "off the")
        self.assertProblem(problems(text=with_doc(lambda d: d["formats"]["16x9"]["layout"].pop("map_credit"))),
                           "formats.16x9.layout", "missing key 'map_credit'")


class TestCameraKeeps(unittest.TestCase):
    """W keys measured in the 9:16 window, re-framed by what they keep."""

    def test_windows(self):
        got = {f: (w.screen_x, w.top, w.band_fade, w.floor, w.floor_fade) for f, w in
               ((f, window_for(SB.formats[f])) for f in FORMATS)}
        # 9:16 to the owner's floor (y 1424); 1:1's band edge on the journal's chip row (y 388); 16:9 taller, to
        # y 1026, its phone standing on the floor (the band edge comes down with W: Window.anchor_bottom), its
        # screen at x 1088 so the bezel ends on the graphics-safe edge (review round 5: x 1104 put it at 1840)
        self.assertEqual(got, {"9x16": (180, 600, 40, 1424, 24), "1x1": (180, 388, 30, 1002, 24),
                               "16x9": (1088, 84, 30, 1026, 24)})       # 16:9: W under its 30-px top fade

    def test_the_reference_is_untouched(self):
        for cut in ("30s", "15s"):
            for sc in SB.cut_scenes(cut):
                ks = (sc.get("camera") or {}).get("W")
                if not ks:
                    continue
                got = camera_W_keys(ks, REF, REF, 56.0, "W")
                self.assertEqual([k["value"] for k in got], [float(k["value"]) for k in ks], sc["id"])
                self.assertTrue(all("keep" not in k for k in got))

    def test_keep_rules(self):
        w11, w169 = window_for(SB.formats["1x1"]), window_for(SB.formats["16x9"])
        self.assertEqual(keep_offset("top", w11, REF), 0.0)
        self.assertAlmostEqual(128 + keep_offset("floor", w11, REF), 128 + 210 / 1.791)        # 245.25: the chips
        self.assertAlmostEqual(312.73 + keep_offset("centre", w11, REF), 312.73 + 105 / 1.791)  # 371.36
        self.assertAlmostEqual(128 + keep_offset("floor", w169, REF), 128 - 118 / 1.791)       # 62.12
        keys = camera_W_keys([{"at": 0, "value": 312.73, "keep": "centre"}, {"at": 1, "value": 56},
                              {"at": 2, "value": 667, "keep": "top"}, {"at": 3, "value": 667}], w169, REF, 56.0, "W")
        self.assertEqual([round(k["value"], 2) for k in keys], [279.79, 56.0, 667.0, 667.0])   # inherited; clamped
        with self.assertRaisesRegex(Exception, "keep is one of top, centre, floor"):
            camera_W_keys([{"at": 0, "value": 1, "keep": "middle"}], w11, REF, 56.0, "W")

    def test_the_old_1315_row_stays_out_of_every_window(self):
        """Its place, in every format: under the floor while Fatou B.'s card
        sits on it (bars 3–4 / the 15-s bar 2), above the window's top edge
        on the lower journal — framing only, the rule the 9:16 measured."""
        for cut in ("30s", "15s"):
            journal = next(s for s in SB.cut_scenes(cut) if s["id"] == "journal")
            for fid in FORMATS:
                base = window_for(SB.formats[fid])
                keys = camera_W_keys(journal["camera"]["W"], base, REF, 56.0, "W")
                floor_W = next(k["value"] for k, raw in zip(keys, journal["camera"]["W"]) if raw["value"] == 128)
                top_W = next(k["value"] for k, raw in zip(keys, journal["camera"]["W"]) if raw["value"] == 667)
                with self.subTest(cut=cut, fmt=fid):
                    win = base.at_top(base.top_for(floor_W))                     # the window each framing shows
                    self.assertGreaterEqual(win.y_of(HIDDEN[1], floor_W), win.floor + win.floor_fade)
                    self.assertGreaterEqual(win.y_of(582.0, floor_W), win.floor - 16)      # the card on the floor
                    self.assertLessEqual(win.y_of(582.0, floor_W), win.floor)
                    win = base.at_top(base.top_for(top_W))                       # 16:9: the band edge came down
                    self.assertLessEqual(win.y_of(HIDDEN[3], top_W), win.top - win.band_fade)


class TestScenesCarryNoPixelPositions(unittest.TestCase):
    """Where things go is the format's: a scene that writes its own position
    is refused (the page's rest/pivot, the macro's target)."""

    def test_the_carnet(self):
        from promo.scenes.base import Context, SceneError
        from promo.scenes.carnet import CarnetScene
        hook = next(s for s in SB.cut_scenes("30s") if s["id"] == "hook")
        ctx = Context(CLOCKS["30s"], SB.formats["16x9"], reference=SB.reference_format)
        sc = CarnetScene(hook, ctx, "hook")
        self.assertEqual(sc.pivot, tuple(float(v) for v in SB.formats["16x9"].layout["hook_page"]["pivot"]))
        self.assertEqual(sc.macro["to"], (1340.0, 640.0))
        for key, value in (("pivot", [540, 1250]), ("rest", {"x": [40, 1040], "top": 640})):
            with self.subTest(key=key), self.assertRaisesRegex(SceneError, f"carnet.{key}: .*layout.hook_page"):
                CarnetScene({**hook, "carnet": {**hook["carnet"], key: value}}, ctx, "hook")
        with self.assertRaisesRegex(SceneError, "macro.focus_to: .*hook_page.macro_to"):
            CarnetScene({**hook, "carnet": {**hook["carnet"], "macro": {**hook["carnet"]["macro"],
                                                                       "focus_to": [540, 1200]}}}, ctx, "hook")

    def test_the_scrim_over_the_page(self):
        """9:16's scrim is the round-3 band (black to y 520, gone by 640);
        16:9's covers the left, where the words are, fading to the right."""
        from promo.scenes.base import Context
        from promo.scenes.carnet import CarnetScene
        hook = next(s for s in SB.cut_scenes("15s") if s["id"] == "hook")
        for fid, black, clear in (("9x16", (540, 500), (540, 660)), ("16x9", (500, 900), (1100, 300))):
            f = SB.formats[fid]
            sc = CarnetScene(hook, Context(CLOCKS["15s"], f, reference=SB.reference_format), "hook")
            s_ = surface.new_surface(*f.size)
            c = s_.getCanvas()
            c.clear(0xFFFFFFFF)
            sc.draw_scrim(c)
            a = surface.to_array(s_)
            with self.subTest(fmt=fid):
                self.assertEqual(tuple(a[black[1], black[0], :3]), (0, 0, 0))
                self.assertEqual(tuple(a[clear[1], clear[0], :3]), (255, 255, 255))


class TestCaptionsEveryFormat(unittest.TestCase):
    def items(self, cut: str, fid: str) -> list[CaptionItem]:
        f = SB.formats[fid]
        return [CaptionItem(c, s["id"], CLOCKS[cut], f.layout, s["id"], size=f.size)
                for s in SB.cut_scenes(cut) for c in s.get("captions", [])]

    def test_every_line_in_its_place(self):
        for cut in ("30s", "15s"):
            for fid in FORMATS:
                f = SB.formats[fid]
                col = f.layout["caption_column_x"]
                for c in self.items(cut, fid):
                    inks = [ty.ink_bounds(p.word.text, c.font, p.x, p.baseline) for p in c.caption.placed]
                    box = Rect(min(b[0] for b in inks), min(b[1] for b in inks), max(b[2] for b in inks),
                               max(b[3] for b in inks))
                    with self.subTest(cut=cut, fmt=fid, caption=c.id):
                        self.assertTrue(covered_by(box, list(f.text_area)), box)
                        if c.in_column:
                            self.assertGreaterEqual(box.x0, col[0])
                            self.assertLessEqual(box.x1, col[1])
                        if c.kind in ("tagline", "store"):          # centred on the mark's axis
                            self.assertAlmostEqual((c.caption.placed[0].x + c.caption.placed[-1].x
                                                    + c.caption.placed[-1].width) / 2, f.layout["lottie_centre"][0])
                        if c.id == "breathe":                       # centred on the canvas
                            self.assertFalse(c.in_column)
                            self.assertAlmostEqual(c.caption.placed[0].x + c.caption.placed[0].width / 2, f.width / 2)

    def test_16x9_sets_its_lines_from_the_columns_edge(self):
        for c in self.items("30s", "16x9"):
            if not c.in_column:
                continue
            firsts = [p for p in c.caption.placed if p is next(q for q in c.caption.placed if q.line == p.line)]
            self.assertEqual(len({round(p.x, 3) for p in firsts}), 1, c.id)          # one left edge
            ink0 = min(ty.ink_bounds(p.word.text, c.font, p.x, p.baseline)[0] for p in firsts)
            self.assertAlmostEqual(ink0, 96.0, delta=6.5, msg=c.id)                 # on the edge, never past it
            self.assertGreaterEqual(ink0, 96.0)
        # a first glyph that overhangs its origin (Poppins « j »: 4 px at 72 px) moves the lines in by that much
        f = SB.formats["16x9"]
        c = CaptionItem({"lines": [[{"w": "jamais", "at": 0}], [{"w": "vu", "at": 8}]], "until": 30}, "t",
                        CLOCKS["30s"], f.layout, "t", size=f.size)
        inks = [ty.ink_bounds(p.word.text, c.font, p.x, p.baseline)[0] for p in c.caption.placed]
        self.assertEqual(min(inks), 96.0)
        self.assertEqual(c.caption.placed[0].x, c.caption.placed[1].x)            # one left edge for both lines

    def test_boxes_say_where_they_are_laid(self):
        items = {c.id: c for c in self.items("30s", "16x9")}
        self.assertTrue(all(b["column"] for b in items["arrive"].boxes(200.0)))
        self.assertFalse(any(b["column"] for b in items["tagline"].boxes(900.0)))


class TestPlacesEveryFormat(unittest.TestCase):
    """Lifts and tiles land where the format puts them: inside the overlays
    zone and the safe area, 780 px wide (16:9: 760, beside the phone)."""

    def test_lift_targets(self):
        k = 3.0                                                     # capture px a point
        for fid in FORMATS:
            f = SB.formats[fid]
            lay, ov = f.layout, f.zones["overlays"]
            x0, x1 = lay["lift_x"]
            slab_x0 = lay["phone_screen_x"][0] - lay["phone_bezel_px"]
            for cut in ("30s", "15s"):
                for sc in SB.cut_scenes(cut):
                    for L in sc.get("lifts") or []:
                        src = tuple(v * k for v in L["rect_pt"])
                        place = {n: float(v) for n, v in lay["lift_y"][L["target"]["y"]].items()}
                        r = Rect(*liftmod.fit_width(src, x0, x1, **place))
                        with self.subTest(fmt=fid, cut=cut, lift=L["id"]):
                            self.assertTrue(ov.contains(r) and f.safe.contains(r), r)
                            if fid == "16x9":
                                self.assertLess(r.x1, slab_x0)              # beside the phone, not over it
            self.assertEqual(x1 - x0, 760 if fid == "16x9" else 780)


class TestOdometerHoldsItsEdge(unittest.TestCase):
    def test_a_left_aligned_punch_keeps_the_left_edge(self):
        """16:9: the counter is set from the column's edge (x 96); its 1.08
        landing punch must not push the figure past it."""
        f = brand.poppins(120)
        o = counter.Odometer(0, 77000, f, brand.PALETTE.INK)

        def left_ink(scale: float, align: str, x: float) -> int:
            s = surface.new_surface(1400, 300)
            c = s.getCanvas()
            c.clear(0xFFFFFFFF)
            o.draw(c, 1.0, x, 200, align=align, scale=scale)
            a = surface.to_array(s)
            return int(np.nonzero(np.any(a[..., :3] < 200, axis=(0, 2)))[0][0])

        rest = left_ink(1.0, "left", 200)
        self.assertGreaterEqual(left_ink(1.08, "left", 200), rest - 1)
        self.assertLess(left_ink(1.08, "centre", 700), left_ink(1.0, "centre", 700) - 20)   # centred: about the middle


class TestInkRegions(unittest.TestCase):
    def test_clear_of_phone(self):
        from promo.verify import clear_of_phone
        phone = (1088, 54, 1840, 1026)
        self.assertEqual(clear_of_phone((0, 380, 1920, 500), phone, (400, 440)), (0, 380, 1086, 500))   # beside
        self.assertEqual(clear_of_phone((0, 58, 1080, 338), (164, 300, 916, 1026), (540, 200)), (0, 58, 1080, 300))
        self.assertEqual(clear_of_phone((90, 1187, 477, 1272), (164, 560, 916, 1216), (283, 1229)),
                         (90, 1216, 477, 1272))                                              # below (the floor)
        self.assertEqual(clear_of_phone((72, 990, 948, 1238), (164, 560, 916, 1216), (510, 1114)),
                         (72, 990, 948, 1238))                          # a lift over the veiled phone keeps its region
        self.assertEqual(clear_of_phone((0, 0, 100, 100), phone, (50, 50)), (0, 0, 100, 100))
        self.assertEqual(clear_of_phone((0, 0, 100, 100), None, (50, 50)), (0, 0, 100, 100))

    def test_hook_words_are_measured_on_their_scrim(self):
        from types import SimpleNamespace
        from promo.verify import on_its_ground
        hook = SimpleNamespace(scrim=((0.0, 0.0, 820.0, 1080.0), (200.0, 0.0)))     # 16:9
        self.assertEqual(on_its_ground(hook, (0, 50, 1920, 480)), (0, 50, 1020, 480))
        band = SimpleNamespace(scrim=((0.0, 0.0, 1080.0, 520.0), (0.0, 120.0)))     # 9:16: unchanged up to 640
        self.assertEqual(on_its_ground(band, (0, 255, 1080, 641)), (0, 255, 1080, 640))
        self.assertEqual(on_its_ground(SimpleNamespace(), (0, 1, 2, 3)), (0, 1, 2, 3))

    def test_only_column_captions_are_held_to_the_column(self):
        from promo.verify import outside_safe
        f = SB.formats["16x9"]
        rec = [{"f": 0, "boxes": [{"kind": "caption", "label": "tagline", "column": False, "rect": [580, 535, 1340, 586]},
                                  {"kind": "caption", "label": "breathe", "column": False, "rect": [753, 498, 1170, 600]}]}]
        self.assertEqual(outside_safe(rec, f), (2, []))
        rec[0]["boxes"][0]["column"] = True
        self.assertEqual(len(outside_safe(rec, f)[1]), 1)


class TestOneSoundtrack(unittest.TestCase):
    def films(self, tmp: Path, contents: dict[str, bytes]) -> None:
        for fid, wav in contents.items():
            d = tmp / f"30s-{fid}"
            d.mkdir(parents=True)
            (d / "reel.mp4").write_bytes(b"mp4")
            (d / "track.wav").write_bytes(wav)
            (d / "events.json").write_text(json.dumps(EVENTS), encoding="utf-8")

    def test_every_format_of_a_cut_holds_the_same_track(self):
        from promo.verify import same_soundtrack
        with tempfile.TemporaryDirectory() as tmp:
            self.films(Path(tmp), {"9x16": b"A", "1x1": b"A", "16x9": b"A"})
            ok, what = same_soundtrack(SB, "30s", Path(tmp))
            self.assertTrue(ok, what)
            self.assertIn("in 3 formats", what)
        with tempfile.TemporaryDirectory() as tmp:
            self.films(Path(tmp), {"9x16": b"A", "1x1": b"A", "16x9": b"B"})
            ok, what = same_soundtrack(SB, "30s", Path(tmp))
            self.assertFalse(ok)
            self.assertIn("DIFFER", what)
        with tempfile.TemporaryDirectory() as tmp:
            self.films(Path(tmp), {"9x16": b"A", "1x1": b"A"})
            (Path(tmp) / "30s-1x1" / "events.json").write_text(json.dumps({**EVENTS, "frames": 959}), encoding="utf-8")
            self.assertFalse(same_soundtrack(SB, "30s", Path(tmp))[0])

    def test_a_build_renders_the_soundtrack_once_per_cut(self):
        from promo.render import AUDIO_FILES, sha256, share_audio
        with tempfile.TemporaryDirectory() as tmp:
            src, out = Path(tmp) / "30s-9x16", Path(tmp) / "30s-1x1"
            src.mkdir()
            (src / "events.json").write_text(json.dumps(EVENTS), encoding="utf-8")
            (src / "track.wav").write_bytes(b"RIFF....")
            with contextlib.redirect_stdout(io.StringIO()):
                clock = share_audio(src, out, 960)
            self.assertEqual(clock.frames, 960)
            for name in ("events.json", "track.wav"):
                self.assertEqual(sha256(out / name), sha256(src / name))
            self.assertIn("events.json", AUDIO_FILES)


@unittest.skipUnless(tools.material_available() and tools.promo_takes_root() is not None,
                     "the recorded takes are not on this machine")
class TestFilmFramesEveryFormat(unittest.TestCase):
    """Real frames of the 1:1 and 16:9 films (the same scenes, laid out)."""

    @classmethod
    def setUpClass(cls):
        from promo.scenes import Film
        cls.films = {fid: Film(SB, "30s", fid, CLOCKS["30s"]) for fid in FORMATS}

    def test_sizes_and_the_same_cut_frames(self):
        ref = [(t["frame"], t["kind"]) for t in self.films["9x16"].transitions()]
        for fid, film in self.films.items():
            self.assertEqual(film.size, SB.formats[fid].size)
            self.assertEqual([(t["frame"], t["kind"]) for t in film.transitions()], ref)

    def test_the_map_credit_inks_its_place(self):
        """9:16 and 1:1 ending on the screen's right edge (x 900, its last
        glyph's overshoot included: over the map it credits — round 3 ended the
        1:1's on the safe edge x 1026, over the bezel's corner; 9:16's sat on
        the floor, which is the phone's since the owner's floor); 16:9 ending
        on the column's edge, x 1040 (round 5: the column moved 16 px left with the phone)."""
        want = {"9x16": (2, 900.0), "1x1": (2, 900.0), "16x9": (2, 1040.0)}
        for fid, (edge, x) in want.items():
            _, rec = self.films[fid].frame(700)
            box = next(b["rect"] for b in rec["boxes"] if b["kind"] == "credit")
            with self.subTest(fmt=fid):
                self.assertAlmostEqual(box[edge], x, delta=0.06)
                self.assertTrue(covered_by(Rect(*box), list(SB.formats[fid].text_area)), box)

    def test_the_13_15_row_under_the_floor_on_the_swipe(self):
        for fid, film in self.films.items():
            frame, rec = film.frame(144)
            self.assertEqual(frame.shape[:2], SB.formats[fid].size[::-1])
            self.assertEqual([t["gesture"] for t in rec["touch_downs"]], ["swipe-arrive"])
            self.assertTrue(all(h["alpha"] < 0.05 for h in rec["hidden"]), (fid, rec["hidden"]))

    def test_16x9_tilts_are_yaws(self):
        j = next(s for s in self.films["16x9"].scenes if s.id == "journal")
        p = j.pose(130.0)
        self.assertEqual(p.rot_x, 0.0)
        self.assertTrue(0 < p.rot_y <= 10.0)
        self.assertEqual(next(s for s in self.films["1x1"].scenes if s.id == "journal").pose(130.0).rot_y, 0.0)

    def test_the_1x1_counter_rolls_inside_its_band(self):
        """Mid-roll the next digits come up from below the figure: in 1:1 the
        band ends at y 300 and the phone starts under it — the roll is cut at
        the band's edge, never drawn over the phone."""
        film = self.films["1x1"]
        rev = next(s for s in film.scenes if s.id == "revenus")
        f = 540
        with_counter, _ = film.frame(f)
        bare = surface.new_surface(*film.size)
        canvas = bare.getCanvas()
        rev.draw_picture(canvas, float(f), frame=f)
        edge = int(rev.window.top - rev.window.band_fade)    # the band's opaque edge (y 358)
        a = with_counter[edge:edge + 40, :, :3].astype(int)
        b = surface.to_array(bare)[edge:edge + 40, :, :3].astype(int)
        self.assertEqual(int(np.abs(a - b).max()), 0)        # nothing of the counter below the band

    def test_the_1x1_counter_clears_the_phone(self):
        """Round 3's review: the 1:1 figure ended 17 px over the phone's bezel
        and the roll's next digits were cut at y 300, right on it — half-digits
        on the phone for the whole roll. Now the figure ends ≥ 30 px over it
        and the rolling band fades out ON the band, by its edge."""
        film = self.films["1x1"]
        rev = next(s for s in film.scenes if s.id == "revenus")
        edge = int(rev.window.top - rev.window.band_fade)                            # y 358 (round 3: 300)
        landed = [b["rect"] for b in film.frame(551)[1]["boxes"] if b["kind"] == "counter"]
        self.assertLessEqual(max(r[3] for r in landed), edge - 30)
        self.assertGreaterEqual(min(r[1] for r in landed), 54)                      # the label inside the safe area
        for f in range(536, 548, 2):                                                 # mid-roll
            with_counter, _ = film.frame(f)
            bare = surface.new_surface(*film.size)
            rev.draw_picture(bare.getCanvas(), float(f), frame=f)
            d = np.abs(with_counter[..., :3].astype(int) - surface.to_array(bare)[..., :3].astype(int)).max(axis=2)
            self.assertLessEqual(int(d[edge - 10:edge].max()), 60, f)                # round 3: 195 at y 290
            self.assertLessEqual(int(d[edge - 5:edge].max()), 30, f)

    def test_the_16x9_push_in_holds_the_safe_edge(self):
        """Round 3's review: the « rempli. » push-in (1.791 → 2.0 px/pt) scaled
        about the phone's axis, so at its peak the FAB and the snackbar reached
        x 1835, past the 16:9 graphics-safe edge (1824). It scales about the
        slab's right edge now (round 5: the screen at x 1088–1808, the bezel
        ending on 1824): the phone grows leftwards, bezel and all."""
        def screen_right(film, f):
            j = next(s for s in film.scenes if s.id == "journal")
            spec = j.phone.spec
            return j.phone.map_rect((0.0, spec.crop_top_pt, spec.screen_pt[0], spec.screen_pt[1]), j.pose(float(f)),
                                    W=j.camera_W(float(f)), window=j.win(float(f)))[2], j.zoom(float(f))
        film = self.films["16x9"]
        bezel = SB.formats["16x9"].layout["phone_bezel_px"]
        for f in (436, 448, 456, 460, 463):
            x1, zoom = screen_right(film, f)
            self.assertLessEqual(x1 + bezel * zoom, 1824.5, f)                          # the slab's edge, too
        self.assertGreater(screen_right(film, 460)[1], 1.1)                          # the push is there
        from promo.scenes import Film
        old = Film(sbmod.load(overrides=["formats.16x9.layout.zoom_pivot_x=null"]), "30s", "16x9", CLOCKS["30s"])
        x1, zoom = screen_right(old, 460)
        self.assertGreater(x1 + bezel * zoom, 1824 + 20)                             # about the axis: past the edge

    def test_the_16x9_counter_is_set_from_the_columns_edge(self):
        """Left-aligned: « Aujourd’hui » (its « A » overhangs 1 px) and the
        figure through its 1.08 landing punch stay on x ≥ 96, the safe edge."""
        film = self.films["16x9"]
        for f in (520, 547, 548, 550):
            _, rec = film.frame(f)
            boxes = [b for b in rec["boxes"] if b["kind"] == "counter"]
            self.assertEqual(len(boxes), 2, f)
            self.assertTrue(all(b["rect"][0] >= 96.0 for b in boxes), (f, boxes))
        self.assertEqual(min(b["rect"][0] for b in film.frame(548)[1]["boxes"] if b["kind"] == "counter"), 96.0)

    def test_a_scene_never_places_what_the_format_places(self):
        from promo.scenes import Film, SceneError
        for override, part in (("scenes.30s.4.counter.figure_baseline=496", "counter_baselines"),
                               ("scenes.30s.5.credit.baseline=1236", "map_credit"),
                               ("scenes.30s.3.stack.layout.y=nowhere", "lift_y places")):
            with self.subTest(override=override), self.assertRaisesRegex(SceneError, part):
                Film(sbmod.load(overrides=[override]), "30s", "1x1", CLOCKS["30s"])

    def test_16x9_lifts_beside_the_phone_on_the_stage(self):
        film = self.films["16x9"]
        _, rec = film.frame(494)
        tiles = [b["rect"] for b in rec["boxes"] if b["label"].startswith("tile")]
        self.assertEqual(len(tiles), 3)
        self.assertTrue(all(r[2] <= 1088 for r in tiles), tiles)
        fi = next(s for s in film.scenes if s.id == "fiche")
        self.assertIsNone(fi.stack["backdrop"])                   # no veil, no panel: the phone stays whole


if __name__ == "__main__":
    unittest.main()
