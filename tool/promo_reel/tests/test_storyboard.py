"""storyboard.yaml: the starter loads; every rule refuses what breaks it, with
its path; variants are held to the same rules; the CLI stubs say what they did."""

from __future__ import annotations

import contextlib
import importlib.util
import io
import sys
import unittest
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import yaml  # noqa: E402

from promo import storyboard as sb  # noqa: E402
from promo.__main__ import main as cli  # noqa: E402
from promo.storyboard import Rect, StoryboardError  # noqa: E402

STARTER = sb.DEFAULT_PATH.read_text(encoding="utf-8")


def problems(*overrides: str, text: str = STARTER) -> list[str]:
    """The problems a variant of the starter has (empty: it loads)."""
    try:
        sb.loads(text, overrides=overrides)
    except StoryboardError as e:
        return e.problems
    return []


def with_doc(change) -> str:
    """The starter, changed by ``change(doc)``, as YAML text."""
    doc = yaml.safe_load(STARTER)
    change(doc)
    return yaml.safe_dump(doc, allow_unicode=True, sort_keys=False)


class Starter(unittest.TestCase):
    def setUp(self):
        self.sb = sb.load()

    def test_meta_is_the_contracts_time_base(self):
        m = self.sb.meta
        self.assertEqual((m.fps, m.bpm, m.key, m.sample_rate), (30, Fraction(225, 2), "C minor", 48000))
        self.assertEqual(self.sb.timebase.frames_per_bar, 64)

    def test_cuts(self):
        c30, c15 = self.sb.cuts["30s"], self.sb.cuts["15s"]
        # the owner's decision (2026-10-19, « Add one bar »): 14 + 1 and 7 + 1 bars
        self.assertEqual((c30.bars, c30.frames, c30.samples), (15, 960, 1_536_000))
        self.assertEqual((c15.bars, c15.frames), (8, 512))
        self.assertEqual(float(c30.duration_s), 32.0)
        self.assertAlmostEqual(float(c15.duration_s), 17.067, places=3)
        for c in (c30, c15):                                   # one bar past what the name holds, never more
            self.assertLessEqual(c.duration_s, c.nominal_s + Fraction(64 * sb.OUTRO_BARS, 30))

    def test_formats(self):
        f = self.sb.formats
        self.assertEqual(list(f), ["9x16", "1x1", "16x9"])
        self.assertEqual(f["9x16"].size, (1080, 1920))
        self.assertEqual(f["9x16"].safe, Rect(120, 270, 900, 1248))
        self.assertEqual(f["9x16"].zones["phone_window"], Rect(180, 600, 900, 1192))
        self.assertEqual(f["9x16"].zones["captions"], Rect(150, 300, 930, 540))
        self.assertEqual(f["1x1"].safe, Rect(54, 54, 1026, 1026))
        self.assertEqual(f["16x9"].safe, Rect(96, 54, 1824, 1026))
        self.assertNotIn("caption_band", f["16x9"].zones)
        for fmt in f.values():
            self.assertEqual(fmt.layout["px_per_pt"], 1.791)
            self.assertEqual(fmt.layout["type_px"]["app"], 72)

    def test_the_scores_are_the_one_source_of_cue_ids(self):
        self.assertEqual(self.sb.music, {"scores": {"30s": "promo/audio/score_30s.yaml",
                                                    "15s": "promo/audio/score_15s.yaml"}})
        self.assertEqual(self.sb.score_path("30s"), sb.PROMO_REEL / "promo/audio/score_30s.yaml")
        self.assertIn("swipe.touch", self.sb.cue_ids("30s"))
        self.assertIn("end.store", self.sb.cue_ids("15s"))
        self.assertEqual(len(self.sb.cue_ids("30s")), 85)                # + end.underline (the outro)
        self.assertEqual(len(self.sb.cut_scenes("30s")), 9)          # rows 1–24 of the 30-s storyboard
        self.assertEqual(self.sb.cut_scenes("15s"), [])

    def test_scene_cue_references_are_checked_per_cut(self):
        found = problems("scenes.30s.0.from=cue:hook.stabx")
        self.assertEqual(len(found), 1)
        self.assertTrue(found[0].startswith("scenes.30s[0].from: cue 'hook.stabx' is not in the cut's cues"), found)
        # a 30-s cue named in the 15-s scenes: the 15-s score has no Fiche
        self.assertTrue(any("scenes.15s[0].at: cue 'fiche.cut'" in p for p in problems("scenes.15s=[{at: 'cue:fiche.cut'}]")))
        self.assertEqual(problems("scenes.15s=[{at: 'cue:drop1.impact+3'}]"), [])

    def test_camera_keys_are_written_in_time_order(self):
        """Review m2: a key written before the one above it (the micro push's
        `5.4.3+3` above `5.4.3+2`) made a glide snap; the renderer sorts
        nothing, so the storyboard refuses it with both keys' frames."""
        self.assertEqual(problems(), [])
        found = problems("scenes.30s.2.camera.zoom.1.at=6.1.0+2")          # f322, before cue:fill.touch1 (f320)
        self.assertEqual(found, ["scenes.30s[2].camera.zoom[2].at: cue:fill.touch1 is f320, not after the key "
                                 "before it (6.1.0+2, f322): camera keys are written in time order"])
        same = problems("scenes.30s.2.camera.W.6.at=5.4.0")                 # two keys on f304
        self.assertTrue(any("camera.W[6].at: 5.4.0 is f304, not after" in p for p in same), same)
        slam = problems("scenes.30s.5.camera.slam.rot_x.1.at=cue:page.cut")
        self.assertTrue(any("camera.slam.rot_x[1].at" in p for p in slam), slam)

    def test_times_resolve_as_the_clock_does(self):
        frames = sb._cue_frames(sb.load().music, "30s")
        self.assertEqual(sb.time_frame("cue:fill.touch1", frames, 896), 320)
        self.assertEqual(sb.time_frame("cue:reveal.glide@end+1", frames, 896), 825)
        self.assertEqual(sb.time_frame("cue:swipe.whoosh", frames, 896), 149)          # pos + offset
        self.assertEqual(sb.time_frame("5.4.2+2", frames, 896), 314)
        self.assertEqual(sb.time_frame("5.2&", frames, 896), 280)
        self.assertEqual(sb.time_frame("end", frames, 960), 960)
        self.assertIsNone(sb.time_frame("cue:hook.stab@end", frames, 896))           # not a span

    def test_the_store_line_is_read_not_fine_print(self):
        """Review M1: « Disponible sur l’App Store » was 34 px, the film's
        smallest type; a line the viewer must read is at least 40 px."""
        self.assertEqual(sb.load().formats["9x16"].layout["type_px"]["store"], 40)
        found = problems("formats.9x16.layout.type_px.store=34")
        self.assertEqual(found, ["formats.9x16.layout.type_px.store: 34 px: a line the viewer must read is at "
                                 "least 40 px"])

    def test_score_references(self):
        self.assertTrue(any("no such score" in p for p in problems("music.scores.30s=promo/audio/none.yaml")))
        self.assertTrue(any("is the score of cut '15s', not 30s" in p
                            for p in problems("music.scores.30s=promo/audio/score_15s.yaml")))
        self.assertTrue(any("one source" in p for p in problems("music.cues=[{id: swipe.touch}]")))

    def test_plan(self):
        plan = self.sb.plan()
        self.assertIn("112.5 BPM · 30 fps · 48000 Hz · C minor", plan)
        self.assertIn("cut 30s: 15 bars = 960 frames = 32.000 s", plan)
        self.assertIn("cut 15s: 8 bars = 512 frames = 17.067 s", plan)
        self.assertIn("films: 6 — 30s/9x16, 30s/1x1, 30s/16x9, 15s/9x16, 15s/1x1, 15s/16x9", plan)
        self.assertIn("films: 1 — 15s/1x1", self.sb.plan(["15s"], ["1x1"]))


class Strict(unittest.TestCase):
    def assertProblem(self, found: list[str], *parts: str):
        self.assertTrue(any(all(p in f for p in parts) for f in found), f"{parts} not in {found}")

    def test_top_level(self):
        self.assertProblem(problems(text=STARTER + "\nextra: 1\n"), "(top level).extra", "unknown key")
        self.assertProblem(problems(text=with_doc(lambda d: d.pop("scenes"))), "missing key 'scenes'")
        self.assertProblem(problems(text="- a list\n"), "(top level)", "must be a mapping")
        self.assertProblem(problems(text="meta: [\n"), "not valid YAML")
        self.assertEqual(problems(text=STARTER + "\nx-shared: {a: 1}\n"), [])   # anchor holders are ignored

    def test_meta(self):
        self.assertProblem(problems("meta.bpm=120"), "meta.bpm", "contract's 112.5 BPM")
        self.assertProblem(problems("meta.fps=25"), "meta.fps", "contract's 30")
        self.assertProblem(problems("meta.sample_rate=44100"), "meta.sample_rate")
        self.assertProblem(problems("meta.key=H minor"), "meta.key", "is not a key")
        self.assertProblem(problems("meta.fps=thirty"), "meta.fps", "whole number")
        self.assertProblem(problems("meta.tempo=1"), "meta.tempo", "unknown key")
        self.assertEqual(problems("meta.key=Eb major", "meta.title=Variant"), [])

    def test_cuts(self):
        self.assertProblem(problems("cuts.30s.frames=900"), "cuts.30s.frames", "15 bars × 64 = 960")
        self.assertProblem(problems("cuts.30s.bars=0"), "cuts.30s.bars", "at least 1")
        # one outro bar past what the name holds (the owner's, 2026-10-19), never two
        self.assertEqual([p for p in problems("cuts.10s={bars: 5, frames: 320}") if p.startswith("cuts")], [])
        self.assertProblem(problems("cuts.10s={bars: 6, frames: 384}"), "cuts.10s", "hold 4 bars", "at most 5")
        self.assertProblem(problems("cuts.30s={bars: 16, frames: 1024}"), "cuts.30s", "hold 14 bars", "at most 15")
        self.assertProblem(problems("cuts.short={bars: 1, frames: 64}"), "cuts.short", "length in seconds")
        self.assertProblem(problems("cuts={}"), "cuts", "at least one cut")

    def test_format_geometry(self):
        self.assertProblem(problems("formats.9x16.size=[1080, 1080]"), "formats.9x16.size", "is not 9:16")
        self.assertProblem(problems("formats.9x16.size=[720, 1280]"), "formats.9x16.size", "short side")
        self.assertProblem(problems("formats.9x16.safe=[120, 270, 900, 2000]"), "formats.9x16.safe", "leaves the")
        self.assertProblem(problems("formats.9x16.safe=[900, 270, 120, 1248]"), "formats.9x16.safe", "is empty")
        self.assertProblem(problems("formats.1x1.safe=[50, 54, 1026, 1026]"), "formats.1x1.safe", "5 % inset")
        self.assertProblem(problems("formats.4x3={}"), "formats.4x3", "missing key 'size'")
        self.assertProblem(problems("formats.wide={}"), "formats.wide", "aspect ratio")

    def test_zones_holding_text_or_ui_stay_in_the_safe_area(self):
        self.assertProblem(problems("formats.9x16.zones.phone_window=[0, 600, 1080, 1192]"),
                           "formats.9x16.zones.phone_window", "must lie inside the safe area")
        # captions may use the rail-free extension above y 840 …
        self.assertEqual(problems("formats.9x16.zones.captions=[120, 300, 960, 840]"), [])
        # … but not below it
        self.assertProblem(problems("formats.9x16.zones.captions=[150, 300, 930, 900]"),
                           "formats.9x16.zones.captions", "rail-free extension")
        # the stage itself (band, floor) may cover the canvas
        self.assertEqual(problems("formats.9x16.zones.floor=[0, 1216, 1080, 1920]"), [])
        self.assertProblem(problems("formats.9x16.zones.sidebar=[0, 0, 10, 10]"), "zones.sidebar", "unknown key")
        self.assertProblem(problems("formats.9x16.zones.captions=null"), "zones.captions", "list of 4 numbers")

    def test_layout_rules(self):
        self.assertProblem(problems("formats.9x16.layout.phone_screen_x=[180, 880]"), "phone_screen_x", "402 pt wide")
        self.assertProblem(problems("formats.16x9.layout.caption_band=true"), "caption_band", "no `caption_band` zone")
        self.assertProblem(problems("formats.9x16.layout.caption_line_max_px=800"), "caption_line_max_px",
                           "wider than the caption column")
        self.assertProblem(problems("formats.16x9.layout.end_tagline_cap_top_y=450"), "end_tagline_cap_top_y",
                           "clear space")
        self.assertProblem(problems("formats.9x16.layout.lift_veil=1.5"), "lift_veil", "at most 1")
        self.assertProblem(problems("formats.9x16.layout.tilt_axis=z"), "tilt_axis", "one of x, y")
        self.assertProblem(problems("formats.9x16.layout.lottie_centre=[200, 680]"), "lottie_centre", "leaves")
        self.assertProblem(problems(text=with_doc(lambda d: d["formats"]["1x1"]["layout"].pop("lift_x"))),
                           "formats.1x1.layout", "missing key 'lift_x'")

    def test_one_storyboard_same_pixel_sizes_in_every_format(self):
        # the starter shares type_px through a YAML alias: overriding one use
        # changes that format only, and is refused
        self.assertProblem(problems("formats.9x16.layout.type_px.app=80"), "formats.*.layout.type_px",
                           "same in every format")
        self.assertProblem(problems("formats.1x1.layout.lottie_comp_width_px=800"),
                           "formats.*.layout.lottie_comp_width_px", "1x1: 800")
        # a scale that no longer shows the whole screen fails in its own format first
        self.assertProblem(problems("formats.1x1.layout.px_per_pt=2.0"), "formats.1x1.layout.phone_screen_x",
                           "shows 360.0 pt")

    def test_every_problem_is_reported_at_once(self):
        found = problems("meta.bpm=120", "cuts.15s.frames=1", "formats.9x16.layout.lift_veil=2")
        self.assertEqual(len(found), 3, found)


class Cues(unittest.TestCase):
    def test_scenes_may_only_name_declared_cues(self):
        text = with_doc(lambda d: d.update(
            music={"cues": [{"id": "drop1.impact", "kind": "impact"}, {"id": "hook.word1"}], "sections": "AUDIO's"},
            scenes=[{"id": "hook", "captions": [{"word": "Votre", "cue": "hook.word1"}]},
                    {"id": "drop", "sound": {"cues": ["drop1.impact", "drop1.typo"]}}]))
        found = problems(text=text)
        self.assertEqual(found, ["scenes[1].sound.cues[1]: cue 'drop1.typo' is not in music.cues "
                                 "(known: drop1.impact, hook.word1)"])
        ok = sb.loads(text.replace("drop1.typo", "hook.word1"))
        self.assertEqual(ok.cue_ids(), {"drop1.impact", "hook.word1"})
        self.assertEqual(ok.music["sections"], "AUDIO's")            # passed through untouched

    def test_cue_declarations(self):
        self.assertTrue(any("declared twice" in p for p in problems("music.cues=[{id: a}, {id: a}]")))
        self.assertTrue(any("mapping with an `id`" in p for p in problems("music.cues=[a]")))
        self.assertTrue(any("without spaces" in p for p in problems("music.cues=[{id: 'a b'}]")))
        self.assertTrue(any("is not a cut" in p for p in problems("music.cues={45s: []}")))
        self.assertEqual(problems("music.cues={30s: [{id: a}], 15s: [{id: a}]}", "scenes=[{cue: a}]"), [])
        self.assertTrue(any("must be a mapping" in p for p in problems("music=[]")))
        self.assertTrue(any("list or a mapping" in p for p in problems("scenes=3")))


class Variants(unittest.TestCase):
    def test_values_are_read_as_yaml(self):
        s = sb.load(overrides=["meta.title=Variant A", "scenes=[{id: hook}, {id: drop}]", "scenes.1.id=drop1"])
        self.assertEqual(s.meta.title, "Variant A")
        self.assertEqual(s.scenes, [{"id": "hook"}, {"id": "drop1"}])
        self.assertEqual(s.overrides, ("meta.title=Variant A", "scenes=[{id: hook}, {id: drop}]", "scenes.1.id=drop1"))
        self.assertIn("variant: --set meta.title=Variant A", s.plan())

    def test_bad_paths(self):
        self.assertTrue(any("has no key 'nope'" in p for p in problems("nope.x=1")))
        self.assertTrue(any("no item 3" in p for p in problems("scenes=[]", "scenes.3=1")))
        self.assertTrue(any("address an item by its index" in p for p in problems("scenes=[a]", "scenes.first=1")))
        self.assertTrue(any("not a mapping or a list" in p for p in problems("meta.fps.x=1")))
        with self.assertRaisesRegex(ValueError, "path.to.key=value"):
            sb.parse_override("meta.fps")
        with self.assertRaisesRegex(ValueError, "empty part"):
            sb.parse_override("meta..fps=1")

    def test_the_document_on_disk_is_not_changed(self):
        sb.load(overrides=["meta.title=Changed"])
        self.assertEqual(sb.load().meta.title, "MyWeli Pro — « CARNET → DROP »")


class Cli(unittest.TestCase):
    def run_cli(self, *args: str) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                code = cli(list(args))
            except SystemExit as e:
                code = e.code if isinstance(e.code, int) else 1
                err.write(str(e.code))
        return code, out.getvalue(), err.getvalue()

    def test_plan(self):
        code, out, _ = self.run_cli("plan", "--cut", "30s")
        self.assertEqual(code, 0)
        self.assertIn("films: 3 — 30s/9x16, 30s/1x1, 30s/16x9", out)

    def test_a_broken_variant_stops_everything(self):
        code, _, err = self.run_cli("build", "--all", "--set", "meta.bpm=120")
        self.assertEqual(code, 2)
        self.assertIn("meta.bpm", err)

    def test_selection(self):
        self.assertNotEqual(self.run_cli("build")[0], 0)                          # says what to build
        self.assertNotEqual(self.run_cli("build", "--cut", "45s")[0], 0)
        self.assertNotEqual(self.run_cli("build", "--all", "--cut", "30s")[0], 0)

    @unittest.skipUnless(importlib.util.find_spec("promo.render") is None, "SCENES' render.py is in the tree")
    def test_stubs_say_nothing_was_rendered_or_verified(self):
        code, out, _ = self.run_cli("build", "--all")
        self.assertEqual(code, 0)
        self.assertIn("NOTHING was rendered", out)
        code, out, _ = self.run_cli("verify", "--all")
        self.assertEqual(code, 0)
        self.assertIn("UNVERIFIED", out)


if __name__ == "__main__":
    unittest.main()
