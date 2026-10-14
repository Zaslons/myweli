"""The box reader's two bit-level parsers, on bytes whose meaning is known:
parameter sets copied out of real files, and ones written here bit by bit."""

from __future__ import annotations

import unittest

import mp4

# avcC's SPS of a film this tool encoded (886 x 1920, High, Level 4.0) and of
# the simulator recorder's probe clip of 2026-10-13 (1206 x 2622, Level 5.0).
FILM_SPS = bytes.fromhex("27640028ac5680e00f1e6e6a02020204")
PROBE_SPS = bytes.fromhex("27640032ac565013005279aa6a181a0204")
# The esds payload AVFoundation wrote for the silent track: AAC-LC, 48 kHz,
# stereo, 256 000 bit/s declared.
FILM_ESDS = bytes.fromhex("000000000380808022000000048080801440140018000003e8000003e80005808080021190068080800102")


class BitWriter:
    def __init__(self):
        self.bits: list[int] = []

    def u(self, n: int, v: int) -> "BitWriter":
        self.bits += [(v >> (n - 1 - i)) & 1 for i in range(n)]
        return self

    def ue(self, v: int) -> "BitWriter":
        code = v + 1
        return self.u(code.bit_length() - 1, 0).u(code.bit_length(), code)

    def se(self, v: int) -> "BitWriter":
        return self.ue(2 * v - 1 if v > 0 else -2 * v)

    def nal(self) -> bytes:
        bits = self.bits + [1]
        bits += [0] * (-len(bits) % 8)
        raw = bytes(int("".join(map(str, bits[i:i + 8])), 2) for i in range(0, len(bits), 8))
        out, zeros = bytearray([0x67]), 0
        for byte in raw:                      # emulation prevention, as an encoder inserts it
            if zeros >= 2 and byte <= 3:
                out.append(3)
                zeros = 0
            out.append(byte)
            zeros = zeros + 1 if byte == 0 else 0
        return bytes(out)


def sps(profile=100, level=40, width_mbs=56, height_units=120, frame_mbs_only=1,
        crop=(0, 5, 0, 0), chroma=1, scaling=False, vui=None) -> bytes:
    w = BitWriter().u(8, profile).u(8, 0).u(8, level).ue(0)
    if profile == 100:
        w.ue(chroma).ue(0).ue(0).u(1, 0).u(1, int(scaling))
        if scaling:
            w.u(1, 1)
            for _ in range(16):
                w.se(0)
            for _ in range(7):
                w.u(1, 0)
    w.ue(0).ue(0).ue(2).ue(1).u(1, 0).ue(width_mbs - 1).ue(height_units - 1).u(1, frame_mbs_only)
    if not frame_mbs_only:
        w.u(1, 0)
    w.u(1, 1)
    w.u(1, 1 if any(crop) else 0)
    if any(crop):
        for v in crop:
            w.ue(v)
    w.u(1, 1 if vui else 0)
    if vui:
        w.u(1, 1).u(8, 255).u(16, vui["sar"][0]).u(16, vui["sar"][1])   # aspect ratio: extended
        w.u(1, 0)                                                       # overscan
        w.u(1, 1).u(3, 5).u(1, 0).u(1, 1).u(8, 1).u(8, 1).u(8, 1)       # video signal: 709
        w.u(1, 0)                                                       # chroma location
        w.u(1, 1).u(32, vui["tick"]).u(32, vui["scale"]).u(1, 1)        # timing
    return w.nal()


class Sps(unittest.TestCase):
    def test_the_film_s_own_parameter_set(self):
        s = mp4.parse_sps(FILM_SPS)
        self.assertEqual((s["profile_idc"], s["level_idc"]), (100, 40))
        self.assertEqual((s["width"], s["height"]), (886, 1920))
        self.assertEqual((s["coded_width"], s["coded_height"]), (896, 1920))   # 56 x 120 macroblocks, cropped
        self.assertEqual(s["frame_mbs_only_flag"], 1)
        self.assertEqual((s["chroma_format_idc"], s["bit_depth_luma"], s["bit_depth_chroma"]), (1, 8, 8))
        self.assertEqual(s["colour"], [1, 1, 1])                               # Rec. 709
        self.assertEqual(s["full_range"], 0)

    def test_the_recorder_s_parameter_set(self):
        s = mp4.parse_sps(PROBE_SPS)
        self.assertEqual((s["profile_idc"], s["level_idc"]), (100, 50))
        self.assertEqual((s["width"], s["height"]), (1206, 2622))
        self.assertEqual(s["colour"], [12, 13, 1])                             # Display P3, sRGB curve, 709 matrix

    def test_a_written_one_reads_back(self):
        s = mp4.parse_sps(sps())
        self.assertEqual((s["width"], s["height"], s["frame_mbs_only_flag"]), (886, 1920, 1))
        self.assertEqual((s["profile_idc"], s["level_idc"]), (100, 40))

    def test_one_pixel_off_cannot_be_written_in_4_2_0(self):
        """Cropping counts in pairs of pixels: 884 and 888 exist, 885 and 887
        do not. A file can only claim an odd size in its headers."""
        self.assertEqual(mp4.parse_sps(sps(crop=(0, 6, 0, 0)))["width"], 884)
        self.assertEqual(mp4.parse_sps(sps(crop=(0, 4, 0, 0)))["width"], 888)
        self.assertEqual(mp4.parse_sps(sps(crop=(0, 5, 0, 1)))["height"], 1918)

    def test_interlaced_is_read_as_interlaced(self):
        s = mp4.parse_sps(sps(width_mbs=120, height_units=34, frame_mbs_only=0, crop=(0, 0, 0, 2)))
        self.assertEqual(s["frame_mbs_only_flag"], 0)
        self.assertEqual((s["width"], s["height"]), (1920, 1080))              # 2 x 34 x 16 - 2 x 2 x 2

    def test_other_profiles_and_optional_parts(self):
        s = mp4.parse_sps(sps(profile=66, level=31))
        self.assertEqual((s["profile_idc"], s["level_idc"], s["width"], s["height"]), (66, 31, 886, 1920))
        self.assertEqual(mp4.parse_sps(sps(scaling=True))["width"], 886)
        s = mp4.parse_sps(sps(vui={"sar": (4, 3), "tick": 1, "scale": 60}))
        self.assertEqual(s["sar"], [4, 3])
        self.assertEqual((s["num_units_in_tick"], s["time_scale"], s["fixed_frame_rate_flag"]), (1, 60, 1))
        self.assertEqual(s["colour"], [1, 1, 1])

    def test_emulation_prevention_bytes_are_removed(self):
        s = mp4.parse_sps(sps(vui={"sar": (1, 1), "tick": 1, "scale": 60}))    # 32-bit fields full of zero bytes
        self.assertEqual((s["num_units_in_tick"], s["time_scale"]), (1, 60))
        self.assertIn(b"\x00\x00\x03", sps(vui={"sar": (1, 1), "tick": 1, "scale": 60}))

    def test_something_that_is_not_an_sps_is_refused(self):
        with self.assertRaises(mp4.Mp4Error):
            mp4.parse_sps(bytes([0x68]) + FILM_SPS[1:])

    def test_exp_golomb(self):
        b = mp4.Bits(bytes([0b1_010_011_0, 0b0100_0010, 0b1_0000000]))
        self.assertEqual([b.ue(), b.ue(), b.ue(), b.ue(), b.ue()], [0, 1, 2, 3, 4])
        b = mp4.Bits(bytes([0b1_010_011_0, 0b0100_0010, 0b1_0000000]))
        self.assertEqual([b.se(), b.se(), b.se(), b.se(), b.se()], [0, 1, -1, 2, -2])


class Esds(unittest.TestCase):
    def test_the_film_s_silent_track(self):
        e = mp4.parse_esds(FILM_ESDS)
        self.assertEqual(e, {"object_type_indication": 0x40, "max_bitrate": 256000, "avg_bitrate": 256000,
                             "audio_object_type": 2, "sample_rate": 48000, "channel_configuration": 2})

    def test_other_configurations_are_told_apart(self):
        def variant(config: bytes) -> dict:
            return mp4.parse_esds(FILM_ESDS.replace(bytes.fromhex("1190"), config))
        self.assertEqual(variant(bytes.fromhex("1210"))["sample_rate"], 44100)          # index 4
        self.assertEqual(variant(bytes.fromhex("1188"))["channel_configuration"], 1)    # mono
        self.assertEqual(variant(bytes.fromhex("2990"))["audio_object_type"], 5)        # SBR (HE-AAC)

    def test_a_payload_without_one_of_its_three_descriptors_is_refused(self):
        """Each descriptor is asked for by its tag; the film's own payload
        with one tag changed fails on that one."""
        self.assertEqual((FILM_ESDS[4], FILM_ESDS[12], FILM_ESDS[30]), (0x03, 0x04, 0x05))
        for at, missing in ((4, "no ES_Descriptor"), (12, "no DecoderConfigDescriptor"),
                            (30, "no DecoderSpecificInfo")):
            damaged = bytearray(FILM_ESDS)
            damaged[at] = 0x7F
            with self.assertRaises(mp4.Mp4Error) as cm:
                mp4.parse_esds(bytes(damaged))
            self.assertEqual(str(cm.exception), f"esds: {missing}")


class Boxes(unittest.TestCase):
    def test_a_file_that_is_not_a_movie_is_refused(self):
        import tempfile
        from pathlib import Path
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "not.mp4"
            p.write_bytes(b"\x00\x00\x00\x10ftypmp42\x00\x00\x00\x00")
            with self.assertRaises(mp4.Mp4Error):
                mp4.read(p)
            p.write_bytes(b"\x00\x00\x00\x04junk")
            with self.assertRaises(mp4.Mp4Error):
                mp4.read(p)


if __name__ == "__main__":
    unittest.main()
