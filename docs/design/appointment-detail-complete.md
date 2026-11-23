# The appointment detail, complete (A2) — design spec

| | |
|---|---|
| **Status** | **Approved by the owner on 2026-11-23** (« Approve as recommended »: the ten recommendations of §11, BACKLOG decisions 194–203). Built in three PRs (A2-api, A2, A2w), each merged on the owner's word: **A2-api merged (#841, `7157a9b3`) and deployed to production on 2026-11-23** (revision `myweli-api-00056-z88`); **A2, the app, built on 2026-11-23** (branch `feat/appointment-detail-app`). An independent reader checked it once against the code on 2026-11-23. Each of its 15 findings was checked again in the code before it went in. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-23 |
| **PRD ref / phase** | FR-APPT-002 (detail), FR-APPT-006 (directions), FR-REBOOK-001 / FR-BOOK-009 (rebook) · V1 · BACKLOG B0.10 (decision 160, Track A) |
| **Module** | `online-booking` (MODULES §2): backend, app and web |
| **ROADMAP entry** | [2026-11-23-appointment-detail-spec.md](../roadmap/entries/2026-11-23-appointment-detail-spec.md) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-web-guardrails ✓ · myweli-backend-guardrails ✓ · myweli-verification-guardrails ✓ |
| **Read at** | `main` `95072597`. Every « today » below was read in the code on 2026-11-23, with its file and line. |
| **Related** | [consumer-app-release-audit.md](consumer-app-release-audit.md) §7 A2, gap 9 · [consumer-app-truth.md](consumer-app-truth.md) (A1) · [web-account-bookings-truth.md](web-account-bookings-truth.md) (A1w: « the detail's layout and its chip's tone are A2's ») · [salon-state-and-refusals.md](salon-state-and-refusals.md) §5 (Decision C) · [web-swiss-salon.md](web-swiss-salon.md) §1 (the 3:2 cover) · [SYSTEM.md](SYSTEM.md) §1, §11–§13, §17 · [WEB-SYSTEM.md](WEB-SYSTEM.md) §4, §10 |

---

## 1. Goal & scope

**Goal:** the screen a client opens on the day of their appointment answers the
day's questions without a second screen:
- **where it stands:** the status, in words;
- **where:** the salon, its address and a way to get there;
- **what:** the services and who does them;
- **when:** the date and the time it starts and ends;
- **what is owed:** the total, the deposit and, while the booking is open, the balance;
- **what to do next:** move it, cancel it, book again, review it.

It answers them the same way in the app and on the website, and says only what MyWeli knows (A1's rule).

**In scope: three PRs.**

| # | Change | Surface |
|---|---|---|
| 2.1 | The booking carries the salon's position, commune, city and, for a live salon, its cover photo | backend + contract |
| 2.2 | One layout for the detail, section by section | app, web |
| 2.3 | The header: photo, name, status chip and a status sentence | app, web |
| 2.4 | « Le rendez-vous »: date, start and end, specialist, calendar | app, web |
| 2.5 | « Prestations »: one line per service | app, web |
| 2.6 | « Le salon »: address, « Itinéraire », « Appeler », « WhatsApp », « Voir le salon » | app, web |
| 2.7 | « Paiement »: total, the deposit's state, the balance while open | app, web |
| 2.8 | The actions: one primary per state, and « Réserver à nouveau » in the app | app, web |
| 2.9 | The app's booking card reads the booking's photo, place and position | app |

**Out of scope, and where each goes:**
- **The cancel flow and its sentences:** done in A1 and A1w. Their words do not change.
- **Prices per service:** the booking stores its total only. A price per line would be today's catalogue price, which may not be what was charged. It would need prices stamped at booking, a backend task of its own.
- **Receipts:** PRD FR-APPT-009 lists them as **[V1]** (`PRD.md:404`), and they are built on neither surface. They are not part of A2's definition in the audit (§7). §11 Q9 asks whether they get their own spec later.
- **Auto-sync of salon bookings** (FR-APPT-008): the audit's gap 19, which waits on phone verification.
- **The booking's currency:** stored by [#837](https://github.com/Zaslons/myweli/pull/837)'s spec. Every amount here keeps reading `currency ?? providerCurrency`, as today.
- **A map on the detail:** §11 Q5.
- **The salon page's own « Itinéraire » link**, a search pin (`MapEmbed.tsx`, `provider-summary.ts:12-14`), stays as it is.

**Found while writing this spec and in its review:**
- **A booking the salon entered cannot open its detail.**
  - `GET /appointments/{id}` answers 403 unless `appointment['userId'] == principal.userId` (`backend/routes/appointments/[id]/index.dart:23-25`). A booking the salon typed is stored with `userId: 'manual'` (`booking_service.dart:344`).
  - So when auto-sync lists such a booking for a client (`routes/appointments/index.dart:101-115`), the app's detail shows an error whose « Réessayer » cannot succeed, and the web says « Rendez-vous introuvable ».
  - **Nobody meets it in production today:** auto-sync matches only a verified phone, and production verifies none (gap 19).
  - **Not fixed in A2:** opening the detail to a phone-matched booking is an authorization change. It belongs with auto-sync's own fix, which must decide who may read a booking matched by phone. It is recorded here so that fix does not miss it.
- **The app guesses « Réservé par votre salon ».**
  - Its card shows it when `clientName != null` (`appointment_card.dart:250-254`), and its cancel sentence skips a salon booking the same way (`cancellation_policy.dart:44`).
  - The server sets `clientName` to null on a client's own booking (`booking_service.dart:260`). It stores whatever name the salon typed on a booking the salon entered (`:356`), and that name can be empty.
  - The web reads `userId === 'manual'` (`web/lib/bff.ts:150-152`), which the server sets on every salon booking (`booking_service.dart:344`).
  - A2 gives the app the web's rule, in one getter used by both call sites (§2.9).
- **The app's « Appeler » and « WhatsApp » are always drawn** (`appointment_detail_screen.dart:534-545`). With no number, the tap answers « Numéro indisponible. » or « WhatsApp indisponible. » (`:78-84`). The web draws each only when the number exists (`AppointmentDetailClient.tsx:307-329`). A2 gives the app the web's rule (§2.6).
- **« Acompte confirmé » can be untrue.**
  - The app says « Acompte confirmé — Le salon a confirmé la réception de votre acompte. » on every confirmed booking with a deposit (`appointment_detail_screen.dart:244-249`).
  - But a salon's « accept » moves a booking from pending to confirmed with no proof check (`pro_appointment_service.dart:40-46`). A salon can confirm a booking whose deposit nobody sent.
  - §2.7 says only what is known.
- **The web says nothing of a deposit once the salon confirmed** (`AppointmentDetailClient.tsx:371-395`). §2.7 gives both surfaces one table.
- **« Envoyer l'acompte » is offered on a past booking nobody confirmed, on both surfaces.**
  - The app: `appointment_detail_screen.dart:250-262` has no time check.
  - The web: `canAttachDeposit` has none either (`web/lib/account/appointments.ts:104-111`).
  - A1w left this to A2 (web-account-bookings-truth.md §1).
- **The web's « Payer avec Wave » link is under 48 px.** It is `py-xs` around a 20 px line, about 28 px tall (`web/components/booking/DepositProof.tsx:104`). It sits on the detail and on the booking confirmation. A2w raises it to `min-h-12`.
- **The app's `SectionHeading` carries no heading semantics** (`widgets/common/section_heading.dart`), while SYSTEM §13.4 asks a section title for `headingLevel: 2`. A2 adds an optional level, which the detail passes, so the other call sites do not change here (§2.2).

---

## 2. UX & flows

### Today

**The app** (`mobile/lib/screens/appointments/appointment_detail_screen.dart`):
- **The title:** « Détails » (`:355`).
- **One card, « Informations du rendez-vous »** (`:389-472`):
  - Date (`:398-407`) and Heure (`:409-418`), in the salon's time, with the « heure du salon » hint;
  - Spécialiste (`:426-432`) and Prix total (`:435-445`);
  - the deposit row and its state (`:446-449`, built at `:226-302`), and « Solde à régler au salon »;
  - Notes.
- **Not shown at all:**
  - the status;
  - the salon: no name, no photo, no address;
  - the services;
  - any directions.
- **Under the card:** the stopped-salon sentence (`:483-487`), then the buttons in this order:
  - « Reporter » (`:503`) and « Ajouter au calendrier » (`:511`), upcoming only;
  - « Annuler le rendez-vous », pending or confirmed;
  - « Donner mon avis » (`:528`), completed only;
  - « Appeler » and « WhatsApp » (`:535-545`), always.
- **No « Réserver à nouveau ».** The app offers it only in the « Passés » list (`my_bookings_screen.dart:259, 292`).

**The web** (`web/components/account/AppointmentDetailClient.tsx`):
- **The header:**
  - an h1 with the salon's name (`:242`);
  - a plain neutral chip with the client rule's words (`:248`). A1w left its tone to A2.
- **Next:**
  - the stopped-salon sentence;
  - « Voir le salon » (`:264-271`);
  - the two calendar buttons, upcoming only;
  - « Appeler » and « WhatsApp », each only when its number exists (`:307-329`).
- **A `<dl>` of rows** (`:331-358`): Date, Prestations (comma-joined), Spécialiste, Notes, Total, Acompte, Reste à payer. Then the « heure du salon » hint and « Réservé par votre salon. ».
- **The deposit:**
  - the `DepositProof` form when `canAttachDeposit`, which has no time check;
  - or, for a pending booking with a proof, « Justificatif d'acompte envoyé · en attente de confirmation du salon. » and « Voir ma capture ».
- **The actions:**
  - « Reporter », with its inline slot picker;
  - « Annuler le rendez-vous »;
  - « Réserver à nouveau », when not upcoming at a live salon (decision 183);
  - the review form, completed only.
- **Not shown:** the address, directions, a photo, the end time.

**What the booking carries** (`backend/lib/src/appointments/appointment_enrichment.dart:58-111`):
- the name, slug, status, phone, WhatsApp and address;
- the country, time zone and currency;
- the deposit's Mobile Money handle;
- the names of the services and of the specialist;
- the salon's booking window, and the duration.
- **It does not carry** the salon's position, commune, city or any photo. The salon's document holds all of them under those keys, in both repositories (`Provider.latitude`, `longitude`, `commune`, `city`, `imageUrls`). `imageUrls[0]` is the salon's cover (`provider_catalog_service.dart:540`).
- **Only the two consumer routes call this enrichment.** The Espace pro, notifications, the server's data export and the B0.24 purge do not.

### 2.1 The booking carries what the detail needs (backend + contract)

`withProviderFacts` adds five live salon facts, read on each request, as its other `provider`-prefixed keys are:

| Key | From the salon's document | Null when |
|---|---|---|
| `providerLatitude` | `latitude` | the salon has no position |
| `providerLongitude` | `longitude` | the salon has no position |
| `providerCommune` | `commune` | no commune |
| `providerCity` | `city` | no city |
| `providerPhotoUrl` | `imageUrls[0]`, the cover | no photo, **or the salon is not live** (`publicSalonStatus != 'active'`) |

- **The allowlist rule holds** (`appointment_enrichment.dart:28-33`: « Only fields that are public while the salon is `active` may ride here »).
  - All five are on the public page of an active salon today.
  - The gallery is resolved to **one** URL, never shipped whole, as the rule asks of the catalogue and the roster.
- **A stopped salon keeps its position, commune and city**, as Decision C kept its name, address and phone: a client with a booking there may still need to get there or reach it.
- **It does not keep its photo.**
  - A photo is decoration, not something a client needs to reach the salon.
  - A salon can be suspended for what it published, so showing a suspended salon's cover would keep serving it.
  - The clients then draw a stopped salon as one with no photo.
- **A position is a pair:** if either number is missing, both keys are null. A client never gets half a coordinate.
- **Every key is optional for the clients.** An app or website that meets an older server (no key) reads null and falls back as each block says. An old app ignores keys it does not know. So the three PRs can ship in any order.

### 2.2 One layout, section by section

The same order on both surfaces. The web keeps its one 672 px column (`max-w-2xl`), which needs no separate desktop layout.

1. **The header** (§2.3): photo, the salon's name, the status chip, one status sentence, and the stopped-salon sentence.
2. **« Le rendez-vous »** (§2.4).
3. **« Prestations »** (§2.5).
4. **« Le salon »** (§2.6).
5. **« Paiement »** (§2.7).
6. **« Notes »**, only when there are notes.
7. **The actions** (§2.8).

**How each surface draws a section:**
- **The app:**
  - each section is an `AppCard` titled with a `SectionHeading` in `titleMedium`;
  - `SectionHeading` gains an optional `headingLevel`, passed as 2 here, so a screen reader announces each section title as a heading (SYSTEM §13.4). Its other call sites do not change in A2;
  - its rows are `LabelValueRow`s, which wrap at 200 % text (SYSTEM §11.1);
  - the title bar reads **« Rendez-vous »** instead of « Détails » (§11 Q7).
- **The web:**
  - the page's h1 stays the salon's name, and each section is an h2 in a `<section>`;
  - label-and-value rows stay a `<dl>`;
  - the web's `Row` (`flex justify-between gap-m`, end of `AppointmentDetailClient.tsx`) does not wrap today: a long value wraps inside its own box. It gains `flex-wrap`, so a value that no longer fits beside its label drops under it, as the app's `LabelValueRow` does.
- **A section with no content is left out**, never shown with a « — ». The one drawn absence is the app's photo placeholder (§2.3), which every salon picture in the app already uses.

### 2.3 The header

- **The photo:**
  - **The shape:** the salon cover's own, **3:2**, the shape you chose for the salon page (web-swiss-salon.md §1; the web's `aspect-cover` token). It is cut at the cards' `object-subject` (50 % 20 %), so a head in an upright photo is not cut off.
  - **The app:**
    - the cover (`providerPhotoUrl`) at full card width, `AspectRatio(3 / 2)` as a named constant, clipped by `AppCard`'s `radiusXL`, through `TimedCachedImage`;
    - with no photo, the local `SalonPhotoPlaceholder` (A1) in the same frame. Every salon picture in the app falls back this way.
  - **The web:**
    - the cover at full card width, `aspect-cover object-cover object-subject`, through `next/image` (`cdn.myweli.com` is already allowed) with `sizes` for a 672 px column;
    - `priority` rather than lazy, since it is the page's largest element;
    - `https://` only, as the card's `photoOf` (`ProviderCard.tsx:22-28`);
    - with no photo, no image block: the name opens the card;
    - a photo that fails to load shows `surfaceVariant`, as the card's `FAILED_COVER`.
  - **On both:** the photo is decoration (empty `alt`, excluded from semantics), because the name beside it says the same.
- **The salon's name:** the app in `titleLarge`, with `headingLevel: 1`; the web keeps its h1 (`:242`). An unnamed salon reads « Salon » (`UNNAMED_SALON`), as today.
- **The status chip:** the client rule (decisions 165–166), in its tone.
  - **The app:** `AppChip.status` with `clientStatusLabel` and `clientStatusTone`, as the « Mes rendez-vous » card.
  - **The web:** `ClientStatusChip` (A1w), which replaces the plain neutral `Chip` (`:248`). This settles what A1w left open.
- **One status sentence under the chip, only where it says something the chip does not** (§11 Q3):

| Booking | Chip | Sentence |
|---|---|---|
| pending, ahead | En attente | **« Le salon doit encore confirmer ce rendez-vous. »** |
| confirmed, ahead | Confirmé | — |
| pending, now or past | Non confirmé | **« Le salon n'a pas confirmé ce rendez-vous avant son heure. »** |
| confirmed, now or past | Confirmé | — |
| completed | Terminé | — |
| noShow | Absent | **« Le salon a indiqué une absence à ce rendez-vous. »** |
| cancelled | Annulé | — |

  - The sentence is `bodyMedium` in `textSecondary`.
  - Its words live beside `clientStatusLabel` on each surface (`client_booking_rule.dart`, `web/lib/account/appointments.ts`), as `clientStatusSentence`.
  - They are added to the shared table (`docs/design/fixtures/client-booking-rule.json`, a `sentence` field per row, null where there is none), so both suites pin them.
  - « Annulé » has no sentence because MyWeli does not know who cancelled: a salon's refusal also stores `cancelled` (`pro_appointment_service.dart:48-53`), and nothing records the author.
- **Under it, the stopped-salon sentence:** unchanged words, now in the header on both surfaces.

### 2.4 « Le rendez-vous »

| Row | Value | Shown when |
|---|---|---|
| Date | **« mardi 1 décembre 2026 »**, in the salon's time | always |
| Heure | **« 09:00 – 10:30 »**, in the salon's time | always; with no `durationMinutes`, the start alone, « 09:00 » |
| Spécialiste | the specialist's name | `artistName` set |

- **The date's form is the app's** (`Formatters.formatDate`, `EEEE d MMMM yyyy`, `formatters.dart:127-129`). The web adds `formatDateLongFr` in `lib/format.ts`, with the weekday, through `salonFormatter`, and uses it on the detail only. `formatDateFr` does not change for its other callers (§11 Q7).
- **The end is the start plus `durationMinutes`**, in the salon's time. **No duration in words:** the two surfaces' duration formatters disagree today (the app's « 1h 30min », `formatters.dart:215-224`; the web's « 1 h 30 »), and the end time already says it.
- **The « heure du salon » hint** stays under the time, as today on both surfaces.
- **The calendar:**
  - the app's « Ajouter au calendrier » and the web's « Ajouter au calendrier (Google) » and « Fichier .ics » move into this section, upcoming only (`isUpcoming`);
  - their behaviour does not change.

### 2.5 « Prestations »

- **One line per service**, in the booking's order (`serviceNames`): an app `Column` of `Text`, a web `<ul>`. The web's comma-joined row goes.
- **No price per line** (§1, out of scope). The total is in « Paiement ».
- **Hidden when the booking names no service**, for example one whose services were all deleted (the server drops them, `appointment_enrichment.dart:87-91`).

### 2.6 « Le salon »

- **The address:**
  - `providerAddress` on its first line;
  - under it, **« commune, ville »**, only when a commune is known and the address does not already contain it, compared without case or accents (« Cocody, Abidjan »). The rule is a pure function on each surface (`placeLine`), unit-tested;
  - with no address, the « commune, ville » line alone;
  - with neither, no address lines.
- **The buttons**, in a row that wraps, each ≥ 48 px, secondary:

| Button | Shown when | Does |
|---|---|---|
| **« Itinéraire »** | the booking has a position | **App:** `Helpers.launchNavigation`, which offers the installed map apps (`helpers.dart:22-…`). **Web:** a new `directionsTo(lat, lng)` = `https://www.google.com/maps/dir/?api=1&destination=lat,lng`, the app's own Google URL, in a new tab: on a phone it opens the Maps app if installed; on a computer, Google Maps asks for a starting point |
| **« Appeler »** | `providerPhone` set | app `callPhone`; web `tel:` (today's) |
| **« WhatsApp »** | `providerWhatsapp` set | `https://wa.me/…` (today's) |
| **« Voir le salon »** | the salon is live (`salonIsLive`) and, on the web, has a slug | **App:** `/provider/:id`. **Web:** `/{slug}` (today's) |

- **« Itinéraire » needs a position** (§11 Q2). A search on the address text is not offered: an Ivorian street address often lands a map on the wrong place, and a wrong pin on the day is worse than none. With no position the address still shows, and the client can call.
- **A stopped salon keeps** its address, « Itinéraire », « Appeler » and « WhatsApp ». That is when a client with a booking needs to reach it most (Decision C). It loses « Voir le salon », whose page 404s, as today.
- **With no button and no address**, the section is left out.
- **No map** (§11 Q5).

### 2.7 « Paiement »

| Row | Value | Shown when |
|---|---|---|
| Total | `totalPrice` | always |
| the deposit (below) | the deposit's state | `depositAmount > 0` |
| Solde à régler au salon | `balanceDue` | `depositAmount > 0` **and the booking is pending or confirmed** |

- **The balance is shown only while the booking is open.** On a cancelled booking it would tell the client they owe money. On a completed or no-show booking MyWeli does not know what was paid at the salon.

**The deposit, one table for both surfaces** (§11 Q4). « Upcoming » is `isUpcoming(a, now)`; « proof » is `depositScreenshotUrl` set:

| Booking | Proof | Label | Sentence | Action |
|---|---|---|---|---|
| pending, upcoming | no | Acompte à envoyer | « Payez le salon directement, puis joignez une capture. » | **App:** « Envoyer l'acompte » (the sheet). **Web:** the `DepositProof` form, which carries its own heading, sentence and « Envoyer la preuve » button, so the row shows the amount alone |
| pending, upcoming | yes | Acompte — en attente de confirmation | « Le salon confirmera après vérification. » | « Voir ma capture » |
| pending, **now or past** | no | **Aucun justificatif envoyé** | — | **none** |
| pending, **now or past** | yes | **Acompte — non confirmé** | **« Voyez directement avec le salon : MyWeli ne détient aucun acompte. »** | « Voir ma capture » |
| confirmed | yes | **Acompte — justificatif envoyé** | — | « Voir ma capture » |
| confirmed | no | **Acompte** | — | — |
| cancelled | yes | Acompte | **« Voyez directement avec le salon : MyWeli ne détient aucun acompte. »** | « Voir ma capture » |
| cancelled, completed or noShow | no | Acompte | — | — |
| completed or noShow | yes | Acompte | — | « Voir ma capture » |

- **Only what is known.**
  - « Acompte confirmé » and « Le salon a confirmé la réception de votre acompte. » go: a salon confirms a booking, not a payment, and can confirm one with no proof (§1).
  - « Aucun justificatif envoyé » says what MyWeli knows — no proof was attached — not that no money moved. It takes the approved cancel sentence's own words (« Vous n'avez envoyé aucun justificatif d'acompte… »).
- **« Envoyer l'acompte » stops at the appointment's time.** After it, a deposit for a visit the salon never confirmed would be money sent for nothing.
  - On the web, `canAttachDeposit` gains the `isUpcoming` check.
  - The server does not refuse a proof on a past pending booking (it refuses one on a booking that is not pending). Hiding the button is a courtesy over a rule the server does not hold, recorded in §6.
- **« Voyez directement avec le salon : MyWeli ne détient aucun acompte. »** is a new sentence, built from the approved cancel sentences' last clause (« Voyez avec le salon pour le récupérer : MyWeli ne détient aucun acompte. », `cancellationNotice`). It promises no refund and does not say who cancelled.
- **A booking the salon entered has no online deposit** (`depositAmount: 0`, `booking_service.dart:352-353`), so it never shows this block.
- **One table, both suites:** the rows live in `docs/design/fixtures/deposit-state.json` and are read by a pure `depositState(appointment, now)` on each surface. That returns the label, sentence and action, so the screens draw what it returns.
- **The web's « Justificatif d'acompte envoyé · en attente de confirmation du salon. » goes.** Its row takes the table's words.
- **The web's « Payer avec Wave » link reaches 48 px** (`DepositProof.tsx:104`, §1).

### 2.8 The actions

The same rules on both surfaces, in this order, each ≥ 48 px, full width on the app. **One primary per state** (SYSTEM §1: colour for « the single primary action »); the others are secondary:

| Action | Shown when | Primary when |
|---|---|---|
| « Envoyer l'acompte » (app) / the proof form (web) | §2.7, first row | always, when shown: money first |
| « Reporter » | `canReschedule` (upcoming, live salon) | no deposit is waiting to be sent |
| « Annuler le rendez-vous » | `canCancel` (pending or confirmed, any time) | never |
| **« Réserver à nouveau »** | **`canRebook`: not upcoming, live salon with its page** (decision 183) | always, when shown |
| « Donner mon avis » (app) / the review form (web) | completed | never on the app (the web's form has its own button) |

- **The app gains « Réserver à nouveau »** (FR-REBOOK-001, §11 Q8).
  - It is the « Passés » button's route, moved to one helper both call: `/booking?providerId=…&serviceIds=…&artistId=…`, from `my_bookings_screen.dart:292-…`.
  - Its rule is the web's `canRebook`: `clientTab != upcoming && salonIsLive`. In the app, `salonIsLive` is false for a status this build does not know, as on the web.
  - So it shows after a cancelled booking, a past « Non confirmé » or « Confirmé », a completed visit and an absence, as on the web since decision 183.
- **Nothing else changes:**
  - « Annuler »'s confirm and its sentence;
  - the web's inline slot picker and the app's reschedule screen;
  - the review sheet and form.

### 2.9 The app's booking card (§11 Q6)

- **Today the card draws its photo, its « city » line and « Itinéraire » from the discovery list in memory** (`appointment_card.dart:39-48, 78-85, 138-235`). A booking at a salon on another page, in another commune or no longer listed shows the placeholder and no place.
- **A2 reads them off the booking first**, as A1 did for the name:
  - the photo: `providerPhotoUrl`;
  - the place line: `placeLine` (§2.6) from the booking;
  - « Itinéraire »: the booking's position.
- **When the booking's field is null, the discovery list is still read.**
  - That covers an older server.
  - On a new server it reads the same salon's same facts, so it cannot contradict the booking, only lag it.
  - The test gives the discovery list a **different** photo and position from the booking's, so a card that read the list first fails it.
- **« Voir sur la carte »** keeps opening `/carte?providerId=…`, shown when there is a position **and the salon is live**. The map finds a salon through the public read (`ProviderProvider.providerForMap`), which 404s a stopped salon. For a stopped salon it would answer « Ce salon n'a pas pu être affiché sur la carte. ».
- **« Réservé par votre salon »** reads `isSalonEntered` (`userId == 'manual'`), and so does the cancel sentence's skip (`cancellation_policy.dart:44`) (§1).

### Edge cases

| Case | What the client sees |
|---|---|
| A live salon with no photo | App: the placeholder in the 3:2 frame. Web: no image block |
| A stopped salon (it has a photo) | No photo (the server sends none): app placeholder, web no block |
| A photo that fails to load | App: `TimedCachedImage`'s error form. Web: `surfaceVariant` |
| No position | No « Itinéraire », no « Voir sur la carte »; the address shows |
| Latitude without longitude, or the reverse | Treated as no position (server, §2.1) |
| No address, no commune | No address lines; the buttons that apply |
| No phone, no WhatsApp | Neither button (the app no longer fails after the tap) |
| A stopped salon | The sentence in the header; address, « Itinéraire », « Appeler », « WhatsApp », calendar and « Annuler » kept; « Reporter », « Voir le salon », « Voir sur la carte » and « Réserver à nouveau » withheld |
| A salon status this build does not know | No « Voir le salon », no « Réserver à nouveau », no sentence (`salonIsLive` false), as today |
| A booking the salon entered | On the card, « Réservé par votre salon »; its detail cannot open today (§1, not A2's) |
| A cancelled booking with a deposit | No balance; the deposit row of §2.7 |
| No `durationMinutes` | The start time alone |
| No service names | « Prestations » left out |
| A long salon name, a long address, 200 % text, 320 px | Everything wraps; nothing scrolls sideways (§8) |
| An older server, without the new keys | Each block falls back as §2.1 and §2.9 say; nothing breaks |
| The time passes while the page is open | The web takes one instant per render (A1w), passed to every new helper; the app reads `AppClock.now()` on each build |

---

## 3. API & contract

**`GET /appointments` and `GET /appointments/{id}`** (the client's own bookings) gain five optional fields on `Appointment` in `docs/api/openapi.yaml`:

```yaml
providerLatitude:  { type: number, nullable: true }   # with providerLongitude, or both null
providerLongitude: { type: number, nullable: true }
providerCommune:   { type: string, nullable: true }
providerCity:      { type: string, nullable: true }
providerPhotoUrl:  { type: string, nullable: true }   # the cover, imageUrls[0]; null unless the salon is live
```

- No new endpoint, no new parameter, no status code.
- **Only the two consumer routes enrich**, as today; the Espace pro's reads are not touched.
- **The web's BFF passes the body through** (`app/api/appointments/[id]/route.ts`), so it needs no change.
- **The web's « Mes données » export** writes the raw booking list (`DataExportClient.tsx:75`), so it gains the five salon facts beside the salon's name and address already in it. None is personal data. The app's export is an allowlist and does not change.
- **The app's model** (`models/appointment.dart`) and **the web's type** (`lib/account/appointments.ts`) gain the same five fields, optional. The app's `fromJson` / `toJson` round-trip them.

## 4. Data model

**None.** All five are read from the salon's document at request time. Nothing is stored on the booking.

## 5. Architecture & patterns

- **Backend:**
  - `appointment_enrichment.dart`'s `_factsFor`: the five keys, the pair rule, `imageUrls[0]` only for a live salon, and the allowlist comment naming them;
  - `openapi.yaml`.
- **App:**
  - `models/appointment.dart`: the five fields and `isSalonEntered`;
  - `screens/appointments/appointment_detail_screen.dart`: the layout of §2.2 from `AppCard`, `SectionHeading` (with its new optional `headingLevel`), `LabelValueRow`, `AppChip.status`, `AppButton` and `InlineFeedback`;
  - a shared rebook route helper, used by the detail and by « Passés »;
  - `core/utils/client_booking_rule.dart`: `clientStatusSentence`;
  - `core/utils/deposit_state.dart`: `depositState(appointment, now)`;
  - `core/utils/place_line.dart`: `placeLine`;
  - `widgets/booking/appointment_card.dart` and `core/utils/cancellation_policy.dart`: §2.9.
- **Web:**
  - `components/account/AppointmentDetailClient.tsx`: the sections, `ClientStatusChip`, the photo, « Le salon », the deposit table;
  - `lib/account/appointments.ts`: `clientStatusSentence`, `depositState`, `canAttachDeposit` with `isUpcoming`, and `placeLine`;
  - `lib/format.ts`: `formatDateLongFr`;
  - `lib/provider-summary.ts`: `directionsTo`;
  - `components/booking/DepositProof.tsx`: the Wave link's `min-h-12`.
- **Shared fixtures, each read by both suites:**
  - `docs/design/fixtures/client-booking-rule.json` gains `sentence` per row;
  - `docs/design/fixtures/deposit-state.json` (new) holds §2.7's table.
- **Tokens only, no arbitrary value.**
  - The web's cover uses the existing `aspect-cover` and `object-subject`.
  - The app's 3:2 frame is one named constant, as SYSTEM §5 « What §5 does not govern » allows.

## 6. Security & privacy

- **No new endpoint, no new trust boundary.**
  - The five fields ride the client's own authenticated, owner-scoped read (`routes/appointments`).
  - Each is public on an active salon's page.
  - BACKEND.md §7 gains no row, because nothing new crosses a boundary. The enrichment's allowlist comment names the five keys and the photo's live-only rule.
- **A stopped salon's position reaches only its booking holders**, as its name, address and phone already do (Decision C). **Its photo reaches nobody** (§2.1).
- **The photo URL is the public R2 object**, the same one the salon's page serves. The web accepts `https://` only, as the card does.
- **The directions URL is built from two numbers**, never from text, so no free-text address reaches a map provider from the client.
- **A late deposit proof** (§2.7): the client hides the button, and the server does not refuse a proof on a past pending booking. That is noted, not changed here. A server rule would be its own backend task, with its own refusal code.
- **The salon booking that cannot open its detail** (§1) stays a 403. A2 does not widen who may read a booking.
- **Nothing new is logged.** The app's `toJson` is called by the mock service only, which caches to `SharedPreferences` in development builds.

## 7. Performance

- **One photo per detail:**
  - app: cached by `TimedCachedImage`;
  - web: `next/image` at the column's width, `priority`, on an authenticated, `noindex` page outside the Lighthouse budgets.
- **No map, so no tiles** (§11 Q5).
- **The server reads the same salon document it already reads:** no new query and no N+1.
- **The app's card stops needing the discovery list to be loaded** to draw a photo.

## 8. Testing plan

**Every test passes `now` explicitly**, or pins `AppClock` (app), as A1w set up.

**Backend:**
- `appointment_enrichment_test.dart`:
  - the five keys from a live salon with all four facts;
  - null when each is missing;
  - the pair rule, so a lone latitude gives two nulls;
  - `imageUrls` empty gives null, and only `[0]` is sent;
  - a suspended and a draft salon keep their position, commune and city, with a null photo;
  - an unknown salon (null document) gives five nulls.
- The route test reads the keys on `GET /appointments/{id}`.

**App** (`flutter test`, goldens on Linux):
- **unit:**
  - `depositState` over `deposit-state.json`;
  - `clientStatusSentence` over the shared table;
  - `placeLine` (the commune not repeated, accents and case ignored);
  - `isSalonEntered`, with both call sites;
  - the rebook helper's route.
- **widget, detail:**
  - every section shown and left out by its data;
  - the section titles announced as headings, level 2;
  - « Itinéraire » only with a position;
  - « Appeler » and « WhatsApp » only with numbers;
  - « Voir le salon » only when live;
  - « Réserver à nouveau » across the client table;
  - one primary button per state;
  - the balance only while open;
  - « Envoyer l'acompte » gone at the appointment's time;
  - the stopped-salon row of the edge cases;
  - 200 % text at 320 dp with no overflow.
- **widget, card:**
  - photo, place line and « Itinéraire » from the booking, with a discovery list that holds **other** values;
  - « Voir sur la carte » withheld for a stopped salon.
- **goldens** (the audit's gap 23, « no golden for the detail »), each at the floor and at 200 %:
  - an upcoming pending booking with a deposit to send;
  - a past « Non confirmé » with a proof;
  - a completed booking at a stopped salon.

**Web:**
- **unit:**
  - `depositState` and `clientStatusSentence` over the two shared files;
  - `placeLine` and `directionsTo`;
  - `formatDateLongFr`, against the app's form for the same instant;
  - `canAttachDeposit` with time.
- **component (RTL):** the same cells as the app's widget tests, and the h1 and h2 order.
- **e2e:**
  - the stub gains a live salon with a position and a photo (p1), a live salon with neither, and one consumer booking per row of §2.7;
  - the existing p3 (Gabon) is a draft salon and stays the stopped case beside p4;
  - `account.spec` reads the sections, « Itinéraire »'s URL and the deposit states;
  - `axe`, `tap-targets` and `type-overflow` (320 px, 200 %) on the detail. `tap-targets` measures every button of « Le salon », of the actions and of `DepositProof`, « Payer avec Wave » included.

**Mutations, each watched red before the PR is called done:**
1. A lone latitude reaches the client.
2. The whole gallery is sent.
3. A suspended salon's photo is sent.
4. « Itinéraire » shows with no position.
5. The app draws « Appeler » with no number.
6. « Envoyer l'acompte » shows on a past pending booking (each surface).
7. « Acompte confirmé » comes back on a confirmed booking with no proof.
8. The balance shows on a cancelled booking.
9. A status sentence changes on one surface (shared table).
10. A deposit row changes on one surface (shared table).
11. The app's detail loses « Réserver à nouveau » for a past « Confirmé ».
12. « Voir le salon » or « Voir sur la carte » shows for a stopped salon.
13. The card reads the discovery list before the booking's photo.
14. `isSalonEntered` goes back to `clientName != null`, at either call site.
15. The commune is repeated when the address contains it.
16. A section with no data is drawn empty.
17. Two primary buttons on one state.
18. A section title loses its heading level (app).
19. The web's chip goes back to the plain `Chip`.
20. « Payer avec Wave » back to `py-xs`.

## 9. Rollout & scope discipline

**Three PRs, each from `main`, each merged on the owner's word** (§11 Q10):

| PR | What | Reaches people when |
|---|---|---|
| **A2-api** | backend + contract (§2.1, §3) | the production backend deploy, on the owner's word |
| **A2** | the app (§2.2–§2.9) | the next consumer build |
| **A2w** | the web (§2.2–§2.8) | its merge, which is a production deploy of `myweli.com` (Vercel) |

- **Any order works** (§2.1). The tests of A2 and A2w run on mocks and the e2e stub, so they do not wait for A2-api.
- **A2-api first is still recommended**, so that the production read-back of A2w can see real fields the day it ships.
- **After each deploy, a read-back** with a control, as A1w did:
  - **backend:** a booking read on production carries the keys. That needs a signed-in client with a booking, which is the owner's; otherwise it is **UNVERIFIED** in production and verified on staging.
  - **web:** the served JS contains the new words, read escape-aware (A1w's lesson: the bundle writes « é » as `\xe9`).
- **Rollback:** the backend's previous revision; Vercel's instant rollback. The clients tolerate the keys' absence.
- **What closes:**
  - the audit's gap 9 (detail half; the name half closed in A1);
  - FR-APPT-002 and FR-APPT-006 on both surfaces;
  - FR-REBOOK-001 on the app's detail;
  - A1w's « detail layout and chip tone are A2's »;
  - « Envoyer l'acompte » on a past booking;
  - the untrue « Acompte confirmé ».
- **Docs in the same PRs:**
  - PRD FR-APPT-006's « ✅ built » becomes true (B1 in the audit);
  - SYSTEM §11.1 records `SectionHeading`'s `headingLevel`;
  - the roadmap entries.

## 10. Definition of done

- [ ] Every sentence of §2 shipped exactly as written, or as the owner changed it in §11.
- [ ] **Backend:** `dart analyze` 0; tests green; contract updated in the same PR.
- [ ] **App:** analyze 0; the full suite green; goldens made on Linux and each one looked at.
- [ ] **Web:** typecheck, lint and build clean; Vitest and e2e green.
- [ ] All four states on the detail (loading, error, not found, the booking). Every section is left out when it has nothing to show.
- [ ] Tokens only.
- [ ] Every control ≥ 48 px with a visible focus ring; one primary per state.
- [ ] Axe clean. Headings: h1 then h2 on the web; level 1 then 2 in the app.
- [ ] Nothing scrolls sideways at 320 px and 200 % text.
- [ ] The two shared tables are read by both suites, and watched red on each side.
- [ ] The mutations of §8 watched red, listed in each PR.
- [ ] Each merge and deploy on the owner's word, read back as §9 says.

## 11. Open questions (each with a recommendation)

**All ten answered on 2026-11-23: « Approve as recommended »** (BACKLOG decisions 194–203, in the order Q1–Q10). Each answer is the recommendation written under its question.

**Q1. Add the salon's position, commune and city, and its cover photo while it is live, to the client's own booking (backend + contract)?**
- Without them the detail cannot show directions or a photo for a salon the app has not loaded. A2 would fall back to the discovery list, the defect §2.9 fixes on the card.
- *Recommended: yes, the five keys of §2.1, with no photo for a stopped salon.*

**Q2. « Itinéraire » only when the salon has a position, never a search on the address text?**
- *Recommended: yes (§2.6).* A wrong pin on the day is worse than none, and the address and « Appeler » remain.

**Q3. The three status sentences (§2.3)?**
- « Le salon doit encore confirmer ce rendez-vous. »
- « Le salon n'a pas confirmé ce rendez-vous avant son heure. »
- « Le salon a indiqué une absence à ce rendez-vous. »
- The others have none.
- *Recommended: as written.* They state what the salon recorded, without blaming anyone.

**Q4. The deposit table (§2.7)?**
- It retires « Acompte confirmé » and its sentence, which can be untrue.
- It withholds « Envoyer l'acompte » from the appointment's time.
- It shows the balance only while the booking is open.
- The new words:
  - « Aucun justificatif envoyé »;
  - « Acompte — non confirmé »;
  - « Acompte — justificatif envoyé »;
  - « Voyez directement avec le salon : MyWeli ne détient aucun acompte. »
- *Recommended: as written.*

**Q5. A small map on the detail?**
- The app has `SalonLocationPreview` (160 dp) and the web `MapEmbed`, both on the salon page.
- *Recommended: no.* « Itinéraire » answers the day's question in one tap. A map adds tiles on a low-end phone, and the salon page, one tap away, has it.

**Q6. The app's booking card reads the same photo, place and position (§2.9), with « Voir sur la carte » only for a live salon?**
- *Recommended: yes, in A2's app PR.* Same fields, same defect as A1's name.

**Q7. The app's title « Rendez-vous » instead of « Détails », and the web's date with its weekday on the detail (« mardi 1 décembre 2026 »), as the app's?**
- *Recommended: yes.*

**Q8. « Réserver à nouveau » on the app's detail for every booking that is not upcoming, at a live salon: cancelled, past « Non confirmé » or « Confirmé », completed, absent?**
- This is the web's rule since decision 183, and FR-REBOOK-001 asks for rebook from history.
- *Recommended: yes, the same rule as the web.*

**Q9. Receipts (FR-APPT-009, [V1] in the PRD, built on neither surface): their own spec later, not in A2?**
- A receipt needs decisions A2 does not have: what it proves when MyWeli holds no money, and what a salon must have entered for it.
- *Recommended: yes, a spec of its own after Track A.*

**Q10. Three PRs (A2-api, A2, A2w), each merged on your word, A2-api first?**
- *Recommended: yes (§9).* The backend deploy is a production deploy and waits for your word, as always.
