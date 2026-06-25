# Provider services & availability — backend — design spec

| | |
|---|---|
| **Status** | Approved — build in 2 PRs (foundation → endpoints) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro services + availability management · V1 |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ (myweli-dev-guardrails for the later app slice) |

## 1. Goal & scope

Let a salon **manage its own catalogue and working hours** on the real backend: create / update / delete / enable-disable its **services**, and read / replace its **availability** (weekly hours, breaks, buffer, blocked dates). Backs the pro app's `ProServiceInterface` service + availability methods (still on `MockProService`). Availability feeds the live slot engine, so editing hours/buffer immediately changes what consumers can book.

**Storage decision — fully normalize** (the app isn't launched, so build the scalable/standard shape, not the frontend-first JSONB blob): services and availability move out of the `providers.data` document into real tables with FK integrity.

**Build in two PRs** (lower risk, each green on its own):
- **PR 1 — normalization foundation (behaviour-preserving):** new tables + backfill out of `data`; `ProvidersRepository` **assembles** the provider DTO from the tables so reads / slot engine / booking are byte-identical. No new endpoints. All existing tests stay green + new assembly/backfill tests.
- **PR 2 — management surface:** the 6 endpoints + `ProviderCatalogService` (validation + ownership) + `Service.active` (enable/disable; inactive = not bookable) + contract + threat model + tests.

**Out of scope (separate slices):** the app `ApiProService` mock→HTTP swap (next slice); gallery photos; deposit policy; artists CRUD; per-artist availability.

## 2. UX & flows
Backs existing pro screens (`service_list_screen`, `service_form_screen`, `availability_screen`) — no UX change here; the app-swap slice keeps the same UX behind the existing interface.

## 3. API & contract (PR 2)

All endpoints **provider-authenticated** (role `provider`) + **ownership-scoped**: token `account.providerId` must equal `{id}` → else **403** (mirrors pro-appointment authz T5). Body `providerId` ignored; server uses the path.

| Method | Path | Body | Success |
|---|---|---|---|
| GET | `/providers/{id}/services` | — | 200 `{items,page,pageSize,total}` |
| POST | `/providers/{id}/services` | service fields | 201 `Service` (server sets `id`,`providerId`,`active=true`) |
| PATCH | `/providers/{id}/services/{serviceId}` | partial (incl. `active`) | 200 `Service` (404 if not this salon's) |
| DELETE | `/providers/{id}/services/{serviceId}` | — | 204 |
| GET | `/providers/{id}/availability` | — | 200 `Availability` |
| PUT | `/providers/{id}/availability` | full `Availability` | 200 `Availability` (full replace) |

**Errors:** 400 `invalid_body`/`invalid_input`, 401 `unauthorized`, 403 `forbidden`, 404 `not_found`, 405.

**Contract/DTOs** (mirror Dart models): add `Service.active: boolean` (default true; also added to Dart `Service` + mock); add `Availability` + `TimeSlot` schemas. The provider DTO stays byte-compatible — services/availability still appear embedded (assembled by the repo).

## 4. Data model (PR 1 — migration `0005_provider_catalogue`)

```
provider_services (
  id text PK, provider_id text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  name text NOT NULL, description text NOT NULL DEFAULT '',
  price double precision NOT NULL, price_max double precision,
  duration_minutes int NOT NULL, duration_variants jsonb NOT NULL DEFAULT '{}',
  artist_ids jsonb NOT NULL DEFAULT '[]', active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now())
  INDEX (provider_id)

provider_availability (provider_id text PK REFERENCES providers(id) ON DELETE CASCADE,
  buffer_minutes int NOT NULL DEFAULT 0)            -- the scalar config + anchor row

provider_working_hours (
  id text PK, provider_id text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  weekday smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),   -- 0=Mon..6=Sun
  start_time time NOT NULL, end_time time NOT NULL,
  is_available boolean NOT NULL DEFAULT true)
  INDEX (provider_id)

provider_breaks ( id text PK, provider_id text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  weekday smallint NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  start_time time NOT NULL, end_time time NOT NULL)
  INDEX (provider_id)

provider_blocked_dates ( provider_id text NOT NULL REFERENCES providers(id) ON DELETE CASCADE,
  blocked_date date NOT NULL, PRIMARY KEY (provider_id, blocked_date))
```

- **`TimeSlot` round-trip:** the model is `{startTime,endTime,isAvailable}` as full ISO datetimes, but the slot engine only uses **time-of-day** (`hour*60+min`) and the `isAvailable` flag. So we store `time` columns and, on assembly, reconstruct each `TimeSlot` with a **canonical placeholder date `2024-01-01`** + the time + `is_available`. Byte-faithful to what the engine/app expect.
- **Backfill (PR 1, in Dart at startup):** if the new tables are empty but providers exist, read each provider's `data` (services + availability), insert the normalized rows, then `UPDATE providers SET data = data - 'services' - 'availability'` → **one source of truth**. (Not launched ⇒ effectively only seed data exists; SQL-in-jsonb parsing avoided by doing it in Dart.)
- **Seed:** `seedProvidersIfEmpty` also populates the 5 tables from the Dart `seedProviders` (or runs the same extract) so a fresh DB is consistent.

## 5. Architecture & patterns

- **Repository is the assembly point (PR 1).** `ProvidersRepository.byId`/`query` return the **full provider DTO** = core (`data`) **+ services** **+ availability** assembled from the tables. So the slot engine, booking service (server-authoritative pricing reads `provider['services']`), and `GET /providers*` are **unchanged at their boundary**. List assembly **batches** (`WHERE provider_id = ANY(@ids)`, group in memory) → no N+1 (≈6 queries for a page regardless of size).
- **Write methods (PR 2):** `servicesFor / addService / updateService / deleteService` and `getAvailability / replaceAvailability` — in-memory + Postgres behind the one interface. `replaceAvailability` is a **transaction**: delete the provider's working-hours/breaks/blocked-dates/buffer rows and reinsert (clean full replace).
- **Routes** (PR 2, thin): principal → require `role==provider` → validate → delegate → shape; one file per path under `routes/providers/[id]/…`.
- **`ProviderCatalogService`** (PR 2; no dart_frog/SQL): resolves `account.providerId` via `ProviderAuthRepository.accountById`, enforces ownership (403), validates, mutates via repo, returns `(ok,error,data)` — mirrors `ProAppointmentService`.
- Wired in `dependencies.dart`; provided via middleware.

## 6. Security & authz (PR 2)
- **Deny by default**; provider token + **ownership** (`account.providerId == path id`) on every endpoint → 403 on mismatch / unlinked. Public still reads services via `GET /providers/{id}`.
- **Validation (400):** `name` non-empty; `price ≥ 0`; `priceMax ≥ price` if set; `durationMinutes > 0`; `durationVariants` values `> 0`; `artistIds` (if sent) reference this salon's artists; availability weekday ∈ 0..6, each window `start < end`, `bufferMinutes ≥ 0`, `blockedDates` parseable. Unknown fields ignored.
- **Server authority:** a provider is price authority for **their own** salon only; client `id`/`providerId` never grant cross-salon access; `serviceId` server-generated. `ON DELETE CASCADE` keeps integrity.
- **Threat model:** add **T12 — provider self-management** (edits only its own salon; ownership 403; bounded input).

## 7. Performance
- Indexed keys (`id` PK, `provider_id` indexes); list assembly batched (no N+1); per-service update touches one row (no whole-document rewrite / lost-update window); bounded payloads. Budgets (BACKEND.md §4) respected.

## 8. Testing plan
- **PR 1 — migration/backfill + assembly (DB-gated):** seeded providers' services/availability land in the 5 tables; `data` no longer carries them; assembled `byId`/`query` return them **embedded & identical** (contract preserved); slot engine + booking unchanged (existing suites stay green); TimeSlot reconstructs to the canonical date.
- **PR 2 — service (unit):** validation → 400; ownership mismatch + unlinked → forbidden; create sets id/providerId/active; update merges (incl. `active`); delete removes; `replaceAvailability` round-trips.
- **PR 2 — handler:** each route success + 400 + 401 + 403 (cross-salon) + 404 + 405.
- **PR 2 — contract:** responses match new paths + `Service.active` + `Availability`/`TimeSlot`.
- **Security/negative (required):** another salon's token → 403; unlinked → 403; no/invalid token → 401.
- **Slot-engine integration:** an inactive service isn't bookable; after `PUT availability` (raise buffer) the engine reflects it.

## 9. Rollout & scope discipline
- Two PRs (foundation → endpoints), each green before the next. Backend-only; no app behaviour change until the follow-up `ApiProService` swap (behind `useApiBackend`, mock default). V1 scope.
- Migration is backward-safe: the assembled DTO keeps the provider contract identical, so shipped reads / booking / slots keep working.

## 10. Definition of done (per PR)
- [ ] `dart format` clean · `dart analyze` = 0 · backend tests green (+ DB-gated in CI incl. migration/backfill).
- [ ] OpenAPI updated in the same PR (PR 2: 6 paths + `Service.active` + `Availability`/`TimeSlot`); Dart `Service` model + mock gain `active` (PR 2).
- [ ] Threat model **T12** added (PR 2); ROADMAP entry added; spec cross-linked from the new tables/routes/service + contract; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (all signed off)
- **Service `active` flag → YES** (toggle = PATCH `active`; inactive not bookable). ✓
- **Scope → backend now**, app `ApiProService` swap is the next slice. ✓
- **Storage → fully normalized** tables (services + availability working-hours/breaks/blocked-dates/buffer), repo assembles the DTO; migrate + backfill out of `data`. ✓
- **Build → two PRs** (normalization foundation, then management endpoints). ✓
