# MyWeli Pro promo reel — « CARNET → DROP »

A code-only social promo for MyWeli Pro: 30 s and 15 s cuts, each in 9:16,
1:1 and 16:9. Every frame is drawn with skia and piped raw to ffmpeg; the
music is synthesised and is the clock; the app's pixels are real frames of
the recorded takes, in order. No editor, no templates, no stock.

The approved storyboard (2026-10-19) is the brief; `storyboard.yaml` is its
machine-readable form and the one source of the pipeline.

> **POSTING GATE (the owner, 2026-10-20).** The films end on « Sur l’App
> Store et Google Play » and « myweli.com ». **Post them only once BOTH the
> iOS and the Android MyWeli Pro apps are live in their stores.** Today the
> Android app is not (docs/BACKLOG.md B0.10: « nothing has been typed into
> Play Console yet »; LAUNCH.md: « Android last »): the end card's store line
> is not true yet, and nothing here checks it — the owner does, on the day.
> myweli.com is true today (the site serves 200 and is where salons choose
> their offer).

Design spec: [docs/design/pro-promo-reel.md](../../docs/design/pro-promo-reel.md)
— the owner's decisions, the honesty rules and how the code holds each one,
the storyboard bar by bar, the formats, the final run's verification, what is
not done and the review rounds.

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
tb.DEFAULT.grid(960, "beat")  # the 60 beats of the 30-s cut
```

Constants: `FPS`, `BPM`, `SAMPLE_RATE`, `FRAMES_PER_STEP`, `FRAMES_PER_BEAT`,
`FRAMES_PER_BAR`, `SAMPLES_PER_FRAME`. `TimeBase(fps, bpm, sample_rate)`
checks any other grid and refuses one that is not whole frames.

## storyboard.yaml — `promo/storyboard.py`

Exactly five top-level keys (plus `x-…` keys, which only hold YAML anchors):

- **meta** — `title`, `fps`, `bpm`, `key`, `sample_rate`. Strict: the time base
  must be the contract's (30 fps, 112.5 BPM, 48 kHz).
- **cuts** — `30s: {bars: 15, frames: 960}`, `15s: {bars: 8, frames: 512}`, each
  with a `description`. A cut is named by its length; `frames` must be
  `bars × 64`; a cut runs the whole bars its name holds plus at most ONE —
  the owner's outro bar (2026-10-19, « Add one bar »: the end card holds
  ≈ 4.3 s): a « 30s » cut is at most 15 bars (32.0 s), a « 15s » cut 8.
- **formats** — `9x16`, `1x1`, `16x9`:
  - `reference: true` on exactly ONE format (9:16): the window the scenes'
    camera W values are measured in (below, « The formats »);
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
    counter 120, counter_label 40, tagline 46, store 40, site 40 — the
    store and site lines at least 40, `MIN_READ_PX` —, credit 24), `lottie_centre`,
    `lottie_comp_width_px` (900), `end_mark_scale`, `end_mark_ink_y`,
    `end_tagline_cap_top_y` (checked: half the mark's height of clear space),
    `lift_x`, `lift_veil`, `tilt_axis`, `tilt_max_deg`, `scene_whip_axis`;
    and WHERE the scenes put what they place — `caption_align` (`centre` on
    `caption_centre_x`, or `left` from the column's edge with
    `caption_centre_x: null`), `caption_cap_top` `{hook, app}` (null: the
    block centred on `caption_centre_y`), `counter_baselines` `[label,
    figure]`, `lift_y` (the three places a lift lands: `card_on_floor`,
    `card_under_caption`, `tile_row`, each ONE of `top`/`centre_y`/`bottom`,
    inside the overlays zone's rows — and, optionally, its own columns `x:
    [x0, x1]` inside the safe area's and the overlays zone's, else `lift_x`:
    16:9's « Arrivé » card and Fiche tiles at the left column's full width),
    `hook_page` `{x, top, pivot, macro_to}`,
    `hook_scrim` `{rect, fade: [right, bottom]}` (it must hold the hook
    block's columns: white words sit on it), `map_credit` `{x, baseline,
    align}`.
  - Across formats, `px_per_pt`, `type_px`, `lottie_comp_width_px`,
    `end_mark_scale` and `screen_crop_top_pt` must be identical: one
    storyboard, re-laid out, never resized.
- **music** — **the cue ids have one source: the scores.** `music.scores`
  maps each cut to its score (`promo/audio/score_30s.yaml`, AUDIO's format,
  SCORE.md): the score IS the music, and its `cues[].id` are that cut's cue
  ids. The storyboard references the scores rather than embedding them
  (500 lines of music in the picture's file, and two copies to keep equal);
  `storyboard.py` reads each referenced score's cue ids, checks that the
  score is that cut's (`cut`, `bars`) and refuses a cue declared twice.
  `music.cues` may still declare ids inline (a list, or `cut → list`) — the
  tests' small storyboards do — but never one a score already declares.
- **scenes** — SCENES' section: a mapping `cut → list of scenes` (or a plain
  list). **A cue reference is the value of a key named `cue` (one id), each
  item of `cues`, or any string written `cue:<id>` (`cue:whip1+6`,
  `cue:riser1@end`), at any depth**: each must be a cue of THAT cut's score.
  **Per-format values**: any mapping in a scene may carry `formats:
  {<format id>: {key: value, …}}` — in that format those keys replace the
  mapping's own, every other format reads it as written
  (`Storyboard.cut_scenes(cut, fmt)` resolves them, `storyboard.for_format`;
  the Film reads its format's). ONE scene, re-laid out: the owner's round-5
  16:9 decisions are written so (`camera.formats.16x9.fill`, the 15-s
  form's `formats: {16x9: {curve: cut}}` and its W). Refused: a format id
  that is not a format, a value that is not a mapping; camera keys are held
  in time order in every format.

Every problem is reported at once, with its path:

```
storyboard.yaml: 2 problems:
  - meta.bpm: 120 is not the contract's 112.5 BPM (promo/timebase.py): the music is the clock, 16 frames a beat
  - scenes.30s[0].from: cue 'hook.stabx' is not in the cut's cues (known: air1.reverse, …)
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
sb.cuts["30s"].frames, sb.cuts["30s"].duration_s         # 960, Fraction(32, 1)
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
with VideoWriter("out/30s/9x16.mp4", 1080, 1920, frames=960, audio="out/30s/mix.wav") as w:
    for frame in frames:          # H×W×4 uint8 RGBA (or bytes, skia.Image, skia.Surface), opaque
        w.write(frame)
```

libx264 High@4.1 (x264 caps its references to the level; the VBV at 50 Mb/s,
62.5 Mb buffer — round 5's films were High@5.0, which ad / DOOH specs and
older 1080p decoders refuse; `probe.Expect.max_level` holds ≤ 4.1), yuv420p,
CRF 16, preset slow, a key frame a second, BT.709 tags
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
probe.check(report, probe.Expect(frames=960, width=1080, height=1920))   # [] or the differences
probe.assert_film("film.mp4", frames=960, width=1080, height=1920)       # raises ProbeError
probe.write_report(report, "film.json", probe.Expect(...))
```

`python -m promo.media.probe film.mp4 --frames 960 --width 1080 --height 1920`.

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

- AUDIO — the score, the synthesis, the mix and loudness, events.json:
  [promo/audio/README.md](promo/audio/README.md) (the score format: SCORE.md)
- LOTTIE — the Skia player of the Pro opening animation:
  [promo/lottie/README.md](promo/lottie/README.md)
- FX — the skia primitives (phone, type, counter, lifts, blur…):
  [promo/fx/README.md](promo/fx/README.md)

## SCENES — `promo/scenes/`, `promo/render.py`, `promo/verify.py`

```
python -m promo build  --cut 30s --format 9x16 --out DIR     # → DIR/30s-9x16/reel.mp4 (+ track.wav, events.json, meter.json, spectrogram.png, render.json)
python -m promo verify --cut 30s --format 9x16 --out DIR     # → DIR/30s-9x16/verify/ (report.txt/json, sheets, frames)
python -m promo.render --frames 0,144,552 --out DIR [--events DIR/30s-9x16/events.json]   # full-size stills, no MP4
build.sh                                                     # both, for every cut × format that is laid out
```

**What is built.** The 30-s cut (960 frames) and the 15-s cut (512 frames),
each in 9:16 (1080×1920), 1:1 (1080×1080) and 16:9 (1920×1080): six films,
`out/<cut>-<format>/`. `build --all` renders each cut's soundtrack ONCE and
shares it with its other formats (the same track.wav and events.json, byte
for byte; render.json records both sha256 and where they came from), then
renders the films one at a time. A cut whose scenes are emptied (`--set
scenes.15s=[]`) is « NOT BUILT » and named; asking for it alone fails —
nothing unbuilt is ever reported as verified.

### The formats — one storyboard, re-laid out (storyboard « 1:1 and 16:9 »)

The scenes say WHAT and WHEN; each format's `layout` says WHERE. No scene
carries a pixel position: the carnet's page (`hook_page`) and its scrim, the
caption placement, the counter's baselines, where each kind of lift lands
(`lift_y` + `lift_x`), the map credit — a scene that writes its own (the
page's `rest`/`pivot`, the macro's `focus_to`, the counter's baselines, the
credit's `x`/`baseline`) is refused. The cut frames, the events.json, the
soundtrack, the take pictures and their timing are the same in every format.

| | 9:16 (reference) | 1:1 | 16:9 |
|---|---|---|---|
| canvas · safe | 1080×1920 · x 120–900, y 270–1248 (platform) | 1080×1080 · x/y 54–1026 (EBU R95 5 %) | 1920×1080 · x 96–1824, y 54–1026 (EBU R95 5 %) |
| captions | band y 0–560, centred on x 540, cap top 330 (hook 300); 72 px | band y 0–358, centred on x 540, cap top 120 (hook 80); 72 px | no band: the left column x 96–1040, set from x 96, centred on y 440 (hook top-left, cap top 130); **88 px** (owner, 2026-10-19) |
| phone window (W on) | x 180–900, y 600–**1424** (y 600) — the owner's floor, app pixels only below 1248 | x 180–900, y **388**–1002 (y 388) — the band edge on the journal's chip row | x 1088–1808 (the bezel ending ON the graphics-safe edge, x 1824), y 54–**1026**, a 30-px top fade (y 84) — **the phone stands on the floor**: where W would leave the screen's bottom above y 1010, the band edge comes down instead |
| lifts | x 120–900 (780 px), over the veiled phone, ≤ y 1248 in flight too (Fatou B.'s, whose place is on the owner's floor, pops in place) | x 150–930 (780 px), over the veiled phone | beside the phone, no veil, no panel; out of the phone `under` the sentence (down, then across): the « Arrivé » card and the Fiche's tiles at the left column's full width, **x 96–1040 (944 px)** (OWNER-APPROVED 2026-10-20), « Total réalisé » x 284–1044 (760 px) |
| counter | centred, baselines 322 / 496 | centred, 120 / 284, its roll fading out by the band's edge (y 358) | from x 96, **144 / 48 px**, baselines 354 / 561; its punch holds the left edge |
| hook | page x 40–1040 from y 640, black to 520 → 640 | page x 120–960 from y 10, black to 400 → 500 (strike rows y ≈ 549–994) | page x 760–1960 on the right, black over x 0–820 → 1020; in the macro only behind the question (y 0–400 → 540) — the split, OWNER-APPROVED |
| tilts · push-in | rotX · about the phone's axis | rotX · about the phone's axis | yaw, ≤ 10° · about the screen's right edge (x 1824) |
| map credit « © OpenStreetMap contributors · © CARTO » | the band's foot, right-aligned to the screen's edge x 900, baseline 552 | the band's foot, right-aligned to the screen's edge x 900, baseline 346 | the left column's foot, right-aligned to x 1040, baseline 1016 |
| reveal · end card | Lottie (540, 680) · mark ink y 400–599, tagline cap top 712, the store line 808, myweli.com 872 | (540, 520) · 250–449, 560, 656, 720 | (960, 500) · 230–429, 540, 636, 700 |
| push about the floor | — (the band edge is fixed) | — | the lower journal and the form's end, **1.23×** (`camera.formats.16x9.fill`; OWNER-APPROVED 2026-10-20, below) |

**The camera re-frames by rule.** The W keys are measured in the reference
window (9:16, y 600–1424 since the owner's floor); each says what it keeps —
`top` (a point on the window's top edge: the 13:15 row hidden under the band
on the lower journal, the Fiche's blurred number, Revenus' title), `centre`
(the active form row in the window's middle), `floor` (Fatou B.'s card on
the floor) or `text_floor` (the lowest row where the app's TEXT is read: the
floor, or the format's text rectangle's bottom where that is higher — 9:16's
y 1248, above the owner's floor; the page's last line ≥ 8 px above it) — and
a format's own window moves it by the difference (`phone.keep_offset`: 0,
half or all of the windows' height difference, or of their text floors'),
never showing the screen's top edge where 9:16 did not (W ≥ 56). 9:16
(re-solved on the pictures for the owner's floor, 2026-10-19): Fatou B. 128,
the form rows 312.73 / 56 / 468.73 / 519.73, the page's end 427.32 (AIR 2:
449.66, the same place without the page's 40-px parallax — round 5 dropped
the phone 40 px on that cut; round 5's 352.46 kept the bar on the floor, both
its lines below y 1248); every `top` key unchanged (667, 521.67, 216, 124,
56). 1:1: 128 → 245.25 (the band edge on the chip row), 312.73 → 371.36,
427.32 → 446.30; 16:9: 128 → 62.12 (the whole screen down to Fatou B.'s
card, its top edge under the band's fade), 312.73 → 279.79, 56 → 56,
427.32 → 263.17. The
13:15 row stays under the floor at the card's framing and above the window's
top edge on the lower journal in all three (tests; verify (h) on every frame
of the scene, as in 9:16).

**16:9: the phone stands on the floor** (the owner's « Re-lay it »,
2026-10-19; `layout.phone_anchor: floor`, `fx.phone.Window.anchor_bottom`).
The band edge rests at y 84 (the window as tall as the frame allows, 84–1026,
942 px — round 3's ended at 1002); where camera W would lift the screen's
bottom above y 1010 (the slab's bottom on the floor, y 1026), the band edge
comes down instead and hides the rows above W: on the lower journal it stands
at y 639, the old 13:15 row under it, the phone on the floor (round 3: hung
from the top, its bottom at y 470 over an empty half frame). The band edge is
keyed like W (`PhoneScene.band`: each W key's highest edge that leaves no
floating screen, moved on the W key's curve — the screen's bottom moves
linearly between two keys that never float, so it never floats between). A
declared dissolve shows each picture through the window of its own end, as
it does with W (round 5: one shared window, the fields in place as in 9:16
and 1:1, put « Créer le rendez-vous », tapped on the dissolve's last frame,
under the floor, its disc on nothing); in 16:9 the 15-s form's skip is now
a declared HARD CUT, framed by the journal's window (below, « The 15-s
16:9 form »). Everything that asks where the phone is — touches, lifts, the
hidden row, verify's regions — reads the frame's own window
(`PhoneScene.win(t)`; render.json records `window_top`). A push-in where the
phone stands on the floor scales about the FLOOR (y 1026; `anchor_y: top`):
the slab's bottom stays on it and everything above moves up, the old 13:15
row further under the band (round 5: about the band edge the « rempli. »
push sank the slab to y ≈ 1071, Koffi A.'s « Confirmé » cut by the floor —
the renderer refuses a push that sinks a slab standing on the floor). The
in-phone whip is exposed over 1.5 frames here (`ANCHORED_WHIP_SHUTTER`): the
band edge comes down with it, so the picture travels about half the camera's
way, and the old row must still cross the window inside ≥ 80 px of blur.

**16:9: the push about the floor** (`camera.fill`, written under
`camera.formats.16x9`; OWNER-APPROVED 2026-10-20, « 16:9 POLISH » (1)). On
the lower journal and the form's end the camera W 667 brings the band edge
down to y 639: the phone shows its bottom 387 px, the upper right empty. The
camera pushes in ABOUT THE FLOOR with the window growing with the phone: the
slab scales about (x 1824, y 1026) — its right edge on the safe edge, its
bottom on the floor — and the band edge rises by the same factor
(`PhoneScene.edge_of`: `floor − (floor − band) × fill`), so pt W stays on
the edge it shows on and the old 13:15 row stays under the band (it rises
with the phone). The screen is LAID OUT from the keyed band edge and SHOWN
from the risen one (`fx.phone.Window.clip_top` / `edge`: the fade and the
clip; the first build laid the window at the risen edge and the pose scaled
it again — the slab floated at y ≈ 912; test_review5 now holds every pushed
frame's slab bottom ON the floor, ± 0.5 px). Eased on the grid: 30 s
5.1.2 → 5.2.2 (onto the « Libre » tap), back 5.2.3 → 5.4.0 under the glide to
the form; 7.2.0 → 7.3.0 (from the « Créer » tap), held through the snackbar,
the « rempli. » push on top (about the floor too: a zoom on a fill must
scale about the floor, else refused); 15 s 3.3.2 → 3.4.2 (the « Libre »
tap's form), held to the whip. **1.23×, not the owner's ~1.3–1.5×**: beside
the left column the slab grows towards the captions, and the column's lines
reach x 878 (« Un créneau libre ? ») and x 1024 (« Créneau ~~libre~~
rempli. », its « p » to y 505 as it rises in). At 1.3× the slab's left edge
reaches x 846 — under « libre ? », 20 px below its ink at the hold and over
it as the push recedes on the glide to the form — and on the form's end its
top (the band's fade from y 493) runs into « rempli. »; 1.23× is the largest
that keeps every caption ≥ 12 px clear of the phone on every frame
(`CAPTION_PHONE_CLEAR_PX`; measured: 15 px, « rempli. » rising, 30 s f448
and 15 s f240). The phone's window grows from 387 to 476 px tall (top y 639
→ 550) and from 752 to 925 px wide (1 033 with the « rempli. » push on top: from x 791);
the upper right above y 520 stays stage. The renderer refuses a fill where
the phone does not stand on the floor (9:16, 1:1: their band edge is the
frame's), a fill under 1, and a film on which any caption comes within the
clearance (`Film.crowded_captions`, before a frame is drawn); verify (g)
re-reads it from render.json (`phone`, per frame) — at the owner's 1.3× it
fails on 30-s f288 (« libre ? ») and from f448 (« rempli. »).

**Order of work** (`render.build_one`): the soundtrack FIRST
(`promo.audio.build_cut` on the cut's score, master limited to −1.5 dBTP so
the AAC stays under −1.0), then the clock is READ from the events.json it
wrote (`scenes.Clock`: every cue's frame is where its sound landed, checked
against the grid), then every frame is drawn and piped to
`media.writer.VideoWriter` with track.wav muxed; `render.json` keeps what each
frame shows, and the renderer's own frame on every beat goes to
`verify/renderer/`.

**storyboard.yaml `scenes.30s`** holds every row of the storyboard (rows
1–24) as data, so a variant is a `--set`, never a code change: per scene its
span (`from`/`to`), stage, source take and masks, the film → take
`timeline`, camera keys (W, zoom with its anchor, slam/tilt, fall, parallax),
touches, lifts, stacked tiles, the counter, the map credit, hidden rows, and
its captions word by word. The header comment of the section documents the
grammar; the times a scene writes are cue ids or grid positions, the take
times are `{named: t}` (a picture written to the ms), `{touch: gesture}`
(the measured touch-down), `{key: …}` or instants inside a held picture.

**`scenes.15s`** lays out « The 15 s cut » (BARS 1–7 and the owner's outro
bar 8) the same way, timed by the 15-s score's own events.json (the same cue
ids wherever the picture event is the same — `python -m promo.audio --cut
15s`). It reuses the 30-s scenes' code with no change beyond data: the AIR,
« Revenus », the reveal and the end card are the 30-s blocks themselves
through YAML anchors and merges (`- <<: *end_card` + its `rows`; Revenus
with `to`, `counter.exit: null`, no lift, no sentence), and the journal
shares the 30-s's hidden-row rule and « Arrivé » lift (`*hidden_1315`,
`<<: *arrive_card`). `storyboard.py` loads every use as its own copy, so a
`--set` on one cut never changes the other. What the 15-s needed that the
code did not have: a carnet without a macro cut or a sink (both optional
now) and the DECLARED DISSOLVE (`sources.Timeline`, below).

| 15-s scene | frames | what |
|---|---|---|
| `hook` (carnet) | f0–47 | the code-drawn page, push under way at f0, the entry inking f0–24; « Votre » f0 « carnet » f8 / « déborde ? » f16, held to f47; three strikes with punches on the log hits f24 / f32 / f40; no strike words, no macro, no sink |
| `air1` | f48–63 | the 30-s AIR, « Respirez. » |
| `journal` (take1b) | f64–255 | the hard cut onto W 257 (no slam); the swipe at 1.11× (open f80), the pane held at 1×, the seamless cut and the tap on f88, the save at 0.965× (« Arrivé » f144), the lift f144–159; the vertical whip f160; the « Libre » tap f168 (released by f173), the form's push at 1× (rest f184); the declared dissolve f193–196 to the filled form (16:9: a declared hard cut on f193, framed at W 667); « Créer » f196 at 0.986×; back to W 667 f204–216 (16:9: already there); the snackbar f232, the push-in to 2.0 px/pt f232–252; 16:9: the push about the floor f168–184, held; « Une cliente » f64 « arrive ? » f72 / « Glissez, » f80 « appuyez. » f88; « Créneau » f160 « libre » f168, struck f236, « rempli. » f240 |
| `revenus` (N1) | f256–319 | the horizontal whip in; « Mois » f272, the label f280, the counter lands on N1's « 77 000 FCFA » on f292 (the app's wait at 0.995×, as the 30-s), alone to the cut |
| `reveal` | f320–375 | the Lottie, the 30-s retime on the 15-s cues |
| `end` | f376–511 | the 30-s card: the mark settles f384, the tagline's one reveal f379–384, « Sur l’App Store et Google Play » f400, « myweli.com » f432, the underline f448, the punch f480 |

**The declared dissolve** (`{at, dissolve: <take time>, until, curve, cite}`
in a timeline): the picture on screen at `at` blends into the take's
picture at `dissolve` by `until`, on the app's base easeInOut — the App
Store film's own rule (tool/app_store_preview/README.md, « One declared
dissolve inside a scene »): the only way to skip footage in which the
screen changes. Each picture is drawn through the camera of its own end of
the dissolve (the W keys at `at` and `until`). Where the band edge is fixed
(9:16, 1:1) the screens blend inside ONE slab whose outline moves with the
blend: the picture it reaches underneath, the one it leaves over it at 1 − u
(`Phone.draw(screens=…)`) — f194 is (1 − u) × f193 + u × f196 within 2 levels
wherever the first picture shows, the second alone below it (round 5: two
whole stages cross-faded drew a second, translucent bezel arc across « Total
/ Créer le rendez-vous »). `curve: cut` makes it a DECLARED HARD CUT — the
picture it reaches from its first frame, the same skip, the same
declaration; the plan lists it as `cut (declared, in the phone)` and verify
(b) holds it to a cut's rule (the picture changes ≥ 2 levels). **The 15-s
16:9 form** (OWNER-APPROVED 2026-10-20, « 16:9 POLISH » (3)): round 5's
3-frame blend of two windows ghosted the fields, and its band edge then came
down 260 px over the still form on f204–216 (W 521.67 → 667, the phone on
the floor: only the edge moves — a curtain). Now `formats: {16x9: {curve:
cut}}`: a hard cut on f193; and the filled form is framed at once by the
journal's own window (W 667 on both sides of the cut, the push about the
floor held), so NOTHING moves from f184 to the snackbar's push (f232) — no
curtain (test_round5 holds one edge and one W over f184–231). What it costs,
16:9 only: the fields « kept in place » across the skip (9:16, 1:1) are gone
— a cut needs none — and the filled form shows its end (« Note », « Total
5 000 FCFA », « Créer le rendez-vous »), not « Client sans numéro » ticked
nor « Yao K. » typed: those are above W 667 (the name field 598–654 pt), and
any framing that showed them would need the band edge to come down over the
still form before the journal's return (the old 13:15 row) — the curtain.
The name is seen 0.8 s later on the journal's new card « 14:45 Yao K. ».
Refused: a dissolve without `cite`, one
that goes back in the take or to the same picture, one without a segment
before it or an `until`, and a touch disc or ripple on any of its frames.
render.json records it (`dissolve`: pictures, blend, both W) and the plan
lists it as a transition (`dissolve (declared)`), and in the honesty list.

| scene kind | module | rows |
|---|---|---|
| `carnet`, `air` | `scenes/carnet.py` | 1–5: the code-drawn carnet (push-in under way at f0, macro cut, strikes with punches, push + sink, grain — macro and sink optional: the 15-s hook has neither), the AIR |
| `phone` | `scenes/phone.py` | 6–22: take1b, take2b, N1, take5b in the 2.5D slab through the camera window |
| `lottie`, `end_card` | `scenes/lottie.py` | 23–24: the Pro opening Lottie retimed, the mark settling, the tagline, « Sur l’App Store et Google Play », « myweli.com », the outro (the underline, the mark's punch) |
| — | `scenes/film.py` | the cut end to end, the horizontal whip between scenes, captions, the per-frame record |

**Rules the renderer enforces** (each a refusal with its storyboard path):
a derived take rate faster than 1× on anything but a drag (the gesture ramps
1.11×, 2.74×, 1.08×; never past 3×); a touch disc whose YAML frame is not
where the timeline puts the measured touch-down, or whose tone is not what
the ground under the finger asks for; a counter that does not land on the
frame the app first shows its figure, that reads that figure on any frame
before it, or that reads a value above it on any frame (the roll eases on
fastOutSlowIn over a span `overrun` frames longer than tick → landing and
snaps home on the landing frame, with its punch; the renderer picks the
smallest overrun that keeps every earlier frame a quarter digit short — 4
frames for 0 → 77 000 over f535–f548, so f547 reads « 76 988 »); a caption
line over 771 px; two caption lines receiving words on the same frame (one
arrival at a time); an underline that touches any caption's ink while both
show (2 px clear; it sits under its line's descenders); a mark punch that
brings the mark's ink nearer the tagline than half its height (a test
builds the 1.2× variant and watches it refused); hook ink the viewer cannot
see — a strike (its 4 frames and its punch), the entry being written or
the margin note off the canvas, outside an EBU graphics-safe area (1:1,
16:9; 9:16's platform rectangle is the TEXT area and its approved page lies
at y ≈ 700–1700: reported in (g), not refused), or more than 15 % under the
scrim on average (`CarnetScene.ink_places`); a `transition` other than
`whip` or `continuous`; a caption that still carries the retired `reading:`
marker; camera keys not in time
order (also refused by `storyboard.py`, with both keys' frames — the
renderer sorts nothing); scenes that do not run end to end; a push about the
floor (`camera.fill`) where the phone does not stand on the floor, under 1,
or with a zoom on it about another anchor than the floor; a film on which a
caption comes within 12 px of the phone as posed (`Film.crowded_captions`,
before a frame is drawn). `storyboard.py` also refuses the store or site
line (`type_px.store`, `type_px.site`) under 40 px, a `formats:` override for
a format that does not exist (or that is not a mapping), a lift place's own
columns (`lift_y.<place>.x`) outside the safe area's or the overlays zone's,
and a cut more than one bar past its name.

**A line that waits for its last word** may ask `recentre: N`: centred
on the words it shows while it waits, it glides over N frames to make room
for each next word, which then rises in on its own frame, in its place —
« Créneau libre » … « rempli. » (2.67 s in the 15-s cut; 136 px left of
centre in round 3). The finished line is exactly the approved one; a
left-aligned line (16:9) never moves.

**A continuous handoff is not a cut.** The end card starts where the reveal
leaves the mark (comp 72, the same place): `transition: {kind:
continuous}`. The plan lists it as `continuous`, never as a join; verify (b)
holds every cut to a picture change and every continuous handoff to none.

**Touches released at once.** A tap the log says was not held may carry
`release_by`: its disc and ripple are gone by that frame. The « Libre » tap
(f280) is gone by f285, before the form pushes in under it on f286.

**The Fiche tiles** lift onto a plain panel in the app's `background` token
(#F6F7F9, colors.dart:34 — the scaffold the tiles sit on in the app) that
GROWS WITH THE LIFTS (`fx.stack.Stack.backdrop_pieces`), one piece per lifted
tile: its card where it is now and its place on the phone, 24 px around, cut
back to the place of any tile still waiting (never over it); and beside it
the strip no card ever reaches — between its piece at rest and the next
tile's place — FADING in place with that tile's own 6-frame pop. So « 0
Absences », never lifted, goes under « 17 000 FCFA » as that card grows over
it (the panel never more than its 24-px pad ahead of the card) and what the
card never reaches fades out with its pop, f480–f485 (round 3: blanked in ONE
frame on f480; round 4: wiped 80 px ahead of the card in 9:16, and in 1:1
pulled back on f480 and showed again — `reach` took its pace from the newest
lift). Nothing pulls back: each piece only grows, a cut stays put while its
tile waits, a strip only grows more opaque (tests/test_round5.py renders the
Fiche in 9:16 AND 1:1 geometry). The pieces sit on whole pixels (snapped
outward, inward where they face a waiting tile) and a strip overlaps its piece
by a pixel (round 5: two pieces meeting on a fractional edge let a 1-px column
of « 0 Absences » through); a strip runs over the tiles' own row only (round
5: over its piece's padded height, a pale rectangle across the next card's
border); and the panel stops 2 px above the next row on the phone, «
PROCHAIN RENDEZ-VOUS »'s cap line (`backdrop.stop_pt`, 407 pt — round 5's
pad sliced the label in 1:1 and hid it in 9:16). Every tile still to lift stays in its place,
veiled, with its texture, until its own beat (f472 / f480 / f488). The row is
centred on the tiles' own row (9:16 y 815, 1:1 y 588), so they lift out in
place.

**Motion blur.** Camera moves blur by subframe accumulation in linear light
(`fx.blur`), only inside the phone window's rows, with enough subframes that
copies sit ≤ 2 px apart; the take's picture is held for the frame (a fast UI
move the take has only a few pictures of would otherwise show as double
images). Where the storyboard asks for the take's own frames to blend (the
swipe, the 2.74× form scroll) each subframe shows its own take picture.
Masks are on the take, so every subframe is already blurred.

### Verification — `promo/verify.py`

All automated, on the written MP4 wherever possible, into `verify/`: (a) the
renderer's frame on every beat (`beats.png`: 60 stills in the 30-s cut, 32 in
the 15-s) and the MP4's beats compared with them (PSNR), (b) every cut, whip
and declared dissolve ± 1 frame from the MP4 (`transitions.png`, labels
wrapped to their cell), plus full-size frames in `frames/` — derived from
render.json (`verify.look_frames`: every transition at T−1, T, T+1 and its
end, every visual event and three frames on, but the take's own picture
changes and caption words; the first and last frames), never a frame list
typed per cut — each join held to its name (`join_problems`: a hard cut
changes the picture, mean |ΔL| from T−1 to T ≥ 2 levels — the films' cuts
change by 8–244 —, a `continuous` handoff does not, and is reported apart,
never counted as a join), (c) every touch-down drawn held to the gesture logs
(`media.touches.cross_check`) and its tone re-measured, (d) BS.1770-4 on the
MP4's decoded AAC (−14 ± 0.5 LUFS, ≤ −1.0 dBTP; ffmpeg's ebur128 as a second
opinion), `spectrogram.png` with bar ticks, and each AIR beat at least 7 LU
under the groove (K-weighted, the cut's drop/groove sections together) on the
WAV master AND on the MP4 (a pass never rests on the codec), and the cut's
last hit ringing out (`outro_tail`: ≥ 20 dB down 22 frames after it, the
last 100 ms ≥ 30 dB under it — the master's 60-ms end fade never chops a
loud tail), all in one verdict (`audio_verdict`, tested measure by
measure), (e)
ffprobe + assertions (`probe.json`; H.264 High at level ≤ 4.1), (f) A/V sync: each click and key's
onset in the MP4 audio against the frame its disc or character first
appears in the MP4's PIXELS (`promo/pixels.py`: the disc's own ring; the
key's box looking like the take's picture with the character), (g) the INK
on MP4 frames — each caption whole, the counter on EVERY frame from its
label's switch through the roll to three frames after it lands (its faded
rolling digits too: ink `faint`, L < 185), every lift, the credit — inside
the format's text area (9:16 the platform's;
1:1 and 16:9 EBU R95 graphics-safe), the captions laid in the caption column
inside it (the AIR's word is centred on the canvas, the end card's lines on
the mark: not column captions; each box says which, `column`), each ink
region kept clear of the phone as it is posed on that frame
(`verify.clear_of_phone`: in 16:9 the phone stands beside the captions, the
counter and the lifts) and the hook's words measured on their scrim
(`verify.on_its_ground`: the lit page's paper fibres beside them pass for
white ink), plus every box render.json records on every frame (a touch disc on the
app's pixels: the phone window's rows across the safe area's columns,
`verify.app_area` — in 9:16 down to the owner's floor; every lift, in flight
too, inside the text rectangle — round 5's « Arrivé » rise and settle crossed
y 1248, a magnified overlay is not the phone's picture; the app's own text the
film keeps readable, `app text` — the page's « Aperçu … / Réserver (après la
mise en ligne) », and since round 6 « Créer le rendez-vous » from the form's
rest to the pop and the snackbar « Rendez-vous créé » to the cut, which 16:9's
push about the floor must never crop — inside it AND wholly in the window,
shown ≥ 0.99; no lift box over a caption's ink on any frame,
`lifts_over_captions` — round 5's 16:9 « Total réalisé » crossed
« rendez-vous » in flight; no caption's ink within 12 px of the phone as
posed, `captions_over_phone` — the record's `phone`, per frame: the owner's
« never cropping … a caption »; every touch disc whole in the window on
every frame the phone is pushed, `touches_cropped` — « never cropping a
touch »; a touch-down cropped on an unpushed frame is reported, not failed:
the Revenus « Mois » tap (shown 0.58–0.69), whose disc's top has sat in the
band's fade since round 1 — the title « Revenus » is kept under the band and
lies 16 pt above the disc, under the fade's 17–22 pt, so no framing shows
both whole), and the
hook's animated ink (the plan's `hook_ink`) seen: inside the canvas, inside
an EBU graphics-safe area, off the scrim, and each strike read off the MP4
on its last frame (`pixels.line_contrast`: the paper beside the stroke ≥ 40
levels lighter than the stroke — 144–191 measured; off the frame fails),
(h) honesty: every generated element
with its source (`honesty.txt`), every blur measured on every picture the
film uses — every take that declares a blur is measured (`blurs_checked`;
the 15-s cut declares none: take1b shows only the « Téléphone du client »
placeholder and N1 no number, which the report says, never as « measured »),
every dissolve declared and going forward (`dissolve_problems`, re-read from
render.json; a declared hard cut too), the map credit — the app's own
« © OpenStreetMap contributors · © CARTO » — WHOLE from its first whole frame
until the map has dimmed out, AIR 2's last frame f767 (`credit_problems`,
on the plan's `credits` spans; round 5 faded it with the falling phone:
f752–767 not whole in all three 30-s films), the old 13:15 row on EVERY frame of its scene — the whip, the
form's push and pop included (`verify.HiddenRow`): its blocks that identify
it (found on no picture of the scene at another height — the new booking is
the same client, so « Yao K. », « 1 prestation » and « Confirmé » are on its
row too; only the old booking's « 13:15 / 13:45 » remain, 1 block of 6)
searched over the WHOLE window in the MP4's pixels — the lifted cards' boxes
left out (round 6: the 944-px « Arrivé » lift magnifies Fatou B.'s card
1.42×, and its small « 13:15 », her end time, is then the old row's large
« 13:15 » at the same pixel size — the search « found the row » in the
flying card, 30-s f233 / f250 and 15-s f145 / f156, Fatou B.'s card in the
MP4; a lift is a known real card, checked at its SOURCE instead: the
renderer refuses a lift or tile whose rect touches a hidden row) —, visible = share found ×
the window's alpha where found ≤ 5 %; all its blocks at the renderer's place
≤ 25 %; and outside the whip, the share of its place the window shows × the
share of it the take's picture shows there ≤ 5 %; inside the whip, a frame
whose shutter shows its place carries it ≥ 80 px (`WHIP_BLUR_MIN_PX`; the
record's `shutter_alpha` and `blur_px` — round 5's first whip frame moved it
37–72 px through the floor fade; the whip is now on the app's base easeInOut:
at least 110 px in 9:16, 86 in 1:1, 90 in 16:9 at its 1.5-frame shutter, as verify reads them) — the speed of every wait
and ramp, (i) reading: everything on screen together, per arrival window
(`reading_windows`: the characters arriving in a window that must be read
before it closes), ≤ 17 cps, the end card like the rest (its own window is
reported: 74 characters f827→f960 = 16.7 cps — the owner's « Sur l’App
Store et Google Play » and « myweli.com », 2026-10-20; round 5's card was 60
characters, 13.5 cps); never two lines receiving
words on one frame; the longest stretch without a visual event (≤ 2 s). Not
counted as reading: the map credit (attribution), the lifted cards (the
app's own pixels), the counter's rolling digits (its start « 0 », labels and
landed figure are).

Across the formats: every built format of a cut must hold ONE soundtrack —
track.wav and events.json byte for byte (`verify.same_soundtrack`, a PASS /
FAIL line after the films; a format re-laid out is never re-timed).

Statuses: PASS or FAIL. `report.txt` leads with the film's status;
`python -m promo verify` exits 0 (PASS) or 1, and so does `build.sh`. (Round
2's OWNER DECISION PENDING is retired: the owner decided the end card,
2026-10-19 — one more bar.)

### Decisions made against the storyboard's text, and why

**OWNER-APPROVED departures (the owner's decisions after round 5,
2026-10-20 — architecture contract, « Owner decisions after round 5 » and
« Owner decision — end card stores + site »):**

- **OWNER-APPROVED 2026-10-20 — the end card: the stores and the site**
  (« Both stores, post later »). ONE version, in order: the mark · « Plus de
  clients, moins de gestion. » (the underline and the mark's punch kept) ·
  « Sur l’App Store et Google Play » (replaces « Disponible sur l’App
  Store ») · « myweli.com », last. Each line arrives ALONE on its own
  beat-grid cue — the tagline whole on `end.mark` (14.1.0, f832; its mask
  from f827), the stores on `end.store` (14.2.0, f848), the site on the new
  `end.site` (14.4.0, f880: the bar's step-12 log made the cue, a soft glint
  a fifth under the store's) — and the 15-s on its own (f384, f400, f432),
  both scores moved to match. The store line Inter Medium 40 px #4A4A4A, cap
  top 96 px under the tagline's; « myweli.com » Inter Medium 40 px in the
  ink #1A1A1A, 64 px under it (the last line, the address, read first after
  the tagline); both ≥ 40 px (`MIN_READ_PX`), centred on the mark's axis,
  inside every format's safe area (verify (g)). Reading, verify (i): 34 + 30
  + 10 = 74 characters f827→f960 = **16.7 cps** (≤ 17; 15 s f379→f512, the
  same). **POSTING GATE** (top of this file): posted only once BOTH the iOS
  and the Android Pro apps are live in their stores.
- **OWNER-APPROVED 2026-10-20 — 9:16 swipe** (« Keep it »): the « Arrivé »
  swipe plays at y ≈ 1290–1410, app pixels below the text-safe line (the
  owner checks it on a phone under a Reels/TikTok overlay); the touch
  ripples are app-area marks, not text (verify (g) holds them to the app's
  pixels, `app_area`).
- **OWNER-APPROVED 2026-10-20 — 9:16 hang** (« Accept it »): on the
  lower-journal and form-end shots the phone stops at y ≈ 985, forced by
  hiding the old 13:15 row. **1:1 hang** (« Keep as is »): the phone hangs
  under the band on the lower journal.
- **OWNER-APPROVED 2026-10-20 — 16:9 polish**, all three: (1) the push about
  the floor on the lower journal and the form's end — at **1.23×**, the most
  the left column's captions allow (« 16:9: the push about the floor »,
  above: the owner's ~1.3–1.5× would put the slab under « libre ? » and into
  « rempli. »), the 13:15 row and every privacy check re-run on the new
  framing; (2) the « Arrivé » lift and the Fiche's tiles at the left
  column's full width, x 96–1040 — the card 944 px, 1.42× the card in the
  phone (round 5: 760 px, 1.15×), « Arrivé » read at 50 %; 16:9 lifts are
  exempt from « same pixel size everywhere »; « Total réalisé » keeps 760 px
  (at 944 it would be 508 px tall: under the two-line sentence, ink to
  y ≈ 523, and inside the safe floor, 1026, there are 427); (3) the 15-s
  form's hard cut on f193 instead of the 3-frame dissolve, and no band-edge
  curtain after it — solved by framing the filled form at once in the
  journal's window (« The declared dissolve », above, with what that costs).
- **OWNER-APPROVED 2026-10-20 — the map credit** (attribution correctness,
  the owner's call): the app's own wording, « © OpenStreetMap contributors ·
  © CARTO » (`cartoCredits`, mobile/lib/widgets/common/carto_basemap_layer.dart:116,
  joined « · »; round 5: « © OpenStreetMap, © CARTO »), and on screen until
  the map has dimmed out — WHOLE from its first whole frame to AIR 2's last,
  f767, in every format (round 5 faded it with the falling phone, f752–763);
  verify (h) `credit_problems`.

**OWNER-APPROVED departures (the owner's decisions after the six-film review,
2026-10-19 — architecture contract, « Owner decisions after the six-film
review »):**

- **OWNER-APPROVED 2026-10-19 — the end card's underline and the mark's
  1.06× punch** (« Keep both »): on the outro's downbeat the hook's strike
  stroke underlines « moins de gestion. », and on the last log the mark
  punches 1.06× (3 frames out, 8 back), moved and scaled only. Neither is in
  the approved storyboard (its honesty section: the mark « only moved and
  scaled »); both meet the ≤ 2-s pattern-interrupt rule over the outro bar
  (below, « The end card »).
- **OWNER-APPROVED 2026-10-19 — the 16:9 split hook** (« Keep the split »):
  the portrait carnet page on the frame's right half, the words on black at
  the left — not the storyboard's « page lies landscape across the frame »
  (below, « 16:9 hook »).
- **The owner's 9:16 floor** (« Extend to ~y 1450 »): in both 9:16 cuts the
  phone window runs to **y 1424** — ≈ 1450, set by the pictures (take1b
  10.000): with Fatou B.'s card bottom (582 pt) just above the floor (11 px)
  and the old 13:15 row's text (612.7 pt) 20 px under the floor fade, the
  band edge falls between « Ma journée » (ink ≤ 104.3 pt, wholly under the
  opaque band from 105.7) and « Aujourd’hui » (136 pt): W 128. At 1450 the
  title would sit half-faded in the band's fade (W 111.9), or the 13:15 text
  would show in the floor fade (W 130). App pixels only below y 1248: the
  captions, the counter and the lifts stay in the platform rectangle, in
  flight too: the « Arrivé » card's place (Fatou B.'s card, y ≈ 1284–1413)
  lies below it, so its lift POPS IN PLACE where it lands (bottom 1236; scale
  0.96 → 1 and a fade over the 6-frame pop, the reverse over the 5-frame
  settle — round 5 rose 200 px from the card and crossed 1248 on 6 frames a
  cut), its place on the phone emptied while it is up (a plain `background`
  panel under the veil — round 5's veiled original read as a second
  booking); the touch discs ride the app's pixels (`verify.app_area`). The
  page's end keeps the app's own qualifier, the owner-preview bar, inside the
  rectangle (W 427.32, `keep: text_floor` — round 5's 352.46 put both its
  lines on the floor, below 1248); the slab then stands ≈ 48 px over the
  floor at the page's end. The map credit, whose floor became the phone's, moved to
  the band's foot like 1:1's. Every camera key that keeps the floor or the
  centre was re-solved (« The camera re-frames by rule »); every privacy check
  re-run on the new framing.
- **The owner's 16:9 re-lay** (« Re-lay it »): the phone stands on the floor
  (its slab's bottom on y 1026 whenever the screen ends inside the window,
  the band edge coming down over the rows above W — « 16:9: the phone stands
  on the floor »), a taller window (84–1026, 942 px; round 3: 918), larger
  captions — the column's words at 88 px (72 × 1.22: the longest line,
  « Chaque rendez-vous », 942 px in the 944-px column; `type_note`), the
  counter at 144 px with a 48-px label, centred on the column's y 440 — and
  the lifts and tiles on their rows beside the phone, under the larger
  caption. The hook's words (96 px), the end card's lockup and the credit
  keep the storyboard's sizes (`storyboard.py` refuses any other difference
  from the reference, and any without its `type_note`).

The 1:1 and 16:9 formats (« 1:1 and 16:9 »):

- **No photos** (the owner's decision): SLOT « FAUTEUIL » (16:9, f640–751, a
  card at x 96–620, y 560–1026 under the caption) stays EMPTY — the no-photo
  layout is the caption alone, where every 16:9 caption sits (the left
  column, centred on y 440), the slot's area the stage's pattern; the zone
  stays declared (`slot_card`) and unused. SLOT « COMPTOIR » was never in
  the cuts' scenes (the code-drawn page plays).
- **1:1 lifts are 780 px wide** (x 150–930), not grown to x 54–1026: « the
  lifts keep the same pixel sizes everywhere » (the section's first rule);
  the 54–1026 span is where they MAY go. 16:9 kept the section's 760 px,
  moved 16 px left with the phone (x 284–1044; the section's 300–1060) — the
  « Total réalisé » card still does; the « Arrivé » card and the Fiche's
  tiles take the left column's full width since the owner's round 5
  (above).
- **1:1 hook block to y 420**, not the band's 300: three 96-px lines
  (« Rayé. / Raturé. / Recopié. ») cannot fit in 54–300 at their 120-px
  pitch — the third's ink reaches y 414; the stage's black covers the page to
  y 400 and is gone by 500 (`hook_scrim`).
- **1:1 hook page 840 px wide** (x 120–960 from y 10), not the square
  filled edge to edge: at 1000 px its third strike row was drawn below the
  frame (round 3, y 1117–1159 — its log hit, whoosh and punch played with no
  strike on screen); now the three strike rows land at y ≈ 549, 734 and
  966–999 and the macro's margin note at x ≈ 96–190, all inside
  graphics-safe; the page's sides show the dark stage (≈ 60 px each side at
  the push), a sheet on a desk.
- **1:1 band edge on the journal's chip row** (round 4's leftover): the
  window starts at y 388 (band opaque to 358), not the section's 330 — on
  Fatou B.'s framing the floor rule put the band's fade on the week's dates
  (186–226 pt, half-faded digits); now W 245.25 puts the dates and their dots
  wholly under the opaque band and the band edge on the chips (233–267 pt), as
  the 9:16 band once did. The window shows ≈ 343 pt (was 375); the captions'
  cap top moves to 120 and the counter to 120 / 284, the band's middle.
- **1:1 counter**: label 120, figure 284 (round 3: 110 / 284 on a band
  ending at 300 — the figure 17 px over the phone's bezel): the figure ends
  72 px over the band's fade, the label's ink stays at y ≥ 81 as it switches
  (safe edge 54); the rolling band fades out by the band's edge
  (`Odometer.draw(floor=…)`; the clip stays as a backstop).
- **The map credit inside the safe area.** 1:1's floor (y 1026–1080) and
  16:9's « under the phone » (y > 1026, the phone's own floor fade) leave no
  room for a 24-px line inside EBU graphics-safe, and 9:16's floor is the
  phone's since the owner's floor: 9:16 and 1:1 put it at the band's foot,
  its INK ending on the screen's right edge x 900, over the map it credits
  (baselines 552 and 346; round 3 ended 1:1's on x 1026, over the bezel's
  corner, where it read as part of the caption block), 16:9 at the left
  column's foot, ending on x 1040 by the phone's lower-left corner (baseline
  1016).
- **16:9 hook** (OWNER-APPROVED 2026-10-19, « Keep the split »): the page lies across the frame's RIGHT (x 760–1960, its
  strike rows in view) with the words top-left on black (`hook_scrim` x
  0–820, fading out by 1020) — the section's « page across the frame,
  captions top-left » with the white words never on scribbles. In the macro
  (f32–63) the black stands only behind the question (`hook_scrim.macro`:
  x 0–820, y 0–400, gone by 540): round 3's full-height scrim hid the f48
  margin note (98 % of it under the black), so the pen scratch played on
  nothing.
- **16:9 captions set from the column's left edge** (x 96, the ink on the
  edge: a first glyph overhanging its origin moves the lines in), the
  column's « centred on y 440 » as the vertical rule; the counter is set
  from the same edge (its 1.08 landing punch holds that edge) and centred on
  the same y — it never shares the screen with the sentence (it exits as the
  sentence arrives), so « above the sentence » needs no separate place.
- **16:9 lifts carry no panel**: the plain panel behind the Fiche's tiles
  hides the VEILED originals between cards that lift over the phone; beside
  the phone, with no veil, the tiles sit on the stage and the phone stays
  whole.
- **16:9 camera**: W sits under the band's 30-px fade (y 84 at rest, lower
  where the phone stands on the floor); the journal's first framing keeps
  Fatou B.'s card on the floor (W 62.12), which puts the cropped screen's top
  at y 73, in the fade — the section's « start the window at the top of the
  cropped screen », the phone's top edge just showing. The screen sits at
  x 1088–1808 so the slab's bezel ends ON the graphics-safe edge, x 1824 (round
  5: at 1104–1824 the bezel ran to 1840, and to 1860 in the drop's slam, past
  action-safe 1853; now ≤ 1824 at rest, ≤ 1853 in the slam — tests), the
  caption column ending at x 1040 and the lifts at 1044, 28–32 px clear of
  it. Its push-in (1.791 → 2.0 px/pt) scales about the slab's RIGHT edge
  (`zoom_pivot_x` 1824) and, where the phone stands on the floor, about the
  floor: the phone grows leftwards and upwards, never past x 1824 nor into
  the floor (round 3, about the phone's axis x 1464: the screen reached
  x 1866 at the peak, the FAB and the snackbar x 1835).

The 15-s cut (« The 15 s cut »):

- **Its length**: 8 bars, 512 frames (17.07 s), not the section's 7 bars —
  the owner's outro bar (2026-10-19), as the 30-s. The end card is the
  30-s's: the tagline as one reveal f379→f384, « Sur l’App Store et Google
  Play » alone on f400 and « myweli.com » alone on f432 (the section's « Plus
  de clients, » f384 / « moins de gestion. » f400 predates the store line:
  two arrivals on f400 are refused); 74 characters f379→f512 = 16.7 cps; the
  underline on f448, the punch on f480.
  The reveal → end handoff on f376 is `continuous` (the mark keeps easing):
  the cut has the storyboard's six joins, not seven.
- **« Créneau libre » centred while it waits** (`recentre: 4`): the line
  waits 2.67 s for « rempli. » (round 3: 136 px left of centre all that
  time); it makes room over f235–239 — « libre » struck on f236 as it goes —
  and « rempli. » rises into its place on f240. The 30-s line does the same
  (f444–447, after its strike on f440).
- **The dissolve's re-frame** (9:16 and 1:1; 16:9 cuts, framed at W 667 —
  the owner's round 5, « The declared dissolve »): the section's « W 660 − Δ, Δ ≈ 128 pt » is
  measured on the two pictures: from « Client sans numéro » down the fields
  moved up **145.33 pt** (the 125.33-pt scroll + the 20-pt « 0/10 » line the
  switch takes away; NCC 0.9998 on the note field), so 130.262 is framed at
  **W 521.67** (667 − 145.33) and the fields stay on their rows (test: the
  note field's best match is at dy 0). W is 667 on both sides, not 660/665:
  the 30-s's measured value that keeps the 13:15 row's last line under the
  band. « Créer » sits at y ≈ 1158 until the camera glides back over f204–216.
- **The dissolve's length** (9:16 and 1:1): f193→f196 (3 frames, 100 ms) as the section
  writes, on AppMotion.base's easeInOut — the App Store film ran it on the
  whole `base` token (200 ms); the « Créer » touch-down on f196 leaves 3.
- **The pane held open** f80–f88: the section's « hold 11.265–11.595 over
  f80–87 » would play the take at 1.24× (refused: only a drag's own segment
  may run faster). take1b has ONE picture from 11.265 s to 22.018 s, so the
  15-s plays it at 1× from 11.265 — the swipe's logged lift (11.420 s) lands
  on f84.7 — and the seamless cut on f88 goes 11.532 → 21.818: the same
  picture (#27) on both sides.
- **The « Arrivé » lift is kept** (f144–159: up on the badge's log hit,
  settled back by f159, `down: 3.2.2+2`), not dropped first: the cut
  verifies at ≤ 17 cps and every gap under 2 s with it.
- **The counter lands on f292** (5.3.1), not f296: N1's measured wait
  (0.663 s) at 0.995×, the 30-s's own decision; f296 would play it at 0.83×.
- **The hook** has no sink (the section has none): its push runs at the
  30-s's speed (1.10 → 1.13 over f0–47) into the hard cut to the AIR.

The 30-s cut:

- **Round 5's review, fixed (not the owner's calls):** the « Arrivé » lift
  settles back over **f248–253** as the storyboard writes it (round 5:
  `down: 4.4.0`, from f240 — landed 4 frames, a flick), landed f237–f247;
  the counter's label ROLLS « Aujourd’hui » → « Mois » like its digits, a
  whole band apart (round 5 crossed the two in place, 12 px apart: one
  garbled word on f536–539, 15-s f280–284); the map credit shows while —
  and only while — the map's tiles show, from the first rows in the floor
  fade (f691; round 5 waited for 40 px of tiles, f694) through AIR 2, white
  on black there (`map_shown_px`: the tiles' rows as posed, × the window's
  alpha — round 5 drew none in AIR 2 and dimmed 1:1's to nothing with the
  map still on) — and, since the owner's round 5, held WHOLE from then until
  the map has dimmed out (f767), no longer fading with the falling phone; the
  in-phone whip runs on the app's base easeInOut, not easeInOutCubic (its
  first and last frames carried the old 13:15 row 37–72 px through the
  fades; verify (h) now holds every whip frame to ≥ 80 px).
- **N1, the Revenus wait.** Touch-down on « Mois » 7.1517 s (first changed
  picture #1 at 7.3517 − 200 ms, read from the pictures: N1 has no App Store
  scan); the first picture showing « 77 000 FCFA » is #26 at 7.815 s: a
  0.663-s wait. The landing is on the 16th 9.3.1, **f548**: the wait plays at
  **0.995×**, inside the approved 0.90–1.00× and never faster than real.
  `revenus.land`/`ding` moved to 9.3.1, the ticks to f536–f544 (three: tick4
  went), the kick punch and the landing clap with them (the 15-s score's to
  5.3.1, f292, the same wait). Rejected: **f552** (the next 8th, the first
  build's choice) plays it at 0.829×, outside the approved band; f544 would
  be 1.24×, faster than real. « Tout » equals « Mois »: not used.
- **The end card** (review M1; the owner's decision 2026-10-19, « Add one
  bar »; the underline and the punch below OWNER-APPROVED 2026-10-19, « Keep
  both »). The tagline arrives as ONE quick reveal as the mark settles (a
  6-frame mask, f827→f832, whole on `end.mark`); « Sur l’App Store et Google
  Play » arrives alone on its own cue (`end.store`, 14.2.0 = f848) and
  « myweli.com » alone on its own (`end.site`, 14.4.0 = f880), at 40 px (the
  owner's end card, 2026-10-20, above; round 5: « Disponible sur l’App
  Store »). The cut gained one bar (30 s: 15 bars, 960 frames, 32.0 s — past
  the historical 30-s WhatsApp Status cap, the owner's call; 15 s: 8 bars),
  a calm outro, and the card holds to the end: 74 characters f827→f960 =
  16.7 cps (round 5: 60, 13.5; round 2: 26.1 over f827→f896). Two calm, on-beat events keep
  the ≤ 2-s pattern-interrupt rule over the longer hold: on the outro's
  downbeat (f896, `end.underline`, a pen scratch) the hook's strike — the
  brand's single round-cap stroke at the type's stem width — draws an
  UNDERLINE under « moins de gestion. » left to right over 8 frames, under
  the « g »'s descender (MP4: stroke y 764–772, the tagline's ink ends at
  756, the store line's starts at 808); on the last log (f928, `end.last`,
  with the last chord) the mark gives a 1.06× punch (3 frames out, 8 back;
  MP4: its ink y 394–606 at the peak, 106 px above the tagline's cap top).
  Longest quiet stretches: f848→f880, f896→f928, f928→f960 (1.07 s each;
  the site's arrival on f880 split round 5's f848→f896, 1.6 s). The
  last chord and log RING OUT before the end (≥ 20 dB down by f950, the
  last 100 ms ≈ −48 dBFS; round 3 held the chord to the last sample and
  the end fade chopped it — verify (d) `outro_tail`).
  The 15-s score has the same outro (the underline on f448, the last log on
  f480); its scenes come with its layout.
- **AIR 2** (row 22, review M2) is near silence, as AIR 1: riser 3 stops dead
  on the cut to black (12.4.0, f752 — the storyboard's « riser stops at
  f764 » conflicted with « near silence »), the breakdown's tail is short
  (vel 0.5, decay 0.3) and the pad is muted over 12.4. Round 3: AIR 1 was
  only 5.8 LU under the groove on the master (6.4 after AAC), AIR 2 6.9 —
  both ≥ 7 on the master now: the AIR reverses at −20 / −18 dB (were −16),
  AIR 1's breath of pad 3 dB down → 8.5 / 8.5 LU on the master. The 15-s
  cut's one AIR: round 2's « 6.4 LU after AAC » did not reproduce (master
  5.87, AAC 6.05); with the reverse at −19 dB, strike 3 at vel 0.7 and the
  breath 3 dB down it is 8.4 LU on the master, 8.9 after AAC.
- **The glide onto « Coupe homme »** takes 6 frames (f314→f320) like the two
  after it; the micro push-in eases back to 1.0 over the same frames.
- **No picture is hidden.** take1b 130.985 is not a black picture: it is the
  form with « Créer le rendez-vous » solid black again after its loader — a
  real state; it plays.
- **The snackbar** « Rendez-vous créé » appears whole in one picture
  (131.44833 s), it does not slide in; the film shows the app's pictures.
- **The Fiche tiles** lift into a ROW (x 120–900, 2.92 px/pt), not a
  360-px-wide column: three tiles 360 px wide stack 1 085 px tall, which the
  storyboard's y 660–1200 cannot hold. The row sits on the tiles' own row
  (centre y 815, was 900) on a plain `background` panel that grows with the
  lifts (review n2, round 2's regression, rounds 3–4's blink and pull-back:
  « The Fiche tiles » above).
- **The end mark**: `end_mark_scale` 1.2 is read against the composition's own
  560 px (a 672-px comp), which is what gives the storyboard's ink y 400–599
  (measured with `Player.ink_bounds`); against the 900-px reveal it would be
  321 px tall and touch the tagline.
- **Camera W** measured on the pictures (9:16, the owner's floor y 1424): 128
  (Fatou B.'s card bottom 582 pt on y 1413, the 13:15 row's text on y 1468,
  20 px under the floor fade; the band edge between « Ma journée » and
  « Aujourd’hui »; round 3, floor 1192: 257, the card on y 1184), 667 for the
  lower journal and the « Créer » shot (the old 13:15 row's last text line,
  644 pt, on y 560 — wholly under the band; 660/662 left 28 % of it in the
  band's fade), 312.73 / 56 / 468.73 / 519.73 for the form rows (each on the
  window's middle, y 1012; « Coupe homme » at y 955 with the screen's top on
  the band edge — round 3: 377.5 / 86.5 / 533.5 / 584.5 in the 600–1192
  window), 216 for the Fiche (the blurred number under the band too), 124 for
  Revenus (its title under the band), 427.32 for the page's end (`keep:
  text_floor`: the bar's « Réserver (après la mise en ligne) » line, ink
  ≤ 807 pt on 28.480, on y 1240 once the page's parallax has lifted the
  phone 40 px — 8 px above the text rectangle's bottom, y 1248; round 5:
  352.46 put it on the floor at y 1374; round 3: 482).
- **The hook's caption band**: the stage's black covers y 0–560 and fades to
  640 over the page, so the macro and the push-in never put scribbles under
  the white words (the layout's caption band, applied to the hook).
- **The « Modifier » chip** in take2b's Fiche is the tag editor
  (client_detail_screen.dart:408, `tags.isEmpty ? '+ Tags' : 'Modifier'`), not
  #614's « Modifier » under the number (:442) — the footage is build 587's.
- Awa K.'s number uses the storyboard's rectangle + 4 pt, σ 14 px (7 % of the
  digits' detail left, measured on the film's picture).

