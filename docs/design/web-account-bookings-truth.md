# Web — « Mes rendez-vous » follows the app's rule (A1w) — design spec

| | |
|---|---|
| **Status** | **Draft, waiting for the owner** (§11, four questions, each with a recommendation). No code before approval. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-23 |
| **PRD ref / phase** | FR-APPT-001, FR-APPT-003/005 · V1 · BACKLOG B0.10 (decision 160), B12.6 (C4), B12.7 (C7, part) |
| **Module** | `online-booking` (MODULES §2), web only |
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
| 2.2 | Each tab in the app's order | found while writing this spec: « À venir » lists the farthest booking first |
| 2.3 | The card's chip: « Non confirmé », neutral | decision 166 |
| 2.4 | « Passés » as in the app: summary, months, « Réserver à nouveau » under each | C7, decision 167 (§11 Q1) |
| 2.5 | An empty state for each tab | decision 169 (§11 Q3) |
| 2.6 | A heading, « Mes rendez-vous » | §11 Q4 |
| 2.7 | The detail: the chip's words, and when « Réserver à nouveau » shows | §11 Q2 |
| 2.8 | One table, pinned on both surfaces | — |

**Out of scope, and where each goes:**
- **The Espace pro: nothing changes.**
  - `statusLabelFr` and `StatusChip`'s kinds are shared with the agenda, the journal and the client card (`components/pro/*`).
  - A salon keeps « En attente » on a past booking nobody confirmed, because for the salon it is work still to do.
  - A test keeps the client helpers out of `components/pro` and `lib/pro` (§8).
- **The detail's layout and its chip's tone:** A2, which settles the appointment detail on both surfaces.
- **The rest of B12.7:** the returning client's home (C5), search (C6), consent (C8), deposit details (C9) and profile (C10).
- **The backend and the contract: nothing changes.**
  - The server sends every booking of the client, newest first, with no paging (`postgres_appointment_repository.dart:92`).
  - `totalPrice` is required (`openapi.yaml:5375`; `total_price … NOT NULL`, `migrations.dart:77`).
- **The app:** no code changes. One test reads the shared table (§2.8).

---

## 2. UX & flows

### Today

- **The tabs** come from `categorize(status)` (`web/lib/account/appointments.ts:120-127`), which looks at the status only:
  - `pending` and `confirmed` go to « À venir », whatever their date. A booking from last month the salon never answered still says « En attente » there (C4, B12.6).
  - `completed` goes to « Passés ».
  - `cancelled` and `noShow` go to « Annulés ». Since decision 165, the app puts a no-show in « Passés ».
- **The order** is the server's, newest first, in every tab. « À venir » therefore opens on the farthest booking; the app opens on the soonest (`appointment_provider.dart`, `upcomingAppointments`).
- **One empty state serves all three tabs** (`AccountClient.tsx:447-458`): « Aucun rendez-vous », « Vos réservations apparaîtront ici. », and a link « Découvrir des salons ».
- **« Passés » is a flat list**: no summary, no months, no « Réserver à nouveau » (C7). The app has all three (`my_bookings_screen.dart:195-290`).
- **No heading over the bookings.** The page reads h1 « Mon compte », then the tab group (« Filtrer mes rendez-vous »), then the list, then h2 « Favoris ».
- **The card's chip** is `StatusChip status={appt.status}` (`AppointmentCard.tsx:49`), with tones from `statusChipKind` (`StatusChip.tsx:15-27`).
- **The detail** (`AppointmentDetailClient.tsx`):
  - the chip is a plain neutral `Chip` with `statusLabelFr(status)` (`:236`), so a past booking nobody confirmed says « En attente »;
  - « Réserver à nouveau » shows for `completed`, `cancelled` and `noShow` only (`lib/account/extras.ts`, `canRebook(status)`; `:524`).
- **What already agrees with the app, and stays:**
  - « Annuler » is offered for `pending` and `confirmed` only (`canCancel`), so never on a no-show;
  - the cancel sentence is the app's word for word, pinned by the app's `cancellation_notice_parity_test.dart`;
  - « Reporter » and the calendar block show for upcoming bookings only (`isUpcoming`).

### 2.1 The rule: the app's table, on the web

| Booking | Tab | Chip | Chip tone (web kind) |
|---|---|---|---|
| `pending`, time after now | À venir | En attente | warning (`pending`), as today |
| `confirmed`, time after now | À venir | Confirmé | success (`ok`), as today |
| `pending`, time now or past | **Passés** | **Non confirmé** | **neutral** |
| `confirmed`, time now or past | **Passés** | Confirmé | success (`ok`) |
| `completed`, any time | Passés | Terminé | neutral, as today |
| `noShow`, any time | **Passés** | Absent | error (`danger`), as today |
| `cancelled` | Annulés | Annulé | error (`danger`), as today |

- **`clientTab(a, now = new Date())`** replaces `categorize(status)` in `lib/account/appointments.ts`.
  - It keeps today's `no_show` alias.
  - **Exactly at now counts as past**, as `isUpcoming` already says (`> Date.now()`) and as the app says.
- **A status this build does not know is placed by its date.** It goes to « À venir » if it is in the future and « Passés » otherwise, with its raw label as today.
  - This fails open: a booking is never hidden.
  - The app cannot meet the case, because its status is a closed enum.
- **`isUpcoming(a, now)` becomes `clientTab(a, now) === 'upcoming'`.** That gives one rule. It answers exactly as today for every status (`pending` or `confirmed`, and in the future), so « Reporter », the calendar block and the salon page's `SalonVisitsCard` do not change.
- **One `now` per render.** The three tabs, the chips and the summary read the same instant, so they cannot disagree.
  - A booking whose time passes while the page is open moves on the next load, as in the app.

### 2.2 The order of each tab

| Tab | Order |
|---|---|
| À venir | soonest first, as in the app |
| Passés | newest first, inside months that are newest first (§2.4) |
| Annulés | newest first, as today |

Two bookings at the same time keep the server's order.

### 2.3 The card's chip

- **The card reads the client rule:** `clientStatusLabel(a, now)` and `clientStatusKind(a, now)`. A past `pending` booking shows **« Non confirmé »** in the neutral kind; every other row of the table keeps its label and kind.
- **`StatusChip` gains an optional `kind`** that overrides the kind it derives from `status`.
  - The client's tone is a fact about the client's view, not a status of its own.
  - Every Espace pro caller passes nothing and is unchanged.
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
- **the amount** is the sum of their `totalPrice`, in the newest visit's currency (`currency`, else `providerCurrency`). This is the app's MVP rule: a mixed-currency history adds nominally, and a per-currency total comes after MP2;
- **the look:**
  - two tiles side by side, each `rounded-xl border border-border bg-secondary p-m`, as the account's other blocks;
  - the value in `text-titleLarge`, the label in `text-bodySmall text-textSecondary`;
  - the tiles wrap to one per row when they do not fit (`flex flex-wrap gap-m`), so a long total never breaks inside its number (`amounts-that-fit.md` §2's rule, read by the browser instead of measured);
- **the markup:** a `<dl>`, each tile a `<div>` holding `<dt>` (the label) and `<dd>` (the value), with the value shown first. A screen reader then reads « visites, 3 ».

**2. Months, newest first.** Each month has:
- **a heading:** `<h3>` with « novembre 2026 », shown upper-case (`text-labelMedium font-medium uppercase text-textTertiary`, the label style of `ManualBookingDialog.tsx:248`). A screen reader reads the words, not the capitals;
- **the month is taken in the salon's time zone** (`providerTimezone`, else `SALON_TZ`), the zone of the card's own date line. A booking at 23:30 UTC on 31 October at a salon in Libreville (UTC+1) is on 1 November, so it sits under « novembre », as its date says.

**3. Under each month, its bookings, newest first.** Each booking has:
- the card, unchanged apart from its chip (§2.3). It still links to the detail;
- below the card:
  - **the salon is live and has its page:** **« Réserver à nouveau »**, a secondary link-button, full width on a phone (`min-h-12`, ≥ 48 px). Its `href` is `rebookHref(a)`: the salon's booking page, with the services and the specialist prefilled (K2; the hub checks them against the live catalogue);
  - **the salon has stopped:** no button. The card already states why (`salonStoppedMessage`, `AppointmentCard.tsx:42-46`). The app shows the same sentence in place of its button, and the web would otherwise print it twice;
  - **a live salon with no slug** (a booking missing its enrichment): no button and no sentence, since `rebookHref` is null, as on the detail today.

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
- The tab group keeps its label « Filtrer mes rendez-vous ». « Favoris » stays an `<h2>`.

### 2.7 The detail

- **The chip's words follow the rule:** `clientStatusLabel(appt, now)`, so a past booking nobody confirmed reads « Non confirmé » here too.
  - The chip stays the plain neutral `Chip` it is today.
  - Its tone, and the detail's layout, are A2's question for both surfaces.
- **« Réserver à nouveau » shows when the booking is not upcoming** (`clientTab(a, now) !== 'upcoming'`: past, whatever its status, or cancelled) **and `rebookHref(a)` is not null**.
  - Today it shows for `completed`, `cancelled` and `noShow` only. A past « Non confirmé » or « Confirmé » booking gains it, as under the same booking in the list (§2.4).
  - `canRebook(status)` becomes `canRebook(a, now)`.
- **Unchanged:**
  - « Annuler » (`pending` or `confirmed`, at any time; past the time, the cancel sentence already says « l’heure du rendez-vous est passée »);
  - « Reporter » and the calendar block (`isUpcoming`);
  - the review form (`completed`).

### 2.8 One table, pinned on both surfaces

- **`docs/design/fixtures/client-booking-rule.json`** holds §2.1's seven rows and the boundary. Each row has the status, minutes from now, the tab, the label and the tone (in the spec's words: warning, success, neutral, error).
- **Both suites read it:**
  - a web unit test runs `clientTab`, `clientStatusLabel` and `clientStatusKind` over it;
  - the app's `client_booking_rule_test.dart` gains a test that runs `clientTab`, `clientStatusLabel` and `clientStatusTone` over the same file.
- **What turns red:**
  - a rule changed on one surface only turns that surface's test red;
  - a change to the table turns both red until both follow.
- That makes « the same on both surfaces » a test, where it was only a sentence in a spec.

### Edge cases

| Case | What the client sees |
|---|---|
| No booking at all | Each tab's own empty state |
| Past bookings, none « Terminé » | « Passés » with months and chips, no summary |
| A booking at exactly now | « Passés »: « Non confirmé » if pending, « Confirmé » if confirmed |
| A `completed` or `noShow` booking dated in the future (the server checks no time before either, `pro_appointment_service.dart:56-62, 112-118`) | « Passés », with its chip; the app does the same |
| A booking the salon typed (`salonEntered`) | The same rule. Its card still says « Réservé par votre salon » |
| A salon in another country | Months in the salon's zone; each amount in its booking's currency; the summary in the newest visit's |
| A stopped salon | No « Réserver à nouveau »; the card's sentence says why |
| A long salon name, or 200 % text | The card wraps as today; the chip and the button stay inside 320 px |
| An unknown status | Placed by its date, raw label; never hidden |
| The time passes while the page is open | Moves on the next load, as in the app |

---

## 3. API & contract

None. `GET /api/appointments` (the BFF over `GET /appointments`) already returns every field used: `status`, `appointmentDate`, `totalPrice`, `currency`, `providerCurrency`, `providerTimezone`, `providerSlug`, `providerStatus`, `serviceIds`, `artistId`.

## 4. Data model

None.

## 5. Architecture & patterns

- **`lib/account/appointments.ts`**, which stays pure and unit-tested:
  - `clientTab(a, now)`, `bookingsForTab(items, tab, now)` (filter and sort), `clientStatusLabel(a, now)`, `clientStatusKind(a, now)`;
  - `groupByMonth(items)`, in the salon's zone;
  - `visitSummary(items)`, which returns the count, the sum and the currency of the `completed` bookings, or null when there are none;
  - `isUpcoming` delegates to `clientTab`.
- **`lib/account/extras.ts`:** `canRebook(a, now)`.
- **`components/account/PastBookings.tsx`** (new) draws the summary, the months and « Réserver à nouveau ».
- **`components/account/AccountClient.tsx`** gets the heading, an empty state per tab, and hands « Passés » to `PastBookings`.
- **`components/account/AppointmentCard.tsx`:** the client chip.
- **`components/StatusChip.tsx`:** the optional `kind`.
- **`components/account/AppointmentDetailClient.tsx`:** the chip's words and `canRebook(a, now)`.
- **Tokens only.** No literal colour or size, and no arbitrary value (WEB-SYSTEM §1–§2). Every class named in §2 exists in the closed theme today.

## 6. Security & privacy

- **No change.** The page shows the signed-in client's own bookings through the same BFF route.
- **« Réserver à nouveau »'s link** is built from the booking's own slug and ids (`rebookHref`), and the booking hub checks them against the live catalogue (K2).
- **Nothing new is logged or stored.**

## 7. Performance

- **Same request, same payload.**
- A sort and a grouping over one client's bookings (tens) run on each render.
- No new dependency. The bundle of the signed-in `/mon-compte` grows by a component.
- `/mon-compte` is `noindex` and outside the Lighthouse budgets, which cover public pages only.

## 8. Testing plan

**Unit (Vitest), `web/tests/account-appointments.test.ts`:**
- the shared table (§2.8), plus the `no_show` alias and an unknown status;
- the boundary: exactly now is past;
- each tab's order;
- months in the salon's zone: the Libreville case of §2.4;
- the summary: `completed` only, the newest visit's currency, null at zero;
- `canRebook(a, now)` across the table;
- `isUpcoming` answers as before for every status, before and after now;
- `StatusChip`'s `kind` override;
- **a pin:** no file under `components/pro` or `lib/pro` imports `clientTab`, `clientStatusLabel`, `clientStatusKind` or `bookingsForTab`, with comments stripped.

**Component (RTL), `web/tests/account-bookings.test.tsx`** (new), with a frozen clock and `listAppointments` mocked:
- « À venir »: soonest first; only future `pending` and `confirmed` bookings;
- « Passés »:
  - the summary is shown with one « Terminé » and hidden with none;
  - the months are in order, each with its heading;
  - « Non confirmé », « Confirmé », « Absent » and « Terminé » chips;
  - « Réserver à nouveau » carries the prefill;
  - a stopped salon has no button;
- « Annulés »: cancelled only, newest first;
- the three empty states, with their words;
- the headings read h1 « Mon compte », h2 « Mes rendez-vous », h3 months, h2 « Favoris »: no skipped level.

**App:** `mobile/test/unit/client_booking_rule_test.dart` gains the shared-table test (§2.8).

**E2E (Playwright):**
- **the stub gains three past bookings for the consumer,** dated with the stub clock's tokens (`stub-clock.mjs`):
  - pending, yesterday;
  - `noShow`, last month;
  - `completed`, last month;
- **every spec that reads `/mon-compte`'s list is re-run against them.** `account.spec.ts` opens `Beauté Divine` with `.first()`, and a new booking must not take its place;
- **`account.spec.ts`:**
  - the three tabs hold what §2.1 says;
  - the summary shows on « Passés »;
  - « Réserver à nouveau » leads to the salon's booking page with the prefill;
- **`axe.spec.ts`:** `/mon-compte` on the « Passés » tab;
- **`type-overflow.spec.ts`:** « Passés » at 320 px and 200 % text;
- **`tap-targets.spec.ts`:** « Réserver à nouveau » is ≥ 48 px.

**Mutations, each to be watched red before the PR is called done:**
1. A no-show goes back to « Annulés ».
2. A past pending booking stays in « À venir ».
3. Exactly now counts as upcoming.
4. A past pending booking says « En attente » again.
5. « Non confirmé » takes the warning kind.
6. « À venir » lists newest first.
7. The summary counts every past booking.
8. The summary shows at zero.
9. Months are taken in UTC.
10. A stopped salon offers « Réserver à nouveau ».
11. The detail keeps `canRebook(status)`.
12. A `components/pro` file imports `clientStatusLabel`.
13. One row of the shared table changes: both suites go red.
14. The « Mes rendez-vous » heading is removed: the heading-order test goes red.

## 9. Rollout & scope discipline

- **After the owner approves:** the branch `feat/web-account-passes`, from `main`, as one PR. It touches:
  - `web/`;
  - the shared table;
  - one app test;
  - the docs: this spec's status, the pointer in `consumer-app-truth.md` §2.7, BACKLOG B12.6 (closed) and B12.7 (C7 closed), the marks for C4 and C7 in `web-flow-audit-2026-11.md`, and the web half of gap 15 in the audit's §6;
  - one roadmap entry.
- **Merging it is a production deploy of `myweli.com` (Vercel), on the owner's word.**
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
- [ ] Tokens only, no arbitrary value; `StatusChip` reused.
- [ ] axe clean on « Passés »; headings without a skipped level; « Réserver à nouveau » ≥ 48 px with a visible focus ring; nothing scrolls sideways at 320 px and 200 % text.
- [ ] The Espace pro unchanged, and the pin on its imports watched red.
- [ ] The 14 mutations of §8 watched red, listed in the PR.
- [ ] Merged and deployed only on the owner's word; read back on `myweli.com` as §9 says.

## 11. Open questions (each with a recommendation)

**Q1. « Passés » as in the app, now: summary, months and « Réserver à nouveau » under each booking (C7)?**
- C7 was left for later on 2026-11-05 (S3), « when touched ».
- A1w touches this exact tab, and without C7 the web's « Passés » keeps a flat list where the app has a history.
- *Recommended: yes, in A1w (§2.4).*

**Q2. On the detail, « Réserver à nouveau » for a past « Non confirmé » or « Confirmé » booking?**
- Today the detail offers it after « Terminé », « Annulé » and « Absent » only.
- With Q1, the same booking offers it in the list, so the two would disagree.
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
