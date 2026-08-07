# Claim-time upload size verification — the cap R2 cannot enforce

> Module: **storage / uploads**. Closes the regression opened by
> [`backend-r2-presigned-put.md`](backend-r2-presigned-put.md) §3 layer 2.

## 1. Why this exists

The old presigned POST pinned `['content-length-range', 0, maxBytes]`, so storage
refused an oversized upload before any bytes landed. Cloudflare R2 does not
implement presigned POST, so we moved to presigned PUT — and **R2 ignores a
signed `content-length`**. Measured: a body 500 bytes larger than the signed
value was accepted with `200`, while a mismatched `content-type` was correctly
rejected with `403 SignatureDoesNotMatch`. The control proves the mechanism
works; the size simply is not covered.

So today `maxBytes` is **advisory**. `UploadSigningService` rejects an
implausible declared size, which stops honest clients — and stops nobody else.

**The exposure.** Any authenticated user can obtain a signed PUT and upload an
object of arbitrary size into the deposit bucket, billed to us, with no ceiling
and no alert. That is a denial-of-wallet, and it sits on the consumer path.

## 2. Where the check belongs

Uploading is two steps: the client PUTs to storage, then **hands the reference
back to us**. That second request is the only moment the server is in the loop
with a real object to inspect, so it is where enforcement has to live.

Four claim points, and they do not share a shape — worth stating, because a
single generic helper would otherwise look sufficient:

| Claim | Field | Bucket | Already validated |
|---|---|---|---|
| deposit | `screenshotKey` (`routes/appointments/[id]/deposit.dart:36`) | private | own-prefix |
| kyc | `documents[].key` (`kyc_service.dart:42-48`) | private | own-prefix, doc type |
| review | `photoUrls` (`reviews_service.dart:64-82`) | public | origin allowlist, count, length |
| gallery | `imageUrls` (`routes/providers/[id]/gallery.dart`) | public | origin allowlist |

**Ownership is already enforced at all four.** This slice adds size and nothing
else — it must not weaken or duplicate the existing checks.

Public claims carry **URLs**, not keys. The key is the URL minus the
`R2_PUBLIC_BASE_URL` prefix, and that prefix is already the origin allowlist
those paths validate against, so derivation is only legal on a URL that passed.

## 3. Design

### 3.1 `StorageService` gains two I/O methods

```dart
Future<int?> objectSize({required String key, required StorageBucket bucket});
Future<void> deleteObject({required String key, required StorageBucket bucket});
```

**This changes the class's contract, deliberately.** Its doc said it "only signs,
it never touches the network". That property is now given up — a size check is
inherently I/O, and a storage interface that cannot stat an object is not a
storage interface. The doc says so rather than leaving a stale claim.

`R2StorageService` performs HEAD/DELETE against its own presigned URLs, reusing
`_presignUrl` — the same signer proven for GET, PUT and DELETE.
`FakeStorageService` returns an injectable canned size, so every claim path is
testable without a bucket.

`objectSize` returns **null when the object does not exist**, which is
distinguishable from a zero-byte object and is treated as a rejection (§3.3).

### 3.2 `UploadVerificationService`

One collaborator, used by all four claim paths:

```dart
Future<({bool ok, String? error})> verify(
  List<String> keys, { required StorageBucket bucket });
```

- any key over `maxBytes` → `ok: false, error: 'upload_too_large'`
- any key missing → `ok: false, error: 'upload_not_found'`
- **every offending object is deleted** before returning. Rejecting while
  leaving the bytes in the bucket would refuse the booking and still pay for the
  storage, which is the outcome we are trying to avoid.

### 3.3 Failure posture — fail closed, and say why

If the HEAD itself fails (network, credentials, R2 outage) the claim is
**rejected**, not accepted. Accepting on error would make the control removable
by anyone who can make one request fail. The route answers `502
storage_unavailable` — distinct from `upload_too_large`, because the client's
correct response differs: retry versus do not.

## 4. Errors

| Code | Status | When |
|---|---|---|
| `upload_too_large` | 400 | object exceeds `maxBytes` |
| `upload_not_found` | 400 | key claimed but no such object |
| `storage_unavailable` | 502 | the check could not be performed |

## 5. Security

**Threat-model delta (BACKEND.md §7) — T61.** *Denial of wallet via unbounded
upload.* An authenticated client obtains a legitimate signed PUT and uploads an
arbitrarily large object; R2 does not enforce the signed `content-length`.
Mitigated at claim time by a server-side HEAD, with the object deleted on
rejection, failing closed on error.

**Residual, and stated plainly:** bytes still land before we look. A client that
uploads and never claims leaves an orphan we never inspect. Bounding *that*
needs a bucket lifecycle rule expiring unclaimed objects under each prefix —
Cloudflare-side configuration, listed in §8 rather than pretended away here.

Unchanged: ownership, prefix and origin checks at every claim; server-built
keys; the content-type allowlist.

## 6. Tests

- oversized object → `upload_too_large`, **and the object is deleted** (the
  delete is asserted, not assumed)
- missing object → `upload_not_found`
- HEAD throws → `storage_unavailable`, and the claim is **refused** — the
  fail-closed test, which is the one that matters if the control is ever
  "simplified"
- at the size boundary: exactly `maxBytes` passes, one byte more fails
- each of the four claim paths rejects an oversized upload — four tests, because
  they have four different shapes and a shared helper does not prove each is
  wired to it
- a public URL outside the allowlist is still refused **before** any key
  derivation is attempted

## 7. Rollout

Backend-only; no client change. A client uploading within the limit sees no
difference. Ships before the mobile/web PUT migration so the cap exists the
moment uploads start working again.

## 8. Not in this PR

1. **Bucket lifecycle rules** expiring unclaimed objects — Cloudflare-side, and
   the only answer to the orphan case in §5.
2. **R2 bucket CORS**, still outstanding for browser uploads.
