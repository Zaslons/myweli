# Pro KYC (provider verification) — design spec

| | |
|---|---|
| **Status** | Built (B1 backend #76 · B2 app uploader) |
| **Owner** | Sadreddine |
| **Last updated** | 2026-06-26 |
| **PRD ref / phase** | Pro KYC onboarding · V1 (PRD §8.2) |
| **ROADMAP entry** | Phase 3 — Backend build + integration (added on build) |
| **Skills checked** | myweli-backend-guardrails ✓ + myweli-dev-guardrails (KYC screen is user-facing) |

## 1. Goal & scope

Put **provider KYC** on the real backend — a salon uploads its identity documents to **private** storage and reads its verification status — replacing `MockProKycService`. The **provider side, end-to-end**; the **verify (approve/reject)** half is a separate admin slice (no admin surface yet — signed off).

**In scope:**
- Backend: `GET`/`POST /me/kyc` (provider-authenticated, self-scoped by the token). KYC documents upload to a **private** object-storage bucket via a new `purpose=kyc` on `POST /uploads/sign` (key namespaced to the account, returns the object **key**, no public URL). Submit stores the doc metadata + keys on the provider account and sets `verificationStatus = pending`. New `kyc_docs` storage (migration `0008`); `KycService` over `ProviderAuthRepository`.
- App: `KycDocument` gains a storage **`key`**; `ApiProKycService` (provider session) uploads each doc to the private bucket, submits, reads status; the KYC screen picks + uploads real files.
- Contract + threat model (new T15) + tests.

**Out of scope (explicit, agreed):** **approve/reject** + the **admin** role/accounts/endpoints (separate admin slice); **viewing** an uploaded doc (the screen shows submitted-state by type/filename, never re-displays the image — so no signed-GET needed yet; keys are stored for the future admin/audit slice).

**Accepted doc types:** images **and PDF** (`image/jpeg|png|webp`, `application/pdf`).

**Build:** 2 PRs — **B1** backend (private upload purpose + KYC submit/status + storage), **B2** app (model key + uploader + screen).

## 2. UX & flows
`pro_kyc_screen` already lists the required docs per business type ("ID card", "selfie", …), each showing **"À fournir"** or **"Fourni · {fileName}"**, with submit gated on all required docs present. This slice makes each "provide" actually **upload the photo to private storage** and the submit/status hit the backend. The screen never displays the stored image (privacy). French copy + the four states already exist; the pro app gets the UX pass (camera/permission, slow-network upload, denied-permission).

## 3. API & contract
- **`POST /uploads/sign`** — gains `purpose: kyc`. Provider-only. Returns a presigned POST to the **private KYC bucket** with key `kyc/{accountId}/{uuid}.{ext}` (server-built from the token → a salon can only write under its own KYC prefix), the content-type allowlist (image/jpeg|png|webp), and the **`key`** — **no `publicUrl`** (KYC objects are never public).
- **`GET /me/kyc`** — provider token → `KycStatus` `{ status, documents: [ { type, fileName, key, submittedAt } ], rejectionReason }`. Self-scoped (token `sub` = provider account).
- **`POST /me/kyc`** — provider token, body `{ documents: [ { type, fileName, key } ] }` → validate (types in the enum; each `key` must start with this account's `kyc/{accountId}/` prefix); store on the account + set `verificationStatus = pending` (resubmit resets pending + clears `rejectionReason`) → `KycStatus`.

Errors: 400 `invalid_input` (bad type / foreign or malformed key / missing required docs), 401, 403 (non-provider), 405.

## 4. Data model
The provider account already persists `verification_status` + `rejection_reason` (`provider_users`). Add the submitted docs:
- **Migration `0008`:** `ALTER TABLE provider_users ADD COLUMN kyc_docs jsonb NOT NULL DEFAULT '[]'`.
- In-memory `ProviderAccount` gains a `kycDocs` field (currently hardcoded `[]` in `toJson`).
- `KycDocument` (app model) gains **`key`** (the private object key). No public URL — the bytes live in the private bucket; only the key + metadata are in the DB.

## 5. Architecture & patterns
- **Storage:** KYC uses a **separate private bucket** (`R2_KYC_BUCKET`) — distinct from the public gallery bucket, since R2 public-read is per-bucket and ID docs must never be publicly reachable. `R2StorageService` learns to presign into the KYC bucket for `purpose=kyc`; `FakeStorageService` is unchanged (dev). `UploadSigningService` maps `purpose` → (bucket, public?): `gallery` → public bucket + `publicUrl`; `kyc` → private bucket + `key` only, prefix `kyc/{accountId}/`.
- **`KycService`** (business logic over `ProviderAuthRepository`): `status(accountId)` reads status/docs/reason; `submit(accountId, documents)` validates (enum types; each key under `kyc/{accountId}/`), writes `kycDocs` + sets `pending`, clears `rejectionReason`. No `dart_frog`/SQL.
- **`ProviderAuthRepository`** gains `getKyc(accountId)` / `updateKyc(accountId, {docs, status})` (in-memory + Postgres `UPDATE provider_users SET kyc_docs=…, verification_status=…, rejection_reason=NULL`).
- **Routes:** `routes/me/kyc.dart` (GET/POST, role=provider). `/uploads/sign` extended for the `kyc` purpose.
- **App:** `ApiProKycService` — for each doc: `POST /uploads/sign {contentType, purpose:kyc}` → multipart-POST the bytes to the private bucket → keep the returned **key** → build `KycDocument{type, fileName, key}`; then `POST /me/kyc {documents}`. `getKycStatus` → `GET /me/kyc`. Provider session + silent refresh. The screen uses the real image picker.

## 6. Security & authz (this is sensitive PII)
- `POST /uploads/sign?purpose=kyc` + `/me/kyc` are **provider-only**, **self-scoped** (key prefix + account are the token's `sub`; a salon can't write or read another's KYC). The submit re-checks each key is under the caller's `kyc/{accountId}/` prefix (no attaching a foreign/arbitrary key).
- **Private storage:** KYC bucket is **not public** (no bound public domain); keys are uuid-named; bytes never pass through the API; no public URL is ever issued. Viewing (future) will be a short-TTL **signed GET**, owner/admin only.
- **Server authority** on `verificationStatus` (always `pending` on submit; only the future admin flips it) and `rejectionReason` (read-only to the provider).
- **Logging:** never log keys/filenames as PII beyond a redacted request-id.
- **Threat model:** new **T15** (KYC PII) — provider-only + self-scoped submit/read; private bucket + unguessable keys + no public URL + no bytes through the API; status/verification server-owned; (future) signed-GET owner/admin-only viewing.

## 7. Performance
- `/uploads/sign` is CPU-only (HMAC). Submit/status: one `provider_users` read/update. Bounded (a handful of docs). No N+1.

## 8. Testing plan
- **Storage/signing:** `purpose=kyc` returns a private-bucket presign + a `kyc/{accountId}/…` key + **no publicUrl**; bad content-type → 400; non-provider → 403.
- **KycService:** submit stores docs + sets pending + clears rejectionReason; rejects a foreign key (not under the account prefix) → invalid_input; bad type → invalid_input; status reads back.
- **Handler:** `GET /me/kyc` → 200; `POST` → 200 pending; non-provider → 403; no token → 401; bad verb → 405.
- **Repo (DB-gated):** `updateKyc`/`getKyc` persist `kyc_docs` + status; survive re-read.
- **App:** `ApiProKycService` uploads (sign → private POST → key), submits `{documents}`, reads status; 401 → provider refresh; foreign-key/forbidden surfaced.

## 9. Definition of done
- [ ] `dart format` clean · `dart analyze` 0 (backend + mobile) · tests green (incl. DB-gated).
- [ ] OpenAPI: `/me/kyc` (GET/POST) + `KycStatus`/`KycDocument`; `/uploads/sign` `kyc` purpose (key, no publicUrl).
- [ ] Threat model T15; ROADMAP entry; spec cross-linked; status → Built.
- [ ] `R2_KYC_BUCKET` documented in `.env.example` (private bucket); **no secrets committed**.
- [ ] Feature-branch + PRs; CI green; no Claude attribution.

## 10. Decisions (signed off)
1. **Provider side end-to-end now; verify (approve/reject) + admin role/accounts are a separate slice.** ✓
2. **Real private storage** — KYC docs upload to a **private** bucket (`R2_KYC_BUCKET`), `KycDocument` gains a storage `key`; no public URL ever. ✓
3. **No in-app viewing** of stored docs now (screen shows submitted-state by type/filename); keys stored for the future admin/audit + signed-GET viewing. ✓
4. **Two PRs** — B1 backend → B2 app (like the upload pipeline). ✓
5. **Images + PDF** accepted (`image/jpeg|png|webp`, `application/pdf`). ✓
