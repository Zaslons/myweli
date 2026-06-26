# Consumer favorites — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Consumer favorites · V1 (PRD §8.2) |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ (myweli-dev-guardrails for the app swap) |

## 1. Goal & scope

Put consumer **favorites** (saved providers) on the real backend — list / add / remove — replacing `ApiFavoritesService`… actually `MockFavoritesService` (the consumer DI still points at the mock, which persists to `SharedPreferences`). Favorites become server-side + per-account, so they follow the user across devices.

**In scope:**
- Backend: `GET /me/favorites`, `POST /me/favorites/{providerId}`, `DELETE /me/favorites/{providerId}` — consumer-authenticated, **self-scoped by the token**. New `favorites` table (migration `0006`), `FavoritesRepository` (in-memory + Postgres), `FavoritesService`.
- App: new `ApiFavoritesService` (consumer session + silent refresh) selected under `AppConfig.useApiBackend`; mock otherwise.
- Contract + threat model + tests (incl. DB-gated).

**Out of scope:** favorites of *artists*; "notify me when available"; any provider-side view of who favorited them.

**Build:** one PR.

## 2. UX & flows
No UX change — `FavoritesProvider` + the home favorites strip / favorites screen already drive this behind `FavoritesServiceInterface`. `isFavorite` is computed **locally** from the loaded id set, so it needs no endpoint. This slice only moves storage from the device to the account.

## 3. API & contract
All require a **consumer** (`user`) token; the user is the token's `sub` (never a path/body param) — so a user only ever sees/edits their own favorites.
- **`GET /me/favorites`** → `{ "providerIds": [ "<id>", … ] }` (the user's saved provider ids).
- **`POST /me/favorites/{providerId}`** → **204** (idempotent — favoriting twice is a no-op). 404 if the provider doesn't exist.
- **`DELETE /me/favorites/{providerId}`** → **204** (idempotent — removing a non-favorite is a no-op).

Errors: 401 `unauthorized`, 403 `forbidden` (non-consumer token), 404 `not_found` (unknown provider on add), 405.

## 4. Data model
New table (migration `0006_favorites`):
```sql
CREATE TABLE IF NOT EXISTS favorites (
  user_id     text NOT NULL,
  provider_id text NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, provider_id)
);
```
The PK doubles as the index for "list by user" (leading `user_id`) and makes add idempotent (`ON CONFLICT DO NOTHING`). No FK (consistent with `appointments.user_id`); `user_id` always comes from a verified token, and provider existence is validated in the service.

## 5. Architecture & patterns
- **`FavoritesRepository`** (interface; in-memory + Postgres): `listForUser(userId) → List<String>`, `add(userId, providerId)`, `remove(userId, providerId)`. Postgres uses `INSERT … ON CONFLICT DO NOTHING` / `DELETE` / `SELECT provider_id … ORDER BY created_at DESC`.
- **`FavoritesService`**: `list(userId)`; `add(userId, providerId)` validates the provider exists via `ProvidersRepository.byId` (→ `not_found`) then delegates; `remove(userId, providerId)` delegates. No cross-user path exists (userId is the token's).
- **Routes** (thin): `routes/me/favorites/index.dart` (GET) + `routes/me/favorites/[providerId].dart` (POST/DELETE). Each: principal → `role==user` → delegate → shape (204 for add/remove).
- DI + middleware provide the repo + service.
- **App:** `ApiFavoritesService implements FavoritesServiceInterface` on the **consumer** `RefreshingHttpClient` (`/auth/refresh`): `getFavoriteProviderIds` → `GET /me/favorites`; `addFavorite`/`removeFavorite` → POST/DELETE (the `userId` arg is ignored — the token scopes it); `isFavorite` → fetch the ids and check membership (no endpoint). DI selects it under `useApiBackend`.

## 6. Validation & authority
- `providerId` (path) must reference a real provider on **add** (→ 404). Remove is lenient (idempotent).
- The **server is the authority** on whose favorites these are — always the token's `sub`; the client cannot act on another user's list.

## 7. Security & authz
- Deny by default; consumer token required; **self-scoped** (no ownership param to forge). A `provider`-role token is rejected (403) — favorites are a consumer feature.
- **Threat model:** extend **T5** (self-scoped `/me` data) to include `/me/favorites` — list/add/remove are always scoped to the token's `sub`.

## 8. Performance
- List: one indexed `SELECT` by `user_id` (PK-covered). Add/remove: one statement. Per-user, naturally bounded (a strip of saved salons) — no pagination needed; the contract can add it later if a power user's list grows. No N+1.

## 9. Testing plan
- **Repo (unit + DB-gated):** add is idempotent; remove is idempotent; `listForUser` returns only that user's ids (isolation), newest-first.
- **Service (unit):** add unknown provider → not_found; add/remove/list happy paths.
- **Handler:** `GET` → 200 `{providerIds}`; `POST` valid → 204; `POST` unknown provider → 404; `DELETE` → 204; **another user's token sees only its own list** (cross-user isolation); no token → 401; provider token → 403; bad verb → 405.
- **App:** `ApiFavoritesService` GET/POST/DELETE hit the right paths + parse; `isFavorite` reflects the list; 401 → consumer silent refresh.

## 10. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green (incl. DB-gated).
- [ ] OpenAPI: the three paths + the `{providerIds}` response.
- [ ] Threat model T5 note; ROADMAP entry; spec cross-linked from the routes/service/repo + `ApiFavoritesService`; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (signed off)
1. **Response = provider ids only** — `GET /me/favorites` → `{ "providerIds": [...] }`; the app resolves ids → providers it already has. ✓
2. **Add to a non-existent provider → 404** (validate existence; no dangling favorites). ✓
