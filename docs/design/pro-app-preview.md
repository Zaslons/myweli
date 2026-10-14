# MyWeli Pro — App Preview (the video shown before the screenshots)

| | |
|---|---|
| **Status** | **Approved by the owner on 2026-10-13** — the recommended film « in a style that follows MyWeli's », and the four decisions of §9: yes to all. **State on 2026-10-14**: the tool is built and reviewed (`tool/app_store_preview/`, #588); a **rehearsal** was cut and sent to the owner (a style proof — it makes no booking); the day of 14 October is staged on the demo salon; « Ma journée » is fixed and in build 581 (decision 2). **The real take is not shot**: it can only be recorded in daytime (§5). Nothing is uploaded. Three small choices came up in production (§9.1). |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-13 |
| **PRD ref / phase** | Launch — store submission · V1 |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Governs** | `tool/app_store_preview/` (its README carries the editing rule in full and the runbook for the take) · [app-store-forms.md](app-store-forms.md) §10, §13.1 · sits next to [pro-app-store-screenshots.md](pro-app-store-screenshots.md) |

## 1. Goal & scope

The owner asked on 2026-10-13 for a motion-design video of the Pro app,
shown first, before the eight screenshots. On the App Store that is an **App
Preview**. This spec says what Apple allows, proposes one film, and lists what
the owner must decide before anything is produced.

**In scope**: one French preview for MyWeli Pro (iPhone), portrait, in the
same brand frame as the stills. **Out of scope**: the consumer app, Google
Play (a different format and rulebook), other languages, an iPad cut.

## 2. What Apple allows — read on Apple's pages on 2026-10-13

| Rule | Value | Source |
|---|---|---|
| What may be shown | **Screen captures of the app itself, only.** Text overlays and narration are allowed where they explain what the footage does not. Touch indicators are allowed. No filmed hands, people or devices. | [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) 2.3.3–2.3.4 · [App previews](https://developer.apple.com/app-store/app-previews/) |
| Length | 15 to 30 seconds | [App preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications) |
| Size | **exactly 886 × 1920** (portrait) for every Face ID / Dynamic Island iPhone class — the device's own resolution is not accepted | same |
| Format | H.264 (`.mov`, `.m4v`, `.mp4`), up to High Profile Level 4.0, target 10–12 Mbps, progressive, **30 fps at most** — or ProRes 422 HQ. HEVC is not listed. | same |
| Sound | stereo AAC, 256 kbps, 44.1 or 48 kHz. Apple's API marks the audio track as **required** for this size — so a silent film still carries a silent track. | same · [Uploading and managing video assets](https://developer.apple.com/documentation/appstoreconnectapi/uploading-and-managing-video-assets) |
| How many | up to three per device size and language; one is enough | specifications page |
| Where it shows | **before the screenshots**, autoplaying **muted**; with autoplay off the *poster frame* shows instead (default: the frame at 5 s) | [Product page](https://developer.apple.com/app-store/product-page/) · specifications page |
| Disclosure | an app that requires sign-in must say so, in the footage or on an end frame | App previews page |
| Prices | no prices or terms in a preview (2.3.7); Apple's preview guidance says the same of specific prices | guidelines · App previews page |
| Personal data | fictional account data, not a real person's (2.3.9) | guidelines |
| First version | the preview must go **in the same submission** as the version; nothing can be uploaded once the version is « Waiting for Review » | [Submit assets from Asset Library](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-assets-from-asset-library) · [App and submission statuses](https://developer.apple.com/help/app-store-connect/reference/app-information/app-and-submission-statuses) |
| Afterwards | replaced only with a new app version; **the poster frame cannot be changed once approved** | [Placing assets on your App Store surfaces](https://developer.apple.com/documentation/appstoreconnectapi/placing-assets-on-your-app-store-surfaces) · specifications page |

**Not stated on any Apple page read** — so neither promised nor forbidden: a
brand frame around the capture (the stills use one), whether a *silent* audio
track passes processing, whether 886 × 1920 counts as the same aspect ratio as
the stills (if not, the preview is moved to « A Closer Look » instead of
leading), whether previews show on the Côte d'Ivoire storefront, and what
`xcrun simctl io recordVideo` really outputs. Each is checked at the step
that meets it (§7), never assumed.

## 3. Three films were drafted; one is recommended

Three storyboards were written independently, each from a different angle,
then scored on six criteria (compliance with 2.3.4, understood muted in three
seconds, one clear idea, fit with the stills, truth to the app, feasibility
on this Mac without installing anything).

| | Idea | Score | Why not, or why |
|---|---|---|---|
| A | « Une journée au salon » — one day from 09:41 to 18:30 | 22/30 | the best hook, but four takes in two time windows, and three captions repeat stills 1, 5 and 8 |
| B | « Trois promesses » — agenda, clients, revenue, one gesture each | 21/30 | safest to shoot, but read rather than seen; frozen frames under a veil; an end card with no app in it |
| **C** | **« Un seul geste » — a free slot becomes a booking, in one take** | **24/30** | one real, uncut flow; the simplest edit; nothing staged outside the app |

**Recommended: C, with A's opening and B's layout** — below.

## 4. The recommended film — « Geste après geste »

**21 seconds, one screen, one continuous flow.** No scene cut, no dissolve,
no change of speed. Portrait 886 × 1920, 30 fps.

**The frame** is the stills' own, scaled: paper background, the MyWeli mark, a
two-line Poppins headline, an Inter sub-line, and the live capture in the same
rounded card with the same shadow. Captions sit in the paper, never over the
app.

| Time | On screen | What happens | Headline · *sub-line* |
|---|---|---|---|
| 0.0 – 3.6 s | « Ma journée », 09:41, a full day | a swipe on a confirmed booking, « Arrivé » — the card turns green | **« Une cliente arrive ? / Un geste suffit. »** |
| 3.6 – 5.4 s | « Ma journée » → « Réservation » | a tap on « Libre — 10:45 »; the form opens with the date and the hour already set | **« Un créneau libre ? / Ajoutez un rendez-vous. »** |
| 5.4 – 10.4 s | « Réservation » | « Coupe homme », « Client sans numéro », the name « Yao K. », scroll to the total | same headline · *« Pris au téléphone ou au comptoir, / même pour un client sans numéro. »* (still 4's sub-line, word for word) |
| about 12.6 – 14 s | « Réservation » → « Ma journée » | « Créer le rendez-vous »; the button's own loader, the form closes, **« 10:45 Yao K. » is in the day** and « Rendez-vous créé » shows | unchanged |
| about 14 – 21.0 s | « Ma journée », at rest | nothing moves: the arrival is green, the slot is taken | **« Votre agenda à jour, / geste après geste. »** · *« Un compte MyWeli Pro est nécessaire. »* |

*Amended 2026-10-14.* The pull-to-refresh shot is gone: decision 2 was
taken and built, and on the fixed app the booking is in the day about 1.25 s
after the tap (seen on the simulator). The film stays **21.0 s, 630 frames** —
not the « about 19 seconds » first expected — because « Rendez-vous créé »
stays its own three seconds inside a stretch that may not be cut, and the
typing was found too slow to shorten further without cutting what the app
does. The times above are the tool's, from the rehearsal; the real take sets
the final ones. The poster stays at 18.0 s.

- **Motion** uses the design system's tokens only (`motion.dart`): captions
  cross-fade in place; a touch point marks each tap and follows each drag.
  Everything that moves inside the card is the app's own animation.
- **Poster frame: 18.0 s**, inside the final hold — the promise and the proof,
  with no touch point or snackbar on it. Apple's default (5 s) would land in
  the middle of the form. It is frozen at approval.
- **Sound: none.** Previews play muted, nothing has to be licensed, and the
  app makes no sound in this flow. The file carries a silent stereo track
  because Apple's spec asks for one.
- **The sign-in disclosure** is the last sub-line, over live footage.
- **Not shown**: the sign-in screen, « Mon abonnement » or any offer, the KYC
  screen, a « Compte de démonstration — … » message, a system alert, a phone
  number (« Client sans numéro » greys the field out), a real person's name.

## 5. Data — the day has to be staged

The film needs a believable day on the demo salon « Maison Nala », in
production: five bookings (one finished, one confirmed for the swipe, three
later) and free slots at 10:45, 13:15 and 14:45. Each take then writes two
things for real: one « Arrivé » — **which cannot be undone** — and one new
booking. Retakes move to the next confirmed card and the next free slot.

The weekly reset wipes the agenda (the next one falls around 18–19 October —
the exact run to be read before staging): shoot before it, or stage again
after it. Same kind of writes as the
screenshot shoot of 12 October — and they need the owner's go again (§9).

### 5.1 Staged on 2026-10-13 for Wednesday 14 October — and why the take needs daylight

Five bookings were created that evening on « Maison Nala », each as « Client
sans numéro » with a name and no phone number:

| Time | Client | Service |
|---|---|---|
| 08:00 – 09:30 | Awa K. | Brushing + Soin Capillaire |
| 09:45 – 10:45 | Mariam T. | Coupe femme — the card that is swiped to « Arrivé » |
| 11:15 – 13:15 | Fatou B. | Tresses |
| 14:00 – 14:45 | Aïcha D. | Brushing |
| 15:30 – 16:00 | Koffi A. | Coupe homme |

So « Ma journée » on the 14th shows « Libre — 10:45 » (30 minutes — exactly a
« Coupe homme »), « Libre — 13:15 » and « Libre — 14:45 ». A free row exists
only between two bookings at least 30 minutes apart.

**The real take can only be shot on the day itself, while the slot is still
ahead of the clock** — three rules of the app and the server, read in the code
and seen on the live agenda:

- the booking form refuses a time that is already past
  (`pro_manual_booking_screen.dart`), so « Libre — 10:45 » must be booked
  before 10:45 GMT — after that the 13:15 slot, then the 14:45 one, still work;
- « Arrivé » is accepted only on the booking's own day in the salon's time
  zone (`pro_appointment_service.dart`), and only on a confirmed booking;
- on the evening of the 13th every booking of that day was already
  « Terminé »: nothing to swipe.

Before the take: mark the 08:00 booking « Terminé », and nothing else. If
14 October is missed, another day is staged the evening before.

Also left on the demo salon: one test booking, « Essai Fix », Saturday 17 at
10:00 — created to see the fix of decision 2 work. Its dot shows in the week
strip. The weekly reset removes it.

## 6. Security & privacy

No secret is involved. The assistant never types the demo account's code; if
the session has lapsed the owner signs in. Names in the film are invented.
The upload goes to App Store Connect only on an explicit go.

## 7. Production — nothing to install

1. **Probe** (no write): record five seconds of a resting screen with
   `xcrun simctl io … recordVideo --codec h264 --mask ignored`, and read the
   file — size, frame timing, audio. Dry-run the form and back out: does an
   iOS keyboard rise, where is « Créer le rendez-vous » after the scroll.
2. **Stage the day** (§5), set the status bar to 09:41 as for the stills.
3. **Record** in the morning window (the form's slot must still be ahead of
   the clock). The assistant drives the simulator gesture by gesture; the
   fallback is the owner performing the 20 seconds by hand.
4. **Conform**: decode with Swift/AVFoundation, resample to a constant
   30 fps, scale the capture to the card. Idle time is removed **only where
   nothing on screen changes — a blinking text caret alone counts as nothing
   changing**, under measured thresholds; nothing between a touch and the end
   of the app's response is cut or retimed, and the tool refuses an edit list
   that does (*amended 2026-10-14: the first wording, « pixel-identical »,
   was not achievable with a caret on screen*).
5. **Compose** with Python and Pillow, reusing the tokens, the fonts, the mark,
   the mask and the shadow of `tool/app_store_screenshots/compose.py`.
6. **Encode** with a Swift `AVAssetWriter`: H.264 High Level 4.0, exactly
   886 × 1920, 30 fps constant, about 11 Mbps, plus the silent AAC track.
   *Measured on the rehearsal: 11 Mbps is the encoder's target; a mostly
   still interface compresses to 2.3 Mbps on average (7.2 Mbps in its busiest
   second). Whether Apple minds is unknown until processing.*
7. **Verify the written file** — size, 630 frames of exactly 1/30 s, 21.000 s,
   profile and level, one enabled stereo track — and **watch the checker fail**
   on the raw take (wrong size, no audio). Decode the 18 s frame and compare it
   with the composed image. A contact sheet goes to the owner.
8. **Sign-off, then upload** on an explicit go; read back the processing state,
   the poster frame, and that the preview sits ahead of the screenshots.

**Tools on this Mac**: Xcode (`simctl`, Swift, AVFoundation, `avmediainfo`),
Python 3 with Pillow and numpy, iMovie. **`ffmpeg` is not installed.** It
would replace the custom Swift encoder of step 6 with one command and give an
independent checker in step 7 — worth asking for only if the Swift encoder
stalls.

**Effort**: about 10 to 12 hours of work, plus the owner's review — an
estimate, not a measurement. A later reshoot with the tools in place: about
three hours.

## 8. Risks

**Refused at processing** (seen only after upload): a size other than
886 × 1920, a length outside 15–30 s, more than 30 fps or a variable frame
rate, HEVC, no audio track.

**Questioned at review**:

- **A mismatch with the binary** — the film must show what the reviewed build
  does. This is why decision 2 comes first.
- **Prices.** « 5 000 FCFA » and « Total » are on screen for about six
  seconds. They are the demo salon's tariffs, not the app's price, and stills
  4 and 6 already show the same thing — but 2.3.7 bars prices in previews and
  this reading is ours, not Apple's. An accepted risk, or the scroll to the
  total is dropped.
- **The brand frame.** Apple's pages do not address it. Fallback: the same
  take, full-bleed, captions over the app's own margins.

**Unknown at Apple** (§2): the silent track, the aspect-ratio rule, the Côte
d'Ivoire storefront.

**On the day**: an iOS keyboard rising over the form, the 30-minute service in
an exactly 30-minute gap, the date of the shoot visible in the form.

**Learned from the rehearsal (2026-10-13/14)**:

- **What the recorder gives**: H.264, 1206 × 2622, no audio, and a *variable*
  frame rate — a frame only when the screen changes. The tool is built on
  that.
- **No software keyboard rose** in the simulator, so the name appears letter
  by letter with nothing covering the form. That state is not guaranteed: it
  is checked, without writing, just before the take.
- **A screenshot taken during a recording makes the Dynamic Island blink out
  for about 0.15 s** in the footage. No screenshot while recording.
- **The creation took about 1.2 s** on the simulator; the tool accepts up to
  about 1.5 s before the final hold becomes too short, and refuses the take
  beyond.
- **The status bar must be set as for the stills** — battery « discharging »,
  which draws it black; « charged » draws it green.
- Ticking « Client sans numéro » moves its row up about 20 points under the
  finger; the runbook's coordinates allow for it.
- The film was looked at frame by frame and measured, **not yet watched
  playing by anyone but the owner**.

## 9. Decisions for the owner — all four taken on 2026-10-13: yes, as recommended

1. **Stage the day and write to « Maison Nala » in production?** Five staged
   bookings; per take, one « Arrivé » and one booking.
   *Recommended: yes, as on 12 October.*
2. **Fix « Ma journée » before filming?** Read in the code today: a booking
   created from « Ma journée » does not appear there until the list is pulled
   down — the form updates one store, the day view reads another, and nothing
   reloads it on return (`pro_journal_screen.dart`, `pro_manual_booking_screen.dart`;
   read, **not observed on a device**). A reviewer adding a booking would meet
   it too. *Recommended: fix it, build once more, and film that build* — the
   film then loses its pull-to-refresh and runs about 19 seconds. A preview
   can only be replaced with a new app version, so a workaround filmed today
   would stay on the store.
3. **The disclosure line**: « Un compte MyWeli Pro est nécessaire. » — with no
   word about offers or prices, in line with the companion position
   ([app-store-forms.md](app-store-forms.md) §2.4). *Recommended: as written.*
4. **The three headlines, the reused sub-line and the 18 s poster frame** —
   frozen once approved. *Recommended: as written.* Optional: move the agenda
   still from position 1 to 3, so the store does not open on two agendas in a
   row.

### 9.1 Three choices that came up in production — the owner's, each with what is built today

1. **The Dynamic Island.** The simulator's recording draws the black pill on
   every frame; none of the eight stills has it (their captures happened to
   come without). *As built: kept — the footage is not retouched.* Painting it
   out would match the stills, and would be retouching captured footage.
2. **When the last headline arrives.** *As built: about 0.6 s after the day
   is back*, while « Rendez-vous créé » is still on screen — which keeps the
   film at 21 s. Waiting for the snackbar to leave needs a 23-second film.
3. **The prices in the stills.** Stills 3, 4, 5, 6 and 8 were shot before the
   one-space price change (#579); the film shows prices as the app prints
   them now. *As decided on 2026-10-13: the stills are not reshot.*

## 10. Definition of done

The owner has signed off §4 and §9; the file passes the checker and the
checker has been seen to fail; the owner has watched the film and the contact
sheet; App Store Connect reports the preview processed, with the 18 s poster,
ahead of the screenshots; [app-store-forms.md](app-store-forms.md) §13.1 and a
roadmap entry record it.

## 11. Open questions

- Does the preview lead on the Côte d'Ivoire storefront? Only the live page
  will say.
- If Apple refuses pure digital silence, the fallback is an inaudible noise
  floor — to be tried only then.
