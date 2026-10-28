#!/usr/bin/env python3
"""Compose the MyWeli Pro Play Store « feature graphic » (1024 × 500).

The banner Play shows above the listing. It is drawn from the same parts as the
App Store frames (compose.py) so the two stores show one product: the surface
background, the MyWeli mark, a Poppins title, an Inter subline (the Play short
description, docs/design/play-store-forms.md §1) and the « Ma journée » capture
in the frames' rounded card, masked the same way (screens.json).

  python3 tool/app_store_screenshots/feature_graphic.py \
      --raw build/app-store/pro/raw --out build/play-store/pro

Play takes a JPEG or a 24-bit PNG with no alpha, exactly 1024 × 500; the file
is re-opened after saving and refused otherwise (compose.save_checked).
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

import compose as c

SIZE = (1024, 500)
SCREEN_ID = "01"  # « Ma journée » — the agenda, the app's first screen

# The raw captures come from the iOS simulator. Their status bar (« 09:41 »,
# the iPhone's signal and battery glyphs) has no place on an Android listing,
# so the card starts below it: the top STATUS_BAR_PX rows of the 1206-wide
# capture are dropped.
STATUS_BAR_PX = 150

TITLE = "MyWeli Pro"
SUBLINE = ["L’agenda, la clientèle et les", "réservations de votre salon."]

# Layout in px at 1024 × 500.
G = {
    "left": 72, "col": 470,
    "mark_h": 52, "title_px": 68, "sub_px": 27, "sub_lh": 38,
    "gap_mark": 28, "gap_title": 18,
    "card_w": 300, "card_x": 650, "card_top": 54, "card_radius": 38,
    "card_border": 2,
}


def compose_banner(raw: Image.Image, colors: dict) -> Image.Image:
    W, H = SIZE
    canvas = Image.new("RGB", SIZE, colors["surface"])
    draw = ImageDraw.Draw(canvas)

    # The text block, centred vertically as one unit.
    m = c.mark(G["mark_h"])
    tf = ImageFont.truetype(str(c.POPPINS), G["title_px"])
    sf = c.inter(G["sub_px"])
    for line in [TITLE, *SUBLINE]:
        f = tf if line == TITLE else sf
        if f.getlength(line) > G["col"]:
            c.die(f"« {line} » is wider than the {G['col']}px column")
    t_box = tf.getbbox(TITLE, anchor="ls")
    title_h = t_box[3] - t_box[1]
    block = (G["mark_h"] + G["gap_mark"] + title_h + G["gap_title"]
             + len(SUBLINE) * G["sub_lh"])
    y = (H - block) // 2
    canvas.paste(m, (G["left"], y), m)
    y += G["mark_h"] + G["gap_mark"]
    draw.text((G["left"], y - t_box[1]), TITLE, font=tf,
              fill=colors["textPrimary"], anchor="ls")
    y += title_h + G["gap_title"]
    for i, line in enumerate(SUBLINE):
        draw.text((G["left"], y + i * G["sub_lh"]), line, font=sf,
                  fill=colors["textSecondary"], anchor="la")

    # The capture: the frames' card, running off the bottom edge.
    cw = G["card_w"]
    ch = round(cw * raw.height / raw.width)
    cx, cy = G["card_x"], G["card_top"]
    r = G["card_radius"]
    mask = c.rounded_mask((cw, ch), r)
    big = Image.new("RGB", (W, cy + ch), colors["surface"])
    big.paste(canvas, (0, 0))
    for opacity, blur, dy in c.L["shadows"]:
        layer = Image.new("L", big.size, 0)
        layer.paste(mask.point(lambda v: round(v * opacity)), (cx, cy + dy // 3))
        layer = layer.filter(ImageFilter.GaussianBlur(blur / 3))
        big.paste(Image.new("RGB", big.size, (0, 0, 0)), (0, 0), layer)
    big.paste(raw.resize((cw, ch), Image.LANCZOS), (cx, cy), mask)
    ring = Image.new("L", (cw * c.SUPERSAMPLE, ch * c.SUPERSAMPLE), 0)
    ImageDraw.Draw(ring).rounded_rectangle(
        (0, 0, cw * c.SUPERSAMPLE - 1, ch * c.SUPERSAMPLE - 1),
        radius=r * c.SUPERSAMPLE, outline=255,
        width=G["card_border"] * c.SUPERSAMPLE,
    )
    ring = ring.resize((cw, ch), Image.LANCZOS)
    big.paste(Image.new("RGB", (cw, ch), colors["border"]), (cx, cy), ring)
    return big.crop((0, 0, W, H))


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
    sc = next((x for x in screens["screens"] if x["id"] == SCREEN_ID), None)
    if sc is None:
        c.die(f"no screen {SCREEN_ID} in screens.json")
    raw = c.raw_card(a.raw / sc["raw"], sc.get("masks", []), colors)
    raw = raw.crop((0, STATUS_BAR_PX, raw.width, raw.height))
    out = a.out / "feature-graphic-1024x500.png"
    digest = c.save_checked(compose_banner(raw, colors), out, SIZE)
    print(f"{out}  1024×500 RGB  {digest}")


if __name__ == "__main__":
    main()
