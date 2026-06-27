# In-app notification center (FR-NOTIF-002)

| | |
|---|---|
| **Requirement** | FR-NOTIF-002 (in-app notification center) |
| **Phase** | Phase 3 — backend build + integration |
| **Status** | **Complete** — PR1 backend (feed + write-on-events) ✅ · PR2 app (ApiNotificationService) ✅. |
| **Mirrors** | App `models/app_notification.dart` + `NotificationServiceInterface` (field-for-field). |

## 1. Goal & scope
Make the existing in-app **notification center** screen real: a per-consumer
**feed** persisted server-side, populated when booking lifecycle events fire
(alongside WhatsApp/SMS + push), with read/read-all. The screen + mock already
exist (FR-NOTIF-002) — this swaps the mock for a backend.

Out of scope: a `reviewRequest` entry on completion (wire on the `complete`
transition later); provider-side notifications (the center is consumer V1).

## 2. Data model — migration `0018_notifications`
```sql
CREATE TABLE notifications (
  id text PRIMARY KEY,
  user_id text NOT NULL,
  type text NOT NULL,          -- AppNotificationType.name
  title text NOT NULL,
  body text NOT NULL,
  route text,                  -- optional in-app deep link (e.g. /bookings)
  read boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX notifications_user_idx ON notifications(user_id, created_at DESC);
```

## 3. Contract / endpoints (consumer, self-scoped)
- `GET /me/notifications` → `{ items: [Notification] }` — the caller's latest (≤50),
  newest first.
- `POST /me/notifications/{id}/read` → mark one read (only the caller's; 404 else).
- `POST /me/notifications/read-all` → mark all the caller's read.

`Notification` mirrors `AppNotification`: `{ id, type, title, body, createdAt,
read, route? }`. (`read-all` is a static segment; `{id}/read` is two segments —
no route collision.)

## 4. Layering / impl
- `NotificationsRepository` (interface + InMemory + Postgres): `add({userId, type,
  title, body, route})`, `listForUser(userId, {limit})`, `markRead(userId, id)
  → bool`, `markAllRead(userId)`. All reads/writes **scoped by `userId`**.
- Routes are thin: resolve the principal → delegate, scoped to `principal.userId`.
- **Write-on-events:** `BookingNotifier` gains the repo and, for an app booking
  (`userId != null`), also **persists a notification** per event — reusing the
  push title (`_pushTitle`) + the rendered body + `route: '/bookings'`. Best-effort
  (never breaks a transition). Template → `AppNotificationType`:
  `bookingConfirmed/bookingAccepted → bookingConfirmed`, `depositReceived →
  depositReceived`, `reminder24h/2h → reminder`, `rescheduled → reschedule`,
  `bookingDeclined/cancelled → cancellation`, `refund/rebookReminder → general`.

## 5. Security (threat model T23)
- **Self-scoped**: every read/mutation is filtered by `user_id = principal.sub`;
  a caller can never list or mark another user's notifications (cross-user → 404
  on mark, never leaked on list). Authed only. No PII beyond the booking summary
  already sent over the other channels.

## 6. Tests
- Repo: add + listForUser (newest first, scoped) · markRead (scoped; foreign id
  → false) · markAllRead.
- Routes: list returns only the caller's; mark-read 200/404; read-all clears unread.
- `BookingNotifier`: a lifecycle event writes a notification for the booking's user.

## 7. App (PR2)
- `ApiNotificationService implements NotificationServiceInterface` (GET/POST above,
  silent refresh); register in DI so the existing notification center + unread
  badge read the real feed in API mode (mock unchanged for demo).

## 8. Rollout
Pure feature + one migration; defaults keep demo (mock) behaviour. No config.
