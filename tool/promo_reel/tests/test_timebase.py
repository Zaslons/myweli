"""The clock: bar.beat.step ⇄ frame ⇄ sample, exactly, on the contract's grid."""

from __future__ import annotations

import sys
import unittest
from fractions import Fraction
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo import timebase as tb  # noqa: E402
from promo.timebase import Pos, TimeBase, TimeBaseError  # noqa: E402


class Constants(unittest.TestCase):
    def test_the_contracts_grid(self):
        self.assertEqual((tb.FPS, tb.BPM, tb.SAMPLE_RATE), (30, Fraction(225, 2), 48_000))
        self.assertEqual((tb.FRAMES_PER_STEP, tb.FRAMES_PER_BEAT, tb.FRAMES_PER_BAR), (4, 16, 64))
        self.assertEqual(tb.SAMPLES_PER_FRAME, 1600)
        self.assertEqual(tb.frame_to_seconds(tb.FRAMES_PER_BAR), Fraction(32, 15))  # 2.1333 s

    def test_cut_lengths(self):
        self.assertEqual(tb.pos_to_frame("15.1.0"), 896)   # the 30-s cut ends where bar 15 would start
        self.assertEqual(tb.pos_to_frame("8.1.0"), 448)    # the 15-s cut: 7 bars
        self.assertAlmostEqual(float(tb.frame_to_seconds(896)), 29.867, places=3)


class Positions(unittest.TestCase):
    def test_formula_on_every_16th_of_the_30s_cut(self):
        previous = None
        for frame in range(0, 896, 4):
            pos = tb.frame_to_pos(frame)
            self.assertEqual((pos.bar - 1) * 64 + (pos.beat - 1) * 16 + pos.step * 4, frame)
            self.assertEqual(tb.pos_to_frame(pos), frame)
            self.assertEqual(tb.parse_pos(str(pos)), pos)
            if previous is not None:
                self.assertEqual(frame - tb.pos_to_frame(previous), 4)
            previous = pos

    def test_the_storyboards_own_positions(self):
        # « GRID AND NOTATION » and the beat-by-beat rows
        cases = {"1.1.0": 0, "1.3.0": 32, "3.1.0": 128, "3.2.0": 144, "3.3.0": 160, "3.4.0": 176,
                 "4.3&": 232, "5.2&": 280, "7.4e": 436, "8.1": 448, "8.1a": 460, "9.1.0": 512,
                 "13.1.0": 768, "14.1.0": 832}
        for text, frame in cases.items():
            with self.subTest(text):
                self.assertEqual(tb.pos_to_frame(text), frame)

    def test_shorthand_is_written_back_canonical(self):
        self.assertEqual(tb.format_pos(tb.parse_pos("5.2&")), "5.2.2")
        self.assertEqual(tb.format_pos(tb.parse_pos("7.4e")), "7.4.1")
        self.assertEqual(tb.format_pos(tb.parse_pos(" 8.1a ")), "8.1.3")
        self.assertEqual(str(Pos(3, 2)), "3.2.0")

    def test_bad_positions_are_refused_with_the_reason(self):
        for text, reason in (("3.5.0", "beat must be 1–4"), ("0.1.0", "bars count from 1"),
                             ("3.1.4", "step must be 0–3"), ("3.1.x", "not a position"),
                             ("bar 3", "not a position"), ("3.0.0", "beat must be 1–4")):
            with self.subTest(text), self.assertRaisesRegex(TimeBaseError, reason):
                tb.parse_pos(text)
        with self.assertRaisesRegex(TimeBaseError, "a position is a string"):
            tb.parse_pos(3)

    def test_off_grid_frames_have_no_position(self):
        with self.assertRaisesRegex(TimeBaseError, r"frame 149 is not on the 16th grid .*3\.2\.1 \+ 1 frame"):
            tb.frame_to_pos(149)
        self.assertEqual(tb.split_frame(149), (Pos(3, 2, 1), 1))
        self.assertEqual(tb.split_frame(144), (Pos(3, 2, 0), 0))

    def test_to_frame_takes_the_storyboards_forms(self):
        for value in (144, "f144", "3.2.0", "3.2", Pos(3, 2, 0), (3, 2, 0)):
            with self.subTest(value=value):
                self.assertEqual(tb.to_frame(value), 144)
        for bad in (-1, True, 1.5, "f-1", None):
            with self.subTest(bad=bad), self.assertRaises(TimeBaseError):
                tb.to_frame(bad)


class Samples(unittest.TestCase):
    def test_frame_and_sample(self):
        self.assertEqual(tb.frame_to_sample(144), 230_400)
        self.assertEqual(tb.pos_to_sample("3.1.0"), 128 * 1600)
        self.assertEqual(tb.sample_to_frame(230_400), 144)
        self.assertEqual(tb.sample_to_pos(230_400), Pos(3, 2, 0))
        self.assertEqual(tb.frame_at_sample(230_401), 144)
        self.assertEqual(tb.frame_at_sample(231_999), 144)
        with self.assertRaisesRegex(TimeBaseError, "1 samples into frame 144"):
            tb.sample_to_frame(230_401)
        with self.assertRaises(TimeBaseError):
            tb.frame_to_sample(-1)

    def test_seconds(self):
        self.assertEqual(tb.frame_to_seconds(144), Fraction(24, 5))
        self.assertEqual(tb.seconds_to_frame(4.8), 144)          # exact, no float drift
        self.assertEqual(tb.seconds_to_frame(4.7999), 143)
        self.assertEqual(tb.seconds_to_frame(Fraction(448, 30)), 448)
        with self.assertRaises(TimeBaseError):
            tb.seconds_to_frame(-0.01)


class OtherTimeBases(unittest.TestCase):
    def test_a_grid_that_is_not_whole_frames_is_refused(self):
        with self.assertRaisesRegex(TimeBaseError, "step"):
            TimeBase(bpm=120)                 # 15 frames a beat: a 16th is 3.75 frames
        with self.assertRaisesRegex(TimeBaseError, "beat"):
            TimeBase(fps=24)                  # 12.8 frames a beat
        with self.assertRaisesRegex(TimeBaseError, "samples"):
            TimeBase(fps=30, bpm=112.5, sample_rate=44_101)
        with self.assertRaises(TimeBaseError):
            TimeBase(bpm=0)
        with self.assertRaises(TimeBaseError):
            TimeBase(fps=True)

    def test_a_valid_other_grid(self):
        t = TimeBase(fps=30, bpm=90, sample_rate=44_100)
        self.assertEqual((t.frames_per_beat, t.frames_per_step, t.frames_per_bar, t.samples_per_frame),
                         (20, 5, 80, 1470))
        self.assertEqual(t.frame("2.1.0"), 80)
        self.assertEqual(TimeBase(bpm="112.5"), tb.DEFAULT)

    def test_grid_listing(self):
        beats = tb.DEFAULT.grid(896, "beat")
        self.assertEqual(len(beats), 56)
        self.assertEqual(tb.DEFAULT.grid(896, "bar")[-1], Pos(14, 1, 0))
        self.assertEqual(len(tb.DEFAULT.grid(448, "step")), 112)
        with self.assertRaises(TimeBaseError):
            tb.DEFAULT.grid(64, "8th")


if __name__ == "__main__":
    unittest.main()
