# AUDIO — the soundtrack and its clock

This module writes the promo's music and its timing. The music is an
amapiano track at 112.5 BPM in C minor, on four chords: Cm9, F9, A♭maj9 and
G7♭9. It is synthesised in code at 48 kHz from a score (see
[SCORE.md](SCORE.md)). No sample, loop or stock sound is used, and the
clicks and the chime are original. Next to the track, the module writes
`events.json`, the clock that SCENES animates to. Every frame number in it
comes from where each sound was actually placed in the render.

The brief, the beats and the sound of each storyboard row come from the
approved storyboard « CARNET → DROP ». The time base and the shape of
`events.json` come from the architecture contract.

```
cd tool/promo_reel
python -m promo.audio --score score_30s.yaml --out OUT/30s     # or --cut 30s
python -m promo.audio --cut 15s --out OUT/15s
python -m unittest tests.test_audio                            # 44 tests, ~10 s
```

| file written | what it holds |
|---|---|
| `track.wav` | 24-bit stereo PCM at 48 kHz, exactly `frames × 1600` samples long (960 or 512 frames), with TPDF dither |
| `events.json` | every bar and every beat; every named cue with its `id`, `kind`, `pos`, exact `frame` and exact `sample`; the sections and the chords |
| `meter.json` | BS.1770-4 integrated, short-term max and momentary max loudness; true and sample peak; LRA; the pass/fail check against the target; readings per bar and per section; the mono fold-down; what the mix did; and ffmpeg's ebur128 reading of the same file as a cross-check |
| `spectrogram.png` | waveform, log-frequency spectrogram and loudness curves on one time axis in bars, with section names and a tick for every cue |
| `waveform.png` | one row per section, the waveform drawn on the beat grid, with every cue id where it lands |

Add `--stems` to also write the five buses and every track to `OUT/stems/`.
The command exits with status 1 when the master misses its target or when
the score is refused.

## How it is built

| module | role |
|---|---|
| (`promo/timebase.py`) | the clock, shared with every module: `frame = (bar−1)·64 + (beat−1)·16 + step·4`, `sample = frame·1600` (`frame_of`, `sample_of_frame`, `pos_of_step`, `Pos.frame/.sample/.step_in_bar`). The audio's own copy, `_time.py`, was merged into it. |
| `score.py`, `kinds.py` | load and validate a score. `kinds.py` holds the vocabulary: instruments, cue kinds and their parameters. A refused score lists every problem with its location. |
| `harmony.py` | notes, chords and voicings, and the log drum's chord-relative degrees |
| `instruments.py` | every sound, synthesised; the first sample of each sound is its onset |
| `arrange.py` | score → five stereo buses (log, drums, keys, fx, ui), plus a record of where each sound was written |
| `mix.py` | sidechain, ducking, glue and bus compression, mono below 150 Hz, the true-peak limiter and the loudness loop |
| `loudness.py` | ITU-R BS.1770-4 (K filter, gating), momentary and short-term loudness, EBU 3342 LRA, true peak by 4× oversampling |
| `events.py` | writes `events.json` from the arranger's record and checks it against the score |
| `analysis.py` | `meter.json`, the two pictures, the ffmpeg cross-check |
| `wav.py`, `build.py`, `__main__.py` | 24-bit file I/O, one cut end to end, the command line |

### The instruments

Each sound below is as the storyboard's « Music plan » asks:

- **Log drum.** A two-operator FM voice at ratio 1. Its index starts at 3,
  drops within about 50 ms, and settles at 0.8, which keeps a slightly
  nasal tone a phone speaker can carry. The pitch starts high and falls
  (`f0·(1 + 2·e^(−t/12 ms))`). A wood partial at 2.4 × f0 sounds for about
  30 ms. A tanh drive of 3 is applied after the envelope, and a clean sub
  runs on the same phase, so it can never cancel the body. The drum is one
  voice: each hit is cut where the next one starts. It can glide (G1 → C2
  on the third strike) and can be low-passed (the hook's 600-Hz stab).
- **Drums.**
  - A 909-style kick: a sine sweeping 165 → 45 Hz (τ 30 ms) plus a 1-ms
    click.
  - A clap: three bursts 10 ms apart and a tail, band-passed to 1–2.5 kHz.
  - A shaker: noise band-passed to 4–12 kHz, with an accent table.
  - Hats: the 808's six square waves plus band-passed noise, open or
    closed.
  - Congas: two modal sines plus a slap.
  - A dry rim tick.
- **Keys.**
  - A DX-style FM Rhodes with an auto-pan tremolo.
  - An organ with drawbars, a percussion harmonic and a key click, played
    through a 6-Hz rotor (modulated delay and amplitude, the two channels
    in quadrature).
  - A whistle: a sine that scoops into pitch, with delayed vibrato.
  - A pad of detuned PolyBLEP saws.
  - A held sub.
- **Effects.**
  - Risers: noise swept 200 Hz → 8 kHz at t² gain over a rising saw, gated
    on 8ths and then 16ths.
  - Impacts: a sub sweep, low-passed noise and a synthetic reverb with a
    measured RT60 of 2.5–2.8 s.
  - Seven whoosh styles, a reverse cymbal, a pen scratch and a pen slash.
- **Interface.**
  - The touch-down click: a 3.2-kHz blip of 8 ms whose pitch moves ±3 %
    per tap. The amount is seeded by the cue id, so it is reproducible.
  - Typing keys and counter ticks.
  - A 520-Hz pop.
  - A wood thock and a card pop.
  - The two-note chime: a rising fifth of sine plus soft FM.
  - A kalimba, a shimmer, an FM glide, and the glint.

### The mix

1. **Sidechain.** The pads and keys duck 5 dB on every kick and 3 dB on
   every log hit, never more than 6 dB in total. The times are the known
   onsets from the render, so each duck begins 4 ms before its hit.
2. **Ducking.** The log drops 3 dB for 40 ms under every click, key and
   tick, so the clicks sit above it.
3. **Glue compression.** The drums and the log go through a 2:1 glue
   compressor with a 12-ms attack, so the punch is kept.
4. **Master bus.**
   - Everything under 150 Hz is folded to mono. The split is zero-phase,
     and the side signal is 19 dB down at 150 Hz and more than 80 dB down
     at 60 Hz.
   - A 1.5:1 compressor, a high-pass at 20 Hz, and a fade to silence over
     the last 60 ms.
5. **Loudness loop.** The master is gained into a true-peak limiter and
   measured, again and again, until it reads −14.0 LUFS-I within 0.02 LU.
   The limiter's gain is never higher than what each sample's
   4×-oversampled peak allows. Its ceiling sits 0.3 dB under −1.0 dBTP,
   and the loop widens that margin if the measured true peak comes out
   higher.

Use `--lufs -12 --ceiling -2` for the storyboard's optional louder TikTok
master.

## The two scores

`score_30s.yaml` (15 bars: the storyboard's 14 and the owner's one-bar
outro, 2026-10-19) follows every row's « Sound » column and the Music plan,
section by section:

- **Hook** (bars 1–2). A low-passed log stab with its sub on frame 0, a rim
  tick on each word, the pen, then the three strikes on f64, f76 and f88,
  the last gliding G1 → C2. Riser 1 runs from f64 to f108, then comes a clap
  roll, and the « Respirez. » AIR with a reverse cymbal into f128 (−20 dB)
  over a breath of pad 3 dB down.
- **Drop 1** (bars 3–4). An impact. The touch-down clicks on f144 and f176.
  The swipe whoosh is panned left to right over f149–160. The open pane gets
  an E♭2 log and a wood thock. The lift gets a log and a pop on f232, and a
  log answers on f244.
- **Groove B** (bars 5–6). A whip that crests on f259, then congas and
  rimshots. Clicks on f280, f320, f336 and f352, and typing on every 16th
  from f360 to f380.
- **Log break** (bar 7). A solo log line. The chime and a log on f436, and
  the pen-slash rhyme on f440.
- **Lift** (bar 8). « rempli. » on f448. Card pops on the log hits f472,
  f480 and f488. Riser 2, then the drum stop on f496.
- **Drop 2** (bars 9–11). A light impact. The whistle, the organ and the
  conga counterpoint come in. A click on f528 and a tick on every 16th from
  f536 to f544. The landing on f548 (9.3.1: N1's wait at 0.995×) is a log, a
  clap, a kick punch and a kalimba. The caption words fall on log hits at f576, f584, f592 and f600.
- **Breakdown** (bar 12). Riser 3 runs from f720 and stops dead on the cut
  to black (f752), with a clap roll; the second AIR (f752–767) is near
  silence like the first: the reverse cymbal (−18 dB) and a short sub tail,
  the pad muted. Both AIRs sit ≥ 7 LU under the groove on the master itself
  (verify (d) holds the master and the MP4 to it): 8.5 and 8.5 LU.
- **Reveal** (bar 13). The big impact (RT60 2.8 s), the shimmer on f784,
  and the FM glide over f804–824.
- **End card** (bar 14). Log hits on f832 (the mark lands, the tagline
  whole), f848 (with the App Store glint, alone on its cue) and f880, over a
  light groove.
- **Outro** (bar 15, the owner's added bar). Calm: no kick, clap or hat; the
  shaker thins to 8ths, then two hits, and fades 7 dB. On the downbeat (f896)
  the log and the pen (`end.underline`, a `pen_scratch` as long as the
  stroke draws, 8 frames) as the hook's strike comes back as an underline;
  on beat 3 (f928) the last log with a short last Rhodes chord (`end.last`,
  the mark's small punch) that RINGS OUT before the end: the chord released
  after 3 16ths, the log at the default decay (0.2 s) with a short room
  (0.9 s, −14 dB), the pad faded out (−40 dB by 15.4.2, released 2 16ths
  before the end) — 21 dB down by f950 and ≈ −48 dBFS over the last 100 ms,
  so the master's 60-ms end fade never chops a loud tail (round 3 held the
  chord to the last sample: 4.6 dB of decay by f950, the last 100 ms at
  −19.8 dBFS; verify (d) `outro_tail` holds it on the master and the MP4).

`score_15s.yaml` (8 bars: 7 and the same outro bar — the underline on f448,
the last log on f480) is re-scored on the 15-s cut's own frames. It is not a
splice of the 30-s audio. Its one AIR (f48–63) is 8.4 LU under its groove on
the master (8.9 after AAC): the reverse at −19 dB, strike 3 lighter (vel 0.7,
decay 0.15) and the breath 3 dB down. (Round 2's « 6.36 LU after AAC » did
not reproduce: the master was 5.87, an AAC encode 6.05.)

### Choices the storyboard left open

- The log patterns are exactly A (steps 0 3 6 10 11 14) and B (steps 0 6 9
  12), written as chord degrees. Where a hero hit falls next to a pattern
  hit, the bar is written as a variant, and each variant is commented in
  the score. For example, bar 3 is A without step 10, because the E♭2 hero
  sits on step 8.
- The owner's addition is a soft `glint` (`end.store`) under « Disponible
  sur l'App Store », at −12 dB with a short reverb. It was on 14.3.0 (f864)
  in the 30-s and 7.3.0 (f416) in the 15-s; SCENES moved it to 14.2.0 (f848)
  and 7.2.0 (f400), with « moins de gestion. »: on the later beat the
  26-character line was on screen for 1.07 s (24 characters a second), over
  the storyboard's 17-cps reading ceiling; from f848 it has 1.6 s (16.3).
  The owner's end card of 2026-10-20 (« Both stores, post later ») keeps it
  under « Sur l’App Store et Google Play » and adds « myweli.com » on its
  own cue: `end.site` (a glint on G5, −13 dB, a fifth under the store's D6)
  and `end.site_log` (C2, vel 0.8) on 14.4.0 (f880) / 7.4.0 (f432) — the
  bar's step-12 log of the end card's pattern, now the cue (the pattern lost
  it, so the hit is not doubled).
- Riser 2 stops one 16th before the drop (f508), as riser 1 does (f108).
- In the 15-s, a short reverse cymbal leads into the reveal (f312–320).
  That cut has no AIR before its reveal.
- « ±3–6 ms humanise » is read as uniform jitter of ±5 ms on the shaker and
  ±3 ms on the hats. It is seeded, so a render is bit-for-bit reproducible.
- Chord changes not stated in the storyboard: bar 7 is Cm9 (the chime's G
  and D sit in it), F9 starts at 11.3.0 with the page's scroll, and the
  15-s bar 4 moves A♭maj9 → G7♭9 so that its chime lands on G7♭9.

## Measured on the current scores

| | 30 s | 15 s |
|---|---|---|
| length | 960 frames, 1 536 000 samples | 512 frames, 819 200 samples |
| integrated loudness | −14.01 LUFS (ffmpeg: −14.0) | −14.00 LUFS (ffmpeg: −14.0) |
| true peak | −1.30 dBTP (ffmpeg: −1.3) | −1.30 dBTP (ffmpeg: −1.2) |
| short-term max / momentary max | −12.5 / −10.4 LUFS | −12.4 / −10.6 LUFS |
| LRA | 2.8 LU | 2.8 LU |
| sections | hook −16.7, drops −12.8 to −14.0, log break −14.5, breakdown −16.0, reveal −13.2, end card −15.1, outro −18.9 | hook −15.4, drop −13.6, revenus −13.0, end card −15.3, outro −18.8 |
| the last hit's tail (`outro_tail`) | f928 → f950: 21.4 dB down; the last 100 ms 35.1 dB under it (≈ −48 dBFS) | f480 → f502: 21.4 dB down; 35.0 dB under |
| AIR under the groove (film master / its MP4) | AIR 1 8.4 / 8.8 LU, AIR 2 8.5 / 9.1 LU | 8.3 / 8.8 LU |
| side under 150 Hz | −36 dB | −37 dB |
| L/R correlation | 0.96 | 0.96 |
| limiter | ≤ 3.7 dB, under 0.7 s above 1 dB | ≤ 3.7 dB |
| cues | 85 | 49 |

## Notes for SCENES

- Read `events.json` and nothing else for timing. A cue's `frame` is where
  its sound starts. Off-grid cues follow real UI animations and carry
  `offset_frames`. Cues that span time carry `end_frame`.
- The cue ids are declared in the two scores, with the picture event of each
  written in a comment. Cues that mark the same picture event in both cuts
  share an id: `drop1.impact`, `swipe.touch`, `create.chime`,
  `revenus.land`, `reveal.impact`, `end.store` and others.
- The 1:1 and 16:9 formats reuse the same `events.json` and the same track.
