"""The owner's decisions after round 5 (2026-10-20) — architecture contract,
« Owner decisions after round 5 » and « Owner decision — end card stores +
site »:

  * the MAP CREDIT in the app's own wording (« © OpenStreetMap contributors ·
    © CARTO », carto_basemap_layer.dart:116), whole until the map has dimmed
    out (f767), in every format;
  * the END CARD: the mark · « Plus de clients, moins de gestion. » · « Sur
    l’App Store et Google Play » · « myweli.com », each line on its own
    beat-grid cue, the combined reading check at ≈ 16.7 cps;
  * 16:9: the push-in about the floor on the lower-journal and form-end
    shots (`camera.fill`), never over a caption; the lifts at the left
    column's full width where it helps; the 15-s form's hard cut at f193
    and no band-edge curtain after it."""

from __future__ import annotations

import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo import storyboard as sbmod  # noqa: E402
from promo import verify as vmod  # noqa: E402
from promo.fx.surface import new_surface  # noqa: E402
from promo.media import tools  # noqa: E402
from promo.scenes.clock import Clock  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent))
from test_scenes import EVENTS, EVENTS15  # noqa: E402

SB = sbmod.load()
STARTER = sbmod.DEFAULT_PATH.read_text(encoding="utf-8")
DART = tools.REPO / "mobile/lib/widgets/common/carto_basemap_layer.dart"
CLOCKS = {"30s": Clock(EVENTS, 960), "15s": Clock(EVENTS15, 512)}
HAVE_TAKES = tools.material_available() and tools.promo_takes_root() is not None
_FILMS: dict = {}


def problems(*overrides: str) -> list[str]:
    try:
        sbmod.loads(STARTER, overrides=overrides)
    except sbmod.StoryboardError as e:
        return e.problems
    return []


def film(cut: str, fid: str, *overrides: str):
    key = (cut, fid, overrides)
    if key not in _FILMS:
        from promo.scenes import Film
        _FILMS[key] = Film(sbmod.load(overrides=list(overrides)) if overrides else SB, cut, fid, CLOCKS[cut])
    return _FILMS[key]


def scene(fm, sid: str):
    return next(s for s in fm.scenes if s.id == sid)


def overlays(sc, f: int) -> dict:
    rec: dict = {"boxes": []}
    sc.draw_overlays(new_surface(*sc.ctx.size).getCanvas(), f, rec)
    return rec


def app_credit() -> str:
    """The credits CARTO's terms require, as the app writes them (`cartoCredits`),
    joined as the contract writes them: « … · … »."""
    m = re.search(r"const cartoCredits = \[(.*?)\];", DART.read_text(encoding="utf-8"), re.S)
    assert m, f"no `const cartoCredits` in {DART}"
    return " · ".join(re.findall(r"'([^']*)'", m.group(1)))


class TestMapCredit(unittest.TestCase):
    def test_the_apps_own_wording(self):
        """Round 5 drew « © OpenStreetMap, © CARTO »; the app credits « ©
        OpenStreetMap contributors » and « © CARTO » (the owner: use the
        app's wording)."""
        self.assertEqual(app_credit(), "© OpenStreetMap contributors · © CARTO")
        seen = 0
        for cut in SB.cuts:
            for sc in SB.cut_scenes(cut):
                if sc.get("credit"):
                    seen += 1
                    self.assertEqual(sc["credit"]["text"], app_credit(), f"{cut} {sc['id']}")
                    self.assertIn("carto_basemap_layer.dart:116", sc["credit"]["cite"])
        self.assertEqual(seen, 2)                                   # the page and AIR 2 (30 s)

    def test_whole_until_the_map_has_dimmed_out(self):
        """verify's rule, on records: whole from its first whole frame to the
        end of the map's last scene — round 5 faded it with the falling
        phone (AIR 2, f752–767)."""
        def rec(f, a, scene="page"):
            return {"f": f, "scene": scene, "boxes": [{"kind": "credit", "alpha": a, "rect": [0, 0, 1, 1]}]}
        spans = {"page": [640, 752], "air2": [752, 768]}
        ok = [rec(f, min(1.0, (f - 690) / 3)) for f in range(690, 752)] + [rec(f, 1.0, "air2") for f in range(752, 768)]
        self.assertEqual(vmod.credit_problems(ok, spans), [])
        faded = ok[:-16] + [rec(f, 1.0 - (f - 751) / 12, "air2") for f in range(752, 768)]
        self.assertRegex(vmod.credit_problems(faded, spans)[0], r"not whole on 16 frames .*\(f767\): f752–f767")
        gone = ok[:-2]                                               # off two frames early
        self.assertRegex(vmod.credit_problems(gone, spans)[0], r"f766–f767")
        self.assertRegex(vmod.credit_problems([], spans)[0], "never whole")
        self.assertEqual(vmod.credit_problems([], {}), [])



class TestEndCardSchema(unittest.TestCase):
    def test_the_site_line_is_read_not_fine_print(self):
        self.assertEqual({SB.formats[f].layout["type_px"]["site"] for f in SB.formats}, {40})
        found = problems("formats.9x16.layout.type_px.site=30")
        self.assertTrue(any("type_px.site" in p and "at least 40" in p for p in found), found)


class TestPerFormatValues(unittest.TestCase):
    """`formats: {16x9: {…}}` on any mapping of a scene: that format reads
    those keys, the others the mapping as written — one scene, re-laid out."""

    def test_resolved_per_format(self):
        j9 = next(s for s in SB.cut_scenes("15s", "9x16") if s["id"] == "journal")
        j16 = next(s for s in SB.cut_scenes("15s", "16x9") if s["id"] == "journal")
        cut9 = next(t for t in j9["timeline"] if "dissolve" in t)
        cut16 = next(t for t in j16["timeline"] if "dissolve" in t)
        self.assertEqual((cut9["curve"], cut16["curve"]), ("ease_in_out", "cut"))
        self.assertNotIn("formats", cut9)
        self.assertEqual([k["value"] for k in j16["camera"]["W"]], [128, 128, 667, 667, 667, 667, 667])
        self.assertEqual([k["value"] for k in j9["camera"]["W"]], [128, 128, 667, 667, 521.67, 521.67, 667])
        self.assertNotIn("fill", j9["camera"])
        self.assertEqual([k["value"] for k in j16["camera"]["fill"]], [1.0, 1.23])
        raw = next(s for s in SB.cut_scenes("15s") if s["id"] == "journal")
        self.assertIn("formats", raw["camera"])                                    # as written, untouched

    def test_an_unknown_format_is_refused(self):
        found = problems("scenes.15s.2.timeline.6.formats={17x9: {curve: cut}}")
        self.assertTrue(any("formats.17x9" in p and "is not a format" in p for p in found), found)
        found = problems("scenes.15s.2.timeline.6.formats=cut")
        self.assertTrue(any("must map format ids" in p for p in found), found)


class TestLiftColumns(unittest.TestCase):
    def test_a_place_may_have_its_own_columns_inside_the_safe_area(self):
        self.assertEqual(SB.formats["16x9"].layout["lift_y"]["card_on_floor"]["x"], [96, 1040])
        found = problems("formats.16x9.layout.lift_y.tile_row.x=[50, 1040]")
        self.assertTrue(any("lift_y.tile_row.x" in p and "safe area's columns" in p for p in found), found)
        found = problems("formats.16x9.layout.lift_y.tile_row.y=700")
        self.assertTrue(any("lift_y.tile_row" in p and "ONE of" in p for p in found), found)


class TestCaptionsClearOfThePhone(unittest.TestCase):
    def test_verify_reads_it_off_the_records(self):
        rec = {"f": 280, "phone": [846.0, 480.0, 1826.0, 1050.0],
               "boxes": [{"kind": "caption", "label": "slot:libre ?", "rect": [633.7, 401.7, 878.3, 472.7]}]}
        self.assertEqual(len(vmod.captions_over_phone([rec])), 1)                  # 7 px under « ? », 32 px across
        self.assertEqual(vmod.captions_over_phone([{**rec, "phone": [846.0, 486.0, 1826.0, 1050.0]}]), [])   # 13 px
        far = {**rec, "phone": [897.0, 520.0, 1826.0, 1050.0]}
        self.assertEqual(vmod.captions_over_phone([far]), [])
        self.assertEqual(vmod.captions_over_phone([{**rec, "phone": None}]), [])


@unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
class TestPushAboutTheFloor(unittest.TestCase):
    """16:9: on the lower journal and the form's end the camera pushes in
    about the floor, its window growing with the phone (`camera.fill`)."""

    def test_where_and_how_much(self):
        for cut, held in (("30s", (280, 284, 416, 436)), ("15s", (184, 196, 232))):
            j = scene(film(cut, "16x9"), "journal")
            self.assertTrue(all(k.frame % 4 == 0 for k in j.fill.keys), [k.frame for k in j.fill.keys])   # on the grid
            for f in held:
                self.assertAlmostEqual(j.fill(float(f)), 1.23, msg=f"{cut} f{f}")
                # pt 667 shows on the risen edge: the old 13:15 row (its last line 644 pt) stays under the band
                w = j.win(float(f))
                y = j.phone.map_point(0.0, 667.0, j.pose(float(f)), W=j.camera_W(float(f)), window=w)[1]
                self.assertAlmostEqual(y, w.edge, delta=0.5)
                self.assertAlmostEqual(w.edge, 1026 - (1026 - 639.263) * 1.23, delta=0.5)
            self.assertLess(j.win(float(held[0])).edge, 552)                     # round 5: 639
        for fid in ("9x16", "1x1"):
            for cut in ("30s", "15s"):
                self.assertFalse(scene(film(cut, fid), "journal").fill, (cut, fid))

    def test_every_cut_and_format_keeps_its_captions_clear(self):
        for cut in ("30s", "15s"):
            for fid in SB.formats:
                self.assertEqual(film(cut, fid).crowded_captions(), [], (cut, fid))

    def test_a_push_over_a_caption_is_refused(self):
        """At the owner's ~1.3 the slab's left edge reaches x 846 under « libre ? »
        (x ≤ 878), its top 20 px under the ink, and recedes over it on the glide
        to the form: the renderer refuses it (render.build_one) and verify (g)
        fails it."""
        over = ["scenes.30s.2.camera.formats.16x9.fill.1.value=1.3", "scenes.30s.2.camera.formats.16x9.fill.2.value=1.3",
                "scenes.30s.2.camera.formats.16x9.fill.5.value=1.3"]
        bad = film("30s", "16x9", *over).crowded_captions()
        self.assertEqual(bad[0]["caption"], "slot:libre\u202f?")                    # the glide to the form, f288
        self.assertIn("filled:rempli.", {b["caption"] for b in bad})               # its rise, f448–
        from promo.render import build_one
        import tempfile
        from promo.scenes import SceneError
        from unittest import mock
        with tempfile.TemporaryDirectory() as d, mock.patch("promo.render.render_audio", lambda sb, cut, out: CLOCKS[cut]):
            with self.assertRaisesRegex(SceneError, r"30s/16x9: on \d+ frames a caption comes within the phone's"):
                build_one(sbmod.load(overrides=over), "30s", "16x9", Path(d))

    def test_only_where_the_phone_stands_on_the_floor(self):
        from promo.scenes import SceneError
        with self.assertRaisesRegex(SceneError, r"camera.fill: a push-in about the floor .* in 9x16"):
            film("30s", "9x16", "scenes.30s.2.camera.fill=[{at: 5.1.2, value: 1.0}, {at: 5.2.2, value: 1.2}]")
        with self.assertRaisesRegex(SceneError, r"pushes IN"):
            film("30s", "16x9", "scenes.30s.2.camera.formats.16x9.fill.1.value=0.9")

    def test_the_snackbar_and_the_button_are_never_cropped(self):
        """« never cropping … the « Créer » button, the snackbar »: both are the
        app's text kept readable — in the text area, wholly in the window —
        on every frame they show; a deeper « rempli. » push (1.6) puts the
        snackbar under the band and verify (g) fails it."""
        for cut, frames in (("30s", (392, 400, 422, 436, 463)), ("15s", (196, 218, 232, 255))):
            for fid in SB.formats:
                sc = scene(film(cut, fid), "journal")
                for f in frames:
                    boxes = [b for b in overlays(sc, f)["boxes"] if b["kind"] == "app text"]
                    with self.subTest(cut=cut, fmt=fid, f=f):
                        self.assertEqual(len(boxes), 1)
                        self.assertEqual(vmod.outside_safe([{"f": f, "boxes": boxes}], SB.formats[fid])[1], [])
        deep = scene(film("30s", "16x9", "scenes.30s.2.camera.zoom.4.value=1.6"), "journal")
        boxes = [b for b in overlays(deep, 460)["boxes"] if b["kind"] == "app text"]
        self.assertLess(boxes[0]["shown"], 0.99)
        self.assertEqual(len(vmod.outside_safe([{"f": 460, "boxes": boxes}], SB.formats["16x9"])[1]), 1)

    def test_a_touch_is_never_cropped(self):
        """On a pushed frame (the record's zoom > 1) every disc is whole —
        verify (g) fails one that is not; a touch-down cropped on an unpushed
        frame is the framing's own (the Revenus « Mois » tap, since round 1)
        and is reported."""
        disc = {"kind": "touch", "label": "tap-x", "down": True, "shown": 0.6, "rect": [0, 0, 1, 1]}
        pushed = vmod.touches_cropped([{"f": 1, "zoom": 1.23, "boxes": [disc]}])
        self.assertEqual([(c["frame"], c["pushed"]) for c in pushed], [(1, True)])
        held = vmod.touches_cropped([{"f": 2, "zoom": 1.23, "boxes": [{**disc, "down": False}]}])
        self.assertEqual([c["pushed"] for c in held], [True])                       # every frame of the push
        framed = vmod.touches_cropped([{"f": 3, "zoom": 1.0, "boxes": [disc]}])
        self.assertEqual([c["pushed"] for c in framed], [False])                    # reported, not failed
        self.assertEqual(vmod.touches_cropped([{"f": 4, "zoom": 1.0, "boxes": [{**disc, "down": False}]}]), [])
        for cut, frames in (("30s", (144, 176, 280, 320, 336, 352, 384, 400)), ("15s", (64, 88, 168, 196))):
            for fid in SB.formats:
                sc = scene(film(cut, fid), "journal")
                for f in frames:
                    downs = [b for b in overlays(sc, f)["boxes"] if b["kind"] == "touch" and b["down"]]
                    with self.subTest(cut=cut, fmt=fid, f=f):
                        self.assertEqual(len(downs), 1)
                        self.assertGreaterEqual(downs[0]["shown"], 0.99)


class TestLiftsAndTheHiddenRow(unittest.TestCase):
    """16:9's 944-px « Arrivé » lift magnifies Fatou B.'s card 1.42×: its
    small end time « 13:15 » is then the old row's large « 13:15 » at the
    same pixel size, and the first full verify of this round found « the old
    row » inside the flying card (30-s f233 / f250, 15-s f145 / f156 —
    Fatou B.'s card in the MP4, not the old row). A lifted card is a known
    real card: the renderer refuses one whose SOURCE touches a hidden row,
    and verify leaves the lifts' boxes out of its search for the row."""

    @unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
    def test_a_lift_on_the_hidden_row_is_refused(self):
        from promo.scenes import SceneError
        with self.assertRaisesRegex(SceneError, r"lifts?.*arrive-card .* shows part of the hidden row « 13:15 Yao K."):
            film("30s", "9x16", "scenes.30s.2.lifts.0.rect_pt=[15.67, 600.0, 386.0, 650.0]")
        self.assertTrue(scene(film("30s", "16x9"), "journal").lifts)                # as written: off the row

    @unittest.skipUnless(HAVE_TAKES, "the recorded takes are not on this machine")
    def test_verify_leaves_the_lifted_cards_out(self):
        import numpy as np
        from promo import pixels
        hid = SB.cut_scenes("30s")[2]["hidden"][0]
        row = vmod.HiddenRow("take1b", hid["label"], hid["rect_pt"], 31.6, [52], 1.791)
        try:
            # a frame of paper with the row pasted at the film's scale, inside a lift's box, the window wide open
            L = np.full((1080, 1920), 250.0)
            T = row.template_at(row.base)
            L[900:900 + T.shape[0], 500:500 + T.shape[1]] = T
            from promo.fx.phone import Window
            win = Window(screen_x=1088.0, top=84.0, band_fade=30.0, floor=1026.0, floor_fade=24.0)
            r = {"rect": [1152.5, 1070.1, 1735.1, 1126.2], "zoom": 1.0, "whip": False, "alpha": 0.0, "picture": 52}
            seen = row.measure(L, r, win, 1920)
            self.assertGreaterEqual(seen["found_visible"], 0.5)                          # found: the guard's teeth
            box = [480.0, 880.0, 520.0 + T.shape[1], 920.0 + T.shape[0]]
            left_out = row.measure(L, {**r, "lifts": [box]}, win, 1920)
            self.assertEqual(left_out["found_visible"], 0.0)
        finally:
            row.close()


class TestTheFormCut(unittest.TestCase):
    def test_a_declared_cut_is_held_to_a_cuts_rule(self):
        t = [{"frame": 193, "kind": "cut (declared, in the phone)", "into": "journal"}]
        self.assertEqual(vmod.join_problems(t, {193: 30.0}), [])
        self.assertRegex(vmod.join_problems(t, {193: 0.5})[0], "called a cut")


if __name__ == "__main__":
    unittest.main()
