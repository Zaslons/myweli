# Store a booking's currency — the stamp the server promises and never keeps

| | |
|---|---|
| **Module** | backend: `appointments` (repository, migration, booking notifier), module `multi-pays` §4. Then two small client PRs: the Pro surfaces of the app and of the website |
| **Status** | **Approved 2026-11-23.** The owner answered the seven questions of §11 at once, « Approve as recommended »: decisions 187–193 in BACKLOG, batch 14 (B14.1–B14.4 are B1–B4 here). **B1 (B14.1) built, merged and DEPLOYED 2026-11-23** (§8.7, §9.1): #840, `d80b4303`; production serves `myweli-api-00055-jv2` (image `d80b430`) since 18:01 UTC; migrations `0047` and `0048` ran at boot; every one of the 4 bookings now stores `XOF`. Each step was on the owner's word. **B3 (B14.3) built and merged 2026-11-23** (§8.8, #843, `c3716e6b`); it ships with the next app builds. **B2 (B14.2) built 2026-11-23** (§8.9), on the owner's « Yes, build B14.2 », in its own PR: migration `0049`; **not merged, not deployed**. B4 not started. |
| **Owner** | the project owner: the answers, each merge, every production read, and each `deploy-backend.yml` dispatch, each on the owner's word |
| **Last updated** | 2026-11-23 |
| **PRD ref / phase** | module `multi-pays` MP1 ([multi-pays-end-version.md](multi-pays-end-version.md) §4, [../modules/multi-pays.md](../modules/multi-pays.md) §4) · V1 |
| **ROADMAP entry** | [2026-11-23-appointment-currency-stamp-spec.md](../roadmap/entries/2026-11-23-appointment-currency-stamp-spec.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails (all three invoked for this spec) · [BACKEND.md](../BACKEND.md) §1–§4, §7 |
| **Related** | [web-account-bookings-truth.md](web-account-bookings-truth.md) §1 (found it; #836, merged 2026-11-23 as `319da3e7`) · [consumer-app-truth.md](consumer-app-truth.md) §3 (corrected on #836) · [infra-rollback.md](infra-rollback.md) · [backend-migration-timeouts.md](backend-migration-timeouts.md) · [deleted-owner-salon-purge.md](deleted-owner-salon-purge.md) (the dual-form jsonb idiom) |

**Legend.**
- **OBSERVED** means read in the code at `main` `ad065999`, or run there. The branch was then rebased onto `95072597` (#836, then #838). Every citation in a file #838 changed was re-read there.
  - "Run" means a throwaway probe against a local Postgres 16 database, created for it and dropped after, applying `main`'s migrations (§2.7). Nothing from the probe is committed.
- **INFERRED** means reasoned from what was observed.
- **UNVERIFIED** means not readable from here: production, Cloud SQL, a console.

---

## 1. Goal & scope

**The defect.** Booking creation stamps each booking with its salon's currency. The comment on it reads « immutable — the Fresha rule ». The Postgres repository neither writes nor reads that field, and the `appointments` table has no column for it. So production has never stored a booking's currency: `git log -S currency` on the Postgres appointment repository is empty, and no migration ever added the column (OBSERVED). Every surface falls back to the salon's currency **today**.

**Why it matters, said plainly.**
- **Today, no user sees a wrong amount.** The locality tree holds one country (Côte d'Ivoire, XOF), so every salon has always been XOF (§2.5).
- **It is latent.** The fallback gives the salon's *current* currency. The day a second currency exists and a salon moves into it, its clients' past bookings would silently be re-priced in the new currency. That is the exact case the stamp exists for.
- **The contract and three documents say it works:** `openapi.yaml`, T57 in BACKEND.md (« Implemented ») and `modules/multi-pays.md` §10 (✅) (§2.6).
- **The backfill is exact only now.** While one currency exists, "the salon's currency at migration time" equals "the salon's currency when it was booked" for every row (§3.3). Once a second currency exists, the backfill becomes a guess.

**In scope:**
- the column, its migration and its backfill (§3.1–§3.3);
- the write path and the read path in the Postgres repository, and the DTO (§3.4);
- the in-memory twin, so it cannot hide the next field Postgres drops (§3.5);
- the server's own readers: the booking notifier, earnings, enrichment (§3.6);
- the later `NOT NULL` step (§3.7);
- the contract wording (§4);
- every reader of `currency` and `providerCurrency` on the app, the website and the Pro surfaces, and which ones change (§5);
- a test that fails on today's Postgres repository (§8.1);
- the rollout on real production data (§9).

**Out of scope:**
- **Totals across bookings:** the dashboard revenue, a client's « Dépensé » and the earnings total stay labelled in the salon's current currency; the client's « Passés » summary keeps its own rule, the newest visit's currency (Q4). A mixed-currency sum cannot occur while one currency exists; multi-pays §4.6 then applies (« groups by currency — no synthetic totals »).
- **The market-change gap:** a salon's currency can change through four writes, none of which checks for bookings (§2.5). Only a tripwire test is proposed here; the guard itself comes with the second market (Q5).
- **Converting currencies:** never done (multi-pays §4.3).
- **The admin console:** it shows the platform currency by design (`admin_detail_widgets.dart:113-119`).
- **Anything in A1w's spec (#836):** this spec does not edit it (§12).

**Fit.** routes → services → repositories → DTOs, unchanged:
- the booking service already computes the stamp (the server is the authority, T57);
- only the repository and the schema learn to keep it;
- no new endpoint, no new service, no new client interface.

**UX.** Nothing a user sees changes while one currency exists. After a salon's currency changes (impossible today), its past bookings keep their own amounts and currency on every per-booking surface. That is the whole user story. No screen, flow or copy is added.

---

## 2. What exists today (OBSERVED)

### 2.1 The write: both creation paths stamp it

- `book` (a client's booking, app or web), `backend/lib/src/appointments/booking_service.dart:243-247`:
  > Multi-pays §4: financial records are stamped with the salon's currency at write time (immutable — the Fresha rule).
  - The line is `'currency': provider['currency'] ?? 'XOF'`.
- `bookManual` (the salon's own entry, and the demo reset, which calls it: `demo_reset_service.dart:281`), `booking_service.dart:342-343`, with the same expression.
- Both hand the map to `AppointmentRepository.create` (`:266`, `:362`).
  - No other writer creates bookings: in `lib/` and `routes/`, `INSERT INTO appointments` appears only in `postgres_appointment_repository.dart:33`.
  - Two raw INSERTs outside the server matter for B2 (§3.7): `backend/test/db/postgres_salon_purge_test.dart:147` and `backend/tool/volume_probe.dart:154`.

### 2.2 Where it is lost: the Postgres repository and the schema

- **The INSERT** (`backend/lib/src/db/postgres_appointment_repository.dart:33-44`) lists 18 columns. `currency` is not among them, so the key is ignored.
- **The read** (`_toDto`, `:197-220`) builds the DTO from named columns. It has no `currency` key.
  - Every read that returns bookings goes through it: `create`, `byId`, `listForUser`, `listForProvider`, `confirmedInWindow` and `update`. `completedForAnalytics` and `countsByStatus` bypass it and return no amounts.
- **The table** (`backend/lib/src/db/migrations.dart:69-86`, migration `0002_appointments`) has no `currency` column, and no later migration adds one.
  - The only `currency text NOT NULL` in the file is the `countries` table (`:803`, migration `0030`).
- **`update`** (`:146-190`) can change six keys: `status`, `appointmentDate`, `endsAt`, `depositScreenshotUrl`, `arrivedAt` and `artistId`. It could never change a currency, which is right: the stamp is immutable.

### 2.3 Why no test saw it

1. **The in-memory twin keeps whatever it is handed.**
   - `InMemoryAppointmentRepository.create` stores and returns the caller's own map (`appointment_repository.dart:130-133`).
   - So every service and handler test, which all run on the twin, sees `currency`.
   - Its `update` merges any key (`:185-196`), where Postgres knows six.
2. **The Postgres test's fixture has no `currency`.**
   - `apptMap` (`backend/test/db/postgres_repositories_test.dart:148-174`) builds the map by hand, without the key.
   - So the round-trip test (`:179-205`) could not catch it.
3. **The one test that reads a stamp cannot tell stamped from inherited.**
   - `multi_pays_test.dart:595-610` asserts an earnings row says `XOF`.
   - A stamped row and an unstamped row that inherits the salon's currency (`provider_earnings_service.dart:59-61`) both give `XOF`.
   - Its own comment says « pre-MP1 row inherits the salon's ».
4. **No test asserts that a new booking carries `currency`** (`grep -rn "currency" backend/test/appointments` finds only the enrichment fixture and a comment, `appointments_test.dart:424`).

### 2.4 What production therefore serves

- **The consumer read** (`GET /appointments`, the detail):
  - the row from `_toDto` carries no `currency`;
  - the enrichment adds `providerCurrency: p?['currency']`, the salon's **live** currency (`appointment_enrichment.dart:81`);
  - its own comment states the rule: « an unprefixed key is stamped into the booking at write time and immutable — `currency` is the deliberate one » (`:24-27`).
- **The clients** read `currency ?? providerCurrency ?? 'XOF'` (§5).
  - In production the first operand is always absent, so they render the salon's live currency.
- **The Pro surfaces** use the salon's currency for each booking (§5.3, §5.6). The one exception is the website's earnings rows, which read the row's `currency` (`RevenusClient.tsx:160`); the server fills it with the salon's today.
- **The server's own messages** use the salon's live currency (`booking_notifier.dart:142-151`, `:165-166`).
- **Earnings rows** fall back to the salon's (`provider_earnings_service.dart:59-61`).

### 2.5 Why no one sees a wrong amount today — and what could change a salon's currency

- **The locality seed holds one country and one city:** `CI` / `XOF` (`backend/lib/src/localities/localities_repository.dart:95-106`) and Abidjan / `Africa/Abidjan` (`:108-118`).
- **Salons from before multi-pays** were stamped `XOF` by `backfillSalonMarketIfNeeded` (`migrations.dart:1862-1913`).
- **Four writes can change a salon's currency, and none checks whether it has bookings:**
  1. `PATCH` of the salon profile with an `areaId` re-derives `commune`, `city`, `countryCode`, `timezone` **and `currency`** from the locality tree (`provider_catalog_service.dart:211-231`; `localities_service.dart:36-44`; `localities_repository.dart:249-261`);
  2. the same `PATCH` with only a `commune` (an editable field, `:197`) re-derives them when the name matches a seeded area (`:232-234`);
  3. publishing self-heals a salon with no `areaId` the same way (`salon_provisioning_service.dart:278-286`);
  4. the demo reset restores the captured document, `currency` included (`demo_reset_service.dart:59`, `:144-148`). That one only touches the demo salon, whose bookings it wipes and recreates.
  - With one country in the tree, each of them can only write `XOF`.
  - Every new salon starts at `'currency': 'XOF'` (`providers_repository.dart:880`).
- **INFERRED: every salon has been `XOF` since multi-pays, so every booking's true stamp is `XOF`.**
  - **UNVERIFIED in production.** The `countries` table is written from that seed only when it is empty (`seedLocalitiesIfEmpty`, `migrations.dart:1784-1786`), and no code writes another row. A hand edit in Cloud SQL would not show here.
  - Step 0 of §9 reads it, on the owner's yes (Q6).

### 2.6 What says it works

| Where | What it says | True? |
|---|---|---|
| `docs/api/openapi.yaml:5385-5390` (`Appointment.currency`) | « Stamped from the salon at creation (multi-pays §4 — immutable); absent on pre-MP1 rows (read as the salon's). » | No: it is absent on **every** row |
| `docs/BACKEND.md:480` (T57, « Implemented (MP1) ») | « the currency is stamped onto financial records at write (immutable self-serve — the Fresha rule) and a timezone change once bookings exist stays support-mediated (no self-serve mutation path) » | No on both halves: the stamp is not stored, and three self-serve writes re-derive timezone and currency (§2.5). Moot only while the tree has one country and one city |
| `docs/modules/multi-pays.md:248-249` (§10) | « ✅ Per-salon `currency` (country-derived), stamped on financial records, threaded through display » | The stamp half: no |
| `docs/modules/multi-pays.md:123-124` (§4.1) | « derived from the country at creation, immutable self-serve (… changing it = a new salon) » | No: four writes re-derive it (§2.5) |
| `docs/design/consumer-app-truth.md:260` | « The server already sends every field used: … `currency` » | No; corrected by #836 (merged), on the same line |
| `docs/design/multi-pays-end-version.md:101-108` (§4) | « appointments stamped `currency` at create » | The plan; true in the service, lost in the repository |

### 2.7 The trap in the obvious backfill — `providers.data` is a JSON string

**The salon's document is stored as a JSON string.** Postgres sees a string inside the `jsonb` column, not an object:
- `migrations.dart:1600-1605`: « the `data` column is stored as a JSON-string scalar, like the rest of the codebase »;
- `postgres_providers_repository.dart:284-286` says the same;
- `postgres_salon_purge_repository.dart:33-38`: « `providers.data` is one in production, 8 of 8 rows on 2026-11-20 ».

**What that does to a backfill.** For a JSON string, Postgres's `data->>'currency'` returns **NULL**. A backfill written as `COALESCE(p.data->>'currency', 'XOF')` would therefore:
- stamp `XOF` on every row;
- look correct today;
- be silently wrong the day a second currency exists.

**The existing idioms** decode both forms:
- `CASE jsonb_typeof(col) WHEN 'string' THEN (col #>> '{}')::jsonb ELSE col END` (`postgres_salon_purge_repository.dart:36-38`);
- the guarded one, which never casts text that is not valid JSON: nested `CASE`s around `pg_input_is_valid(col #>> '{}', 'jsonb')` (`postgres_provider_auth_repository.dart:555-564`, « Postgres 16, as CI and Cloud SQL »). A bare cast raises on such text, and in a migration one bad document would fail every deploy.

**OBSERVED by the probe** (local Postgres 16, `main`'s migrations, a throwaway database dropped after):
- a booking created through `PostgresAppointmentRepository` with `currency: 'XAF'`:
  - `create` returns no `currency` key;
  - `byId` gives `null`;
  - `currency` is the **only** key of the input map missing from the read;
  - `information_schema` has no `appointments.currency` column.
- a salon created and given `currency: 'XAF'` through `PostgresProvidersRepository`:
  - `jsonb_typeof(data) = 'string'`;
  - `data->>'currency'` gives `NULL`;
  - the decoded form gives `XAF`;
  - `byId` gives `XAF`.

> The same naive shape is in migration `0021` (`UPDATE providers SET slug = data->>'slug'`, `migrations.dart:498`). It ran once, long ago. Whether it read anything then is not knowable from here, and slugs have been written by the application since. It is noted only as evidence that the trap is real; nothing is proposed for it.

---

## 3. The design

### 3.1 The column — four options

| Option | Rollback to the image before | What it guards | Verdict |
|---|---|---|---|
| **A. Nullable column + backfill now; `SET NOT NULL` later (B2)** | Safe: an older image's INSERT leaves it `NULL`, which every reader already handles | The contract step makes Postgres refuse a booking without a stamp: the exact defect, made loud | **Recommended (Q1)** |
| B. `NOT NULL DEFAULT 'XOF'` in one step | Safe: the default fills it | Nothing. Any future writer that forgets the column gets `XOF` silently. That is today's defect made invisible, and wrong once a second currency exists | Rejected |
| C. Nullable + backfill + `SET NOT NULL` in one migration | **Unsafe on the booking path.** The previous image's INSERT omits the column, so every booking fails with 23502. Same class as `0026` | Same as A, one deploy sooner | Rejected for now; it is A's B2, one deploy later |
| D. Nullable forever | Safe | Nothing at the database | Rejected as an end state |

**Expand → migrate → contract** (LAUNCH.md §1.4; `migration_reversibility_test.dart:28-34`):
- B1 expands and migrates;
- B2 contracts, once the image before B1 is no longer the rollback target (§3.7).

### 3.2 The migrations (B1)

**Two entries, not one.** Each migration runs in its own transaction (`runMigrations`, `migrations.dart:1428-1450`):
- `ALTER TABLE … ADD COLUMN` takes `ACCESS EXCLUSIVE` and holds it until that transaction commits;
- splitting the backfill into the next entry releases the lock before the `UPDATE`, which needs only row locks;
- so readers on the still-serving old revision never wait behind the backfill;
- it costs nothing.

```text
id: '00NN_appointment_currency'
  // Stamped booking currency (appointment-currency-stamp.md §3). Nullable on
  // purpose: an older image's INSERT omits it and writes NULL, which every
  // reader already handles. The NOT NULL is B2 (§3.7).
  'ALTER TABLE appointments ADD COLUMN IF NOT EXISTS currency text'

id: '00NN+1_appointment_currency_backfill'
  kAppointmentCurrencyBackfill
```

```sql
-- kAppointmentCurrencyBackfill: one statement (each execute runs one).
-- Nested CASEs because CASE is the construct whose evaluation order Postgres
-- guarantees: the cast only ever sees text pg_input_is_valid accepted.
UPDATE appointments a
   SET currency = COALESCE(
         (SELECT CASE jsonb_typeof(p.data)
                   WHEN 'string' THEN
                     CASE WHEN pg_input_is_valid(p.data #>> '{}', 'jsonb')
                          THEN (p.data #>> '{}')::jsonb ->> 'currency' END
                   ELSE p.data ->> 'currency'
                 END
            FROM providers p
           WHERE p.id = a.provider_id),
         'XOF')
 WHERE a.currency IS NULL
```

**Properties:**
- **Only fills `NULL`.** It never overwrites a stamp. Running it twice changes nothing.
- **A named constant**, like `kSalonValidationBackfill` (`migrations.dart:1296`). The test runs it directly (§8.3), and B2 runs it again.
- **Three cases fall to `XOF`, without an error:**
  - a salon whose document has no `currency` key (or is a JSON `null`, an array, a number);
  - a salon whose string document is not valid JSON: the guard skips the cast rather than failing the migration, which would fail every deploy until the row is fixed;
  - a booking whose salon row no longer exists.
  - That is the booking service's own fallback (`provider['currency'] ?? 'XOF'`), and the only currency that has existed.
  - The salon purge deletes a salon's bookings with it (`postgres_salon_purge_repository.dart:402`), so orphans should be rare.
- **No `// rollback-safe:` marker is needed.** Neither statement matches a pattern of `migration_reversibility_test.dart:69-104`, and a nullable `ADD COLUMN` widens.
  - That test also scans the comments inside each migration, so B1's comments must not contain a flagged phrase (`SET NOT NULL`, `RENAME`, `DROP COLUMN`…). The draft comment above says « The NOT NULL is B2 », which matches none.
- **`pg_input_is_valid` needs Postgres 16.** The code says CI and Cloud SQL run 16 (`postgres_provider_auth_repository.dart:557-558`), and that guard already runs in production. Step 0's query uses the same expression, so it is also a dry run of the decode (§9).

**The id numbers: `0047_appointment_currency` and `0048_appointment_currency_backfill`** (B1 landed first).
- [managed-home-stories.md](managed-home-stories.md) names `0047` on paper and is not built (decision 179): its PR B **must** renumber (`0049` or later). `migration_reversibility_test.dart:174-180` refuses a duplicate id and an unsorted list, so the collision cannot ship.
- Ids are strings, and they apply in list order.

### 3.3 What the backfill uses, said plainly

**Each existing booking gets its salon's currency as of the migration, not as of the booking.** That is the best available fact: nothing recorded the currency at booking time.

**It is exact for every existing row** (INFERRED, §2.5). No salon's currency can have changed:
- the tree has one country;
- every pre-multi-pays salon was stamped `XOF`.

**Where it is not exact, and why that does not matter today:**
- **A salon with no `currency` key, or a deleted salon:** `XOF`, the booking service's own fallback.
- **Bookings written by the old revision during the deploy:** the migration runs at boot while the previous revision still serves (`backend-migration-timeouts.md`), so a booking made between the migration's commit and the traffic switch is written `NULL`.
  - It reads exactly as today (`currency ?? providerCurrency`) and is fixed by B2's re-run (§3.7).
  - A boot-time re-run on every start was considered: it heals the same rows sooner, but it is a scan on every cold start for rows that B2 fixes anyway. Not proposed.

**Step 0 of §9 turns "exact" from inferred into observed:** a read-only count of salons by currency, on the owner's yes (Q6).

### 3.4 The write path, the read path, the DTO

`postgres_appointment_repository.dart`:
- **INSERT:** add `currency` to the column list and `@currency:text` to `VALUES`, with `'currency': a['currency']`.
  - No default in Dart: the service is the authority. In B1 a missing stamp stores `NULL`; after B2, Postgres refuses it.
- **`_toDto`:** add `'currency': r['currency']` (a `String?`).
- **`update`:** unchanged. It has no `currency` branch, and that is the immutability rule; §8.2 pins it on both twins.
- **No index.** No query filters or sorts on it.

**What the DTO carries after B1.**
- Every repository read now has `currency`.
- Every caller already spreads the row (`...a`) or passes it through:
  - the consumer enrichment (`appointment_enrichment.dart:65-66`);
  - the provider enrichment (`clients_service.dart:571`);
  - the journal (`journal_service.dart:103`);
  - the admin details (`admin_provider_service.dart:96`, `admin_user_service.dart:50`).
- So **every** appointment payload gains `currency` with no route or service change.

### 3.5 The in-memory twin

Two changes, so the twin cannot hide the next divergence:
1. **The twin contract runs on both repositories** (§8.2). A key Postgres drops turns it red even though the twin keeps it.
2. **`InMemoryAppointmentRepository.update` ignores a `currency` key**, as Postgres does.
   - A full whitelist of Postgres's six keys would be the honest twin, but it would break a caller: `InMemoryClientsRepository` changes a guest's phone through the twin's `update` (`clients_repository.dart:312`), a key Postgres's `update` does not know (its twin does that in its own SQL). Listed in §12.

### 3.6 The server's own readers

| Reader | Today | After B1 |
|---|---|---|
| Booking notifier: the amounts in WhatsApp/SMS, push and the in-app notification centre (`booking_notifier.dart:154-167`) | `salon.currency`, the live one | **`a['currency'] ?? salon.currency`**: a reminder or a refund message prices the booking in its own currency. One line in B1 |
| Earnings rows (`provider_earnings_service.dart:59-61`) | `a['currency'] ?? currency`, and the first is always absent | Unchanged code; now reads the stamp |
| Earnings total and response `currency` (`:45`, `:72`) | the salon's | Unchanged (Q4) |
| Dashboard revenue (`provider_dashboard_service.dart:100-118`) | sums `totalPrice`; labelled by the client | Unchanged (Q4) |
| A client's « Dépensé » (`clients_service.dart:162`, `:195`) | sums `totalPrice` | Unchanged (Q4) |
| Consumer enrichment (`appointment_enrichment.dart:81`) | adds `providerCurrency`; `currency` absent | Unchanged code; both now present, as the naming rule says |

### 3.7 B2 — the contract step

A later, small backend PR, deployed **once the rollback target already writes `currency`**: the deploy after B1's, or any later one.

```text
id: '00MM_appointment_currency_not_null'
  // rollback-unsafe: an image before 00NN omits `currency` from its INSERT;
  // with NOT NULL every booking it writes fails (23502). Roll back no further
  // than the first image that writes it (appointment-currency-stamp.md §3.7).
  kAppointmentCurrencyBackfill
  'ALTER TABLE appointments ALTER COLUMN currency SET NOT NULL'
```

**Why in that order:**
- the backfill first catches the rows of B1's own deploy window, and any rows a rollback wrote;
- `SET NOT NULL` scans the table under `ACCESS EXCLUSIVE`, which is milliseconds at today's size (§7).

**What B2 changes elsewhere:**
- ~~the contract makes `currency` non-nullable and required on `Appointment`~~ — **not done, on purpose (as built, §8.9):** a replayed creation response (`Idempotency-Key`, `kIdempotencyWindow` = 24 h) is returned as it was first sent, so one stored before 0047 has no `currency`. The contract says the column is NOT NULL and keeps the field nullable. `web/lib/api/schema.ts` is regenerated for the new description (CI fails on drift, §4);
- `migration_reversibility_test.dart` flags `SET NOT NULL` and demands the declaration, so it is red until written;
- DEPLOYMENT.md's rollback list (`:789-797`) gains it;
- **every raw INSERT without the column now fails with 23502**, so B2 also changes:
  - `backend/test/db/postgres_salon_purge_test.dart:147` and `backend/tool/volume_probe.dart:154`, which name a currency;
  - `apptMap`, whose `currency` parameter defaults to `'XOF'` rather than null;
  - §8.3, whose rows must be written NULL: it then runs inside a transaction that drops the `NOT NULL`, inserts, backfills, asserts and rolls back (DDL is transactional in Postgres).

---

## 4. Contract — `docs/api/openapi.yaml` (B1)

**`Appointment.currency` (`:5385-5390`):** the description becomes:
> Stamped from the salon at creation and stored with the booking (multi-pays §4 — immutable; appointment-currency-stamp.md). Null only on a booking written by an image older than migration 00NN during a deploy or a rollback window; read it as the salon's (`providerCurrency`).
- It stays `nullable: true` in B1; B2 tightens it.
- **`web/lib/api/schema.ts` is regenerated in the same PR** (`npm run gen:api`). CI runs it and fails on any drift (`.github/workflows/ci.yml:634-638`), and the generated file embeds this description.
  - So B1 touches `web/`. Whether a merge that changes only that generated file starts a production web deploy depends on Vercel's trigger, which DEPLOYMENT.md does not state (UNVERIFIED). Sibling specs treat every merge into `web/` as a production web deploy, so B1's merge is asked for on that basis.

**Unchanged:**
- `providerCurrency` (`:5443-5446`);
- `EarningsTransaction.currency` (`:6088-6091`), which is now true;
- `EarningsData.currency`.

No endpoint, status code or error envelope changes.

---

## 5. Every reader of `currency` and `providerCurrency`

**The rule after B1:**
- **an amount of one booking** is shown in **that booking's** currency: `currency`, else the salon's;
- **a total over bookings** is shown in the salon's current currency (Q4).

### 5.1 Backend
See §3.6.

### 5.2 The client app (MyWeli), per booking: already right, no change

| File:line | Reads |
|---|---|
| `mobile/lib/core/utils/cancellation_policy.dart:54` | `a.currency ?? a.providerCurrency ?? 'XOF'` |
| `mobile/lib/screens/appointments/appointment_detail_screen.dart:188`, `:230`, `:314`, `:441-442`, `:456-457` | `currency ?? providerCurrency` (`?? 'XOF'` at `:230`, `:441-443`, `:456-458`) |
| `mobile/lib/widgets/booking/appointment_card.dart:408-411` | `currency ?? providerCurrency ?? 'XOF'` |

- The model already parses `currency` (`mobile/lib/models/appointment.dart:61`, `:349`). After B1 these read the stamp, with no app release.
- **One total, with its own rule:** the « Passés » summary (`my_bookings_screen.dart:209-215`) sums every completed visit, across salons, and labels the sum with the newest visit's `currency ?? providerCurrency` (its comment: « MVP: a mixed-currency history sums nominally »).
  - After B1 that label becomes the newest visit's stamp instead of its salon's live currency, with no app change. That is the summary's own documented rule, and the same as A1w's; Q4 keeps it.
- Booking screens (`booking_hub_screen.dart`, `booking_confirmation_screen.dart`, `provider_detail_screen.dart`) price **a salon's catalogue** before a booking exists, so the salon's `currency` is right there.

### 5.3 The Pro app: per booking, they read the salon's live currency — change in B3

| File:line | Shows | Today | B3 |
|---|---|---|---|
| `mobile/lib/screens/provider/appointments/appointment_list_screen.dart:355-358` | a booking's total | `salonCurrency` | `appointment.currency ?? salonCurrency` |
| `mobile/lib/screens/provider/appointments/appointment_calendar_view.dart:267-270` | a booking's total | `salonCurrency` | same |
| `mobile/lib/screens/provider/appointments/pro_appointment_detail_screen.dart:203-206`, `:224` | total and announced deposit | `salonCurrency` | same |
| `mobile/lib/screens/provider/clients/client_detail_screen.dart:1049-1052` | one visit's amount | `salonCurrency` | `v.currency ?? salonCurrency` |
| `mobile/lib/screens/provider/earnings/earnings_screen.dart:255-259` | one earnings row | `earnings.currency ?? salonCurrency`: the response's, not the row's | `transaction.currency ?? earnings.currency ?? salonCurrency` |
| `mobile/lib/services/interfaces/pro_service_interface.dart:175-198` (`EarningsTransaction`) | — | ignores the row's `currency`, which the server sends (`provider_earnings_service.dart:61`) and the website already reads | gains `currency` (`fromJson`) |

**Totals, unchanged (Q4):**
- `dashboard_screen.dart:336-349`;
- `client_detail_screen.dart:675-677` (« Dépensé »);
- `earnings_screen.dart:202-204`;
- `pro_data_export_screen.dart:150-152` (the summary line of the export screen; the export's rows are §5.7).

**Settings examples, not bookings:** `deposit_settings_screen.dart:348-372` and `pro_manual_booking_screen.dart:386`.

**The mock** (`mobile/lib/services/mock/mock_appointment_service.dart:105`, `:204`) sets only `providerCurrency`. It mirrors today's production defect. B3 makes it stamp `currency: salon.currency` when it builds a booking (mock realism: the DTO shape).

### 5.4 The admin console (Flutter Web): unchanged

`admin_detail_widgets.dart:113-119` and `admin_dispute_detail_screen.dart:126` show the platform currency, « by design (multi-pays) ». Not this spec's.

### 5.5 The website, consumer side: already right, no change

| File:line | Reads |
|---|---|
| `web/components/account/AppointmentCard.tsx:56` | `appt.currency ?? appt.providerCurrency` |
| `web/components/account/AppointmentDetailClient.tsx:219` | same, for the total, deposit, balance and cancellation notice (`:344-379`, `:518`) |
| `web/lib/account/appointments.ts:30-35` | the type already declares both |

- After B1 these read the stamp, with no web deploy.
- **One total, with its own rule:** A1w's « Passés » summary (#838), `visitSummary` (`web/lib/account/appointments.ts:261-279`), rendered at `PastBookings.tsx:54`. It labels the sum with the newest visit's `currency ?? providerCurrency`, the app's rule (§5.2, Q4).
  - Its comment says « The server never stores `currency` today, so in production this is always `providerCurrency` » (`:263-264`). That becomes false when B1 deploys; B1 rewords it.

### 5.6 The website, espace pro: per booking, they read the salon's — change in B4

| File:line | Shows | Today | B4 |
|---|---|---|---|
| `web/lib/pro/today.ts:5-32` (`ProAppointment`) | — | no `currency` field | gains `currency?: string \| null` |
| `web/components/pro/ProAppointmentRow.tsx:46-48` | a booking's total | `profile.provider.currency` passed down | `appt.currency ?? currency` |
| `web/components/pro/JournalGrid.tsx:384` | a block's price | same | same |
| `web/components/pro/JournalPanel.tsx:226-231` | total and deposit | same | same |
| `web/components/pro/ProAppointmentDetailClient.tsx:321-326` | total and deposit | same | same |
| `web/components/pro/ClientCardClient.tsx:521-523` | one visit's amount | same | `v.currency ?? currency` |

**Already per row:** `web/components/pro/RevenusClient.tsx:160` (`t.currency ?? currency`).

**Totals, unchanged (Q4):**
- `AujourdhuiClient.tsx:363-371`;
- `ClientCardClient.tsx:466`;
- `JournalPanel.tsx:193` (the client's « Dépensé » in the journal panel);
- `RevenusClient.tsx:85`.

### 5.7 The four data exports: per-booking amounts with no currency — change in B3 and B4

Each export writes one row per booking with its amounts and no currency. Decided together, so the twins stay identical:

| Export | File:line | Row today | Change |
|---|---|---|---|
| Client, app | `mobile/lib/core/utils/data_export.dart:30-41` | `totalPrice`, `depositAmount` | adds `currency` (B3) |
| Client, website | `web/lib/account/export.ts:26-34` (« the exact shape the app builds ») | same | adds `currency` (B4) |
| Salon, app | `mobile/lib/core/utils/data_export.dart:141-150` | `totalPrice` | adds `currency` (B3) |
| Salon, website | `web/lib/pro/export.ts:60-65` | `totalPrice` | adds `currency` (B4) |

- The value is `a.currency`, else the salon's (`providerCurrency` on the client side, the salon's currency on the Pro side), else null.
- A new key in an export is additive: nothing reads these files back.

### 5.8 Fixtures

- **Backend:** `apptMap` (`postgres_repositories_test.dart:148-174`) gains `currency`; the twin contract owns the round-trip from then on.
- **Clients:** B3/B4 tests assert a booking whose `currency` differs from the salon's renders its own.
  - This is the discriminating case: `XOF` against `XOF` proves nothing (§2.3).
  - **The stamp must be a non-franc code (`EUR`).** Both formatters print « FCFA » for `XOF` and `XAF` alike (`mobile/lib/core/utils/formatters.dart:92`, `web/lib/format.ts:39`), so `XAF` against `XOF` renders the same text.

---

## 6. Security & threat model

- **No new endpoint, route or trust boundary.**
  - The value is server-derived, from the salon's document, computed by the booking service.
  - It is never client-writable: no editable-field list gains it, and `update` cannot write it.
- **Disclosure:** `currency` is the salon's public currency, already served as `providerCurrency` to the same readers. Not PII.
  - Account erasure keeps bookings (`appointment_repository.dart:38-47`), and keeps their currency with them.
- **T57 (`BACKEND.md:480`) is corrected in B1** to say what holds:
  - the stamp is stored since `00NN`;
  - **four writes re-derive a salon's timezone and currency with no booking check** (the area pick, a commune-only edit, the publish self-heal, the demo restore; §2.5), harmless while the tree has one country and one city, and pinned by the tripwire (Q5);
  - its status stays « Implemented » for the validation half only.
- No new T row.

---

## 7. Performance & locks

- **Payload:** about 16 bytes per booking (`"currency":"XOF"`). No new query, no N+1, no index.
- **The migration's locks:**
  - `ADD COLUMN` with no default is a catalog change: instant, but it needs `ACCESS EXCLUSIVE`;
  - the schema `lock_timeout` is 3 s (`migrations.dart:1364`);
  - if a long query holds the table, the migration fails, the revision never becomes ready, and the old one keeps serving: a deploy that rolls itself back (`backend-migration-timeouts.md`). Re-dispatch later.
- **The backfill** touches every row once, with a primary-key lookup per row into `providers`, under the 60 s statement timeout (`:1384`).
  - **The row count is UNVERIFIED.** The console's analytics overview shows the total of bookings (`GET /admin/analytics`, `analytics_service.dart:46-50`), and step 0 counts it (Q6).
  - Each updated row is a new row version: unless the update stays on the same page, it adds an entry to every index and re-checks the per-artist `EXCLUDE` constraint, and each row decodes its salon's document once.
  - Thousands of rows still take well under a second. For scale, the timeout's own comment measured an `EXCLUDE` index **build** over `appointments` on `db-f1-micro` at 14.3 s for 100 000 rows (`:1371-1383`). A product released on 2026-11-10 is far below that size, and step 0 reads the real count.
- **B2's `SET NOT NULL`** scans once under `ACCESS EXCLUSIVE`, milliseconds at that size.
  - At a large size, the known escape is a `CHECK (currency IS NOT NULL) NOT VALID`, then `VALIDATE`. Not needed now. It matches no pattern of the reversibility test, so if it is ever used, its `// rollback-unsafe:` line must be written by hand.

---

## 8. Tests — red first, each watched red on committed code

**Order.** Each new test is committed **before** the fix and run red against today's repository. Three exceptions say why: 8.2.3 (a pin, green today), 8.5 (a tripwire, green by design) and 8.3 (it tests a constant the fix creates; its evidence is m3, m4 and m10). The commit message records it (verification §2, §11). Postgres tests run in CI with `DATABASE_URL` (`.github/workflows/ci.yml:130-161`) and skip without it. Locally they need a database (memory: never another session's).

**Isolation.** The suite's `setUp` truncates `appointments` but not `providers` (`postgres_repositories_test.dart:96-103`). A test that changes a salon's currency uses a salon of its own, never the seeded `provider1`.

### 8.1 The test that fails on today's Postgres repository

`postgres_repositories_test.dart`, group `PostgresAppointmentRepository`:

> **a booking created and read back through Postgres keeps its currency.**
- `create(apptMap(…, currency: 'XAF'))`, then check the returned map, `byId`, `listForUser`, `listForProvider`, `confirmedInWindow` (after confirming it) and `update` (a status change).
- Each must carry `currency: 'XAF'`.
- **`XAF`, not `XOF`.** A literal `XOF` default, or any fallback, would pass on `XOF`.
- **Red today:** the probe shows `null` (§2.7).

### 8.2 The twin contract — what the service writes comes back

`backend/test/appointments/appointment_repository_contract.dart`, after `salon_validation_contract.dart`'s pattern. Run once on `InMemoryAppointmentRepository` and once on Postgres.

1. **Key parity through the real service.**
   - Setup: `BookingService.book` **and** `bookManual`, with a salon whose `currency` is `XAF`, each writing through a recording wrapper.
     - The two paths build separate map literals (`booking_service.dart:242-264`, `:339-360`), so a key added to one only is caught only if both run.
     - If `book` cannot be driven on Postgres (it needs a free slot), a source-level check that the two literals have the same key set stands in, said as weaker.
   - **The wrapper deep-copies the map when it captures it.** The twin stores and returns the caller's own map and mutates it in place on `update` (`appointment_repository.dart:130-133`, `:177-182`, `:191`), so a captured reference would follow every later change and compare the twin to itself.
   - Assert, per read path (`create`, `byId`, `listForUser`, `listForProvider`, `confirmedInWindow`): every captured key is present and deep-equal (numbers as `num`, dates as instants).
   - For `update`, the same, except the keys the update changed (`bookManual` writes `confirmed`, so a status change differs by design).
   - **This is the guard on the class of defect, not only this field** (verification §12): the next key either path adds without a column turns it red.
   - It is red today on Postgres (`currency`) and green on the twin.
2. **Immutable.** `update(id, {'currency': 'EUR', 'status': 'confirmed'})` leaves `currency` `XAF` on both repositories.
   - Red today on the twin, which merges any key (`appointment_repository.dart:191`).
3. **The salon changes, the booking does not.**
   - After creation, the salon's currency is set to `XOF`.
   - `GET /appointments` (handler test) then returns `currency: 'XAF'` and `providerCurrency: 'XOF'` side by side.
   - **Green today, and said so.** Handler tests run on the twin, which already keeps the stamp, so this one is not red-first. It pins the enrichment's naming rule; m9 is what turns it red.

### 8.3 The backfill — both storage forms, orphans, idempotent

A Postgres test runs `kAppointmentCurrencyBackfill` directly against rows written the way an older image writes them: a raw `INSERT` without the column.

| Row | Its salon | After the backfill |
|---|---|---|
| R1 | written **by `PostgresProvidersRepository`** (so `data` is a JSON string, as in production) with `currency: 'XAF'` | `XAF` |
| R2 | its `data` inserted by raw SQL as a jsonb **object**, `currency: 'XAF'` | `XAF` (the `ELSE` branch) |
| R3 | a salon document with no `currency` key | `XOF` |
| R4 | no salon row (orphan) | `XOF` |
| R5 | already stamped `XAF`; its salon now `XOF` | still `XAF` (never overwritten) |
| R6 | its `data` a JSON string that is not valid JSON (`to_jsonb('not json'::text)`) | `XOF`, and the statement does not fail |

- **Run twice:** the same result (idempotent).
- **The test does not assert which form `data` has.** That assertion would turn red on a repair if the storage is ever fixed (verification §15). It covers both forms instead.

### 8.4 The notifier

A booking stamped `EUR` at a salon now `XOF`: the rendered amount says `EUR`, not « FCFA ».
- **`EUR`, not `XAF`.** `_money` prints « FCFA » for both `XOF` and `XAF` (`booking_notifier.dart:176-178`), so an `XAF` stamp and an `XOF` salon render the same text and the test could not tell them apart.

### 8.5 The tripwire (if Q5 is answered as recommended)

`multi_pays_test.dart`:
- `seedCountries` has **one** distinct currency, and `seedCities` **one** distinct timezone.
- Its failure message names this spec and the guard to build first: refuse, or route to support, **any** write that changes a salon's currency or timezone once it has bookings (the four of §2.5).
- **Which event turns it red** (verification §15): adding a second market to the seed. That is not a repair of a defect. It is the moment the guard must exist, and the message says so; the guard's PR deletes the tripwire.
- **What it cannot see** (verification §12): a market added by a migration that inserts into `countries` directly instead of through the seed. Said in its comment.

### 8.6 Mutations to watch red, and controls that must stay green

| # | Mutation (on committed code) | Must turn red |
|---|---|---|
| m1 | drop `currency` from the INSERT: the column, the `@currency` placeholder **and** the parameter-map entry (dropping fewer fails on a SQL or driver error, which proves nothing) | 8.1, 8.2.1 |
| m2 | drop it from `_toDto` | 8.1, 8.2.1 |
| m3 | backfill with `p.data->>'currency'` instead of the decoded form | 8.3 R1 (the one that discriminates) |
| m4 | backfill without `WHERE a.currency IS NULL` | 8.3 R5 |
| m5 | the twin's `update` merges `currency` again | 8.2.2 |
| m6 | add a key (`'probe': 1`) to the map `bookManual` builds | 8.2.1 on Postgres |
| m6b | the same in the map `book` builds | 8.2.1 on Postgres |
| m7 | notifier back to `salon.currency` | 8.4 |
| m8 | a second `Country` with another currency in the seed | 8.5 |
| m8b | a second `City` with another time zone in the seed | 8.5 |
| m9 | the enrichment writes `'currency': p?['currency']` over the stamp | 8.2.3 |
| m10 | drop the `pg_input_is_valid` guard (a bare cast) | 8.3 R6 (the statement fails) |
| m11 | the twin's `create` stores a copy without `currency` | 8.2.1 on the twin: proves the twin half can fail at all |

**Controls that must stay GREEN:**
- the twin passes 8.2.1 under m1 and m2, which touch Postgres only: the contract fails per repository, not all at once;
- `migration_reversibility_test.dart` passes on B1's migrations with no marker.

**Each mutation asserts that the file changed before trusting a green** (verification §11).

### 8.7 As built (B1, 2026-11-23)

**Red first, on committed code** (commit `81184258`, tests only):
- §8.1: `Expected: 'XAF'`, `Actual: <null>`;
- §8.2.1 on Postgres, `book` and `bookManual`: « create lost "currency": the service wrote it, the read dropped it »; green on the twin;
- §8.2.2: `<null>` on Postgres, `'EUR'` on the twin;
- §8.4: « Acompte reçu : 5000 FCFA » for a booking stamped `EUR`;
- §8.2.3: green, as stated.

**After the fix** (commit `4234477c`):
- the Postgres appointment group, 9 tests, green; key parity passing on both paths confirms `currency` was the only key Postgres lost;
- 172 tests green across the in-memory contract, the notifier, multi-pays (with the tripwire), migration reversibility and timeouts, and appointments.

**Mutations, on committed code, by a harness that refuses a dirty tree, asserts each edit changed the file, and requires the named failure text, not just a non-zero exit:**
- m1–m11 with m6b and m8b, 13 in all: **all red for the stated reason**;
- C1 (the twin under m1) and C2 (reversibility with no marker): green;
- **one false red, caught by the needle:** the first m1 dropped the column and the placeholder but not the parameter, and went red on the driver's « Contains superfluous variables: currency », not on a lost value. Rerun with all three halves, it went red on `Actual: <null>`. A check on the exit code alone would have counted the first run.

**The contract text:** `web/lib/api/schema.ts` regenerated with the lockfile's `openapi-typescript` 7.13.0. Control first: a run on the unchanged contract left no diff; after the rewording, exactly one generated line changed.

### 8.8 As built (B3, 2026-11-23)

**What changed in the app**, as §5.3 and §5.7 list it:
- **Pro screens:** the list, the calendar's day list, the booking detail (total and announced deposit) and the client card's visit rows read `appointment.currency` first, and the salon's only as the fallback;
- **earnings:** `EarningsTransaction` gains `currency`, and each « Revenus » row reads it first;
- **exports:** both data exports' booking rows carry `currency`;
- **mocks:** a new booking is stamped with its salon's currency, and each earnings row with the booking's.

The totals are unchanged (decision 190).

**Red first, on committed code** (commit `233fcb2a`, tests only):
- every widget test checks a **currency-blind control** first: the booking's amount, or the visit history and its unique price, is on screen. A missing « EUR » can therefore only mean the wrong currency.
  - **The control caught one false red:** the first client-card run failed because the history is below the fold of the default test surface. The test now uses a tall surface, as the existing history test does.
- the five Pro rows found no « EUR »; both export rows and the mock's booking had `currency: null`.

**After the fix** (commit `c1271516`):
- `flutter analyze`: no issues;
- 225 tests green across the new and neighbouring suites;
- **the full mobile suite: 4035 passed, 68 skipped** (the goldens, which skip on the Mac and run in CI).
- No rendering changes while every salon is XOF, so no golden moves.

**Mutations, on committed code** (a harness that refuses a dirty tree, asserts each edit applied, and rejects a red that names a control):
- **m1–m10, each reverting one site, all red for the stated reason:** the list, the calendar, the detail's total, the detail's deposit, the visit row, the « Revenus » row, `EarningsTransaction.fromJson`, both export rows, and the mock's stamp;
- **C1, green:** with the list reverted, the calendar's test stays green, so each test is aimed at its own row.

### 8.9 As built (B2, 2026-11-23)

**What changed:**
- **migration `0049_appointment_currency_not_null`:** `kAppointmentCurrencyBackfill` again, then `ALTER COLUMN currency SET NOT NULL`;
  - declared `// rollback-unsafe:`, naming `myweli-api-00055-jv2` as the furthest a rollback may go;
- **DEPLOYMENT.md's rollback paragraph** names `0049` as the constraint to watch;
- **the contract:** the description changes, and the field stays nullable (§3.7, the replay window);
- **fixtures:** the volume probe tool's INSERT and the salon purge test's fixture name a currency;
- **the backfill test (§8.3)** writes its older-image rows on one connection inside `BEGIN … ROLLBACK`, after lifting the NOT NULL there.

**Red first** (commit `e9edb244`, tests only): the new test « the column refuses a booking without a currency (23502) » was red on today's schema (`is_nullable` `'YES'`). The restructured backfill test and the purge test stayed green.

**The full suite found one more:**
- a test fixture that built a booking map by hand without a currency, in the B6.10 account-deletion test;
- 0049 refused it with 23502: the constraint caught, on the first run, a writer the booking service would never have been;
- the fixture now names `XOF`.

**Verification:**
- **a misleading green, caught:** the first full run printed « exit 0 », but that was `tail`'s status, and the run had one failure. The suite was rerun with its own exit code.
- **now:** the full backend suite, on a fresh database with `DATABASE_URL`, **2974 passed, 2 skipped** (the R2 live tests); format 0 changed; analyze no issues.

**Mutations, on committed code:**
- **m1, red:** 0049 loses its `// rollback-unsafe:` declaration, and `migration_reversibility_test.dart` names it;
- **m2, red:** 0049 does not set NOT NULL, and the 23502 test goes red. It ran **on a fresh database**: one that has recorded 0049 never runs it again, so the mutation would have changed nothing there.
- **C1, green:** the same test, on a fresh database, with the committed code.
- **Not tested, said plainly:** removing the backfill from 0049. A test database has no NULL row at migration time, so nothing could tell. In production that failure is loud and safe: `SET NOT NULL` would fail on a NULL row, the revision would never become ready, and the old one would keep serving. Production has no NULL row (read 2026-11-23 18:03 UTC).

**The contract text:** `web/lib/api/schema.ts` regenerated (one line).
- Control: `HEAD`'s contract regenerates `HEAD`'s `schema.ts` byte for byte.
- Merging this PR touches `web/` (the generated doc string), so it is a production web deploy under the usual rule, with nothing visible.

---

## 9. Rollout — production data is real

Staging is retired (`infra/gcp/staging.state` = `absent`). A merge builds and pushes the image and deploys nothing, and « Nothing has rehearsed it; CI's boot smoke and the deploy's verify step are what run before production » (`DEPLOYMENT.md:621-625`).

**Step 0, before B1's deploy: production read-only, on the owner's yes (Q6).** Three `SELECT`s in Cloud SQL Studio; no write.

```sql
SELECT code, currency FROM countries;
SELECT CASE jsonb_typeof(data)
         WHEN 'string' THEN
           CASE WHEN pg_input_is_valid(data #>> '{}', 'jsonb')
                THEN (data #>> '{}')::jsonb ->> 'currency' END
         ELSE data ->> 'currency'
       END AS currency, count(*)
  FROM providers GROUP BY 1;
SELECT count(*) FROM appointments;
```

**Expected:**
- one row, `CI | XOF`;
- one group, `XOF`;
- a count, for §7.

**What stops or pauses the rollout:**
- **any currency other than `XOF` stops it:** the backfill would then be a guess, and this spec returns to the owner;
- **a `NULL` group pauses it:** salons whose currency cannot be read (no key, or a document that is not valid JSON). Their bookings would get `XOF`, which is right while only `XOF` exists; the group is named to the owner before the deploy rather than discovered after.
- The second query is also a dry run of the backfill's decode, on every salon.

**B1: backend, one PR.**
1. **Tests first:** §8.1–§8.5, red on committed code, recorded.
2. **The fix:** migrations, the repository, the twin, the notifier line.
3. **The docs, in the same PR:**
   - the contract (§4), and `web/lib/api/schema.ts` regenerated from it;
   - T57 (§6);
   - `modules/multi-pays.md` §4.1 and §10;
   - this spec's status;
   - a roadmap entry.
4. **Checks:** `dart format`, `dart analyze --fatal-infos --fatal-warnings` = 0, the full backend suite with a database, then CI green.
5. **Merge on the owner's word.** It builds the image; nothing is deployed.
6. **Production dispatch on the owner's word:** `deploy-backend.yml` with `environment: production`, `confirm: deploy`, `image_tag: <merge sha>`. The migration runs at boot, before the port opens.
7. **Read-back, against what runs:**
   - `status.traffic[].revisionName` names the new revision;
   - `/health` returns 200;
   - no error logged by the new revision;
   - `GET /appointments` for a real account returns `currency` on each booking;
   - on the owner's yes, `SELECT currency, count(*) FROM appointments GROUP BY 1` shows `XOF` only, with `NULL` at 0 or a handful from the deploy window (§3.3);
   - `gh run list --workflow=production-checks.yml --limit 3` (verification §16).
8. **A records PR:** the roadmap entry turns 🟢 and the spec is « Built ».

### 9.1 As run (B1, 2026-11-23)

Each step on the owner's word, in this order: « Yes, merge it », « Yes, run them », « Yes, deploy it ».

**Merged:** #840, squash `d80b4303` on `be39d114`, pinned to the tested head `8929a70f`; `main`'s tree equals it (CI 12/12 on the PR, 10/10 on `main`). The push built and pushed image `d80b430`; staging is absent, so nothing was deployed by it.

**Step 0, 17:50 UTC, read-only.**
- **Method:** the Cloud SQL Auth Proxy with `--gcloud-auth` on `127.0.0.1:15433`, stopped after. The database URL (secret `DATABASE_URL` v1) was held in environment variables only and never printed. The session was set `default_transaction_read_only=on`, and every query ran inside `BEGIN READ ONLY … ROLLBACK`.
- **Control:** a probe write (`UPDATE providers SET id = id WHERE false`) was **refused**. The same probe was first shown to pass without the setting and to be refused with it, on a throwaway local database that was then dropped.
- **Results** (aggregates only):
  - countries: `CI | XOF`, one row;
  - salons by currency, through the backfill's own decode: `XOF | 8`, no unreadable group. All 8 documents are JSON strings (2026-11-20), so the naive `data->>'currency'` would have read `NULL` for all 8;
  - bookings: **4**.
- **Verdict:** as expected. The backfill is exact, and `pg_input_is_valid` exists in production, so 0048 can run.

**Deploy, 18:00:30 UTC:** `deploy-backend.yml`, `environment: production`, `confirm: deploy`, `image_tag: d80b430`, run `45233724565`. Every step succeeded, including « Verify the revision actually serves ». The rollback target is `myweli-api-00054-7lb`, which was serving 100 % with no pin; B1 is additive, so pinning back to it is safe.

**Read-back, 18:02–18:03 UTC, against what runs:**
- `status.traffic`: `myweli-api-00055-jv2`, 100 %, `latestRevision`; the revision is labelled `commit: d80b430`, Ready, image `…/api@sha256:23d738b8…`;
- `https://api.myweli.com/health`: HTTP 200, `env: prod`;
- the new revision's logs: 21 entries, none at `ERROR` or above;
- read-only, the same method and control as step 0:
  - `0047_appointment_currency` applied at 18:01:33.38 and `0048_appointment_currency_backfill` at 18:01:33.48;
  - the column is `currency | text | nullable`;
  - bookings by stored currency: **`XOF | 4`**, with **no `NULL`**, so no booking was written by the old revision during the switch;
- `production-checks.yml`: the last three runs were green; they ran before the deploy, and the next scheduled run covers the new revision.

**Not read:** a booking through the API, because it needs a signed-in account. The stored value is observed above, and the read path is covered by §8.1 and §8.2.

**What this means for B2 — corrected 2026-11-23.** This first said that B2 « waits for one more backend deploy after this one ». That was wrong. When B2 deploys, the revision a one-step rollback reaches is the one serving now, `00055-jv2`, which writes `currency`: **B2 can be the very next backend deploy.** The constraint is a two-step rollback: once B2 is live, no rollback may go back past `00055-jv2` (to `00054-7lb` or older, which omit the column and would fail every booking with 23502). B2's `// rollback-unsafe:` line says exactly that, and DEPLOYMENT.md's rollback list gains it (§3.7).

**B2: the contract step** (§3.7, §8.9). Its own PR, deployed on the owner's word. It can be the next backend deploy, because a one-step rollback from it reaches `00055-jv2`, which writes `currency`.
- **Before:** no production read is needed. 0049 runs the backfill itself, and the last read found no NULL (18:03 UTC).
- **Read-back:** the serving revision, `/health`, and `is_nullable = 'NO'` plus the count by currency (read-only, on the owner's yes).

**B3: the app** (§5.3, and the two app exports of §5.7). Its own PR. It reaches users with the next builds of both apps; no store action of its own.
- It needs neither B1 nor B2: before B1 deploys, `currency` is absent and the fallback is today's.
- Goldens only if a rendering changes, and with one currency it does not.

**B4: the website** (§5.6, and the two website exports of §5.7). Its own PR. Its merge is a production web deploy, on the owner's word. Independent of B1 for the same reason.

**Rollback:**
- **B1 is additive.** Pinning traffic to the previous revision is safe: it ignores the column, and its bookings are written `NULL` and read as the salon's.
- **B2 is the one to declare** (§3.7).
- **What B1 changes about an earlier rollback:** nothing. It adds no constraint.

---

## 10. Definition of done (for the build, after the answers)

- [ ] Every test in §8 committed red first and watched red on today's code (8.2.3 and 8.5 excepted, as said); m1–m11 watched red with the file-changed assertion; the controls green.
- [ ] `dart format` clean · `dart analyze --fatal-infos --fatal-warnings` = 0 · backend suite green **with** `DATABASE_URL` · CI green.
- [ ] The contract (§4) with `web/lib/api/schema.ts` regenerated, T57 (§6) and `modules/multi-pays.md` §4.1/§10 corrected in the same PR as the code.
- [ ] `// Design: docs/design/appointment-currency-stamp.md` near the migration, the repository and the notifier line.
- [ ] Step 0 read and recorded (or Q6's alternative), the deploy read back against the serving revision (§9 step 7), and the numbers written here.
- [ ] Feature branch and PR; commits authored as the owner, with no attribution; merge and deploy on the owner's word.

---

## 11. Questions for the owner — answered 2026-11-23, « Approve as recommended » (decisions 187–193)

**Q1. The column.** Nullable now with a backfill, and `NOT NULL` in a second deploy (B2)?
- **Recommended: yes (option A, §3.1).** → ✅ **Decision 187.**
- Alternatives: `NOT NULL DEFAULT 'XOF'` at once (hides the next forgotten stamp); everything in one migration (a rollback would break every booking); nullable forever.

**Q2. What existing bookings get.** The salon's currency at migration time, else `XOF` (the booking service's own rule)?
- **Recommended: yes.** It is exact for every existing booking, because only `XOF` has ever existed (§3.3), and step 0 confirms it. → ✅ **Decision 188.**
- Alternatives: a literal `XOF` for all (the same result today, the wrong rule tomorrow); leave old rows empty (the contract keeps lying for them).

**Q3. The Pro screens and the exports.** In the app and on the website, does each booking's amount use the booking's own currency (B3, B4)? With the app's earnings rows reading their own currency, and all four data exports (client and salon, app and website) carrying each booking's currency?
- **Recommended: yes**, in two small PRs riding the next app builds and the next web deploy. → ✅ **Decision 189.**
- Alternative: leave them until a second currency exists. Cheap now, easy to forget then.

**Q4. Totals.** Revenue, « Dépensé » and the earnings total stay in the salon's current currency, and the client's « Passés » summary keeps its rule (the newest visit's currency, now its stamp), until a second currency exists?
- **Recommended: yes.** A mixed sum cannot occur today; multi-pays §4.6 (« no synthetic totals ») decides it then. → ✅ **Decision 190.**

**Q5. The market-change gap.** Today four writes can change a salon's currency and timezone, bookings or not: the area pick, a commune-only edit, the publish self-heal and the demo restore (§2.5). Add a tripwire test now that fails the day a second currency or timezone is added to the seed, and build the guard, covering all four, with that market?
- **Recommended: yes.** → ✅ **Decision 191.**
- Alternatives: build the guard now (no second market exists to exercise it against); or nothing, and T57 stays half-false.

**Q6. Reading production.** Step 0 before the deploy (three read-only `SELECT`s: countries, salons by currency, booking count) and one count after, each on your yes in Cloud SQL Studio?
- **Recommended: yes.** It turns "exact" from inferred into observed. → ✅ **Decision 192.** Approved in principle; each read is still asked for at the moment it runs.
- Alternative: the API read-back only (a booking now shows `currency`), which cannot see the other rows.

**Q7. When.** Build B1 next, independent of Track A: backend only, no app release?
- **Recommended: yes**, because the backfill is exact only while one currency exists. → ✅ **Decision 193.**
- B2, B3 and B4 follow, each on your word.

*Decisions 187–193 (171–181 are the home stories', 182–186 A1w's; 194–203 were then taken by A2, #839).*

---

## 12. Out of scope, and what this spec found next to it

- **A1w (spec #836, `319da3e7`; code #838, `95072597`), not edited here.**
  - Its §1 (`web-account-bookings-truth.md:52-56`) and its correction to `consumer-app-truth.md:260` call this « a backend task of its own ».
  - Two sentences say the summary is in `providerCurrency` « in production »: its spec (`web-account-bookings-truth.md:148`) and its code comment (`web/lib/account/appointments.ts:263-264`). Both are true until B1 deploys, then false (verification §7).
  - Once this spec merges, a records PR points §1 at it; B1's PR rewords both sentences.
- **The in-memory `update` merges any key, where Postgres knows six** (§3.5). Only `currency` is aligned here. A full whitelist would break `InMemoryClientsRepository`'s guest-phone change, which writes `clientPhone` through it (`clients_repository.dart:312`), so it needs its own small design.
- **The locality seed reaches Postgres only when `countries` is empty** (`migrations.dart:1784-1786`). Yet its comment says « a new market appends rows there and redeploys », and the area check falls back to the seed (`provider_catalog_service.dart:227`, `:376-379`). How a second market reaches production is therefore undecided. It belongs to the multi-pays wave that adds it, alongside Q5's guard.
- **Migration `0021`'s `data->>'slug'`** (§2.7): history; nothing to do.

---

## 13. Review log

**2026-11-23, one independent read-only reviewer, told to refute the draft against the code.**
- **No blockers.** It re-checked the claims in §2 and found them right, among them: the 18-column INSERT, `_toDto`, the six-key `update`, both stamps, the only three callers of `create`, the JSON-string storage (the driver JSON-encodes a Dart `String` sent as `jsonb`), the backfill's validity on both forms, that splitting the migration releases the lock, and that B1's rollback is safe (the old image reads named keys, and the driver prepares a fresh statement per call, so no cached-plan error).
- **Eight should-fix findings, each re-checked in the code and folded in:**
  1. the key-parity test could not go green on `update` (it changes `status`), compared the twin to itself without a copy, and guarded only `bookManual`'s map (§8.2.1);
  2. two tests are green today by design, and now say so (§8);
  3. B1 must regenerate `web/lib/api/schema.ts`, or CI fails (§4);
  4. B2 breaks two raw INSERTs, `apptMap`'s default and §8.3's NULL rows (§3.7);
  5. the four data exports were missing (§5.7);
  6. a salon's currency changes through four writes, not one (§2.5, §6, Q5);
  7. a bare cast in the backfill could fail every deploy on one invalid document: the guarded form, R6 and m10 (§3.2, §8.3);
  8. the « Passés » summary is a total, with its own rule (§5.2, Q4).
- **Nits, folded in:**
  - the table's migration is `0002`;
  - the demo reset's call is at `:281`;
  - the notifier test needs a non-franc code;
  - the website's earnings rows are the Pro exception;
  - `JournalPanel.tsx:193` is a total;
  - the reversibility test requires sorted ids and scans comments;
  - the `NOT VALID` escape needs a hand-written declaration;
  - the backfill's per-row cost;
  - the whitelist follow-up breaks a caller;
  - suite isolation;
  - m1 must drop both halves;
  - the git history behind « never stored ».
- **Two of the author's own, before the review:** the notifier and client tests must use a non-franc code, because both formatters print « FCFA » for `XOF` and `XAF`; and 8.2.3 is a pin, green today.
