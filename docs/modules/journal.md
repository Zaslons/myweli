# Module: Journal & bookings — `journal`

| | |
|---|---|
| **Module** | `journal` — [docs/MODULES.md](../MODULES.md) §1 — **the core**: every module attaches to the visit record (YCLIENTS's own architecture) |
| **YCLIENTS analog** | Электронный журнал — their flagship: the staff-column day grid a receptionist runs the salon from |
| **Status** | **Signed off** (2026-07-08) — §10 questions resolved. Core 🟢 built & live; this doc covers the replica gaps: the journal grid, visit-status depth, booking-card density, waitlist, group/recurring. Next: J1 design spec |
| **Depends on** | `catalogue` artists (✅ — `Appointment.artistId` already exists) · `access` capabilities (`journal.*` — doc ✅) · `clients` (for card density, ⏳) |
| **Feeds** | Everything: `payments` (deposits), `finance` (revenue), `analytics` (fill rate/no-show), `loyalty` (visits), `notifications` (lifecycle), `payroll` (V3) |

## 1. Vision & YCLIENTS reference

The journal is where a salon *lives* during the day. YCLIENTS's signature
screen is the **day grid**: one column per master, a time axis, color-coded
visit blocks, drag to move, click an empty cell to book, and a booking card
dense enough that the receptionist knows who's walking in (visit count, spend,
notes) before they open the door.

MyWeli's journal core is **built and live** — lifecycle, slot engine,
concurrency-safe double-booking protection, on app + web + consumer side. What
separates us from the replica is not machinery but **surface depth**:
YCLIENTS's grid, their in-day visit statuses, and their card density. This doc
specifies exactly that — adapted to our two realities: **mobile-first pros**
(the phone journal must be first-class, not a shrunken grid) and **desktop for
the front desk** (the web grid for salons with a reception).

## 2. Ground truth — what is built today (🟢 live)

- **Lifecycle:** `pending → confirmed → completed | cancelled | noShow`
  (model `AppointmentStatus`); routes `accept / reject / cancel / complete /
  no-show / reschedule` — role-aware and ownership-scoped (threat T5/T11).
- **Slot engine:** durations, buffers, breaks, working hours; request dedupe
  (`slotsRequestId`); reschedule goes through the same guard.
- **Concurrency safety:** app-level `slot_unavailable` (409) + Postgres
  exact-start partial unique index + `btree_gist` duration-overlap EXCLUDE —
  overlaps cannot slip through under load.
- **Pro surfaces:** app calendar + list (`screens/provider/appointments|calendar`),
  manual booking (`/pro/appointment/new`), detail with transitions; web
  `/pro/rendez-vous` (Calendrier + Liste tabs), detail, accept.
- **Consumer surfaces:** booking hub (service → artist « Sans préférence » →
  slot → confirm w/ deposit + required phone), my-bookings, reschedule/cancel
  per policy, review post-completion.
- **Deposit tie-in:** screenshot deposit inside the pending flow (`payments`).
- `Appointment.artistId` exists → the grid needs **no data-model change**.

## 3. User stories (complete set)

**Owner / Manager (pro app, phone — primary CI persona)**
1. As an owner, I open the app in the morning and see **ma journée**: every
   booking, per artist, at a glance — including who hasn't confirmed.
2. As an owner, when a client walks in, I mark **« Client arrivé »** so the
   artist knows, and at the end I mark « Terminé » to trigger the review ask.
3. As an owner, a client calls to move Thursday's braids to Friday — I
   long-press the booking, pick a new slot, done in under 15 seconds.
4. As an owner, a walk-in wants 14 h — I tap the empty 14 h slot on the right
   artist's line and create the booking with name + phone only.
5. As an owner, I see a no-show pattern — I mark « Non présenté » so the
   client's reliability is tracked (feeds `clients`/`analytics`).

**Receptionist on desktop (web grid — salons with a front desk)**
6. As a receptionist, I run the day from the **grid**: columns = artists, rows
   = time; I drag a block to another time/artist and the engine validates it.
7. As a receptionist, I click any empty cell → quick-create with client
   search-or-create (feeds `clients`), service, duration pre-filled.
8. As a receptionist, I hover/tap a block and see the client's history (visits,
   no-shows, total spend) without leaving the grid *(needs `clients`)*.

**Collaborateur (staff, via `access`)**
9. As an artist, I see **only my column/day** (« {Salon} — votre planning »),
   and can mark my own bookings arrived/done (`journal.view.own/manage.own`).

**Consumer (already served, kept for completeness)**
10. As a client, I book/reschedule/cancel within policy and always know the
    status of my booking (+ reminders 24 h/2 h).
11. As a client on a full day, I join a **waitlist** and get notified when a
    slot frees up (⏳ — story defined here, built in its slice).

## 4. UX — full specification

### 4.1 In-day visit statuses (new, both surfaces) — J2

YCLIENTS tracks the visit *inside* the day (ожидание / пришёл / не пришёл).
We add ONE state, not a parallel machine: **`arrived` flag on confirmed**
(timestamped `arrivedAt`), plus the existing terminal transitions.

- Copy: chip « Arrivé » (confirmed+arrived), « En attente » (pending),
  « Confirmé », « Terminé », « Annulé », « Non présenté ».
- Color language (tokens, both surfaces): pending = warning · confirmed =
  info · arrived = success-tint · completed = neutral/done · cancelled =
  muted/strikethrough · noShow = error-tint. One legend, everywhere.
- Transitions on the detail sheet AND as swipe/quick actions on rows/blocks:
  confirmed → « Client arrivé » → « Terminé ». Guard: « Terminé » before end
  time asks confirmation; « Non présenté » only after start time.

### 4.2 The web journal grid (flagship) — J1

Replaces the Calendrier tab's day view at `/pro/rendez-vous` (Liste stays).

- **Layout:** sticky time axis (left, salon open→close, 15-min lines); one
  column per active artist (avatar+name header) + a « Sans artiste » column
  when unassigned bookings exist; **« Maintenant » line** (red) auto-scrolled
  into view on load; day switcher (‹ today ›, date picker, « Aujourd'hui »).
- **Blocks:** service name + client first name + FR time range; height =
  duration; status color (§4.1); deposit badge when paid; lock icon when the
  policy forbids moving (e.g. completed).
- **Interactions:**
  - Click block → right-side **panel** (not navigation): full detail,
    transitions, client mini-card (`clients` when built), « Reprogrammer ».
  - **Drag** block to another cell/column → optimistic move + server
    `reschedule` (same slot guard); reject → snap back + toast
    « Créneau indisponible » (409 `slot_unavailable`). Artist change via drag
    across columns = same call with new `artistId`.
  - Click empty cell → **quick-create popover**: client (search by name/phone
    or « Nouveau client » name+phone), service (duration/price prefilled),
    artist+time prefilled from the cell → « Créer ». Full form still available
    (« Plus d'options » → manual booking).
- **States:** loading = grid skeleton (BrandLoader); empty day = axis +
  « Aucun rendez-vous ce jour » + CTA « + Nouveau rendez-vous »; error =
  standard retry block; offline = read-only cached day + banner.
- **Density/responsive:** ≥1280 px shows ~5 columns comfortably; more artists →
  horizontal scroll with pinned axis; 768–1280 px = 2–3 columns + swipe;
  <768 px = the mobile pattern (§4.3), never a cramped grid.
- **A11y/keyboard:** blocks focusable; ←→ artist, ↑↓ 15 min, Enter = panel;
  drag has a keyboard equivalent (« Reprogrammer » in panel).

### 4.3 Pro app journal (phone) — J1b

No grid cosplay on 360 px — a **per-artist day timeline**:

- Header: date nav + horizontally scrollable **artist filter chips**
  (« Tous » default; avatar chips; « Sans artiste » when relevant).
- Body: vertical timeline of the day's bookings (time-ordered cards: time
  range, client, service, artist avatar, status chip, deposit badge); gaps
  ≥30 min render as tappable « Libre {14 h – 15 h 30} » slots → manual booking
  prefilled (story #4).
- Quick actions: swipe right = « Arrivé »/« Terminé » (state-appropriate),
  swipe left = « Reprogrammer »; long-press = action sheet. All actions also
  in the detail screen (discoverability + a11y).
- Reschedule = existing slot-picker flow, prefilled, ≤3 taps (story #3).
- Week strip above (dots = load density) for context without a week grid.
- Pull-to-refresh = BrandRefresh (mark loader), per the loader rule.

### 4.4 Waitlist (consumer + pro) — J3 ⏳

- Consumer: full day/slot → « Ce créneau est pris. Être prévenu si ça se
  libère ? » → joins waitlist (service, artist?, date, window).
- Trigger: cancel/reschedule frees a matching window → push+WhatsApp to the
  **first** waiter: « Un créneau s'est libéré {jeudi 14 h} chez {Salon} » →
  15-min **hold** to confirm in-app; timeout → next waiter. No auto-booking.
- Pro: read-only waitlist count/list per day in the journal (« 3 en attente »);
  no manual assignment in V2 (keeps it fair + simple).
- Data: `waitlist_entries(id, provider_id, user_id, service_id, artist_id?,
  date, window_start, window_end, status: waiting|offered|expired|converted,
  offered_at)`; offer idempotency; entry TTL = the requested day.

### 4.5 Group & recurring — J4 (V2 late / gated)

Group visits (one slot, N seats — braiding courses) and recurring (« toutes
les 2 semaines ») are PRD-V2 but **NOT in the first journal wave**; they get
their own design specs when scheduled. The grid renders group blocks as
`x/N places` when they arrive (layout accounts for it now).

## 5. Data model & API deltas

- `appointments`: + `arrived_at TIMESTAMPTZ NULL` (single migration; `arrived`
  is derived). No other change for J1/J2.
- New endpoints (contract locked per-slice in openapi.yaml):
  - `GET /providers/{id}/journal?date=` — day view: bookings (all statuses,
    incl. cancelled toggled off by default) + artists + hours + breaks in ONE
    payload (grid renders from a single request; no N+1).
  - `POST /appointments/{id}/arrive` — confirmed → arrived (idempotent).
  - Reschedule: existing endpoint + optional `artistId` (drag across columns).
  - Waitlist (J3): `POST /providers/{id}/waitlist` · `GET .../waitlist?date=` ·
    `POST /waitlist/{id}/confirm` (hold) · offer job inside the cancel path.
- Capabilities (`access`): grid+list = `journal.view.all`; transitions/create/
  drag = `journal.manage.all`; staff column-view = `journal.view.own` with
  server-side artist filter. Until `access` ships, owner-only as today.

## 6. Security & threat-model deltas

| # | Surface | Threat | Mitigation |
|---|---|---|---|
| T41 | `GET .../journal` | **I** — cross-salon day harvest (clients' names+phones for a whole day) | Same ownership boundary as T5 (`account.providerId == {id}` → else 403); client PII in the payload limited to first name + masked phone until `clients.view` (then audited) |
| T42 | Drag-reschedule | **T** — move a booking to an invalid/taken slot via crafted call | Server re-validates EVERY move through the slot engine + DB exclusions (never trusts the grid); artist change validated against salon's artists |
| T43 | `arrive` | **T** — status spoofing (arrive before booking day / after terminal) | State-machine guard server-side: only `confirmed`, only on the booking day; idempotent; audited actor |
| T44 | Waitlist | **DoS/T** — flood entries to hold a salon hostage; offer race | Per-user active-entry cap (e.g. 3/salon/day), rate-limited joins; offers hold-locked (single `offered` at a time, TTL), conversion re-runs the slot guard |

Existing T5/T11 tests extend to the new endpoints (REQUIRED negatives:
cross-salon journal 403, cross-artist own-view 403, invalid arrive 409/422).

## 7. Performance

- Journal day payload: one indexed query (`provider_id, date`) + artists —
  target <150 ms p95; payload <50 KB typical day.
- Grid: virtualize only if >12 columns (rare); optimistic drag with rollback;
  no polling — refetch on action/focus (push-refresh later via `notifications`).
- Phone timeline: const widgets, ListView.builder, budgets per ROADMAP Part 6
  (60 fps on the reference low-end Android).

## 8. Testing

- Backend: unit (state machine incl. arrive guards; waitlist offer/hold/race),
  handler (new endpoints success + 401/403/404/409/422/429 + 405), contract,
  concurrency (parallel drags on one slot → exactly one 200), T41–T44 negatives.
- Web: RTL units (grid math: block layout, now-line, drag targets), e2e on the
  stub (open grid → drag → panel updates; quick-create; arrive→done; empty/
  error states), Lighthouse budget on `/pro/rendez-vous`.
- App: provider tests (journal state, optimistic updates), widget tests
  (timeline + chips + swipe actions + gap slots; all four states), goldens for
  the status chips/legend; mock realism (latency, 409 on drag, pagination).

## 9. Rollout

| Slice | Contents | Notes |
|---|---|---|
| J1 | Web **journal grid** (day view: read + click-panel + drag + quick-create) + `GET .../journal` | The flagship; replaces Calendrier-day |
| J1b | Pro app **day timeline** (artist chips, gap slots, swipe actions) | Same API; ships right after J1 |
| J2 | « Client arrivé » (+`arrived_at`, chips/colors both surfaces) | Tiny; can ride with J1 |
| J3 | Waitlist (consumer join → offer/hold → pro visibility) | Needs push live (real FCM) first |
| J4 | Group + recurring | Own specs; gated on demand |

Each slice: guardrails skill → design spec (`docs/design/journal-<slice>.md`)
→ **user sign-off** → build (backend → web → app) → tests/CI → PR → ROADMAP +
this doc's status refreshed. Full-depth rule applies within each slice.

## 10. Decisions (user sign-off, 2026-07-08)

1. **Grid granularity: 15 minutes** — lines and drag-snap (YCLIENTS default;
   fine enough for 15-min services, readable on a laptop).
2. **Cancelled bookings: toggle, off by default** — « Voir les annulés » shows
   muted strikethrough ghost blocks for investigating a day; the list always
   includes them.
3. **« Sans artiste »: kept** — no forced assignment at creation (booking
   friction stays zero); the grid renders the « Sans artiste » column and
   dragging a block onto an artist column assigns in one gesture.
4. **Waitlist hold: 15 minutes** — first in line gets push/WhatsApp + 15 min
   to confirm, then the offer passes to the next waiter.
5. **« Arrivé » notifies the linked artist: yes, activated when `access`
   ships staff logins** — a no-op until then (no staff accounts to notify).
