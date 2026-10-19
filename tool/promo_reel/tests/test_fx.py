"""FX primitives (tool/promo_reel/promo/fx): unittest, fast, no real captures.

  python -m unittest discover -s tool/promo_reel/tests -p 'test_fx.py'
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

import numpy as np
import skia

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo.fx import (blur, brand, carnet, counter, easing, grain, lift, pattern, phone,  # noqa: E402
                      projection, punch, stack, surface, touch)
from promo.fx import type as ty  # noqa: E402
from promo.fx.projection import Pose  # noqa: E402


def render(w: int, h: int, draw, background: int = 0xFFFFFFFF) -> np.ndarray:
    s = surface.new_surface(w, h)
    c = s.getCanvas()
    c.clear(background)
    draw(c)
    return surface.to_array(s)


def ink_columns(a: np.ndarray, background=(255, 255, 255)) -> np.ndarray:
    """Columns holding any pixel off the background."""
    return np.nonzero(np.any(np.any(a[..., :3] != np.array(background, np.uint8), axis=2), axis=0))[0]


# ---- easing ------------------------------------------------------------------------

class Easing(unittest.TestCase):
    NAMED = ["easeIn", "easeOut", "easeInOut", "easeOutCubic", "easeInOutCubic", "easeInCubic", "fastOutSlowIn"]

    def test_every_curve_lands_exactly(self):
        for name in self.NAMED + ["linear"]:
            c = easing.curve(name)
            self.assertEqual(c(0.0), 0.0, name)
            self.assertEqual(c(1.0), 1.0, name)
            self.assertEqual(c(-3.0), 0.0, name)
            self.assertEqual(c(7.0), 1.0, name)

    def test_curves_are_monotone(self):
        ts = np.linspace(0, 1, 2001)
        for name in self.NAMED:
            ys = np.array([easing.curve(name)(t) for t in ts])
            self.assertTrue(np.all(np.diff(ys) >= -1e-12), name)

    def test_same_curves_as_flutter(self):
        """Within Flutter's own bisection error of the App Preview's port."""
        pb = brand.preview_brand()
        cubics = dict(pb.CUBICS, fastOutSlowIn=(0.4, 0.0, 0.2, 1.0), easeInCubic=(0.55, 0.055, 0.675, 0.19))
        for name, pts in cubics.items():
            for t in np.linspace(0, 1, 401):
                self.assertAlmostEqual(easing.curve(name)(t), pb.cubic(pts, t), delta=0.004, msg=name)

    def test_precise_solver(self):
        c = easing.FAST_OUT_SLOW_IN
        for t in (0.1, 0.37, 0.5, 0.83):
            s = c.parameter(t)
            self.assertAlmostEqual(c._bez(c.a, c.c, s), t, delta=1e-8)

    def test_motion_tokens_in_frames(self):
        got = {k: v.frames for k, v in brand.motion_tokens().items()}
        self.assertEqual(got, {"fast": 3, "base": 6, "emphasis": 9, "slow": 12})
        frames, c = easing.motion("emphasis")
        self.assertEqual(frames, 9)
        self.assertIs(c, easing.EASE_OUT_CUBIC)

    def test_keyframes_hit_their_values(self):
        k = easing.Keyframes([easing.Key(128, 1.10), easing.Key(136, 1.00, easing.FAST_OUT_SLOW_IN),
                              easing.Key(150, 2.0)])
        self.assertEqual(k(100), 1.10)
        self.assertEqual(k(128), 1.10)
        self.assertEqual(k(136), 1.00)
        self.assertEqual(k(150), 2.0)
        self.assertEqual(k(999), 2.0)
        self.assertTrue(1.0 < k(132) < 1.10)
        with self.assertRaises(ValueError):
            easing.Keyframes([easing.Key(5, 0), easing.Key(5, 1)])


# ---- brand -------------------------------------------------------------------------

class Brand(unittest.TestCase):
    def test_tokens_come_from_colors_dart(self):
        P = brand.PALETTE
        self.assertEqual((P.INK, P.PAPER, P.BLACK, P.WHITE), (0xFF1A1A1A, 0xFFFAFAFA, 0xFF000000, 0xFFFFFFFF))
        self.assertEqual(P.INK_SECONDARY, 0xFF4A4A4A)
        with self.assertRaises(brand.BrandError):
            brand.token("noSuchToken")

    def test_the_mark_is_one_round_stroke(self):
        g = brand.mark_geometry()
        self.assertEqual(len(g.points), 6)
        self.assertAlmostEqual(g.stroke, 28.85)
        self.assertAlmostEqual(g.weight, 28.85 / 258.85, places=6)
        path, w = brand.mark_path(66.0, (100, 100))
        b = path.computeTightBounds()
        self.assertAlmostEqual(b.height() + w, 66.0, places=4)

    def test_fonts(self):
        self.assertEqual(brand.poppins(72).getTypeface().getFamilyName(), "Poppins")
        self.assertGreater(brand.inter(40, 500).measureText("Mois"), 0)


# ---- type -------------------------------------------------------------------------

class French(unittest.TestCase):
    def test_spacing_and_quotes(self):
        N = ty.NNBSP
        self.assertEqual(ty.french("Votre carnet déborde ?"), f"Votre carnet déborde{N}?")
        self.assertEqual(ty.french("arrive?"), f"arrive{N}?")
        self.assertEqual(ty.french("Quoi ?!"), f"Quoi{N}?!")
        self.assertEqual(ty.french("Note : ok ; fin !"), f"Note{N}: ok{N}; fin{N}!")
        self.assertEqual(ty.french("« Plus »"), f"«{N}Plus{N}»")
        self.assertEqual(ty.french("Aujourd'hui"), "Aujourd’hui")
        self.assertEqual(ty.french("Libre — 10:45"), "Libre — 10:45")
        self.assertEqual(ty.french("https://myweli.com"), "https://myweli.com")

    def test_idempotent(self):
        for s in ("Votre carnet déborde ?", "« Plus » : oui ; non !", "Aujourd'hui"):
            once = ty.french(s)
            self.assertEqual(ty.french(once), once)

    def test_fcfa_is_the_apps_format(self):
        N = ty.NNBSP
        self.assertEqual(ty.fcfa(77000), f"77{N}000 FCFA")
        self.assertEqual(ty.fcfa(5000), f"5{N}000 FCFA")
        self.assertEqual(ty.fcfa(181000), f"181{N}000 FCFA")
        self.assertEqual(ty.fcfa(1234567), f"1{N}234{N}567 FCFA")
        self.assertEqual(ty.fcfa(0), "0 FCFA")
        self.assertEqual(ty.fcfa(999), "999 FCFA")


class Measuring(unittest.TestCase):
    def test_storyboard_widths(self):
        """The storyboard measured its lines with these advances."""
        self.assertAlmostEqual(ty.measure("Votre carnet", brand.poppins(96)), 601.44, delta=0.05)
        self.assertAlmostEqual(ty.measure(ty.fcfa(77000), brand.poppins(120)), 712.0, delta=0.1)
        self.assertAlmostEqual(ty.measure("Plus de clients, moins de gestion.", brand.poppins(46)), 762.4, delta=0.1)

    def test_nnbsp_is_never_a_box(self):
        f = brand.poppins(96)
        self.assertEqual(f.unicharToGlyph(0x202F), 0, "Poppins gained a U+202F glyph: revisit nnbsp_advance")
        s = ty.shape(ty.french("déborde ?"), f)
        self.assertNotIn(0, s.glyphs)
        self.assertEqual(len(s.glyphs), len("déborde?"))
        self.assertAlmostEqual(ty.nnbsp_advance(f), ty.measure(" ", f) / 2)
        # Inter has its own
        fi = brand.inter(40)
        self.assertNotEqual(fi.unicharToGlyph(0x202F), 0)

    def test_unknown_glyph_is_an_error(self):
        with self.assertRaises(ValueError):
            ty.shape("一", brand.poppins(40))

    def test_break_lines(self):
        f = brand.poppins(72)
        cases = {
            "Une cliente arrive ? Glissez, appuyez.": ["Une cliente arrive ?", "Glissez, appuyez."],
            "Ils réservent dès la mise en ligne.": ["Ils réservent", "dès la mise en ligne."],
            "Chaque rendez-vous terminé, compté.": ["Chaque rendez-vous", "terminé, compté."],
            "Votre page, prête pour vos clients.": ["Votre page, prête", "pour vos clients."],
        }
        for text, want in cases.items():
            got = ty.break_lines(ty.french(text), f, 771)
            self.assertEqual(got, [ty.french(w) for w in want])
            self.assertTrue(all(ty.measure(line, f) <= 771 for line in got))
        self.assertEqual(ty.break_lines("Respirez.", brand.poppins(96), 771), ["Respirez."])
        with self.assertRaises(ValueError):
            ty.break_lines("anticonstitutionnellement " * 6, f, 300)

    def test_caption_rejects_a_line_too_wide(self):
        with self.assertRaises(ValueError):
            ty.Caption([[ty.Word("Plus de clients, moins de gestion, toujours.", 0)]], brand.poppins(72),
                       brand.PALETTE.INK, cap_top=300)


class Reveal(unittest.TestCase):
    def caption(self):
        return ty.Caption([[ty.Word("Votre", 0), ty.Word("carnet", 8)], [ty.Word("déborde ?", 16)]],
                          brand.poppins(96), brand.PALETTE.INK, cap_top=300)

    def test_word_timing(self):
        cap = self.caption()
        p = cap.find("carnet")
        self.assertEqual(cap.word_state(p, 6.9), (0.0, 24.0))          # not yet
        a, dy = cap.word_state(p, 8)                                   # its cue frame already moves
        self.assertGreater(a, 0.3)
        self.assertGreater(dy, 0)
        self.assertEqual(cap.word_state(p, 11), (1.0, 0.0))            # settled 3 frames later

    def test_settled_caption_is_the_typeset_line(self):
        cap = self.caption()
        f = brand.poppins(96)
        b0 = 300 + ty.cap_height(f)
        a = render(1080, 600, lambda c: cap.draw(c, 40))
        b = render(1080, 600, lambda c: (ty.draw_text(c, "Votre carnet", f, 540, b0, brand.PALETTE.INK, align="centre"),
                                         ty.draw_text(c, ty.french("déborde ?"), f, 540, b0 + 1.15 * 96,
                                                      brand.PALETTE.INK, align="centre")))
        self.assertLessEqual(int(np.abs(a.astype(int) - b.astype(int)).max()), 1)

    def test_mask_reveal_runs_left_to_right(self):
        f = brand.poppins(46)
        cols = []
        for p in (0.3, 0.6, 1.0):
            a = render(900, 120, lambda c: ty.draw_mask_reveal(c, "moins de gestion.", f, 20, 80, 0xFF000000, p))
            cols.append(ink_columns(a).max())
        self.assertLess(cols[0], cols[1])
        self.assertLess(cols[1], cols[2])


class Strike(unittest.TestCase):
    def test_starts_at_four_widths_and_grows_to_full(self):
        self.assertEqual(ty.strike_length(300, 10, 0.0), 40)
        self.assertEqual(ty.strike_length(300, 10, 1.0), 300)
        self.assertEqual(ty.strike_length(30, 10, 0.0), 30)            # never longer than full

    def test_drawn_extent(self):
        for p, want in ((0.0, 44.0), (1.0, 400.0)):
            a = render(600, 60, lambda c: ty.draw_strike(c, (100, 30), (500, 30), 11, p, 0xFF000000))
            cols = ink_columns(a)
            self.assertAlmostEqual(cols.max() - cols.min() + 1, want, delta=1.5)
        a = render(600, 60, lambda c: ty.draw_strike(c, (100, 30), (500, 30), 11, -0.1, 0xFF000000))
        self.assertEqual(len(ink_columns(a)), 0)

    def test_stem_width_is_the_letters(self):
        self.assertAlmostEqual(ty.stem_width(brand.poppins(72)), 11.0, delta=0.6)


# ---- counter ------------------------------------------------------------------------

class Counter(unittest.TestCase):
    PAIRS = [(0, 77000), (0, 5000), (12345, 67000), (77000, 0), (999, 1000), (5, 5), (0, 1234567), (100500, 7)]

    def test_reads_start_and_lands_exactly_on_end(self):
        f = brand.poppins(120)
        for a, b in self.PAIRS:
            o = counter.Odometer(a, b, f, brand.PALETTE.INK)
            self.assertEqual(o.text_at(0.0), ty.fcfa(a), (a, b))
            self.assertEqual(o.text_at(1.0), ty.fcfa(b), (a, b))
            self.assertEqual(o.text_at(1.5), ty.fcfa(b), (a, b))
            for col in o.columns:
                self.assertEqual((col.start + col.steps) % 10, (b // 10 ** col.k) % 10)

    def test_width_runs_continuously_from_start_to_end(self):
        f = brand.poppins(120)
        o = counter.Odometer(0, 77000, f, brand.PALETTE.INK)
        self.assertAlmostEqual(o.width(0.0), ty.measure(ty.fcfa(0), f), places=3)
        self.assertAlmostEqual(o.width(1.0), ty.measure(ty.fcfa(77000), f), places=3)
        ws = [o.width(p) for p in np.linspace(0, 1, 481)]
        self.assertLess(max(abs(x - y) for x, y in zip(ws, ws[1:])), 25.0)

    def test_fast_columns_spin_faster(self):
        o = counter.Odometer(0, 77000, brand.poppins(120), brand.PALETTE.INK)
        self.assertEqual([c.steps for c in o.columns], [7, 17, 20, 30, 40])

    def test_landed_counter_is_the_typeset_figure_pixel_for_pixel(self):
        f = brand.poppins(120)
        ink = brand.PALETTE.INK
        for a, b in ((0, 77000), (77000, 0), (12345, 67000)):
            o = counter.Odometer(a, b, f, ink)
            landed = render(1080, 260, lambda c: o.draw(c, 1.0, 540, 180))
            typeset = render(1080, 260, lambda c: ty.draw_text(c, ty.fcfa(b), f, 540, 180, ink, align="centre"))
            self.assertTrue(np.array_equal(landed, typeset), (a, b))

    def test_mid_roll_draws_something(self):
        o = counter.Odometer(0, 77000, brand.poppins(120), brand.PALETTE.INK)
        a = render(1080, 260, lambda c: o.draw(c, 0.4, 540, 180))
        self.assertGreater(len(ink_columns(a)), 300)


# ---- punch -----------------------------------------------------------------------------

class Punch(unittest.TestCase):
    def test_envelopes(self):
        self.assertEqual(punch.punch(63, 64), 1.0)
        self.assertEqual(punch.punch(64, 64), 1.0)
        self.assertAlmostEqual(punch.punch(67, 64), 1.025)
        self.assertEqual(punch.punch(72, 64), 1.0)
        self.assertTrue(1.0 < punch.punch(69, 64) < 1.025)
        self.assertEqual(punch.settle(551, 552), 1.0)
        self.assertEqual(punch.settle(552, 552), 1.08)
        self.assertEqual(punch.settle(557, 552), 1.0)
        both = punch.Punches([punch.Punch(64), punch.Punch(66)])
        self.assertGreater(both(67), punch.Punch(64)(67))


# ---- projection and phone ---------------------------------------------------------------

def synthetic_capture(marker_pt=(201.0, 437.0), size_pt=8) -> np.ndarray:
    """A 1206×2622 grey capture with a red square centred on `marker_pt`."""
    a = np.full((2622, 1206, 4), 200, np.uint8)
    a[..., 3] = 255
    x, y = marker_pt
    h = size_pt * 3 / 2
    a[round(y * 3 - h):round(y * 3 + h), round(x * 3 - h):round(x * 3 + h), :3] = (255, 0, 0)
    return a


def red_centroid(a: np.ndarray) -> tuple[float, float]:
    m = (a[..., 0] > 200) & (a[..., 1] < 80) & (a[..., 2] < 80)
    ys, xs = np.nonzero(m)
    return float(xs.mean() + 0.5), float(ys.mean() + 0.5)


class Projection(unittest.TestCase):
    def test_rest_pose_is_identity(self):
        h = projection.homography(Pose(), (0, 0, 100, 200))
        self.assertTrue(np.allclose(h, np.eye(3)))

    def test_rot_x_tips_the_top_away(self):
        h = projection.homography(Pose(rot_x=20), (0, 0, 100, 200))
        (tl, tr, bl, br) = [projection.apply(h, *p) for p in ((0, 0), (100, 0), (0, 200), (100, 200))]
        self.assertLess(tr[0] - tl[0], br[0] - bl[0])

    def test_rot_y_turns_the_right_edge_away(self):
        h = projection.homography(Pose(rot_y=20), (0, 0, 100, 200))
        (tl, tr, bl, br) = [projection.apply(h, *p) for p in ((0, 0), (100, 0), (0, 200), (100, 200))]
        self.assertLess(br[1] - tr[1], bl[1] - tl[1])

    def test_project_agrees_with_the_homography(self):
        pose = Pose(rot_x=17, rot_y=-9, rot_z=4, scale=1.2, dx=10, dy=-30)
        rest = (100, 200, 500, 900)
        pts = np.array([[100, 200], [500, 900], [321, 456]])
        self.assertTrue(np.allclose(projection.project(pose, rest, pts), projection.apply_many(projection.homography(pose, rest), pts)))

    def test_solve_offset(self):
        pose = projection.solve_offset(Pose(rot_x=22, scale=2.0), (0, 0, 1000, 1300), (300, 700), (540, 960))
        x, y = projection.apply(projection.homography(pose, (0, 0, 1000, 1300)), 300, 700)
        self.assertAlmostEqual(x, 540, places=6)
        self.assertAlmostEqual(y, 960, places=6)


class PhoneT(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.phone = phone.Phone(synthetic_capture())

    def test_window_formula(self):
        w = phone.Window()
        self.assertEqual(w.y_of(300, 257), 600 + 43 * 1.791)
        self.assertEqual(w.point(0, 257, 257), (180, 600))
        self.assertAlmostEqual(w.W_for(581, 1184), 581 - 584 / 1.791)
        self.assertEqual(w.pt_of(*w.point(110, 546, 257), 257), (110.0, 546.0))
        self.assertEqual(w.alpha_at(500), 0.0)
        self.assertEqual(w.alpha_at(900), 1.0)
        self.assertEqual(w.alpha_at(1300), 0.0)
        self.assertAlmostEqual(w.alpha_at(580), 0.5)

    def test_map_point_in_window_mode(self):
        x, y = self.phone.map_point(0, 300, W=300)
        self.assertAlmostEqual(x, 180)
        self.assertAlmostEqual(y, 600)
        x, y = self.phone.map_point(402, 400, W=300)
        self.assertAlmostEqual(x, 180 + 402 * 1.791)                   # 899.98: the brief's 1.791 px/pt
        self.assertAlmostEqual(y, 600 + 100 * 1.791, places=6)

    def test_pixels_land_where_map_point_says(self):
        """Both draw paths (exact Lanczos when flat, skia's when turned)."""
        for pose, where in ((Pose(), {"W": 437 - 150}), (Pose(rot_x=18, rot_y=-12), {"centre": (540, 960)}),
                            (Pose(scale=1.3, dx=7.25), {"W": 380.4})):
            a = render(1080, 1920, lambda c: self.phone.draw(c, pose, fade=False, **where))
            got = red_centroid(a)
            want = self.phone.map_point(201.0, 437.0, pose, **where)
            self.assertAlmostEqual(got[0], want[0], delta=0.6, msg=str(pose))
            self.assertAlmostEqual(got[1], want[1], delta=0.6, msg=str(pose))

    def test_band_and_floor_hide_the_phone(self):
        a = render(1080, 1920, lambda c: self.phone.draw(c, W=100), background=0xFF00FF00)
        self.assertEqual(tuple(a[550, 540, :3]), (0, 255, 0))       # under the band
        self.assertEqual(tuple(a[1250, 540, :3]), (0, 255, 0))      # under the floor
        self.assertEqual(tuple(a[900, 540, :3]), (200, 200, 200))   # the screen

    def test_overlay_is_in_screen_points(self):
        def overlay(c):
            c.drawRect(skia.Rect.MakeXYWH(50, 500, 10, 10), skia.Paint(Color=0xFFFF0000))
        a = render(1080, 1920, lambda c: self.phone.draw(c, W=400, overlay=overlay, fade=False))
        got = red_centroid(a)
        # both the capture's marker (201, 437) and the overlay's (55, 505) are red: take the overlay's half
        m = (a[..., 0] > 200) & (a[..., 1] < 80)
        ys, xs = np.nonzero(m[:, :500])
        self.assertAlmostEqual(xs.mean() + 0.5, 180 + 55 * 1.791, delta=0.6)
        self.assertAlmostEqual(ys.mean() + 0.5, 600 + 105 * 1.791, delta=0.6)
        self.assertIsNotNone(got)

    def test_turned_phone_shows_its_side_wall(self):
        a = render(1080, 1920, lambda c: self.phone.draw(c, Pose(rot_y=30), centre=(540, 960)))
        side = phone.PhoneSpec().side
        self.assertTrue(np.any(np.all(a[..., :3] == np.array(brand.rgb(side), np.uint8), axis=2)))

    def test_rejects_a_capture_of_the_wrong_size(self):
        with self.assertRaises(ValueError):
            phone.Phone(np.zeros((100, 50, 4), np.uint8))


# ---- blur ------------------------------------------------------------------------------

class Blur(unittest.TestCase):
    def test_static_scene_is_unchanged(self):
        def scene(c, t):
            c.clear(0xFFFAFAFA)
            c.drawCircle(60, 40, 20, skia.Paint(AntiAlias=True, Color=0xFF1A1A1A))
        plain = render(120, 80, lambda c: scene(c, 0))
        acc = blur.accumulate(scene, (120, 80), 5.0, samples=8)
        self.assertLessEqual(int(np.abs(acc.astype(int) - plain.astype(int)).max()), 1)

    def test_light_is_averaged_linearly(self):
        def scene(c, t):
            c.clear(0xFFFFFFFF if (t % 1.0) < 0.5 else 0xFF000000)
        lin = blur.accumulate(scene, (64, 64), 10.5, samples=8, shutter=1.0)
        enc = blur.accumulate(scene, (64, 64), 10.5, samples=8, shutter=1.0, linear=False)
        self.assertAlmostEqual(float(lin[..., 0].mean()), 187.5, delta=1.0)
        self.assertAlmostEqual(float(enc[..., 0].mean()), 127.5, delta=1.0)

    def test_transfer_round_trip(self):
        v = np.arange(256, dtype=np.uint8)
        back = blur.to_encoded(blur.to_linear(v))
        self.assertLess(float(np.abs(back - v).max()), 0.3)

    def test_region_leaves_the_rest_still(self):
        def scene(c, t):
            c.clear(0xFFFFFFFF)
            c.drawRect(skia.Rect.MakeXYWH(10 + 6 * t, 10, 8, 8), skia.Paint(Color=0xFF000000))
            c.drawRect(skia.Rect.MakeXYWH(10 + 6 * t, 60, 8, 8), skia.Paint(Color=0xFF000000))
        plain = render(100, 80, lambda c: scene(c, 3.0))
        out = blur.accumulate(scene, (100, 80), 3.0, samples=16, region=(0, 0, 100, 40))
        self.assertTrue(np.array_equal(out[40:], plain[40:]))
        self.assertFalse(np.array_equal(out[:40], plain[:40]))

    def test_samples_for(self):
        self.assertEqual(blur.samples_for(0), 8)
        self.assertEqual(blur.samples_for(60, max_gap=2.0), 30)
        self.assertEqual(blur.samples_for(10_000), 64)

    def test_whip(self):
        w = blur.WhipPan(start=256, distance=403.0)
        self.assertEqual(w.offset(250), 0.0)
        self.assertEqual(w.offset(256), 0.0)
        self.assertEqual(w.offset(262), 403.0)
        self.assertAlmostEqual(w.peak_frame(), 259.0, delta=0.1)       # the whoosh's +3
        self.assertGreater(w.samples(259, px_per_unit=1.791), 8)
        drawn = []
        w.draw_transition(skia.Surface(10, 10).getCanvas(), 259, lambda c: drawn.append("out"),
                          lambda c: drawn.append("in"))
        self.assertEqual(drawn, ["out", "in"])


# ---- lift and stack ----------------------------------------------------------------------

class Lift(unittest.TestCase):
    def test_same_pixels_at_one_to_one(self):
        rng = np.random.default_rng(3)
        src = rng.integers(0, 256, (60, 80, 4), dtype=np.uint8)
        src[..., 3] = 255
        pic = surface.Picture(src)
        style = lift.LiftStyle(radius_src=0, outline=0, shadows=())
        a = render(200, 120, lambda c: lift.draw_card(c, pic, (10, 10, 70, 50), (100, 40, 160, 80), style=style))
        self.assertTrue(np.array_equal(a[40:80, 100:160, :3], src[10:50, 10:70, :3]))

    def test_pop_progress(self):
        self.assertEqual(lift.pop_progress(230, 232), 0.0)
        self.assertGreater(lift.pop_progress(232, 232), 0.0)
        self.assertEqual(lift.pop_progress(237, 232), 1.0)
        self.assertEqual(lift.pop_progress(253, 232, down=248), 0.0)
        self.assertTrue(0 < lift.pop_progress(250, 232, down=248) < 1)

    def test_layouts(self):
        r = lift.fit_width((0, 0, 300, 60), 120, 900, bottom=1190)
        self.assertEqual(r, (120, 1190 - 156, 900, 1190))
        rs = stack.stack_rects([(0, 0, 100, 100), (0, 0, 100, 50), (0, 0, 100, 100)], x0=330, width=360, gap=16,
                               top=660)
        self.assertEqual([round(b[1] - a[3]) for a, b in zip(rs, rs[1:])], [16, 16])
        self.assertTrue(all(r[2] - r[0] == 360 for r in rs))

    def test_stack_pops_in_order(self):
        src = np.full((90, 90, 4), 255, np.uint8)
        st = stack.Stack(src, [(0, 0, 30, 30)] * 3, [(0, 0, 10, 10)] * 3, [(0, 0, 50, 50)] * 3, ups=[472, 480, 488])
        self.assertEqual([round(st.progress(i, 480), 3) > 0 for i in range(3)], [True, True, False])


# ---- touch ------------------------------------------------------------------------------

class Touch(unittest.TestCase):
    def test_tone_by_ground(self):
        white = np.full((300, 300, 3), 255, np.uint8)
        green = np.zeros((300, 300, 3), np.uint8)
        green[...] = (0x2D, 0x50, 0x16)                               # AppColors.success
        self.assertEqual(touch.tone_at(white, 150, 150, 144), "dark")
        self.assertEqual(touch.tone_at(green, 150, 150, 144), "light")
        self.assertEqual(touch.tone_colour("light"), brand.PALETTE.WHITE)

    def test_ripple_and_disc_timing(self):
        self.assertEqual(touch.ripple_state(176, 176)[0], 48.0)
        self.assertIsNone(touch.ripple_state(186, 176))
        self.assertIsNone(touch.ripple_state(175, 176))
        d5, a5 = touch.ripple_state(181, 176)
        self.assertTrue(48 < d5 < 96 and 0 < a5 < 1)
        self.assertEqual(touch.touch_alpha(174, 176), 0.0)
        self.assertGreater(touch.touch_alpha(176, 176), 0.0)
        self.assertEqual(touch.touch_alpha(178, 176), 1.0)
        self.assertEqual(touch.touch_alpha(190, 176, up=184), 0.0)

    def test_disc_size(self):
        a = render(200, 200, lambda c: touch.draw_touch(c, 100, 100, scale=1.791))
        cols = ink_columns(a)
        self.assertAlmostEqual(cols.max() - cols.min() + 1, 48 * 1.791, delta=2)


# ---- pattern and grain ------------------------------------------------------------------

class Pattern(unittest.TestCase):
    def test_dark_and_light_colours(self):
        a = render(400, 400, lambda c: pattern.draw_pattern(c, (0, 0, 400, 400), dark=True), 0xFF000000)
        self.assertEqual(int(a[..., 0].max()), 0x1E)
        b = render(400, 400, lambda c: pattern.draw_pattern(c, (0, 0, 400, 400), dark=False), 0xFFFAFAFA)
        self.assertEqual(int(b[..., 0].min()), 0xED)

    def test_drift_is_periodic_and_smooth(self):
        spec = pattern.SPEC
        a = render(300, 300, lambda c: pattern.draw_pattern(c, (0, 0, 300, 300), dark=False), 0xFFFAFAFA)
        b = render(300, 300, lambda c: pattern.draw_pattern(c, (0, 0, 300, 300), dark=False,
                                                            offset=(0, 2 * spec.pitch_y)), 0xFFFAFAFA)
        self.assertLessEqual(int(np.abs(a.astype(int) - b.astype(int)).max()), 1)
        c_ = render(300, 300, lambda c: pattern.draw_pattern(c, (0, 0, 300, 300), dark=False, offset=(0, 0.5)),
                    0xFFFAFAFA)
        self.assertFalse(np.array_equal(a, c_))

    def test_clear_zone_stays_clear(self):
        clear = (100, 100, 300, 300)
        a = render(400, 400, lambda c: pattern.draw_pattern(c, (0, 0, 400, 400), dark=False, clear=clear),
                   0xFFFAFAFA)
        self.assertTrue(np.all(a[100:300, 100:300, :3] == 0xFA))


class Grain(unittest.TestCase):
    def test_seeded_per_frame(self):
        img = np.full((64, 64, 4), 120, np.uint8)
        img[..., 3] = 255
        a = grain.apply_grain(img, 7, seed=3)
        self.assertTrue(np.array_equal(a, grain.apply_grain(img, 7, seed=3)))
        self.assertFalse(np.array_equal(a, grain.apply_grain(img, 8, seed=3)))
        self.assertLess(abs(float(a[..., 0].mean()) - 120), 1.0)
        self.assertTrue(np.all(a[..., 3] == 255))

    def test_dither_keeps_a_slow_gradient_unbanded(self):
        ramp = np.tile(np.linspace(100.0, 101.0, 1000, dtype=np.float32), (200, 1))
        q = grain.quantize(ramp, seed=1, frame=0).astype(np.float32)
        blocks = q.reshape(200, 10, 100).mean(axis=(0, 2))
        ideal = ramp.reshape(200, 10, 100).mean(axis=(0, 2))
        self.assertLess(float(np.abs(blocks - ideal).max()), 0.05)
        plain = np.floor(ramp + 0.5).reshape(200, 10, 100).mean(axis=(0, 2))
        self.assertGreater(float(np.abs(plain - ideal).max()), 0.3)    # what dithering fixes


# ---- carnet ------------------------------------------------------------------------------

class Carnet(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.c = carnet.Carnet(seed=7)

    def test_seeded(self):
        other = carnet.Carnet(seed=7)
        self.assertEqual({k: round(e.length, 6) for k, e in self.c.entries.items()},
                         {k: round(e.length, 6) for k, e in other.entries.items()})
        third = carnet.Carnet(seed=8)
        self.assertNotEqual(round(self.c.entries["row03"].length, 3), round(third.entries["row03"].length, 3))

    def test_the_page_is_full(self):
        ids = set(self.c.entries)
        for need in ("write", "squeeze", "arrow", "margin", "header"):
            self.assertIn(need, ids)
        self.assertEqual(sum(1 for k in ids if k.startswith("cross")), 2)
        rows = [k for k in ids if k.startswith("row")] + ["write"]
        self.assertEqual(len(rows), self.c.rows)
        squeeze = self.c.entries["squeeze"].bounds
        a = self.c.squeeze_after
        # squeezed: its ink sits around the rule between its two rows, small
        self.assertLess(squeeze[3] - squeeze[1], self.c.style.pitch)

    def test_ink_draws_on_in_pen_order(self):
        cv_w, cv_h = self.c.size
        x0, y0, x1, y1 = (int(v) for v in self.c.entries["write"].bounds)

        def amount(p):
            a = render(cv_w, cv_h, lambda cv: self.c.draw_entry(cv, "write", p))
            return int((a[y0:y1, x0:x1, 0] < 200).sum()), ink_columns(a)

        n0, _ = amount(0.0)
        n_half, cols_half = amount(0.5)
        n1, cols_full = amount(1.0)
        self.assertEqual(n0, 0)
        self.assertLess(n_half, n1)
        self.assertLess(cols_half.max(), cols_full.max())               # left to right

    def test_animated_entries_wait_for_their_ink(self):
        rest = self.c.rest_rect(0, 600, 0)
        size = (600, round(rest[3]) + 10)
        idle = render(*size, lambda cv: self.c.draw(cv, Pose(), rest, ink={}), 0xFF000000)
        shown = render(*size, lambda cv: self.c.draw(cv, Pose(), rest, ink={"write": 1.0, "margin": 1.0}), 0xFF000000)
        self.assertFalse(np.array_equal(idle, shown))

    def test_strikes(self):
        w = self.c.strike_width()
        self.assertAlmostEqual(w, brand.mark_geometry().weight * 60 * 1.5, places=6)
        (ax, ay), (bx, by) = self.c.strike_segment(4)
        e = self.c.entries["row04"].bounds
        self.assertLess(ax, e[0])
        self.assertGreater(bx, e[2])
        with self.assertRaises(KeyError):
            self.c.strike_segment(999)

    def test_no_font_no_letters(self):
        """Honesty: the scribbles are pen paths, never type."""
        src = Path(carnet.__file__).read_text(encoding="utf-8")
        for banned in ("skia.Font", "TextBlob", "drawString", "poppins(", "inter("):
            self.assertNotIn(banned, src)


if __name__ == "__main__":
    unittest.main()
