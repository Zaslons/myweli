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

A **rehearsal** on other gestures is a `--variant` of the storyboard (below):
the same command with `--variant dry-run` writes `preview-rehearsal.mp4`.

## What is in here

| File | What it does |
|---|---|
| `storyboard.json` | The approved captions, shots and timings — the one source for the film's words and numbers — and its `variants`: rehearsals on other gestures. |
| `preview.py` | The command: `build`, and each step on its own (`scan`, `bursts`, `check`, `verify`, `sheet`, `selftest`). |
| `edit.py` | The edit list: tells a change from a caret, finds each gesture in the take, proposes what to keep, and **refuses** an edit list that breaks the editing rule. |
| `track.py` | Follows each drag in the picture: how far the content under the finger has moved in every frame. Only the touch point depends on it. |
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
2. **follow** — `track.json`: for each drag, how far the picture has moved
   under the finger in each frame.
3. **propose** — `edit.json`: the ranges of the take that are kept, the
   pictures that are held, where each caption changes and where each touch
   point is. `cuts.txt` says the same in plain lines.
4. **check** — the edit list against the editing rule below. A refused edit
   list stops the build; nothing is written after it.
5. **export** — the kept ranges at a constant 30 frames per second, by
   *frame-hold*: a film frame shows the last picture the take presented at or
   before its instant. Never a blend. Swift and Python each work out which
   picture every film frame shows; the build stops if they disagree.
6. **compose** — each frame at 886 × 1920.
7. **encode** — `preview.mp4`.
8. **sheet** — `contact-sheet.png`, two frames per second **decoded from the
   written file**, and `poster.png`.
9. **verify** — the written file, read back. Non-zero exit on any miss.

## The editing rule

App Review 2.3.4 asks for real captured footage. The simulator is driven one
gesture at a time, with seconds between gestures, so a take is mostly waiting
(the rehearsal take of 2026-10-13: 122.75 s for 15 s of action). The tool
removes the waiting and nothing else.

- **From a touch-down to the last change on screen before the next
  touch-down, the take plays once, in order, at its own speed.** No cut, no
  hold, no change of speed inside that window. There is no way to write a
  speed in an edit list.
- **Time the app spends waiting on itself stays.** A loader that spins, a
  snackbar that leaves after its four seconds, a list that arrives after a
  network call: all of it is inside the window of the gesture that caused it,
  still stretches included. Only the still stretch that *ends at a touch-down*
  — the app waiting for the finger — may be shortened.
- **A typed key is a touch-down.** Text typed one key at a time is one
  gesture in the storyboard and as many windows as keys: the wait before each
  key may be cut, the letter appearing may not.
- **A rest may be lengthened** by holding its picture.
- **A cut only jumps between two pictures that are the same picture.** The
  frame held before a cut is compared directly with the frame the film
  resumes on.
- **A blinking text caret alone counts as nothing changing** (below). The
  caret can therefore skip a beat at a cut, and stands still during a hold.
  `cuts.txt` lists the caret frames in every cut, with their box.
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
| `E_VARIANT` | an edit list made for a rehearsal offered as the film's, or the reverse |
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

`cuts.txt` prints, for every take, the loudest quiet frame and the faintest
change frame: read them. On the rehearsal take the loudest quiet frame had 3
strong pixels — a caret half-way through its fade — and the faintest change
11.

The take's first picture counts as a change: it has nothing before it to be
measured by.

### What a caret is

Read on the rehearsal take, the app's own: the caret is 2 points wide and 23
to 26 tall, and it **fades** in and out. Most of its frames stay under the
thresholds above. Those that pass show the whole caret, or a corner of it —
its last row of pixels, 1 × 1 point — always in the same place. Size alone
does not tell it: a typed « . » changes a box 5.3 × 26 points, and a typed
space moves the caret and nothing else. So a caret is told by **where** it
is:

- it is no bigger than 3 × 34 points;
- it is first seen, at least 10 points tall, **inside the last burst of
  changes** — the field that took focus, the character just typed, the form
  that scrolled. A caret-shaped box anywhere else is the caret arriving
  somewhere new: a change;
- from then on, whatever stays within that one column is the caret,
  fragments included, until the next change.

The two sides of a cut are held to the same rule: they may differ by the
caret of the stretch the cut is in, where it blinks, and by nothing else.

The minimum height keeps small real changes out: the probe's refresh spinner
grows by boxes of 5 × 1 to 17 × 15 pixels inside the list that has just
moved.

### How a touch-down is found

The screen cannot show the instant a finger lands. The earliest evidence is
the first frame the app changes.

- The gesture log says when each gesture was asked for and when the driver's
  call came back (`after_s`, `before_s`). The tool takes the **first** burst
  of changes that starts in between; none is a refusal (`E_MATCH`). A log
  written by hand may say `near_s` instead: the burst that starts within
  ±0.5 s of it; none, or two, is a refusal.
- **Tap**: the point appears 200 ms (`touch.tap_lead`) before the first
  changed frame — whole for 100 ms on the control before the control reacts
  — and starts to leave 100 ms after it (`touch.tap_dwell`).
- **Drag**: timed by the picture, below.
- **Typed key**: no touch point (the key is not on the screen); its kept
  range starts 100 ms before the letter shows.
- Nothing changes on screen between a touch-down and the first changed
  frame, so a few frames of error here move the touch point, never the
  footage. `cuts.txt` prints how far the first change is from the touch; a
  large distance on a tap means the wrong burst was matched — or, as with the
  back arrow of the rehearsal, that the first thing to change was elsewhere
  (a field losing focus).

### How a drag is timed

A gesture log says where a drag went. Its times are the ones the driver
**asked** for: on the rehearsal take, drags logged at 16 ms a sample reached
the app at 25 to 29 ms a sample, and the first frame of one came late. Timed
by the log, the touch point trailed the card it was dragging.

While a finger drags something, what was under it moves with it. `track.py`
looks, in every frame of the drag, for the patch of the resting picture that
was under the touch-down point, and measures how far along the drag's axis it
has gone. On the rehearsal take that distance was, in every frame, the
position of one of the logged samples — to a third of a point on the swiped
card, to four points on the scrolled form: the picture follows the finger
with nothing lost at the start. So:

- **while the picture follows**, the point is where the log has the finger
  when it is that far along — one position a frame, held until the next
  frame, as the picture is;
- **before** the first frame that moved, and **after** the picture stops
  following (a pane fully open, a list at its end), the log's own times are
  used, 1:1;
- the point leaves no later than the first frame in which the picture
  **turns back** (a list springing back from its end): the finger has let go
  by then.

A drag that cannot be followed — nothing to recognise under the finger, or a
path that turns back on itself — is timed by the logged path alone, and
`cuts.txt` says « NOT followed in the picture ». `down_s` in the log
overrides both.

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
  captions do not move at all; two different headlines are superimposed for
  the middle frames of the fade.
- **The touch point** is a disc 48 points across (the design system's touch
  target) in `primary` at 12 % with a 1.5-point ring at 45 %; in `secondary`
  (white) where it lands on a dark or green fill. It fades in over `fast` and
  out over `base`. The card clips it.
- **Motion** names tokens only (`storyboard.json` → `motion`, `touch.tap_*`);
  the durations and curves are read from `mobile/lib/core/theme/motion.dart`
  and evaluated by time with Flutter's own `Cubic` bisection.
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
still screen most of the time cannot spend it: the rehearsal cut of
2026-10-13 came out at 2.4 Mbps on average, 7.2 Mbps in its busiest second,
and the silent track at 2 kbit/s. What the picture needed instead was a
ceiling on the quantiser — without one each key frame was softer than the
frames after it (44 dB against 51 dB on a still frame); with it, every frame
measured 54 dB or better. Forcing a constant 11 Mbps pads the file and
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

Written by whoever drives the simulator, one entry per call, in the order the
calls were made. Points are device points (402 × 874 on the iPhone 17 Pro);
times are seconds of the take — the wall clock minus the instant the recorder
printed « Recording started » (on the rehearsal take every gesture's first
change fell between its two times).

```json
{
  "device_points": [402, 874],
  "gestures": [
    {"id": "swipe-arrive", "kind": "drag", "after_s": 1.602, "before_s": 8.12,
     "path": [[110, 410, 0], [110.4, 410, 16], [111.8, 410, 32], [250, 410, 448]]},
    {"id": "tap-arrive", "kind": "tap", "after_s": 9.4, "before_s": 12.9, "at": [71, 410]},
    {"id": "type-nom", "kind": "type", "keys": [
      {"after_s": 48.917, "before_s": 52.36}, {"after_s": 52.39, "before_s": 55.538}]},
    {"kind": "drag", "after_s": 103.0, "before_s": 114.0, "film": false}
  ]
}
```

- `id` — the storyboard's gesture id; the log must have the storyboard's
  gestures in the storyboard's order (`optional` ones may be absent).
- `after_s`, `before_s` — written just before the call that makes the
  gesture, and just after it returns. The driver's calls take 2 to 11 s and
  the touch lands somewhere inside: the tool finds where.
- `near_s` — instead of the two: when the screen starts to answer, to within
  ±0.5 s (`tolerance_s` overrides it for one gesture), read from
  `preview.py bursts`.
- `at` — where a tap lands.
- `path` — a drag: every sample **as it was sent**, `[x, y, ms since
  touch-down]`, from 0. The tool matches the picture to these positions; a
  path reduced to its two ends cannot be followed as well. `down_s` —
  optional, the drag's touch-down if it is known better than the picture
  tells it.
- `keys` — typed text, one entry per key pressed, each with its own times.
  Without `keys`, the text is one piece from its first letter on.
- `"film": false` — something done after the film's last gesture (leaving
  the screen before stopping the recorder). The film ends before it. Without
  this line the tool takes those changes for the app's own and keeps them.

## The storyboard

| Key | Meaning |
|---|---|
| `film.duration_s`, `poster_s`, `final_hold_min_s` | The film's length, the poster frame's time, the shortest final hold accepted. |
| `motion.*`, `touch.tap_lead`, `touch.tap_dwell` | Names of motion tokens — nothing else is accepted. |
| `touch.*` | The touch point: size and ring in points, opacities, and the luminance under which it turns white. |
| `timing.rest_s` | No change for this long ends a burst of changes. |
| `timing.tail_s` | Real footage kept after a response's last change, before any hold or cut. |
| `timing.lead_in_s` | The first screen held before the first touch. |
| `timing.caption_lead_s` | A shot's caption is in place this long before its first touch-down. |
| `timing.sync_tolerance_s` | How far `near_s` may be from where a burst starts. |
| `timing.rehearsal_*` | A rehearsal with gestures missing: the hold given to a shot with no footage. |
| `captions` | Two hand-set headline lines; zero to two hand-set sub-lines. ` ` is the narrow no-break space French sets before « ? ». |
| `shots[].gestures[].rest_after_s` | The hold after a gesture's response, on top of `tail_s`. For typed text: after its last key. |
| `shots[].caption_after` | For a shot with no gesture: the caption changes this long after the named gesture's own burst ends. |
| `variants.<name>` | A rehearsal on other gestures: its own `shots`, and values of `film` and `timing` laid over the film's. It cannot give captions, motion or the touch point. |

Every time must be a whole number of frames.

### Variants

A take that must not write to the salon cannot make the film's gestures: it
opens the « Arrivé » pane and closes it, fills the form and leaves it.
`variants.dry-run` is that take's storyboard — the film's frame, captions,
motion and rules, with other gestures. `--variant dry-run` selects it on
`build`, `bursts`, `check`, `verify` and `sheet`.

A variant is a rehearsal and only that. Its film is written to
`preview-rehearsal.mp4`, never `preview.mp4`; `cuts.txt` and `verify.txt` say
REHEARSAL and name the variant; its edit list is refused by a build of the
film (`E_VARIANT`), and the film's by a build of the variant. `verify` run by
hand says REHEARSAL when it is given `--variant`, or when the file's name
says so — a rehearsal that has been **renamed** and is checked against the
film's storyboard is not recognised: do not rename one.

## Runbook — the final take

Each step says where it comes from: **observed** on the rehearsal take of
2026-10-13 (a dry run: `variants.dry-run`), or **UNVERIFIED**.

1. **Stage.** iPhone 17 Pro simulator (402 × 874 points, 1206 × 2622
   pixels), language and region as for the stills
   (`docs/design/pro-app-store-screenshots.md` §7), the build that is going
   to review, the day staged as `docs/design/pro-app-preview.md` §5 says. The
   owner signs in. The sign-in code is never typed by a script and never
   written down. If the app is signed out, stop.
2. **Status bar.**
   `xcrun simctl status_bar <udid> override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100`
3. **Check the keyboard, without writing anything.** Open « Libre — 10:45 »,
   tick « Client sans numéro », tap the name field, take a screenshot, leave
   by the back arrow. Observed: no software keyboard in the rehearsal take —
   but its driver reported one earlier in the same session. With a keyboard
   up, « Total » and « Créer le rendez-vous » are behind it and the scroll of
   the storyboard does not show them: do not film until it is down.
4. **Record.**
   `xcrun simctl io <udid> recordVideo --codec h264 --mask ignored take.mov`.
   Note the wall clock when « Recording started » is printed: the gesture
   log's times count from it. Stop with Ctrl-C and wait for « Wrote video ».
   Observed: H.264, 1206 × 2622, no sound, a frame only when the screen
   changes (3453 frames in 122.75 s, none at all for stretches of nine
   seconds, some 2 ms apart), frames out of order in the file.
5. **Let the screen rest two seconds before the first gesture.** Observed:
   the take's first picture, at 0.000 s, was the resting screen, 5.4 s before
   the first change — a take does have a picture of the screen before it
   first changes. (The probe clip's first picture was already an answer; its
   first gesture came with the recorder's start.) The tool refuses a take
   that begins on the first gesture's answer (`E_NO_REST`) and a film that
   starts less than 0.3 s after the take's first picture (`E_START`).
6. **The gestures**, one call at a time, in the storyboard's order, each
   logged as above.
   - Wait until the screen is still, then a second more, between two calls.
     Observed: the driver's own latency gives 3 to 9 s, which is plenty; the
     tool needs half a second of stillness to tell two gestures apart.
   - **Drags**: send every sample and log them as sent. Observed: paths of
     29 and 40 samples 16 ms apart were followed frame by frame. (The driver
     reports that a path of 6 samples moved the card in three jumps.)
   - **The scroll to the total**: the form's end is 126 points away.
     Observed: a 170-point drag overshoots, and the list springs back for
     half a second — real, and half a second of film. A drag of about 128
     points arrives without it. **UNVERIFIED** on the device.
   - **Typed text**: one key per call, plain ASCII. Reported by the
     rehearsal's driver, not filmed: a name with an accent was pasted instead
     of typed, and an iOS alert came up. « Yao K. » has no accent.
   - **The name field** does not take focus by itself: it is tapped
     (`tap-nom`).
   - After « Créer le rendez-vous », wait until the snackbar has gone, then
     two seconds, then stop the recorder. Anything done before stopping goes
     in the log with `"film": false`.
7. **Build.** `preview.py build --take take.mov --gestures gestures.json
   --out <folder>`. If it refuses on length (`E_LENGTH`, `E_POSTER`,
   `E_FINAL_HOLD`), the real responses are longer than the storyboard allowed
   for: shorten `rest_after_s` values, never the footage. See « The time the
   final film has » below before the take, not after.
8. **Read `cuts.txt`.** Each gesture sits on the burst you expect; every drag
   says « followed in the picture »; the loudest quiet frame is under the
   thresholds; no cut lists change frames; caret boxes are where the caret
   is; every cut's two sides are « the same frame », « quiet » or « caret ».
9. **Look.** `contact-sheet.png` and `poster.png`, next to
   `build/app-store/pro/overview.png`:
   - same paper, mark, type, card, border and shadow as the stills;
   - every caption is whole and changes where the story does;
   - the touch point is on the control when the app answers, and stays on
     the same piece of the card or the list all along a drag — play
     `preview.mp4` for this, a sheet cannot show it;
   - the poster frame (18.0 s) has no snackbar and no touch point;
   - nothing that must not be shown: the sign-in screen, an offer or « Mon
     abonnement », a system alert, « Compte de démonstration — … », a phone
     number, a real person's name, an iOS keyboard.
10. **`verify.txt` says PASS**, with no « REHEARSAL ». The upload is the
    owner's, on an explicit go; this tool uploads nothing.

### The time the final film has

Measured on the rehearsal cut, with the storyboard's rests: the lead-in, the
swipe, the tap on the free slot, the form filled key by key and the scroll
take the film to **13.8 s** before the last tap. (The rehearsal's closing
swipe stands in for the tap on « Arrivé »; the two are about as long.)

Then the tap on « Créer le rendez-vous » opens one window that cannot be
cut: the loader, the form closing, the snackbar staying, the snackbar
leaving. « Rendez-vous créé » is a `SnackKind.success` — three seconds, read
in `mobile/lib/widgets/common/app_snack_bar.dart`; it has **not been
filmed**. With the « under about a second » the driver who staged the day
reported between the tap and the form having closed, that window is about
4.5 s, and the screen is not at rest before about **18.5 s**. The storyboard puts the poster frame at 18.0 s, on a screen
with no snackbar, in a 20 s film that ends on a hold of at least 3 s: that
does not fit, and the tool will refuse (`E_POSTER`, `E_FINAL_HOLD`) rather
than squeeze.

What gives, in the storyboard and nowhere else:

- 1.5 to 2 s taken from before the last tap — the lead-in, the rests after
  « Arrivé », after the free slot and after the scroll, and the scroll's
  overshoot (runbook, step 6) — at the price of a film that breathes less;
  or
- the poster frame a little later (about 19.5 s in a 22 s film). The poster
  was approved at 18.0 s: moving it is the owner's decision.

(The tap on « Arrivé » shows no snackbar when it succeeds — read in
`pro_journal_screen.dart`, not filmed.)

A **rehearsal** (`--rehearsal`) accepts a take that does not have every
gesture of the film: shots without footage become holds with their captions.
A take with *other* gestures is a variant (above).

## Tests

```
python3 tool/app_store_preview/preview.py selftest          # about three minutes
python3 tool/app_store_preview/tests/mutations.py           # about fifteen; on a clean, committed tree
```

`selftest` needs no simulator. It covers the tokens and curves, the frame
against the stills', caption layout, what a caret is on rows copied from the
rehearsal take, every refusal of the editing rule on takes whose answer is
known, typed keys, the drag followed on pictures drawn for it, the variants,
the bit-level parsers on bytes copied from real files, and an end-to-end run
on a synthetic take with the recorder's shape — twice: the film, and a
variant. It then writes some thirty files that are wrong on purpose — no
sound, 14.9 s, 884 wide, a header that claims 887, 25 frames per second, a
variable frame rate, reordered frames, a tone, 44.1 kHz, mono, a disabled
track, a rotated picture… — and requires the checker to name exactly that
fault.

`mutations.py` breaks each check in the code in turn — every refusal
silenced, every verification made to pass, numbers and comparisons bent, the
Swift helpers too — and requires a named test to fail each time. A mutation
whose anchor is no longer in the source is an error, not a pass, and so is a
refusal added to the code without being watched.

## Known limits

- The change thresholds are calibrated on one probe clip and one rehearsal
  take. What a caret is was read on one field of one screen.
- A burst is matched to a gesture by time alone: the first that starts
  between `after_s` and `before_s`. A driver that asks for a gesture while
  the app is still answering the one before would be matched to the wrong
  burst; the runbook's rests prevent it, and `cuts.txt` shows it.
- A drag is followed along one axis, on the content under its touch-down
  point. Where the picture does not follow the finger at all (a drag that
  only draws) the log's own times are used.
- The recorder's Dynamic Island pill is in the footage.
- Whether App Store Connect accepts pure digital silence, this bit rate, or a
  brand frame around the capture is not known until a file is uploaded.
