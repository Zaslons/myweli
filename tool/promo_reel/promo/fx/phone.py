"""The 2.5D phone: a real screen capture inside a generic black slab, turned
in real perspective, seen whole or through the camera WINDOW.

THE SLAB (storyboard, LAYOUT 9:16): a 16-px black bezel, radius 96, no
notch, no buttons. Its screen is the simulator capture (iPhone 17 Pro,
1206 × 2622 px = 402 × 874 pt at 3 px/pt) cropped from screen point 56 down
— no status bar, no Dynamic Island — drawn 720 px wide (x 180–900), so
1.791 frame px per screen point. The pixels are the capture's own, resampled
once through one projective matrix: nothing is redrawn.

2.5D: the slab is a flat object turned by a `projection.Pose` (rot_x / rot_y
/ rot_z, zoom, move) and projected through a pinhole camera — one 3×3
skia.Matrix, so the screen is perspective-correct per pixel. When turned,
the slab's thickness shows as a side wall: the convex hull of its front and
back outlines (exact for a convex prism), filled a shade off black, with a
one-pixel rim on the front edge so the black slab still reads on the black
stage.

THE WINDOW (« Le trait »'s camera, tool/marketing_video): a camera window
W, in screen points, puts screen point p at frame y = top + (p − W) ×
px_per_pt (and x = screen_x + x_pt × px_per_pt). The phone is drawn into a
layer that is faded to nothing under the caption band (opaque above
top − band_fade, clear from `top`) and under the floor (clear down to
`floor`, gone below floor + floor_fade): the stage — and its pattern —
shows through, uninterrupted. In 9:16 the band edge is y 600 with a 40-px
fade, the floor (the owner's, 2026-10-19) 1424 with a 24-px fade; the
`Window()` default keeps the storyboard's 600–1192 window. In 16:9 the
phone stands on the floor (`anchor_bottom`): the band edge comes down with W
where the screen would end above it.

Overlays (touch discs, privacy blurs drawn late) can be drawn in SCREEN
POINTS through `draw(..., overlay=fn)`: fn(canvas) runs under the same
matrix and the screen's clip, so a touch rides the perspective and is cut by
the screen's corners like the pixels under it.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Callable

import numpy as np
import skia

from . import projection
from .projection import Pose
from .surface import Picture, Rect, draw_exact, sampling_for, skrect, vertical_fade

Overlay = Callable[[skia.Canvas], None]


@dataclass(frozen=True)
class PhoneSpec:
    capture_px_per_pt: float = 3.0           # simulator captures: 1206 × 2622 px = 402 × 874 pt
    screen_pt: tuple[float, float] = (402.0, 874.0)
    crop_top_pt: float = 56.0                # status bar and Dynamic Island cropped away
    px_per_pt: float = 1.791                 # frame px per screen point (720 px / 402 pt)
    bezel: float = 16.0                      # px
    radius: float = 96.0                     # px, outer corner
    depth: float = 14.0                      # px, the slab's thickness (side wall when turned)
    body: int = 0xFF000000                   # AppColors.primary
    side: int = 0xFF1C1C1C                   # the side wall, a shade off black
    rim: int = 0xFF3A3A3A                    # 1-px rim on the front edge
    rim_width: float = 1.0
    # (opacity, blur, dy): the stills' card shadow at 1080 (compose.py), blur
    # as CSS — the Gaussian's sigma is blur / 2. Empty for no shadow.
    shadows: tuple[tuple[float, float, float], ...] = ((0.10, 37.0, 25.0),)

    @property
    def screen_px(self) -> tuple[float, float]:
        """The visible screen (cropped) in frame px at rest."""
        w, h = self.screen_pt
        return w * self.px_per_pt, (h - self.crop_top_pt) * self.px_per_pt

    @property
    def size(self) -> tuple[float, float]:
        """The slab's outer size in frame px at rest."""
        w, h = self.screen_px
        return w + 2 * self.bezel, h + 2 * self.bezel

    @property
    def screen_radius_pt(self) -> float:
        return max(0.0, self.radius - self.bezel) / self.px_per_pt


@dataclass(frozen=True)
class Window:
    """The camera window (frame px; W in screen points).

    `anchor_bottom` (16:9, the owner's « Re-lay it », 2026-10-19): the phone
    stands on the floor — its screen's bottom edge never rises above this y.
    Where camera W would leave the screen's bottom floating above it, the
    band edge comes down instead (`top_for`): the rows above W go under the
    band, the slab's bottom stays on the floor. None: the band edge is fixed
    (`top`), as in 9:16 and 1:1."""

    screen_x: float = 180.0                  # frame x of screen x = 0 pt
    top: float = 600.0                       # the band edge: screen point W sits here
    band_fade: float = 40.0                  # the band is opaque above top − band_fade
    floor: float = 1192.0                    # the floor fade starts here …
    floor_fade: float = 24.0                 # … and is opaque from floor + floor_fade
    px_per_pt: float = 1.791
    anchor_bottom: float | None = None       # the screen's bottom never rises above this y (None: no anchor)
    screen_bottom_pt: float = 874.0          # the screen's last point (402 × 874 pt)
    #: the lowest row where the app's text is READ: the floor, or the platform's text rectangle's bottom where
    #: that is higher (9:16: y 1248 — the owner's floor is app pixels only below it). None: the floor.
    text_floor: float | None = None

    @property
    def read_floor(self) -> float:
        return self.floor if self.text_floor is None else min(self.floor, self.text_floor)

    def top_for(self, W: float) -> float:
        """The band edge under camera W: `top`, or lower when the phone stands
        on the floor and W would lift the screen's bottom above it."""
        if self.anchor_bottom is None:
            return self.top
        return max(self.top, self.anchor_bottom - (self.screen_bottom_pt - W) * self.px_per_pt)

    def at_top(self, top: float) -> "Window":
        """This window with its band edge at `top` (the window a frame shows)."""
        from dataclasses import replace
        return replace(self, top=float(top), anchor_bottom=None)

    def _fixed(self) -> None:
        if self.anchor_bottom is not None:
            raise ValueError("an anchored window's band edge depends on camera W: use at_top(top_for(W)) first")

    def y_of(self, p_pt: float, W: float) -> float:
        """Frame y of screen point p under camera W."""
        self._fixed()
        return self.top + (p_pt - W) * self.px_per_pt

    def x_of(self, x_pt: float) -> float:
        return self.screen_x + x_pt * self.px_per_pt

    def point(self, x_pt: float, y_pt: float, W: float) -> tuple[float, float]:
        return self.x_of(x_pt), self.y_of(y_pt, W)

    def pt_of(self, x: float, y: float, W: float) -> tuple[float, float]:
        """The screen point at frame (x, y) under camera W."""
        self._fixed()
        return (x - self.screen_x) / self.px_per_pt, W + (y - self.top) / self.px_per_pt

    def W_for(self, p_pt: float, y: float) -> float:
        """The camera W that puts screen point p at frame y (e.g. Fatou B.'s
        card bottom on y 1184)."""
        self._fixed()
        return p_pt - (y - self.top) / self.px_per_pt

    @property
    def centre_y(self) -> float:
        return (self.top + self.floor) / 2

    def fade_stops(self) -> list[tuple[float, float]]:
        """(y, alpha) of the phone layer's mask. An anchored window has no
        mask of its own: its band edge is the frame's (`at_top`)."""
        self._fixed()
        return [(self.top - self.band_fade, 0.0), (self.top, 1.0),
                (self.floor, 1.0), (self.floor + self.floor_fade, 0.0)]

    def alpha_at(self, y: float) -> float:
        """How much of the phone shows at frame y (1 inside, 0 under band/floor)."""
        stops = self.fade_stops()
        return float(np.interp(y, [s[0] for s in stops], [s[1] for s in stops]))


WINDOW_9X16 = Window()


def _rrect_outline(rect: Rect, radius: float, per_corner: int = 24) -> np.ndarray:
    """A rounded rectangle's outline as points (clockwise from the top-left)."""
    x0, y0, x1, y1 = rect
    r = min(radius, (x1 - x0) / 2, (y1 - y0) / 2)
    centres = [(x1 - r, y0 + r, -90), (x1 - r, y1 - r, 0), (x0 + r, y1 - r, 90), (x0 + r, y0 + r, 180)]
    pts = []
    for cx, cy, a0 in centres:
        for i in range(per_corner + 1):
            a = math.radians(a0 + 90 * i / per_corner)
            pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return np.array(pts)


def _polygon_path(pts: np.ndarray) -> skia.Path:
    path = skia.Path()
    path.moveTo(*pts[0])
    for p in pts[1:]:
        path.lineTo(*p)
    path.close()
    return path


class Phone:
    """A phone with a screen picture. `set_screen()` swaps the picture (a
    take's next frame) without rebuilding anything else."""

    def __init__(self, screen, spec: PhoneSpec = PhoneSpec()):
        self.spec = spec
        self.set_screen(screen)

    def set_screen(self, screen) -> None:
        """`screen`: a full capture (skia.Image, uint8 RGBA array, PIL image
        or path), 402 × 874 pt at `capture_px_per_pt`."""
        pic = screen if isinstance(screen, Picture) else Picture(screen)
        s = self.spec
        want = (round(s.screen_pt[0] * s.capture_px_per_pt), round(s.screen_pt[1] * s.capture_px_per_pt))
        if (pic.width, pic.height) != want:
            raise ValueError(f"screen capture is {pic.width}×{pic.height}, expected {want[0]}×{want[1]}")
        self.picture = pic

    # ---- geometry -------------------------------------------------------------

    def rest_screen(self, *, W: float | None = None, window: Window = WINDOW_9X16,
                    centre: tuple[float, float] = (540.0, 960.0)) -> Rect:
        """The screen's rectangle in the frame before any pose: under camera W
        through `window`, or (W None) centred on `centre`."""
        sw, sh = self.spec.screen_px
        if W is not None:
            x0 = window.screen_x
            y0 = window.y_of(self.spec.crop_top_pt, W)
        else:
            x0, y0 = centre[0] - sw / 2, centre[1] - sh / 2
        return (x0, y0, x0 + sw, y0 + sh)

    def rest_slab(self, **where) -> Rect:
        x0, y0, x1, y1 = self.rest_screen(**where)
        b = self.spec.bezel
        return (x0 - b, y0 - b, x1 + b, y1 + b)

    def _pose_for(self, pose: Pose, W: float | None, window: Window, slab: Rect) -> Pose:
        """Window mode turns the phone about the WINDOW's centre (what the
        viewer sees), not the slab's (which may be far below the floor)."""
        if pose.pivot is None and W is not None:
            return pose.but(pivot=((slab[0] + slab[2]) / 2, window.centre_y))
        return pose

    def matrix(self, pose: Pose = Pose(), *, W: float | None = None, window: Window = WINDOW_9X16,
               centre: tuple[float, float] = (540.0, 960.0)) -> np.ndarray:
        """3×3 map from SCREEN POINTS (full-screen coordinates, the gesture
        logs' units) to frame px."""
        s = self.spec
        screen = self.rest_screen(W=W, window=window, centre=centre)
        slab = self.rest_slab(W=W, window=window, centre=centre)
        h = projection.homography(self._pose_for(pose, W, window, slab), slab)
        pt_to_rest = projection.affine(s.px_per_pt, s.px_per_pt, screen[0], screen[1] - s.crop_top_pt * s.px_per_pt)
        return h @ pt_to_rest

    def map_point(self, x_pt: float, y_pt: float, pose: Pose = Pose(), **where) -> tuple[float, float]:
        """Frame position of screen point (x_pt, y_pt)."""
        return projection.apply(self.matrix(pose, **where), x_pt, y_pt)

    def map_rect(self, rect_pt: Rect, pose: Pose = Pose(), **where) -> Rect:
        """Frame bounding box of a screen-point rectangle (exact when flat)."""
        h = self.matrix(pose, **where)
        x0, y0, x1, y1 = rect_pt
        pts = projection.apply_many(h, np.array([[x0, y0], [x1, y0], [x1, y1], [x0, y1]]))
        return (float(pts[:, 0].min()), float(pts[:, 1].min()), float(pts[:, 0].max()), float(pts[:, 1].max()))

    # ---- drawing ------------------------------------------------------------

    def draw(self, canvas: skia.Canvas, pose: Pose = Pose(), *, W: float | None = None,
             window: Window = WINDOW_9X16, centre: tuple[float, float] = (540.0, 960.0),
             opacity: float = 1.0, fade: bool = True, overlay: Overlay | None = None,
             sampling: skia.SamplingOptions | None = None, frame_size: tuple[int, int] | None = None,
             screens: list[tuple[Picture, float, float]] | None = None) -> None:
        """Draw the phone. Window mode when W is given (fades under the band
        and the floor unless fade=False); else free, centred on `centre`.

        `screens` (window mode): the screen is filled by these pictures, in
        order — each (picture, its own camera W, alpha) — inside the ONE
        slab drawn at `W`: a declared dissolve between two framings blends
        the screen textures only, never two slabs (review round 5: the 15-s
        9:16 dissolve showed a second, translucent bezel arc across the
        form's rows)."""
        if opacity <= 0:
            return
        s = self.spec
        slab = self.rest_slab(W=W, window=window, centre=centre)
        p = self._pose_for(pose, W, window, slab)
        h_slab = projection.homography(p, slab)
        M = self.matrix(pose, W=W, window=window, centre=centre)
        dev = canvas.getBaseLayerSize()
        fw, fh = frame_size if frame_size else (dev.width(), dev.height())

        windowed = W is not None and fade
        need_layer = windowed or opacity < 1.0
        if need_layer:
            paint = skia.Paint()
            paint.setAlphaf(min(1.0, opacity))
            canvas.saveLayer(None, paint)
        if windowed:
            # nothing under the opaque band or floor can show: do not draw it
            canvas.save()
            canvas.clipRect(skrect((-fw, window.top - window.band_fade, 2 * fw, window.floor + window.floor_fade)))

        outline = _rrect_outline(slab, s.radius)
        front = projection.apply_many(h_slab, outline)
        front_path = _polygon_path(front)

        # shadow: the projected silhouette, offset and blurred, in frame space
        for alpha, blur, dy in s.shadows:
            sp = skia.Paint(AntiAlias=True, Color=s.body)
            sp.setAlphaf(alpha)
            sp.setMaskFilter(skia.MaskFilter.MakeBlur(skia.kNormal_BlurStyle, blur / 2))
            canvas.save()
            canvas.translate(0, dy)
            canvas.drawPath(front_path, sp)
            canvas.restore()

        # side wall: the slab's thickness, seen when it is turned
        if not p.is_flat and s.depth > 0:
            back = projection.project(p, slab, outline, depth=s.depth)
            hull = projection.convex_hull(np.vstack([front, back]))
            canvas.drawPath(_polygon_path(hull), skia.Paint(AntiAlias=True, Color=s.side))

        # front face: the bezel, its rim, the screen
        canvas.save()
        canvas.concat(projection.to_skia(h_slab))
        rr = skia.RRect.MakeRectXY(skrect(slab), s.radius, s.radius)
        canvas.drawRRect(rr, skia.Paint(AntiAlias=True, Color=s.body))
        if s.rim_width > 0:
            inset = s.rim_width / 2
            rim = skia.RRect.MakeRectXY(skrect((slab[0] + inset, slab[1] + inset, slab[2] - inset, slab[3] - inset)),
                                        s.radius - inset, s.radius - inset)
            canvas.drawRRect(rim, skia.Paint(AntiAlias=True, Color=s.rim, Style=skia.Paint.kStroke_Style,
                                             StrokeWidth=s.rim_width))
        canvas.restore()

        canvas.save()
        base = canvas.getTotalMatrix()
        Msk = projection.to_skia(M)
        canvas.concat(Msk)
        w_pt, h_pt = s.screen_pt
        screen_pt = (0.0, s.crop_top_pt, w_pt, h_pt)
        r_pt = s.screen_radius_pt
        canvas.clipRRect(skia.RRect.MakeRectXY(skrect(screen_pt), r_pt, r_pt), skia.ClipOp.kIntersect, True)
        k = s.capture_px_per_pt
        src = (0.0, s.crop_top_pt * k, w_pt * k, h_pt * k)
        layers = [(self.picture, None, 1.0)] if not screens else screens
        for pic, W_pic, alpha in layers:
            if alpha <= 0:
                continue
            pic = pic if isinstance(pic, Picture) else Picture(pic)
            # a picture framed by its own camera W: moved by its offset inside the slab's screen (window mode)
            M_pic = M if W_pic is None or W is None else self.matrix(pose, W=W_pic, window=window, centre=centre)
            group = alpha < 1.0
            if group:
                gp = skia.Paint()
                gp.setAlphaf(alpha)
                canvas.saveLayer(None, gp)
            if sampling is None and p.is_flat and p.rot_z == 0:
                # a plain scale + move: Lanczos from a fractional box (surface.draw_exact)
                canvas.setMatrix(base)                 # keep the clip, drop the matrix
                x0, y0 = projection.apply(M_pic, 0.0, s.crop_top_pt)
                x1, y1 = projection.apply(M_pic, w_pt, h_pt)
                draw_exact(canvas, pic, src, (x0, y0, x1, y1))
                canvas.concat(Msk)
            else:
                canvas.setMatrix(base)
                canvas.concat(projection.to_skia(M_pic))
                smp = sampling if sampling is not None else sampling_for(s.px_per_pt / k * p.scale)
                canvas.drawImageRect(pic.image, skrect(src), skrect(screen_pt), smp, None,
                                     skia.Canvas.kFast_SrcRectConstraint)
                canvas.setMatrix(base)
                canvas.concat(Msk)
            if group:
                canvas.restore()
        if overlay is not None:
            overlay(canvas)
        canvas.restore()

        if windowed:
            canvas.restore()
            vertical_fade(canvas, (-fw, 0, 2 * fw, fh), window.fade_stops())
        if need_layer:
            canvas.restore()
