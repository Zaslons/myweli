# Messaging & notifications (WhatsApp + SMS) — backend

| | |
|---|---|
| **Requirement** | FR-NOTIF-001 (push/SMS/WhatsApp for lifecycle events) · FR-AUTH-002 (OTP via SMS) · WhatsApp BSP spike (OQ-5) |
| **Phase** | Phase 4 — productionize integrations (the deferred V1 risk spike) |
| **Status** | **Built** — PR A (foundation + OTP + webhook) · PR B (booking lifecycle events + 24h/2h reminder scheduler). Real Twilio creds + WhatsApp template approval are the remaining ops step. |
| **Decision** | Foundation + reminder scheduler · **Twilio** (WhatsApp + SMS) **+ Termii** (cheap CI SMS — [messaging-termii.md](messaging-termii.md)), runtime-selectable via `MESSAGING_PROVIDER` · OTP routed through the seam (SMS) |
| **Mirrors** | App seam `MessagingServiceInterface` + `models/messaging.dart` + `core/utils/message_templates.dart` (field-for-field) |

## 1. Goal & scope
Give the backend a **provider-agnostic outbound-messaging seam** so the FR-NOTIF-001
lifecycle events and the OTP code are actually delivered (WhatsApp-first, SMS
fallback), with the **Twilio** adapter as the concrete target — switched on by env,
**never** with secrets in the repo. No real send is possible in CI (needs a
registered BSP + approved templates + creds), so everything is built behind an
interface with a **dev `LogMessagingProvider`** and unit-tested against a mocked
HTTP client.

**No-custody / compliance:** transactional messages always send; **promotional**
(rebook reminder) only to opted-in recipients (ARTCI / WhatsApp policy). OTP and
PII are never logged; the OTP body is never persisted.

### PR breakdown
- **PR A (this slice):** the seam — `MessagingProvider` (interface + `LogMessagingProvider` + `TwilioMessagingProvider`), `MessagingService` (`sendTemplate` + `sendOtp` + opt-out), outbox + opt-out repos (InMemory + Postgres, migration `0015_messaging`), DI, **OTP wiring** (`/auth/otp/request` → SMS, best-effort), a **delivery-status webhook** (`/webhooks/messaging/status`, shared-secret guarded), contract + `.env.example` + threat model + tests.
- **PR B:** **booking lifecycle events** (confirmed/accepted/declined/cancelled/rescheduled/deposit/refund — wired at their transitions, resolving the consumer's phone) **+ the reminder scheduler** (24h/2h): `ReminderScheduler.tick()` + idempotent reminder log + an internal cron route (`CRON_SECRET`).

## 2. Contract (mirror the app)
- `MessageTemplate` (string name, matches the app enum): `bookingConfirmed`,
  `depositReceived`, `reminder24h`, `reminder2h`, `bookingAccepted`,
  `bookingDeclined`, `rescheduled`, `cancelled`, `refund`, `rebookReminder`.
- `MessageChannel`: `whatsApp` | `sms` (push = FCM, later). `DeliveryStatus`:
  `queued` | `sent` | `delivered` | `failed`. `MessageCategory`:
  `transactional` (all but `rebookReminder`) | `promotional`.
- `OutboundMessage` (outbox row): `id, recipientPhone, channel, template, params
  (jsonb), body, status, createdAt` — same shape the app's `OutboundMessage` reads.

## 3. Layering
```
routes (webhook, thin)            services                         repositories
─────────────────────  ────────────────────────────  ────────────────────────────
/webhooks/messaging  → MessagingService.updateStatus → MessagingOutboxRepository
(auth/booking routes) → MessagingService.sendTemplate → (+ MessagingProvider)
                       MessagingService.sendOtp        MessagingPrefsRepository (opt-out)
                                       │
                                       ▼
                        MessagingProvider (BSP adapter)
                        ├─ LogMessagingProvider (dev/CI — records, redacts OTP)
                        └─ TwilioMessagingProvider (prod — env creds, injected http)
```
- **`MessagingService`** (no dart_frog/SQL): `sendTemplate` checks opt-out
  (promotional only), renders the body, picks channel (`whatsApp` → `sms`
  fallback), calls the provider, records an `OutboundMessage` in the outbox, and
  is **best-effort** (a messaging failure never breaks a booking/auth flow — it is
  caught + logged without the body). `sendOtp(phone, code)` sends SMS via the
  provider **without** persisting or logging the code. `updateStatus(providerMsgId,
  status)` for the webhook.
- **`MessagingProvider`**: `send({to, channel, body, templateName, params})` →
  `({ok, providerMessageId?, error?})`.
  - `LogMessagingProvider`: returns `sent`; logs `template + recipient + channel`
    only (never the body — OTP-safe). The dev/CI default.
  - `TwilioMessagingProvider`: form-POST to
    `…/Accounts/{sid}/Messages.json` with Basic auth; SMS uses `From`/`To`,
    WhatsApp uses `whatsapp:` prefixes. (Approved-template `ContentSid` wiring is a
    follow-up once templates are approved; until then WhatsApp falls back to SMS.)
    Selected by DI when `TWILIO_*` env is present; otherwise `LogMessagingProvider`
    — and in **prod** a missing config fails fast (like `JWT_SECRET`/R2).

## 4. Data model — migration `0015_messaging`
```sql
CREATE TABLE outbound_messages (
  id text PRIMARY KEY,
  recipient_phone text NOT NULL,
  channel text NOT NULL,
  template text NOT NULL,
  params jsonb NOT NULL DEFAULT '{}',
  body text NOT NULL,
  status text NOT NULL DEFAULT 'queued',
  provider_message_id text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX outbound_messages_recipient_idx ON outbound_messages(recipient_phone, created_at DESC);
CREATE INDEX outbound_messages_provider_idx ON outbound_messages(provider_message_id);

CREATE TABLE messaging_opt_out (
  phone text PRIMARY KEY,
  opted_out boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
```
The outbox never stores the OTP (OTP goes via `sendOtp`, not `sendTemplate`).

## 5. Security / authz (threat-model deltas)
- **OTP over SMS** — code never logged or persisted; SMS interception is an
  accepted residual risk (short TTL + lockout already mitigate). The plaintext is
  carried in-memory from `requestOtp` to `sendOtp` via a new internal `code` field
  (not echoed to clients in prod; `devCode` stays dev-only).
- **Webhook spoofing** — the status webhook verifies the Twilio signature
  (`X-Twilio-Signature`, HMAC over the URL+params with the auth token) when
  configured; deny-by-default otherwise. No PII echoed.
- **Opt-in (promotional)** — `rebookReminder` is gated on `messaging_opt_out`.
- **Secrets** — `TWILIO_ACCOUNT_SID/AUTH_TOKEN/SMS_FROM/WHATSAPP_FROM` via env
  only (`.env.example` documents them; gitleaks stays green). **SMS is mandatory
  in prod; `WHATSAPP_FROM` is optional** — without it, WhatsApp sends return
  `whatsapp_not_configured` and the service falls back to SMS (SMS-first launch).
- **Delivery status** — each Twilio send attaches a per-message `StatusCallback`
  = `PUBLIC_BASE_URL/webhooks/messaging/status?secret=MESSAGING_WEBHOOK_SECRET`
  (only when both env vars are set; else omitted). Twilio then POSTs status →
  the secret-guarded webhook → outbox `updateStatus`. OTP sends aren't in the
  outbox, so their callbacks no-op.
- **Logging** — structured, redacted: never the body, code, or `Authorization`.
- New STRIDE rows (BACKEND.md §7): **T18** OTP-over-SMS delivery,
  **T19** messaging webhook spoofing, **T20** promotional opt-in enforcement.

## 6. Errors / performance
- Send is **best-effort + async-safe**: failures are caught, recorded as
  `failed`, and never propagate to the triggering request. No ret/backoff in PR A
  (the scheduler/webhook handle eventual status); a retry queue is a later concern.
- Webhook returns 200 quickly; bad signature → 403; unknown id → 200 (idempotent).

## 7. Tests
- `MessagingService`: promotional skipped when opted out · transactional always
  sent · WhatsApp→SMS fallback · outbox records status · `sendOtp` does **not**
  persist/log the code · `updateStatus` updates the row.
- `TwilioMessagingProvider` (mocked http): builds the right URL/auth/form for SMS
  and WhatsApp; parses the returned SID + status; maps errors to `failed`.
- Outbox + opt-out repos (InMemory; DB-gated Postgres).
- OTP route still returns `devCode` in dev and now triggers `sendOtp`.
- Webhook handler: valid signature updates status; bad signature → 403.

## 8. Rollout
- Dev/CI: `LogMessagingProvider` (no creds) — fully functional + tested.
- Prod: set `TWILIO_*`; register the BSP, get templates approved, point the Twilio
  status callback at `/webhooks/messaging/status`. Until templates are approved,
  WhatsApp degrades to SMS. Reminder scheduler (PR B) driven by an external cron.

## 9. Open questions
- Approved WhatsApp **template names / `ContentSid`s** (per-event) — needed before
  the WhatsApp template path replaces the SMS fallback. Tracked for the ops step.
- Per-operator SMS sender-ID registration in CI (Orange/MTN/Moov) — ops.
