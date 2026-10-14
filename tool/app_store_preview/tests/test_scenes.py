"""A film made of scenes: the plan, and every refusal — each on a take
whose answer is known in advance (tests/test_edit.py's: a tap answered at
3.000–3.167 s, the app on its own at 6.000–6.083 s, a caret at 7–8 s, a
drag answered at 10.000–11.000 s)."""

from __future__ import annotations

import copy
import unittest
from pathlib import Path

import scenes
from edit import Refusal
from tests.test_edit import CHANGE, LOG, SB, TAKE, burst, scan_of

BASE = Path("/nowhere/takes")
# Two scenes from one take. S1: the tap (its window runs to the app's own
# change at 6.083 s: the last change before the drag's touch-down); S2: the
# drag. Rests long enough for 15 s.
SB2 = {
    "version": 2,
    "film": {"fps": 30, "width": 886, "height": 1920, "frame": "framed", "poster": {"scene": "S1", "at_s": 4.0}},
    "motion": {"join": "base", "dissolve": "base", "end_card": "base", "touch_in": "fast", "touch_out": "base"},
    "touch": dict(SB["touch"]),
    "timing": {"rest_s": 0.5, "tail_s": 0.3, "sync_tolerance_s": 0.5, "lead_in_s": 1.0},
    "band": {"top_pt": 62, "bottom_pt": 34},
    "end_card": {"title": "MyWeli Pro", "line": "Un compte MyWeli Pro est nécessaire.", "duration_s": 2.2},
    "scenes": [
        {"id": "S1", "take": "t.mov", "gestures": "t.json", "headline": ["Une", "deux"], "budget_s": 7.0,
         "keep": [{"gesture": "tap-a", "rest_after_s": 3.0}]},
        {"id": "S2", "take": "t.mov", "gestures": "t.json", "headline": ["Trois", "quatre"], "lead_in_s": 1.5,
         "keep": [{"gesture": "drag-b", "rest_after_s": 3.0}]},
    ],
}


# One scene: the tap, a declared dissolve over the caret's stretch, the drag.
DISSOLVING = copy.deepcopy(SB2)
DISSOLVING["scenes"] = [{"id": "S1", "take": "t.mov", "gestures": "t.json", "headline": ["a", "b"],
                         "keep": [{"gesture": "tap-a", "rest_after_s": 1.0},
                                  {"dissolve": "base", "lead_in_s": 0.6},
                                  {"gesture": "drag-b", "rest_after_s": 6.0}]}]
DISSOLVING["film"]["poster"] = {"scene": "S1", "at_s": 0.5}
# S2 keeps half a second of the caret's stretch by times, then the drag.
CUTTING = copy.deepcopy(SB2)
CUTTING["scenes"][1]["keep"] = [{"from_s": 7.5, "to_s": 8.0}, {"gesture": "drag-b", "rest_after_s": 3.0}]


def TAKE_OF(takes: dict) -> scenes.Take:
    return next(iter(takes.values()))


def setup(doc: dict | None = None, rows: list | None = None, log: dict | None = None):
    sb = scenes.load(copy.deepcopy(doc or SB2), BASE)
    scan = scan_of(rows if rows is not None else TAKE)
    takes = {}
    for scene in sb["scenes"]:
        key = scenes.take_key(scene)
        if key not in takes:
            takes[key] = scenes.read_take(sb, key, "t.mov", scan, copy.deepcopy(log or LOG), None)
    return sb, takes


def planned(doc: dict | None = None, **kw):
    sb, takes = setup(doc, **kw)
    return scenes.propose(sb, takes), sb, takes


def refused(test, code: str, plan: dict, sb: dict, takes: dict, contains: str = "", **kw) -> str:
    with test.assertRaises(Refusal) as cm:
        scenes.check(plan, sb, takes, **kw)
    test.assertEqual(cm.exception.code, code, cm.exception.message)
    test.assertIn(contains, cm.exception.message)
    return cm.exception.message


def doc_with(**changes) -> dict:
    d = copy.deepcopy(SB2)
    for path, value in changes.items():
        node = d
        keys = path.split("__")
        for k in keys[:-1]:
            node = node[int(k)] if k.isdigit() else node[k]
        last = keys[-1]
        if isinstance(node, list):
            node[int(last)] = value
        else:
            node[last] = value
    return d


class Storyboard(unittest.TestCase):
    def test_the_storyboard_of_scenes_is_checked_for_shape(self):
        cases = {
            "version": (doc_with(version=1), "\"version\": 2"),
            "frame": (doc_with(film__frame="letterbox"), "film.frame is one of framed, full-bleed"),
            "size": (doc_with(film__width=884), "886 x 1920 at 30 fps"),
            "token": (doc_with(motion__join=None), "motion.join names a motion token"),
            "band": (doc_with(band={"top_pt": 62}), "band: top_pt and bottom_pt"),
            "end card": (doc_with(end_card={"title": "MyWeli Pro"}), "end_card: a title, the disclosure line"),
            "no scene": (doc_with(scenes=[]), "lists its scenes"),
            "same id": (doc_with(scenes__1__id="S1"), "its own id"),
            "headline": (doc_with(scenes__0__headline=["un", "deux", "trois"]), "one or two hand-set lines"),
            "subline": (doc_with(scenes__0__subline=["", "x"]), "zero to two hand-set lines"),
            "band side": (doc_with(scenes__0__band="middle"), "band is one of top, bottom"),
            "nothing kept": (doc_with(scenes__0__keep=[]), "`keep` lists what the scene shows"),
            "two kinds": (doc_with(scenes__0__keep=[{"gesture": "tap-a", "dissolve": "base"}]), "one of `gesture`"),
            "times": (doc_with(scenes__0__keep=[{"from_s": 3.0, "to_s": 2.0}]), "a later `to_s`"),
            "ground": (doc_with(scenes__0__keep=[{"gesture": "tap-a", "ground": "grey"}]), "ground is light or dark"),
            "poster": (doc_with(film__poster={"scene": "S9", "at_s": 1.0}), "film.poster"),
            "paths": (doc_with(scenes__0__take=None), "`take` and `gestures` are paths"),
        }
        for name, (doc, words) in cases.items():
            with self.subTest(name), self.assertRaises(Refusal) as cm:
                scenes.load(doc, BASE)
            self.assertIn(words, cm.exception.message, name)

    def test_a_dissolve_sits_between_two_things_and_there_is_one_at_most(self):
        for keep in ([{"dissolve": "base"}, {"gesture": "tap-a"}],
                     [{"gesture": "tap-a"}, {"dissolve": "base"}],
                     [{"gesture": "tap-a"}, {"dissolve": "base"}, {"dissolve": "base"}, {"gesture": "drag-b"}]):
            with self.assertRaises(Refusal) as cm:
                scenes.load(doc_with(scenes__0__keep=keep), BASE)
            self.assertEqual(cm.exception.code, "E_DISSOLVE")
        with self.assertRaises(Refusal) as cm:
            scenes.load(doc_with(scenes__0__keep=[{"gesture": "tap-a"}, {"dissolve": "base"}, {"gesture": "drag-b"},
                                                  {"dissolve": "base"}, {"gesture": "x"}]), BASE)
        self.assertIn("one dissolve inside a scene at most", cm.exception.message)

    def test_a_mask_is_checked_for_shape(self):
        good = {"rect_px": [10, 20, 30, 40]}
        scenes.load(doc_with(scenes__0__masks=[good]), BASE)
        for mask, words in (({"rect_px": [10, 20, 30]}, "`rect_px` is [x, y, width, height]"),
                            ({"rect_px": [10, 20, 0, 40]}, "`rect_px`"),
                            ({"rect_px": [10.5, 20, 30, 40]}, "whole pixels"),
                            ({**good, "style": "pixelate"}, "style is one of fill, blur"),
                            ({**good, "track": True}, "names the band that scrolls"),
                            ({**good, "track": {"scroll_px": [30, 50]}}, "around its rectangle"),
                            ({**good, "ref_s": "start"}, "ref_s is in seconds")):
            with self.subTest(mask), self.assertRaises(Refusal) as cm:
                scenes.load(doc_with(scenes__0__masks=[mask]), BASE)
            self.assertEqual(cm.exception.code, "E_MASK")
            self.assertIn(words, cm.exception.message)

    def test_paths_are_resolved_against_the_takes_folder(self):
        sb = scenes.load(SB2, BASE)
        self.assertEqual(sb["scenes"][0]["take_path"], str((BASE / "t.mov").resolve()))
        self.assertEqual(scenes.take_key(sb["scenes"][0]), scenes.take_key(sb["scenes"][1]))
        self.assertFalse(sb["rehearsal"])

    def test_the_films_own_storyboard_of_scenes_is_well_formed(self):
        import json
        from tests.support import TOOL
        for name in ("storyboard-scenes.json", "storyboard-scenes-demo.json"):
            doc = json.loads((TOOL / name).read_text(encoding="utf-8"))
            sb = scenes.load(doc, TOOL)
            self.assertEqual(sb["end_card"]["line"], "Un compte MyWeli Pro est nécessaire.", name)
            lo, hi = scenes.END_CARD_S
            self.assertTrue(lo <= sb["end_card"]["duration_s"] <= hi, name)


class Propose(unittest.TestCase):
    def test_each_scene_is_its_gestures_whole_with_its_rests(self):
        """S1: the tap from its touch-down (2.900 s: `fast` before the first
        change) to 0.3 s after the last change of its window — the app's own
        change at 6.083 s, since nothing touches the screen before the drag —
        with its lead-in and rest. S2: the drag, timed by the logged path
        (the touch-down 14 ticks before the first change: 18 pt of a 300 pt
        drag in 400 ms) to 0.3 s after 11.000 s."""
        plan, sb, takes = planned()
        s1, s2 = plan["scenes"]
        self.assertEqual(s1["runs"], [{"segments": [
            {"kind": "hold", "src_at": 1740, "frames": 30, "why": "lead-in: the screen at rest"},
            {"kind": "live", "src_in": 1740, "src_out": 3860},
            {"kind": "hold", "src_at": 3840, "frames": 90, "why": "rest after tap-a"}]}])
        self.assertEqual(s2["runs"], [{"segments": [
            {"kind": "hold", "src_at": 5986, "frames": 45, "why": "lead-in: the screen at rest"},
            {"kind": "live", "src_in": 5986, "src_out": 6806},
            {"kind": "hold", "src_at": 6786, "frames": 90, "why": "rest after drag-b"}]}])
        self.assertEqual((s1["dissolves"], s2["dissolves"]), ([], []))

    def test_touch_points_are_in_scene_time_and_named_by_scene(self):
        plan, _, _ = planned()
        s1, s2 = plan["scenes"]
        self.assertEqual(s1["touches"], [{"gesture": "S1/tap-a", "kind": "tap", "down": 600, "up": 780,
                                          "path": [[600, 100, 300]]}])
        self.assertEqual(s2["touches"], [{"gesture": "S2/drag-b", "kind": "drag", "down": 900, "up": 1140,
                                          "path": [[900.0, 200, 600], [1140.0, 200, 300]]}])

    def test_joins_end_card_and_where_each_scene_lands(self):
        """A join is the token's frames less one between the two pictures:
        `base` is 6 frames, so 5 blends — the last picture of one, five
        frames between, the first of the next: 200 ms from one to the
        other, as the token says."""
        plan, sb, takes = planned()
        self.assertEqual(plan["joins"], [{"after": "S1", "to": "S2", "token": "base", "frames": 5},
                                         {"after": "S2", "to": "end", "token": "base", "frames": 5}])
        self.assertEqual(plan["end_card"], {"frames": 66})
        placed, joins, end, total = scenes.places(plan)
        self.assertEqual([(p.id, p.first, p.frames) for p in placed], [("S1", 0, 226), ("S2", 231, 176)])
        self.assertEqual((joins, end, total), ([(226, 5), (407, 5)], 412, 478))
        self.assertEqual(plan["poster_frame"], 120)
        film = scenes.check(plan, sb, takes)
        self.assertEqual(film["total"], 478)

    def test_a_dissolve_inside_a_scene_skips_forward_between_two_rests(self):
        """S1: the tap, a dissolve, the drag — the caret stretch between them
        skipped, declared."""
        plan, sb, takes = planned(DISSOLVING)
        s1 = plan["scenes"][0]
        self.assertEqual(len(s1["runs"]), 2)
        self.assertEqual(s1["dissolves"], [{"token": "base", "frames": 5}])
        self.assertEqual(s1["runs"][1]["segments"][0], {"kind": "hold", "src_at": 5986, "frames": 18,
                                                         "why": "lead-in: the screen at rest after the dissolve"})
        self.assertEqual(scenes.scene_layout(s1), [("run", 0, 166), ("dissolve", 0, 5), ("run", 1, 239)])
        self.assertEqual(scenes.run_starts(s1), [0, 171])
        self.assertEqual(s1["touches"][1]["down"], (171 + 18) * 20)
        self.assertIsNone(scenes.picture_at(s1, 168))
        self.assertEqual(scenes.picture_at(s1, 165), (0, 165, 3840))
        self.assertEqual(scenes.picture_at(s1, 171), (1, 0, 5986))
        scenes.check(plan, sb, takes)
        log = scenes.describe(plan, sb, takes)
        self.assertIn("DISSOLVE base  5 frames from the picture at take   6.400 s to the picture at take   9.977 s: "
                      "the take's   6.400 s –   9.977 s is skipped, declared (no gesture in it)", log)

    def test_a_stretch_kept_by_times_brings_the_gestures_it_holds(self):
        doc = doc_with(scenes__0__keep=[{"from_s": 2.5, "to_s": 6.5, "rest_after_s": 3.0}],
                       scenes__0__lead_in_s=1.0)
        plan, sb, takes = planned(doc)
        self.assertEqual(plan["scenes"][0]["runs"][0]["segments"][1], {"kind": "live", "src_in": 1500, "src_out": 3900})
        self.assertEqual([t["gesture"] for t in plan["scenes"][0]["touches"]], ["S1/tap-a"])
        scenes.check(plan, sb, takes)

    def test_a_stretch_by_times_that_is_not_whole_frames_is_refused(self):
        sb, takes = setup(doc_with(scenes__0__keep=[{"from_s": 2.5, "to_s": 6.51}]))
        with self.assertRaises(Refusal) as cm:
            scenes.propose(sb, takes)
        self.assertEqual(cm.exception.code, "E_GRID")
        # said in the storyboard's own terms, before any segment is made of it
        self.assertIn("scene S1: 2.5–6.51 s is not a whole number of film frames", cm.exception.message)
        sb, takes = setup(doc_with(scenes__0__keep=[{"from_s": 2.5001, "to_s": 6.5}]))
        with self.assertRaises(Refusal) as cm:
            scenes.propose(sb, takes)
        self.assertEqual(cm.exception.code, "E_GRID")

    def test_a_scene_names_gestures_its_take_has_in_the_takes_order(self):
        sb, takes = setup(doc_with(scenes__0__keep=[{"gesture": "tap-z"}]))
        with self.assertRaises(Refusal) as cm:
            scenes.propose(sb, takes)
        self.assertEqual(cm.exception.code, "E_SCENE")
        self.assertIn("names gesture `tap-z`, which its take's log does not have (it has: tap-a, drag-b)",
                      cm.exception.message)
        sb, takes = setup(doc_with(scenes__0__keep=[{"gesture": "drag-b"}, {"gesture": "tap-a"}]))
        with self.assertRaises(Refusal) as cm:
            scenes.propose(sb, takes)
        self.assertIn("not in its take's order", cm.exception.message)

    def test_a_scene_does_not_run_into_the_next_gesture_of_its_take(self):
        """The tap's range may start up to a frame early to sit well on the
        film's frames; it never ends past the next gesture's touch-down."""
        plan, _, takes = planned()
        tm = next(iter(takes.values())).tm
        live = plan["scenes"][0]["runs"][0]["segments"][1]
        self.assertLessEqual(live["src_out"], tm.gestures[1].down)


class Refusals(unittest.TestCase):
    def setUp(self):
        self.plan, self.sb, self.takes = planned()

    def test_the_proposal_is_accepted(self):
        scenes.check(self.plan, self.sb, self.takes)

    def test_inside_a_scene_version_1s_rule_holds(self):
        """A cut inside the tap's window (between its touch-down and the
        app's own change it waits for) is refused by `check_take`."""
        p = copy.deepcopy(self.plan)
        p["scenes"][0]["runs"][0]["segments"][1:2] = [{"kind": "live", "src_in": 1740, "src_out": 2040},
                                                      {"kind": "live", "src_in": 3540, "src_out": 3860}]
        refused(self, "E_PROTECTED", p, self.sb, self.takes, "gesture `tap-a`")

    def test_a_speed_cannot_be_written_in_a_scene_either(self):
        p = copy.deepcopy(self.plan)
        p["scenes"][1]["runs"][0]["segments"][1]["speed"] = 2
        refused(self, "E_SHAPE", p, self.sb, self.takes)

    def test_a_scene_that_shows_a_gesture_it_does_not_name_is_refused(self):
        """S1 kept on, by hand, into the drag's answer."""
        p = copy.deepcopy(self.plan)
        p["scenes"][0]["runs"][0]["segments"][1:] = [{"kind": "live", "src_in": 1740, "src_out": 6100},
                                                     {"kind": "hold", "src_at": 6080, "frames": 90}]
        refused(self, "E_SCENE", p, self.sb, self.takes, "shows the answer to `drag-b`")

    def test_a_plan_for_another_take_is_refused(self):
        p = copy.deepcopy(self.plan)
        p["scenes"][1]["take"]["sha256"] = "cd" * 32
        refused(self, "E_TAKE", p, self.sb, self.takes, "scene S2")

    def test_touch_points_moved_by_hand_are_refused(self):
        p = copy.deepcopy(self.plan)
        p["scenes"][0]["touches"][0]["down"] += 20
        refused(self, "E_TOUCH", p, self.sb, self.takes, "scene S1")

    def test_a_plan_that_is_not_the_storyboards_is_refused(self):
        for change, words in ((lambda p: p.update(version=1), "\"version\": 2"),
                              (lambda p: p.update(rehearsal=True), "rehearsal"),
                              (lambda p: p.update(frame="poster"), "frame is one of"),
                              (lambda p: p["scenes"].reverse(), "not the storyboard's")):
            p = copy.deepcopy(self.plan)
            change(p)
            refused(self, "E_PLAN", p, self.sb, self.takes, words)

    def test_an_undeclared_dissolve_is_refused(self):
        """Footage is skipped inside a scene only where the storyboard says."""
        p = copy.deepcopy(self.plan)
        p["scenes"][0]["runs"].append({"segments": [{"kind": "hold", "src_at": 5986, "frames": 10}]})
        p["scenes"][0]["dissolves"].append({"token": "base", "frames": 5})
        refused(self, "E_DISSOLVE", p, self.sb, self.takes, "declares 0 dissolve(s)")

    def test_joins_are_the_storyboards_on_its_token(self):
        p = copy.deepcopy(self.plan)
        p["joins"][0]["token"] = "slow"
        refused(self, "E_JOIN", p, self.sb, self.takes, "the joins must be")
        p = copy.deepcopy(self.plan)
        p["joins"][1]["frames"] = 12
        refused(self, "E_JOIN", p, self.sb, self.takes, "is 12 frames between its two pictures; `base` is 5")

    def test_a_join_from_footage_that_plays_is_refused(self):
        p = copy.deepcopy(self.plan)
        p["scenes"][0]["runs"][0]["segments"].pop()          # S1 ends on its live range
        refused(self, "E_JOIN", p, self.sb, self.takes, "the join after scene S1: the scene ends on footage that plays")
        p = copy.deepcopy(self.plan)
        p["scenes"][1]["runs"][0]["segments"].pop(0)         # S2 starts on its live range
        p["scenes"][1]["touches"] = scenes.scene_touches(p["scenes"][1], self.sb["scenes"][1], TAKE_OF(self.takes))
        refused(self, "E_JOIN", p, self.sb, self.takes, "the join into scene S2: the scene starts on footage")

    def test_a_join_while_a_touch_point_is_on_screen_is_refused(self):
        """A tap answered in one frame (1.800 s): its point appears `fast`
        before (1.740 s), lifts `base` after the answer and leaves over
        `base` — 300 ticks, 15 film frames from the touch-down. The scene
        is the lead-in (30), the tap's range (13: to 0.3 s after the
        answer) and a rest: with a rest of one frame the scene's last frame
        is the 44th, the point still fading on it; with three, it is gone."""
        rows = [(1800, CHANGE)] + burst(6000, 6600)
        sb, takes = setup(doc_with(scenes__0__keep=[{"gesture": "tap-a", "rest_after_s": 1 / 30}]), rows=rows)
        plan = scenes.propose(sb, takes)
        self.assertEqual(scenes.scene_frames(plan["scenes"][0]), 44)
        refused(self, "E_JOIN", plan, sb, takes, "the join after scene S1: the touch point of `S1/tap-a` is still "
                                                 "on screen")
        sb, takes = setup(doc_with(scenes__0__keep=[{"gesture": "tap-a", "rest_after_s": 0.1}]), rows=rows)
        plan = scenes.propose(sb, takes)
        refused(self, "E_LENGTH", plan, sb, takes)          # past the join: what is left is a short film

    def test_a_join_from_a_picture_that_is_still_changing_is_refused(self):
        """The tap's range cut to end one frame after the app's own change
        (6.083 s): the window is whole, and the picture held after it has
        not rested for 0.3 s."""
        p = copy.deepcopy(self.plan)
        p["scenes"][0]["runs"][0]["segments"][1:] = [{"kind": "live", "src_in": 1740, "src_out": 3680},
                                                     {"kind": "hold", "src_at": 3660, "frames": 90}]
        msg = refused(self, "E_JOIN", p, self.sb, self.takes, "the join after scene S1: the picture (6.100 s")
        self.assertIn("not at rest — it changed at 6.083 s", msg)

    def test_a_declared_dissolve_between_pictures_not_at_rest_is_refused(self):
        plan, sb, takes = planned(DISSOLVING)
        p = copy.deepcopy(plan)
        p["scenes"][0]["runs"][0]["segments"][1:] = [{"kind": "live", "src_in": 1740, "src_out": 3680},
                                                     {"kind": "hold", "src_at": 3660, "frames": 30}]
        refused(self, "E_DISSOLVE", p, sb, takes, "the dissolve's « from » picture (6.100 s of the take) is not at "
                                                  "rest — it changed at 6.083 s")
        p = copy.deepcopy(plan)
        p["scenes"][0]["runs"][0]["segments"].pop()
        refused(self, "E_DISSOLVE", p, sb, takes, "a dissolve is between two pictures at rest")
        p = copy.deepcopy(plan)
        p["scenes"][0]["dissolves"][0]["frames"] = 11
        refused(self, "E_DISSOLVE", p, sb, takes, "the dissolve is `base`, 5 frames")
        p = copy.deepcopy(plan)
        p["scenes"][0]["dissolves"][0]["token"] = "slow"
        refused(self, "E_DISSOLVE", p, sb, takes, "the dissolve is `base`")
        # the « to » picture is the next run's first: version 1's own start rule refuses one still changing
        p = copy.deepcopy(plan)
        p["scenes"][0]["runs"][1]["segments"][0]["src_at"] = 3640
        refused(self, "E_START", p, sb, takes, "while the screen is still changing")

    def test_a_dissolve_that_goes_back_in_the_take_is_refused(self):
        """The drag's run, by hand, from the tap's touch-down on: whole on
        its own — and the dissolve into it goes back 2.1 s."""
        plan, sb, takes = planned(DISSOLVING)
        p = copy.deepcopy(plan)
        p["scenes"][0]["runs"][1]["segments"][:2] = [{"kind": "hold", "src_at": 1746, "frames": 18},
                                                     {"kind": "live", "src_in": 1746, "src_out": 6806}]
        refused(self, "E_ORDER", p, sb, takes, "the dissolve goes back in the take (2.910 s after 6.400 s)")

    def test_a_touch_point_on_a_picture_of_the_dissolve_is_refused(self):
        """The one-frame tap of the join test, then a dissolve: its « from »
        picture still has the tap's point fading on it."""
        rows = [(1800, CHANGE)] + burst(6000, 6600)
        doc = copy.deepcopy(DISSOLVING)
        doc["scenes"][0]["keep"][0]["rest_after_s"] = 1 / 30
        doc["scenes"][0]["keep"][2]["rest_after_s"] = 9.0         # 15 s of film once the dissolve is allowed
        sb, takes = setup(doc, rows=rows)
        plan = scenes.propose(sb, takes)
        refused(self, "E_DISSOLVE", plan, sb, takes, "the touch point of `S1/tap-a` is on a picture of the dissolve")
        doc["scenes"][0]["keep"][0]["rest_after_s"] = 0.1
        sb, takes = setup(doc, rows=rows)
        scenes.check(scenes.propose(sb, takes), sb, takes)

    def test_the_end_card_is_one_and_a_half_to_two_and_a_half_seconds(self):
        for seconds in (1.4, 2.6):
            sb, takes = setup(doc_with(end_card={**SB2["end_card"], "duration_s": seconds}))
            plan = scenes.propose(sb, takes)
            refused(self, "E_END_CARD", plan, sb, takes, "within 1.5–2.5 s")
        p = copy.deepcopy(self.plan)
        p["end_card"]["frames"] = 70
        refused(self, "E_END_CARD", p, self.sb, self.takes, "the storyboard says 2.2 s")

    def test_the_film_is_15_to_30_seconds(self):
        short = doc_with(scenes__0__keep=[{"gesture": "tap-a", "rest_after_s": 0.5}])
        plan, sb, takes = planned(short)
        refused(self, "E_LENGTH", plan, sb, takes, "(13.433 s); Apple takes 15 to 30 s — S1 5.03 s; S2 5.87 s")
        for rest, total in ((17.0, None), (17.1, "(30.033 s)")):       # 898 frames, then 901
            plan, sb, takes = planned(doc_with(scenes__0__keep=[{"gesture": "tap-a", "rest_after_s": rest}],
                                               film__poster={"scene": "S1", "at_s": 4.0}))
            if total is None:
                self.assertEqual(scenes.check(plan, sb, takes)["total"], 898)
            else:
                refused(self, "E_LENGTH", plan, sb, takes, total)

    def test_a_caption_too_long_for_its_scene_is_refused(self):
        """17 characters a second at most: S2 is 5.87 s, so 99 characters is
        the most its caption may bring; 100 is refused."""
        for n, ok in ((99, True), (100, False)):
            words = "x" * (n - 1)                           # two lines, read joined by a space
            plan, sb, takes = planned(doc_with(scenes__1__headline=[words[: n // 2], words[n // 2:]]))
            if ok:
                scenes.check(plan, sb, takes)
            else:
                refused(self, "E_CAPTION", plan, sb, takes, "scene S2's caption brings 100 characters")

    def test_the_end_cards_line_must_be_read_in_its_time(self):
        """37 characters at 17 a second need 2.18 s: a 2.1 s end card is too
        short for a line one character longer than the disclosure."""
        plan, sb, takes = planned(doc_with(end_card={**SB2["end_card"], "line": "x" * 37, "duration_s": 2.1}))
        refused(self, "E_CAPTION", plan, sb, takes, "the end card's line brings 37 characters")
        plan, sb, takes = planned(doc_with(end_card={**SB2["end_card"], "line": "x" * 35, "duration_s": 2.1}))
        scenes.check(plan, sb, takes)

    def test_what_each_caption_brings_and_for_how_long(self):
        doc = doc_with(scenes__0__subline=["sous", "titre"])
        plan, sb, _ = planned(doc)
        self.assertEqual(scenes.caption_load(sb, plan), [
            {"what": "scene S1's caption", "scene": "S1", "characters": len("Une deux sous titre"), "frames": 226},
            {"what": "scene S2's caption", "scene": "S2", "characters": len("Trois quatre"), "frames": 176},
            {"what": "the end card's line", "scene": "end", "characters": 36, "frames": 66}])

    def test_in_the_full_bleed_frame_a_band_never_covers_a_touch(self):
        """The tap is at (100, 300) pt; the disc is 24 pt across each way."""
        plan, sb, takes = planned()
        plan["frame"] = sb["film"]["frame"] = "full-bleed"
        refused(self, "E_CAPTION", plan, sb, takes, "the caption bands were not measured")
        clear = {"S1": [16, 62, 386, 143], "S2": [16, 62, 386, 143]}
        scenes.check(plan, sb, takes, bands=clear)
        refused(self, "E_CAPTION", plan, sb, takes, "scene S1: the caption band (200–277 pt from the top) covers the "
                "touch of `S1/tap-a` at (100, 300) pt", bands={**clear, "S1": [16, 200, 386, 277]})
        scenes.check(plan, sb, takes, bands={**clear, "S1": [16, 200, 386, 275.9]})
        # the drag: every point of its path
        refused(self, "E_CAPTION", plan, sb, takes, "covers the touch of `S2/drag-b` at (200, 300) pt",
                bands={**clear, "S2": [16, 250, 386, 290]})
        # a framed film needs no band
        plan["frame"] = sb["film"]["frame"] = "framed"
        scenes.check(plan, sb, takes, bands={**clear, "S1": [16, 200, 386, 400]})

    def test_the_poster_is_a_picture_at_rest_in_its_scene(self):
        cases = [
            (0.5, None),                                      # the lead-in
            (4.0, None),                                      # mid-scene, between the tap's answer and the app's own
            (1.2, "the touch point of `S1/tap-a` is on it"),  # 0.2 s after the touch-down
            (4.1, "the screen changed at 6.000 s"),           # on the app's own change
            (7.6, "is not in scene S1"),                      # past S1's end: the join
        ]
        for at, words in cases:
            plan, sb, takes = planned(doc_with(film__poster={"scene": "S1", "at_s": at}))
            if words is None:
                scenes.check(plan, sb, takes)
            else:
                refused(self, "E_POSTER", plan, sb, takes, words)
        p = copy.deepcopy(self.plan)
        p["poster_frame"] += 1
        refused(self, "E_POSTER", p, self.sb, self.takes, "not the storyboard's")

    def test_the_poster_is_not_in_a_dissolve(self):
        doc = copy.deepcopy(DISSOLVING)
        doc["film"]["poster"]["at_s"] = 168 / 30          # the scene's dissolve is its frames 166 to 170
        plan, sb, takes = planned(doc)
        refused(self, "E_POSTER", plan, sb, takes, "falls in scene S1's dissolve")

    def test_the_cut_endpoints_are_compared_when_given(self):
        """S2 keeps the caret's stretch by times, then the drag: the cut
        between them jumps from the picture at 7.500 s to the one at
        8.000 s. Given comparisons, a cut without one is refused."""
        plan, sb, takes = planned(CUTTING)
        segs = plan["scenes"][1]["runs"][0]["segments"]
        self.assertEqual([s["kind"] for s in segs], ["hold", "live", "live", "hold"])
        refused(self, "E_ENDPOINT", plan, sb, takes, "no comparison", diffs={})
        scenes.check(plan, sb, takes)


class Describe(unittest.TestCase):
    def test_the_log_says_where_each_scene_lands_against_its_budget(self):
        plan, sb, takes = planned()
        log = scenes.describe(plan, sb, takes)
        self.assertIn("  S1   film  0.000 –  7.533 s   7.53 s  budget 7 s, +0.53 s", log)
        self.assertIn("  join film  7.533 –  7.700 s  base: 5 frames between the last picture of S1 and the first "
                      "of S2", log)
        self.assertIn("  end  film 13.733 – 15.933 s  the end card, 2.20 s", log)
        self.assertIn("  film  1.000 –  4.533 s  LIVE  take   2.900 s –   6.433 s  (106 frames, 1:1)", log)
        self.assertIn("  the end card's line           36 characters, whole for  2.20 s (16.4 a second)", log)
        self.assertNotIn("REHEARSAL", log)
        plan, sb, takes = planned(doc_with(rehearsal=True))
        self.assertTrue(scenes.describe(plan, sb, takes).startswith("REHEARSAL"))

    def test_a_cut_inside_a_scene_is_logged(self):
        plan, sb, takes = planned(CUTTING)
        log = scenes.describe(plan, sb, takes)
        self.assertIn("  cut  take   7.967 s –   9.977 s removed, lands on film", log)
        self.assertIn("0 quiet frames, 1 caret-only", log)


class Bursts(unittest.TestCase):
    def test_a_take_whose_burst_rows_are_moved_still_finds_its_gestures(self):
        """A sanity check on the fixture itself: the scan the tests read has
        the tap's answer where the docstring says."""
        sb, takes = setup()
        tm = next(iter(takes.values())).tm
        self.assertEqual([(g.id, g.first_change, g.last_change) for g in tm.gestures],
                         [("tap-a", 1800, 3650), ("drag-b", 6000, 6600)])
        self.assertEqual(burst(1800, 1820), [(1800, CHANGE), (1810, CHANGE), (1820, CHANGE)])


if __name__ == "__main__":
    unittest.main()
