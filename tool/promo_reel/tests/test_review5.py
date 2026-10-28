"""Round 5's review (2026-10-19): every finding that was not the owner's
call, held on the film's own geometry and frames.

  * the page's end keeps the app's own qualifier — « Aperçu … / Réserver
    (après la mise en ligne) » — inside the text rectangle, wholly in view;
  * the « Arrivé » lift never leaves the platform rectangle (it pops in place
    where its card lies on the owner's floor), settles on the storyboard's
    f248–253, and its place on the phone is emptied while it is lifted;
  * the in-phone whip carries the old 13:15 row across the window only
    inside ≥ 80 px of blur;
  * the map credit shows while — and only while — the map's tiles show,
    AIR 2 included;
  * the counter's label rolls, its two words never drawn over each other;
  * the 15-s dissolve blends the screens inside ONE slab (1:1 here; 9:16 in
    test_scenes);
  * the Fiche's panel has no seam, its strips run over the tiles' row only,
    and it stops above « PROCHAIN RENDEZ-VOUS »;
  * 16:9: the push-in keeps the phone on the floor, the slab stays inside
    graphics-safe, the lifts pass under the sentence.

Each was watched failing on the round-5 build (HEAD 730a2bbb) before its
fix — the commit message lists what each read there."""

from __future__ import annotations

import math
import sys
import unittest
from pathlib import Path

import numpy as np
import skia

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo import storyboard as sbmod  # noqa: E402
from promo.fx import brand, counter, lift, stack  # noqa: E402
from promo.fx.blur import subframe_times  # noqa: E402
from promo.fx.surface import Picture, new_surface, to_array  # noqa: E402
from promo.media import tools  # noqa: E402
from promo.scenes.clock import Clock  # noqa: E402
from promo.storyboard import Rect, covered_by  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_round5 import UPS, fiche_geometry, tiles_picture  # noqa: E402
from test_scenes import EVENTS, EVENTS15  # noqa: E402

SB = sbmod.load()
CLOCKS = {"30s": Clock(EVENTS, 960), "15s": Clock(EVENTS15, 512)}
HAVE_TAKES = tools.material_available() and tools.promo_takes_root() is not None
FORMATS = ("9x16", "1x1", "16x9")
QUALIFIER_PT = (74.0, 750.5, 328.0, 807.5)        # the owner-preview bar's two lines, take5b 28.480
LUMA = np.array([0.2126, 0.7152, 0.0722])


def luminance(rgba: np.ndarray) -> np.ndarray:
    return rgba[..., :3].astype(float) @ LUMA


# ── no takes: the label, the panel ───────────────────────────────────────────────────────────────


class TestTheLabelRolls(unittest.TestCase):
    """« Aujourd’hui » → « Mois »: crossing in place 12 px apart, the two read
    as one garbled word for 3–4 frames (30-s f536–539, 15-s f280–284)."""

    def rows(self, old: str, new: str, p: float) -> np.ndarray:
        s = new_surface(1080, 400)
        c = s.getCanvas()
        c.clear(brand.PALETTE.PAPER)
        counter.draw_label_switch(c, old, new, p, brand.inter(40), 540.0, 200.0, brand.PALETTE.INK_SECONDARY,
                                  align="centre")
        L = luminance(to_array(s))
        return np.nonzero((L < 200).any(axis=1))[0]

    def test_the_two_labels_never_meet(self):
        for p in np.linspace(0.05, 0.95, 19):
            old, new = self.rows("Aujourd’hui", "", p), self.rows("", "Mois", p)
            if len(old) and len(new):
                with self.subTest(p=round(float(p), 2)):
                    self.assertLess(old.max(), new.min())                    # the old above, the new below: apart
        # whole at either end: the typeset label
        self.assertGreater(len(self.rows("Aujourd’hui", "Mois", 0.0)), 25)
        self.assertGreater(len(self.rows("Aujourd’hui", "Mois", 1.0)), 25)


def panel_frame(fid: str, f: float, st: stack.Stack, origins, absences) -> np.ndarray:
    """The Fiche as test_round5 renders it: the tiles and « 0 Absences »' stand-in
    on paper, then the veil-less panel and the cards."""
    pic = Picture(tiles_picture())
    s = new_surface(1080, 1920)
    c = s.getCanvas()
    c.clear(brand.PALETTE.PAPER)
    for o in origins:
        lift.draw_card(c, pic, (0.0, 0.0, 260.0, 252.0), o, lift=0.0)
    lift.draw_card(c, pic, (900.0, 0.0, 1160.0, 252.0), absences, lift=0.0)
    st.draw(c, float(f), veil_rect=None, backdrop=(brand.token("background"), 24.0, 24.0))
    return luminance(to_array(s))


class TestTheFichePanel(unittest.TestCase):
    def stack(self, fid: str):
        origins, absences, targets = fiche_geometry(fid)
        srcs = [(i * 300.0, 0.0, i * 300.0 + 260.0, 252.0) for i in range(3)]
        return stack.Stack(tiles_picture(), srcs, origins, targets, list(UPS)), origins, absences

    def test_no_seam_between_its_pieces(self):
        """9:16 f484–f511: a 1-px column of « 0 Absences » showed between two
        pieces meeting on a fractional edge (x 657–658, 30 levels darker)."""
        for fid in ("9x16", "1x1"):
            st, origins, absences = self.stack(fid)
            x0, y0, x1, y1 = (int(round(v)) for v in absences)
            for f in (484, 486, 490, 495):
                L = panel_frame(fid, f, st, origins, absences)
                cards = [st.lifts[i].rect(st.progress(i, float(f))) for i in range(3) if st.progress(i, float(f)) > 0]
                cols = L[y0 + 8:y1 - 8, :].min(axis=0)
                for x in range(x0 + 4, x1 - 4):
                    if any(r[0] - 3 <= x <= r[2] + 3 for r in cards):
                        continue                                              # a card (its outline, its shadow)
                    if any(abs(x - o[0]) < 3 or abs(x - o[2]) < 3 for o in origins):
                        continue                                              # a waiting tile's own edge
                    with self.subTest(fmt=fid, f=f, x=x):
                        self.assertGreater(cols[x], min(cols[x - 3], cols[x + 3]) - 8.0)

    def test_its_strips_run_over_the_tiles_row_only(self):
        """1:1 f481–f487: the strip ran over its piece's padded height (y 442–734),
        a pale rectangle across the next card's top border."""
        for fid in ("9x16", "1x1"):
            st, origins, _ = self.stack(fid)
            top, bottom = math.floor(min(o[1] for o in origins)), math.ceil(max(o[3] for o in origins))
            for f in np.arange(479.0, 500.0, 0.5):
                for r, a, strip in st.backdrop_pieces(float(f), 24.0):
                    if strip:
                        with self.subTest(fmt=fid, f=float(f)):
                            self.assertGreaterEqual(r[1], top)
                            self.assertLessEqual(r[3], bottom)


# ── the films' own frames (the takes) ────────────────────────────────────────────────────────────


_FILMS: dict = {}


def film(cut: str, fid: str, *overrides: str):
    key = (cut, fid, overrides)
    if key not in _FILMS:
        from promo.scenes import Film
        sb = sbmod.load(overrides=list(overrides)) if overrides else SB
        _FILMS[key] = Film(sb, cut, fid, CLOCKS[cut])
    return _FILMS[key]


def scene(f, sid: str):
    return next(s for s in f.scenes if s.id == sid)


def overlays(sc, f: int) -> dict:
    """The boxes a phone scene records on frame f (its overlays drawn on a scratch canvas)."""
    rec: dict = {"boxes": []}
    s = new_surface(*sc.ctx.size)
    sc.draw_overlays(s.getCanvas(), f, rec)
    return rec


def slab(sc, t: float, pose=None) -> tuple[float, float, float, float]:
    """The slab's frame rect on t (posed), bezel included."""
    spec = sc.phone.spec
    pose = sc.pose(t) if pose is None else pose
    x0, y0, x1, y1 = sc.phone.map_rect((0.0, spec.crop_top_pt, spec.screen_pt[0], spec.screen_pt[1]), pose,
                                       W=sc.camera_W(t) if hasattr(sc, "camera_W") else sc.W(t), window=sc.win(t))
    b = spec.bezel * pose.scale
    return x0 - b, y0 - b, x1 + b, y1 + b


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestThePageEnd(unittest.TestCase):
    """30-s 9:16 f736–767: W 352.46 put both lines of the owner-preview bar
    below y 1248 (y ≈ 1270–1375) — the app's qualifier the storyboard pairs
    with « Ils réservent dès la mise en ligne. »."""

    def test_the_qualifier_inside_the_rectangle_wholly_in_view(self):
        for fid in FORMATS:
            fm = film("30s", fid)
            area = list(SB.formats[fid].text_area)
            for sid, frames in (("page", range(736, 752)), ("air2", range(752, 768))):
                sc = scene(fm, sid)
                for f in frames:
                    t = float(f)
                    _, opacity = sc.fall_state(t)
                    if opacity < 0.5:
                        continue                                             # the phone gone with the fall
                    win = sc.win(t)
                    r = sc.phone.map_rect(QUALIFIER_PT, sc.pose(t), W=sc.W(t), window=win)
                    with self.subTest(fmt=fid, f=f):
                        self.assertTrue(covered_by(Rect(*r), area), r)
                        self.assertGreaterEqual(min(win.alpha_at(float(y)) for y in np.linspace(r[1], r[3], 9)), 0.99)


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestTheArriveLift(unittest.TestCase):
    def test_it_settles_on_the_storyboards_frames(self):
        """30-s: « The card settles back over f248–253 » (5-frame easeIn) — round
        5 settled from f240, landed 4 frames, gone by f245."""
        L = next(l for l in scene(film("30s", "9x16"), "journal").lifts if l["id"] == "arrive-card")
        p = lambda t: lift.pop_progress(float(t), L["up"], 6.0, L["down"], 5.0)
        self.assertEqual(L["down"], 248.0)
        self.assertTrue(all(p(f) == 1.0 for f in range(237, 249)), [round(p(f), 3) for f in range(236, 254)])
        self.assertEqual(p(253), 0.0)

    def test_its_place_is_emptied_while_it_is_lifted(self):
        """The veiled original (« 11:15 Fatou B. 13:15 Arrivé ») stayed legible
        under the landed copy: it read as a second booking."""
        for cut, f in (("30s", 240), ("15s", 151)):
            fm = film(cut, "9x16")
            j = scene(fm, "journal")
            L = next(l for l in j.lifts if l["id"] == "arrive-card")
            frame, _ = fm.frame(f)
            x0, y0, x1, y1 = j.phone.map_rect(L["rect_pt"], j.pose(float(f)), W=j.camera_W(float(f)),
                                              window=j.win(float(f)))
            inner = luminance(frame)[int(y0) + 10:int(y1) - 10, int(x0) + 10:int(x1) - 10]
            with self.subTest(cut=cut):
                self.assertLess(float(inner.std()), 2.0)                      # plain: no text, no badge
                self.assertGreater(float(inner.min()), 230.0)


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestTheWhip(unittest.TestCase):
    """The first whip frame carried the old 13:15 row into the floor fade
    with 37–72 px of blur (and the last one through the band's fade)."""

    MIN_BLUR = 80.0

    def test_the_row_crosses_only_inside_the_blur(self):
        for cut in ("30s", "15s"):
            for fid in FORMATS:
                j = scene(film(cut, fid), "journal")
                label, rect, _ = j.hidden[0]
                whip = next(k for k in j.W.keys if k.blur == "whip")
                for f in range(int(whip.frame) - 7, int(whip.frame) + 1):
                    b = j.blur_at(f)
                    ts = subframe_times(float(f), b.samples, b.shutter) if b else [float(f)]
                    places, shown = [], 0.0
                    for t in ts:
                        win = j.win(t)
                        r = j.phone.map_rect(rect, j.pose(t), W=j.camera_W(t), window=win)
                        places.append(r)
                        shown = max(shown, max(win.alpha_at(float(y)) for y in np.linspace(r[1], r[3], 24)))
                    if shown > 0.05:
                        with self.subTest(cut=cut, fmt=fid, f=f):
                            self.assertGreaterEqual(abs(places[-1][1] - places[0][1]), self.MIN_BLUR)


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestTheMapCredit(unittest.TestCase):
    """« While map tiles show, a credit line »: round 5 showed tiles in the
    floor fade with no credit (f691–693), faded 1:1's to nothing while the
    map was on (f734–750) and drew none in AIR 2 (f752–763)."""

    @staticmethod
    def tiles_shown(sc, page, t: float) -> float:
        """Rows of map tiles the frame shows (window-weighted px × the fall's opacity)."""
        c = page.credit
        idx = sc.timeline.index(t)
        s = c["track"].at_ticks(sc.source.take.pts[idx])
        x0, y0, x1, y1 = c["map"]
        y0, y1 = y0 - s, min(y1 - s, 740.0)
        if y1 <= y0:
            return 0.0
        win = sc.win(t)
        _, fy0, _, fy1 = sc.phone.map_rect((x0, y0, x1, y1), sc.pose(t), W=sc.W(t), window=win)
        _, opacity = sc.fall_state(t)
        return float(np.mean([win.alpha_at(float(y)) for y in np.linspace(fy0, fy1, 64)])) * (fy1 - fy0) * opacity

    def test_the_credit_follows_the_tiles(self):
        for fid in FORMATS:
            fm = film("30s", fid)
            page = scene(fm, "page")
            for sid in ("page", "air2"):
                sc = scene(fm, sid)
                for f in range(sc.start, sc.end):
                    shown = self.tiles_shown(sc, page, float(f))
                    _, opacity = sc.fall_state(float(f))
                    credit = [b for b in overlays(sc, f)["boxes"] if b["kind"] == "credit"]
                    with self.subTest(fmt=fid, f=f, shown=round(shown, 1)):
                        if shown >= 2.0:
                            self.assertEqual(len(credit), 1)
                            if shown >= 4.0 * opacity:                       # whole while the tiles show
                                self.assertGreaterEqual(credit[0]["alpha"], 0.99)
                        elif shown <= 0.0 and sid == "page" and f < 680:
                            self.assertEqual(credit, [])                     # no map yet, no credit
                        elif sid == "air2":
                            # the owner's round 5 (2026-10-20): whole until the map has dimmed out (f767) — the
                            # falling phone fades, the credit does not (round 5's own rule faded it with the phone)
                            self.assertGreaterEqual(credit[0]["alpha"], 0.99)


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestTheSquareDissolve(unittest.TestCase):
    def test_one_slab(self):
        """1:1 15-s f194–195: two whole stages cross-faded drew a second,
        translucent bezel arc across the form (the 9:16's: test_scenes)."""
        fm = film("15s", "1x1")
        for f in (194, 195):
            L = luminance(fm.frame(f)[0])
            band = ((L[380:1002, 300:780] >= 40) & (L[380:1002, 300:780] < 200)).mean(axis=1) >= 0.9
            runs = np.diff(np.concatenate([[0], band.astype(int), [0]]))
            longest = max((e - s for s, e in zip(np.where(runs == 1)[0], np.where(runs == -1)[0])), default=0)
            with self.subTest(f=f):
                self.assertLess(longest, 6)


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestTheNextLabelUnderTheFiche(unittest.TestCase):
    """The panel's 24-px bottom pad sliced « PROCHAIN RENDEZ-VOUS »'s top third
    in 1:1 (its first ink row at y 734, not 730) and hid it whole in 9:16."""

    LABEL_PT = (34.0, 407.0, 184.0, 415.0)

    def test_the_label_shows_whole(self):
        for fid in ("9x16", "1x1"):
            fm = film("30s", fid)
            fi = scene(fm, "fiche")
            for f in (490, 505):
                frame, _ = fm.frame(f)
                x0, y0, x1, y1 = fi.phone.map_rect(self.LABEL_PT, fi.pose(float(f)), W=fi.W(float(f)),
                                                  window=fi.win(float(f)))
                L = luminance(frame)
                top = L[int(round(y0)) - 1:int(round(y0)) + 3, int(x0):int(x1)]
                with self.subTest(fmt=fid, f=f):
                    self.assertGreater(int((top < 215).sum()), 10)            # its cap line's ink, in view


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestLandscape(unittest.TestCase):
    def test_the_push_keeps_the_phone_on_the_floor(self):
        """The « rempli. » push scaled about the band edge: the slab sank to
        y ≈ 1071, Koffi A.'s « Confirmé » cut by the floor (30-s f437–463,
        15-s f233–255). Round 6 (the owner's push about the floor, `fill`, on
        the lower journal and the form's end): every pushed frame keeps the
        slab ON the floor — never sunk into it, never lifted off it (its first
        build laid the window at the risen edge and scaled it again: the slab
        floated at y ≈ 912)."""
        for cut in ("30s", "15s"):
            j = scene(film(cut, "16x9"), "journal")
            pushed = []
            for f in range(j.start, j.end):
                t = float(f)
                z = j.zoom(t) * j.fill(t)
                if z > 1.0 + 1e-6:
                    pose = j.pose(t)
                    if slab(j, t, pose.but(scale=pose.scale / z, pivot=None))[3] <= 1026.5:   # it stands on the floor
                        pushed.append(f)
            self.assertGreater(len(pushed), 60 if cut == "30s" else 70, cut)   # the fills and the « rempli. » push
            for f in pushed:
                with self.subTest(cut=cut, f=f):
                    self.assertAlmostEqual(slab(j, float(f))[3], 1026.0, delta=0.5)

    def test_a_push_that_would_sink_is_refused(self):
        from promo.scenes import SceneError
        with self.assertRaisesRegex(SceneError, "sinks the slab"):
            film("30s", "16x9", "scenes.30s.2.camera.zoom.4.anchor_y=700", "scenes.30s.2.camera.formats.16x9.fill=[]")
        # on the push about the floor, a zoom about any other anchor is refused (the two share the floor)
        with self.assertRaisesRegex(SceneError, r"camera.fill: on f437 a zoom about another anchor .* runs on the push"):
            film("30s", "16x9", "scenes.30s.2.camera.zoom.4.anchor_y=700")

    def test_the_slab_inside_graphics_safe(self):
        """At rest the bezel ran to x 1840 (graphics-safe ends at 1824), in the
        drop's slam to 1860 (past action-safe, 1853)."""
        for cut in ("30s", "15s"):
            for sc in film(cut, "16x9").scenes:
                if not hasattr(sc, "phone"):
                    continue
                for f in range(sc.start, sc.end, 2):
                    t = float(f)
                    pose = sc.pose(t)
                    x1 = slab(sc, t)[2]
                    with self.subTest(cut=cut, scene=sc.id, f=f):
                        self.assertLessEqual(x1, 1853.0)                     # action-safe, always
                        if pose.is_flat and abs(pose.scale - 1.0) < 1e-9:
                            self.assertLessEqual(x1, 1824.5)                 # graphics-safe, at rest

    def test_the_lifts_pass_under_the_sentence(self):
        """The « Total réalisé » card crossed « rendez-vous » (f595) and grazed
        « terminé, » (f597) in flight; landed, its top was 22 px under the
        sentence's ink."""
        fm = film("30s", "16x9")
        for sid, frames in (("revenus", range(593, 640)), ("fiche", range(470, 512)), ("journal", range(230, 256))):
            sc = scene(fm, sid)
            for f in frames:
                boxes = overlays(sc, f)["boxes"] + fm.captions.boxes(float(f))
                lifts = [b["rect"] for b in boxes if b["kind"] == "lift"]
                caps = [b["rect"] for b in boxes if b["kind"] == "caption"]
                for a in lifts:
                    for c in caps:
                        with self.subTest(scene=sid, f=f):
                            self.assertFalse(min(a[2], c[2]) > max(a[0], c[0]) and min(a[3], c[3]) > max(a[1], c[1]),
                                             (a, c))
        landed = [b["rect"] for b in overlays(scene(fm, "revenus"), 620)["boxes"] if b["kind"] == "lift"][0]
        ink = max(c[3] for c in (b["rect"] for b in fm.captions.boxes(620.0) if b["kind"] == "caption"))
        self.assertGreaterEqual(landed[1] - ink, 40.0)                       # clear of the sentence


if __name__ == "__main__":
    unittest.main()
