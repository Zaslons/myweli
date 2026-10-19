# MyWeli Pro — marketing Reel « Le trait » — design spec

| | |
|---|---|
| **Status** | **Approved 2026-10-18; amended 2026-10-18 (A1 + A2).** A1 (owner: people and pictures): the hook opens on the owner's picture of a salon owner writing in her paper notebook (the drawn notebook leaves S1, S6 keeps it), a people beat S7b (« Plus de temps pour votre métier. ») shows a stylist braiding a client, the end card runs 27.0–30.0 s — and A1 as built: the hook's black bottom band, under the Reels caption, is kept (the owner was asked explicitly and answered on 2026-10-18: « Keep the black band »). A2 (owner: the salon page shows Maison Nala): S5 opens on the top of the public page — its cover photo, its « Maison N » logo, its name — under « Photos, tarifs, horaires : tout sur votre page. ». The fixes from the review of the first render (R1) and the items of the review of the second render (R2: S7 runs 20.0–24.367 s so S7b's caption has its reading time, S3's card waits for S2's lockup, S4's arriving bubbles fade with what shows of them, S1's headline at the top of the safe zone, the AI pictures a posting step) and of the third (R3: S5's scroll chosen by position on a smooth target, S7's one black-button frame held on the loading picture, S7b's caption at the top of the safe zone, a dedicated cover picture with the headline 30 px lower) and of the fourth (R4: S7b's push-in cut to 1.02 and held still about the top of the stylist's bun, the cover picture on frame 0's push-in) are in. Approved first by the owner's sign-off on the final storyboard. Owner's decisions: the storyboard is approved as written, « carnet » kept; the « MyWeli Pro » unit is built from the wordmark SVG plus the « Pro » vectors of the Pro app-open Lottie, and on the end card the drawn mark becomes the Pro app icon — both approved; render now with the existing takes (no re-take, nothing written to production); posting is the owner's later decision; Reels 9:16, 1080 × 1920, 30 fps, 30 s, no music (the owner adds Instagram music), CTA « Disponible sur l’App Store »; audience: salon owners. **Built** on `feat/pro-marketing-reel` — see §9 for what the build measured (§9.2 for A1 and R1, §9.3 for A2 and R2, §9.4 for R3, **§9.5 « As built » for R4**, the current film). |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-19 |
| **PRD ref / phase** | Launch — marketing · V1 (the « real motion-design film for Facebook, WhatsApp and the website » that [pro-app-preview.md](pro-app-preview.md) §0.1 left as a later owner decision) |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Governs** | `tool/marketing_video/` (its README has the build and the checks in full). Sits next to [pro-app-preview.md](pro-app-preview.md) (`tool/app_store_preview/`, whose brand tokens, fonts, take conform and movie writer it reuses) and [pro-app-store-screenshots.md](pro-app-store-screenshots.md). |

## 1. Goal & scope

**What.** A 30-second vertical film that tells a salon owner in Abidjan, with
the sound off, that MyWeli Pro answers three things that go wrong on a salon
day — the paper appointment book, the same client questions at night, the
client who walks in without an appointment — on real footage of the demo
salon « Maison Nala », whose public page opens on its own cover photo and
logo (A2). It opens and closes on people (A1): a salon owner at her paper
notebook, and a stylist braiding a relaxed client under « Plus de temps
pour votre métier. ».

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

## 2. The storyboard (approved 2026-10-18, amended the same day: A1, A2; R3 and R4 the reviews of the third and fourth renders)

30.000 s, 900 frames at 30 fps. Cuts on a 0.5 s grid (frames 75, 180, 300,
375, 525, 600, 810) so a 115–130 BPM track locks to them — except the S7 →
S7b dissolve, which starts at frame 731 (24.37 s, R2) so S7b's caption has
its reading time; a 200-ms dissolve whose middle is within 2 frames of the
24.5 s beat. Pains are black (#000); answers are paper (#FAFAFA).

| Scene | Time (frames) | On screen (French) | Picture | Motion |
|---|---|---|---|---|
| **S1** hook « carnet » (A1) | 0.00–2.50 (0–74) | « Votre salon, / encore au carnet ? » | The owner's picture (AI-generated, 941×1672): a salon owner writing in her paper notebook, full bleed in width at 1.1477 (the least that fills the width), its notebook at y ≈ 1170–1480 (the crossing at y 1232, above the caption zone), its bottom edge fading to black at y ≈ 1599 (A1 as built: the black band under the Reels caption kept, the owner's answer of 2026-10-18); a black gradient 72 % → 0 (y 380–960); Poppins Medium 92/106 white headline at y 280–492, the top of the safe zone (R2) | Push-in 1.00 → 1.04 about the stroke's start (linear, 0–2.50); headline settles from scale 1.02 (`fast`); at 1.45–1.70 a white 8-px stroke leaves the pen tip and crosses the open pages (x 246.8–735, y 1232) over a soft shadow. Cover frame: f54 (1.80 s), exported as its own picture with the headline 30 px lower (R3; the film's frames unchanged) |
| **S2** mark + promise | 2.50–6.00 (75–179) | « MyWeli Pro » (vector unit) · « Plus de clients, moins de gestion. » | Paper; the mark 220 px tall at (540, 580); the « MyWeli Pro » unit 480 px wide at y 756; the tagline Poppins Medium 52 #3D3D3D at y 950–1014 | The S1 stroke thickens to 2560 px about its line (`slow`) and becomes the page; pen dot 2.70; the mark draws 2.80–3.40 in the fast loader's path order on (0.4, 0, 0.2, 1); unit 3.15, tagline 3.20 rise 16 px (`emphasis`); exit 6.00–6.20 (40 px up, easeIn); S3's card starts only at 6.10 (R2), so it never enters the lockup's clear space while it shows |
| **S3** answer « Ma journée » | 6.00–10.00 (180–299) | « Votre journée, / heure par heure. » | Answer layout (below); take1b « Ma journée » | Card rises 6.10–6.40 (R2); camera W 56 → 350 at 7.10 (`slow`); LIVE swipe on Fatou B. 11:15 (take 10.662–11.628 s, 1:1), the green « Arrivé » pane opens; held open to 10.00; black touch disc follows the logged drag |
| **S4** pain « questions » | 10.00–12.50 (300–374) | « Encore les mêmes / questions ? » — « C’est combien, les tresses ? » 22:41 · « Vous êtes où exactement ? » 22:43 · « Vous fermez à quelle heure ? » 22:47 · « Allô ? » 23:02 | Hard cut to black; neutral received bubbles #1E1E1E, Inter Regular 48 white, timestamps Inter 34 #8A8A8A, stacked y 614–1150 | Bubbles arrive at 10.30/10.60/10.90 as one column: each enters one slot below the bottom slot and rises with the others 140 px (`base`), fading and scaling in on `fast` — never more opaque than the share of it above y 1152 (R2); nothing below y 1152 is drawn; a full-width stroke through « quelle heure » at 11.90 |
| **S5** answer « page » (A2) | 12.50–17.50 (375–524) | « Photos, tarifs, horaires : / tout sur votre page. » (78 px: the first line is 965 px at 84) | Answer layout; take5b: the page at rest on its top (cover photo, « Maison N » logo, « Maison Nala », « Abidjan », « Nouveau »), its one drag — the take's pictures chosen by scroll position (R3) —, the page at rest after it; the status bar and the back button's disc under the solid band (W 136); the salon's phone row masked white on every picture that shows it | Stroke thickens to paper; card enters at W 136 on the top of the page (12.80) and holds it (about 1.4 s); the page's own scroll 14.00–16.10 (R3: take5b's drag 26.167–28.533 s, each frame the picture whose scroll is nearest a smooth target, the gesture's own cosine eased in from rest, 2.095 s fitted to the take, moved by its sub-pixel remainder) brings « Services · 5 services • Voir les tarifs » and the map, at rest to 16.40; camera W 136 → 470 (`slow`) at 16.40 to the hours and « Aperçu — voici ce que verront vos clients. » |
| **S6** pain « sans rendez-vous » | 17.50–20.00 (525–599) | « Un client / sans rendez-vous ? » — « 13h  Mariam — brushing », « 14h  Aïcha — tresses », « 15h30  Koffi — coupe homme », « 16h30  Rokia — soin capillaire », « 17h  Awa — tresses », « + 14h45  coupe homme · n° ? » | Hard cut to black; the S1 notebook, afternoon page; the walk-in squeezed on the minor rule at baseline 804 | Entries 4–5 pop; the squeezed entry pops at 17.95; « n° ? » struck at 18.45; full-width stroke at y 788, 19.60–19.85 |
| **S7** answer « réservation » | 20.00–24.367 (600–730) | « En quelques gestes, / même sans numéro. » | Answer layout; take1b at W 553, then 682: « Libre — 14:45 » → « Réservation » → the filled form (« Client sans numéro », « Yao K. ») → « Créer le rendez-vous » → « Rendez-vous créé » and the new 14:45 row | Card enters 20.30; tap « Libre » (black disc, gone by 21.10) at 20.90, LIVE 19 frames (to where the take stops changing, R2); 2-frame hold; **declared dissolve** 21.600–22.000 (12 frames on `slow`, skips 97.5 s of real input); 8-frame hold (R2); white disc on the black button, LIVE 22.267–24.200 with the real server time — frame 690 (23.00) holds the loading picture over the take's one black-button picture before the push (R3); the camera pans W 553 → 682 (23.10–23.50) as « Ma journée » comes back, the old 13:15 « Yao K. » sliding under the band; « Rendez-vous créé » 0.9 s; headline fades 24.167–24.367 |
| **S7b** people (A1, R2) | 24.367–27.00 (731–809) | « Plus de temps / pour votre métier. » | The owner's picture (AI-generated, 941×1672): a stylist braiding a relaxed client, full bleed at 1.1483 (the least that fills the frame); a soft black gradient 62 % → 0 (y 420–1000); the caption Poppins Medium 92/106 white at y 269–481, the top of the safe zone (R3), clear of the stylist's bun | The S7 page dissolves into the picture (`base`, from frame 731, off the 0.5 s grid); push-in 1.00 → 1.02 about the top of the stylist's bun, held still under the caption (linear; R4 — it was 1.03 about the braiding hands); caption lines rise 24 px and fade in at 24.367/24.417 (`emphasis`); the picture dissolves into the end card at 27.00 (`base`) |
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
their exit at least max(1.5 s, characters ÷ 15 + 0.5 s), **with no
exception** (R2): S1 2.77 s of 2.57 needed; tagline 2.80 of 2.77; S3 3.80 of
2.57; S4 2.73 of 2.37; S5 4.75 of 3.63; S6 2.70 of 2.37; S7 3.92 of 2.97;
**S7b's caption 2.63 of 2.63** (it was 2.00, A1's beat); CTA 2.25 of 2.23.
Brand time 6.43 s of 30 (21.4 %, ≤ 25 %).

## 3. Truth rules — what the film claims, and what it deliberately does not

- **Every answer is the real app, recorded.** S3 and S7 are the production
  recording take1b (2026-10-14, demo salon Maison Nala, invented client
  names); S5 is take5b (the keyed build with real CARTO tiles): the page at
  rest on its top with the salon's own cover photo and logo, its one drag,
  the page at rest after it (A2). LIVE ranges play 1:1, conformed to
  30 fps by frame-hold (`Conform.swift`), never retimed, never blended
  except the one **declared dissolve** in S7 — the App Store film's own cut —
  which must read as a time skip, never as a speed-up. **Two declared
  departures (R3, the review of the third render):** S5's drag shows the
  take's own pictures in the take's own order, but each frame takes the
  picture whose scroll is nearest a smooth target — the gesture's own
  cosine, its length (2.095 s, against the 2.306 s the take's drag took)
  fitted to the take's scroll map, eased in from rest — moved by the
  remainder (at most 5.6 capture px, 1.9 pt); the simulator had presented
  the drag at about 44 distinct positions a second (102 in 2.306 s), which a 30-fps frame-hold turned
  into a 9 / 18-px judder. The page's cover scrolls with the content (no
  parallax), so that move is the page's own; only its fade (84–168 pt of
  scroll) is read at the picture's scroll, at most 1.9 pt off. And S7's
  frame 690 holds the loading picture one frame (33 ms) over the take's one
  picture where « Créer le rendez-vous » turns black again before the form
  closes.
- **Code paths behind the screens** (checked when the storyboard was
  written): `pro_journal_screen.dart` `_startPane` (« Arrivé ») and `_gap()`
  (« Libre — HH:MM » opens `/pro/appointment/new`);
  `pro_manual_booking_screen.dart` (« Client sans numéro » l.361, « Créer le
  rendez-vous » l.407, « Rendez-vous créé » l.250); `provider_detail_screen.dart`
  (« Voir les tarifs » l.678, the « Aperçu » bar l.1192, « Réserver (après la
  mise en ligne) » l.1207).
- **Headlines are approved store copy or literal on screen**: S3 is
  screens.json 01 word for word; S5's « Photos, tarifs, horaires » is the
  owner's A2 headline, each word on the page itself (the cover photo,
  « Voir les tarifs », the hours; screens.json 02 before it); S7 joins
  screens.json 04's headline and sub-line.
- **Not claimed, on purpose**: no SMS, WhatsApp or reminder sending (messaging
  is OFF until the company is registered — S4's bubbles are the pain, no
  MyWeli screen answers them with a message); no payment, deposit or
  no-show prevention (no screen exists; the « lapin » beat was removed); no
  before/after (A2: only a partner salon's real work may ever be shown as
  before/after); no figures, prices or offers; S3 shows the gesture opening « Arrivé », not
  that the arrival was saved; « Réserver (après la mise en ligne) » stays
  visible as the page's own caveat.
- **Never on screen**: a readable phone number (S5's salon phone row is
  masked white in capture space before the camera moves, on every picture
  of the page's scroll; S7 shows no digits), the status bar, the Dynamic
  Island, the page's floating back button, a real person (A1's people are
  the owner's AI-generated pictures:
  illustrative atmosphere, never captioned as real customers, never a
  testimonial), a third-party chat look (no WhatsApp green, no ticks, no
  logo), an Apple logo or badge artwork.
- **Maison Nala's photos (A2)**: the cover photo and the « Maison N » logo
  are the demo salon's own, shown as its public page shows them; the owner
  confirmed they are free-licensed (the source links of Maison Nala's
  cover and logo, owed before posting).
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
| Covers | `poster-hook.png` (frame 0), `poster-end.png` (the last frame) — composed, lossless; `cover.png`, the storyboard's cover (frame 54, 1.80 s) **composed as its own picture with the headline 30 px lower** (R3: block top y 310, its ink 41 px below the 4:5 crop's top, where the film's frame 54 has 11), and `cover-4x5.png`, the same cut to the 4:5 feed crop (1080 × 1350). R4: its picture is at frame 0's push-in (scale 1.00), its stroke and words frame 54's — her face 21 px lower than on frame 54, so the second line keeps a band of braids above her hairline. **On Instagram the cover is uploaded separately**, as the Reel's cover picture; the film's own frames, frame 0 among them, are unchanged |
| Review | `contact-sheet.png` (a frame every 0.5 s, decoded from the written file, labelled), `frame-<t>.png` at 28 key moments (R4 adds 26.5 s), `verify.txt` |

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
missing glyph, the reading times with no exception (R2) and the brand time;
the cover picture's headline at least 40 px inside the 4:5 crop (R3);
no two of S4's bubbles ever overlapping; no card moving more than 410 px
between two frames; no card box inside S2's lockup's clear space (the mark
and the unit, half the mark's height all round) or the tagline's line while
they show (R2); A1's pictures never smaller than their fill nor larger than
their push-in. Against the build: each LIVE and HOLD range of take1b and
take5b against its take map (R3: S7's one held frame declared and checked as
a `skip`; S5's drag frames each on the picture nearest the plan's target,
moved by exactly the remainder, never back), S5's scroll steps measured on
the composed frames (R3: never back, none above 1.6 × the mean of its
neighbours + 0.5 px, the first no larger than the next five, within 0.35 px
of the scroll the frames were drawn at), S5's phone row white on every composed frame —
through the page's own scroll (A2) as at the camera stops — and on the
decoded file, key frames decoded against the composed ones (48 dB; 47 where
the ground is a photograph), and the white words over A1's pictures at 4.5:1
or more against what lies under them (the cover picture's too), S7b's
caption at least 8 px above the stylist's braids on every frame where it is
whole (R3; R4 raised it from 2). A self-test runs verify on a
deliberately wrong file, on a plan with a box outside the zone, on
overlapping bubbles, a jumping card, an over-enlarged picture, S7b's caption
at A1's 2.0-s beat and S3's card entering at 6.00 s, on a take5b row moved
off its rectangle and a scroll map 2 pt off, on the third render's S5
cadence (by numbers and on pixels), a step that goes back, a skip on the
wrong picture or standing for two frames, a drag frame on a farther
picture or chosen by time, the film's own frame 54 as the cover, and a
dark band drawn 4 px under S7b's second line (R4), and watches each fail.

## 7. Risks (from the storyboard, carried as approved; updated for A1)

1. **Footage age.** take1b and take5b are from 2026-10-14; since then only
   #611 (2026-10-15, the PhoneNumberField's 10-digit rule) touches a filmed
   screen. The EMPTY phone field shows for about 0.55 s in S7 (21.43–21.97
   s, through the dissolve). The owner chose to render with the existing
   takes.
2. **Duplicate « Yao K. ».** take1b already holds a 13:15 « Yao K. ». The
   camera pans as « Ma journée » comes back, so both rows are on screen
   together only for frames 691–699 (23.03–23.30 s, **0.30 s**, while the
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
13. **People (A1) — a POSTING STEP.** The two pictures are AI-generated by
    the owner (ChatGPT/Gemini, 2026-10-18; `build/marketing/photos/PROVENANCE.md`),
    used as illustrative atmosphere, never captioned as real customers or a
    testimonial. **When posting: turn on TikTok's « AI-generated content »
    label, and Meta's « AI info » disclosure on Instagram and Facebook; the
    post caption must not imply a real salon or a real customer.** The
    pictures are 941 × 1672, enlarged 1.148–1.194× in the film (slightly
    soft at full size).
14. **S1's framing (A1 as built — the black band under the Reels caption
    kept; the owner's answer, 2026-10-18: « Keep the black band »).** To bring
    the notebook's crossing above the caption zone, the picture sits 320 px
    above its natural place: its bottom edge fades into black (the bottom
    17 % of the hook, under the Reels caption, which it helps to read). The
    headline block now sits at y 280, the top of the safe zone (R2), so its
    second line ends above her hairline.
15. **S7b's caption reading time — resolved (R2).** « Plus de temps pour
    votre métier. » (32 characters) is on screen 2.63 s, what the rule asks:
    S7b starts at frame 731 (24.37 s, off the 0.5 s grid), with 19 frames
    taken from S7's still stretches (the unfilled form 13 → 6 still frames,
    the filled form's hold 20 → 8); the tap, the dissolve and the
    snackbar's 0.9 s are untouched.
16. **Maison Nala's photos (A2).** The cover photo and the logo are the demo
    salon's own; the owner confirmed their free licence, but their source
    links are still to be recorded — the source links of Maison Nala's
    cover and logo, owed before posting.
17. **S5's pace (A2, R3).** The page's own scroll, its pictures chosen by
    position on a smooth 2.095-s cosine (§3's declared departure), runs in a
    5-s beat: the top of the page holds about 1.4 s (the scroll then eases
    in from rest), Services and the map settle and rest 0.3 s, the hours
    hold 0.7 s after a 400-ms camera move; v2's map stop (W 300) is left out.
18. **The cover (R3, R4).** The film's frame 54 has only 11 px above its
    headline in the 4:5 feed crop; the cover picture sets the headline 30
    px lower (41 px) on the picture at frame 0's push-in, her face 21 px
    lower than on frame 54, so the second line keeps a band of braids
    above her hairline (R4; at frame 54's push-in it ended on it). Upload
    `cover.png` as the Reel's cover on Instagram rather than picking a
    frame.

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

### 9.2 Amendment A1 and the review's fixes (R1) — the second render (2026-10-18)

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


### 9.3 Amendment A2 and the second review's items (R2) — the third render (2026-10-18)

Rendered from the same takes (take1b `b0a455b9…`, take5b `59fab94b…` with
its scroll map `phone_rect_per_frame.csv` `e1fd9c51…`), A1's two pictures
and the storyboard as amended (sha256 `7b7513e1…`), in a scratch folder — no
film, take or picture is committed:

- `reel.mp4`: 900 frames, 30.000 s, 41,940,795 bytes, sha256
  `9aad431cfe94b48f…`; **PASS — 35 checks** (the new one: « S2's clear space
  kept »); 11.18 Mbit/s on average, 49.72 Mbit in the busiest second (Level
  4.1 allows 62.5; against the second render's 9.36, S5's live scroll over
  the cover photo costs 30 Mbit more and S7b's 0.63 s more of a photograph
  24 Mbit more), the sound decoding to zeros; the worst graphic key
  frame at 52.2 dB (frame 387, S5's card entering), the worst photograph key
  frame (frame 0) at 47.8 dB.
- 594 distinct pictures in 900 frames; 61 s end to end on four processes
  (conform 19 s, compose 17 s, encode 12 s, covers + sheet + verify 14 s).
- Reading times all met, **no exception**: S7b's caption 2.63 s of 2.63. Safe
  zone: the tightest box is S1's first headline line at frame 0 (its line
  box at the 1.02 settle), 8.9 px inside the zone's top. The white words over
  the pictures at 9.5:1 (S1, up from 8.4 with the headline higher) and 6.4:1
  (S7b) or better.
- S5's phone row: 43 of take5b's 71 pictures carry a mask — each the rest
  picture's rectangle moved by the picture's scroll, holding the rest
  picture's row pixel for pixel and ringed by white, and on every picture
  the page just above the bar matches the rest picture moved by that
  scroll (the scroll map is checked, not trusted: 2 pt off on a picture
  whose row is under the bar, it is refused); 72 composed frames show the
  masked row (39 of them in the page's own scroll), every pixel of it
  white; 13 decoded frames across the scroll, the stop and the camera move,
  white to 245 or more.

**A2, as built.** S5's card enters at 12.80 s on the top of Maison Nala's
page at W 136: the band hides the status bar and the back button's white
disc (to pt 110.3, frame y 542) — the cover photo of the salon interior
shows from the band's fade to y 936, the « Maison N » logo at 757–900,
« Maison Nala », « Abidjan », « Nouveau » below it. The top holds to 14.00;
the take's own drag then plays LIVE 1:1 (take5b 26.167–28.533 s, 71 frames,
the cover collapsing into the header as the app draws it) and settles on
Services, « Voir les tarifs » and the map at 16.33; at 16.40 the camera
moves W 136 → 470 (`slow`, as S3's) to the hours and « Aperçu — voici ce que
verront vos clients. », held to 17.50. The headline « Photos, tarifs,
horaires : tout sur votre page. » is set at 78 px (896 / 769 px): at 84 its
first line is 965 px, wider than the column and the safe zone, and the
suggested break is the only one. The take never shows the top of the page
in motion before the drag: it rests on its top for its first 26.17 s, so the
top is a held picture of the real page, not a camera move on a still.

**R2 — each item of the second review, and what changed:**

| Item | Change | Checked by |
|---|---|---|
| (a) S7b's caption was 2.00 s against the rule's 2.63 | The S7 → S7b dissolve starts at frame 731 (24.367 s): S7's first live range ends where the take stops changing (the unfilled form's still frames 13 → 6) and the filled form holds 8 frames (was 20); the tap, the 12-frame dissolve and « Rendez-vous créé »'s 0.9 s untouched. The storyboard's concept names the one off-grid cut, and the plan refuses any other | « reading time » with no exception (2.63 of 2.63); a self-test puts the caption back at A1's 2.0-s beat and watches it fail by name |
| (b) S3's card's words under S2's lockup on frames 184–185 | S3's card enters at 6.10 (frames 180–182 are paper and the leaving lockup); the paper plate at the lockup's opacity is gone | « S2's clear space kept »: no card box in the lockup's clear space (mark and unit, half the mark's height all round) or the tagline's line while they show — 211 px below the tagline at its closest (frame 185); a self-test enters the card at 6.00 and watches it fail at frame 183 |
| (c) An arriving bubble sliced at full white at y 1152 | Its opacity is the lesser of its `fast` fade and the share of it above y 1152 | a self-test over frames 309–335 (and the same test against a column edge moved on purpose: 15 violations) |
| (d) S1's black band; the second line on her hairline | The band left as built (amendment « A1 as built »; the owner had not answered yet — the answer, « Keep the black band », came after this render, §9.4); the headline block moves to y 280, the top of the safe zone | the safe zone (8.9 px in at the settle); looked at on frame 0 and at grid-thumbnail size (112 and 180 px wide): the second line ends at y ≈ 472, above her hairline (y ≈ 500) |
| (e) The AI pictures a « check » | A posting step (§7 risk 13): TikTok's « AI-generated content » label and Meta's « AI info » disclosure on; a caption that implies no real salon or customer | — |

**Looked at** (the contact sheet and the 19 key frames decoded from the
file — 0.0, 1.5, 3.5, 6.1, 6.2, 10.4, 11.0, 12.9, 13.5, 14.5, 15.5, 17.0,
21.0, 24.0, 24.5, 25.5, 26.9, 27.5, 29.5 s — and frame strips of S2 → S3
(180–189), S4's arrivals at the column edge, S5's top under the band
(393–440), S7 (624–668, 690–745) and S7 → S7b): the top of the page reads at
once — photo, logo, name — with no status bar and no back button; the
scroll is the app's own; the phone row is never seen; S3's card meets the
logo only after it has gone; the arriving bubbles are faint where they are
cut; the caption reads for its whole 2.63 s. At 24.5 s the S7 page is still
faintly in the dissolve (frame 735, the fifth of six), as a `base` dissolve
is.

**Deviations, A2 and R2** (the tool's README lists them with their reasons):
S5's headline at 78 px; S5 at W 136 (not 122) and without v2's W 300 stop;
S5's rest picture is take5b's 28.500 s (v2 held 28.665 s, the same picture);
S5's camera move on `slow` 400 ms (v2's were 600 ms); the one cut off the
0.5 s grid (frame 731); S3's card at 6.10.

**Since the takes**: no commit touches the journal screen or the public
page; #611 and #614 touched the booking form's phone field, whose empty
state reads the same (« +225 », « Téléphone du client », a « 0/10 »
counter — read in code, not filmed).

### 9.4 As built — the third review's items (R3): the fourth render (2026-10-19)

Rendered from the same takes (take1b `b0a455b9…`; take5b `59fab94b…` with
its scroll map `e1fd9c51…`), A1's two pictures and the storyboard as amended
(sha256 `1aee19a3…`), in a scratch folder — no film, take or picture is
committed:

- `reel.mp4`: 900 frames, 30.000 s, 41,862,549 bytes, sha256
  `3c4b6012329825cd…` (rebuilt from the commit; the sha256 is per encode:
  two encodes of the same frames differ in 11 bytes — the boxes' creation
  times and one byte of the encoder's own SEI note — and decode to the same
  pictures); **PASS — 38 checks** (new: « cover headline 40 px
  inside the 4:5 crop », « S5 scroll smooth », « S7b caption clear of her
  hair »); 11.16 Mbit/s on average, 49.82 Mbit in the busiest second; the
  worst graphic key frame at 51.8 dB (frame 435, S5's scroll), the worst
  photograph key frame at 47.8 dB (frame 735).
- 586 distinct pictures in 900 frames; 77 s end to end on four processes.
  Against the third render only frames 421–489 (S5's scroll), 690 (S7) and
  732–814 (S7b's caption) differ; frame 0 is identical.
- Reading times, brand time (21.4 %), safe zone, rail, bubbles, cards,
  S2's clear space and the pictures' scale as in §9.3; the tightest box is
  now S7b's first caption line, whose line box sits on the safe zone's top
  (0.0 px in; its ink about 20 px lower).

**The owner's answer.** Asked explicitly on 2026-10-18 whether to keep the
hook's black band under the Reels caption, the owner answered « Keep the
black band ». The storyboard's amendment reads « A1 as built — black band
under the Reels caption kept; owner's answer 2026-10-18 » (by: owner); R2's
earlier wording, which called the band accepted before the owner had
answered, is corrected.

**R3 — each item of the third review, and what changed:**

| Item | Change | Checked by |
|---|---|---|
| S5's scroll juddered (steps of about 9 and 18 px in turn, a 15-px first step) | The take's drag is exported whole (145 pictures, 102 distinct scroll positions, each checked to the capture pixel on the picture). The target is s*(t) = 862 px × (1 − cos πu) / 2, u = (t − 14.000 s) / 2.095 s: the gesture's own cosine eased in from rest, its length fitted to the take's positions by least squares with the repeated samples removed (2.0951 s). Each of the 63 frames 420–482 shows the picture nearest the target, moved by the remainder (at most 5.56 capture px) before the camera transform; the phone-row mask, painted before the shift, moves with it. The scroll ends at 16.10; Services and the map rest to 16.40 | « S5 scroll smooth »: steps measured on the composed frames, 0.38 px first, 16.1 px at the most, within 0.04 px of the planned scroll; never back, none above 1.6 × its neighbours' mean + 0.5 px, the first no larger than the next five — on the third render's frames it fails (25 steps above, a 14.9-px first step). « take map »: every drag frame on the nearest picture, never back. Looked at: frames 419–457 of the cover's collapse — no tear; under the band the picture brightens steadily as the cover fades (frames 438–450), no flicker |
| S7's black flash at 23.00 s (f690) | A declared `skip`: frame 690 holds the loading picture of frame 689; the next live range resumes 1:1 at 131.028 s | « take map » (a skip shows the picture its range ends on and stands for exactly one frame; self-tests refuse one on another picture or two frames long); the button region reads 245 on frames 684–690, then the push. The black « Créer » bar shows on the push's first three frames (f691–693, 23.033–23.100 s; a sliver of 68 and 27 px at the card's right edge on f694–695): the leaving form's own button, carried off by the app's own push — not the flash coming back |
| S7b's « pour » on the stylist's bun | The caption block at y 269, the top of the safe zone (47 px higher). At the review's ~35 px (y 281) « pour » met the bun from about frame 780 and was 8 px into it at frame 808: the push-in raises the bun 18 px | « S7b caption clear of her hair »: on all 69 frames where the caption is whole, its second line at least 4 px above the braids (it fails at y 281: 8 px into them; at the third render's y 316: 43 px); looked at on frame 809 |
| The cover's 4:5 headroom (11 px) | `cover.png`, composed apart with the headline 30 px lower, and `cover-4x5.png`; uploaded separately on Instagram; frame 0 unchanged | « cover headline 40 px inside the 4:5 crop » (41.0 px; fails at the film's own 11.0); the cover's words at 8.6:1 or more |
| Docs lagging the build | The README's camera move (`slow` 400 ms, as S3's and S7's); the rationale's reading table and brand share from verify (S4 2.73, S6 2.70, 21.4 %); the source links named inline (« the source links of Maison Nala's cover and logo, owed before posting ») | — |

**Looked at** (the contact sheet and the 27 key frames decoded from the
file — 0.0, 1.5, 3.5, 6.1, 6.2, 10.4, 11.0, 12.9, 13.5, 13.9, 14.1, 14.5,
15.0, 15.5, 16.0, 16.3, 17.0, 21.0, 22.9, 23.0, 23.1, 24.0, 24.5, 25.5,
26.9, 27.5, 29.5 s — the cover and its 4:5 cut, frames 419–457 of S5's
collapse, frames 462–486 of the masked row, and frames 737, 770 and 809 of
S7b): the scroll starts imperceptibly and settles the same way; the cover
folds into the header with no seam; the phone row is never seen; at 23.00
the button is still loading, and the black « Créer » bar shows on the
push's first three frames (f691–693, from 23.033 s), carried off the card's
right edge by the app's own push (a last 68- and 27-px sliver on f694–695);
« pour » stays above the bun to the last frame; on the cover the headline
has room above it in the 4:5 cut, and its second line ends on her hairline,
her face clear.

**Deviations, R3**: S7b's caption block at y 269 (47 px higher, not ~35:
35 px left « pour » in the bun); S5's scroll re-paced on the fitted cosine
(§3); the cover a composed picture, not a frame of the film.

### 9.5 As built — the fourth review's items (R4): the current film (2026-10-19)

The fourth render's review said ship, with nits; R4 takes them. Rendered
from the same takes and pictures and the storyboard as amended (sha256
`6e3f924e…`), in a scratch folder — no film, take or picture is committed:

- `reel.mp4`: 900 frames, 30.000 s, 41,878,457 bytes, sha256
  `2ed0814a68748544…`; **PASS — 38 checks**; 11.16 Mbit/s on average, 49.98
  Mbit in the busiest second; the worst graphic key frame at 51.8 dB (frame
  435), the worst photograph key frame at 47.8 dB (frame 735), over 28 key
  frames (26.5 s added). 39 self-tests.
- 586 distinct pictures in 900 frames; 72 s end to end on four processes.
  Against the fourth render only frames 732–814 differ (S7b and its
  dissolve into the end card); both posters are identical.

**R4 — each item of the fourth review, and what changed:**

| Item | Change | Checked by |
|---|---|---|
| S7b: « pour » 4–5 px above the bun on the last 0.3 s, a guard of 2 px | The push-in runs 1.00 → 1.02 (was 1.03) and holds still the top of the stylist's bun, picture point (220, 420), not her braiding hands: about the hands, 1.02 alone still left 9 px at its full extent (frames 810–815). The bun now stays where it is; the hands drift 14 px down and 8 px right over the 2.63 s | « S7b caption clear of her hair » asks 8 px (was 2): 23 px on all 69 frames where the caption is whole (closest at frame 741); on the fourth render's frames it fails (4 px at frame 808). New self-test: a dark band drawn 4 px under the second line fails by name, 12 px passes, a band through the ink is « into the braids »; with the guard back at 2 it goes red. On the decoded frames at 25.5, 26.5 and 26.9 s, measured as the review did (ink above 200, braid below 45, x 228–290): 24 px (the fourth render: 5) |
| The cover's second line on her hairline | `cover.png` is composed on the picture at frame 0's push-in (scale 1.00) with frame 54's stroke and words; the headline still 30 px lower | « cover headline 40 px inside the 4:5 crop » (41.0 px); the cover's words at 8.6:1 or more against the cover's own ground. Her face sits 21 px lower than on frame 54 and the line 30 px lower: the band of braids between them is 9 px narrower than frame 54's (the review measured about 25 px there, so about 16 here) and 21 px wider than on the fourth render's cover. Looked at at 2× and 3×: a band of braids runs between the line and her forehead; `cover-4x5.png` is exactly `cover.png`[285:1635] |
| Doc leftovers | The end card's brand time (6.43 s, or 21.4 %, 193 of 900 frames: S2 81–185 and the end card from its pen dot, 812–899); A2's « what » marks its 1:1 scroll « — R3: chosen by scroll position on a smooth target, not 1:1 »; §3 and the README give one figure for the drag, about 44 distinct positions a second (102 in 2.306 s); the black « Créer » bar on the push's first three frames, f691–693 (§9.4, README) | Measured on the composed frames: the bar is 341, 230 and 132 px wide on f691–693, then a 68- and a 27-px sliver at the card's right edge on f694–695, gone from f696 |

**Looked at** (the contact sheet and the key frames decoded from the file,
with 0.0, 24.5, 25.5, 26.5, 26.9 and 29.5 s side by side; S7b's caption at
2× on 25.5, 26.5 and 26.9 s against the fourth render's 26.9; the cover and
its 4:5 cut, and its hairline at 2× and 3× against frame 54 and the fourth
render's cover; S7's push, frames 690–697): a clear band of wall stays
between « pour » and the bun to the dissolve; the cover keeps its headroom
in the 4:5 cut, with braids between the second line and her forehead.

**Deviations, R4**: S7b's push-in about the bun, not the hands (§2); while
the caption rises in (24 px on `emphasis`, frames 733–736) its second line
passes within 3 px of the bun at 8 % opacity and 9 px at 34 %, 15 px or more
from 61 % on; the cover's stroke is frame 54's (x 246.8–735), so on the
picture at scale 1.00 its end runs about 13 px further past the page's edge
onto the counter than on frame 54.

## 10. Open questions

- Posting date and channels: the owner's decision (after the App Store
  release and once salons can go online).
- A re-take on the current build would remove risks 1–3 (owner chose not to,
  2026-10-18).
- The posting steps (§7 risks 13 and 16): the AI-content labels on TikTok and
  Meta, and the cover photo's and logo's source links recorded.
