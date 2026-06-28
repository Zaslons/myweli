# Web M7.1 — pro « Rendez-vous » (Calendrier + Liste) `/pro/rendez-vous`

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001 (pro dashboard), M7.1 ([web-m7-pro-dashboard.md](web-m7-pro-dashboard.md)). |
| **Mirrors** | the pro app's **`/pro/appointments`** screen (`mobile/lib/screens/provider/appointments/appointment_list_screen.dart` + `appointment_calendar_view.dart`). |
| **Surface** | `web/app/pro/(dash)/rendez-vous` — **no backend change** (reuses the M7.0 pro BFF). |
| **Skill** | `myweli-web-guardrails`. Memory: [[web-mirror-app-flow]]. |
| **Status** | **Built** — Calendrier + Liste, sidebar "Rendez-vous" live. |

## 1. Goal & app parity
Mirror the app's **« Rendez-vous »** flow on desktop: the same two views and the
same sub-tabs, so a salon manages bookings the same way on web as in the app.
(The app has **no** separate "Agenda" — the calendar lives inside Rendez-vous —
so the M7.0 sidebar's separate "Agenda" item is dropped; one "Rendez-vous" link.)

## 2. UX & flow (faithful to the app)
- **`/pro/rendez-vous`** (pro shell → sidebar "Rendez-vous"). Authed gate as M7.0.
- **Two view tabs: « Calendrier » | « Liste »** (app's top tabs).
  - **Calendrier:** a month grid (Monday-start), prev/next month, **today** + days
    **with bookings** marked; click a day → that day's appointments below ("pour
    {date}"), sorted by time. Default selected = today.
  - **Liste:** sub-tabs **« Aujourd'hui » · « À venir » · « En attente » · « Tous »**
    (the app's exact sub-tabs) → the filtered list.
- **Row** (`ProAppointmentRow`, extracted from Aujourd'hui and reused): time ·
  client · services · **status chip** (En attente/Confirmé/Terminé/Annulé/Absence)
  · total. *Desktop adaptation:* shows service **names** (the app shows
  "{n} service(s)" for space) — same data, richer on a wide screen.

## 3. States
loading · **empty** (Calendrier: "Aucun rendez-vous ce jour-là." / Liste: "Aucun
rendez-vous.") · error (+retry) · success.

## 4. Data (no backend change)
Reuse **`GET /api/pro/appointments`** once (provider-scoped server-side), then
**filter client-side** — `appointmentsOnDate` (calendar day) + `filterList(tab)`
(liste) in `lib/pro/agenda.ts`. Service names mapped from the salon
(`GET /api/pro/me`). **Perf follow-up:** a server `?from=&to=` range query for
high-volume salons (V1 volumes are small → client filter is fine, keeps M7.1
backend-free).

## 5. Security
Pro httpOnly cookies + `callApiPro` (silent refresh); list **provider-scoped
server-side**; `/pro/rendez-vous` `noindex`.

## 6. Tests
- **Unit:** `appointmentsOnDate` (right day, sorted), `filterList` (the 4 tabs),
  `monthMatrix` (6×7, Monday-start), `daysWithBookings`, `addDays`/`addMonths`.
- **e2e:** logged-in provider → `/pro/rendez-vous`: Calendrier shows today's
  booking; switch to Liste → Aujourd'hui shows it. (M7.0 stub: bookings dated today.)

## 7. Open questions (resolved)
- Date filtering = **client-side over the existing list** (server `from/to`
  deferred). · One `ProAppointmentRow` shared across Aujourd'hui + Rendez-vous.
- **Followed the app's flow/user story** (two tabs + four sub-tabs) per
  [[web-mirror-app-flow]].
