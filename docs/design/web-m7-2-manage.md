# Web M7.2 — pro booking detail + lifecycle actions `/pro/rendez-vous/[id]`

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001 (pro dashboard), M7.2 ([web-m7-pro-dashboard.md](web-m7-pro-dashboard.md)). |
| **Mirrors** | the app's **« Détails du rendez-vous »** (`mobile/lib/screens/provider/appointments/pro_appointment_detail_screen.dart`). |
| **Surface** | `web/app/pro/(dash)/rendez-vous/[id]` + pro BFF action/screenshot routes — **no backend change**. |
| **Skill** | `myweli-web-guardrails`. Memory: [[web-mirror-app-flow]]. |
| **Status** | **Built** — detail (derived from the provider list) + accept/reject/complete/no-show (confirm on absent) + deposit proof; status-string fix (noShow/Absent). 3 unit + 1 e2e. |

## 1. Goal & app parity
Tap a booking → see its details and **act on it**, exactly like the app's pro
detail screen.

## 2. Actions per status (faithful to the app)
- **`pending`** → **Accepter** (→ confirmed) · **Refuser** (→ cancelled).
- **`confirmed`** → **Marquer comme terminé** (→ completed) · **Marquer comme
  absent** (→ noShow, **confirm dialog** "Le client ne s'est pas présenté ?").
- **`completed` / `cancelled` / `noShow`** → terminal, no actions.
- **No provider "Annuler"** — the app's pro flow has none (cancel is the client's
  action, already on the consumer web). Endpoints: `POST /appointments/{id}/{accept,
  reject,complete,no-show}` (bodyless; server enforces ownership + valid transition).

## 3. Detail content (mirrors the app)
Date/heure · client (name/phone if present) · prestations (names from the salon) ·
statut · **Acompte**: "Acompte annoncé : {montant}" + proof state — if a
screenshot exists, **« Voir le justificatif »** (loads the short-lived **signed**
URL via `GET /appointments/{id}/deposit-screenshot`, the salon-side private view).

## 4. Data (no backend change)
- **Detail read:** `GET /appointments/{id}` is **consumer-scoped** (403 for a
  provider), so the detail is **derived from the provider list** (`GET /appointments`
  → `listForProvider`, already provider-scoped) — the BFF finds the id in the
  salon's own list (404 otherwise). Server authority preserved.
- **Actions:** pro BFF `POST /api/pro/appointments/[id]/[action]` (allowlist
  accept|reject|complete|no-show) → the lifecycle endpoints (`callApiPro`). After
  success, re-fetch the list → status updates.
- **Deposit proof:** pro BFF `GET /api/pro/appointments/[id]/deposit-screenshot`
  → `{url}` (signed).
- Rows in Rendez-vous + Aujourd'hui become **links** to the detail (`ProAppointmentRow`
  gains an optional `href`).

## 5. Status-string fix (correctness, found via the app)
The canonical wire statuses are **`pending/confirmed/completed/cancelled/noShow`**
(camelCase) and **reject → `cancelled`** (no "rejected"). The web's `statusLabelFr`
+ consumer `categorize` currently use `no_show`/`rejected` → **fix to `noShow`**
(label **« Absent »**, matching the app) with `no_show` kept as a harmless alias.

## 6. States
loading · **not-found** (id not in the salon's list → "Rendez-vous introuvable") ·
error (+retry; action failure → message) · success. Action in-flight → buttons
disabled; no-show → confirm first.

## 7. Security
Pro httpOnly cookies + `callApiPro`; actions + screenshot are **provider-scoped
server-side** (ownership from the account; cross-salon → 403; invalid transition →
409). `/pro/*` `noindex`. Signed screenshot URL is short-lived.

## 8. Tests
- **Unit:** `actionsFor(status)` (the per-status action sets), `statusLabelFr`
  (noShow → Absent), `categorize` (noShow → cancelled tab).
- **e2e:** provider login → Rendez-vous → open a **pending** booking → **Accepter**
  → status becomes **Confirmé**. Extend the stub: detail via list, action endpoints
  (mutate the stub's status), deposit-screenshot.

## 9. Open questions (proposed defaults)
- **OQ-M7.2-1** Detail derived from the provider **list** (vs a new provider detail
  GET) → default (backend-free; list is already provider-scoped).
- **OQ-M7.2-2** Actions = accept/reject/complete/no-show, **no provider-cancel** →
  default (mirrors the app).
- **OQ-M7.2-3** Include deposit-proof viewing (signed URL) → default (the app does).
