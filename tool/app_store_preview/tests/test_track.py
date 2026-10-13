"""Following a drag in the picture: how far the content under the finger has
moved, on pictures whose answer is known. The whole chain — a take, its
frames, track.json, the touch point in the composed film — is in
tests/test_e2e.py."""

from __future__ import annotations

import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np
from PIL import Image

import edit as editlist
import track
from tests.test_edit import CHANGE, NOISE, SB, scan_of

SIZE = (300, 400)      # rows, columns
PX = 1.0               # pixels per point here: the patch is 120 x 48


def texture(seed: int = 3) -> np.ndarray:
    return np.random.default_rng(seed).integers(0, 256, SIZE).astype(np.float32)


def moved(picture: np.ndarray, dx: int = 0, dy: int = 0) -> np.ndarray:
    """The picture with its content dx to the right and dy down; what comes
    in at the edge is flat."""
    out = np.full_like(picture, 128.0)
    h, w = picture.shape
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = \
        picture[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


class Follow(unittest.TestCase):
    def test_the_content_under_the_finger_is_found_where_it_went(self):
        ref = texture()
        frames = [moved(ref, dx=s) for s in (0, 7, 20, 20, 35, 61)]
        shifts, why = track.follow(ref, frames, (150, 150), "x", 1, 80, PX)
        self.assertEqual([s for s, _ in shifts], [0.0, 7.0, 20.0, 20.0, 35.0, 61.0])
        self.assertEqual([e for _, e in shifts], [0.0] * 6)
        self.assertEqual(why, "")

    def test_the_other_way_and_the_other_axis(self):
        ref = texture()
        left, _ = track.follow(ref, [moved(ref, dx=-s) for s in (5, 30)], (200, 150), "x", -1, 60, PX)
        self.assertEqual([s for s, _ in left], [5.0, 30.0])
        up, _ = track.follow(ref, [moved(ref, dy=-s) for s in (5, 30, 90)], (200, 200), "y", -1, 100, PX)
        self.assertEqual([s for s, _ in up], [5.0, 30.0, 90.0])
        down, _ = track.follow(ref, [moved(ref, dy=s) for s in (12,)], (200, 100), "y", 1, 100, PX)
        self.assertEqual([s for s, _ in down], [12.0])
        # looked for the wrong way, it is not there
        wrong, why = track.follow(ref, [moved(ref, dx=-30)], (200, 150), "x", 1, 60, PX)
        self.assertEqual((wrong, why), ([], "lost after 0 frames: what was under the finger is not in the picture"))

    def test_a_picture_that_turns_back_is_followed_back(self):
        ref = texture()
        shifts, _ = track.follow(ref, [moved(ref, dy=-s) for s in (10, 40, 55, 50, 44)], (200, 200), "y", -1, 60, PX)
        self.assertEqual([s for s, _ in shifts], [10.0, 40.0, 55.0, 50.0, 44.0])

    def test_it_is_looked_for_a_little_past_the_end_of_the_logged_path(self):
        """A card that snaps shut goes further than the finger did: seen, so
        that edit.followed_path can tell the finger has let go."""
        ref = texture()
        reach = 30
        past = int(track.BEYOND_PT * PX)
        shifts, why = track.follow(ref, [moved(ref, dx=reach + past)], (150, 150), "x", 1, reach, PX)
        self.assertEqual(([s for s, _ in shifts], why), ([float(reach + past)], ""))
        shifts, why = track.follow(ref, [moved(ref, dx=reach + past + 1)], (150, 150), "x", 1, reach, PX)
        self.assertEqual(shifts, [])
        self.assertIn("lost after 0 frames", why)

    def test_nothing_to_recognise_is_said_not_guessed(self):
        flat = np.full(SIZE, 240.0, dtype=np.float32)
        self.assertEqual(track.follow(flat, [flat], (150, 150), "x", 1, 60, PX),
                         ([], "nothing to recognise under the finger: the picture there is flat"))
        faint = flat + np.random.default_rng(1).normal(0, track.MIN_TEXTURE * 0.9, SIZE).astype(np.float32)
        self.assertEqual(track.follow(faint, [faint], (150, 150), "x", 1, 60, PX)[0], [])
        clear = flat + np.random.default_rng(1).normal(0, track.MIN_TEXTURE * 1.2, SIZE).astype(np.float32)
        self.assertEqual([s for s, _ in track.follow(clear, [clear], (150, 150), "x", 1, 60, PX)[0]], [0.0])

    def test_what_is_no_longer_in_the_picture_is_lost_and_what_came_before_is_kept(self):
        ref = texture()
        frames = [moved(ref, dx=10), moved(ref, dx=25), texture(seed=9), moved(ref, dx=40)]
        shifts, why = track.follow(ref, frames, (150, 150), "x", 1, 80, PX)
        self.assertEqual([s for s, _ in shifts], [10.0, 25.0])
        self.assertEqual(why, "lost after 2 frames: what was under the finger is not in the picture")
        # a lossy copy is still the content: a few levels of noise are not a loss
        noisy = moved(ref, dx=10) + np.random.default_rng(5).normal(0, 3, SIZE).astype(np.float32)
        shifts, why = track.follow(ref, [noisy], (150, 150), "x", 1, 80, PX)
        self.assertEqual(([s for s, _ in shifts], why), ([10.0], ""))
        self.assertLess(shifts[0][1], track.MAX_ERROR)

    def test_the_patch_is_the_content_around_the_finger_and_no_more(self):
        """Something else moving elsewhere on the screen does not pull the
        reading: only what is within 60 pt along and 24 pt across counts."""
        ref = texture()
        frame = moved(ref, dx=20)
        frame[:60] = texture(seed=8)[:60]             # the top of the screen is something else entirely
        frame[250:] = 0.0                             # and so is the bottom
        shifts, _ = track.follow(ref, [frame], (150, 150), "x", 1, 80, PX)
        self.assertEqual([s for s, _ in shifts], [20.0])
        self.assertEqual(shifts[0][1], 0.0)
        frame[140:160, 100:260] = 0.0                 # …but a stripe through the patch itself is
        shifts, _ = track.follow(ref, [frame], (150, 150), "x", 1, 80, PX)
        self.assertGreater(shifts[0][1] if shifts else 99.0, 5.0)

    def test_a_finger_near_the_edge_of_the_screen(self):
        ref = texture()
        shifts, why = track.follow(ref, [moved(ref, dx=30)], (10, 5), "x", 1, 60, PX)
        self.assertEqual(([s for s, _ in shifts], why), ([30.0], ""))


class ReadDrags(unittest.TestCase):
    """The wiring around `follow`: which frames of the take are looked at,
    against which picture, along which axis — with the frame export (Swift)
    stood in for by pictures made here."""

    SCREEN = (874, 402)       # rows, columns: one pixel a point

    def setUp(self):
        self.work = Path(tempfile.mkdtemp(prefix="preview-track-"))
        self.addCleanup(shutil.rmtree, self.work, ignore_errors=True)
        rest = np.random.default_rng(4).integers(0, 256, self.SCREEN).astype(np.float32)
        # the take: at rest; a drag upwards answered in six frames (the list
        # 10, 30, 50, 70, 80, 80 pt up), a still frame, then the list 20 pt
        # back down; five seconds later something else entirely
        ups = [10, 30, 50, 70, 80, 80]
        rows = [(1800 + 10 * k, CHANGE) for k in range(6)] + [(1900, NOISE), (1950, CHANGE), (4800, CHANGE)]
        self.scan = scan_of(rows)
        self.scan["video"].update(width=self.SCREEN[1], height=self.SCREEN[0])
        other = np.random.default_rng(5).integers(0, 256, self.SCREEN).astype(np.float32)
        self.pictures = [rest] + [moved(rest, dy=-u) for u in ups] + [moved(rest, dy=-80), moved(rest, dy=-60), other]
        self.sb = copy.deepcopy(SB)
        self.sb["shots"] = [
            {"id": "B", "caption": "two", "gestures": [{"id": "drag-b", "kind": "drag", "rest_after_s": 0.5}]},
            {"id": "C", "caption": "three", "caption_after": {"gesture": "drag-b", "delay_s": 0.5}, "gestures": []}]
        self.log = {"device_points": [402, 874], "gestures": [
            {"id": "drag-b", "kind": "drag", "near_s": 3.0, "path": [[200, 600, 0], [200, 500, 160]]},
            {"kind": "tap", "near_s": 8.0, "film": False}]}
        self.asked: list[int] = []

    def export(self, name, command, take, *args):
        """What `conform export` does, for a list of one-frame holds."""
        self.assertEqual((name, command, args[0], args[2]), ("conform", "export", "--segments", "--out"))
        segments = json.loads(Path(args[1]).read_text())["segments"]
        out = Path(args[3])
        pts = [f["pts"] for f in self.scan["frames"]]
        sources = {}
        for s in segments:
            self.assertEqual((s["kind"], s["frames"]), ("hold", 1))
            i = pts.index(s["src_at"])
            self.asked.append(i)
            Image.fromarray(self.pictures[i].astype(np.uint8)).save(out / f"src_{i:06d}.png")
            sources[str(i)] = {"pts": s["src_at"], "file": f"src_{i:06d}.png"}
        (out / "manifest.json").write_text(json.dumps({"sources": sources}))

    def read(self) -> dict:
        with mock.patch.object(track.swifttools, "run", self.export):
            return track.read_drags(Path("take.mov"), self.scan, self.log, self.sb, self.work)

    def test_each_drag_is_read_on_the_frames_of_its_own_burst(self):
        got = self.read()
        self.assertEqual(list(got), ["drag-b"])
        # the picture before the drag, then every frame that changed in its
        # burst — not the still one in the middle, not what came five seconds later
        self.assertEqual(self.asked, [0, 1, 2, 3, 4, 5, 6, 8])
        self.assertEqual(got["drag-b"], {
            "axis": "y", "sign": -1, "ref": 0, "error": 0.0, "turn": 1950,
            "frames": [[1800, 10.0], [1810, 30.0], [1820, 50.0], [1830, 70.0], [1840, 80.0], [1850, 80.0],
                       [1950, 60.0]]})
        self.assertEqual(list(self.work.iterdir()), [])          # the pictures were only needed to measure

    def test_the_axis_and_the_way_come_from_the_logged_path(self):
        self.log["gestures"][0]["path"] = [[200, 600, 0], [205, 700, 160]]       # downwards, a little askew
        self.pictures[1:9] = [moved(self.pictures[0], dy=d) for d in (10, 30, 50, 70, 80, 80, 80, 90)]
        got = self.read()["drag-b"]
        self.assertEqual((got["axis"], got["sign"], got["turn"]), ("y", 1, None))
        self.assertEqual([s for _, s in got["frames"]], [10.0, 30.0, 50.0, 70.0, 80.0, 80.0, 90.0])
        self.log["gestures"][0]["path"] = [[200, 600, 0], [100, 590, 160]]       # leftwards
        self.pictures[1:9] = [moved(self.pictures[0], dx=-d) for d in (10, 30, 50, 70, 80, 80, 80, 90)]
        got = self.read()["drag-b"]
        self.assertEqual((got["axis"], got["sign"]), ("x", -1))
        self.assertEqual([s for _, s in got["frames"]], [10.0, 30.0, 50.0, 70.0, 80.0, 80.0, 90.0])

    def test_a_drag_that_cannot_be_read_says_why_and_stops_nothing(self):
        self.pictures[0] = np.full(self.SCREEN, 250.0, dtype=np.float32)          # a blank screen under the finger
        got = self.read()["drag-b"]
        self.assertEqual((got["frames"], got["turn"]), ([], None))
        self.assertEqual(got["why"], "nothing to recognise under the finger: the picture there is flat")
        # …and edit.locate then times it by the log, and says so
        drag = editlist.locate(self.scan, self.log, self.sb, tracks={"drag-b": got}).gestures[0]
        self.assertIn("NOT followed in the picture (nothing to recognise under the finger", drag.how)

    def test_a_take_with_no_drag_asks_for_no_picture(self):
        self.sb["shots"][0]["gestures"][0]["kind"] = "tap"
        self.log["gestures"][0] = {"id": "drag-b", "kind": "tap", "near_s": 3.0, "at": [200, 600]}
        self.assertEqual((self.read(), self.asked), ({}, []))


class Turned(unittest.TestCase):
    def test_the_first_frame_clearly_behind_the_furthest(self):
        self.assertIsNone(track.turned([]))
        self.assertIsNone(track.turned([[10, 5.0], [20, 30.0], [30, 30.0], [40, 29.5]]))   # within a point: at rest
        self.assertEqual(track.turned([[10, 5.0], [20, 30.0], [30, 28.9], [40, 20.0]]), 30)
        self.assertEqual(track.turned([[10, 5.0], [20, 30.0], [30, 29.0], [40, 28.9]]), 40)


if __name__ == "__main__":
    unittest.main()
