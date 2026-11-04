"""Command line: ``python -m promo.lottie {check,filmstrip,frame}`` (run from tool/promo_reel).

* ``check`` — the acceptance: render the two golden frames as the app draws
  them, compare with mobile/test/golden/goldens/pro_splash_*.png, print the
  numbers; ``--out DIR`` also writes our renders and golden|ours|diff sheets.
  Exits 1 if a shape does not match (IoU < 0.99 or an error above 64 levels).
* ``filmstrip`` — every ``--step``-th composition frame plus the end, labelled.
* ``frame`` — one frame on #FAFAFA at a given width, e.g. the film's 900 px.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import PRO_OPEN_ANIMATION, Player
from . import check

IOU_FLOOR = 0.99
MAX_ERROR_CEILING = 64


def _check(args: argparse.Namespace) -> int:
    player = Player(args.json)
    results = check.acceptance(player, Path(args.goldens))
    ok = True
    report = {}
    for name, (case, drawn, comparison) in results.items():
        report[name] = {'comp_frame': case.comp_frame, 'drawn_at': drawn, **comparison.as_dict()}
        passed = comparison.iou >= IOU_FLOOR and comparison.max_abs_error <= MAX_ERROR_CEILING
        ok &= passed
        print(
            f'{name}: comp {case.comp_frame:g} (drawn {drawn:.3f}) — '
            f'mean |Δ| {comparison.mean_abs_error:.4f}, ink-box mean |Δ| {comparison.roi_mean_abs_error:.3f}, '
            f'max |Δ| {comparison.max_abs_error}, IoU {comparison.iou:.4f}, '
            f'soft IoU {comparison.soft_iou:.4f}, ink ratio {comparison.ink_ratio:.4f}, '
            f'centroid Δ ({comparison.centroid_shift[0]:+.3f}, {comparison.centroid_shift[1]:+.3f}) px '
            f'— {"OK" if passed else "MISMATCH"}'
        )
        if args.out:
            out = Path(args.out)
            ours = check.render_surface(player, drawn)
            golden = check.load_png(Path(args.goldens) / f'{name}.png')
            check.save_png(ours, out / f'{name}.ours.png')
            check.save_png(check.diff_sheet(ours, golden), out / f'{name}.sheet.png')
    if args.out:
        Path(args.out, 'check.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    return 0 if ok else 1


def _filmstrip(args: argparse.Namespace) -> int:
    player = Player(args.json)
    first, last = player.frames
    frames = [float(f) for f in range(int(first), int(last), args.step)]
    if frames[-1] != last:
        frames.append(last)
    check.save_png(check.filmstrip(player, frames, args.cell, args.columns), args.out)
    print(f'{args.out}: {len(frames)} frames, every {args.step} from {first:g} to {last:g}')
    return 0


def _frame(args: argparse.Namespace) -> int:
    player = Player(args.json)
    comp_w, comp_h = player.size
    width = args.width
    height = round(width * comp_h / comp_w)
    margin = args.margin
    size = (width + 2 * margin, height + 2 * margin)
    dst = player.dst_rect((size[0] / 2, size[1] / 2), width)
    check.save_png(check.render_surface(player, args.at, size=size, dst_rect=dst, color=args.color), args.out)
    print(f'{args.out}: comp {args.at:g} at {width} px')
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog='python -m promo.lottie', description=__doc__.splitlines()[0])
    parser.add_argument('--json', default=str(PRO_OPEN_ANIMATION), help='the Lottie file (default: the Pro one)')
    sub = parser.add_subparsers(dest='command', required=True)

    p = sub.add_parser('check', help='compare with the Flutter goldens')
    p.add_argument('--goldens', default=str(check.GOLDENS_DIR))
    p.add_argument('--out', help='write renders, sheets and check.json here')
    p.set_defaults(run=_check)

    p = sub.add_parser('filmstrip', help='a labelled grid of frames')
    p.add_argument('--out', required=True)
    p.add_argument('--step', type=int, default=10)
    p.add_argument('--cell', type=int, default=360, help='cell width in px')
    p.add_argument('--columns', type=int, default=4)
    p.set_defaults(run=_filmstrip)

    p = sub.add_parser('frame', help='one frame as PNG')
    p.add_argument('--at', type=float, required=True, help='composition frame (continuous)')
    p.add_argument('--width', type=int, default=900)
    p.add_argument('--margin', type=int, default=40)
    p.add_argument('--color', help="'#RRGGBB' to recolour (default: the file's #111111)")
    p.add_argument('--out', required=True)
    p.set_defaults(run=_frame)

    args = parser.parse_args(argv)
    return args.run(args)


if __name__ == '__main__':
    sys.exit(main())
