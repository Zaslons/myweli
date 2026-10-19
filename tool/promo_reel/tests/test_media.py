"""promo.media: takes decoded picture-accurately, blurs placed and measured,
films written and read back frame-exactly, touch-downs found as the App
Store tool finds them.

Two kinds of material:
  * drawn here — a VFR « take » whose every picture carries its own number
    as a barcode, and a CFR film whose every frame carries its number: a
    picture or frame handed over in the wrong place is caught by its content;
  * the real takes (the main checkout's gitignored build/ folder) — skipped
    when they are not on this machine.
"""

from __future__ import annotations

import atexit
import math
import shutil
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from promo.media import masks, probe, sheets, tools, touches  # noqa: E402
from promo.media.masks import Blur, MaskError, MaskSet, ScrollTrack  # noqa: E402
from promo.media.takes import DecodeError, Take, TakeError  # noqa: E402
from promo.media.writer import VideoWriter, WriterError  # noqa: E402

WORK = Path(tempfile.mkdtemp(prefix="promo-media-"))
atexit.register(shutil.rmtree, WORK, ignore_errors=True)

HAVE_FFMPEG = True
try:
    tools.ffmpeg(), tools.ffprobe()
except tools.ToolMissing:  # pragma: no cover
    HAVE_FFMPEG = False
HAVE_MATERIAL = HAVE_FFMPEG and tools.material_available()
needs_ffmpeg = unittest.skipUnless(HAVE_FFMPEG, "ffmpeg/ffprobe not installed")
needs_material = unittest.skipUnless(HAVE_MATERIAL, "the recorded takes are not on this machine")


# ---- drawn material ----------------------------------------------------------------

def draw_code(rgba: np.ndarray, number: int, bits: int, block: int, y: int, x0: int = 20) -> None:
    """``number`` as ``bits`` black/white squares on one row."""
    for k in range(bits):
        x = x0 + k * (block + 4)
        rgba[y:y + block, x:x + block, :3] = 255 if (number >> k) & 1 else 0


def read_code(rgba: np.ndarray, bits: int, block: int, y: int, x0: int = 20) -> int:
    value = 0
    for k in range(bits):
        x = x0 + k * (block + 4)
        centre = rgba[y + block // 4:y + 3 * block // 4, x + block // 4:x + 3 * block // 4, :3]
        if centre.mean() > 128:
            value |= 1 << k
    return value


# A VFR take: 402 × 874 px (1 px a point), timescale 600, pictures at uneven
# times, as the Simulator's recorder writes them.
TAKE_GAPS = [300, 6, 9, 30, 6, 60, 9, 9, 300, 6] * 3      # ticks between pictures
TAKE_TICKS = [0] + [int(t) for t in np.cumsum(TAKE_GAPS)]
SCROLL_PER_PICTURE = 2      # pt the « content » moves up per picture
BAR_TOP = 800               # an opaque bar from y 800 pt down
NUMBER = "+225 07 12 34 56 78"   # a phone-number-like line of text, scrolling with the content
NUMBER_AT = (60, 400)            # where it is at scroll 0 (pt = px here)


def _number_font():
    from PIL import ImageFont
    return ImageFont.truetype(str(tools.FONTS / "Inter-Variable.ttf"), 26)


def number_rect(margin: float = 4) -> tuple[float, float, float, float]:
    """The number's ink box at scroll 0, grown by ``margin``."""
    from PIL import Image, ImageDraw
    x0, y0, x1, y1 = ImageDraw.Draw(Image.new("RGB", (1, 1))).textbbox(NUMBER_AT, NUMBER, font=_number_font())
    return (x0 - margin, y0 - margin, x1 + margin, y1 + margin)


def take_picture(i: int) -> np.ndarray:
    from PIL import Image, ImageDraw
    im = Image.new("RGB", (402, 874), (255, 255, 255))
    d = ImageDraw.Draw(im)
    d.text((NUMBER_AT[0], NUMBER_AT[1] - SCROLL_PER_PICTURE * i), NUMBER, font=_number_font(), fill=(74, 74, 74))
    d.rectangle((0, BAR_TOP, 402, 874), fill=(60, 60, 60))   # the bar
    a = np.dstack([np.asarray(im), np.full((874, 402), 255, np.uint8)])
    draw_code(a, i, 6, 40, 20)
    return a


def synthetic_take() -> Path:
    """The drawn take as an H.264 .mov: picture i at TAKE_TICKS[i] (timescale 600)."""
    folder = WORK / "synthetic_take"
    movie = folder / "take.mov"
    if movie.exists():
        return movie
    folder.mkdir(parents=True)
    from PIL import Image
    for i in range(len(TAKE_TICKS)):
        Image.fromarray(take_picture(i)[..., :3]).save(folder / f"p{i:03d}.png")
    # setpts gives picture N its tick: if(eq(N,1),300,if(eq(N,2),306,…,0))
    expr = "0"
    for n in range(len(TAKE_TICKS) - 1, 0, -1):
        expr = f"if(eq(N\\,{n})\\,{TAKE_TICKS[n]}\\,{expr})"
    subprocess.run([tools.ffmpeg(), "-v", "error", "-y", "-framerate", "600", "-i", str(folder / "p%03d.png"),
                    "-vf", f"settb=1/600,setpts='{expr}',scale=out_color_matrix=bt709:out_range=tv,format=yuv420p",
                    "-c:v", "libx264", "-crf", "12", "-fps_mode", "passthrough", "-enc_time_base", "1/600",
                    "-video_track_timescale", "600", "-colorspace", "bt709", "-color_range", "tv", str(movie)],
                   check=True)
    return movie


def tone_wav(path: Path, samples: int, rate: int = 48_000) -> Path:
    t = np.arange(samples) / rate
    x = (0.25 * np.sin(2 * np.pi * 440 * t) * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(np.stack([x, x], 1).tobytes())
    return path


def film_frame(n: int, w: int = 1080, h: int = 1920) -> np.ndarray:
    a = np.full((h, w, 4), 250, np.uint8)
    a[..., 3] = 255
    draw_code(a, n, 8, 100, 300)
    a[1200:1400, (n * 15) % (w - 200):(n * 15) % (w - 200) + 200, :3] = (26, 26, 26)
    return a


# ---- takes -------------------------------------------------------------------------------

@needs_ffmpeg
class SyntheticTake(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.take = Take(synthetic_take())

    @classmethod
    def tearDownClass(cls):
        cls.take.close()

    def test_every_pictures_time_is_read(self):
        self.assertEqual(list(self.take.pts), [int(t) for t in TAKE_TICKS])
        self.assertEqual(self.take.timescale, 600)
        self.assertEqual((self.take.width, self.take.height, self.take.px_per_pt), (402, 874, 1.0))

    def test_every_picture_is_the_one_asked_for(self):
        take = Take(synthetic_take())
        for i in range(take.count):                       # in order: one decoder reads on
            self.assertEqual(read_code(take.picture(i), 6, 40, 20), i)
        self.assertEqual(take.decodes, 1)
        for i in (25, 3, 30, 0, 17):                      # jumps back and far: a new seek each
            self.assertEqual(read_code(take.picture(i), 6, 40, 20), i)
        take.close()

    def test_the_picture_shown_at_t_is_the_latest_at_or_before_t(self):
        t = self.take
        for i, ticks in enumerate(TAKE_TICKS):
            self.assertEqual(t.index_at(ticks / 600), i)                    # on its own time
            if i:
                self.assertEqual(t.index_at((ticks - 1) / 600), i - 1)     # one tick before: the one before
        self.assertEqual(t.index_at(1e6), t.count - 1)                      # after the last: the last, held
        with self.assertRaises(TakeError):
            t.index_at(-0.001)
        p = t.picture_at(0.52)
        self.assertEqual((p.index, p.ticks), (2, 306))
        self.assertEqual(read_code(p.rgba, 6, 40, 20), 2)
        self.assertFalse(p.rgba.flags.writeable)

    def test_a_picture_named_by_its_millisecond_time(self):
        t = self.take
        self.assertEqual(t.index_named(0.51), 2)
        self.assertEqual(t.index_named(0.5109), 2)          # rounded up by up to a millisecond
        self.assertEqual(t.time_named(0.525), 315 / 600)
        self.assertEqual(t.picture_named(0.525).index, 3)
        with self.assertRaisesRegex(TakeError, "no picture at 0.513 s .* picture 2 at 0.5100 s"):
            t.index_named(0.513)                             # inside picture 2's time on screen: not a picture's time

    def test_pictures_between(self):
        shown = self.take.pictures_between(0.51, 0.51 + 1 / 30)            # 306 … 326 ticks
        self.assertEqual([s.index for s in shown], [2, 3])                 # pictures at 306 and 315
        shown = self.take.pictures_between(0.5, 0.6)                       # 300 … 360 ticks
        self.assertEqual([s.index for s in shown], [1, 2, 3, 4, 5])
        self.assertAlmostEqual(sum(s.weight for s in shown), 1.0)
        self.assertAlmostEqual(shown[0].end_s - shown[0].start_s, 6 / 600)
        self.assertEqual(self.take.pictures_between(0.6, 0.5), [])

    def test_a_picture_handed_over_at_another_time_is_an_error(self):
        take = Take(synthetic_take())
        take.pts = tuple(p + 1 if i == 5 else p for i, p in enumerate(take.pts))   # an index that lies by a tick
        with self.assertRaisesRegex(DecodeError, "asked for picture 5 at 352 ticks, ffmpeg handed over a "
                                                 "picture at 351 ticks"):
            take.picture(5)
        take.close()

    def test_cache_holds_its_budget(self):
        take = Take(synthetic_take(), cache_mb=3)                          # one picture is 1.4 MB
        for i in range(6):
            take.picture(i)
        self.assertLessEqual(take._cache_bytes, 3 * 1024 * 1024)
        self.assertEqual(read_code(take.picture(0), 6, 40, 20), 0)         # evicted, decoded again
        take.close()

    def test_bad_picture_numbers(self):
        for bad in (-1, self.take.count, 1.0, True):
            with self.subTest(bad=bad), self.assertRaises(TakeError):
                self.take.picture(bad)

    def test_a_vfr_take_is_not_a_film(self):
        problems = probe.check(probe.probe(synthetic_take()), probe.Expect(audio=False, profile=None, colour=None))
        self.assertTrue(any("not constant frame rate" in p for p in problems), problems)


# ---- masks ---------------------------------------------------------------------------------

@needs_ffmpeg
class Masks(unittest.TestCase):
    def setUp(self):
        self.take = Take(synthetic_take())
        rows = ["seconds,scroll_pt"] + [f"{t / 600:.3f},{SCROLL_PER_PICTURE * i}" for i, t in enumerate(TAKE_TICKS)]
        self.csv = WORK / "scroll.csv"
        self.csv.write_text("\n".join(rows) + "\n")

    def tearDown(self):
        self.take.close()

    def test_a_tracked_blur_follows_the_scroll_and_hides_the_content(self):
        track = ScrollTrack.from_csv(self.csv, self.take)
        rect = number_rect()
        self.take.set_masks([Blur("number", rect, sigma_px=14, track=track)])
        for i in (0, 5, 20, 30):
            placed = self.take.masks.placed(self.take.pts[i])
            s = SCROLL_PER_PICTURE * i
            want = (math.floor(rect[0]), math.floor(rect[1] - s), math.ceil(rect[2]), math.ceil(rect[3] - s))
            self.assertEqual(placed[0].box_px, want)
            raw, masked = self.take.raw_picture(i), self.take.picture(i)
            x0, y0, x1, y1 = placed[0].box_px
            outside = np.ones(raw.shape[:2], bool)
            outside[y0:y1, x0:x1] = False
            self.assertTrue(np.array_equal(raw[outside], masked[outside]), "pixels outside the box changed")
            self.assertFalse(np.array_equal(raw[y0:y1, x0:x1], masked[y0:y1, x0:x1]))
        cover = self.take.masks.verify()
        self.assertEqual(len(cover), self.take.count)
        self.assertTrue(all(c.share_left <= masks.LEGIBLE for c in cover))

    def test_a_weak_blur_is_refused(self):
        self.take.set_masks([Blur("number", number_rect(), sigma_px=0.3, track=ScrollTrack.from_csv(self.csv, self.take))])
        with self.assertRaisesRegex(MaskError, "leaves .* of the detail"):
            self.take.masks.verify([0])

    def test_a_blur_on_nothing_is_refused(self):
        self.take.set_masks([Blur("nowhere", (330, 600, 380, 650))])
        with self.assertRaisesRegex(MaskError, "sits on nothing"):
            self.take.masks.verify([0, 1])

    def test_the_picture_on_screen_when_a_blur_starts_is_blurred(self):
        # picture 1 is shown from 0.500 s to 0.510 s: a blur from 0.505 s is on it, not on picture 0
        self.take.set_masks([Blur("number", number_rect(), from_s=0.505, to_s=0.53)])
        on = [i for i in range(self.take.count) if self.take.masks.active(self.take.pts[i])]
        self.assertEqual(on, [1, 2, 3])                   # 3 starts at 0.525 s, inside
        self.assertIs(self.take.picture(0), self.take.raw_picture(0))

    def test_a_clipped_blur_never_touches_or_reads_the_bar(self):
        self.take.set_masks([Blur("edge", (100, 770, 300, 830), sigma_px=8, clip_y_pt=(0, BAR_TOP))])
        raw, masked = self.take.raw_picture(0), self.take.picture(0)
        self.assertEqual(self.take.masks.placed(0)[0].box_px, (100, 770, 300, 800))
        self.assertTrue(np.array_equal(raw[BAR_TOP:], masked[BAR_TOP:]), "the bar was blurred")
        # the rows just above the bar are white and stay so: the dark bar was not read
        # (read, it would pull them down towards its grey 60)
        self.assertGreaterEqual(int(masked[790:800, 100:300, :3].min()), int(raw[770:800, 100:300, :3].min()) - 3)

    def test_a_table_that_is_not_the_takes_is_refused(self):
        self.csv.write_text("seconds,scroll_pt\n0.000,0\n")
        with self.assertRaisesRegex(MaskError, "rows for the"):
            ScrollTrack.from_csv(self.csv, self.take)
        rows = ["seconds,scroll_pt"] + [f"{t / 600 + 0.005:.3f},0" for t in TAKE_TICKS]
        self.csv.write_text("\n".join(rows) + "\n")
        with self.assertRaisesRegex(MaskError, "not this take's"):
            ScrollTrack.from_csv(self.csv, self.take)

    def test_bad_blurs(self):
        with self.assertRaises(MaskError):
            Blur("empty", (10, 10, 10, 20))
        with self.assertRaises(MaskError):
            Blur("backwards", (0, 0, 10, 10), from_s=2, to_s=1)
        with self.assertRaises(MaskError):
            MaskSet([Blur("a", (0, 0, 1, 1)), Blur("a", (2, 2, 3, 3))], self.take)


# ---- writer, probe, sheets -----------------------------------------------------------------------

@needs_ffmpeg
class WriteAndReadBack(unittest.TestCase):
    """A 2-s film (60 frames, 1080 × 1920, a tone) through writer.py, probe.py and sheets.py."""

    @classmethod
    def setUpClass(cls):
        cls.wav = tone_wav(WORK / "tone.wav", 60 * 1600)
        cls.mp4 = WORK / "two-seconds.mp4"
        with VideoWriter(cls.mp4, 1080, 1920, frames=60, audio=cls.wav) as w:
            for n in range(60):
                w.write(film_frame(n))

    def test_the_film_is_what_was_asked(self):
        report = probe.assert_film(self.mp4, frames=60, width=1080, height=1920)
        v, a = report["video"], report["audio"]
        self.assertEqual((v["codec"], v["profile"], v["pix_fmt"], v["frames"]), ("h264", "High", "yuv420p", 60))
        self.assertTrue(v["cfr"])
        self.assertEqual(v["measured_fps"], 30.0)
        self.assertEqual((v["color_primaries"], v["color_transfer"], v["color_space"], v["color_range"]),
                         ("bt709", "bt709", "bt709", "tv"))
        self.assertEqual((a["codec"], a["sample_rate"], a["channels"]), ("aac", 48000, 2))
        self.assertGreater(a["bit_rate"], 200_000)
        self.assertLessEqual(abs(report["av"]["duration_difference_s"]), 1024 / 48000)
        self.assertTrue(report["container"]["faststart"])
        self.assertLess(report["container"]["boxes"].index("moov"), report["container"]["boxes"].index("mdat"))
        self.assertFalse((WORK / "two-seconds.partial.mp4").exists())

    def test_probe_reports_each_difference(self):
        report = probe.probe(self.mp4)
        found = probe.check(report, probe.Expect(frames=61, width=1080, height=1080, fps=25))
        for part in ("frames: 60, expected 61", "height: 1920, expected 1080", "frame rate measured 30.0"):
            self.assertTrue(any(part in p for p in found), (part, found))
        with self.assertRaises(probe.ProbeError):
            probe.assert_film(self.mp4, frames=59)
        saved = probe.write_report(report, WORK / "report.json", probe.Expect(frames=60, width=1080, height=1920))
        self.assertIn('"problems": []', saved.read_text())

    def test_frames_are_pulled_exactly(self):
        wanted = [0, 1, 2, 17, 30, 31, 58, 59]
        pulled = sheets.pull_frames(self.mp4, wanted)
        self.assertEqual(sorted(pulled), wanted)
        for n, rgba in pulled.items():
            self.assertEqual(read_code(rgba, 8, 100, 300), n, f"frame {n}")
            self.assertEqual(rgba.shape, (1920, 1080, 4))
        with self.assertRaises(sheets.SheetError):
            sheets.pull_frames(self.mp4, [60])

    def test_contact_sheet(self):
        out = sheets.beat_sheet(self.mp4, WORK / "sheet.png", every=8)
        from PIL import Image
        with Image.open(out) as im:
            self.assertEqual(im.width, 12 + 8 * (200 + 12))
        self.assertEqual(sheets.label(144), "f144 · 4.800 s · 3.2.0")
        self.assertEqual(sheets.label(149), "f149 · 4.967 s · 3.2.1+1")
        saved = sheets.save_frames(self.mp4, [5], WORK / "frames")
        self.assertEqual(saved[0].name, "f0005.png")

    def test_a_film_without_sound_is_reported(self):
        silent = WORK / "silent.mp4"
        with VideoWriter(silent, 160, 90, frames=3) as w:
            for n in range(3):
                w.write(film_frame(n, 160, 90))
        found = probe.check(probe.probe(silent), probe.Expect(frames=3))
        self.assertIn("no audio stream", found)


@needs_ffmpeg
class WriterRefuses(unittest.TestCase):
    def frame(self, n=0):
        return film_frame(n, 160, 90)

    def test_a_missing_frame_leaves_no_file(self):
        out = WORK / "short.mp4"
        w = VideoWriter(out, 160, 90, frames=3)
        w.write(self.frame())
        with self.assertRaisesRegex(WriterError, "1 frames written, the film has 3"):
            w.close()
        self.assertFalse(out.exists())
        self.assertFalse((WORK / "short.partial.mp4").exists())

    def test_one_frame_too_many(self):
        with VideoWriter(WORK / "long.mp4", 160, 90, frames=1) as w:
            w.write(self.frame())
            with self.assertRaisesRegex(WriterError, "one too many"):
                w.write(self.frame())

    def test_bad_frames(self):
        w = VideoWriter(WORK / "bad.mp4", 160, 90, frames=2)
        try:
            with self.assertRaisesRegex(WriterError, "expected \\(90, 160, 4\\)"):
                w.write(np.zeros((90, 161, 4), np.uint8))
            see_through = self.frame()
            see_through[0, 0, 3] = 0
            with self.assertRaisesRegex(WriterError, "not opaque"):
                w.write(see_through)
            with self.assertRaisesRegex(WriterError, "bytes, expected"):
                w.write(b"\xff" * 10)
        finally:
            w.abort()
        self.assertFalse((WORK / "bad.partial.mp4").exists())

    def test_the_soundtrack_must_be_exactly_as_long(self):
        wav = tone_wav(WORK / "short.wav", 60 * 1600 - 1)
        with self.assertRaisesRegex(WriterError, "need exactly 96000 \\(\\+1\\)"):
            VideoWriter(WORK / "x.mp4", 160, 90, frames=60, audio=wav)
        wav44 = tone_wav(WORK / "44k.wav", 1000, rate=44_100)
        with self.assertRaisesRegex(WriterError, "44100 Hz"):
            VideoWriter(WORK / "x.mp4", 160, 90, frames=60, audio=wav44)

    def test_bad_specs(self):
        with self.assertRaisesRegex(WriterError, "even"):
            VideoWriter(WORK / "x.mp4", 161, 90, frames=1)
        with self.assertRaisesRegex(WriterError, "at least one frame"):
            VideoWriter(WORK / "x.mp4", 160, 90, frames=0)
        with self.assertRaisesRegex(WriterError, "is an .mp4"):
            VideoWriter(WORK / "x.mov", 160, 90, frames=1)

    def test_skia_frames(self):
        import skia
        surface = skia.Surface(160, 90)
        surface.getCanvas().clear(skia.ColorSetRGB(250, 250, 250))
        out = WORK / "skia.mp4"
        with VideoWriter(out, 160, 90, frames=2) as w:
            w.write(surface)
            w.write(surface.makeImageSnapshot())
        self.assertEqual(probe.count_video_frames(out), 2)


# ---- touches: the cross-check --------------------------------------------------------------------

def td(gesture: str, down: float, kind: str = "tap", take: str = "take1b") -> touches.TouchDown:
    return touches.TouchDown(take, gesture, kind, down, down + 0.2, (0, 1), (0, 0), "test")


class CrossCheck(unittest.TestCase):
    DOWNS = [td("swipe-arrive", 10.672, "drag"), td("tap-arrive", 21.818), td("type-nom[1]", 66.333, "key")]

    def test_indicators_on_observed_touch_downs_pass(self):
        r = touches.cross_check([touches.RenderedTouch("take1b", 144, 10.672, "swipe-arrive"),
                                 touches.RenderedTouch("take1b", 176, 21.8181)], self.DOWNS,
                                required=[("take1b", "tap-arrive")])
        self.assertTrue(r.ok, r.problems)
        self.assertEqual([m.touch_down.gesture for m in r.matches], ["swipe-arrive", "tap-arrive"])
        self.assertIn("OK: every indicator", r.report())

    def test_every_way_an_indicator_can_be_wrong(self):
        r = touches.cross_check([
            touches.RenderedTouch("take1b", 145, 10.672),                    # off the 16th grid
            touches.RenderedTouch("take1b", 200, 23.0),                      # no touch-down there
            touches.RenderedTouch("take1b", 360, 66.333),                    # a typed key
            touches.RenderedTouch("take1b", 176, 21.818, "tap-libre"),       # named wrong
            touches.RenderedTouch("take1b", 180, 21.820),                    # twice on one touch-down
            touches.RenderedTouch("take9", 400, 1.0),                        # unknown take
        ], self.DOWNS, required=[("take1b", "tap-creer")])
        text = "\n".join(r.problems)
        for part in ("f145: the indicator is not on the 16th grid", "f200: take1b 23.000 s has no observed touch-down",
                     "f360: type-nom[1] is a typed key", "f176: drawn as 'tap-libre'",
                     "f180: tap-arrive already has an indicator at f176", "f400: no touch-down is known in take",
                     "take1b tap-creer: no indicator in the film"):
            self.assertIn(part, text)
        self.assertFalse(r.ok)


# ---- the real takes ------------------------------------------------------------------------------

@needs_material
class RealTakes(unittest.TestCase):
    """take1b, take2b and take5b as the storyboard uses them."""

    def test_take1b_pictures_at_the_storyboards_times(self):
        with Take("take1b") as t:
            self.assertEqual((t.count, t.width, t.height, t.timescale), (4524, 1206, 2622, 600))
            self.assertIsNotNone(t.scan)                       # scan.json checked: same file, same times
            rest = t.picture_at(10.000)                        # « the screen is at rest 0–10.66 s »
            self.assertEqual((rest.index, rest.ticks), (0, 0))
            before, after = t.picture_at(23.619), t.picture_at(23.620)
            self.assertEqual((after.ticks, before.ticks), (14172, 13809))
            # Fatou B.'s left border: navy while « Confirmé », the success green (#2D5016) once « Arrivé »
            self.assertTrue(np.allclose(before.rgba[1640, 50:56, :3].mean(0), (26, 27, 47), atol=3))
            self.assertTrue(np.allclose(after.rgba[1640, 50:56, :3].mean(0), (45, 80, 22), atol=3))
            # the scaffold #F6F7F9 decodes within a level
            self.assertTrue(np.allclose(rest.rgba[300, 20, :3], (246, 247, 249), atol=1))

    def test_storyboard_times_are_rounded_to_the_millisecond(self):
        with Take("take1b") as t:
            # « snackbar in 131.448 »: the picture at 131.44833 s; strictly, 131.448 s is still before it
            self.assertEqual((t.index_named(131.448), t.index_at(131.448)), (4502, 4501))
            self.assertEqual(t.index_named(66.333), t.index_at(t.time_named(66.333)))   # the key « Y »
            self.assertEqual(t.index_named(23.620), t.index_at(23.620))
            with self.assertRaisesRegex(TakeError, "names two pictures"):
                t.index_named(10.78417)                      # between pictures 1 tick apart (10.78333, 10.785)
        with Take("take5b") as t:
            self.assertEqual(t.index_named(26.174), 1)      # the notes round 26.17333 up

    def test_take1b_decode_matches_an_independent_decode(self):
        with Take("take1b") as t:
            i = t.index_at(23.620)
            mine = t.picture(i)
        out = subprocess.run([tools.ffmpeg(), "-v", "error", "-i", str(t.path), "-vf",
                              f"select=eq(n\\,{i}),scale=in_color_matrix=bt709:in_range=tv:"
                              "flags=accurate_rnd+full_chroma_int+bitexact,format=rgba",
                              "-fps_mode", "passthrough", "-frames:v", "1", "-f", "rawvideo", "-"],
                             capture_output=True, check=True).stdout
        theirs = np.frombuffer(out, np.uint8).reshape(mine.shape)
        self.assertTrue(np.array_equal(mine, theirs))

    def test_the_awa_k_number_is_blurred_on_the_fiche(self):
        with Take("take2b") as t:
            t.set_masks([Blur("awa-number", (97.0, 183.0, 235.3, 193.3), sigma_px=14, margin_pt=4,
                              from_s=6.435, to_s=30.96)])
            cover = t.masks.verify([t.index_at(6.5)])
            self.assertEqual(len(cover), 1)
            self.assertGreater(cover[0].detail_before, 100)
            self.assertLessEqual(cover[0].share_left, masks.LEGIBLE)

    def test_the_salon_number_is_blurred_while_it_scrolls(self):
        with Take("take5b") as t:
            track = ScrollTrack.from_csv(t.files.phone_rect_csv, t)
            t.set_masks([Blur("salon-number", (38, 873.5, 220, 892.5), sigma_px=14, from_s=27.146,
                              clip_y_pt=(0, 740), track=track)])
            cover = t.masks.verify()
            self.assertGreater(len(cover), 80)
            end = [c for c in cover if abs(c.time_s - 28.48) < 1e-3][0]
            self.assertEqual(end.box_px, (114, 1758, 660, 1816))   # x 38–220, y 586.2–605.2 pt at the end rest
            self.assertTrue(all(c.box_px[3] <= 2220 for c in cover))   # never on the bar (y ≥ 740 pt)


@needs_material
class RealTouchDowns(unittest.TestCase):
    def test_take1b_matches_the_storyboard(self):
        got = {d.gesture: round(d.down_s, 3) for d in touches.touch_downs("take1b")}
        want = {"swipe-arrive": 10.672, "tap-arrive": 21.818, "tap-libre": 32.165, "tap-service": 41.188,
                "tap-sans-numero": 49.440, "tap-nom": 57.930, "tap-creer": 130.265,
                "type-nom[1]": 66.333, "type-nom[2]": 73.052, "type-nom[3]": 80.282, "type-nom[4]": 87.548,
                "type-nom[5]": 95.083, "type-nom[6]": 105.115}
        for gesture, down in want.items():
            self.assertEqual(got[gesture], down, gesture)

    def test_other_takes(self):
        take3 = {d.gesture: d for d in touches.touch_downs("take3")}
        self.assertAlmostEqual(take3["tap-semaine"].down_s, 6.097, places=3)   # the animatic's f528
        take5b = touches.touch_downs("take5b")
        self.assertAlmostEqual(take5b[0].first_change_s, 26.173, places=3)     # « first moved picture 26.174 »
        self.assertIn("NOT followed", take5b[0].how)

    def test_the_two_logs_agree(self):
        files = touches.take_files("take1b")
        self.assertEqual(touches._from_jsonl(files.gestures_jsonl)["gestures"][0]["path"][-1], [250, 546, 608])
        self.assertEqual(touches.load_gestures("take1b")["gestures"][1]["id"], "tap-arrive")

    def test_the_30s_films_indicators(self):
        # the storyboard's touch-downs, on their frames (rows 7–15)
        downs = touches.touch_downs("take1b")
        rendered = [touches.RenderedTouch("take1b", f, s) for f, s in
                    ((144, 10.672), (176, 21.818), (280, 32.165), (320, 41.188), (336, 49.440),
                     (352, 57.930), (400, 130.265))]
        result = touches.cross_check(rendered, downs)
        self.assertTrue(result.ok, result.report())


if __name__ == "__main__":
    unittest.main()
