# Pro gallery photos — design spec

| | |
|---|---|
| **Status** | Built (PR A of 2: the URL-list foundation) |
| **Companion** | [pro-image-upload-pipeline.md](pro-image-upload-pipeline.md) (PR B — Cloudflare R2 bytes→URL) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro profile / portfolio · V1 |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ (myweli-dev-guardrails for the app swap) |

## 1. Goal & scope

Put the salon **gallery** (its portfolio photo list) on the real backend — load + persist the **ordered list of image URLs** — replacing `ApiProService.getGalleryPhotos` / `updateGalleryPhotos`'s delegation to `MockProService`.

**Scope boundary (important):** the app already splits two concerns —
- the **bytes → hosted URL** upload pipeline (`ImageUploadServiceInterface`, still mock) — compress/scan/upload to object storage/CDN, returns a server-authoritative URL. This carries the **storage-provider decision** and is its **own future slice**; and
- the **gallery URL list** the salon curates (`ProServiceInterface.getGalleryPhotos` / `updateGalleryPhotos`) — *this slice*.

`ProGalleryProvider.addPhoto` already calls `ImageUploadService.uploadImage(...)` → URL, then `updateGalleryPhotos(providerId, [...photos, url])`. So this slice makes the **persistence** real; the upload stays on the mock pipeline until the storage slice lands. No bytes ever pass through the API (BACKEND.md §4).

**In scope:**
- Backend: `GET /providers/{id}/gallery` + `PUT /providers/{id}/gallery` (provider-authenticated, ownership-scoped) over the provider's `imageUrls` (stored in the `providers.data` jsonb). New `ProvidersRepository.updateGallery` (in-memory + Postgres) + `ProviderCatalogService.gallery` / `updateGallery`.
- App: the two `ApiProService` gallery methods → the endpoints.
- Contract + threat model + tests (incl. DB-gated).

**Out of scope:** the image **upload pipeline** / storage provider (separate slice); reordering UX beyond the list the app sends; per-photo metadata.

**Build:** one PR (backend GET/PUT + repo method + app swap).

## 2. UX & flows
No UX change — `pro_photos_screen` + `ProGalleryProvider` already drive load / add / remove behind the interfaces (with upload progress + all four states). This slice only makes the load/save calls hit the backend.

## 3. API & contract
Both **provider** token + **ownership** (`account.providerId == {id}` → else 403):
- **`GET /providers/{id}/gallery`** → `{ "imageUrls": [ "<url>", … ] }`.
- **`PUT /providers/{id}/gallery`** — body `{ "imageUrls": [ … ] }` (the full ordered list, replace-wholesale, mirroring availability) → `{ "imageUrls": [ … ] }`.

Errors: 400 `invalid_body` / `invalid_input` (not a string list / over cap / empty or over-long entry), 401, 403, 404 `not_found`, 405.

## 4. Data model
`imageUrls` already lives in each provider's **`providers.data` jsonb** (services + availability were normalized out; the rest of the DTO stays in `data`). No migration — `updateGallery` read-modify-writes the `data` blob (the established pattern, since `data` is stored as a JSON-string scalar so jsonb operators don't apply), inside a `runTx` for atomicity.

## 5. Architecture & patterns
- **`ProvidersRepository.updateGallery(providerId, List<String> imageUrls)`** → returns the stored list, or null if the provider doesn't exist.
  - *InMemory:* set `provider['imageUrls']`, return it.
  - *Postgres:* `runTx` → `SELECT data … FOR UPDATE` → decode → `data['imageUrls'] = list` → `UPDATE providers SET data = @data:jsonb` (mirrors `backfillCatalogueIfNeeded`).
- **`ProviderCatalogService.gallery` / `updateGallery`** (gallery is salon catalogue management, alongside services/availability): ownership check → read `byId` / validate + delegate. Returns `CatalogResult`.
- **Route** `routes/providers/[id]/gallery.dart` (thin): principal → `role==provider` → `GET`→`gallery`, `PUT`→parse+`updateGallery`, else 405 → shape. Mirrors `services.dart` / `availability.dart`.
- DI: no new singleton (reuses `ProviderCatalogService`).
- **App:** `getGalleryPhotos` → `GET …/gallery` → `data['imageUrls']`; `updateGalleryPhotos` → `PUT …/gallery` `{imageUrls}` → `data['imageUrls']`. Provider session + silent refresh.

## 6. Validation (server-authoritative)
- Body must contain `imageUrls` = a **list of strings** (else 400 `invalid_input`).
- **Count cap:** ≤ **20** photos (no unbounded list) → else 400 `invalid_input`.
- Each entry: non-empty after trim, ≤ **2048** chars → else 400.
- Replace-wholesale (the app always sends the full intended list) — server stores exactly what's sent (after validation); server is the authority on persistence, the salon on ordering/selection.

> **Future tightening (noted, not this slice):** once the upload pipeline lands, the gallery should only accept **URLs the server issued** (our CDN origin) — rejecting arbitrary external URLs (anti-SSRF / tracking-pixel / hotlink). Today the seed uses `asset:…` placeholders and there's no issuer yet, so origin-allowlisting waits for the storage slice. ← see open question.

## 7. Security & authz
- Deny by default; provider token + ownership (cross-salon / unlinked → 403). A salon edits only its own gallery.
- All input validated at the boundary (§6). No bytes through the API. Nothing sensitive logged (URLs are public profile data).
- **Threat model:** extend **T12** (catalogue/availability mgmt) to include the gallery list (same ownership + boundary validation), and record the future CDN-origin tightening.

## 8. Performance
- GET: one `byId` (already used for the public profile). PUT: one `byId`-equivalent read-modify-write of `data` in a single tx. Bounded at ≤20 small strings. No N+1, well within budgets. (Bytes/CDN are out of band.)

## 9. Testing plan
- **Service (unit):** `gallery` returns the list (ownership ok); `updateGallery` replaces it; over-cap / non-string / empty / over-long → invalid_input; cross-salon + unlinked → forbidden; missing provider → not_found.
- **Handler:** `GET` → 200 `{imageUrls}`; `PUT` valid → 200 (persisted, re-GET reflects it); bad body → 400; no token → 401; cross-salon → 403; other verb → 405.
- **Contract:** responses match the `{imageUrls}` shape.
- **Repo (DB-gated `@Tags(['postgres'])`):** `updateGallery` persists into `data` and survives a re-read; unknown provider → null.
- **App:** `getGalleryPhotos` GETs + parses; `updateGalleryPhotos` PUTs `{imageUrls}` + parses; 401 → provider silent refresh; forbidden → error.

## 10. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green (incl. DB-gated).
- [ ] OpenAPI: `GET`/`PUT /providers/{id}/gallery` + the `{imageUrls}` shape.
- [ ] Threat model T12 note; ROADMAP entry; spec cross-linked from the route/service/repo + `ApiProService`; status → Built.
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 11. Decisions (signed off)
1. **Full pipeline, sequenced into 2 PRs.** This spec is **PR A** — the gallery **URL-list** backend (GET/PUT) — independent of any storage provider and shippable now. **PR B** = the **bytes→URL upload pipeline** on **Cloudflare R2** (S3-compatible), specced separately in [pro-image-upload-pipeline.md](pro-image-upload-pipeline.md). ✓
2. **Photo cap = 20** per salon. ✓
3. **URL origin validation** — PR A validates **shape / count / length** only (no URL issuer exists yet; seed uses `asset:` placeholders). PR B introduces the R2/CDN origin and **tightens the gallery `PUT` to allowlist server-issued URLs** (anti-SSRF / hotlink / tracking-pixel) — the threat-model follow-up lands with PR B. ✓
