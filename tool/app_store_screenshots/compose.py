#!/usr/bin/env python3
"""Compose the MyWeli Pro App Store screenshots.

Raw simulator captures (iPhone 17 Pro, 1206 × 2622) become captioned brand
frames in the two sizes App Store Connect takes for an iPhone-only app:

  6.3  1206 × 2622  — the REQUIRED slot (« iPhone with Dynamic Island,
                       medium display », Apple's spec page since Oct 2026)
  6.9  1320 × 2868  — the optional large-display slot

Spec: docs/design/pro-app-store-screenshots.md. The layout below is that
spec's table, given at 1320 wide and scaled for 1206.

  python3 tool/app_store_screenshots/compose.py \
      --raw build/app-store/pro/raw --out build/app-store/pro [--only 03]

Every output is re-opened after saving and must be the exact size, mode RGB,
with no alpha and no transparency key — Apple rejects alpha, and a capture
from the simulator carries one.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
import sys
from io import BytesIO
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
COLORS_DART = ROOT / "mobile/lib/core/theme/colors.dart"
MARK_SVG = ROOT / "mobile/assets/brand/myweli_mark_black.svg"
POPPINS = HERE / "fonts/Poppins-Medium.ttf"
INTER = HERE / "fonts/Inter-Variable.ttf"

RAW_SIZE = (1206, 2622)
OUTPUTS = {"6.3": (1206, 2622), "6.9": (1320, 2868)}

# The spec's layout, in px at 1320 wide.
L = {
    "mark_h": 64, "mark_top": 72,
    "head_px": 88, "head_min_px": 76, "head_lh": 1.15, "head_top": 176,
    "head_col": 1128,
    "sub_px": 44, "sub_lh": 60, "sub_top": 436, "sub_col": 1000,
    "card_w": 960, "card_top": 656, "card_radius": 118, "card_border": 3,
    # elevation4 (app_theme.dart) × 3: (opacity, blur, offset y)
    "shadows": [(0.10, 45, 30), (0.05, 18, 12)],
}

SUPERSAMPLE = 2  # anti-aliasing for the card's rounded mask and outline


def die(msg: str) -> None:
    print(f"compose: {msg}", file=sys.stderr)
    sys.exit(1)


def tokens() -> dict[str, tuple[int, int, int]]:
    """Read the colour tokens by name from colors.dart, so a token change
    cannot drift away from the frames silently."""
    src = COLORS_DART.read_text(encoding="utf-8")
    out = {}
    for name in ("surface", "textPrimary", "textSecondary", "border", "divider"):
        m = re.search(
            rf"static const Color {name} = Color\(\s*0x([0-9A-Fa-f]{{8}})", src
        )
        if not m:
            die(f"colour token `{name}` not found in {COLORS_DART}")
        argb = m.group(1)
        if argb[:2].upper() != "FF":
            die(f"colour token `{name}` is not opaque ({argb})")
        out[name] = tuple(int(argb[i : i + 2], 16) for i in (2, 4, 6))
    return out


def inter(px: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(INTER), px)
    f.set_variation_by_axes([14, 400])  # opsz 14 (text), wght 400 (Regular)
    return f


def mark(height: int) -> Image.Image:
    png = subprocess.run(
        ["rsvg-convert", "-h", str(height), str(MARK_SVG)],
        check=True, capture_output=True,
    ).stdout
    return Image.open(BytesIO(png)).convert("RGBA")


def fit_headline(lines: list[str], s: float) -> ImageFont.FreeTypeFont:
    if not 1 <= len(lines) <= 2:
        die(f"a headline has 1 or 2 hand-set lines, got {len(lines)}: {lines}")
    col = L["head_col"] * s
    px = L["head_px"]
    while px >= L["head_min_px"]:
        f = ImageFont.truetype(str(POPPINS), round(px * s))
        if all(f.getlength(t) <= col for t in lines):
            return f
        px -= 2
    die(f"headline does not fit {L['head_col']}px at {L['head_min_px']}px: {lines}")


def wrap_subline(text: str | list[str], f: ImageFont.FreeTypeFont,
                 col: float) -> list[str]:
    """A list is hand-set (French breaks: never end a line on « à », « de »…)
    and must fit as given; a string is wrapped by measured width."""
    if isinstance(text, list):
        if not 1 <= len(text) <= 2:
            die(f"a subline has 1 or 2 lines, got {len(text)}: {text}")
        for t in text:
            if f.getlength(t) > col:
                die(f"subline line wider than {col:.0f}px: {t}")
        return text
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = f"{cur} {w}".strip()
        if f.getlength(trial) <= col:
            cur = trial
        else:
            if not cur:
                die(f"subline word wider than the column: {w}")
            lines.append(cur)
            cur = w
    lines.append(cur)
    if len(lines) > 2:
        die(f"subline needs {len(lines)} lines, max 2: {text}")
    # Never one word alone on line 2: pull a word down from line 1.
    if len(lines) == 2 and len(lines[1].split()) == 1:
        head = lines[0].split()
        moved = f"{head[-1]} {lines[1]}"
        if len(head) > 1 and f.getlength(moved) <= col:
            lines = [" ".join(head[:-1]), moved]
    return lines


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    w, h = size
    big = Image.new("L", (w * SUPERSAMPLE, h * SUPERSAMPLE), 0)
    ImageDraw.Draw(big).rounded_rectangle(
        (0, 0, w * SUPERSAMPLE - 1, h * SUPERSAMPLE - 1),
        radius=radius * SUPERSAMPLE, fill=255,
    )
    return big.resize(size, Image.LANCZOS)


def raw_card(path: Path, masks: list[list[int]], c: dict) -> Image.Image:
    im = Image.open(path)
    if im.size != RAW_SIZE:
        die(f"{path.name} is {im.size[0]}×{im.size[1]}, expected "
            f"{RAW_SIZE[0]}×{RAW_SIZE[1]} (capture on the iPhone 17 Pro simulator)")
    if im.mode in ("RGBA", "LA"):
        lo, _ = im.getchannel("A").getextrema()
        if lo < 255:
            die(f"{path.name} has transparent pixels — not a plain screen capture")
    im = im.convert("RGB")
    d = ImageDraw.Draw(im)
    for x, y, w, h in masks:
        # A neutral bar over a client's digits (the demo numbers look real).
        d.rounded_rectangle((x, y, x + w, y + h), radius=h // 2, fill=c["divider"])
    return im


def frame(screen: dict, raw: Image.Image, size: tuple[int, int], c: dict) -> Image.Image:
    W, H = size
    s = W / 1320
    canvas = Image.new("RGB", (W, H), c["surface"])
    draw = ImageDraw.Draw(canvas)

    m = mark(round(L["mark_h"] * s))
    canvas.paste(m, ((W - m.width) // 2, round(L["mark_top"] * s)), m)

    hf = fit_headline(screen["headline"], s)
    lh = round(L["head_px"] * L["head_lh"] * s)
    for i, t in enumerate(screen["headline"]):
        draw.text((W / 2, L["head_top"] * s + i * lh), t, font=hf,
                  fill=c["textPrimary"], anchor="ma")

    sf = inter(round(L["sub_px"] * s))
    for i, t in enumerate(wrap_subline(screen["subline"], sf, L["sub_col"] * s)):
        draw.text((W / 2, L["sub_top"] * s + i * L["sub_lh"] * s), t, font=sf,
                  fill=c["textSecondary"], anchor="ma")

    cw = round(L["card_w"] * s)
    ch = round(cw * raw.height / raw.width)
    cx, cy = (W - cw) // 2, round(L["card_top"] * s)
    if cy + ch > H:
        die(f"card overflows the canvas at {W}×{H}")
    r = round(L["card_radius"] * s)
    mask = rounded_mask((cw, ch), r)

    for opacity, blur, dy in L["shadows"]:
        layer = Image.new("L", (W, H), 0)
        layer.paste(mask.point(lambda v: round(v * opacity)), (cx, cy + round(dy * s)))
        layer = layer.filter(ImageFilter.GaussianBlur(blur * s / 2))
        canvas.paste(Image.new("RGB", (W, H), (0, 0, 0)), (0, 0), layer)

    canvas.paste(raw.resize((cw, ch), Image.LANCZOS), (cx, cy), mask)

    bw = max(1, round(L["card_border"] * s))
    ring = Image.new("L", (cw * SUPERSAMPLE, ch * SUPERSAMPLE), 0)
    ImageDraw.Draw(ring).rounded_rectangle(
        (0, 0, cw * SUPERSAMPLE - 1, ch * SUPERSAMPLE - 1),
        radius=r * SUPERSAMPLE, outline=255, width=bw * SUPERSAMPLE,
    )
    ring = ring.resize((cw, ch), Image.LANCZOS)
    canvas.paste(Image.new("RGB", (cw, ch), c["border"]), (cx, cy), ring)
    return canvas


def save_checked(im: Image.Image, path: Path, size: tuple[int, int]) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    im.save(path, "PNG")
    back = Image.open(path)
    if back.size != size or back.mode != "RGB" or "transparency" in back.info:
        die(f"{path} came back {back.size} {back.mode} {back.info} — refusing it")
    return hashlib.sha256(path.read_bytes()).hexdigest()[:12]


def overview(frames: list[Image.Image], out: Path) -> None:
    """One image of the whole set, in upload order, for sign-off."""
    tw = 300
    th = round(tw * frames[0].height / frames[0].width)
    gap, cols = 40, 4
    rows = (len(frames) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw + (cols + 1) * gap,
                              rows * th + (rows + 1) * gap), (255, 255, 255))
    for i, f in enumerate(frames):
        x = gap + (i % cols) * (tw + gap)
        y = gap + (i // cols) * (th + gap)
        sheet.paste(f.resize((tw, th), Image.LANCZOS), (x, y))
    sheet.save(out, "PNG")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--raw", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--screens", type=Path, default=HERE / "screens.json")
    ap.add_argument("--only", help="compose one screen by id, e.g. 03")
    a = ap.parse_args()

    for f in (POPPINS, INTER, MARK_SVG):
        if not f.exists():
            die(f"missing {f}")
    c = tokens()
    screens = json.loads(a.screens.read_text(encoding="utf-8"))["screens"]
    if a.only:
        screens = [x for x in screens if x["id"] == a.only] or die(f"no screen {a.only}")

    print(f"{'file':<34} {'size':<11} {'mode':<4} sha256")
    made: dict[str, list[Image.Image]] = {k: [] for k in OUTPUTS}
    for sc in screens:
        raw = raw_card(a.raw / sc["raw"], sc.get("masks", []), c)
        for label, size in OUTPUTS.items():
            im = frame(sc, raw, size, c)
            name = f"pro-{sc['id']}-{sc['name']}.png"
            p = a.out / f"{size[0]}x{size[1]}" / name
            digest = save_checked(im, p, size)
            made[label].append(im)
            print(f"{p.relative_to(a.out)!s:<34} {size[0]}×{size[1]:<6} RGB  {digest}")
    if not a.only:
        overview(made["6.3"], a.out / "overview.png")
        print(f"overview: {a.out / 'overview.png'}")


if __name__ == "__main__":
    main()
