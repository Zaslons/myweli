# Auto-sync of provider-entered bookings (FR-APPT-008)

| | |
|---|---|
| **Requirement** | FR-APPT-008 [V1] — when a provider manually books a client (FR-PRO-BOOK-002), matched **by phone number**, the appointment appears automatically in that client's app. |
| **Phase** | V1 small-gap sweep (ROADMAP §1.8). |
| **Surfaces** | Backend (`GET /appointments` consumer list) · Consumer app (badge only). |
| **Status** | **Built** (single PR) — read-time verified-phone match + card badge. |
| **Builds on** | Manual booking (`pro-manual-booking.md`): `POST /providers/{id}/appointments` stores `userId: 'manual'` + a **validated E.164** `clientPhone`. |

## 1. Goal & scope
Bridge the paper journal and the consumer app: a salon books a walk-in/phone
client by number, and once that person is signed in (their phone is
**OTP-verified**), the appointment shows up in their "Mes rendez-vous" — "your
salon already booked you, see it here". Drives organic install + trust.

## 2. Mechanism — read-time match on the verified phone (no mutation)
The consumer's `phoneNumber` is **OTP-verified at registration** and stored
E.164; manual bookings store `clientPhone` **validated E.164**. So the consumer
list simply also returns manual bookings whose `clientPhone` equals the **account's
verified phone**:

- `GET /appointments` (consumer): resolve the caller's verified phone
  server-side (`AuthRepository.userById(principal.userId).phoneNumber`) and pass
  it to the repo. The match phone is **never** taken from the request.
- `AppointmentRepository.listForUser(userId, {status, matchPhone})`:
  returns rows where `user_id = userId` **OR** (`matchPhone != null` **and**
  `client_phone = matchPhone`). Disjoint sets (own bookings have null
  `client_phone`; manual have `user_id = 'manual'`), so no dedupe needed.

No ownership migration / no write path — purely a read-time join on the verified
phone. Idempotent and self-correcting (it always reflects the current account
phone). Manual bookings stay owned by the salon; the consumer just sees them.

## 3. Data / perf
- No new column. Migration **`0020`**: partial index
  `appointments(client_phone) WHERE client_phone IS NOT NULL` so the added
  `OR client_phone = …` stays index-backed (no seq scan; BACKEND §4).
- Postgres `listForUser`: `WHERE (user_id = @u OR (@phone::text IS NOT NULL AND
  client_phone = @phone)) [AND status = @s] ORDER BY appointment_date DESC`.

## 4. Security (threat model T26)
- **Server-resolved match phone only** — the caller never supplies it; it's the
  account's OTP-verified `phoneNumber`. A user can therefore only ever see manual
  bookings for the number **they proved they own**.
- Provider list path (`listForProvider`) is unchanged (own salon only).
- **Residual risk (accepted, bounded):** phone-number recycling — a reassigned
  number could surface a prior holder's manual booking. Same risk class as an
  SMS/WhatsApp confirmation to a recycled number; the row carries only a name +
  service summary (no payment data). Noted, not mitigated in V1.

## 5. App
The matched bookings already render in "Mes rendez-vous" (the list calls
`getAppointments` → `listForUser`). Only change: a subtle **« Réservé par votre
salon »** chip on cards where the booking was salon-entered (`clientName != null`)
— surfacing the FR-APPT-008 narrative. Tokens only; FR copy. No new screen.

## 6. Tests
- **Backend repo:** `listForUser` returns own + phone-matched manual bookings;
  honours `status`; a different phone sees nothing of mine; null `matchPhone` →
  own only.
- **Backend route:** a consumer whose verified phone matches a manual booking
  gets it in `GET /appointments`; the match phone comes from the account, not the
  query; provider path unchanged; anon → 401.
- **App:** `AppointmentCard` shows the chip when `clientName != null`, hides it
  otherwise.

## 7. Rollout
Additive; one index migration. Existing behaviour unchanged for users with no
manual bookings on their number. Mock app data already includes `clientName` on
manual entries for the demo badge.
