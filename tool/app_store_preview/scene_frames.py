"""The frames of a film made of scenes: two frames to choose from, the
cross-dissolves, the end card.

  framed      the stills' frame — paper, mark, Poppins headline, Inter
              sub-line, the capture in the rounded card with its border and
              shadow — with a LARGER card. The stills put the card under a
              two-line sub-line; the scenes' captions are headlines, so the
              card moves up into the sub-line's place and grows down to the
              stills' own margin at the bottom (`FramedLayout`): 711 x 1546,
              64.6 % of the frame, against version 1's 644 x 1400 (53.0 %).
              A film whose captions have sub-lines keeps them: the card then
              starts under its longest one (58.2 % under one line, 55.0 %
              under two).
  full-bleed  the capture fills the frame: scaled by 886/1206 in both
              directions (never stretched), the 8.5 rows of the capture the
              frame's shape has no room for cropped equally top and bottom.
              The caption sits in a band of the brand black (`primary`), white
              text, over the capture — under the status bar, or above the home
              indicator where a scene's touch is near the top. Its sizes are
              the app's tokens: Poppins at `headlineSmall`, Inter at
              `bodyLarge`, padding `spacingM`/`spacingSM`, margins
              `spacingM`, corners `radiusXXL` (app_theme.dart,
              text_styles.dart — read, not typed).

Both share the end card (the mark, « MyWeli Pro », the sign-in disclosure,
in the stills' type) and the dissolves: every pixel of the frame goes from
one picture to the next along the motion token's curve.
"""

from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

import frames
import masks as masking
import scenes
from brand import ROOT, colours, die, motion, stills

L = stills.L
APP_THEME = ROOT / "mobile/lib/core/theme/app_theme.dart"
TEXT_STYLES = ROOT / "mobile/lib/core/theme/text_styles.dart"


# ---- tokens the band is drawn with -----------------------------------------------

def dimension(name: str) -> float:
    """A spacing or radius token of AppTheme, in points."""
    m = re.search(rf"static const double {name} = ([\d.]+);", APP_THEME.read_text(encoding="utf-8"))
    if not m:
        die(f"no dimension token `{name}` in {APP_THEME}")
    return float(m.group(1))


def text_style(name: str) -> tuple[float, float]:
    """(font size, line height) of an AppTextStyles style, in points."""
    src = TEXT_STYLES.read_text(encoding="utf-8")
    m = re.search(rf"static const TextStyle {name} = TextStyle\((.*?)\);", src, re.S)
    if not m:
        die(f"no text style `{name}` in {TEXT_STYLES}")
    size = re.search(r"fontSize: ([\d.]+)", m.group(1))
    height = re.search(r"height: ([\d.]+) / ([\d.]+)", m.group(1))
    if not size or not height:
        die(f"text style `{name}` has no fontSize or height in {TEXT_STYLES}")
    return float(size.group(1)), float(height.group(1))


# ---- the framed variant: the stills' frame, a larger card ------------------------

class FramedLayout(frames.Layout):
    """The stills' layout at the film's size, the card moved up into the
    sub-line's place (or under the film's longest sub-line) and grown down
    to the stills' own margin at the bottom. Mark, headline and sub-line
    are where the stills have them."""

    def __init__(self, size: tuple[int, int], raw_size: tuple[int, int], sub_lines: int):
        super().__init__(size, raw_size)
        s = self.s
        bottom = self.H - (self.card_y + self.card_h)          # the stills' margin under the card
        gap = (L["sub_top"] - L["head_top"] - 2 * L["head_px"] * L["head_lh"]) * s   # under the headline
        top = self.head_top + 2 * self.head_lh + gap
        if sub_lines:
            top += sub_lines * self.sub_lh + gap
        stills_w = self.card_w
        self.card_y = round(top)
        self.card_w = int((self.H - bottom - self.card_y) * self.raw_w / self.raw_h)
        self.card_h = round(self.card_w * self.raw_h / self.raw_w)
        self.card_x = (self.W - self.card_w) // 2
        self.card_radius = round(L["card_radius"] * s * self.card_w / stills_w)
        if self.card_w <= 0 or self.card_y + self.card_h > self.H - bottom + 1:
            die(f"the framed card has no room under {sub_lines} line(s) of sub-line at {self.W}x{self.H}")

    def share(self) -> float:
        return self.card_w * self.card_h / (self.W * self.H)


def framed_composer(sb: dict, raw_size: tuple[int, int], points: tuple[float, float]) -> frames.Composer:
    sub = max(len(s["subline"]) for s in sb["scenes"])
    film = {"film": sb["film"], "touch": sb["touch"],
            "motion": {"caption": sb["motion"]["join"], "touch_in": sb["motion"]["touch_in"],
                       "touch_out": sb["motion"]["touch_out"]},
            "captions": {s["id"]: {"headline": s["headline"], "subline": s["subline"]} for s in sb["scenes"]}}
    return frames.Composer(film, raw_size, points, FramedLayout((sb["film"]["width"], sb["film"]["height"]),
                                                                 raw_size, sub))


# ---- the full-bleed variant -------------------------------------------------------

class FullBleed(frames.Composer):
    """The capture fills the frame; the caption is a band over it."""

    def __init__(self, sb: dict, raw_size: tuple[int, int], points: tuple[float, float]):
        film = {"film": sb["film"], "touch": sb["touch"],
                "motion": {"caption": sb["motion"]["join"], "touch_in": sb["motion"]["touch_in"],
                           "touch_out": sb["motion"]["touch_out"]},
                "captions": {}}
        super().__init__(film, raw_size, points)
        W, H = self.size
        self.raw = raw_size
        self.scale = W / raw_size[0]                       # the same in both directions: never stretched
        self.rows = H / self.scale                         # the capture's rows the frame shows
        self.y0 = (raw_size[1] - self.rows) / 2            # cropped equally top and bottom
        if self.y0 < 0:
            die(f"a {raw_size[0]}x{raw_size[1]} capture is too short to fill {W}x{H}")
        self.pt = W / points[0]                            # frame pixels per point
        self.dy_pt = self.y0 / (raw_size[0] / points[0])   # the crop at the top, in points
        self.points = points
        self.sb2 = sb
        self._bands: dict[str, tuple[Image.Image, tuple[int, int, int, int]]] = {}

    def card(self, raw: Image.Image) -> Image.Image:
        if raw.size != self.raw:
            die(f"a capture is {raw.size[0]}x{raw.size[1]}, expected {self.raw[0]}x{self.raw[1]}")
        return raw.convert("RGB").resize(self.size, Image.LANCZOS, box=(0, self.y0, self.raw[0], self.y0 + self.rows))

    def ground(self, card, x_pt, y_pt):
        return super().ground(card, x_pt, y_pt - self.dy_pt)

    def draw_touch(self, card, x_pt, y_pt, alpha, tone):
        super().draw_touch(card, x_pt, y_pt - self.dy_pt, alpha, tone)

    def capture_box(self, box: tuple[int, int, int, int]) -> tuple[int, int, int, int]:
        """A box of capture pixels, in frame pixels (rounded outwards)."""
        x0, y0, x1, y1 = box
        f = self.scale
        return (int(np.floor(x0 * f)), int(np.floor((y0 - self.y0) * f)),
                int(np.ceil(x1 * f)), int(np.ceil((y1 - self.y0) * f)))

    def band(self, scene: dict) -> tuple[Image.Image, tuple[int, int, int, int]]:
        """The caption band of a scene: an RGBA layer the size of the frame,
        and its box in frame pixels."""
        sid = scene["id"]
        if sid in self._bands:
            return self._bands[sid]
        pt, c = self.pt, colours()
        margin, pad_h, pad_v = dimension("spacingM"), dimension("spacingM"), dimension("spacingSM")
        radius = dimension("radiusXXL")
        head_pt, head_lh = text_style("headlineSmall")
        floor_pt, _ = text_style("titleLarge")
        sub_pt, sub_lh = text_style("bodyLarge")
        width = self.size[0] - 2 * margin * pt
        column = width - 2 * pad_h * pt
        size = head_pt
        while True:
            font = ImageFont.truetype(str(stills.POPPINS), round(size * pt))
            if all(font.getlength(t) <= column for t in scene["headline"]):
                break
            size -= 1
            if size < floor_pt:
                die(f"scene {sid}: the headline does not fit the band at {floor_pt:g} pt: {scene['headline']}")
        sub = stills.inter(round(sub_pt * pt))
        for t in scene["subline"]:
            if sub.getlength(t) > column:
                die(f"scene {sid}: a sub-line is wider than the band: {t}")
        for t in scene["headline"]:
            frames.check_glyphs(t, font, f"scene {sid}'s headline")
        for t in scene["subline"]:
            frames.check_glyphs(t, sub, f"scene {sid}'s sub-line")
        lines = [(t, font, head_lh * pt) for t in scene["headline"]] + [(t, sub, sub_lh * pt) for t in scene["subline"]]
        probe = ImageDraw.Draw(Image.new("L", (8, 8)))
        y, ink_top, ink_bottom, placed = 0.0, None, None, []
        for t, f, lh in lines:
            bbox = probe.textbbox((0, y), t, font=f, anchor="ma")
            ink_top = bbox[1] if ink_top is None else min(ink_top, bbox[1])
            ink_bottom = bbox[3] if ink_bottom is None else max(ink_bottom, bbox[3])
            placed.append((t, f, y))
            y += lh
        height = (ink_bottom - ink_top) + 2 * pad_v * pt
        x0 = margin * pt
        if scene["band"] == "top":
            top = (self.sb2["band"]["top_pt"] - self.dy_pt) * pt
        else:
            top = (self.points[1] - self.sb2["band"]["bottom_pt"] - self.dy_pt) * pt - height
        box = (round(x0), round(top), round(x0 + width), round(top + height))
        layer = Image.new("RGBA", self.size, (0, 0, 0, 0))
        ss = stills.SUPERSAMPLE
        shape = Image.new("L", ((box[2] - box[0]) * ss, (box[3] - box[1]) * ss), 0)
        ImageDraw.Draw(shape).rounded_rectangle((0, 0, shape.width - 1, shape.height - 1), radius=radius * pt * ss,
                                                fill=255)
        shape = shape.resize((box[2] - box[0], box[3] - box[1]), Image.LANCZOS)
        layer.paste(Image.new("RGBA", shape.size, c["primary"] + (255,)), box[:2], shape)
        d = ImageDraw.Draw(layer)
        shift = top + pad_v * pt - ink_top
        for t, f, yy in placed:
            d.text((self.size[0] / 2, yy + shift), t, font=f, fill=c["secondary"] + (255,), anchor="ma")
        self._bands[sid] = (layer, box)
        return layer, box

    def band_points(self, scene: dict) -> list[float]:
        """The band's box in device points, as the gesture log counts them."""
        _, (x0, y0, x1, y1) = self.band(scene)
        return [x0 / self.pt, y0 / self.pt + self.dy_pt, x1 / self.pt, y1 / self.pt + self.dy_pt]

    def compose(self, scene: dict, card: Image.Image) -> Image.Image:
        layer, _ = self.band(scene)
        out = card.convert("RGBA")
        out.alpha_composite(layer)
        return out.convert("RGB")


# ---- the end card -----------------------------------------------------------------

# The end card's layout, in px at 1320 wide like the stills' table `L` (and
# scaled the same way): a sign-off, so larger than the stills' header — the
# mark three times the stills' 64, the title half as large again as their
# 88-px headline, the disclosure line a fifth larger than their 44-px
# sub-line: at the size the App Store shows a preview, the line Apple asks
# for must be read. The colours are the stills' (textPrimary, textSecondary
# on surface).
END = {"mark_h": 192, "title_px": 132, "line_px": 52, "mark_gap": 72, "line_gap": 40, "col": 1128}


def end_card(sb: dict) -> Image.Image:
    """The mark, « MyWeli Pro » and the sign-in disclosure, on the paper, in
    the stills' type (Poppins, Inter), the group centred."""
    W, H = sb["film"]["width"], sb["film"]["height"]
    s = W / frames.STILLS_WIDTH
    c = colours()
    end = sb["end_card"]
    mark = stills.mark(round(END["mark_h"] * s))
    title = ImageFont.truetype(str(stills.POPPINS), round(END["title_px"] * s))
    line = stills.inter(round(END["line_px"] * s))
    frames.check_glyphs(end["title"], title, "the end card's title")
    frames.check_glyphs(end["line"], line, "the end card's line")
    for text, font in ((end["title"], title), (end["line"], line)):
        if font.getlength(text) > END["col"] * s:
            die(f"the end card's « {text} » is wider than its column")
    probe = ImageDraw.Draw(Image.new("L", (8, 8)))
    t_box = probe.textbbox((0, 0), end["title"], font=title, anchor="ma")
    l_box = probe.textbbox((0, 0), end["line"], font=line, anchor="ma")
    block = mark.height + END["mark_gap"] * s + t_box[3] + END["line_gap"] * s + l_box[3]
    top = (H - block) / 2
    canvas = Image.new("RGB", (W, H), c["surface"])
    canvas.paste(mark, ((W - mark.width) // 2, round(top)), mark)
    d = ImageDraw.Draw(canvas)
    y = top + mark.height + END["mark_gap"] * s
    d.text((W / 2, y), end["title"], font=title, fill=c["textPrimary"], anchor="ma")
    d.text((W / 2, y + t_box[3] + END["line_gap"] * s), end["line"], font=line, fill=c["textSecondary"], anchor="ma")
    return canvas


def blend(a: Image.Image, b: Image.Image, k: float) -> Image.Image:
    if k <= 0:
        return a
    if k >= 1:
        return b
    x = np.asarray(a, dtype=np.float32)
    y = np.asarray(b, dtype=np.float32)
    return Image.fromarray(np.rint(x + (y - x) * k).astype(np.uint8), "RGB")


# ---- the film ---------------------------------------------------------------------

def timeline(plan: dict) -> list[tuple]:
    """What each film frame is:
      ("pic", scene, local frame, n-th picture frame of the scene)
      ("in", scene, local frame, i, count)   the scene's own dissolve
      ("join", scene, i, count)              the join after a scene
      ("end", i)                             the end card"""
    out: list[tuple] = []
    for si, (ps, j) in enumerate(zip(plan["scenes"], plan["joins"])):
        local, pic = 0, 0
        for kind, _, count in scenes.scene_layout(ps):
            for i in range(count):
                if kind == "run":
                    out.append(("pic", si, local, pic))
                    pic += 1
                else:
                    out.append(("in", si, local, i, count))
                local += 1
        out += [("join", si, i, j["frames"]) for i in range(j["frames"])]
    out += [("end", i) for i in range(plan["end_card"]["frames"])]
    return out


def compose_film(sb: dict, plan: dict, data: dict[str, dict], out_dir: Path,
                 points: tuple[float, float]) -> dict:
    """Every frame of the film, written once per distinct picture.
    `data[scene id]`: `manifest` and `src` (conform export of the scene),
    `masks` (picture number -> [masks.OnPicture]), `take_T`. Returns the
    frame count, the touch grounds, and the masked regions verify checks."""
    fps = sb["film"]["fps"]
    raw_size = None
    for d in data.values():
        raw_size = (d["manifest"]["width"], d["manifest"]["height"])
    variant = plan["frame"]
    composer = FullBleed(sb, raw_size, points) if variant == "full-bleed" else framed_composer(sb, raw_size, points)
    the_end = end_card(sb)
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "masks").mkdir(exist_ok=True)
    tl = timeline(plan)
    scenes_sb = sb["scenes"]
    expected = {f"{s['id']}/{g}": want for s in scenes_sb for g, want in scenes.grounds(s).items()}
    tones: dict[str, str] = {}
    landed: dict[str, dict] = {}
    T_of = {s["id"]: data[s["id"]]["take_T"] for s in scenes_sb}
    out_ticks = {s["id"]: motion(sb["motion"]["touch_out"]).frames(fps) * (T_of[s["id"]] // fps) for s in scenes_sb}
    cache: dict[tuple, Image.Image] = {}
    names: list[str] = []
    written: dict[tuple, str] = {}
    regions: list[dict] = []

    def raw_of(si: int, j: int, masked: bool) -> Image.Image:
        d = data[scenes_sb[si]["id"]]
        with Image.open(d["src"] / d["manifest"]["sources"][str(j)]["file"]) as im:
            raw = im.convert("RGB")
        if masked:
            for m in d["masks"].get(j, []):
                raw = masking.cover(raw, m.box, m.style, m.colour)
        return raw

    def boxes_of(si: int, j: int) -> list[tuple[int, int, int, int]]:
        out = []
        for m in data[scenes_sb[si]["id"]]["masks"].get(j, []):
            if variant == "full-bleed":
                b = composer.capture_box(m.box)
            else:
                lay = composer.lay
                fx, fy = lay.card_w / lay.raw_w, lay.card_h / lay.raw_h
                b = (lay.card_x + int(np.floor(m.box[0] * fx)), lay.card_y + int(np.floor(m.box[1] * fy)),
                     lay.card_x + int(np.ceil(m.box[2] * fx)), lay.card_y + int(np.ceil(m.box[3] * fy)))
            b = (max(0, b[0]), max(0, b[1]), min(composer.size[0], b[2]), min(composer.size[1], b[3]))
            if b[2] > b[0] and b[3] > b[1]:
                out.append(b)
        return out

    def picture(si: int, local: int, pic: int, masked: bool = True) -> tuple[Image.Image, tuple]:
        """A scene's frame: the capture (masked), the touch points, the caption."""
        scene, ps = scenes_sb[si], plan["scenes"][si]
        d = data[scene["id"]]
        j = d["manifest"]["film"][pic]
        active = []
        for t in ps["touches"]:
            state = composer.touch_state(t, local, T_of[scene["id"]])
            if state is None:
                continue
            x, y, alpha = state
            gid = t["gesture"]
            if gid not in tones:
                at_x, at_y = t["path"][0][1:3]
                card = composer.card(raw_of(si, j, True))
                tones[gid] = composer.tone(card, at_x, at_y)
                under, around = composer.ground(card, at_x, at_y) or (1.0, 1.0)
                got = "dark" if tones[gid] == "light" else "light"
                landed[gid] = {"at": [at_x, at_y], "ground": got, "under": round(under, 3), "around": round(around, 3)}
                want = expected.get(gid, "light")
                if got != want:
                    die(f"the touch of `{gid}` lands on a {got} ground at ({at_x:g}, {at_y:g}) pt — luminance "
                        f"{under:.2f} under the finger — and the storyboard says {want}: it missed what it was "
                        f"aimed at, or the screen is not the storyboard's")
            active.append((round(x, 3), round(y, 3), round(alpha, 4), tones[gid]))
        key = ("pic", si, j, tuple(active), masked)
        if key not in cache:
            if len(cache) > 24:
                cache.pop(next(iter(cache)))
            card = composer.card(raw_of(si, j, masked))
            for x, y, alpha, tone in active:
                composer.draw_touch(card, x, y, alpha, tone)
            if variant == "full-bleed":
                image = composer.compose(scene, card)
            else:
                image = composer.frame(composer.under(scene["id"]), card)
            cache[key] = image
        return cache[key], key

    def last_pic(si: int) -> tuple[int, int]:
        ps = plan["scenes"][si]
        n = scenes.scene_frames(ps)
        count = sum(c for kind, _, c in scenes.scene_layout(ps) if kind == "run")
        return n - 1, count - 1

    def save(n: int, image: Image.Image, key: tuple) -> None:
        if key not in written:
            name = f"f_{n:06d}.png"
            stills.save_checked(image, out_dir / name, composer.size)
            written[key] = name
        names.append(written[key])

    def region(n: int, boxes: list, masked: Image.Image, original: Image.Image, key: tuple) -> None:
        for b in boxes:
            tag = hashlib.sha256(repr((key, b)).encode()).hexdigest()[:16]
            m, o = out_dir / "masks" / f"m_{tag}.png", out_dir / "masks" / f"o_{tag}.png"
            if not m.exists():
                masked.crop(b).save(m)
                original.crop(b).save(o)
            regions.append({"frame": n, "box": list(b), "masked": f"masks/{m.name}", "original": f"masks/{o.name}"})

    def pic_counts(si: int) -> list[int]:
        """Scene-local frame -> n-th picture frame (or -1 in its dissolve)."""
        out, pic = [], 0
        for kind, _, count in scenes.scene_layout(plan["scenes"][si]):
            for _ in range(count):
                out.append(pic if kind == "run" else -1)
                pic += kind == "run"
        return out

    counts = [pic_counts(si) for si in range(len(scenes_sb))]
    for n, f in enumerate(tl):
        if f[0] == "pic":
            _, si, local, pic = f
            image, key = picture(si, local, pic)
            save(n, image, key)
            boxes = boxes_of(si, data[scenes_sb[si]["id"]]["manifest"]["film"][pic])
            if boxes:
                region(n, boxes, image, picture(si, local, pic, masked=False)[0], key)
            continue
        if f[0] == "in":
            _, si, local, i, count = f
            ends = [(si, local - i - 1), (si, local - i + count)]
            token = motion(plan["scenes"][si]["dissolves"][0]["token"])
        elif f[0] == "join":
            _, si, i, count = f
            ends = [(si, last_pic(si)[0])] + ([(si + 1, 0)] if si + 1 < len(scenes_sb) else [None])
            token = motion(plan["joins"][si]["token"])
        else:
            save(n, the_end, ("end",))
            continue
        k = round(token.at((i + 1) / fps), 6)
        sides, plain, boxes = [], [], []
        for end in ends:
            if end is None:
                sides.append((the_end, ("end",)))
                plain.append(the_end)
                continue
            s_i, loc = end
            p = counts[s_i][loc]
            image, key = picture(s_i, loc, p)
            sides.append((image, key))
            plain.append(picture(s_i, loc, p, masked=False)[0])
            boxes += boxes_of(s_i, data[scenes_sb[s_i]["id"]]["manifest"]["film"][p])
        key = ("blend", sides[0][1], sides[1][1], k)
        image = blend(sides[0][0], sides[1][0], k)
        save(n, image, key)
        if boxes:
            region(n, boxes, image, blend(plain[0], plain[1], k), key)

    manifest = {"fps": fps, "width": composer.size[0], "height": composer.size[1], "frames": names}
    (out_dir / "frames.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    info = {"frames": len(names), "pictures": len(written), "grounds": landed, "regions": regions}
    if variant == "framed":
        lay = composer.lay
        info["card"] = {"x": lay.card_x, "y": lay.card_y, "w": lay.card_w, "h": lay.card_h,
                        "share": round(lay.share(), 4)}
    else:
        info["bands"] = {s["id"]: composer.band(s)[1] for s in scenes_sb}
    return info


def band_points(sb: dict, raw_size: tuple[int, int], points: tuple[float, float]) -> dict[str, list[float]]:
    """Each scene's caption band in device points (the full-bleed frame)."""
    fb = FullBleed(sb, raw_size, points)
    return {s["id"]: fb.band_points(s) for s in sb["scenes"]}
