"""What every scene shares: its span, its stage, keys read from YAML, and the
record of what it drew on a frame."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

import skia

from ..fx.blur import samples_for
from .keys import Key, Track, curve
from .stage import Stage


#: How a scene is joined to the one before it, when not by a hard cut (the default): a `whip` (6 frames,
#: motion-blurred), or `continuous` — the picture carries on unbroken (the end card's mark keeps easing up
#: from where the reveal left it): a scene handoff, not a join, and verify (b) holds it to no picture change.
TRANSITION_KINDS = ("whip", "continuous")


class SceneError(ValueError):
    """A scene the storyboard describes but the renderer cannot draw as written."""


@dataclass
class Blur:
    """Motion blur for one frame: subframes, shutter (frames), the region that
    moves (None: the whole frame)."""

    samples: int
    shutter: float = 0.5
    region: tuple[int, int, int, int] | None = None
    #: True: each subframe shows the take's own picture at its instant (the
    #: app's frames blended — for a moderate UI move); False: the picture of
    #: the frame itself, only the camera moving (no double images of a fast
    #: UI move the take only has a few pictures of).
    ui: bool = False


@dataclass
class Context:
    clock: Any                       # scenes.clock.Clock
    fmt: Any                         # storyboard.Format
    sources: dict = field(default_factory=dict)   # take name → sources.TakeSource
    fps: int = 30
    #: the format the scenes' camera W values are measured in (storyboard
    #: `reference: true`, 9:16); None: this format is
    reference: Any = None

    @property
    def reference_fmt(self):
        return self.reference if self.reference is not None else self.fmt

    @property
    def size(self) -> tuple[int, int]:
        return self.fmt.width, self.fmt.height

    @property
    def layout(self) -> dict:
        return self.fmt.layout

    def source(self, name: str):
        from .sources import TakeSource
        if name not in self.sources:
            self.sources[name] = TakeSource(name)
        return self.sources[name]


def track(ctx: Context, specs: list | None, where: str, default: float = 0.0) -> Track:
    """A Track from [{at, value, curve, blur, …extra}]."""
    keys = []
    for i, k in enumerate(specs or []):
        p = f"{where}[{i}]"
        if not isinstance(k, dict) or "at" not in k or "value" not in k:
            raise SceneError(f"{p}: a key is {{at, value[, curve, blur]}}")
        try:
            extra = {n: v for n, v in k.items() if n not in ("at", "value", "curve", "blur")}
            keys.append(Key(float(ctx.clock.frame(k["at"])), float(k["value"]), curve(k.get("curve")),
                            k.get("blur"), extra))
        except ValueError as e:
            raise SceneError(f"{p}: {e}") from None
        if len(keys) > 1 and keys[-1].frame <= keys[-2].frame:
            raise SceneError(f"{p}: {k['at']} is f{keys[-1].frame:g}, not after the key before it "
                             f"(f{keys[-2].frame:g}): keys are written in time order")
    try:
        return Track(keys, default)
    except ValueError as e:
        raise SceneError(f"{where}: {e}") from None


def blur_for_track(tr: Track, t: float, px_per_unit: float, region=None, whip_shutter: float = 1.0) -> Blur | None:
    """Motion blur for a keyframed move into a key that asks for it. A whip
    exposes over `whip_shutter` frames (1: a 360° shutter; longer where the
    picture travels less than the camera — 16:9's anchored phone)."""
    k = tr.key_into(t)
    if k is None or not k.blur:
        return None
    if k.blur == "whip":
        h = whip_shutter / 2
        speed = max(tr.speed(t + d * h) for d in (-1.0, -0.5, 0.0, 0.5, 1.0)) * px_per_unit
        return Blur(samples_for(speed, shutter=whip_shutter, max_gap=2.0), whip_shutter, region)
    n = int(k.blur)
    speed = max(tr.speed(t + d) for d in (-0.25, 0.0, 0.25)) * px_per_unit
    return Blur(max(n, samples_for(speed, shutter=0.5, max_gap=2.0, minimum=n)), 0.5, region)


class Scene:
    """A stretch of the film [start, end), drawn by a subclass."""

    kind = "?"

    def __init__(self, spec: dict, ctx: Context, where: str):
        self.spec, self.ctx, self.where = spec, ctx, where
        self.id = spec.get("id") or where
        self.rows = list(spec.get("rows") or [])
        try:
            self.start = ctx.clock.frame(spec["from"])
            self.end = ctx.clock.frame(spec["to"])
        except KeyError as e:
            raise SceneError(f"{where}: needs {e.args[0]}") from None
        if self.end <= self.start:
            raise SceneError(f"{where}: ends (f{self.end}) before it starts (f{self.start})")
        try:
            self.stage = Stage.parse(spec.get("stage"), where)
        except ValueError as e:
            raise SceneError(str(e)) from None
        self.cite = spec.get("cite")
        self.transition = spec.get("transition")
        if self.transition is not None and (not isinstance(self.transition, dict)
                                            or self.transition.get("kind") not in TRANSITION_KINDS):
            raise SceneError(f"{where}.transition: {{kind: {' | '.join(TRANSITION_KINDS)}}} (a hard cut is the "
                             f"default and is not written), not {self.transition!r}")
        self.grain = spec.get("grain")

    @property
    def size(self) -> tuple[int, int]:
        return self.ctx.size

    def seconds(self, t: float) -> float:
        return (t - self.start) / self.ctx.fps

    # ---- what a subclass draws -----------------------------------------------------

    def draw_picture(self, canvas: skia.Canvas, t: float, fast: bool = False, frame: int | None = None) -> None:
        """The layer motion blur accumulates: the stage and the moving picture.
        ``t`` is the (sub)frame instant, ``frame`` the frame being rendered."""
        raise NotImplementedError

    def draw_overlays(self, canvas: skia.Canvas, f: int, rec: dict) -> None:
        """Sharp layers drawn once per frame on top (lifts, counter, credit)."""

    def blur_at(self, f: int) -> Blur | None:
        return None

    def record(self, f: int, rec: dict) -> None:
        """What the frame shows, for verify (pictures, touches, boxes…)."""

    def events(self) -> list[tuple[int, str]]:
        """(frame, what) of every visual event this scene makes (cuts excluded)."""
        return []

    def generated(self) -> list[dict]:
        """Generated elements and their citations (verify's honesty list)."""
        return []
