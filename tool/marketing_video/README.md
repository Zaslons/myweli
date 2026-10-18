# Marketing Reel — MyWeli Pro « Le trait »

Builds the 30-second vertical film for salon owners — Instagram and Facebook
Reels, TikTok, WhatsApp Status — from the owner-approved storyboard
(2026-10-18) and the production takes of 2026-10-14. One white stroke, in
the mark's single weight and round caps, crosses out three things that go
wrong on a salon day and thickens into the paper page on which MyWeli Pro
answers, on real footage of the demo salon « Maison Nala ».

The film is specified in [`docs/design/pro-marketing-reel.md`](../../docs/design/pro-marketing-reel.md).
This tool is the sibling of [`tool/app_store_preview/`](../app_store_preview/README.md)
and reuses its pieces rather than copying them: `brand.py` (colour tokens
from `colors.dart`, motion tokens from `motion.dart`, Flutter's cubic),
the stills' fonts, `Conform.swift` (the takes to 30 fps by frame-hold),
`Common.swift` + `Writer.swift` (`writeMovie`), `Inspect.swift`, `mp4.py`,
`avmediainfo`'s reader and `frames.check_glyphs`.

Nothing is installed: Python 3 with Pillow and numpy, Xcode's `swiftc` and
AVFoundation, `rsvg-convert`. `ffmpeg` is not used.

```
python3 tool/marketing_video/reel.py build \
    --assets "<main checkout>/build/app-store/pro" \
    --out <folder> [--work <scratch folder>] [--jobs 4]
python3 tool/marketing_video/reel.py verify <folder>/reel.mp4 [--work <scratch folder>]
python3 tool/marketing_video/reel.py sheet <folder>/reel.mp4 --out contact-sheet.png
python3 tool/marketing_video/reel.py selftest          # about ten seconds
```

`--assets` is the folder that holds `preview/v2/takes/take1b/take.mov`,
`preview/v2/takes/take5b/take.mov` and `preview/v2/final/film.json`. They
are build products (`build/` is ignored by git) and are only read: never
copy a take into the repository.

## Outputs

| File | What it is |
|---|---|
| `reel.mp4` | The master: H.264 High@4.1, 1080 × 1920, 30 fps constant, 900 frames, 30.000 s, yuv420p, a silent stereo AAC-LC 48 kHz track |
| `poster-hook.png`, `poster-end.png`, `cover.png` | Frame 0, the last frame (899) and the storyboard's cover (frame 51, 1.70 s), as composed — lossless, for a platform's cover picker |
| `contact-sheet.png` | A frame every 0.5 s, **decoded from the written file**, labelled with its time and scene; cuts outlined |
| `frame-<t>.png` | The key moments (0.0, 1.0, 2.4, 3.5, 5.0, 7.0, 9.0, 11.0, 14.0, 17.0, 18.5, 22.0, 25.0, 27.0, 29.5 s), decoded from the written file |
| `verify.txt` | Every check and its reading; « PASS — N checks — reel.mp4 sha256 … » |
| `build.json` | The file's sha256, the storyboard's, the takes', the timings |

The work folder keeps the conformed take pictures, the composed frames
(each distinct picture once, `frames/frames.json` naming one per film frame)
and the decoded frames.

## What is in here

| File | What it does |
|---|---|
| `storyboard.json` | **The film's single source** — the approved storyboard, copied as approved, without `_ownerDecisions`. |
| `reel_plan.py` | Reads it: every word (`scenes[].onScreenText`), every scene boundary, size, rate, length, cuts, safe zone, rail, crops, cover frame. The numbers the storyboard gives only in prose are transcribed once, and `ANCHORS` holds the storyboard's own phrase for each: a storyboard that stops saying one is refused. |
| `reel_draw.py` | The primitives: round-capped strokes and the trimmed polyline by signed distance (supersampled 4 × 4; analytic for the page-wide « trait »), rounded rectangles, discs, the continuous-corner tile, the stills' shadows, type through an alpha mask at fractional positions. A `Frame` records every word, logo and shape it places — and can run « dry », drawing nothing. |
| `reel_brand.py` | The logo from vectors only: the mark from its SVG, drawn in the fast loader Lottie's path order and timing; the « MyWeli Pro » unit — the wordmark SVG plus the « Pro » outlines of the Pro app-open Lottie, placed as that file places them (the transform fitted on the M and W strokes), rendered by `rsvg-convert`; the Pro icon's mark box measured on `Icon-1024.png`. |
| `reel_footage.py` | The takes conformed by `Conform.swift`, the S5 mask, the S3 drag, the card and its camera window. |
| `reel_scenes.py` | The film frame by frame (`Composer.frame(n)`), and the reading windows. |
| `reel_verify.py` | Reads the written file back and checks it, the plan and the build. |
| `reel.py` | The command. |
| `swift/ReelEncode.swift` | `MovieSpec.social` and the encoder, compiled with the App Preview's `Common.swift` and `Writer.swift` (registered in its `swifttools.SOURCES` at run time; built into its `build/bin`). |
| `tests/` | The self-test. |

## How a frame is made

Film frame n is t = n / 30 s. `reel_plan.Plan.scene_at` names its scene;
the scene draws its ground (Ink Black, or paper `surface`), then its layers
in order. Times, sizes and colours come from the plan; durations and curves
from `motion.dart` (`fast`, `base`, `emphasis`, `slow`, `stagger`); an exit
is `base`'s 200 ms on `easeIn` (« exits accelerate »); every stroke draws on
the Lottie's (0.4, 0, 0.2, 1), added to `brand.CUBICS` as `fastOutSlowIn`
and checked there against Flutter's `curves.dart`; S5's camera moves are
600 ms `easeInOutCubic` (« a camera move, not UI motion »).

- **The « trait ».** A polyline thickened by a disc is exactly a stroke
  with round caps and round joins. A strike draws by trim 0 → 100 %: at 0 it
  is a dot as wide as the stroke — the pen touching down. The page-wide
  trait thickens from 8 to 2400 px about its line on `slow`; at 2400 its
  rounded ends cover every corner of the frame, so the stroke has become the
  page.
- **The mark.** The loader's vertices, mapped onto the SVG's geometry, must
  land on the SVG's own vertices (they do, to a tenth of a unit), its start
  must be the middle of the right stem, its trim must run 0 → 100 over its
  first keyframes on `fastOutSlowIn` — or the build stops. Drawn 0.6 s out
  of a pen dot the size of the stroke's cap.
- **Type.** Poppins Medium (headlines, the tagline) and Inter at opsz 14
  (Medium for the notebook, Regular for the bubbles, SemiBold for the CTA).
  A line set in a line box has the font's ascent and descent centred in it,
  as a text engine does. French spacing: U+202F before « ? » and « : ».
- **The card.** The capture from screen point 56 down, resampled straight
  into the frame with a fractional box (a camera move lands on the
  sub-pixel), its rounded rectangle and 3-px ring from their signed
  distance, the stills' two shadows. The paper band (0–552, fading to 600)
  clips the card's layer, not what lies under it.
- **The end card.** The pattern's marks are 72 px tall on a brick grid,
  drifting up 12 px/s; each mark fades whole by its own box's distance to
  the clear zone (80 px feather), so no mark is cut and none enters the zone.

## The file

`MovieSpec.social` (`swift/ReelEncode.swift`): `.mp4`, H.264 High Profile
Level 4.1, 1080 × 1920, 30 fps constant, progressive, no frame reordering,
a key frame every 30 frames, Rec. 709 tags; one stereo AAC-LC 48 kHz track
of digital silence (so WhatsApp never treats the film as a GIF); a target of
10 Mbit/s and a quantiser ceiling of 10.

**10 Mbit/s is the target, not the file's rate.** Half the film's frames
are holds and flat paper (444 distinct pictures in 900 frames), and the
encoder spends what the picture needs: measured on the film 2026-10-18,
**2.74 Mbit/s on average, 8.80 Mbit in its busiest second**, 10.3 MB.
Padding to a constant rate was measured worse by the App Preview and is not
done. The quantiser ceiling is what buys quality: the worst key frame
decodes at 54.5 dB from what was composed (at a ceiling of 20 the hook's
first frame, a key frame of white type on black, fell to 48.8 dB).

## Verify — 30 checks

`reel.py verify` reads the written file back through three readers that
must agree (the App Preview's box parser, AVFoundation, `avmediainfo`):

- **the file**: container; one video and one sound track; H.264; High@4.1;
  1080 × 1920 in the SPS, `stsd`, `tkhd`, AVFoundation and `avmediainfo`;
  upright, square pixels; progressive; yuv420p 8-bit; every sample exactly
  1/30 s on the grid (constant 30 fps); no reordering; 900 frames; 30.000 s;
  the bit rate (0.5–12 Mbit/s on average, Level 4.1's 62.5 Mbit in any
  second); AAC-LC stereo 48 kHz, the whole film long, **decoding to
  zeros**;
- **the plan**: every frame laid out dry — every word, logo and shape's ink
  box and line box inside the storyboard's safe zone (x 65–1015, y
  269–1248) on every one of the 900 frames, and nothing in the right-hand
  rail (x > 850, y > 1152); the cover frame and the end card inside the
  4:5 feed crop; no character drawn as a missing glyph; every timed line on
  screen at least max(1.5 s, characters ÷ 15 + 0.5 s); the logo on screen
  at most 25 % of the film;
- **the build** (with `--work`): take1b's nine exported ranges against the
  take's own map (each hold shows the picture its live range starts or ends
  on; a live range never goes back; no picture later than its instant); S5's
  phone row white on every composed frame that shows it, and on frames
  decoded from the file across the camera stops and moves; the key frames
  decoded against the composed ones (at least 48 dB).

`verify` without `--work` runs the file and the plan, and says « NOT
checked » for the build.

## Deviations from the storyboard

Where a detail was ambiguous or could not be done as written, the calmer,
more precise option was taken:

1. **U+202F.** `onScreenText` carries plain spaces before « ? » and « : »;
   the visuals ask for U+202F, and every width the storyboard states was
   measured with it. `typeset()` sets it (a test holds both).
2. **A card enters from below the frame.** S3 says « Card rises from top
   y 1920 to 600 (offset +1320 → 0) ». For S5 (rest W 100) and S7 (rest W
   553) a fixed +1320 would start the card on screen — S7's top edge at y
   807 — and pop it in. Every card's top edge starts at y 1920 instead: S3
   travels 1320 px as written, S5 1418.5, S7 2432.7, all on `emphasis`.
3. **S8's dot and draw overlap** (26.55–26.65 and 26.60). The stroke's width
   follows the dot's growth until the dot is whole, so the pen never jumps.
4. **The pattern's feather** fades whole marks (above), not pixels: on the
   first render the pixel feather cut marks in half along the clear zone.
5. **S4's bubbles.** A new bubble arrives on `fast` (100 ms) while the one
   above moves up on `base` (200 ms): for two frames they overlap. Drawn
   first, the new bubble passes under the moving one, so words never print
   over words (they did on the first render, at 11.00 s); at 11.00 the top
   of « Allô ? » is still under « Vous fermez à quelle heure ? ».
6. **The widest bubble** is b3, « Vous fermez à quelle heure ? » 22:47:
   842 px, x 90–932 (the storyboard's 809 px is b1's). Inside the zone and
   above the rail.
7. **take5b « at 30.000 s »** is the picture presented at 28.665 s: nothing
   changes between them in that variable-rate take, and frame-hold (and
   AVAssetImageGenerator at zero tolerance) shows that picture at 30.000 s.
8. **S3's touch point** follows the App Store film's verified, picture-
   followed path (`final/film.json`, its S1 drag, take sha256 checked)
   7.0 s later — the storyboard's « 7.61–8.36 » is that path's timing;
   the raw logged path is not used.
9. **Round caps.** The fast loader Lottie strokes its mark with butt caps
   (`lc: 1`); the storyboard and the SVG say round. Round.
10. **The tile's continuous corner** is a superellipse (n ≈ 4.9) that meets a
    63-px rounded corner on the diagonal.
11. **Grid phase.** The pattern's rows are centred on the frame's middle and
    its columns on x 540 (the storyboard gives the pitches, not the phase).
12. **Bit rate** — above: 2.74 Mbit/s against a 10 Mbit/s target.
13. **Not built**: the 13.5-s cut-down and the post caption the storyboard
    lists among its deliverables — not asked of this tool.

## What the footage still carries (the storyboard's risks, unchanged)

The empty phone field (S7, 21.87–22.37 s) is the take's; since the take
only #611/#614 touched it, and the empty field reads the same — « +225 »,
« Téléphone du client », a « 0/10 » counter, now the app's own instead of
the package's (read in `phone_number_field.dart`, not filmed). The two
« Yao K. » rows in S7's last second, and « Tarifs » being one tap away,
remain; only a re-take removes them (the owner chose not to, 2026-10-18).
At W 100 the public page's own back button shows faintly in the band's fade
(S5, 13.1–14.0 s).

## Tests

```
python3 tool/marketing_video/reel.py selftest
```

Ten tests, about ten seconds. Files written by the App Preview's test writer
(`TestClip.swift`), never by the Reel's encoder: a right file of 900 frames
passes every file check; a 2-s file with a 440 Hz tone at High@4.0 fails on
exactly « 900 frames », « duration 30.000 s », « sound is silent » and
« profile and level »; a file without a sound track fails on « tracks » and
« sound track ». The film's own frames pass the safe zone; a word moved
below it fails it; a word under the rail fails the rail. A storyboard that
no longer says a transcribed number is refused; one carrying
`_ownerDecisions` is refused; the words carry French spacing; every width
the storyboard measured comes back from the faces the tool draws with.
