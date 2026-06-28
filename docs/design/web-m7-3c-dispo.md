# Web M7.3c — pro Disponibilités (horaires + tampon + dates bloquées) `/pro/disponibilites`

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001, M7.3c ([web-m7-3-catalogue.md](web-m7-3-catalogue.md)). |
| **Mirrors** | the app's `/pro/availability` (`mobile/lib/screens/provider/availability/availability_screen.dart`). |
| **Surface** | `web/app/pro/(dash)/disponibilites` + a pro-BFF availability route — **no backend change**. |
| **Skill** | `myweli-web-guardrails`. Memory: [[web-mirror-app-flow]]. |
| **Status** | **Built** — `/pro/disponibilites` hours (per-day Ouvert/Fermé + range) + tampon + dates bloquées; 3 unit + 1 e2e. Multi-slot/pause round-tripped. |

## 0. Refined remaining M7.3 split
- **7.3c — Disponibilités** *(this PR)*.
- **7.3d — Acompte + Abonnement + Tableau de bord (G3)** — deposit-policy form +
  the PRO-SUB view + dashboard revenue stats (mostly small/read views).
- **7.3e — Profil + médias** — salon profile edit + gallery + before/after (heaviest).

## 1. Goal & app parity
Edit the salon's **opening hours**, **tampon entre rendez-vous**, and **dates
bloquées** on the web, mirroring the app's Disponibilité screen.

## 2. UX & flow
- **`/pro/disponibilites`** (sidebar "Disponibilités" → live). Authed gate as M7.0.
- **Horaires (Lun→Dim):** each day a row — **Ouvert/Fermé** toggle + **début**/**fin**
  (`type="time"`) when open. *Desktop adaptation:* **one range per day** (covers the
  common case); the app's **multiple slots + recurring pause** are **deferred**
  (flagged — kept on save, not wiped).
- **Tampon entre rendez-vous:** preset chips (0 / 5 / 10 / 15 / 30 min).
- **Dates bloquées:** add (date picker) + list with remove.
- **Enregistrer** → one PUT of the full Availability. Validation: when open, fin >
  début.

## 3. States
loading · error (+retry) · success (toast "Disponibilités enregistrées") ·
validation (fin > début). Empty isn't really applicable (every day has a state).

## 4. Data (no backend change)
- **Load = reuse `GET /me/provider`** → `provider.availability` (already returned).
- **Save via pro BFF** `PUT /api/pro/disponibilites` → `PUT /providers/{pid}/availability`
  with the full object. The client sends its own `providerId`; the backend enforces
  ownership + re-validates (time windows). Preserve `breaks` + any extra slots not
  shown in the UI by round-tripping them.

## 5. Security
Pro httpOnly cookies + `callApiPro` (one call/request); client passes its own
`providerId`, **authz server-side** (forged id → 403). `/pro/*` `noindex`.

## 6. Tests
- **Unit (`lib/pro/availability.ts`):** `toEditable(availability)` (per-day
  open/range, Monday-first), `toApi(form, base)` (round-trips providerId/buffer/
  blockedDates/untouched fields), `validateHours` (fin > début).
- **e2e:** provider → `/pro/disponibilites` shows the seeded hours → toggle a day /
  change a time → **Enregistrer** → success. Stub: PUT availability mutates the pro
  salon copy; `/me/provider` reflects it.

## 7. Open questions (proposed defaults)
- **OQ-7.3c-1** Hours = **one range per day** (Fermé otherwise); multi-slot + pause
  **deferred** (round-tripped, not wiped) → default.
- **OQ-7.3c-2** Acompte moves to **7.3d** (grouped with abonnement + stats), not here → default.
