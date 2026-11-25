# Pro revenue analytics — revenue by collaborateur, prestation and canal — design spec

| | |
|---|---|
| **Status** | Draft — waits for the owner's answers to §17 (Q1–Q12). No code before. |
| **Owner** | Sadreddine |
| **Last updated** | 2026-11-25 |
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
10. Twelve questions for the owner in §17, each with a recommendation.

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
  `confirmed` + `completed` (`:34`), bucketed on salon days (`:58-82`).
  **Sums `totalPrice` across currencies** (`:107-109`) — §16.
- **`GET /providers/{id}/earnings`** — `ProviderEarningsService.earningsFor`
  (`backend/lib/src/provider_earnings_service.dart`). Gate `finances.view`
  (`:34`). `completed` only (`:39-42`), optional UTC range, every row in one
  response (no pagination). `totalEarnings` **sums across currencies** under
  the salon's currency (`:54`, `:72`) — §16. Each row carries its own
  currency (`:61`).
- **The booking record** (`backend/lib/src/db/migrations.dart:69-86` and
  later columns; `postgres_appointment_repository.dart:211-236`):

  | Need | Stored? | Where |
  |---|---|---|
  | Collaborateur | ✅ `artist_id`, nullable (« Sans préférence ») | `booking_service.dart:251`; changed on reassignment (`kAppointmentUpdatableKeys`, `appointment_repository.dart:91-98`) |
  | Collaborateur's **name** | ❌ live roster only; `deleteArtist` removes it (`provider_catalog_service.dart:807-818`) | — |
  | Services | ✅ `service_ids` jsonb (duplicates allowed) | `booking_service.dart:250` |
  | **Price per service** | ❌ only `total_price` = Σ the services' `price` at booking (`booking_service.dart:140-153`, `:322-335`) | — |
  | Service **name** | ❌ live catalogue only; `deleteService` removes it (`:163-173`) | — |
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
  flag-hidden V2 (`FeatureFlags.futureProviderFeatures`), a hand-drawn fake
  chart and fake rankings. Decision 30 says its chart would count « Total
  réalisé ».

### 2.3 Website

- `/pro/revenus` — `web/components/pro/RevenusClient.tsx`: the same four
  periods as chips, « Total réalisé », a `DataTable` ledger (Date · Montant,
  each row links to the booking). Sidebar entry gated on `finances.view`
  (`web/lib/pro/nav.ts:34`). BFF: `web/app/api/pro/earnings/route.ts`,
  `web/app/api/pro/dashboard/route.ts`; periods in `web/lib/pro/earnings.ts`.

### 2.4 Who sees money (access.md §2.2)

Only **Propriétaire** has `finances.view`. Manager: « sees no money
figures » (sign-off 2026-07-11); access.md §8 item 4: Manager + finances
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
| `upcomingAmount` / `upcomingCount` | `confirmed` bookings whose start is **now or later** | « Prévu » |
| `pendingCount` / `pendingAmount` | `pending` bookings whose start is now or later | « … demandes en attente » |
| `toCloseAmount` / `toCloseCount` | `confirmed` bookings whose start is **before now** — done or not, nobody said | « À clôturer » |
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

### 3.3 The breakdowns

Each row carries `completedAmount`, `completedCount`, `averageTicket`, its
`share` of the group's `completedAmount` (0–1, server-computed so the shares
add up to 1), and the same three for the comparison period.

- **Par collaborateur** — grouped by `artist_id`. One booking, one
  collaborateur. `null` → one row « Sans collaborateur attribué ».
  A reassigned booking counts for the collaborateur it has now.
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
4. Mark each such line `estimated`.

A row whose amount includes an estimated line carries `estimated: true`; the
app and the website print « estimé » beside it, with the footnote (§4.10).
No production row is written.

### 3.5 Periods and comparison — the server owns the calendar

The client sends `period` + `date` (any day inside it), or `period=custom` +
`from` + `to`. The server answers with the resolved dates, so the app and
the website share one definition of a week, a month and « the period
before ».

| `period` | Range | `compare=previous` | `compare=year` |
|---|---|---|---|
| `day` | that day | the day before | the same date a year earlier (29 Feb → 28 Feb) |
| `week` | Monday → Sunday containing `date` | the week before | the week 52 weeks earlier (same weekdays) |
| `month` | 1st → last day | the previous calendar month, in full | the same month a year earlier |
| `year` | 1 Jan → 31 Dec | the previous year | the previous year |
| `custom` | `from` → `to` (≤ 366 days) | the same number of days, just before | the same dates a year earlier |

**Like for like (Q8).** When today (salon time) falls inside the range, the
current figures only run to now. The comparison is then cut to the same
number of elapsed days — on 25 November, « Mois » compares 1–25 November with
1–25 October, not with all of October — and the response says so
(`likeForLike: true`, the dates compared). A comparison range longer than its
source month is clipped to its own end (31 March → 28 February).

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
│ │ ▲ +12 %          ││ ▲ +4 %          ││     one per row past 1.3×
│ └──────────────────┘└─────────────────┘│     or when a value would not fit
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
- **« Dates… »** opens the platform date-range picker (French, Monday
  first, `french_test.dart`), limited to 366 days and to the bounds of §3.5;
  a longer choice shows the field's error « 366 jours au plus » — never a
  toast.
- **« Comparé à : … ▾ »** — a text button that opens a bottom sheet:
  « Période précédente » · « Même période l'an dernier » · « Aucune
  comparaison », radio-style option cards (§3.3 `borderStrong`). The line
  shows the resolved dates (« 1–25 octobre », « novembre 2025 »), or
  « Aucune comparaison ». The choice persists for the session, not on disk.

### 4.4 « À clôturer »

Shown when `toCloseCount > 0` in any group: a `StatusBanner` (info) « {n}
rendez-vous passé(s) à clôturer » + « Confirmés mais pas encore marqués
« Terminé » : ils ne comptent pas dans le réalisé. » and a text button
« Voir » → the ledger on « À clôturer », where each row opens the booking
and its « Terminé » / « Absent » actions (journal J1, existing). Coming back
reloads the figures.

### 4.5 The figures (KPI grid)

`_StatBlock`'s rules, moved to a shared widget (`KpiGrid`, §12.1): two
across; one per row past 1.3× text scale **or** when any value would not fit
half the width (measured, as `_StatBlock` measures today). Each tile: title
(`bodyMedium`, `textSecondary`) · value (`titleLarge`, `textPrimary`, the
amount never breaks inside — `EarningsTotal`'s step-down rule, owner's
decision 2026-10-22) · delta (§3.6) · optional caption (`bodySmall`,
`textTertiary`). Tiles: « Réalisé » · « Rendez-vous terminés » · « Panier
moyen » · « Taux d'absence » (+ « {n} absence(s) · {montant} ») · « Prévu »
(full width; only when the period ends today or later).

### 4.6 « Évolution »

- Bars of « Réalisé » per bucket, `primary` on the card, height a named
  constant (160 dp, §5 « What §5 does not govern »), `radiusSmall` tops.
  No axis numbers; the first, middle and last bucket dates under the bars
  (`bodySmall`, `textTertiary`).
- **Tap a bar** → it is selected (a 2 dp `borderFocus` outline) and a line
  above the chart reads « mar. 4 nov. · 45 000 FCFA · 2 rendez-vous ». Tap
  it again or elsewhere → the line returns to the period total.
- Each bar is a `Semantics` button with that same sentence; a bar too thin
  to hit (31 per 328 dp ≈ 10 dp) is reached by a horizontal drag across the
  chart (the selected bar follows the finger) **and** by « Voir en liste »,
  which swaps the chart for a list of buckets (date · amount · count) — the
  same list a screen reader and 200 % text use.
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
  « {client} · {prestations} · {collaborateur} ». A client whose account was
  deleted reads « Client supprimé »; a booking without a collaborateur reads
  « Sans collaborateur ». Tap → the booking's detail
  (`/pro/appointments/:id`).

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
| **Period change** | The bar updates at once; the content goes back to the skeleton. **The previous period's numbers are never shown under the new label** (earnings_screen's rule, `:178-180`). An older answer arriving late is dropped (a request id, the booking hub's `slotsRequestId` pattern). |
| **Error** | `AppErrorView` « Chargement impossible » + the failure's sentence + « Réessayer » (same period); `wifi_off` for no connection. |
| **Salon with no completed booking ever** (`everCompleted: false`) | `EmptyState` icon `insights_outlined`, « Pas encore de revenus », « Vos revenus s'afficheront ici dès votre premier rendez-vous marqué « Terminé ». », action « Voir les rendez-vous » (→ `/pro/journal`). The period bar stays (a salon with upcoming bookings sees « Prévu »). |
| **A period with nothing completed** | Figures at 0 with their deltas; no chart; « Répartition » shows `EmptyState` « Aucun rendez-vous terminé sur cette période » + « Période précédente ». |
| **A future period** | « Réalisé » 0 FCFA, « Prévu » leads; « Répartition » empty state « Rien de terminé pour l'instant : cette période n'a pas commencé. » |
| **Several currencies in the period** | A segmented control above the figures, one segment per currency (« XOF · franc CFA (UEMOA) », « XAF · franc CFA (CEMAC) »), the largest « Réalisé » first. Nothing adds two currencies. |
| **Access refused** (403 — a role changed mid-session, a stale deep link) | `EmptyState` icon `lock_outline`, « Réservé au propriétaire », « Seul le propriétaire du salon voit les revenus. » — no retry (retrying cannot succeed, SYSTEM §12). `not_a_member` follows the existing sign-out path. |
| **Salon switch** | `resetForSalonSwitch`: the state empties, the in-flight answer is dropped. |
| **Comparison has no data** | Deltas read « nouveau » or nothing (§3.6), never an error. |

### 4.12 Edge cases

- **Long French names** (« Prestation supprimée · Tresses africaines avec
  rajouts ») wrap; amounts never break inside (`expectNoMidWordBreak`).
- **200 % text at 360 dp**: one tile per row, chips scroll, the share bar
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
| Ledger | « Rendez-vous terminés » · « Voir tout ({n}) » · « Terminés » · « À venir » · « À clôturer » · « Absents » · « Annulés » · « Afficher plus » · « Client supprimé » · « Sans collaborateur » · « sur {total} » |
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
- **Évolution**: an SVG bar chart, `role="img"` with an `aria-label`
  summarising the period, each bar a focusable `<button>` with its sentence;
  hover and focus show the same line as the app. « Voir les données » toggles
  a real `<table>` (date · montant · rendez-vous).
- **Répartition**: a `tablist` (arrow keys move between tabs) and a
  `DataTable` per tab: columns « Nom » · « Rendez-vous » · « Montant » ·
  « Part » · « Panier moyen » · « Évolution ». Column headers sort
  (`aria-sort`). Each row is a link (the DataTable's navigation row).
- **Ledger**: `DataTable` « Rendez-vous terminés », its filter chips,
  numbered pages of 20 (« Précédent » / « Suivant », the current page
  announced).

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
| Sortable columns | menu | column headers |
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
  now. access.md keeps money owner-only by sign-off, and item 4 says a change
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
| `date` | `YYYY-MM-DD` | required unless `custom`; any day inside the period |
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
`pageSize` 1–50 (default 20).

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
        clientName:  { type: string, nullable: true }   # null = deleted account
        serviceNames:
          type: array
          items: { type: string, nullable: true }       # null = deleted, no kept name
        artistLabel: { type: string, nullable: true }
        artistState: { type: string, enum: [active, removed, unassigned] }
        channel:     { type: string, enum: [app, web, salon, online] }
        estimated:   { type: boolean }
```

`upcoming` soonest first; the others newest first; ties broken by id.
`clientName` only — never the phone (the owner has `clients.view`, but the
ledger does not need a phone; the booking detail has it).

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

### 8.1 Three nullable columns on `appointments` (migration 0051, additive)

| Column | Type | Written by | Content |
|---|---|---|---|
| `service_lines` | `jsonb` | `book`, `bookManual` | `[{ "serviceId", "name", "price", "durationMinutes" }]`, one per `service_ids` entry, in its order; Σ `price` = `total_price` |
| `artist_name` | `text` | `book`, `bookManual`; and every write of `artistId` (reassignment: `rescheduleByProvider`, the journal's drag) | the collaborateur's name at that moment; `NULL` when `artist_id` is `NULL` |
| `channel` | `text` | `book` (`app` or `web`, §8.2), `bookManual` (`salon`) | `app` · `web` · `salon`; a CHECK keeps it to these three or NULL |

- **No backfill** (Q5). A NULL is a meaningful state — « made before R1 » —
  read by the aggregator: lines estimated (§3.4); `artist_name` NULL → the
  live roster, else « Ancien collaborateur »; `channel` NULL → `salon` when
  `user_id = 'manual'`, else `online`.
- `kAppointmentUpdatableKeys` gains `artistName` (written with `artistId`
  only). `service_lines` and `channel` are never updated: immutable, like
  `currency` (« the Fresha rule »). Both twins read the list (B15.1).
- **Rollback-safe**: an older image reads with `SELECT *` / `RETURNING *`
  and `_toDto` picks named keys, so it ignores the columns; its INSERT names
  its columns, so it leaves them NULL, which reads as « before R1 » —
  correct for the labels, an estimate for the lines. No constraint an older
  image could trip (the CHECK allows NULL). The migration says so in its
  header.
- The demo salon's snapshot/reset (`postgres_demo_snapshot_repository.dart`)
  and the salon purge (B0.24) are read in R1 for the new columns: the purge
  deletes rows whole; the demo reset must restore lines and channels for its
  seeded bookings, or they read as estimated (acceptable, but the reviewer
  sees « estimé » — R1 decides with a test).

### 8.2 How a booking knows « app » from « web »

The website's booking BFF (`web/app/api/bookings/route.ts`) adds
`X-Myweli-Channel: web` to its `POST /appointments`. The route reads it,
keeps `web` if and only if the value is exactly `web`, else `app` (the app
sends nothing; builds 0.0.2 neither). The header is client-declared: it only
ever labels a salon's own statistics, is enum-checked, and is never used for
authorisation (T85, §10). **The website ships the header first (R0w)**, so
no website booking is ever stamped `app`.

### 8.3 Reads (R2)

- `AppointmentRepository.revenueRows(providerId, fromUtc, toUtcExclusive)`
  → the narrow fields the aggregator needs (`id`, `status`,
  `appointmentDate`, `artistId`, `artistName`, `totalPrice`, `currency`,
  `userId`, `channel`, `serviceIds`, `serviceLines`), ordered by
  `appointment_date, id`. Postgres: one `SELECT` on
  `appointments_provider_date_idx`.
- `AppointmentRepository.revenueLedger(providerId, range, status, filters,
  limit, offset)` → a page + its total; `serviceId` filter =
  `service_ids ? @sid`.
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
  `:322-335`) and stamp `channel` and `artistName`;
  `AppointmentLifecycleService.rescheduleByProvider` writes `artistName`
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
- **PII**: the ledger carries client names to the owner only, never phones;
  nothing logged but the route, the status and the duration.
- **Threat model** (BACKEND.md §7) — new row **T85**, « Revenue analytics
  (`GET /providers/{id}/analytics/revenue*`) »: **I** — a member without
  `finances.view`, or another salon, reads money or client names → the
  capability check and its REQUIRED negative tests; **D** — a 366-day range
  with a year comparison on a busy salon → the range cap, the measured
  budget (§11), `no-store`; **T** — a forged `X-Myweli-Channel` → it can only
  relabel the salon's own statistics, enum-checked, never used for authz.
  T5 gains « analytics » in its provider-reads list.

---

## 11. Performance

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

- **`KpiGrid` / `KpiTile`** — `_StatBlock`'s measured two-across-or-one
  rule, moved out of `dashboard_screen.dart` so the Accueil and « Revenus »
  share it; a tile = title · value · `DeltaBadge` · caption.
- **`DeltaBadge`** — arrow glyph (`arrow_upward` / `arrow_downward`,
  `iconS`) + signed text; `success` / `error` by the figure's good direction,
  `textSecondary` for « stable »; never colour alone; its semantics sentence
  (§12.3).
- **`ShareBar`** — 4 dp, `primary` on `surfaceVariant`, `radiusPill`,
  `ExcludeSemantics` (the row says the share in words).
- **`BarSeries`** — the « Évolution » chart: bars `primary`, a selected bar
  outlined `borderFocus` 2 dp, height the named constant
  `BarSeries.height = 160`, each bar a semantics button; the list form.
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
  button, rows, « Voir », « Voir en liste ». A chart bar narrower than 48 dp
  is not the only way in (§4.6).
- **Screen readers**: a tile reads « Réalisé : 1 250 000 FCFA, en hausse de
  12 % par rapport à octobre 2026 »; a rate « Taux d'absence : 5,9 %, en
  baisse de 1,2 point »; a row as in §4.7; the period label is a heading
  (level 2) and changes are announced (« Novembre 2026 »).
- **200 % text** at 360 dp: §4.12, pinned.
- **Colour independence**: deltas carry glyph + sign + words; « estimé » is
  a word.
- **Website**: semantic `<table>`/ARIA table, `tablist`, `aria-sort`, a
  visible `:focus-visible` ring, labelled fields, the dialog's focus trap,
  `aria-live` for errors, axe clean.

---

## 13. Testing plan

### 13.1 Backend

- **Period resolution** (pure): every row of §3.5's table; Monday weeks
  across a year end; 29 Feb in both directions; like-for-like on the 1st,
  the 15th and the last day; clipping (31 March → 28 Feb); bounds and the
  366-day cap.
- **Aggregator** (pure): each figure of §3.2 by status and by « now »
  (a confirmed booking one minute before and one after); salon-time
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
  ordering, filters, page totals).
- **Writes (R1)**: `book` / `bookManual` store lines, `artistName`,
  `channel` — a Postgres round-trip that fails before R1 (the B14.1 lesson:
  a twin keeps what Postgres drops); reassignment writes `artistName`; the
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
  ledger; accept `channel=Web`; reorder rows on equal amounts by map order.

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
  48 dp targets.
- **Goldens** (authored on Linux, `gh workflow run goldens.yml`): success,
  empty salon, empty period, refused, detail, ledger, 200 %.
- The old screen's wording tests (`pro_earnings_wording_test.dart`) move
  to the new screen's words; « encaiss » stays forbidden.

### 13.3 Website

- Unit (Vitest): URL ⇄ query (malformed → current month), labels, deltas,
  CSV (separator `;`, UTF-8 BOM for Excel, amounts as integers, one file per
  table, the filename « revenus-collaborateurs-2026-11.csv »).
- RTL: states, roles (owner sees; the three others get the refused state
  from a 403), the `tablist` keys, `aria-sort`.
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
| **R1** | Migration 0051 (three nullable columns, no backfill), the writes, the twins' key list, the header read, the demo reset | backend | R0w live | its deploy (`deploy-backend.yml`) |
| **R2** | The two endpoints, the period resolver, the aggregator, the repo reads + contract, OpenAPI, T85, `schema.ts` regenerated | backend (+ `web/lib/api/schema.ts`) | R1 | its deploy |
| **R3** | « Revenus » rebuilt, details, ledger, Accueil taps, shared widgets, goldens; placeholder deleted | app | R2 deployed | the next Pro build in the stores |
| **R4** | `/pro/revenus` rebuilt, details, ledger, CSV | website | R2 deployed | its merge |

Plus a records PR after each deploy, as usual. R3 and R4 are independent of
each other once R2 is deployed.

**Production reads** (read-only, each on the owner's yes): before R1, the
count of bookings by number of services and the count referencing a service
or a collaborateur that no longer exists — how many rows will read
« estimé » or « Ancien collaborateur ». After R1, a count of new bookings
with lines, channel and name.

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
- [ ] T85 + T5 updated (R2); SYSTEM.md §11.3 entries marked built (R3/R4).
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

---

## 17. Open questions for the owner

**Q1–Q12 are decisions 237–248** in `docs/BACKLOG.md` §2, open (batch 17).
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
   access.md item 4 says.*
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
   same period last year, or nothing; and while a period is in progress,
   compared like for like (1–25 November with 1–25 October)? *Recommended:
   yes to all.*
9. **Par catégorie and à domicile.** Not possible now: prestations have no
   category and no booking records à domicile. Defer « par catégorie » to a
   catalogue spec that gives each prestation one of the Ivorian categories,
   and « à domicile » to the V2 home-service module? *Recommended: yes.*
10. **Export.** « Exporter (CSV) » of each table on the website (opens in
    Excel), nothing on the app for now? *Recommended: yes.*
11. **Offer.** Available on every offer, trial included — no gate by tier?
    *Recommended: yes; « Statistiques » is already in the Pro offer's list.*
12. **Order of work.** R0w → R1 (production read before, deploy on your
    word) → R2 (deploy on your word) → R3 and R4; each merge, read and
    deploy on your word? *Recommended: yes.*
