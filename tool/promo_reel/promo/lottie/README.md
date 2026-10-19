## Lottie — the Pro app's opening animation, drawn by Skia

`promo/lottie/` plays `mobile/assets/lottie/open/myweli_loader_mixed_pro.json` — the file
`pro_splash_screen.dart:45` loads and `:212-219` plays at 220 px wide on `#FAFAFA` — onto a
`skia.Canvas` at any **continuous** composition time, so the reveal (bars 13–14) can retime it
and accumulate sub-frames. It depends on skia-python and numpy only; no Lottie library.

```python
from promo.lottie import Player, PRO_OPEN_ANIMATION

player = Player(PRO_OPEN_ANIMATION)    # validates the file
player.frames, player.fps, player.size  # (0.0, 142.0), 25.0, (560, 380)
player.markers                          # {'intro': (0, 74), 'wordmark': (12, 38), 'loop': (74, 142)}
dst = player.dst_rect((540, 680), 900)  # the storyboard's placement: comp 900 px wide
player.render(canvas, 60.25, dst)       # file colour #111111; color='#FFFFFF' recolours
player.ink_bounds(142)                  # Rect(231.84, 106.72, 328.16, 273.28), comp units
player.device_frame(1.0)                # 141.990: the comp time the app draws at the end
```

`render(canvas, comp_frame, dst_rect, color=None)`: the 560 × 380 frame is fitted into
`dst_rect` (uniform, centred) and clipped to it. `comp_frame` is clamped to `[ip, op)`: the out
point is exclusive in Lottie, so `142` draws what the app rests on (`141.990`, the finished mark);
`74` draws the same picture. `color` is `None`, an ARGB int, `'#RRGGBB'` or a `skia.Color4f`.

**What it implements — exactly the file's features** (`model.py` enforces it; anything else raises
`UnsupportedFeature` naming the JSON path: masks, mattes, parenting, precomps, time remap,
expressions, hold keyframes, spatial tangents, dashes, other shapes, trim « individually »…):
10 shape layers; groups of paths → optional trim → fill/stroke → transform; static and morphing
paths; non-zero fills; strokes with butt/round caps and round joins; one simultaneous trim
(the `redraw` erase/redraw); layer opacity fades; one easing, cubic-bezier(0.4, 0, 0.2, 1).

**How it stays exact.** Each rule is lottie-flutter 3.5.1's (`mobile/pubspec.lock`), read from
its source and cited in `player.py`: layer order and `[ip, op)` visibility, paint order, path
construction, the trim (first contour, « within 1 % = untrimmed », start = end → nothing, the
integer `floorMod`), byte colours, `roundProgress`. One rule is Flutter's engine:
`DisplayListBuilder::DrawPath` records a rectangle path as `DrawRect` (and round rect, oval,
line likewise) — without it the « l » of the wordmark is up to 25 levels off at two edges.
Deliberate differences, both sub-visible: opacity is continuous (the app rounds it to whole
percent, then truncates the alpha byte — at most ~2 levels apart, during fades only) and easing
is solved exactly (the app's table is ≤ 3e-6 off).

**Acceptance** — `python -m promo.lottie check [--out DIR]` renders the goldens' frames as the
app draws them (390 × 844, DPR 1, Lottie 220 px wide, centred) and compares with
`mobile/test/golden/goldens/` (Flutter on Linux):

| golden | comp (drawn) | mean abs err | max abs err | IoU of ink | centroid shift |
|---|---|---|---|---|---|
| `pro_splash_wordmark` | 25 (24.998) | 0.0015 / 255 | 2 / 255 | 0.9993 | 0.003 px |
| `pro_splash_end` | 142 (141.990) | 0.0002 / 255 | 1 / 255 | 1.0000 | 0.000 px |

Same ink bounding boxes in both. `python -m promo.lottie filmstrip --out strip.png` draws every
10th frame; `python -m promo.lottie frame --at 60 --width 900 --out f.png` one frame.

**Third-party players** (tried in a throwaway venv, not used): `rlottie-python` 1.3.8 renders
every frame **empty** — it evaluates the layers' animated opacity as 0 (with opacity made static
it draws comp 25, still not 142). `lottie` 0.7.2 (python-lottie) exports SVG that, rasterised
with rsvg-convert, matches the shapes (IoU 0.992–0.997 at 25/60/141) but its easing is off: at
comp 90 the erase has advanced to s = 0.8247 against the exact 0.8144 (≈ 0.2 frame early).

Tests: `python -m unittest tests.test_lottie` (38 tests, < 0.1 s).
