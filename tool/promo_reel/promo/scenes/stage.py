"""The stage every scene stands on: #FAFAFA paper with the light brand pattern
behind the app, #000 with the dark one in the hook and the two air beats
(storyboard « LAYOUT 9:16 »: « Stage »); bare paper for the brand reveal and
the end card (« The brand pattern … never near the logo »).

``drift_px_s`` moves the dark pattern (4 px/s); a parallax offset can be
added (the public page: the pattern at 0.4× the phone's drift).
"""

from __future__ import annotations

from dataclasses import dataclass

import skia

from ..fx import pattern
from ..fx.brand import PALETTE
from ..fx.surface import skrect


@dataclass(frozen=True)
class Stage:
    ground: str = "paper"                    # paper | black
    pattern: float = 1.0                     # the pattern's opacity (0: none)
    drift_px_s: tuple[float, float] = (0.0, 0.0)

    @classmethod
    def parse(cls, spec: dict | None, where: str) -> "Stage":
        spec = spec or {}
        ground = spec.get("ground", "paper")
        if ground not in ("paper", "black"):
            raise ValueError(f"{where}.stage.ground: paper or black, not {ground!r}")
        drift = tuple(float(v) for v in spec.get("drift_px_s", (0, 0)))
        return cls(ground, float(spec.get("pattern", 1.0)), drift)  # type: ignore[arg-type]

    @property
    def dark(self) -> bool:
        return self.ground == "black"

    @property
    def colour(self) -> int:
        return PALETTE.BLACK if self.dark else PALETTE.PAPER

    def draw(self, canvas: skia.Canvas, size: tuple[int, int], seconds: float,
             offset: tuple[float, float] = (0.0, 0.0)) -> None:
        """The ground and the pattern, ``seconds`` into the scene."""
        w, h = size
        canvas.drawRect(skrect((0, 0, w, h)), skia.Paint(Color=self.colour))
        if self.pattern > 0:
            dx = self.drift_px_s[0] * seconds + offset[0]
            dy = self.drift_px_s[1] * seconds + offset[1]
            pattern.draw_pattern(canvas, (0, 0, w, h), dark=self.dark, alpha=self.pattern, offset=(dx, dy),
                                 origin=(w / 2, h / 2))
