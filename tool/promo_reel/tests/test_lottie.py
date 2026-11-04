"""Tests for promo.lottie — the Skia player of the Pro app's opening Lottie.

Run from tool/promo_reel:  python -m unittest tests.test_lottie   (≈1 s)
"""

from __future__ import annotations

import copy
import json
import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import numpy as np  # noqa: E402
import skia  # noqa: E402

from promo.lottie import PRO_OPEN_ANIMATION, LottieError, Player, UnsupportedFeature  # noqa: E402
from promo.lottie import check, model  # noqa: E402
from promo.lottie.bezier import CubicBezier  # noqa: E402
from promo.lottie.player import trim_path  # noqa: E402

FAST_OUT_SLOW_IN = CubicBezier(0.4, 0.0, 0.2, 1.0)  # the file's only easing


def _pro_json() -> dict:
    with open(PRO_OPEN_ANIMATION, encoding='utf-8') as handle:
        return json.load(handle)


def _layer(data: dict, name: str) -> dict:
    return next(layer for layer in data['layers'] if layer['nm'] == name)


class FileContractTest(unittest.TestCase):
    """The file parses, and its timing is what pro_splash_screen.dart relies on."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.player = Player(PRO_OPEN_ANIMATION)

    def test_timing_size_and_markers(self) -> None:
        self.assertEqual(self.player.frames, (0.0, 142.0))
        self.assertEqual(self.player.fps, 25.0)
        self.assertEqual(self.player.size, (560, 380))
        self.assertEqual(
            self.player.markers,
            {'intro': (0.0, 74.0), 'wordmark': (12.0, 38.0), 'loop': (74.0, 142.0)},
        )

    def test_layers(self) -> None:
        names = [layer.name for layer in self.player.composition.layers]
        self.assertEqual(names, ['redraw', 'M', 'W', 'L_y', 'L_e', 'L_l', 'L_i', 'L_P', 'L_r', 'L_o'])
        redraw = self.player.composition.layers[0]
        self.assertEqual((redraw.in_frame, redraw.out_frame), (72.0, 142.0))
        stroke = redraw.groups[0].paints[0]
        self.assertEqual((stroke.cap, stroke.join), ('butt', 'round'))
        m_stroke = self.player.composition.layers[1].groups[0].paints[0]
        self.assertEqual((m_stroke.cap, m_stroke.join), ('round', 'round'))
        self.assertEqual(m_stroke.rgb, (17, 17, 17))  # 0.0667 × 255, a byte

    def test_device_frames(self) -> None:
        # FrameRate.composition floors to 25 fps over 142.01 frames.
        self.assertAlmostEqual(self.player.device_frame(1.0), 142 * 142 / 142.01, places=9)
        self.assertAlmostEqual(self.player.device_frame(25 / 142), 25 * 142 / 142.01, places=9)
        self.assertEqual(self.player.device_frame(0.0), 0.0)
        self.assertAlmostEqual(self.player.last_frame, 141.990000704, places=6)
        redraw = self.player.composition.layers[0]
        self.assertTrue(redraw.visible_at(self.player.last_frame))
        self.assertFalse(redraw.visible_at(142.0))  # Lottie's out point is exclusive


class UnsupportedFeatureTest(unittest.TestCase):
    """Every feature the file does not use is refused by name, never drawn wrong."""

    def assertRefused(self, mutate, needle: str) -> None:
        data = _pro_json()
        mutate(data)
        with self.assertRaises(UnsupportedFeature) as caught:
            model.parse(data)
        self.assertIn(needle, str(caught.exception))

    def test_parenting(self) -> None:
        self.assertRefused(lambda d: d['layers'][1].update(parent=1), 'parent')

    def test_masks(self) -> None:
        self.assertRefused(lambda d: d['layers'][1].update(hasMask=True, masksProperties=[]), 'hasMask')

    def test_track_matte(self) -> None:
        self.assertRefused(lambda d: d['layers'][1].update(tt=1), "'tt'")

    def test_time_remap(self) -> None:
        self.assertRefused(lambda d: d['layers'][1].update(tm={'a': 0, 'k': 0}), "'tm'")

    def test_time_stretch_and_start(self) -> None:
        self.assertRefused(lambda d: d['layers'][1].update(sr=2), '.sr')
        self.assertRefused(lambda d: d['layers'][1].update(st=5), '.st')

    def test_precomp_and_assets(self) -> None:
        self.assertRefused(lambda d: d['assets'].append({'id': 'comp_0', 'layers': []}), 'assets')
        self.assertRefused(lambda d: d['layers'][1].update(ty=0), '.ty')

    def test_expression(self) -> None:
        self.assertRefused(lambda d: d['layers'][1]['ks']['o'].update(x='time'), 'expressions')

    def test_hold_keyframe(self) -> None:
        self.assertRefused(lambda d: d['layers'][1]['ks']['o']['k'][0].update(h=1), "'h'")

    def test_spatial_tangents(self) -> None:
        self.assertRefused(lambda d: d['layers'][1]['ks']['o']['k'][0].update(to=[0, 0]), "'to'")

    def test_per_dimension_easing(self) -> None:
        def mutate(d: dict) -> None:
            d['layers'][1]['ks']['o']['k'][0]['o'] = {'x': [0.4, 0.4], 'y': [0, 0]}

        self.assertRefused(mutate, 'per-dimension')

    def test_trim_individually(self) -> None:
        self.assertRefused(lambda d: d['layers'][0]['shapes'][0]['it'][1].update(m=2), '.m')

    def test_dashes(self) -> None:
        self.assertRefused(lambda d: d['layers'][0]['shapes'][0]['it'][2].update(d=[]), "'d'")

    def test_nested_group_and_other_shapes(self) -> None:
        def nest(d: dict) -> None:
            group = d['layers'][1]['shapes'][0]
            group['it'].insert(0, copy.deepcopy(group))

        self.assertRefused(nest, 'nested groups')

        def ellipse(d: dict) -> None:
            d['layers'][1]['shapes'][0]['it'].insert(0, {'ty': 'el', 'p': {'a': 0, 'k': [0, 0]}})

        self.assertRefused(ellipse, "'el'")

    def test_split_position_and_skew(self) -> None:
        self.assertRefused(lambda d: d['layers'][1]['ks'].update(p={'s': True}), 'split')
        self.assertRefused(lambda d: d['layers'][1]['ks'].update(sk={'a': 0, 'k': 0}), "'sk'")

    def test_animated_colour(self) -> None:
        def mutate(d: dict) -> None:
            stroke = d['layers'][1]['shapes'][0]['it'][1]
            stroke['c'] = {'a': 1, 'k': [{'t': 0, 's': [0, 0, 0], 'o': {'x': [0], 'y': [0]}, 'i': {'x': [1], 'y': [1]}}, {'t': 9, 's': [1, 1, 1]}]}

        self.assertRefused(mutate, 'animated value')

    def test_morph_needs_equal_vertex_counts(self) -> None:
        def mutate(d: dict) -> None:
            shape = d['layers'][1]['shapes'][0]['it'][0]['ks']['k'][2]['s'][0]
            for key in ('v', 'i', 'o'):
                shape[key] = shape[key][:4]

        self.assertRefused(mutate, 'vertex counts')

    def test_effects_and_text_layers(self) -> None:
        self.assertRefused(lambda d: d['layers'][1].update(ef=[]), "'ef'")
        self.assertRefused(lambda d: d['layers'][1].update(ty=5), '.ty')

    def test_not_lottie_at_all(self) -> None:
        with self.assertRaises(LottieError):
            model.parse({'layers': []})


class EasingAndKeyframesTest(unittest.TestCase):
    def test_bezier_matches_a_dense_sampling(self) -> None:
        u = np.linspace(0.0, 1.0, 200001)

        def axis(p1: float, p2: float) -> np.ndarray:
            c = 3 * p1
            b = 3 * (p2 - p1) - c
            return (((1 - c - b) * u + b) * u + c) * u

        x, y = axis(0.4, 0.2), axis(0.0, 1.0)
        for t in (0.01, 0.1, 0.25, 0.5, 0.75, 0.9, 0.99):
            self.assertAlmostEqual(FAST_OUT_SLOW_IN(t), float(np.interp(t, x, y)), places=6)
        self.assertEqual(FAST_OUT_SLOW_IN(0.0), 0.0)
        self.assertEqual(FAST_OUT_SLOW_IN(1.0), 1.0)
        self.assertAlmostEqual(CubicBezier(0.25, 0.25, 0.75, 0.75)(0.3), 0.3, places=9)

    def test_bezier_is_monotonic(self) -> None:
        values = [FAST_OUT_SLOW_IN(t / 500) for t in range(501)]
        self.assertEqual(values, sorted(values))

    def test_handles_outside_unit_x_are_refused(self) -> None:
        with self.assertRaises(ValueError):
            CubicBezier(1.2, 0, 0.2, 1)

    def test_keyframe_evaluation(self) -> None:
        player = Player(PRO_OPEN_ANIMATION)
        trim = player.composition.layers[0].groups[0].trim
        # before the first keyframe: the first value; after the last: the last
        self.assertEqual(trim.start.scalar(0.0), 0.0)
        self.assertEqual(trim.end.scalar(200.0), 100.0)
        # inside 74 → 104, s eases 0 → 100 along the file's curve
        self.assertAlmostEqual(trim.start.scalar(89.0), 100 * FAST_OUT_SLOW_IN(0.5), places=9)
        # the 0.01-frame segment 104 → 104.01 is continuous, not a jump
        self.assertAlmostEqual(trim.end.scalar(104.005), 100 * (1 - FAST_OUT_SLOW_IN(0.5)), places=6)
        self.assertEqual(trim.end.scalar(104.01), 0.0)
        # exactly on a keyframe, the segment that starts there applies
        opacity = player.composition.layers[1].transform.opacity
        self.assertEqual(opacity.scalar(12.0), 100.0)
        self.assertEqual(opacity.scalar(73.0), 0.0)


class TrimTest(unittest.TestCase):
    def setUp(self) -> None:
        self.square = skia.Path()
        self.square.addRect(skia.Rect.MakeWH(100, 100))  # perimeter 400, closed

    def _length(self, path: skia.Path) -> float:
        return skia.PathMeasure(path, False).getLength()

    def test_full_range_keeps_the_closed_path(self) -> None:
        self.assertIs(trim_path(self.square, 0.0, 1.0, 0.0), self.square)
        self.assertIs(trim_path(self.square, 0.0, 0.995, 0.0), self.square)  # within 1 %

    def test_equal_ends_draw_nothing(self) -> None:
        self.assertTrue(trim_path(self.square, 0.4, 0.4, 0.0).isEmpty())
        self.assertTrue(trim_path(self.square, 1.0, 1.0, 0.0).isEmpty())

    def test_partial_is_an_open_piece_of_the_right_length(self) -> None:
        piece = trim_path(self.square, 0.25, 0.5, 0.0)
        self.assertAlmostEqual(self._length(piece), 100.0, places=3)
        self.assertFalse(piece.isLastContourClosed())
        swapped = trim_path(self.square, 0.5, 0.25, 0.0)  # start > end is swapped
        self.assertAlmostEqual(self._length(swapped), 100.0, places=3)

    def test_offset_wraps_around(self) -> None:
        piece = trim_path(self.square, 0.0, 0.5, 0.75)  # 300 → 500 = 300 → 400, then 0 → 100
        measure = skia.PathMeasure(piece, False)
        lengths = [measure.getLength()]
        while measure.nextContour():
            lengths.append(measure.getLength())
        self.assertEqual(len(lengths), 2)
        self.assertAlmostEqual(sum(lengths), 200.0, places=3)


class RenderTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.player = Player(PRO_OPEN_ANIMATION)

    def _render(self, comp_frame: float, **kwargs) -> np.ndarray:
        return check.render_surface(self.player, comp_frame, **kwargs)

    def test_acceptance_against_the_flutter_goldens(self) -> None:
        results = check.acceptance(self.player)
        self.assertEqual(set(results), {'pro_splash_wordmark', 'pro_splash_end'})
        for name, (case, drawn, comparison) in results.items():
            with self.subTest(name):
                # Measured 2026-10-19: wordmark max 2 / IoU 0.9993, end max 1 / IoU 1.0.
                self.assertLessEqual(comparison.max_abs_error, 4)
                self.assertGreaterEqual(comparison.iou, 0.999)
                self.assertLess(comparison.mean_abs_error, 0.01)
                self.assertLess(abs(comparison.centroid_shift[0]), 0.02)
                self.assertLess(abs(comparison.centroid_shift[1]), 0.02)
                self.assertEqual(comparison.bbox_ours, comparison.bbox_golden)
        self.assertAlmostEqual(results['pro_splash_wordmark'][1], 24.998239560594325, places=9)

    def test_frame_zero_is_blank(self) -> None:
        picture = self._render(0.0)
        self.assertTrue((picture[..., :3] == 250).all())
        self.assertIsNone(self.player.ink_bounds(0.0))

    def test_time_is_clamped_to_the_drawable_range(self) -> None:
        end = self._render(self.player.last_frame)
        self.assertTrue(np.array_equal(self._render(142.0), end))
        self.assertTrue(np.array_equal(self._render(1000.0), end))
        self.assertTrue(np.array_equal(self._render(-5.0), self._render(0.0)))
        with self.assertRaises(ValueError):
            self._render(math.nan)

    def test_the_rest_frame_equals_the_end_of_the_intro(self) -> None:
        # the storyboard freezes comp 74 as « the same picture as comp 142 »
        self.assertTrue(np.array_equal(self._render(74.0), self._render(142.0)))

    def test_sub_frames_interpolate(self) -> None:
        lefts = [self.player.ink_bounds(f).left() for f in (60.0, 60.25, 60.5, 60.75, 61.0)]
        self.assertEqual(lefts, sorted(lefts))
        self.assertEqual(len(set(lefts)), 5)

    def test_the_erase_keeps_the_eased_share_of_the_mark(self) -> None:
        # comp 90: the trim start has eased to s(90); what is left is (1 − s) of the outline
        redraw = self.player.composition.layers[0].groups[0]
        outline = self.player._path(redraw.paths[0], 90.0)
        full = skia.PathMeasure(outline, False).getLength()
        self.assertAlmostEqual(full, 74 * 2 + 148 + 4 * math.hypot(38.88, 38.88), places=2)
        piece = self.player._trimmed(outline, redraw.trim, 90.0)
        start = FAST_OUT_SLOW_IN((90.0 - 74.0) / 30.0)
        self.assertAlmostEqual(skia.PathMeasure(piece, False).getLength(), full * (1 - start), places=2)

    def test_the_trim_erases_then_redraws_from_the_right_edge(self) -> None:
        # comp 90: what is left of the erase is the end of the outline —
        # the upper-right diagonal and the right edge down to (318.88, 190)
        erasing = self.player.ink_bounds(90.0)
        self.assertGreater(erasing.left(), 290.0)
        self.assertLess(erasing.bottom(), 191.0)
        # comp 110: the redraw starts at (318.88, 190) and runs down the right
        # edge; its start is a butt cap, flat on y = 190
        redrawing = self.player.ink_bounds(110.0)
        self.assertAlmostEqual(redrawing.top(), 190.0, places=3)
        self.assertAlmostEqual(redrawing.left(), 318.88 - 18.56 / 2, places=3)
        self.assertLess(redrawing.bottom(), 264.0)
        # 104 → 104.01: erased and faded out, nothing on screen
        self.assertIsNone(self.player.ink_bounds(104.0))

    def test_ink_bounds_in_composition_units(self) -> None:
        mark = self.player.ink_bounds(142.0)
        # the closed path ±9.28 (half of the 18.56 stroke), round joins
        for got, want in zip(
            (mark.left(), mark.top(), mark.right(), mark.bottom()), (231.84, 106.72, 328.16, 273.28)
        ):
            self.assertAlmostEqual(got, want, places=2)
        wordmark = self.player.ink_bounds(25.0)
        self.assertAlmostEqual(wordmark.left(), 57.54, places=2)
        self.assertAlmostEqual(wordmark.bottom(), 238.61, places=2)

    def test_fade_in_opacity_is_continuous(self) -> None:
        # comp 6: half-way through the letters' 0 → 100 fade, eased
        width = 900
        dst = self.player.dst_rect((500, 320), width)
        picture = check.render_surface(self.player, 6.0, size=(1000, 640), dst_rect=dst)
        expected = 250 - FAST_OUT_SLOW_IN(0.5) * (250 - 17)
        self.assertAlmostEqual(int(picture[..., 0].min()), expected, delta=1.5)

    def test_colour_override_and_fit(self) -> None:
        dst = skia.Rect.MakeXYWH(0, 0, 400, 400)  # square: the 560 × 380 frame is centred
        surface = skia.Surface(400, 400)
        canvas = surface.getCanvas()
        canvas.clear(skia.ColorBLACK)
        self.player.render(canvas, 142.0, dst, color='#FFFFFF')
        picture = surface.makeImageSnapshot().toarray()[..., 0].astype(float) / 255.0
        self.assertEqual(picture.max(), 1.0)
        ys, xs = np.mgrid[0:400, 0:400]
        # the finished mark is centred in its composition, so it lands on the rect's centre
        self.assertAlmostEqual(float((xs * picture).sum() / picture.sum()), 199.5, delta=0.3)
        self.assertAlmostEqual(float((ys * picture).sum() / picture.sum()), 199.5, delta=0.3)
        with self.assertRaises(ValueError):
            self.player.render(canvas, 0.0, dst, color='white')
        with self.assertRaises(ValueError):
            self.player.render(canvas, 0.0, skia.Rect.MakeWH(0, 10))


if __name__ == '__main__':
    unittest.main()
