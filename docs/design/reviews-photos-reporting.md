# Review photos end-to-end + « Signaler » (P2b — audit 2.13 / 2.14)

**Status:** Built (PR fix/parity-p2b-reviews-trust) · **Audit:**
[parity-audit-modules-2026-07.md](parity-audit-modules-2026-07.md) module 2 ·
**Contract:** [openapi.yaml](../api/openapi.yaml) — `POST /uploads/sign` gains
`purpose=review`; `POST /appointments/{id}/review` already took `photoUrls`,
`POST /reviews/{id}/report` already existed.

## Goal & scope

Two review-trust gaps, plus a latent one the audit missed:

- **2.13** — web can neither submit nor display review photos on the public
  page. **Digging deeper: NOBODY could submit them against the real backend** —
  `UploadSigningService` only knows `gallery`/`kyc`/`deposit`, and the app's
  upload client signs `purpose=gallery` under the PROVIDER session, so a
  consumer's review-photo attach only ever worked on mocks. Fixing 2.13 for
  real means a backend purpose + an app fix + the web UI.
- **2.14** — `POST /reviews/{id}/report` (consumer-only, idempotent, optional
  `reason`) and the admin moderation queue are live, but neither surface has
  a « Signaler » action.

## Backend — `purpose=review` on `/uploads/sign`

- **Consumer-only** (`user` token), like `deposit`; gate per purpose in the
  route: `deposit`/`review` → `user`, `gallery`/`kyc` → `provider`.
- **Public bucket** (photos render on public review tiles), prefix
  `review/{userId}`, images only, 5 MB, returns `publicUrl` — exactly the
  gallery shape but consumer-scoped.
- Threat model (BACKEND.md §7): new consumer write path to the public bucket —
  mitigated like gallery (server-derived key under the caller's own prefix,
  unguessable object id, pinned content-type + size, 5-min TTL). Review submit
  already caps `photoUrls` at 6 and validates entries.
- Tests: sign `review` as user → 200 with `review/{userId}` key + publicUrl;
  as provider → 403; bad content-type → 400.

## App — real consumer upload + « Signaler »

- `ApiImageUploadService` gains ctor knobs (`purpose`, `refreshPath`,
  session store) — a second DI instance signs `purpose=review` under the
  CONSUMER session (`/auth/refresh`); the provider gallery instance is
  untouched. `ProviderProvider.uploadReviewPhoto` switches to it.
- `ReviewServiceInterface.reportReview(reviewId, {reason})` → mock + API
  impl (consumer session). `ReviewTile` gains an optional `onReport` (hidden
  when null — the pro Avis screen keeps read-only tiles); the salon detail
  wires it: « Signaler » → dialog (optional reason, 500 max) → snackbar
  « Merci. Notre équipe va examiner cet avis. » / error snackbar; signed-out
  → « Connectez-vous pour signaler un avis. »

## Web — photos both ways + « Signaler »

- **Submit:** `ReviewForm` gains the app's photo attach (≤3, like the app's
  sheet): file input → sign (`/api/uploads/sign` now whitelists
  `purpose: 'review' | 'deposit'`, still consumer-session) → direct-to-storage
  POST → thumbnail strip with remove; `photoUrls` ride `submitReview` and the
  BFF forwards them.
- **Display:** public `ReviewList` becomes a light client component — photo
  thumbnails (64px strip, plain `img`; user content, lightbox on tap with a
  fullscreen overlay + close).
- **Report:** « Signaler » under each review → inline optional-reason form →
  `POST /api/reviews/{id}/report` (new BFF). 401 → « Connectez-vous pour
  signaler cet avis » linking `/connexion?returnTo={salon}`; success →
  « Merci. Notre équipe va examiner cet avis. »

## Tests

- Backend: the three sign-route cases + existing suites.
- App: widget test — tile shows « Signaler » only with the callback; dialog
  reports through a mock (analyze 0).
- Web unit: photo-list reducer (add/remove/cap).
- Web e2e: public page shows the stub review's photo & « Signaler »
  (anonymous → the login prompt); signed-in report → merci; ReviewForm photo
  attach → submit with `photoUrls` (stub echoes).
