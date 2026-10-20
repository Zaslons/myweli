"""AUDIO: the clock, the BS.1770-4 meter, the score, the instruments, the
render, the master and events.json — proved on signals whose answer is known.

Run from tool/promo_reel:  python -m unittest tests.test_audio
"""

from __future__ import annotations

import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
import wave
from pathlib import Path

import numpy as np
from scipy import signal

ROOT = Path(__file__).resolve().parents[1]                 # tool/promo_reel
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from promo import timebase as tb                              # noqa: E402
from promo.audio import arrange, dsp, harmony, loudness, mix, wav  # noqa: E402
from promo.audio import instruments as ins                 # noqa: E402
from promo.audio import score as score_mod                 # noqa: E402
from promo.audio.build import build_cut, find_score        # noqa: E402
from promo.audio.__main__ import main as cli_main          # noqa: E402

FS = 48_000

# The storyboard's sound cues, transcribed by hand from promo-storyboard-full.md
# (« Beat by beat (30 s) », « The 15 s cut », « Music plan »): id -> frame.
STORYBOARD_30S = {
    "hook.stab": 0, "hook.word1": 0, "hook.word2": 8, "hook.word3": 16, "hook.pen": 0, "hook.cut": 32,
    "hook.cut_rim": 32, "hook.margin": 48, "strike1": 64, "strike2": 76, "strike3": 88, "strike1.slash": 64,
    "strike2.slash": 76, "strike3.slash": 88, "riser1": 64, "clap_roll1": 96, "air1.reverse": 112,
    "drop1.impact": 128, "swipe.touch": 144, "swipe.whoosh": 149, "swipe.open": 160, "swipe.open_wood": 160,
    "tap.touch": 176, "tap.close": 184, "arrive.log": 232, "arrive.pop": 232, "arrive.answer": 244,
    "arrive.air": 250, "whip1": 256, "slot.touch": 280, "slot.push": 286, "slot.rest": 304,
    "fill.touch1": 320, "fill.tape": 322, "fill.touch2": 336, "fill.touch3": 352, "fill.key1": 360,
    "fill.key2": 364, "fill.key3": 368, "fill.key4": 372, "fill.key5": 376, "fill.key6": 380,
    "create.drag": 384, "create.touch": 400, "create.close": 422, "create.done": 436, "create.chime": 436,
    "create.strike": 440, "create.filled": 448, "fiche.cut": 464, "fiche.log1": 472, "fiche.card1": 472,
    "fiche.log2": 480, "fiche.card2": 480, "fiche.log3": 488, "fiche.card3": 488, "riser2": 480,
    "lift.reverse": 496, "drop2.impact": 512, "drop2.whip": 512, "revenus.touch": 528, "revenus.tick1": 536,
    "revenus.tick2": 540, "revenus.tick3": 544, "revenus.land": 548, "revenus.ding": 548,
    "sentence.word1": 576, "sentence.word2": 584, "sentence.word3": 592, "sentence.word4": 600,
    "sentence.pop": 600, "page.cut": 640, "page.drag": 672, "riser3": 720, "breakdown.tail": 736,
    "clap_roll2": 744, "air2.reverse": 752, "reveal.impact": 768, "reveal.shimmer": 784, "reveal.glide": 804,
    "end.mark": 832, "end.store": 848, "end.store_log": 848, "end.site": 880, "end.site_log": 880,
    "end.underline": 896, "end.last": 928,
}
SPANS_30S = {"hook.pen": 24, "riser1": 108, "clap_roll1": 108, "air1.reverse": 128, "swipe.whoosh": 160,
             "tap.close": 190, "arrive.air": 256, "fill.tape": 334, "create.drag": 392, "create.close": 430,
             "riser2": 508, "lift.reverse": 512, "page.drag": 704, "riser3": 752, "clap_roll2": 752,
             "air2.reverse": 768, "reveal.glide": 824, "end.underline": 904}
STORYBOARD_15S = {
    "hook.stab": 0, "hook.word1": 0, "hook.word2": 8, "hook.word3": 16, "strike1": 24, "strike2": 32,
    "strike3": 40, "riser1": 16, "clap_roll1": 40, "air1.reverse": 48, "drop1.impact": 64, "swipe.touch": 64,
    "swipe.whoosh": 69, "swipe.open": 80, "tap.touch": 88, "tap.close": 96, "arrive.log": 144, "whip1": 160,
    "slot.touch": 168, "slot.push": 174, "create.touch": 196, "create.close": 218, "create.done": 232,
    "create.chime": 232, "create.strike": 236, "create.filled": 240, "drop2.impact": 256, "drop2.whip": 256,
    "revenus.touch": 272, "revenus.tick1": 280, "revenus.tick2": 284, "revenus.tick3": 288,
    "revenus.land": 292, "revenus.ding": 292, "reveal.impact": 320,
    "reveal.shimmer": 336, "reveal.glide": 356, "end.mark": 384, "end.store": 400, "end.store_log": 400,
    "end.site": 432, "end.site_log": 432, "end.underline": 448, "end.last": 480,
}
SPANS_15S = {"riser1": 44, "air1.reverse": 64, "reveal.glide": 376, "end.underline": 456}


def sine(freq: float, seconds: float, dbfs: float, phase: float = 0.0) -> np.ndarray:
    t = np.arange(int(round(seconds * FS))) / FS
    return 10 ** (dbfs / 20) * np.sin(2 * np.pi * freq * t + phase)


def stereo(*parts: tuple[float, float]) -> np.ndarray:
    """1-kHz tone in both channels, a sequence of (seconds, dBFS)."""
    x = np.concatenate([sine(1000, s, d) for s, d in parts])
    return np.stack([x, x], axis=1)


def dominant_hz(x: np.ndarray) -> float:
    n = 1 << 16
    spec = np.abs(np.fft.rfft(x * np.hanning(len(x)), n))
    return float(np.argmax(spec) * FS / n)


# ══ the clock ══════════════════════════════════════════════════════════════

class TestTimebase(unittest.TestCase):
    def test_formulas(self):
        self.assertEqual(tb.frame_of(1, 1, 0), 0)
        self.assertEqual(tb.frame_of(3, 1, 0), 128)              # DROP 1
        self.assertEqual(tb.frame_of(3, 2, 0), 144)              # the swipe's touch-down
        self.assertEqual(tb.frame_of(14, 4, 3), 892)
        self.assertEqual(tb.sample_of_frame(1), 1600)
        self.assertEqual(tb.parse_pos("9.3.1").frame, 548)       # the counter lands
        self.assertEqual(tb.parse_pos("9.3.1").sample, 548 * 1600)
        for n in range(1, 15):                                    # « Bar n starts at frame (n-1) x 64 »
            self.assertEqual(tb.frame_of(n), (n - 1) * 64)

    def test_beat_is_exactly_16_frames(self):
        self.assertEqual(tb.SAMPLES_PER_BEAT, 25_600)
        self.assertAlmostEqual(tb.SAMPLES_PER_BEAT / FS, 60 / 112.5, places=12)
        self.assertEqual(tb.FRAMES_PER_BAR * 15, 960)            # the 30-s cut: 14 bars + the owner's outro

    def test_round_trip_every_16th(self):
        for frame in range(0, 960, 4):
            p = tb.pos_of_frame(frame)
            self.assertEqual(p.frame, frame)
            self.assertEqual(tb.parse_pos(str(p)), p)
            self.assertEqual(p.sample, frame * 1600)

    def test_refuses(self):
        for bad in ("0.1.0", "1.5.0", "1.1.4", "x", "1.1.0.0", "3.1.x"):
            with self.subTest(bad=bad), self.assertRaises(tb.PositionError):
                tb.parse_pos(bad)
        with self.assertRaises(tb.PositionError):
            tb.pos_of_frame(149)                                   # off the 16th grid
        with self.assertRaises(tb.PositionError):
            tb.pos_of_step(3, 16)

    def test_one_clock(self):
        # the audio engine reads the same promo/timebase.py as every other module:
        # the storyboard's shorthand is a position here too, written back canonically
        self.assertEqual(tb.parse_pos("3.1"), tb.parse_pos("3.1.0"))
        self.assertEqual(str(tb.parse_pos("5.2&")), "5.2.2")
        self.assertIs(tb.PositionError, tb.TimeBaseError)
        self.assertEqual(tb.pos_of_step(9, 10), tb.Pos(9, 3, 2))
        self.assertLess(tb.Pos(3, 4, 3), tb.Pos(4, 1, 0))         # positions order like the music
        import promo.audio
        self.assertFalse((Path(promo.audio.__file__).parent / "_time.py").exists())


# ══ the meter ══════════════════════════════════════════════════════════════

class TestLoudness(unittest.TestCase):
    def test_k_filter_matches_the_published_coefficients(self):
        for (b, a), (b2, a2) in zip(loudness.k_filter_derived(48_000), (loudness.SHELF_48K, loudness.RLB_48K)):
            np.testing.assert_allclose(b, b2, atol=1e-9)
            np.testing.assert_allclose(a, a2, atol=1e-9)

    def test_1khz_sine_at_minus_20_dbfs_mono(self):
        """BS.1770-4: L = -0.691 + 10 log10(G z), z the K-weighted mean square.
        A -20 dBFS sine has mean square 0.1^2 / 2 = 0.005; the K filter's gain
        at 1 kHz is computed here from the PUBLISHED coefficients, not from
        the module: expected = -0.691 + 10 log10(0.005 |H(1 kHz)|^2) = -23.0036."""
        _, h1 = signal.freqz([1.53512485958697, -2.69169618940638, 1.19839281085285],
                             [1.0, -1.69065929318241, 0.73248077421585], worN=[1000.0], fs=FS)
        _, h2 = signal.freqz([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621], worN=[1000.0], fs=FS)
        expected = -0.691 + 10 * np.log10(0.005 * abs(h1[0] * h2[0]) ** 2)
        measured = loudness.integrated(sine(1000, 10, -20))
        self.assertAlmostEqual(expected, -23.0036, places=3)
        self.assertLess(abs(measured - expected), 0.01)
        self.assertLess(abs(measured - (-23.0)), 0.1)

    def test_ebu_3341_cases(self):
        cases = {
            "1: stereo -23 dBFS": (stereo((20, -23)), -23.0),
            "2: stereo -33 dBFS": (stereo((20, -33)), -33.0),
            "3: -36/-23/-36 (relative gate)": (stereo((2, -36), (12, -23), (2, -36)), -23.0),
            "4: -72/-36/-23/-36/-72": (stereo((2, -72), (2, -36), (12, -23), (2, -36), (2, -72)), -23.0),
            "5: -26/-20/-26": (stereo((4, -26), (4.02, -20), (4, -26)), -23.0),
        }
        for name, (x, want) in cases.items():
            with self.subTest(name):
                self.assertLess(abs(loudness.integrated(x) - want), 0.1)

    def test_momentary_and_short_term_of_a_steady_tone(self):
        x = stereo((6, -23))
        self.assertLess(np.max(np.abs(loudness.momentary(x) + 23.0)), 0.05)
        self.assertLess(np.max(np.abs(loudness.short_term(x) + 23.0)), 0.05)

    def test_loudness_range_ebu_3342(self):
        self.assertLess(abs(loudness.loudness_range(stereo((20, -20), (20, -30))) - 10.0), 1.0)
        self.assertLess(abs(loudness.loudness_range(stereo((20, -20), (20, -15))) - 5.0), 1.0)

    def test_true_peak_finds_the_peak_between_samples(self):
        x = dsp.fade(sine(12_000, 1, 0.0, phase=np.pi / 4), 480, 480)   # samples at ±0.707, peak 1.0 between them
        self.assertAlmostEqual(loudness.sample_peak_db(x), -3.01, places=2)
        self.assertLess(abs(loudness.true_peak_db(x)), 0.05)
        self.assertLess(abs(loudness.true_peak_db(dsp.fade(sine(997, 1, -6.0), 480, 480)) + 6.0), 0.01)


# ══ notes and chords ═══════════════════════════════════════════════════════

class TestHarmony(unittest.TestCase):
    def test_notes(self):
        self.assertEqual(harmony.parse_note("C2"), 36)
        self.assertEqual(harmony.parse_note("E♭2"), 39)
        self.assertEqual(harmony.parse_note("Eb2"), 39)
        self.assertEqual(harmony.parse_note("F#1"), 30)
        self.assertAlmostEqual(harmony.note_hz("A4"), 440.0)
        self.assertAlmostEqual(harmony.note_hz("C2"), 65.406, places=3)

    def test_the_four_voicings_lead_by_step(self):
        want = {"Cm9": [51, 55, 58, 62], "F9": [51, 55, 57, 60], "A♭maj9": [51, 55, 58, 60], "G7♭9": [53, 56, 59, 62]}
        for symbol, notes in want.items():
            self.assertEqual(harmony.parse_chord(symbol).voicing(), notes, symbol)

    def test_log_degrees_follow_the_chord(self):
        cm9, f9 = harmony.parse_chord("Cm9"), harmony.parse_chord("F9")
        self.assertEqual(cm9.degree_note("1"), 36)               # C2
        self.assertEqual(cm9.degree_note("5,"), 31)              # G1, the storyboard's log G1
        self.assertEqual(cm9.degree_note("7,"), 34)              # B♭1
        self.assertEqual(cm9.degree_note("3"), 39)               # E♭2
        self.assertEqual(f9.degree_note("3"), 45)                # A2: F9's major third
        self.assertEqual(f9.degree_note("8"), 53)
        with self.assertRaises(harmony.HarmonyError):
            harmony.parse_chord("Cm13")


# ══ the score format ═══════════════════════════════════════════════════════

MINIMAL = {
    "score": 1, "cut": "t", "bars": 2, "tempo": 112.5, "key": "C minor", "swing": 0.56,
    "sections": [{"name": "a", "bars": "1-2"}],
    "chords": {1: "Cm9"},
    "patterns": {"four": "x...|x...|x...|x..."},
    "tracks": {"kick": {"instrument": "kick", "bars": {"1-2": "four"}}},
    "cues": [{"id": "a.click", "kind": "click", "pos": "1.2.0"}],
}


def variant(**changes) -> dict:
    data = json.loads(json.dumps(MINIMAL))
    data.update(changes)
    return data


class TestScore(unittest.TestCase):
    def refused(self, data: dict) -> str:
        with self.assertRaises(score_mod.ScoreError) as cm:
            score_mod.parse(data, source="t.yaml")
        return str(cm.exception)

    def test_grids(self):
        self.assertEqual(score_mod.split_grid("x...|x...|x...|x..."), list("x...x...x...x..."))
        self.assertEqual(score_mod.split_grid("1! . . 1 | . . 5, . | . . 7, 1 | . . 3 ."),
                         ["1!", ".", ".", "1", ".", ".", "5,", ".", ".", ".", "7,", "1", ".", ".", "3", "."])
        self.assertEqual(score_mod.parse_bars("3-6", 14), [3, 4, 5, 6])
        self.assertEqual(score_mod.parse_bars("1-2, 5", 14), [1, 2, 5])

    def test_minimal_loads(self):
        sc = score_mod.parse(MINIMAL)
        self.assertEqual(sc.frames, 128)
        self.assertEqual(sc.cue("a.click").frame, 16)

    def test_refusals_name_the_problem(self):
        bad_cue = lambda **c: variant(cues=[{"id": "a.x", "kind": "click", "pos": "1.1.0", **c}])  # noqa: E731
        self.assertIn("past the cut's 2 bars", self.refused(bad_cue(pos="3.2.0")))
        self.assertIn("is not one of", self.refused(bad_cue(kind="boom")))
        self.assertIn("has no parameter 'lpf'", self.refused(bad_cue(lpf=600)))
        self.assertIn("takes no end or dur", self.refused(bad_cue(dur=4)))
        self.assertIn("id used twice", self.refused(variant(cues=[{"id": "a.x", "kind": "click", "pos": "1.1.0"},
                                                                  {"id": "a.x", "kind": "click", "pos": "1.2.0"}])))
        self.assertIn("needs 'note'", self.refused(bad_cue(kind="log")))
        self.assertIn("spans time", self.refused(bad_cue(kind="riser")))
        self.assertIn("swing applies to shakers and hats only",
                      self.refused(variant(tracks={"kick": {"instrument": "kick", "swing": True, "bars": {1: "four"}}})))
        self.assertIn("a bar has 16", self.refused(variant(tracks={"kick": {"instrument": "kick",
                                                                             "bars": {1: "x...x..."}}})))
        self.assertIn("not a degree", self.refused(variant(tracks={"log": {"instrument": "log", "bars": {
            1: "1 . . 4 | . . . . | . . . . | . . . ."}}})))
        self.assertIn("bar 1 needs a chord", self.refused(variant(chords={2: "Cm9"})))
        self.assertIn("fixed at 112.5", self.refused(variant(tempo=120)))
        self.assertIn("cover bars 1-2", self.refused(variant(sections=[{"name": "a", "bars": 1}])))

    def test_the_shipped_scores(self):
        for name, bars in (("score_30s.yaml", 15), ("score_15s.yaml", 8)):        # + the owner's outro bar
            sc = score_mod.load(find_score(name))
            self.assertEqual(sc.bars, bars)
            self.assertEqual(sc.frames, bars * 64)
            self.assertEqual([c.chord.symbol for c in sc.chords][:1], ["Cm9"])

    def test_log_patterns_a_and_b(self):
        sc = score_mod.load(find_score("score_30s.yaml"))
        hits = lambda name: [i for i, tok in enumerate(sc.patterns[name]) if tok != "."]  # noqa: E731
        self.assertEqual(hits("log_a"), [0, 3, 6, 10, 11, 14])
        self.assertEqual(hits("log_b"), [0, 6, 9, 12])

    def test_every_storyboard_cue_is_scored_on_its_frame(self):
        for name, table, spans in (("score_30s.yaml", STORYBOARD_30S, SPANS_30S),
                                   ("score_15s.yaml", STORYBOARD_15S, SPANS_15S)):
            sc = score_mod.load(find_score(name))
            for cid, frame in table.items():
                with self.subTest(score=name, cue=cid):
                    self.assertEqual(sc.cue(cid).frame, frame)
            for cid, end in spans.items():
                with self.subTest(score=name, span=cid):
                    self.assertEqual(sc.cue(cid).end_frame, end)

    def test_the_store_and_site_lines_have_their_soft_cues(self):
        """The owner's end card (2026-10-20, « Both stores, post later »): « Sur
        l’App Store et Google Play » and, last, « myweli.com » — each alone on
        its own cue, a soft glint over a log, on the beat grid."""
        for name, store, site in (("score_30s.yaml", 848, 880), ("score_15s.yaml", 400, 432)):
            sc = score_mod.load(find_score(name))
            for cid, frame in (("end.store", store), ("end.site", site)):
                cue = sc.cue(cid)
                self.assertEqual((cue.kind, cue.frame, cue.frame % 16), ("glint", frame, 0))
                self.assertLess(cue.gain, -6)                     # small and soft
                self.assertEqual(sc.cue(cid + "_log").frame, frame)
            self.assertLess(store, site)                          # the site last


# ══ the arranger ═══════════════════════════════════════════════════════════

class TestArrange(unittest.TestCase):
    def test_a_cue_replaces_the_grid_hit_and_needs_no_track(self):
        data = variant(cues=[{"id": "a.kick", "kind": "kick", "pos": "1.2.0", "vel": 1.0},
                             {"id": "a.log", "kind": "log", "pos": "2.1.0", "note": "C2"}])
        r = arrange.render(score_mod.parse(data))
        kicks = [p for p in r.placed if p.kind == "kick"]
        self.assertEqual(len(kicks), 8)                           # 2 bars of four, one of them now the cue
        at = tb.parse_pos("1.2.0").sample
        self.assertEqual([p.source for p in kicks if p.sample == at], ["cue"])
        logs = [(p.label, p.sample) for p in r.placed if p.kind == "log"]
        self.assertEqual(logs, [("a.log", tb.parse_pos("2.1.0").sample)])   # no log track: a default one
        self.assertGreater(np.abs(r.stems["log"]).max(), 0.1)

    def test_the_log_is_one_voice(self):
        data = variant(cues=[{"id": "a.one", "kind": "log", "pos": "1.1.0", "note": "C2", "decay": 0.9},
                             {"id": "a.two", "kind": "log", "pos": "1.1.3", "note": "G1"}])
        r = arrange.render(score_mod.parse(data))
        first = next(p for p in r.placed if p.label == "a.one")
        self.assertEqual(first.length, 3 * tb.SAMPLES_PER_STEP)   # cut where the next hit starts


# ══ the instruments ════════════════════════════════════════════════════════

class TestInstruments(unittest.TestCase):
    def test_log_drum(self):
        f0 = harmony.note_hz("C2")
        x = ins.log_drum(f0, 0.9)
        self.assertEqual(x[0], 0.0)                               # starts on its zero crossing, at the onset
        self.assertGreater(np.abs(x[:96]).max(), 0.3)             # and is loud within 2 ms
        crossings = lambda seg: np.sum(np.diff(np.signbit(seg)) != 0) / 2 / (len(seg) / FS)  # noqa: E731
        self.assertGreater(crossings(x[:240]), 2 * f0)            # the downward pitch transient (first 5 ms)
        tail = x[int(0.15 * FS): int(0.45 * FS)]
        self.assertLess(abs(dominant_hz(tail) - f0), 3.0)         # settles on f0
        head = x[: int(0.03 * FS)]
        spec = np.abs(np.fft.rfft(head, 1 << 15))
        freqs = np.fft.rfftfreq(1 << 15, 1 / FS)
        wood = spec[(freqs > 2.2 * f0) & (freqs < 2.7 * f0)].max()
        self.assertGreater(wood, 0.05 * spec.max())               # the ~2.4 f0 wood partial is there early

    def test_glide_and_low_pass(self):
        x = ins.log_drum(harmony.note_hz("C2"), 0.9, glide_from=harmony.note_hz("G1"), decay_s=0.5)
        self.assertLess(abs(dominant_hz(x[int(0.2 * FS): int(0.6 * FS)]) - 65.4), 3.0)
        stab = ins.log_drum(65.4, 1.0, lp=600)
        spec = np.abs(np.fft.rfft(stab[: FS // 4]))
        freqs = np.fft.rfftfreq(FS // 4, 1 / FS)
        self.assertLess(spec[freqs > 3000].max(), 0.01 * spec.max())

    def test_kick_sweeps_165_to_45(self):
        x = ins.kick(1.0)
        first_half_cycle = np.argmax(np.diff(np.signbit(x[48:])) != 0) + 48      # past the 1-ms click
        self.assertLess(first_half_cycle / FS, 1 / (2 * 100))                    # starts above 100 Hz
        late = x[int(0.15 * FS): int(0.45 * FS)]
        self.assertLess(abs(dominant_hz(late) - 45), 4)

    def test_ui_click_is_original_3k2_8ms_with_3_percent_pitch(self):
        pitches = []
        for seed in range(20):
            x = ins.ui_click(seed=seed)
            self.assertEqual(len(x), int(0.008 * FS))
            pitches.append(dominant_hz(x))
        self.assertTrue(all(3200 * 0.96 < p < 3200 * 1.04 for p in pitches), pitches)
        self.assertGreater(np.ptp(pitches), 40)                   # the pitch really moves per tap

    def test_chime_is_a_rising_fifth(self):
        x = ins.chime(f=783.99, gap=0.09)[:, 0]
        first = dominant_hz(x[: int(0.08 * FS)])
        second = dominant_hz(x[int(0.4 * FS): int(0.8 * FS)] - 0)
        self.assertLess(abs(first - 783.99), 6)
        self.assertTrue(abs(second - 783.99 * 2 ** (7 / 12)) < 8 or abs(second - 783.99) < 8)

    def test_reverb_rt60(self):
        for rt in (2.5, 2.8):
            self.assertLess(abs(dsp.schroeder_rt60(dsp.reverb_ir(rt)) - rt) / rt, 0.12)

    def test_whip_crests_three_frames_in(self):
        x = ins.whoosh("whip", peak_samples=3 * 1600, seed="t")
        env = np.convolve(np.abs(x).mean(axis=1), np.ones(480) / 480, mode="same")
        self.assertLess(abs(int(np.argmax(env)) - 4800), 1600)

    def test_riser_is_gated_and_stops_dead(self):
        n = 44 * 1600
        x = ins.riser(n, cells=[(0, 12800), (32 * 1600, 6400)], seed="t")
        self.assertEqual(len(x), n)
        late = np.abs(x[int(0.75 * n):]).mean(axis=1)
        self.assertGreater((late < 1e-6).mean(), 0.3)             # gaps between the gates
        self.assertLess(np.abs(x[-10:]).max(), np.abs(x).max() * 0.05)


# ══ the mix ════════════════════════════════════════════════════════════════

class TestMix(unittest.TestCase):
    def test_limiter_holds_the_true_peak(self):
        g = np.random.default_rng(1)
        x = g.standard_normal((FS * 3, 2)) * 0.3
        x[FS: FS + 2000] *= 8                                     # a +18 dB burst
        x[2 * FS: 2 * FS + 4] = 3.0
        y, gain = mix.limit(x, -1.0)
        self.assertLessEqual(loudness.true_peak_db(y), -1.0 + 0.05)
        self.assertTrue(np.all(gain <= 1.0))
        self.assertGreater(gain[: FS // 2].min(), 0.6)            # it leaves the quiet part alone

    def test_sidechain_and_ducking_from_known_times(self):
        s = mix.MixSettings()
        n = FS * 2
        g = mix.sidechain_gain(n, [FS // 4], [3 * FS // 2], s)
        self.assertAlmostEqual(dsp.db(g[FS // 4]), -5.0, places=1)       # 5 dB on the kick
        self.assertAlmostEqual(dsp.db(g[3 * FS // 2]), -3.0, places=1)   # 3 dB on the log
        both = mix.sidechain_gain(n, [FS], [FS], s)
        self.assertAlmostEqual(dsp.db(both[FS]), -6.0, places=1)         # never more than 6
        self.assertGreater(dsp.db(g[FS // 4 + int(0.5 * FS)]), -0.25)    # recovered by the next beat (0.53 s)
        self.assertLess(dsp.db(g[FS // 4 - int(0.002 * FS)]), -1.0)      # the duck starts just before the hit
        d = mix.duck_gain(n, [FS], depth_db=3.0, hold_ms=40.0)
        self.assertAlmostEqual(dsp.db(d[FS + int(0.02 * FS)]), -3.0, places=2)
        self.assertAlmostEqual(dsp.db(d[FS + int(0.05 * FS)]), 0.0, places=2)

    def test_mono_below_150hz(self):
        side_low = np.stack([sine(60, 2, -10), -sine(60, 2, -10)], axis=1)
        side_high = np.stack([sine(2000, 2, -10), -sine(2000, 2, -10)], axis=1)
        y = mix.mono_bass(side_low, 150.0)
        self.assertLess(dsp.db(np.abs(y[FS // 2: -FS // 2]).max()) + 10, -60)     # 60 Hz side: gone
        y = mix.mono_bass(side_high, 150.0)
        self.assertLess(abs(dsp.db(np.abs(y[FS // 2: -FS // 2, 0]).max()) + 10), 0.1)   # 2 kHz side: kept


# ══ the render, the master, events.json ════════════════════════════════════

def air_on(audio: np.ndarray, events: dict) -> dict:
    """verify (d)'s AIR rule on a master as written."""
    from promo.verify import air_levels
    return air_levels(audio, events)


def air_after_aac(wav_path: Path, events: dict) -> dict:
    """The AIR check verify runs on the MP4, on the master passed through the
    film's own AAC encoder (its low-pass takes a little off the reverse
    cymbal's air: −0.5 dB on AIR 1)."""
    import subprocess
    from promo.media import tools, writer
    from promo.verify import air_levels
    m4a = wav_path.with_suffix(".m4a")
    subprocess.run([tools.ffmpeg(), "-v", "error", "-y", "-i", str(wav_path), "-c:a", "aac", "-b:a",
                    f"{writer.DEFAULT_AUDIO_BITRATE_K}k", "-ar", "48000", str(m4a)], check=True)
    raw = subprocess.run([tools.ffmpeg(), "-v", "error", "-i", str(m4a), "-f", "f32le", "-ac", "2", "-ar", "48000",
                          "-"], capture_output=True, check=True).stdout
    return air_levels(np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64), events)


class TestBuild15s(unittest.TestCase):
    """The 15-s cut built end to end, files and all."""

    @classmethod
    def setUpClass(cls):
        cls.out = Path(tempfile.mkdtemp(prefix="promo-audio-15s-"))
        cls.result = build_cut("score_15s.yaml", cls.out)
        cls.events = json.loads((cls.out / "events.json").read_text())
        cls.meter = json.loads((cls.out / "meter.json").read_text())
        cls.audio, cls.rate = wav.read(cls.out / "track.wav")

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.out, ignore_errors=True)

    def test_files(self):
        for name in ("track.wav", "events.json", "meter.json", "spectrogram.png", "waveform.png"):
            self.assertTrue((self.out / name).stat().st_size > 1000, name)
        with wave.open(str(self.out / "track.wav")) as w:
            self.assertEqual((w.getnchannels(), w.getsampwidth(), w.getframerate()), (2, 3, 48_000))
            self.assertEqual(w.getnframes(), 512 * 1600)

    def test_the_air_beat_is_near_silence(self):
        """The 15-s cut's one AIR (f48–63) was 4.3 LU under its groove (strike
        3's tail rang into it), then 5.9 on the master: ≥ 7 LU under, on the
        master AND after AAC (the reverse 3 dB down, strike 3 lighter, the
        breath 3 dB down: 8.4 LU on the master as written)."""
        from promo.verify import AIR_UNDER_LU
        self.assertEqual(AIR_UNDER_LU, 7.0)
        for a in (air_on(self.audio, self.events), air_after_aac(self.out / "track.wav", self.events)):
            self.assertEqual([r["cue"] for r in a["air"]], ["air1.reverse"])
            self.assertTrue(a["ok"], a)

    def test_master_targets(self):
        self.assertLess(abs(loudness.integrated(self.audio) + 14.0), 0.1)
        self.assertLessEqual(loudness.true_peak_db(self.audio), -1.0)
        self.assertTrue(self.meter["target"]["integrated_ok"] and self.meter["target"]["true_peak_ok"])
        self.assertLess(self.meter["mono"]["side_below_150hz_db"], -20)
        ff = self.meter.get("ffmpeg_ebur128")
        if ff and ff["integrated_lufs"] is not None:              # cross-check, when ffmpeg is installed
            self.assertLess(abs(ff["integrated_lufs"] + 14.0), 0.2)
            self.assertLessEqual(ff["true_peak_dbfs"], -1.0 + 0.1)

    def test_the_outro_rings_out(self):
        """The 15-s outro (bar 8) as the 30-s's: the last log and chord on
        f480 ring out before the end — ≥ 20 dB down by f502, the last 100 ms
        ≥ 30 dB under the hit (review round 3: 4.8 dB, then chopped)."""
        from promo.verify import outro_tail
        tail = outro_tail(self.audio, self.events)
        self.assertEqual((tail["cue"], tail["frame"]), ("end.last", 480))
        self.assertTrue(tail["ok"], tail)
        self.assertLess(np.abs(self.audio[-1]).max(), 1e-4)

    def test_events_frames_are_the_cue_positions_exactly(self):
        sc = self.result.render.score
        by_id = {c["id"]: c for c in self.events["cues"]}
        self.assertEqual(set(by_id), {c.id for c in sc.cues})
        for cue in sc.cues:
            e = by_id[cue.id]
            self.assertEqual(e["pos"], str(cue.pos))
            self.assertEqual(e["frame"], cue.pos.frame + cue.offset)
            self.assertEqual(e["sample"], e["frame"] * 1600)
        for cid, frame in STORYBOARD_15S.items():
            self.assertEqual(by_id[cid]["frame"], frame, cid)
        self.assertEqual(self.events["frames"], 512)
        self.assertEqual([b["frame"] for b in self.events["bars"]], [64 * k for k in range(8)])
        self.assertEqual(len(self.events["beats"]), 32)
        for b in self.events["beats"]:
            self.assertEqual(b["sample"], b["frame"] * 1600)
            self.assertEqual(tb.parse_pos(b["pos"]).frame, b["frame"])

    def test_clicks_start_on_their_frame(self):
        """A/V sync: a click's onset / 1600 is its frame — silence the frame
        before (the UI bus has nothing else), sound within 0.5 ms."""
        ui = self.result.render.stems["ui"].mean(axis=1)
        clicks = [c for c in self.events["cues"] if c["kind"] in ("click", "key", "tick")]
        self.assertGreater(len(clicks), 5)
        for c in clicks:
            s = c["sample"]
            self.assertLess(np.abs(ui[s - 1600: s]).max(), 1e-9, c["id"])
            self.assertGreater(np.abs(ui[s: s + 24]).max(), 1e-3, c["id"])

    def test_grid_rules(self):
        r = self.result.render
        kicks = [p for p in r.placed if p.kind == "kick"]
        self.assertTrue(all(p.sample == p.grid_sample for p in kicks))          # kick: unswung, on the grid
        shakers = [p for p in r.placed if p.kind == "shaker"]
        for p in shakers:
            late = p.sample - p.grid_sample
            odd = (p.grid_sample // tb.SAMPLES_PER_STEP) % 2 == 1
            swing = 768 if odd else 0                                           # 56 %: 0.06 of an 8th
            self.assertLessEqual(abs(late - swing), 5 * 48)                     # ± 5 ms humanise
        logs = [p.sample for p in r.placed if p.kind == "log"]
        self.assertEqual(len(logs), len(set(logs)))                             # one voice, one hit per sample
        land = self.result.render.score.cue("revenus.land").sample
        self.assertFalse([p for p in r.placed if p.kind == "log" and p.source == "grid" and p.grid_sample == land])

    def test_frame_zero_is_never_silent(self):
        self.assertGreater(np.abs(self.audio[:1600]).max(), 0.05)


class TestBuild30s(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.out = Path(tempfile.mkdtemp(prefix="promo-audio-30s-"))
        cls.result = build_cut("score_30s.yaml", cls.out, pictures=False, ffmpeg_check=False)
        cls.audio, _ = wav.read(cls.out / "track.wav")
        cls.events = json.loads((cls.out / "events.json").read_text())

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.out, ignore_errors=True)

    def test_master_and_length(self):
        self.assertEqual(len(self.audio), 960 * 1600)
        self.assertLess(abs(loudness.integrated(self.audio) + 14.0), 0.1)
        self.assertLessEqual(loudness.true_peak_db(self.audio), -1.0)

    def test_every_storyboard_cue_lands_on_its_frame(self):
        by_id = {c["id"]: c for c in self.events["cues"]}
        for cid, frame in STORYBOARD_30S.items():
            self.assertEqual(by_id[cid]["frame"], frame, cid)
            self.assertEqual(by_id[cid]["sample"], frame * 1600, cid)
        for cid, end in SPANS_30S.items():
            self.assertEqual(by_id[cid]["end_frame"], end, cid)
        self.assertEqual(len(self.events["beats"]), 60)

    def test_both_air_beats_are_near_silence(self):
        """Review M2: AIR 2 (f752–767) played at the groove's level (0.3 LU
        under it); riser 3 now stops dead on the cut, the breakdown's tail is
        short and the pad is muted. Round 3: both ≥ 7 LU under the groove on
        the MASTER as well as after AAC (AIR 1 was 5.8 on the master): the
        reverses 4 / 2 dB down and AIR 1's breath 3 dB down."""
        for a in (air_on(self.audio, self.events), air_after_aac(self.out / "track.wav", self.events)):
            rows = {r["cue"]: r for r in a["air"]}
            self.assertEqual(sorted(rows), ["air1.reverse", "air2.reverse"])
            self.assertTrue(a["ok"], a)
            self.assertGreaterEqual(min(r["under_groove_lu"] for r in rows.values()), 7.0)
        by_id = {c["id"]: c for c in self.events["cues"]}
        self.assertLessEqual(by_id["riser3"]["end_frame"], 752)              # nothing rises into the black

    def test_the_outro_bar(self):
        """The owner's added bar 15 (2026-10-19): calm — no kick, clap or hat;
        the shaker thins; the underline's pen on the downbeat, as long as the
        stroke draws (8 frames); the last log and the last chord on beat 3;
        its tail RINGS OUT before the end (review round 3: the chord was held
        to the last sample and the end fade chopped it): ≥ 20 dB down by f950,
        the last 100 ms ≥ 30 dB under the hit, the second half of the bar no
        louder than the first, silence on the last sample."""
        r = self.result.render
        bar = tb.SAMPLES_PER_BAR
        b15 = 14 * bar

        def kinds(a: int) -> list[str]:
            return [p.kind for p in r.placed if a <= p.grid_sample < a + bar]

        self.assertFalse({"kick", "clap", "hat"} & set(kinds(b15)))
        self.assertLess(kinds(b15).count("shaker"), kinds(b15 - bar).count("shaker") / 2)
        by_id = {c["id"]: c for c in self.events["cues"]}
        u = by_id["end.underline"]
        self.assertEqual((u["kind"], u["frame"], u["end_frame"]), ("pen_scratch", 896, 904))
        self.assertEqual((by_id["end.last"]["kind"], by_id["end.last"]["pos"]), ("log", "15.3.0"))
        self.assertIn("rhodes", kinds(b15))                                   # the last chord
        rms = lambda a, b: 20 * np.log10(np.sqrt(np.mean(self.audio[a * 1600:b * 1600] ** 2)) + 1e-12)  # noqa: E731
        self.assertGreater(rms(950, 957), -50)                                # the tail still rings …
        self.assertLess(np.abs(self.audio[-1]).max(), 1e-4)                   # … into the end fade
        from promo.verify import outro_tail
        tail = outro_tail(self.audio, self.events)
        self.assertEqual(tail["cue"], "end.last")
        self.assertTrue(tail["ok"], tail)                                     # … and out, before it
        self.assertLessEqual(loudness.segment(self.audio, (928 * 1600, 960 * 1600)),
                             loudness.segment(self.audio, (896 * 1600, 928 * 1600)) + 0.5)   # calm to the end

    def test_the_hook_is_darker_than_the_drop(self):
        """« A dark, staccato hook »: bar 1 sits well under DROP 1 (4.7 LU as mixed)."""
        bar = tb.SAMPLES_PER_BAR
        hook = loudness.integrated(self.audio[: bar])
        drop = loudness.integrated(self.audio[2 * bar: 4 * bar])
        self.assertGreater(drop - hook, 3.5)


class TestCli(unittest.TestCase):
    def test_find_score(self):
        self.assertEqual(find_score("30s").name, "score_30s.yaml")
        self.assertEqual(find_score("score_15s.yaml").name, "score_15s.yaml")
        with self.assertRaises(FileNotFoundError):
            find_score("score_99s.yaml")

    def test_refused_score_exits_1(self):
        tmp = Path(tempfile.mkdtemp(prefix="promo-audio-cli-"))
        try:
            bad = tmp / "bad.yaml"
            bad.write_text("score: 1\ncut: x\nbars: 1\nchords: {1: Cm9}\nsections: [{name: a, bars: 1}]\n"
                           "cues: [{id: a.b, kind: click, pos: 2.1.0}]\n")
            err = io.StringIO()
            with contextlib.redirect_stderr(err):
                self.assertEqual(cli_main(["--score", str(bad), "--out", str(tmp / "out")]), 1)
            self.assertIn("past the cut's 1 bars", err.getvalue())
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
