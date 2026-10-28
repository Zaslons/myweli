#!/usr/bin/env python3
"""Compose the MyWeli Pro Play Store phone screenshots (1080 × 1920, 9:16).

The same eight frames the owner approved for the App Store (compose.py,
screens.json — captions, captures, masks), laid out for Play. Two things differ:

- **The size.** The Play Console takes phone screenshots « en 16:9 ou 9:16 »
  (its own upload rule, read in the form on 2026-10-28 — Google's help page
  still says « at most twice the short side », which 1080 × 2160 met and the
  console refuses). 1080 × 1920 is 9:16; the App Store frames are 1206 × 2622.
- **The status bar.** The captures come from the iOS simulator; their status
  bar (« 09:41 », the iPhone's glyphs) is cropped off, as on the feature
  graphic (feature_graphic.STATUS_BAR_PX).

The card is narrower than on the App Store frame so the whole screen still
fits, with the frame's margin under it, at this height.

It also writes the 512 × 512 store icon: the Pro app's own 1024 marketing icon
(ios/…/AppIcon-pro.appiconset, pinned by mobile/test/infra/ios_app_icon_test
as Pro's and not the consumer app's), scaled down. Play asks for a 32-bit PNG,
full-square, no rounded corners (it applies its own mask), so the file is
RGBA with every pixel opaque.

  python3 tool/app_store_screenshots/play_screenshots.py \
      --raw build/app-store/pro/raw --out build/play-store/pro

Spec: docs/design/play-store-forms.md §1.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image

import compose as c
from feature_graphic import STATUS_BAR_PX

SIZE = (1080, 1920)
ICON_SRC = c.ROOT / "mobile/ios/Runner/Assets.xcassets/AppIcon-pro.appiconset/Icon-1024.png"
ICON_SIZE = (512, 512)
# Card width at the 1320-wide reference layout (compose.L): 960 on the App
# Store frame; 777 here leaves ~80 px under the card at 1920 high.
CARD_W = 777


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--raw", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()

    for f in (c.POPPINS, c.INTER, c.MARK_SVG):
        if not f.exists():
            c.die(f"missing {f}")
    colors = c.tokens()
    screens = json.loads((c.HERE / "screens.json").read_text(encoding="utf-8"))
    c.L = {**c.L, "card_w": CARD_W}

    frames = []
    for sc in screens["screens"]:
        raw = c.raw_card(a.raw / sc["raw"], sc.get("masks", []), colors)
        raw = raw.crop((0, STATUS_BAR_PX, raw.width, raw.height))
        im = c.frame(sc, raw, SIZE, colors)
        p = a.out / f"{SIZE[0]}x{SIZE[1]}" / f"pro-{sc['id']}-{sc['name']}.png"
        digest = c.save_checked(im, p, SIZE)
        frames.append(im)
        print(f"{p.relative_to(a.out)!s:<34} {SIZE[0]}×{SIZE[1]} RGB  {digest}")
    c.overview(frames, a.out / "overview-play.png")
    print(f"overview: {a.out / 'overview-play.png'}")

    src = Image.open(ICON_SRC)
    if src.size != (1024, 1024):
        c.die(f"{ICON_SRC.name} is {src.size}, expected 1024×1024")
    icon = src.convert("RGBA").resize(ICON_SIZE, Image.LANCZOS)
    icon.putalpha(255)
    ip = a.out / "icon-512.png"
    icon.save(ip, "PNG")
    with Image.open(ip) as back:
        lo, _ = back.getchannel("A").getextrema() if back.mode == "RGBA" else (0, 0)
        if back.size != ICON_SIZE or back.mode != "RGBA" or lo != 255:
            c.die(f"{ip} came back {back.size} {back.mode} — refusing it")
    print(f"icon-512.png  512×512 RGBA (opaque)  {hashlib.sha256(ip.read_bytes()).hexdigest()[:12]}")


if __name__ == "__main__":
    main()
