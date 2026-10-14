"""The command line's own refusals, the helpers' refusals of a bad request,
and two things the README says the tool does not do."""

from __future__ import annotations

import ast
import atexit
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from PIL import Image

import swifttools
from tests.support import TOOL

WORK = Path(tempfile.mkdtemp(prefix="preview-cli-"))
atexit.register(shutil.rmtree, WORK, ignore_errors=True)


def preview(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["python3", str(TOOL / "preview.py"), *args], capture_output=True, text=True)


class Command(unittest.TestCase):
    def test_a_take_that_is_not_there_stops_the_build(self):
        (WORK / "g.json").write_text(json.dumps({"device_points": [402, 874], "gestures": []}))
        r = preview("build", "--take", str(WORK / "nothing.mov"), "--gestures", str(WORK / "g.json"),
                    "--out", str(WORK / "out"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("no such take", r.stderr)
        self.assertFalse((WORK / "out").exists())

    def test_a_gesture_log_that_cannot_be_read_stops_the_build(self):
        (WORK / "broken.json").write_text("{ not json")
        r = preview("build", "--take", str(WORK / "nothing.mov"), "--gestures", str(WORK / "broken.json"),
                    "--out", str(WORK / "out"))
        self.assertEqual(r.returncode, 1)
        self.assertIn("cannot read", r.stderr)

    def test_a_build_that_is_refused_leaves_no_earlier_result_behind(self):
        """Refused before the take is even looked at — a variant the
        storyboard does not have, a log that cannot be read, a take that is
        not there: the film, the sheet and the PASS report of an earlier
        build in that folder are gone all the same."""
        (WORK / "g2.json").write_text(json.dumps({"device_points": [402, 874], "gestures": []}))
        (WORK / "broken2.json").write_text("{ not json")
        results = ("preview.mp4", "preview-rehearsal.mp4", "verify.txt", "poster.png", "poster-decoded.png",
                   "contact-sheet.png", "edit.json", "cuts.txt", "track.json", "build.json")
        refusals = {
            "variant": (["--variant", "nope", "--gestures", str(WORK / "g2.json")], "the storyboard has no variant `nope`"),
            "log": (["--gestures", str(WORK / "broken2.json")], "cannot read"),
            "take": (["--gestures", str(WORK / "g2.json")], "no such take"),
        }
        for name, (args, why) in refusals.items():
            folder = WORK / f"earlier-{name}"
            folder.mkdir()
            for result in results:
                (folder / result).write_text("an earlier build's")
            (folder / "notes.txt").write_text("not a result of a build")
            r = preview("build", "--take", str(WORK / "nothing.mov"), "--out", str(folder), *args)
            self.assertEqual(r.returncode, 1, name)
            self.assertIn(why, r.stderr)
            self.assertEqual(sorted(p.name for p in folder.iterdir()), ["notes.txt"], name)

    def test_a_self_test_that_runs_no_test_is_a_failure(self):
        """An empty sweep must not read as a clean one."""
        r = preview("selftest", "--pattern", "there_is_no_such_test_*.py")
        self.assertEqual(r.returncode, 1)
        self.assertIn("Ran 0 tests", r.stderr)


class Conform(unittest.TestCase):
    """`conform` asked for something it cannot do exactly says so."""

    @classmethod
    def setUpClass(cls):
        folder = WORK / "take"
        folder.mkdir()
        for name, shade in (("a", 250), ("b", 20)):
            Image.new("RGB", (96, 208), (shade,) * 3).save(folder / f"{name}.png")
        (folder / "clip.json").write_text(json.dumps({
            "width": 96, "height": 208, "timescale": 600, "end": 600,
            "frames": [{"pts": 0, "file": "a.png"}, {"pts": 100, "file": "b.png"}, {"pts": 400, "file": "a.png"}]}))
        cls.take = folder / "take.mov"
        swifttools.run("testclip", folder / "clip.json", "--out", cls.take)

    def refused(self, *args) -> str:
        r = swifttools.run("conform", *args, check=False)
        self.assertEqual(r.returncode, 1, args)
        return r.stderr

    def export(self, segments: list[dict]) -> str:
        (WORK / "segments.json").write_text(json.dumps({"fps": 30, "segments": segments}))
        return self.refused("export", self.take, "--segments", WORK / "segments.json", "--out", WORK / "exported")

    def test_a_range_that_is_not_whole_frames(self):
        self.assertIn("7 ticks is not a whole number of 1/30 s frames",
                      self.export([{"kind": "live", "src_in": 0, "src_out": 7}]))

    def test_a_range_that_ends_before_it_starts(self):
        self.assertIn("src_out is not after src_in", self.export([{"kind": "live", "src_in": 40, "src_out": 40}]))

    def test_a_hold_of_no_frames_and_a_kind_it_does_not_know(self):
        self.assertIn("a hold needs at least one frame", self.export([{"kind": "hold", "src_at": 0, "frames": 0}]))
        self.assertIn("kind must be `live` or `hold`", self.export([{"kind": "dissolve", "src_at": 0, "frames": 3}]))
        self.assertIn("missing integer `frames`", self.export([{"kind": "hold", "src_at": 0}]))

    def test_levels_the_wrong_way_round(self):
        self.assertIn("need 0 <= --soft < --strong <= 254",
                      self.refused("scan", self.take, "--out", WORK / "scan.json", "--soft", 70, "--strong", 64))

    def test_a_flag_it_does_not_have(self):
        self.assertIn("unknown flag --speed", self.refused("scan", self.take, "--out", WORK / "scan.json", "--speed", 2))

    def test_a_pair_of_frames_the_take_does_not_have_or_in_the_wrong_order(self):
        (WORK / "pairs.json").write_text(json.dumps({"pairs": [[0, 9]]}))
        self.assertIn("the take has no frame 9",
                      self.refused("diff", self.take, "--pairs", WORK / "pairs.json", "--out", WORK / "d.json"))
        (WORK / "pairs.json").write_text(json.dumps({"pairs": [[2, 1]]}))
        self.assertIn("a pair is [earlier, later] frame numbers",
                      self.refused("diff", self.take, "--pairs", WORK / "pairs.json", "--out", WORK / "d.json"))

    def test_the_two_levels_a_change_is_measured_by(self):
        """`soft` counts the pixels that moved by more than 16 levels,
        `strong` those that moved by more than 64 — what README « What counts
        as a change » and edit.py's thresholds are stated in. A patch 40
        levels lighter than its ground is soft and not strong; one 100
        levels lighter is both. Counted to the pixel."""
        folder = WORK / "levels"
        folder.mkdir()
        ground = Image.new("RGB", (96, 208), (120, 120, 120))
        faint, clear = ground.copy(), ground.copy()
        faint.paste((160, 160, 160), (16, 16, 48, 48))
        clear.paste((220, 220, 220), (48, 112, 80, 144))
        for name, im in (("ground", ground), ("faint", faint), ("clear", clear)):
            im.save(folder / f"{name}.png")
        (folder / "clip.json").write_text(json.dumps({
            "width": 96, "height": 208, "timescale": 600, "end": 600,
            "frames": [{"pts": 0, "file": "ground.png"}, {"pts": 100, "file": "faint.png"},
                       {"pts": 200, "file": "ground.png"}, {"pts": 300, "file": "clear.png"}]}))
        swifttools.run("testclip", folder / "clip.json", "--out", folder / "take.mov")
        swifttools.run("conform", "scan", folder / "take.mov", "--out", folder / "scan.json")
        scan = json.loads((folder / "scan.json").read_text())
        self.assertEqual(scan["levels"], {"soft": 16, "strong": 64})
        self.assertEqual([(f["soft"], f["strong"]) for f in scan["frames"]],
                         [(0, 0), (32 * 32, 0), (32 * 32, 0), (32 * 32, 32 * 32)])
        self.assertEqual([f.get("box") for f in scan["frames"]], [None, None, None, [48, 112, 80, 144]])
        # asked for other levels, the same pictures count otherwise
        swifttools.run("conform", "scan", folder / "take.mov", "--out", folder / "scan2.json", "--soft", 50, "--strong", 150)
        scan = json.loads((folder / "scan2.json").read_text())
        self.assertEqual([(f["soft"], f["strong"]) for f in scan["frames"]], [(0, 0), (0, 0), (0, 0), (32 * 32, 0)])

    def test_what_it_does_do_on_the_same_take(self):
        """The control: the same take, asked properly, is scanned, compared
        and exported — the refusals above are about the request."""
        swifttools.run("conform", "scan", self.take, "--out", WORK / "scan.json")
        scan = json.loads((WORK / "scan.json").read_text())
        self.assertEqual([f["pts"] for f in scan["frames"]], [0, 100, 400])
        self.assertEqual([f["strong"] for f in scan["frames"]], [0, 96 * 208, 96 * 208])   # every pixel, both times
        (WORK / "pairs.json").write_text(json.dumps({"pairs": [[0, 2], [0, 1]]}))
        swifttools.run("conform", "diff", self.take, "--pairs", WORK / "pairs.json", "--out", WORK / "d.json")
        pairs = json.loads((WORK / "d.json").read_text())["pairs"]
        self.assertEqual([(p["a"], p["b"], p["strong"]) for p in pairs], [(0, 2, 0), (0, 1, 96 * 208)])
        (WORK / "segments.json").write_text(json.dumps({"fps": 30, "segments": [
            {"kind": "live", "src_in": 60, "src_out": 160}, {"kind": "hold", "src_at": 399, "frames": 2},
            {"kind": "hold", "src_at": 400, "frames": 1}]}))
        swifttools.run("conform", "export", self.take, "--segments", WORK / "segments.json", "--out", WORK / "ok")
        manifest = json.loads((WORK / "ok" / "manifest.json").read_text())
        # instants 60, 80, 100, 120, 140 -> frames 0, 0, 1, 1, 1; 399 is still frame 1, 400 is frame 2
        self.assertEqual(manifest["film"], [0, 0, 1, 1, 1, 1, 1, 2])
        self.assertEqual(sorted(manifest["sources"]), ["0", "1", "2"])


class WhatTheToolDoesNotDo(unittest.TestCase):
    """The README says nothing is installed and ffmpeg is not used. That is a
    denial, and a denial rots: this reads the sources."""

    # every program the tool or its tests start, and why
    LAUNCHED = {
        "xcrun": "swiftc and avmediainfo, from Xcode",
        "python3": "the tests run the command line",
        "afconvert": "one test makes a sound-only file (macOS)",
        "git": "tests/mutations.py checks the tree is clean",
        "rsvg-convert": "the stills' composer rasterises the mark",
    }

    def programs(self) -> set[str]:
        found: set[str] = set()
        sources = list(TOOL.glob("*.py")) + list((TOOL / "tests").glob("*.py")) + [
            TOOL.parent / "app_store_screenshots" / "compose.py"]
        self.assertGreater(len(sources), 12)                 # an empty sweep must not read as a clean one
        for path in sources:
            for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
                if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)
                        and node.func.attr in ("run", "Popen", "check_output", "call", "system")
                        and isinstance(node.func.value, ast.Name) and node.func.value.id in ("subprocess", "os")):
                    continue
                first = node.args[0] if node.args else None
                if isinstance(first, ast.List) and first.elts:
                    head = first.elts[0]
                    if isinstance(head, ast.Constant) and isinstance(head.value, str):
                        found.add(head.value)
                    else:
                        # a computed program: the compiled helper (swifttools) or this interpreter
                        found.add(ast.unparse(head))
                else:
                    found.add(ast.unparse(first) if first is not None else "?")
        return found

    def test_only_what_is_already_on_the_mac_is_started(self):
        computed = {"str(binary(name))", "sys.executable"}
        self.assertEqual(self.programs() - computed, set(self.LAUNCHED))

    def test_no_installer_and_no_ffmpeg_in_the_sources(self):
        banned = ("ffmpeg", "ffprobe", "brew", "pip", "npm")
        for path in list(TOOL.glob("*.py")) + list((TOOL / "swift").glob("*.swift")):
            tree_free = path.read_text(encoding="utf-8")
            if path.suffix == ".py":
                # code only: names and string constants, not comments or docstrings
                tree = ast.parse(tree_free)
                docstrings = {id(n.body[0].value) for n in ast.walk(tree)
                              if isinstance(n, (ast.Module, ast.FunctionDef, ast.ClassDef)) and n.body
                              and isinstance(n.body[0], ast.Expr) and isinstance(n.body[0].value, ast.Constant)}
                words = [n.value for n in ast.walk(tree)
                         if isinstance(n, ast.Constant) and isinstance(n.value, str) and id(n) not in docstrings]
                words += [n.id for n in ast.walk(tree) if isinstance(n, ast.Name)]
            else:
                words = [line.split("//")[0] for line in tree_free.splitlines()]
            for word in words:
                for name in banned:
                    self.assertNotRegex(word, rf"(?<![A-Za-z]){name}(?![A-Za-z])", f"{path.name}: {word[:60]!r}")


if __name__ == "__main__":
    unittest.main()
