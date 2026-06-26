# Pro manual (walk-in/phone) booking — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro manual booking · V1 |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ (myweli-dev-guardrails for the app swap) |

## 1. Goal & scope

Let a salon enter a booking itself — a client with no app account — directly onto its calendar, confirmed immediately with no online deposit. The booking time is **arbitrary**, covering all salon-entered cases:
- a **walk-in** happening now, or one **logged after the fact** (a past time);
- a **future appointment booked by phone** (a client calls today and books for next week).

A future manual booking is created `confirmed` and **occupies that slot for app consumers** — the slot engine excludes *all* non-cancelled bookings regardless of origin, so an online client can't double-book a phone-booked slot. (Exact-start collisions are DB-guarded → 409; **duration-overlap** collisions remain the system-wide pending follow-up, threat model T11 — not specific to manual booking.)

Backs `ApiProService.createManualBooking` (today on `MockProService`).

**In scope:**
- Backend: `POST /providers/{id}/appointments` (provider-authenticated, ownership-scoped) → 201 `Appointment` (status `confirmed`). Server prices it from the salon's services; stores `clientName`/`clientPhone`.
- App: `ApiProService.createManualBooking` → the endpoint; the rest of `ProServiceInterface` unchanged.
- Contract (the path; `Appointment` already in the contract) + threat model + tests.

**Out of scope:** the **SMS invite** (`sendSmsInvite`) — notifications/SMS are a deferred integration (PRD §8); the flag is accepted but a no-op for now. Deposits (no online deposit for walk-ins — paid in person). Per-artist assignment beyond the existing `artistId`.

**Fit:** mirrors the consumer booking pricing (server-authoritative) but is a distinct salon-initiated path (confirmed, no deposit, sentinel client). New `BookingService.bookManual`; route does authz (role + ownership); reuses the existing `AppointmentRepository.create` (no migration). App swap is the same `RefreshingHttpClient` pattern (provider session + silent refresh).

## 2. UX & flows
No UX change — `pro_manual_booking_screen` already exists and drives this behind `ProServiceInterface`; loading/empty/error/success handled there. (The screen collects services, date/time, optional client name/phone, notes.)

## 3. API & contract
`POST /providers/{id}/appointments` — **provider** token + **ownership** (`account.providerId == {id}` → else 403). Body:
```
{ serviceIds:[string]  (required, non-empty),
  appointmentDateTime: string (ISO, required),
  artistId?: string, clientName?: string, clientPhone?: string,
  notes?: string, sendSmsInvite?: bool (accepted, no-op) }
```
Success **201 `Appointment`** (status `confirmed`, server-priced, `depositAmount:0`, `balanceDue:total`, `userId:"manual"`, `clientName`/`clientPhone` set). Errors: 400 `invalid_input`/`invalid_body`, 401 `unauthorized`, 403 `forbidden`, 404 `provider_not_found`, **409 `slot_unavailable`** (exact-start already booked), 405.

`Appointment` schema already in the contract — no schema change, just the path. `providerId`/`userId`/`status`/`id`/price are **server-set** (client-sent values ignored).

## 4. Data model
None. Reuses `appointments` (`user_id` is `text NOT NULL`, **no FK** — so the sentinel `"manual"` is valid; matches the mock). The partial unique index on `(provider_id, appointment_date)` for non-cancelled statuses still applies → atomic exact-start double-book guard.

## 5. Architecture & patterns
- **`BookingService.bookManual({providerId, serviceIds, appointmentDateTime, artistId, clientName, clientPhone, notes})`** — looks up the provider, prices from its services (rejecting unknown/`active:false` → `invalid_service`), builds a **`confirmed`** appointment (`userId:"manual"`, deposit 0), and `create`s it. **No slot-engine validation** (walk-ins are arbitrary/off-grid times — see open question); the DB unique index still rejects an exact-start collision (`create` → null → `slot_unavailable`). Identity-agnostic, like `book`.
- **Route** `POST routes/providers/[id]/appointments.dart` (thin): principal → require `role==provider` → **authorize ownership** (`ProviderAuthRepository.accountById(sub).providerId == {id}` → else 403) → validate body → `bookingService.bookManual(...)` → shape (201 / 409 / 400 / 404). (Authorize-in-route is the documented route responsibility, BACKEND.md §1.)
- App: `ApiProService.createManualBooking` → `_authed.send(POST …/appointments)` → `Appointment.fromJson`.

## 6. Security & authz
- Deny by default; provider token + ownership (403 cross-salon/unlinked). The salon may only create bookings for **its own** Provider.
- **Server authority:** price/total/deposit/status/id/userId are server-set; client values ignored. Validate: `serviceIds` non-empty + each exists & active; `appointmentDateTime` parseable; `clientPhone` (if provided) E.164 (`isValidE164`) → else 400. `clientName`/`notes` trimmed; empty → null.
- No new secrets; nothing sensitive logged (a walk-in phone is PII — not logged).
- **Threat model:** extend **T5** — manual booking is a provider write scoped to its own salon (ownership 403).

## 7. Performance
- One provider read + one insert; the unique-index check is atomic. No N+1. Budgets respected.

## 8. Testing plan
- **Service (unit):** prices from the salon's services; creates a `confirmed`, deposit-0, `userId:"manual"` appointment with client name/phone; unknown/inactive service → `invalid_service`; empty services → `no_services`; an exact-start collision with an existing non-cancelled booking → `slot_unavailable`.
- **Handler:** `POST` success → 201 `confirmed`; no token → 401; cross-salon → 403; bad body → 400; bad phone → 400; non-POST → 405.
- **Contract:** response matches `Appointment`.
- **Security/negative (required):** another salon's token → 403; unlinked → 403; no/invalid token → 401.
- **App:** `createManualBooking` POSTs to `/providers/{id}/appointments`, parses the `Appointment`; 401 → provider silent refresh; forbidden → error.
- DB-gated: a Postgres manual-create + the exact-start conflict (reuses the appointment repo, already DB-tested) — light addition.

## 9. Rollout & scope discipline
- Behind `useApiBackend`; mocks default; no UX change. V1. `sendSmsInvite` is a no-op until the notifications slice.

## 10. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green (+ DB-gated in CI).
- [ ] OpenAPI updated (the path); responses match.
- [ ] Threat model T5 note; ROADMAP entry; spec cross-linked from the route/service + `ApiProService`; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (signed off)
1. **No slot-engine validation** — for walk-ins **and** future phone bookings alike (one rule; the salon is the authority on its own calendar). Only the DB exact-start unique index guards collisions (→ 409); the slot engine still excludes the booking from consumer availability. ✓
2. **Past times allowed** (log a walk-in after the fact). ✓
3. **`clientPhone` validated as E.164 when provided** (optional; empty/omitted is fine). ✓
4. **Future phone bookings use the same endpoint + same rule** as walk-ins (no separate path/validation). ✓
