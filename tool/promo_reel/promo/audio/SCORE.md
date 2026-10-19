# The score format

A score is one YAML file that says, for one cut of the promo, everything the
soundtrack plays: the sections, the chord of every bar, the 16-step grid of
every instrument in every bar, and the **named cues** — the sounds tied to a
picture event, which SCENES addresses by id through `events.json`.

`score_30s.yaml` (14 bars) and `score_15s.yaml` (7 bars) are the two scores.
The 15-s one is its own score, re-written for that cut, never a splice of the
30-s audio. `score.py` loads and validates a score; anything it refuses is
listed with its location, for example
`cues[12] 'drop1.impact': pos '15.1.0' is past the cut's 14 bars`.

```
python -m promo.audio --score score_30s.yaml --out DIR      # or: --cut 30s
```

## The clock

The music is the clock (architecture contract, « Time base »): 112.5 BPM at
30 fps puts a beat on exactly 16 frames.

| unit  | frames | samples (48 kHz) | seconds |
|-------|-------:|-----------------:|--------:|
| 16th  | 4      | 6 400            | 0.1333  |
| beat  | 16     | 25 600           | 0.5333  |
| bar   | 64     | 102 400          | 2.1333  |

A **position** is written `bar.beat.step`: bar and beat count from 1, step is
the 16th inside the beat (0–3). `3.1.0` is the downbeat of bar 3.

    frame  = (bar - 1) * 64 + (beat - 1) * 16 + step * 4
    sample = frame * 1600

Positions are relative to the start of the cut. YAML reads `3.1.0` as text,
which is what the loader expects; write `3.1` and it is refused.

## Top level

```yaml
score: 1             # the format version
cut: 30s             # written into events.json
bars: 14             # the cut lasts bars x 64 frames, exactly
tempo: 112.5         # fixed: any other value is refused
key: C minor         # informative
swing: 0.56          # where the off-16th sits in its 8th (0.50 = straight)
sections: [...]
chords: {...}
patterns: {...}
tracks: {...}
cues: [...]
```

## Sections

```yaml
sections:
  - {name: hook, bars: 1-2}
  - {name: drop1, bars: 3-4}
```

The sections list every bar once, in order, with no gaps. They name the arc
(events.json and the analysis pictures carry them); they change no sound.

## Chords

```yaml
chords:
  1: Cm9          # a bar number: the chord from its downbeat
  4: F9
  10.3.0: G7b9    # a position: a change inside a bar
```

Bar 1 needs a chord. A chord holds until the next one. Symbols are a root
(`C`, `Eb`/`E♭`, `F#`…) and a quality: `m9`, `9`, `maj9`, `7b9`/`7♭9`, `m7`,
`7`, `maj7`, `m`, or nothing for a major triad.

The keys never need their notes typed in. A voicing is the chord's 3rd, 5th,
7th and 9th, each placed in one fixed twelve-semitone window (E♭3–D4). Every
pitch class has exactly one place in that window, so the promo's four chords
move into each other by steps:

| chord  | Rhodes / pad voicing | Rhodes left hand | log degree `1` |
|--------|----------------------|------------------|----------------|
| Cm9    | E♭3 G3 B♭3 D4        | C3               | C2             |
| F9     | E♭3 G3 A3 C4         | F2               | F2             |
| A♭maj9 | E♭3 G3 B♭3 C4        | A♭2              | A♭2            |
| G7♭9   | F3 A♭3 B3 D4         | G2               | G2             |

The organ plays the same voicing an octave up, and the pad adds the root
under it. The sub plays the root between G1 and F♯2.

## Patterns and grids

A **grid** is one bar: sixteen tokens, one per 16th. You can write it in
three ways:

- a string with no spaces, one character per step: `"x...|x...|x...|x..."`
  (the `|` is only there to help the eye);
- a string with spaces, one token per word: `"1! . . 1 | . . 5, . | …"`;
- a YAML list of sixteen tokens.

`patterns` names grids so that tracks can reuse them:

```yaml
patterns:
  four:   "x...|x...|x...|x..."
  log_a:  "1! . . 1 | . . 5, . | . . 7, 1 | . . 3 ."   # steps 0 3 6 10 11 14
  log_b:  "1! . . . | . . 8 . | . 7 . . | 5 . . ."     # steps 0 6 9 12
```

Every grid has `.` for a rest. The other tokens depend on the instrument:

| family | instruments | tokens |
|---|---|---|
| drum | kick, clap, rim, shaker | `x` hit (velocity 0.8), `X` accent (1.0), `g` ghost (0.5) |
| hat | hat | the drum tokens are closed hats; `o` / `O` are open hats |
| conga | conga | `h` high open, `l` low open, `s` slap, `m` muted; capital letters are accents |
| chord | rhodes, organ, pad, sub | `x`/`X`/`g` start the bar's chord; `-` holds it for another 16th |
| log | log | a degree of the chord (`1 3 5 7 8 9`), or a note (`C2`, `E♭2`, `B1`) |
| melody | whistle | a note (`G5`, `Bb5`); `-` holds it |

**Log tokens.** A degree is counted from the chord's root, which sits between
B♭1 and A2. `3`, `5`, `7` and `9` lie above the root (`9` is an octave plus a
second) and `8` is the octave. Each `,` drops the note an octave and each `'`
raises it, so on Cm9 `5,` is G1 and `7,` is B♭1. One pattern therefore follows
every chord change. A `>` glides from one pitch to another: `G1>C2`, `5,>1`. A
trailing `!` makes an accent (velocity 1.0) and a trailing `?` a ghost (0.5).
The loader checks every degree against the chord it falls on (`Cm7 has no
degree 9`).

**Holds.** `-` adds a 16th to the note before it, across the bar line too: a
bar that starts with `-` continues the previous bar's note. A bar the track
does not list is silent, and it ends any held note.

## Tracks

```yaml
tracks:
  shaker:
    instrument: shaker
    gain: -16                 # dB
    pan: 0.25                 # -1 left .. +1 right
    swing: true               # shakers and hats only
    humanise: 5               # ± ms, uniform and seeded; shakers and hats only
    params: {tau: 0.02}       # the instrument's own settings (below)
    automation:
      gain: [[1.1.0, -4], [2.4.0, -4], [3.1.0, 0]]   # dB, linear between points
      lp:   [[1.1.0, 600], [1.4.0, 1200]]            # low-pass Hz, geometric between points
    reverb: 1.4               # optional send: RT60 in seconds…
    wet: -16                  # …and its level in dB
    bars:
      1: sixteenths           # a pattern name…
      2: "xxxx|xxxx|xxxx|...."   # …or a grid
      3-7: sixteenths         # a range of bars
      9-11, 14: sixteenths    # several ranges
```

The track name is free; `instrument` picks the sound. Several tracks may share
an instrument.

**Swing** (56 %): the off-16th of every 8th is late by (0.56 − 0.50) × an
8th, which is 768 samples (16 ms). The storyboard swings shakers and hats
only, so the loader refuses swing or humanise anywhere else. Kick, clap, log,
impacts and clicks stay on the grid.

**Instrument parameters** (`params:`):

| instrument | parameters (default) |
|---|---|
| log | `decay` 0.2 s, `drive` 3, `index` 3, `sub_db` −2, `wood_db` −6, `lp` none |
| kick | `decay` 0.2 s, `f_start` 165 Hz, `f_end` 45 Hz |
| clap | `tail` 0.09 s |
| shaker | `tau` 0.02 s, `accents` [0.75, 0.5, 1.0, 0.6] (by 16th within the beat) |
| rhodes | `release` 0.16 s, `tremolo_hz` 4.2, `tremolo` 0.35 (auto-pan depth) |
| organ | `drawbars` "888400000", `percussion` true, `leslie_hz` 6 |
| whistle | `vibrato_hz` 5.6, `vibrato_cents` 28 |
| pad | `cutoff` 1300 Hz, `attack` 0.35 s, `release` 0.6 s |
| sub | `attack` 0.12 s, `release` 0.5 s |

## Cues

```yaml
cues:
  - {id: drop1.impact, kind: impact, pos: 3.1.0, f_start: 80, f_end: 30, tau: 0.8, rt60: 2.5}
  - {id: swipe.whoosh, kind: whoosh, style: swipe, pos: 3.2.1, offset: 1, end: 3.3.0}
  - {id: tap.close, kind: whoosh, style: close, pos: 3.4.2, dur: 6}
  - {id: swipe.open, kind: log, pos: 3.3.0, note: Eb2, vel: 1.0}
```

A cue is one sound tied to one picture event. These keys work on every cue:

| key | meaning |
|---|---|
| `id` | lower-case dotted words, unique in the score; SCENES addresses the event by it |
| `kind` | what sounds (table below) |
| `pos` | where it starts, `bar.beat.step` |
| `offset` | whole frames off the grid (−15…15). Only for sounds that follow a real UI animation the app drew between grid lines, such as a pane that closes on f184.6. |
| `end` (+ `end_offset`) or `dur` | for sounds that span time: an end position, or a length in frames |
| `gain` | dB |
| `pan` | −1…1, for mono sounds |
| `reverb`, `wet` | a reverb send: RT60 in seconds, level in dB |

A cue's sound starts at `frame × 1600` exactly: the first sample of the sound
is its onset. A reverse cymbal or a riser spans from `pos` to `end` and stops
dead there. A whoosh crests `peak` frames after `pos`.

**A cue of a grid instrument replaces the grid.** Cues of kind `log`, `kick`,
`clap`, `rim`, `conga` or `rhodes` play through the first track of that
instrument, with its gain, pan and send. If that track has a hit on the same
16th, the cue takes its place. This is how the storyboard's rule is written:
« a log or kick lands on every hero frame first, and the rest of each phrase
fills from pattern A or B ». The hero hit is a cue that SCENES can address,
and the pattern fills the rest of the bar.

**The log drum is one voice.** Each hit is cut, with a 6-ms fade, where the
next one starts, whether that next hit comes from the grid or from a cue.

| kind | parameters (default) | the sound |
|---|---|---|
| `log` | `note` (required), `glide_from`, `vel` 0.9, `decay`, `lp`, `octave` false, `index` | a log-drum hit |
| `kick` / `clap` / `rim` | `vel` | one hit |
| `conga` | `vel`, `stroke` h/l/m/s | one conga stroke |
| `rhodes` | `vel`, `gate` 3 (16ths) | a stab of the bar's chord |
| `clap_roll` | `rate` 16 or 32, `vel_from` 0.45, `vel_to` 1.0; needs `end` | claps on every 16th or 32nd up to `end` |
| `impact` | `f_start` 80, `f_end` 30, `tau` 0.8, `rt60` 2.5, `sub` true, `noise_db` −4, `wet_db` −6, `sub_db` 0 | a sub sweep, low-passed noise and a synthetic reverb; `sub: false` makes a soft hit |
| `whoosh` | `style` (required): whip, swipe, swish, close, drag, tape, air; `peak` (frames) | a band-passed noise sweep; `swipe` pans left to right, `air` swells into its end |
| `riser` | `gates` [[pos, 8 or 16], …], `f_lo` 200, `f_hi` 8000, `saw_from` A2, `saw_to` A5; needs `end` | noise swept 200 Hz → 8 kHz at t² gain over a rising saw, chopped on 8ths and then 16ths |
| `reverse` | needs `end` | a reverse cymbal into `end` |
| `pen_scratch` | `end`/`dur` optional (180 ms without) | pen on paper, 2–6 kHz |
| `pen_slash` | `length_ms` 120 | a pen striking a line out, 1 → 5 kHz |
| `click` | `f` 3200 | the touch-down: an original 3.2 kHz, 8-ms blip whose pitch moves ±3 % per tap (seeded by the id) |
| `key` | `f` 2400 | a typing key |
| `tick` | `f` 5200 | the counter's tick |
| `pop` | `f` 520 | a lift's soft pop: a sine of 40 ms |
| `thock` / `cardpop` | | a wood thock / thock + low thump |
| `chime` | `note` G5, `interval` 7, `gap_ms` 90 | the original two-note chime, a rising fifth of sine + soft FM |
| `glint` | `note` D6 | a small, soft bell |
| `kalimba` | `note` C6 | a kalimba ding |
| `shimmer` | | a soft, high Cm9 shimmer |
| `glide` | `from` G3, `to` C5; needs `end` | a rising FM glide |

The log, the UI clicks, the keys and the ticks also drive the mix. The
sidechain on pads and keys follows every kick and log onset, and the log
ducks 3 dB for 40 ms under every click, key and tick. These times come from
where the sounds were placed, never from guesses.

## What comes out

`events.json` lists every bar and beat, plus every cue with its `id`, `kind`,
`pos`, exact `frame` and exact `sample` (with `offset_frames` and
`end_frame`/`end_sample` where they apply). It is written from the
arranger's record of where each sound landed. The record is checked against
the score, and a disagreement stops the build. See `events.py`.
