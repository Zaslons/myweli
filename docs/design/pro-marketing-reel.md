# MyWeli Pro — marketing Reel « Le trait » — design spec

| | |
|---|---|
| **Status** | **Approved 2026-10-18; amended 2026-10-18 (A1, owner: people and pictures).** A1: the hook opens on the owner's picture of a salon owner writing in her paper notebook (the drawn notebook leaves S1, S6 keeps it), S7 runs 20.0–25.0 s, a people beat S7b (25.0–27.0 s, « Plus de temps pour votre métier. ») shows a stylist braiding a client, the end card runs 27.0–30.0 s; the fixes from the review of the first render (R1) are in. Approved first by the owner's sign-off on the final storyboard. Owner's decisions: the storyboard is approved as written, « carnet » kept; the « MyWeli Pro » unit is built from the wordmark SVG plus the « Pro » vectors of the Pro app-open Lottie, and on the end card the drawn mark becomes the Pro app icon — both approved; render now with the existing takes (no re-take, nothing written to production); posting is the owner's later decision; Reels 9:16, 1080 × 1920, 30 fps, 30 s, no music (the owner adds Instagram music), CTA « Disponible sur l’App Store »; audience: salon owners. **Built** on `feat/pro-marketing-reel` — see §9 for what the build measured (§9.2 for A1 and R1). |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-18 |
| **PRD ref / phase** | Launch — marketing · V1 (the « real motion-design film for Facebook, WhatsApp and the website » that [pro-app-preview.md](pro-app-preview.md) §0.1 left as a later owner decision) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Governs** | `tool/marketing_video/` (its README has the build and the checks in full). Sits next to [pro-app-preview.md](pro-app-preview.md) (`tool/app_store_preview/`, whose brand tokens, fonts, take conform and movie writer it reuses) and [pro-app-store-screenshots.md](pro-app-store-screenshots.md). |

## 1. Goal & scope

**What.** A 30-second vertical film that tells a salon owner in Abidjan, with
the sound off, that MyWeli Pro answers three things that go wrong on a salon
day — the paper appointment book, the same client questions at night, the
client who walks in without an appointment — on real footage of the demo
salon « Maison Nala ». It opens and closes on people (A1): a salon owner at
her paper notebook, and a stylist braiding a relaxed client under « Plus de
temps pour votre métier. ».

**The idea, « Le trait ».** One white stroke, in the single weight and round
caps of the MyWeli mark, crosses out each pain (black, abrupt, staccato) and
thickens into a clean paper page (#FAFAFA) on which the answer plays (smooth,
decelerating). The first time it becomes paper, a pen dot draws the mark;
« MyWeli Pro » and the Pro line « Plus de clients, moins de gestion. » land
by 3.5 s. At the end the mark draws itself again and becomes the real Pro app
icon, above « Disponible sur l’App Store ».

**In scope.** The film (`reel.mp4`), its cover frames, a contact sheet and
a verify report, all built by `tool/marketing_video/` from the approved
storyboard (`tool/marketing_video/storyboard.json`, the owner-approved copy
minus `_ownerDecisions`, with its amendments), the takes of 2026-10-14 and
the owner's two pictures (A1).

**Out of scope.** Music (the owner adds it inside Instagram), the 13.5 s
cut-down and the post caption the storyboard suggests (§8), posting, any
re-take, any change to the app.

## 2. The storyboard (approved 2026-10-18, amended the same day: A1)

30.000 s, 900 frames at 30 fps. Cuts on a 0.5 s grid (frames 75, 180, 300,
375, 525, 600, 750, 810) so a 115–130 BPM track locks to them. Pains are black
(#000); answers are paper (#FAFAFA).

| Scene | Time (frames) | On screen (French) | Picture | Motion |
|---|---|---|---|---|
| **S1** hook « carnet » (A1) | 0.00–2.50 (0–74) | « Votre salon, / encore au carnet ? » | The owner's picture (AI-generated, 941×1672): a salon owner writing in her paper notebook, full bleed at 1.1477 (the least that fills the width), its notebook at y ≈ 1170–1480 (the crossing at y 1232, above the caption zone), its bottom edge fading to black at y ≈ 1599; a black gradient 72 % → 0 (y 380–960); Poppins Medium 92/106 white headline at y 316–528 | Push-in 1.00 → 1.04 about the stroke's start (linear, 0–2.50); headline settles from scale 1.02 (`fast`); at 1.45–1.70 a white 8-px stroke leaves the pen tip and crosses the open pages (x 246.8–735, y 1232) over a soft shadow. Cover frame: f54 (1.80 s) |
| **S2** mark + promise | 2.50–6.00 (75–179) | « MyWeli Pro » (vector unit) · « Plus de clients, moins de gestion. » | Paper; the mark 220 px tall at (540, 580); the « MyWeli Pro » unit 480 px wide at y 756; the tagline Poppins Medium 52 #3D3D3D at y 950–1014 | The S1 stroke thickens to 2560 px about its line (`slow`) and becomes the page; pen dot 2.70; the mark draws 2.80–3.40 in the fast loader's path order on (0.4, 0, 0.2, 1); unit 3.15, tagline 3.20 rise 16 px (`emphasis`); exit 6.00–6.20 (40 px up, easeIn), drawn over S3's rising card on its own clear space of paper |
| **S3** answer « Ma journée » | 6.00–10.00 (180–299) | « Votre journée, / heure par heure. » | Answer layout (below); take1b « Ma journée » | Card rises 6.00–6.30; camera W 56 → 350 at 7.10 (`slow`); LIVE swipe on Fatou B. 11:15 (take 10.662–11.628 s, 1:1), the green « Arrivé » pane opens; held open to 10.00; black touch disc follows the logged drag |
| **S4** pain « questions » | 10.00–12.50 (300–374) | « Encore les mêmes / questions ? » — « C’est combien, les tresses ? » 22:41 · « Vous êtes où exactement ? » 22:43 · « Vous fermez à quelle heure ? » 22:47 · « Allô ? » 23:02 | Hard cut to black; neutral received bubbles #1E1E1E, Inter Regular 48 white, timestamps Inter 34 #8A8A8A, stacked y 614–1150 | Bubbles arrive at 10.30/10.60/10.90 as one column: each enters one slot below the bottom slot and rises with the others 140 px (`base`), fading and scaling in on `fast`; nothing below y 1152 is drawn; a full-width stroke through « quelle heure » at 11.90 |
| **S5** answer « page » | 12.50–17.50 (375–524) | « Tarifs, horaires, plan : / tout sur votre page. » | Answer layout; take5b at 30.000 s (one frame), the salon's phone row masked white | Stroke thickens to paper; card enters to W 122 (« Services · 5 services • Voir les tarifs »; the page's back button under the band); camera W 300 (map, « Zone 4, Marcory ») at 14.00 and W 470 (hours, « Aperçu — voici ce que verront vos clients. ») at 15.50, each 600 ms easeInOutCubic |
| **S6** pain « sans rendez-vous » | 17.50–20.00 (525–599) | « Un client / sans rendez-vous ? » — « 13h  Mariam — brushing », « 14h  Aïcha — tresses », « 15h30  Koffi — coupe homme », « 16h30  Rokia — soin capillaire », « 17h  Awa — tresses », « + 14h45  coupe homme · n° ? » | Hard cut to black; the S1 notebook, afternoon page; the walk-in squeezed on the minor rule at baseline 804 | Entries 4–5 pop; the squeezed entry pops at 17.95; « n° ? » struck at 18.45; full-width stroke at y 788, 19.60–19.85 |
| **S7** answer « réservation » | 20.00–25.00 (600–749) | « En quelques gestes, / même sans numéro. » | Answer layout; take1b at W 553, then 682: « Libre — 14:45 » → « Réservation » → the filled form (« Client sans numéro », « Yao K. ») → « Créer le rendez-vous » → « Rendez-vous créé » and the new 14:45 row | Card enters 20.30; tap « Libre » (black disc, gone by 21.10) at 20.90, LIVE 26 frames; 2-frame hold; **declared dissolve** 21.833–22.233 (12 frames on `slow`, skips 97.3 s of real input); hold; white disc on the black button, LIVE 22.90–24.83 with the real server time; the camera pans W 553 → 682 (23.73–24.13) as « Ma journée » comes back, the old 13:15 « Yao K. » sliding under the band; headline fades 24.80–25.00 |
| **S7b** people (A1) | 25.00–27.00 (750–809) | « Plus de temps / pour votre métier. » | The owner's picture (AI-generated, 941×1672): a stylist braiding a relaxed client, full bleed at 1.1483 (the least that fills the frame); a soft black gradient 62 % → 0 (y 420–1000); the caption Poppins Medium 92/106 white at y 316–528 | The S7 page dissolves into the picture (`base`, 25.00–25.20); push-in 1.00 → 1.03 about the braiding hands (linear); caption lines rise 24 px and fade in at 25.00/25.05 (`emphasis`); the picture dissolves into the end card at 27.00 (`base`) |
| **S8** end card | 27.00–30.00 (810–899) | « MyWeli Pro » (vector unit) · « Disponible sur l’App Store » | Paper with the light brand pattern (#EDEEEF marks, brick grid, clear zone x 140–940 × y 380–1180); the Pro app icon tile 280 px at y 450–730; the unit 560 px at y 826–912; black pill 680 × 110 at y 1000–1110, Inter SemiBold 46 white | Pattern fades in under the dissolving picture and drifts up 12 px/s; pen dot 27.05; the mark draws 27.10–27.70; the tile's hairline and shadow fade in 27.65 (the mark becomes the icon); unit 27.70; CTA 27.75; clean hold to the last frame (the loop point) |

**Shared answer layout (S3, S5, S7).** Paper; the headline Poppins Medium
84/96 #1A1A1A centred in x 90–990, block y 316–508; a header band of paper
over y 0–552 fading out over 552–600, above the card; the card is the
capture cropped from screen point 56 (no status bar, no Dynamic Island), 900
px wide at x 90–990 (2.2388 px a point), radius 110, a 3-px #D0D0D0 ring and
the stills' two shadows scaled to 1080 — card and shadow one group under the
band's fade. Every card enters the same way: the card as it rests, clipped
by the band, rises 1320 px from y 1920 on `emphasis` (at most 410 px a
frame). A camera window W places screen point
p at frame y = 600 + (p − W) × 2.2388.

**Words on screen and reading time.** Every headline, the tagline, S7b's
caption and the CTA stay from the start of their entrance to the start of
their exit at least max(1.5 s, characters ÷ 15 + 0.5 s): S1 2.77 s of 2.57
needed; tagline 2.80 of 2.77; S3 3.80 of 2.57; S4 2.73 of 2.37; S5 4.75 of
3.50; S6 2.70 of 2.37; S7 4.55 of 2.97; CTA 2.25 of 2.23. **S7b's caption is
the exception: 2.00 s (its whole A1 beat) against the 2.63 s its 32
characters need** — flagged for the owner (§7 risk 15). Brand time 6.43 s of
30 (21.4 %, ≤ 25 %).

## 3. Truth rules — what the film claims, and what it deliberately does not

- **Every answer is the real app, recorded.** S3 and S7 are the production
  recording take1b (2026-10-14, demo salon Maison Nala, invented client
  names); S5 is take5b's frame at 30.000 s (the keyed build with real CARTO
  tiles, the cover photo scrolled away). LIVE ranges play 1:1, conformed to
  30 fps by frame-hold (`Conform.swift`), never retimed, never blended
  except the one **declared dissolve** in S7 — the App Store film's own cut —
  which must read as a time skip, never as a speed-up.
- **Code paths behind the screens** (checked when the storyboard was
  written): `pro_journal_screen.dart` `_startPane` (« Arrivé ») and `_gap()`
  (« Libre — HH:MM » opens `/pro/appointment/new`);
  `pro_manual_booking_screen.dart` (« Client sans numéro » l.361, « Créer le
  rendez-vous » l.407, « Rendez-vous créé » l.250); `provider_detail_screen.dart`
  (« Voir les tarifs » l.678, the « Aperçu » bar l.1192, « Réserver (après la
  mise en ligne) » l.1207).
- **Headlines are approved store copy or literal on screen**: S3 is
  screens.json 01 word for word; S5's « Tarifs, horaires, plan » are the
  page's own words (screens.json 02); S7 joins screens.json 04's headline and
  sub-line.
- **Not claimed, on purpose**: no SMS, WhatsApp or reminder sending (messaging
  is OFF until the company is registered — S4's bubbles are the pain, no
  MyWeli screen answers them with a message); no payment, deposit or
  no-show prevention (no screen exists; the « lapin » beat was removed); no
  figures, prices or offers; S3 shows the gesture opening « Arrivé », not
  that the arrival was saved; « Réserver (après la mise en ligne) » stays
  visible as the page's own caveat.
- **Never on screen**: a readable phone number (S5's salon phone row is
  masked white in capture space before the camera moves; S7 shows no
  digits), the status bar, the Dynamic Island, the unverified cover photo, a
  real person (A1's people are the owner's AI-generated pictures:
  illustrative atmosphere, never captioned as real customers, never a
  testimonial), a third-party chat look (no WhatsApp green, no ticks, no
  logo), an Apple logo or badge artwork.
- **The logo is vectors only**: the mark from `myweli_mark_black.svg`, the
  draw-on from the fast loader Lottie, the « MyWeli Pro » unit from the
  wordmark SVG plus the « Pro » glyph vectors of
  `myweli_loader_mixed_pro.json` — never typed text; clear space (half the
  mark's height) kept; the tagline beside the logo, outside the lockup.
- **Brand**: Ink Black and paper only; the only functional colours are inside
  the real UI (the green pane, the snackbar). Poppins Medium and Inter (two
  weights a screen at most, no italics). Motion tokens from `motion.dart`
  (stagger 50, fast 100, base 200, emphasis 300, slow 400); entrances
  decelerate, exits accelerate; every stroke on the Lottie's (0.4, 0, 0.2, 1).

## 4. Formats

| | |
|---|---|
| Master | `reel.mp4` — MPEG-4, H.264 High Profile Level 4.1, 1080 × 1920, 30 fps constant (900 frames, 30.000 s), 8-bit 4:2:0 (yuv420p), progressive, no frame reordering, a key frame every 30 frames, Rec. 709 tags; one **silent** stereo AAC-LC 48 kHz track (so WhatsApp and the other uploaders never treat it as a GIF) |
| Where | Instagram Reels (the owner adds music there), Facebook Reels, TikTok, WhatsApp Status — the same master |
| Safe zone | Every word of the film inside x 65–1015, y 269–1248 (clear of the Reels top bar, the caption zone and the right-hand rail, which starts at y 1152 for x > 850); everything of the hook and the end card inside the 4:5 feed crop (y 285–1635) and the 3:4 grid crop (y 240–1680) |
| Covers | `poster-hook.png` (frame 0), `poster-end.png` (the last frame), `cover.png` (frame 54, 1.80 s, the storyboard's cover) — composed, lossless |
| Review | `contact-sheet.png` (a frame every 0.5 s, decoded from the written file, labelled), `frame-<t>.png` at 18 key moments, `verify.txt` |

## 5. Architecture

`tool/marketing_video/` is a sibling of `tool/app_store_preview/` and reuses
it rather than copying it: `brand.py` (colour tokens from `colors.dart`,
motion tokens from `motion.dart`, Flutter's cubic bisection — `fastOutSlowIn`
added to its `CUBICS`), the stills' fonts (`tool/app_store_screenshots/fonts`),
`swift/Conform.swift` (the takes to 30 fps by frame-hold), `Common.swift` +
`Writer.swift` (`writeMovie`) with a new `MovieSpec.social` in the tool's own
`swift/ReelEncode.swift`, `Inspect.swift` and `mp4.py` (reading the file back),
and `frames.check_glyphs` (no missing glyph). What the film adds: the
compositor primitives (round-capped strokes and the mark draw-on by signed
distance, supersampled; the stroke that thickens into the page; kinetic type;
message bubbles; the notebook; the card with a camera window; the touch disc;
the brand pattern; the icon tile; the vector « MyWeli Pro » unit through
`rsvg-convert`), A1's pictures (`reel_photo.py`: sha256-checked, placed at
the least scale that fills, pushed in about a held point, their gradients),
the plan that ties every number to the storyboard, and the social verify. Python 3 + Pillow + numpy + `swiftc`/AVFoundation; nothing
installed.

## 6. Verification

`reel.py verify` reads the written file back with three readers (the tool's
own box parse, AVFoundation, `avmediainfo`) and checks: container, one video
and one sound track, H.264 High@4.1, 1080 × 1920 everywhere, 8-bit 4:2:0
progressive with square pixels, every frame exactly 1/30 s, 900 frames,
30.000 s, no reordering, the bit rate, AAC-LC stereo 48 kHz running the whole
film and decoding to digital silence. Against the plan: every text box of the
storyboard inside the safe zone on every frame (and none in the rail), no
missing glyph, the reading times and the brand time; no two of S4's bubbles
ever overlapping; no card moving more than 410 px between two frames; A1's
pictures never smaller than their fill nor larger than their push-in. Against the build:
each LIVE and HOLD range against its take map, S5's phone row white on every
composed frame and on the decoded file, key frames decoded against the
composed ones (48 dB; 47 where the ground is a photograph), and the white
words over A1's pictures at 4.5:1 or more against what lies under them. A self-test runs verify on a deliberately wrong file, on a
plan with a box outside the zone, on overlapping bubbles, a jumping card, an
over-enlarged picture and a caption cut shorter than its beat, and watches
each fail.

## 7. Risks (from the storyboard, carried as approved; updated for A1)

1. **Footage age.** take1b is from 2026-10-14; since then only #611
   (2026-10-15, the PhoneNumberField's 10-digit rule) touches a filmed screen.
   The EMPTY phone field shows for about 0.8 s in S7 (21.43–22.23 s, through
   the dissolve). The owner chose to render with the existing takes.
2. **Duplicate « Yao K. ».** take1b already holds a 13:15 « Yao K. ». The
   camera now pans as « Ma journée » comes back, so both rows are on screen
   together only for frames 710–718 (23.67–23.97 s, **0.30 s**, while the
   journal slides back in and the pan runs) — the first render showed both
   for about 2.4 s. Only a re-take under another name removes it.
3. **« Tarifs »** is the collapsed « 5 services • Voir les tarifs »; the prices
   are one tap away, not shown literally.
4. **« En quelques gestes »** sits on a declared dissolve that hides 97 s of
   scripted input: it must read as a time skip — now 12 frames on `slow`, a
   clean picture on each side.
5. **« Plus de clients »** is an outcome promise with no number; post only
   when salons can be published and booked, and after the App Store release.
6. **The CTA is App Store only** (owner's decision): most owners in Côte
   d'Ivoire use Android.
7. **Logo.** No official « MyWeli Pro » lockup exists; the unit and the
   mark-becomes-icon move are new arrangements — approved by the owner on
   2026-10-18.
8. **Register and wording** (« carnet » kept by the owner; the four client
   messages; A1's « Plus de temps pour votre métier. ») want a local reader;
   the white strikes and hard cuts are brand-review points against « Calm,
   not hyped ».
9. **S2's 2.5-s hold** is the film's slowest stretch; fallback: a 2.0-s S2
   without the tagline, the line moved to the caption.
10. **Safe zones.** « Créer le rendez-vous » at y 1225 with its right end under
    the rail; « Réserver (après la mise en ligne) » (y 1334) in the caption
    zone. Check on a real phone with Instagram and TikTok.
11. **No music** in the file; the 0.5-s grid suits 115–130 BPM.
12. **Tooling** — built (`tool/marketing_video/`).
13. **People (A1).** The two pictures are AI-generated by the owner
    (ChatGPT/Gemini, 2026-10-18; `build/marketing/photos/PROVENANCE.md`),
    used as illustrative atmosphere, never captioned as real customers or a
    testimonial. Meta (Instagram, Facebook) and TikTok ask creators to label,
    or label themselves, photorealistic AI-generated content: check each
    platform's AI-content setting when posting. The pictures are 941 × 1672,
    enlarged 1.148–1.194× in the film (slightly soft at full size).
14. **S1's framing (A1).** To bring the notebook's crossing above the caption
    zone, the picture sits 320 px above its natural place: its bottom edge
    fades into black (the bottom 17 % of the hook, under the Reels caption),
    and the headline's second line sits on her hairline.
15. **S7b's caption reading time.** « Plus de temps pour votre métier. » (32
    characters) is on screen 2.00 s, A1's whole beat; the film's rule asks
    2.63 s. More time means about 0.65 s from S7's holds (at their shortest)
    or from the end card (the CTA has 0.02 s to spare), or a shorter line —
    the owner's call.

## 8. How to rebuild

```
python3 tool/marketing_video/reel.py build \
    --assets "<main checkout>/build/app-store/pro" \
    [--photos "<main checkout>/build/marketing/photos"] \
    --out <folder> [--work <scratch folder>] [--jobs 4]
python3 tool/marketing_video/reel.py verify <folder>/reel.mp4 --work <scratch folder>
python3 tool/marketing_video/reel.py selftest
```

`--assets` is the folder that holds `preview/v2/takes/take1b/take.mov`,
`preview/v2/takes/take5b/take.mov` and `preview/v2/final/film.json` (the
App Store film's verified touch path); `--photos` (by default
`build/marketing/photos` beside it) holds A1's two pictures, checked against
the sha256 the storyboard quotes. `build/` is ignored by git: the takes, the
pictures and every output stay out of the repository. The build composes the 900
frames, encodes `reel.mp4`, writes the covers, the contact sheet and the key
frames (decoded from the written file), then runs verify; it exits non-zero
on any failed check.

## 9. As built

### 9.1 The first render (2026-10-18, before A1)

Rendered from the takes of 2026-10-14 (take1b sha256 `b0a455b9…`, take5b
`59fab94b…`) and the storyboard copy (sha256 `2dc5befc…`), in a scratch
folder — no film is committed:

- `reel.mp4`: 900 frames, 30.000 s, 10,288,793 bytes, sha256
  `ad6c66d2d827c91c…`; **PASS — 30 checks**; 2.74 Mbit/s on average, 8.80
  Mbit in the busiest second (Level 4.1 allows 62.5), the sound decoding to
  zeros; every key frame decoded at 54.5 dB or better from what was
  composed.
- 444 distinct pictures in 900 frames; 47 s end to end on four processes
  (conform 13 s, compose 15 s, encode 8 s, covers + sheet + verify 11 s).
- Safe zone: every word, logo and shape inside x 65–1015, y 269–1248 on all
  900 frames (the tightest, S6's second headline line at 525, 19 px in);
  nothing in the rail; reading times all met (S1 2.70 s of 2.57 … CTA 2.60
  of 2.23); the logo on screen 6.93 s (23.1 %).
- **Looked at**: the contact sheet and the 15 key frames decoded from the
  file. Two defects of the first render were fixed and rendered again: S4's
  newest bubble printed its words over the bubble still moving up (now
  drawn beneath it), and the end card's pattern feather cut marks in half
  (now each mark fades whole).

**Deviations from the storyboard**, each the calmer or more precise
reading (the tool's README lists them with their reasons): U+202F set where
`onScreenText` has plain spaces; every card's top edge starts at y 1920
(S5 and S7 would otherwise pop in on screen); S8's stroke width follows the
pen dot's growth where the two overlap; the pattern fades whole marks; a new
S4 bubble passes under the one moving up (at 11.00 s the top of « Allô ? »
is still hidden); the widest bubble is b3 at 842 px (x 90–932), not 809;
take5b's « 30.000 s » picture is the one presented at 28.665 s; S3's touch
point is the App Store film's picture-followed drag; round caps where the
loader Lottie has butt caps; the bit rate is 2.74 Mbit/s against a 10 Mbit/s
target (the picture needs no more; padding measured worse). The cut-down and
the caption were not built.

The review of this render (R1, §9.2) replaced two of these readings: the
cards' entrance and S4's bubbles.

### 9.2 Amendment A1 and the review's fixes (R1) — the current film (2026-10-18)

Rendered from the same takes, A1's two pictures (`hook-owner-notebook.webp`
sha256 `a78c7149…`, `closing-stylist-braiding.webp` `2027a9a0…`, checked by
the build) and the amended storyboard (sha256 `442f7664…`), in a scratch
folder — no film and no picture is committed:

- `reel.mp4`: 900 frames, 30.000 s, 35,132,545 bytes, sha256
  `87085ce361a1f226…`; **PASS — 34 checks**; 9.36 Mbit/s on average, 51.97
  Mbit in the busiest second (Level 4.1 allows 62.5), the sound decoding to
  zeros; the worst graphic key frame at 55.3 dB, the worst photograph key
  frame (frame 0) at 47.8 dB.
- 530 distinct pictures in 900 frames; 58 s end to end on four processes
  (conform 13 s, compose 16 s, encode 15 s, covers + sheet + verify 14 s).
- Safe zone: every word, logo and shape — S1's stroke included — inside x
  65–1015, y 269–1248 on all 900 frames (the tightest, S1's stroke, 12 px
  in); nothing in the rail; the logo on screen 6.43 s (21.4 %); reading times
  met except S7b's caption, 2.00 s of 2.63 (§7 risk 15, flagged); the white
  words over the pictures at 8.4:1 (S1) and 6.4:1 (S7b) or better against the
  brightest 5 % under each line; the pictures enlarged 1.1477 → 1.1936 (S1)
  and 1.1483 → 1.1828 (S7b): the least that fills, times the push-in, no
  more.
- **The encoder's ceiling** moved from 10 to 12: at 10, A1's photographs
  cost 65.0 Mbit in the busiest second, over Level 4.1 (measurements in the
  tool's README); verify holds key frames to 48 dB, and to 47 where the
  ground is a photograph (its grain: 47.8 dB is 1.1 grey levels RMS).

**A1, as built.** S1 opens on the owner's picture, full bleed in width,
placed 320 px above its natural place so the notebook's crossing (y 1232)
is above the caption zone; it fades into black at its bottom edge
(y ≈ 1599); a 72 % → 0 black gradient (y 380–960) under the white question;
the push-in 1.00 → 1.04 holds the stroke's start still; at 1.45 s the stroke
leaves the pen tip and crosses both pages (x 246.8–735), over a soft shadow
so it reads on white paper, then thickens to 2560 px into S2's page. S7 is
20.0–25.0 s with its holds trimmed and every LIVE range whole. S7b
(25.0–27.0 s): the S7 page dissolves into the stylist picture (`base`), the
caption rises at 25.00/25.05, the picture pushes in 1.00 → 1.03 about the
braiding hands and dissolves into the end card at 27.00. S8 (27.0–30.0 s):
dot 27.05, draw 27.10–27.70, tile 27.65, wordmark 27.70, CTA 27.75 (2.25 s
of 2.23).

**R1 — each finding of the review, and what changed:**

| Finding | Fix | Checked by |
|---|---|---|
| S4: each new bubble popped into the slot the one before was still leaving (clipped words, a second edge) at all three arrivals | The stack moves as one column: the new bubble enters one slot lower and rises with the others on `base`, fading and scaling on `fast`; nothing below y 1152 is drawn | « S4 bubbles never overlap » (384 pairs on 76 frames); it fails on the first render's motion (12 overlapping pairs) and on a test layout |
| S7's card travelled 2432 px in 300 ms (725 px in one frame) | S5 and S7 enter like S3: the card as it rests, clipped by the band, rises 1320 px from y 1920 | « cards move at most 410 px a frame » (404.6 px, S3's own first frame); it fails on the first render's motion (S7 745.7 px, S5 434.8 px) |
| S3's card covered S2's lockup while it was still visible | S2's exiting layer is drawn over the card, on its own clear space of paper at its own opacity | looked at, frames 180–189 |
| S5's first stop showed the page's back chevron in the band's fade | First stop W 122 (« ≈ 118 » leaves the chevron's tail at grey 223; 122 leaves none — the darkest pixel of x 110–220, y 540–610 is the card's own 247, where the first render had 22) | measured on frames 393–425 |
| The duplicate « Yao K. » was on screen about 2.4 s | The camera pans W 553 → 682 (23.73–24.13 s) as « Ma journée » comes back: both rows are now visible on frames 710–718 only, **0.30 s** | the old row's glyphs (pt 612–624 of the take) against the band, frame by frame |
| A grey smear where the band fades (the shadow seen through the card) | Card and shadow composed as one group under the band's alpha | the fade at x 95, 540, 980 now runs 250 → 247 with nothing darker but the card's own words |
| The « Libre » disc stayed over the pushing form | It fades out over 20.90–21.10 (`base`), gone on the push's first frame | looked at, frames 626–636 |
| The 5-frame dissolve read as a glitch | 12 frames on `slow`, taken from the filled-form hold, a clean picture on each side (frames 654 and 666) | looked at, frames 653–667 |
| Each strike began as a lone dot | Every strike starts at four times its width | self-test |

**Looked at** (the contact sheet and the 18 key frames decoded from the
file, and frame strips of every transition): the hook reads at frame 0 and
at grid-thumbnail size; the pictures are sharp enough at full size and never
stretched; the caption reads over the picture. Transitions checked frame by
frame: S1 → S2, S2 → S3, S4's three arrivals, S5's and S7's entrances, S7's
tap, dissolve and pan, S7 → S7b, S7b → S8.

**Deviations, A1 and R1** (the tool's README lists them with their reasons):
S7b's caption 2.00 s against the rule's 2.63; S5's first stop W 122 rather
than « ≈ 118 »; S1's picture fades into black below y ≈ 1599 and its stroke
ends short of the phone, with a soft shadow, thickening to 2560 px; S4's
column edge at y 1152; S2's lockup leaves on its own paper clear space; S7's
holds 18 / 2 / 20 / 5 frames, the headline out at 24.80; S8 re-timed with
the mark's 0.6-s draw intact (wordmark and CTA on the 50-ms stagger);
S7b → S8 a `base` dissolve (A1 leaves that transition open); the push-ins
hold once their span ends; the encoder's ceiling 12 and the photographs'
47-dB floor.


**Since the takes**: no commit touches the journal screen or the public
page; #611 and #614 touched the booking form's phone field, whose empty
state reads the same (« +225 », « Téléphone du client », a « 0/10 »
counter — read in code, not filmed).

## 10. Open questions

- Posting date and channels: the owner's decision (after the App Store
  release and once salons can go online).
- A re-take on the current build would remove risks 1–3 (owner chose not to,
  2026-10-18).
- S7b's caption: keep 2.0 s, lengthen the beat, or shorten the line (§7 risk
  15) — the owner's call.
- The AI-content label each platform asks for photorealistic generated
  pictures (§7 risk 13), at posting.
