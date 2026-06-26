# Booking duration-overlap exclusion (btree_gist) — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Booking integrity · V1 (T11 follow-up) |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ |

## 1. Goal & scope

Close the **T11 follow-up**: today overbooking is prevented by (a) the app-level slot engine and (b) a Postgres **partial unique index** on `(provider_id, appointment_date)` — which only rejects an **exact-start** collision. Two bookings at **different starts but overlapping durations** (e.g. a 09:00–11:00 service and a 10:00 booking) can still slip through **under concurrency** (both pass the app check, then both insert). This slice adds a **Postgres `btree_gist` EXCLUDE constraint** so any duration overlap for the same provider is rejected **atomically at the database**.

**In scope (backend only):**
- Store the booking's **duration** so the DB knows its time span.
- A `btree_gist` EXCLUDE constraint on `(provider_id =, time-range &&)` for active bookings.
- `PostgresAppointmentRepository.create` (and the reschedule `update`) treat an exclusion violation as `slot_unavailable` (return null), exactly like the exact-start path.
- Threat-model T11 update + tests (DB-gated).

**Out of scope:** changing the app-level slot engine (unchanged — still the first line + the only check the in-memory repo needs); the **buffer** stays an app-level courtesy gap (the DB invariant is "no two service-time ranges overlap"); no API/contract behaviour change (a blocked booking is still `409 slot_unavailable`).

**Build:** one PR.

## 2. UX & flows
No user-facing change. A racing second booking that would overlap now reliably gets the same `slot_unavailable` (409) it already gets sequentially — just now guaranteed under concurrency.

## 3. API & contract
No new endpoint. Booking still returns **409 `slot_unavailable`** when the slot is taken (now including concurrent duration overlaps). The `Appointment` schema gains an optional read-only **`durationMinutes`** (server-computed) so the stored span is visible.

## 4. Data model (migration `0009`)
- `ALTER TABLE appointments ADD COLUMN duration_minutes int NOT NULL DEFAULT 30` — the booked services' total duration (server-computed). Default covers any legacy rows; new bookings always set it.
- `CREATE EXTENSION IF NOT EXISTS btree_gist;`
- The exclusion constraint (active bookings only — mirrors the existing index predicate):
```sql
ALTER TABLE appointments ADD CONSTRAINT appointments_no_overlap
  EXCLUDE USING gist (
    provider_id WITH =,
    tstzrange(appointment_date,
              appointment_date + make_interval(mins => duration_minutes)) WITH &&
  ) WHERE (status IN ('pending', 'confirmed'));
```
The existing exact-start partial unique index is **kept** (a positive-duration overlap also covers exact starts, so it's redundant, but keeping it is zero-risk and leaves the proven `ON CONFLICT` path untouched). Range is **half-open** `[start, end)` → back-to-back bookings (one ends exactly when the next starts) are allowed. The constraint is added to an **empty** `appointments` table (pre-launch) — no backfill conflict.

## 5. Architecture & patterns
- **`BookingService.book` + `bookManual`** already loop the services to price them — also **sum `durationMinutes`** there and put `durationMinutes` in the appointment map. (No new dependency; same data already in hand.)
- **`AppointmentRepository`**: `create` stores `durationMinutes`; `_toDto` returns it. In-memory keeps storing the map as-is (no constraint — the slot engine remains its guard).
- **`PostgresAppointmentRepository`**:
  - `create`: keep the `INSERT … ON CONFLICT (exact-start) DO NOTHING` (→ null), **wrapped** so a `ServerException` with `code == '23P01'` (exclusion_violation = duration overlap) also returns **null**. Other errors rethrow.
  - `update`: a reschedule that moves the date onto an overlapping slot now throws `23P01`; catch it → **null** (status-only transitions never change the range, so they never hit it).
- **`AppointmentLifecycleService._moveTo`** (reschedule): if `update` returns null → `slot_unavailable` (the DB backstop behind the app slot check).

## 6. Security & authz
No new surface. Strengthens integrity: the DB is now the authority that **no two active bookings overlap per provider**, independent of app-level races. (BACKEND.md §3.4 — server is the authority; §3.7 idempotency note unaffected.)

## 7. Performance
- The GiST index backing the constraint makes the overlap check indexed (no scan). One extra index on inserts/date-updates — negligible at V1 volume. No N+1; no read-path change.

## 8. Testing plan
- **DB-gated (`@Tags(['postgres'])`):**
  - Insert a booking spanning 09:00 + 120 min; a second **overlapping** booking at 10:00 (same provider, pending/confirmed) → `create` returns **null**.
  - A **non-overlapping** booking at 11:00 (back-to-back) → succeeds.
  - **Cancelling** the first frees the range (a later overlapping insert succeeds).
  - A **different provider** overlapping in time → succeeds (per-provider).
  - Reschedule `update` onto an overlapping slot → null (and `_moveTo` → slot_unavailable).
- **Service (in-memory):** `book`/`bookManual` put `durationMinutes` in the appointment (= sum of service durations). Existing sequential double-booking test still passes (slot engine).
- **Migration:** runs clean on an empty table; idempotent.

## 9. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 · tests green (incl. DB-gated).
- [ ] OpenAPI: `Appointment.durationMinutes` (optional, read-only).
- [ ] Threat model **T11** updated (overlap now DB-enforced); ROADMAP entry; spec cross-linked from the migration/repo. Status → Built.
- [ ] Feature-branch + PR; CI green (the Postgres job is the real check); no Claude attribution.

## 10. Decisions (signed off)
1. **DB guards raw service overlap** (`[start, start+dur)`); the per-provider buffer stays an app-level slot-engine concern (baking it in would wrongly reject valid back-to-back-with-buffer bookings). ✓
2. **Keep the exact-start unique index** (redundant under the EXCLUDE but zero-risk; leaves the `ON CONFLICT` path untouched, with the `23P01` try/catch added on top). ✓
