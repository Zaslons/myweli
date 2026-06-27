# Notification preferences (FR-NOTIF-004)

| | |
|---|---|
| **Requirement** | FR-NOTIF-004 — "Notification preferences (channel & category opt-out where law/store requires)." |
| **Phase** | V1 small-gap sweep (ROADMAP §1.8). |
| **Surfaces** | Backend (`/me/notification-preferences` + send-path enforcement) · Consumer app (`NotificationPreferencesScreen`). |
| **Status** | **Complete** — PR1 backend ✅ (prefs storage + routes + send-path enforcement) · PR2 app ✅ (preferences screen + service wiring). |
| **Builds on** | The existing per-phone promotional opt-out (`MessagingPrefsRepository`, consulted in `MessagingService.sendTemplate`) and the `BookingNotifier` orchestrator. |

## 1. Goal & scope
Let a consumer control which **non-essential** notifications they receive, and
satisfy the ARTCI marketing opt-out (PRD §18). Preferences are **per-user**,
**opt-out** (default ON), stored server-side, and **respected at send time** —
no dead toggles.

**Three toggles** (signed off): **reminders**, **marketing**, **push**.
**Always-on (not a toggle):** transactional confirmations/changes
(confirmed/accepted/declined/deposit/rescheduled/cancelled/refund) — service
messages that always send.

Out of scope (V2): per-channel granularity *within* WhatsApp vs SMS; quiet
hours; provider-side preferences.

## 2. Data model — migration `0019_notification_preferences`
```sql
CREATE TABLE notification_preferences (
  user_id    text PRIMARY KEY,
  reminders  boolean NOT NULL DEFAULT true,
  marketing  boolean NOT NULL DEFAULT true,
  push       boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);
```
**No row = all-true defaults** (a fresh user receives everything). Upsert on write.

## 3. Contract (consumer, self-scoped) — `routes/me/notification-preferences/index.dart`
- `GET /me/notification-preferences` → `200 { reminders, marketing, push }`.
- `PUT /me/notification-preferences` body `{ reminders?, marketing?, push? }`
  (partial; each provided field must be a bool → else `400 invalid_body`) →
  `200` merged prefs. Unknown fields ignored; the three transactional categories
  can't be disabled (not exposed).
- `405` for other verbs. Authed only; the key is **always `principal.userId`**
  (no id in the path → nothing to enumerate or cross-access).

`NotificationPreferences` schema mirrors the app model field-for-field.

## 4. Layering / impl
- **Repo** `NotificationPrefsRepository` (interface + InMemory + Postgres):
  - `Future<NotificationPrefs> get(String userId)` — returns all-true defaults when absent.
  - `Future<NotificationPrefs> update(String userId, {bool? reminders, bool? marketing, bool? push})` — upsert merge, returns the row.
  - `NotificationPrefs { reminders, marketing, push }` (const default = all true).
- **Route** thin: resolve principal → `get` / `update` scoped to `principal.userId`.
- **Send-path enforcement (the point of the feature)** — centralized in
  `BookingNotifier.notify` (the reminder **scheduler** also calls `notify`, so one
  place covers both event + scheduled sends). For an app booking (`userId != null`)
  load prefs once, then gate:

  | Send | Gated by |
  |---|---|
  | `reminder24h` / `reminder2h` messaging | `reminders` |
  | promotional template (`rebookReminder`) messaging | `marketing` |
  | all other (transactional) messaging | always |
  | push (`_push.sendToUser`, any template) | `push` **and** the template's category (so "reminders off" also kills the reminder push) |
  | in-app feed entry (`_notifications.add`) | always (it's a passive history log, not a proactive notification) |

  Manual bookings (a `clientPhone`, no `userId`) have no app account → defaults
  (all true), unchanged behaviour. Keep `MessagingService`'s per-phone
  promotional check as a lower-layer backstop.

## 5. Security (threat model T24)
- **Self-scoped:** every read/write is keyed by `principal.userId`; no path id, so
  no enumeration or cross-user access.
- **Tampering:** the server only honours the three known boolean fields; a client
  cannot disable transactional service messages or inject other keys.
- No new PII; authed only; standard error envelope.

## 6. App (PR2)
- `models/notification_preferences.dart` — `{reminders, marketing, push}` + json/copyWith.
- `NotificationServiceInterface` gains `getPreferences()` + `updatePreferences({reminders, marketing, push})`; **Mock** (latency, in-memory) + **Api** (`GET`/`PUT`).
- `NotificationPreferencesProvider` (ChangeNotifier): load; optimistic toggle with **revert + snackbar on failure**.
- `NotificationPreferencesScreen`: three `SwitchListTile`s (Rappels de rendez-vous · Offres & promotions · Notifications push) + an info row explaining confirmations always send. Four states (loading/empty-n.a./error+retry/success). Tokens only; FR copy.
- Entry: replace the **dead Switch** in `profile_screen` "Notifications" tile with a nav tile → `/profile/notifications`. Router registers the route.

### Copy (FR)
- Title: « Préférences de notification ».
- « Rappels de rendez-vous » — sub: « Rappels 24 h et 2 h avant vos rendez-vous. »
- « Offres & promotions » — sub: « Offres, nouveautés et relances. »
- « Notifications push » — sub: « Notifications sur cet appareil. »
- Info: « Les confirmations et changements de rendez-vous sont toujours envoyés. »
- Save error: « Impossible d'enregistrer. Réessayez. »

## 7. Tests
- **Backend:** repo defaults (absent → all true) + upsert merge; route GET/PUT (200, partial update, `400` non-bool, `401`, `405`); **BookingNotifier gating** — reminders off → no reminder messaging/push (but feed entry stays); marketing off → promotional skipped; push off → no push, messaging still sent; manual booking unaffected.
- **App:** model json round-trip; mock get/update; provider toggle + revert-on-failure; `ApiNotificationService` prefs parse + PUT path.

## 8. Rollout
One migration; defaults keep current behaviour (everything on). No config, no flag.
PR1 backend (storage + enforcement) → PR2 app (screen). Mock unchanged for demo.
