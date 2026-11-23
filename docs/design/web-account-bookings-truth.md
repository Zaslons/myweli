# Web — « Mes rendez-vous » follows the app's rule (A1w) — design spec

| | |
|---|---|
| **Status** | **Approved by the owner on 2026-11-23** (« Approve as recommended »: the five recommendations of §11, BACKLOG decisions 182–186). An independent reader checked it once against the code on 2026-11-23. Each of its 15 findings was checked again in the code before it went in. **Built on 2026-11-23** in its own PR (A1w, #838, branch `feat/web-account-passes`); its merge is a production web deploy, on the owner's word. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-23 |
| **PRD ref / phase** | FR-APPT-001, FR-APPT-003/005 · V1 · BACKLOG B0.10 (decision 160), B12.6 (C4), B12.7 (C7, part) |
| **Module** | `online-booking` (MODULES §2), web, with one app fix if §11 Q5 says so |
| **ROADMAP entry** | [2026-11-23-web-account-bookings-truth-spec.md](../roadmap/entries/2026-11-23-web-account-bookings-truth-spec.md) |
| **Skills checked** | myweli-web-guardrails ✓ · myweli-dev-guardrails ✓ · myweli-verification-guardrails ✓ · no backend, contract or data change |
| **Read at** | `main` `ad065999`. Every « today » below was read in the code on 2026-11-23, with its file and line. |
| **Related** | [consumer-app-truth.md](consumer-app-truth.md) §2.7 (the rule; decisions 165–169), built in the app by #834 · [web-flow-audit-2026-11.md](web-flow-audit-2026-11.md) C4, C7 · [web-true-sentences.md](web-true-sentences.md) §3 · [WEB-SYSTEM.md](WEB-SYSTEM.md) §4, §10 · [SYSTEM.md](SYSTEM.md) §12, §13 |

---

## 1. Goal & scope

**Goal:** the website's « Mes rendez-vous » sorts, labels and sums up a
client's bookings exactly as the app has done since A1 (#834). It uses the
same table, the same words and the same flow: what a client reads on
`myweli.com/mon-compte` and in the app is the same fact.

**In scope: one web PR (A1w).**

| # | Change | Origin |
|---|---|---|
| 2.1 | One rule for the tabs, the app's table | C4, B12.6, decisions 165–166 |
| 2.2 | Each tab in the app's order, each a real list | found while writing this spec: « À venir » lists the farthest booking first |
| 2.3 | The card's chip: « Non confirmé », and a neutral pill drawn as the app draws it | decision 166 |
| 2.4 | « Passés » as in the app: summary, months, « Réserver à nouveau » under each | C7, decision 167 (§11 Q1) |
| 2.5 | An empty state for each tab | decision 169 (§11 Q3) |
| 2.6 | A heading, « Mes rendez-vous » | §11 Q4 |
| 2.7 | The detail: the chip's words, and when « Réserver à nouveau » shows | §11 Q2 |
| 2.8 | One table, pinned on both surfaces | — |

**Out of scope, and where each goes:**
- **The Espace pro: nothing changes.**
  - `statusLabelFr`, `StatusChip` and its kinds are shared with the agenda, the journal and the client card (`components/pro/*`). None of them changes.
  - A salon keeps « En attente » on a past booking nobody confirmed, because for the salon it is work still to do.
  - A test keeps the client helpers out of `components/pro`, `lib/pro` and `app/pro` (§8).
- **The detail's layout and its chip's tone:** A2, which settles the appointment detail on both surfaces.
- **The rest of B12.7:** the returning client's home (C5), search (C6), consent (C8), deposit details (C9) and profile (C10).
- **The backend and the contract: nothing changes here** (§3).
- **The app:** one test reads the shared table (§2.8). Its month grouping is §11 Q5.
- **Three defects this spec found, each outside the website:**
  - **The app groups « Passés » months in UTC.**
    - The key is the date's own year and month (`visit_history.dart:25`), and the date is parsed with no zone (`appointment.dart:328`).
    - The card beside it dates the same booking in the salon's zone (`appointment_card.dart:368-372`).
    - In Côte d'Ivoire (UTC+0) both agree. At a salon in Libreville (UTC+1), a booking at 00:30 on 1 November sits under « octobre ».
    - This is §11 Q5.
  - **The server never stores a booking's `currency`.**
    - Booking creation stamps it (`booking_service.dart:247`, « immutable — the Fresha rule »).
    - The Postgres insert has no column for it (`postgres_appointment_repository.dart:33-38`), and the `appointments` table has none in `migrations.dart`.
    - So production never sends it back, and every client reads `providerCurrency`, the salon's currency today.
    - It is a backend task of its own: [appointment-currency-stamp.md](appointment-currency-stamp.md), BACKLOG batch 14 (B14.1 stores it from migration `0047`).
  - **The detail offers « Envoyer l’acompte » beside a past « Non confirmé ».**
    - `canAttachDeposit` has no time check (`appointments.ts:103-110`).
    - The app does the same (`appointment_detail_screen.dart:250-261`).
    - That is A2's, on both surfaces.

---

## 2. UX & flows

### Today

- **The tabs** come from `categorize(status)` (`web/lib/account/appointments.ts:120-127`), which looks at the status only:
  - `pending` and `confirmed` go to « À venir », whatever their date. A booking from last month the salon never answered still says « En attente » there (C4, B12.6).
  - `completed` goes to « Passés ».
  - `cancelled` and `noShow` go to « Annulés ». Since decision 165, the app puts a no-show in « Passés ».
- **The order** is the server's, newest first, in every tab. « À venir » therefore opens on the farthest booking; the app opens on the soonest (`appointment_provider.dart`, `upcomingAppointments`).
- **The lists** are `<div>`s of cards (`AccountClient.tsx:446`), not `<ul>`s (WEB-SYSTEM §4: « Lists are `<ul>/<li>` »).
- **One empty state serves all three tabs** (`AccountClient.tsx:447-458`): « Aucun rendez-vous », « Vos réservations apparaîtront ici. », and a link « Découvrir des salons ».
- **« Passés » is a flat list**: no summary, no months, no « Réserver à nouveau » (C7). The app has all three (`my_bookings_screen.dart:195-290`).
- **No heading over the bookings.** The page reads h1 « Mon compte » (in the page shell, `app/mon-compte/page.tsx:13`), then the tab group (« Filtrer mes rendez-vous »), then the list, then h2 « Favoris » and h2 « Confidentialité » (`AccountClient.tsx:557`).
- **The card's chip** is `StatusChip status={appt.status}` (`AppointmentCard.tsx:49`), with kinds from `statusChipKind` (`StatusChip.tsx:15-27`):
  - « Terminé » is drawn in the `neutral` variant, `bg-surface` on the card's white;
  - `Chip.tsx:21-29` records that this pill has no visible shape (about 1.04:1);
  - the app draws its neutral chip as a `textSecondary` tint (`app_chip.dart:116-120`), which is the web's `ink` variant.
- **The detail** (`AppointmentDetailClient.tsx`):
  - the chip is a plain neutral `Chip` with `statusLabelFr(status)` (`:236`), so a past booking nobody confirmed says « En attente »;
  - « Réserver à nouveau » shows for `completed`, `cancelled` and `noShow` only (`lib/account/extras.ts`, `canRebook(status)`; `:524`);
  - it is about 36 px tall: `px-l py-s` with no `min-h-12` (`:527-529`), under the 48 px floor.
- **What already agrees with the app, and stays:**
  - « Annuler » is offered for `pending` and `confirmed` only (`canCancel`), so never on a no-show;
  - the cancel sentence is the app's word for word, pinned by the app's `cancellation_notice_parity_test.dart`;
  - « Reporter » and the calendar block show for upcoming bookings only (`isUpcoming`).

### 2.1 The rule: the app's table, on the web

| Booking | Tab | Chip | Chip tone |
|---|---|---|---|
| `pending`, time after now | À venir | En attente | warning, as today |
| `confirmed`, time after now | À venir | Confirmé | success, as today |
| `pending`, time now or past | **Passés** | **Non confirmé** | **neutral** |
| `confirmed`, time now or past | **Passés** | Confirmé | success |
| `completed`, any time | Passés | Terminé | neutral, as today |
| `noShow`, any time | **Passés** | Absent | error, as today |
| `cancelled` | Annulés | Annulé | error, as today |

- **`clientTab(a, now = new Date())`** replaces `categorize(status)` in `lib/account/appointments.ts`.
  - **It reads the status normalised as `StatusChip` does:** lower case, without `_`, `-` or spaces (`StatusChip.tsx:22`). `noShow`, `no_show`, `NO_SHOW` and `no-show` are then one status, which today's `categorize` does for two spellings only.
  - **Exactly at now counts as past**, as `isUpcoming` already says (`> Date.now()`) and as the app says.
- **A status this build does not know is placed by its date.** It goes to « À venir » if it is in the future and « Passés » otherwise, with its raw label as today.
  - This fails open: a booking is never hidden.
  - *Corrected 2026-11-23 (independent review):* the app does not « fail open » here. It reads an unknown status as `pending` (`appointment.dart:329-331`, `orElse`), so it would say « En attente » or « Non confirmé » where the web shows the raw word. Neither surface meets the case today: the API's enum and the server produce only the five statuses.
- **`isUpcoming(a, now)` keeps its status check and asks the rule only about the time.** It is true when the status is `pending` or `confirmed` and `clientTab(a, now) === 'upcoming'`.
  - It answers exactly as today, including for an unknown status, which is never upcoming. So « Reporter », the calendar block and the salon page's `SalonVisitsCard` do not change.
  - `SalonVisitsCard`'s `.filter(isUpcoming)` (`SalonVisitsCard.tsx:35`) becomes a lambda that passes `now`. A bare `filter` would hand the list index in as `now`.
- **One `now` per render.** The three tabs, the chips and the summary read the same instant, so they cannot disagree.
  - A booking whose time passes while the page is open moves on the next load, as in the app.
  - *As built (2026-11-23, after the independent review):* the list takes its instant **when the bookings load**, so a tab click never moves a booking. The detail takes one **per render**, as `isUpcoming` did before A1w. The cancel sentence reads that instant too, so a client who taps « Annuler » after the time is told it has passed, and the chip and « Reporter » beside it agree. Both are tested by moving the clock while the page stays open.

### 2.2 Each tab: its order, as a real list

| Tab | Order |
|---|---|
| À venir | soonest first, as in the app |
| Passés | newest first, inside months that are newest first (§2.4) |
| Annulés | newest first, as today |

- Two bookings at the same time keep the server's order.
- **Each tab is a `<ul>`, and each booking an `<li>`**, as WEB-SYSTEM §4 asks. In « Passés » the `<li>` holds the card and its button (§2.4).

### 2.3 The card's chip

- **The card reads the client rule:** `clientStatusLabel(a, now)` and `clientStatusTone(a, now)`. A past `pending` booking shows **« Non confirmé »**, neutral; every other row of the table keeps its label and tone.
- **A small `ClientStatusChip`** in `components/account/` draws it:
  - the `tinted` variant for warning, success and error, as `StatusChip` does;
  - **the `ink` variant for neutral**, which is the app's neutral. « Non confirmé » and « Terminé » therefore get a visible pill, where `StatusChip`'s neutral has none on the card's white.
- **`StatusChip` does not change**, and the Espace pro keeps it.
- **« Non confirmé » is not added to `STATUS_FR`.** That map is shared with the Espace pro; the label lives beside `clientTab`, as it does in the app (`client_booking_rule.dart`).
- **At 200 % text and 320 px:** « Non confirmé » is the longest chip. The card's right column must not push the row sideways. `type-overflow.spec.ts` checks this on « Passés » (§8).

### 2.4 « Passés »: the app's history

From top to bottom, on a phone and on a desktop alike. The page is one 672 px column (`max-w-2xl`), so no separate desktop layout is needed.

**1. The summary, only when at least one booking is « Terminé »** (decision 167):
- two figures, as the app's `VisitSummary`:
  - **« N »** over **« visite »** or **« visites »** (`pluralFr`);
  - the amount (`formatFcfa`) over **« dépensés »**;
- **only `completed` bookings count.** A past « Non confirmé » or « Confirmé » booking, or an absence, is listed below with its own chip and counted nowhere;
- **hidden when there are none**, rather than reading « 0 visite » above a list of past bookings;
- **the amount** is the sum of their `totalPrice`, in the newest visit's currency (`currency`, else `providerCurrency`), which is the app's MVP rule:
  - a mixed-currency history adds nominally; a per-currency total comes after MP2;
  - until B14.1 is deployed (migration `0047`), the server stores no `currency`, so in production this is `providerCurrency`; from then on, the newest visit's own stamp (§1);
- **the look:**
  - two `Card`s side by side (WEB-SYSTEM §10), wrapping to one per row when they do not fit (`flex flex-wrap gap-m`), so a long total never breaks inside its number (`amounts-that-fit.md` §2's rule, read by the browser instead of measured);
  - the value in `text-titleLarge`, the label in `text-bodySmall text-textSecondary`;
- **the markup:** a `<dl>`, each card holding `<dt>` (the label) and `<dd>` (the value), with the value shown first. A screen reader then reads « visites, 3 ».

**2. Months, newest first.** Each month has:
- **a heading:** `<h3>` with « novembre 2026 », shown upper-case (`text-labelMedium font-medium uppercase text-textTertiary`, the label style of `ManualBookingDialog.tsx:248`). A screen reader reads the words, not the capitals;
- **the month is taken in the salon's zone** (`providerTimezone`, else `SALON_TZ`), the zone of the card's own date line. A booking at 23:30 UTC on 31 October at a salon in Libreville (UTC+1) is on 1 November, so it sits under « novembre », as its date says. The app takes the month in UTC today (§1, §11 Q5);
- **its bookings, newest first, in a `<ul>`.**

**3. Each `<li>` holds the card, unchanged apart from its chip (§2.3), and below it:**
- **when the salon is live and has its page:** **« Réserver à nouveau »**.
  - It is a `ButtonLink`, secondary variant: it carries `min-h-12` (≥ 48 px) and the focus ring. It is full width on a phone.
  - Its `href` is `rebookHref(a)`: the salon's booking page, with the services and the specialist prefilled (K2; the hub checks them against the live catalogue).
  - **Its accessible name adds the salon:** a visually hidden « chez {salon} » (`sr-only`). A screen reader's list of links then reads « Réserver à nouveau chez Beauté Divine », not N identical links.
- **when the salon has stopped:** no button. The card already states why (`salonStoppedMessage`, `AppointmentCard.tsx:42-46`). The app shows the same sentence in place of its button, and the web would otherwise print it twice;
- **a live salon with no slug** (a booking missing its enrichment), or **a salon status this build does not know:** no button and no sentence. `rebookHref` is null, as on the detail today.

**Unchanged:** loading (`SkeletonRows`), the error state and its retry. The three tabs read one list, so they fail together, as in the app.

### 2.5 An empty state for each tab

| Tab | Icon | Title | Text | Action |
|---|---|---|---|---|
| À venir | `event` | Aucun rendez-vous | Vos réservations apparaîtront ici. | « Découvrir des salons » (today) |
| Passés | `event` | **Aucun rendez-vous passé** | **Vos rendez-vous passés apparaîtront ici.** | « Découvrir des salons » |
| Annulés | `cancellation` | **Aucun rendez-vous annulé** | **Vos rendez-vous annulés apparaîtront ici.** | none |

- **The « Passés » words are decision 169's**, already in the app.
- **The « Annulés » words are new.** Today « Vos réservations apparaîtront ici. » under an empty « Annulés » reads as if a cancelled booking were the thing to look forward to.
- **« Annulés » gets no link:** an empty cancelled list leaves nothing to do.
- **The app's « À venir » and « Annulés » keep their own sentence** (« Vous n’avez pas de rendez-vous dans cette catégorie »). Bringing the app to the web's words would need a new app build and can wait for one (§11 Q3).
- **Icons:** the icon set has no « history » glyph, and adding one is out of scope. « Passés » keeps `event`; `cancellation` already exists.

### 2.6 A heading: « Mes rendez-vous »

- **An `<h2>` « Mes rendez-vous » above the tabs,** styled as « Favoris » (`text-titleLarge font-semibold text-textPrimary`). The app's screen carries the same title.
- **Why:**
  - the months' `<h3>`s need an `<h2>` above them; without it they would follow the `<h1>` directly, a skipped level (WEB-SYSTEM §4);
  - today the bookings are the one block of the account page with no title.
- **The page then reads:** h1 « Mon compte », h2 « Mes rendez-vous », h3 for each month (on « Passés »), h2 « Favoris », h2 « Confidentialité ».
- The tab group keeps its label « Filtrer mes rendez-vous ».

### 2.7 The detail

- **The chip's words follow the rule:** `clientStatusLabel(appt, now)`, so a past booking nobody confirmed reads « Non confirmé » here too.
  - The chip stays the plain neutral `Chip` it is today.
  - Its tone, and the detail's layout, are A2's question for both surfaces.
- **« Réserver à nouveau » shows when the booking is not upcoming** (`clientTab(a, now) !== 'upcoming'`: past, whatever its status, or cancelled) **and `rebookHref(a)` is not null**.
  - Today it shows for `completed`, `cancelled` and `noShow` only. A past « Non confirmé » or « Confirmé » booking gains it, as under the same booking in the list (§2.4).
  - `canRebook(status)` becomes `canRebook(a, now)`.
  - **This is a web choice, not parity:** the app's detail has neither a status chip nor « Réserver à nouveau ».
  - **It becomes a `ButtonLink`** (primary, as today's look), so it reaches 48 px.
- **Unchanged:**
  - « Annuler » (`pending` or `confirmed`, at any time). Past the time, a client who sent a deposit proof is told « l’heure du rendez-vous est passée »; with no deposit there is no sentence, as today;
  - « Reporter » and the calendar block (`isUpcoming`);
  - the review form (`completed`);
  - « Envoyer l’acompte » on a past « Non confirmé », which is A2's (§1).

### 2.8 One table, pinned on both surfaces

- **`docs/design/fixtures/client-booking-rule.json`** holds §2.1's seven rows and the boundary. Each row has the status, minutes from now, the tab, the label and the tone (in the spec's words: warning, success, neutral, error).
- **Both suites read it:**
  - a web unit test runs `clientTab`, `clientStatusLabel` and `clientStatusTone` over it;
  - the app's `client_booking_rule_test.dart` gains a test that runs `clientTab`, `clientStatusLabel` and `clientStatusTone` over the same file.
- **What turns red:**
  - a rule changed on one surface only turns that surface's test red;
  - a change to the table turns both red until both follow.
- That makes « the same on both surfaces » a test, where it was only a sentence in a spec.
- **Two old pointers follow the new name:** `client_booking_rule.dart:10` (« web `categorize(a, now)` ») and `consumer-app-truth.md` §2.7 both say `clientTab`.

### Edge cases

| Case | What the client sees |
|---|---|
| No booking at all | Each tab's own empty state |
| Past bookings, none « Terminé » | « Passés » with months and chips, no summary |
| A booking at exactly now | « Passés »: « Non confirmé » if pending, « Confirmé » if confirmed |
| A `completed` or `noShow` booking dated in the future (the server checks no time before either, `pro_appointment_service.dart:56-62, 112-118`) | « Passés », with its chip; the app does the same |
| `noShow` spelled `no_show`, `NO_SHOW` or `no-show` | « Passés », « Absent » |
| A booking the salon typed (`salonEntered`) | The same rule. Its card still says « Réservé par votre salon » |
| A salon in another country | Months in the salon's zone; each amount in its booking's currency, which is the salon's in practice (§1); the summary in the newest visit's |
| A stopped salon | No « Réserver à nouveau »; the card's sentence says why |
| A salon status this build does not know | No button and no sentence (`salonIsLive` false, `salonStoppedMessageFor` null), as on the detail today |
| A long salon name, or 200 % text | The card wraps as today; the chip and the button stay inside 320 px |
| An unknown booking status | Placed by its date, raw label; never hidden; never upcoming for « Reporter » |
| A date or a salon zone that does not parse | The page fails, as before A1w: the card's own date line already threw on it (`Intl`), and the month heading now throws the same way. The app falls back to Abidjan. The zone is derived by the server from the salon's city (T57), and the date is the server's ISO string, so neither has been seen. |
| The time passes while the page is open | Moves on the next load, as in the app |

---

## 3. API & contract

**None.** `GET /api/appointments` (the BFF over `GET /appointments`) returns every field used, with one gap:
- **sent:** `status`, `appointmentDate`, `totalPrice`, `providerCurrency`, `providerTimezone`, `providerSlug`, `providerStatus`, `serviceIds`, `artistId`;
- **the gap:** `currency` is declared but never stored (§1), so the summary falls back to `providerCurrency`, as every amount on the page already does.

`totalPrice` is required (`openapi.yaml:5375`; `total_price … NOT NULL`, `migrations.dart:77`). The server sends every booking of the client, newest first, with no paging (`postgres_appointment_repository.dart:92`).

## 4. Data model

None.

## 5. Architecture & patterns

- **`lib/account/appointments.ts`**, which stays pure and unit-tested:
  - `clientTab(a, now)`, `bookingsForTab(items, tab, now)` (filter and sort), `clientStatusLabel(a, now)`, `clientStatusTone(a, now)`;
  - `groupByMonth(items)`, in the salon's zone;
  - `visitSummary(items)`, which returns the count, the sum and the currency of the `completed` bookings, or null when there are none;
  - `isUpcoming(a, now)`: the status check, then the rule.
- **`lib/account/extras.ts`:** `canRebook(a, now)`.
- **`components/account/ClientStatusChip.tsx`** (new): `Chip` `tinted` or `ink`.
- **`components/account/PastBookings.tsx`** (new): the summary in two `Card`s, the months, and « Réserver à nouveau » as a `ButtonLink`.
- **`components/account/AccountClient.tsx`:** the heading, an empty state per tab, `<ul>` lists, and « Passés » handed to `PastBookings`.
- **`components/account/AppointmentCard.tsx`:** `ClientStatusChip`.
- **`components/account/AppointmentDetailClient.tsx`:** the chip's words; `canRebook(a, now)`; « Réserver à nouveau » as a `ButtonLink`.
- **`components/account/SalonVisitsCard.tsx`:** `isUpcoming` called with `now`.
- **`mobile/lib/core/utils/client_booking_rule.dart`:** the pointer comment (§2.8). With Q5, also `visit_history.dart`'s `groupVisitsByMonth`.
- **Tokens only.** No literal colour or size, and no arbitrary value (WEB-SYSTEM §1–§2). Every class named in §2 exists in the closed theme today. `Card`, `Chip`, `ButtonLink`, `EmptyState` and `Tabs` are reused; nothing is drawn by hand.

## 6. Security & privacy

- **No change.** The page shows the signed-in client's own bookings through the same BFF route.
- **« Réserver à nouveau »'s link** is built from the booking's own slug and ids (`rebookHref`), and the booking hub checks them against the live catalogue (K2).
- **Nothing new is logged or stored.**

## 7. Performance

- **Same request, same payload.**
- A sort and a grouping over one client's bookings (tens) run on each render.
- No new dependency. The bundle of the signed-in `/mon-compte` grows by two small components.
- `/mon-compte` is `noindex` and outside the Lighthouse budgets, which cover public pages only.

## 8. Testing plan

**Every test passes `now` explicitly.** `account-appointments.test.ts`'s `mk()` dates its bookings `2026-12-01T09:00Z` (`:14`). Left on a default `now`, a pending one would move to « Passés » on that day, and the suite would go red on a date.

**Unit (Vitest):**
- **rewritten:**
  - `account-appointments.test.ts:6-32`: `categorize` and `filterByTab` give way to `clientTab` and `bookingsForTab`; its `noShow` → « Annulés » becomes « Passés »;
  - `account-extras.test.ts:23-27`: `canRebook(status)` becomes `canRebook(a, now)`;
- **new:**
  - the shared table (§2.8), the four spellings of `noShow`, and an unknown status;
  - the boundary: exactly now is past;
  - each tab's order;
  - months in the salon's zone: the Libreville case of §2.4;
  - the summary: `completed` only, the newest visit's currency, null at zero;
  - `canRebook(a, now)` across the table;
  - `isUpcoming` answers as before for every status, before and after now, including an unknown status in the future;
  - `ClientStatusChip`: `ink` for neutral, `tinted` otherwise;
  - **a pin:** no file under `components/pro`, `lib/pro` or `app/pro` imports `clientTab`, `clientStatusLabel`, `clientStatusTone`, `bookingsForTab` or `ClientStatusChip`, with comments stripped.
    - *As built, wider (independent review):* the pin scans every file the Espace pro renders through, following its imports. That includes `components/StatusChip.tsx`, which the folders' scan could not see. Only the two files that define the helpers are exempt. It also forbids `canRebook`, `UNCONFIRMED_PAST_LABEL`, `AppointmentCard`, `PastBookings` and the words « Non confirmé ».

**Component (RTL), `web/tests/account-bookings.test.tsx`** (new), with a frozen clock and `listAppointments` mocked:
- « À venir »: soonest first; only future `pending` and `confirmed` bookings;
- « Passés »:
  - the summary is shown with one « Terminé » and hidden with none;
  - the months are in order, each with its h3, under the h2 « Mes rendez-vous »;
  - « Non confirmé », « Confirmé », « Absent » and « Terminé » chips;
  - « Réserver à nouveau » carries the prefill and its accessible name names the salon;
  - a stopped salon has no button;
- « Annulés »: cancelled only, newest first;
- the three lists are `<ul>`s;
- the three empty states, with their words.

**App:**
- `client_booking_rule_test.dart` gains the shared-table test (§2.8);
- with Q5, `visit_history_test.dart` gains the Libreville case.

**E2E (Playwright):**
- **the stub clock gains two tokens, `YESTERDAY` and `LAST_MONTH`.**
  - They go in `stub-clock.mjs`'s `materialiseDates`, with a case each in `stub-clock.test.ts`.
  - Today it has only `TODAY` and `TOMORROW` (`stub-clock.mjs:39,43`).
- **`consumerAppt` takes a date per booking.** Today every consumer booking is `tomorrowAt9` (`stub-api.mjs:367`), and the detail route reuses that factory (`:2340`).
- **Three past bookings are added for the consumer:**
  - pending, yesterday;
  - `noShow`, last month;
  - `completed`, last month;
- **every spec that reads `/mon-compte` is re-run against them.** `account.spec.ts:26` opens `Beauté Divine` with `.first()`, and a new booking must not take its place;
- **month headings are never asserted by their text in e2e.** Near the start of a month, « yesterday » and « last month » can share a month, so only their count and order are read, never their words;
- **`account.spec.ts`:**
  - the three tabs hold what §2.1 says;
  - the summary shows on « Passés »;
  - « Réserver à nouveau » leads to the salon's booking page with the prefill;
  - the heading order of §2.6 on the whole page. The h1 is in the page shell, so only a page-level test sees it;
- **`axe.spec.ts`:** `/mon-compte` on the « Passés » tab;
- **`type-overflow.spec.ts`:** « Passés » at 320 px and 200 % text;
- **`tap-targets.spec.ts`:** both « Réserver à nouveau », in the list and on the detail, are ≥ 48 px.

**Mutations, each to be watched red before the PR is called done:**
1. A no-show goes back to « Annulés ».
2. A past pending booking stays in « À venir ».
3. Exactly now counts as upcoming.
4. A past pending booking says « En attente » again.
5. « Non confirmé » takes the warning tone.
6. « À venir » lists newest first.
7. The summary counts every past booking.
8. The summary shows at zero.
9. Months are taken in UTC.
10. A stopped salon offers « Réserver à nouveau ».
11. The detail keeps `canRebook(status)`.
12. A `components/pro` file imports `clientStatusLabel`.
13. One row of the shared table changes: both suites go red.
14. The « Mes rendez-vous » heading is removed: the heading-order test goes red.
15. `ClientStatusChip` draws neutral as `neutral` instead of `ink`.
16. `isUpcoming` loses its status check: an unknown status in the future gets « Reporter ».
17. `NO_SHOW` is not normalised.
18. The detail's « Réserver à nouveau » goes back to a 36 px link.

## 9. Rollout & scope discipline

- **After the owner approves:** the branch `feat/web-account-passes`, from `main`, as one PR. It touches:
  - `web/`;
  - the shared table;
  - one app test and one app comment (and, with Q5, `groupVisitsByMonth`);
  - the docs: this spec's status, the pointer in `consumer-app-truth.md` §2.7, BACKLOG B12.6 (closed) and B12.7 (C7 closed), the marks for C4 and C7 in `web-flow-audit-2026-11.md`, and the web half of gap 15 in the audit's §6;
  - one roadmap entry.
- **Merging it is a production deploy of `myweli.com` (Vercel), on the owner's word.** The app part, if any, reaches clients only with the next consumer build.
- **Read-back after the deploy:**
  - the JavaScript served for `/mon-compte` contains « Aucun rendez-vous passé » and « Non confirmé »;
  - the production monitor's last run (`production-checks.yml`).
- **The page itself needs a signed-in account with past bookings.** The owner may look with their own. Otherwise it is verified on the e2e stub and **UNVERIFIED** on production.
- **Rollback:** Vercel's instant rollback to the previous deployment.
- **What closes:**
  - B12.6 (C4);
  - C7 in B12.7;
  - the web half of audit gap 15;
  - decision 165's « the web moves them out of « Annulés » in A1w ».

## 10. Definition of done

- [ ] Every sentence in §2 shipped exactly as written, or as the owner changed it in §11.
- [ ] Typecheck, lint and `next build` clean; Vitest and the e2e green; the app's suite green with the shared-table test.
- [ ] All four states on each tab; French words; FCFA and dates through `lib/format`.
- [ ] Tokens only, no arbitrary value; `Card`, `Chip`, `ButtonLink`, `EmptyState` and `Tabs` reused.
- [ ] axe clean on « Passés »; the heading order of §2.6; lists are `<ul>`s; both « Réserver à nouveau » ≥ 48 px with a visible focus ring; nothing scrolls sideways at 320 px and 200 % text.
- [ ] The Espace pro unchanged, and the pin on its imports watched red.
- [ ] The 18 mutations of §8 watched red, listed in the PR.
- [ ] Merged and deployed only on the owner's word; read back on `myweli.com` as §9 says.

## 11. Open questions (each with a recommendation)

**All five answered on 2026-11-23: « Approve as recommended »** (BACKLOG decisions 182–186, in the order Q1–Q5). Each answer is the recommendation written under its question.

**Q1. « Passés » as in the app, now: summary, months and « Réserver à nouveau » under each booking (C7)?**
- C7 was left for later on 2026-11-05 (S3), « when touched ».
- A1w touches this exact tab, and without C7 the web's « Passés » keeps a flat list where the app has a history.
- *Recommended: yes, in A1w (§2.4).*

**Q2. On the detail, « Réserver à nouveau » for a past « Non confirmé » or « Confirmé » booking?**
- Today the detail offers it after « Terminé », « Annulé » and « Absent » only.
- With Q1, the same booking offers it in the list, so the two would disagree.
- This is a web choice: the app's detail has no « Réserver à nouveau ».
- *Recommended: yes. Any booking that is not upcoming, at a live salon (§2.7).*

**Q3. The empty states' words (§2.5)?**
- « Passés » takes decision 169's words.
- « Annulés » gets « Aucun rendez-vous annulé » / « Vos rendez-vous annulés apparaîtront ici. », with no link.
- « À venir » keeps today's words and link.
- The app's two generic sentences stay until a later app build.
- *Recommended: as written.*

**Q4. A visible heading « Mes rendez-vous » above the tabs (§2.6)?**
- The months need it for a correct heading order, and the app's screen carries the same title.
- *Recommended: yes.*

**Q5. Fix the app's months in A1w, so both surfaces group « Passés » in the salon's zone?**
- The app keys months on the UTC date (§1), while its card dates the same booking in the salon's zone. The two agree in Côte d'Ivoire and disagree at a salon one hour ahead.
- The fix is one function, `groupVisitsByMonth` keyed on `toSalonTime`, plus its test. It reaches clients with the next consumer build, and nothing is deployed for it.
- *Recommended: yes, in A1w.* The other choice is to leave the web on UTC to match today's app, which would copy a defect.
