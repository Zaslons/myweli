# Web M7.3 — pro catalogue / dispo / profil / abonnement

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001 (pro dashboard), M7.3 ([web-m7-pro-dashboard.md](web-m7-pro-dashboard.md)). |
| **Mirrors** | the pro app's `/pro/services`, `/pro/artists`, `/pro/availability`, `/pro/deposit-settings`, `/pro/profile`, `/pro/subscription`. |
| **Skill** | `myweli-web-guardrails`. Memory: [[web-mirror-app-flow]]. |
| **Status** | **7.3a built** — `/pro/catalogue` services list + inline create/edit/delete; 6 unit + 1 e2e. **7.3b–7.3d pending.** |

## 0. M7.3 sub-split (it's the largest pro area)
- **7.3a — Catalogue : Services (✅ done)** — `/pro/catalogue` services list + inline create/edit/delete (mirrors the app's service form). List reuses `GET /me/provider`; mutations via pro BFF (client passes its own providerId, backend enforces ownership). 6 unit + 1 e2e.
- **7.3b — Catalogue : Équipe (✅ done)** — Services|Équipe tabs on /pro/catalogue; artistes list + inline create/edit/delete (Nom + Spécialisation). Same BFF/ownership pattern as Services. Per-staff custom hours deferred. 2 unit + 1 e2e. Spec: [web-m7-3b-equipe.md](web-m7-3b-equipe.md).
- **7.3c — Disponibilités (✅ done)** — `/pro/disponibilites` weekly hours (per-day
  Ouvert/Fermé + range) + tampon + dates bloquées; load reuses `GET /me/provider`,
  save via pro-BFF PUT; multi-slot/pause round-tripped. 3 unit + 1 e2e. Spec:
  [web-m7-3c-dispo.md](web-m7-3c-dispo.md).
- **7.3d — Abonnement + Tableau de bord (G3) (✅ done)** — `/pro/abonnement`
  (read-only PRO-SUB: trial status + Pro offer card + Nous contacter) + **revenue
  cards** on `/pro` home (consume `GET /providers/{id}/dashboard` — **closes G3**).
  4 unit + 1 e2e. Spec: [web-m7-3d-abo-stats.md](web-m7-3d-abo-stats.md).
- **7.3e — Profil + médias + Acompte** — salon profile edit + gallery/before-after
  + deposit-policy form (+ the « Configurer mon profil » nudge on the home).

---

# 7.3a — Catalogue : Services `/pro/catalogue`

## 1. Goal & app parity
Manage the salon's **services** on the web, mirroring the app's service list +
form (`mobile/lib/screens/provider/services/`).

## 2. UX & flow
- **`/pro/catalogue`** (pro shell; sidebar "Catalogue" → live). Authed gate as M7.0.
  (Équipe arrives as a tab in 7.3b.)
- **List:** each service → **Nom · prix (range) · durée · badge Actif/Inactif**;
  **« Ajouter un service »**.
- **Create / edit:** an **inline form** (desktop-friendly) with the app's fields:
  **Nom** (requis) · **Description** · **Prix — à partir de** (requis, FCFA) ·
  **Prix maximum** (optionnel, ≥ prix de départ) · **Durée (min)** · **Actif**
  (toggle). **Enregistrer** · **Supprimer** ("Supprimer ce service ?" confirm).
- Server is authoritative (sets id/providerId; validates ranges).

## 3. States
loading · **empty** ("Aucun service. Ajoutez votre premier service.") · error
(+retry) · success · **validation** (nom/prix requis; prix max ≥ prix; durée > 0).

## 4. Data
- **List = reuse `GET /me/provider`** → `provider.services` (no new read).
- **Mutations via pro BFF** — the client sends **its own `providerId`** (from
  `/me/provider`); the backend re-derives the caller's salon and **enforces
  ownership** (role=provider + account.providerId == pid → else 403), so a forged
  id is rejected:
  - `POST /api/pro/catalogue/services` → `POST /providers/{pid}/services`
  - `PATCH /api/pro/catalogue/services/[serviceId]` → backend PATCH
  - `DELETE /api/pro/catalogue/services/[serviceId]?providerId=` → backend DELETE
  After a mutation, re-fetch `/me/provider`. Backend re-validates. **No backend change.**

## 5. Security
Pro httpOnly cookies + `callApiPro` (one backend call per request — avoids a
two-call refresh-rotation hazard). The client passes its own `providerId`, but
**authz is server-side**: the backend matches it against the caller's account
(forged id → 403). `/pro/*` `noindex`.

## 6. Tests
- **Unit:** `validateService` (nom/prix requis; priceMax ≥ price; durée > 0) +
  payload build.
- **e2e:** provider → `/pro/catalogue` shows the seeded service; **add a service**
  → it appears in the list. Extend the stub: services POST/PATCH/DELETE (mutate a
  list) + `/me/provider` reflecting it.

## 7. Open questions (proposed defaults)
- **OQ-7.3a-1** Create/edit = **inline form** on `/pro/catalogue` (vs sub-routes) → default.
- **OQ-7.3a-2** List = reuse `GET /me/provider` (no new read) → default.
- **OQ-7.3a-3** Client passes its own `providerId`; **backend enforces ownership**
  (one call per request, avoids the double-call refresh hazard) → default.
