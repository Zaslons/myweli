"""A cut, end to end: its scenes in order, the caption track, the transitions,
and one frame at a time with a record of what it shows.

Per frame:
  1. the scene's picture layer (stage, phone / carnet / Lottie, touch discs) —
     motion-blurred by subframe accumulation when the scene says the frame
     moves (a whip, a glide, a fast UI picture, the push-in, the morph);
     a whip between two scenes slides both, captions and overlays with them;
  2. grain (the hook only), after the blur;
  3. the scene's sharp overlays (lifts, tiles, the counter, the credit);
  4. the captions, crisp, coloured by the stage.

Takes' masks are on the pictures before step 1: nothing the film draws ever
reads an unblurred phone number.
"""

from __future__ import annotations

from typing import Callable

import numpy as np
import skia

from ..fx import blur as blurmod
from ..fx import grain as grainmod
from ..fx.surface import image_from_array, new_surface, to_array
from .base import Context, Scene, SceneError
from .captions import CaptionItem, CaptionTrack
from .carnet import AirScene, CarnetScene
from .clock import Clock
from .lottie import EndCardScene, RevealScene
from .phone import PhoneScene

KINDS: dict[str, type[Scene]] = {
    "carnet": CarnetScene,
    "air": AirScene,
    "phone": PhoneScene,
    "lottie": RevealScene,
    "end_card": EndCardScene,
}

class Film:
    """A cut in a format. Every format of the storyboard is laid out by its
    own `layout` (the scenes read every place from it, and re-frame their
    camera from the reference format's window by each W key's `keep`): the
    same scenes, the same events.json, the same cut frames."""

    def __init__(self, storyboard, cut: str, fmt_id: str, clock: Clock):
        if fmt_id not in storyboard.formats:
            raise SceneError(f"format {fmt_id}: not in the storyboard (have: {', '.join(storyboard.formats)})")
        specs = storyboard.cut_scenes(cut, fmt_id)        # `formats:` overrides resolved for this format
        if not specs:
            raise SceneError(f"cut {cut}: storyboard.yaml has no scenes for it yet")
        self.storyboard, self.cut = storyboard, cut
        self.fmt = storyboard.formats[fmt_id]
        self.clock = clock
        self.ctx = Context(clock, self.fmt, fps=storyboard.meta.fps, reference=storyboard.reference_format)
        self.frames = storyboard.cuts[cut].frames
        if clock.frames != self.frames:
            raise SceneError(f"events.json has {clock.frames} frames, cut {cut} {self.frames}")
        self.scenes: list[Scene] = []
        caps: list[CaptionItem] = []
        for i, spec in enumerate(specs):
            where = f"scenes.{cut}[{i}]"
            kind = spec.get("kind")
            if kind not in KINDS:
                raise SceneError(f"{where}.kind: one of {', '.join(KINDS)}, not {kind!r}")
            sc = KINDS[kind](spec, self.ctx, where)
            self.scenes.append(sc)
            for j, c in enumerate(spec.get("captions") or []):
                try:
                    caps.append(CaptionItem(c, sc.id, clock, self.fmt.layout, f"{where}.captions[{j}]",
                                            size=self.size))
                except (KeyError, ValueError) as e:
                    raise SceneError(f"{where}.captions[{j}]: {e}") from None
        try:
            self.captions = CaptionTrack(caps)
        except ValueError as e:
            raise SceneError(f"scenes.{cut} captions: {e}") from None
        if self.scenes[0].start != 0:
            raise SceneError(f"the first scene starts on f{self.scenes[0].start}, not f0")
        for a, b in zip(self.scenes, self.scenes[1:]):
            if a.end != b.start:
                raise SceneError(f"scene {a.id} ends on f{a.end} but {b.id} starts on f{b.start}: end to end")
        if self.scenes[-1].end != self.frames:
            raise SceneError(f"the last scene ends on f{self.scenes[-1].end}, the cut on f{self.frames}")
        ids = [s.id for s in self.scenes]
        if len(set(ids)) != len(ids):
            raise SceneError(f"scene ids repeat: {ids}")

    @property
    def size(self) -> tuple[int, int]:
        return self.fmt.width, self.fmt.height

    def scene_at(self, f: int) -> Scene:
        for s in self.scenes:
            if s.start <= f < s.end:
                return s
        raise SceneError(f"no scene on f{f}")

    def previous(self, sc: Scene) -> Scene | None:
        i = self.scenes.index(sc)
        return self.scenes[i - 1] if i else None

    def whip(self, sc: Scene) -> tuple[blurmod.WhipPan, str] | None:
        tr = sc.transition
        if not tr or tr.get("kind") != "whip":
            return None
        forced = self.fmt.layout.get("scene_whip_axis")         # 16:9: scene-to-scene whips are horizontal
        axis = {"horizontal": "x", "vertical": "y"}[forced] if forced else tr.get("axis", "x")
        dist = float(self.size[0] if axis == "x" else self.size[1])
        return blurmod.WhipPan(start=float(sc.start), distance=dist, frames=float(tr.get("frames", 6))), axis

    # ---- one frame ----------------------------------------------------------------------

    def _layer(self, draw: Callable[[skia.Canvas], None]) -> np.ndarray:
        s = new_surface(*self.size)
        draw(s.getCanvas())
        return to_array(s)

    def _full(self, sc: Scene, canvas: skia.Canvas, t: float, f: int, rec: dict, caption_freeze: float | None) -> None:
        """A scene with its overlays and captions, as one picture (for a whip)."""
        sc.draw_picture(canvas, t, fast=True, frame=f)
        sc.draw_overlays(canvas, f, {} if rec is None else rec)
        self.captions.draw(canvas, t, sc.stage.dark, owner=sc.id, freeze=caption_freeze)

    def frame(self, f: int) -> tuple[np.ndarray, dict]:
        if not 0 <= f < self.frames:
            raise SceneError(f"f{f} is outside the cut (0–{self.frames - 1})")
        sc = self.scene_at(f)
        rec: dict = {"f": f, "scene": sc.id, "kind": sc.kind, "stage": sc.stage.ground}
        w = self.whip(sc)
        if w is not None and f < w[0].start + w[0].frames:
            whip, axis = w
            prev = self.previous(sc)
            last = float(prev.end - 1)

            def scene(canvas: skia.Canvas, t: float) -> None:
                whip.draw_transition(canvas, t,
                                     lambda c: self._full(prev, c, last, int(last), None, last),
                                     lambda c: self._full(sc, c, t, int(round(t)), None, None), axis=axis)

            n = whip.samples(float(f), shutter=1.0)
            out = blurmod.accumulate(scene, self.size, float(f), samples=n, shutter=1.0, seed=f)
            rec["blur"] = {"samples": n, "shutter": 1.0, "whip": True}
            rec["transition"] = "whip"
            sc.record(f, rec)
            rec.pop("touch_downs", None)
            rec.setdefault("boxes", [])
            return out, rec
        b = sc.blur_at(f)
        if b is not None:
            out = blurmod.accumulate(lambda c, t: sc.draw_picture(c, t, fast=True, frame=f), self.size, float(f),
                                     samples=b.samples, shutter=b.shutter, region=b.region, seed=f)
            rec["blur"] = {"samples": b.samples, "shutter": b.shutter, "ui": b.ui}
        else:
            out = self._layer(lambda c: sc.draw_picture(c, float(f), frame=f))
        if sc.grain:
            out = grainmod.apply_grain(out, f, seed=int(sc.grain.get("seed", 0)))
        surf = new_surface(*self.size)
        canvas = surf.getCanvas()
        canvas.drawImage(image_from_array(out), 0, 0)
        sc.draw_overlays(canvas, f, rec)
        self.captions.draw(canvas, float(f), sc.stage.dark)
        rec.setdefault("boxes", []).extend(self.captions.boxes(float(f)))
        sc.record(f, rec)
        return to_array(surf), rec

    def crowded_captions(self) -> list[dict]:
        """Every frame of a phone scene on which a caption's ink comes within
        the phone's clearance (verify.CAPTION_PHONE_CLEAR_PX) of the phone as
        posed — from the scenes, before a frame is drawn: the renderer refuses
        them (render.build_one), verify (g) re-reads them from render.json.
        The owner's round 5 (2026-10-20): 16:9's push about the floor grows
        the slab towards the left column « never cropping … a caption »."""
        from ..verify import captions_over_phone
        recs = []
        for sc in self.scenes:
            if not isinstance(sc, PhoneScene):
                continue
            for f in range(sc.start, sc.end):
                area = sc.phone_area(float(f))
                if area is not None:
                    recs.append({"f": f, "phone": list(area), "boxes": self.captions.boxes(float(f))})
        return captions_over_phone(recs)

    # ---- what the film is made of ------------------------------------------------------------

    @staticmethod
    def continuous(sc: Scene) -> bool:
        """A scene handoff with no picture change (`transition: {kind: continuous}`): not a cut."""
        return bool(sc.transition) and sc.transition.get("kind") == "continuous"

    def transitions(self) -> list[dict]:
        """Every join — hard cuts, whips (scene to scene and in the phone), declared dissolves — and every
        `continuous` scene handoff, labelled so (no picture change: verify (b) counts it apart and holds
        it to that)."""
        out = []
        for sc in self.scenes[1:]:
            w = self.whip(sc)
            kind = "whip" if w else ("continuous" if self.continuous(sc) else "cut")
            out.append({"frame": sc.start, "kind": kind, "into": sc.id, "frames": int(w[0].frames) if w else 0})
        for sc in self.scenes:
            if isinstance(sc, PhoneScene):
                for a, b in zip(sc.W.keys, sc.W.keys[1:]):
                    if b.blur == "whip" and a.value != b.value:
                        out.append({"frame": int(a.frame), "kind": "whip (in the phone)", "into": sc.id,
                                    "frames": int(b.frame - a.frame)})
                for s in sc.dissolves:
                    # `curve: cut` (16:9's 15-s form, the owner's round 5): a declared HARD cut, held to a cut's rule
                    out.append({"frame": int(s.start), "kind": "cut (declared, in the phone)" if s.cut else
                                "dissolve (declared)", "into": sc.id, "frames": 0 if s.cut else int(round(s.end - s.start))})
            if isinstance(sc, CarnetScene) and sc.macro:
                out.append({"frame": sc.macro["at"], "kind": "cut", "into": f"{sc.id} (macro)", "frames": 0})
                out.append({"frame": sc.macro["until"], "kind": "cut", "into": f"{sc.id} (wide)", "frames": 0})
        return sorted(out, key=lambda d: d["frame"])

    def events(self) -> list[tuple[int, str]]:
        ev = [(sc.start, f"{'continuous into' if self.continuous(sc) else 'cut into'} {sc.id}") for sc in self.scenes]
        for sc in self.scenes:
            ev += sc.events()
        ev += [(int(at), f"word « {w} »") for _, at, w in self.captions.words()]
        ev += [(int(c.strike[1]), f"strike « {c.strike[0]} »") for c in self.captions.items if c.strike]
        ev += [(int(c.underline["at"]), f"underline « {c.underline['text']} »") for c in self.captions.items
               if c.underline]
        return sorted(e for e in ev if 0 <= e[0] < self.frames)

    def generated(self) -> list[dict]:
        out = []
        for sc in self.scenes:
            out += sc.generated()
        for c in self.captions.items:
            out.append({"element": f"caption « {c.text} »", "scene": c.owner, "cite": c.cite})
            if c.underline:
                out.append({"element": f"underline under « {c.underline['text']} » ({c.id})", "scene": c.owner,
                            "cite": "the brand's single round-cap stroke at the type's stem width — the hook's "
                                    "strikes' pen (promo/fx/type.py draw_strike; brand book: the mark's one "
                                    "stroke) — on the owner's outro bar (2026-10-19); no text, no UI"})
        return out

    def plan(self) -> dict:
        """The static description of the film (for the build record)."""
        d = {"cut": self.cut, "format": self.fmt.id, "frames": self.frames,
             "scenes": [{"id": s.id, "kind": s.kind, "rows": s.rows, "frames": [s.start, s.end]} for s in self.scenes],
             "transitions": self.transitions(), "timelines": {}}
        for s in self.scenes:
            if isinstance(s, PhoneScene):
                d["timelines"][s.id] = {"take": s.source.name, "segments": s.timeline.report(),
                                        "touches": [{"gesture": t.gesture, "kind": t.kind, "down_s": round(t.down_s, 5),
                                                     "frame": t.down_f, "up_frame": round(t.up_f, 3), "tone": t.tone}
                                                    for t in s.touches]}
                if s.credit:
                    # where the map shows: its credit is held whole to the last of these (verify (h))
                    d.setdefault("credits", {})[s.id] = [s.start, s.end]
                if s.hidden:
                    d.setdefault("hidden", {})[s.id] = [{"take": s.source.name, "label": lab, "rect_pt": list(rect),
                                                         "shown_on_s": shown} for lab, rect, shown in s.hidden]
            if isinstance(s, RevealScene):
                d["lottie_rates"] = s.rates()
            if isinstance(s, CarnetScene):
                d.setdefault("hook_ink", {})[s.id] = s.ink_places()
        return d
