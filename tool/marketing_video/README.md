# Marketing Reel — MyWeli Pro « Le trait »

Builds the 30-second vertical film for salon owners — Instagram and Facebook
Reels, TikTok, WhatsApp Status — from the owner-approved storyboard
(2026-10-18, amended the same day by the owner: A1, people and pictures; A2,
the salon page shows Maison Nala; with the items of three reviews, R1–R3),
the production takes of 2026-10-14 and the owner's two pictures. It opens on a salon owner writing in her paper
notebook; one white stroke, in the mark's single weight and round caps,
crosses out three things that go wrong on a salon day and thickens into the
paper page on which MyWeli Pro answers, on real footage of the demo salon
« Maison Nala » — whose public page opens on its own cover photo and logo;
a stylist braiding a client says what the answers give back, « Plus de
temps pour votre métier. », before the end card.

The film is specified in [`docs/design/pro-marketing-reel.md`](../../docs/design/pro-marketing-reel.md).
This tool is the sibling of [`tool/app_store_preview/`](../app_store_preview/README.md)
and reuses its pieces rather than copying them: `brand.py` (colour tokens
from `colors.dart`, motion tokens from `motion.dart`, Flutter's cubic),
the stills' fonts, `Conform.swift` (the takes to 30 fps by frame-hold),
`Common.swift` + `Writer.swift` (`writeMovie`), `Inspect.swift`, `mp4.py`,
`avmediainfo`'s reader and `frames.check_glyphs`.

Nothing is installed: Python 3 with Pillow (with WebP) and numpy, Xcode's
`swiftc` and AVFoundation, `rsvg-convert`. `ffmpeg` is not used.

```
python3 tool/marketing_video/reel.py build \
    --assets "<main checkout>/build/app-store/pro" \
    [--photos "<main checkout>/build/marketing/photos"] \
    --out <folder> [--work <scratch folder>] [--jobs 4]
python3 tool/marketing_video/reel.py verify <folder>/reel.mp4 [--work <scratch folder>]
python3 tool/marketing_video/reel.py sheet <folder>/reel.mp4 --out contact-sheet.png
python3 tool/marketing_video/reel.py selftest          # about eleven seconds
```

`--assets` is the folder that holds `preview/v2/takes/take1b/take.mov`,
`preview/v2/takes/take5b/take.mov` with its scroll map
`phone_rect_per_frame.csv`, and `preview/v2/final/film.json`.
`--photos` (by default `build/marketing/photos` beside `--assets`'
`build/app-store`) holds A1's pictures, `hook-owner-notebook.webp` and
`closing-stylist-braiding.webp`, with their `PROVENANCE.md`; each must have
the sha256 the storyboard quotes, or the build stops. All of them are build
products (`build/` is ignored by git) and are only read: never copy a take
or a picture into the repository.

## Outputs

| File | What it is |
|---|---|
| `reel.mp4` | The master: H.264 High@4.1, 1080 × 1920, 30 fps constant, 900 frames, 30.000 s, yuv420p, a silent stereo AAC-LC 48 kHz track |
| `poster-hook.png`, `poster-end.png` | Frame 0 and the last frame (899), as composed — lossless |
| `cover.png`, `cover-4x5.png` | The storyboard's cover (frame 54, 1.80 s) composed as its own picture with S1's headline 30 px lower (R3), and the same cut to the 4:5 feed crop (y 285–1635, 1080 × 1350). **Upload it separately on Instagram** as the Reel's cover picture: the film's frame 54 keeps only 11 px above its headline in the 4:5 crop, the cover picture 41. The film's frames are unchanged |
| `contact-sheet.png` | A frame every 0.5 s, **decoded from the written file**, labelled with its time and scene; cuts outlined |
| `frame-<t>.png` | The key moments (0.0, 1.5, 3.5, 6.1, 6.2, 10.4, 11.0, 12.9, 13.5, 13.9, 14.1, 14.5, 15.0, 15.5, 16.0, 16.3, 17.0, 21.0, 22.9, 23.0, 23.1, 24.0, 24.5, 25.5, 26.9, 27.5, 29.5 s), decoded from the written file |
| `verify.txt` | Every check and its reading; « PASS — N checks — reel.mp4 sha256 … » |
| `build.json` | The file's sha256, the storyboard's, the takes' (and take5b's scroll map's), the pictures', take5b's distinct scroll positions, the fitted length of S5's scroll, the largest remainder and how many take5b pictures carry a mask, the timings |

The work folder keeps the conformed take pictures, the decoded pictures
(`photos/`), the composed frames (each distinct picture once,
`frames/frames.json` naming one per film frame) and the decoded frames.

## What is in here

| File | What it does |
|---|---|
| `storyboard.json` | **The film's single source** — the approved storyboard, without `_ownerDecisions`, with its amendments (`amendments`: A1, the owner's people and pictures; R1, the fixes from the review of the first render; A1 as built — the black band under the Reels caption kept, the owner's answer of 2026-10-18; A2, the owner's salon page; R2 and R3, the items of the reviews of the second and third renders). |
| `reel_plan.py` | Reads it: every word (`scenes[].onScreenText`), every scene boundary, size, rate, length, cuts, safe zone, rail, crops, cover frame. The numbers the storyboard gives only in prose are transcribed once, and `ANCHORS` holds the storyboard's own phrase for each: a storyboard that stops saying one is refused. |
| `reel_draw.py` | The primitives: round-capped strokes and the trimmed polyline by signed distance (supersampled 4 × 4; analytic for the page-wide « trait »), a stroke's soft shadow, rounded rectangles, discs, the continuous-corner tile, the stills' shadows, type through an alpha mask at fractional positions, dissolves. A `Frame` records every word, logo and shape it places — and can run « dry », drawing nothing; it can clip below a line (S4's chat column). |
| `reel_brand.py` | The logo from vectors only: the mark from its SVG, drawn in the fast loader Lottie's path order and timing; the « MyWeli Pro » unit — the wordmark SVG plus the « Pro » outlines of the Pro app-open Lottie, placed as that file places them (the transform fitted on the M and W strokes), rendered by `rsvg-convert`; the Pro icon's mark box measured on `Icon-1024.png`. |
| `reel_footage.py` | The takes conformed by `Conform.swift` (S7's one held frame, a declared `skip`); take5b's drag exported whole, each picture's scroll checked to the capture pixel, S5's frames chosen by scroll position on the fitted target and their remainders (R3); the S5 mask on every take5b picture (moved by the take's own scroll map, checked against the rest picture's row); the S3 drag; the card, its camera window and its sub-pixel shift. |
| `reel_photo.py` | A1's pictures: checked against their sha256, placed at the least scale that fills, pushed in about a point held still, their gradients. |
| `reel_scenes.py` | The film frame by frame (`Composer.frame(n)`), and the reading windows. |
| `reel_verify.py` | Reads the written file back and checks it, the plan and the build. |
| `reel.py` | The command. |
| `swift/ReelEncode.swift` | `MovieSpec.social` and the encoder, compiled with the App Preview's `Common.swift` and `Writer.swift` (registered in its `swifttools.SOURCES` at run time; built into its `build/bin`). |
| `tests/` | The self-test. |

## How a frame is made

Film frame n is t = n / 30 s. `reel_plan.Plan.scene_at` names its scene;
the scene draws its ground (one of A1's pictures, Ink Black, or paper
`surface`), then its layers in order. Times, sizes and colours come from the
plan; durations and curves from `motion.dart` (`fast`, `base`, `emphasis`,
`slow`, `stagger`); an exit is `base`'s 200 ms on `easeIn` (« exits
accelerate »); every stroke draws on the Lottie's (0.4, 0, 0.2, 1), added to
`brand.CUBICS` as `fastOutSlowIn` and checked there against Flutter's
`curves.dart`; S5's camera move is `slow` 400 ms easeInOutCubic (S3's and
S7's too); S5's scroll follows its own smooth target (R3, below).

- **The pictures (A1).** A uniform scale, never a stretch: the least that
  fills the frame's width (S1, 1080 / 941 = 1.1477) or the whole frame (S7b,
  1920 / 1672 = 1.1483), times a linear push-in (1.00 → 1.04 over S1,
  1.00 → 1.03 over S7b) about a point of the picture held still — S1's
  stroke start on the notebook, S7b's braiding hands. Resampled straight
  into the frame (Lanczos, a fractional box). S1's picture sits 320 px above
  its natural place so the notebook's crossing (y 1232) is above the Reels
  caption zone; its bottom edge (y ≈ 1599) fades into black over 160 px
  (A1 as built — the black band under the Reels caption kept: the owner,
  asked on 2026-10-18, answered « Keep the black band »). A black gradient from
  the top carries the white words: S1 72 % to y 380, easing to 0 at y 960;
  S7b 62 % to y 420, easing to 0 at y 1000. Natural colour, no other
  filter. S1's headline block sits at y 280, the top of the safe zone
  (R2), so its second line ends above her hairline; S7b's caption block at
  y 269, the top of the safe zone (R3), so « pour » stays above the
  stylist's bun as the push-in raises it 18 px (verify measures the gap on
  every frame: at least 4 px).
- **The cover (R3).** `Composer.cover` draws the storyboard's cover frame
  (54) with S1's headline 30 px lower, so its ink sits 41 px inside the 4:5
  feed crop (frame 54 itself: 11 px); it is written as `cover.png` and
  `cover-4x5.png` and uploaded apart. The film's frames are not touched.
- **The « trait ».** A polyline thickened by a disc is exactly a stroke
  with round caps and round joins. Every strike draws left to right from a
  short visible length — four times its width — so it is never a lone dot.
  S1's stroke leaves the pen tip and crosses the open notebook (x 246.8–735,
  y 1232) over a soft shadow (black 40 %, 3 px blur, 2 px down) so the white
  line reads on the white page; it thickens from 8 to 2560 px about its line
  on `slow`. The page-wide traits of S4 and S6 thicken to 2400. At its last
  width each covers every corner of the frame (the build checks it), so the
  stroke has become the page.
- **The mark.** The loader's vertices, mapped onto the SVG's geometry, must
  land on the SVG's own vertices (they do, to a tenth of a unit), its start
  must be the middle of the right stem, its trim must run 0 → 100 over its
  first keyframes on `fastOutSlowIn` — or the build stops. Drawn 0.6 s out
  of a pen dot the size of the stroke's cap.
- **Type.** Poppins Medium (headlines, the tagline, S7b's caption) and Inter
  at opsz 14 (Medium for the notebook, Regular for the bubbles, SemiBold for
  the CTA). A line set in a line box has the font's ascent and descent
  centred in it, as a text engine does. French spacing: U+202F before « ? »
  and « : ».
- **The chat column (S4).** The stack moves as one column: a new bubble
  enters one slot (140 px) below the bottom slot and rises into it with the
  older bubbles on `base`, while it fades and scales in on `fast`. Nothing
  below the column's edge (y 1152) is drawn, so a bubble rises into view,
  and it is never more opaque than the share of it above that edge (R2: no
  half-sliced line at full white); no two bubbles ever overlap.
- **The card.** The capture from screen point 56 down, resampled straight
  into the frame with a fractional box (a camera move lands on the
  sub-pixel), its rounded rectangle and 3-px ring from their signed
  distance, the stills' two shadows. The card and its shadow are one group,
  laid on the frame through the paper band (0–552, fading to 600) — the band
  clips the card's layer, not what lies under it, and under its fade the
  paper shows through, never the shadow. Every card enters the same way:
  the card as it RESTS, clipped by the band, rises 1320 px from y 1920 on
  `emphasis` (404.6 px in its first frame, the most any card moves).
- **The exit of S2's lockup** (R2). The mark, the unit and the tagline
  leave on `exit` (6.00–6.20); S3's card starts rising at 6.10, so it
  reaches neither the logo's clear space nor the tagline's line before they
  are gone — 211 px below the tagline at its closest (frame 185). Verify
  holds it on every frame; no paper plate is laid over the card any more.
- **S5, the salon page (A2).** The card opens on the top of Maison Nala's
  public page at W 136 — the cover photo, the « Maison N » logo, the name,
  « Abidjan », « Nouveau » — with the status bar and the back button's
  white disc (to pt 110.3, frame y 542) under the solid band. From 14.00 s
  the page's own scroll (R3): the take presented its drag at about 44
  distinct positions a second, so a 30-fps frame-hold stepped 9 and 18 px
  in turn after a 15-px first step. The whole drag is exported (145
  pictures, 102 positions, each checked to the capture pixel on the
  picture); the target is the gesture's own cosine eased in from rest,
  s*(t) = 862 px × (1 − cos πu) / 2, u = (t − 14.000 s) / 2.095 s, its
  length fitted to those positions by least squares (repeated samples
  removed, start pinned to the rest; the build refits it and stops if it
  is not 2.095 s); each frame 420–482 shows the picture nearest the target,
  moved by the remainder (at most 5.56 capture px) in capture space
  before the camera transform. The cover is anchored to its bar and
  scrolls with the content (`_SalonCover`, no parallax), so the shift is
  the page's own motion; only the cover's fade is read at the picture's
  scroll. The scroll ends at 16.10, Services and the map rest to 16.40,
  then the camera moves W 136 → 470 (`slow`) to the hours. The headline
  is set at 78 px: « Photos, tarifs, horaires : » is 965 px at 84. The phone row is painted out on every
  picture that shows it: the rest picture's rectangle moved by the
  picture's scroll (the take's `phone_rect_per_frame.csv`) and cut at the
  opaque bottom bar — painted before the shift, so it moves with the
  picture; each rectangle must hold the rest picture's row pixel
  for pixel (and no rectangle 1–3 px off may), and be ringed by white; and
  on every picture the page just above the bar must be the rest picture's
  moved by that scroll (best within 1 px), so the map is checked, not
  trusted — a map 2 pt off on a picture whose row is under the bar is
  refused.
- **S7.** The « Libre » disc is gone before « Réservation » pushes in; the
  first live range ends where the take stops changing (R2); the declared
  dissolve runs 12 frames on `slow`, from a clean picture to a clean
  picture; the filled form holds 8 frames (R2); frame 690 (23.00 s) holds
  the loading picture of frame 689 over the take's one picture where
  « Créer le rendez-vous » turns black again before the push (R3: a
  declared `skip`, one frame, then 1:1 again); as « Ma journée » comes
  back, the camera pans W 553 → 682 so the old 13:15 « Yao K. » slides
  under the band; the headline fades out (24.167–24.367), then the page
  dissolves into S7b's picture (`base`) from frame 731 — off the 0.5 s
  grid, so the caption has its 2.63 s (R2).
- **The end card.** S7b's picture dissolves into it (`base`, 27.00–27.20).
  The pattern's marks are 72 px tall on a brick grid, drifting up 12 px/s;
  each mark fades whole by its own box's distance to the clear zone (80 px
  feather), so no mark is cut and none enters the zone.

## The file

`MovieSpec.social` (`swift/ReelEncode.swift`): `.mp4`, H.264 High Profile
Level 4.1, 1080 × 1920, 30 fps constant, progressive, no frame reordering,
a key frame every 30 frames, Rec. 709 tags; one stereo AAC-LC 48 kHz track
of digital silence (so WhatsApp never treats the film as a GIF); a target of
10 Mbit/s and a quantiser ceiling of 12.

**The ceiling is what buys quality, and A1's pictures set it.** The first
cut, graphics and screen captures only, used the App Preview's 10 (2.74
Mbit/s on average). A1's two photographs push in on every frame, and at 10
their grain cost 11.56 Mbit/s on average and **65.0 Mbit in the busiest
second — over Level 4.1's 62.5**. Measured on the A1 film (2026-10-18),
ceiling: average / busiest second / worst of 46 decoded frames — 11: 10.11 / 56.8
/ 48.0 dB; **12: 9.36 / 52.0 / 47.8**; 14: 7.08 / 39.2 / 47.0; 16: 5.40 /
31.6 / 45.5. At 12 the file is inside Level 4.1 with room, every graphic key
frame decodes at 55 dB or better, and only a photograph's grain falls under
48 dB (47.8 dB is 1.1 grey levels root mean square). Padding to a constant
rate was measured worse by the App Preview and is not done. A2 and R2 raise
the film to 11.18 Mbit/s on average and 49.7 Mbit in the busiest second
(2026-10-18) — S5's live scroll over the cover photo costs 30 Mbit more,
S7b's 0.63 s more of a photograph 24 Mbit more: inside the 12-Mbit/s
average verify accepts and Level 4.1's 62.5. R3 leaves them at 11.16 and
49.8 (2026-10-19).

## Verify — 38 checks

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
  box and line box (S1's stroke among them) inside the storyboard's safe
  zone (x 65–1015, y 269–1248) on every one of the 900 frames, and nothing
  in the right-hand rail (x > 850, y > 1152); the cover frame, the cover
  picture and the end card inside the 4:5 feed crop, and **the cover
  picture's headline at least 40 px below the crop's top** (R3); no
  character drawn as a missing glyph;
  every timed line on screen at least max(1.5 s, characters ÷ 15 + 0.5 s),
  **with no exception** (R2: S7b's caption 2.63 s of 2.63); the logo on
  screen at most 25 % of the film; **no two of S4's bubbles ever overlap**
  (their whole boxes, clipped or not); **no card moves more than 410 px
  between two frames**; **no card box enters S2's lockup's clear space**
  (the mark and the unit, half the mark's height all round) **nor the
  tagline's line while they show** (R2); **A1's pictures never smaller than
  their fill and never larger than their push-in** (the largest scale
  reported);
- **the build** (with `--work`): take1b's exported ranges against the
  take's own map (each hold shows the picture its live range starts or
  ends on; a live range never goes back; no picture later than its
  instant; S7's `skip` shows the picture its range ends on and stands for
  exactly one frame); take5b's drag exported whole and each S5 frame on the
  picture nearest the plan's target, moved by exactly the remainder, never
  back (R3); **S5's scroll steps measured on the composed frames** (a
  sub-pixel match of the card below the cover's fade): never back, none
  above 1.6 × the mean of its two neighbours + 0.5 px, the first no larger
  than the next five, within 0.35 px of the scroll the frames were drawn
  at (R3; on the third render's frames it fails: 25 steps above, a 14.9-px
  first step); S5's phone row white on every composed frame that shows
  it — through the page's own scroll as at the camera stops — and on frames
  decoded from the file across the scroll, the stop and the move; the key frames
  decoded against the composed ones (at least 48 dB, 47 where the ground is
  one of A1's photographs); **the white words over the pictures at 4.5:1 or
  more** against the brightest 5 % of what lies under each line (the cover
  picture's too); **S7b's caption at least 2 px above the stylist's
  braids** on every frame where it is whole (R3: 8 px into them at y 281,
  43 px at the third render's 316).

`verify` without `--work` runs the file and the plan, and says « NOT
checked » for the build.

## Deviations from the storyboard

Where a detail was ambiguous or could not be done as written, the calmer,
more precise option was taken:

1. **U+202F.** `onScreenText` carries plain spaces before « ? » and « : »;
   the visuals ask for U+202F, and every width the storyboard states was
   measured with it. `typeset()` sets it (a test holds both).
2. **One cut off the 0.5 s grid (R2).** S7b starts at frame 731 (24.367
   s), so « Plus de temps pour votre métier. » (32 characters) has the 2.63
   s the film's rule asks; the 19 frames come from S7's still stretches.
   It is a 200-ms dissolve, not a hard cut; its middle (24.45 s) is within
   2 frames of the 24.5 s beat. The plan reads the one off-grid frame from
   the storyboard and refuses any other.
3. **S5 (A2) at W 136.** On the top of the page the back button is a white
   disc to pt 110.3; from about W 132 it lies wholly under the solid band,
   and 136 leaves a margin (it ends at frame y 542). The W 300 stop of v2
   is gone: the 5-s beat holds the top of the page (about 1.4 s), the
   scroll (2.10 s), Services and the map at rest (0.3 s), and the hours
   (0.7 s at rest after a 400-ms `slow` camera move, as S3's).
   **S5's scroll is not 1:1 in time (R3)**: the take's own pictures, in its
   order, chosen by scroll position on the fitted cosine (2.095 s against
   the take's 2.306-s drag) and moved by at most 5.56 capture px (1.9 pt).
   The headline is 78 px, not 84: « Photos, tarifs, horaires : » measures
   965 px at 84, over the column and the safe zone, and cannot break
   elsewhere.
4. **S1's framing (A1 as built — the black band kept, the owner's answer
   of 2026-10-18).** To
   bring the notebook's crossing above the caption zone the picture sits
   320 px above its natural place: its bottom edge fades into black (the
   bottom 17 % of the hook is black, under the Reels caption). The headline
   block sits at y 280, the top of the safe zone (R2; it was 316 and its
   second line sat on her hairline). The stroke runs from the pen tip to
   the right page's edge (x 246.8–735), not across the phone on the counter,
   with a soft shadow so it reads on the white page; its thickening ends at
   2560 px (at 2400 both top corners would stay uncovered: a shorter stroke
   needs a wider page).
5. **S4's column edge.** Entering one slot lower, a bubble would sit below
   the safe zone and, for b3, under the rail; nothing below y 1152 is drawn,
   so it rises into view out of the column's edge.
6. **S3's card enters at 6.10 s (R2)**, not 6.00: it then reaches S2's
   clear space only once the lockup has left; frames 180–182 are paper and
   the leaving lockup.
7. **S7's timing (A1, R2: 20.0–24.367 s).** The holds give way, never the
   action: the pre-tap hold 18 frames (was 21), the first live range 19
   frames (was 26: it ends where the take stops changing, 32.765 s), the
   unfilled form's hold 2, the filled form 8 (was 20, before that 28), the
   last hold 5 (was 38); the headline fades out 24.167–24.367, then the page
   dissolves into S7b. The « Libre » disc fades out over 20.90–21.10, gone on
   the first frame of the push (the storyboard's 21.30 put it over the
   form). The snackbar keeps its 0.9 s.
8. **S8 re-timed (A1: 27.0–30.0 s).** The mark keeps its 0.6-s loader timing,
   so the re-timing is not strictly proportional: the dot at +0.05, the draw
   at +0.10 and the tile at the draw's end − 0.05 as before; the wordmark and
   the CTA follow on the 50-ms `stagger` (27.70, 27.75) so the CTA keeps its
   reading time (2.25 s of 2.23). S7b's picture dissolves into the card
   (`base`), the one transition A1 leaves open.
9. **The push-ins** run over A1's spans (S1 0–2.50 s, S7b 24.367–27.00 s) and
   hold while the picture leaves (S1 under the thickening page, S7b in its
   dissolve).
10. **S8's dot and draw overlap** (27.05–27.15 and 27.10). The stroke's width
    follows the dot's growth until the dot is whole, so the pen never jumps.
11. **The pattern's feather** fades whole marks, not pixels.
12. **The widest bubble** is b3, « Vous fermez à quelle heure ? » 22:47:
    842 px, x 90–932 (the storyboard's 809 px is b1's). Inside the zone and
    above the rail.
13. **take5b's rest after the scroll** is the picture presented at 28.500 s
    (v2 held the one at 28.665 s, « 30.000 s »: an encoder refresh of the
    same picture); the scroll's target ends on it (R3: the picture chosen at
    the rest is the hold's own).
14. **S3's touch point** follows the App Store film's verified, picture-
    followed path (`final/film.json`, its S1 drag, take sha256 checked)
    7.0 s later — the storyboard's « 7.61–8.36 » is that path's timing.
15. **Round caps.** The fast loader Lottie strokes its mark with butt caps
    (`lc: 1`); the storyboard and the SVG say round. Round.
16. **The tile's continuous corner** is a superellipse (n ≈ 4.9) that meets a
    63-px rounded corner on the diagonal.
17. **Grid phase.** The pattern's rows are centred on the frame's middle and
    its columns on x 540 (the storyboard gives the pitches, not the phase).
18. **Bit rate and quantiser** — above: 11.16 Mbit/s at a ceiling of 12
    (R3; 11.18 in the third render, 9.36 before A2's live scroll and R2's
    longer S7b), and a 47-dB floor for the photographs' key frames.
19. **Not built**: the 13.5-s cut-down and the post caption the storyboard
    lists among its deliverables — not asked of this tool.
20. **S7's frame 690 (R3)** holds the loading picture: one take picture
    (130.985 s) is skipped, a 33-ms departure from 1:1, declared as a
    `skip` and checked.
21. **S7b's caption at y 269 (R3)**, 47 px above the other headlines, not
    the review's ~35: at y 281 « pour » still met the bun from about frame
    780 (8 px into it at frame 808); 269 is the safe zone's top, and its
    line box sits on it (0.0 px in, its ink about 20 px lower).
22. **The cover is a composed picture (R3)**, not a frame of the film: its
    headline is 30 px lower, so its second line ends on her hairline (frame
    0 keeps it above).

## What the footage still carries (the storyboard's risks)

The empty phone field (S7, about 21.43–21.97 s, through the dissolve) is the
take's; since the take only #611/#614 touched it, and the empty field reads
the same — « +225 », « Téléphone du client », a « 0/10 » counter, now the
app's own instead of the package's (read in `phone_number_field.dart`, not
filmed). The two « Yao K. » rows are on screen together only while « Ma
journée » slides back in and the camera pans — frames 691–699, 23.03–23.30
s, 0.30 s (the first render showed both for about 2.4 s); only a re-take
under another name removes them. « Tarifs » stays one tap away. S5's cover
photo and logo are the demo salon's own; the owner confirmed their free
licence; still to be recorded: the source links of Maison Nala's cover and
logo, owed before posting.

## Posting step — the AI pictures

S1 and S7b are the owner's AI-generated pictures (photorealistic people).
When posting: **turn on TikTok's « AI-generated content » label, and Meta's
« AI info » disclosure** on Instagram and Facebook; the post caption must
not imply a real salon or a real customer. The film itself never captions
them as real people, customers or a testimonial.

## Tests

```
python3 tool/marketing_video/reel.py selftest
```

Thirty-five tests, about twelve seconds. Files written by the App Preview's test
writer (`TestClip.swift`), never by the Reel's encoder: a right file of 900
frames passes every file check; a 2-s file with a 440 Hz tone at High@4.0
fails on exactly « 900 frames », « duration 30.000 s », « sound is silent »
and « profile and level »; a file without a sound track fails on « tracks »
and « sound track ». The film's own frames pass the safe zone; a word moved
below it fails it; a word under the rail fails the rail. The film's own
motion passes; two bubbles drawn over each other fail; a card that jumps
500 px fails; a picture enlarged past its push-in, or short of the width,
fails; every line meets the reading rule with no exception, and S7b's
caption at A1's 2.0-s beat fails it by name; S3's card entering at 6.00 s
fails « S2's clear space kept » at frame 183; an arriving bubble is never
more opaque than its share above the column's edge; take5b's mask follows
the scroll map and stops at the bar, a row moved off its rectangle is
refused, and so is a map 2 pt off where the row is under the bar; every
strike starts as a short stroke. R3: the third render's S5 cadence fails
« S5 scroll smooth » by name (a 14.9-px first step, steps above 1.6 × their
neighbours), on its numbers and measured on pixels of a textured page moved
by it; the plan's target passes and the pixel measure finds a known
sub-pixel move to 0.1 px; a step that goes back fails; a `skip` holding the
picture its range ends on for one frame passes, one on another picture or
two frames long is refused, and S7's skip sits between its two live
ranges; S5's frames on the nearest picture pass, a frame on a farther
picture or chosen by time is refused; the cover picture keeps 40 px above
its headline in the 4:5 crop, and the film's own frame 54 (11.0 px) fails. A storyboard that no longer says a
transcribed number is refused; one carrying `_ownerDecisions` is refused;
the words carry French spacing; every width the storyboard measured comes
back from the faces the tool draws with.
