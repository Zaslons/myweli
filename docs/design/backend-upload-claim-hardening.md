# Upload claim hardening — the four surfaces `pending/` never protected

| | |
|---|---|
| **Status** | Built (PR A: deposit · PR B: gallery + KYC) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-08-15 |
| **PRD ref / phase** | NFR-SEC-002 · launch readiness |
| **ROADMAP entry** | Launch readiness — backend hardening |
| **Skills checked** | myweli-backend-guardrails |

Companion to [backend-upload-orphans.md](backend-upload-orphans.md) (why `pending/`
exists) and [backend-upload-size-verification.md](backend-upload-size-verification.md)
(T61, the claim-time cap). Read those first — this spec assumes both.

## 1. Goal & scope

`pending/` was designed so that "an object under this prefix has never been claimed",
which is what makes a lifecycle rule on it impossible to get wrong. The design was
correct. The **enrolment** was not: three separate audits each declared the wiring
complete, and each missed surfaces.

- [backend-upload-orphans.md §4.1](backend-upload-orphans.md) already records round one:
  before/after pairs, artist photos and the consumer avatar never promoted at all.
- This spec covers round two, found while tracing every claim path end to end.

**In scope**

| | Defect | Class |
|---|---|---|
| **A1** | `POST /appointments` stores a client-supplied `depositScreenshotUrl` with no prefix check, no ownership check, no size verification and no promotion | security + T61 bypass + data loss |
| **A2** | A claimed key may contain `..` segments, so a `startsWith` prefix check is not by itself an ownership check | security (defence in depth) |
| **A3** | Four route-level casts turn a non-string JSON value into a 500 | correctness |
| **B1** | The salon gallery is **write-once** — every mutation after the first 400s | user-blocking |
| **B2** | KYC **partial resubmit** after a rejection always 400s | user-blocking |
| **B3** | `verifyAndPromote` is non-atomic: a mid-batch copy failure leaves earlier objects promoted-but-unrecorded and makes the identical retry impossible | reliability |
| **B4** | One `asset:` url silently disables verification *and* promotion for every other url in the same request | T61 bypass |

**Out of scope** (filed separately, see §9): review-photo resubmit silently dropping the
previous photos; deposit replacement orphaning the superseded object; mapping
`storage_unavailable` to 503; the consumer avatar upload using the pro session.

## 2. UX & flows

No new screens. Two existing flows stop failing:

- **Gallery.** Add, reorder, restore and **delete** all PUT the whole current list, so all
  four are broken from the second save onward. A salon can presently only manage its
  gallery by clearing it and re-uploading. After B1 all four work.
- **KYC.** After an admin rejection the banner says « Veuillez renvoyer vos documents. »
  Replacing only the flagged document, or pressing submit again, 400s with a bare
  `invalid_input` the UI cannot attribute to a field. After B2 both work. (Re-uploading
  *every* tile already worked — the report's "can never resubmit" overstates it; see §8.)

## 3. API & contract

No new endpoints. Contract changes:

- `POST /appointments` — `depositScreenshotUrl` documents its accepted shape
  (`pending/deposit/{userId}/…`, freshly signed) and gains `400 invalid_input`,
  `400 upload_too_large`, `400 upload_not_found`.
- `PUT /providers/{id}/gallery` — documents that already-stored urls pass through and
  anything else is refused.
- `POST /me/kyc` — documents that an already-stored key passes through, and the new
  document-count cap.

## 4. Data model

None. `appointments.deposit_screenshot_url` keeps holding a **bare object key** — never a
url. Three consumers depend on that: `DepositService.screenshotUrl` presigns it directly,
`AdminDisputeService` rides the same call for evidence, and `UserErasureService`
normalises it as a key.

## 5. Architecture & patterns

### 5.1 `promoteNewKeys` — the primitive, and why not a second copy of it

[PR #379](backend-upload-orphans.md) added `promoteNewUrls` for **url**-shaped save
surfaces. KYC is **key**-shaped: the KYC bucket has no public base at all, so
`promoteNewUrls` cannot apply — it needs a `publicBaseUrl` to strip and there is none.

The wrong fix is a second, independent key-shaped promoter copied from the url one. This
repo has already paid for one rule living in two functions. So:

```
promoteNewKeys(keys, {alreadyStored, bucket})     ← the primitive
verifyAndPromote(keys, {bucket})                  ≡ promoteNewKeys(alreadyStored: {})
promoteNewUrls(urls, {publicBaseUrl, alreadyStored, bucket})
                                                  → url-level pass-through,
                                                    then delegates to promoteNewKeys
```

The identity `verifyAndPromote == promoteNewKeys(alreadyStored: {})` is exact, which is
what makes the collapse safe, and is pinned by a test.

`verifyAndPromote` keeps its name, signature and **strictness**: it is the *claim* form,
and the deposit paths depend on it refusing anything not pending. Only *save* surfaces get
`alreadyStored`.

### 5.2 Membership, not shape — and the scope of the set

A promoted key is just a key without the prefix, so "not pending" is indistinguishable
from "arbitrary string the client invented". An unchanged value must therefore be one the
caller **provably already had**, matched against server state — and the set must be scoped
as narrowly as the surface:

| Surface | `alreadyStored` is | Source |
|---|---|---|
| Gallery | that salon's `imageUrls` | `ProvidersRepository.byId` |
| KYC | that account's `kycDocs` | the account already loaded at the top of `submit` |
| Artist photo | *that artist's* current photo, not the salon's | pinned since PR #379 |
| Deposit at booking | **empty by construction** — there is no prior row | — |

### 5.3 Copy-all, then delete-all

The promotion loop was `copy → delete source → copy → delete source`. Nothing was
destroyed (the deleted object is always the source of a copy that succeeded), but a
mid-batch failure left keys `0..N-1` at their **final** prefix, unrecorded in Postgres —
outside `pending/`, so no lifecycle rule collects them — and the identical retry then
fails *differently*, because `verify()` HEADs a source promotion has already deleted
(`storage_unavailable` on attempt one, `upload_not_found` on attempt two).

The fix is **not** a compensating rollback. A rollback would have to `CopyObject` *from* a
just-written object, which is the exact source-visibility window
[backend-upload-orphans.md §6.2](backend-upload-orphans.md) documents, and `copyObject`
has no retry — the rollback would be the least reliable step in the sequence.

Copy-all-then-delete-all is idempotent instead: the destination is a pure function of the
source (`promotedKey`), so a retry overwrites rather than duplicating, and a mid-loop copy
failure leaves **every** pending source intact. The whole request is retryable with the
same payload, and no orphan is created.

Exposure is the multi-key callers: KYC, review photos, gallery, before/after. Single-key
callers (deposit, artist, avatar) cannot hit it.

### 5.4 A `startsWith` prefix check is not an ownership check

`promotedKey` accepted any key beginning `pending/`, including one carrying `..` segments.
`pending/deposit/{me}/../{you}/x.jpg` satisfies both the ownership prefix check and the
pending check, and `promotedKey` maps it to `deposit/{me}/../{you}/x.jpg`.

Whether that resolves to another tenant's object depends on whether R2 normalises dot
segments in an object key (S3 keys are opaque strings, so probably not) and on whether
Dart's `Uri` normalises the path before or after the SigV4 canonical request is built
(before → the signature matches the normalised path; after → 403). **Both are empirical
questions about someone else's implementation, and neither was tested here.**

That is the whole argument for fixing it by construction rather than by analysis:
`promotedKey` now returns null for any key containing an empty, `.` or `..` segment. One
change, every claim path, no dependence on how R2 or `dart:core` behave. It is placed in
`promotedKey` — not in each caller — because that function is already the single gate
every claim path passes through.

We did **not** demonstrate an exploit, and the PR does not claim one.

## 6. Security & authz

### 6.1 A1 — the deposit field, stated accurately

`POST /appointments` accepted `depositScreenshotUrl` as an opaque string and wrote it to
the column. The read endpoint authorises on the **appointment** (`appt['userId'] == sub`,
or the salon's `journalViewAll`, or admin) and then presigns whatever string is in the
column. So a user who owns the appointment can have the server presign a key they do not
own.

**Blast radius, precisely — the report overstates this and the PR must not repeat it:**

- **Bucket:** `StorageBucket.deposit` only. The bucket is a compile-time constant at the
  call site and `presignGet` takes it as a required typed enum. The stored string cannot
  redirect the read to the KYC or public bucket.
- **Objects reachable:** only `pending/deposit/{userId}/…` and their promoted twins.
- **Not enumerable:** object ids are 16 bytes of `Random.secure()` and no endpoint lists a
  bucket. This is a *targeted* read of a key the attacker already knows — not a browsable
  cross-tenant dump. A realistic acquisition path does exist (a salon legitimately receives
  raw keys on the Appointment DTO and could replay one from a consumer account), which is
  why it is still a defect worth fixing at severity.

The **certain** damage is the honest path, not the attack: mobile signs a *pending* key and
passes it inline at booking, booking never promotes it, and production expires `pending/`
daily — so the payment proof for a real dispute disappears while the row still claims one
is attached. And no `objectSize` HEAD ever runs, so T61 does not apply to this path at all.

**Fix:** `BookingService` takes the verifier (optional, matching `KycService`), and `book`
requires `pending/deposit/{userId}/…`, then `verifyAndPromote`s, then stores the **promoted**
key.

**Why validate rather than delete the field.** Deleting it is cleaner on paper — web never
sends it — but the route reads only known keys, so removing it makes an attached proof a
silent no-op: the POST still 201s and the user is told the deposit was sent for a booking
that has none. A field already in an installed app build cannot be un-sent, so the server
must validate it regardless. Deprecating it and moving mobile to the attach-after-create
ordering web already uses is a **follow-up**, deliberately not coupled to the security fix.

**Defence in depth:** the read path also requires `deposit/{appointment.userId}/…` before
presigning, so a future regression in any write path cannot re-open the read.

**Ordering and its residual.** The prefix check is free and runs first, before any side
effect. Promotion runs immediately before the insert, so a refused upload creates nothing.
If the insert then loses the slot race, one promoted screenshot is orphaned — rare, and
strictly better than today, where *every* screenshot is orphaned under `pending/` and then
deleted.

### 6.2 Erasure

`DELETE /me` deletes deposit objects under `deposit/{userId}/` only, so today's
booking-written `pending/…` keys survive erasure. After A1 the column only ever holds a
promoted key, so this closes itself. The prefix filter is **not** widened to accept
`pending/…` — that guard is the only thing stopping a planted foreign key from becoming a
*destructive* cross-tenant primitive.

### 6.3 Threat model

`docs/BACKEND.md` §7: T61 gains the booking-time deposit write (the "seven surfaces"
sentence was already out of date), and a new row records the ownership-check gap and the
segment hardening.

## 7. Errors

| Code | Status | When |
|---|---|---|
| `invalid_input` | 400 | key not `pending/deposit/{userId}/…`; key with a `.`/`..`/empty segment; a save url/key that is neither pending nor already stored; too many KYC documents |
| `upload_too_large` | 400 | over the T61 cap (object deleted) |
| `upload_not_found` | 400 | the claimed object does not exist |
| `storage_unavailable` | 400 | storage unreachable — **fails closed**, never accepted (503 would be better; filed separately) |

## 8. Tests

Every one of these constructs the service **with** a verifier and a non-null
`publicBaseUrl`. The existing gallery and KYC suites do not, which is exactly why both bugs
shipped green: `provider_catalog_test.dart` builds `ProviderCatalogService` with no
verifier, and `kyc_test.dart` builds `KycService(providerAuth)` with none — so its
`resubmit clears a prior rejection` test is a false positive.

- **Deposit:** foreign-user key refused *and no appointment created* (asserted by read-back);
  an already-promoted key refused (no `alreadyStored` at create); happy path stores the
  promoted key with `copied`/`deleted` asserted; non-string → 400 not 500; oversized refused
  and deleted; and the read path refusing a foreign key on your own booking.
- **Traversal:** `..`, `.` and empty segments refused by `promotedKey`, through every claim
  path.
- **Gallery:** second save, **delete** after a first save, **reorder** after a first save,
  cross-salon url refused, clearing still works.
- **KYC:** resubmit replacing **one** document; bare resubmit with no changes; a promoted key
  belonging to another account refused (the shape-vs-membership assertion); a promoted key
  this account once had and no longer has, refused; over-cap refused.
- **Partial promotion:** a fake that fails the **second** copy — `deleted` must be empty, and
  the identical retry must succeed. The existing "a failed copy refuses rather than
  half-applying" test cannot express this: it passes a single key, so the failure is always
  at index 0 and half-application is unobservable.
- **Drift pin:** `promoteNewKeys(alreadyStored: {})` ≡ `verifyAndPromote` over the same
  fixtures.

## 9. Rollout & open questions

**Blast radius of shipping:** production holds 0 providers, 0 appointments and 0 objects in
all three buckets. Nothing to migrate, nothing to clean up.

**Decisions taken that differ from the audit brief:**

1. **`asset:` stays in `galleryOriginsFor`.** The brief recommended dropping it from the
   configured-base branch so the allowlist and the promoter agree. But `promoteNewUrls`
   already refuses a *new* `asset:` url, so dropping it changes no observable behaviour for
   new data — it would only break an `asset:` url that is *already stored*, with no security
   gain. The B4 bypass is closed by deleting the all-or-nothing length guard, which is the
   actual defect.
2. **Reviews get the guard fix but not the `alreadyStored` fix.** Closing B4 on reviews is
   the same two-line guard change; the full save-shaped fix needs a new
   `reviewByAppointment` repository read and is filed separately.

**Open, deliberately not answered here:** whether R2 normalises dot segments in an object
key. §5.4 makes it moot for us; it would still be worth knowing.

## 10. Not in this change

- Review-photo resubmit silently dropping the previous photos (needs a repository read).
- Deposit replacement orphaning the superseded promoted object.
- `storage_unavailable` → 503 across the contract.
- Deprecating the inline booking-time deposit field once mobile moves to attach-after-create.
