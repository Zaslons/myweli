"""Compose the film's frames: the App Store stills' frame, with a live card.

Every frame is 886 x 1920 RGB:

  paper, the MyWeli mark, the headline and the sub-line — the stills' own
  drawing, at the stills' own numbers x 886/1320 (`Layout`);
  the capture, scaled into the stills' card with its border and its shadow;
  the touch point, drawn on the capture and clipped by the card.

A caption changes by cross-fading in place: every pixel goes from the old
picture to the new one along the motion token's curve, so a headline that
stays the same does not flicker while a sub-line appears under it. Nothing
else moves in the paper; everything that moves in the card is the app.

The layout numbers are not typed here. `Layout` takes them from the stills'
table `L` (px at 1320 wide) and scales them once; tests/test_frames.py
checks that a film frame with a still capture is, pixel for pixel, the frame
`tool/app_store_screenshots/compose.py` would make at 886 x 1920.
"""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from brand import colours, die, motion, stills

L = stills.L
STILLS_WIDTH = 1320  # the width the stills' table `L` is given at


class Layout:
    """The stills' layout at the film's size. The single place where
    886/1320 is applied."""

    def __init__(self, size: tuple[int, int], raw_size: tuple[int, int]):
        self.W, self.H = size
        self.s = s = self.W / STILLS_WIDTH
        self.raw_w, self.raw_h = raw_size
        self.mark_h = round(L["mark_h"] * s)
        self.mark_top = round(L["mark_top"] * s)
        self.head_top = L["head_top"] * s
        self.head_lh = round(L["head_px"] * L["head_lh"] * s)
        self.head_col = L["head_col"] * s
        self.sub_px = round(L["sub_px"] * s)
        self.sub_top = L["sub_top"] * s
        self.sub_lh = L["sub_lh"] * s
        self.sub_col = L["sub_col"] * s
        self.card_w = round(L["card_w"] * s)
        self.card_h = round(self.card_w * self.raw_h / self.raw_w)
        self.card_x = (self.W - self.card_w) // 2
        self.card_y = round(L["card_top"] * s)
        self.card_radius = round(L["card_radius"] * s)
        self.card_border = max(1, round(L["card_border"] * s))
        if self.card_y + self.card_h > self.H:
            die(f"the card overflows the canvas at {self.W}x{self.H}")


def _drawn(font, ch: str) -> tuple[bytes, float]:
    side = font.size * 3
    im = Image.new("L", (side, side), 0)
    ImageDraw.Draw(im).text((font.size, font.size), ch, font=font, fill=255)
    return im.tobytes(), font.getlength(ch)


def check_glyphs(text: str, font, what: str) -> None:
    """A character the font does not have is drawn as the font's « missing »
    box — the picture U+FFFF, which no font has, comes out as."""
    missing = _drawn(font, chr(0xFFFF))
    for ch in text:
        if _drawn(font, ch) == missing:
            die(f"{what}: the font has no glyph for {ch!r} (U+{ord(ch):04X}) in « {text} »")


class Composer:
    def __init__(self, storyboard: dict, raw_size: tuple[int, int], device_points: tuple[float, float]):
        film = storyboard["film"]
        self.sb = storyboard
        self.size = (film["width"], film["height"])
        self.fps = film["fps"]
        self.lay = Layout(self.size, raw_size)
        self.c = colours()
        self.pt = self.lay.card_w / device_points[0]  # card px per device point
        # the capture and the screen in points must be the same shape
        if abs(raw_size[0] * device_points[1] - raw_size[1] * device_points[0]) > 0.001 * raw_size[1] * device_points[0]:
            die(f"a {raw_size[0]}x{raw_size[1]} capture is not {device_points[0]:g}x{device_points[1]:g} points")
        for f in (stills.POPPINS, stills.INTER, stills.MARK_SVG):
            if not f.exists():
                die(f"missing {f}")
        self.mark = stills.mark(self.lay.mark_h)
        lay = self.lay
        self.mask = stills.rounded_mask((lay.card_w, lay.card_h), lay.card_radius)
        ss = stills.SUPERSAMPLE
        ring = Image.new("L", (lay.card_w * ss, lay.card_h * ss), 0)
        ImageDraw.Draw(ring).rounded_rectangle(
            (0, 0, lay.card_w * ss - 1, lay.card_h * ss - 1),
            radius=lay.card_radius * ss, outline=255, width=lay.card_border * ss)
        self.ring = ring.resize((lay.card_w, lay.card_h), Image.LANCZOS)
        self.border = Image.new("RGB", (lay.card_w, lay.card_h), self.c["border"])
        self._under: dict[str, Image.Image] = {}
        self._fade = motion(storyboard["motion"]["caption"])
        self._in = motion(storyboard["motion"]["touch_in"])
        self._out = motion(storyboard["motion"]["touch_out"])

    # ---- the paper ----------------------------------------------------------

    def caption_fonts(self, caption: dict):
        lay = self.lay
        head = stills.fit_headline(caption["headline"], lay.s)
        sub = stills.inter(lay.sub_px)
        lines = stills.wrap_subline(caption["subline"], sub, lay.sub_col) if caption["subline"] else []
        for t in caption["headline"]:
            check_glyphs(t, head, "headline")
        for t in lines:
            check_glyphs(t, sub, "sub-line")
        return head, sub, lines

    def text_bottom(self, caption: dict) -> float:
        """The lowest inked row of a caption — it must stay above the card."""
        lay = self.lay
        head, sub, lines = self.caption_fonts(caption)
        probe = ImageDraw.Draw(Image.new("RGB", self.size))
        bottom = 0.0
        for i, t in enumerate(caption["headline"]):
            bottom = max(bottom, probe.textbbox((lay.W / 2, lay.head_top + i * lay.head_lh), t, font=head, anchor="ma")[3])
        for i, t in enumerate(lines):
            bottom = max(bottom, probe.textbbox((lay.W / 2, lay.sub_top + i * lay.sub_lh), t, font=sub, anchor="ma")[3])
        return bottom

    def under(self, caption_id: str) -> Image.Image:
        """Everything below the card: paper, mark, caption, the card's shadow.
        The same calls, in the same order, as the stills' `frame()`."""
        if caption_id in self._under:
            return self._under[caption_id]
        if caption_id not in self.sb["captions"]:
            die(f"no caption `{caption_id}` in the storyboard")
        caption = self.sb["captions"][caption_id]
        lay, c = self.lay, self.c
        canvas = Image.new("RGB", self.size, c["surface"])
        draw = ImageDraw.Draw(canvas)
        canvas.paste(self.mark, ((lay.W - self.mark.width) // 2, lay.mark_top), self.mark)

        head, sub, lines = self.caption_fonts(caption)
        for i, t in enumerate(caption["headline"]):
            draw.text((lay.W / 2, lay.head_top + i * lay.head_lh), t, font=head,
                      fill=c["textPrimary"], anchor="ma")
        for i, t in enumerate(lines):
            draw.text((lay.W / 2, lay.sub_top + i * lay.sub_lh), t, font=sub,
                      fill=c["textSecondary"], anchor="ma")
        if self.text_bottom(caption) >= lay.card_y:
            die(f"caption `{caption_id}` reaches the capture")

        for opacity, blur, dy in L["shadows"]:
            layer = Image.new("L", self.size, 0)
            layer.paste(self.mask.point(lambda v: round(v * opacity)),
                        (lay.card_x, lay.card_y + round(dy * lay.s)))
            layer = layer.filter(ImageFilter.GaussianBlur(blur * lay.s / 2))
            canvas.paste(Image.new("RGB", self.size, (0, 0, 0)), (0, 0), layer)
        self._under[caption_id] = canvas
        return canvas

    def paper(self, before: str, after: str, k: float) -> Image.Image:
        """The paper while a caption changes: `before` at k = 0, `after` at 1."""
        if k <= 0 or before == after:
            return self.under(before)
        if k >= 1:
            return self.under(after)
        a = np.asarray(self.under(before), dtype=np.float32)
        b = np.asarray(self.under(after), dtype=np.float32)
        return Image.fromarray(np.rint(a + (b - a) * k).astype(np.uint8), "RGB")

    # ---- the card -----------------------------------------------------------

    def card(self, raw: Image.Image) -> Image.Image:
        if raw.size != (self.lay.raw_w, self.lay.raw_h):
            die(f"a capture is {raw.size[0]}x{raw.size[1]}, expected {self.lay.raw_w}x{self.lay.raw_h}")
        return raw.convert("RGB").resize((self.lay.card_w, self.lay.card_h), Image.LANCZOS)

    def tone(self, card: Image.Image, x_pt: float, y_pt: float) -> str:
        """`light` where the touch lands on a dark or green fill, else `dark`."""
        r = self.sb["touch"]["diameter_pt"] / 2 * self.pt
        cx, cy = x_pt * self.pt, y_pt * self.pt
        box = (max(0, round(cx - r)), max(0, round(cy - r)),
               min(card.width, round(cx + r)), min(card.height, round(cy + r)))
        if box[2] <= box[0] or box[3] <= box[1]:
            return "dark"
        patch = np.asarray(card.crop(box), dtype=np.float32) / 255
        luminance = float((patch @ np.array([0.2126, 0.7152, 0.0722], dtype=np.float32)).mean())
        return "light" if luminance < self.sb["touch"]["light_below_luminance"] else "dark"

    def draw_touch(self, card: Image.Image, x_pt: float, y_pt: float, alpha: float, tone: str) -> None:
        """A soft disc with a thin ring, centred to the sub-pixel so a drag
        moves smoothly. Drawn on the capture, so the card's mask clips it."""
        if alpha <= 0:
            return
        t = self.sb["touch"]
        colour = self.c["secondary"] if tone == "light" else self.c["primary"]
        ss = 4
        r = t["diameter_pt"] / 2 * self.pt
        ring_w = t["ring_pt"] * self.pt
        cx, cy = x_pt * self.pt, y_pt * self.pt
        pad = 2
        x0, y0 = int(np.floor(cx - r)) - pad, int(np.floor(cy - r)) - pad
        side = int(np.ceil(2 * r)) + 2 * pad + 1
        big = Image.new("L", (side * ss, side * ss), 0)
        d = ImageDraw.Draw(big)
        ox, oy = (cx - x0) * ss, (cy - y0) * ss
        box = (ox - r * ss, oy - r * ss, ox + r * ss, oy + r * ss)
        d.ellipse(box, fill=round(255 * t["fill_opacity"] * alpha))
        d.ellipse(box, outline=round(255 * t["ring_opacity"] * alpha), width=max(1, round(ring_w * ss)))
        # A plain area average: a sharper filter rings, and a ring of its own
        # shows as a halo around a flat, soft disc.
        a = big.resize((side, side), Image.BOX)
        card.paste(Image.new("RGB", (side, side), colour), (x0, y0), a)

    # ---- one frame ----------------------------------------------------------

    def frame(self, paper: Image.Image, card: Image.Image) -> Image.Image:
        lay = self.lay
        canvas = paper.copy()
        canvas.paste(card, (lay.card_x, lay.card_y), self.mask)
        canvas.paste(self.border, (lay.card_x, lay.card_y), self.ring)
        return canvas

    def caption_state(self, captions: list[dict], n: int) -> tuple[str, str, float]:
        """(old caption, new caption, progress) at film frame n."""
        current, previous, since = captions[0]["caption"], captions[0]["caption"], None
        for c in captions[1:]:
            if c["frame"] <= n:
                previous, current, since = current, c["caption"], c["frame"]
        if since is None:
            return current, current, 1.0
        k = self._fade.at((n - since) / self.fps)
        return previous, current, k

    def touch_state(self, touch: dict, n: int, timescale: int) -> tuple[float, float, float] | None:
        """(x, y, opacity) of a touch point at film frame n, or None."""
        t = n * timescale / self.fps
        down, up = touch["down"], touch["up"]
        if t < down:
            return None
        alpha = self._in.at((t - down) / timescale)
        if t >= up:
            alpha *= 1 - self._out.at((t - up) / timescale)
        if alpha <= 0:
            return None
        path = touch["path"]
        x, y = path[-1][1], path[-1][2]
        for (ta, xa, ya), (tb, xb, yb) in zip(path, path[1:]):
            if t < tb:
                u = max(0.0, (t - ta) / (tb - ta))
                x, y = xa + (xb - xa) * u, ya + (yb - ya) * u
                break
        return x, y, alpha


def compose(storyboard: dict, edit: dict, sources: list[int], source_dir: Path, out_dir: Path,
            device_points: tuple[float, float]) -> dict:
    """Render every film frame. `sources[n]` is the source frame film frame n
    shows; `source_dir` holds them as conform export wrote them. A picture
    that repeats is written once: frames.json names a file for every frame."""
    manifest = json.loads((source_dir / "manifest.json").read_text(encoding="utf-8"))
    if manifest["film"] != sources:
        die("conform export and edit.py disagree on which source frame each film frame shows")
    composer = Composer(storyboard, (manifest["width"], manifest["height"]), device_points)
    out_dir.mkdir(parents=True, exist_ok=True)
    T = edit["timescale"]
    cards: dict[int, Image.Image] = {}
    tones: dict[str, str] = {}
    written: dict[tuple, str] = {}
    names: list[str] = []

    def card_for(j: int) -> Image.Image:
        if j not in cards:
            if len(cards) > 8:
                cards.pop(next(iter(cards)))
            cards[j] = composer.card(Image.open(source_dir / manifest["sources"][str(j)]["file"]))
        return cards[j]

    for n, j in enumerate(sources):
        before, after, k = composer.caption_state(edit["captions"], n)
        k = round(k, 6)
        active = []
        for touch in edit["touches"]:
            state = composer.touch_state(touch, n, T)
            if state is None:
                continue
            x, y, alpha = state
            if touch["gesture"] not in tones:
                # decided once, where the finger lands, on the picture it lands on
                tones[touch["gesture"]] = composer.tone(card_for(j), touch["path"][0][1], touch["path"][0][2])
            active.append((round(x, 3), round(y, 3), round(alpha, 4), tones[touch["gesture"]]))
        if k <= 0:
            after = before          # the change has not begun: the old caption, whole
        elif k >= 1:
            before = after
        key = (before, after, k if before != after else 1.0, j, tuple(active))
        if key not in written:
            card = card_for(j)
            if active:
                card = card.copy()
                for x, y, alpha, tone in active:
                    composer.draw_touch(card, x, y, alpha, tone)
            image = composer.frame(composer.paper(before, after, k), card)
            name = f"f_{n:06d}.png"
            stills.save_checked(image, out_dir / name, composer.size)
            written[key] = name
        names.append(written[key])

    frames = {"fps": composer.fps, "width": composer.size[0], "height": composer.size[1], "frames": names}
    (out_dir / "frames.json").write_text(json.dumps(frames, indent=1) + "\n", encoding="utf-8")
    return {"frames": len(names), "pictures": len(written), "tones": tones}
