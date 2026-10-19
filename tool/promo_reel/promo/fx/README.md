# FX — the skia drawing primitives

`tool/promo_reel/promo/fx/` · owner: FX · tests: `tool/promo_reel/tests/test_fx.py`

Pure functions and small classes that draw on a `skia.Canvas`. They know nothing
about the storyboard's times: SCENES passes frames (floats — a motion-blur
subframe is just frame 12.375) read from `events.json`. Everything random is
seeded; the same arguments always draw the same pixels.

```sh
cd tool/promo_reel
python -m unittest discover -s tests -p 'test_fx.py'      # 65 tests, < 1 s
python -m promo.fx.demo --out DIR                          # four 1080×1920 showcase sheets
```

## Conventions

- **Frames** are floats at 30 fps. Cue frames are the FIRST VISIBLE frame of an
  entrance (a word, a disc, a lift): the animation runs over [cue − 1, cue + n − 1],
  so the frame the beat lands on already moves.
- **Units**: frame px, unless a name says `_pt` (screen points: the gesture logs'
  unit) or `_src` (capture px, 3 px/pt).
- **Colours** are skia ARGB ints; app tokens come from `colors.dart` by name
  (`brand.token("textPrimary")`, or `brand.PALETTE.INK`).
- **Curves** are Flutter's (`easing.EASE_OUT_CUBIC`, `easing.FAST_OUT_SLOW_IN`, …),
  control points imported from `tool/app_store_preview/brand.py`, solved to 1e-9;
  every curve maps 1 → exactly 1, so an animated value lands exactly on its target.

## Modules and their API

| module | what you call |
|---|---|
| `easing` | `Cubic(a,b,c,d)`, `EASE_IN/OUT/IN_OUT`, `EASE_OUT_CUBIC`, `EASE_IN_OUT_CUBIC`, `EASE_IN_CUBIC`, `FAST_OUT_SLOW_IN`, `curve(name)`, `flipped(c)`, `progress(t, start, frames)`, `ease(t, start, frames, c)`, `tween(t, start, frames, a, b, c)`, `motion(token) → (frames, curve)`, `Keyframes([Key(frame, value, curve)])`, `lerp`, `clamp01`, `smoothstep` |
| `brand` | `PALETTE` (INK, INK_SECONDARY, INK_TERTIARY, PAPER, BLACK, WHITE, BORDER, PATTERN_ON_BLACK, PATTERN_ON_PAPER), `token(name)`, `rgb(c)`, `with_alpha(c, a)`, `poppins(px)`, `inter(px, weight=500, opsz=None)`, `mark_geometry()`, `mark_path(height, centre) → (path, stroke)`, `mark_paint(colour, stroke)`, `motion_tokens()` |
| `surface` | `new_surface(w, h)`, `to_array(surface_or_image)`, `image_from_array(a)`, `as_image(x)`, `save_png(x, path)`, `Picture(src)` + `draw_exact(canvas, pic, src, dst)`, `layer(canvas, alpha)`, `scaled_about(canvas, s, cx, cy)`, `vertical_fade(canvas, rect, stops)`, `SAMPLING_CUBIC`, `SAMPLING_MIPMAP` |
| `projection` | `Pose(rot_x, rot_y, rot_z, scale, dx, dy, z, focal=2400, pivot)`, `homography(pose, rest) → 3×3`, `project(pose, rest, pts, depth)`, `apply`, `apply_many`, `to_skia`, `solve_offset(pose, rest, point, target)`, `lerp_pose` |
| `type` | `french(text)`, `fcfa(n)`, `group_thousands(n)`, `shape(text, font)`, `measure(text, font)`, `draw_text(canvas, text, font, x, baseline, colour, alpha, align)`, `break_lines(text, font, max_width, max_lines=2)`, `Caption(lines=[[Word(text, at)]], font, colour, centre_x, cap_top \| baseline, line_height, max_width=771, reveal=RISE \| MASK)` → `.draw(canvas, t, alpha, dy)`, `.find(text)`, `draw_mask_reveal(…)`, `draw_strike(canvas, p0, p1, width, progress, colour)`, `strike_word(canvas, caption, text, t, at, colour)`, `stem_width(font)`, `cap_height`, `x_height`, `ink_bounds` |
| `phone` | `Phone(capture).draw(canvas, pose, *, W=None, window=WINDOW_9X16, centre, opacity, fade, overlay, sampling)`, `.map_point(x_pt, y_pt, pose, W=…)`, `.map_rect(rect_pt, …)`, `.matrix(…)`, `.set_screen(capture)`; `Window(screen_x=180, top=600, band_fade=40, floor=1192, floor_fade=24, px_per_pt=1.791)` with `y_of`, `point`, `pt_of`, `W_for`, `alpha_at`; `PhoneSpec` |
| `blur` | `accumulate(render, size, t, samples=8, shutter=1.0, linear=True, region=None) → RGBA uint8`, `Accumulator`, `subframe_times`, `samples_for(speed)`, `WhipPan(start, distance, frames=6)` with `offset(t)`, `speed(t)`, `peak_frame()`, `samples(t, px_per_unit)`, `draw_transition(canvas, t, draw_out, draw_in, axis)` |
| `lift` | `Lift(picture, src, origin, target).draw(canvas, p, veil_rect)`, `draw_card`, `draw_veil`, `pop_progress(t, up, frames=6, down, down_frames=5)`, `fit_width(src, x0, x1, top \| centre_y \| bottom)`, `LiftStyle`, `CARD_SHADOW` |
| `stack` | `Stack(picture, sources, origins, targets, ups).draw(canvas, t, veil_rect)`, `stack_rects(sources, x0, width, gap, top \| centre_y)` |
| `counter` | `Odometer(start, end, font, colour, suffix=" FCFA", curve=FAST_OUT_SLOW_IN).draw(canvas, p, x, baseline, align, alpha, scale)`, `.text_at(p)`, `.digits_at(p)`, `.width(p)`; `draw_label_switch(canvas, old, new, p, font, x, baseline, colour)` |
| `touch` | `draw_touch(canvas, x, y, tone, alpha, scale)`, `draw_ripple(canvas, x, y, t, down, tone, scale)`, `draw_tap(…)`, `touch_alpha(t, down, up)`, `ripple_state(t, down)`, `tone_at(rgb, x, y, diameter)`, `TouchStyle` |
| `pattern` | `draw_pattern(canvas, rect, dark, alpha, offset, origin, clear, feather)`, `mark_centres`, `PatternSpec(mark_height=66, pitch_x=110, pitch_y=110)` |
| `grain` | `apply_grain(rgba, frame, seed, spec, amount)`, `quantize(values, seed, frame)` (TPDF dither), `GrainSpec` |
| `carnet` | `Carnet(seed).draw(canvas, pose, rest, ink={id: p}, strikes={row: p}, light=1.0)`, `.rest_rect(x0, x1, top)`, `.focus(pose, rest, page_xy, frame_xy)`, `.strike_segment(row)`, `.entries` (`rowNN`, `write`, `squeeze`, `arrow`, `margin`, `crossNN`, `header`, `tickNN`), `.write_row`, `.squeeze_after`, `.crossed_rows` |
| `punch` | `punch(t, at, peak=1.025, out=3, back=5)`, `settle(t, at, start=1.08, frames=5)`, `Punch`, `Punches` |

## Decisions worth knowing

- **French spacing without a glyph.** Poppins Medium has no U+202F (it would draw
  a box). `type.shape` maps characters to glyphs itself and gives U+202F an
  advance of half the word space (0.13 em) and no glyph — the width the
  storyboard measured: « 77 000 FCFA » = 712 px at 120 px. Poppins has no
  kerning at all (no `kern`, GPOS only for Devanagari marks), so unkerned
  advances are the app's own widths.
- **Real pixels resampled once, with Lanczos.** A flat draw of a capture (the
  phone in its window, every lift) is resampled from a fractional source box with
  Lanczos-3 and blitted 1:1 (`surface.draw_exact`) — sharp and identical at every
  sub-pixel camera position. Through a perspective, skia's Mitchell cubic.
- **Motion blur averages light, not code values.** Subframes are decoded to linear
  light, averaged premultiplied in float32 and re-encoded with TPDF dither: a smear
  of black type on white is the bright 50 % it really is (level 188), not the muddy
  128 an sRGB average gives. 8 subframes is the floor; fast whips take up to 64,
  so copies stay ≤ 2 px apart.
- **The counter lands exactly.** Every column's strip ends on its final digit with
  zero offset at progress 1, and the landed figure is the typeset string pixel for
  pixel (tested). Leading columns grow in with their first step, so « 0 FCFA »
  widens smoothly into « 77 000 FCFA ».
- **The carnet has no letters.** Every scribble is a seeded pen path (humps,
  loops, ascenders, descenders, a slant); no font is used (a test checks the
  source). The strikes are the brand's, not the pen's.

## Showcase

`python -m promo.fx.demo` writes `sheet-type.png`, `sheet-phone.png`,
`sheet-carnet.png`, `sheet-fx.png` (each a 3 × 3 grid of real 1080 × 1920
frames at a third of their size) and every frame at full size in `frames/`.
It reads the App Store raw captures `pro-01-agenda.png` and
`pro-05-client.png` (gitignored `build/`; `--shot`/`--client` to override) and
blurs Awa K.'s number before use.
