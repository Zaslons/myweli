# Web manual booking — multi-service + the missing entry points

| | |
|---|---|
| **Module** | `journal` / `clients` — the web salon-entered booking, closing two flagged parity gaps |
| **Status** | **Built** (2026-07-10) — one PR: dialog + entry points + tests · **amended 2026-10-13**: the SMS control is removed and the dialog sends `sendSmsInvite: false` ([amounts-that-fit.md](amounts-that-fit.md) §2 « Web ») |
| **Trigger** | Parity follow-ups flagged on the ROADMAP: the web quick-create books **one** service via a `<select>` while the app's `ProManualBookingScreen` is multi-service with note + total; and the web has **no** « Nouveau rendez-vous » outside a journal grid cell (the client card CTA was deferred in clients-c1.md §6) |
| **Scope** | Web only, **no backend change** — `POST /providers/{id}/appointments` already takes `serviceIds[]` + `notes` + `sendSmsInvite`, and the pro BFF passes the body through |
| **Out of scope** | An artist picker in the standalone dialog (the app's manual screen has none — unassigned bookings are assigned later by dragging in the grid) · SMS invite delivery (backend no-op until the notifications slice) — and, since 2026-10-13, any SMS control in the dialog (§2) |
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

> **Since build 569 the app no longer shows that switch**
> ([pro-screenshot-shoot-fixes.md](pro-screenshot-shoot-fixes.md) §1.6): it
> promised a message nothing sends — the backend never reads `sendSmsInvite`,
> and messaging waits for company registration. It sits behind
> `FeatureFlags.smsInvite` (false) and the form sends `false`. The paragraph
> above is what was read on 2026-07-10; §2 below is what the web does today.

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
- **No SMS control** (removed 2026-10-13,
  [amounts-that-fit.md](amounts-that-fit.md) §1.5). The dialog used to carry
  « Envoyer la confirmation par SMS » — ticked by default, enabled as soon as
  a phone was present, under « Le client reçoit un lien vers l'app (bientôt
  disponible) » — and posted `sendSmsInvite: true` on every booking with a
  phone, including every one opened from a client card. Nothing sends that
  message. The app hid its switch in build 569; the web has no feature-flag
  mechanism to mirror `FeatureFlags.smsInvite`, so the control and its state
  are **deleted**, not hidden, and the dialog sends `sendSmsInvite: false`
  **explicitly** — the same payload as the app. No flag, no env variable: when
  SMS exists, the control comes back as a designed change, with this spec.
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
  `sendSmsInvite` stays in the contract and in the client's input type; the
  dialog — its only caller — always sends `false` (2026-10-13).
- Security: unchanged — pro httpOnly cookies, ownership enforced server-side
  (T10/T41 family); no new endpoint, no new trust boundary.

## 4. Tests

- Unit: the four helpers (total, combine, future guard, gate) + edge cases.
- e2e: grid quick-create now checks **two services + note** · rendez-vous
  header CTA (standalone date/time path) · client-card CTA (pre-picked
  client). Stub POST already 409s on `T10:00` for the collision copy.
- RTL (`tests/manual-booking-phone.test.tsx`, 2026-10-13): no « Envoyer la
  confirmation par SMS », no « bientôt disponible », no checkbox beyond the
  service rows — with no phone and with a pre-picked client who has one — and
  the POSTed body carries `sendSmsInvite === false` on all three paths (a
  typed phone, a pre-picked client with a phone, no phone). The twin of the
  app's guard in `mobile/test/widget/manual_booking_phone_test.dart`.
- RTL (`tests/client-card-phone.test.tsx`, 2026-10-13): entry point 3
  end to end in jsdom — the card opens the dialog, a booking is made, and the
  POSTed `clientPhone` is the client's **stored** number, not the grouped
  text the card shows ([clients-c1.md](clients-c1.md) §6). The e2e journey
  for this entry point cannot see the difference: the stub accepts any phone,
  where the backend answers 400 `invalid_phone` to one that is not E.164.

## 5. Rollout

One PR (`feat/web-manual-booking-multiservice`): dialog rewrite + two new
entry points + helpers + tests + this spec; README index + clients-c1 note +
ROADMAP refreshed. Gates: tsc/lint/build · unit · e2e.
