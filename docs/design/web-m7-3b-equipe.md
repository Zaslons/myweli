# Web M7.3b — pro catalogue : Équipe (artistes) `/pro/catalogue`

| | |
|---|---|
| **Requirement** | FR-WEB-MP-001, M7.3b ([web-m7-3-catalogue.md](web-m7-3-catalogue.md)). |
| **Mirrors** | the app's `/pro/artists` list + employee form (`mobile/lib/screens/provider/artists/`). |
| **Surface** | `web/app/pro/(dash)/catalogue` (adds an **Équipe** tab) — **no backend change**. |
| **Skill** | `myweli-web-guardrails`. Memory: [[web-mirror-app-flow]]. |
| **Status** | **Built** — Services|Équipe tabs on `/pro/catalogue`; artistes list + inline create/edit/delete; 2 unit + 1 e2e. Per-staff hours deferred. |

## 1. Goal & app parity
Manage the salon's **équipe (artistes)** on the web — same flow as 7.3a Services,
mirroring the app's employee list + form.

## 2. UX & flow
- **`/pro/catalogue`** gains two tabs: **Services** (7.3a) | **Équipe**.
- **Équipe list:** each artist → **Nom · Spécialisation** + **« Ajouter un membre »**.
- **Create / edit:** inline form (same pattern as Services) — **Nom** (requis) ·
  **Spécialisation** (optionnel). **Enregistrer** · **Supprimer** ("Supprimer ce
  membre ?" confirm).
- **Deferred (flag):** the app's **"Suit les horaires du salon" / per-staff custom
  hours** (`Artist.weeklyHours`) — heavier; on web the artist defaults to the salon
  hours for now. Noted, not silently dropped.

## 3. States
loading · **empty** ("Aucun membre. Ajoutez votre équipe.") · error (+retry) ·
success · **validation** (nom requis).

## 4. Data (no backend change)
- **List = reuse `GET /me/provider`** → `provider.artists` (already returned).
- **Mutations via pro BFF** (client sends its own `providerId`; backend enforces
  ownership), mirroring Services:
  - `POST /api/pro/catalogue/artists` → `POST /providers/{pid}/artists`
  - `PATCH /api/pro/catalogue/artists/[artistId]` → backend PATCH
  - `DELETE /api/pro/catalogue/artists/[artistId]?providerId=` → backend DELETE
  After a mutation, re-fetch `/me/provider`. `rating`/`reviewCount` are read-only
  (server-owned).

## 5. Security
Same as 7.3a: pro httpOnly cookies + `callApiPro` (one call/request); client passes
its own `providerId`, **authz server-side** (forged id → 403). `/pro/*` `noindex`.

## 6. Tests
- **Unit:** `validateArtist` (nom requis) + `buildArtistPayload`.
- **e2e:** provider → `/pro/catalogue` → **Équipe** tab shows the seeded artist
  (Awa) → **add a member** → it appears. Stub: artists POST/PATCH/DELETE on the
  pro salon copy.

## 7. Open questions (proposed defaults)
- **OQ-7.3b-1** Équipe = a **tab on /pro/catalogue** (vs a separate route) → default.
- **OQ-7.3b-2** Per-staff custom hours **deferred** (defaults to salon hours) → default.
