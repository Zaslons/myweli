# MyWeli Pro promo reel — « CARNET → DROP »

A code-only social promo for MyWeli Pro: 30 s and 15 s cuts, each in 9:16,
1:1 and 16:9. Every frame is drawn with skia and piped raw to ffmpeg; the
music is synthesised and is the clock; the app's pixels are real frames of
the recorded takes, in order. No editor, no templates, no stock.

The approved storyboard (2026-10-19) is the brief; `storyboard.yaml` is its
machine-readable form and the one source of the pipeline.

```
tool/promo_reel/build.sh            # the one command: venv, checks, build every cut × format, verify
tool/promo_reel/build.sh --set meta.title="Test"   # the same on a variant
tool/promo_reel/build.sh test       # the unit tests
```

`build.sh` creates `tool/promo_reel/.venv` with Python 3.12
(`/usr/local/bin/python3.12`, else `python3.12` on the PATH, or `PROMO_PYTHON`)
and exactly the pinned `requirements.txt` (rebuilt when that file changes),
checks ffmpeg and ffprobe (Homebrew: `brew install ffmpeg`; it stops and says
so when they are missing), then runs `python -m promo build --all` and
`python -m promo verify --all`. Outputs go to `out/` (ignored by git, like
`.venv/`).

The recorded material is read, never written: the takes, gesture logs and the
App Store tool's scans live under `build/app-store/pro/preview/v2/` of the
**main checkout** (`build/` is gitignored, so a worktree does not have it — the
tool finds the main checkout through the worktree's `.git` file, or
`PROMO_MATERIAL` points at that folder).

## Layout and owners

| Path | Owner | What |
|---|---|---|
| `build.sh`, `requirements.txt`, `.gitignore` | MEDIA | the one command, pinned versions |
| `storyboard.yaml` | MEDIA (schema), SCENES (content) | the one source |
| `promo/timebase.py` | MEDIA | bar.beat.step ⇄ frame ⇄ sample |
| `promo/storyboard.py` | MEDIA | load + check the storyboard, variants |
| `promo/__main__.py` | MEDIA | `python -m promo plan/build/verify` (hands over to SCENES' modules) |
| `promo/media/` | MEDIA | takes, masks, writer, probe, sheets, touches |
| `promo/audio/` | AUDIO | the score, the mix, loudness, `events.json` |
| `promo/lottie/` | LOTTIE | the Skia Lottie player |
| `promo/fx/` | FX | skia drawing primitives |
| `promo/scenes/`, `promo/render.py`, `promo/verify.py` | SCENES | every storyboard row, every cut and format, the verification suite |
| `tests/test_<module>.py` | each builder | unittest, fast |

## The time base — `promo/timebase.py`

The music is the clock. At 112.5 BPM and 30 fps every grid line is a whole
frame and every frame a whole number of samples:

| | frames | seconds | samples |
|---|---|---|---|
| 16th (step) | 4 | 0.1333 | 6 400 |
| 8th | 8 | 0.2667 | 12 800 |
| beat | 16 | 0.5333 | 25 600 |
| bar (4/4) | 64 | 2.1333 | 102 400 |
| frame | 1 | 1/30 | 1 600 |

Positions are `bar.beat.step` from the cut's start (1-based bar and beat,
step 0–3): `frame = (bar − 1)·64 + (beat − 1)·16 + step·4`,
`sample = frame · 1600`. The storyboard's shorthand reads too: `5.2` = `5.2.0`,
`5.2e` / `5.2&` / `5.2a` = steps 1 / 2 / 3. All arithmetic is exact (ints and
`Fraction`); a frame off the 16th grid has no position (an error, never a
snap — `split_frame` says how far off it is).

```python
from promo import timebase as tb
tb.pos_to_frame("3.2.0")      # 144          tb.frame_to_pos(144)    # Pos(bar=3, beat=2, step=0)
tb.pos_to_frame("5.2&")       # 280          tb.split_frame(149)     # (Pos(3, 2, 1), 1)
tb.frame_to_sample(144)       # 230400       tb.sample_to_frame(230400)  # 144 (an error inside a frame)
tb.frame_at_sample(230401)    # 144          tb.to_frame("f144") == tb.to_frame("3.2") == 144
tb.frame_to_seconds(144)      # Fraction(24, 5)   tb.seconds_to_frame(4.8)  # 144
tb.DEFAULT.grid(896, "beat")  # the 56 beats of the 30-s cut
```

Constants: `FPS`, `BPM`, `SAMPLE_RATE`, `FRAMES_PER_STEP`, `FRAMES_PER_BEAT`,
`FRAMES_PER_BAR`, `SAMPLES_PER_FRAME`. `TimeBase(fps, bpm, sample_rate)`
checks any other grid and refuses one that is not whole frames.

## storyboard.yaml — `promo/storyboard.py`

Exactly five top-level keys (plus `x-…` keys, which only hold YAML anchors):

- **meta** — `title`, `fps`, `bpm`, `key`, `sample_rate`. Strict: the time base
  must be the contract's (30 fps, 112.5 BPM, 48 kHz).
- **cuts** — `30s: {bars: 14, frames: 896}`, `15s: {bars: 7, frames: 448}`, each
  with a `description`. A cut is named by its length; `frames` must be
  `bars × 64`; a cut never runs longer than its name.
- **formats** — `9x16`, `1x1`, `16x9`:
  - `size` (the id's aspect ratio, short side 1080 so every pixel size carries
    over), `safe` `[x0, y0, x1, y1]`, `safe_basis` (`platform` — the strict
    TikTok/Reels/Status rectangle x 120–900, y 270–1248 — or
    `ebu_r95_graphics`, checked to be the 5 % inset), `safe_note`,
    `rail_free` (9:16: captions may run to x 960 above y 840);
  - `zones`: content zones that must lie inside the safe area (or the
    rail-free extension) — `captions`, `hook_block`, `phone_window`,
    `overlays` (lifts, counter, ripples), `slot_card` — and stage zones that
    may cover the canvas — `caption_band`, `caption_fade`, `top_fade`,
    `floor_fade`, `floor`;
  - `layout` (every key required, null where it does not apply):
    `caption_band`, `caption_column_x`, `caption_centre_x`, `caption_centre_y`,
    `caption_line_max_px` (771), `caption_lines_max` (2), `phone_screen_x`,
    `px_per_pt` (1.791 — checked to show the screen's 402 pt), `screen_crop_top_pt`
    (56), `phone_bezel_px`, `phone_radius_px`, `type_px` (hook 96, app 72,
    counter 120, counter_label 40, tagline 46, credit 24), `lottie_centre`,
    `lottie_comp_width_px` (900), `end_mark_scale`, `end_mark_ink_y`,
    `end_tagline_cap_top_y` (checked: half the mark's height of clear space),
    `lift_x`, `lift_veil`, `tilt_axis`, `tilt_max_deg`, `scene_whip_axis`.
  - Across formats, `px_per_pt`, `type_px`, `lottie_comp_width_px`,
    `end_mark_scale` and `screen_crop_top_pt` must be identical: one
    storyboard, re-laid out, never resized.
- **music** — AUDIO's section, passed through. Only `music.cues` is read: a
  list of `{id: …, …}` (or a mapping `cut → list`), ids unique, no spaces.
- **scenes** — SCENES' section (a list, or a mapping), passed through. **A cue
  reference is the value of a key named `cue` (one id) or `cues` (a list of
  ids), at any depth**: each must be declared in `music.cues`.

Every problem is reported at once, with its path:

```
storyboard.yaml: 2 problems:
  - meta.bpm: 120 is not the contract's 112.5 BPM (promo/timebase.py): the music is the clock, 16 frames a beat
  - scenes[1].sound.cues[1]: cue 'drop1.typo' is not in music.cues (known: drop1.impact, hook.word1)
```

Variants: `--set path.to.key=value` (repeatable) overrides one value before the
check, so a variant is held to the same rules. The value is YAML
(`--set formats.9x16.safe=[120,270,900,1248]`, `--set 'meta.title="no"'` to
force a string); list items by index (`--set scenes.0.id=hook`); every key on
the path must exist but the last.

```python
from promo import storyboard
sb = storyboard.load()                                   # or load(path, overrides=["meta.title=X"])
sb.meta.bpm, sb.timebase.frames_per_bar                  # Fraction(225, 2), 64
sb.cuts["30s"].frames, sb.cuts["30s"].duration_s         # 896, Fraction(448, 15)
sb.formats["9x16"].safe, sb.formats["9x16"].zones["phone_window"]   # Rect(120, 270, 900, 1248), …
sb.formats["16x9"].layout["lift_x"]                      # [300, 1060]
sb.music, sb.scenes, sb.cue_ids()                        # pass-through data, declared cue ids
print(sb.plan())                                         # what a build makes
```

## The command — `python -m promo`

```
python -m promo plan   [--all | --cut 30s --format 9x16 …] [--set path=value …]
python -m promo build  --all [--set …] [--out DIR]
python -m promo verify --all [--set …] [--out DIR]
```

Each loads and checks the storyboard first (exit 2 on a problem). `build` and
`verify` hand over to SCENES' modules as soon as they exist — nothing here
changes:

```python
# promo/render.py
def build(storyboard, cuts: list[str], formats: list[str], out_dir: Path) -> None: ...
# promo/verify.py
def verify(storyboard, cuts: list[str], formats: list[str], out_dir: Path) -> bool: ...
```

Until then `build` prints the plan and says that nothing was rendered, and
`verify` says plainly that no film was verified. If `render.py` exists and
`verify.py` does not, `verify` fails.

## Media — `promo/media/`

### takes.py — a take, picture by picture

The recorder writes a picture only when the screen changes (VFR, H.264,
1206 × 2622, timescale 600 = one tick is 1/600 s). **The picture shown at `t`
is the latest whose time is ≤ t.** Every picture's time comes from the
container (packets, no decoding); when the App Store tool scanned the take
(`final/takes/take-N/scan.json`: take-1 = take1b, take-2 = take2b,
take-3 = take5b, take-4 = take3) the scan must be the same file (sha256) with
the same pictures and times. A picture is decoded by ffmpeg seeking to the
picture before it on its exact tick; ffmpeg's `showinfo` reports the time of
every picture it hands over and each is identified by that time — a picture
handed over where another was expected is an error, never a neighbour.
Reading on from an open decoder needs no new seek; decoded pictures are kept
in an LRU cache (a byte budget; one picture is 12.6 MB). Colour: BT.709
matrix, limited range, values taken as they are (the App Store tool's rule:
the scaffold #F6F7F9 decodes to 247/247/249).

```python
from promo.media.takes import Take
take = Take("take1b")                     # or Take(path/to/take.mov); Take(..., cache_mb=768)
take.count, take.pts[:3], take.timescale  # 4524, (0, 6470, 6471), 600
take.index_at(23.620)                     # 52: the « Arrivé » picture (23.619 → 51, still « Confirmé »)
p = take.picture_at(10.0)                 # Picture(index, ticks, time_s, rgba) — rgba H×W×4 uint8, read-only
take.picture(52); take.skia_image(52)     # masked pixels (numpy / skia.Image)
take.pictures_between(t0, t1)             # [Shown(index, ticks, start_s, end_s, weight)] — for motion blur
take.raw_picture(52)                      # UNMASKED: for measuring and mask checks only
take.index_named(131.448)                 # 4502 — see below; take.time_named(…), take.picture_named(…)
```

**Times written in the notes and the storyboard are picture times rounded to
the millisecond.** « Snackbar in 131.448 » is the picture at 131.44833 s:
`index_at(131.448)` follows the rule and returns the picture BEFORE it (no
snackbar). `index_named(t)` returns the picture a written time means (the
nearest within 1 ms; none, or two equally near, is an error). In take1b this
matters for 22.018 (the « Arrivé » press), 41.388, 49.798, 66.333 (« Y »),
87.548 (space), 95.083 (« K ») and 131.448 (the snackbar); in take2b for
5.818, 31.468 and 32.318; in take5b for 27.213. Anchor a scene on
`time_named(…)`, then map film time to take time and use `index_at`. Times
that are instants inside a held picture (10.000, 11.595, 23.985, 31.600,
32.998, 132.381; take2b 6.500; take5b 25.900) are not picture times:
`index_at` is right for them, and `index_named` refuses them.

`python -m promo.media.takes take1b 10.0 out.png` prints which picture is shown
and saves it.

### masks.py — blurs on the source pictures

A `Blur` is a rectangle in points of the take (402 × 874; 3 px a point) with a
margin, a Gaussian σ in pixels of the take, its stretch of the take, an
optional band it is cut to (`clip_y_pt`: what scrolls under an opaque bar is
hidden by the bar, and the blur neither writes nor reads the bar), and an
optional `ScrollTrack` (the content's scroll per picture, e.g. take5b's
`phone_rect_per_frame.csv`, matched row by row to the take's pictures).
Blurs are attached to the take, and `Take.picture()` only hands out blurred
pictures — so every lift, push-in and motion-blur subframe is made from them.
A blur is on every picture **on screen** at any instant of its stretch.
`verify()` measures what each blur leaves (the App Store tool's measure) and
refuses one that leaves more than 15 % of the content's detail, or that sits
on nothing.

```python
from promo.media.masks import Blur, ScrollTrack
fiche = Take("take2b")
fiche.set_masks([Blur("awa-number", (97.0, 183.0, 235.3, 193.3), sigma_px=14, margin_pt=4,
                      from_s=6.435, to_s=30.96)])
page = Take("take5b")
page.set_masks([Blur("salon-number", (38, 873.5, 220, 892.5), sigma_px=14, from_s=27.146,
                     clip_y_pt=(0, 740), track=ScrollTrack.from_csv(page.files.phone_rect_csv, page))])
page.masks.verify()        # [Coverage(label, index, time_s, box_px, detail_before, detail_after)]
page.masks.report()        # every picture a blur is on, and where — for the build record
```

Measured: Awa K.'s number keeps 7 % of its detail (175 → 13); the salon number
at most 11 % over the 84 pictures it is on.

### writer.py — frames + WAV → MP4

```python
from promo.media.writer import VideoWriter
with VideoWriter("out/30s/9x16.mp4", 1080, 1920, frames=896, audio="out/30s/mix.wav") as w:
    for frame in frames:          # H×W×4 uint8 RGBA (or bytes, skia.Image, skia.Surface), opaque
        w.write(frame)
```

libx264 High, yuv420p, CRF 16, preset slow, a key frame a second, BT.709 tags
and matrix (sRGB values carried as Rec. 709, as the App Store film); AAC-LC
48 kHz stereo 256 kb/s; `+faststart`. The frame count is exact (one too many
and one too few are refused), the WAV must be exactly `frames × 1600`
samples at 48 kHz, every frame must be opaque, and the file is written as
`*.partial.mp4` and renamed only once ffmpeg finished and the file holds that
many frames.

### probe.py — what a film is

```python
from promo.media import probe
report = probe.probe("film.mp4")     # JSON-able: file (sha256), container (boxes, faststart),
                                     # video (codec, profile, size, colour tags, frames counted,
                                     # CFR measured on every packet, key frames), audio, av
probe.check(report, probe.Expect(frames=896, width=1080, height=1920))   # [] or the differences
probe.assert_film("film.mp4", frames=896, width=1080, height=1920)       # raises ProbeError
probe.write_report(report, "film.json", probe.Expect(...))
```

`python -m promo.media.probe film.mp4 --frames 896 --width 1080 --height 1920`.

### sheets.py — looking at a written film

```python
from promo.media import sheets
sheets.pull_frames("film.mp4", [144, 160])     # {144: rgba, 160: rgba} — exactly those frames
sheets.save_frames("film.mp4", [144], "out/frames")
sheets.beat_sheet("film.mp4", "out/sheet.png") # every beat, labelled « f144 · 4.800 s · 3.2.0 »
sheets.contact_sheet([sheets.Tile(rgba, "label"), …], "sheet.png", columns=8, tile_width=200)
```

A frame is pulled by an accurate seek to half a frame before it, the film's
clock kept, and checked by the time ffmpeg reports for it.

### touches.py — touch-downs, and the film's indicators held to them

The App Store tool's rule (its README, « How a touch-down is found ») on the
same data, its own code imported (`edit.read_frames`, `find_bursts`,
`followed_path`) and its constants read (`rest_s`, `touch.tap_lead` = motion
`base` = 200 ms): each logged gesture is the first burst of changes after
`after_s`; a tap lands 200 ms before its first changed picture; a drag is
timed by the picture (followed, or the logged path back to Flutter's 18-pt
slop); a typed key has no touch point — its picture is the first change that
is more than a caret fragment (take1b's space: 87.548 s, not the caret's foot
at 85.333 s).

```python
from promo.media import touches
downs = touches.touch_downs("take1b")   # [TouchDown(take, gesture, kind, down_s, first_change_s, window_s, at_pt, how)]
print(touches.report(downs))
result = touches.cross_check(
    [touches.RenderedTouch("take1b", frame=144, src_s=10.672)], downs,
    required=[("take1b", "tap-arrive")])          # ok / problems / report()
```

`cross_check` holds every indicator to an observed touch-down of a tap or a
drag in the same take (within half a film frame at 1×), never on a typed key,
at most once per touch-down, on the 16th grid; `required` gestures must have
one. `python -m promo.media.touches take1b take2b take3 take5b` prints them:

| take | gesture | touch-down | first change |
|---|---|---|---|
| take1b | swipe-arrive (drag, followed) | 10.672 | 10.865 |
| take1b | tap-arrive / tap-libre / tap-service | 21.818 / 32.165 / 41.188 | +0.200 |
| take1b | tap-sans-numero / tap-nom / tap-creer | 49.440 / 57.930 / 130.265 | +0.200 |
| take1b | keys Y a o ␠ K . | — | 66.333 73.052 80.282 87.548 95.083 105.115 |
| take1b | scroll-form (drag, followed) | 120.300 | 120.400 |
| take2b | tap-client / scroll-fiche | 5.450 / 30.860 | 5.650 / 30.960 |
| take3 | tap-semaine / tap-mois | 6.097 / 17.252 | 6.297 / 17.452 |
| take5b | scroll-page (drag, not followed) | 25.887 | 26.173 |

## Tests

```
tool/promo_reel/build.sh test                          # or, with any venv that has the requirements:
cd tool/promo_reel && python -m unittest discover -s tests
```

`unittest`, no pytest. The media tests draw their own material — a VFR
« take » whose pictures carry their number as a barcode, at uneven times one
to 300 ticks apart, and a CFR film whose frames carry theirs — so a picture or
frame handed over in the wrong place is caught by its content. Tests on the
real takes run when the material is on the machine and are skipped otherwise.

---

Sections below are added by each builder (AUDIO, LOTTIE, FX, SCENES).
