# Termii SMS provider — cheap CI SMS behind the messaging seam

| | |
|---|---|
| **Requirement** | FR-AUTH-002 (OTP via SMS) · FR-NOTIF-001 (SMS lifecycle events) — cost/coverage for Côte d'Ivoire |
| **Phase** | Accounts / launch — productionize the messaging integration for the CI market |
| **Status** | **Built** — `TermiiMessagingProvider` + `MESSAGING_PROVIDER` selector; activation (Termii account + creds) = ops |
| **Decision** | Add a **second BSP** (Termii) behind the existing `MessagingProvider` seam; **plain-SMS only** (OTP stays server-owned); generic sender at launch |
| **Builds on** | [messaging-notifications.md](messaging-notifications.md) (the seam, outbox, status webhook) |

## 1. Goal & scope
Twilio SMS to Côte d'Ivoire is **$0.4925/segment** vs **$0.008** US (~62×) — confirmed on Twilio's pricing page; a $26.60 / 54-segment test bill suspended the account. **Termii** (a West-Africa BSP) lists **~14 FCFA (~$0.023) per SMS** to CI — **~21× cheaper** — and covers Orange/MTN/Moov. This slice adds a `TermiiMessagingProvider` so the backend can send OTP + lifecycle SMS through Termii, selectable at runtime, **without touching any business logic** (the OTP/booking flows above the seam are unchanged).

**In scope:** the provider adapter, a `MESSAGING_PROVIDER` selector, config/env, tests, docs.
**Out of scope (deferred):** branded (ARTCI-registered) sender ID, Termii delivery-report webhook, WhatsApp-over-Termii, moving transactional messages to push. See [[sms-channel-cost-decision]] (memory) for the channel strategy.

## 2. Design
`TermiiMessagingProvider implements MessagingProvider` ([messaging_provider.dart](../../backend/lib/src/messaging/messaging_provider.dart)) — a near-mirror of `TwilioMessagingProvider`:

- **Endpoint:** `POST {baseUrl}/api/sms/send`, **JSON** body (Twilio used form-encoding):
  `{ to, from, sms, type:"plain", channel, api_key }`.
- **Plain SMS only.** We pass our **own** rendered text (`Votre code Myweli : <code>`). We deliberately do **not** use Termii's Token/OTP API — the OTP lifecycle stays server-owned (generated, **hashed at rest, short TTL, rate-limit + lockout**, dev-code inline only off-prod). Termii is a dumb pipe, exactly like Twilio.
- **Phone:** strip the leading `+` from E.164 (`+225…` → `225…`) — Termii wants the bare MSISDN.
- **Success:** 2xx **with** `message_id` → `(ok:true, providerMessageId)`. A 2xx **without** `message_id` is a soft rejection (balance/sender) → `(ok:false, error:'termii_rejected')`. Non-2xx → `termii_<status>`. Network failure → `termii_unreachable`. **Never throws** (the seam contract).
- **WhatsApp:** returns `whatsapp_not_configured` so the service falls back to SMS (parity with the Twilio adapter).

### Selection (`dependencies.dart`)
`MESSAGING_PROVIDER` ∈ `termii | twilio | log | disabled`; **unset → auto-detect**, preferring Termii when its creds are present, else Twilio. Switching is a one-env-var flip with **no code change**, and the other provider's config can stay for **instant rollback**. Production still **fails fast** if no provider is configured.

**`disabled` — messaging deliberately off (added by G1).** The launch posture: MyWeli ships before company registration, and both channels need a registered entity, so there is no SMS to configure. Production accepts this value and **only** this value as an alternative to real credentials. It is never auto-detected, so "nothing configured" still fails fast; the opt-out has to be typed. It differs from `log` in the one way that matters — it reports `ok: false`, so `messaging_service.dart:61` writes `failed` to the outbox and leaves an honest, queryable record of what was never sent. `log` claims success, which is why production refuses it.

## 3. Config (all via env; secrets `sync:false`, never in git)
| Key | Required | Notes |
|---|---|---|
| `MESSAGING_PROVIDER` | no | `termii`/`twilio`/`log`/`disabled`; unset → auto-detect. `disabled` = deliberately off, the only prod-legal non-provider |
| `TERMII_API_KEY` | for Termii | secret |
| `TERMII_SENDER_ID` | for Termii | generic now; branded needs ARTCI registration |
| `TERMII_BASE_URL` | no | default `https://api.ng.termii.com` |
| `TERMII_CHANNEL` | no | Termii route `generic`/`dnd` (default `generic`) |

Documented in [.env.example](../../backend/.env.example). (Written when the
backend ran on Render, where the slots were declared in `render.yaml`; they are
now Secret Manager entries referenced from
[infra/gcp/service.yaml](../../infra/gcp/service.yaml).)

## 4. Security
- **OTP authority stays server-side** (the reason we use plain-SMS, not Termii's Token API).
- `TERMII_API_KEY` is a secret → env only, `sync:false`, gitignored; never logged. The provider logs nothing (OTP-safe), same as the others; the outbox is the audit record.
- **Threat model:** Termii is the *same class* of outbound BSP dependency already modelled for Twilio (no new trust boundary, no new endpoint) — no STRIDE delta. The status webhook is unchanged (Twilio-shaped; Termii delivery reports are a deferred follow-up).

## 5. Errors
Coded results only (`termii_rejected` / `termii_<status>` / `termii_unreachable` / `whatsapp_not_configured`); the service maps `ok` → outbox `sent`/`failed`. No stack/SQL/credential leakage.

## 6. Tests
[termii_messaging_provider_test.dart](../../backend/test/termii_messaging_provider_test.dart) (mocked `http.Client`): request shape + `+`-stripping + success/`message_id`, 2xx-without-id → rejected, non-2xx → coded, network → unreachable/never-throws, WhatsApp → not-configured + no call, custom route forwarded. Existing `messaging_test.dart` (service/outbox) stays green.

## 7. Rollout (zero-risk)
Default behaviour is unchanged until `TERMII_*` + `MESSAGING_PROVIDER=termii` are set. On Cloud Run that means adding the secrets (`gcloud secrets versions add`), referencing them from [infra/gcp/service.yaml](../../infra/gcp/service.yaml), and deploying — production currently runs `MESSAGING_PROVIDER=disabled`, and flipping it is a reviewed change to that file rather than a dashboard edit, which is the point of the declarative manifest. Then send one real OTP to a CI number, confirm delivery + price in the Termii dashboard, and leave it flipped. Twilio config stays for instant rollback.

## 8. Open questions
- Branded **ARTCI-registered** sender ID (needs company registration) — replaces the generic sender later.
- **Termii delivery-report webhook** for true sent/delivered tracking (its payload differs from Twilio's per-message callback).
- WhatsApp-over-Termii vs Meta direct, post company registration.
