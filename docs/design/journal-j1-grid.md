# Journal J1 — the web journal grid (+ « Client arrivé » riding along)

| | |
|---|---|
| **Module** | `journal` — slice **J1** (+ **J2** rides along) of [docs/modules/journal.md](../modules/journal.md) (Signed off 2026-07-08; §10 decisions apply) |
| **Status** | **Draft** — awaiting sign-off, then build |
| **Scope** | The **desktop journal grid** (YCLIENTS's signature screen) as the new default « Journée » view at `/pro/rendez-vous` — one-payload day endpoint, drag-reschedule, click-to-create with **C2 client search**, side panel with the **client mini-card**, and the « Client arrivé » in-day status — **backend + web** |
| **Out of scope** | The pro-app day timeline (module slice J1b — its own spec next) · waitlist (J3) · group/recurring (J4) · C3/C4 |
| **Decisions locked** | 15-min lines & snap · cancelled = toggleable ghosts, off by default · « Sans artiste » column kept, drag-to-assign · arrive notifies the artist only once `access` ships (no-op now) |
| **Cross-refs** | [clients-c1.md](clients-c1.md) (Built — C2 integrates here) · [MODULES.md](../MODULES.md) §1 · `docs/api/openapi.yaml` |

## 1. Goal

Give the front desk the screen it runs the day from: **columns per artist, a
time axis, color-coded blocks, drag to move, click an empty cell to book** —
with the client's history one hover away. This is the largest single UX gap vs
YCLIENTS and the anchor of the `journal` module.

## 2. Backend (PR J1a)

### 2.1 `GET /providers/{id}/journal?date=YYYY-MM-DD`

One payload renders the whole grid (no N+1 — journal.md §5/§7):

```jsonc
{
  "date": "2026-07-10",
  "hours": { "open": "09:00", "close": "19:00",
             "breaks": [{ "start": "12:30", "end": "13:30" }] },
  "artists": [{ "id", "name", "imageUrl" }],
  "appointments": [ /* Appointment DTOs, ALL statuses for the day, enriched
                       with salonClientId + clientNoShowCount + durationMinutes
                       + arrivedAt */ ]
}
```

- Provider-only + ownership (the T5/T41 boundary); **read audited**? No —
  journal reads are the salon's own operational day view, not the client base;
  the T46 audit stays on `clients.*` reads (the panel's mini-card fetch IS
  audited, since it goes through `GET .../clients/{id}`).
- Client PII in the payload = what the appointment already carries (name,
  phone) — same exposure as today's provider list (T41).
- **Day boundary = Africa/Abidjan = UTC+0** — dates compare in UTC (happy
  coincidence: CI runs on UTC; note it in code for future regions).
- Closed day → `hours: null`, appointments still listed (edge: a booking on a
  closed day renders on a neutral axis 08:00–20:00).

### 2.2 `POST /appointments/{id}/arrive` (J2)

- Migration **`0025_appointment_arrived`**: `arrived_at timestamptz NULL`.
- Guards (threat T43): provider-only + ownership; only `confirmed`; only on
  the booking's calendar day (UTC); **idempotent** (second call → 200, same
  state). Clears nothing — terminal transitions behave exactly as today.
- `arrivedAt` joins every appointment payload (consumer sees it too — it's
  their own visit; harmless and honest).

### 2.3 Reschedule gains `artistId` (drag across columns)

The existing reschedule endpoint accepts an optional `artistId` (validated:
must belong to the salon → 400 `invalid_artist`); same slot-engine guard +
DB exclusions re-validate every move (threat T42 — the grid is never
trusted). Drag targets snap to **15-minute** starts.

### 2.4 Contract & threats

OpenAPI: `/providers/{id}/journal` + `JournalDay` schema; `arrive` path;
reschedule body extended; `Appointment` += `arrivedAt`, `durationMinutes`
already present. Threat rows **T41–T43** land in BACKEND.md §7. Web types
regenerated in the same PR.

## 3. Web UX (PR J1b-web) — the grid

### 3.1 Placement

`/pro/rendez-vous` view toggle becomes **Journée · Calendrier · Liste**, with
**Journée the default**. Calendrier (month overview) and Liste stay as they
are — the grid is additive, nothing regresses.

### 3.2 Layout

- Sticky **time axis** left (open→close, one line per 15 min, hour labels
  bold); **one column per active artist** (avatar + first name header) + a
  **« Sans artiste »** column when unassigned bookings exist that day.
- **« Maintenant » line** (error-color, 1 px, dot on the axis) when viewing
  today — auto-scrolled into view on load, updated every minute (a local 60 s
  interval; cheap).
- **Day switcher** header: ‹ › arrows, a date input, « Aujourd'hui » button;
  the selected date lives in the URL (`?date=`) so refresh/share keeps it.
- **Breaks** render as hatched rows across all columns; outside-hours area is
  dimmed. Both reject drops.
- **Header counters**: « {n} rendez-vous · {k} en attente » for the day.
- Toggle « Voir les annulés » (off by default) → cancelled blocks appear as
  ghosts (muted, strikethrough, non-draggable).

### 3.3 Blocks

Positioned by start time, height = `durationMinutes` (min height 24 px —
15-min services stay clickable). Content by height: time range · client first
name · service; tiny blocks show client name only. Status colors (tokens,
matching the app's journal language): pending = warning-tint · confirmed =
info-tint · **arrivé = success-tint** · completed = neutral · noShow =
error-tint. Deposit badge (₣) when `depositAmount > 0`; lock glyph on
non-draggable blocks (completed/cancelled/noShow).

### 3.4 Interactions

- **Click a block → side panel** (right, 360 px; grid stays visible):
  - client line: name + **no-show badge** (1 neutral / ≥2 red) + masked phone;
  - **mini-card** (C2): on open, fetch `GET .../clients/{salonClientId}` →
    Visites · Dépensé · Absences + the latest note snippet + « Voir la
    fiche » → `/pro/clients/{id}` (this read is audited — by design);
  - booking facts: date/time, services, total FCFA, deposit + proof link;
  - **actions by state**: pending → Accepter / Refuser · confirmed →
    **Client arrivé** / Terminé / Non présenté · arrived → Terminé / Non
    présenté; plus Reprogrammer (opens the keyboard-accessible move dialog)
    and Annuler where policy allows. Guards mirror the app (« Terminé »
    before end time asks confirmation; « Non présenté » only after start).
- **Drag a block** (pending/confirmed only): ghost follows snapped to 15-min
  cells; drop → **optimistic move** + reschedule call (+ `artistId` when the
  column changed); 409 `slot_unavailable` → snap back + toast « Créneau
  indisponible »; other errors → snap back + standard error toast.
  Keyboard path: panel → « Reprogrammer » dialog (date/time/artist selects).
- **Click an empty cell → quick-create popover** anchored to the cell:
  1. **Client** (C2): search-as-you-type against `GET .../clients?query=`
     (name/phone, the C1 endpoint) → pick, or « Nouveau client » (name +
     phone inline); picking prefills name+phone into the booking.
  2. **Service**: single select (duration + price shown); « Plus d'options »
     hands off to the full manual form for multi-service cases.
  3. Time + artist prefilled from the cell (editable) → « Créer » → the
     existing manual-booking POST (arrives `confirmed`, server-priced) →
     block appears in place.
  - Note (from C1's model): a quick-create **without a phone** books fine but
    creates no client row (journal-only guest) — the popover hints
    « Ajoutez le téléphone pour retrouver ce client dans Clients ».

### 3.5 States & responsive

- Loading = grid-shaped skeleton (time axis + 3 ghost columns).
- Empty day = axis + centered « Aucun rendez-vous ce jour » + « + Nouveau
  rendez-vous » (opens quick-create at the next quarter-hour).
- Error = standard retry block. No artists at all → single « Salon » column.
- ≥1280 px ~5 comfortable columns; more → horizontal scroll, axis pinned;
  768–1280 px → 2–3 columns + swipe; **<768 px → the existing Liste view is
  shown instead** (the toggle hides Journée; the phone experience is the
  app's J1b timeline, not a cramped grid).
- A11y: blocks are buttons (aria-label « {client}, {service}, {time} »);
  ←→ moves focus across artists, ↑↓ by 15 min, Enter opens the panel; all
  drag outcomes reachable via the Reprogrammer dialog.

## 4. Security / performance / tests

- **T41** cross-salon journal read → 403 (REQUIRED negative); **T42** drag
  tampering re-validated server-side (negative: crafted reschedule to a taken
  slot → 409; foreign artist → 400); **T43** arrive guards (wrong state /
  wrong day → 409/422; idempotent repeat → 200).
- Perf: journal endpoint <150 ms p95 (one indexed day query + artists);
  web bundle — the grid code-splits under the pro dash route (no public-page
  JS impact); drag is pure CSS transforms (no re-layout per frame).
- Tests — backend: handler (200 shape incl. closed day + enrichment,
  401/403/405), arrive unit+handler incl. guards/idempotency, reschedule
  artistId validation, T41–T43 negatives; PG section for `arrived_at`.
  Web: unit (grid math: block geometry from times, snap, now-line position,
  overlap column layout), e2e on the stub (grid renders seeded day → drag via
  Reprogrammer dialog → panel actions arrive→terminé → quick-create with
  client search → new block; cancelled-ghosts toggle; badge in panel).
  Stub-api gains `/providers/:id/journal` + arrive + reschedule-with-artist.

## 5. Rollout

| PR | Contents | Gate |
|---|---|---|
| J1a backend | Migration 0025 · journal endpoint · arrive · reschedule artistId · contract + threats + regenerated types | analyze 0 · full suite green |
| J1b web | « Journée » grid + panel + drag + quick-create (C2) + stub/e2e | tsc/lint/build · unit · e2e green |

After J1b: journal.md §status + MODULES.md §1 refreshed (grid ✅, C2 ✅);
ROADMAP entry. The pro-app **day timeline** (module J1b) follows as its own
spec. Conventional commits `feat(journal): …`, user merges each PR.

## 6. Open questions

None — the module sign-off (journal §10, 2026-07-08) resolved the product
decisions; implementation latitude (drag library vs pointer events, exact
skeleton) stays within the web design standards.
