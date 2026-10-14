"""Tokens: colours and motion are read from the design system's files, and
the curves are Flutter's."""

from __future__ import annotations

import re
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

import brand
from tests.support import STORYBOARD, dies


class Colours(unittest.TestCase):
    def test_the_seven_tokens_come_from_colors_dart(self):
        src = """
        class AppColors {
          static const Color primary = Color(0xFF010203); // brand
          static const Color secondary = Color(
            0xFFF1F2F3,
          );
          static const Color surface = Color(0xFF111213);
          static const Color textPrimary = Color(0xFF212223);
          static const Color textSecondary = Color(0xFF313233);
          static const Color border = Color(0xFF414243);
          static const Color divider = Color(0xFF515253);
        }
        """
        with tempfile.TemporaryDirectory() as tmp:
            dart = Path(tmp) / "colors.dart"
            dart.write_text(src, encoding="utf-8")
            with mock.patch.object(brand.stills, "COLORS_DART", dart):
                c = brand.colours()
        self.assertEqual(c, {
            "primary": (1, 2, 3), "secondary": (0xF1, 0xF2, 0xF3), "surface": (0x11, 0x12, 0x13),
            "textPrimary": (0x21, 0x22, 0x23), "textSecondary": (0x31, 0x32, 0x33),
            "border": (0x41, 0x42, 0x43), "divider": (0x51, 0x52, 0x53),
        })

    def test_the_real_file_has_them_all(self):
        self.assertEqual(set(brand.colours()), {
            "surface", "textPrimary", "textSecondary", "border", "divider", "primary", "secondary"})

    def test_the_stills_still_read_their_five(self):
        self.assertEqual(set(brand.stills.tokens()), {"surface", "textPrimary", "textSecondary", "border", "divider"})


class MotionTokens(unittest.TestCase):
    def test_durations_and_curves_come_from_motion_dart(self):
        src = """
        class AppMotion {
          static const Duration stagger = Duration(milliseconds: 50);
          static const Duration fast = Duration(milliseconds: 120);
          static const Curve fastCurve = Curves.easeOutCubic;
          static const Duration base = Duration(milliseconds: 240);
          static const Curve baseCurve = Curves.easeIn;
        }
        """
        with tempfile.TemporaryDirectory() as tmp:
            dart = Path(tmp) / "motion.dart"
            dart.write_text(src, encoding="utf-8")
            with mock.patch.object(brand, "MOTION_DART", dart):
                t = brand.motion_tokens()
        self.assertEqual({k: (v.ms, v.curve) for k, v in t.items()},
                         {"fast": (120, "easeOutCubic"), "base": (240, "easeIn")})

    def test_a_curve_the_table_does_not_know_stops_the_tool(self):
        src = ("static const Duration fast = Duration(milliseconds: 100);\n"
               "static const Curve fastCurve = Curves.bounceOut;\n")
        with tempfile.TemporaryDirectory() as tmp:
            dart = Path(tmp) / "motion.dart"
            dart.write_text(src, encoding="utf-8")
            with mock.patch.object(brand, "MOTION_DART", dart), dies(self, "Curves.bounceOut"):
                brand.motion_tokens()

    def test_a_motion_file_without_tokens_or_with_half_a_token_stops_the_tool(self):
        with tempfile.TemporaryDirectory() as tmp:
            dart = Path(tmp) / "motion.dart"
            dart.write_text("class AppMotion {}\n", encoding="utf-8")
            with mock.patch.object(brand, "MOTION_DART", dart), dies(self, "no motion tokens found"):
                brand.motion_tokens()
            dart.write_text("static const Curve fastCurve = Curves.easeOut;\n", encoding="utf-8")
            with mock.patch.object(brand, "MOTION_DART", dart), dies(self, "`fast` has a curve but no duration"):
                brand.motion_tokens()

    def test_the_storyboard_names_tokens_only_and_they_are_whole_frames(self):
        tokens = brand.motion_tokens()
        fps = STORYBOARD["film"]["fps"]
        used = list(STORYBOARD["motion"].values()) + [STORYBOARD["touch"]["tap_dwell"]]
        for name in used:
            self.assertIn(name, tokens)
            self.assertEqual(tokens[name].frames(fps) * 1000, tokens[name].ms * fps)
        with dies(self, "is not a motion token"):
            brand.motion("0.2s")

    def test_a_token_that_is_not_a_whole_number_of_frames_stops_the_tool(self):
        with dies(self, "not a whole number of frames"):
            brand.Motion("odd", 110, "easeOut").frames(30)


class Curves(unittest.TestCase):
    def reference(self, points, t: float) -> float:
        """The same Bézier, solved another way: sample the curve densely and
        interpolate y at x = t."""
        a, b, c, d = points
        u = np.linspace(0, 1, 200_001)
        x = 3 * a * (1 - u) ** 2 * u + 3 * c * (1 - u) * u ** 2 + u ** 3
        y = 3 * b * (1 - u) ** 2 * u + 3 * d * (1 - u) * u ** 2 + u ** 3
        return float(np.interp(t, x, y))

    def test_every_curve_matches_the_bezier_it_names(self):
        for name, points in brand.CUBICS.items():
            for t in np.linspace(0, 1, 41):
                # Flutter's bisection stops within 0.001 of x; the slope of
                # these curves keeps y within 0.004 of the true value.
                self.assertAlmostEqual(brand.cubic(points, float(t)), self.reference(points, float(t)),
                                       delta=0.004, msg=f"{name} at {t}")

    def test_known_values(self):
        self.assertEqual(brand.cubic(brand.CUBICS["easeInOut"], 0.5), 0.5)  # symmetric: exact
        for points in brand.CUBICS.values():
            self.assertEqual(brand.cubic(points, 0.0), 0.0)
            self.assertEqual(brand.cubic(points, 1.0), 1.0)
            self.assertEqual(brand.cubic(points, 1.7), 1.0)
            self.assertEqual(brand.cubic(points, -0.2), 0.0)
        # entering decelerates: easeOut is ahead of linear at the midpoint
        self.assertGreater(brand.cubic(brand.CUBICS["easeOut"], 0.5), 0.6)
        self.assertLess(brand.cubic(brand.CUBICS["easeIn"], 0.5), 0.4)

    def test_progress_is_evaluated_by_time(self):
        fast = brand.Motion("fast", 100, "easeOut")
        self.assertEqual(fast.at(0.05), brand.cubic(brand.CUBICS["easeOut"], 0.5))
        self.assertEqual(fast.at(0.0), 0.0)
        self.assertEqual(fast.at(0.1), 1.0)
        self.assertEqual(fast.at(3.0), 1.0)

    def test_the_table_is_flutters_own(self):
        flutter = shutil.which("flutter")
        if not flutter:
            self.skipTest("no Flutter SDK on this machine")
        curves = Path(flutter).resolve().parents[1] / "packages/flutter/lib/src/animation/curves.dart"
        if not curves.exists():
            self.skipTest(f"no {curves}")
        src = curves.read_text(encoding="utf-8")
        for name, points in brand.CUBICS.items():
            m = re.search(rf"static const Cubic {name} = Cubic\(([^)]*)\);", src)
            self.assertIsNotNone(m, name)
            self.assertEqual(tuple(float(v) for v in m.group(1).split(",")), points, name)


if __name__ == "__main__":
    unittest.main()
