# Multi-chair capacity + the web booking hub (parity with the app's flow)

| | |
|---|---|
| **Modules** | `journal` (the slot engine/capacity) + `online-booking` (the web funnel) — [MODULES.md](../MODULES.md) §1/§2 |
| **Status** | **Signed off** (2026-07-10) — capacity decisions locked in chat (§2); build = K1 backend → K2 web hub → K3 app |
| **Trigger** | The web↔app booking-flow audit (2026-07-10) found (a) the web funnel is a linear wizard while the app is an **order-free adaptive hub**, and (b) a deeper engine gap: **the whole salon is single-capacity** — one booking per salon per time slot regardless of team size, `/availability` is salon-level with no `artistId`, and even the app's API layer silently drops the chosen artist |
| **Why it matters** | A 3-stylist salon can only hold 1 booking per slot today — losing ~⅔ of its bookable capacity. The artist picker is currently cosmetic against the real backend |
| **Cross-refs** | [journal-j1-grid.md](journal-j1-grid.md) (drag-assign consumes this) · `booking_hub_screen.dart` (the reference UX) · BACKEND.md T11 (revised here) |

## 1. Ground truth (verified 2026-07-10)

- DB: `appointments_no_overlap EXCLUDE (provider_id WITH =, tstzrange &&)` +
  `appointments_slot_unique (provider_id, appointment_date)` — **salon-level**.
- `SlotService.availableSlots` has no artist concept; `GET /availability`
  takes no `artistId`; the app's `getAvailableTimeSlots` collects `artistId`
  but never sends it. The web never collected it for slots at all.
- `Artist.workingHours` exists on the model (per-weekday time slots) — unused
  by the engine.
- The app hub (read line-by-line): three sections visible at once; the FIRST
  interaction fixes an entry point (`services` | `artist` | `dateTime`) and
  the auto-advance order adapts; constraints run in every direction
  (services⇄artists capability, artist→slots, time-first default-30-min +
  re-validation, artist-first → earliest-slot auto-pick in 14 days,
  length-variant → duration/slots); sticky summary; Confirmer gates on
  services + time (artist optional).

## 2. Capacity decisions (user sign-off, 2026-07-10)

1. **Per-artist capacity.** A start time is bookable **for artist X** when X
   has no overlapping pending/confirmed booking, X can perform every selected
   service (`artistIds` capability rule, same as the app hub), and the time
   falls inside X's working hours when defined. **« Sans préférence »** is
   bookable when **at least one capable artist is free**; a salon with N
   capable artists can hold N parallel bookings.
2. **Unassigned bookings consume one chair.** A « Sans préférence » booking
   counts as one unit against the capable-artist pool at that time (app-level
   count inside the slot check); the salon assigns the artist later by
   dragging in the journal grid (built in J1). Accepted trade-off: a small
   race window under concurrency for *unassigned* bookings only (assigned
   bookings stay DB-enforced); pre-launch acceptable, hardening later.
3. **Artist working hours respected when defined**; artists without hours
   inherit the salon's hours. Salons with **zero artists keep today's
   behaviour** (capacity 1, salon hours) — nothing regresses.

## 3. K1 — backend: the artist-aware slot engine

- **`SlotService.availableSlots` gains `artistId`** and becomes
  capacity-aware:
  - `artistId` given → slots where THAT artist is free (their bookings +
    their hours ∩ salon hours/breaks/blocked) and capable of `serviceIds`.
  - No `artistId`, salon has artists → slots where
    `overlapping(pending|confirmed) < capableArtists(serviceIds, time)`
    (unassigned bookings count as 1 each; assigned count against their
    artist AND the pool).
  - No artists → today's single-capacity logic unchanged.
- **`GET /availability` accepts `artistId`** (validated: belongs to the
  salon → else ignored/400).
- **Booking-time enforcement** (server authority — the slot check re-runs on
  create/manual/reschedule already; it inherits the new logic):
  - Migration **0026**: drop the salon-level `appointments_no_overlap` and
    `appointments_slot_unique`; add **per-artist** versions
    (`(provider_id, artist_id, appointment_date)` unique and
    `EXCLUDE (provider_id WITH =, artist_id WITH =, tstzrange &&)` for
    non-null artists, `WHERE status IN ('pending','confirmed')`). Unassigned
    (`artist_id IS NULL`) rows rely on the app-level pool count (§2.2).
  - Reschedule + drag (J1) validate against the target artist's calendar.
- **Contract**: availability param + docs; threat **T11 revised** (per-artist
  double-booking; pool-count race documented for unassigned) — BACKEND.md.
- **Tests**: per-artist slot math (busy artist excluded, capable-pool counts,
  artist hours, zero-artist salons unchanged), booking/reschedule collision
  per artist (two artists same time OK; same artist → 409), unassigned pool
  exhaustion → `slot_unavailable`, PG constraint sections, T11 negatives.

## 4. K2 — web: the booking hub (faithful port of the app flow)

Replaces the linear wizard in `BookingFlow.tsx` (confirm/done steps kept):

- **Three sections always visible** (Prestations · Spécialiste · Date et
  heure) as cards with live summary values — stacked on mobile-web, side by
  side with the sticky summary on desktop (web-design-latitude: same flow,
  desktop-native layout).
- **Entry-point adaptivity**: the first interaction sets the entry point; the
  auto-advance (expand + scroll) follows the app's three orderings exactly
  (`services→artist→time`, `artist→services→time(auto-earliest)`,
  `time→services→artist`).
- **The constraint graph, ported 1:1**:
  - services⇄artists: incompatible artists dim/disable; an incompatible
    chosen artist is dropped (`_artistCanDoServices` logic);
  - artist → slots: `artistId` in every slot fetch (K1);
  - time-first: slots load with the 30-min default before services; the
    chosen time re-validates (and silently clears) when services/variants
    change;
  - artist-first + services → **earliest-slot auto-pick within 14 days** +
    « Prochain créneau : … » hint;
  - **length variants** (court/moyen/long): the selector appears when
    selected services declare variants; drives duration, slot fetches, and
    the `lengthVariant` booking param (the app's `booking_duration` helpers
    ported to `lib/booking/state.ts`).
- **Slot fetches carry a request id** (stale responses dropped — the app's
  `slotsRequestId` pattern).
- **Deposit proof in-flow**: when the created booking carries
  `depositAmount > 0`, the done step becomes the app's sheet equivalent —
  operator + number + **screenshot upload** (signed POST via `/uploads/sign`
  → `POST /appointments/{id}/deposit`) with « Acompte envoyé · en attente de
  confirmation du salon »; « joindre plus tard » keeps the current copy. The
  appointment detail in mon-compte gains the same attach action.
- **Rebook prefill**: `/[slug]/reserver?services=a,b&artist=x` (sanitized
  against the live catalogue like the app's `sanitizeRebookSelection`);
  « Réserver à nouveau » passes the params and the hub lands on Date et
  heure.
- Sticky summary (total FCFA, durée, « Spécialiste optionnel… ») and all
  four states per section; French copy mirrors the app (« Pas de
  préférence », « Le salon choisit pour vous », « Aucun créneau
  disponible »…).
- **Tests**: the state machine ports to pure `lib/booking/state.ts` logic
  (entry-point orderings, constraint graph, variant duration) — heavily
  unit-tested; e2e journeys for all THREE entry orders + variants + the
  deposit upload; stub availability honours `artistId`.

## 5. K3 — app: send the artist (one-line fix + no UX change)

`ApiAppointmentService.getAvailableTimeSlots` adds `if (artistId != null)
'artistId': artistId` to the query — the hub's artist-aware behaviour becomes
real instead of cosmetic. (Mock already honours it.) Rides with K1's PR or a
tiny follow-up.

## 6. Rollout

| Slice | Contents | Gate |
|---|---|---|
| K1 backend (+K3 app line) | Slot engine + capacity + migration 0026 + availability param + contract + T11 | analyze 0 · full suites (incl. PG constraint tests in CI) |
| K2 web hub | The port above + stub/e2e | tsc/lint/build · unit · e2e |

Each PR: conventional commit, user merges; ROADMAP + this spec + MODULES.md
refreshed after K2.
