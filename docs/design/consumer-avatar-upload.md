# Consumer avatar upload — a purpose of its own

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-08-15 |
| **PRD ref / phase** | FR-PROF — profile photo · V1 |
| **ROADMAP entry** | Launch readiness — consumer profile |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails |

Companion to [pro-image-upload-pipeline.md](pro-image-upload-pipeline.md) (the
presign → direct-to-R2 pipeline) and
[account-deletion-erasure.md](account-deletion-erasure.md) (what erasure owes).

## 1. Goal & scope

A signed-in consumer can set a profile photo. The **UI has always existed**; in
API mode it has never worked, for two independent reasons that both had to be
fixed for the feature to exist at all.

**In scope**

| | Defect | Effect |
|---|---|---|
| **A** | `AuthProvider.uploadAvatar` resolves `serviceLocator.imageUploadService` — the instance built with a **provider** session store and the constructor defaults `purpose: 'gallery'`, `refreshPath: '/auth/provider/refresh'` | dead in API mode |
| **B** | `edit_profile_screen._pickAvatar` calls `showMockImagePicker` **unconditionally**, with no `AppConfig.useApiBackend` branch — unlike every other upload surface | dead in API mode |
| **C** | There is no consumer purpose that means "profile photo" | — |
| **D** | `DELETE /me` never erases the avatar object | public object outlives the account |
| **E** | The pro artist photo has defect **B** verbatim (`artist_form_screen.dart`) | dead in API mode |
| **F** | The consumer web BFF *coerces* an unknown `purpose` to `deposit` instead of rejecting it | a trap for the next caller |

**Out of scope:** any web avatar UI (none exists); `PATCH /me` requiring the
avatar key to be under the caller's own prefix (see §9).

## 2. What actually happens today — the severity, stated precisely

The report that opened this work said a consumer avatar upload "signs with a
provider session". **That is not what happens**, and the correction matters
because it changes the severity from a cross-tenant write to a dead feature.

| Mode | Behaviour |
|---|---|
| **Mock** — every `flutter test`, every debug run, every CI APK | `MockImageUploadService` echoes the source; the flow works end to end. **No defect is observable.** |
| **API mode, any real install** | The consumer binary's `myweli_provider_session` is always empty, so `ApiImageUploadService` returns `'Non connecté'` **before any HTTP call**. Avatar upload is 100% dead — and defect **B** would kill it a second time even if **A** were fixed alone. |
| **Both sessions on one device** | Would sign under the salon's prefix — but **unreachable in any shipped build**: consumer and pro are separate applicationIds (`com.myweli.app` / `com.myweli.pro`) with no keychain sharing, and `main.dart` builds `AuthProvider` while `main_pro.dart` builds `ProAuthProvider`. Never both. |

And the server **fails closed** regardless: `POST /uploads/sign` role-gates
`gallery` to `role == 'provider'`, so a consumer token carrying the default
purpose is a hard 403. No cross-role signature can be produced.

**Urgency:** `AppConfig.useApiBackend` is `bool.fromEnvironment('USE_API_BACKEND')`
and no CI build sets it — but the documented store-submission command does. This
is a **launch blocker, not a production incident**. Zero avatar objects exist, so
there is nothing to migrate.

## 3. The decision — a dedicated `avatar` purpose, not a reuse of `review`

The cheap fix is to point `AuthProvider` at the existing consumer instance
(`reviewImageUploadService`: consumer session, `purpose: 'review'`). It needs no
backend change at all. It was rejected.

**The purpose string *is* the storage namespace.** The key is
`pending/{purpose}/{prefixId}/{id}.{ext}` and promotion only strips `pending/`,
so choosing the purpose chooses the prefix that erasure, moderation and any
future lifecycle rule will reason about — permanently.

Filing a profile photo under `review/{userId}/` is wrong in **both** directions
at once:

- **It under-deletes today.** `DELETE /me` erases `review/{userId}/` objects from
  the list `reviews.anonymizeUser` returns. An avatar never enters
  `reviews.photo_urls`, so it would sit in that prefix and still not be erased —
  the namespace collision with none of the benefit.
- **It over-deletes tomorrow.** The documented non-convergence fix in
  [account-deletion-erasure.md](account-deletion-erasure.md) §11 is "sweep
  everything under `review/{userId}/`". That sweep would silently delete profile
  photos. So would any moderation takedown of a reviewer's images.

A field called `reviewImageUploadService` uploading profile photos, and a
`purpose: 'review'` in the logs for a face, are the smaller costs.

The delta is also smaller than it looks: the cheap option still needs the picker
fix, the DI rework and the test repair, and still leaves erasure open as separate
work. The dedicated purpose is that plus ~4 backend lines, one contract line, and
a 3-line erasure close. **Now is the free moment** — zero objects, no users.

## 4. API & contract

`POST /uploads/sign` gains `purpose: 'avatar'`:

| | |
|---|---|
| **Role** | `user` (consumer) — joins `deposit` and `review` in the consumer set |
| **Bucket** | public (the photo renders in-app) |
| **Key** | `pending/avatar/{userId}/{objectId}.{ext}` → `avatar/{userId}/…` once claimed |
| **Content types** | images only (jpeg/png/webp) — the non-KYC allowlist, unchanged |
| **Response** | carries `publicUrl`, like every public-bucket purpose |

It reuses the `review` branch verbatim (`prefixId = accountId`, public bucket);
only the prefix differs, and only because `purpose` is interpolated into the key.

The claim is unchanged: `PATCH /me` already promotes any pending public url from
our own delivery origin, so it accepts `pending/avatar/…` with no change.

**Pre-existing contract drift fixed while here:** `UploadTicket` required
`fields` and pinned `method: [POST]`, describing the presigned-POST policy that
was replaced by a presigned PUT. The service returns `method: 'PUT'` with a
`headers` map. The schema now says what the service does.

## 5. Data model

None. The avatar url lives on `users.avatar_url` as it already did.

## 6. Security & authz

- **Consumer-only.** `avatar` joins `consumerPurposes` in the route, so a
  provider token requesting it is a 403 — symmetric with `gallery`/`kyc` being
  refused to a consumer token.
- **Self-scoped.** `prefixId` is the token's `sub`; the client never chooses the
  path.
- **Erasure (D).** `eraseUser` now captures the user row it already fetches for
  its null check and, after the review/deposit sweeps and **before** the identity
  delete, erases `avatar/{userId}/`. It reuses `_eraseObjects` unchanged, which
  normalises a url to a key and then enforces the own-prefix filter — so a Google
  OAuth `picture` url sitting in `avatarUrl` is skipped rather than fetched, and
  a foreign key planted on the row cannot become a delete primitive. The ordering
  rule the file states — identity last — is preserved.
- **No threat-model row is added.** This introduces no new trust boundary: T13
  (`/uploads/sign`) already covers per-purpose role gating and server-built keys,
  and T59 (erasure) already states the own-prefix rule. Both rows are amended to
  name the new purpose rather than a new row invented.

## 7. UX

`_pickAvatar` gains the `AppConfig.useApiBackend` branch every other upload
surface already has — the real picker in API mode, the mock one otherwise. Copy,
states and the error snackbar are unchanged; the screen simply stops failing.

The same one-line gap in the **pro artist form** is fixed in the same pass. It is
a different screen, but it is the same defect, it is a launch blocker for the
same reason, and fixing one instance of a two-instance bug while documenting the
other would be worse.

## 8. Tests

- **Backend service:** `avatar` → public bucket, `pending/avatar/{userId}/`,
  `publicUrl` present. **Route:** consumer → 200, provider → **403**.
- **The negative test is rewritten.** `purpose: 'avatar'` was the canonical
  *rejected* purpose in `upload_signing_test.dart`; it now uses a genuinely
  invalid string, so the invalid-purpose branch stays covered instead of
  quietly becoming the happy path.
- **Erasure:** the avatar object is presign-DELETEd; a bystander's
  `avatar/{other}/` object is untouched; a Google `picture` url is **skipped**.
- **Mobile behaviour:** the avatar service signs `purpose: 'avatar'`, sends the
  **consumer** token, refreshes at `/auth/refresh` (not `/auth/provider/refresh`),
  and sends no `salonId`.
- **Mobile DI pin:** the `di_push_wiring_test` `isA<>` pattern **cannot** be
  reused — under `flutter test` every slot is a `MockImageUploadService`, so the
  type proves nothing. The pin asserts **instance identity** instead: the avatar
  slot is used and the gallery slot is not. It fails on the old wiring.
- **The test that should have caught this is repaired.**
  `consumer_avatar_test.dart` registered only `serviceLocator.imageUploadService`
  — the very field the bug read — which is precisely why the defect survived.

## 9. Rollout & open questions

Nothing to migrate: zero avatar objects, no real users. Shipping order does not
matter — the app on mocks is unaffected either way.

**Open, out of scope:** `PATCH /me` accepts any pending public url from our
origin, so it does not verify the avatar key is under the *caller's* prefix. The
only defence is the 16-byte unguessable object id. Now that avatars have their
own prefix the check is finally expressible (`pending/avatar/{userId}/`), which
is a reason to do it — but it belongs with the avatar-promotion code rather than
here. Filed separately.

## 10. Not in this change

- Any web avatar upload UI. The web BFF's purpose allowlist is corrected so it
  **rejects** an unknown purpose instead of silently coercing it to `deposit`,
  but no web feature is added.
- The `PATCH /me` prefix check (§9).
