"""Showcase sheets for the FX primitives — every primitive at 2–3 states.

  python -m promo.fx.demo [--out DIR] [--shot PNG] [--client PNG]
  (run from tool/promo_reel; DIR defaults to build/promo_reel/fx-demo)

Writes four 1080 × 1920 sheets (sheet-*.png), each a 3 × 3 grid of real
1080 × 1920 frames drawn at a third of their size, and every frame at full
size (frames/*.png) for close inspection. The phone and the lifts use real
captures (default: the App Store raw captures in the main checkout's
build/app-store/pro/raw, read only). Awa K.'s number on the client capture
is blurred before use, as the storyboard requires of every shot of it.

This is a look-book, not the film: the stage, band and layout here are
stand-ins so each primitive can be judged in context.
"""

from __future__ import annotations

import argparse
import sys
import time
from pathlib import Path

import numpy as np
import skia
from scipy import ndimage

from . import blur, carnet, counter, easing, grain, lift, pattern, punch, stack, touch
from . import type as ty
from .brand import PALETTE, ROOT, inter, poppins
from .phone import Phone, Window
from .projection import Pose
from .surface import SAMPLING_CUBIC, Picture, image_from_array, new_surface, save_png, skrect, to_array

W, H = 1080, 1920
RAW = ROOT / "build/app-store/pro/raw"
MAIN_RAW = Path("/Users/sadreddinedaher/beauty app/build/app-store/pro/raw")
WINDOW = Window()


# ---- stand-in stage -----------------------------------------------------------------

def stage(canvas: skia.Canvas, dark: bool, t: float = 0.0, pattern_alpha: float = 1.0,
          clear: tuple | None = None) -> None:
    canvas.clear(PALETTE.BLACK if dark else PALETTE.PAPER)
    pattern.draw_pattern(canvas, (0, 0, W, H), dark=dark, alpha=pattern_alpha, offset=(0, -4.0 * t / 30),
                         clear=clear)


# ---- measuring real cards on a capture (demo only) --------------------------------------

def card_rect(rgb: np.ndarray, x: int, y: int, ground=(246, 247, 249)) -> tuple[float, float, float, float]:
    """The bounding box (capture px) of the card under (x, y): everything
    connected to it that is not the screen's ground (AppColors.background),
    so a card's coloured left border and its badge are part of it."""
    mask = np.any(rgb != np.array(ground, np.uint8), axis=2)
    labels, _ = ndimage.label(mask)
    ys, xs = np.nonzero(labels == labels[y, x])
    return float(xs.min()), float(ys.min()), float(xs.max() + 1), float(ys.max() + 1)


def blur_rect(rgba: np.ndarray, rect_pt, margin_pt: float = 4.0, sigma: float = 14.0, k: float = 3.0) -> np.ndarray:
    """A Gaussian blur over a screen-point rectangle (+ margin) of a capture."""
    x0, y0, x1, y1 = [round(v * k) for v in (rect_pt[0] - margin_pt, rect_pt[1] - margin_pt,
                                              rect_pt[2] + margin_pt, rect_pt[3] + margin_pt)]
    out = rgba.copy()
    pad = int(3 * sigma)
    a0, b0 = max(0, y0 - pad), max(0, x0 - pad)
    region = out[a0:y1 + pad, b0:x1 + pad, :3].astype(np.float32)
    blurred = ndimage.gaussian_filter(region, (sigma, sigma, 0))
    out[y0:y1, x0:x1, :3] = np.clip(blurred[y0 - a0:y1 - a0, x0 - b0:x1 - b0] + 0.5, 0, 255).astype(np.uint8)
    return out


# ---- panels ----------------------------------------------------------------------------

class Demo:
    def __init__(self, shot: Path, client: Path):
        from PIL import Image
        self.agenda_rgba = np.asarray(Image.open(shot).convert("RGBA"))
        self.agenda = Picture(self.agenda_rgba)
        c = np.asarray(Image.open(client).convert("RGBA"))
        # Awa K.'s number: x 97.0–235.3, y 183.0–193.3 pt (storyboard) + 4 pt, sigma 14 px
        self.client_rgba = blur_rect(c, (97.0, 183.0, 235.3, 193.3))
        self.client = Picture(self.client_rgba)
        self.phone = Phone(self.agenda)
        self.carnet = carnet.Carnet(seed=7)
        rgb = self.agenda_rgba[..., :3]
        self.fatou = card_rect(rgb, 1120, 1600)                       # Fatou B.'s card
        crgb = self.client_rgba[..., :3]
        self.tiles = [card_rect(crgb, x, 880) for x in (60, 345, 912)]   # Visites, Dépensé, Dernière

    # ---- sheet A: type and counter ----

    def hook_caption(self, t: float):
        def draw(c):
            stage(c, True, t, 0.4)
            cap = ty.Caption([[ty.Word("Votre", 0), ty.Word("carnet", 8)], [ty.Word("déborde ?", 16)]],
                             poppins(96), PALETTE.WHITE, cap_top=300)
            cap.draw(c, t)
            self._label(c, f"Caption rise+fade  f{t:g}", dark=True)
        return draw

    def strike_stack(self, t: float):
        def draw(c):
            stage(c, True, t, 0.4)
            cap = ty.Caption([[ty.Word("Rayé.", 64)], [ty.Word("Raturé.", 76)], [ty.Word("Recopié.", 88)]],
                             poppins(96), PALETTE.WHITE, cap_top=300, line_height=120)
            cap.draw(c, t)
            self._label(c, f"Stacking words  f{t:g}", dark=True)
        return draw

    def creneau(self, t: float):
        def draw(c):
            stage(c, False, t)
            cap = ty.Caption([[ty.Word("Créneau", 400), ty.Word("libre", 408), ty.Word("rempli.", 448)]],
                             poppins(72), PALETTE.INK, cap_top=330)
            cap.draw(c, t)
            ty.strike_word(c, cap, "libre", t, 440, PALETTE.INK)
            self._label(c, f"Strike « libre »  f{t:g}")
        return draw

    def counter_panel(self, p: float, label_p: float, scale: float, name: str):
        def draw(c):
            stage(c, False, 0)
            odo = counter.Odometer(0, 77000, poppins(120), PALETTE.INK)
            counter.draw_label_switch(c, "Aujourd’hui", "Mois", label_p, inter(40), 540, 360,
                                      PALETTE.INK_SECONDARY)
            odo.draw(c, p, 540, 520, scale=scale)
            self._label(c, f"Counter {name}  « {odo.text_at(p)} »")
        return draw

    # ---- sheet B: phone ----

    def phone_window(self, Wpt: float, pose: Pose = Pose(), touch_t: float | None = None, name: str = ""):
        def draw(c):
            stage(c, False, 0)
            def overlay(cv):
                if touch_t is not None:
                    # Fatou B.'s card, the swipe touch-down point (110, 546) pt
                    tone = touch.tone_at(self.agenda_rgba, 110 * 3, 546 * 3, 48 * 3)
                    touch.draw_tap(cv, 110, 546, touch_t, 0, None, tone=tone)
            self.phone.draw(c, pose, W=Wpt, overlay=overlay)
            self._caption_band_words(c, "Une cliente arrive ?")
            self._label(c, f"Window W={Wpt:g} {name}")
        return draw

    def phone_free(self, pose: Pose, dark: bool, opacity: float = 1.0, name: str = ""):
        def draw(c):
            stage(c, dark, 0, 0.4 if dark else 1.0)
            self.phone.draw(c, pose, centre=(540, 1010), opacity=opacity)
            self._label(c, f"Free {name}", dark=dark)
        return draw

    # ---- sheet C: carnet ----

    def carnet_panel(self, t: float, name: str, *, macro: bool = False, blur_samples: int = 1,
                     sink: float = 1.0, with_grain: bool = True):
        cn = self.carnet
        rest = cn.rest_rect(40, 1040, 640)

        def pose_at(tt: float) -> Pose:
            base = Pose(rot_x=22, pivot=(540, 1250))
            if macro:
                # the squeezed entry, its arrow, the margin note and two crossed rows
                p = Pose(rot_x=16, scale=2.0, pivot=(540, 1250))
                ax0, _, _, _ = cn.entries["arrow"].bounds
                _, sy = cn.entry_centre("squeeze")
                return cn.focus(p, rest, (ax0 + 150, sy + 40), (540, 1200))
            s = easing.lerp(1.10, 1.16, easing.progress(tt, 0, 95))
            if tt >= 96:
                s *= easing.lerp(1.0, 1.5, easing.EASE_IN_CUBIC(easing.progress(tt, 96, 16)))
            s *= punch.Punches([punch.Punch(64), punch.Punch(76), punch.Punch(88)])(tt)
            return base.but(scale=s)

        def page_state(tt: float) -> dict:
            ink = {"write": easing.lerp(0.3, 1.0, easing.progress(tt, 0, 24))}
            if macro:
                ink["margin"] = easing.EASE_OUT(easing.progress(tt, 48, 8))
            strikes = {r: easing.progress(tt, at, 4) for r, at in ((cn.write_row - 7, 64), (cn.write_row - 3, 76),
                                                                    (cn.write_row + 2, 88)) if tt >= at}
            light = sink * (1.0 - 0.85 * easing.EASE_IN(easing.progress(tt, 96, 16)))
            return {"ink": ink, "strikes": strikes, "light": light}

        def scene(cv: skia.Canvas, tt: float) -> None:
            cv.clear(PALETTE.BLACK)
            cn.draw(cv, pose_at(tt), rest, **page_state(tt))

        def draw(c):
            if blur_samples > 1:
                frame = blur.accumulate(scene, (W, H), t, samples=blur_samples)
            else:
                s = new_surface(W, H)
                scene(s.getCanvas(), t)
                frame = to_array(s)
            if with_grain:
                frame = grain.apply_grain(frame, int(t), seed=11)
            c.drawImage(image_from_array(frame), 0, 0)
            if not macro and t < 64:
                cap = ty.Caption([[ty.Word("Votre", 0), ty.Word("carnet", 8)], [ty.Word("déborde ?", 16)]],
                                 poppins(96), PALETTE.WHITE, cap_top=300)
                cap.draw(c, t)
            elif not macro:
                cap = ty.Caption([[ty.Word("Rayé.", 64)], [ty.Word("Raturé.", 76)], [ty.Word("Recopié.", 88)]],
                                 poppins(96), PALETTE.WHITE, cap_top=300, line_height=120)
                cap.draw(c, t)
            self._label(c, f"Carnet {name} f{t:g}", dark=True)
        return draw

    def air(self, t: float):
        def draw(c):
            stage(c, True, t)
            ty.draw_text(c, ty.french("Respirez."), poppins(96), 540, 1000, PALETTE.WHITE, align="centre")
            self._label(c, f"Air beat, dark pattern drifting f{t:g}", dark=True)
        return draw

    # ---- sheet D: lifts, blur, touch, pattern, tagline ----

    def lift_panel(self, p: float):
        def draw(c):
            stage(c, False, 0)
            Wpt = 257.0
            self.phone.draw(c, W=Wpt)
            src = self.fatou
            k = 3.0
            origin = self.phone.map_rect(tuple(v / k for v in src), W=Wpt)
            target = lift.fit_width(src, 120, 900, bottom=1190)
            lift.Lift(self.agenda, src, origin, target).draw(c, p, veil_rect=(0, 0, W, H))
            self._caption_band_words(c, "Une cliente arrive ?")
            self._label(c, f"UI lift p={p:g}")
        return draw

    def stack_panel(self, t: float):
        def draw(c):
            stage(c, False, 0)
            ph = Phone(self.client)
            Wpt = 200.0
            ph.draw(c, W=Wpt)
            k = 3.0
            origins = [ph.map_rect(tuple(v / k for v in r), W=Wpt) for r in self.tiles]
            targets = stack.stack_rects(self.tiles, x0=330, width=360, gap=16, top=660)
            st = stack.Stack(self.client, self.tiles, origins, targets, ups=[472, 480, 488])
            st.draw(c, t, veil_rect=(0, 0, W, H))
            self._label(c, f"Stacked lifts f{t:g}")
        return draw

    def whip_panel(self, t: float, samples: int | None):
        whip = blur.WhipPan(start=256, distance=403.0)      # W 257 → 660 pt

        def scene(cv, tt):
            cv.clear(PALETTE.PAPER)
            pattern.draw_pattern(cv, (0, 0, W, H), dark=False)
            # subframes need no Lanczos: the blur is softer than any resampler
            self.phone.draw(cv, W=257.0 + whip.offset(tt), sampling=SAMPLING_CUBIC)

        def draw(c):
            n = samples or whip.samples(t, px_per_unit=WINDOW.px_per_pt)
            window = (0, int(WINDOW.top - WINDOW.band_fade), W, int(WINDOW.floor + WINDOW.floor_fade))
            frame = blur.accumulate(scene, (W, H), t, samples=n, region=window)
            c.drawImage(image_from_array(frame), 0, 0)
            self._label(c, f"Vertical whip f{t:g}  {n} subframes")
        return draw

    def hwhip_panel(self, t: float):
        whip = blur.WhipPan(start=512, distance=-W)

        client_phone = Phone(self.client)

        def out_scene(cv):
            cv.drawRect(skrect((0, 0, W, H)), skia.Paint(Color=PALETTE.PAPER))
            pattern.draw_pattern(cv, (0, 0, W, H), dark=False)
            client_phone.draw(cv, W=200.0, sampling=SAMPLING_CUBIC)

        def in_scene(cv):
            cv.drawRect(skrect((0, 0, W, H)), skia.Paint(Color=PALETTE.PAPER))
            pattern.draw_pattern(cv, (0, 0, W, H), dark=False)
            self.phone.draw(cv, W=56.0, sampling=SAMPLING_CUBIC)

        def scene(cv, tt):
            whip.draw_transition(cv, tt, out_scene, in_scene, axis="x")

        def draw(c):
            n = whip.samples(t)
            frame = blur.accumulate(scene, (W, H), t, samples=n)
            c.drawImage(image_from_array(frame), 0, 0)
            self._label(c, f"Horizontal whip f{t:g}  {n} subframes")
        return draw

    def touch_panel(self):
        def draw(c):
            stage(c, False, 0)
            # three ripple stages on light ground, three on the black stage
            c.drawRect(skrect((0, 1100, W, H)), skia.Paint(Color=PALETTE.BLACK))
            for i, tt in enumerate((0, 3, 7)):
                x = 220 + i * 320
                touch.draw_tap(c, x, 800, tt, 0, None, tone="dark", scale=WINDOW.px_per_pt)
                touch.draw_tap(c, x, 1450, tt, 0, None, tone="light", scale=WINDOW.px_per_pt)
                ty.draw_text(c, f"f+{tt}", inter(32), x, 960, PALETTE.INK_SECONDARY, align="centre")
            self._label(c, "Touch disc + ripple, dark / light")
        return draw

    def pattern_panel(self, t: float, dark: bool):
        def draw(c):
            stage(c, dark, t, 1.0, clear=(180, 700, 900, 1100))
            self._label(c, f"Pattern {'dark' if dark else 'light'} t={t:g} (clear zone)", dark=dark)
        return draw

    def tagline_panel(self, t: float):
        def draw(c):
            c.clear(PALETTE.PAPER)
            cap = ty.Caption([[ty.Word("Plus de clients,", 832), ty.Word("moins de gestion.", 848)]],
                             poppins(46), PALETTE.INK, cap_top=712, reveal=ty.MASK)
            cap.draw(c, t)
            self._label(c, f"Tagline mask reveal f{t:g}")
        return draw

    # ---- helpers ----

    def _caption_band_words(self, c, text):
        ty.Caption([[ty.Word(w, -10) for w in text.split(" ")]], poppins(72), PALETTE.INK, cap_top=330).draw(c, 0)

    @staticmethod
    def _label(c, text, dark=False):
        ty.draw_text(c, text, inter(30, 500), 40, 1880, 0xFF8A8A8A if not dark else 0xFF6E6E6E)


def render_sheet(name: str, panels, out: Path) -> Path:
    sheet = new_surface(W, H)
    sc = sheet.getCanvas()
    sc.clear(0xFF202020)
    for i, (pname, draw) in enumerate(panels):
        t0 = time.time()
        s = new_surface(W, H)
        draw(s.getCanvas())
        save_png(s, out / "frames" / f"{name}-{i + 1}-{pname}.png")
        img = s.makeImageSnapshot().withDefaultMipmaps()
        col, row = i % 3, i // 3
        sc.drawImageRect(img, skrect((col * 360, row * 640, col * 360 + 360, row * 640 + 640)),
                         skia.SamplingOptions(skia.FilterMode.kLinear, skia.MipmapMode.kLinear))
        print(f"  {name} {i + 1} {pname}: {1000 * (time.time() - t0):.0f} ms", flush=True)
    # hairlines between panels
    line = skia.Paint(Color=0xFF202020, StrokeWidth=2, Style=skia.Paint.kStroke_Style)
    for k in (1, 2):
        sc.drawLine(k * 360, 0, k * 360, H, line)
        sc.drawLine(0, k * 640, W, k * 640, line)
    return save_png(sheet, out / f"sheet-{name}.png")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", type=Path, default=ROOT / "build/promo_reel/fx-demo")
    ap.add_argument("--shot", type=Path, default=None, help="agenda capture (pro-01-agenda.png)")
    ap.add_argument("--client", type=Path, default=None, help="client capture (pro-05-client.png)")
    ap.add_argument("--only", default=None, help="render one sheet: type, phone, carnet, fx")
    a = ap.parse_args(argv)
    raw = RAW if (RAW / "pro-01-agenda.png").is_file() else MAIN_RAW
    shot = a.shot or raw / "pro-01-agenda.png"
    client = a.client or raw / "pro-05-client.png"
    for p in (shot, client):
        if not p.is_file():
            print(f"demo: capture not found: {p} (pass --shot / --client)", file=sys.stderr)
            return 2
    d = Demo(shot, client)
    sheets = {
        "type": [
            ("hook-f0", d.hook_caption(0)), ("hook-f9", d.hook_caption(9)), ("hook-f20", d.hook_caption(20)),
            ("stack-f78", d.strike_stack(78)), ("strike-f441", d.creneau(441)), ("strike-f452", d.creneau(452)),
            ("counter-0", d.counter_panel(0.0, 0.0, 1.0, "p=0")),
            ("counter-mid", d.counter_panel(0.35, 1.0, 1.0, "p=0.35")),
            ("counter-land", d.counter_panel(1.0, 1.0, punch.settle(553, 552), "landed +1f")),
        ],
        "phone": [
            ("window-56", d.phone_window(56.0)),
            ("window-257-touch", d.phone_window(257.0, touch_t=4, name="touch")),
            ("slam", d.phone_window(150.0, Pose(rot_x=14, scale=1.10), name="slam rotX14 ×1.10")),
            ("free-rotx12", d.phone_free(Pose(rot_x=12), False, name="rotX 12")),
            ("free-roty-10", d.phone_free(Pose(rot_y=-10), False, name="rotY −10")),
            ("fall-back", d.phone_free(Pose(scale=0.93), True, 0.55, "falling back on black")),
            ("window-660", d.phone_window(660.0, name="lower journal")),
            ("push-2.0", d.phone_window(600.0, Pose(scale=2.0 / 1.791), name="push 2.0 px/pt")),
            ("free-extreme", d.phone_free(Pose(rot_x=28, rot_y=24, rot_z=-6), False, name="rotX28 rotY24")),
        ],
        "carnet": [
            ("wide-f0", d.carnet_panel(0, "wide")), ("wide-f24", d.carnet_panel(24, "wide")),
            ("macro-f52", d.carnet_panel(52, "macro", macro=True)),
            ("strike-f66", d.carnet_panel(66, "strike")), ("strikes-f92", d.carnet_panel(92, "strikes")),
            ("push-blur-f104", d.carnet_panel(104, "push+blur", blur_samples=16)),
            ("sink-f110", d.carnet_panel(110, "sink", blur_samples=16)),
            ("air-f112", d.air(112)), ("air-f127", d.air(127)),
        ],
        "fx": [
            ("lift-0.5", d.lift_panel(0.5)), ("lift-1", d.lift_panel(1.0)),
            ("stack-f483", d.stack_panel(483)), ("stack-f495", d.stack_panel(495)),
            ("whip-v-f259", d.whip_panel(259, None)), ("whip-h-f515", d.hwhip_panel(515)),
            ("touch", d.touch_panel()), ("tagline-f849", d.tagline_panel(849)),
            ("tagline-f860", d.tagline_panel(860)),
        ],
    }
    for name, panels in sheets.items():
        if a.only and name != a.only:
            continue
        path = render_sheet(name, panels, a.out)
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
