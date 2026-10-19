"""Round 5: the owner's decisions after the six-film review (2026-10-19) and
the leftovers of round 4's confirm.

  * 9:16 FLOOR — the phone window runs to y 1424 (≈ 1450; app pixels only):
    the old 13:15 row stays hidden, the touch discs ride the app's pixels
    below the platform's text rectangle, text and lifts stay inside it;
  * 16:9 RE-LAY — the phone stands on the floor (its bottom never floats),
    the band edge comes down over the rows above W, the window is taller,
    the captions and the counter larger;
  * the 1:1 band edge on the journal's chip row (its fade no longer cuts the
    week's dates);
  * the Fiche's panel never pulls back and never blanks « 0 Absences » in one
    frame (9:16 AND 1:1 geometry);
  * verify()'s VERDICTS, not only its rules: a join that is not what it is
    called fails (b), hook ink off its ground fails (g), the counter is
    measured on every frame of its roll, the AIR and the outro tail are held
    on the master AND on the MP4 (d), and the tail's « 20 dB down 22 frames
    on » half counts."""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import numpy as np
import yaml

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo import storyboard as sbmod  # noqa: E402
from promo import verify as vmod  # noqa: E402
from promo.fx import brand, lift, stack  # noqa: E402
from promo.fx.phone import Window  # noqa: E402
from promo.fx.surface import Picture, new_surface, to_array  # noqa: E402
from promo.media import tools  # noqa: E402
from promo.scenes.captions import CaptionItem  # noqa: E402
from promo.scenes.clock import Clock  # noqa: E402
from promo.scenes.phone import camera_W_keys, window_for  # noqa: E402
from promo.storyboard import Rect  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_scenes import EVENTS, EVENTS15  # noqa: E402

SB = sbmod.load()
STARTER = sbmod.DEFAULT_PATH.read_text(encoding="utf-8")
REF = window_for(SB.formats["9x16"])
CLOCKS = {"30s": Clock(EVENTS, 960), "15s": Clock(EVENTS15, 512)}
K = 1.791
HAVE_TAKES = tools.material_available() and tools.promo_takes_root() is not None


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


def concrete(win: Window, W: float) -> Window:
    """The window a frame shows under camera W (16:9: its band edge)."""
    return win.at_top(win.top_for(W)) if hasattr(win, "top_for") else win


# ── 9:16 floor ───────────────────────────────────────────────────────────────────────────────────


class TestOwnersFloor(unittest.TestCase):
    def assertProblem(self, found: list[str], *parts: str):
        self.assertTrue(any(all(p in f for p in parts) for f in found), f"{parts} not in {found}")

    def test_the_window_runs_to_the_floor_text_does_not(self):
        f = SB.formats["9x16"]
        self.assertEqual(f.zones["phone_window"], Rect(180, 600, 900, 1424))
        self.assertGreaterEqual(f.zones["phone_window"].y1, 1400)                # ≈ 1450, set by the pictures
        self.assertEqual(f.zones["overlays"].y1, 1248)                           # lifts and the counter: the platform's
        self.assertTrue(all(z.y1 <= 1248 for n, z in f.zones.items() if n in ("captions", "hook_block", "overlays")))
        for name, place in f.layout["lift_y"].items():
            self.assertLessEqual(next(iter(place.values())), 1248, name)

    def test_a_window_past_the_safe_bottom_says_why(self):
        self.assertEqual(problems(), [])
        self.assertProblem(problems(text=with_doc(lambda d: d["formats"]["9x16"].pop("phone_window_note"))),
                           "9x16.zones.phone_window", "past the safe area's bottom", "phone_window_note")
        # downwards only: never above the safe area's top, never past its columns
        self.assertProblem(problems("formats.9x16.zones.phone_window=[180, 200, 900, 1424]"),
                           "9x16.zones.phone_window", "columns and below its top")
        self.assertProblem(problems("formats.9x16.zones.phone_window=[100, 600, 900, 1424]"),
                           "9x16.zones.phone_window", "columns and below its top")

    def test_the_old_1315_row_and_fatou_on_the_new_floor(self):
        """Measured on take1b 10.000: Fatou B.'s card bottom 582 pt just above
        the floor, the 13:15 row's text (612.7 pt) under the floor fade, and the
        band edge between « Ma journée » (ink ≤ 104.3 pt) and « Aujourd’hui »
        (136 pt) — no half-faded title."""
        win = window_for(SB.formats["9x16"])
        for cut in ("30s", "15s"):
            j = next(s for s in SB.cut_scenes(cut) if s["id"] == "journal")
            W = next(float(k["value"]) for k in j["camera"]["W"] if k.get("keep") == "floor")
            with self.subTest(cut=cut):
                self.assertLessEqual(win.floor - 16, win.y_of(582.0, W))
                self.assertLessEqual(win.y_of(582.0, W), win.floor)
                self.assertGreaterEqual(win.y_of(612.7, W), win.floor + win.floor_fade + 8)
                self.assertLessEqual(104.33, W - win.band_fade / K)                 # the title wholly under the band
                self.assertLessEqual(W, 136.0)                                       # « Aujourd’hui » wholly in view


class TestTouchesRideThePhone(unittest.TestCase):
    """A touch disc is where the finger was, on the app's pixels — in 9:16
    down to the owner's floor; never in the caption band, never past the
    floor. Text, lifts and the counter keep the platform rectangle."""

    def test_rules(self):
        f = SB.formats["9x16"]
        recs = [{"f": 1, "boxes": [
            {"kind": "touch", "label": "on Fatou B.'s card, below 1248", "rect": [334, 1306, 420, 1392]},
            {"kind": "touch", "label": "in the caption band", "rect": [400, 300, 480, 380]},
            {"kind": "touch", "label": "past the floor", "rect": [400, 1440, 480, 1500]},
            {"kind": "touch", "label": "a ripple past the screen's edge (clipped by it)", "rect": [158, 900, 330, 1060]},
            {"kind": "lift", "label": "a lift below 1248", "rect": [120, 1260, 900, 1300]},
            {"kind": "lift", "label": "a lift at rest below 1248", "rect": [120, 1260, 900, 1300], "rest": True},
            {"kind": "lift", "label": "a lift rising out of Fatou B.'s card", "rect": [131, 1109, 896, 1258],
             "rest": False},
            {"kind": "lift", "label": "a lift in transit past the floor", "rect": [131, 1400, 896, 1500], "rest": False},
            {"kind": "counter", "label": "the counter in the band", "rect": [200, 330, 880, 500]}]}]
        counted, bad = vmod.outside_safe(recs, f)
        self.assertEqual(counted, 9)
        self.assertEqual(sorted(b["label"] for b in bad), ["a lift at rest below 1248", "a lift below 1248",
                                                           "a lift in transit past the floor", "in the caption band",
                                                           "past the floor"])


# ── 1:1 band edge ────────────────────────────────────────────────────────────────────────────────


class TestSquareBandEdge(unittest.TestCase):
    """Round 4's leftover: on Fatou B.'s framing the 1:1 band fade cut the
    week's dates (186–226 pt). The band edge sits on the chip row now
    (233–267 pt), as 9:16's did: the dates wholly under the opaque band."""

    def test_the_dates_under_the_band_the_chips_at_its_edge(self):
        win = window_for(SB.formats["1x1"])
        for cut in ("30s", "15s"):
            j = next(s for s in SB.cut_scenes(cut) if s["id"] == "journal")
            keys = camera_W_keys(j["camera"]["W"], win, REF, 56.0, "W")
            W = next(k["value"] for k, raw in zip(keys, j["camera"]["W"]) if raw.get("keep") == "floor")
            with self.subTest(cut=cut, W=W):
                self.assertLessEqual(226.0, W - win.band_fade / K)                   # dates and dots: opaque band
                self.assertTrue(233.0 <= W <= 267.0, W)                              # the edge on the chips
                self.assertLessEqual(win.y_of(612.7, W), 1080)                       # (sanity: on the canvas)
                self.assertGreaterEqual(win.y_of(612.7, W), win.floor + win.floor_fade)   # 13:15 still under the floor


# ── 16:9 re-lay ──────────────────────────────────────────────────────────────────────────────────


class TestLandscapeRelay(unittest.TestCase):
    def test_the_window_is_taller_and_anchored(self):
        win = window_for(SB.formats["16x9"])
        self.assertGreater(win.floor - win.top, 918)                             # round 3: 84–1002
        self.assertEqual(SB.formats["16x9"].layout["phone_anchor"], "floor")
        self.assertEqual(win.anchor_bottom, 1026 - 16)                           # the slab's bottom on y 1026
        self.assertTrue(990 <= win.anchor_bottom + 16 <= 1026)
        self.assertEqual(win.top_for(82.0), win.top)                             # the screen fills: the resting edge
        self.assertAlmostEqual(win.top_for(667.0), 1010 - (874 - 667) * K, places=6)   # the lower journal
        with self.assertRaisesRegex(ValueError, "anchored"):
            win.alpha_at(500.0)                                                  # its band edge needs W
        for fid in ("9x16", "1x1"):
            self.assertIsNone(window_for(SB.formats[fid]).anchor_bottom)

    def test_the_1315_row_under_the_band_on_the_lower_journal(self):
        win = window_for(SB.formats["16x9"])
        w = concrete(win, 667.0)
        self.assertLessEqual(w.y_of(644.0, 667.0), w.top - w.band_fade)

    def test_larger_captions_and_counter(self):
        lay9, lay16 = SB.formats["9x16"].layout, SB.formats["16x9"].layout
        self.assertGreaterEqual(lay16["type_px"]["app"], 1.2 * lay9["type_px"]["app"])
        self.assertGreaterEqual(lay16["type_px"]["counter"], 1.2 * lay9["type_px"]["counter"])
        for role in ("tagline", "store", "credit"):
            self.assertEqual(lay16["type_px"][role], lay9["type_px"][role], role)
        # every line still in the column, at most caption_line_max_px
        f = SB.formats["16x9"]
        for cut in ("30s", "15s"):
            for s in SB.cut_scenes(cut):
                for c in s.get("captions") or []:
                    item = CaptionItem(c, s["id"], CLOCKS[cut], f.layout, s["id"], size=f.size)
                    if item.kind == "app":
                        self.assertEqual(item.font.getSize(), lay16["type_px"]["app"])

    def test_type_sizes_differ_only_with_a_reason(self):
        found = problems(text=with_doc(lambda d: d["formats"]["16x9"].pop("type_note")))
        self.assertTrue(any("16x9.layout.type_px" in p and "type_note" in p for p in found), found)
        found = problems("formats.16x9.layout.type_px.tagline=60")
        self.assertTrue(any("16x9.layout.type_px" in p and "tagline" in p and "reference's" in p for p in found), found)
        found = problems("formats.1x1.layout.type_px.app=60", "formats.1x1.type_note=bigger")
        self.assertTrue(any("1x1.layout.type_px" in p and "never smaller" in p for p in found), found)
        self.assertEqual(problems(), [])


# ── the Fiche's panel ────────────────────────────────────────────────────────────────────────────

TILES_PT = [(16.33, 286.0, 102.33, 369.67), (112.33, 286.0, 197.0, 369.67), (300.33, 286.0, 385.67, 369.67)]
ABSENCES_PT = (206.33, 286.0, 291.33, 369.67)          # « 0 Absences »: between tiles 2 and 3, never lifted
UPS = (472.0, 480.0, 488.0)


def fiche_geometry(fid: str):
    """The Fiche as the format lays it out: the tiles' places on the phone
    (W 216, `keep: top` — the same W in every format), their targets."""
    f = SB.formats[fid]
    lay = f.layout
    sc = next(s for s in SB.cut_scenes("30s") if s["id"] == "fiche")
    win = window_for(f)
    W = camera_W_keys(sc["camera"]["W"], win, REF, 56.0, "W")[0]["value"]
    w = concrete(win, W)

    def place(r):
        return (w.screen_x + r[0] * K, w.y_of(r[1], W), w.screen_x + r[2] * K, w.y_of(r[3], W))
    srcs = [tuple(v * 3 for v in r) for r in TILES_PT]
    x0, x1 = map(float, lay["lift_x"])
    gap = float(sc["stack"]["layout"]["gap"])
    centre = float(lay["lift_y"][sc["stack"]["layout"]["y"]]["centre_y"])
    h = (x1 - x0 - gap * 2) / sum((r[2] - r[0]) / (r[3] - r[1]) for r in srcs)
    targets = stack.stack_rects(srcs, x0=x0, gap=gap, axis="horizontal", y0=centre - h / 2, height=h)
    return [place(r) for r in TILES_PT], place(ABSENCES_PT), targets


def tiles_picture() -> np.ndarray:
    """Tiles of dark horizontal strokes on a light card (each column has texture)."""
    pic = np.full((260, 1200, 4), 250, np.uint8)
    for i in range(4):
        x0 = i * 300
        for k in range(6):
            pic[40 + 30 * k:52 + 30 * k, x0 + 10:x0 + 250, :3] = 30
    pic[..., 3] = 255
    return pic


class TestFichePanel(unittest.TestCase):
    """Round 4's leftover: « 0 Absences » blinked for one frame at f480 in 9:16
    (the panel ran 80 px ahead of the « 17 000 » card) and, in 1:1, came back
    for a frame (the panel's edge pulled back when tile 2 lifted: `reach`
    took its pace from the NEWEST lift). Rendered as the film draws it, in
    9:16 AND 1:1 geometry: no column of what lies between is blanked in one
    frame farther than the pad from a card, none ever comes back, all of it
    is under the panel or a card at the end; a waiting tile keeps its own."""

    PAD = 24.0

    def frames(self, fid: str):
        origins, absences, targets = fiche_geometry(fid)
        pic = tiles_picture()
        srcs = [(i * 300.0, 0.0, i * 300.0 + 260.0, 252.0) for i in range(3)]
        st = stack.Stack(pic, srcs, origins, targets, list(UPS))
        P = Picture(pic)
        out = {}
        for f in range(470, 501):
            s = new_surface(1080, 1920)
            c = s.getCanvas()
            c.clear(brand.PALETTE.PAPER)
            for o in origins:
                lift.draw_card(c, P, srcs[0], o, lift=0.0)
            lift.draw_card(c, P, (900.0, 0.0, 1160.0, 252.0), absences, lift=0.0)    # « 0 Absences »' stand-in
            st.draw(c, float(f), veil_rect=None, backdrop=(brand.token("background"), self.PAD, 24.0))
            L = to_array(s)[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722]
            cards = [st.lifts[i].rect(st.progress(i, float(f))) for i in range(3) if st.progress(i, float(f)) > 0]
            out[f] = (L, cards)
        return st, origins, absences, out

    def column_contrast(self, L, rect) -> np.ndarray:
        x0, y0, x1, y1 = (int(round(v)) for v in rect)
        return L[y0 + 6:y1 - 6, x0 + 10:x1 - 10].std(axis=0)

    def test_what_lies_between_is_covered_never_blanked(self):
        for fid in ("9x16", "1x1"):
            st, origins, absences, out = self.frames(fid)
            xs = np.arange(int(round(absences[0])) + 10, int(round(absences[2])) - 10)
            base = self.column_contrast(out[470][0], absences)
            self.assertGreater(float(base.min()), 20, fid)
            gone_at: dict[int, int] = {}
            blanked, back, left = [], [], []
            for f in range(471, 501):
                now = self.column_contrast(out[f][0], absences)
                before = self.column_contrast(out[f - 1][0], absences)
                cards = out[f][1]
                for i, x in enumerate(xs):
                    if any(r[0] <= x <= r[2] for r in cards):
                        continue                                             # under a card: the card shows
                    near = min((max(r[0] - x, x - r[2]) for r in cards), default=1e9)
                    if before[i] >= 0.5 * base[i] and now[i] <= 0.1 * base[i] and near > self.PAD + 2:
                        blanked.append((f, int(x), round(float(near))))     # blanked in one frame, far from a card
                    if now[i] <= 0.1 * base[i]:
                        gone_at.setdefault(i, f)
                    elif i in gone_at and now[i] >= 0.3 * base[i]:
                        back.append((f, int(x)))                             # it came back
            end = self.column_contrast(out[500][0], absences)
            for i, x in enumerate(xs):
                if not any(r[0] <= x <= r[2] for r in out[500][1]) and end[i] >= 0.1 * base[i]:
                    left.append(int(x))                                      # still showing at the end
            with self.subTest(fmt=fid, rule="never blanked in one frame"):
                self.assertEqual((blanked[:3], len(blanked)), ([], 0), "blanked in one frame (f, x, px from a card)")
            with self.subTest(fmt=fid, rule="never comes back"):
                self.assertEqual((back[:3], len(back)), ([], 0), "came back (f, x)")
            with self.subTest(fmt=fid, rule="all under the panel or a card at the end"):
                self.assertEqual(left, [], "still showing at the end")

    def test_a_waiting_tile_keeps_its_texture(self):
        for fid in ("9x16", "1x1"):
            st, origins, absences, out = self.frames(fid)
            for f in range(470, 501):
                for o, up in zip(origins, UPS):
                    if f < up:
                        with self.subTest(fmt=fid, f=f, up=up):
                            self.assertGreater(float(self.column_contrast(out[f][0], o).mean()), 20)

    def test_the_panel_only_grows(self):
        """The pieces' union (opaque) and the strips' opacity never decrease."""
        if not hasattr(stack.Stack, "backdrop_pieces"):
            self.fail("no backdrop_pieces: the panel is one rectangle (round 4)")
        for fid in ("9x16", "1x1"):
            origins, absences, targets = fiche_geometry(fid)
            st = stack.Stack(tiles_picture(), [(0.0, 0.0, 260.0, 252.0)] * 3, origins, targets, list(UPS))
            prev = None
            for t in np.arange(470.0, 500.0, 0.25):
                cov = np.zeros((700, 1080))
                for (x0, y0, x1, y1), a, _strip in st.backdrop_pieces(float(t), self.PAD):
                    sl = cov[max(0, int(y0) - 400):max(0, int(y1) - 400), max(0, int(x0)):int(x1)]
                    np.maximum(sl, a, out=sl)
                if prev is not None:
                    with self.subTest(fmt=fid, t=float(t)):
                        self.assertGreaterEqual(float((cov - prev).min()), -1e-9)
                prev = cov


# ── 16:9 / 9:16 frames (the takes) ─────────────────────────────────────────────────────────────


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestFramesOnTheFloor(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from promo.scenes import Film
        cls.films = {(cut, fid): Film(SB, cut, fid, CLOCKS[cut]) for cut in ("30s", "15s") for fid in ("9x16", "16x9")}

    @staticmethod
    def win(j, f: float):
        return j.win(f) if hasattr(j, "win") else j.window

    def screen_bottom(self, j, f: float) -> float:
        spec = j.phone.spec
        return j.phone.map_rect((0.0, spec.crop_top_pt, spec.screen_pt[0], spec.screen_pt[1]), j.pose(float(f)),
                                W=j.camera_W(float(f)), window=self.win(j, f))[3]

    def test_the_16x9_phone_never_floats(self):
        """Round 3's review: on the lower journal the 16:9 phone hung from the
        top, its bottom at y 470 over an empty half frame. It stands on the
        floor now: on every frame of every phone scene its screen's bottom is
        at y ≥ 1010 (the slab's bottom on the floor, y 1026, or below it)."""
        for cut in ("30s", "15s"):
            film = self.films[(cut, "16x9")]
            for j in film.scenes:
                if not hasattr(j, "phone") or j.fall:
                    continue
                for f in range(j.start, j.end, 2):
                    if abs(j.zoom(float(f)) - 1.0) > 1e-6 or j.slam_scale(float(f)) != 1.0:
                        continue                                    # a push-in or a slam grows past the floor
                    with self.subTest(cut=cut, scene=j.id, f=f):
                        self.assertGreaterEqual(self.screen_bottom(j, f), 1010.0 - 0.5)
        j = next(s for s in self.films[("30s", "16x9")].scenes if s.id == "journal")
        self.assertAlmostEqual(self.screen_bottom(j, 270), 1010.0, delta=0.5)        # the lower journal: on it
        self.assertGreater(self.win(j, 270).top, 600)                                # the band came down

    def test_the_15s_dissolve_stands_both_pictures_on_the_floor(self):
        """The 15-s form's declared dissolve (W 667 → 521.67): in 16:9 each
        picture stands on the floor through the window of its own end, so
        « Créer le rendez-vous » — tapped on the dissolve's last frame — is in
        view (a window shared for the fields' sake put it under the floor and
        its disc in nothing: verify (f), round 5's first build)."""
        j = next(s for s in self.films[("15s", "16x9")].scenes if s.id == "journal")
        for f in (193, 196):
            self.assertAlmostEqual(self.screen_bottom(j, f), 1010.0, delta=0.5)
        w = self.win(j, 196.0)
        self.assertLessEqual(w.y_of(832.0 + 20, j.camera_W(196.0)), w.floor - 40)    # the button, the tap at 832 pt
        frame, rec = self.films[("15s", "16x9")].frame(196)
        self.assertEqual([t["gesture"] for t in rec["touch_downs"]], ["tap-creer"])
        disc = next(b["rect"] for b in rec["boxes"] if b["kind"] == "touch")
        self.assertLess(disc[3], w.floor)
        # in the PIXELS: the black button drawn where the tap lands (f196), and on f193 (the picture the
        # dissolve leaves, alone) the slab's bottom bezel on the floor
        L = frame[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722]
        y = int(round(w.y_of(832.0, j.camera_W(196.0))))
        self.assertGreater(int((L[y - 12:y + 12, 1200:1700] < 40).sum()), 5000)
        first, _ = self.films[("15s", "16x9")].frame(193)
        L = first[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722]
        self.assertGreater(int((L[1012:1022, 1300:1600] < 40).sum()), 2000)
        # mid-dissolve (f195, the filled form dominating) it is already drawn through its own window, and the
        # frame's record says so (the window of the picture that dominates, as camera W)
        mid, _ = self.films[("15s", "16x9")].frame(195)
        L = mid[..., :3].astype(float) @ [0.2126, 0.7152, 0.0722]
        self.assertGreater(int((L[y - 12:y + 12, 1200:1700] < 100).sum()), 5000)
        self.assertAlmostEqual(j.win(195.0).top, j.win(196.0).top, places=6)
        self.assertAlmostEqual(j.win(194.0).top, j.win(193.0).top, places=6)
        self.assertGreater(j.win(193.0).top - j.win(196.0).top, 200)                  # two framings

    def test_the_arrive_lift_lands_inside_the_rectangle(self):
        """9:16: Fatou B.'s card sits on the owner's floor (y ≈ 1284–1413); its
        lift rises out of it into the platform rectangle and lands there
        (bottom 1236). In transit it is the app's pixels moving (`rest:
        false`); landed it is held to the text rectangle."""
        film = self.films[("30s", "9x16")]
        boxes = {f: next(b for b in film.frame(f)[1]["boxes"] if b["label"] == "arrive-card") for f in (233, 238)}
        self.assertFalse(boxes[233]["rest"])
        self.assertGreater(boxes[233]["rect"][3], 1248)                              # still rising out of the card
        self.assertTrue(boxes[238]["rest"])
        self.assertLessEqual(boxes[238]["rect"][3], 1248)                            # landed inside
        for f, b in boxes.items():
            self.assertEqual(vmod.outside_safe([{"f": f, "boxes": [b]}], SB.formats["9x16"])[1], [], f)
        landed_low = {**boxes[238], "rect": [120.0, 1260.0, 900.0, 1400.0]}
        self.assertEqual(len(vmod.outside_safe([{"f": 0, "boxes": [landed_low]}], SB.formats["9x16"])[1]), 1)

    def test_the_9x16_swipe_rides_fatou_b_on_the_floor(self):
        _, rec = self.films[("30s", "9x16")].frame(150)
        disc = next(b["rect"] for b in rec["boxes"] if b["kind"] == "touch")
        self.assertGreater(disc[1], 1248)                                             # below the text rectangle …
        self.assertEqual(vmod.outside_safe([rec], SB.formats["9x16"])[1], [])       # … where a disc may be
        self.assertTrue(all(h["alpha"] < 0.05 for h in rec["hidden"]), rec["hidden"])


# ── verify()'s verdicts ─────────────────────────────────────────────────────────────────────────


class FakeMeasure(SimpleNamespace):
    def as_dict(self):
        return {"integrated_lufs": self.integrated_lufs, "true_peak_dbtp": self.true_peak_dbtp}


class TestVerdicts(unittest.TestCase):
    """Round 4's confirm: these guards passed every test with their WIRING
    into verify_film's verdicts removed (M9 joins_bad out of (b), M10
    hook_bad out of (g), M1b the MP4's AIR / tail passed for the master's).
    verify_film runs here on a film directory whose measurements are given:
    each section's status must follow them."""

    FRAMES = 512                       # the 15-s cut

    def run_film(self, *, joins_change: float = 50.0, hook_ok: bool = True, air_mp4: bool = True,
                 air_master: bool = True, tail_mp4: bool = True, tail_master: bool = True) -> dict:
        n = self.FRAMES * 1600
        mp4_audio, master_audio = np.zeros((n, 2)), np.zeros((n, 2)) + 1e-9
        doc = {"records": [{"f": f, "scene": "x", "boxes": []} for f in range(self.FRAMES)],
               "plan": {"transitions": [{"frame": 32, "kind": "cut", "into": "x", "frames": 0}], "timelines": {}},
               "events": [[0, "cut into x"], [32, "cut into y"], [40, "lift"]], "generated": [], "masks": {}}
        events = {"cut": "15s", "fps": 30, "frames": self.FRAMES, "cues": [], "sections": []}
        hook = [{"what": "strike 1", "in_canvas": hook_ok, "in_safe": True, "scrim": 0.0, "box": [200, 900, 800, 950]}]
        film = SimpleNamespace(plan=lambda: {"hook_ink": {"hook": hook}}, scenes=[], captions=SimpleNamespace(items=[]),
                               ctx=SimpleNamespace(sources={}))
        measured = {"ring": {}, "change": {}, "rows": [], "hidden": {}, "strikes": [],
                    "ink": [{"frame": 10, "kind": "caption", "label": "c", "ink": "dark", "column": True,
                             "region": (0, 300, 1080, 400), "box": [200.0, 330.0, 880.0, 380.0]}]}
        probe = {"video": {"codec": "h264", "profile": "High", "width": 1080, "height": 1920, "pix_fmt": "yuv420p",
                           "color_space": "bt709", "frames": self.FRAMES, "cfr": True, "measured_fps": 30,
                           "duration_s": 2.1333},
                 "audio": {"codec": "aac", "sample_rate": 48000, "channels": 2, "bit_rate": 256000, "duration_s": 2.1333},
                 "av": {"duration_difference_s": 0.0}, "container": {"faststart": True}}

        def pull(mp4, frames):
            return {f: np.full((4, 4, 3), (0 if f < 32 else joins_change), np.uint8) for f in frames}

        def air(audio, events, spf=1600):
            ok = air_mp4 if audio is mp4_audio else air_master
            return {"groove_sections": ["drop1"], "groove_lufs": -12.0, "ok": ok,
                    "air": [{"cue": "air1.reverse", "frames": [10, 20], "lufs": -30.0, "under_groove_lu": 18.0 if ok else 3.0,
                             "ok": ok}]}

        def tail(audio, events, spf=1600):
            ok = tail_mp4 if audio is mp4_audio else tail_master
            return {"cue": "end.last", "frame": 40, "hit_dbfs": -10.0, "at_frame": 60, "at_dbfs": -40.0,
                    "decay_db": 30.0 if ok else 5.0, "last_100ms_dbfs": -60.0, "end_under_db": 50.0, "ok": ok}

        m = FakeMeasure(integrated_lufs=-14.0, true_peak_dbtp=-1.5, lra_lu=5.0)
        with tempfile.TemporaryDirectory() as tmp:
            d = Path(tmp)
            (d / "render.json").write_text(json.dumps(doc), encoding="utf-8")
            (d / "events.json").write_text(json.dumps(events), encoding="utf-8")
            (d / "reel.mp4").write_bytes(b"")
            patches = [
                mock.patch.object(vmod.probemod, "probe", lambda p: probe),
                mock.patch.object(vmod.probemod, "check", lambda r, e: []),
                mock.patch.object(vmod.probemod, "write_report", lambda *a, **k: None),
                mock.patch.object(vmod.sheets, "pull_frames", pull),
                mock.patch.object(vmod.sheets, "contact_sheet", lambda *a, **k: None),
                mock.patch.object(vmod.sheets, "save_frames", lambda *a, **k: None),
                mock.patch.object(vmod.touchmod, "touch_downs", lambda name: []),
                mock.patch.object(vmod.touchmod, "cross_check",
                                  lambda *a, **k: SimpleNamespace(ok=True, matches=[], problems=[], report=lambda: "")),
                mock.patch("promo.scenes.Film", lambda *a, **k: film),
                mock.patch("promo.scenes.Clock", lambda *a, **k: None),
                mock.patch.object(vmod, "pixel_plan", lambda film, records, events: {"clicks": [], "keys": []}),
                mock.patch.object(vmod, "run_pixels", lambda *a, **k: measured),
                mock.patch.object(vmod, "_decode_audio", lambda p: mp4_audio),
                mock.patch.object(vmod.loudness, "measure", lambda a: m),
                mock.patch.object(vmod.analysis, "ffmpeg_ebur128",
                                  lambda p: {"integrated_lufs": -14.0, "true_peak_dbfs": -1.5}),
                mock.patch.object(vmod.analysis, "meter", lambda *a, **k: {}),
                mock.patch.object(vmod.analysis, "spectrogram_png", lambda *a, **k: None),
                mock.patch.object(vmod.wav, "read", lambda p: (master_audio, 48000)),
                mock.patch.object(vmod, "air_levels", air),
                mock.patch.object(vmod, "outro_tail", tail),
                mock.patch.object(vmod, "_bandpass", lambda x, *a, **k: x),
                mock.patch.object(vmod, "caption_reading",
                                  lambda items, fps: [{"caption": "c", "cps": 10.0, "ok": True}]),
                mock.patch.object(vmod, "reading_items", lambda film: []),
            ]
            with contextlib.ExitStack() as stack_, contextlib.redirect_stdout(io.StringIO()):
                for p in patches:
                    stack_.enter_context(p)
                res = vmod.verify_film(SB, "15s", "9x16", d)
        return {k: s["status"] for k, s in res.sections.items()}

    def test_the_harness_passes_what_should_pass(self):
        got = self.run_film()
        self.assertEqual((got["b"], got["d"], got["g"]), ("PASS", "PASS", "PASS"), got)

    def test_b_fails_a_cut_that_changes_nothing(self):
        """M9: (b)'s verdict without `not joins_bad`."""
        self.assertEqual(self.run_film(joins_change=0.0)["b"], "FAIL")

    def test_g_fails_hook_ink_off_its_ground(self):
        """M10: (g)'s verdict without `not hook_bad`."""
        self.assertEqual(self.run_film(hook_ok=False)["g"], "FAIL")

    def test_d_holds_the_master_and_the_mp4_apart(self):
        """M1b: verify passing the MP4's AIR and tail in place of the master's."""
        self.assertEqual(self.run_film(air_master=False)["d"], "FAIL")
        self.assertEqual(self.run_film(air_mp4=False)["d"], "FAIL")
        self.assertEqual(self.run_film(tail_master=False)["d"], "FAIL")
        self.assertEqual(self.run_film(tail_mp4=False)["d"], "FAIL")


class TestCounterSampling(unittest.TestCase):
    """M17: (g) measures the counter's ink on EVERY frame from its label's
    switch through the roll to three frames after it lands (round 3's 16:9
    roll drew a fading digit 2 px past the safe edge on one frame)."""

    def test_every_frame_of_the_roll(self):
        font = brand.poppins(120)
        cnt = {"switch": 535.0, "from": 536.0, "land": 548.0, "label_font": brand.inter(40),
               "odo": SimpleNamespace(font=font), "figure_baseline": 496.0, "label_baseline": 322.0}
        sc = SimpleNamespace(id="revenus", counter=cnt, start=512, end=576)
        film = SimpleNamespace(fmt=SimpleNamespace(width=1080), scenes=[sc], scene_at=lambda f: sc,
                               captions=SimpleNamespace(items=[]), plan=lambda: {})
        plan = vmod.pixel_plan(film, [], {"cues": []})
        frames = sorted(t["frame"] for t in plan["ink"] if t["kind"] == "counter")
        self.assertEqual(frames, list(range(534, 552)))


class TestOutroTailBothHalves(unittest.TestCase):
    """M6: the tail rule's « ≥ 20 dB down 22 frames on » half. A last hit
    that holds for a second and is then cut to silence ends quiet (its last
    100 ms pass) but never RANG OUT: it fails."""

    def test_held_then_cut(self):
        frames, S = 140, 1600
        t = np.arange(frames * S) / 48000
        x = np.zeros(frames * S)
        hit = slice(100 * S, 131 * S)
        x[hit] = 0.5 * np.sin(2 * np.pi * 220 * t[hit]) * np.linspace(1.0, 0.6, 31 * S)
        audio = np.stack([x, x], axis=1)
        r = vmod.outro_tail(audio, {"cues": [{"id": "end.last", "kind": "log", "frame": 100}]}, S)
        self.assertGreaterEqual(r["end_under_db"], 30.0)            # the end rule alone would pass it
        self.assertLess(r["decay_db"], 20.0)
        self.assertFalse(r["ok"])


if __name__ == "__main__":
    unittest.main()
