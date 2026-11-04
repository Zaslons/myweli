"""``python -m promo.audio --score score_30s.yaml --out DIR`` (run from tool/promo_reel).

Writes into DIR: track.wav (24-bit stereo, 48 kHz), events.json, meter.json,
spectrogram.png and waveform.png. ``--cut 30s`` is short for
``--score score_30s.yaml``. Exit status 1 when the master misses its target
(-14 LUFS ±0.1, true peak <= -1.0 dBTP) or the score is refused.
"""

from __future__ import annotations

import argparse
import sys

from .build import build_cut
from .mix import MixSettings
from .score import ScoreError


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="python -m promo.audio", description=__doc__.split("\n\n")[0])
    which = ap.add_mutually_exclusive_group(required=True)
    which.add_argument("--score", help="a score YAML (a bare name is looked up in promo/audio/)")
    which.add_argument("--cut", help="a cut name: 30s -> score_30s.yaml")
    ap.add_argument("--out", required=True, help="output directory")
    ap.add_argument("--lufs", type=float, default=-14.0, help="integrated loudness target (default -14)")
    ap.add_argument("--ceiling", type=float, default=-1.0, help="true-peak ceiling in dBTP (default -1.0)")
    ap.add_argument("--no-pictures", action="store_true", help="skip spectrogram.png and waveform.png")
    ap.add_argument("--no-ffmpeg", action="store_true", help="skip the ffmpeg ebur128 cross-check")
    ap.add_argument("--stems", action="store_true", help="also write the five buses and every track to DIR/stems/")
    args = ap.parse_args(argv)
    try:
        result = build_cut(args.score or args.cut, args.out,
                           settings=MixSettings(target_lufs=args.lufs, ceiling_dbtp=args.ceiling),
                           pictures=not args.no_pictures, ffmpeg_check=not args.no_ffmpeg, stems=args.stems)
    except (ScoreError, FileNotFoundError) as e:
        print(f"promo.audio: {e}", file=sys.stderr)
        return 1
    m = result.meter
    ok = m["target"]["integrated_ok"] and m["target"]["true_peak_ok"]
    print(f"{result.out}/track.wav  {m['duration_s']:.3f} s  {m['frames']} frames  "
          f"{m['integrated_lufs']:.2f} LUFS-I  TP {m['true_peak_dbtp']:.2f} dBTP  LRA {m['lra_lu']:.1f} LU  "
          f"cues {len(result.events['cues'])}  ({result.seconds:.1f} s)")
    if m.get("ffmpeg_ebur128"):
        f = m["ffmpeg_ebur128"]
        print(f"ffmpeg ebur128: I {f['integrated_lufs']} LUFS, LRA {f['lra_lu']} LU, true peak {f['true_peak_dbfs']} dBFS")
    if not ok:
        print("promo.audio: the master misses its loudness or true-peak target", file=sys.stderr)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
