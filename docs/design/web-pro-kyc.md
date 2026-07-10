# Web pro KYC — « Vérification » (documents upload) on the pro dashboard

| | |
|---|---|
| **Module** | `access` / onboarding — web parity slice of the pro KYC flow |
| **Status** | **Built** (2026-07-10) — one PR: page + profil entry + BFF + tests |
| **Trigger** | Parity follow-up flagged on the ROADMAP: the pro app has « Vérification » (`ProKycScreen`, docs/design/pro-kyc.md); the web pro dashboard cannot upload KYC at all — a salon that registered on the web (web-pro-registration.md) is stuck |
| **Scope** | Web only, **no backend change** — `GET/POST /me/kyc` + `POST /uploads/sign?purpose=kyc` (private bucket, `kyc/{accountId}/` prefix) already exist and the account JSON already carries `businessType`/`verificationStatus` |
| **Out of scope** | Admin approve/reject (admin console, built) · deposit activation logic (unchanged — acomptes stay gated on `verified`) |
| **Cross-refs** | `pro_kyc_screen.dart` + `kyc_document.dart` (the reference) · [pro-kyc.md](pro-kyc.md) (the app/backend slice) · [web-pro-registration.md](web-pro-registration.md) (why web-born salons need this) |

## 1. The app flow being mirrored (read 2026-07-10)

`ProKycScreen`: a **status banner** (pending « Vérification en attente /
Soumettez vos documents… » · verified « Compte vérifié / Vous pouvez activer
les acomptes. » · rejected « Vérification refusée » + `rejectionReason`) over
**four document tiles** — Pièce d'identité (CNI / passeport) · Photo du
visage · Registre de commerce (RCCM) · Justificatif d'adresse — each showing
« À fournir » / « Fourni · {fileName} » with Ajouter/Modifier + Retirer.
**Required rules** (`isKycDocumentRequired`): ID + selfie always; RCCM unless
`businessType == other` (freelancers à domicile); address proof always
optional. Upload happens **at add time** (sign → private storage → keep
`{type, fileName, key}` locally); « Soumettre pour vérification » POSTs the
full document list → status `pending`, prior rejection cleared. Verified =
read-only. Accepted files: jpg/png/webp/pdf. Privacy line: « Les acomptes
sont activés une fois votre compte vérifié. Vos documents sont chiffrés et
confidentiels. »

## 2. UX — `/pro/verification` (web-adapted)

- **Entry point** mirrors the app: the **Profil** page's section links gain
  « Vérification » with the status as the right-side hint (À vérifier ⇢ from
  `account.verificationStatus`, already in the loaded profile — no extra
  fetch).
- The page: status banner → four tiles (label + « (optionnel) » when not
  required for this `businessType`) → privacy line → « Soumettre pour
  vérification » (disabled until the required docs are present, with the
  app's helper hint) → success toast « Documents soumis pour vérification ».
- Tiles: hidden file input per tile (`accept` = jpeg/png/webp/pdf); add =
  sign → direct-to-storage POST → local `{type, fileName, key}`; Retirer
  drops it locally; Modifier replaces. Existing documents from `GET /me/kyc`
  prefill the tiles (submit is a full replace, the app semantics).
- Verified → banner only, tiles read-only, no submit.
- Four states: loading text · error + « Réessayer » · the form (its own
  empty state is « À fournir » on every tile) · success.

## 3. Layering & security

- **BFF `GET|POST /api/pro/kyc`** → `/me/kyc` (self-scoped server-side —
  the token's account, never a client id; T-model unchanged).
- **`/api/pro/uploads/sign` gains an allowlisted `purpose`** —
  `gallery` (default) | `kyc` only; `deposit` stays consumer-only on the
  consumer BFF. The API derives the private key prefix from the token.
- Document bytes go browser → private bucket (never through our API);
  the page keeps only `{fileName, key}` — no PII in logs or state beyond
  the file name (PRD NFR-SEC-002 posture preserved).
- Pure helpers in `lib/pro/kyc.ts` (unit-tested): the doc-type catalogue +
  labels, `isKycDocRequired(type, businessType)` (unknown/missing
  businessType → conservative: RCCM required), `hasRequiredDocs`,
  `canSubmitKyc`.
- `lib/pro/upload.ts` gains `uploadKycDocument(file)` (sign purpose=kyc →
  storage POST → `{key, fileName}`), mirroring `uploadGalleryImage`.

## 4. Tests

- Unit: required-doc rules per businessType (incl. missing → conservative),
  submit gate, upload client (mocked fetch: happy + failed sign).
- e2e: login → Profil « Vérification » → the four tiles; add ID + selfie
  (setInputFiles → stub storage POST) with `businessType: other` in the stub
  (RCCM shows « (optionnel) ») → submit → « Documents soumis pour
  vérification »; stateful stub flips its stored docs.

## 5. Rollout

One PR (`feat/web-pro-kyc`): page + profil entry + BFF + helpers + stub +
tests + this spec; README index + ROADMAP refreshed (parity list → consumer
web discovery map only). Gates: tsc/lint/build · unit · e2e.
