# App Store App Preview — MyWeli Pro

Turns a raw iOS Simulator recording into the App Preview shown before the
screenshots on the App Store: « Geste après geste », French, portrait,
886 × 1920, 30 frames per second, 15 to 30 s.

The film is specified in `docs/design/pro-app-preview.md`. This tool is the
sibling of `tool/app_store_screenshots/`: the same paper, mark, type, card,
border and shadow — imported from it, not copied — with a live capture in the
card instead of a still.

Nothing is installed: Xcode's `swiftc` and AVFoundation, Python 3 with Pillow
and numpy, `rsvg-convert`. `ffmpeg` is not used.

```
python3 tool/app_store_preview/preview.py build \
    --take take.mov --gestures gestures.json \
    --out build/app-store/pro/preview/final
```

Outputs are build products (`build/` is ignored by git): `preview.mp4`,
`poster.png`, `contact-sheet.png`, `cuts.txt`, `edit.json`, `verify.txt`.

## What is in here

| File | What it does |
|---|---|
| `storyboard.json` | The approved captions, shots and timings. The one source for the film's words and numbers. |
| `preview.py` | The command: `build`, and each step on its own (`scan`, `bursts`, `check`, `verify`, `sheet`, `selftest`). |
| `edit.py` | The edit list: finds each gesture in the take, proposes what to keep, and **refuses** an edit list that breaks the editing rule. |
| `frames.py` | Composes each frame: the stills' frame, captions and their cross-fade, the capture in the card, the touch point. |
| `brand.py` | Reads the colour and motion tokens from the app's theme files and imports the stills' composer. |
| `verify.py`, `mp4.py` | Read the written file back and check every requirement. `mp4.py` parses the file's bytes itself, without AVFoundation. |
| `swift/Conform.swift` | Reads the take: every frame's time and how much changed; exports kept ranges at 30 fps by frame-hold. |
| `swift/Encode.swift`, `Writer.swift` | Write `preview.mp4`. Nothing to configure. |
| `swift/Inspect.swift` | AVFoundation's reading of a written file; decodes frames and sound for `verify`. |
| `swift/TestClip.swift` | Tests only: writes synthetic takes and films that are wrong on purpose. |
| `tests/` | The self-tests, and `mutations.py`, which breaks each check in turn and watches a test go red. |

The Swift helpers are compiled on first use into `build/bin/` and rebuilt when
their sources change.

## How a film is made

1. **scan** — every frame of the take, in presentation order: its time (in
   the take's own ticks, never rounded) and how many pixels differ from the
   frame before.
2. **propose** — `edit.json`: the ranges of the take that are kept, the
   pictures that are held, where each caption changes and where each touch
   point is. `cuts.txt` says the same in plain lines.
3. **check** — the edit list against the editing rule below. A refused edit
   list stops the build; nothing is written after it.
4. **export** — the kept ranges at a constant 30 frames per second, by
   *frame-hold*: a film frame shows the last picture the take presented at or
   before its instant. Never a blend. Swift and Python each work out which
   picture every film frame shows; the build stops if they disagree.
5. **compose** — each frame at 886 × 1920.
6. **encode** — `preview.mp4`.
7. **sheet** — `contact-sheet.png`, two frames per second **decoded from the
   written file**, and `poster.png`.
8. **verify** — the written file, read back. Non-zero exit on any miss.

## The editing rule

App Review 2.3.4 asks for real captured footage. The simulator is driven one
gesture at a time, with seconds between gestures, so a take is mostly waiting.
The tool removes the waiting and nothing else.

- **From a touch-down to the last change on screen before the next
  touch-down, the take plays once, in order, at its own speed.** No cut, no
  hold, no change of speed inside that window. There is no way to write a
  speed in an edit list.
- **Time the app spends waiting on itself stays.** A loader that spins, a
  snackbar that leaves after its four seconds, a list that arrives after a
  network call: all of it is inside the window of the gesture that caused it,
  still stretches included. Only the still stretch that *ends at a touch-down*
  — the app waiting for the finger — may be shortened.
- **A rest may be lengthened** by holding its picture.
- **A cut only jumps between two pictures that are the same picture.** The
  frame held before a cut is compared directly with the frame the film
  resumes on.
- **A blinking text caret alone counts as nothing changing.** While a field
  has focus the caret blinks for ever; a stretch where the only change is a
  caret-shaped box (at most 6 × 34 points, at least 10 points tall) is
  treated as still, and may be cut. The caret can therefore skip a beat at a
  cut, and stands still during a hold. `cuts.txt` lists the caret frames in
  every cut, with their box.
- The film starts on a screen that has been still for at least 0.3 s, and
  ends on a hold of the final screen.

`edit.check` re-derives the windows from the scan and the gesture log — it
believes nothing an edit list says about them — and refuses with a code:

| Code | Refused |
|---|---|
| `E_PROTECTED` | a cut or a hold between a touch-down and the end of the app's response |
| `E_CHANGE_REMOVED` | a cut over a frame where the screen changes |
| `E_ENDPOINT` | a cut between two pictures that differ |
| `E_SHAPE`, `E_GRID` | anything but a kept range or a held instant (a speed, a frame count on a range); a range that is not whole frames |
| `E_ORDER` | going back in the take |
| `E_START` | starting before the take's first picture, or while the screen still changes |
| `E_TAKE` | an edit list made for another take (file hash) |
| `E_LENGTH`, `E_FINAL_HOLD`, `E_POSTER`, `E_CAPTION`, `E_TOUCH` | a film that is not the storyboard's: its length, its final hold, a poster frame outside it or on a touch point, captions out of order, a touch point moved by hand |

Every cut is logged in `cuts.txt`: the take range removed, the film time it
lands on, the frames inside it, and the comparison of its two sides.

### What counts as a change

The recording is lossy. A screen that does not change still decodes to
slightly different values, and the encoder keeps refining text edges after
the picture has stopped moving. On the probe clip of 2026-10-13 (8.3 s of
« Ma journée ») the loudest still frame had 500 pixels off by more than 16
levels and 1 off by more than 64; the faintest real change — the first dot of
the refresh spinner — had 5 off by more than 64. So a frame is a **change**
when at least 4 pixels moved by more than 64 levels, or at least 2000 by more
than 16 (`edit.py`, `STRONG_MIN`, `SOFT_MIN`).

These numbers come from one short clip. `cuts.txt` prints, for every take,
the loudest quiet frame and the faintest change frame: read them. If they
crowd the thresholds, look at those two frames before trusting the cuts.

The take's first picture counts as a change: the recorder writes a frame when
the screen changes, and only then.

### How a touch-down is found

The screen cannot show the instant a finger lands. The earliest evidence is
the first frame the app changes.

- The gesture log says roughly when each gesture was made (`near_s`). The
  tool takes the burst of changes that **starts** within ±0.5 s of it; none,
  or two, is a refusal (`E_MATCH`).
- **Tap**: the touch-down is placed 100 ms (the `fast` token) before the
  first changed frame — the length of the touch point's own fade-in, so it is
  fully there when the app answers.
- **Drag**: Flutter starts a drag once the finger is 18 points from where it
  landed. The touch-down is placed that far back along the logged path, or at
  `down_s` when the log gives it.
- **Typed text**: no touch point; the window starts at the first character.
- Nothing changes on screen between a touch-down and the first changed
  frame, so a few frames of error here move the touch point, never the
  footage. `cuts.txt` prints how far the first change is from the touch; a
  large distance on a tap means the wrong burst was matched.

## The frame

The stills' own, from `tool/app_store_screenshots/compose.py`, at its layout
table × 886/1320 (`frames.Layout`, the one place the ratio is applied). A
test composes a film frame and the stills' frame from the same caption and
capture and requires them identical, pixel for pixel.

- **Colours** are read by name from `mobile/lib/core/theme/colors.dart`
  through the stills' `tokens()`.
- **Captions** sit in the paper and never reach the capture (checked). A
  caption changes by cross-fading in place over `base` (200 ms, `easeInOut`,
  §9 of the design system: « cross-fades »). Pixels that are the same in both
  captions do not move at all.
- **The touch point** is a disc 48 points across (the design system's touch
  target) in `primary` at 12 % with a 1.5-point ring at 45 %; in `secondary`
  (white) where it lands on a dark or green fill. It fades in over `fast`,
  stays 200 ms on a tap, follows a drag point for point, and fades out over
  `base`. The card clips it.
- **Motion** names tokens only (`storyboard.json` → `motion`); the durations
  and curves are read from `mobile/lib/core/theme/motion.dart` and evaluated
  by time with Flutter's own `Cubic` bisection.
- Everything that moves inside the card is the app.

Two things the capture brings that the stills do not have:

- The recorder draws the **Dynamic Island** as a black pill at the top of the
  screen; `simctl io screenshot` does not. It is left as recorded.
- The recorder tags its file Display P3 with the sRGB curve. The tool takes
  the decoded values as they are, as the stills take a screenshot's: greys
  are identical, and a saturated colour is carried exactly as in the stills.
  Decoded greys were within one level of a screenshot of the same screen.

## The file

`MovieSpec.appPreview` in `swift/Writer.swift`: `.mp4`, H.264 High Profile
Level 4.0, 886 × 1920, 30 fps constant, progressive, no frame reordering, a
key frame every second, Rec. 709; one stereo AAC-LC track, 48 kHz, declared
256 kbit/s, digital silence. Apple marks the sound track as required; the
film has no sound.

**11 Mbps is the encoder's target, not the file's rate.** A film that is a
still screen most of the time cannot spend it: the probe cut came out at
1.1 Mbps, and the silent track at 2 kbit/s. What the picture needed instead
was a ceiling on the quantiser — without one each key frame was softer than
the frames after it (44 dB against 51 dB on a still frame); with it, every
frame measured 54 dB or better. Forcing a constant 11 Mbps pads the file and
measured worse; it is not used. Whether App Store Connect minds a file below
its 10–12 Mbps target is **UNVERIFIED** — nothing has been uploaded.

`verify` checks the written file (24 checks with the poster): container,
codec, profile and level, exactly 886 × 1920 in the bitstream and in every
header, upright, square pixels, progressive, 8-bit 4:2:0 with no alpha, every
sample exactly 1/30 s, no reordering, frame count and duration equal to the
storyboard's and within 15–30 s, bit rate, exactly one video and one sound
track, both enabled, AAC-LC stereo at 48 kHz, the sound as long as the film
and decoding to zeros, under 500 MB, and the frame decoded at the poster time
against the composed poster. Three readers must agree: the tool's own parse
of the file's bytes, AVFoundation, and `avmediainfo`.

A trap worth knowing: asked for an odd size, AVFoundation writes the next
even one down **without a word** (885 → 884). H.264 4:2:0 has no odd sizes.

## The gesture log

Written by whoever drives the simulator. Points are device points (402 × 874
on the iPhone 17 Pro), times are seconds of the take.

```json
{
  "device_points": [402, 874],
  "gestures": [
    {"id": "swipe-arrive", "kind": "drag", "near_s": 4.1,
     "path": [[60, 300, 0], [240, 300, 350]]},
    {"id": "tap-arrive", "kind": "tap", "near_s": 7.6, "at": [70, 300]},
    {"id": "type-nom", "kind": "type", "near_s": 31.0},
    {"kind": "tap", "near_s": 52.0, "film": false}
  ]
}
```

- `id` — the storyboard's gesture id; the log must have the storyboard's
  gestures in the storyboard's order (`optional` ones may be absent).
- `near_s` — when the screen starts to answer, to within ±0.5 s
  (`tolerance_s` overrides it for one gesture). Read it from
  `preview.py bursts`.
- `at` — where a tap lands. `path` — a drag: `[x, y, ms since touch-down]`,
  from 0. `down_s` — optional, the drag's touch-down if it is known.
- `"film": false` — something done after the film's last gesture (leaving
  the screen before stopping the recorder). The film ends before it. Without
  this line the tool takes those changes for the app's own and keeps them.

## The storyboard

| Key | Meaning |
|---|---|
| `film.duration_s`, `poster_s`, `final_hold_min_s` | The film's length, the poster frame's time, the shortest final hold accepted. |
| `motion.*`, `touch.tap_dwell` | Names of motion tokens — nothing else is accepted. |
| `touch.*` | The touch point: size and ring in points, opacities, and the luminance under which it turns white. |
| `timing.rest_s` | No change for this long ends a burst of changes. |
| `timing.tail_s` | Real footage kept after a response's last change, before any hold or cut. |
| `timing.lead_in_s` | The first screen held before the first touch. |
| `timing.caption_lead_s` | A shot's caption is in place this long before its first touch-down. |
| `timing.sync_tolerance_s` | How far `near_s` may be from where a burst starts. |
| `timing.rehearsal_*` | Rehearsals only: the hold given to a shot with no footage. |
| `captions` | Two hand-set headline lines; zero to two hand-set sub-lines. ` ` is the narrow no-break space French sets before « ? ». |
| `shots[].gestures[].rest_after_s` | The hold after a gesture's response, on top of `tail_s`. |
| `shots[].caption_after` | For a shot with no gesture: the caption changes this long after the named gesture's own burst ends. |

Every time must be a whole number of frames.

## Runbook — the final take

What is **observed** below was seen on the probe of 2026-10-13 or in this
tool's tests; steps on the simulator that this tool's author did not perform
are marked **UNVERIFIED**.

1. **Stage.** iPhone 17 Pro simulator (402 × 874 points, 1206 × 2622
   pixels), language and region as for the stills
   (`docs/design/pro-app-store-screenshots.md` §7), the build that is going
   to review, the day staged as `docs/design/pro-app-preview.md` §5 says. The
   owner signs in. The sign-in code is never typed by a script and never
   written down. If the app is signed out, stop.
2. **Status bar.**
   `xcrun simctl status_bar <udid> override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100`
3. **Record.**
   `xcrun simctl io <udid> recordVideo --codec h264 --mask ignored take.mov`.
   Wait for « Recording started ». Stop with Ctrl-C and wait for « Wrote
   video ». Observed: H.264, 1206 × 2622, no sound, a frame only when the
   screen changes, frames out of order in the file.
4. **Wake the recorder, then wait.** The recorder writes a frame when the
   screen changes. The probe's first picture, at 0.000 s, shows the tapped
   day already selected above what reads as the previous day's list — the
   first frame of the tap's answer, not the screen before it. If that reading
   is right, a take has no picture of the screen *before* its first change.
   So make the screen change once before the first gesture and let it rest
   at least two seconds. **UNVERIFIED** which harmless change is best
   (re-applying the status-bar override with another minute, then 9:41 again,
   is the obvious candidate) and that the recorder behaves this way every
   time. `preview.py bursts` prints when the take's first picture is. The
   tool refuses a take that begins on the first gesture's answer
   (`E_NO_REST`), and a film that starts less than 0.3 s after the take's
   first picture (`E_START`).
5. **The gestures**, one at a time, in the storyboard's order. After each,
   wait until the screen is still, then two seconds more. Note for each: its
   storyboard id, where it landed in points, and for a drag its path and
   duration. After « Créer le rendez-vous », wait until the snackbar has gone,
   then two seconds, then stop the recorder. Anything done before stopping
   goes in the log with `"film": false`.
6. **Find the times.**
   `preview.py scan take.mov --out scan.json`, then `preview.py bursts
   scan.json`: one line per burst of changes, with where on screen. Write each
   gesture's `near_s` from it. A burst with no gesture is the app on its own.
7. **Build.** `preview.py build --take take.mov --gestures gestures.json
   --out <folder>`. If it refuses on length (`E_LENGTH`, `E_POSTER`,
   `E_FINAL_HOLD`), the real responses are longer than the storyboard
   allowed for: shorten `rest_after_s` values, never the footage.
8. **Read `cuts.txt`.** Each gesture sits on the burst you expect; a tap's
   first change is a few points from the touch; the loudest quiet frame is
   well under the thresholds; no cut lists change frames; caret boxes are
   where the caret is.
9. **Look.** `contact-sheet.png` and `poster.png`, next to
   `build/app-store/pro/overview.png`:
   - same paper, mark, type, card, border and shadow as the stills;
   - every caption is whole and changes where the story does;
   - the touch point is on the control when the app answers, and on the card
     it drags — play `preview.mp4` for this, a sheet cannot show it;
   - the poster frame (18.0 s) has no snackbar and no touch point;
   - nothing that must not be shown: the sign-in screen, an offer or « Mon
     abonnement », a system alert, « Compte de démonstration — … », a phone
     number, a real person's name, an iOS keyboard.
10. **`verify.txt` says PASS**, with no « REHEARSAL ». The upload is the
    owner's, on an explicit go; this tool uploads nothing.

A **rehearsal** (`--rehearsal`) accepts a take that does not have every
gesture: shots without footage become holds with their captions. It proves
the chain; it is written to `preview-rehearsal.mp4` and says so in
`verify.txt`.

## Tests

```
python3 tool/app_store_preview/preview.py selftest          # about two minutes
python3 tool/app_store_preview/tests/mutations.py           # on a clean, committed tree
```

`selftest` needs no simulator. It covers the tokens and curves, the frame
against the stills', caption layout, every refusal of the editing rule on
takes whose answer is known, the bit-level parsers on bytes copied from real
files, and an end-to-end run on a synthetic take with the recorder's shape.
It then writes some twenty films that are wrong on purpose — no sound,
14.9 s, 884 wide, a header that claims 887, 25 frames per second, a variable
frame rate, reordered frames, a tone, 44.1 kHz, mono, a disabled track, a
rotated picture… — and requires the checker to name exactly that fault.

`mutations.py` removes each check from the code in turn and requires a named
test to fail. A mutation whose anchor is no longer in the source is an error,
not a pass.

## Known limits

- The change thresholds and the caret box are calibrated on one probe clip
  and on synthetic takes. The app's real caret has not been recorded:
  **UNVERIFIED** that it fits the box.
- A burst is matched to a gesture by time alone.
- The recorder's Dynamic Island pill is in the footage.
- Whether App Store Connect accepts pure digital silence, this bit rate, or a
  brand frame around the capture is not known until a file is uploaded.
