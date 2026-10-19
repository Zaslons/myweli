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

**What is built.** The 30-s cut in 9:16 (896 frames). The 15-s cut has no
scenes yet and 1:1 / 16:9 are not laid out: `build`/`verify --all` name them
(« NOT BUILT … ») and build/verify the rest; asking for one of them alone
fails — nothing unbuilt is ever reported as verified.

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

| scene kind | module | rows |
|---|---|---|
| `carnet`, `air` | `scenes/carnet.py` | 1–5: the code-drawn carnet (push-in under way at f0, macro cut, strikes with punches, push + sink, grain), the AIR |
| `phone` | `scenes/phone.py` | 6–22: take1b, take2b, N1, take5b in the 2.5D slab through the camera window |
| `lottie`, `end_card` | `scenes/lottie.py` | 23–24: the Pro opening Lottie retimed, the mark settling, the tagline, « Disponible sur l’App Store » |
| — | `scenes/film.py` | the cut end to end, the horizontal whip between scenes, captions, the per-frame record |

**Rules the renderer enforces** (each a refusal with its storyboard path):
a derived take rate faster than 1× on anything but a drag (the gesture ramps
1.11×, 2.74×, 1.08×; never past 3×); a touch disc whose YAML frame is not
where the timeline puts the measured touch-down, or whose tone is not what
the ground under the finger asks for; a counter that does not land on the
frame the app first shows its figure; a caption line over 771 px; scenes
that do not run end to end.

**Motion blur.** Camera moves blur by subframe accumulation in linear light
(`fx.blur`), only inside the phone window's rows, with enough subframes that
copies sit ≤ 2 px apart; the take's picture is held for the frame (a fast UI
move the take has only a few pictures of would otherwise show as double
images). Where the storyboard asks for the take's own frames to blend (the
swipe, the 2.74× form scroll) each subframe shows its own take picture.
Masks are on the take, so every subframe is already blurred.

### Verification — `promo/verify.py`

All automated, on the written MP4 wherever possible, into `verify/`: (a) the
renderer's frame on every beat (`beats.png`, 56 stills) and the MP4's beats
compared with them (PSNR), (b) every cut and whip ± 1 frame from the MP4
(`transitions.png`, plus full-size frames in `frames/`), (c) every touch-down
drawn held to the gesture logs (`media.touches.cross_check`) and its tone
re-measured, (d) BS.1770-4 on the MP4's decoded AAC (−14 ± 0.5 LUFS, ≤ −1.0
dBTP; ffmpeg's ebur128 as a second opinion) and `spectrogram.png` with bar
ticks, (e) ffprobe + assertions (`probe.json`), (f) A/V sync: each click and
key's onset in the MP4 audio (correlated with the master) ÷ 1600 against the
frame its disc or picture appears, (g) every caption / lift / counter / disc /
credit box on every frame inside the platform text area, (h) honesty: every
generated element with its source (`honesty.txt`), every blur measured on
every picture the film uses, the old 13:15 row never readable outside the
whip, the speed of every wait and ramp, (i) reading speed (≤ 17 cps) and the
longest stretch without a visual event (≤ 2 s). `report.txt` is the summary;
the exit status is 1 when anything fails.

### Decisions made against the storyboard's text, and why

- **N1, the Revenus wait.** Touch-down on « Mois » 7.152 s (first changed
  picture #1 at 7.352 − 200 ms, read from the pictures: N1 has no App Store
  scan); the first picture showing « 77 000 FCFA » is #26 at 7.815 s. The
  wait, 0.663 s, is ≤ 0.8 s, so the landing stays on f552 (`revenus.*` cues
  unchanged) — which plays the wait at 0.829×. The storyboard also asks for
  0.90–1.00×; for this wait the two rules cannot both hold (the previous 8th,
  f544, would need 1.24×, faster than real). The grid and « never faster »
  win. « Tout » equals « Mois »: not used.
- **« Disponible sur l’App Store »** appears on 14.2.0 (f848) with « moins
  de gestion. », not on 14.3.0: from f864 it would show for 1.07 s (24
  characters a second, over the 17-cps ceiling). `end.store` moved in both
  scores (the 15-s's to 7.2.0 for the same reason).
- **No picture is hidden.** take1b 130.985 is not a black picture: it is the
  form with « Créer le rendez-vous » solid black again after its loader — a
  real state; it plays.
- **The snackbar** « Rendez-vous créé » appears whole in one picture
  (131.44833 s), it does not slide in; the film shows the app's pictures.
- **The Fiche tiles** lift into a ROW (x 120–900, 2.92 px/pt), not a
  360-px-wide column: three tiles 360 px wide stack 1 085 px tall, which the
  storyboard's y 660–1200 cannot hold.
- **The end mark**: `end_mark_scale` 1.2 is read against the composition's own
  560 px (a 672-px comp), which is what gives the storyboard's ink y 400–599
  (measured with `Player.ink_bounds`); against the 900-px reveal it would be
  321 px tall and touch the tagline.
- **Camera W** measured on the pictures: 257 (Fatou B.'s card bottom 582 pt on
  y 1184), 667 for the lower journal and the « Créer » shot (the old 13:15
  row's last text line, 644 pt, on y 560 — wholly under the band; 660/662
  left 28 % of it in the band's fade), 377.5 / 86.5 / 533.5 / 584.5 for the
  form rows, 216 for the Fiche (the blurred number under the band too), 124
  for Revenus (its title under the band), 482 for the page's end (the bar's
  « Réserver » line ≥ 8 px above the floor).
- **The hook's caption band**: the stage's black covers y 0–560 and fades to
  640 over the page, so the macro and the push-in never put scribbles under
  the white words (the layout's caption band, applied to the hook).
- **The « Modifier » chip** in take2b's Fiche is the tag editor
  (client_detail_screen.dart:408, `tags.isEmpty ? '+ Tags' : 'Modifier'`), not
  #614's « Modifier » under the number (:442) — the footage is build 587's.
- Awa K.'s number uses the storyboard's rectangle + 4 pt, σ 14 px (7 % of the
  digits' detail left, measured on the film's picture).

