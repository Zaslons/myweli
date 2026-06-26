# Pro-side reschedule — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro appointment management · V1 |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ (myweli-dev-guardrails for the app swap) |

## 1. Goal & scope

Let a **salon move one of its own bookings** to a new time, on the real backend — replacing `ApiProService.rescheduleAppointment`'s delegation to `MockProService`. The mirror of the consumer reschedule, but authorized by **salon ownership** instead of the booking's user.

**In scope:**
- Backend: make the existing **`POST /appointments/{id}/reschedule`** *role-aware* — a `provider` token reschedules by **salon ownership**; a `user` token keeps today's self-ownership path. New `AppointmentLifecycleService.rescheduleByProvider(...)` reuses the same slot-validation + date-move logic. No new path, no migration, no repo change.
- App: `ApiProService.rescheduleAppointment` → the endpoint (provider session + silent refresh), mapping `200` → `true`.
- Contract (note the provider branch) + threat model + tests.

**Out of scope:** a reschedule **UX** for the pro (no screen wires `proAppointmentProvider.reschedule` yet — this slice makes the call real for when one lands); notifying the client (notifications deferred); duration-overlap (system-wide T11 follow-up).

**Build:** one PR (backend role-branch + app swap).

## 2. UX & flows
No UX change in this slice. `proAppointmentProvider.reschedule(appointmentId, newDateTime)` already exists and optimistically updates the local list on success; it just needs a real backend. (A pro reschedule screen, when built, gets its own UX spec per the rules.)

## 3. API & contract
**`POST /appointments/{id}/reschedule`** — body `{ "newDateTime": <ISO-8601 UTC> }`. **Role-aware**, deny-by-default:
- **`user`** (unchanged): caller must own the booking (`appointment.userId == sub`) → else 403.
- **`provider`** (new): the token account's linked `providerId` must equal the booking's `providerId` → else 403 (unlinked account → 403 too).

Both branches: new time **must be an open, free slot** for that salon (see §6); deposit/balance carry over unchanged. Returns **`200`** with the updated `Appointment`.
Errors: 400 `invalid_body`/`invalid_input`, 401 `unauthorized`, 403 `forbidden`, 404 `not_found`, 409 `slot_unavailable` / `invalid_state`.

## 4. Data model
None. Reuses `appointments` (`byId`, `update` of `appointmentDate`). No migration.

## 5. Architecture & patterns
- **`AppointmentLifecycleService.rescheduleByProvider(id, providerId, newDateTime)`** (new) — identical to `reschedule` but the ownership check is `appointment.providerId == providerId` (the resolved managed salon) instead of `userId`. Same state guard, same `SlotService` re-validation, same date-only `update`. Keeps the slot logic in one place.
- **Route** `routes/appointments/[id]/reschedule.dart` — role-branch after parsing: `provider` → resolve `account.providerId` via `ProviderAuthRepository` (null → 403) → `rescheduleByProvider`; else → `reschedule` (today). Mirrors how `GET /appointments` is role-scoped. Still thin (parse → authorize → delegate → shape); error switch maps `not_found`→404, `forbidden`→403, else→409.
- **App:** `ApiProService.rescheduleAppointment` → `_authed.send(POST /appointments/{id}/reschedule, {newDateTime})` (provider `RefreshingHttpClient`); `200` → `ApiResponse.success(true)`, else `_errorFrom`.

## 6. Rules (server-authoritative; UTC)
- **State guard:** only non-terminal bookings move (`pending`/`confirmed`; `cancelled`/`completed`/`noShow` → `invalid_state`). Mirrors the consumer path.
- **Slot validation:** the new time must be one of `SlotService.availableSlots(provider, date, serviceIds)` (rejects **past / closed-day / already-taken** → `slot_unavailable`). This both keeps the salon on its own grid and guarantees the date-only `update` can't hit the exact-start unique index (no 500). ← see open question.
- Deposit, balance, services, artist unchanged — only `appointmentDate` moves.

## 7. Security & authz
- Deny by default; provider branch requires `role==provider` **and** salon ownership (cross-salon / unlinked → 403). A provider can never move another salon's booking; a user can never use the provider branch (role-gated).
- Validate body + `newDateTime` parse (400). Server is the authority on the new status/date; client only proposes the time.
- **Threat model:** **T11** already covers booking/reschedule slot safety; extend its note to include the **pro** reschedule branch (ownership-scoped, same slot guard).

## 8. Performance
- One `byId` + one `availableSlots` (precomputed engine, indexed by provider/date) + one `update`. Provider branch adds one `accountById`. No N+1, well within budgets.

## 9. Testing plan
- **Service (unit):** `rescheduleByProvider` moves a confirmed booking to a free slot (date updated; deposit/balance intact); cross-salon → forbidden; unlinked account → forbidden; terminal (`completed`/`cancelled`) → invalid_state; taken/closed/past time → slot_unavailable.
- **Handler:** provider token reschedules own booking → 200; cross-salon → 403; `user` token still self-reschedules (regression); no token → 401; bad body/date → 400; non-POST → 405.
- **Contract:** response is an `Appointment`; matches OpenAPI.
- **App:** `ApiProService.rescheduleAppointment` POSTs `{newDateTime}` to the path and maps 200 → true; 401 → provider silent refresh; conflict/forbidden → error.
- DB-gated: not required (no new SQL; `update`/`byId` already DB-tested).

## 10. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green.
- [ ] OpenAPI `POST /appointments/{id}/reschedule` description notes the role-aware (provider) branch.
- [ ] Threat model T11 note; ROADMAP entry; spec cross-linked from the route/service + `ApiProService`; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (signed off)
1. **Slot-validated** — the pro reschedule requires an open, free slot, exactly like the consumer reschedule (rejects past/closed/already-taken → `slot_unavailable`). Reuses the existing `SlotService` logic; no repo change, no exact-start-collision risk. (Off-grid moves stay the province of manual walk-in booking.) ✓
2. **State guard** mirrors the consumer path — `pending`/`confirmed` move; terminal states (`cancelled`/`completed`/`noShow`) → `invalid_state`. ✓
