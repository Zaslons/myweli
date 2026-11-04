"""FX — the promo's skia drawing primitives (tool/promo_reel/promo/fx).

Pure functions and small classes that draw on a skia.Canvas, deterministic
(every random choice is seeded), parameterised, and free of any knowledge of
the storyboard's times: SCENES drives them from events.json.

  easing      the app's curves (Flutter's control points), keyframes, frame time
  brand       colour tokens (colors.dart), fonts, the mark's geometry, motion tokens
  surface     RGBA surfaces ⇄ numpy, exact Lanczos draws of real pictures, layers
  projection  2.5D poses → one projective matrix (perspective-correct)
  type        French typography, measuring, captions word by word, mask reveal, strike
  phone       the slab + real screen, 2.5D, the camera window with band/floor fades
  blur        motion blur by subframe accumulation (linear light), the whip pan
  lift        a real UI region lifted as a magnified card over the paper veil
  stack       several lifts stacked, one per beat
  counter     the odometer that lands exactly on the app's figure; FCFA format
  touch       the touch disc and its ripple, black or white by ground
  pattern     the brand brick pattern, dark or light, drifting
  grain       per-frame seeded film grain; TPDF dithering for every quantisation
  carnet      the procedural ruled carnet page: scribbles, ink drawing on, strikes
  punch       scale-punch envelopes
  demo        `python -m promo.fx.demo` — the showcase sheets

Modules are imported individually (`from promo.fx import phone`;
`from promo.fx import type as ty` — never `import *`, which would shadow the
builtin `type`). This package imports nothing on its own, so loading one
primitive stays cheap.
"""
