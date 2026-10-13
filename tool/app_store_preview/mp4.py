"""Read an MP4/QuickTime file's boxes directly — no AVFoundation.

verify.py needs a reader that is not the writer: the film is written by
AVFoundation, and asking AVFoundation alone whether the file is right would be
asking it to mark its own work. This parser reads the bytes: the track
headers, the sample tables (every sample's duration and size), the H.264
sequence parameter set inside `avcC` (profile, level, the coded size and its
cropping, progressive or interlaced) and the AAC configuration inside `esds`.

Only what the checks need is parsed; an unknown box is skipped by its size.
"""

from __future__ import annotations

import struct
from pathlib import Path

CONTAINERS = {b"moov", b"trak", b"edts", b"mdia", b"minf", b"stbl", b"dinf", b"udta"}


class Mp4Error(Exception):
    pass


def _boxes(data: bytes, start: int, end: int):
    """(type, payload start, payload end) for each box in data[start:end]."""
    pos = start
    while pos + 8 <= end:
        size, kind = struct.unpack(">I4s", data[pos:pos + 8])
        head = 8
        if size == 1:
            size = struct.unpack(">Q", data[pos + 8:pos + 16])[0]
            head = 16
        elif size == 0:
            size = end - pos
        if size < head or pos + size > end:
            raise Mp4Error(f"box {kind!r} at {pos} has an impossible size {size}")
        yield kind, pos + head, pos + size
        pos += size


class Bits:
    """An H.264 RBSP bit reader (emulation-prevention bytes already removed)."""

    def __init__(self, data: bytes):
        self.data, self.pos = data, 0

    def u(self, n: int) -> int:
        v = 0
        for _ in range(n):
            byte = self.data[self.pos >> 3]
            v = (v << 1) | ((byte >> (7 - (self.pos & 7))) & 1)
            self.pos += 1
        return v

    def ue(self) -> int:
        zeros = 0
        while self.u(1) == 0:
            zeros += 1
            if zeros > 32:
                raise Mp4Error("bad Exp-Golomb code in the SPS")
        return (1 << zeros) - 1 + (self.u(zeros) if zeros else 0)

    def se(self) -> int:
        k = self.ue()
        return (k + 1) // 2 if k & 1 else -(k // 2)


def parse_sps(nal: bytes) -> dict:
    """ITU-T H.264 §7.3.2.1.1 — the fields that fix the picture's size and
    scan."""
    if nal[0] & 0x1F != 7:
        raise Mp4Error("the first parameter set in avcC is not an SPS")
    rbsp = bytearray()
    zeros = 0
    for byte in nal[1:]:
        if zeros >= 2 and byte == 3:
            zeros = 0
            continue  # emulation prevention
        rbsp.append(byte)
        zeros = zeros + 1 if byte == 0 else 0
    b = Bits(bytes(rbsp))
    out: dict = {"profile_idc": b.u(8), "constraints": b.u(8), "level_idc": b.u(8)}
    b.ue()  # seq_parameter_set_id
    chroma, depth_luma, depth_chroma, separate = 1, 8, 8, 0
    if out["profile_idc"] in (100, 110, 122, 244, 44, 83, 86, 118, 128, 138, 139, 134, 135):
        chroma = b.ue()
        if chroma == 3:
            separate = b.u(1)
        depth_luma, depth_chroma = 8 + b.ue(), 8 + b.ue()
        b.u(1)  # qpprime_y_zero_transform_bypass_flag
        if b.u(1):  # seq_scaling_matrix_present_flag
            for i in range(8 if chroma != 3 else 12):
                if b.u(1):
                    last, nxt = 8, 8
                    for _ in range(16 if i < 6 else 64):
                        if nxt:
                            nxt = (last + b.se() + 256) % 256
                        last = nxt or last
    out.update(chroma_format_idc=chroma, bit_depth_luma=depth_luma, bit_depth_chroma=depth_chroma)
    b.ue()  # log2_max_frame_num_minus4
    poc = b.ue()
    if poc == 0:
        b.ue()
    elif poc == 1:
        b.u(1)
        b.se()
        b.se()
        for _ in range(b.ue()):
            b.se()
    out["max_num_ref_frames"] = b.ue()
    b.u(1)  # gaps_in_frame_num_value_allowed_flag
    width_mbs = b.ue() + 1
    height_units = b.ue() + 1
    frame_mbs_only = b.u(1)
    if not frame_mbs_only:
        b.u(1)  # mb_adaptive_frame_field_flag
    b.u(1)  # direct_8x8_inference_flag
    left = right = top = bottom = 0
    if b.u(1):
        left, right, top, bottom = b.ue(), b.ue(), b.ue(), b.ue()
    sub_w = 1 if chroma in (0, 3) or separate else 2
    sub_h = 2 if chroma == 1 and not separate else 1
    out["frame_mbs_only_flag"] = frame_mbs_only
    out["coded_width"] = width_mbs * 16
    out["coded_height"] = (2 - frame_mbs_only) * height_units * 16
    out["width"] = out["coded_width"] - sub_w * (left + right)
    out["height"] = out["coded_height"] - sub_h * (2 - frame_mbs_only) * (top + bottom)
    if b.u(1):  # vui_parameters_present_flag
        if b.u(1):  # aspect_ratio_info_present_flag
            idc = b.u(8)
            out["sar"] = [b.u(16), b.u(16)] if idc == 255 else {0: None, 1: [1, 1]}.get(idc, f"idc {idc}")
        if b.u(1):
            b.u(1)  # overscan
        if b.u(1):  # video_signal_type_present_flag
            b.u(3)
            out["full_range"] = b.u(1)
            if b.u(1):
                out["colour"] = [b.u(8), b.u(8), b.u(8)]  # primaries, transfer, matrix
        if b.u(1):
            b.ue()
            b.ue()
        if b.u(1):  # timing_info_present_flag
            out["num_units_in_tick"], out["time_scale"] = b.u(32), b.u(32)
            out["fixed_frame_rate_flag"] = b.u(1)
    return out


def _descriptor(data: bytes, pos: int) -> tuple[int, int, int]:
    """(tag, payload start, payload end) of an MPEG-4 descriptor."""
    tag = data[pos]
    pos += 1
    size = 0
    for _ in range(4):
        byte = data[pos]
        pos += 1
        size = (size << 7) | (byte & 0x7F)
        if not byte & 0x80:
            break
    return tag, pos, pos + size


def parse_esds(data: bytes) -> dict:
    """ISO/IEC 14496-1 ES_Descriptor -> the AAC AudioSpecificConfig."""
    out: dict = {}
    tag, pos, end = _descriptor(data, 4)  # after version/flags
    if tag != 0x03:
        raise Mp4Error("esds: no ES_Descriptor")
    flags = data[pos + 2]
    pos += 3 + (2 if flags & 0x80 else 0)   # ES_ID, flags, dependsOn_ES_ID
    if flags & 0x40:
        pos += 1 + data[pos]                 # URL
    pos += 2 if flags & 0x20 else 0          # OCR_ES_Id
    tag, pos, cfg_end = _descriptor(data, pos)
    if tag != 0x04:
        raise Mp4Error("esds: no DecoderConfigDescriptor")
    out["object_type_indication"] = data[pos]
    out["max_bitrate"], out["avg_bitrate"] = struct.unpack(">II", data[pos + 5:pos + 13])
    tag, pos, end = _descriptor(data, pos + 13)
    if tag != 0x05:
        raise Mp4Error("esds: no DecoderSpecificInfo")
    b = Bits(data[pos:end])
    aot = b.u(5)
    if aot == 31:
        aot = 32 + b.u(6)
    index = b.u(4)
    rates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
    out["audio_object_type"] = aot
    out["sample_rate"] = b.u(24) if index == 15 else rates[index]
    out["channel_configuration"] = b.u(4)
    return out


def _full(data: bytes, a: int) -> tuple[int, int]:
    """(version, flags) of a full box whose payload starts at a."""
    v = struct.unpack(">I", data[a:a + 4])[0]
    return v >> 24, v & 0xFFFFFF


def _visual_entry(data: bytes, kind: bytes, a: int, b: int) -> dict:
    out = {"format": kind.decode("latin-1")}
    out["width"], out["height"] = struct.unpack(">HH", data[a + 24:a + 28])
    out["depth"] = struct.unpack(">H", data[a + 74:a + 76])[0]
    for sub, sa, sb in _boxes(data, a + 78, b):
        if sub == b"avcC":
            out["avcC"] = {"profile": data[sa + 1], "compatibility": data[sa + 2], "level": data[sa + 3]}
            count = data[sa + 5] & 0x1F
            if count:
                length = struct.unpack(">H", data[sa + 6:sa + 8])[0]
                out["sps"] = parse_sps(data[sa + 8:sa + 8 + length])
        elif sub == b"pasp":
            out["pasp"] = list(struct.unpack(">II", data[sa:sa + 8]))
        elif sub == b"fiel":
            out["fiel"] = [data[sa], data[sa + 1]]  # field count, ordering
        elif sub == b"colr":
            kind_ = data[sa:sa + 4].decode("latin-1")
            out["colr"] = [kind_] + (list(struct.unpack(">HHH", data[sa + 4:sa + 10])) if kind_ in ("nclc", "nclx") else [])
        elif sub == b"clap":
            out["clap"] = list(struct.unpack(">8i", data[sa:sa + 32]))
    return out


def _audio_entry(data: bytes, kind: bytes, a: int, b: int) -> dict:
    out = {"format": kind.decode("latin-1")}
    version = struct.unpack(">H", data[a + 8:a + 10])[0]
    out["channels"], out["sample_size"] = struct.unpack(">HH", data[a + 16:a + 20])
    out["sample_rate"] = struct.unpack(">I", data[a + 24:a + 28])[0] / 65536
    child = a + 28 + {0: 0, 1: 16, 2: 36}.get(version, 0)
    for sub, sa, sb in _boxes(data, child, b):
        if sub == b"esds":
            out["esds"] = parse_esds(data[sa:sb])
        elif sub == b"wave":  # QuickTime wraps esds in a wave atom
            for sub2, sa2, sb2 in _boxes(data, sa, sb):
                if sub2 == b"esds":
                    out["esds"] = parse_esds(data[sa2:sb2])
    return out


def _track(data: bytes, a: int, b: int) -> dict:
    t: dict = {"edits": None}
    for kind, sa, sb in _boxes(data, a, b):
        if kind == b"tkhd":
            version, flags = _full(data, sa)
            off = sa + (24 if version == 1 else 16)   # past times and track id
            t["id"] = struct.unpack(">I", data[sa + (20 if version == 1 else 12):sa + (24 if version == 1 else 16)])[0]
            off += 4                                   # reserved
            t["tkhd_duration"] = struct.unpack(">Q" if version == 1 else ">I", data[off:off + (8 if version == 1 else 4)])[0]
            off += (8 if version == 1 else 4) + 8 + 2 + 2 + 2 + 2  # reserved, layer, group, volume, reserved
            t["matrix"] = list(struct.unpack(">9i", data[off:off + 36]))
            w, h = struct.unpack(">II", data[off + 36:off + 44])
            t["enabled"] = bool(flags & 1)
            t["tkhd_width"], t["tkhd_height"] = w / 65536, h / 65536
        elif kind == b"edts":
            for sub, ea, eb in _boxes(data, sa, sb):
                if sub == b"elst":
                    version, _ = _full(data, ea)
                    n = struct.unpack(">I", data[ea + 4:ea + 8])[0]
                    edits, pos = [], ea + 8
                    for _ in range(n):
                        if version == 1:
                            dur, media = struct.unpack(">Qq", data[pos:pos + 16])
                            pos += 16
                        else:
                            dur, media = struct.unpack(">Ii", data[pos:pos + 8])
                            pos += 8
                        rate = struct.unpack(">i", data[pos:pos + 4])[0] / 65536
                        pos += 4
                        edits.append({"duration": dur, "media_time": media, "rate": rate})
                    t["edits"] = edits
        elif kind == b"mdia":
            for sub, ma, mb in _boxes(data, sa, sb):
                if sub == b"mdhd":
                    version, _ = _full(data, ma)
                    if version == 1:
                        t["timescale"], t["duration"] = struct.unpack(">IQ", data[ma + 20:ma + 32])
                    else:
                        t["timescale"], t["duration"] = struct.unpack(">II", data[ma + 12:ma + 20])
                elif sub == b"hdlr":
                    t["handler"] = data[ma + 8:ma + 12].decode("latin-1")
                elif sub == b"minf":
                    for sub2, na, nb in _boxes(data, ma, mb):
                        if sub2 == b"stbl":
                            _sample_table(data, na, nb, t)
    return t


def _sample_table(data: bytes, a: int, b: int, t: dict) -> None:
    t.update(entries=[], stts=[], ctts=False, sync_samples=None, sizes=[])
    for kind, sa, sb in _boxes(data, a, b):
        if kind == b"stsd":
            n = struct.unpack(">I", data[sa + 4:sa + 8])[0]
            pos = sa + 8
            for _ in range(n):
                size, fmt = struct.unpack(">I4s", data[pos:pos + 8])
                if t.get("handler") == "vide":
                    t["entries"].append(_visual_entry(data, fmt, pos + 8, pos + size))
                elif t.get("handler") == "soun":
                    t["entries"].append(_audio_entry(data, fmt, pos + 8, pos + size))
                else:
                    t["entries"].append({"format": fmt.decode("latin-1")})
                pos += size
        elif kind == b"stts":
            n = struct.unpack(">I", data[sa + 4:sa + 8])[0]
            t["stts"] = [list(struct.unpack(">II", data[sa + 8 + 8 * i:sa + 16 + 8 * i])) for i in range(n)]
        elif kind == b"ctts":
            n = struct.unpack(">I", data[sa + 4:sa + 8])[0]
            offsets = [struct.unpack(">Ii", data[sa + 8 + 8 * i:sa + 16 + 8 * i])[1] for i in range(n)]
            t["ctts"] = any(offsets)
        elif kind == b"stss":
            t["sync_samples"] = struct.unpack(">I", data[sa + 4:sa + 8])[0]
        elif kind == b"stsz":
            fixed, n = struct.unpack(">II", data[sa + 4:sa + 12])
            t["sizes"] = [fixed] * n if fixed else list(struct.unpack(f">{n}I", data[sa + 12:sa + 12 + 4 * n]))


def read(path: Path) -> dict:
    """The file's structure: {ftyp, movie, tracks, order, file_bytes}."""
    data = Path(path).read_bytes()
    out: dict = {"file_bytes": len(data), "ftyp": None, "movie": {}, "tracks": [], "order": []}
    for kind, a, b in _boxes(data, 0, len(data)):
        out["order"].append(kind.decode("latin-1"))
        if kind == b"ftyp":
            out["ftyp"] = {"major": data[a:a + 4].decode("latin-1"),
                           "compatible": [data[i:i + 4].decode("latin-1") for i in range(a + 8, b, 4)]}
        elif kind == b"moov":
            for sub, sa, sb in _boxes(data, a, b):
                if sub == b"mvhd":
                    version, _ = _full(data, sa)
                    if version == 1:
                        ts, dur = struct.unpack(">IQ", data[sa + 20:sa + 32])
                    else:
                        ts, dur = struct.unpack(">II", data[sa + 12:sa + 20])
                    out["movie"] = {"timescale": ts, "duration": dur}
                elif sub == b"trak":
                    out["tracks"].append(_track(data, sa, sb))
    if not out["movie"]:
        raise Mp4Error(f"{path}: no movie header — not an MP4 or QuickTime file")
    return out
