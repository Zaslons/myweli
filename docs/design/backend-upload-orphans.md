# Upload orphans — why a lifecycle rule is not the answer

> Module: **storage / uploads**. Closes the residual left open by
> [`backend-upload-size-verification.md`](backend-upload-size-verification.md) §5.

## 1. The residual

Claim-time verification (T61) bounds the size of an object a client **claims**.
It cannot see an object nobody claims, because nothing ever asks the server
about it. So an authenticated client can:

1. call `POST /uploads/sign` — role-gated, but any consumer may sign a
   `deposit` upload;
2. PUT an object of **any size** (R2 ignores the signed `content-length` — §2 of
   the presigned-PUT spec);
3. never claim it.

No cap applies, because the cap runs at claim time. Repeat at will. **This is
the one path where the size limit does not exist at all**, and it bills us.

**It is not theoretical.** `r2_live_test.dart` left two orphans in
`myweli-uploads` — its `tearDownAll` deleted only the happy-path key, so when
the `objectSize` test failed (the HEAD-signature bug) its object survived, twice.
Found by listing the buckets. Both purged; the test's cleanup now covers every
key it can create.

## 2. Why the obvious fix does not work

A bucket lifecycle rule expires objects **by age and prefix**. It cannot
distinguish *claimed* from *unclaimed*, because that fact lives in Postgres, not
in the object.

Against the key layout as it is today, an age-based rule is **unsafe on all
three buckets**:

| Bucket | Contents | What an age rule would delete |
|---|---|---|
| `myweli-uploads` | gallery + review photos | a salon's gallery, while it is still on their page |
| `myweli-kyc-private` | identity / KYB documents — **retained** (`storage_service.dart:29`) | compliance evidence |
| `myweli-deposits-private` | Mobile Money proofs — "transient", **but no TTL was ever agreed** | payment evidence for a booking, and for any dispute |

The deposit bucket is the tempting one — the code calls it transient. But a
deposit screenshot is the *evidence a client paid*, and disputes exist
(`dispute_service.dart`). Deleting those on a timer, with no agreed retention
window, trades a storage-cost risk for an evidence-loss risk. That is a worse
trade, and it is not ours to make silently.

**So: no age-based rule on content prefixes.** The only rule set today is on
`livetest/` (§5), which by construction holds nothing but test residue.

## 3. What would actually work

Three designs, in ascending cost:

### 3.1 Rate-limit `POST /uploads/sign` — cheapest, partial

Bounds how many objects one account can create per day. Cheap, no data risk, no
key change. **Does not bound size**, so one determined account still uploads
arbitrarily large objects — just fewer of them. A useful floor, not a solution.

### 3.2 A `pending/` prefix, promoted on claim — correct, structural

Sign into `pending/{purpose}/{id}/…`; on a successful claim the server copies to
the final key and deletes the pending one. Orphans then live under a prefix that
contains **nothing but orphans**, and a 24-hour lifecycle rule on it is exactly
right — no heuristics, no risk to claimed data.

Costs: `StorageService.copyObject` (S3 `CopyObject`, supported by R2), the four
claim paths must promote rather than record directly, and the prefix checks
(`key.startsWith('deposit/$userId/')`) shift.

**The timing argument matters.** All three buckets are empty today — verified by
listing them. There is no data to migrate, so this costs nothing now and costs a
migration later. That is the same reasoning that made the GCP move worth doing
when it was.

### 3.3 A sweep cron — precise, no key change

A scheduled job lists objects older than N hours and deletes those not
referenced in Postgres. Exact rather than heuristic, and reuses the Cloud
Scheduler wiring that already exists. Costs a list-and-cross-check per bucket,
and gets slower as the buckets grow.

### Recommendation

**§3.2 now, §3.1 alongside.** The prefix scheme is the only design where the
deletion rule cannot be wrong, and it is free to adopt while the buckets are
empty. Rate-limiting is a few lines and bounds the abuse rate meanwhile.

§3.3 is the fallback if the prefix change is ever judged too invasive — it
reaches the same place at higher running cost.

## 4. Decision — §3.2, built

The owner chose the `pending/` prefix, and confirmed the app is **not yet public**
so there is no data to migrate and nothing to lose. Built:

- `UploadSigningService` issues `pending/{purpose}/{prefixId}/{id}.{ext}`.
- `UploadVerificationService.verifyAndPromote` size-checks, then copies to the
  final key and deletes the pending original, returning the promoted keys.
- All four claim paths record the **promoted** key. Public claims (review,
  gallery) rebuild the stored URL from it — keeping the pending URL would point
  at an object the lifecycle rule is about to expire.
- `StorageService.copyObject` (S3 `CopyObject`) signs `x-amz-copy-source` as a
  **signed header** — the same mechanism that pins `content-type`, which is why
  `_presignUrl` grew that parameter in the presigned-PUT work.

**Ordering is load-bearing and tested:** an oversized upload is refused *before*
promotion. Promoting first would move the offending object to its final key,
where the lifecycle rule can no longer collect it.

## 5. What is configured now

- **`livetest/` expiry — owner action, and deliberately so.** Setting it via the
  S3 API with the application's own R2 credentials returns **403 AccessDenied**:
  that token is scoped to object read/write and cannot reconfigure buckets.
  **That is the correct posture** — the credentials the backend carries should
  not be able to attach a rule that deletes objects — so this is a dashboard
  action rather than something to route around by minting an admin token.

  R2 → `myweli-uploads` → Settings → Object Lifecycle Rules → Add:
  prefix `livetest/`, delete after **1 day**.

  Safe because the prefix is only ever written by `r2_live_test.dart`, and the
  test now cleans up after itself anyway — this is the belt to that braces.
- **The default multipart-abort rule (7 days)** already exists on each bucket
  from R2's defaults. It reclaims *incomplete* multipart uploads, which is a
  different failure from a completed-but-unclaimed object, and is not a fix for
  §1.
