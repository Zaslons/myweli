# Web notifications + « Revenus » (parity P1c — audit 5.1 / 5.2 / 9.1 / 9.2)

**Status:** Built (PR fix/parity-p1c-web-surfaces) · **Audit:**
[parity-audit-modules-2026-07.md](parity-audit-modules-2026-07.md) modules 5 + 9 ·
**Contract:** [openapi.yaml](../api/openapi.yaml) (`/me/notifications*`,
`/me/notification-preferences`, `/providers/{id}/earnings` — all pre-existing;
**no backend change**).

## Goal & scope

Close the last P1 parity gaps: a web-only consumer never sees booking-lifecycle
notifications in-product (5.1), cannot edit notification preferences (5.2), and
a salon on web has no earnings page (9.1) and no week-revenue card (9.2). All
four endpoints already serve the app — this is web UI + BFF plumbing only.

## 1. Consumer notification center (5.1) — `/mon-compte/notifications`

Mirrors the app's `notifications_screen` flow (list newest-first ≤50, unread
emphasis, tap = mark-read + follow the deep link, « Tout lire »), web-adapted.

- **Entry points:** a bell in the site header (unread dot; renders only for a
  signed-in session — anonymous 401 → nothing, no polling) + a « Notifications »
  row on /mon-compte.
- **List:** white cards (bg-secondary, rounded-xl); leading glyph per type
  (bookingConfirmed ✓ · depositReceived 💰-class wallet · reminder ⏰ ·
  reschedule ⇄ · cancellation ✕ · reviewRequest ★ · general 🔔 — inline SVG,
  `currentColor`); unread = bold title + primary dot; body + `formatDateTimeFr`.
- **Tap:** `POST /me/notifications/{id}/read` (optimistic) then follow
  `webRouteFor(route)` — the notifier only ever writes `/bookings` →
  `/mon-compte`; unknown/null → stay.
- **« Tout lire »:** visible while unreadCount > 0 → `POST read-all`.
- **States:** loading « Chargement… » · error « Chargement impossible » +
  Réessayer · empty « Aucune notification » + « Vos confirmations de rendez-vous
  et nouveautés apparaîtront ici. » · list.

## 2. Préférences (5.2) — a block on the same page

The app has a separate screen; on web the three toggles live under the list
(one page, fewer hops — same PUT). Copy mirrors the app: « Rappels de
rendez-vous » (Rappels 24 h et 2 h avant vos rendez-vous.) · « Offres &
promotions » (Offres, nouveautés et relances.) · « Notifications push »
(Notifications push sur vos appareils mobiles.). Optimistic toggle, revert +
error line on failure. Footer note: « Les confirmations et changements de
rendez-vous sont toujours envoyés. »

## 3. Pro « Revenus » (9.1) — `/pro/revenus` (+ 9.2 week card)

Mirrors the app's `earnings_screen`: period tabs **Aujourd'hui · Semaine ·
Mois · Tout** (semaine = Monday-start, same ranges as the app) → total card
(`formatFcfa`, realized/completed only) → transaction rows (date · montant).
Empty: « Aucune transaction ». Sidebar gains « Revenus » (before Profil).
9.2: the pro home's revenue grid gains « Revenus cette semaine »
(`weekRevenue` was already in the DTO — web simply dropped it).

## BFF slice (all new routes, session-cookie → bearer)

| Route | Method | Backend |
|---|---|---|
| `/api/me/notifications` | GET | `GET /me/notifications` |
| `/api/me/notifications/read-all` | POST | idem |
| `/api/me/notifications/[id]/read` | POST | idem (self-scoped) |
| `/api/me/notification-preferences` | GET · PUT | idem (partial PUT) |
| `/api/pro/earnings` | GET | `GET /providers/{id}/earnings?startDate=&endDate=` (ownership-scoped → 403) |

Pro idiom as everywhere: the client sends its own `providerId`; the backend
enforces ownership. No new public fields; authed pages `robots: noindex`.

## Security · perf

httpOnly-cookie session via `callApi`/`callApiPro`; the header bell fires ONE
fetch on mount (no polling; anonymous → BFF 401 without a backend call). No
PII beyond the caller's own data.

## Tests

- **Unit:** `webRouteFor` mapping + unread count (notifications), `periodRange`
  for the four tabs incl. Monday-start week (earnings).
- **e2e:** consumer — bell dot → page shows the unread item → « Tout lire » →
  emphasis cleared → toggle a préférence (stub-persisted). Pro — sidebar →
  Revenus: total + rows; « Aujourd'hui » tab narrows to today's transaction.
