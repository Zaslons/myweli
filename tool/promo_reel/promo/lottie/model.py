"""Parse and validate a Lottie (Bodymovin) JSON into an immutable model.

The player implements exactly the features the Pro app's opening animation
(mobile/assets/lottie/open/myweli_loader_mixed_pro.json, Bodymovin 5.7.4)
uses, and this parser is where that contract is enforced: every object is
checked against an allow-list of keys and values, and anything else raises
:class:`UnsupportedFeature` naming the JSON path — a replacement file that
needs masks, mattes, a precomp or an expression fails loudly instead of
rendering wrong.

Supported (the file's whole feature set):

* composition: ``fr``, ``ip``/``op``, ``w``/``h``, ``markers``; no assets.
* layers: shape layers (``ty`` 4) only, 2D, unparented, no masks/mattes, no
  time remap or stretch, start time 0, normal blend; visible on [ip, op).
* layer and group transforms: anchor, position, scale, rotation, opacity —
  static or animated (no skew, no split position, no 3D rotation).
* layer contents: groups (``gr``) whose items are, in this order: one or more
  paths (``sh``), an optional trim (``tm``, simultaneous mode), one or more
  fills (``fl``) / strokes (``st``), then the group transform (``tr``).
* paths: static or morphing (equal vertex counts and closed flag across
  keyframes).
* fills: static colour, opacity, non-zero or even-odd rule.
* strokes: static colour, opacity, width, butt/round/square cap,
  miter/round/bevel join, miter limit; no dashes.
* keyframes: ``t``/``s`` with cubic-Bézier easing ``o``/``i`` (one handle
  per property); no hold, no ``e`` end values, no spatial tangents.
"""

from __future__ import annotations

import bisect
import json
import os
import re
from dataclasses import dataclass, field
from typing import Any, Callable, Iterable

import numpy as np

from .bezier import CubicBezier


class LottieError(ValueError):
    """The file is not a Lottie composition this player can read."""


class UnsupportedFeature(LottieError):
    """The file uses a Lottie feature this player deliberately does not implement."""


# Keys that carry names or editor bookkeeping only — never rendering.
_META = frozenset({'nm', 'mn', 'ix', 'cix', 'np'})


def _keys(obj: Any, allowed: Iterable[str], where: str) -> dict:
    if not isinstance(obj, dict):
        raise LottieError(f'{where}: expected an object, got {type(obj).__name__}')
    unknown = set(obj) - set(allowed) - _META
    if unknown:
        raise UnsupportedFeature(
            f'{where}: unsupported key(s) {sorted(unknown)} — this player implements '
            'only the features of myweli_loader_mixed_pro.json (see promo/lottie/model.py)'
        )
    return obj


def _require(obj: dict, key: str, where: str) -> Any:
    if key not in obj:
        raise LottieError(f'{where}: missing required key {key!r}')
    return obj[key]


def _only(obj: dict, key: str, allowed: Iterable[Any], where: str, default: Any = None) -> Any:
    value = obj.get(key, default)
    allowed = tuple(allowed)
    if value not in allowed:
        raise UnsupportedFeature(
            f'{where}.{key} = {value!r} is not supported (allowed: {list(allowed)})'
        )
    return value


def _number(value: Any, where: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise LottieError(f'{where}: expected a number, got {value!r}')
    return float(value)


# --------------------------------------------------------------------------
# Animated properties
# --------------------------------------------------------------------------


@dataclass(frozen=True, eq=False)
class Animated:
    """One property's value over time: a static value, or keyframes.

    Values are float arrays of a fixed shape (``(1,)`` for a scalar, ``(n,)``
    for a vector, ``(3, n, 2)`` for a path's vertices and tangents).
    Evaluation follows lottie-flutter's ``BaseKeyframeAnimation``: before the
    first keyframe the first value, after the last the last; inside segment
    k the value eases from ``s[k]`` to ``s[k+1]`` along keyframe k's curve. A
    zero-length segment is never entered (its end value applies from its time).
    """

    times: tuple[float, ...]
    values: tuple[np.ndarray, ...]
    eases: tuple[CubicBezier, ...] = field(default=())

    @property
    def is_static(self) -> bool:
        return len(self.values) == 1

    def at(self, t: float) -> np.ndarray:
        values = self.values
        if len(values) == 1:
            return values[0]
        times = self.times
        if t <= times[0]:
            return values[0]
        if t >= times[-1]:
            return values[-1]
        k = bisect.bisect_right(times, t) - 1
        span = times[k + 1] - times[k]
        eased = self.eases[k]((t - times[k]) / span)
        return values[k] + (values[k + 1] - values[k]) * eased

    def scalar(self, t: float) -> float:
        return float(self.at(t)[0])


def _handle(obj: Any, where: str) -> tuple[float, float]:
    _keys(obj, {'x', 'y'}, where)

    def one(key: str) -> float:
        value = _require(obj, key, where)
        if isinstance(value, list):
            if len(value) != 1:
                raise UnsupportedFeature(
                    f'{where}.{key}: per-dimension easing ({len(value)} handles) is not supported'
                )
            value = value[0]
        return _number(value, f'{where}.{key}')

    return one('x'), one('y')


def _animated(
    obj: Any,
    where: str,
    convert: Callable[[Any, str], np.ndarray],
    *,
    may_animate: bool = True,
) -> Animated:
    """Parse ``{"a": 0|1, "k": ...}`` with ``convert`` turning one value into an array."""
    if isinstance(obj, dict) and 'x' in obj:
        raise UnsupportedFeature(f'{where}.x: expressions are not supported')
    _keys(obj, {'a', 'k'}, where)
    animated = _only(obj, 'a', (0, 1), where, default=0)
    k = _require(obj, 'k', where)
    if animated == 0:
        return Animated(times=(0.0,), values=(convert(k, f'{where}.k'),))
    if not may_animate:
        raise UnsupportedFeature(f'{where}: an animated value is not supported here')
    if not isinstance(k, list) or len(k) < 2:
        raise LottieError(f'{where}.k: an animated property needs at least two keyframes')
    times: list[float] = []
    values: list[np.ndarray] = []
    eases: list[CubicBezier] = []
    for n, kf in enumerate(k):
        kw = f'{where}.k[{n}]'
        _keys(kf, {'t', 's', 'o', 'i'}, kw)
        t = _number(_require(kf, 't', kw), f'{kw}.t')
        if times and t < times[-1]:
            raise LottieError(f'{kw}.t = {t}: keyframe times must not decrease')
        times.append(t)
        values.append(convert(_require(kf, 's', kw), f'{kw}.s'))
        if values[-1].shape != values[0].shape:
            raise UnsupportedFeature(
                f'{kw}.s: shape {values[-1].shape} differs from the first keyframe '
                f'{values[0].shape} (vertex counts must match to morph)'
            )
        if n < len(k) - 1:  # the last keyframe's handles ease nothing
            x1, y1 = _handle(_require(kf, 'o', kw), f'{kw}.o')
            x2, y2 = _handle(_require(kf, 'i', kw), f'{kw}.i')
            try:
                eases.append(CubicBezier(x1, y1, x2, y2))
            except ValueError as error:
                raise UnsupportedFeature(f'{kw}: {error}') from None
    return Animated(times=tuple(times), values=tuple(values), eases=tuple(eases))


def _scalar(value: Any, where: str) -> np.ndarray:
    if isinstance(value, list):
        if len(value) != 1:
            raise LottieError(f'{where}: expected one number, got {value!r}')
        value = value[0]
    return np.array([_number(value, where)])


def _vector(value: Any, where: str) -> np.ndarray:
    if not isinstance(value, list) or not 2 <= len(value) <= 3:
        raise LottieError(f'{where}: expected [x, y] or [x, y, z], got {value!r}')
    return np.array([_number(v, where) for v in value])


# --------------------------------------------------------------------------
# Model
# --------------------------------------------------------------------------


@dataclass(frozen=True, eq=False)
class Transform:
    """A layer's ``ks`` or a group's ``tr``: M = T(p) · R(r) · S(s / 100) · T(−a)."""

    anchor: Animated
    position: Animated
    scale: Animated
    rotation: Animated
    opacity: Animated


@dataclass(frozen=True, eq=False)
class PathShape:
    """An ``sh`` item: vertices ``v`` with in/out tangents ``i``/``o`` (relative)."""

    name: str
    closed: bool
    geometry: Animated  # (3, n, 2): v, i, o


@dataclass(frozen=True, eq=False)
class Trim:
    """A ``tm`` item (simultaneous mode): start/end in percent, offset in degrees."""

    start: Animated
    end: Animated
    offset: Animated


@dataclass(frozen=True, eq=False)
class Fill:
    rgb: tuple[int, int, int]
    opacity: Animated
    even_odd: bool


@dataclass(frozen=True, eq=False)
class Stroke:
    rgb: tuple[int, int, int]
    opacity: Animated
    width: Animated
    cap: str  # 'butt' | 'round' | 'square'
    join: str  # 'miter' | 'round' | 'bevel'
    miter_limit: float


@dataclass(frozen=True, eq=False)
class Group:
    name: str
    paths: tuple[PathShape, ...]
    trim: Trim | None
    paints: tuple[Fill | Stroke, ...]  # JSON order (the last one is drawn first)
    transform: Transform


@dataclass(frozen=True, eq=False)
class Layer:
    index: int
    name: str
    in_frame: float
    out_frame: float
    transform: Transform
    groups: tuple[Group, ...]  # JSON order (the last one is drawn first)

    def visible_at(self, t: float) -> bool:
        """Lottie's in/out rule: on from ``ip`` inclusive to ``op`` exclusive."""
        return self.in_frame <= t < self.out_frame


@dataclass(frozen=True, eq=False)
class Composition:
    version: str
    name: str
    fps: float
    in_frame: float
    out_frame: float
    width: int
    height: int
    markers: dict[str, tuple[float, float]]
    layers: tuple[Layer, ...]  # JSON order (the first one is on top)


def _transform(obj: Any, where: str, *, layer: bool) -> Transform:
    _keys(obj, {'a', 'p', 's', 'r', 'o'} | ({'ty'} if not layer else set()), where)
    for key in ('a', 'p', 's', 'r', 'o'):
        _require(obj, key, where)
    position = obj['p']
    if isinstance(position, dict) and position.get('s'):
        raise UnsupportedFeature(f'{where}.p: split (separate X/Y) position is not supported')

    def planar(value: Any, w: str) -> np.ndarray:
        v = _vector(value, w)
        if len(v) == 3 and v[2] != 0 and layer:
            raise UnsupportedFeature(f'{w}: a non-zero z (3D) is not supported')
        return v[:2]

    def scale(value: Any, w: str) -> np.ndarray:
        v = _vector(value, w)
        return v[:2]

    return Transform(
        anchor=_animated(obj['a'], f'{where}.a', planar),
        position=_animated(obj['p'], f'{where}.p', planar),
        scale=_animated(obj['s'], f'{where}.s', scale),
        rotation=_animated(obj['r'], f'{where}.r', _scalar),
        opacity=_animated(obj['o'], f'{where}.o', _scalar),
    )


def _shape_value(value: Any, where: str) -> tuple[bool, np.ndarray]:
    # A keyframe's "s" wraps the shape in a one-element list.
    if isinstance(value, list):
        if len(value) != 1:
            raise LottieError(f'{where}: expected one shape, got {len(value)}')
        value = value[0]
    _keys(value, {'c', 'v', 'i', 'o'}, where)
    closed = bool(_require(value, 'c', where))
    arrays = []
    for key in ('v', 'i', 'o'):
        points = _require(value, key, where)
        try:
            array = np.array(points, dtype=float).reshape(-1, 2)
        except (TypeError, ValueError):
            raise LottieError(f'{where}.{key}: expected a list of [x, y] points') from None
        if array.shape[0] != len(points):
            raise LottieError(f'{where}.{key}: expected a list of [x, y] points')
        arrays.append(array)
    if not arrays[0].shape[0]:
        raise LottieError(f'{where}: a path needs at least one vertex')
    if not arrays[0].shape == arrays[1].shape == arrays[2].shape:
        raise LottieError(f'{where}: v, i and o must have the same number of points')
    return closed, np.stack(arrays)


def _path_shape(obj: dict, where: str) -> PathShape:
    _keys(obj, {'ty', 'ks', 'ind', 'hd'}, where)
    _only(obj, 'hd', (False,), where, default=False)
    flags: list[bool] = []

    def convert(value: Any, w: str) -> np.ndarray:
        closed, array = _shape_value(value, w)
        flags.append(closed)
        return array

    geometry = _animated(_require(obj, 'ks', where), f'{where}.ks', convert)
    if len(set(flags)) != 1:
        raise UnsupportedFeature(f'{where}: morphing between open and closed paths is not supported')
    return PathShape(name=str(obj.get('nm', '')), closed=flags[0], geometry=geometry)


def _rgb(obj: Any, where: str) -> tuple[int, int, int]:
    def convert(value: Any, w: str) -> np.ndarray:
        if not isinstance(value, list) or len(value) not in (3, 4):
            raise LottieError(f'{w}: expected [r, g, b] or [r, g, b, a]')
        return np.array([_number(v, w) for v in value])

    colour = _animated(obj, where, convert, may_animate=False).values[0]
    rgb = colour[:3]
    # lottie-flutter's ColorParser: components ≤ 1 are unit floats, scaled by
    # 255 and truncated to a byte. A 4th component is ignored: the paint's
    # alpha is always replaced by the computed opacity.
    if np.all(rgb <= 1.0):
        rgb = rgb * 255.0
    r, g, b = (int(c) for c in rgb)
    for c in (r, g, b):
        if not 0 <= c <= 255:
            raise LottieError(f'{where}: colour component {c} is out of range')
    return r, g, b


_CAPS = {1: 'butt', 2: 'round', 3: 'square'}
_JOINS = {1: 'miter', 2: 'round', 3: 'bevel'}


def _fill(obj: dict, where: str) -> Fill:
    _keys(obj, {'ty', 'c', 'o', 'r', 'hd', 'bm'}, where)
    _only(obj, 'hd', (False,), where, default=False)
    _only(obj, 'bm', (0,), where, default=0)
    rule = _only(obj, 'r', (1, 2), where, default=1)
    return Fill(
        rgb=_rgb(_require(obj, 'c', where), f'{where}.c'),
        opacity=_animated(_require(obj, 'o', where), f'{where}.o', _scalar),
        even_odd=rule == 2,
    )


def _stroke(obj: dict, where: str) -> Stroke:
    _keys(obj, {'ty', 'c', 'o', 'w', 'lc', 'lj', 'ml', 'hd', 'bm'}, where)
    _only(obj, 'hd', (False,), where, default=False)
    _only(obj, 'bm', (0,), where, default=0)
    cap = _only(obj, 'lc', _CAPS, where, default=2)
    join = _only(obj, 'lj', _JOINS, where, default=2)
    return Stroke(
        rgb=_rgb(_require(obj, 'c', where), f'{where}.c'),
        opacity=_animated(_require(obj, 'o', where), f'{where}.o', _scalar),
        width=_animated(_require(obj, 'w', where), f'{where}.w', _scalar),
        cap=_CAPS[cap],
        join=_JOINS[join],
        miter_limit=_number(obj.get('ml', 4.0), f'{where}.ml'),
    )


def _trim(obj: dict, where: str) -> Trim:
    _keys(obj, {'ty', 's', 'e', 'o', 'm', 'hd'}, where)
    _only(obj, 'hd', (False,), where, default=False)
    _only(obj, 'm', (1,), where, default=1)  # 2 = "individually": not used, not implemented
    return Trim(
        start=_animated(_require(obj, 's', where), f'{where}.s', _scalar),
        end=_animated(_require(obj, 'e', where), f'{where}.e', _scalar),
        offset=_animated(_require(obj, 'o', where), f'{where}.o', _scalar),
    )


def _group(obj: dict, where: str) -> Group:
    _keys(obj, {'ty', 'it', 'hd', 'bm'}, where)
    _only(obj, 'hd', (False,), where, default=False)
    _only(obj, 'bm', (0,), where, default=0)
    items = _require(obj, 'it', where)
    if not isinstance(items, list):
        raise LottieError(f'{where}.it: expected a list')
    kinds = ''.join(
        {'sh': 'p', 'tm': 't', 'fl': 'd', 'st': 'd', 'tr': 'x'}.get(
            item.get('ty') if isinstance(item, dict) else None, '?'
        )
        for item in items
    )
    # paths, an optional trim, paints, the transform — the one layout the
    # file uses, so every paint draws every path and the trim trims them all.
    if not re.fullmatch(r'p+t?d+x', kinds):
        found = [item.get('ty') if isinstance(item, dict) else item for item in items]
        raise UnsupportedFeature(
            f'{where}.it: items {found} — supported: one or more "sh", an optional "tm", '
            'one or more "fl"/"st", then "tr" (nested groups, other shapes and modifiers '
            'are not implemented)'
        )
    paths: list[PathShape] = []
    trim: Trim | None = None
    paints: list[Fill | Stroke] = []
    transform: Transform | None = None
    for n, item in enumerate(items):
        w = f'{where}.it[{n}]'
        ty = item['ty']
        if ty == 'sh':
            paths.append(_path_shape(item, w))
        elif ty == 'tm':
            trim = _trim(item, w)
        elif ty == 'fl':
            paints.append(_fill(item, w))
        elif ty == 'st':
            paints.append(_stroke(item, w))
        else:
            transform = _transform(item, w, layer=False)
    assert transform is not None
    return Group(
        name=str(obj.get('nm', '')),
        paths=tuple(paths),
        trim=trim,
        paints=tuple(paints),
        transform=transform,
    )


def _layer(obj: dict, where: str) -> Layer:
    _keys(obj, {'ddd', 'ind', 'ty', 'ks', 'ao', 'shapes', 'ip', 'op', 'st', 'bm', 'sr', 'hd'}, where)
    _only(obj, 'ty', (4,), where)
    _only(obj, 'ddd', (0,), where, default=0)
    _only(obj, 'ao', (0,), where, default=0)
    _only(obj, 'bm', (0,), where, default=0)
    _only(obj, 'sr', (1,), where, default=1)
    _only(obj, 'hd', (False,), where, default=False)
    if _number(obj.get('st', 0), f'{where}.st') != 0:
        raise UnsupportedFeature(f'{where}.st: a layer start time other than 0 is not supported')
    in_frame = _number(_require(obj, 'ip', where), f'{where}.ip')
    out_frame = _number(_require(obj, 'op', where), f'{where}.op')
    shapes = _require(obj, 'shapes', where)
    if not isinstance(shapes, list):
        raise LottieError(f'{where}.shapes: expected a list')
    groups = []
    for n, item in enumerate(shapes):
        w = f'{where}.shapes[{n}]'
        if not isinstance(item, dict) or item.get('ty') != 'gr':
            raise UnsupportedFeature(f'{w}: only groups ("gr") are supported at the layer level')
        groups.append(_group(item, w))
    return Layer(
        index=int(_number(_require(obj, 'ind', where), f'{where}.ind')),
        name=str(obj.get('nm', '')),
        in_frame=in_frame,
        out_frame=out_frame,
        transform=_transform(_require(obj, 'ks', where), f'{where}.ks', layer=True),
        groups=tuple(groups),
    )


def parse(data: Any) -> Composition:
    """Validate a decoded Lottie document and build its model."""
    where = '$'
    _keys(data, {'v', 'fr', 'ip', 'op', 'w', 'h', 'ddd', 'assets', 'markers', 'layers', 'meta'}, where)
    _only(data, 'ddd', (0,), where, default=0)
    if data.get('assets'):
        raise UnsupportedFeature('$.assets: precomps and images are not supported')
    fps = _number(_require(data, 'fr', where), '$.fr')
    in_frame = _number(_require(data, 'ip', where), '$.ip')
    out_frame = _number(_require(data, 'op', where), '$.op')
    if not (fps > 0 and out_frame > in_frame):
        raise LottieError(f'$: invalid timing fr={fps} ip={in_frame} op={out_frame}')
    width = int(_number(_require(data, 'w', where), '$.w'))
    height = int(_number(_require(data, 'h', where), '$.h'))
    if width <= 0 or height <= 0:
        raise LottieError(f'$: invalid size {width}x{height}')
    markers: dict[str, tuple[float, float]] = {}
    for n, marker in enumerate(data.get('markers') or []):
        w = f'$.markers[{n}]'
        _keys(marker, {'tm', 'cm', 'dr'}, w)
        start = _number(_require(marker, 'tm', w), f'{w}.tm')
        markers[str(_require(marker, 'cm', w))] = (
            start,
            start + _number(_require(marker, 'dr', w), f'{w}.dr'),
        )
    layers = _require(data, 'layers', where)
    if not isinstance(layers, list):
        raise LottieError('$.layers: expected a list')
    return Composition(
        version=str(data.get('v', '')),
        name=str(data.get('nm', '')),
        fps=fps,
        in_frame=in_frame,
        out_frame=out_frame,
        width=width,
        height=height,
        markers=markers,
        layers=tuple(_layer(layer, f'$.layers[{n}]') for n, layer in enumerate(layers)),
    )


def load(path: str | os.PathLike) -> Composition:
    """Read and validate a Lottie JSON file."""
    with open(path, encoding='utf-8') as handle:
        try:
            data = json.load(handle)
        except json.JSONDecodeError as error:
            raise LottieError(f'{os.fspath(path)}: not JSON ({error})') from None
    return parse(data)
