# Push notifications (FCM) — backend foundation

| | |
|---|---|
| **Requirement** | FR-NOTIF-001 (push channel — FCM) |
| **Phase** | Phase 4 — productionize integrations (deferred V1 channel) |
| **Status** | **Built** — backend foundation + FCM v1 adapter (PR #101); **provider-directed events + deep-link routes + per-platform options** (this PR, 2026-07-14). The app plugin lands in the mobile slice ([push-notifications-app.md](push-notifications-app.md)). |
| **Decision** | Write the **FCM HTTP v1** adapter now (mock-tested); **backend-only** this slice |

## 1. Goal & scope
Add the third notification channel: **push via Firebase Cloud Messaging**. The
backend gains a **device-token registry**, a provider-agnostic `PushProvider`
(dev `LogPushProvider` + real `FcmV1PushProvider`, env-selected, fail-fast in
prod), and pushes the **same booking lifecycle events** that already fire
WhatsApp/SMS to the consumer's registered devices (best-effort).

**Out of scope (ops / follow-up):** the app `firebase_messaging` integration
(permission, token retrieval, register-on-login, foreground/background handling,
tap → deep-link to the in-app notification centre) — it needs the **Firebase
project** + platform config (`google-services.json` / APNs key), which aren't in
the repo. Real sends need the **service-account** creds (also ops).

## 2. Contract / endpoints
- `POST /me/devices` — register `{ token, platform }` (`android|ios|web`) for the
  authenticated principal (consumer or provider). Upsert by token.
- `DELETE /me/devices` — body `{ token }`; removes the caller's token (logout).

## 3. Layering
```
routes (/me/devices)          services                       repositories / adapters
────────────────────  ──────────────────────────  ──────────────────────────────────
POST/DELETE /me/devices → PushService.register/      → DeviceTokenRepository
                          unregister
(booking transitions) → BookingNotifier → PushService.sendToUser → PushProvider
                                                          ├─ LogPushProvider (dev)
                                                          └─ FcmV1PushProvider (prod)
                                                                └─ AccessTokenSource
```
- **`PushService`**: `register/unregister`; `sendToUser(userId, title, body,
  data)` → loads the user's tokens, calls the provider, and **prunes invalid
  tokens** the provider reports (FCM `UNREGISTERED`). Best-effort.
- **`PushProvider`**: `send({tokens, title, body, data}) → ({sent, invalidTokens})`.
  - `LogPushProvider` (dev/CI): no network, reports all sent.
  - `FcmV1PushProvider`: one `messages:send` per token (v1 is single-recipient);
    `Bearer` access token from an **`AccessTokenSource`**.
- **`AccessTokenSource`** (seam so the send path is testable without creds):
  - `ServiceAccountTokenSource`: mints + caches a Google OAuth2 token — RS256 JWT
    (`iss`=client_email, `scope`=…/firebase.messaging, `aud`=oauth2 token URL)
    signed with the SA private key → `oauth2.googleapis.com/token`.

## 4. Data model — migration `0017_device_tokens`
```sql
CREATE TABLE device_tokens (
  token text PRIMARY KEY,        -- one token → one user (re-register reassigns)
  user_id text NOT NULL,
  role text NOT NULL,            -- user | provider
  platform text NOT NULL,        -- android | ios | web
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX device_tokens_user_idx ON device_tokens(user_id);
```

## 5. Security / authz (threat-model delta T22)
- **Token registration** is **self-scoped** to the authed principal; a token row
  is owned by `user_id` = the caller's `sub`. Unregister only removes the
  caller's own token. Re-registering a token reassigns it to the new owner
  (handles device hand-off).
- **Secrets**: the FCM service account (`FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`,
  `FCM_PRIVATE_KEY`) via env only — never the repo (gitleaks stays green).
  Fail-fast in prod when unset (like JWT/storage/Twilio).
- **No PII in pushes** beyond the booking summary already sent over SMS/WhatsApp;
  invalid tokens are pruned (no indefinite fan-out to dead devices).

## 6. Errors / performance
- Send is **best-effort** — never blocks/fails a transition (caught + logged).
- v1 is per-token; we loop the (typically 1–3) tokens per user. A batched/multicast
  path is a later optimization if fan-out grows.
- The OAuth access token is **cached** until shortly before expiry (one mint/hour).

## 7. Tests
- `DeviceTokenRepository` (InMemory; DB-gated Postgres): upsert reassigns owner;
  tokensForUser; scoped delete.
- `PushService`: sendToUser loads tokens + calls provider; **prunes invalid
  tokens**; no tokens → no-op.
- `FcmV1PushProvider` (mocked http + fake `AccessTokenSource`): builds the right
  `messages:send` URL/`Bearer`/body; parses success; maps `UNREGISTERED` → invalid.
- `/me/devices` routes: register (200, self-scoped) · unregister · 401 anon.
- `BookingNotifier` also pushes to the consumer's devices on a transition.

## 8. Rollout
- Dev/CI: `LogPushProvider` — fully functional + tested, no creds.
- Prod: create the Firebase project, set `FCM_*`; wire the app
  (`firebase_messaging` + platform config) to retrieve tokens and `POST
  /me/devices`. Then lifecycle events + reminders reach devices.

## 9. Open questions — ANSWERED (2026-07-14, with the app integration)
- **Deep-link target per event** → the push `data` carries a **`route`**:
  consumer pushes `/appointment/{id}` (fallback `/bookings`), salon pushes
  `/pro/appointment/{id}` (see §10). The in-app FEED row deliberately keeps
  `/bookings` on the consumer side — the web notification center maps that path.
- **Per-platform options** → `FcmV1PushProvider` now sends
  `android: { priority: 'high', notification: { channel_id: 'myweli_default' } }`
  and `apns: { headers: { 'apns-priority': '10' } }`. Bookings are
  time-sensitive; the channel id is the one the app creates at boot
  (`FcmV1PushProvider.androidChannelId` == the app's `kPushChannelId` — a
  background notification would otherwise land in the unnamed default channel).

## 10. Provider-directed pushes — `SalonNotifier` (2026-07-14)

`BookingNotifier` only ever notified the **consumer**, while the pro app asked
for push permission promising « soyez prévenu·e dès qu'un client réserve ».
`SalonNotifier` is its provider-directed sibling: **push + in-app feed only**
(no WhatsApp/SMS to salons — the `MessageTemplate` set maps 1:1 to approved
consumer templates and stays untouched).

| Event | Fired from | Title (FR) |
|---|---|---|
| `newBooking` | `POST /appointments` (the client's own booking) | « Nouvelle réservation » |
| `clientCancelled` | `POST /appointments/{id}/cancel` (consumer-owned route) | « Réservation annulée » |
| `depositSubmitted` | `POST /appointments/{id}/deposit` (proof attached) | « Justificatif d'acompte reçu » |

**The guard:** salon-entered bookings ride `POST /providers/{id}/appointments`,
which has **no hook** — a salon is never notified about its own entry (pinned
by a test that provides a live notifier and asserts an empty feed).

**Recipient rule (stated once, enforced in `_recipients`):** every **ACTIVE**
member with a **linked account** whose role can see the whole journal
(`Cap.journalViewAll` — owner / manager / réception); an **own-scope**
Collaborateur (`Cap.journalViewOwn`) only when the booking is assigned to
**their** artist. An unassigned booking therefore reaches view-all members
only. Deduped by account. Invited (not yet accepted) and revoked rows are
skipped.

**Preferences:** all three events are **transactional**, so the
reminders/marketing toggles don't apply; the push channel still honours each
recipient's `push` preference. The **in-app feed row is always written** — a
passive history log (the same posture as the consumer feed, threat T24) that
fuels the pro bell.

**Payload:**
```json
{ "event": "new_booking|client_cancelled|deposit_submitted",
  "appointmentId": "a1",
  "providerId": "p1",          // the pro app switches salon before deep-linking (R6)
  "route": "/pro/appointment/a1" }
```
Bodies render the **salon's wall-clock** (multi-pays §3) and carry **no client
PII** — the name/phone stay in the app behind auth (threat T58).

**No REST contract change:** no new endpoints; `/me/devices`,
`/me/notifications` and `/me/notification-preferences` are already
role-agnostic (a provider account reads its own feed with its provider
session). `openapi.yaml` is untouched by this PR.
