# Pro staff (artists) management — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro staff management · V1 (PRD §8.2 "staff") |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ (myweli-dev-guardrails for the app swap) |

## 1. Goal & scope

Put salon **staff (artists)** management on the real backend — list / add / edit / remove the salon's team — replacing `MockProArtistService`. Mirrors the **services** CRUD exactly (same ownership, same `provider.data` storage), so it's a low-risk slice.

**In scope:**
- Backend: `GET`/`POST /providers/{id}/artists` + `PATCH`/`DELETE /providers/{id}/artists/{artistId}` (provider-authenticated, ownership-scoped). New `ProvidersRepository.addArtist`/`updateArtist`/`deleteArtist` (in-memory + Postgres, read-modify-write `data.artists`) + artist methods on `ProviderCatalogService`.
- App: `ApiProArtistService` (provider session + silent refresh) selected under `useApiBackend`; the `artistId`-only edits resolve the salon from the session (like the catalogue).
- Contract + threat model + tests (incl. DB-gated).

**Out of scope:** per-staff availability *in the slot engine* (the artist's `workingHours` round-trips + is stored, but booking still uses salon hours — per-staff slot computation is a later concern); staff invites/accounts (one provider account today).

**Build:** one PR.

## 2. UX & flows
No UX change — `artist_list_screen` + `artist_form_screen` already drive list/add/edit/remove behind `ProArtistServiceInterface`. Artists also surface publicly via the provider `GET` (already embeds `artists`).

## 3. API & contract
All require a **provider** token + **ownership** (`account.providerId == {id}` → else 403):
- **`GET /providers/{id}/artists`** → `{ items: [Artist], total }`.
- **`POST /providers/{id}/artists`** body `{ name, specialization?, imageUrl?, workingHours? }` → **201** the created `Artist`.
- **`PATCH /providers/{id}/artists/{artistId}`** (partial) → 200 the updated `Artist`.
- **`DELETE /providers/{id}/artists/{artistId}`** → **204**.

Errors: 400 `invalid_input` (empty name / bad workingHours), 401, 403, 404 `not_found`, 405.

## 4. Data model
None. Artists already live in each provider's **`providers.data.artists`** list. New repo methods read-modify-write that list (the established `updateGallery`/`updateRatings` pattern). No migration.

## 5. Architecture & patterns
- **`ProvidersRepository`**: `addArtist(providerId, artist) → Map?`, `updateArtist(providerId, artistId, changes) → Map?`, `deleteArtist(providerId, artistId) → bool`. InMemory mutates `data.artists`; Postgres `runTx` read-modify-writes `data`.
- **`ProviderCatalogService`** (artists are salon catalogue mgmt, alongside services/availability/gallery/deposit): ownership → validate → delegate. **Server-owned:** `id`, `providerId`, and **`rating`/`reviewCount`** (these come from reviews — created `null`, recomputed by the reviews slice; never client-settable). `name` required non-empty; `workingHours` stored as sent (`{weekday: [TimeSlot]}` JSON).
- **Routes** mirror `services/`: `routes/providers/[id]/artists/index.dart` (GET/POST) + `[artistId].dart` (PATCH/DELETE).
- **App:** `ApiProArtistService` — `getArtists` → GET; `createArtist(providerId, data)` → POST; `updateArtist(artistId, data)` / `deleteArtist(artistId)` → resolve `providerId` from the persisted provider session → PATCH/DELETE. JSON-normalizes `data.workingHours` (int keys → strings, `TimeSlot` → json) like `Artist.toJson`. DI selects it under `useApiBackend`.

## 6. Validation & authority
- `name`: required, non-empty (trimmed) → else `invalid_input`.
- `specialization`/`imageUrl`: optional strings.
- `workingHours`: optional `{ "<0..6>": [ {start,end,...} ] }`; stored as-is (booking doesn't consume it yet).
- **Ignored if sent:** `rating`, `reviewCount`, `id`, `providerId` — server-owned.

## 7. Security & authz
- Deny by default; provider token + ownership (cross-salon / unlinked → 403). A salon edits only its own staff.
- **Threat model:** covered by **T12** (provider catalogue mgmt) — extend the surface list to include `/artists` (same ownership + boundary validation; rating/reviewCount server-owned).

## 8. Performance
- GET: one `byId`. Write: one atomic read-modify-write of `data`. Bounded (a salon's team). No N+1.

## 9. Testing plan
- **Service (unit):** create sets id/providerId, ignores client rating/reviewCount; list; update merges editable fields; delete; empty name → invalid_input; cross-salon + unlinked → forbidden; unknown artist → not_found.
- **Handler:** `POST` → 201; `GET` → 200 `{items,total}`; `PATCH` unknown → 404; `DELETE` → 204; cross-salon → 403; no token → 401; bad verb → 405.
- **Repo (DB-gated):** add/update/delete persist into `data.artists` and survive a re-read; unknown provider → null/false.
- **App:** `ApiProArtistService` GET/POST/PATCH/DELETE hit the right paths (artistId-only via the session); `workingHours` serialized; 401 → provider silent refresh.

## 10. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green (incl. DB-gated).
- [ ] OpenAPI: the artist paths + `Artist` schema; rating/reviewCount documented as read-only.
- [ ] Threat model T12 note; ROADMAP entry; spec cross-linked; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions
- Mirrors the **services** CRUD (ownership, `provider.data` storage, route shape) — no new patterns. `rating`/`reviewCount` are **server-owned** (from reviews). Per-staff `workingHours` **round-trips** but doesn't yet change slot computation. No open questions.
