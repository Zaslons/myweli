"""``python -m promo {plan,build,verify}`` — the pipeline's entry point.

    python -m promo plan   [--all | --cut 30s --format 9x16 …] [--set path=value …]
    python -m promo build  [selection] [--set …] [--out DIR]
    python -m promo verify [selection] [--set …] [--out DIR]

Every command first loads and checks storyboard.yaml (with the variant's
``--set`` overrides): a broken storyboard stops everything, exit code 2.

``build`` and ``verify`` hand over to the modules SCENES adds — a module is
used as soon as it is in the tree, nothing here changes:

    promo/render.py  def build(storyboard, cuts: list[str], formats: list[str], out_dir: Path) -> None
    promo/verify.py  def verify(storyboard, cuts: list[str], formats: list[str], out_dir: Path) -> bool

Until then ``build`` prints the plan and renders nothing, and ``verify`` says
plainly that no film was verified (there is none). If render.py exists and
verify.py does not, ``verify`` fails: a film may exist that nothing checked.
"""

from __future__ import annotations

import argparse
import importlib
import importlib.util
import sys
from pathlib import Path
from typing import Callable, Sequence

from . import storyboard as sbmod

PROMO_REEL = Path(__file__).resolve().parents[1]
DEFAULT_OUT = PROMO_REEL / "out"


def _parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="python -m promo", description="MyWeli Pro promo reel pipeline.")
    sub = ap.add_subparsers(dest="command", required=True)
    for name, text in (("plan", "load and check the storyboard; print what a build makes"),
                       ("build", "render every selected cut × format"),
                       ("verify", "verify every selected film")):
        p = sub.add_parser(name, help=text, description=text)
        p.add_argument("--all", action="store_true", help="every cut and every format")
        p.add_argument("--cut", action="append", default=[], metavar="ID", help="a cut (repeatable): 30s, 15s")
        p.add_argument("--format", action="append", default=[], metavar="ID",
                       help="a format (repeatable): 9x16, 1x1, 16x9")
        p.add_argument("--set", action="append", default=[], metavar="PATH=VALUE", dest="overrides",
                       help="a variant: override one storyboard value (repeatable)")
        p.add_argument("--storyboard", type=Path, default=sbmod.DEFAULT_PATH)
        p.add_argument("--out", type=Path, default=DEFAULT_OUT, help=f"output folder (default {DEFAULT_OUT})")
    return ap


def _select(sb: sbmod.Storyboard, args: argparse.Namespace) -> tuple[list[str], list[str]]:
    if args.all and (args.cut or args.format):
        raise SystemExit("python -m promo: --all selects everything; leave out --cut/--format")
    if not args.all and not args.cut and not args.format and args.command != "plan":
        raise SystemExit("python -m promo: say what to work on: --all, or --cut ID and/or --format ID")
    cuts = args.cut or list(sb.cuts)
    formats = args.format or list(sb.formats)
    for kind, chosen, known in (("cut", cuts, sb.cuts), ("format", formats, sb.formats)):
        unknown = [c for c in chosen if c not in known]
        if unknown:
            raise SystemExit(f"python -m promo: no {kind} {', '.join(unknown)} in the storyboard "
                             f"(have: {', '.join(known)})")
    return cuts, formats


def _hook(module: str, function: str) -> Callable | None:
    """``module.function`` when the module is in the tree, else None."""
    if importlib.util.find_spec(module) is None:
        return None
    fn = getattr(importlib.import_module(module), function, None)
    if not callable(fn):
        raise SystemExit(f"python -m promo: {module} has no function {function}()")
    return fn


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        sb = sbmod.load(args.storyboard, overrides=args.overrides)
    except sbmod.StoryboardError as e:
        print(e, file=sys.stderr)
        return 2
    cuts, formats = _select(sb, args)
    if args.command == "plan":
        print(sb.plan(cuts, formats))
        return 0
    render = _hook("promo.render", "build")
    if args.command == "build":
        print(sb.plan(cuts, formats))
        if render is None:
            print("build: promo/render.py is not in the tree yet (SCENES, phase 2) — the storyboard is valid; "
                  "NOTHING was rendered.")
            return 0
        render(sb, cuts=cuts, formats=formats, out_dir=args.out)
        return 0
    verify = _hook("promo.verify", "verify")
    if verify is None:
        if render is None:
            print("verify: the storyboard is valid. UNVERIFIED: no film exists yet (promo/render.py and "
                  "promo/verify.py are not in the tree) — nothing about a film was checked.")
            return 0
        print("verify: promo/render.py exists but promo/verify.py does not — a film may have been built "
              "that nothing checks.", file=sys.stderr)
        return 1
    return 0 if verify(sb, cuts=cuts, formats=formats, out_dir=args.out) else 1


if __name__ == "__main__":
    raise SystemExit(main())
