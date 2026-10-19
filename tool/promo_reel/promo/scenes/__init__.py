"""SCENES — every storyboard row, drawn from storyboard.yaml and events.json.

    clock.py     the film's clock: cue ids, grid positions and offsets → frames,
                 read from the events.json the audio engine wrote (never typed)
    keys.py      keyframed values (camera W, zoom, tilt…) on the app's curves
    sources.py   a take as a scene uses it: masks, touch-downs, the film → take
                 time map (timeline), pictures held for resampling
    stage.py     the stage: paper or black, the brand pattern, its drift
    captions.py  the caption track (word by word, strikes, colour by stage)
    carnet.py    rows 1–4, the code-drawn carnet hook
    phone.py     rows 6–22, the phone scenes (journal, Fiche, Revenus, page, air)
    lottie.py    rows 23–24, the Pro opening Lottie and the end card
    film.py      a cut: its scenes end to end, transitions, one frame at a time,
                 and the per-frame record verify.py reads

A scene is built from its YAML and the clock; ``Film.frame(f)`` returns an
RGBA frame and a record of what it drew (boxes, touches, pictures, events).
"""

from __future__ import annotations

from .base import SceneError
from .clock import Clock, ClockError
from .film import Film

__all__ = ["Clock", "ClockError", "Film", "SceneError"]
