# Pro revenue analytics — revenue by collaborateur, prestation and canal — design spec

| | |
|---|---|
| **Status** | **Approved 2026-11-25** — the owner answered all thirteen questions of §17 at once, « Approve as recommended » (decisions 237–249). **R0w live 2026-11-25** (#866, `afd2de97`). **R1's production read done 2026-11-25** (§19). **R1 live 2026-11-26** (#872, migration **0052**, merged 2026-11-25 `3f3305a5`, deployed 2026-11-26 11:09 UTC, revision `myweli-api-00061-kwl`); the count after waits for real bookings, on the owner's word. **R2 live 2026-11-26** (#884, merged `306a5d50`, deployed 19:40 UTC, revision `myweli-api-00062-f5c`; as built: §20). **R3 built 2026-11-27** (#893, branch `feat/pro-revenue-r3-app`; as built: §21); it reaches users with the next Pro store build. R4 next, on the owner's word. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-27 |
| **PRD ref / phase** | FR-PRO-EARN-001 [V1] (« completed revenue by day/week/month ») + FR-PRO-DASH-001 [V1] (« no-show rate ») + the revenue half of **FR-PRO-OPS-004 [V3]** (« revenue, top services/staff, no-show analytics »), pulled forward on the owner's request of 2026-11-25 — Q1 |
| **Module** | `analytics` (MODULES §10) on top of `finance` (§9); authz from `access` (§11) |
| **ROADMAP entry** | [2026-11-25-pro-revenue-analytics-spec.md](../roadmap/entries/2026-11-25-pro-revenue-analytics-spec.md) |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-backend-guardrails ✓ · myweli-web-guardrails ✓ · myweli-verification-guardrails (before any « done ») |
| **Reference** | YCLIENTS « Аналитика » (its revenue, average-check, by-staff, by-service and booking-source reports), adapted to Côte d'Ivoire: no custody, FCFA, phone-first |

**The request (owner, 2026-11-25):** « let's open another session where we
will build a feature so that in the analyses, for revenue, we can see per
worker, and per service and all of that ».

**The plan in ten lines.**
1. The « Revenus » screen (app) and page (website) become the salon's revenue
   analytics: one period, its comparison, five figures, a chart, and the
   revenue broken down **par collaborateur**, **par prestation** and **par
   canal**, each row opening its own detail.
2. « Réalisé » stays what « Total réalisé » means today: completed bookings,
   at the price shown at booking. Confirmed bookings are « Prévu », apart.
   Past confirmed bookings nobody closed are « À clôturer », apart, with a way
   to close them.
3. Money is grouped by currency and never summed across currencies.
4. The server owns every definition: the periods, the comparison, the
   buckets, the figures. The app and the website only draw.
5. Each new booking keeps its service lines (name and price), its
   collaborateur's name and its channel, so last year's figures keep last
   year's prices and names. Older bookings are **estimated at read time** and
   say so: no production row is rewritten.
6. Owner only (`finances.view`), as today.
7. Not possible yet, and why: par catégorie (services have no category) and
   à domicile (no booking records it). Q9.
8. Five PRs: a one-line website header, the backend columns, the backend
   endpoints, the app, the website.
9. No chart library: plain widgets and SVG, no APK growth.
10. Thirteen questions for the owner in §17, each with a recommendation.

---

## 1. Goal & scope

### 1.1 Why

A salon owner today sees one number per period: « Total réalisé » on
« Revenus », and « Revenus prévus » on the Accueil. They cannot answer the
questions an owner asks every month:

- Which collaborateur brought in the most, and how does that compare with
  last month?
- Which prestations make the money? Which sell often but cheaply?
- How much comes from MyWeli (the app, the website) and how much from
  bookings the salon enters itself? That is the question that decides whether
  the subscription pays for itself.
- What is my average ticket? How much do absences cost me?

YCLIENTS answers all of these in « Аналитика »; MyWeli is its replica for
Côte d'Ivoire (MODULES.md), and these are the reports a salon there will
compare us against.

### 1.2 In scope

- **Backend:** two read endpoints, owner-only — the figures
  (`GET /providers/{id}/analytics/revenue`) and the bookings behind them
  (`GET /providers/{id}/analytics/revenue/appointments`, paginated) — plus
  three nullable columns on `appointments` written for every new booking
  (§8). The OpenAPI contract, the threat model, the tests.
- **App (MyWeli Pro):** the « Revenus » screen rebuilt (§4), a detail screen
  per collaborateur / prestation / canal, the ledger screen, the Accueil money
  cards tappable into it. Interface + mock + API service, provider, goldens.
- **Website (espace pro):** `/pro/revenus` rebuilt at parity with the app,
  desktop-adapted (§5): URL-addressable periods and details, sortable tables,
  CSV export (Q10).
- **Definitions** written once (§3) and pinned by tests on both surfaces.

### 1.3 Out of scope (and where each goes)

| Not here | Why | Where it goes |
|---|---|---|
| Par **catégorie** | `Service` has no category field (`mobile/lib/models/service.dart:36-46`, `provider_catalog_service.dart:111-122`). | A catalogue spec that gives each service one of the Ivorian categories (consumer-search.md's five shared categories), then a fourth tab here. Q9 |
| **À domicile** vs en salon | No booking records where it happens; à domicile is V2 (PRD FR-DISC-009, §260). | The V2 home-service module; a fifth tab then. Q9 |
| **Remplissage** (fill rate), **clients nouveaux / fidèles**, heures et jours forts | Not revenue; fill rate needs capacity per collaborateur and hour. | `analytics` next slices (MODULES §10) — their own specs. |
| **Commissions**, payroll | FR-PRO-COMM-001 [V2], FR-PRO-PAYROLL-001 [V3]. | `payroll`. |
| A **final price** at checkout (the price actually paid, discounts, extras) | No booking has one; « Terminé » takes no amount (`pro_appointment_service.dart:56-61`). A ranged service (`priceMax`) is booked at its « à partir de » price. | Its own spec (a YCLIENTS-style « visite payée »). The footnote says it until then (§4.10). |
| **Acomptes** reçus | Screenshot-based, between the salon and its client (no custody). | Unchanged. |
| **Réseau** (several salons summed) | Each figure is per salon; `network` is V3. | `network`. |
| Changing `GET /dashboard` or `GET /earnings` | Builds 0.0.2 in both stores call them. | Unchanged; §16 notes what they do with currencies. |

### 1.4 Fit with the architecture

- Backend: `routes → services → repositories`, a pure Dart aggregator in the
  service (§9.1), two new repository reads with a contract on both twins
  (BACKEND.md §5, decision 223).
- App: `models → services (interface + mock + api) → providers → screens`,
  `go_router`, `SalonScoped` providers, `AppAsyncView`.
- Website: the pro BFF (`callApiPro`), the OpenAPI-typed client
  (`web/lib/api/schema.ts` regenerated), client components under
  `/pro/(dash)/revenus`.

---

## 2. What exists today (read in the code, 2026-11-25, `main` `ed60594c`)

### 2.1 Backend

- **`GET /providers/{id}/dashboard`** — `ProviderDashboardService.statsFor`
  (`backend/lib/src/provider_dashboard_service.dart`). Gate
  `journal.view.all`; the three money fields are removed without
  `finances.view` (`:45-50`). Reads **the salon's whole history**
  (`listForProvider(providerId)`, `:40`) and folds it in Dart. Revenue =
  `confirmed` + `completed` (`:34`), bucketed on salon days (`:58-86`).
  **Sums `totalPrice` across currencies** (`:107-109`) — §16.
- **`GET /providers/{id}/earnings`** — `ProviderEarningsService.earningsFor`
  (`backend/lib/src/provider_earnings_service.dart`). Gate `finances.view`
  (`:34`). `completed` only (`:39-42`), optional UTC range, every row in one
  response (no pagination). `totalEarnings` **sums across currencies** under
  the salon's currency (`:54`, `:72`) — §16. Each row carries its own
  currency (`:61`).
- **The booking record** (`backend/lib/src/db/migrations.dart:69-86` and
  later columns; `_toDto`, `postgres_appointment_repository.dart:213-239`):

  | Need | Stored? | Where |
  |---|---|---|
  | Collaborateur | ✅ `artist_id`, nullable (« Sans préférence »); **an empty string also exists** — both booking routes pass `artistId` through after `trim()` with no empty-to-null step (`routes/providers/[id]/appointments.dart:70`) | `booking_service.dart:251`; changed on reassignment (`kAppointmentUpdatableKeys`, `appointment_repository.dart:91-98`) — the only path that changes it is `rescheduleByProvider` |
  | Collaborateur's **name** | ❌ live roster only; `deleteArtist` removes it (`provider_catalog_service.dart:807-818`). `artistName` already exists as a **read-time** key: the consumer enrichment resolves it from the roster (`appointment_enrichment.dart:107`; OpenAPI « Consumer-read enrichment ») and the app reads it — so a stored name needs another key (§8.1) | — |
  | Client's name | ⚠️ `client_name` is only what the **salon typed** on a booking it entered; `book` writes `null` for every online booking by design (`booking_service.dart:260`; OpenAPI: must not be reused). The salon's name for a client is `salon_clients.display_name`, resolved per booking as `clientDisplayName` by `ClientsService._identityOf` (`clients_service.dart:583-611`), anonymised by erasure | — |
  | End time | ✅ `ends_at` stored (`migrations.dart:274`) but not returned by reads; `durationMinutes` is | — |
  | Services | ✅ `service_ids` jsonb (duplicates allowed) | `booking_service.dart:250` |
  | **Price per service** | ❌ only `total_price` = Σ the services' `price` at booking (`booking_service.dart:140-153`, `:322-335`) | — |
  | Service **name** | ❌ live catalogue only; `deleteService` removes it (`provider_catalog_service.dart:163-173`) | — |
  | Price at booking | ✅ `total_price` (the « à partir de » price of a ranged service) | — |
  | Currency | ✅ `currency`, NOT NULL since 0049 (B14.2) | `booking_service.dart:247`, `:343` |
  | Status | ✅ `pending` · `confirmed` · `completed` · `cancelled` (client cancel **and** salon refusal) · `noShow` | `pro_appointment_service.dart:40-61`, `:112-117`; `appointment_lifecycle_service.dart:51` |
  | **Channel** | ⚠️ only salon vs online: `user_id = 'manual'` for a booking the salon enters (`booking_service.dart:344`); app vs website is not recorded | — |
  | À domicile | ❌ | — |
  | Who cancelled | ❌ (a client cancel and a salon refusal are both `cancelled`) | — |
  | When it was completed | ❌ (no `completed_at`); every figure dates a booking by `appointment_date` | — |

- Index `appointments_provider_date_idx (provider_id, appointment_date)`
  exists (`migrations.dart:88-89`) — the range reads in §9 use it.

### 2.2 App

- **« Revenus »** — `mobile/lib/screens/provider/earnings/earnings_screen.dart`:
  four tabs (Aujourd'hui · Semaine · Mois · Tout) on salon days, « Total
  réalisé » card, a transaction list (date, amount — no client, service or
  collaborateur). Entry: Accueil → « Analyses » → « Revenus », shown only with
  `finances.view` (`dashboard_screen.dart:394-400`).
- **Accueil** — two money cards « Revenus prévus » (today, this month), not
  tappable (`dashboard_screen.dart:331-352`).
- **`ProEarningsProvider`** — `SalonScoped`, drops another salon's answer
  (`pro_earnings_provider.dart`).
- **Placeholder** — `screens/provider/features/reports_analytics_screen.dart`,
  flag-hidden V2 (`FeatureFlags.futureProviderFeatures`) **and reached by no
  route at all**, a hand-drawn fake chart and fake rankings. Decision 30 says
  its chart would count « Total réalisé ».
- **Date pickers** — there is **no** Material picker in the app, on purpose
  (`app_theme.dart:590-596`; SYSTEM §21 row 73: Flutter's picker cannot show
  a date at 200 % text). Dates are chosen with `myweli_date_picker.dart` /
  `MyweliMonthGrid`, which pick one date within bounds — no range mode.
- **Stat cards** — `_StatBlock` decides two-across or one-per-row by
  **measuring** every card's texts (`TextFit.columns`,
  `dashboard_screen.dart:507-533`), not by a text-scale threshold; values in
  `headlineSmall` (`:576`).

### 2.3 Website

- `/pro/revenus` — `web/components/pro/RevenusClient.tsx`: the same four
  periods as chips, « Total réalisé », a `DataTable` ledger (Date · Montant,
  each row links to the booking). Sidebar entry gated on `finances.view`
  (`web/lib/pro/nav.ts:34`). BFF: `web/app/api/pro/earnings/route.ts`,
  `web/app/api/pro/dashboard/route.ts`; periods in `web/lib/pro/earnings.ts`.
- Shared pieces: `Tabs` is deliberately **not** an ARIA tablist (a
  `role="group"` of buttons, `web/components/Tabs.tsx:28-36`); `DataTable`
  has **no** in-widget sorting or pagination — callers own them
  (`web/components/DataTable.tsx:14-18`).
- Both surfaces offer « Tout » (all time) today (`earnings_screen.dart:148`,
  `web/lib/pro/earnings.ts:13`).

### 2.4 Who sees money (access.md §2.2)

Only **Propriétaire** has `finances.view`. Manager: « sees no money
figures » (sign-off 2026-07-11); access.md §11 question 4: Manager + finances
« decide only from real salon feedback, as a V3 override, not a preset
change ». Réception: no. Collaborateur: « ma journée » only.

### 2.5 Currency (#837, batch 14)

Batch 14 is complete: every booking stores its currency (NOT NULL since
0049, deployed, #846), the Pro screens and exports show each booking's own
(#843, #848). One country exists in the locality tree (XOF), and a salon's
currency changes only through `areaId` (T57); decision 191 keeps a tripwire
test now and the guard with the second market. **This spec groups every
amount by the booking's own currency** and never adds two currencies.

---

## 3. Definitions — the one place they are written

Every figure below is computed by the server (§9.1). The app and the website
never recompute one.

### 3.1 Which booking belongs to which period

A booking belongs to the period that contains its **start**
(`appointment_date`), read in the **salon's timezone** (`salon_time.dart`,
multi-pays MP1). Not the day it was created, not the day it was marked
« Terminé » (no such date is stored — §2.1).

### 3.2 The figures (per currency group, for one period)

| Field | Definition | French label |
|---|---|---|
| `completedAmount` | Σ `total_price` of `completed` bookings | « Réalisé » |
| `completedCount` | number of `completed` bookings | « Rendez-vous terminés » |
| `averageTicket` | `completedAmount / completedCount`; `null` when the count is 0 | « Panier moyen » |
| `upcomingAmount` / `upcomingCount` | `confirmed` bookings whose **end** (start + `durationMinutes`) is **now or later** — still to come, or under way | « Prévu » |
| `pendingCount` / `pendingAmount` | `pending` bookings whose start is now or later | « … demandes en attente » |
| `toCloseAmount` / `toCloseCount` | `confirmed` bookings whose **end** is **before now** — done or not, nobody said. By the end, not the start: a three-hour braid that began ten minutes ago is not « à clôturer » | « À clôturer » |
| `noShowAmount` / `noShowCount` | `noShow` bookings | « Absences » |
| `noShowRate` | `noShowCount / (completedCount + noShowCount)`; `null` when both are 0 | « Taux d'absence » |
| `cancelledAmount` / `cancelledCount` | `cancelled` bookings (client cancellations **and** salon refusals — §2.1) | « Annulés ou refusés » |

- **« Réalisé » = completed only** — exactly « Total réalisé » today
  (provider-earnings.md §6, §12), so the two screens can never disagree. Q4.
- **The Accueil's « Revenus prévus »** stays `confirmed + completed` of the
  day / month (provider-dashboard-stats.md §6). For the current month it
  equals « Réalisé » + « Prévu » + « À clôturer » of « Mois » here, and a
  test pins that equality (§13.1) — so a tap from that card lands on figures
  that add up to it.
- A past `pending` booking (a request nobody answered) counts nowhere: it
  never happened as far as the salon said.
- **The current period is always counted whole**, today included and the
  days after it: « Réalisé » counts every completed booking dated in the
  range — the server lets the salon mark a booking « Terminé » before its
  date (`pro_appointment_service.dart:56-63` has no time check), and the
  Accueil counts those too — and « Prévu » is the rest of the range. Only the
  **comparison** is cut (§3.5).
- **« now »** is one instant per answer (`asOf`), so the figures, the banner
  and the « À clôturer » list agree (§7.2).

### 3.3 The breakdowns

Each row carries `completedAmount`, `completedCount`, `averageTicket`, its
`share` of the group's `completedAmount` (0–1, server-computed so the shares
add up to 1), and the same three for the comparison period.

- **Par collaborateur** — grouped by `artist_id`. One booking, one
  collaborateur. `null` **or an empty string** (§2.1) → one row « Sans
  collaborateur attribué ». A reassigned booking counts for the collaborateur
  it has now. An id that is not on the roster and has no kept name reads
  « Ancien collaborateur » — the server cannot tell a removed collaborateur
  from an id that never existed (`bookManual` does not check the id against
  the roster); R1 makes new bookings store `null` for an empty id.
- **Par prestation** — grouped by `serviceId` over the booking's **service
  lines** (§8.1). A line's amount is its price at booking; the lines of a
  booking add up to its `total_price` exactly (an invariant, tested). A
  booking with two prestations counts once in each row's count, so the counts
  add up to more than the bookings (the footnote says so, §4.10); the amounts
  add up exactly.
- **Par canal** — `app` (MyWeli, the app) · `web` (MyWeli, the website) ·
  `salon` (entered by the salon) · `online` (an online booking made before
  the channel was recorded: app or website, unknown). Q7.

**The label of a row** — group by the id, label from the **live** name if it
still exists, else the name kept on the booking (§8.1), else the generic one:

| Axis | `state` | Label shown |
|---|---|---|
| collaborateur | `active` | the live name |
| | `removed` | the kept name + « · a quitté l'équipe » ; no kept name: « Ancien collaborateur » |
| | `unassigned` | « Sans collaborateur attribué » |
| prestation | `active` | the live name |
| | `removed` | the kept name + « · prestation supprimée » ; no kept name: « Prestation supprimée » |
| canal | — | « Application MyWeli » · « Site MyWeli » · « Ajouté par le salon » · « En ligne (avant le suivi) » |

A renamed service shows its new name over all its history — one row per id,
never two rows for one service.

### 3.4 Older bookings — estimated, never rewritten (Q5)

A booking made before R1 deploys has no service lines. The aggregator
**estimates** them at read time, the one algorithm, in one function:

1. Take today's catalogue price of each `serviceId` on the booking (0 for a
   service that no longer exists).
2. Share the booking's `total_price` in proportion to those prices; if they
   are all 0, share it equally.
3. Round each share to the currency's unit (XOF and XAF have no minor unit)
   and give the remainder to the largest line, so the lines add up to
   `total_price` exactly.
4. Mark each such line `estimated` — **except the line of a booking with a
   single service**: its line is its `total_price`, exact by construction,
   so it is not marked (a precision of decision 241's own words, « exact for
   every single-prestation booking »; recorded 2026-11-25 after the
   production read, §19).

A row whose amount includes an estimated line carries `estimated: true`; the
app and the website print « estimé » beside it, with the footnote (§4.10).
No production row is written.

### 3.5 Periods and comparison — the server owns the calendar

The client sends `period` and, optionally, `date` (any day inside it) — **no
`date` means the salon's today, as the server reads it**, so a phone whose
clock is wrong still opens on the right month — or `period=custom` + `from`
+ `to`. The server answers with the resolved dates, so the app and the
website share one definition of a week, a month and « the period before ».
Stepping ‹ › sends the `date` the client computes from the answer's `from`
(one unit earlier or later): date arithmetic on a date, no clock involved.

| `period` | Range | `compare=previous` | `compare=year` |
|---|---|---|---|
| `day` | that day | the day before | the same date a year earlier (29 Feb → 28 Feb) |
| `week` | Monday → Sunday containing `date` | the week before | the week 52 weeks earlier (same weekdays) |
| `month` | 1st → last day | the previous calendar month, in full | the same month a year earlier |
| `year` | 1 Jan → 31 Dec | the previous year | the previous year |
| `custom` | `from` → `to` (≤ 366 days) | the same number of days, just before | the same dates a year earlier |

**Like for like (Q8).** When `asOf` falls inside the current range, the
current figures stay whole (§3.2) but the **comparison is cut at the same
point of its own period**: the same number of days from its start and the
same salon wall-clock time. On 25 November at 14:30, « Mois » compares
November with **1 October 00:00 → 25 October 14:30** — not with all of
October, and not with all of 25 October. The response says so
(`likeForLike: true`, the comparison's `from`, its `cutoff` instant). A cut
that falls past the comparison's own end is clipped to it (31 March →
28 February 24:00). The label reads « 1er – 25 oct., même avancement ».

**No « Tout » (Q8).** Both surfaces offer an all-time period today (§2.3).
Every range here is capped at 366 days (§11's budget), so « Tout » goes;
« Année » and « Dates » cover a salon's history year by year. The question
says it.

**Buckets of the chart** — `day` when the range is ≤ 31 days, `week`
(Monday-start, the first and last clipped to the range) when ≤ 92, else
`month`. A range with fewer than two buckets has no chart.

**Bounds** — `from` ≥ 2020-01-01; `to` ≤ today + 366 days; ≤ 366 days long.
A future period is allowed: its « Réalisé » is 0 and its « Prévu » is the
point.

### 3.6 Deltas

| Case | Shown |
|---|---|
| previous > 0 | `(current − previous) / previous`, rounded to the whole percent: « +12 % », « −8 % » |
| rounds to 0 | « stable » |
| previous = 0, current > 0 | « nouveau » (never « +∞ % ») |
| both 0, or no comparison | nothing |
| `noShowRate` | the difference in **points**, one decimal: « −1,2 pt » |

Up is good for every figure except « Taux d'absence ». The colour follows
that (`success` / `error`, neutral for « stable »), and **never alone**: an
arrow glyph and the sign carry the direction, and the screen reader hears a
sentence (§12.3).

---

## 4. UX — the app (MyWeli Pro)

### 4.1 Entry points

1. Accueil → « Analyses » → **« Revenus »** (exists; `finances.view`).
   Opens « Mois », the current month, compared with the previous month.
2. Accueil → the **« Aujourd'hui · Revenus prévus »** card → « Revenus » on
   « Jour », today. **New: the card becomes tappable** for `finances.view`
   (Q2). It is not tappable for a member without it (they do not see it).
3. Accueil → the **« Ce mois · Revenus prévus »** card → « Revenus » on
   « Mois ».
4. A booking detail is reached **from** the ledger, never the other way.

`/pro/earnings` keeps its path (no deep link breaks). The new routes:
`/pro/earnings/collaborateur/:artistId`, `/pro/earnings/prestation/:serviceId`,
`/pro/earnings/canal/:channel`, `/pro/earnings/rendez-vous` — each with the
period in the query (`?period=month&date=2026-11-25&compare=previous`), so
Back returns to the same period.

### 4.2 The screen, top to bottom (360 dp first)

```
┌ Revenus ─────────────────────────────┐
│ [Jour] [Semaine] (Mois) [Année] [Dates…] │  ← AppChip.choice, scrolls sideways if it must
│   ‹    Novembre 2026    ›             │  ← 48 dp arrows, tooltips
│   Comparé à : 1–25 octobre ▾          │  ← opens the comparison sheet
│ ┌ ⓘ 4 rendez-vous passés à clôturer ┐ │  ← StatusBanner (info), only when > 0
│ │ Confirmés mais pas marqués « Terminé » : │
│ │ ils ne comptent pas dans le réalisé.  │
│ │                          [Voir]   │ │
│ └───────────────────────────────────┘ │
│ ┌ Réalisé ─────────┐┌ Terminés ───────┐│
│ │ 1 250 000 FCFA   ││ 48              ││  ← KPI grid: two across,
│ │ ▲ +12 %          ││ ▲ +4 %          ││     all one per row when a
│ └──────────────────┘└─────────────────┘│     tile's texts would not fit (measured)
│ ┌ Panier moyen ────┐┌ Taux d'absence ─┐│
│ │ 26 042 FCFA      ││ 5,9 %           ││
│ │ ▲ +8 %           ││ ▼ −1,2 pt       ││
│ │                  ││ 3 absences ·    ││
│ │                  ││ 45 000 FCFA     ││
│ └──────────────────┘└─────────────────┘│
│ ┌ Prévu ─────────────────────────────┐ │  ← only when the period ends today or later
│ │ 320 000 FCFA                        │ │
│ │ 12 rendez-vous confirmés à venir    │ │
│ │ + 3 demandes en attente             │ │
│ └─────────────────────────────────────┘ │
│ Évolution                [Voir en liste]│
│ ▁▃▅▂▇▄▁▆▃▅▂▁▃▅▇▂▄▆▃▁▅▃▂▆▄▁▃▅▂▇          │  ← bars, one per bucket
│ 1 nov.        15 nov.         30 nov.   │
│ Répartition                             │
│ (Collaborateurs) [Prestations] [Canaux] │
│                         Trier : Montant ▾│
│ Awa Koné                 420 000 FCFA   │
│ ████████████▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁   │  ← share bar
│ 16 rdv · panier 26 250 FCFA · 34 %  ▲ +9 %│
│ …                                       │
│ Rendez-vous terminés        Voir tout (48)│
│ mar. 25 nov. · 14:30          35 000 FCFA│
│ Fatou B. · Tresses · Awa Koné           │
│ …(5 rows)                               │
│ Montants calculés au prix affiché lors  │
│ de la réservation. Les paiements se font│
│ entre vous et vos clients : MyWeli      │
│ n'encaisse rien. …                       │
└─────────────────────────────────────────┘
```

### 4.3 The period bar

- **Chips** « Jour » · « Semaine » · « Mois » · « Année » · « Dates… »
  (`AppChip.choice`). Picking one keeps the anchor date: from « Mois »
  (novembre 2026) to « Semaine » gives the week containing today when the
  month is the current one, else the month's first week.
- **‹ ›** step one period (`date` ± one unit); custom ranges step by their
  own length. Tooltips « Période précédente » / « Période suivante ». ›
  stops at today + 366 days; ‹ at 2020.
- **The label** — « Mardi 25 novembre » · « 24 – 30 nov. 2026 » ·
  « Novembre 2026 » · « 2026 » · « 3 oct. – 25 nov. 2026 », formatted from the
  server's `from`/`to`. A period containing today adds « (en cours) »
  under it in `bodySmall`.
- **« Dates… »** opens a bottom sheet with two fields, « Du » and « Au »,
  each opening MyWeli's own date picker (`myweli_date_picker.dart`, bounded
  by §3.5 — there is no Material picker in the app, §2.2, and no range mode
  is built: two single dates are enough). A range over 366 days, or « Au »
  before « Du », shows the field's error (« 366 jours au plus », « La date
  de fin précède la date de début ») under « Au » — never a toast. « Afficher »
  applies it.
- **« Comparé à : … ▾ »** — a text button that opens a bottom sheet:
  « Période précédente » · « Même période l'an dernier » · « Aucune
  comparaison », radio-style option cards (§3.3 `borderStrong`). The line
  shows the resolved dates (« 1–25 octobre », « novembre 2025 »), or
  « Aucune comparaison ». The choice persists for the session, not on disk.

### 4.4 « À clôturer »

Shown when `toCloseCount > 0` in any group: a `StatusBanner` (`color:
AppColors.info`, an `iconM` glyph) « {n} rendez-vous passé(s) à clôturer »
with the line « Confirmés mais pas encore marqués « Terminé » : ils ne
comptent pas dans le réalisé. », and **directly under it**, outside the
banner (it has no action slot — `status_banner.dart:24-36`, SYSTEM §11.1), a
text button « Voir » → the ledger on « À clôturer », where each row opens the
booking and its « Terminé » / « Absent » actions (journal J1, existing).
Coming back reloads the figures.

### 4.5 The figures (KPI grid)

`_StatBlock`'s rule, moved unchanged to a shared widget (`KpiGrid`, §12.1):
two across, or **all** tiles one per row when any tile's texts would not fit
half the width — **measured** (`TextFit.columns`, width × text size ×
the figures), never a text-scale threshold (§2.2). The Accueil keeps exactly
its shape; `dashboard_role_test` and `layout_test` stay green through the
move. Each tile: title (`bodyMedium`, `textSecondary`) · value
(`headlineSmall`, as the Accueil's, `textPrimary`; an amount never breaks
inside — the grid measures it) · delta (§3.6) · optional caption
(`bodySmall`, `textTertiary`). Tiles: « Réalisé » · « Rendez-vous terminés » · « Panier
moyen » · « Taux d'absence » (+ « {n} absence(s) · {montant} ») · « Prévu »
(full width; only when the period ends today or later).

### 4.6 « Évolution »

- Bars of « Réalisé » per bucket, `primary` on the card, height a named
  constant (160 dp, §5 « What §5 does not govern »), `radiusSmall` tops.
  No axis numbers; the first, middle and last bucket dates under the bars
  (`bodySmall`, `textTertiary`).
- **Tap or drag across the chart** → the nearest bar is selected (the
  selected bar follows the finger, so a 10 dp bar — 31 in 328 dp — is still
  easy to reach) and a line above the chart reads « mar. 4 nov. · 45 000
  FCFA · 2 rendez-vous ». **Selection is shown by fill, not by an outline**:
  the selected bar stays `primary`, the others turn `borderStrong` (3.22:1,
  still visible). A 2 dp `borderFocus` outline would be black on a black bar
  (`primary` and `borderFocus` are both `#000000`, SYSTEM §3.1, §3.3). Tap
  outside the bars → no selection, the line returns to the period total.
- **One semantics node for the whole chart** (328 × 160 dp — it passes
  `androidTapTargetGuideline`, where 31 ten-dp buttons would fail it):
  label « Évolution du réalisé », value = the selected bucket's sentence (or
  the period total), and `onIncrease` / `onDecrease` move the selection — a
  screen reader swipes through the buckets. « Voir en liste » swaps the chart
  for a list of buckets (date · amount · count), the form 200 % text and
  anyone who prefers it use.
- The comparison is not drawn (two series on 160 dp do not read on a phone);
  it is in the figures above.
- No chart under two buckets (« Jour »).

### 4.7 « Répartition »

- Three tabs (`AppChip.choice`, one row): « Collaborateurs » ·
  « Prestations » · « Canaux ». « Collaborateurs » first. A tab with one row
  only (a solo salon) still shows: one row at 100 % is an answer.
- **Sort** — « Trier : Montant ▾ » opens a menu: « Montant » (default) ·
  « Rendez-vous » · « Nom ». Rows with `completedAmount = 0` in the period
  but present in the comparison stay, at the bottom, so a collaborateur who
  dropped to zero is visible.
- **A row** (`AppCard`, whole row tappable, ≥ 48 dp): the label (wraps,
  never truncated) · the amount, right · a share bar (4 dp, `primary` on
  `surfaceVariant`, `radiusPill`) · « {n} rdv · panier {montant} · {part} % »
  · the delta. `estimated` adds « estimé » after the amount. One semantics
  node: « Awa Koné, 420 000 FCFA, 34 % du réalisé, 16 rendez-vous, panier
  moyen 26 250 FCFA, en hausse de 9 % par rapport à octobre. Ouvrir le
  détail. »
- **Tap** → the detail (§4.8).

### 4.8 The detail of a row

Title = the row's label. The same period bar (inherited, then free), the
same « Comparé à », then:

- the KPI grid **for that row only** (Réalisé · Terminés · Panier moyen ·
  Taux d'absence · Prévu);
- « Évolution » for that row;
- « Répartition » with the **other** axes only (a collaborateur → «
  Prestations » · « Canaux »; a prestation → « Collaborateurs » · « Canaux »;
  a canal → « Collaborateurs » · « Prestations »). Rows there do **not**
  drill further (one level is enough on a phone; the website can — §5.4);
- the ledger, filtered.

For a prestation, « Réalisé » counts that prestation's **lines** only, so a
two-prestation booking adds its line, not its total; the ledger rows show the
line amount and « sur {total} » under it.

### 4.9 The ledger (« Rendez-vous »)

- On the main screen: « Rendez-vous terminés », the 5 latest, « Voir tout
  ({n}) ».
- **The ledger screen**: filter chips « Terminés » (default) · « À venir » ·
  « À clôturer » · « Absents » · « Annulés »; pages of 20, « Afficher plus »
  at the end (no infinite scroll — it is announced and it is a control).
  « À venir » soonest first; the others newest first.
- **A row**: date and time in salon time · amount (its own currency) ·
  « {client} · {prestations} · {collaborateur} ». The client is the salon's
  name for them — `clientDisplayName`, the journal's (§2.1, §7.2): a booking
  with none (an erased client, or a reader without `clients.view`) reads
  « Client », the journal's own fallback. A booking without a collaborateur
  reads « Sans collaborateur ». Tap → the booking's detail
  (`/pro/appointment/:id?salon={salonId}`, the existing route, which switches
  salon first when it must — `pro_router.dart:171-181`).

### 4.10 Footnotes (always under the content, `bodySmall`, `textTertiary`)

- « Montants calculés au prix affiché lors de la réservation. Les paiements
  se font entre vous et vos clients : MyWeli n'encaisse rien. »
- On « Prestations »: « Un rendez-vous à plusieurs prestations compte pour
  chacune. »
- When a row is estimated: « Estimé : réservation faite avant le
  {date de R1}, répartie selon les prix actuels de vos prestations. »

**Never** « encaissé », « chiffre d'affaires », « paiements reçus »: MyWeli
does not see a payment (PRD OQ-1; provider-dashboard-stats.md §12).

### 4.11 States

| State | What the screen shows |
|---|---|
| **First load** | The period bar (real) + a skeleton: the KPI grid's tiles, a chart block, three rows (`app_skeleton.dart` shapes; one label « Chargement des revenus… »). |
| **Period change** | The bar updates at once; the content goes back to the skeleton. **The previous period's numbers are never shown under the new label** (earnings_screen's rule, `:162-164`). An older answer arriving late is dropped (a request id, the booking hub's `slotsRequestId` pattern). |
| **Error** | `AppErrorView` « Chargement impossible » + the failure's sentence + « Réessayer » (same period); `wifi_off` for no connection. |
| **Salon with no completed booking ever** (`everCompleted: false`) | `EmptyState` icon `insights_outlined`, « Pas encore de revenus », « Vos revenus s'afficheront ici dès votre premier rendez-vous marqué « Terminé ». », action « Voir les rendez-vous » (→ `/pro/journal`). The period bar stays (a salon with upcoming bookings sees « Prévu »). |
| **A period with nothing completed** | Figures at 0 with their deltas; no chart; « Répartition » shows `EmptyState` « Aucun rendez-vous terminé sur cette période » + « Période précédente ». |
| **A future period** | « Réalisé » 0 FCFA, « Prévu » leads; « Répartition » empty state « Rien de terminé pour l'instant : cette période n'a pas commencé. » |
| **Several currencies in the period** | A segmented control above the figures, one segment per currency (« XOF · franc CFA (UEMOA) », « XAF · franc CFA (CEMAC) »), the largest « Réalisé » first. Nothing adds two currencies. |
| **Access refused** (403 — a role changed mid-session, a stale deep link) | `EmptyState` icon `lock_outline`, « Réservé au propriétaire », « Seul le propriétaire du salon voit les revenus. » — no retry (retrying cannot succeed, SYSTEM §12). The new endpoints answer only `forbidden`; a revoked member is caught as today, through `ProAccessGuard.report` (`pro_access_guard.dart:18-22`) and the `/me/provider` probe that answers `not_a_member`. |
| **Salon switch** | `resetForSalonSwitch`: the state empties, the in-flight answer is dropped. |
| **Comparison has no data** | Deltas read « nouveau » or nothing (§3.6), never an error. |

### 4.12 Edge cases

- **Long French names** (« Prestation supprimée · Tresses africaines avec
  rajouts ») wrap; amounts never break inside (`expectNoMidWordBreak`).
- **200 % text at 360 dp**: one tile per row (the grid measures it), chips scroll, the share bar
  stays full width, the chart keeps its height and « Voir en liste » is the
  readable form. Pinned in `layout_test` (360/375/390 × 1×/2×) and
  `vertical_fit_test`.
- **A slow 3G answer**: the skeleton stays; nothing reflows when it lands
  (the skeleton has the content's shape).
- **Low-end Android**: one request per period (§11); bars are plain
  `Container`s in a `Row` (no `CustomPainter` repaint per frame, no chart
  package); the ledger is a paginated `ListView.builder`.
- **Midnight in Abidjan**: the server's « today », never the device's.
- **A salon whose currency changed** (not possible today, decision 191):
  two groups, the switcher.

### 4.13 Copy (French, complete)

| Where | Text |
|---|---|
| Screen title | « Revenus » |
| Chips | « Jour » · « Semaine » · « Mois » · « Année » · « Dates… » |
| Arrows (tooltips) | « Période précédente » · « Période suivante » |
| In progress | « (en cours) » |
| Comparison line | « Comparé à : {dates} » · « Aucune comparaison » |
| Comparison sheet | title « Comparer à » · « Période précédente » · « Même période l'an dernier » · « Aucune comparaison » |
| Custom range error | « 366 jours au plus » · « La date de fin précède la date de début » |
| Banner | « {n} rendez-vous passé(s) à clôturer » · « Confirmés mais pas encore marqués « Terminé » : ils ne comptent pas dans le réalisé. » · « Voir » |
| Tiles | « Réalisé » · « Rendez-vous terminés » · « Panier moyen » · « Taux d'absence » · « {n} absence(s) · {montant} » · « Prévu » · « {n} rendez-vous confirmé(s) à venir » · « + {n} demande(s) en attente » |
| Deltas | « +12 % » · « −8 % » · « stable » · « nouveau » · « −1,2 pt » |
| Chart | « Évolution » · « Voir en liste » · « Voir le graphique » · « {date} · {montant} · {n} rendez-vous » |
| Tabs | « Collaborateurs » · « Prestations » · « Canaux » |
| Sort | « Trier : {critère} » · « Montant » · « Rendez-vous » · « Nom » |
| Row meta | « {n} rdv · panier {montant} · {part} % » · « estimé » |
| Labels | « Sans collaborateur attribué » · « Ancien collaborateur » · « · a quitté l'équipe » · « Prestation supprimée » · « · prestation supprimée » · « Application MyWeli » · « Site MyWeli » · « Ajouté par le salon » · « En ligne (avant le suivi) » |
| Ledger | « Rendez-vous terminés » · « Voir tout ({n}) » · « Terminés » · « À venir » · « À clôturer » · « Absents » · « Annulés » · « Afficher plus » · « Client » · « Sans collaborateur » · « sur {total} » |
| Empty | « Pas encore de revenus » · « Vos revenus s'afficheront ici dès votre premier rendez-vous marqué « Terminé ». » · « Voir les rendez-vous » · « Aucun rendez-vous terminé sur cette période » · « Période précédente » · « Rien de terminé pour l'instant : cette période n'a pas commencé. » · ledger: « Aucun rendez-vous » + « Aucun rendez-vous {filtre} sur cette période. » |
| Refused | « Réservé au propriétaire » · « Seul le propriétaire du salon voit les revenus. » |
| Footnotes | §4.10 |

Plurals go through `Formatters.count` / `Formatters.plural` (CLDR, French
locale), never « (s) » on screen (SYSTEM §17.1, A13); the table writes
« (s) » only as a placeholder.

---

## 5. UX — the website (espace pro, `/pro/revenus`)

Same flow and same story as the app (web-mirror-app-flow), its own desktop
layout (web-design-latitude).

### 5.1 Layout

- Width cap `max-w-5xl` for every state (skeleton, error, success —
  WEB-SYSTEM row 18's rule); the page breathes at `xl:`.
- `h1` « Revenus »; lead « Ce que vos rendez-vous terminés ont rapporté, par
  collaborateur, prestation et canal. »
- **Toolbar**: the five `ChipButton`s · ‹ label › · `<label for>` « Comparer
  à » + native `<select>` · « Exporter (CSV) » (Q10). Keyboard: ← / → step
  the period when focus is not in a field, guarded like the journal's
  shortcuts (WEB-SYSTEM §9); `e.repeat` ignored.
- **« Dates… »** opens a dialog (focus trapped and restored) with two
  `<input type="date">` labelled « Du » / « Au », errors tied to each field
  (`aria-invalid`, `aria-describedby`).
- **Figures**: `Card` tiles, two across under `md`, five across at `lg`.
- **Évolution**: an SVG bar chart drawn by hand, **one** focusable element
  (`tabIndex=0`, `role="img"`, an `aria-label` summarising the period): the
  pointer selects the nearest bar on hover or tap, ← / → move the selection
  while it has focus, and the line above it (`aria-live="polite"`) says the
  bucket's sentence — as the app. No bar is its own button (31 bars at a
  phone width would be 10 px targets). Selection by fill, as the app (§4.6).
  « Voir les données » toggles a real `<table>` (date · montant ·
  rendez-vous), the accessible form.
- **Répartition**: the shared **`Tabs`** (a `role="group"` of buttons with
  `aria-pressed` — deliberately not an ARIA tablist, `Tabs.tsx:28-36`) and a
  `DataTable` per tab: columns « Nom » · « Rendez-vous » · « Montant » ·
  « Part » · « Panier moyen » · « Évolution ». **Sort by a labelled `<select>`**
  « Trier par » above the table (« Montant », « Rendez-vous », « Nom »), the
  app's three choices — `DataTable` has no sorting and the page owns it, as
  it owns paging (§2.3). Each row is a link (the DataTable's navigation row).
- **Ledger**: `DataTable` « Rendez-vous terminés », its filter chips, pages
  of 20 loaded by « Afficher plus » (the page's own control, as
  `ClientsClient`'s « Charger plus »), the new count announced.

### 5.2 URLs (everything addressable, Back works, a link can be shared)

- `/pro/revenus?periode=mois&date=2026-11-25&comparer=precedente`
  (`periode` = jour|semaine|mois|annee|dates; `comparer` =
  precedente|annee|aucune; `du`/`au` for « dates »).
- `/pro/revenus/collaborateurs/[artistId]` · `/pro/revenus/prestations/[serviceId]`
  · `/pro/revenus/canaux/[canal]` · `/pro/revenus/rendez-vous` — same query.
- A malformed query falls back to the current month, without an error page.

### 5.3 States

The app's table (§4.11), with the website's pieces: `SkeletonRows` /
skeleton tiles, `ErrorState` + « Réessayer » (`aria-live` announced),
`EmptyState`, the « Réservé au propriétaire » state for a 403, the existing
redirect to `/pro/connexion` for a 401.

### 5.4 Parity, and where the website does more

| | App | Website |
|---|---|---|
| Periods, comparison, figures, chart, three axes, details, ledger, states, copy | ✅ | ✅ same |
| Detail inside a detail (collaborateur → prestation) | — (one level) | ✅ the URL can carry both filters |
| Sorting | a menu | a labelled `<select>` |
| CSV export | — (Q10) | ✅ « Exporter (CSV) » per table |
| Push the app | — | the pro shell's existing nudge to MyWeli Pro |

`/pro/*` is `noindex`; no SEO work.

---

## 6. Who sees what (RBAC)

| Role | « Revenus » / analytics | Accueil money cards |
|---|---|---|
| **Propriétaire** | ✅ all of it (`finances.view`) | ✅, tappable |
| **Manager** | ❌ — card hidden; the endpoints answer 403 | ❌ (fields absent) |
| **Réception** | ❌ — same | ❌ |
| **Collaborateur** | ❌ — same (Q3) | ❌ |

- One capability, `finances.view`, checked by the server on every read
  (deny by default); the app and the website only hide.
- **Q3 — should a Collaborateur see their own figures?** Recommended: not
  now. access.md keeps money owner-only by sign-off, and its §11 question 4 says a change
  comes « from real salon feedback, as a V3 override ». If the owner says
  yes, it is a new capability `finances.view.own` on the Collaborateur preset,
  scoped to the server-resolved `artist_id` like T40, and a « Mes revenus »
  card in « Ma journée » — its own small spec.
- **Plan**: no tier gate — « Statistiques & avis clients » is in the Pro
  offer (`web/lib/pro/subscription-plans.ts:49`) and every offer includes
  Pro's. Q11.

---

## 7. API & contract (`docs/api/openapi.yaml`, R2)

### 7.1 `GET /providers/{id}/analytics/revenue`

Provider token; membership of `{id}` with `finances.view` (→ 403
`forbidden`); `GET` only (405).

**Query**

| Param | Values | Rule |
|---|---|---|
| `period` | `day` · `week` · `month` · `year` · `custom` | required |
| `date` | `YYYY-MM-DD` | optional (not with `custom`); any day inside the period; absent → the salon's today |
| `from`, `to` | `YYYY-MM-DD` | required with `custom`; `from ≤ to`; ≤ 366 days |
| `compare` | `previous` (default) · `year` · `none` | |
| `artistId` | an id, or `none` (unassigned) | optional filter |
| `serviceId` | an id | optional filter |
| `channel` | `app` · `web` · `salon` · `online` | optional filter |

Ids match `^[A-Za-z0-9_-]{1,64}$`. An unknown id is not an error: its figures
are 0 and its label `null`. Errors: 400 `invalid_input` (a malformed or
out-of-bounds value), 400 `range_too_long`, 401, 403, 405.

**Response `RevenueAnalytics`**

```yaml
RevenueAnalytics:
  required: [period, from, to, inProgress, timezone, asOf, bucket,
             comparison, everCompleted, groups]
  properties:
    period:      { type: string, enum: [day, week, month, year, custom] }
    from:        { type: string, format: date }      # resolved, salon dates
    to:          { type: string, format: date }
    inProgress:  { type: boolean }                    # today is inside [from, to]
    timezone:    { type: string }                     # the salon's IANA zone
    asOf:        { type: string, format: date-time }  # the server's "now"
    bucket:      { type: string, enum: [day, week, month] }
    comparison:
      type: object
      required: [mode]
      properties:
        mode:        { type: string, enum: [previous, year, none] }
        from:        { type: string, format: date, nullable: true }
        to:          { type: string, format: date, nullable: true }
        likeForLike: { type: boolean }
        cutoff:      { type: string, format: date-time, nullable: true }  # where the comparison stops when likeForLike
    filters:
      type: object
      properties:
        artistId:  { type: string, nullable: true }
        serviceId: { type: string, nullable: true }
        channel:   { type: string, nullable: true }
        label:     { type: string, nullable: true }   # the filtered row's label (§3.3)
        state:     { type: string, nullable: true }
    everCompleted: { type: boolean }   # the salon has ≥ 1 completed booking, ever
    groups:                             # one per currency; [] = nothing in either range
      type: array
      items: { $ref: '#/components/schemas/RevenueGroup' }

RevenueGroup:
  required: [currency, current, series, byArtist, byService, byChannel]
  properties:
    currency:       { type: string }                       # ISO-4217
    current:        { $ref: '#/components/schemas/RevenueFigures' }
    previous:       { $ref: '#/components/schemas/RevenueFigures', nullable: true }
    series:
      type: array    # one point per bucket of the current range, zero-filled
      items:
        type: object
        required: [start, end, completedAmount, completedCount]
        properties:
          start: { type: string, format: date }
          end:   { type: string, format: date }
          completedAmount: { type: number }
          completedCount:  { type: integer }
    byArtist:  { type: array, items: { $ref: '#/components/schemas/RevenueRow' } }
    byService: { type: array, items: { $ref: '#/components/schemas/RevenueRow' } }
    byChannel: { type: array, items: { $ref: '#/components/schemas/RevenueRow' } }

RevenueFigures:
  required: [completedAmount, completedCount, averageTicket, upcomingAmount,
             upcomingCount, pendingAmount, pendingCount, toCloseAmount,
             toCloseCount, noShowAmount, noShowCount, noShowRate,
             cancelledAmount, cancelledCount, estimated]
  # every field as defined in §3.2; averageTicket and noShowRate nullable;
  # estimated = some completed amount here comes from §3.4

RevenueRow:
  required: [key, label, state, share, current, estimated]
  properties:
    key:   { type: string, nullable: true }   # artistId / serviceId / channel; null = unassigned
    label: { type: string, nullable: true }   # live name ?? kept name; null → the client's generic label
    state: { type: string, enum: [active, removed, unassigned, legacy] }
    share: { type: number }                   # of the group's current completedAmount, 0–1
    current:  { $ref: '#/components/schemas/RevenueRowFigures' }
    previous: { $ref: '#/components/schemas/RevenueRowFigures', nullable: true }
    estimated: { type: boolean }

RevenueRowFigures:
  required: [completedAmount, completedCount, averageTicket]
```

- Rows are sorted by current `completedAmount` desc, then label, then key —
  a total order, so two reads never swap rows. A row appears if it has a
  completed booking in either range.
- When a filter is set, the axis it filters is `[]` (a collaborateur's
  detail has no « Collaborateurs » tab).
- `Cache-Control: private, no-store`.

### 7.2 `GET /providers/{id}/analytics/revenue/appointments`

Same gate, same period and filter params, plus `status` = `completed`
(default) · `upcoming` · `toClose` · `noShow` · `cancelled`, `page` ≥ 1,
`pageSize` 1–50 (default 20), and `asOf` — the figures' `asOf`, so the
« À clôturer » list holds exactly the bookings the banner counted
(accepted only within the last 24 hours and not in the future; absent →
the server's now).

```yaml
RevenueLedgerPage:
  required: [items, page, pageSize, total]
  items:
    RevenueLedgerRow:
      required: [appointmentId, appointmentDate, status, amount, totalPrice,
                 currency, serviceNames, artistState, channel, estimated]
      properties:
        appointmentId:   { type: string }
        appointmentDate: { type: string, format: date-time }
        status:          { type: string }
        amount:      { type: number }  # the line's amount under a serviceId filter, else totalPrice
        totalPrice:  { type: number }
        currency:    { type: string }
        clientDisplayName: { type: string }  # ABSENT without clients.view, or when no client resolves (erased)
        serviceNames:
          type: array
          items: { type: string, nullable: true }       # null = deleted, no kept name
        artistLabel: { type: string, nullable: true }
        artistState: { type: string, enum: [active, removed, unassigned] }
        channel:     { type: string, enum: [app, web, salon, online] }
        estimated:   { type: boolean }
```

`upcoming` soonest first; the others newest first; ties broken by id.

**The client's name.** `clientName` is not the field: it is `null` on every
online booking by design (§2.1). The row carries `clientDisplayName`, the
salon's name for the client, resolved **as the journal resolves it**
(`ClientsService._identityOf`, `salon_clients`), but through a **batched**
lookup for the page's ≤ 50 rows — not `enrichForProvider`, which reads the
salon's whole history on every call (`clients_service.dart:555`). It is
**field-gated on `clients.view`**, as `/dashboard` gates money on
`finances.view`: absent without it (today every owner has both; access.md
plans per-person grants in V3). Never the phone — the booking detail has it.

### 7.3 Unchanged

`GET /providers/{id}/dashboard` and `GET /providers/{id}/earnings` keep
their shape and meaning: builds 0.0.2 in both stores call them.

### 7.4 Clients

- App: `ProServiceInterface.getRevenueAnalytics(SalonId, RevenueQuery)` and
  `getRevenueLedger(SalonId, RevenueQuery, LedgerStatus, int page)`;
  `ApiProService` → the endpoints; `MockProService` → realistic data (three
  collaborateurs incl. one removed and the unassigned row, six prestations
  incl. a deleted one, all four channels, an estimated row, two currencies
  behind a debug switch), 300–900 ms latency, a failure and an empty salon.
  Models `RevenueAnalytics` & co. with `fromJson`, equatable, shaped
  field-for-field on the contract.
- Website: `web/app/api/pro/revenue/route.ts` and
  `web/app/api/pro/revenue/appointments/route.ts` (BFF, `callApiPro`, the
  client's `providerId` checked by the backend), types from the regenerated
  `web/lib/api/schema.ts`.

---

## 8. Data model (R1)

### 8.1 Three nullable columns on `appointments` (migration 0052, additive)

*Numbered 0051 when this spec was written; A4-api's `unaccent` (#864)
merged first and took 0051, so R1 is 0052.*

| Column | Type | Written by | Content |
|---|---|---|---|
| `service_lines` | `jsonb` | `book`, `bookManual` | `[{ "serviceId", "name", "price", "durationMinutes" }]`, one per `service_ids` entry, in its order; Σ `price` = `total_price`. **Stored as a real JSON array** — the Dart list passed to the `:jsonb` parameter, never `jsonEncode`d first, which is what makes `service_ids` a JSON string (§8.3, §19); a DB-gated test asserts `jsonb_typeof(service_lines) = 'array'`, **and the column's CHECK refuses anything else** (`jsonb_typeof(service_lines) = 'array'`, 23514), so `_toDto` returns the column as read — an array or NULL, never a string (as built in R1: stronger than the test alone) |
| `artist_name_kept` | `text` | `book`, `bookManual`; and every write of `artistId` (reassignment: `rescheduleByProvider`, the journal's drag) | the collaborateur's name at that moment; `NULL` when there is no collaborateur |
| `channel` | `text` | `book` (`app` or `web`, §8.2), `bookManual` (`salon`) | `app` · `web` · `salon`; a CHECK keeps it to these three or NULL |

- **Its own key, `artistNameKept`** — not `artistName`, which is already the
  **live** roster name every consumer read adds (§2.1). Reusing it would make
  one key mean two things: a consumer read would overwrite the kept name with
  the live one (or with null), a pro read would show the kept one.
- **The three keys travel with the booking.** The twins' contract requires
  every key the booking service writes to come back from every read
  (`appointment_repository_contract.dart:99`), as `currency` does; so
  `_toDto` returns `serviceLines`, `channel` and `artistNameKept`, and the
  OpenAPI `Appointment` schema documents them as stored, read-only fields.
  Nothing on any client reads them outside this feature; a consumer sees
  only its own booking's lines, which are its own prices.
- **An empty `artistId` is stored as `null`** from R1 on (§3.3).
- **No backfill** (Q5). A NULL is a meaningful state — « made before R1 » —
  read by the aggregator: lines estimated (§3.4); `artist_name_kept` NULL →
  the live roster, else « Ancien collaborateur »; `channel` NULL → `salon`
  when `user_id = 'manual'` (erasure keeps `user_id`,
  `postgres_appointment_repository.dart:282-293`), else `online`.
- **The updatable keys** gain `artistNameKept`, which is more than one line
  of `kAppointmentUpdatableKeys`: the Postgres `SET` builder gains its
  branch (`postgres_appointment_repository.dart:190-193`),
  `checkAppointmentChanges` its type check (`appointment_repository.dart:132-137`)
  **and a rule that it is only accepted together with `artistId`** (else
  `ArgumentError`, on both twins), and the « six keys » of the doc comment
  and the contract become seven (`:87-88`, contract `:230`). `service_lines`
  and `channel` are never updated: immutable, like `currency` (« the Fresha
  rule »). Both twins read the list (B15.1).
- **Rollback-safe, with one known drift.** An older image reads with
  `SELECT *` / `RETURNING *` and `_toDto` picks named keys, so it ignores the
  columns; its INSERT names its columns, so it leaves them NULL, which reads
  as « before R1 ». No constraint it could trip (the CHECK allows NULL).
  **The drift:** an older image that moves a booking to another
  collaborateur writes `artist_id` and leaves `artist_name_kept` naming the
  previous one; while the new collaborateur is on the roster the live name
  wins, but if they are later removed, that booking's revenue shows under the
  old name. Accepted (a rollback is rare and short); the migration header
  says so.
- **The salon purge** (B0.24) deletes rows whole
  (`postgres_salon_purge_repository.dart:402`): nothing to do.
- **The demo salon.** Its reset wipes the bookings and recreates them
  through `bookManual` (`demo_reset_service.dart:151-157`, `:281-289`), so
  R1's writes cover them with no extra work. **The real gap is its data:**
  every seeded booking is `confirmed`, with one service and no collaborateur.
  A store reviewer opening « Revenus » would see « Pas encore de revenus », an
  « À clôturer » banner and « Sans collaborateur attribué ». Q13 asks whether
  the reset should also seed past completed bookings across two or three
  collaborateurs and several prestations, and an absence.

### 8.2 How a booking knows « app » from « web »

The website's booking BFF (`web/app/api/bookings/route.ts`) adds
`X-Myweli-Channel: web` to its `POST /appointments`. The route reads it,
keeps `web` if and only if the value is exactly `web`, else `app` (the app
sends nothing; builds 0.0.2 neither). The header is client-declared: it only
ever labels a salon's own statistics, is enum-checked, and is never used for
authorisation (T85, §10). **The website ships the header first (R0w)**, so
no website booking is ever stamped `app`.

### 8.3 Reads (R2)

*As built, `revenueRows` returns one `json_agg` document per range (§20.2).*


- `AppointmentRepository.revenueRows(providerId, fromUtc, toUtcExclusive)`
  → the narrow fields the aggregator needs (`id`, `status`,
  `appointmentDate`, `durationMinutes`, `artistId`, `artistNameKept`, `totalPrice`, `currency`,
  `userId`, `channel`, `serviceIds`, `serviceLines`), ordered by
  `appointment_date, id`. Postgres: one `SELECT` on
  `appointments_provider_date_idx`.
- `AppointmentRepository.revenueLedger(providerId, range, status, filters,
  limit, offset)` → a page + its total. **The `serviceId` filter decodes
  both storage forms of `service_ids`**: production stores it as a JSON
  *string* inside `jsonb` (written with `jsonEncode` on a `:jsonb`
  parameter, `postgres_appointment_repository.dart:49`, `:61`; read back by
  `_toDto`, `:214`), so `service_ids ? @sid` alone would match nothing —
  read in production, 4 of 4 rows (§19). The decode is
  `providers.data`'s (`kAppointmentCurrencyBackfill`): nested `CASE`s and
  `pg_input_is_valid`, so an unreadable value is skipped, never cast.
- `AppointmentRepository.hasCompleted(providerId)` → `EXISTS`.
- All three: implemented on both twins with **one contract test run against
  both** (decision 223).

---

## 9. Architecture

### 9.1 Backend

- **Route** `backend/routes/providers/[id]/analytics/revenue/index.dart` and
  `…/revenue/appointments.dart` (thin: principal → `role == provider` →
  parse/validate the query → delegate → shape; 405 for non-GET).
- **`RevenueAnalyticsService`** (`backend/lib/src/analytics/`): membership +
  `finances.view` (`MembershipService.can`), the salon (`ProvidersRepository.byId`
  for its timezone, roster and catalogue), the period resolution
  (`revenue_period.dart`, pure, §3.5), two `revenueRows` reads (current,
  comparison), the fold (`revenue_aggregator.dart`, pure, §3.2–§3.4), the
  labels. No `dart_frog`, no SQL.
- **Why fold in Dart, not `GROUP BY` in SQL.** One definition the in-memory
  twin and Postgres share (the repo's twins have diverged before — B15,
  B16); every rule unit-testable without a database; the dashboard and
  earnings already fold. The cost is bounded by the 366-day cap (§11). If the
  measured p95 misses its budget, the fold moves into SQL behind the same
  service API — the threshold is written in §11, not left to taste.
- **Writes (R1)**: `BookingService.book` / `bookManual` build the lines in
  the loop that already prices them (`booking_service.dart:140-153`,
  `:322-335`) and stamp `channel` and `artistNameKept`;
  `AppointmentLifecycleService.rescheduleByProvider` writes `artistNameKept`
  with `artistId`.

### 9.2 App

`lib/models/revenue_analytics.dart` · `ProServiceInterface` +
`MockProService` + `ApiProService` · **`ProRevenueProvider`** (`SalonScoped`,
holds the query, the request id, the analytics and the ledger pages; replaces
`ProEarningsProvider` on this screen — that one stays for nothing else and is
deleted with the old screen) · `screens/provider/earnings/` rebuilt:
`revenue_screen.dart`, `revenue_detail_screen.dart`,
`revenue_ledger_screen.dart`, widgets in `widgets/pro/revenue/` · routes in
`pro_router.dart` · DI. `reports_analytics_screen.dart` deleted with its
`futureProviderFeatures` arm (Q2).

### 9.3 Website

`components/pro/RevenusClient.tsx` rebuilt; new
`RevenueDetailClient.tsx`, `RevenueLedgerClient.tsx`; pure helpers in
`lib/pro/revenue.ts` (query ⇄ URL, labels, delta formatting, CSV);
`app/pro/(dash)/revenus/{page,collaborateurs/[id],prestations/[id],canaux/[canal],rendez-vous}`.

---

## 10. Security & authz

- **AuthN**: provider access token; the BFF's httpOnly pro cookies on the
  website.
- **AuthZ**: deny by default; `finances.view` on `{id}` for **both**
  endpoints, checked before any read; another salon's id → 403 (the same
  answer as no capability — no existence oracle).
- **Inputs**: every query param validated at the boundary (§7.1); the range
  capped; `pageSize` clamped server-side.
- **Server authority**: every figure, label and date is the server's.
- **PII**: the ledger's client names are **field-gated on `clients.view`**
  (absent without it), on top of `finances.view` for the endpoint; never a
  phone; nothing logged but the route, the status and the duration. The CSV
  export (Q10) covers the breakdown tables only — no client name leaves in a
  file.
- **Threat model** (BACKEND.md §7) — new row **T85**, « Revenue analytics
  (`GET /providers/{id}/analytics/revenue*`) »: **I** — a member without
  `finances.view`, or another salon, reads money; a member with money but
  not `clients.view` reads client names → the two capability checks and
  their REQUIRED negative tests; **D** — a 366-day range
  with a year comparison on a busy salon → the range cap, the measured
  budget (§11), `no-store`; **T** — a forged `X-Myweli-Channel` → it can only
  relabel the salon's own statistics, enum-checked, never used for authz.
  T5 gains « analytics » in its provider-reads list.
  **As built:** T85 landed with R1, scoped to what R1 ships — the header
  and the three columns (their CHECKs, the kept name only with its id,
  immutability, disclosure). R2 extends the same row with the endpoints'
  **I** and **D** and adds T5's « analytics ».

---

## 11. Performance

*Measured on R2 as built: §20.3.*


| Budget | Value | How it is held |
|---|---|---|
| `/analytics/revenue` p95 server-side | **< 500 ms** for 366 days + a year comparison on a salon of **40 bookings a day** (≈ 29 000 rows read); < 200 ms for a month | a DB-gated benchmark test seeds that salon and fails over budget; over it → the fold moves to SQL (§9.1) |
| `/analytics/revenue/appointments` p95 | < 200 ms | `LIMIT/OFFSET` on the index |
| Response size | < 40 KB gzipped for a salon of 50 collaborateurs and 200 prestations | rows are bounded by the salon's roster and catalogue (plus removed ones that sold in either range); the series has ≤ 31 points (days), ≤ 14 (weeks) or ≤ 13 (months) per range (§3.5) |
| App | one request per period change; the ledger paginated; no chart package (APK unchanged); 60 fps scrolling | `ListView.builder`, `const`, plain widgets |
| Website | client component code-split under `/pro`; no chart library | SVG by hand |

---

## 12. Design system & accessibility

### 12.1 New shared pieces (added to SYSTEM.md §11.3 in this PR, built in R3/R4)

- **`KpiGrid` / `KpiTile`** — `_StatBlock` moved out of
  `dashboard_screen.dart` **unchanged** (measured by `TextFit.columns`,
  values in `headlineSmall`), so the Accueil and « Revenus » share it; a tile
  = title · value · `DeltaBadge` · caption. The Accueil's tests stay green
  through the move.
- **`DeltaBadge`** — arrow glyph (`arrow_upward` / `arrow_downward`,
  `iconS`) + signed text; `success` / `error` by the figure's good direction,
  `textSecondary` for « stable »; never colour alone; its semantics sentence
  (§12.3).
- **`ShareBar`** — 4 dp, `primary` on `surfaceVariant`, `radiusPill`,
  `ExcludeSemantics` (the row says the share in words).
- **`BarSeries`** — the « Évolution » chart: bars `primary`; with a
  selection, the selected bar `primary` and the others `borderStrong` (a
  fill change — an outline in `borderFocus` would be black on black); height
  the named constant `BarSeries.height = 160`; **one** semantics node with
  `onIncrease` / `onDecrease` (no per-bar buttons: they would be 10 dp
  targets); and its list form.
- Website twins in `web/components/pro/revenue/` with the same names and
  tokens (closed Tailwind theme; no arbitrary value; `h-chart` added to the
  theme if no existing height token fits).

### 12.2 Tokens

`AppColors` / `AppTextStyles` / `AppTheme` only: `primary` for bars and the
share fill (19.59:1 on white — bars clear 1.4.11's 3:1 with room),
`surfaceVariant` track, `textPrimary` values, `textSecondary` titles,
`textTertiary` captions and footnotes (4.76:1, the floor), `success` /
`error` deltas (8.63 / 9.34:1), `info` banner. No literal colour, size or
duration; the enforcement pins (SYSTEM §20) must not grow.

### 12.3 Accessibility

- **Targets ≥ 48×48**: chips, arrows, the comparison button, the sort
  button, rows, « Voir », « Voir en liste », and the chart as one target
  (§4.6) — no target narrower than 48 dp exists on the screen.
- **Screen readers**: a tile reads « Réalisé : 1 250 000 FCFA, en hausse de
  12 % par rapport à octobre 2026 »; a rate « Taux d'absence : 5,9 %, en
  baisse de 1,2 point »; a row as in §4.7; the period label is a heading
  (level 2) and changes are announced (« Novembre 2026 »).
- **200 % text** at 360 dp: §4.12, pinned.
- **Colour independence**: deltas carry glyph + sign + words; « estimé » is
  a word.
- **Website**: the `DataTable`'s ARIA table, the shared `Tabs`, a labelled
  sort `<select>`, the chart's one focusable element with its live line, a
  visible `:focus-visible` ring, labelled fields, the dialog's focus trap,
  `aria-live` for errors, axe clean.

---

## 13. Testing plan

### 13.1 Backend

- **Period resolution** (pure): every row of §3.5's table; Monday weeks
  across a year end; 29 Feb in both directions; like-for-like on the 1st,
  the 15th and the last day — the comparison's cutoff at the same day offset
  **and** salon wall-clock time (a completed booking at 15:00 on 25 October
  is outside a 14:30 cutoff, one at 14:00 inside); the current range never
  cut; clipping (31 March → 28 Feb); bounds and the 366-day cap; no `date`
  → the salon's today (a test clock just before and after salon midnight).
- **Aggregator** (pure): each figure of §3.2 by status and by « now » —
  « À clôturer » by the **end** (a confirmed three-hour booking that began
  ten minutes ago is « Prévu »; one that ended a minute ago is « À
  clôturer »); a completed booking dated later in the current month counts in
  « Réalisé »; an empty-string `artistId` lands in « Sans collaborateur
  attribué »; salon-time
  boundaries (a booking at 23:30 and at 00:30 salon time in a non-UTC test
  zone); currency groups never summed; shares add up to 1; the lines
  invariant (Σ = `total_price`); duplicates in `service_ids`; §3.4's estimate
  (proportional, all-zero equal split, rounding remainder, a deleted service);
  the labels table of §3.3 row by row; the sort's total order; deltas of
  §3.6 (left to the clients, but the figures they read are tested here).
- **The Accueil equality**: for the current month, `monthRevenue` of
  `/dashboard` = Réalisé + Prévu + À clôturer of `/analytics/revenue`
  (single currency).
- **Repository**: `revenueRows`, `revenueLedger`, `hasCompleted` — one
  contract on both twins + DB-gated on Postgres (range ends exclusive,
  ordering, filters, page totals, the ledger's `asOf` window).
- **The ledger's client name**: an online booking (`clientName` null) shows
  its `salon_clients` name; an erased client has none; a caller without
  `clients.view` gets none (the field absent — tested with a capability
  override in the test's membership double); the lookup is one batched read
  per page, never `enrichForProvider`.
- **Writes (R1)**: `book` / `bookManual` store lines, `artistNameKept`,
  `channel` — a Postgres round-trip that fails before R1 (the B14.1 lesson:
  a twin keeps what Postgres drops); reassignment writes `artistNameKept`; `artistNameKept` without `artistId` refused on both twins; an empty `artistId` stored as `null`; the
  channel header (`web` exact → `web`; `WEB`, `x`, absent → `app`).
- **Handlers**: 200 per period; 400 for each malformed param and
  `range_too_long`; 401; **403 for Manager, Réception, Collaborateur, another
  salon's owner, a revoked member**; 405; `Cache-Control`.
- **Contract**: responses validate against `RevenueAnalytics` /
  `RevenueLedgerPage`.
- **Benchmark** (DB-gated): §11's salon, over budget → fail.
- **Mutations to watch red** (each named in the PR): drop `confirmed` from
  « Prévu »'s « now or later »; count `pending` as « Prévu »; sum two
  currencies; date a booking in UTC instead of salon time; compare the full
  previous month while in progress; give the rounding remainder to the first
  line; label a removed artist « active »; skip `finances.view` on the
  ledger; accept `channel=Web`; reorder rows on equal amounts by map order;
  date « À clôturer » by the start instead of the end; return
  `clientDisplayName` without `clients.view`; cut the current range at now.

### 13.2 App

- Model `fromJson` round-trips the contract's example.
- `ProRevenueProvider`: period stepping, request-id drop of a late answer,
  salon switch, 403 → the refused state, error → retry same period.
- Widget tests: every state of §4.11; each label of §3.3; « estimé »;
  the currency switcher; the « À clôturer » banner's link; Accueil cards
  tappable only with `finances.view` (and still absent for the three other
  roles — `dashboard_role_test`).
- a11y: `layout_test` subjects (« Revenus » success, detail, ledger) at
  360/375/390 × 1×/2×; `expectNoMidWordBreak`; the semantics sentences;
  `androidTapTargetGuideline` on the whole screen, chart included (one node,
  its increase/decrease actions moving the selection); the selected bar told
  apart by fill.
- `KpiGrid`'s move: the Accueil's `dashboard_role_test`, `layout_test` and
  its goldens unchanged.
- « Dates… »: two `myweli_date_picker` fields, the field errors under « Au »,
  no Material picker (the existing pin that forbids them stays green).
- **Goldens** (authored on Linux, `gh workflow run goldens.yml`): success,
  empty salon, empty period, refused, detail, ledger, 200 %.
- The old screen's wording tests (`pro_earnings_wording_test.dart`) move
  to the new screen's words; « encaiss » stays forbidden.

### 13.3 Website

- Unit (Vitest): URL ⇄ query (malformed → current month), labels, deltas,
  CSV (separator `;`, UTF-8 BOM for Excel, amounts as integers, one file per
  table, the filename « revenus-collaborateurs-2026-11.csv »).
- RTL: states, roles (owner sees; the three others get the refused state
  from a 403), the sort `<select>`, the chart's keys and live line.
- e2e (Playwright, the stub): owner → `/pro/revenus` → a collaborateur →
  the ledger → a booking; ← / → stepping; Back keeps the period; axe on each
  page. The stub gains the two endpoints (ports per the e2e memory).
- `pro-revenus-wording.test.tsx` moves to the new words.

---

## 14. The PRs, in order (Q12)

Each merge, each production read and each deploy waits for the owner's word.

| # | PR | Surface | Depends on | Ships to users when |
|---|---|---|---|---|
| **R0w** | The booking BFF sends `X-Myweli-Channel: web` | website | — | its merge (Vercel) |
| **R1** | Migration 0052 (three nullable columns with their CHECKs, no backfill), the writes, the twins' key list, the header read, an empty `artistId` stored as `null`, OpenAPI's `Appointment` gains the three stored keys and `POST /appointments` the header, `schema.ts` regenerated, T85 (the header and the columns) | backend (+ `web/lib/api/schema.ts`) | R0w live | its deploy (`deploy-backend.yml`) |
| **R2** | The two endpoints, the period resolver, the aggregator, the repo reads + contract, the batched client-name lookup, OpenAPI, T85 extended + T5, `schema.ts` regenerated; the demo reset's richer agenda if Q13 says yes | backend (+ `web/lib/api/schema.ts`) | R1 | its deploy |
| **R3** | « Revenus » rebuilt, details, ledger, Accueil taps, shared widgets, goldens; placeholder deleted | app | R2 deployed | the next Pro build in the stores |
| **R4** | `/pro/revenus` rebuilt, details, ledger, CSV | website | R2 deployed | its merge |

Plus a records PR after each deploy, as usual. R3 and R4 are independent of
each other once R2 is deployed.

**Production reads** (read-only, each on the owner's yes): before R1, the
count of bookings by number of services and the count referencing a service
or a collaborateur that no longer exists — how many rows will read
« estimé » or « Ancien collaborateur » (**done 2026-11-25, §19**). After R1,
a count of new bookings with lines, channel and name (**R1 deployed
2026-11-26; the count waits until real bookings exist from the website, the
app and a salon**).

**Store assets**: App Store screenshot 8 (« Revenus ») and the preview film's
scene S4 already show an older card (provider-earnings.md §12); this screen
changes more. Reshooting is the owner's call at the next submission — not
part of this work.

---

## 15. Definition of done (per PR)

- [ ] `dart format` · `dart analyze --fatal-infos --fatal-warnings` = 0 ·
      `flutter analyze` = 0 · `tsc` · `lint` · `next build`.
- [ ] Tests of §13 for its surface, red first where a defect is claimed;
      the mutations of §13.1 watched red and named in the PR.
- [ ] OpenAPI updated with the code; `schema.ts` regenerated, no drift.
- [ ] T85 written (R1) and extended + T5 updated (R2); SYSTEM.md §11.3 entries marked built (R3/R4).
- [ ] Goldens from Linux, each changed PNG opened.
- [ ] This spec cross-linked from the routes, the service, the screens and
      the contract; its status moved.
- [ ] A roadmap entry file in French; BACKLOG updated.
- [ ] Feature branch, PR, CI green; commits authored as the owner, no
      Claude attribution.
- [ ] After merge: `main`'s tree = the PR head's tree; `main`'s CI green.
- [ ] Before any « done »: `myweli-verification-guardrails`.

---

## 16. Found while reading (not fixed here)

1. **`/dashboard` and `/earnings` add amounts across currencies.**
   `todayRevenue`/`weekRevenue`/`monthRevenue`
   (`provider_dashboard_service.dart:107-109`) and `totalEarnings`
   (`provider_earnings_service.dart:54`) sum `totalPrice` whatever each
   booking's currency, and label the sum with the salon's. Unreachable
   today: one currency exists, and decision 191's tripwire guards a salon's
   currency change. The analytics endpoint groups correctly from the start;
   the two old endpoints get the same treatment with the second market,
   where decision 191 already points. Recommended: a line in BACKLOG under
   batch 14's follow-ups, no work now.
2. **`/dashboard` reads the salon's whole history on every Accueil open**
   (`provider_dashboard_service.dart:40`, `listForProvider` without a
   range). Fine at today's volumes; a busy salon's Accueil will slow with
   time. R2's `revenueRows` gives it a ranged read for free; recommended as
   a follow-up, measured first.
3. **PRD FR-PRO-EARN-001** promises « deposits collected, balance
   expected » on the earnings screen; neither exists, and with screenshot
   deposits MyWeli can only know a proof was sent, not that money arrived.
   Recommended: reword the requirement when Q1's PRD edit is made.
4. **`bookManual` stores any `artistId` it is given** (found building R1).
   The client's `book` refuses an id not on the roster (the slot engine's
   `invalid_artist`) and the journal's drag does too (T42), but the salon's
   own « Ajouter un rendez-vous » never checks: an id from another salon,
   or a stale one, is stored as sent. Bounded to the salon's own bookings
   (the route requires `journal.manage.all` on that salon), and R1 keeps no
   name for it (`artistNameKept` null), so its revenue reads under
   « Ancien collaborateur ». Recommended: refuse it with `invalid_artist`,
   as the other two paths do, in its own small PR with a test.

---

## 17. Open questions for the owner

**Q1–Q13 are decisions 237–249** in `docs/BACKLOG.md` §2 (batch 17).
**✅ Answered 2026-11-25: « Approve as recommended »** — all thirteen, each
as its recommendation below says.
The highest number on `main` and in the open PRs on 2026-11-25 was 236
(A4's); no other worktree held a higher one.

1. **Scope.** Build the revenue part of the « reports & analytics » V3 item
   (FR-PRO-OPS-004) now, with the PRD and MODULES §9–§10 updated to say so?
   *Recommended: yes — it is what you asked for; fill rate and client
   analytics stay later.*
2. **Where it lives.** Rebuild « Revenus » (app and website) into this
   analytics — one money screen — make the two Accueil « Revenus prévus »
   cards open it, and delete the flag-hidden `reports_analytics_screen.dart`?
   *Recommended: yes. The alternative, a separate « Statistiques » screen
   next to « Revenus », gives two screens with overlapping totals — the
   « one word, two numbers » problem of 2026-10-14.*
3. **Who sees it.** Owner only (`finances.view`), as today? Or should a
   Collaborateur see their own figures in « Ma journée »? *Recommended: owner
   only now; a Collaborateur's own figures later, from salon feedback, as
   access.md §11 question 4 says.*
4. **The rule.** « Réalisé » = completed bookings only (the « Total
   réalisé » of today), confirmed ones shown apart as « Prévu », past
   confirmed ones nobody closed shown as « À clôturer » with a link to close
   them? *Recommended: yes.*
5. **Prices per prestation.** Keep each new booking's lines (prestation,
   price at booking) from R1 on, and **estimate** older bookings at read
   time from today's prices, marked « estimé », rather than rewriting
   production rows? *Recommended: yes (no production write; the estimate is
   said, and exact for every single-prestation booking).*
6. **A collaborateur who leaves.** Keep the collaborateur's name on each
   booking, so their past revenue keeps their name after they are removed
   from the team? *Recommended: yes.*
7. **Channel.** Record each new booking's channel — Application MyWeli,
   Site MyWeli, Ajouté par le salon — with older online bookings shown as
   « En ligne (avant le suivi) »? *Recommended: yes, the website's header
   first (R0w).*
8. **Periods and comparison.** Jour · Semaine · Mois · Année · Dates (≤ 366
   jours), ‹ › to step; compared by default with the previous period, or the
   same period last year, or nothing; while a period is in progress, the
   comparison cut at the same point of its own period (November so far
   against 1 October → 25 October 14:30); and **« Tout » (all time), which
   both surfaces offer today, removed** — « Année » and « Dates » replace
   it? *Recommended: yes to all.*
9. **Par catégorie and à domicile.** Not possible now: prestations have no
   category and no booking records à domicile. Defer « par catégorie » to a
   catalogue spec that gives each prestation one of the Ivorian categories,
   and « à domicile » to the V2 home-service module? *Recommended: yes.*
10. **Export.** « Exporter (CSV) » of each breakdown table on the website
    (opens in Excel; no client names in the file), nothing on the app for
    now? *Recommended: yes.*
11. **Offer.** Available on every offer, trial included — no gate by tier?
    *Recommended: yes; « Statistiques » is already in the Pro offer's list.*
12. **Order of work.** R0w → R1 (production read before, deploy on your
    word) → R2 (deploy on your word) → R3 and R4; each merge, read and
    deploy on your word? *Recommended: yes.*
13. **The demo salon.** Its weekly reset seeds only confirmed bookings, with
    no collaborateur, so the store reviewer's account would open « Revenus »
    on « Pas encore de revenus ». Should the reset also seed past completed
    bookings across two or three collaborateurs and several prestations, and
    one absence, in R2? *Recommended: yes — the reviewer then sees the
    screen the store listing describes.*

---

## 18. Review — an independent reader, told to refute it against the code

One reader, given the spec and the repository and asked to refute it, read
106 places in the code and returned 20 findings: 3 blockers, 12 should-fix,
5 nits. Each was re-read in the code before it was folded in; all 20 held.
What changed:

| # | Finding | Now |
|---|---|---|
| 1 | **Blocker.** The ledger read `clientName`, which `book` writes `null` for every online booking (`booking_service.dart:260`): every online row would have read « Client supprimé » | `clientDisplayName` from `salon_clients`, the journal's resolution, batched per page (§7.2, §4.9) |
| 2 | **Blocker.** `artistName` already exists as the live roster name on consumer reads (`appointment_enrichment.dart:107`, OpenAPI); a stored `artistName` would mean two things | its own key, `artistNameKept` (column `artist_name_kept`); the three keys returned by `_toDto` and documented (§8.1) |
| 3 | **Blocker.** « the current figures only run to now » contradicted « Prévu », the Accueil equality, and a completed booking dated later in the month (« Terminé » has no time check, `pro_appointment_service.dart:56-63`); 1–25 vs 1–25 compared part of a day with a whole one | the current range is always whole; only the comparison is cut, at the same day offset and wall-clock time (§3.2, §3.5) |
| 4 | The demo reset was misdescribed: it recreates bookings through `bookManual`, so R1 covers them; the gap is its data (all confirmed, no collaborateur) | §8.1 corrected; Q13 |
| 5 | « the platform date-range picker » — the app has no Material picker, on purpose | two `myweli_date_picker` fields (§4.3) |
| 6 | A `borderFocus` outline on a `primary` bar is black on black; 10 dp bars as buttons fail the tap-target guideline | selection by fill; one semantics node with increase/decrease; the website's chart one focusable element (§4.6, §5.1, §12) |
| 7 | `_StatBlock` has no 1.3× rule — it measures; its values are `headlineSmall` | `KpiGrid` = `_StatBlock` moved unchanged (§4.5, §12.1, SYSTEM §11.3) |
| 8 | Removing « Tout » was not said | §3.5 and Q8 say it |
| 9 | The shared `Tabs` is deliberately not a tablist; `DataTable` has no sorting or paging | the shared `Tabs`, a « Trier par » `<select>`, « Afficher plus » (§5.1) |
| 10 | « the server's today » cannot hold with `date` required | `date` optional, defaulting to the salon's today; the ledger takes the figures' `asOf` (§3.5, §7.2) |
| 11 | Client names on `finances.view` alone | field-gated on `clients.view`; no names in the CSV (§7.2, §10, Q10) |
| 12 | The updatable key needs more than one line | the `SET` branch, the type check, « only with `artistId` », the seven keys (§8.1) |
| 13 | An older image's reassignment leaves the kept name stale | written down as the one known drift (§8.1) |
| 14 | Empty-string `artistId`s exist | read as unassigned; stored as `null` from R1 (§2.1, §3.3, §8.1) |
| 15 | « À clôturer » by the start counts a booking under way | by the end, start + `durationMinutes` (§3.2) |
| 16–20 | access.md section number; the detail route is `/pro/appointment/:id?salon=`; `StatusBanner` has no action slot; the endpoints answer only `forbidden` (a revoked member is caught by `ProAccessGuard`); five line numbers; the placeholder is reached by no route | each corrected in place |

Checked and correct by the same reader: the `X-Myweli-Channel` header
reaches the backend (the BFF passes route headers, the Cloudflare Worker
forwards all headers); only two paths create bookings and one changes the
collaborateur; erasure keeps `user_id`; the purge deletes rows whole;
migration 0051 (taken by A4-api the same day — R1 is 0052), threat T85 and decision 237 were the next free numbers; only
the owner preset has `finances.view`; the Pro offer lists « Statistiques ».

---

## 19. The production read before R1 (2026-11-25)

On the owner's « Yes, read it » (decision 248's read).

**Method** — the one batch 14 and B16.1 used:
- the Cloud SQL Auth Proxy on loopback, stopped after (no listener left on
  its port);
- the database URL held in a shell variable only, never printed or written;
- the session opened with `default_transaction_read_only=on` (read back as
  `on`) and the query inside `BEGIN READ ONLY … ROLLBACK`;
- the probe write `UPDATE appointments SET status = status WHERE false`
  refused (« cannot execute UPDATE in a read-only transaction »);
- aggregates only: no id, no name, no single booking's amount.

The query first ran on a throwaway local Postgres 16 holding one row per
case. The cases: both storage forms of the salon document and of
`service_ids`, an unreadable document and an unreadable `service_ids`, a
deleted service, prices changed since booking, duplicates, an artist null,
empty, on the roster and not on it, a manual and an online booking, two
currencies. It reported each case as expected. There the probe write passed
without the setting and was refused with it. The container was then removed.

**A defect in the read itself, found by its own numbers.** The first run in
production (12:43 UTC) classed all four bookings as having no readable
`service_ids`. The query only read a JSON array, and production stores
`service_ids` as a JSON **string** inside `jsonb` (§8.3). It was confirmed
in the code, then the query was fixed to decode both forms. The fixed query
was re-tested on the throwaway database with both forms. Then the same read
ran again, by the same method, at 12:44:07–12:44:08 UTC. The figures below
are that run's.

| | Production, 2026-11-25 12:44 UTC |
|---|---|
| Bookings | **4**, in **1** salon |
| Status | 4 `confirmed`; **0 `completed`** anywhere |
| Channel | 4 entered by the salon (`user_id = 'manual'`); 0 online |
| Services per booking | 4 with one service; 0 with two or more |
| A service no longer in the catalogue | 0 |
| Collaborateur | 4 without one (`artist_id` null); 0 empty, 0 off the roster |
| Currency | 4 XOF |
| `service_ids` storage | 4 of 4 a JSON string |
| Salon documents unreadable | 0 |

**What it means.**
- **No booking in production will read « estimé » or « Ancien
  collaborateur » today.** There is no completed booking, every booking has
  one service (exact, §3.4), and none has a collaborateur to lose.
- Every booking made after R1's deploy carries its lines. So the estimate
  only ever covers the bookings made until then.
- The four look like the demo salon's regenerated agenda: four, confirmed,
  entered through `bookManual`, no collaborateur (B16.2 §1; decision 249).
  This is **INFERRED**: the read takes no salon id.
- **Two consequences, folded in above:**
  - §8.3: the ledger's `serviceId` filter decodes both forms;
  - §8.1: `service_lines` is written as a real array, with a test on its
    stored type, so the new column does not repeat `service_ids`' encoding.
- **One precision**, §3.4: a single-service line is exact and is not marked
  `estimated`.

---

## 20. R2 as built (2026-11-26)

On the owner's « Oui, démarrer R2 » and « Yes, and read the demo »
(2026-11-26). PR #884, branch `feat/backend-revenue-r2-endpoints`.

**Where it lives.**
- `backend/lib/src/analytics/revenue_period.dart` — the calendar (§3.5),
  pure;
- `…/revenue_aggregator.dart` — the fold (§3.2–§3.4), pure;
- `…/revenue_analytics_service.dart` — the gate, the reads, the ledger rows;
- `…/revenue_query_parser.dart` — the boundary (every query parameter);
- `backend/routes/providers/[id]/analytics/revenue/{index,appointments}.dart`;
- `AppointmentRepository.revenueRows` / `revenueLedger` / `hasCompleted` and
  `ClientsRepository.displayNamesFor` on both twins, each under a contract
  run on both (decision 223);
- OpenAPI: the two paths, eight `Revenue*` parameters, ten schemas;
  `web/lib/api/schema.ts` regenerated.

### 20.1 Precisions to §3 and §7 (nothing reversed)

1. **Bounds apply to the dates sent** (`date`, `from`, `to`): each on or
   after 2020-01-01 and at most the salon's today + 366 days. A period around
   a valid date may reach past them (the week of 1 January 2020 starts on
   30 December 2019): harmless, and the only reading that lets « Semaine »
   step onto that day.
2. **The contract sends everything, nullable rather than absent:**
   `filters` and all five `comparison` fields are required (null when they
   do not apply); `filters.state` uses the rows' enum; the ledger page also
   echoes the `asOf` it measured against; a ledger row's `status` is the
   stored one (`completed`, `confirmed`, `noShow`, `cancelled`).
3. **`estimated` is only where an estimate can be.** « Réalisé », the rows by
   collaborateur and by canal are built on each booking's `totalPrice`, which
   is exact; only a prestation's amount (the rows by prestation, the figures
   and ledger under a `serviceId` filter) can rest on an estimated line. A
   row's flag covers its current or its previous amount.
4. **Shares** are basis points by largest remainder: the shares of one axis
   add up to exactly 10 000 / 10 000.
5. **The average ticket** is rounded to the currency's unit.
6. **Groups**: the salon's own currency first, then by code.
7. **The estimate's remainder** goes to the largest line, the first of equals
   (§3.4 step 3).
8. **A removed collaborateur or prestation** is labelled with the name kept
   on its **latest** booking, in either range.
9. **Canal rows** carry no label (the clients name them); `online` is
   `state: legacy`.
10. **A salon that vanished** after the gate answers 404; unreachable for a
    member, and the gate's 403 comes first for anyone else.

### 20.2 The read (§8.3), as built

`revenueRows` returns **one `json_agg` document per range**, decoded at once,
instead of one driver row per booking. Measured on the benchmark salon
(14 600 rows a year, Postgres 16): the driver's per-cell decoding was most of
the time — 110–130 ms per range for the twelve columns, about 75 ms as one
document. Same keys, same order, same rows as the in-memory twin;
`service_ids` decoded in SQL (both storage forms; an unreadable value reads
as null, as in the ledger's filter). The ledger page (≤ 50 rows) keeps
ordinary rows.

### 20.3 The budget (§11), measured

`backend/test/db/revenue_analytics_budget_test.dart` — its own database, the
§11 salon (40 bookings a day over two years, `service_ids` in production's
string form, half the rows with kept lines and half estimated, every channel),
p95 of 20 timed calls after 2 untimed:

| Read | First draft (one driver row per booking) | As built | Budget |
|---|---|---|---|
| « Année » + the year before (~29 000 rows) | ≈ 420 ms, once over 500 | **≈ 165 ms** (≈ 280 with the two ranges read one after the other, ≈ 240 at once; **430 in CI** before the dates below, **331 in CI** after) | 500 ms |
| « Mois » | ≈ 45 ms | **≈ 14 ms** | 200 ms |
| A ledger page, filtered by prestation | ≈ 20 ms | **≈ 16 ms** | 200 ms |

Measured on a Mac against Postgres in Docker; CI measures it again on every
run, and the test fails over budget. **CI on the merged head** (`53ab3ab1`,
the runner's Postgres 16, read in the job's log): « Année » + the year before
**331 ms**, « Mois » 25 ms, a ledger page 30 ms: about twice the Mac's
figures, and 169 ms under the budget. **The two ranges are read at once** — two
connections, not more: an instance has four (`kMaxConnectionsPerInstance`),
so the cheap « ever completed » `EXISTS` runs after them.

**Dates.** CI measured the first pushed head at **430 ms** — under the budget,
with little room. Half of the fold was `DateTime.parse` (~24 ms of ~49 for
29 000 rows) and the read rebuilt and reformatted every date in Dart. Now
Postgres writes the ISO string itself (`to_char(… AT TIME ZONE 'UTC', …)`;
a test runs it in a Tokyo session) and the fold reads that one shape digit
by digit (`parseRevenueInstant`; any other shape goes to `DateTime.parse`).
The fold went from ~49 to ~27 ms, the whole answer from ~240 to ~165 ms.
The fold itself is now about 27 ms of the 165; if a busier salon ever crosses the line, the next step is still §9.1's
(the fold into SQL behind the same service API).

### 20.4 Beyond §13.1's list

- **The ledger lists exactly what the figures count**: for every figure and
  six filters, the ledger's pages add up to the figure's count and amount.
  The figures fold in Dart and the ledger filters in SQL — two codes, one
  definition, held together by this test (both twins).
- `service_ids` in its three forms on Postgres (an array, a JSON string,
  unreadable text): the filter reads the first two and skips the third.

### 20.5 The demo salon's agenda (decision 249, Q13)

**The read, 2026-11-26 14:59 UTC** (on the owner's « Yes, and read the
demo »; read-only session, the write probe refused with 25006; the script run
first on a throwaway Postgres; counts only):
- the demo salon has **no collaborateur**, live or in its snapshot;
- 5 active prestations, none bound to a collaborateur;
- 4 confirmed bookings.

**As built** (`DemoResetService._regenerateAgenda`, `kDemoAgenda`): each reset
enters 16 bookings through `bookManual`, relative to the reset:
- 12 completed over the last eight weeks, on every prestation in turn, one
  with two prestations;
- 1 absence;
- yesterday's booking left confirmed: the « À clôturer » banner;
- 2 ahead.

The past ones are closed through the Pro app's own path,
`ProAppointmentService.complete` / `noShow`, which also touches the client
card's last visit. Collaborateurs: the salon's own in turn, every fourth
booking unassigned; with none on the roster, every booking is unassigned.

**So, until the owner acts, « Par collaborateur » on the demo shows one row,
« Sans collaborateur attribué ».** Adding two or three collaborateurs is the
owner's step: on the demo account in the app, **then a new capture**
(`POST /admin/demo/snapshot`) — the reset restores the snapshot's `artists`,
so collaborateurs added without a capture are removed at the next reset.

Early in a month, « Mois » can show no completed booking yet: the agenda's
latest is three days back. « Semaine », « Année » and « Dates » still show
figures.

### 20.6 Mutations watched red (on committed code)

Each applied alone, its target tests run, the file restored; each turned the
named test red. A no-op edit (the control) stayed green.

| # | Mutation | Red on |
|---|---|---|
| 1 | drop `confirmed` from « Prévu » | « a booking that ends exactly now is still « Prévu » », the three-hour braid |
| 2 | count `pending` as « Prévu » | « pending: from now on counts » |
| 3 | sum two currencies | « two currencies → two groups », « a currency met only in the comparison » |
| 4 | date the series in UTC, not salon time | « 23:30 and 00:30 salon time land on their SALON days » |
| 5 | compare the full previous month while in progress | the period's like-for-like tests; the service's « 25 October 14:00 / 15:00 » |
| 6 | give the rounding remainder to the first line | « the remainder to the LARGEST line » |
| 7 | label a removed artist « active » | « the labels table », « an unknown id » |
| 8 | skip `finances.view` on the ledger | « deny by default, on BOTH endpoints » (each role, revoked), « another salon → 403 on both » |
| 9 | accept `channel=Web` | « each malformed parameter → 400 » |
| 10 | order equal amounts by arrival | « the sort is a total order » |
| 11 | date « À clôturer » by the start | the braid test, and « the ledger lists exactly what the figures count » |
| 12 | return `clientDisplayName` without `clients.view` | « without clients.view: the field is ABSENT » |
| 13 | cut the current range at now | the period's « never cut at now », the Accueil equality, the like-for-like service test |
| 14 | skip `finances.view` on the figures | the same role tests as 8 |
| 15 | the in-memory ledger's « toClose » by the start | the twin contract's « by the END against asOf » |
| 16 | the same in Postgres's SQL | the same contract, on Postgres |
| 17 | Postgres's prestation filter on raw `service_ids` | « reads a jsonb array and a JSON string », the contract's filters |
| 18 | `revenueRows` returns `service_ids` undecoded | the contract's narrow-keys test |
| 19 | the ledger's total = the page's length | « the total counts every match » |
| 20 | `displayNamesFor` across salons (Postgres) | « by user id and by phone, this salon only » |
| 21 | the demo agenda leaves its past bookings open | « past bookings closed as the app closes them », « the owner's « Revenus » then has figures » |
| 22 | an estimated line not marked | the three `estimated` tests |
| 23 | the like-for-like cut at midnight, not the wall-clock time | the period's and the service's like-for-like tests |
| 24 | the fast date reader swaps month and day | « the fast path agrees with DateTime.parse », the series tests |
| 25 | `to_char` without `AT TIME ZONE 'UTC'` | « the start is UTC whatever the session's zone » |

Three first attempts proved nothing and were redone: two did not apply
(the formatter had reflowed the line), one broke the build instead of a test.

---

## 21. R3 as built (2026-11-27)

On the owner's « Oui, construire R3 » (2026-11-27), to the plan approved
with it. PR #893, branch `feat/pro-revenue-r3-app`, one PR (Q12).

**Where it lives** (`mobile/`):
- `lib/models/revenue_analytics.dart` — `RevenueQuery` and the answers,
  read field for field and strictly (a body without its parts is
  `unreadable`, never a screen of zeros; an unknown enum value too);
- `lib/core/utils/revenue_periods.dart` — the period bar's calendar, stepped
  from the server's answer (§3.5), the titles, the comparison's words; pure;
- `lib/core/utils/revenue_wording.dart` — §3.3's labels, §3.6's deltas,
  §4.13's counts and the footnotes; pure;
- `ProServiceInterface.getRevenueAnalytics` / `getRevenueLedger` on the API
  service and the mock — `MockRevenueWorld` (`services/mock/mock_revenue.dart`)
  folds a deterministic history by §3's rules;
- `lib/providers/pro_revenue_provider.dart` — one view per screen, keyed;
- `lib/widgets/pro/revenue/` — `KpiGrid` / `KpiTile`, `DeltaBadge`,
  `ShareBar`, `BarSeries` (+ `BarSeriesList`), `RevenueLedgerTile`;
- `lib/screens/provider/earnings/` — `revenue_screen.dart` (« Revenus » and
  the page its details share), `revenue_detail_screen.dart`,
  `revenue_ledger_screen.dart`, `revenue_sheets.dart`;
- the routes of §4.1 in `pro_router.dart`; the Accueil on `KpiGrid`.

**Deleted:** `earnings_screen.dart` (with `EarningsTotal`),
`pro_earnings_provider.dart`, `reports_analytics_screen.dart` (Q2) and their
tests (`earnings_total_fit_test`, `pro_earnings_wording_test`).
`getEarnings` stays: the salon export reads it.

### 21.1 Precisions to §4 (nothing reversed)

1. **A detail's bar names the kind of row** — « Collaborateur »,
   « Prestation », « Canal » — and **the row's name is the page's heading**
   (level 2), which wraps. §4.8 said « Title = the row's label »; an app-bar
   title has one line and no wrap (SYSTEM §13.3, A15: « a title is a label,
   not a sentence »), and `layout_test` failed on « Prestation supprimée » at
   200 %. The name rides with the link (`libelle`), so it shows at once.
2. **The period chips and the ledger's filter chips wrap** instead of
   scrolling sideways: at the default text size, on 360–390 dp, « Dates… »
   and « Annulés » sat past the edge. Found by a test whose tap missed.
3. **`KpiTile` keeps the Accueil's card** (a `bodySmall` title, an optional
   glyph), where §4.5 wrote `bodyMedium` — the precision approved with the
   plan. The Accueil renders as before.
4. **`EarningsTotal` left with the old screen** (the shrinking headline,
   B7.10's owner exception): the grid measures every figure and goes one
   tile per row when one would not fit.
5. **The latest five bookings** under « Revenus » are a second, small
   request (`pageSize` 5), sent after the figures land and only when
   something was completed in the period. A period change is still one
   request for the figures (§11).
6. **The currency segments follow the server's order** (the salon's own
   first, §20.1 item 6), not « the largest Réalisé first »: two currencies'
   amounts cannot be compared to sort them.
7. **« Estimé »'s footnote shows where « estimé » is printed**: the figures,
   or a row of the tab on screen.
8. **A salon with no completed booking ever** still sees, above « Pas encore
   de revenus », the « À clôturer » banner and « Prévu » when bookings are
   coming (the demo salon's state before its first « Terminé »).
9. **The comparison's words**: « 1er – 25 oct. 2026, même avancement » while
   in progress; « octobre 2026 » for a whole month; « 2025 » for a whole
   year; else the range. A delta's sentence ends « par rapport à … » (« à la
   période … » before a range).
10. **The one « encaiss » allowed is the footnote's negation**, « MyWeli
    n'encaisse rien » (§4.10's text). The wording test forbids « encaissé »,
    « encaissement », « paiements reçus », « chiffre d'affaires » on every
    tab, and any other « encaiss ».
11. **A ledger link's `asOf` older than 23 hours is dropped** (the server
    refuses one older than 24) and the server's now is asked instead.
12. **The mock's latency is the house's `mockDelay`** (300 ms), on which the
    tests settle — not 300–900 ms.
13. **A refusal shows no period bar**: nothing on it could succeed. Found
    looking at the refusal's golden, where the bar sat with an empty title
    and two dead arrows.
14. **The first load is titled at once** (« Novembre 2026 ») from the
    salon's today by the phone's clock — for the title only, which the
    answer replaces; the query still asks the server's today (§3.5). Found
    on the same golden.

### 21.2 Tests (§13.2)

- `test/unit/revenue_analytics_test.dart` — the model on the contract's
  shapes (strict), the query ⇄ route, the calendar (‹ › by kind, custom
  ranges, 2020, today + 366, the anchor), the titles, §3.6's deltas, §3.3's
  labels row by row, the mock's fold (the ledger lists what the figures
  count, shares add up to 1, two currencies, the server's codes).
- `test/unit/pro_revenue_provider_test.dart` — the old figures leave at
  once, a late answer is dropped, one view per screen, a salon switch, 403
  refused (no retry), « Réessayer » asks the same period, the ledger's pages.
- `test/unit/pro_late_answers_test.dart` — `ProRevenueProvider` in the
  salon-switch guard, `load` and `loadLedger`, answered and thrown.
- `test/widget/pro_revenue_screen_test.dart` — every state of §4.11, the
  labels on each tab, « estimé », the banner's « Voir » (status, `asOf`,
  reload on return), the period bar (the provisional title while the answer
  is held), « Comparé à », « Dates… » (MyWeli's picker, the error under
  « Au », no Material picker), a row's detail and its `none`, the currency
  segments, the semantics sentences, the chart's one node, the ledger.
- `test/widget/pro_revenue_wording_test.dart` — the real mock world, every
  tab: no payment words.
- `test/widget/dashboard_role_test.dart` — each « Revenus prévus » card opens
  its period; the count cards are not buttons; the three other roles still
  have no money card.
- `test/a11y/layout_test.dart` — « Revenus », a detail and the ledger at
  360/375/390 × 1×/2× with seven- and eight-digit amounts: no truncation,
  crush, clip or broken token, the bar title whole, `androidTapTargetGuideline`
  (the chart one target); `test/a11y/vertical_fit_test.dart` — the empty
  salon on the floor phone.
- `test/golden/pro_screens_golden_test.dart` — `pro_revenus`,
  `pro_revenus_vide`, `pro_revenus_periode_vide`, `pro_revenus_refuse`,
  `pro_revenus_detail`, `pro_revenus_registre`, `pro_revenus_w360_x2`,
  authored on Linux; `pro_earnings*.png` removed.
- `test/unit/revenue_r2_answers_test.dart` — **the model on the R2 server's
  own answers** (`test/support/revenue_r2/`): month, week, year, a custom
  range, a prestation's detail and two ledger pages, answered on 2026-11-27
  by `main`'s backend (`dart_frog build`) on a throwaway local Postgres
  holding a demo salon with three collaborateurs and the agenda the real
  weekly reset generates. Nothing from production.

### 21.3 In the simulator, on the real endpoints (2026-11-27)

The Pro app (debug, `USE_API_BACKEND=true`, `API_BASE_URL` the local
server) on an iPhone 17 Pro simulator, signed in as the demo account
through the demo seam (a local code):
- the Accueil read « Ce mois · 100 000 FCFA · Revenus prévus »; its card
  opened « Revenus » on « Mois »;
- « Novembre 2026 (en cours) », « Comparé à : 1er – 27 oct. 2026, même
  avancement », « 1 rendez-vous passé à clôturer », Réalisé 70 000 FCFA,
  7 terminés, taux d'absence 12,5 %, Prévu 20 000 FCFA; the three
  collaborateurs and « Sans collaborateur attribué » under « Répartition »;
- a collaborateur's detail: « Collaborateur » in the bar, « Adjoua K. » as
  the heading, her figures;
- « Voir » → « À clôturer » listed the one booking; opened, marked
  « Terminé »; back on « Revenus »: no banner, Réalisé 80 000 FCFA,
  8 terminés — and 80 000 + 20 000 « Prévu » = the Accueil's 100 000
  (§3.2's equality).

**One thing read there and traced, not a defect:** the ledger's rows read
« Client » where the booking's detail reads the typed name. The local
script built its `BookingService` without the clients service, so no client
card was written; in production `bookManual` records the card with the
typed name (`ClientsService.recordBooking`, `displayName: clientName`), and
the ledger shows it. **Inferred from the code**, not read on the demo salon.

The server was stopped and the database container removed after.

### 21.4 Mutations watched red (on committed code)

Each applied alone, its target tests run, the file restored and read back
clean. A no-op edit (the control) stayed green.

| # | Mutation | Red on |
|---|---|---|
| 1 | a late answer kept (the request id dropped) | « a late answer is dropped », the late-answers guard |
| 2 | a 403 read as a failure | « 403: refused, no error to retry », the screen's 403 |
| 3 | a period change keeps the old figures | « a load empties the view first » |
| 4 | ‹ on a month stays on it | « ‹ and › one unit, by kind » |
| 5 | another kind always anchored on `from` | « another kind keeps the anchor », the period bar |
| 6 | no « stable » | « percent, stable, nouveau, nothing » |
| 7 | absences: up is good | « the no-show rate: points, one decimal, up is bad » |
| 8 | a removed collaborateur labelled as active | the labels table, the screen's labels |
| 9 | `KpiGrid` unmeasured (always two across) | `layout_test` (« Revenus », a detail), the Accueil's stat cards |
| 10 | the currency choice ignored | « two currencies: one segment each, never a sum » |
| 11 | a ledger row in the salon's currency | « Revenus: each booking is in its own currency » |
| 12 | the chart's selection not by fill | « the chart: one node … told apart by fill » |
| 13 | the footnote says « encaissé » | the wording tests (screen and words) |
| 14 | the ledger sends `compare` | the API service's ledger test |
| 15 | the banner's « Voir » forgets `asOf` | « the banner's « Voir » … » |
| 16 | a stale `asOf` kept | « a ledger link's asOf … dropped » |
| 17 | the mock's ledger: « À clôturer » by the start | « a booking under way is « Prévu » … » — **green first**: the mock's ledger test could not see it; the under-way test was written, then it turned red |
| 18 | « Estimé » explained on every tab | « the labels of §3.3 on each tab, « estimé » and its footnote » |
| 19 | the Accueil's day card not tappable | « OWNER: each money card opens « Revenus » on its period » |
| 20 | the period chips scroll again | « « Dates… »: MyWeli's picker … » (the tap misses) |
| 21 | the row's name in the app bar | `layout_test`: a detail at 360/375/390 × 2× |
| 22 | a body without `groups` read as none | « strict: a body without its parts throws », the API's unreadable |
| 23 | the first load untitled | « the first load: the period titled at once … » |
| 24 | a period bar on a refusal | « 403: « Réservé au propriétaire », no « Réessayer » » |
