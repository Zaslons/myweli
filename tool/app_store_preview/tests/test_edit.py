"""The edit list: where gestures are found, what is proposed, and every
refusal — each on a take whose answer is known in advance."""

from __future__ import annotations

import copy
import math
import unittest

import edit
from edit import Refusal
from tests.support import STORYBOARD

T = 600          # ticks per second, as the simulator's recorder writes
STEP = 20        # ticks per film frame at 30 fps

CHANGE = {"soft": 50_000, "strong": 40_000, "max": 255, "box": [100, 600, 1100, 900]}
NOISE = {"soft": 500, "strong": 1, "max": 65, "box": [1092, 2402, 1093, 2403]}   # the probe's loudest still frame
CARET = {"soft": 360, "strong": 360, "max": 250, "box": [300, 700, 306, 760]}    # 2 x 20 pt, where CHANGE was
REST = 300       # ticks without a change that end a burst (timing.rest_s)


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
    "touch": {**STORYBOARD["touch"], "tap_lead": "fast", "tap_dwell": "base"},
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
#   7–8 s   a caret blinks three times, where the app last changed
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
        """Told by where it is: in the column it blinks in, or — the first
        time — inside the last burst of changes."""
        column, area = [300, 700, 306, 760], [100, 600, 1100, 900]

        def kind(box, soft=360, strong=360, column=None, area=None):
            return edit.frame_kind({"soft": soft, "strong": strong, "box": box}, 3.0, column, area)

        # with nothing known about a caret, nothing is one
        self.assertEqual(kind([300, 700, 306, 760]), "change")
        # in its column: the whole caret, a fragment of it, a slightly wider reading of it
        self.assertEqual(kind([300, 700, 306, 760], column=column), "caret")
        self.assertEqual(kind([300, 757, 303, 760], strong=4, column=column), "caret")     # its last row of pixels
        self.assertEqual(kind([299, 694, 308, 772], column=column), "caret")               # 3 x 26 pt together
        self.assertEqual(kind([299, 694, 309, 772], column=column), "change")              # wider than a caret
        self.assertEqual(kind([300, 694, 306, 797], column=column), "change")              # taller than a line of text
        self.assertEqual(kind([315, 700, 321, 760], column=column), "change")              # a caret, 5 pt further: text moved it
        self.assertEqual(kind([300, 694, 316, 772], column=column), "change")              # a typed « . »: 5.3 pt wide
        self.assertEqual(kind([300, 700, 306, 760], soft=2000, column=column), "change")   # something else moved too
        self.assertEqual(kind([300, 700, 306, 760], column=column, area=[900, 900, 1000, 1000]), "caret")
        # seen for the first time: caret-shaped, inside the last burst of changes
        self.assertEqual(kind([300, 700, 306, 760], area=area), "caret")
        self.assertEqual(kind([97, 597, 103, 657], area=area), "caret")                    # 1 pt outside: slack
        self.assertEqual(kind([96, 597, 102, 657], area=area), "change")                   # further out: somewhere new
        self.assertEqual(kind([300, 871, 306, 904], area=area), "change")                  # below it by more than 1 pt
        self.assertEqual(kind([300, 700, 309, 802], area=area), "caret")                   # 3 x 34 pt, the limit
        self.assertEqual(kind([300, 700, 310, 760], area=area), "change")                  # too wide
        self.assertEqual(kind([300, 700, 306, 803], area=area), "change")                  # too tall
        self.assertEqual(kind([300, 700, 306, 730], area=area), "caret")                   # 10 pt tall, the least
        self.assertEqual(kind([300, 700, 306, 729], area=area), "change")                  # a fragment proves nothing
        self.assertEqual(kind([611, 887, 616, 900], strong=61, area=area), "change")       # the probe's spinner arrow
        self.assertEqual(kind([300, 700, 306, 760], soft=2000, area=area), "change")
        self.assertEqual(kind([300, 700, 306, 760], strong=2, area=area), "quiet")

    def test_the_apps_own_caret(self):
        """Rows of the rehearsal take of 2026-10-13, as conform scan gave
        them: the name field takes focus, « Yao K. » is typed. The caret
        fades; what passes the thresholds is the caret, or a corner of it."""
        rows = [
            (24782, 21396, 19862, [48, 2172, 1158, 2340]),   # 41.3 s  the field takes focus: its label floats up
            (24803, 6576, 5493, [53, 2169, 1153, 2335]),
            (24812, 6086, 3912, [53, 2166, 1153, 2335]),
            (24823, 3314, 2341, [55, 2165, 1152, 2333]),
            (24833, 2256, 1257, [64, 2164, 479, 2190]),
            (25083, 464, 4, [109, 2292, 112, 2295]),         # the caret's last row of pixels, 1 x 1 pt
            (25315, 464, 1, [109, 2223, 110, 2224]),         # under the thresholds
            (25344, 464, 72, [110, 2224, 114, 2292]),        # the caret
            (25703, 464, 4, [109, 2292, 112, 2295]),
            (26914, 600, 48, [113, 2240, 114, 2288]),
            (30073, 1190, 710, [111, 2217, 146, 2295]),      # 50.1 s  « Y »
            (30373, 464, 75, [140, 2223, 146, 2295]),        # the caret, after it
            (30413, 611, 9, [140, 2240, 144, 2256]),
            (31963, 1179, 1093, [140, 2217, 170, 2295]),     # « a »
            (32564, 465, 49, [169, 2239, 170, 2288]),
            (33534, 464, 12, [165, 2288, 170, 2295]),
            (33874, 1222, 1176, [164, 2217, 200, 2295]),     # « o » — no caret frame passes before the space
            (35802, 928, 928, [194, 2217, 215, 2295]),       # the space: the caret moves, nothing else
            (36154, 464, 144, [209, 2217, 215, 2288]),
            (37354, 612, 7, [209, 2219, 211, 2223]),
            (37804, 1322, 1266, [209, 2217, 248, 2295]),     # « K »
            (38974, 464, 65, [243, 2223, 247, 2288]),
            (40116, 498, 494, [248, 2217, 264, 2295]),       # « . » — 5.3 x 26 pt: a caret, by size alone
            (41293, 464, 68, [259, 2223, 263, 2288]),
            (47823, 601, 4, [258, 2292, 261, 2295]),
        ]
        scan = scan_of([(pts, {"soft": soft, "strong": strong, "max": 200, "box": box})
                        for pts, soft, strong, box in rows], end=60000)
        reading = edit.read_frames(scan, 3.0, REST)
        pts = [f["pts"] for f in scan["frames"]]
        typed = [24782, 24803, 24812, 24823, 24833, 30073, 31963, 33874, 35802, 37804, 40116]
        self.assertEqual([p for p, k in zip(pts, reading.kinds) if k == "change"], [0] + typed)
        self.assertEqual([p for p, k in zip(pts, reading.kinds) if k == "quiet"], [25315])
        self.assertEqual(reading.kinds.count("caret"), 13)
        # every frame of a still stretch knows the column its caret blinks in,
        # the frames before the caret was first seen included
        at = dict(zip(pts, reading.columns))
        self.assertEqual(at[24833], [109, 2224, 114, 2295])           # after the focus
        self.assertEqual(at[25083], [109, 2224, 114, 2295])
        self.assertEqual(at[30073], [140, 2223, 146, 2295])           # after « Y »
        self.assertEqual(at[33874], None)                             # after « o »: none was seen
        self.assertEqual(at[40116], [258, 2223, 263, 2295])           # after « . »
        self.assertEqual(dict(zip(pts, reading.areas))[33874], [164, 2217, 200, 2295])

    def test_a_caret_that_turns_up_somewhere_new_is_a_change(self):
        """A typed space moves the caret and nothing else. If the caret was
        dark at that instant, all the screen shows is a caret appearing a few
        points further: a change — and from then on, its new column."""
        blink = lambda x: {"soft": 464, "strong": 70, "max": 200, "box": [x, 700, x + 6, 772]}  # noqa: E731
        scan = scan_of(burst(1800, 1900) + [(2400, blink(300)), (2700, blink(300)),
                                             (3000, blink(315)), (3300, blink(315)), (3600, blink(300))])
        kinds = dict(zip([f["pts"] for f in scan["frames"]], edit.frame_kinds(scan, 3.0, REST)))
        self.assertEqual([kinds[p] for p in (2400, 2700, 3000, 3300, 3600)],
                         ["caret", "caret", "change", "caret", "change"])

    def test_a_caret_shape_where_nothing_changed_is_a_change_the_first_time(self):
        """Nothing changed there: it is not the caret of anything the app
        just did. Seen again in the same place, it is one."""
        blink = {"soft": 464, "strong": 70, "max": 200, "box": [300, 1500, 306, 1572]}
        scan = scan_of(burst(1800, 1900) + [(2400, blink), (2700, blink), (3000, blink)])
        kinds = dict(zip([f["pts"] for f in scan["frames"]], edit.frame_kinds(scan, 3.0, REST)))
        self.assertEqual([kinds[p] for p in (2400, 2700, 3000)], ["change", "caret", "caret"])
        # and with no change at all before it — a take that opens on a focused field
        scan = scan_of([(2400, blink), (2700, blink)])
        self.assertEqual(edit.frame_kinds(scan, 3.0, REST), ["change", "change", "caret"])

    def test_small_changes_inside_the_last_burst_are_not_a_caret(self):
        """The probe clip's refresh spinner: an arrow that grows by a few
        pixels a frame, inside the list that has just moved."""
        dots = [[611, 773, 616, 774], [611, 773, 620, 779], [611, 773, 628, 788], [611, 887, 616, 900]]
        scan = scan_of(burst(1800, 1900) + [(2000 + 10 * n, {"soft": 40, "strong": 30, "max": 200, "box": b})
                                             for n, b in enumerate(dots)])
        self.assertEqual(edit.frame_kinds(scan, 3.0, REST).count("caret"), 0)
        # …and a fragment that comes before a caret elsewhere is not that caret
        scan = scan_of(burst(1800, 1900) + [(2400, {"soft": 40, "strong": 30, "max": 200, "box": dots[0]}),
                                             (2700, dict(CARET))])
        kinds = dict(zip([f["pts"] for f in scan["frames"]], edit.frame_kinds(scan, 3.0, REST)))
        self.assertEqual((kinds[2400], kinds[2700]), ("change", "change"))

    def test_a_fragment_is_only_the_caret_of_its_own_stretch(self):
        """A corner of a caret, then a change, then a caret in that place:
        the corner came before the change — it is not that caret's."""
        corner = {"soft": 464, "strong": 4, "max": 200, "box": [300, 757, 303, 760]}
        typed = {"soft": 1200, "strong": 1100, "max": 250, "box": [280, 694, 320, 772]}
        scan = scan_of(burst(1800, 1900) + [(2400, corner), (2500, typed), (2800, dict(CARET)), (3100, corner)])
        kinds = dict(zip([f["pts"] for f in scan["frames"]], edit.frame_kinds(scan, 3.0, REST)))
        self.assertEqual([kinds[p] for p in (2400, 2500, 2800, 3100)], ["change", "change", "caret", "caret"])
        # with nothing between them, it is: the caret, a moment earlier
        scan = scan_of(burst(1800, 1900) + [(2400, corner), (2800, dict(CARET))])
        kinds = dict(zip([f["pts"] for f in scan["frames"]], edit.frame_kinds(scan, 3.0, REST)))
        self.assertEqual((kinds[2400], kinds[2800]), ("caret", "caret"))
        # a small change somewhere else is a change in between, like a big one
        dot = {"soft": 40, "strong": 30, "max": 200, "box": [611, 773, 616, 774]}
        scan = scan_of(burst(1800, 1900) + [(2400, corner), (2500, dot), (2800, dict(CARET)), (3100, dict(CARET))])
        kinds = dict(zip([f["pts"] for f in scan["frames"]], edit.frame_kinds(scan, 3.0, REST)))
        self.assertEqual([kinds[p] for p in (2400, 2500, 2800, 3100)], ["change", "change", "change", "caret"])
        # …and two corners of the same caret are both it
        top = {"soft": 464, "strong": 5, "max": 200, "box": [300, 700, 303, 703]}
        scan = scan_of(burst(1800, 1900) + [(2400, corner), (2500, top), (2800, dict(CARET))])
        self.assertEqual(edit.frame_kinds(scan, 3.0, REST)[-3:], ["caret", "caret", "caret"])

    def test_the_area_a_caret_may_appear_in_is_the_whole_burst(self):
        """The focus burst ends on a frame that does not cover the caret (the
        label still floating): the burst as a whole does."""
        wide = lambda box: {"soft": 9000, "strong": 8000, "max": 250, "box": box}  # noqa: E731
        rows = [(1800, wide([100, 600, 1100, 900])), (1810, wide([100, 600, 400, 640])), (2400, dict(CARET))]
        self.assertEqual(edit.frame_kinds(scan_of(rows), 3.0, REST)[-1], "caret")
        # a frame a rest later begins another burst: the first one no longer counts
        rows = [(1800, wide([100, 600, 1100, 900])), (2100, wide([100, 600, 400, 640])), (2700, dict(CARET))]
        self.assertEqual(edit.frame_kinds(scan_of(rows), 3.0, REST)[-1], "change")
        rows = [(1800, wide([100, 600, 1100, 900])), (2099, wide([100, 600, 400, 640])), (2700, dict(CARET))]
        self.assertEqual(edit.frame_kinds(scan_of(rows), 3.0, REST)[-1], "caret")
        # a faint change with no box may be anywhere
        rows = [(1800, {"soft": 2500, "strong": 0, "max": 40}), (2400, dict(CARET))]
        self.assertEqual(edit.frame_kinds(scan_of(rows), 3.0, REST)[-1], "caret")

    def test_bursts_are_split_by_a_rest(self):
        scan = scan_of(TAKE)
        kinds = edit.frame_kinds(scan, 3.0, REST)
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
        self.assertEqual([b.start for b in edit.find_bursts(close, edit.frame_kinds(close, 3.0, REST), 300)], [0, 1000])
        apart = scan_of(burst(1000, 1100) + burst(1400, 1500))
        self.assertEqual([b.start for b in edit.find_bursts(apart, edit.frame_kinds(apart, 3.0, REST), 300)],
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

    def test_the_drivers_own_times_find_the_first_change_in_between(self):
        """`after_s` and `before_s`: when the driver asked for the gesture and
        when its call came back. The touch-down is in between — found from
        the first frame that changes there."""
        _, log, _ = fixture()
        log["gestures"][0] = {"id": "tap-a", "kind": "tap", "after_s": 1.2, "before_s": 7.5, "at": [100, 300]}
        self.assertEqual(edit.locate(scan_of(TAKE), log, copy.deepcopy(SB)).gestures[0].first_change, 1800)
        log["gestures"][0].update(after_s=3.0, before_s=3.0001)        # the very instant counts
        self.assertEqual(edit.locate(scan_of(TAKE), log, copy.deepcopy(SB)).gestures[0].first_change, 1800)
        log["gestures"][0].update(after_s=3.01, before_s=7.5)          # asked for after 3.0 s: the next one
        self.assertEqual(edit.locate(scan_of(TAKE), log, copy.deepcopy(SB)).gestures[0].first_change, 3600)
        log["gestures"][0].update(after_s=3.01, before_s=5.9)
        self.assertIn("nothing starts changing between 3.01 s and 5.9 s", self.refused("E_MATCH", log=log))
        del log["gestures"][0]["before_s"]
        self.assertIn("`after_s` needs a later `before_s`", self.refused("E_LOG", log=log))
        log["gestures"][0].update(after_s=3.0, before_s=3.0)
        self.assertIn("`after_s` needs a later `before_s`", self.refused("E_LOG", log=log))
        # a burst already taken by the gesture before is not taken again
        _, log, _ = fixture()
        log["gestures"][1] = {"id": "drag-b", "kind": "drag", "after_s": 2.0, "before_s": 12.0,
                              "path": [[200, 600, 0], [200, 300, 400]]}
        self.assertEqual(edit.locate(scan_of(TAKE), log, copy.deepcopy(SB)).gestures[1].first_change, 3600)

    def test_a_tap_point_appears_before_the_answer_and_leaves_after_it(self):
        """`touch.tap_lead` and `touch.tap_dwell`, motion tokens both."""
        scan, log, sb = fixture()
        sb["touch"].update(tap_lead="base", tap_dwell="fast")          # 200 ms before, 100 ms after
        tap = edit.locate(scan, log, sb).gestures[0]
        self.assertEqual((tap.down, tap.first_change, tap.up), (1680, 1800, 1860))
        sb["motion"]["touch_in"] = "slow"                              # a fade-in longer than the lead
        self.assertIn("the point would not be whole when the app answers", self.refused("E_STORYBOARD", sb=sb))

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


# Typed text: one gesture in the storyboard, one key at a time on the screen.
#   3.0 s   tap-a's answer
#   5.0 s   a key: a letter and the caret after it; 5.5 s the caret blinks
#   8.0 s   a key; 8.5 s the caret blinks
#  11.0 s   a key
KEY = lambda x: {"soft": 1200, "strong": 1100, "max": 250, "box": [x, 694, x + 40, 772]}        # noqa: E731
BLINK = lambda x: {"soft": 464, "strong": 70, "max": 200, "box": [x + 34, 700, x + 40, 772]}    # noqa: E731
KEYS_TAKE = burst(1800, 1900) + [(3000, KEY(300)), (3300, BLINK(300)), (4800, KEY(334)), (5100, BLINK(334)),
                                 (6600, KEY(368))]
KEYS_SB = copy.deepcopy(SB)
KEYS_SB["shots"] = [
    {"id": "A", "caption": "one", "gestures": [{"id": "tap-a", "kind": "tap", "rest_after_s": 0.2},
                                                {"id": "type-b", "kind": "type", "rest_after_s": 0.5}]},
    {"id": "C", "caption": "three", "caption_after": {"gesture": "type-b", "delay_s": 0.5}, "gestures": []},
]
KEYS_LOG = {"device_points": [402, 874], "gestures": [
    {"id": "tap-a", "kind": "tap", "near_s": 3.0, "at": [100, 300]},
    {"id": "type-b", "kind": "type", "keys": [{"near_s": 5.0}, {"after_s": 7.0, "before_s": 9.0}, {"near_s": 11.0}]},
]}


class Keys(unittest.TestCase):
    def fixture(self):
        return scan_of(KEYS_TAKE), copy.deepcopy(KEYS_LOG), copy.deepcopy(KEYS_SB)

    def test_each_key_is_found_on_its_own(self):
        scan, log, sb = self.fixture()
        tap, *keys = edit.locate(scan, log, sb).gestures
        self.assertEqual([k.id for k in keys], ["type-b[1]", "type-b[2]", "type-b[3]"])
        self.assertEqual({k.gesture for k in keys}, {"type-b"})
        self.assertEqual([k.last for k in keys], [False, False, True])
        # a key is not on the screen: its range starts the touch point's
        # fade-in before the letter shows, on a picture that is still
        self.assertEqual([(k.down, k.first_change, k.last_change) for k in keys],
                         [(2940, 3000, 3000), (4740, 4800, 4800), (6540, 6600, 6600)])
        self.assertEqual([k.path for k in keys], [[], [], []])           # and no touch point
        self.assertEqual(tap.last_change, 1900)                          # the caret after the tap's answer is not a change

    def test_the_waits_between_keys_are_cut_and_nothing_else(self):
        scan, log, sb = self.fixture()
        e = edit.propose(scan, log, sb)
        self.assertEqual(e["segments"], [
            {"kind": "hold", "src_at": 1740, "frames": 30, "why": "lead-in: the screen at rest before the first touch"},
            {"kind": "live", "src_in": 1740, "src_out": 2100},
            {"kind": "hold", "src_at": 2080, "frames": 6, "why": "rest after tap-a"},
            {"kind": "live", "src_in": 2940, "src_out": 3200},       # a key and 0.3 s after it…
            {"kind": "live", "src_in": 4740, "src_out": 5000},       # …then the next, with no hold between
            {"kind": "live", "src_in": 6540, "src_out": 6800},
            {"kind": "hold", "src_at": 6780, "frames": 15, "why": "rest after type-b"},
            {"kind": "hold", "src_at": 6780, "frames": 342, "why": "final hold"},
        ])
        self.assertEqual(e["touches"], [{"gesture": "tap-a", "kind": "tap", "down": 600, "up": 780,
                                         "path": [[600.0, 100, 300]]}])
        # the last caption follows the LAST key
        self.assertEqual(e["captions"][-1], {"frame": 54 + 26 + 3 + 15, "caption": "three"})
        tm = edit.check(e, scan, log, sb)
        # the caret between two keys may be cut: it blinks in its column
        pairs = edit.cut_pairs(e, scan, 30)
        pts = [f["pts"] for f in scan["frames"]]
        self.assertEqual([(pts[a], pts[b]) for a, b in pairs], [(3000, 3300), (4800, 5100)])
        diffs = {pairs[0]: BLINK(300), pairs[1]: BLINK(334)}
        edit.check(e, scan, log, sb, diffs)
        self.assertEqual(edit.pair_kind(BLINK(300), tm, pairs[0][1]), "caret")
        # …a corner of it too: in its column, it needs no other proof
        corner = {"soft": 464, "strong": 4, "max": 200, "box": [334, 769, 337, 772]}
        edit.check(e, scan, log, sb, {pairs[0]: corner, pairs[1]: BLINK(334)})
        # …but the two sides of a cut may not differ by a letter
        with self.assertRaises(Refusal) as cm:
            edit.check(e, scan, log, sb, {pairs[0]: KEY(334), pairs[1]: BLINK(334)})
        self.assertEqual(cm.exception.code, "E_ENDPOINT")
        # …nor by a caret that is not this stretch's
        with self.assertRaises(Refusal) as cm:
            edit.check(e, scan, log, sb, {pairs[0]: BLINK(334), pairs[1]: BLINK(334)})
        self.assertEqual(cm.exception.code, "E_ENDPOINT")
        self.assertIn("box [368, 700, 374, 772]", cm.exception.message)

    def test_a_cut_may_skip_a_caret_that_never_passed_the_thresholds(self):
        """Between « o » and the space of the rehearsal take no frame of the
        caret was loud enough to be seen — and the two sides of the cut still
        differed by it. It is where the last key left it: nothing changing."""
        # the take with its blinks under the thresholds: frames, but quiet ones
        scan = scan_of([(pts, dict(NOISE) if row["strong"] == 70 else row) for pts, row in KEYS_TAKE])
        _, log, sb = self.fixture()
        e = edit.propose(scan, log, sb)
        tm = edit.check(e, scan, log, sb)
        pairs = edit.cut_pairs(e, scan, 30)
        self.assertEqual((tm.reading.columns[pairs[0][1]], tm.reading.areas[pairs[0][1]]),
                         (None, [300, 694, 340, 772]))
        edit.check(e, scan, log, sb, {pairs[0]: BLINK(300), pairs[1]: BLINK(334)})
        with self.assertRaises(Refusal) as cm:                               # a caret outside what the key changed
            edit.check(e, scan, log, sb, {pairs[0]: BLINK(310), pairs[1]: BLINK(334)})
        self.assertEqual(cm.exception.code, "E_ENDPOINT")

    def test_a_cut_inside_a_keys_answer_is_refused(self):
        scan, log, sb = self.fixture()
        e = edit.propose(scan, log, sb)
        e["segments"][4]["src_in"] = 4820            # the second letter is already there when the film resumes
        e["segments"][4]["src_out"] = 5000
        with self.assertRaises(Refusal) as cm:
            edit.check(e, scan, log, sb)
        self.assertEqual(cm.exception.code, "E_PROTECTED")
        self.assertIn("gesture `type-b[2]`", cm.exception.message)

    def test_a_key_has_its_own_tail(self):
        """`timing.key_tail_s`: a key answers in one frame and the next key
        follows — 0.1 s before the letter, 0.1 s after it, 7 frames; the tap
        keeps the 0.3 s every other answer has."""
        scan, log, sb = self.fixture()
        sb["timing"]["key_tail_s"] = 0.1
        e = edit.propose(scan, log, sb)
        self.assertEqual([s for s in e["segments"] if s["kind"] == "live"], [
            {"kind": "live", "src_in": 1740, "src_out": 2100},
            {"kind": "live", "src_in": 2940, "src_out": 3080},
            {"kind": "live", "src_in": 4740, "src_out": 4880},
            {"kind": "live", "src_in": 6540, "src_out": 6680}])
        self.assertEqual(e["segments"][-2], {"kind": "hold", "src_at": 6660, "frames": 15, "why": "rest after type-b"})
        edit.check(e, scan, log, sb)

    def test_text_typed_in_one_go_is_one_piece(self):
        scan, log, sb = self.fixture()
        log["gestures"][1] = {"id": "type-b", "kind": "type", "near_s": 5.0}
        typed = edit.locate(scan, log, sb).gestures[1]
        # everything up to the end of the take is its answer: the other letters too
        self.assertEqual((typed.id, typed.down, typed.last_change, typed.last), ("type-b", 2940, 6600, True))

    def test_keys_that_are_not_a_list_of_times_are_refused(self):
        for keys in ([], "Yao", [5.0, 8.0]):
            scan, log, sb = self.fixture()
            log["gestures"][1]["keys"] = keys
            with self.assertRaises(Refusal) as cm:
                edit.locate(scan, log, sb)
            self.assertEqual(cm.exception.code, "E_LOG")
            self.assertIn("`keys` is a list of when each key was pressed", cm.exception.message)
        scan, log, sb = self.fixture()
        log["gestures"][1]["keys"][1] = {}
        with self.assertRaises(Refusal) as cm:
            edit.locate(scan, log, sb)
        self.assertIn("gesture `type-b[2]` needs `near_s`", cm.exception.message)


# A drag, as the log has it: 10 pt every 16 ms from x = 100 to 190, then the
# finger rests 120 ms before it leaves.
DRAG = [[100 + 10 * n, 300, 16 * n] for n in range(10)] + [[190, 300, 264]]


class Follow(unittest.TestCase):
    """`followed_path`: the logged path, placed on what the picture did."""

    def track(self, frames, **more):
        return {"axis": "x", "sign": 1, "frames": frames, "turn": None, **more}

    def test_the_point_is_where_the_log_has_the_finger_when_the_picture_is_that_far(self):
        # the picture: late to start (20 pt already at its first frame), then
        # 10 pt a frame at uneven times, and it stops at 60 pt — a pane fully open
        seen = [[6000, 20.0], [6010, 30.0], [6030, 40.0], [6040, 50.0], [6060, 60.0], [6070, 60.0], [6080, 60.0]]
        got = edit.followed_path(DRAG, self.track(seen), T)
        self.assertEqual(got["points"], [
            [5980.8, 100, 300], [5990.4, 110, 300],             # before: the log's own times, back from 6000
            [6000.0, 120.0, 300.0], [6010.0, 130.0, 300.0], [6030.0, 140.0, 300.0], [6040.0, 150.0, 300.0],
            [6060.0, 160.0, 300.0],                             # one point a frame, as far as the picture
            [6069.6, 170, 300], [6079.2, 180, 300], [6088.8, 190, 300], [6160.8, 190, 300],   # after: the log's
        ])
        self.assertEqual((got["down"], got["up"], got["step"]), (5980.8, 6160.8, [6000, 6060]))
        self.assertEqual((got["frames"], got["reach"]), (5, (20.0, 60.0, 90)))

    def test_between_two_logged_samples_the_point_is_between_them(self):
        got = edit.followed_path(DRAG, self.track([[6000, 25.0], [6020, 47.5]]), T)
        self.assertEqual(got["points"][3:5], [[6000.0, 125.0, 300.0], [6020.0, 147.5, 300.0]])
        self.assertEqual(got["points"][2], [5995.2, 120, 300])     # the sample at 32 ms, 8 ms before 40 ms

    def test_the_finger_has_left_when_the_picture_turns_back(self):
        seen = [[6000, 20.0], [6010, 30.0], [6030, 40.0], [6040, 50.0], [6060, 60.0], [6075, 55.0]]
        got = edit.followed_path(DRAG, self.track(seen, turn=6075), T)
        # 15 ticks after the last frame that followed = 25 ms of the log: 9/16 of the way from 170 to 180
        self.assertEqual(got["points"][-2:], [[6069.6, 170, 300], [6075.0, 175.625, 300.0]])
        self.assertEqual(got["up"], 6075.0)

    def test_a_picture_that_goes_further_than_the_finger_is_on_its_own(self):
        """A pane that snaps shut after the finger lets go."""
        seen = [[6000, 20.0], [6010, 60.0], [6020, 90.0], [6030, 92.5], [6040, 110.0]]
        got = edit.followed_path(DRAG, self.track(seen), T)
        self.assertEqual(got["step"], [6000, 6020])
        self.assertEqual(got["points"][-2:], [[6020.0, 190.0, 300.0], [6092.0, 190, 300]])   # then the log's 120 ms rest
        seen[3][1] = 91.9                                          # within 2 pt of the end: still the finger,
        got = edit.followed_path(DRAG, self.track(seen), T)        # at the end of its path
        self.assertEqual((got["step"], got["reach"]), ([6000, 6030], (20.0, 90, 90)))

    def test_a_picture_that_dips_is_followed_no_further(self):
        seen = [[6000, 20.0], [6010, 30.0], [6020, 25.0], [6030, 40.0]]
        self.assertEqual(edit.followed_path(DRAG, self.track(seen), T)["step"], [6000, 6010])

    def test_an_upward_drag(self):
        path = [[330, 600 - 10 * n, 16 * n] for n in range(6)]
        got = edit.followed_path(path, {"axis": "y", "sign": -1, "frames": [[900, 10.0], [915, 30.0]], "turn": None}, T)
        self.assertEqual(got["points"], [[890.4, 330, 600], [900.0, 330.0, 590.0], [915.0, 330.0, 570.0],
                                         [924.6, 330, 560], [934.2, 330, 550]])

    def test_a_picture_that_gives_nothing_to_go_by(self):
        none = lambda frames, path=DRAG: edit.followed_path(path, self.track(frames), T)  # noqa: E731
        self.assertIsNone(none([]))
        self.assertIsNone(none([[6000, 0.0], [6010, 0.4]]))                  # it never moved
        self.assertIsNone(none([[6000, 20.0]]))                              # one frame is not a path
        self.assertIsNone(none([[6000, 20.0], [6010, 20.0]]))                # it moved once and stopped
        self.assertIsNone(none([[6000, 20.0], [6010, 10.0]]))                # it went the other way
        self.assertIsNone(none([[6000, 20.0], [6010, 30.0]], [[100, 300, 0], [150, 300, 50], [120, 300, 90]]))
        self.assertIsNotNone(none([[6000, 0.5], [6010, 30.0]]))              # half a point: it has begun

    def located(self, track):
        scan, log, sb = fixture()
        log["gestures"][1]["path"] = [[200, 600 - p[0] + 100, p[2]] for p in DRAG]   # the same drag, upwards
        tracks = {"drag-b": track} if track else None
        return edit.locate(scan, log, sb, tracks=tracks).gestures[1], scan, log, sb, tracks

    def test_a_followed_drag_is_placed_by_its_frames(self):
        frames = [[6000, 20.0], [6010, 30.0], [6030, 40.0], [6040, 50.0], [6060, 60.0]]
        drag, scan, log, sb, tracks = self.located({"axis": "y", "sign": -1, "frames": frames, "turn": None})
        # the point is whole by the time the picture moves: `fast` before the
        # first change, earlier than the log's own start
        self.assertEqual((drag.down, drag.first_change, drag.up, drag.step), (5940, 6000, 6161, [6000, 6060]))
        self.assertEqual(drag.path[:4], [[5940.0, 200, 600], [5980.8, 200, 600], [5990.4, 200, 590],
                                         [6000.0, 200.0, 580.0]])
        self.assertEqual(drag.how, "followed in the picture on 5 frames, from 20.0 to 60.0 pt of the 90 pt logged")
        e = edit.propose(scan, log, sb, tracks=tracks)
        touch = e["touches"][1]
        self.assertEqual((touch["down"], touch["up"], touch["step"]), (3320, 3541, [3380, 3440]))
        self.assertEqual(touch["path"][3], [3380.0, 200.0, 580.0])
        edit.check(e, scan, log, sb, tracks=tracks)
        said = edit.describe(e, scan, log, sb, tracks=tracks)
        self.assertIn("followed in the picture on 5 frames", said)
        # the film's frames are on ticks 5940, 5960, …: at 6000 the picture is 20 pt along, at 6020 it shows the
        # frame of 6010 (30 pt), at 6040 50 pt, at 6060 60 pt
        self.assertIn("drags, film frame by film frame (points the picture moved under the finger)\n"
                      "  drag-b           20 10 20 10\n"
                      "                   first step 20 pt; 0 film frames did not move\n", said)
        self.assertEqual(edit.drag_steps(edit.locate(scan, log, sb, tracks=tracks).gestures[1], tracks["drag-b"],
                                         edit.spans(e, T, 30), STEP), [20.0, 10.0, 20.0, 10.0])
        self.assertNotIn("drags, film frame by film frame", edit.describe(edit.propose(scan, log, sb), scan, log, sb))
        # the same edit list without the reading of the picture: the points are not where the data puts them
        with self.assertRaises(Refusal) as cm:
            edit.check(e, scan, log, sb)
        self.assertEqual(cm.exception.code, "E_TOUCH")

    def test_a_log_that_starts_before_the_fade_in_keeps_its_own_start(self):
        frames = [[6000, 80.0], [6010, 85.0], [6020, 90.0]]          # the first frame is 128 ms into the log
        drag, *_ = self.located({"axis": "y", "sign": -1, "frames": frames, "turn": None})
        self.assertEqual((drag.down, drag.path[0], drag.path[1]), (5923, [5923.0, 200, 600], [5923.2, 200, 600]))

    def test_a_drag_that_cannot_be_followed_says_so_and_keeps_the_logs_times(self):
        drag, scan, log, sb, tracks = self.located({"axis": "y", "sign": -1, "frames": [], "turn": None,
                                                    "why": "nothing to recognise under the finger"})
        self.assertEqual(drag.how, "NOT followed in the picture (nothing to recognise under the finger): timed by "
                                   "the logged path, 1:1")
        self.assertIsNone(drag.step)
        self.assertEqual(drag.down, 6000 - round(28.8 * 0.6))         # 18 pt along the log: 28.8 ms
        self.assertIn("NOT followed in the picture", edit.describe(edit.propose(scan, log, sb, tracks=tracks),
                                                                   scan, log, sb, tracks=tracks))
        drag, *_ = self.located({"axis": "y", "sign": -1, "frames": [[6000, 0.2]], "turn": None})
        self.assertIn("the picture gave nothing to go by", drag.how)
        drag, *_ = self.located(None)
        self.assertIn("the pictures were not looked at", drag.how)

    def test_a_logged_touch_down_wins_over_the_picture(self):
        scan, log, sb = fixture()
        track = {"axis": "y", "sign": -1, "frames": [[6000, 20.0], [6010, 30.0]], "turn": None}
        followed = edit.locate(scan, log, sb, tracks={"drag-b": track}).gestures[1]
        self.assertEqual((followed.down, followed.step), (5940, [6000, 6010]))      # the picture can be followed…
        log["gestures"][1]["down_s"] = 9.95
        drag = edit.locate(scan, log, sb, tracks={"drag-b": track}).gestures[1]
        self.assertEqual((drag.down, drag.step, drag.how), (5970, None, "timed by the log's own `down_s`"))


# The rehearsal take's opening swipe, as conform scan timed its eleven changed
# pictures (ticks of 1/600 s) — the take's first picture before them. The
# driver's samples reached the app unevenly: the pictures are 2 to 29 ticks
# apart, and the touch-down was read at 3203.
SWIPE = [0, 3271, 3273, 3283, 3312, 3333, 3343, 3353, 3374, 3383, 3404, 3414]


class Phase(unittest.TestCase):
    """Where a kept range sits on the film's thirty frames a second."""

    def test_what_the_film_shows_of_a_take_with_more_pictures_than_frames(self):
        # started on the touch-down: the film's instants are 3263, 3283, 3303, 3323, 3343, 3363, 3383, 3403, 3423
        # — the picture of 3283 is still there at 3303, the picture of 3383 at 3403: two frames that do not move
        self.assertEqual(edit.sampling(SWIPE, 3203, 21, STEP, REST), (2, 6))
        # one tick earlier: 3282, 3302, 3322, 3342, 3362, 3382, 3402, 3422 — eight pictures, none twice
        self.assertEqual(edit.sampling(SWIPE, 3202, 21, STEP, REST), (0, 8))
        # a picture that stays because the take is at rest is not a repeat…
        self.assertEqual(edit.sampling([0, 1000], 940, 20, STEP, REST), (0, 1))
        # …nor is the one the range starts on, however long before its first change
        self.assertEqual(edit.sampling([0, 900, 1000], 940, 20, STEP, 300), (0, 1))
        # two pictures further apart than a rest are two bursts: the wait between them is the app's
        self.assertEqual(edit.sampling([0, 1000, 1300], 940, 30, STEP, 300), (0, 2))
        self.assertEqual(edit.sampling([0, 1000, 1299], 940, 30, STEP, 300), (14, 2))

    def test_a_range_starts_where_the_film_repeats_least_then_shows_most_then_latest(self):
        self.assertEqual(edit.phase(SWIPE, 3203, 3414 + 180, 180, math.inf, STEP, REST), 1)
        # a picture every film frame: nothing to gain, the range starts on its touch-down
        even = [0] + list(range(1000, 1201, 20))
        self.assertEqual(edit.phase(even, 940, 1380, 180, math.inf, STEP, REST), 0)
        # no repeat either way, but 6 ticks earlier the film shows both pictures instead of one
        self.assertEqual(edit.sampling([0, 1000, 1010], 955, 13, STEP, REST), (0, 1))
        self.assertEqual(edit.sampling([0, 1000, 1010], 949, 14, STEP, REST), (0, 2))
        self.assertEqual(edit.phase([0, 1000, 1010], 955, 1190, 180, math.inf, STEP, REST), 6)

    def test_it_never_reaches_into_what_is_around_it(self):
        uneven = [0, 1000, 1030, 1050]
        self.assertEqual(edit.sampling(uneven, 940, 16, STEP, REST), (1, 3))
        self.assertEqual(edit.phase(uneven, 940, 1230, 180, math.inf, STEP, REST), 1)
        self.assertEqual(edit.phase(uneven, 940, 1230, 939, math.inf, STEP, REST), 1)
        self.assertEqual(edit.phase(uneven, 940, 1230, 940, math.inf, STEP, REST), 0)   # the screen was not still before
        # the next range starts at 1255: one to four ticks earlier this one would run to 1259…1256
        self.assertEqual(edit.phase(uneven, 940, 1230, 180, 1255, STEP, REST), 5)
        self.assertEqual(edit.frames_for(935, 1230, STEP) * STEP + 935, 1255)

    def swipe(self):
        scan = scan_of([(p, CHANGE) for p in SWIPE[1:]], end=6000)
        _, log, sb = fixture()
        log["gestures"].pop(0)
        log["gestures"][0].update(near_s=3271 / T, tolerance_s=0.01, down_s=3203 / T)
        sb["shots"] = sb["shots"][1:]                       # the drag, then the last caption
        return scan, log, sb

    def test_propose_sets_each_range_on_the_films_frames(self):
        scan, log, sb = self.swipe()
        e = edit.propose(scan, log, sb)
        self.assertEqual(e["segments"][:2], [
            {"kind": "hold", "src_at": 3202, "frames": 30, "why": "lead-in: the screen at rest before the first touch"},
            {"kind": "live", "src_in": 3202, "src_out": 3202 + 21 * STEP}])     # one tick before the touch-down
        pts = [f["pts"] for f in scan["frames"]]
        shown = [pts[j] for j in edit.film_sources(e, scan, 30)[30:51]]
        self.assertEqual(sorted(set(shown) - {0}), [3273, 3283, 3312, 3333, 3353, 3374, 3383, 3414])
        self.assertEqual([b for a, b in zip(shown, shown[1:]) if a == b and 3271 <= a < 3414], [])   # none twice
        # the touch-down is where it was in the take: one tick into the range
        self.assertEqual(e["touches"][0]["down"], 30 * STEP + 1)
        tm = edit.check(e, scan, log, sb)
        self.assertEqual(tm.gestures[0].down, 3203)
        self.assertIn("(21 frames, 1:1)  shows 8 of the take's 11 changed pictures, 0 twice while it moved",
                      edit.describe(e, scan, log, sb))

    def test_the_film_does_not_start_into_the_takes_first_picture(self):
        """The first range's start is the film's: 0.3 s after the take's
        first picture and no earlier, whatever a tick would gain."""
        def take(down: int):
            # the swipe's pictures, as far from the film's frames as they were in the take (68 ticks, + 3 frames)
            first = down + 68 + 3 * STEP
            scan = scan_of([(p - 3271 + first, CHANGE) for p in SWIPE[1:]], end=6000)
            _, log, sb = self.swipe()
            log["gestures"][0].update(near_s=first / T, down_s=down / T)
            return scan, log, sb

        scan, log, sb = take(180)
        e = edit.propose(scan, log, sb)
        self.assertEqual(e["segments"][1]["src_in"], 180)
        self.assertEqual(edit.sampling([f["pts"] for f in scan["frames"]], 180, 24, STEP, REST)[0], 2)   # at a price
        edit.check(e, scan, log, sb)
        scan, log, sb = take(181)                            # one tick later: there is one to take
        self.assertEqual(edit.propose(scan, log, sb)["segments"][1]["src_in"], 180)

    def test_a_range_does_not_run_into_the_one_after_it(self):
        """Starting earlier can cost a range one more film frame at its end.
        Here the swipe's pictures answer a tap that lands at 3211, the range
        ends at 3631, and the next touch lands at 3635: nine ticks earlier —
        the first start with no repeat — it would run to 3642, into the next
        range. Sixteen ticks earlier it ends on 3635."""
        scan = scan_of([(p, CHANGE) for p in SWIPE[1:]] + burst(3760, 3800), end=6000)
        _, log, sb = fixture()
        sb["timing"].update(tail_s=197 / T, caption_lead_s=0.0)
        sb["shots"][1]["caption"] = "one"
        log["gestures"][0].update(near_s=3271 / T, tolerance_s=0.01)
        log["gestures"][1].update(near_s=3760 / T, tolerance_s=0.01, down_s=3635 / T)
        self.assertEqual(edit.locate(scan, log, sb).gestures[0].down, 3211)
        self.assertEqual(edit.phase(SWIPE + list(range(3760, 3801, 10)), 3211, 3414 + 197, 180, math.inf, STEP, REST), 9)
        self.assertEqual(edit.frames_for(3202, 3414 + 197, STEP) * STEP + 3202, 3642)
        e = edit.propose(scan, log, sb)
        self.assertEqual([(s["src_in"], s["src_out"]) for s in e["segments"] if s["kind"] == "live"][0], (3195, 3635))
        self.assertEqual([s["src_in"] for s in e["segments"] if s["kind"] == "live"][1], 3635)
        edit.check(e, scan, log, sb)

    def test_a_range_is_not_moved_into_the_one_before_it(self):
        """Two answers close together: the second range cannot start earlier
        than the first one ends, whatever it would gain."""
        def take(down: int):
            scan = scan_of(burst(1800, 1900) + [(p + down - 3203, CHANGE) for p in SWIPE[1:]], end=6000)
            _, log, sb = fixture()
            sb["timing"].update(tail_s=0.5, caption_lead_s=0.0)
            sb["shots"][1]["caption"] = "one"
            log["gestures"][1].update(near_s=(3271 + down - 3203) / T, tolerance_s=0.01, down_s=down / T)
            return scan, log, sb

        self.assertEqual(edit.frames_for(1740, 1900 + 300, STEP) * STEP + 1740, 2220)   # where the first range ends
        scan, log, sb = take(2800)
        e = edit.propose(scan, log, sb)
        self.assertEqual([s["src_in"] for s in e["segments"] if s["kind"] == "live"], [1740, 2799])
        scan, log, sb = take(2220)                           # the second touch lands as the first range ends
        e = edit.propose(scan, log, sb)
        self.assertEqual([s["src_in"] for s in e["segments"] if s["kind"] == "live"], [1740, 2220])
        edit.check(e, scan, log, sb)
        scan, log, sb = take(2221)                           # one tick later: there is one tick to take
        e = edit.propose(scan, log, sb)
        self.assertEqual([s["src_in"] for s in e["segments"] if s["kind"] == "live"], [1740, 2220])


class Variants(unittest.TestCase):
    """A rehearsal on other gestures: the same film, never the film."""

    DOC = {**copy.deepcopy(SB), "variants": {"dry": {
        "_what": "a take that writes nothing",
        "film": {"duration_s": 16.0},
        "timing": {"lead_in_s": 0.5},
        "shots": [{"id": "A", "caption": "one", "gestures": [{"id": "tap-a", "kind": "tap", "rest_after_s": 1.0}]},
                  {"id": "C", "caption": "three", "caption_after": {"gesture": "tap-a", "delay_s": 0.5},
                   "gestures": []}],
    }}}

    def test_the_film_itself_carries_no_variant(self):
        sb = edit.storyboard(copy.deepcopy(self.DOC))
        self.assertNotIn("variants", sb)
        self.assertNotIn("variant", sb)
        self.assertEqual(sb, SB)

    def test_a_variant_gives_its_shots_and_lays_its_numbers_over_the_films(self):
        sb = edit.storyboard(copy.deepcopy(self.DOC), "dry")
        self.assertEqual(sb["variant"], "dry")
        self.assertEqual([s["id"] for s in sb["shots"]], ["A", "C"])
        self.assertEqual(sb["film"], {**SB["film"], "duration_s": 16.0})
        self.assertEqual(sb["timing"], {**SB["timing"], "lead_in_s": 0.5})
        self.assertEqual((sb["captions"], sb["motion"], sb["touch"]), (SB["captions"], SB["motion"], SB["touch"]))
        self.assertNotIn("variants", sb)
        self.assertEqual(self.DOC["film"]["duration_s"], 15.0)        # the film's own is untouched

    def test_a_variant_cannot_touch_the_words_or_the_motion(self):
        for key in ("captions", "motion", "touch"):
            doc = copy.deepcopy(self.DOC)
            doc["variants"]["dry"][key] = {}
            with self.assertRaises(Refusal) as cm:
                edit.storyboard(doc, "dry")
            self.assertEqual(cm.exception.code, "E_STORYBOARD")
            self.assertIn(f"may only give film, shots, timing — it gives {key}", cm.exception.message)

    def test_a_variant_the_file_does_not_have_is_refused(self):
        with self.assertRaises(Refusal) as cm:
            edit.storyboard(copy.deepcopy(self.DOC), "wet")
        self.assertEqual((cm.exception.code, cm.exception.message),
                         ("E_STORYBOARD", "the storyboard has no variant `wet` (it has: dry)"))
        with self.assertRaises(Refusal) as cm:
            edit.storyboard(copy.deepcopy(SB), "dry")
        self.assertIn("(it has: none)", cm.exception.message)

    def take(self):
        scan = scan_of(TAKE)
        log = {"device_points": [402, 874], "gestures": [dict(LOG["gestures"][0])]}
        return scan, log

    def test_an_edit_list_cannot_cross_between_the_film_and_a_variant(self):
        scan, log = self.take()
        dry = edit.storyboard(copy.deepcopy(self.DOC), "dry")
        e = edit.propose(scan, log, dry, rehearsal=True)
        self.assertEqual(e["variant"], "dry")
        edit.check(e, scan, log, dry)
        # the variant's edit list, offered to the film
        film = edit.storyboard(copy.deepcopy(self.DOC))
        film["shots"], film["film"], film["timing"] = dry["shots"], dry["film"], dry["timing"]
        with self.assertRaises(Refusal) as cm:
            edit.check(e, scan, log, film)
        self.assertEqual((cm.exception.code, cm.exception.message),
                         ("E_VARIANT", "the edit list was made for the variant `dry`, this storyboard is the film itself"))
        # the film's edit list, offered to the variant
        mine = edit.propose(scan, log, film)
        self.assertIsNone(mine["variant"])
        with self.assertRaises(Refusal) as cm:
            edit.check(mine, scan, log, dry)
        self.assertIn("was made for the film itself, this storyboard is the variant `dry`", cm.exception.message)

    def test_a_variants_edit_list_cannot_say_it_is_the_film(self):
        scan, log = self.take()
        dry = edit.storyboard(copy.deepcopy(self.DOC), "dry")
        e = edit.propose(scan, log, dry, rehearsal=True)
        e["rehearsal"] = False
        with self.assertRaises(Refusal) as cm:
            edit.check(e, scan, log, dry)
        self.assertEqual((cm.exception.code, cm.exception.message),
                         ("E_VARIANT", "the variant `dry` is a rehearsal: its edit list cannot say it is the film"))

    def test_the_log_says_which_variant(self):
        scan, log = self.take()
        dry = edit.storyboard(copy.deepcopy(self.DOC), "dry")
        e = edit.propose(scan, log, dry, rehearsal=True)
        self.assertIn("REHEARSAL — the storyboard's variant `dry`; this is not the film.",
                      edit.describe(e, scan, log, dry))

    def test_every_variant_of_the_real_storyboard_makes_a_film(self):
        """As for the film itself: one burst per gesture, typed text as three keys."""
        self.assertGreater(len(STORYBOARD.get("variants", {})), 0)
        for name in STORYBOARD["variants"]:
            sb = edit.storyboard(copy.deepcopy(STORYBOARD), name)
            for shot in sb["shots"]:
                self.assertIn(shot["caption"], sb["captions"], f"{name}: {shot['id']}")
            log = {"device_points": [402, 874], "gestures": []}
            rows, t = [], 3.0
            for shot in sb["shots"]:
                for g in shot["gestures"]:
                    entry = {"id": g["id"], "kind": g["kind"], "near_s": t}
                    if g["kind"] == "tap":
                        entry["at"] = [200, 400]
                    elif g["kind"] == "drag":
                        entry["path"] = [[100, 400, 0], [300, 400, 300]]
                    elif g["kind"] == "type":
                        del entry["near_s"]
                        entry["keys"] = [{"near_s": t + 3.0 * k} for k in range(3)]
                    for _ in entry.get("keys", [0]):
                        rows += burst(round(t * T), round(t * T) + 240)
                        t += 3.0
                    log["gestures"].append(entry)
            scan = scan_of(rows, end=round((t + 3) * T))
            e = edit.propose(scan, log, sb, rehearsal=True)
            edit.check(e, scan, log, sb)
            self.assertEqual(sum(s.frames for s in edit.spans(e, T, 30)), round(sb["film"]["duration_s"] * 30), name)
            self.assertTrue(e["rehearsal"])
            self.assertEqual(e["variant"], name)


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

    def after_the_tap(self, **caption_after):
        """tap-a alone: its own burst ends at 1900 ticks, the app goes on
        until 3650 (a snackbar leaving)."""
        scan = scan_of([(300, NOISE)] + burst(1800, 1900) + burst(3600, 3650))
        _, log, sb = fixture()
        log["gestures"].pop()
        sb["shots"] = [sb["shots"][0], {"id": "C", "caption": "three", "gestures": [],
                                        "caption_after": {"gesture": "tap-a", "delay_s": 0.5, **caption_after}}]
        return scan, log, sb

    def test_a_caption_that_follows_a_gesture_counts_from_its_first_rest_or_from_its_last_change(self):
        scan, log, sb = self.after_the_tap()
        tap = edit.locate(scan, log, sb).gestures[0]
        self.assertEqual((tap.burst_end, tap.last_change), (1900, 3650))
        # the range starts at film frame 30 on tick 1740: tick 1900 is frame 38, tick 3650 is in frame 126
        self.assertEqual(edit.propose(scan, log, sb)["captions"][1], {"frame": 38 + 15, "caption": "three"})
        scan, log, sb = self.after_the_tap(**{"from": "first_rest"})
        self.assertEqual(edit.propose(scan, log, sb)["captions"][1]["frame"], 38 + 15)
        scan, log, sb = self.after_the_tap(**{"from": "last_change"})
        e = edit.propose(scan, log, sb)
        self.assertEqual(e["captions"][1]["frame"], 126 + 15)
        edit.check(e, scan, log, sb)
        scan, log, sb = self.after_the_tap(**{"from": "the end"})
        with self.assertRaises(Refusal) as cm:
            edit.propose(scan, log, sb)
        self.assertEqual((cm.exception.code, cm.exception.message),
                         ("E_STORYBOARD", "shot C: caption_after.from is `the end`; it is one of first_rest, last_change"))

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
        # the second touch follows the first answer by 0.4 s: its caption can
        # only be in place 0.2 s before it — after the first touch point has
        # gone, before the second lands
        sb["timing"]["caption_lead_s"] = 0.2
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
        self.assertIsNone(edit.propose(scan, log, edit.storyboard(STORYBOARD))["variant"])
        e = edit.propose(scan, log, STORYBOARD)
        edit.check(e, scan, log, STORYBOARD)
        # read from the storyboard, not pinned: rewording or retiming the film
        # must not turn this red — only a storyboard that cannot make a film
        film, fps = STORYBOARD["film"], STORYBOARD["film"]["fps"]
        self.assertEqual(sum(s.frames for s in edit.spans(e, T, fps)), round(film["duration_s"] * fps))
        told = []
        for shot in STORYBOARD["shots"]:
            if not told or told[-1] != shot["caption"]:
                told.append(shot["caption"])
        self.assertEqual([c["caption"] for c in e["captions"]], told)
        drawn = [g["id"] for shot in STORYBOARD["shots"] for g in shot["gestures"] if g["kind"] != "type"]
        self.assertEqual([t["gesture"] for t in e["touches"]], drawn)
        self.assertEqual(e["poster_frame"], round(film["poster_s"] * fps))
        self.assertGreaterEqual(e["poster_frame"], e["final_hold_from"])
        self.assertTrue(15 <= film["duration_s"] <= 30)

    def film_take(self, sb: dict, creation_s: float, snackbar_s: float = 3.0):
        """A take of the film's own gestures, each answered for as long as
        the rehearsal take of 2026-10-13 measured it. Not measured, ASSUMED:
        the tap on « Arrivé » (0.4 s), and the last tap — the loader and the
        form closing (`creation_s`), then « Rendez-vous créé » staying its
        three seconds (SnackKind.success, app_snack_bar.dart) and leaving in
        0.3 s."""
        measured = {"swipe-arrive": 0.238, "tap-arrive": 0.4, "tap-libre": 0.352, "tap-coupe": 0.110,
                    "tap-sans-numero": 0.160, "tap-nom": 0.085, "scroll-total": 1.550}

        def answer(start_s: float, length_s: float) -> list[tuple[int, dict]]:
            return burst(round(start_s * T), round((start_s + length_s) * T))

        rows, log, t = [], {"device_points": [402, 874], "gestures": []}, 5.0
        for shot in sb["shots"]:
            for g in shot["gestures"]:
                entry = {"id": g["id"], "kind": g["kind"]}
                if g["kind"] == "type":
                    entry["keys"] = [{"near_s": t + 3.0 * k} for k in range(len("Yao K."))]
                    rows += [(round(k["near_s"] * T), CHANGE) for k in entry["keys"]]
                    t += 3.0 * len(entry["keys"])
                else:
                    entry["near_s"] = t
                    if g["kind"] == "tap":
                        entry["at"] = [200, 400]
                    else:
                        entry["path"] = [[110, 410, 0], [250, 410, 448]]
                    if g["id"] == "tap-creer":
                        rows += answer(t, creation_s) + answer(t + creation_s + snackbar_s, 0.3)
                        t += creation_s + snackbar_s
                    else:
                        rows += answer(t, measured[g["id"]])
                    t += 4.0
                log["gestures"].append(entry)
        return scan_of(rows, end=round((t + 5) * T)), log

    def test_the_film_has_room_for_the_creation_and_its_snackbar(self):
        """The last tap opens one window that cannot be cut: the loader, the
        form closing, the snackbar staying, the snackbar leaving — and the
        poster frame, frozen at approval, must find the screen at rest after
        it. The storyboard as it stands leaves that room; a retiming that
        takes it away turns this red."""
        sb = edit.storyboard(copy.deepcopy(STORYBOARD))
        fps = sb["film"]["fps"]
        for creation in (0.6, 1.0, 1.4):
            scan, log = self.film_take(sb, creation)
            e = edit.propose(scan, log, sb)
            edit.check(e, scan, log, sb)
            sp = edit.spans(e, T, fps)
            window = [s for s in sp if s.kind == "live"][-1]
            self.assertGreaterEqual(window.frames, round((creation + 3.0 + 0.3) * fps), creation)   # whole, in one piece
            self.assertLessEqual(sp[-1].film_in, e["poster_frame"], creation)       # the snackbar has left by then
            self.assertGreaterEqual(sp[-1].frames, round(sb["film"]["final_hold_min_s"] * fps), creation)
        # a creation that takes three seconds does not fit — refused, not squeezed
        scan, log = self.film_take(sb, 3.0)
        with self.assertRaises(Refusal) as cm:
            edit.check(edit.propose(scan, log, sb), scan, log, sb)
        self.assertIn(cm.exception.code, ("E_FINAL_HOLD", "E_POSTER", "E_LENGTH"))

    def test_the_name_is_typed_at_a_typing_pace(self):
        """Six keys, each on film from 0.1 s before its letter to 0.1 s after
        it: seven frames a key, with the storyboard's own numbers."""
        sb = edit.storyboard(copy.deepcopy(STORYBOARD))
        scan, log = self.film_take(sb, 0.6)
        e = edit.propose(scan, log, sb)
        keys = [g for g in edit.locate(scan, log, sb).gestures if g.kind == "type"]
        ranges = [s for s in e["segments"] if s["kind"] == "live" and any(s["src_in"] <= k.down < s["src_out"] for k in keys)]
        self.assertEqual([(s["src_out"] - s["src_in"]) // STEP for s in ranges], [7] * 6)


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
        e, scan, log, sb = proposed()
        e["segments"][2]["speed"] = 0.5                     # a hold has nothing else to say either
        self.assertIn("a hold is kind, src_at, frames (and why) — got", self.refused("E_SHAPE", e, scan, log, sb))

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
        elsewhere = {**CARET, "box": [600, 700, 606, 760]}       # caret-shaped, but not where this one blinks
        self.assertIn("they are not the same picture (soft 360, strong 360, box [600, 700, 606, 760])",
                      self.refused("E_ENDPOINT", e, scan, log, sb, {pairs[0]: elsewhere}))
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
        order = "the captions must be ['one', 'two', 'three'], the first from frame 0"
        self.assertEqual(self.refused("E_CAPTION", e, scan, log, sb), order)
        e, scan, log, sb = proposed()
        del e["captions"][2]
        self.assertEqual(self.refused("E_CAPTION", e, scan, log, sb), order)
        e, scan, log, sb = proposed()
        e["captions"][0]["frame"] = 1
        self.assertEqual(self.refused("E_CAPTION", e, scan, log, sb), order)
        e, scan, log, sb = proposed()
        e["captions"][2]["frame"] = 447
        self.assertIn("runs past the end", self.refused("E_CAPTION", e, scan, log, sb))

    def test_a_caption_moved_by_hand_is_refused(self):
        """Well spaced, in order, on a still screen — and not where the
        storyboard puts it: the storyboard is the one source for timings."""
        e, scan, log, sb = proposed()
        self.assertEqual(e["captions"][1], {"frame": 142, "caption": "two"})
        e["captions"][1]["frame"] = 150
        self.assertEqual(self.refused("E_CAPTION", e, scan, log, sb),
                         "caption `two` changes at frame 150; the storyboard and the take put it at frame 142")
        e, scan, log, sb = proposed()
        e["captions"][2]["frame"] -= 1
        self.assertIn("caption `three` changes at frame 211;", self.refused("E_CAPTION", e, scan, log, sb))

    def test_a_rehearsals_shot_with_no_footage_places_its_own_caption(self):
        """What `check` cannot work out again, and says so: a shot that is a
        hold has no gesture to count from. Its caption is held to the order
        and the spacing, nothing more — a rehearsal is never the film."""
        scan = scan_of(burst(1800, 1900))
        _, log, sb = fixture()
        log["gestures"].pop()
        e = edit.propose(scan, log, sb, rehearsal=True)
        self.assertEqual([c["frame"] for c in e["captions"]], [0, 87, 159])
        tm = edit.check(e, scan, log, sb)
        placed = edit.place_captions(tm, edit.spans(e, T, 30), sb, True)
        self.assertEqual([c["frame"] for c in placed], [0, None, None])
        e["captions"][1]["frame"] = 100
        edit.check(e, scan, log, sb)
        e["captions"][1]["frame"] = 2
        self.assertIn("starts before `one` has finished changing", self.refused("E_CAPTION", e, scan, log, sb))

    def test_a_caption_that_changes_while_the_card_moves_is_refused(self):
        """A caption changes at rest. With 0.2 s of rest after the tap, the
        next caption — 0.8 s before the next touch — starts cross-fading as
        the app's own bar comes in."""
        scan, log, sb = fixture()
        sb["shots"][0]["gestures"][0]["rest_after_s"] = 0.2
        e = edit.propose(scan, log, sb)
        self.assertEqual(e["captions"][1], {"frame": 118, "caption": "two"})   # frames 118–123; the bar moves on 123–126
        self.assertEqual(self.refused("E_CAPTION", e, scan, log, sb),
                         "caption `two` changes at 3.933 s while the picture in the card is still changing "
                         "(4.100 s) — a caption changes at rest: lengthen the rest before it")
        sb["shots"][0]["gestures"][0]["rest_after_s"] = 0.5                    # frames 127–132: the bar is in
        e = edit.propose(scan, log, sb)
        self.assertEqual(e["captions"][1]["frame"], 127)
        edit.check(e, scan, log, sb)

    def test_a_caption_that_changes_under_a_touch_point_is_refused(self):
        scan = scan_of(burst(1800, 1900))
        _, log, sb = fixture()
        log["gestures"].pop()
        after = {"gesture": "tap-a", "delay_s": 0.1}
        sb["shots"] = [{"id": "A", "caption": "one", "gestures": [{"id": "tap-a", "kind": "tap", "rest_after_s": 0}]},
                       {"id": "C", "caption": "three", "caption_after": after, "gestures": []}]
        e = edit.propose(scan, log, sb)
        # the answer ends on frame 38; the point lifts at 39 and is gone 0.2 s later, at 45
        self.assertEqual((e["captions"][1]["frame"], e["touches"][0]["up"] // STEP), (41, 39))
        self.assertEqual(self.refused("E_CAPTION", e, scan, log, sb),
                         "caption `three` changes at 1.367 s while the touch point of `tap-a` is on screen — a "
                         "caption changes at rest: lengthen the rest before it")
        after["delay_s"] = 0.2                              # frame 44: its last frame
        self.assertIn("while the touch point", self.refused("E_CAPTION", edit.propose(scan, log, sb), scan, log, sb))
        after["delay_s"] = 0.3                              # frame 47
        edit.check(edit.propose(scan, log, sb), scan, log, sb)

    def test_a_caption_too_long_for_its_time_on_screen_is_refused(self):
        """`three` is whole from frame 218 to the end, 7.73 s: 131 characters
        at 17 a second, not one more."""
        scan, log, sb = fixture()
        sb["captions"]["three"] = {"headline": ["x" * 65, "y" * 65], "subline": []}
        e = edit.propose(scan, log, sb)
        self.assertEqual(e["captions"][2]["frame"] + 6, 218)
        edit.check(e, scan, log, sb)
        sb["captions"]["three"]["headline"][1] += "y"
        self.assertEqual(self.refused("E_CAPTION", e, scan, log, sb),
                         "caption `three` brings 132 characters and they are whole on screen for 7.73 s: at 17 "
                         "characters a second they need 7.76 s")

    def test_what_a_caption_brings_and_for_how_long(self):
        sb = {"captions": {
            "a": {"headline": ["Un titre", "sur deux lignes."], "subline": []},
            "b": {"headline": ["Un titre", "sur deux lignes."], "subline": ["Une ligne dessous."]},
            "c": {"headline": ["Autre", "titre."], "subline": ["Une ligne dessous."]},
            "d": {"headline": ["Tout", "change."], "subline": ["Et la ligne aussi."]},
            "e": {"headline": ["Tout", "change."], "subline": []}}}
        caps = [{"frame": f, "caption": c} for f, c in ((0, "a"), (90, "b"), (300, "c"), (400, "d"), (500, "e"))]
        self.assertEqual(edit.caption_reading(caps, sb, 6, 600), [
            # the first caption is whole from frame 0; its headline stays until `c` replaces it
            {"caption": "a", "characters": len("Un titre sur deux lignes."), "frames": 300},
            # `b` brings a sub-line under the same headline: only the sub-line is to be read, and it outlives `c`
            {"caption": "b", "characters": len("Une ligne dessous."), "frames": 400 - 96},
            {"caption": "c", "characters": len("Autre titre."), "frames": 400 - 306},
            # both parts new: read together, until the first of them goes
            {"caption": "d", "characters": len("Tout change. Et la ligne aussi."), "frames": 500 - 406},
            # `e` only takes a line away: nothing to read
        ])

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
        sb["shots"] = [                                    # one caption all along: only the point is in the way
            {"id": "A", "caption": "one", "gestures": [{"id": "tap-a", "kind": "tap", "rest_after_s": 0}]},
            {"id": "C", "caption": "one", "gestures": []},
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
            # how near the take comes to the thresholds — the first picture, a
            # change by nature and not by measure, is not the "faintest"
            "       loudest quiet frame:     0.500 s  soft 500, strong 1",
            "       faintest change frame:   3.000 s  soft 50000, strong 40000",
            "    0.000 s –   0.000 s     1 frames  (no gesture: the app on its own, or outside the film)",
            "    3.000 s –   3.167 s    11 frames  <- tap-a",
            "    6.000 s –   6.083 s     6 frames  (no gesture: the app on its own, or outside the film)",
            "  film  1.000 –  4.533 s  LIVE  take   2.900 s –   6.433 s  (106 frames, 1:1)  shows 10 of the take's "
            "17 changed pictures, 0 twice while it moved",
            # the fixture's three captions say the same two words: read once, on screen to the end
            "  film  0.000 s  one  — 3 characters, whole for 15.00 s (0.2 a second; at most 17)\n",
            "  film  4.733 s  two\n",
            "  film  4.533 –  5.533 s  HOLD  the picture at take   6.400 s  (30 frames)  rest after tap-a",
            "  1. take   0.000 s –   2.900 s removed: before the film starts (1 change frame in it",
            "  2. take   6.400 s –   9.977 s removed, lands on film  5.533 s: 0 quiet frames, 3 caret-only "
            "frames in the box [300, 700, 306, 760]; frame 18 against frame 21: soft 360, strong 360 (caret)",
            "  3. take  11.310 s –  15.000 s removed: after the film ends (0 change frames in it)",
            "poster frame: film 13 s (frame 390); final hold from 7.400 s; 450 frames, 15.000 s",
        ):
            self.assertIn(line, text)


if __name__ == "__main__":
    unittest.main()
