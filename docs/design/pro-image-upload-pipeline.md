# Image upload pipeline (Cloudflare R2) — design spec

| | |
|---|---|
| **Status** | Built (B1 backend #70 · B2 app picker+uploader) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro profile / portfolio · V1 |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ + myweli-dev-guardrails (app uploader is user-facing) |
| **Companion** | [pro-gallery.md](pro-gallery.md) (PR A — the gallery URL list, shipped #69) |

## 1. Goal & scope

Make the **bytes → hosted URL** half real: a salon picks a photo, the app compresses it and uploads it **directly to Cloudflare R2** (never through our API — BACKEND.md §4), and gets back a CDN URL it then saves to the gallery (PR A). This replaces the mock `ImageUploadService` + the mock image picker.

**Decisions carried in (signed off):** Cloudflare **R2** (S3-compatible — same client works for AWS S3 / Supabase); **client-side compression**, R2+CDN serves the single optimized file as-is (no on-the-fly variants); **moderation deferred** (validate content-type + size only; trust the authenticated salon for its own portfolio).

**In scope:**
- Backend: a `StorageService` interface (Fake for dev/CI + tests; **R2** S3-compatible presigner for prod), `POST /uploads/sign` (provider-auth) issuing a short-lived **presigned upload** + the public URL, env config, and the **gallery origin-allowlist** tightening (T12 follow-up).
- App: real `ApiImageUploadService` (compress → upload to the presigned URL → progress) + a real `image_picker` sheet replacing the mock; DI selection behind `AppConfig.useApiBackend`.
- Contract + threat model + tests.

**Out of scope:** content/NSFW moderation + virus scan (later hardening slice); on-the-fly image variants (Cloudflare Images); non-gallery uploads (KYC docs, avatars) — the endpoint is generalizable but only gallery is wired now.

**Delivery — 2 PRs:**
- **B1 (backend):** `StorageService` + R2 presigner + `POST /uploads/sign` + env + gallery origin-allowlist + tests (Fake storage — no live creds needed). Mergeable alone.
- **B2 (app):** `image_picker` + `flutter_image_compress` + real `ApiImageUploadService` + real picker sheet + DI. Mergeable after B1.

## 2. UX & flows
`pro_photos_screen` → tap **add** → a real picker sheet (Camera / Gallery) → the app compresses, shows the existing upload-progress UI (`ProGalleryProvider.isUploading`/`uploadProgress`), then the photo appears. All four states already exist; only the **picker** (mock → real) and the **uploader** (mock → R2) change. The pro app gets the user-facing UX treatment (camera/gallery permissions, denied-permission state, oversized-image + slow-network handling, French copy).

## 3. API & contract
**`POST /uploads/sign`** — **provider** token required (role=provider **and** a linked `providerId`; unlinked → 403). Body:
```
{ "contentType": "image/jpeg", "purpose": "gallery" }
```
- `contentType` ∈ { `image/jpeg`, `image/png`, `image/webp` } (else 400 `invalid_input`).
- `purpose` ∈ { `gallery` } for now (else 400) — namespaces the key.

Response **200** — a **presigned POST** (so the size cap is enforced at R2):
```
{ "method": "POST",
  "uploadUrl": "<bucket endpoint>",
  "fields": { "key": "gallery/{providerId}/{uuid}.jpg",
              "Content-Type": "image/jpeg",
              "bucket": "...", "X-Amz-Algorithm": "AWS4-HMAC-SHA256",
              "X-Amz-Credential": "...", "X-Amz-Date": "...",
              "Policy": "<base64 policy>", "X-Amz-Signature": "..." },
  "publicUrl": "<https://{R2_PUBLIC_BASE_URL}/{key}>",
  "maxBytes": 5242880,
  "expiresInSeconds": 300 }
```
The client sends a **multipart/form-data POST** to `uploadUrl` with every `fields` entry followed by the `file` (last), then sends `publicUrl` to `PUT /providers/{id}/gallery` (PR A). The signed **policy** pins the exact `key`, the `Content-Type`, and a **`content-length-range`** (0..`maxBytes`) — R2 rejects an oversized or mistyped upload at the storage boundary.
Errors: 400 `invalid_input`/`invalid_body`, 401, 403, 405, 503 `storage_unconfigured` (R2 env missing in a non-dev environment).

## 4. Data model
None. R2 is the object store; the gallery URL list (PR A) is the only DB state. Object key: `gallery/{providerId}/{uuid}.{ext}` — **server-built from the token's `providerId`**, so a salon can only ever write under its own prefix.

## 5. Architecture & patterns
- **`StorageService`** (interface, no dart_frog/SQL):
  - `PresignedPost presignPost({required String key, required String contentType, required int maxBytes, Duration ttl})` → `{url, fields}` (the multipart POST target + signed form fields).
  - `String publicUrl(String key)`.
  - **`FakeStorageService`** — deterministic, no network (`url=https://fake-storage.local/{bucket}`, `publicUrl=https://fake-storage.local/{key}`, fake fields); used in dev/CI/tests when R2 isn't configured.
  - **`R2StorageService`** — S3-compatible **SigV4 presigned POST** (region `auto`, service `s3`): a base64 **policy** (expiration + conditions: exact `key`, `Content-Type`, `content-length-range 0..maxBytes`, bucket, the `x-amz-*` fields) signed with the SigV4 key-derivation chain, built in-house with `crypto` HMAC-SHA256 (no heavy AWS SDK → lean + OSV-clean). Config from env.
  - **Selection** mirrors the repo/`DATABASE_URL` pattern: R2 env present → `R2StorageService`, else `FakeStorageService`.
- **`UploadSigningService`** (business logic): validate `contentType`/`purpose`, build the ownership-scoped key, call `StorageService`. Ownership via the provider account's `providerId` (like the catalogue services).
- **Route** `routes/uploads/sign.dart` (thin): principal → `role==provider` → parse/validate → delegate → shape. `POST` only.
- **Gallery tightening (B1):** `ProviderCatalogService.updateGallery` gains an **origin allowlist** — when `R2_PUBLIC_BASE_URL` is configured, every gallery URL must start with it (reject external/SSRF/hotlink → `invalid_input`); when unset (dev/Fake), also allow the fake origin + `asset:` seed placeholders.
- **App (B2):** `ApiImageUploadService implements ImageUploadServiceInterface`: compress (`flutter_image_compress`, longest edge ~1600px, quality ~80) → `POST /uploads/sign` (provider `RefreshingHttpClient`) → `http.MultipartRequest` POST to `uploadUrl` with `fields` + the `file` (last) and progress → return `publicUrl`. Real picker sheet via `image_picker`. DI selects it under `useApiBackend`.

## 6. Security & authz
- `POST /uploads/sign` deny-by-default; **provider token + linked providerId** (unlinked → 403). The key is **server-built from the token** — the client cannot choose the provider prefix or the object path (no path traversal / cross-salon writes).
- **Server is the authority** on the key, content-type allowlist, and TTL. Presigned URL is **single-purpose** (one `PUT`, one content-type), short-lived (~5 min).
- **Size cap** — enforced **server-side at R2** via the presigned-POST `content-length-range` condition (0..`maxBytes`); an oversized upload is rejected at the storage boundary, not merely trusted from the client.
- **Secrets:** `R2_*` via env only; documented in `.env.example`; never logged (redact). gitleaks stays green.
- **Public read:** delivery via R2 bound to a Cloudflare domain (`R2_PUBLIC_BASE_URL`); the bucket isn't listable; keys are uuid-named (unguessable).
- **Threat model:** new **T13** (object upload) — presigned, ownership-scoped key, content-type allowlist, short TTL, no bytes through the API; size-cap + moderation noted as follow-ups. Completes the **T12** gallery origin-allowlist.

## 7. Performance
- `POST /uploads/sign` is pure CPU (HMAC) — sub-ms, no I/O. Bytes go **client → R2 edge directly** (off our API; R2 has zero egress + CDN). Client compression keeps payloads small on bad networks. No N+1.

## 8. Testing plan
- **Backend:** `FakeStorageService` unit; `R2StorageService` SigV4 presign unit (deterministic given fixed key/secret/clock — assert URL host/path/query `X-Amz-*` structure; validate against a known SigV4 vector); `UploadSigningService` (content-type allowlist, key namespacing by providerId, unlinked → forbidden); `POST /uploads/sign` handler (200 via Fake, 400 bad content-type, 401, 403, 405); gallery origin-allowlist (in-origin ok, external → invalid_input, asset/fake allowed when unconfigured).
- **App:** `ApiImageUploadService` (mock `http`: POSTs `/uploads/sign`, PUTs to the returned URL, returns `publicUrl`; sign 401 → provider refresh; sign/put failure → error). Compression + picker are thin platform wrappers behind the interface (smoke-tested, not unit-pinned).
- **Contract:** `/uploads/sign` response matches OpenAPI.

## 9. Definition of done (per PR)
- [ ] `dart format` clean · `dart analyze` 0 · tests green (incl. DB-gated where relevant).
- [ ] OpenAPI: `/uploads/sign` + the response schema; gallery origin rule noted.
- [ ] Threat model T13 + T12 update; ROADMAP entry; spec cross-linked; status → Built.
- [ ] **No secrets**; `R2_*` documented in `.env.example`; OSV clean (any new dep justified).
- [ ] Feature-branch + PR; CI green; no Claude attribution.

## 10. What you provision (not code)
To go live (after B1+B2 merge): create the R2 bucket, an API token (access key/secret), bind a public domain for delivery, and set `R2_ACCOUNT_ID` (or `R2_ENDPOINT`), `R2_BUCKET`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_PUBLIC_BASE_URL` in the prod secret manager. Until then the app runs on the Fake storage / mocks. I never commit credentials.

## 11. Decisions (signed off)
1. **Presigned POST + `content-length-range`** — hard server-side size cap at R2 (not a client-trusted limit). The app uploads via multipart POST. ✓
2. **Delivery = 2 PRs** — B1 (backend signing endpoint + StorageService + gallery origin rule, testable on Fake storage) then B2 (app picker + uploader). ✓
3. **R2 endpoint config** — accept `R2_ACCOUNT_ID` (derive `https://{account}.r2.cloudflarestorage.com`) **or** an explicit `R2_ENDPOINT` (endpoint wins if set, so AWS S3 / Supabase / MinIO drop in). ✓
4. **`/uploads/sign` stays gallery-only** now (`purpose=gallery`) but is built generic for later reuse (KYC docs / avatars). ✓
5. Carried in: **R2** (S3-compatible), **client-side compression** + serve-as-is, **moderation deferred**. ✓
