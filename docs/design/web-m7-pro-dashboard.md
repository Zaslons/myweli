# Web M7 — pro dashboard `/pro` (the desktop salon tool)

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001 (pro web dashboard, parity with the pro app). |
| **Milestone** | M7 ([public-web.md](public-web.md) §11). The last web surface. |
| **Surface** | Backend (tiny: `GET /me/provider`) + `web/app/pro/*` + a **pro BFF**. |
| **Skills** | `myweli-web-guardrails` (+ `myweli-backend-guardrails` for `GET /me/provider`). |
| **Status** | **M7.0 ✅** (auth + shell + Aujourd'hui) · **M7.1 ✅** (« Rendez-vous »: Calendrier + Liste) · **M7.2 ✅** (booking detail + lifecycle actions). **M7.3 pending.** |

## 1. Goal
A **desktop-grade** tool so a salon can run Myweli from a PC: log in, see today's
agenda, manage bookings (accept/reject/complete/no-show), and edit the
catalogue/hours — at **parity with the pro app**, adapted to a wide screen.

## 2. Architecture (whole M7)
- **`/pro/*` namespace** with its **own desktop layout** (left sidebar nav:
  Aujourd'hui · Agenda · Rendez-vous · Catalogue · Disponibilités · Profil ·
  Abonnement) — distinct from the consumer site (no public header/install-as-client;
  it nudges the **pro app** instead).
- **Pro session = separate** httpOnly cookies (`myweli_pro_at`/`_rt`) and a **pro
  BFF** (`app/api/pro/*`) with its own `callApiPro` (silent refresh via
  **`/auth/provider/refresh`**). Consumer and pro sessions never collide
  (distinct cookie names — WEB.md §4).
- **All authed, `noindex`, dynamic.** Reuses the existing hardened provider
  endpoints; the server stays the authority (ownership resolved from the provider
  account, never a client id).

## 3. Backend (small) — `GET /me/provider`
Mirror of `GET /me`: the provider's salon id is resolved server-side from the
account, and there's no endpoint to read "my own salon". Add **`GET /me/provider`**
→ `{ account, provider }` (the provider account + its managed provider record);
`role=provider` + linked salon required (else 403/404). OpenAPI + handler test
(self/anon/non-provider/unlinked) + threat-model row. *(backend guardrails.)*

## 4. PR breakdown (decision)
- **M7.0 — auth + shell + Aujourd'hui** *(✅ done)*: `GET /me/provider`; pro BFF
  (`request-otp`/`verify`/`logout` + `callApiPro` silent refresh via
  `/auth/provider/refresh`); `/pro/connexion` (provider phone/OTP); `/pro` layout
  (sidebar — later sections show "Bientôt") + **Aujourd'hui** (today's bookings +
  counts from `GET /appointments`); logout. **Login only** (new-salon registration
  stays in the app for now — flagged parity gap).
- **M7.1 — « Rendez-vous » (✅ done):** mirrors the app's `/pro/appointments` —
  **Calendrier** (month grid + day list) **+ Liste** (Aujourd'hui/À venir/En
  attente/Tous); shared `ProAppointmentRow`; client-side day/tab filter over the
  pro list (no backend change). Sidebar's separate "Agenda" dropped (the app has
  none). 5 unit + 1 e2e. Spec: [web-m7-1-agenda.md](web-m7-1-agenda.md).
- **M7.2 — Manage bookings (✅ done):** `/pro/rendez-vous/[id]` detail (derived
  from the provider list — `GET /appointments/{id}` is consumer-scoped) +
  **Accepter / Refuser / Terminé / Absent** (confirm on absent) + deposit
  justificatif (signed URL). No provider-cancel (mirrors the app). Status-string
  fix: `noShow`/« Absent ». 3 unit + 1 e2e. Spec: [web-m7-2-manage.md](web-m7-2-manage.md).
- **M7.3 — Catalogue & dispo (+ profil/abonnement)**: services CRUD,
  weekly hours, deposit policy, artists, profile, the PRO-SUB view.

## 5. M7.0 — UX & states
- **`/pro/connexion`** — provider phone → OTP (`/api/pro/auth/*`); on success →
  `/pro`. Already-signed-in → `/pro`. Unknown provider → "Compte introuvable —
  inscrivez-vous dans l'app Myweli Pro" (+ app push). `returnTo` continuity.
- **`/pro` (Aujourd'hui)** — authed (no session → redirect `/pro/connexion`):
  greeting (salon name), **today's counts** (à confirmer / confirmés /
  à venir), and **today's bookings** list (time, client, services, status). Each
  state: loading · empty ("Aucun rendez-vous aujourd'hui") · error+retry · success.
- **Layout** — sidebar nav (the 7 sections; later ones show a "Bientôt" hint
  until their PR lands), salon name, logout. Desktop-first (WEB-DESIGN-STANDARDS
  responsive rules); tokens only.

## 6. Security
Pro httpOnly cookies (no tokens in JS); same-origin pro BFF; **silent refresh**
via `/auth/provider/refresh`; every read/action is **provider-scoped server-side**
(salon resolved from the account → a provider only ever sees/acts on its own
salon; cross-salon → API 403). `/pro/*` `noindex`. Logout clears pro cookies.

## 7. Tests (M7.0)
- **Backend:** `GET /me/provider` → 200 (linked provider), 401 (anon), 403
  (non-provider role), 404/403 (unlinked account).
- **Unit (web):** today's-counts derivation (à confirmer/confirmés/à venir from a
  booking list), pro BFF refresh helper (shares the M6 pattern).
- **e2e (Playwright):** provider login (OTP) → `/pro` shows today's bookings;
  **unauthenticated `/pro` → `/pro/connexion`**. Extend the stub with
  `/auth/provider/otp/*`, `/auth/provider/refresh`, `/me/provider`, provider
  `GET /appointments`.

## 8. Rollout
Additive; one small backend route. `/pro/*` dynamic + noindex. Deployed with the
rest; the pro-app store links filled at the accounts phase.

## 9. Open questions (proposed defaults)
- **OQ-M7-1** PR split = 7.0 shell → 7.1 agenda → 7.2 manage → 7.3 catalogue → default.
- **OQ-M7-2** Pro session = separate `myweli_pro_*` cookies + pro BFF → default.
- **OQ-M7-3** Add **`GET /me/provider`** (`{account, provider}`) → default.
- **OQ-M7-4** M7.0 = **login only** (new-salon registration stays in the app) → default.
