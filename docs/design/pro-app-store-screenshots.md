# MyWeli Pro — App Store screenshots

| | |
|---|---|
| **Status** | **Approved by the owner and uploaded to App Store Connect (2026-10-13, evening)** — 16 images, all processed, in order, checksums matching ([app-store-forms.md](app-store-forms.md) §13.1). **Done** (2026-10-13): 8 frames in both sizes. **Reordered the same day after build 569:** the Aperçu reshot on the top of the salon page (« Nouveau », no « Connectez-vous » card) and moved to position 2; the booking form and the client card (screens 4 and 5) reshot on 569 too. Owner sign-off and upload in App Store Connect pending |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-10-13 |
| **PRD ref / phase** | Launch — store submission · V1 |
| **Skills checked** | myweli-dev-guardrails · myweli-verification-guardrails |
| **Governs** | `tool/app_store_screenshots/compose.py` · `screens.json` · `fonts/` · [app-store-forms.md](app-store-forms.md) §10 |

## 1. Goal & scope

Eight French screenshots of MyWeli Pro (iPhone only), taken on the
production demo salon « Maison Nala », framed with a short caption in the
brand's type, for the App Store listing. Build 565's code is what is shown:
`main` has had no `mobile/` commit since `75503243`, the commit 565 was built
from.

*(2026-10-13: the owner now wants an App Preview shown before these frames — proposed in [pro-app-preview.md](pro-app-preview.md), awaiting sign-off.)*
Out of scope: an App Preview video, an iPad set, other locales (the app is
French only and sold in Côte d'Ivoire only).

## 2. What Apple requires (checked 2026-10-12)

Apple's spec page
(developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
now reads: « To submit your app, you must provide screenshots for the
following required display sizes: iPhone: At least one screenshot for iPhone
with Dynamic Island (medium display). » That slot takes **1206 × 2622** or
1179 × 2556, portrait. **A 6.9" set (1320 × 2868) no longer fills it.** The
wording appeared between 2026-09-22 and 2026-10-06 (Wayback snapshots, per
the research pass); §10 of app-store-forms.md predates it.

- 1–10 images per size, PNG or JPEG, **no alpha channel or transparency**.
- Captions and overlays are allowed (Guideline 2.3.3: « may also include text
  and image overlays »), as long as the screens show the app in use; never
  the splash or the sign-in screen.
- Status bar: full Wi-Fi, full signal, full battery (Apple's marketing
  guidelines). 9:41 is a convention.
- Only the first three images show in search results, so the strongest go
  first.

We upload **both** sizes: 1206 × 2622 (required) and 1320 × 2868 (the
large-display slot). Both come from one capture run, because the frame scales
the capture into a card.

## 3. The set, in upload order

| # | Screen | Path from launch (signed in) | State to capture |
|---|---|---|---|
| 1 | Agenda « Ma journée » | Accueil → « Rendez-vous » | « Aujourd'hui », « Tous », top of the list: a « Terminé », an « Arrivé », « Libre » gaps, « Confirmé » bookings |
| 2 | Aperçu de ma page | Accueil → « Configurer mon profil » → « Aperçu de ma page » | the top of the page: cover photo, logo, name, « Abidjan », **« Nouveau »** (build 569, #573), then « Services » and the start of « Contact »; « Réserver (après la mise en ligne) » at the bottom. No phone in frame, so no mask. Never « Mettre mon profil en ligne » (the button on the screen before) |
| 3 | Accueil | the start screen | top, non-zero « Aujourd'hui » stats; the push sheet dismissed with « Plus tard » |
| 4 | Réservation | Accueil → « Rendez-vous » → « Nouveau » | « Coupe femme » and « Soin Capillaire » ticked, 15/10/2026 at 10:00, « Client sans numéro » ticked, name « Aya T. »; no picker or keyboard open; never « Créer le rendez-vous » (below the fold, untouched). Reshot on 569: no « (walk-in) », no SMS line |
| 5 | Fiche client | Accueil → « Clients » → Awa K. | tags, visits, « Dépensé », next booking, history. Reshot on 569: the number grouped (masked after « +225 07 »), four equal tiles, « 13 oct. 2026 » |
| 6 | Services | Accueil → « Configuration » → « Services » | top of the list |
| 7 | Disponibilité | Accueil → « Disponibilité » | scrolled to the hours and « Modèles »; **no taps** (every chip writes) |
| 8 | Revenus | Accueil → « Analyses » → « Revenus » | « Aujourd’hui » tab, after that day’s five bookings were marked « Terminé » (the screen counts completed bookings; « Semaine » showed the same five) |

**Avant / Après was dropped** (owner, 2026-10-12): the demo pairs looked weak
live. Until build 569 the Aperçu was framed on « Contact », because the header
showed « 0.0 · 0 avis » and a client-only « Connectez-vous… » card (§9). Build
569 fixed both (#573), so on 2026-10-13 it was reshot on the header — the
salon's best first impression — and moved to position 2, right after the
agenda. Never shown: « Mon
abonnement » or any offer, the KYC screen, « Compte de démonstration — … »
(appears only after a blocked action), a system alert, a ComingSoon screen.

## 4. Data on Maison Nala (owner-approved writes, 2026-10-12)

The weekly reset dates the demo bookings around the reset itself
(`demo_reset_service.dart`), so the agenda is empty from today on. The owner
approved filling it **in production, as the demo account, through the app**:
about six bookings on the capture day, one or two later that week, one past
visit marked « Terminé », tags on that client, and on the day itself 08:00
« Terminé » and 09:00 « Arrivé » (« Arrivé » works on the booking's day only).
The next reset (due 2026-10-18 10:37 UTC, run at the next 03:00 UTC tick)
wipes them.

**What a snapshot recapture would keep** (read in
`backend/lib/src/demo/demo_reset_service.dart`, `capture` and steps 1–3 of the
reset): the snapshot holds the **salon document only** (name, services,
prices, address, description, photos…). The agenda and the client book are
wiped and regenerated relative to « now » at every reset, whatever the
snapshot says. So recapturing after the shoot keeps the tidied content (§6a)
and freezes none of the bookings, tags or statuses; it also restarts the
7-day clock. The recapture is the owner's call (`POST /admin/demo/snapshot`,
production).

**Privacy.** The demo clients' numbers (`+225 07 00 00 01 01`–`04`) look
like real Orange CI numbers. The owner chose to **mask the digits** on any
screen that shows one: `screens.json` `masks` paints a neutral `divider` bar
over them, in raw-capture pixels. Follow-up: move the demo seed to numbers
that cannot belong to anyone.

## 5. The frame

Light, no drawn device, one layout for all eight, measured at 1320 wide and
scaled for 1206:

| Element | Spec |
|---|---|
| Background | `surface` #FAFAFA |
| Mark | `myweli_mark_black.svg`, 64 px tall, top 72 (brand book p.17 clear space) |
| Headline | Poppins Medium 88 px (may shrink to 76), line height 1.15, `textPrimary`, centred, column 1128, top 176, two hand-set lines |
| Subline | Inter Regular (opsz 14) 44 px, line height 60, `textSecondary`, column 1000, top 436, hand-set lines (never a line ending on « à ») |
| Card | the capture at 960 wide, top 656, radius 118, 3 px `border` outline, `elevation4` × 3 shadow |

Colours are read by name from `mobile/lib/core/theme/colors.dart`, so a token
change reaches the frames. Type per the brand book p.21 (Poppins for
headings, Inter for body); both fonts are SIL OFL 1.1, committed with their
licences in `tool/app_store_screenshots/fonts/`.

## 6. Captions

Every claim was checked against the code by the research pass; « SMS »,
« walk-in », prices, subscriptions and the website are deliberately absent.

| # | Headline | Subline |
|---|---|---|
| 1 | Votre journée, / heure par heure. | Acceptez, reprogrammez ou marquez / l’arrivée d’un geste. |
| 2 | Votre page MyWeli, / prête pour vos clients. | Prestations, horaires, plan d’accès : / ils réservent dès la mise en ligne. |
| 3 | L’essentiel du salon, / dès l’ouverture. | Rendez-vous du jour, demandes / en attente et revenus. |
| 4 | Ajoutez un rendez-vous / en quelques gestes. | Pris au téléphone ou au comptoir, / même pour un client sans numéro. |
| 5 | Vos clients, connus / visite après visite. | Historique, notes et étiquettes, / à chaque réservation. |
| 6 | Vos prestations, / vos prix en FCFA. | Chaque prestation, son prix / et sa durée, en un coup d’œil. (The list shows the minimum price only — a range would not be visible, §9.) |
| 7 | Fixez vos horaires, / les créneaux suivent. | Pauses, jours bloqués et modèles / d’horaires prêts à l’emploi. |
| 8 | Suivez vos revenus, / jour après jour. | Chaque rendez-vous terminé est compté, / par jour, semaine ou mois. |

### 6.1 What the set does not show, and why (owner review, 2026-10-13)

The eight frames tell the day-to-day story (agenda, home, booking, clients,
services, hours, public page, revenue). Three things are not shown, each for a
reason that is checked, not assumed:
- **Online bookings from clients** (the « En attente » requests): the demo
  salon cannot be published, so it never receives one; « En attente » is
  always 0. Screen 2's caption (the Aperçu) carries the promise instead, worded to match
  the « Réserver (après la mise en ligne) » button in the frame.
- **Deposits (« Acompte & annulation »)**: on the demo the screen shows « Les
  acomptes sont disponibles après la vérification de votre compte » and the
  switch locked — KYC, which the demo cannot pass.
- **Team, reviews, notifications**: empty on the demo (no employees,
  invitations blocked, 0 reviews). The store description carries them.

Owner decisions (screen numbers as they were before the 2026-10-13 reorder):
screen 4 — now 5 — kept as is on 565 (the « dimanch / e » break, §9), **then
reshot on 569 with the booking form the same day, once the fixes were in a
build** (owner, 2026-10-13); screen 7's caption — now 2 — changed to the
online-booking promise; screen 8 added.

**Photos.** The owner says the salon photos were found online. None of the
frames showed them until the 2026-10-13 reorder. **Screen 2 now shows the
cover photo**: on 2026-10-13 the owner stated the photos are free-licence and
approved reshooting the Aperçu on the header. That licence is the owner's
statement — not checked from here; keep the source of each image with the
salon's files, so it can be shown if ever asked.

## 6a. The shoot, 2026-10-12 (owner-approved production writes)

Content tidied in the app as the demo account (it survives the next reset
only if the owner recaptures the snapshot, §4): « Coupe femme », « Coupe
homme », « Brushing » capitalised; Tresses priced 15 000–25 000 FCFA (the
Pro list shows only the minimum, hence screen 5's subline); address « Zone 4,
Marcory », commune Marcory, description « …de Marcory… sur rendez-vous ».

Agenda: Tue 13 Oct 08:00 Awa K. (Brushing), 09:00 Mariam T. (Coupe femme),
10:30 Fatou B. (Tresses), 13:00 Aïcha D. (Brushing + Soin), 15:30 Koffi A.
(walk-in, Coupe homme); Thu 15 14:30 Awa K. (Coupe femme + Soin), Fri 16
16:30 Fatou B. (Brushing). Awa K.'s 4 Oct visit marked « Terminé »; tags
VIP + Fidèle. SMS off on every booking (the backend ignores it anyway).

Captured: 3 (a walk-in « Aya T. » on Thu 15 10:00, form never submitted),
5, 6, 7. **On 13 Oct** (« Arrivé » works on the booking's day only): mark
08:00 « Terminé » and 09:00 « Arrivé », then capture 1 (agenda), 2
(Accueil) and 4 (Awa K.'s card; mask her number, measured on the raw).
**On the evening of 13 Oct**: mark the rest of that day's bookings « Terminé »
(after their time — never a future one), then capture 8 (« Revenus »,
« Semaine »).

The salon phone on screen 7 (`+225 07 00 00 01 00`) is masked after
« +225 07 », like the clients'. *(That was the « Contact » framing; the header frame that replaced it on
2026-10-13 — now screen 2 — shows no phone.)*

## 7. Procedure

1. Simulator **iPhone 17 Pro** (402 × 874 pt at 3× = 1206 × 2622), language
   `fr-CI`/`fr`, region `fr_CI`.
2. Debug Pro build against production, with the app's CARTO key read from
   Secret Manager into the command and never printed (otherwise screen 8
   shows « API KEY REQUIRED »).
3. The **owner** signs in as `revue@myweli.test`; the assistant never types
   the code.
4. `xcrun simctl status_bar <sim> override --time 9:41 --dataNetwork wifi
   --wifiMode active --wifiBars 3 --cellularMode active --cellularBars 4
   --batteryState discharging --batteryLevel 100`; « charged » draws a bolt.
5. Per screen: wait for spinners and images, then `xcrun simctl io <sim>
   screenshot build/app-store/pro/raw/pro-0N-<name>.png`. Look at it: no
   spinner, snackbar, keyboard, open sheet, « Démo », stray English.
6. `python3 tool/app_store_screenshots/compose.py --raw
   build/app-store/pro/raw --out build/app-store/pro` writes
   `1206x2622/` and `1320x2868/` plus `overview.png`. Each file is re-opened
   and must be the exact size, RGB, with no transparency, or the run stops.
7. The owner signs off on `overview.png`, then uploads in App Store Connect,
   in file-name order.

## 8. Definition of done

- [x] Eight captures, each inspected (two captures 1.5–2 s apart compared
      pixel-identical before keeping each one, so nothing was mid-scroll).
- [x] Both sizes composed; the script's checks pass; the mask covers the
      client number (screen 5; the reshot Aperçu shows no number).
- [x] Reordered after build 569 (2026-10-13): the Aperçu reshot on the header,
      captured twice 2 s apart and compared identical, moved to position 2;
      the other raw captures renamed to the new ids, captions unchanged; the
      565 set archived locally in `build/app-store/pro-565-set/`.
- [x] Screens 4 and 5 reshot on 569 (2026-10-13), each captured twice 2 s
      apart and compared identical. The booking form was filled and left by
      the back arrow — « Créer le rendez-vous » never touched, the agenda read
      unchanged afterwards. The client card's mask was re-measured on the new
      capture (glyph columns, raw pixels): `[466, 543, 246, 42]` covers the
      digits after « +225 07 ».
- [ ] Owner sign-off on the overview.
- [ ] Uploaded in App Store Connect; the required medium-display slot reads
      filled.
- [ ] app-store-forms.md §10 and §13 updated.

## 9. Open questions

- Whether App Store Connect shows the medium-display slot as required for
  this app: read it on the version page when uploading.

## 9. Defects seen during the shoot (build 565, follow-up task)

Owner decision: shoot on 565, fix after. **All fixed in build 569** (#573,
#574). Screen numbers below are the pre-reorder ones. Frames 4 and 5 (the
booking and the client card) were **reshot on 569** on 2026-10-13, so no frame
of the set shows any of these any more.
- The owner preview shows the client-only « Vos rendez-vous ici —
  Connectez-vous… » card (screen 7 avoids it by framing).
- The client card shows a raw `+2250700000101` (masked on screen 4).
- « Réessayer » breaks mid-word on a failed photo tile.
- Accueil stat cards come out at different heights (« Ce mois » wraps).
- The client card's « Dernière » tile breaks « dimanch / e » — **visible on
  screen 4**.
- Visible on screen 3 and accepted for 565: « (walk-in) » in English, and the
  SMS line « (bientôt disponible) ».
