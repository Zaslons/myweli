"""A take as the film uses it: masks on, touch-downs measured, film time mapped
to take time, pictures held for resampling.

TAKE TIMES in the storyboard are honest about what they are:

  10.000                 an instant of the take as written (inside a held picture)
  {named: 23.620}        the picture whose time is written 23.620 to the
                         millisecond (it is at 23.62000 s; « 131.448 » is the
                         picture at 131.44833 — takes.index_named)
  {touch: tap-arrive}    the touch-down promo.media.touches measures
                         (first changed picture − 200 ms: 21.81833 s)
  {first_change: g}      that gesture's first changed picture
  {key: type-nom[1]}     a typed key's first picture

THE TIMELINE maps film frames (floats: subframes are fractional) to take
seconds, segment by segment (storyboard.yaml, « TIMELINE »). A derived rate
(``until`` + ``src_until``) is checked: a server wait never plays faster than
1×; only a drag's own segment may run faster (the storyboard's gesture-speed
ramps: 1.11×, 2.74×, 1.08×), and never past 3×.

A DISSOLVE (``{at, dissolve: take time, until, curve, cite}``) blends the
picture on screen at ``at`` into the take's picture at ``dissolve`` by
``until`` — the only way a timeline skips footage in which the screen
changes (the App Store film's rule, tool/app_store_preview/README.md « One
declared dissolve inside a scene »: the 15-s cut's 32.998 → 130.262 skips
the form fill). It is declared (``cite``) and goes forward in the take;
the scene draws each picture through its own camera (the phone's
``draw_picture``) and refuses a touch disc on its frames. ``curve: cut``
makes it a DECLARED HARD CUT — the picture it reaches from its first frame,
the same skip, the same declaration (the owner's round 5, 2026-10-20: the
15-s 16:9 form, whose two pictures stand on the floor each in its own
window, cuts — a blend of two windows ghosts; on f192, the bar-4 downbeat,
since round 8: verify (b) holds every cut to the 16th grid).

Masks are attached to the take before any picture is read, so every picture
a scene, a lift or a motion-blur subframe gets is already blurred.
"""

from __future__ import annotations

import collections
import math
from dataclasses import dataclass, field
from typing import Any

import numpy as np

from ..fx.surface import Picture
from ..media import touches as touches_mod
from ..media.masks import Blur, ScrollTrack
from ..media.takes import Take, TakeError

#: The fastest a gesture ramp may play (the storyboard's largest is 2.74×).
MAX_GESTURE_RATE = 3.0
#: A derived rate this close to 1 counts as 1× (float error on frame times).
RATE_EPSILON = 1e-6


class SourceError(ValueError):
    pass


class TakeSource:
    """One take, its masks and touch-downs, and a cache of resampling Pictures."""

    def __init__(self, name: str, cache_pictures: int = 12):
        try:
            self.take = Take(name)
        except TakeError as e:
            raise SourceError(f"take {name!r}: {e}") from None
        self.name = name
        self._blurs: dict[str, Blur] = {}
        self._pictures: collections.OrderedDict[int, Picture] = collections.OrderedDict()
        self._cache_n = cache_pictures
        self._downs: dict[str, touches_mod.TouchDown] | None = None
        self._tracks: dict[str, ScrollTrack] = {}

    # ---- masks ------------------------------------------------------------------

    def add_masks(self, specs: list[dict], where: str) -> None:
        """Masks from the storyboard; the same label twice must be the same blur."""
        changed = False
        for i, m in enumerate(specs or []):
            p = f"{where}.masks[{i}]"
            try:
                track = self.scroll_track(m["track"]) if m.get("track") else None
                blur = Blur(m["label"], tuple(float(v) for v in m["rect_pt"]), sigma_px=float(m.get("sigma_px", 14)),
                            margin_pt=float(m.get("margin_pt", 0)), from_s=m.get("from_s"), to_s=m.get("to_s"),
                            clip_y_pt=tuple(m["clip_y_pt"]) if m.get("clip_y_pt") else None, track=track)
            except (KeyError, TypeError, ValueError) as e:
                raise SourceError(f"{p}: {e}") from None
            old = self._blurs.get(blur.label)
            if old is not None:
                if old != blur:
                    raise SourceError(f"{p}: mask {blur.label!r} on {self.name} is declared twice, differently")
                continue
            self._blurs[blur.label] = blur
            changed = True
        if changed:
            self.take.set_masks(list(self._blurs.values()))
            self._pictures.clear()

    @property
    def blurs(self) -> list[Blur]:
        return list(self._blurs.values())

    def scroll_track(self, csv_name: str) -> ScrollTrack:
        if csv_name not in self._tracks:
            path = self.take.files.folder / csv_name
            self._tracks[csv_name] = ScrollTrack.from_csv(path, self.take)
        return self._tracks[csv_name]

    # ---- touch-downs and take times ----------------------------------------------------

    @property
    def downs(self) -> dict[str, touches_mod.TouchDown]:
        if self._downs is None:
            self._downs = {d.gesture: d for d in touches_mod.touch_downs(self.take)}
        return self._downs

    def down(self, gesture: str) -> touches_mod.TouchDown:
        try:
            return self.downs[gesture]
        except KeyError:
            raise SourceError(f"{self.name}: no gesture {gesture!r} (have: {', '.join(self.downs)})") from None

    def resolve(self, value: Any, where: str) -> float:
        """Seconds of the take for a take time written in the storyboard."""
        if isinstance(value, bool):
            raise SourceError(f"{where}: {value!r} is not a take time")
        if isinstance(value, (int, float)):
            return float(value)
        if isinstance(value, dict) and len(value) == 1:
            (kind, arg), = value.items()
            try:
                if kind == "named":
                    return self.take.time_named(float(arg))
                if kind == "touch":
                    return self.down(arg).down_s
                if kind == "first_change":
                    return self.down(arg).first_change_s
                if kind == "key":
                    d = self.down(arg)
                    if d.kind != "key":
                        raise SourceError(f"{where}: {arg!r} is a {d.kind}, not a typed key")
                    return d.down_s
            except TakeError as e:
                raise SourceError(f"{where}: {e}") from None
        raise SourceError(f"{where}: {value!r} is not a take time (a number, or one of named / touch / "
                          f"first_change / key)")

    # ---- pixels -----------------------------------------------------------------------

    def picture(self, index: int) -> Picture:
        """Picture ``index`` (masked) held for resampling (fx.surface.Picture)."""
        pic = self._pictures.get(index)
        if pic is not None:
            self._pictures.move_to_end(index)
            return pic
        pic = Picture(self.take.picture(index))
        self._pictures[index] = pic
        while len(self._pictures) > self._cache_n:
            self._pictures.popitem(last=False)
        return pic

    def rgba(self, index: int) -> np.ndarray:
        return self.take.picture(index)


@dataclass
class Segment:
    start: float                 # film frame the segment starts on
    kind: str                    # hold | run | scroll
    src0: float                  # take seconds at `start`
    rate: float = 0.0            # take seconds per film second (run)
    cap: float | None = None     # src_until: the take time the run stops at
    end: float | None = None     # film frame the cap is reached on
    blur: int | None = None
    derived: bool = False        # the rate comes from until/src_until
    gesture: str | None = None   # the segment starts on this gesture's touch-down
    scroll: tuple | None = None  # (indices, scroll values, scroll start, scroll end)
    where: str = ""
    to: float | None = None      # dissolve: the take time of the picture it blends into
    curve: Any = None            # dissolve: the blend's curve (the app's, promo/fx/easing.py)
    cite: str | None = None      # dissolve: where it is declared
    cut: bool = False            # dissolve: `curve: cut` — a declared hard cut (the picture it reaches at once)


class Timeline:
    """Film frame → take seconds (and picture), from the storyboard's segments."""

    def __init__(self, source: TakeSource, specs: list[dict], clock, fps: int, where: str):
        self.source, self.fps = source, fps
        self.segments: list[Segment] = []
        take = source.take
        for i, s in enumerate(specs):
            p = f"{where}.timeline[{i}]"
            if s.get("at") == "chain":
                if not self.segments or self.segments[-1].end is None:
                    raise SourceError(f"{p}: `at: chain` needs a previous segment that reaches its src_until")
                start = self.segments[-1].end
            else:
                start = float(clock.frame(s["at"]))
            if "hold" in s:
                self.segments.append(Segment(start, "hold", source.resolve(s["hold"], f"{p}.hold"), where=p))
                continue
            if "dissolve" in s:
                self.segments.append(self._dissolve(s, start, clock, p))
                continue
            if "src" not in s:
                raise SourceError(f"{p}: a segment holds (`hold`) or runs (`src`)")
            src0 = source.resolve(s["src"], f"{p}.src")
            gesture = None
            if isinstance(s["src"], dict) and "touch" in s["src"]:
                gesture = s["src"]["touch"]
            cap = source.resolve(s["src_until"], f"{p}.src_until") if "src_until" in s else None
            derived = False
            if "until" in s:
                if cap is None:
                    raise SourceError(f"{p}: `until` needs `src_until`")
                until = float(clock.frame(s["until"]))
                if until <= start:
                    raise SourceError(f"{p}: ends (f{until:g}) before it starts (f{start:g})")
                rate = (cap - src0) / ((until - start) / fps)
                derived = True
            else:
                rate = float(s.get("rate", 1.0))
            if rate <= 0:
                raise SourceError(f"{p}: rate {rate:.3f} — a take is only ever played forward")
            is_drag = gesture is not None and source.down(gesture).kind == "drag"
            limit = MAX_GESTURE_RATE if is_drag else 1.0
            if s.get("pick") != "scroll" and rate > limit + RATE_EPSILON:
                raise SourceError(f"{p}: plays {rate:.3f}× — faster than {limit:g}× "
                                  + ("(the gesture ramps stop at 3×)" if is_drag else
                                     "(a wait is never sped up; only a drag's own segment may be)"))
            end = None if cap is None else start + (cap - src0) / rate * fps
            seg = Segment(start, "run", src0, rate, cap, end, s.get("blur"), derived, gesture, where=p)
            if s.get("pick") == "scroll":
                track = source.scroll_track(s["track"])
                i0, i1 = take.index_at(src0), take.index_at(cap)
                idx = list(range(i0, i1 + 1))
                vals = [track.at_ticks(take.pts[j]) for j in idx]
                if any(b < a - 1e-6 for a, b in zip(vals, vals[1:])):
                    raise SourceError(f"{p}: the scroll goes back; pictures cannot be picked by position")
                seg.kind = "scroll"
                seg.scroll = (idx, vals, vals[0], vals[-1])
            self.segments.append(seg)
        if not self.segments:
            raise SourceError(f"{where}.timeline: empty")
        for a, b in zip(self.segments, self.segments[1:]):
            if b.start < a.start:
                raise SourceError(f"{b.where}: starts before the segment above it")

    def _dissolve(self, s: dict, start: float, clock, p: str) -> Segment:
        from .keys import curve
        if not self.segments:
            raise SourceError(f"{p}: a dissolve blends the picture on screen into a later one: it needs a "
                              f"segment before it")
        if "until" not in s:
            raise SourceError(f"{p}: a dissolve needs `until` (the film frame it is whole on)")
        until = float(clock.frame(s["until"]))
        if until <= start:
            raise SourceError(f"{p}: ends (f{until:g}) before it starts (f{start:g})")
        if not s.get("cite"):
            raise SourceError(f"{p}: a dissolve skips footage in which the screen changes: it is declared — `cite` "
                              f"where (the App Store film's rule, tool/app_store_preview/README.md E_DISSOLVE)")
        frm = self.src(start)
        to = self.source.resolve(s["dissolve"], f"{p}.dissolve")
        take = self.source.take
        if take.index_at(to) <= take.index_at(frm):
            raise SourceError(f"{p}: dissolves from the picture at {frm:.3f} s (#{take.index_at(frm)}) to the one at "
                              f"{to:.3f} s (#{take.index_at(to)}): never back in the take, nor to the same picture "
                              f"(E_ORDER)")
        if s.get("curve") == "cut":
            return Segment(start, "dissolve", frm, end=until, to=to, curve=lambda u: 1.0, cite=s.get("cite"),
                           where=p, cut=True)
        try:
            cv = curve(s.get("curve", "ease_in_out"))
        except ValueError as e:
            raise SourceError(f"{p}.curve: {e} — or `cut` (a declared hard cut)") from None
        return Segment(start, "dissolve", frm, end=until, to=to, curve=cv, cite=s.get("cite"), where=p)

    def segment(self, t: float) -> Segment:
        seg = self.segments[0]
        for s in self.segments:
            if s.start <= t + 1e-9:
                seg = s
            else:
                break
        return seg

    def dissolve_at(self, t: float) -> tuple[Segment, int, int, float] | None:
        """(segment, picture from, picture to, blend 0..1) while a dissolve
        runs at film frame t; None otherwise."""
        s = self.segment(t)
        if s.kind != "dissolve" or not s.start <= t < s.end:
            return None
        u = s.curve(min(1.0, max(0.0, (t - s.start) / (s.end - s.start))))
        take = self.source.take
        return s, take.index_at(s.src0), take.index_at(s.to), u

    def src(self, t: float) -> float:
        """Take seconds shown at film frame t (in a dissolve: the picture
        that dominates the blend)."""
        s = self.segment(t)
        if s.kind == "hold" or t < s.start:
            return s.src0
        if s.kind == "dissolve":
            d = self.dissolve_at(t)
            return s.to if d is None or d[3] >= 0.5 else s.src0
        if s.kind == "scroll":
            return self.source.take.time_s(self.index(t))
        v = s.src0 + (t - s.start) / self.fps * s.rate
        return min(v, s.cap) if s.cap is not None else v

    def scroll_progress(self, t: float) -> float | None:
        """0..1 along a scroll-picked segment (None outside one)."""
        s = self.segment(t)
        if s.kind != "scroll":
            return None
        return min(1.0, max(0.0, (t - s.start) / (s.end - s.start)))

    def index(self, t: float) -> int:
        """The take's picture on screen at film frame t."""
        s = self.segment(t)
        if s.kind == "scroll" and t >= s.start:
            idx, vals, a, b = s.scroll
            u = min(1.0, max(0.0, (t - s.start) / (s.end - s.start)))
            target = a + (b - a) * (1 - math.cos(math.pi * u)) / 2
            best = min(range(len(idx)), key=lambda k: (abs(vals[k] - target), k))
            return idx[best]
        return self.source.take.index_at(self.src(t))

    def moving(self, t: float) -> bool:
        s = self.segment(t)
        return s.kind != "hold" and (s.end is None or t < s.end)

    def blur_at(self, t: float) -> int | None:
        s = self.segment(t)
        if s.blur and self.moving(t):
            return int(s.blur)
        return None

    def frame_of(self, src: float, tolerance_s: float = 1e-6) -> float | None:
        """The first film frame (float) on which the take reaches ``src``."""
        for k, s in enumerate(self.segments):
            nxt = self.segments[k + 1].start if k + 1 < len(self.segments) else math.inf
            if s.kind == "hold":
                if abs(s.src0 - src) <= tolerance_s:
                    return s.start
                continue
            if s.kind in ("scroll", "dissolve"):
                continue
            hi = s.cap if s.cap is not None else math.inf
            if s.src0 - tolerance_s <= src <= hi + tolerance_s:
                t = s.start + max(0.0, src - s.src0) / s.rate * self.fps
                if t <= nxt + 1e-9:
                    return t
        return None

    def report(self) -> list[dict]:
        """Every segment, for the build record and the honesty list."""
        out = []
        for s in self.segments:
            d = {"from_frame": round(s.start, 3), "kind": s.kind, "src_s": round(s.src0, 5)}
            if s.kind == "dissolve":
                take = self.source.take
                d.update(to_s=round(s.to, 5), until_frame=round(s.end, 3), frames=round(s.end - s.start, 3),
                         pictures=[take.index_at(s.src0), take.index_at(s.to)], cite=s.cite, cut=s.cut)
                out.append(d)
                continue
            if s.kind != "hold":
                d["rate"] = round(s.rate, 4)
                if s.cap is not None:
                    d["src_until_s"] = round(s.cap, 5)
                    d["until_frame"] = round(s.end, 3)
                if s.gesture:
                    d["gesture"] = s.gesture
            out.append(d)
        return out
