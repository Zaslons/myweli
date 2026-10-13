"""The checker, watched refusing.

Each test writes a film that is wrong in one way — or changes a few header
bytes of a good one — and requires `verify` to name exactly that fault. A
good file, made by another writer than the film's, must pass.
"""

from __future__ import annotations

import atexit
import hashlib
import json
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np
from PIL import Image, ImageDraw

import mp4
import swifttools
import verify
from tests.support import TOOL
from tests.test_edit import SB

T = 600
WORK = Path(tempfile.mkdtemp(prefix="preview-verify-"))
atexit.register(shutil.rmtree, WORK, ignore_errors=True)
CLIPS: dict[str, Path] = {}


def film_clip(name: str, frames: int = 450, step: int = 20, size=(886, 1920), ext: str = "mp4",
              flat: bool = False, noise: float = 0.0, pts: list[int] | None = None, **knobs) -> Path:
    """A 15 s film, right unless a knob says otherwise (see TestClip.swift).
    `noise`: that share of the picture's height is pure noise, and every
    frame has another — nothing an encoder can save on."""
    if name in CLIPS:
        return CLIPS[name]
    folder = WORK / name
    folder.mkdir(parents=True, exist_ok=True)
    rng = np.random.default_rng(5)
    pictures = []
    for k in range(4):
        im = Image.new("RGB", size, (250, 250, 250))
        if noise:
            band = rng.integers(0, 256, (round(size[1] * noise), size[0], 3), dtype=np.uint8)
            im.paste(Image.fromarray(band, "RGB"), (0, 0))
        elif not flat:
            d = ImageDraw.Draw(im)
            for _ in range(160):
                x, y = int(rng.integers(0, size[0] - 80)), int(rng.integers(0, size[1] - 30))
                shade = int(rng.integers(0, 200))
                d.rectangle((x, y, x + int(rng.integers(8, 80)), y + int(rng.integers(4, 28))), fill=(shade,) * 3)
        im.save(folder / f"p{k}.png")
        pictures.append(f"p{k}.png")
    times = pts if pts is not None else [i * step for i in range(frames)]
    clip = {"width": size[0], "height": size[1], "timescale": T, "end": knobs.pop("end", times[-1] + step),
            "audio": True, "bitrate": 6_000_000,
            "frames": [{"pts": t, "file": pictures[(i if noise else i // 15) % 4]} for i, t in enumerate(times)]}
    clip.update(knobs)
    (folder / "clip.json").write_text(json.dumps(clip))
    out = folder / f"{name}.{ext}"
    swifttools.run("testclip", folder / "clip.json", "--out", out)
    CLIPS[name] = out
    return out


def failed(path: Path, poster: Path | None = None, sb: dict = SB) -> set[str]:
    return {c.name for c in verify.verify(path, sb, poster) if not c.ok}


def patched(source: Path, name: str, patch) -> Path:
    """A copy of a good film with a few header bytes changed."""
    data = bytearray(source.read_bytes())
    patch(data)
    out = WORK / f"{name}.mp4"
    out.write_bytes(data)
    return out


class VerifyRefuses(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.good = film_clip("good")

    def test_a_right_file_from_another_writer_passes(self):
        self.assertEqual(failed(self.good), set())

    def test_a_take_as_the_recorder_writes_it(self):
        """.mov, capture-sized, a frame only when the picture changes, no
        sound: everything the raw take is, the film must not be."""
        pts = [0, 244, 250, 258, 1267, 1498, 1508, 1518, 2388, 3192]          # the probe's own rhythm
        take = film_clip("take", size=(1206, 2622), ext="mov", pts=pts, end=4976, audio=False, profile="high")
        self.assertEqual(failed(take), {
            "container",                 # QuickTime
            "tracks", "sound track",     # no sound
            "size",                      # 1206 x 2622
            "profile and level",         # a capture-sized picture is past Level 4.0
            "every frame is 1/30 s", "frame rate",
            "frame count", "duration",
            "video bit rate"})           # a take is mostly a still screen

    def test_no_sound_track(self):
        self.assertEqual(failed(film_clip("no-sound", audio=False)), {"tracks", "sound track"})

    def test_14_9_seconds(self):
        self.assertEqual(failed(film_clip("short", frames=447)), {"frame count", "duration"})

    def test_30_1_seconds(self):
        self.assertEqual(failed(film_clip("long", frames=903)), {"frame count", "duration"})

    def test_a_length_apple_takes_but_the_storyboard_does_not_say(self):
        self.assertEqual(failed(film_clip("sixteen-seconds", frames=480)), {"frame count", "duration"})

    def test_a_length_the_storyboard_says_but_apple_does_not_take(self):
        """The film is exactly as long as its storyboard — and 0.1 s short of
        the App Store's minimum."""
        sb = {**SB, "film": {**SB["film"], "duration_s": 14.9}}
        self.assertEqual(failed(film_clip("short", frames=447), sb=sb), {"duration"})
        # …and the other end: 30.1 s, as its storyboard says, and 0.1 s past the maximum
        sb = {**SB, "film": {**SB["film"], "duration_s": 30.1}}
        self.assertEqual(failed(film_clip("long", frames=903), sb=sb), {"duration"})

    def test_a_size_off_by_one_pixel(self):
        """Asked for 885 wide, AVFoundation writes 884 without a word (H.264
        4:2:0 has no odd sizes); a header can still claim 887."""
        narrow = film_clip("narrow", size=(885, 1920))
        self.assertEqual(mp4.read(narrow)["tracks"][0]["entries"][0]["sps"]["width"], 884)
        self.assertEqual(failed(narrow), {"size"})
        short = film_clip("short-by-a-row", size=(886, 1919))
        self.assertEqual(mp4.read(short)["tracks"][0]["entries"][0]["sps"]["height"], 1918)
        self.assertEqual(failed(short), {"size"})

    def test_a_header_that_claims_another_size(self):
        def tkhd_887(data: bytearray) -> None:
            i = data.find(b"tkhd")
            assert struct.unpack(">I", data[i + 80:i + 84])[0] == 886 << 16
            data[i + 80:i + 84] = struct.pack(">I", 887 << 16)
        self.assertEqual(failed(patched(self.good, "tkhd-887", tkhd_887)), {"size"})

        def stsd_887(data: bytearray) -> None:
            i = data.find(b"avc1")
            assert struct.unpack(">H", data[i + 28:i + 30])[0] == 886
            data[i + 28:i + 30] = struct.pack(">H", 887)
        self.assertEqual(failed(patched(self.good, "stsd-887", stsd_887)), {"size"})

    def test_the_wrong_profile(self):
        self.assertEqual(failed(film_clip("main", profile="main41")), {"profile and level"})

    def test_the_wrong_level(self):
        self.assertEqual(failed(film_clip("level-4-1", profile="high41")), {"profile and level"})

    def test_hevc(self):
        self.assertLessEqual({"codec", "profile and level"}, failed(film_clip("hevc", codec="hevc")))

    def test_a_variable_frame_rate(self):
        """450 frames in exactly 15 s — 30 a second on average — but shown
        for 1/60 s and 1/20 s in turn."""
        pts = [0]
        for i in range(1, 449):
            pts.append(pts[-1] + (10 if i % 2 else 30))
        pts.append(pts[-1] + 20)
        self.assertEqual(failed(film_clip("vfr", pts=pts, end=9000)), {"every frame is 1/30 s"})

    def test_25_frames_per_second(self):
        self.assertEqual(failed(film_clip("pal", frames=375, step=24)),
                         {"every frame is 1/30 s", "frame rate", "frame count"})

    def test_reordered_frames(self):
        # B-frames also push the track one frame late: the edit list is no
        # longer plain and the presentation times leave the grid.
        self.assertEqual(failed(film_clip("reordered", reordering=True)),
                         {"no frame reordering", "every frame is 1/30 s", "duration"})

    def test_a_blank_film(self):
        self.assertEqual(failed(film_clip("blank", flat=True)), {"video bit rate"})

    def test_a_film_past_apples_bit_rate(self):
        """A band of noise, new in every frame, asked for at 16 Mbps: within
        what Level 4.0 can carry, past the 12 Mbps Apple's target stops at."""
        heavy = film_clip("heavy", noise=0.3, bitrate=16_000_000)
        self.assertEqual(failed(heavy), {"video bit rate"})
        seen = {c.name: c.seen for c in verify.verify(heavy, SB)}["video bit rate"]
        rate, peak = (float(x) for x in re.findall(r"([\d.]+) Mbps", seen))
        self.assertGreater(rate, 12.0, seen)
        self.assertLessEqual(peak, 25.0, seen)             # so it is the average this file fails on

    def test_pixels_that_are_not_square(self):
        """The right 886 x 1920 samples, to be shown twice as wide."""
        wide = film_clip("wide-pixels", pasp=[2, 1])
        entry = mp4.read(wide)["tracks"][0]["entries"][0]
        self.assertEqual((entry["pasp"], entry["sps"]["width"], entry["sps"]["height"]), ([2, 1], 886, 1920))
        self.assertLessEqual({"upright, square pixels"}, failed(wide))
        self.assertIn("pasp [2, 1]", {c.name: c.seen for c in verify.verify(wide, SB)}["upright, square pixels"])

    def test_sound_that_is_not_silence(self):
        self.assertEqual(failed(film_clip("tone", audio={"tone": True})), {"sound is digital silence"})

    def test_sound_at_44_1_khz(self):
        self.assertEqual(failed(film_clip("cd", audio={"rate": 44100})),
                         {"sound is stereo at 48 kHz", "sound runs the whole film"})

    def test_mono_sound(self):
        self.assertEqual(failed(film_clip("mono", audio={"channels": 1, "bitrate": 128000})),
                         {"sound is stereo at 48 kHz", "sound bit rate"})

    def test_sound_that_is_not_aac_lc(self):
        self.assertLessEqual({"sound is AAC-LC"}, failed(film_clip("lossless", audio={"format": "alac"})))

    def test_he_aac(self):
        """Written the backward-compatible way, HE-AAC reads as AAC-LC at half
        the rate with an extension: it is the 48 kHz check that catches it."""
        self.assertLessEqual({"sound is stereo at 48 kHz"},
                             failed(film_clip("he", audio={"format": "he", "bitrate": 64000})))

    def test_sound_that_stops_early(self):
        self.assertEqual(failed(film_clip("cut-sound", audio={"end": 8400})), {"sound runs the whole film"})

    def test_sound_declared_at_128_kbps(self):
        self.assertEqual(failed(film_clip("128k", audio={"bitrate": 128000})), {"sound bit rate"})

    def test_a_mov_container(self):
        self.assertEqual(failed(film_clip("quicktime", ext="mov")), {"container"})

    def test_a_container_that_is_an_mp4_by_name_only_or_by_brand_only(self):
        """Each half of the check on its own: the film's bytes under another
        name, and a QuickTime brand under the film's name."""
        for ext in ("mov", "m4v"):
            other = WORK / f"renamed.{ext}"
            shutil.copyfile(self.good, other)
            self.assertEqual(failed(other), {"container"}, ext)
            self.assertIn(f".{ext}, brand 'mp42'", verify.verify(other, SB)[0].seen)

        def quicktime(data: bytearray) -> None:
            i = data.find(b"ftyp")
            assert data[i + 4:i + 8] == b"mp42"
            data[i + 4:i + 8] = b"qt  "
        branded = patched(self.good, "brand-qt", quicktime)
        self.assertLessEqual({"container"}, failed(branded))
        self.assertIn(".mp4, brand 'qt  '", verify.verify(branded, SB)[0].seen)

    def test_a_disabled_video_track(self):
        def off(data: bytearray) -> None:
            i = data.find(b"tkhd")
            assert data[i + 7] & 1
            data[i + 7] &= 0xFE
        self.assertEqual(failed(patched(self.good, "video-off", off)), {"video enabled"})

    def test_a_disabled_sound_track(self):
        def off(data: bytearray) -> None:
            i = data.find(b"tkhd", data.find(b"tkhd") + 4)
            assert data[i + 7] & 1
            data[i + 7] &= 0xFE
        self.assertEqual(failed(patched(self.good, "sound-off", off)), {"sound enabled"})

    def test_a_rotated_picture(self):
        def rotate(data: bytearray) -> None:
            i = data.find(b"tkhd")
            data[i + 44:i + 80] = struct.pack(">9i", 0, 65536, 0, -65536, 0, 0, 1920 << 16, 0, 1 << 30)
        self.assertLessEqual({"upright, square pixels"}, failed(patched(self.good, "rotated", rotate)))

    def test_interlaced(self):
        def two_fields(data: bytearray) -> None:
            i = data.find(b"fiel")
            assert data[i + 4] == 1
            data[i + 4:i + 6] = bytes([2, 6])
        self.assertEqual(failed(patched(self.good, "fields", two_fields)), {"progressive"})

    def test_a_depth_that_says_alpha(self):
        def depth_32(data: bytearray) -> None:
            i = data.find(b"avc1")
            assert struct.unpack(">H", data[i + 78:i + 80])[0] == 24
            data[i + 78:i + 80] = struct.pack(">H", 32)
        self.assertEqual(failed(patched(self.good, "depth-32", depth_32)), {"no alpha, 8-bit 4:2:0"})

    def test_a_file_over_the_size_limit(self):
        with mock.patch.object(verify, "MAX_BYTES", self.good.stat().st_size):
            self.assertEqual(failed(self.good), {"file size"})

    def test_the_size_limit_is_apples_500_mb(self):
        """The same film, told to weigh 500 MB to the byte: one byte under
        passes, the limit itself does not."""
        real = mp4.read

        def weighing(size: int):
            return lambda path: {**real(path), "file_bytes": size}
        with mock.patch.object(mp4, "read", weighing(500 * 1000 * 1000 - 1)):
            self.assertEqual(failed(self.good), set())
        with mock.patch.object(mp4, "read", weighing(500 * 1000 * 1000)):
            self.assertEqual(failed(self.good), {"file size"})

    def test_a_poster_frame_that_is_not_the_composed_one(self):
        folder = self.good.parent
        index = round(SB["film"]["poster_s"] * 30)
        right = folder / f"p{(index // 15) % 4}.png"
        wrong = folder / f"p{(index // 15 + 1) % 4}.png"
        self.assertEqual(failed(self.good, right), set())
        self.assertEqual(failed(self.good, wrong), {"poster frame"})

    def test_a_poster_time_past_the_end_of_the_film(self):
        """12 s of film and a poster frame at 13 s: there is no such frame."""
        brief = film_clip("twelve-seconds", frames=360)
        self.assertEqual(failed(brief, brief.parent / "p0.png"), {"frame count", "duration", "poster frame"})
        report = {c.name: c.seen for c in verify.verify(brief, SB, brief.parent / "p0.png")}
        self.assertIn("cannot decode frame 390", report["poster frame"])

    def poster(self) -> tuple[Path, np.ndarray]:
        index = round(SB["film"]["poster_s"] * 30)
        right = self.good.parent / f"p{(index // 15) % 4}.png"
        with Image.open(right) as im:
            return right, np.asarray(im.convert("RGB")).astype(int)

    def test_a_poster_a_shade_off_everywhere(self):
        """One level lighter all over, or two — a colour conversion gone
        wrong: no block stands out, and it is not the composed picture. 48 dB
        is one level of error, root mean square: a picture a level off
        everywhere cannot measure better, however good the encode."""
        right, a = self.poster()
        for shade in (1, 2):
            lighter = self.good.parent / f"lighter-{shade}.png"
            Image.fromarray(np.clip(a + shade, 0, 255).astype(np.uint8), "RGB").save(lighter)
            self.assertEqual(failed(self.good, lighter), {"poster frame"}, shade)
            seen = {c.name: c.seen for c in verify.verify(self.good, SB, lighter)}["poster frame"]
            psnr = float(re.search(r"([\d.]+) dB", seen).group(1))
            block = float(re.search(r"by ([\d.]+) levels", seen).group(1))
            self.assertLess(psnr, verify.POSTER_MIN_PSNR, seen)
            self.assertLessEqual(block, verify.POSTER_MAX_BLOCK, seen)   # the whole picture gives it away, not a block

    def test_a_patch_the_size_of_one_block_is_enough(self):
        right, a = self.poster()
        a[1600:1616, 320:336] = np.clip(a[1600:1616, 320:336] - 40, 0, 255)
        patch = self.good.parent / "one-block.png"
        Image.fromarray(a.astype(np.uint8), "RGB").save(patch)
        self.assertEqual(failed(self.good, patch), {"poster frame"})
        seen = {c.name: c.seen for c in verify.verify(self.good, SB, patch)}["poster frame"]
        psnr, block = float(re.search(r"([\d.]+) dB", seen).group(1)), float(re.search(r"by ([\d.]+) levels", seen).group(1))
        self.assertGreaterEqual(psnr, verify.POSTER_MIN_PSNR, seen)   # too small for the whole picture to notice
        self.assertGreater(block, verify.POSTER_MAX_BLOCK, seen)

    def test_a_poster_one_step_short_of_its_cross_fade(self):
        """The frame before the last caption has finished arriving: 6 % of
        the picture before it is still there (`base`, easeInOut, 5 of 6
        frames in). On the rehearsal film of 2026-10-13 that frame measured
        44.1 dB and 10.8 levels against the limits of the day, 42 and 12 —
        and passed as the poster."""
        right, a = self.poster()
        index = round(SB["film"]["poster_s"] * 30)
        with Image.open(self.good.parent / f"p{(index // 15 + 1) % 4}.png") as im:
            before = np.asarray(im.convert("RGB")).astype(int)
        early = self.good.parent / "one-step-early.png"
        Image.fromarray(np.rint(a + (before - a) * 0.057).astype(np.uint8), "RGB").save(early)
        self.assertEqual(failed(self.good, early), {"poster frame"})

    def test_a_check_that_was_not_run_is_said_not_to_have_run(self):
        """Without a composed poster the frame at the poster time is compared
        with nothing: 23 checks that pass are not 24."""
        right, _ = self.poster()
        checks = verify.verify(self.good, SB)
        self.assertEqual([(c.ok, c.skipped, c.seen) for c in checks if c.name == "poster frame"],
                         [(True, True, "NOT compared — no composed poster was given")])
        text, ok = verify.report(checks, self.good)
        self.assertTrue(ok)
        self.assertIn("  skip  poster frame                 NOT compared", text)
        self.assertTrue(text.endswith("PASS — 23 checks; NOT RUN: poster frame\n"), text[-80:])
        text, ok = verify.report(verify.verify(self.good, SB, right), self.good, " — a note")
        self.assertTrue(text.endswith("PASS — 24 checks — a note\n"), text[-80:])
        self.assertNotIn("skip", text)
        short = verify.report(verify.verify(film_clip("short", frames=447), SB), self.good)[0]
        self.assertTrue(short.endswith("FAIL — 2 of 23 checks: frame count, duration; NOT RUN: poster frame\n"))

    def test_a_touch_point_left_on_the_poster(self):
        """One small difference is enough: a 12 % disc the poster should not
        have."""
        folder = self.good.parent
        index = round(SB["film"]["poster_s"] * 30)
        with Image.open(folder / f"p{(index // 15) % 4}.png") as right:
            spotted = right.copy()
        disc = Image.new("L", spotted.size, 0)
        ImageDraw.Draw(disc).ellipse((400, 900, 476, 976), fill=round(255 * 0.12))
        spotted.paste(Image.new("RGB", spotted.size, (0, 0, 0)), (0, 0), disc)
        spotted.save(folder / "spotted.png")
        self.assertEqual(failed(self.good, folder / "spotted.png"), {"poster frame"})

    def test_something_that_is_not_a_movie(self):
        junk = WORK / "junk.mp4"
        junk.write_bytes(b"not a movie at all")
        self.assertEqual(failed(junk), {"readable (boxes)"})
        self.assertFalse(verify._avmediainfo(junk)["ok"])
        self.assertTrue(verify._avmediainfo(self.good)["ok"])

    def test_a_file_avmediainfo_finds_errors_in(self):
        real = verify._avmediainfo

        def with_errors(path):
            return {**real(path), "ok": False}
        with mock.patch.object(verify, "_avmediainfo", with_errors):
            self.assertEqual(failed(self.good), {"avmediainfo reads it"})

    def test_the_second_opinion_on_the_frame_time_counts(self):
        """avmediainfo's shortest sample is one of the three readings of
        « every frame is 1/30 s ». The three read the same bytes and cannot
        be made to disagree on a real file, so the disagreement is staged."""
        real = verify._avmediainfo

        def shorter(path):
            info = real(path)
            video = next(t for t in info["tracks"] if t["kind"] == "Video")
            assert video["min_duration"] == [20, 600]
            video["min_duration"] = [10, 600]
            return info
        with mock.patch.object(verify, "_avmediainfo", shorter):
            self.assertEqual(failed(self.good), {"every frame is 1/30 s"})

    def test_sound_that_starts_late(self):
        """As long as the film, from 0.01 s in: AVFoundation's reading of the
        sound track's time range, staged as above."""
        real = swifttools.run

        def late(name, *args, **kw):
            r = real(name, *args, **kw)
            if (name, args[0]) == ("inspect", "facts"):
                out = Path(args[args.index("--out") + 1])
                facts = json.loads(out.read_text())
                sound = next(t for t in facts["tracks"] if t["type"] == "soun")
                assert sound["time_range"][0][0] == 0
                sound["time_range"][0][0] = 480
                out.write_text(json.dumps(facts))
            return r
        with mock.patch.object(swifttools, "run", late):
            self.assertEqual(failed(self.good), {"sound runs the whole film"})

    def test_a_file_cut_short(self):
        """The index is at the front, so the headers of a truncated film are
        all there: it must still not pass."""
        data = self.good.read_bytes()
        cut = WORK / "cut.mp4"
        cut.write_bytes(data[: len(data) * 2 // 3])
        self.assertEqual(failed(cut), {"readable (boxes)"})

    def test_a_file_whose_headers_are_cut_or_hollow(self):
        """Wherever the parse trips, the answer is a failed check — never a
        crash that someone could read as "the checker did not complain"."""
        data = self.good.read_bytes()
        cut = WORK / "cut-in-the-headers.mp4"
        cut.write_bytes(data[: data.find(b"moov") + 200])
        self.assertEqual(failed(cut), {"readable (boxes)"})

        def box(kind: bytes, payload: bytes) -> bytes:
            return struct.pack(">I4s", 8 + len(payload), kind) + payload
        # a movie whose last box is a track header with nothing in it: its
        # fields would be read past the end of the file
        mvhd = box(b"mvhd", struct.pack(">IIIII", 0, 0, 0, 600, 9000) + bytes(80))
        hollow = WORK / "hollow.mp4"
        hollow.write_bytes(box(b"ftyp", b"mp42\0\0\0\0mp42") + box(b"moov", mvhd + box(b"trak", box(b"tkhd", b""))))
        with self.assertRaises(mp4.Mp4Error) as cm:
            mp4.read(hollow)
        self.assertIn("cut short or malformed", str(cm.exception))
        self.assertEqual(failed(hollow), {"readable (boxes)"})

    def test_a_film_whose_pictures_are_not_where_the_headers_say(self):
        """The headers promise 450 samples; AVFoundation finds none of them
        and says nothing. The two readers' counts no longer agree."""
        def lost(data: bytearray) -> None:
            i = data.find(b"stco")
            n = struct.unpack(">I", data[i + 8:i + 12])[0]
            assert n > 0
            for k in range(n):
                data[i + 12 + 4 * k:i + 16 + 4 * k] = struct.pack(">I", 0x7FFF0000)
        self.assertEqual(failed(patched(self.good, "lost-samples", lost)),
                         {"every frame is 1/30 s", "frame count"})

    def test_a_file_avfoundation_cannot_open(self):
        refusal = subprocess.CompletedProcess([], 1, "", "inspect: cannot open it")
        with mock.patch.object(swifttools, "run", return_value=refusal):
            checks = verify.verify(self.good, SB)
        self.assertEqual([(c.name, c.ok, c.seen) for c in checks],
                         [("readable (AVFoundation)", False, "inspect: cannot open it")])

    def test_a_file_with_no_picture(self):
        import wave
        with wave.open(str(WORK / "silence.wav"), "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(48000)
            w.writeframes(b"\0" * 4 * 48000 * 15)
        subprocess.run(["afconvert", "-f", "mp4f", "-d", "aac", "-b", "256000", str(WORK / "silence.wav"),
                        str(WORK / "sound-only.mp4")], check=True, capture_output=True)
        self.assertEqual(failed(WORK / "sound-only.mp4"), {"tracks", "video track", "sound runs the whole film"})

    def command(self, *args) -> subprocess.CompletedProcess:
        (WORK / "storyboard.json").write_text(json.dumps(SB))
        return subprocess.run(["python3", str(TOOL / "preview.py"), "verify", "--storyboard",
                               str(WORK / "storyboard.json"), *map(str, args)], capture_output=True, text=True)

    def built(self, name: str, source: Path | None = None, **record) -> Path:
        """A film in its own folder with the record a build leaves beside it."""
        folder = WORK / name
        folder.mkdir(exist_ok=True)
        movie = folder / "preview.mp4"
        shutil.copyfile(source or self.good, movie)
        (folder / "build.json").write_text(json.dumps({
            "file": movie.name, "sha256": hashlib.sha256(movie.read_bytes()).hexdigest(),
            "rehearsal": False, "variant": None, **record}))
        return movie

    def test_the_command_exits_non_zero_on_a_miss(self):
        bad = self.built("built-short", film_clip("short", frames=447))
        r = self.command(bad, "--no-poster")
        self.assertEqual(r.returncode, 1)
        self.assertIn("FAIL — 2 of 23 checks: frame count, duration; NOT RUN: poster frame", r.stdout)
        right, _ = self.poster()
        r = self.command(self.built("built-good"), "--poster", right)
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertRegex(r.stdout, r"PASS — 24 checks — the film, sha256 [0-9a-f]{16}…\n$")

    def test_the_command_wants_the_poster_or_to_be_told_there_is_none(self):
        movie = self.built("built-good")
        r = self.command(movie)
        self.assertEqual((r.returncode, r.stdout), (1, ""))
        self.assertIn("give --poster <poster.png> — or --no-poster", r.stderr)
        r = self.command(movie, "--no-poster")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("  skip  poster frame                 NOT compared — no composed poster was given", r.stdout)
        self.assertRegex(r.stdout, r"PASS — 23 checks; NOT RUN: poster frame — the film, sha256 [0-9a-f]{16}…\n$")

    def test_a_file_no_build_names_is_not_called_the_film(self):
        """Every check passes, and the command still exits 1: a rehearsal
        copied out of its folder and renamed is exactly this."""
        stray = WORK / "stray"
        stray.mkdir(exist_ok=True)
        movie = stray / "preview.mp4"
        shutil.copyfile(self.good, movie)
        said = ("PASS — 23 checks; NOT RUN: poster frame\nNOT IDENTIFIED — no build.json beside preview.mp4 names "
                "these bytes: it may be a rehearsal, a copy or another writer's file, and is not known to be the film\n")
        r = self.command(movie, "--no-poster")
        self.assertEqual(r.returncode, 1)
        self.assertTrue(r.stdout.endswith(said), r.stdout[-300:])
        # a record of another file's bytes, and one that cannot be read, name nothing
        (stray / "build.json").write_text(json.dumps({"file": "preview.mp4", "sha256": "ab" * 32, "rehearsal": False}))
        r = self.command(movie, "--no-poster")
        self.assertEqual(r.returncode, 1)
        self.assertTrue(r.stdout.endswith(said), r.stdout[-300:])
        for junk in ("{ not json", "[1, 2]"):
            (stray / "build.json").write_text(junk)
            r = self.command(movie, "--no-poster")
            self.assertEqual(r.returncode, 1, junk)
            self.assertTrue(r.stdout.endswith(said), junk)
        r = self.command(stray / "nothing.mp4", "--no-poster")
        self.assertEqual(r.returncode, 1)
        self.assertIn("no such file", r.stderr)

    def test_a_rehearsal_is_one_whatever_its_name(self):
        """preview.mp4 by name; the record beside it says what it was built as."""
        movie = self.built("built-rehearsal", rehearsal=True)
        r = self.command(movie, "--no-poster")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertTrue(r.stdout.endswith("PASS — 23 checks; NOT RUN: poster frame — REHEARSAL, not the film: built "
                                          "with --rehearsal, some shots have no footage\n"), r.stdout[-200:])
        movie = self.built("built-variant", rehearsal=True, variant="dry")
        r = self.command(movie, "--no-poster")
        self.assertEqual((r.returncode, r.stdout), (1, ""))
        self.assertIn("preview.mp4 was built as the storyboard's variant `dry` (build.json beside it names these "
                      "bytes) and is being checked as the film: add --variant dry", r.stderr)


class EncoderRefuses(unittest.TestCase):
    """`encode` has nothing to configure, and will not write anything else."""

    def refused(self, manifest: dict, picture: tuple[int, int] = (886, 1920)) -> str:
        folder = WORK / "encode"
        folder.mkdir(exist_ok=True)
        Image.new("RGB", picture).save(folder / "f.png")
        (folder / "frames.json").write_text(json.dumps(manifest))
        (folder / "out.mp4").write_bytes(b"an earlier film")
        r = swifttools.run("encode", folder, "--out", folder / "out.mp4", check=False)
        self.assertEqual(r.returncode, 1, manifest)
        # nothing is left that could pass for this run's film — not a half-
        # written file, not the earlier one
        self.assertEqual(sorted(p.name for p in folder.glob("out.mp4*")), [])
        return r.stderr

    def test_there_is_nothing_to_configure(self):
        folder = WORK / "encode-flags"
        folder.mkdir(exist_ok=True)
        Image.new("RGB", (886, 1920)).save(folder / "f.png")
        (folder / "frames.json").write_text(json.dumps(
            {"fps": 30, "width": 886, "height": 1920, "frames": ["f.png"] * 450}))
        r = swifttools.run("encode", folder, "--out", folder / "out.mp4", "--bitrate", 5_000_000, check=False)
        self.assertEqual(r.returncode, 1)
        self.assertIn("unknown flag --bitrate", r.stderr)
        self.assertFalse((folder / "out.mp4").exists())

    def test_an_output_that_is_not_an_mp4_is_refused_and_left_alone(self):
        folder = WORK / "encode-mov"
        folder.mkdir(exist_ok=True)
        Image.new("RGB", (886, 1920)).save(folder / "f.png")
        (folder / "frames.json").write_text(json.dumps(
            {"fps": 30, "width": 886, "height": 1920, "frames": ["f.png"] * 450}))
        (folder / "out.mov").write_bytes(b"someone's file")
        r = swifttools.run("encode", folder, "--out", folder / "out.mov", check=False)
        self.assertEqual(r.returncode, 1)
        self.assertIn("the output must be a .mp4", r.stderr)
        self.assertEqual((folder / "out.mov").read_bytes(), b"someone's file")

    def test_a_film_under_15_s_or_over_30_s(self):
        base = {"fps": 30, "width": 886, "height": 1920}
        self.assertIn("a preview is 15 to 30 s", self.refused({**base, "frames": ["f.png"] * 449}))
        self.assertIn("a preview is 15 to 30 s", self.refused({**base, "frames": ["f.png"] * 901}))

    def test_another_frame_rate_or_size(self):
        frames = ["f.png"] * 450
        self.assertIn("refusing it", self.refused({"fps": 25, "width": 886, "height": 1920, "frames": frames}))
        self.assertIn("refusing it", self.refused({"fps": 30, "width": 888, "height": 1920, "frames": frames}))
        self.assertIn("refusing it", self.refused({"fps": 30, "width": 886, "height": 1918, "frames": frames}))

    def test_a_test_clip_that_fails_leaves_nothing_either(self):
        folder = WORK / "clip-fails"
        folder.mkdir(exist_ok=True)
        Image.new("RGB", (884, 1920)).save(folder / "f.png")
        (folder / "clip.json").write_text(json.dumps({
            "width": 886, "height": 1920, "timescale": T, "end": 600,
            "frames": [{"pts": 20 * i, "file": "f.png"} for i in range(30)]}))
        (folder / "out.mp4").write_bytes(b"an earlier clip")
        r = swifttools.run("testclip", folder / "clip.json", "--out", folder / "out.mp4", check=False)
        self.assertEqual(r.returncode, 1)
        self.assertIn("is 884x1920, the movie is 886x1920", r.stderr)
        self.assertEqual(sorted(p.name for p in folder.glob("out.mp4*")), [])

    def test_a_picture_of_another_size(self):
        self.assertIn("is 884x1920, the movie is 886x1920",
                      self.refused({"fps": 30, "width": 886, "height": 1920, "frames": ["f.png"] * 450},
                                   picture=(884, 1920)))


if __name__ == "__main__":
    unittest.main()
