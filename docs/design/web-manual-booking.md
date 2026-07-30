# Web manual booking — multi-service + the missing entry points

| | |
|---|---|
| **Module** | `journal` / `clients` — the web salon-entered booking, closing two flagged parity gaps |
| **Status** | **Built** (2026-07-10) — one PR: dialog + entry points + tests |
| **Trigger** | Parity follow-ups flagged on the ROADMAP: the web quick-create books **one** service via a `<select>` while the app's `ProManualBookingScreen` is multi-service with note + total; and the web has **no** « Nouveau rendez-vous » outside a journal grid cell (the client card CTA was deferred in clients-c1.md §6) |
| **Scope** | Web only, **no backend change** — `POST /providers/{id}/appointments` already takes `serviceIds[]` + `notes` + `sendSmsInvite`, and the pro BFF passes the body through |
| **Out of scope** | An artist picker in the standalone dialog (the app's manual screen has none — unassigned bookings are assigned later by dragging in the grid) · SMS invite delivery (backend no-op until the notifications slice) |
| **Cross-refs** | `pro_manual_booking_screen.dart` (the reference flow) · [journal-j1-grid.md](journal-j1-grid.md) §3.4 (quick-create) · [clients-c1.md](clients-c1.md) §6 (the deferred card CTA) · [booking-capacity-web-hub.md](booking-capacity-web-hub.md) (manual bookings bypass the slot engine BY DESIGN — the per-artist DB guard still applies) |

## 1. The app flow being mirrored (read 2026-07-10)

`ProManualBookingScreen`: SERVICES = **checkbox list** (name · price range ·
duration) with a running **Total** (sum of min prices — the server re-prices
anyway) · DATE & HEURE pickers (future-only guard: « Choisissez une date et
une heure à venir ») · CLIENT (phone / walk-in / optional name) · **SMS
switch** (« Envoyer la confirmation par SMS » — « bientôt disponible », only
with a phone) · **Note (optionnel)** · submit gate = ≥1 service + datetime +
client. Entry points in the app: appointment-list FAB · journal FAB + gap
slots · client-card CTA (prefilled).

## 2. UX — one dialog, three entry points

`QuickCreatePopover` grows into **`ManualBookingDialog`** (same modal shell,
same C1 client search-or-create — that signed-off pattern is *kept*, not
regressed to the app's raw phone field):

- **Prestations**: the `<select>` becomes the app's **checkbox list**
  (name · price range · duration) + a running **Total** row. Gate: ≥1.
- **Date & heure**: when opened from a **grid cell**, the time stays fixed
  (current behaviour — the cell IS the choice). When opened **standalone**,
  the dialog shows a date input (prefilled with the view's day, min today)
  + a time input; past datetimes are rejected with the app's copy.
- **Client**: unchanged search-or-create (≥2 chars searches C1; unknown name
  + optional phone creates). When opened from the **client card**, the
  client arrives pre-picked.
- **Note (optionnel)** textarea → `notes`.
- **SMS switch** mirroring the app: enabled only when a phone is present,
  subtitle « Le client reçoit un lien vers l'app (bientôt disponible) » →
  `sendSmsInvite` (accepted server-side, no-op until notifications).
- Errors: 409 → « Ce créneau est déjà pris. » · other → « Création
  impossible. Réessayez. » (unchanged).

**Entry points** (parity with the app's three):
1. **Journal grid cell** — as today, now multi-service.
2. **`/pro/rendez-vous` header** — « + Nouveau rendez-vous » button beside
   the view toggle (all three views), standalone dialog prefilled with the
   selected journal day.
3. **Client card** (`/pro/clients/[id]`) — « Nouveau rendez-vous » beside
   Appeler/WhatsApp, dialog with the client pre-picked (closes the C1b
   deferral).

States: dialog reuses the page's loaded profile (no extra fetch); busy
spinner on submit; empty-services salons see the app's guidance line.

## 3. Layering & contract

- Pure helpers in `lib/pro/manual-booking.ts` (unit-tested):
  `manualBookingTotal(services, ids)` (sum of min prices, the app's total),
  `combineDateTime(ymd, hm)` → ISO, `isFutureIso(iso, now)`,
  `canSubmitManualBooking({...})` (the app's gate).
- `createManualBooking` (existing) gains `notes` + `sendSmsInvite` fields —
  already in the OpenAPI contract and forwarded by the BFF; **no drift**.
- Security: unchanged — pro httpOnly cookies, ownership enforced server-side
  (T10/T41 family); no new endpoint, no new trust boundary.

## 4. Tests

- Unit: the four helpers (total, combine, future guard, gate) + edge cases.
- e2e: grid quick-create now checks **two services + note** · rendez-vous
  header CTA (standalone date/time path) · client-card CTA (pre-picked
  client). Stub POST already 409s on `T10:00` for the collision copy.

## 5. Rollout

One PR (`feat/web-manual-booking-multiservice`): dialog rewrite + two new
entry points + helpers + tests + this spec; README index + clients-c1 note +
ROADMAP refreshed. Gates: tsc/lint/build · unit · e2e.
