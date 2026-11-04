"""A small, exact Skia player for the Pro app's opening Lottie.

It draws what the app draws — lottie-flutter 3.5.1 (mobile/pubspec.lock), the
package behind ``Lottie.asset`` in pro_splash_screen.dart:212-219 — at any
continuous composition time, so the film can retime the animation and blur
it over sub-frames. Every rule below is lottie-flutter's, cited by file under
``lib/src/`` of that package:

* layers draw bottom-up (the JSON's last layer first) and are visible on
  [ip, op) (``parser/layer_parser.dart`` in/out keyframes);
* inside a group the last paint draws first; a fill or stroke paints every
  path listed before it; a simultaneous trim cuts each path on its own
  (``animation/content/content_group.dart``, ``shape_content.dart``);
* paths are built point to point — a line when both handles sit on their
  vertices, a cubic otherwise, then ``close`` (``utils/misc.dart``);
* the trim keeps the first contour only, treats « start/end within 1 % of
  the full length » as the untrimmed (closed) path, and returns nothing when
  start equals end (``utils/utils.dart`` ``applyTrimPathIfNeeded``);
* opacity multiplies layer × group × paint; a stroke of width ≤ 0 is not
  drawn (``base_stroke_content.dart``); colours are bytes (``ColorParser``).

Two deliberate differences, both sub-visible: opacity stays continuous
(lottie-flutter rounds opacity to whole percent), and keyframe easing solves
the Bézier exactly (lottie-flutter samples it into a table, ≤ 3e-6 off).
Flutter's own recording rule is mirrored too: a path that is a rectangle,
round rectangle, oval or single line is drawn as that primitive
(:func:`_draw_path`).
"""

from __future__ import annotations

import math
import os
from pathlib import Path
from typing import Iterator, Sequence, Union

import skia

from . import model
from .model import Fill, Group, PathShape, Stroke, Transform, Trim

ColorLike = Union[int, str, skia.Color4f, None]
RectLike = Union[skia.Rect, Sequence[float]]

_CAP = {'butt': skia.Paint.kButt_Cap, 'round': skia.Paint.kRound_Cap, 'square': skia.Paint.kSquare_Cap}
_JOIN = {
    'miter': skia.Paint.kMiter_Join,
    'round': skia.Paint.kRound_Join,
    'bevel': skia.Paint.kBevel_Join,
}

# lottie-flutter's LottieComposition.roundProgress adds this many frames to
# the duration so the controller's end (1.0) lands just inside the out point.
_FLUTTER_END_OFFSET = 0.01


def device_frame(controller_value: float, fps: float, in_frame: float, out_frame: float) -> float:
    """The composition time lottie-flutter draws for an ``AnimationController`` value.

    The app's ``Lottie`` uses ``FrameRate.composition``: progress is floored
    to whole frames of the file's own rate (25 fps), over a duration padded
    by 0.01 frame (``composition.dart`` ``roundProgress``). The end of a pass
    (1.0) therefore draws 141.990, not 142 — still inside the ``redraw``
    layer's [72, 142) — which is why the app rests on the finished mark.
    """
    duration = out_frame - in_frame
    total_frames = (duration + _FLUTTER_END_OFFSET) / fps * fps
    frame_index = int(total_frames * controller_value)
    return in_frame + frame_index / total_frames * duration


def _rect(value: RectLike) -> skia.Rect:
    if isinstance(value, skia.Rect):
        return value
    left, top, right, bottom = (float(v) for v in value)
    return skia.Rect.MakeLTRB(left, top, right, bottom)


def _color4f(color: ColorLike) -> skia.Color4f | None:
    """``None`` keeps the file's colours; else an ARGB int, ``'#RRGGBB'`` or a Color4f."""
    if color is None:
        return None
    if isinstance(color, skia.Color4f):
        return color
    if isinstance(color, str):
        text = color.lstrip('#')
        if len(text) != 6 or any(c not in '0123456789abcdefABCDEF' for c in text):
            raise ValueError(f"colour {color!r}: expected '#RRGGBB'")
        return skia.Color4f(int(text, 16) | 0xFF000000)
    if isinstance(color, int) and not isinstance(color, bool) and 0 <= color <= 0xFFFFFFFF:
        return skia.Color4f(color)
    raise ValueError(f'colour {color!r}: expected None, an ARGB int, "#RRGGBB" or a skia.Color4f')


def _matrix(transform: Transform, t: float) -> skia.Matrix:
    """T(p) · R(r) · S(s / 100) · T(−a) (``transform_keyframe_animation.dart``)."""
    p = transform.position.at(t)
    a = transform.anchor.at(t)
    s = transform.scale.at(t)
    r = transform.rotation.scalar(t)
    m = skia.Matrix()
    m.preTranslate(float(p[0]), float(p[1]))
    if r:
        m.preRotate(r)
    m.preScale(float(s[0]) / 100.0, float(s[1]) / 100.0)
    m.preTranslate(-float(a[0]), -float(a[1]))
    return m


def _build_path(geometry, closed: bool) -> skia.Path:
    """``MiscUtils.getPathFromData``: lines where handles are zero, cubics elsewhere."""
    vertices, in_tangents, out_tangents = geometry
    count = len(vertices)
    path = skia.Path()
    path.moveTo(float(vertices[0][0]), float(vertices[0][1]))

    def segment(previous: int, current: int) -> None:
        start = vertices[previous]
        end = vertices[current]
        cp1 = start + out_tangents[previous]
        cp2 = end + in_tangents[current]
        if (cp1 == start).all() and (cp2 == end).all():
            path.lineTo(float(end[0]), float(end[1]))
        else:
            path.cubicTo(
                float(cp1[0]), float(cp1[1]), float(cp2[0]), float(cp2[1]), float(end[0]), float(end[1])
            )

    for k in range(1, count):
        segment(k - 1, k)
    if closed:
        segment(count - 1, 0)
        path.close()
    return path


def _draw_path(canvas: skia.Canvas, path: skia.Path, paint: skia.Paint) -> None:
    """``drawPath`` as Flutter records it: simple paths become their primitive.

    Flutter's ``DisplayListBuilder::DrawPath`` (engine/src/flutter/display_list/
    dl_builder.cc:1295-1325) draws a path that is a rectangle as ``DrawRect``
    (for a stroke only when closed), then tries a round rectangle, an oval and
    a single line. Skia rasterises those with exact edge coverage, a general
    path with 4× vertical supersampling — the « l » of the wordmark, a bare
    rectangle, is up to 25 levels off at its top and bottom edges without this.
    """
    stroke = paint.getStyle() == skia.Paint.kStroke_Style
    rect = skia.Rect()
    if path.isRect(rect) and (not stroke or path.isLastContourClosed()):
        canvas.drawRect(rect, paint)
        return
    rrect = skia.RRect()
    if path.isRRect(rrect):
        canvas.drawRRect(rrect, paint)
        return
    oval = skia.Rect()
    if path.isOval(oval):
        canvas.drawOval(oval, paint)
        return
    start, end = skia.Point(0, 0), skia.Point(0, 0)
    if path.isLine(start, end):
        canvas.drawLine(start, end, paint)
        return
    canvas.drawPath(path, paint)


def _floor_mod(x: float, y: float) -> int:
    # MiscUtils.floorMod truncates both operands to integers first; mirrored.
    xi, yi = int(x), int(y)
    return xi - yi * (xi // yi)


def trim_path(path: skia.Path, start: float, end: float, offset: float) -> skia.Path:
    """``Utils.applyTrimPathIfNeeded`` (start/end as 0–1 fractions, offset in turns)."""
    measure = skia.PathMeasure(path, False)
    length = measure.getLength()  # the first contour only, as lottie-flutter
    if start == 1.0 and end == 0.0:
        return path
    if length < 1.0 or abs(end - start - 1.0) < 0.01:
        return path
    new_start = min(length * start, length * end) + offset * length
    new_end = max(length * start, length * end) + offset * length
    if new_start >= length and new_end >= length:
        new_start = _floor_mod(new_start, length)
        new_end = _floor_mod(new_end, length)
    if new_start < 0:
        new_start = _floor_mod(new_start, length)
    if new_end < 0:
        new_end = _floor_mod(new_end, length)
    if new_start == new_end:
        return skia.Path()
    if new_start >= new_end:
        new_start -= length
    trimmed = skia.Path()
    measure.getSegment(new_start, new_end, trimmed, True)
    if new_end > length:
        extra = skia.Path()
        measure.getSegment(0, math.fmod(new_end, length), extra, True)
        trimmed.addPath(extra)
    elif new_start < 0:
        extra = skia.Path()
        measure.getSegment(length + new_start, length, extra, True)
        trimmed.addPath(extra)
    return trimmed


class Player:
    """Plays one Lottie composition onto a ``skia.Canvas``.

    ``Player(path)`` validates the file (unsupported features raise
    :class:`~promo.lottie.model.UnsupportedFeature`). Then:

    * ``frames`` — ``(ip, op)`` in composition frames (``(0.0, 142.0)``);
    * ``fps`` — the file's frame rate (25.0);
    * ``size`` — the composition's ``(width, height)`` (``(560, 380)``);
    * ``markers`` — ``{name: (start, end)}`` in composition frames;
    * ``render(canvas, comp_frame, dst_rect, color=None)`` draws one instant.
    """

    def __init__(self, path: str | os.PathLike) -> None:
        self.path = Path(path)
        self.composition = model.load(self.path)
        c = self.composition
        self.fps: float = c.fps
        self.frames: tuple[float, float] = (c.in_frame, c.out_frame)
        self.size: tuple[int, int] = (c.width, c.height)
        self.markers: dict[str, tuple[float, float]] = dict(c.markers)
        self._static_paths: dict[PathShape, skia.Path] = {}  # model objects hash by identity

    # ------------------------------------------------------------------ time

    @property
    def last_frame(self) -> float:
        """The last instant drawn: where the app's controller at 1.0 lands (141.990)."""
        return self.device_frame(1.0)

    def device_frame(self, controller_value: float) -> float:
        """The composition time the app draws for an ``AnimationController`` value."""
        return device_frame(controller_value, self.fps, *self.frames)

    def _time(self, comp_frame: float) -> float:
        t = float(comp_frame)
        if not math.isfinite(t):
            raise ValueError(f'comp_frame must be finite, got {comp_frame!r}')
        # The out point is exclusive in Lottie: a layer whose op is the
        # composition's would vanish at op itself. op is therefore drawn as
        # the app draws its end — the finished mark — and anything past it
        # holds there; anything before ip holds ip.
        return min(max(t, self.frames[0]), self.last_frame)

    # ---------------------------------------------------------------- layout

    def dst_rect(self, center: Sequence[float], width: float) -> skia.Rect:
        """The rectangle of the composition frame ``width`` px wide, centred on ``center``."""
        w, h = self.size
        height = width * h / w
        cx, cy = float(center[0]), float(center[1])
        return skia.Rect.MakeXYWH(cx - width / 2.0, cy - height / 2.0, width, height)

    def _fit(self, dst_rect: RectLike) -> tuple[float, float, float]:
        """Uniform scale and offset placing the composition in ``dst_rect`` (contain, centred)."""
        rect = _rect(dst_rect)
        if rect.isEmpty() or not rect.isFinite():
            raise ValueError(f'dst_rect must be a finite, non-empty rectangle, got {rect}')
        w, h = self.size
        scale = min(rect.width() / w, rect.height() / h)
        dx = rect.left() + (rect.width() - w * scale) / 2.0
        dy = rect.top() + (rect.height() - h * scale) / 2.0
        return scale, dx, dy

    # --------------------------------------------------------------- drawing

    def render(
        self,
        canvas: skia.Canvas,
        comp_frame: float,
        dst_rect: RectLike,
        color: ColorLike = None,
    ) -> None:
        """Draw the composition at ``comp_frame`` (any real number) into ``dst_rect``.

        The composition frame (``size``) is fitted into ``dst_rect`` uniformly
        and centred, and clipped to it, as lottie-flutter clips to the
        composition. ``color`` replaces every fill and stroke colour (its
        alpha multiplies the animation's opacity); ``None`` keeps the file's
        ``#111111``. Everything is anti-aliased.
        """
        t = self._time(comp_frame)
        scale, dx, dy = self._fit(dst_rect)
        override = _color4f(color)
        w, h = self.size
        canvas.save()
        try:
            canvas.translate(dx, dy)
            canvas.scale(scale, scale)
            # composition_layer.dart clips to the composition (dart:ui's
            # clipRect is anti-aliased by default).
            canvas.clipRect(skia.Rect.MakeWH(w, h), True)
            for matrix, path, paint in self._draw_ops(t, override):
                canvas.save()
                canvas.concat(matrix)
                _draw_path(canvas, path, paint)
                canvas.restore()
        finally:
            canvas.restore()

    def ink_bounds(self, comp_frame: float) -> skia.Rect | None:
        """The tight bounds of everything drawn at ``comp_frame``, in composition units.

        Strokes count with their real outline (caps and joins). ``None`` when
        nothing is drawn (comp frame 0 is blank by design).
        """
        t = self._time(comp_frame)
        bounds: skia.Rect | None = None
        for matrix, path, paint in self._draw_ops(t, None):
            if paint.getStyle() == skia.Paint.kStroke_Style:
                outline = skia.Path()
                paint.getFillPath(path, outline)
            else:
                outline = path
            outline = skia.Path(outline)
            outline.transform(matrix)
            if outline.isEmpty():
                continue
            box = outline.computeTightBounds()
            if bounds is None:
                bounds = box
            else:
                bounds.join(box)
        return bounds

    def _draw_ops(
        self, t: float, override: skia.Color4f | None
    ) -> Iterator[tuple[skia.Matrix, skia.Path, skia.Paint]]:
        """Every (matrix, path, paint) drawn at ``t``, in drawing order."""
        for layer in reversed(self.composition.layers):
            if not layer.visible_at(t):
                continue
            alpha = layer.transform.opacity.scalar(t) / 100.0
            if alpha <= 0.0:
                continue
            layer_matrix = _matrix(layer.transform, t)
            for group in reversed(layer.groups):
                yield from self._group_ops(group, t, layer_matrix, alpha, override)

    def _group_ops(
        self,
        group: Group,
        t: float,
        parent: skia.Matrix,
        parent_alpha: float,
        override: skia.Color4f | None,
    ) -> Iterator[tuple[skia.Matrix, skia.Path, skia.Paint]]:
        alpha = parent_alpha * group.transform.opacity.scalar(t) / 100.0
        if alpha <= 0.0:
            return
        matrix = skia.Matrix.Concat(parent, _matrix(group.transform, t))
        paths = [self._path(shape, t) for shape in group.paths]
        if group.trim is not None:
            paths = [self._trimmed(path, group.trim, t) for path in paths]
        for paint_model in reversed(group.paints):
            paint = self._paint(paint_model, t, alpha, override)
            if paint is None:
                continue
            combined = skia.Path()
            if isinstance(paint_model, Fill):
                combined.setFillType(
                    skia.PathFillType.kEvenOdd if paint_model.even_odd else skia.PathFillType.kWinding
                )
            for path in paths:
                combined.addPath(path)
            if combined.isEmpty():
                continue
            yield matrix, combined, paint

    def _path(self, shape: PathShape, t: float) -> skia.Path:
        if shape.geometry.is_static:
            cached = self._static_paths.get(shape)
            if cached is None:
                cached = _build_path(shape.geometry.values[0], shape.closed)
                self._static_paths[shape] = cached
            return cached
        return _build_path(shape.geometry.at(t), shape.closed)

    @staticmethod
    def _trimmed(path: skia.Path, trim: Trim, t: float) -> skia.Path:
        return trim_path(
            path,
            trim.start.scalar(t) / 100.0,
            trim.end.scalar(t) / 100.0,
            trim.offset.scalar(t) / 360.0,
        )

    @staticmethod
    def _paint(
        paint_model: Fill | Stroke, t: float, alpha: float, override: skia.Color4f | None
    ) -> skia.Paint | None:
        alpha *= paint_model.opacity.scalar(t) / 100.0
        if override is not None:
            red, green, blue = override.fR, override.fG, override.fB
            alpha *= override.fA
        else:
            red, green, blue = (c / 255.0 for c in paint_model.rgb)
        alpha = min(max(alpha, 0.0), 1.0)
        if alpha <= 0.0:
            return None
        paint = skia.Paint()
        paint.setAntiAlias(True)
        paint.setColor4f(skia.Color4f(red, green, blue, alpha))
        if isinstance(paint_model, Stroke):
            width = paint_model.width.scalar(t)
            if width <= 0.0:  # Android draws a hairline; After Effects and lottie-flutter don't
                return None
            paint.setStyle(skia.Paint.kStroke_Style)
            paint.setStrokeWidth(width)
            paint.setStrokeCap(_CAP[paint_model.cap])
            paint.setStrokeJoin(_JOIN[paint_model.join])
            paint.setStrokeMiter(paint_model.miter_limit)
        return paint
