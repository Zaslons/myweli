"""The edit list: where gestures are found, what is proposed, and every
refusal — each on a take whose answer is known in advance."""

from __future__ import annotations

import copy
import unittest

import edit
from edit import Refusal
from tests.support import STORYBOARD

T = 600          # ticks per second, as the simulator's recorder writes
STEP = 20        # ticks per film frame at 30 fps

CHANGE = {"soft": 50_000, "strong": 40_000, "max": 255, "box": [100, 600, 1100, 900]}
NOISE = {"soft": 500, "strong": 1, "max": 65, "box": [1092, 2402, 1093, 2403]}   # the probe's loudest still frame
CARET = {"soft": 360, "strong": 360, "max": 250, "box": [300, 1500, 306, 1560]}  # 2 x 20 pt


def scan_of(rows: list[tuple[int, dict]], end: int = 9000) -> dict:
    frames = [{"i": 0, "pts": 0, "soft": 0, "strong": 0, "max": 0}]
    for pts, row in sorted(rows, key=lambda r: r[0]):
        frames.append({"i": len(frames), "pts": pts, **row})
    return {
        "video": {"width": 1206, "height": 2622, "timescale": T, "duration_ticks": end,
                  "codec": "avc1", "nominal_fps": 14.0, "audio_tracks": 0},
        "levels": {"soft": 16, "strong": 64},
        "take": {"file": "take.mov", "bytes": 1234, "sha256": "ab" * 32},
        "frames": frames,
    }


def burst(start: int, end: int, every: int = 10) -> list[tuple[int, dict]]:
    return [(p, CHANGE) for p in range(start, end + 1, every)]


SB = {
    "film": {"fps": 30, "width": 886, "height": 1920, "duration_s": 15.0, "poster_s": 13.0,
             "final_hold_min_s": 3.0},
    "motion": {"caption": "base", "touch_in": "fast", "touch_out": "base"},
    "touch": dict(STORYBOARD["touch"]),
    "timing": {"rest_s": 0.5, "tail_s": 0.3, "sync_tolerance_s": 0.5, "lead_in_s": 1.0,
               "caption_lead_s": 0.8, "rehearsal_hold_s": 2.4, "rehearsal_caption_delay_s": 0.3},
    "captions": {k: {"headline": ["a", "b"], "subline": []} for k in ("one", "two", "three")},
    "shots": [
        {"id": "A", "caption": "one", "gestures": [{"id": "tap-a", "kind": "tap", "rest_after_s": 1.0}]},
        {"id": "B", "caption": "two", "gestures": [{"id": "drag-b", "kind": "drag", "rest_after_s": 0.5}]},
        {"id": "C", "caption": "three", "caption_after": {"gesture": "drag-b", "delay_s": 0.5},
         "gestures": []},
    ],
}

LOG = {
    "device_points": [402, 874],
    "gestures": [
        {"id": "tap-a", "kind": "tap", "near_s": 3.0, "at": [100, 300]},
        {"id": "drag-b", "kind": "drag", "near_s": 10.0, "path": [[200, 600, 0], [200, 300, 400]]},
    ],
}

# The take, by the clock:
#   0.5 s   a still frame the encoder touched up            (noise)
#   3.0 s   tap-a's answer, 3.000–3.167 s
#   6.0 s   the app, on its own (a snackbar leaving), 6.000–6.083 s
#   7–8 s   a caret blinks three times
#  10.0 s   drag-b's answer, 10.000–11.000 s
#  11.7 s   a still frame the encoder touched up
TAKE = ([(300, NOISE)] + burst(1800, 1900) + burst(3600, 3650)
        + [(4200, CARET), (4500, CARET), (4800, CARET)] + burst(6000, 6600) + [(7000, NOISE)])


def fixture():
    scan = scan_of(TAKE)
    return scan, copy.deepcopy(LOG), copy.deepcopy(SB)


def proposed():
    scan, log, sb = fixture()
    return edit.propose(scan, log, sb), scan, log, sb


class Kinds(unittest.TestCase):
    def test_what_is_a_change(self):
        kind = lambda **row: edit.frame_kind(row, 3.0)  # noqa: E731
        self.assertEqual(kind(soft=0, strong=0), "quiet")
        self.assertEqual(kind(soft=500, strong=1, box=[5, 5, 6, 6]), "quiet")      # the probe's loudest still frame
        self.assertEqual(kind(soft=1999, strong=3, box=[0, 0, 900, 900]), "quiet")
        self.assertEqual(kind(soft=16, strong=5, box=[611, 773, 616, 774]), "change")  # the probe's faintest change
        self.assertEqual(kind(soft=4, strong=4, box=[0, 0, 900, 900]), "change")
        self.assertEqual(kind(soft=2000, strong=0), "change")                      # faint, but wide

    def test_what_is_a_caret(self):
        kind = lambda box, soft=360, strong=360: edit.frame_kind({"soft": soft, "strong": strong, "box": box}, 3.0)  # noqa: E731
        self.assertEqual(kind([300, 1500, 306, 1560]), "caret")     # 2 x 20 pt
        self.assertEqual(kind([300, 1500, 318, 1602]), "caret")     # 6 x 34 pt, the limit
        self.assertEqual(kind([300, 1500, 319, 1560]), "change")    # too wide
        self.assertEqual(kind([300, 1500, 306, 1603]), "change")    # too tall
        self.assertEqual(kind([300, 1500, 306, 1529]), "change")    # shorter than a line of text: not a caret
        self.assertEqual(kind([611, 887, 616, 900], strong=61), "change")  # the probe's spinner arrow
        self.assertEqual(kind([300, 1500, 306, 1560], soft=2000), "change")  # something else moved too

    def test_bursts_are_split_by_a_rest(self):
        scan = scan_of(TAKE)
        kinds = edit.frame_kinds(scan, 3.0)
        # the take's first picture counts as a change: the recorder only
        # writes a frame when the screen changes
        self.assertEqual(kinds[0], "change")
        self.assertEqual((kinds.count("change"), kinds.count("quiet"), kinds.count("caret")), (79, 2, 3))
        bursts = edit.find_bursts(scan, kinds, 300)
        self.assertEqual([(b.start, b.end, b.frames) for b in bursts],
                         [(0, 0, 1), (1800, 1900, 11), (3600, 3650, 6), (6000, 6600, 61)])
        self.assertEqual(bursts[1].box, [100, 600, 1100, 900])
        # a rest of exactly `rest` splits; one tick less does not
        close = scan_of(burst(1000, 1100) + burst(1399, 1500))
        self.assertEqual([b.start for b in edit.find_bursts(close, edit.frame_kinds(close, 3.0), 300)], [0, 1000])
        apart = scan_of(burst(1000, 1100) + burst(1400, 1500))
        self.assertEqual([b.start for b in edit.find_bursts(apart, edit.frame_kinds(apart, 3.0), 300)],
                         [0, 1000, 1400])

    def test_frame_hold(self):
        pts = [0, 10, 20, 37, 100]
        self.assertEqual([edit.held(pts, t) for t in (0, 9, 10, 36, 37, 99, 100, 5000)], [0, 0, 1, 2, 3, 3, 4, 4])
        self.assertIsNone(edit.held([5, 10], 4))


class Locate(unittest.TestCase):
    def test_touch_downs_and_responses_are_found_from_the_data(self):
        scan, log, sb = fixture()
        tm = edit.locate(scan, log, sb)
        tap, drag = tm.gestures
        # a tap's point starts `fast` (100 ms) before the app first changes
        self.assertEqual((tap.first_change, tap.down, tap.up), (1800, 1740, 1920))
        # …and the app's answer runs on to the last change before the next
        # touch: the snackbar that leaves on its own at 6 s belongs to it
        self.assertEqual((tap.last_change, tap.burst_end), (3650, 1900))
        # a drag moves the screen once the finger is 18 pt out: 24 ms here
        self.assertEqual((drag.first_change, drag.down, drag.up), (6000, 5986, 6226))
        self.assertEqual(drag.last_change, 6600)
        self.assertEqual(drag.path, [[5986.0, 200, 600], [6226.0, 200, 300]])
        self.assertEqual(tap.distance_pt, 0.0)

    def test_what_follows_the_film_is_not_part_of_the_last_response(self):
        scan = scan_of(TAKE + burst(8400, 8460))
        _, log, sb = fixture()
        self.assertEqual(edit.locate(scan, log, sb).gestures[-1].last_change, 8460)
        log["gestures"].append({"kind": "tap", "near_s": 14.0, "film": False})
        self.assertEqual(edit.locate(scan, log, sb).gestures[-1].last_change, 6600)

    def refused(self, code: str, scan=None, log=None, sb=None, rehearsal=False) -> str:
        s, l, b = fixture()
        with self.assertRaises(Refusal) as cm:
            edit.locate(scan or s, log or l, sb or b, rehearsal)
        self.assertEqual(cm.exception.code, code)
        return cm.exception.message

    def test_a_gesture_with_no_change_near_it_is_refused(self):
        _, log, _ = fixture()
        log["gestures"][0]["near_s"] = 4.6
        self.assertIn("nothing starts changing within ±0.5 s of 4.6 s", self.refused("E_MATCH", log=log))

    def test_two_changes_near_a_gesture_are_refused(self):
        _, log, _ = fixture()
        scan = scan_of(TAKE + burst(2300, 2320))
        log["gestures"][0]["near_s"] = 3.4
        self.assertIn("2 changes start within", self.refused("E_MATCH", scan=scan, log=log))
        log["gestures"][0].update(near_s=3.0, tolerance_s=0.1)
        self.assertEqual(edit.locate(scan, log, copy.deepcopy(SB)).gestures[0].first_change, 1800)

    def test_a_take_that_begins_on_the_first_answer_is_refused(self):
        _, log, _ = fixture()
        scan = scan_of(burst(20, 120) + burst(6000, 6600))
        log["gestures"][0]["near_s"] = 0.0
        self.assertIn("no picture at its touch-down", self.refused("E_NO_REST", scan=scan, log=log))

    def test_a_touch_down_inside_the_previous_response_is_refused(self):
        _, log, _ = fixture()
        scan = scan_of(TAKE + burst(5500, 5600))   # the screen is still changing at 9.333 s…
        log["gestures"][1]["down_s"] = 9.2         # …and the finger is said to land at 9.2 s
        self.assertIn("the screen is still changing at 9.333 s, after its touch-down at 9.200 s — the "
                      "gestures are too close", self.refused("E_MATCH", scan=scan, log=log))

    def test_a_touch_down_after_the_answer_is_refused(self):
        _, log, _ = fixture()
        log["gestures"][1]["down_s"] = 10.2
        self.assertIn("after the app already changed", self.refused("E_MATCH", log=log))

    def test_the_log_must_be_the_storyboards_gestures_in_its_order(self):
        _, log, _ = fixture()
        log["gestures"].reverse()
        self.assertIn("not in the storyboard's order", self.refused("E_LOG", log=log))
        _, log, _ = fixture()
        log["gestures"][0]["id"] = "tap-z"
        self.assertIn("`tap-z` is not in the storyboard", self.refused("E_LOG", log=log))
        _, log, _ = fixture()
        log["gestures"][0]["kind"] = "drag"
        self.assertIn("is a tap in the storyboard, a drag in the log", self.refused("E_LOG", log=log))
        _, log, _ = fixture()
        del log["device_points"]
        self.assertIn("device_points", self.refused("E_LOG", log=log))
        _, log, _ = fixture()
        log["gestures"][0]["film"] = False
        self.assertIn("must come after every filmed gesture", self.refused("E_LOG", log=log))

    def test_a_missing_gesture_is_refused_unless_it_is_a_rehearsal_or_optional(self):
        _, log, sb = fixture()
        del log["gestures"][0]
        self.assertIn("missing storyboard gestures: tap-a", self.refused("E_LOG", log=log))
        self.assertEqual([g.id for g in edit.locate(scan_of(TAKE), log, sb, rehearsal=True).gestures], ["drag-b"])
        sb["shots"][0]["gestures"][0]["optional"] = True
        self.assertEqual([g.id for g in edit.locate(scan_of(TAKE), log, sb).gestures], ["drag-b"])

    def test_a_drag_that_never_leaves_its_start_is_refused(self):
        _, log, _ = fixture()
        log["gestures"][1]["path"] = [[200, 600, 0], [200, 590, 400]]
        self.assertIn("never moves 18 pt", self.refused("E_LOG", log=log))

    def test_a_take_whose_clock_is_not_a_multiple_of_30_is_refused(self):
        scan, _, _ = fixture()
        scan["video"]["timescale"] = 1000
        self.assertIn("not a multiple of 30", self.refused("E_TAKE", scan=scan))

    def test_a_log_that_does_not_describe_its_gestures_is_refused(self):
        def broken(change) -> str:
            _, log, sb = fixture()
            change(log, sb)
            return self.refused("E_LOG", log=log, sb=sb)

        self.assertIn("is not 400x874 points at one scale",
                      broken(lambda log, sb: log.update(device_points=[400, 874])))
        self.assertIn("no gesture to film", broken(lambda log, sb: log.update(gestures=[])))
        self.assertIn("appears twice",
                      broken(lambda log, sb: log["gestures"].append(dict(log["gestures"][1]))))
        self.assertIn("`tap-a` needs `near_s`", broken(lambda log, sb: log["gestures"][0].pop("near_s")))
        self.assertIn("tap `tap-a` needs `at`", broken(lambda log, sb: log["gestures"][0].pop("at")))
        self.assertIn("drag `drag-b` needs `path`",
                      broken(lambda log, sb: log["gestures"][1].update(path=[[200, 600, 0]])))
        self.assertIn("path times start at 0 and increase",
                      broken(lambda log, sb: log["gestures"][1].update(path=[[200, 600, 0], [200, 300, 0]])))
        self.assertIn("path times start at 0 and increase",
                      broken(lambda log, sb: log["gestures"][1].update(path=[[200, 600, 5], [200, 300, 400]])))

        def pinch(log, sb):
            sb["shots"][0]["gestures"][0]["kind"] = "pinch"
            log["gestures"][0]["kind"] = "pinch"
        self.assertIn("unknown kind `pinch`", broken(pinch))


class Propose(unittest.TestCase):
    def test_the_film_is_rests_and_whole_responses(self):
        e, scan, log, sb = proposed()
        self.assertEqual(e["segments"], [
            {"kind": "hold", "src_at": 1740, "frames": 30, "why": "lead-in: the screen at rest before the first touch"},
            {"kind": "live", "src_in": 1740, "src_out": 3860},     # touch-down … last change + 0.3 s
            {"kind": "hold", "src_at": 3840, "frames": 30, "why": "rest after tap-a"},
            {"kind": "live", "src_in": 5986, "src_out": 6806},
            {"kind": "hold", "src_at": 6786, "frames": 15, "why": "rest after drag-b"},
            {"kind": "hold", "src_at": 6786, "frames": 228, "why": "final hold"},
        ])
        self.assertEqual(sum(s.frames for s in edit.spans(e, T, 30)), 450)
        self.assertEqual(e["final_hold_from"], 222)
        self.assertEqual(e["poster_frame"], 390)
        self.assertEqual(e["take"], scan["take"])
        self.assertFalse(e["rehearsal"])
        edit.check(e, scan, log, sb)   # and it obeys the rule

    def test_captions_land_before_the_touch_or_after_the_named_response(self):
        e, *_ = proposed()
        self.assertEqual(e["captions"], [
            {"frame": 0, "caption": "one"},
            {"frame": 142, "caption": "two"},     # 0.8 s before drag-b's touch-down at film frame 166
            {"frame": 212, "caption": "three"},   # 0.5 s after drag-b's own burst ends
        ])

    def test_touch_points_are_in_film_time(self):
        e, *_ = proposed()
        self.assertEqual(e["touches"], [
            {"gesture": "tap-a", "kind": "tap", "down": 600, "up": 780, "path": [[600.0, 100, 300]]},
            {"gesture": "drag-b", "kind": "drag", "down": 3320, "up": 3560,
             "path": [[3320.0, 200, 600], [3560.0, 200, 300]]},
        ])

    def test_film_frames_show_the_take_by_frame_hold(self):
        e, scan, *_ = proposed()
        src = edit.film_sources(e, scan, 30)
        pts = [f["pts"] for f in scan["frames"]]
        self.assertEqual(len(src), 450)
        self.assertEqual({pts[j] for j in src[:30]}, {300})          # lead-in: the picture at 1740
        self.assertEqual([pts[j] for j in src[30:36]], [300, 300, 300, 1800, 1820, 1840])
        self.assertEqual(pts[src[135]], 3650)                        # the live range ends on the last change
        self.assertEqual({pts[j] for j in src[136:166]}, {3650})     # and the rest holds it
        self.assertEqual(pts[src[166]], 4800)                        # resumes on the caret's last blink
        self.assertEqual({pts[j] for j in src[222:]}, {6600})

    def test_responses_that_touch_are_one_piece(self):
        """With a longer tail, the first range reaches the second touch-down:
        the two play as one piece, the real rest between them kept."""
        scan = scan_of(burst(1800, 1900) + burst(2200, 2600))
        _, log, sb = fixture()
        sb["timing"]["tail_s"] = 0.5
        log["gestures"][1].update(near_s=3.67, tolerance_s=0.1)
        e = edit.propose(scan, log, sb)
        live = [s for s in e["segments"] if s["kind"] == "live"]
        self.assertEqual(live, [{"kind": "live", "src_in": 1740, "src_out": 2920}])
        self.assertEqual([s.get("why") for s in e["segments"] if s["kind"] == "hold"],
                         ["lead-in: the screen at rest before the first touch", "rest after drag-b", "final hold"])
        edit.check(e, scan, log, sb)

    def test_a_rehearsal_holds_the_shots_it_has_no_footage_for(self):
        scan, log, sb = fixture()
        del log["gestures"][0]
        e = edit.propose(scan, log, sb, rehearsal=True)
        self.assertEqual([(s["kind"], s.get("why", "")) for s in e["segments"]], [
            ("hold", "rehearsal: shot A has no footage"), ("live", ""),
            ("hold", "rest after drag-b"), ("hold", "final hold")])
        self.assertEqual([c["frame"] for c in e["captions"]], [0, 48, 118])
        self.assertTrue(e["rehearsal"])
        edit.check(e, scan, log, sb)

    def test_a_film_longer_than_the_storyboard_is_refused(self):
        scan, log, sb = fixture()
        sb["film"].update(duration_s=7.0, poster_s=6.9)
        with self.assertRaises(Refusal) as cm:
            edit.propose(scan, log, sb)
        self.assertEqual(cm.exception.code, "E_LENGTH")

    def test_a_storyboard_time_that_is_not_whole_frames_is_refused(self):
        scan, log, sb = fixture()
        sb["shots"][0]["gestures"][0]["rest_after_s"] = 0.25
        with self.assertRaises(Refusal) as cm:
            edit.propose(scan, log, sb)
        self.assertEqual(cm.exception.code, "E_STORYBOARD")
        self.assertIn("0.25 s is not a whole number of frames", cm.exception.message)

    def test_a_shot_without_a_gesture_must_be_the_last_and_say_when_its_caption_comes(self):
        scan, log, sb = fixture()
        sb["shots"].insert(1, {"id": "A2", "caption": "one", "gestures": []})
        with self.assertRaises(Refusal) as cm:
            edit.propose(scan, log, sb)
        self.assertEqual((cm.exception.code, cm.exception.message),
                         ("E_STORYBOARD", "shot A2 has no gesture and is not the last shot"))
        scan, log, sb = fixture()
        del sb["shots"][2]["caption_after"]
        with self.assertRaises(Refusal) as cm:
            edit.propose(scan, log, sb)
        self.assertEqual((cm.exception.code, cm.exception.message),
                         ("E_STORYBOARD", "shot C has no gesture: it needs `caption_after`"))

    def test_the_real_storyboard_makes_a_film(self):
        """Every gesture of storyboard.json, on a take with one burst each."""
        log = {"device_points": [402, 874], "gestures": []}
        rows, t = [], 3.0
        for shot in STORYBOARD["shots"]:
            for g in shot["gestures"]:
                entry = {"id": g["id"], "kind": g["kind"], "near_s": t}
                if g["kind"] == "tap":
                    entry["at"] = [200, 400]
                elif g["kind"] == "drag":
                    entry["path"] = [[100, 400, 0], [300, 400, 300]]
                log["gestures"].append(entry)
                rows += burst(round(t * T), round(t * T) + 240)
                t += 3.0
        scan = scan_of(rows, end=round((t + 3) * T))
        e = edit.propose(scan, log, STORYBOARD)
        edit.check(e, scan, log, STORYBOARD)
        self.assertEqual(sum(s.frames for s in edit.spans(e, T, 30)), 600)
        self.assertEqual([c["caption"] for c in e["captions"]], ["arrivee", "creneau", "comptoir", "agenda"])
        self.assertEqual(len(e["touches"]), 8)   # nine gestures, one of them typed
        self.assertEqual(e["poster_frame"], 540)


class Refusals(unittest.TestCase):
    """`check` on an edit list someone wrote by hand."""

    def refused(self, code: str, e, scan, log, sb, diffs=None) -> str:
        with self.assertRaises(Refusal) as cm:
            edit.check(e, scan, log, sb, diffs)
        self.assertEqual(cm.exception.code, code, cm.exception.message)
        return cm.exception.message

    def test_a_cut_between_a_touch_down_and_the_end_of_the_response_is_refused(self):
        """THE rule. The cut removes only still frames — the four seconds a
        snackbar stays up — and is refused all the same: that wait is the
        app's."""
        e, scan, log, sb = proposed()
        e["segments"][1:2] = [{"kind": "live", "src_in": 1740, "src_out": 2040},
                              {"kind": "live", "src_in": 3540, "src_out": 3860}]
        msg = self.refused("E_PROTECTED", e, scan, log, sb)
        self.assertIn("gesture `tap-a`", msg)
        self.assertIn("(2.900 s) to the end of the app's response (6.083 s)", msg)

    def test_a_hold_inside_a_response_is_refused(self):
        e, scan, log, sb = proposed()
        e["segments"][1:2] = [{"kind": "live", "src_in": 1740, "src_out": 2040},
                              {"kind": "hold", "src_at": 2020, "frames": 30},
                              {"kind": "live", "src_in": 2040, "src_out": 3860}]
        self.assertIn("cuts or holds inside it", self.refused("E_PROTECTED", e, scan, log, sb))

    def test_trimming_the_touch_down_is_refused(self):
        e, scan, log, sb = proposed()
        e["segments"][0]["src_at"] = 1780
        e["segments"][1]["src_in"] = 1780     # 40 ticks after the touch-down, still before the app moves
        e["segments"][1]["src_out"] = 3860
        self.refused("E_PROTECTED", e, scan, log, sb)

    def test_ending_a_response_one_frame_early_is_refused(self):
        e, scan, log, sb = proposed()
        e["segments"][1]["src_out"] = 1740 + 96 * STEP   # the last instant shown is 3640; the last change is 3650
        self.refused("E_PROTECTED", e, scan, log, sb)

    def test_a_cut_over_a_change_outside_any_response_is_refused(self):
        e, _, log, sb = proposed()
        scan = scan_of(TAKE + burst(600, 620))            # something happens before the first touch
        e["segments"][0]["src_at"] = 300                  # the film starts before it and jumps over it
        self.assertIn("the screen changes at 1.000 s of the take and the edit list removes it",
                      self.refused("E_CHANGE_REMOVED", e, scan, log, sb))

    def test_starting_while_the_screen_still_changes_is_refused(self):
        e, _, log, sb = proposed()
        scan = scan_of(TAKE + burst(600, 620))
        e["segments"][0]["src_at"] = 700                  # 0.13 s after the last change before the film
        self.assertIn("while the screen is still changing", self.refused("E_START", e, scan, log, sb))
        e["segments"][0]["src_at"] = 800                  # 0.3 s after it: at rest
        edit.check(e, scan, log, sb)

    def test_starting_right_after_the_takes_first_picture_is_refused(self):
        """The recorder's first frame is the first frame of some change: the
        screen may still be moving."""
        e, scan, log, sb = proposed()
        e["segments"][0]["src_at"] = 100                  # 0.17 s into the take
        self.assertIn("starts at 0.167 s while the screen is still changing (0.000 s)",
                      self.refused("E_START", e, scan, log, sb))
        e["segments"][0]["src_at"] = 180                  # 0.3 s: at rest
        edit.check(e, scan, log, sb)

    def test_starting_before_the_takes_first_picture_is_refused(self):
        e, scan, log, sb = proposed()
        for f in scan["frames"]:
            f["pts"] += 100
        scan["frames"][0]["pts"] = 50
        for g in log["gestures"]:
            g["near_s"] += 100 / T
        e = edit.propose(scan, log, sb)
        e["segments"][0]["src_at"] = 40
        self.assertIn("before the take's first picture", self.refused("E_START", e, scan, log, sb))

    def test_going_back_in_the_take_is_refused(self):
        e, scan, log, sb = proposed()
        e["segments"][1], e["segments"][3] = e["segments"][3], e["segments"][1]
        self.assertIn("goes back in the take", self.refused("E_ORDER", e, scan, log, sb))

    def test_a_speed_cannot_be_written(self):
        e, scan, log, sb = proposed()
        e["segments"][1]["speed"] = 2
        self.assertIn("Footage plays at its own speed", self.refused("E_SHAPE", e, scan, log, sb))
        e, scan, log, sb = proposed()
        e["segments"][1]["frames"] = 53                    # "play these 106 frames in 53"
        self.refused("E_SHAPE", e, scan, log, sb)
        e, scan, log, sb = proposed()
        e["segments"][2]["frames"] = 0
        self.refused("E_SHAPE", e, scan, log, sb)
        e, scan, log, sb = proposed()
        e["segments"][2]["kind"] = "dissolve"
        self.refused("E_SHAPE", e, scan, log, sb)

    def test_a_range_that_is_not_whole_frames_is_refused(self):
        e, scan, log, sb = proposed()
        e["segments"][1]["src_out"] += 7
        self.assertIn("not a whole number of film frames", self.refused("E_GRID", e, scan, log, sb))

    def test_a_malformed_edit_list_is_refused(self):
        e, scan, log, sb = proposed()
        e["segments"] = []
        self.assertIn("has no segments", self.refused("E_SHAPE", e, scan, log, sb))
        e, scan, log, sb = proposed()
        e["segments"][1]["src_out"] = e["segments"][1]["src_in"]
        self.assertIn("src_out after src_in", self.refused("E_SHAPE", e, scan, log, sb))
        e, scan, log, sb = proposed()
        del e["segments"][2]["frames"]
        self.assertIn("a hold is kind, src_at, frames", self.refused("E_SHAPE", e, scan, log, sb))
        e, scan, log, sb = proposed()
        e["segments"][2]["src_at"] = 3840.5
        self.assertIn("src_at must be a tick", self.refused("E_SHAPE", e, scan, log, sb))

    def test_film_time_is_only_defined_inside_the_film(self):
        e, scan, *_ = proposed()
        sp = edit.spans(e, T, 30)
        self.assertEqual(edit.film_tick(sp, 1800, T, 30), 30 * STEP + 60)
        with self.assertRaises(Refusal) as cm:
            edit.film_tick(sp, 4500, T, 30)                 # in the stretch that was cut
        self.assertEqual(cm.exception.code, "E_PROTECTED")
        e["segments"][0]["src_at"] = -20
        with self.assertRaises(Refusal) as cm:
            edit.spans(e, T, 30)
        self.assertEqual(cm.exception.code, "E_SHAPE")
        e["segments"][0] = {"kind": "hold", "src_at": 0, "frames": 30}
        for f in scan["frames"]:
            f["pts"] += 10
        with self.assertRaises(Refusal) as cm:
            edit.film_sources(e, scan, 30)                  # nothing to show at 0: the take starts at 10
        self.assertEqual(cm.exception.code, "E_START")

    def test_an_edit_list_for_another_take_is_refused(self):
        e, scan, log, sb = proposed()
        scan["take"]["sha256"] = "cd" * 32
        self.assertIn("made for another take", self.refused("E_TAKE", e, scan, log, sb))

    def test_a_cut_between_two_different_pictures_is_refused(self):
        e, scan, log, sb = proposed()
        pairs = edit.cut_pairs(e, scan, 30)
        # the lead-in holds the picture the film starts on: no jump there
        pts = [f["pts"] for f in scan["frames"]]
        self.assertEqual([(pts[a], pts[b]) for a, b in pairs], [(3650, 4800)])
        same = {pairs[0]: dict(NOISE)}
        edit.check(e, scan, log, sb, same)
        edit.check(e, scan, log, sb, {pairs[0]: dict(CARET)})   # only the caret differs: the same picture
        self.assertIn("they are not the same picture",
                      self.refused("E_ENDPOINT", e, scan, log, sb, {pairs[0]: dict(CHANGE)}))
        self.assertIn("no comparison of frames", self.refused("E_ENDPOINT", e, scan, log, sb, {}))

    def test_the_wrong_length_is_refused(self):
        e, scan, log, sb = proposed()
        e["segments"][-1]["frames"] += 1
        self.assertIn("451 frames", self.refused("E_LENGTH", e, scan, log, sb))
        e, scan, log, sb = proposed()
        sb["film"].update(duration_s=14.9)                 # the storyboard's own length, under Apple's 15 s
        e["segments"][-1]["frames"] -= 3
        self.assertIn("Apple takes 15 to 30 s", self.refused("E_LENGTH", e, scan, log, sb))

    def test_a_short_or_missing_final_hold_is_refused(self):
        e, scan, log, sb = proposed()
        sb["film"]["final_hold_min_s"] = 9.0
        self.assertIn("the final hold is 7.60 s", self.refused("E_FINAL_HOLD", e, scan, log, sb))
        e, scan, log, sb = proposed()
        e["final_hold_from"] = 200
        self.assertIn("does not end on a hold", self.refused("E_FINAL_HOLD", e, scan, log, sb))

    def test_captions_out_of_order_or_overlapping_are_refused(self):
        e, scan, log, sb = proposed()
        e["captions"][1]["frame"] = 5                      # `base` is 6 frames: the first fade is not over
        self.assertIn("starts before `one` has finished changing", self.refused("E_CAPTION", e, scan, log, sb))
        e, scan, log, sb = proposed()
        e["captions"][1], e["captions"][2] = e["captions"][2], e["captions"][1]
        self.refused("E_CAPTION", e, scan, log, sb)
        e, scan, log, sb = proposed()
        del e["captions"][2]
        self.refused("E_CAPTION", e, scan, log, sb)
        e, scan, log, sb = proposed()
        e["captions"][0]["frame"] = 1
        self.refused("E_CAPTION", e, scan, log, sb)
        e, scan, log, sb = proposed()
        e["captions"][2]["frame"] = 447
        self.assertIn("runs past the end", self.refused("E_CAPTION", e, scan, log, sb))

    def test_a_touch_point_moved_by_hand_is_refused(self):
        e, scan, log, sb = proposed()
        e["touches"][0]["down"] += STEP
        self.assertIn("not where the take and the gesture log put them", self.refused("E_TOUCH", e, scan, log, sb))
        e, scan, log, sb = proposed()
        e["touches"][1]["path"][1][1] = 250
        self.refused("E_TOUCH", e, scan, log, sb)

    def test_the_poster_frame_is_the_storyboards_and_falls_on_a_settled_screen(self):
        e, scan, log, sb = proposed()
        e["poster_frame"] = 300
        self.assertIn("not the storyboard's", self.refused("E_POSTER", e, scan, log, sb))
        scan, log, sb = fixture()
        sb["film"]["poster_s"] = 7.3                       # frame 219: the final hold starts at 222
        e = edit.propose(scan, log, sb)
        self.assertIn("after the last caption and touch point have settled (7.40 s)",
                      self.refused("E_POSTER", e, scan, log, sb))
        sb["film"]["poster_s"] = 7.4
        edit.check(edit.propose(scan, log, sb), scan, log, sb)
        sb["film"]["poster_s"] = 15.0                      # frame 450: the film's frames are 0 to 449
        self.refused("E_POSTER", edit.propose(scan, log, sb), scan, log, sb)

    def test_the_poster_frame_waits_for_the_last_caption(self):
        """In the final hold is not enough: a caption still cross-fading
        would be frozen half-way on the App Store."""
        scan, log, sb = fixture()
        sb["shots"][2]["caption_after"]["delay_s"] = 1.0   # the last caption starts at frame 227, in the hold
        sb["film"]["poster_s"] = 7.6                       # frame 228: the hold began at 222, the fade ends at 233
        e = edit.propose(scan, log, sb)
        self.assertEqual((e["final_hold_from"], e["captions"][-1]["frame"], e["poster_frame"]), (222, 227, 228))
        self.assertIn("have settled (7.77 s)", self.refused("E_POSTER", e, scan, log, sb))
        sb["film"]["poster_s"] = 7.8                       # frame 234
        edit.check(edit.propose(scan, log, sb), scan, log, sb)

    def test_the_poster_frame_waits_for_the_last_touch_point(self):
        """A last tap answered in one frame, no rest after it: the final hold
        begins while its touch point is still fading out."""
        scan = scan_of([(1800, CHANGE)])
        _, log, sb = fixture()
        del log["gestures"][1]
        sb["shots"] = [
            {"id": "A", "caption": "one", "gestures": [{"id": "tap-a", "kind": "tap", "rest_after_s": 0}]},
            {"id": "C", "caption": "three", "caption_after": {"gesture": "tap-a", "delay_s": 0}, "gestures": []},
        ]
        sb["film"]["poster_s"] = 44 / 30
        e = edit.propose(scan, log, sb)
        # the hold begins at frame 43; the point lifts at frame 39 and is gone 0.2 s later, at 45
        self.assertEqual((e["final_hold_from"], e["touches"][0]["up"] // STEP, e["poster_frame"]), (43, 39, 44))
        self.assertIn("have settled (1.50 s)", self.refused("E_POSTER", e, scan, log, sb))
        sb["film"]["poster_s"] = 1.5
        edit.check(edit.propose(scan, log, sb), scan, log, sb)


class Describe(unittest.TestCase):
    def test_every_cut_is_logged_with_what_it_removes_and_where_it_lands(self):
        e, scan, log, sb = proposed()
        pairs = edit.cut_pairs(e, scan, 30)
        text = edit.describe(e, scan, log, sb, {pairs[0]: dict(CARET)})
        for line in (
            "frames 79 change, 2 quiet, 3 caret-only (a change: >= 4 strong or >= 2000 soft pixels)",
            "    0.000 s –   0.000 s     1 frames  (no gesture: the app on its own, or outside the film)",
            "    3.000 s –   3.167 s    11 frames  <- tap-a",
            "    6.000 s –   6.083 s     6 frames  (no gesture: the app on its own, or outside the film)",
            "  film  1.000 –  4.533 s  LIVE  take   2.900 s –   6.433 s  (106 frames, 1:1)",
            "  film  4.533 –  5.533 s  HOLD  the picture at take   6.400 s  (30 frames)  rest after tap-a",
            "  1. take   0.000 s –   2.900 s removed: before the film starts (1 change frame in it",
            "  2. take   6.400 s –   9.977 s removed, lands on film  5.533 s: 0 quiet frames, 3 caret-only "
            "frames in the box [300, 1500, 306, 1560]; frame 18 against frame 21: soft 360, strong 360 (caret)",
            "  3. take  11.310 s –  15.000 s removed: after the film ends (0 change frames in it)",
            "poster frame: film 13 s (frame 390); final hold from 7.400 s; 450 frames, 15.000 s",
        ):
            self.assertIn(line, text)


if __name__ == "__main__":
    unittest.main()
