# R2 uploads — presigned PUT, because R2 does not implement presigned POST

> Module: **storage / uploads**. Fixes a **confirmed production defect**: every
> client upload in the product is broken. Prior art:
> [`pro-image-upload-pipeline.md`](pro-image-upload-pipeline.md) (the design this
> corrects), [`infra-gcp-migration.md`](infra-gcp-migration.md) (where it was
> found).

## 1. The defect

`storage_service.dart:5-7` signs an **S3 POST Object** (multipart form + policy).
Cloudflare R2 answers such a request:

```
HTTP 501
<Error><Code>NotImplemented</Code>
<Message>Presigned post requests are not yet implemented</Message></Error>
```

Measured against the live Cloud Run service with real R2 credentials, using a
real consumer session obtained through the Q1b smoke seam.

**Everything that uploads is dead:** deposit screenshots — which *are* the
no-custody payment flow — plus review photos, salon gallery images, and KYC
documents. The server signs happily and returns a valid-looking ticket; the
failure is entirely on the client's subsequent request.

**Why nothing caught it.** `upload_signing_test.dart` asserts the *shape* of what
we produce, never that a storage provider accepts it. The full backend suite and
the 47-assertion funnel gate were green throughout. A test that only checks our
own output cannot detect that the counterparty rejects it (§6).

## 2. Measured R2 behaviour

Four probes against the real deposit bucket, presigned PUT:

| Probe | Result | Conclusion |
|---|---|---|
| body matches signed `content-length` | **200** | presigned PUT works — this is the fix |
| body **500 bytes larger** than signed `content-length` | **200** | **size is NOT enforced** |
| no `content-length` signed, 5 KB body | **200** | same |
| signed `content-type`, different one sent | **403 `SignatureDoesNotMatch`** | content-type **is** enforced |

The fourth probe is the control: it proves the signed-headers mechanism genuinely
works, which is what makes the second probe's result trustworthy rather than a
bug in the harness. R2 verifies `content-type` and ignores `content-length`.

**Consequence: signing the size would be security theatre.** It would read like
enforcement in review and enforce nothing.

## 3. What this costs, and how it is paid back

Today the POST policy carries `['content-length-range', 0, maxBytes]`
(`storage_service.dart:167`), so oversized uploads are refused by storage before
any bytes land. That guarantee **cannot be preserved** on R2. Losing it silently
would leave any authenticated consumer able to PUT an object of arbitrary size
into the deposit bucket — billed to us.

So enforcement moves, in two layers:

1. **Advisory, at signing time.** The client declares `contentLength`; the
   service rejects `<= 0` or `> maxBytes` with `400 invalid_input` before
   signing. Catches honest clients, keeps the limit in the contract, and gives a
   clean error instead of a mysterious storage failure. **This is not a security
   control** — a malicious client simply lies.
2. **Authoritative, at claim time.** Every upload is followed by a request that
   hands the key back to the server (deposit proof, review photo, gallery, KYC).
   That handler issues a `HEAD` and rejects — and deletes — an object over the
   limit. This is the real enforcement, and it is the only layer that survives a
   lying client.

Layer 2 is **not in this PR** (§8) and the gap is stated rather than glossed:
until it lands, the size limit is advisory only. That is still strictly better
than today, where the limit is enforced by a request that always fails.

## 4. Design

### 4.1 `PresignedUpload` replaces `PresignedPost`

```dart
class PresignedUpload {
  const PresignedUpload({required this.url, required this.headers});
  final String url;
  final Map<String, String> headers;
}
```

Not a bare `String`: the caller must know **which headers the signature pins**,
because sending anything else yields `403 SignatureDoesNotMatch` (probe 4).

### 4.2 The signer already exists and is proven

`_presignUrl` (`:210`) has signed GET and DELETE in production since the KYC
work. PUT reuses it rather than growing a second signing path — the smallest
change with the most existing evidence behind it.

It hardcodes the header set in three coupled places: `'host:$host\n'` (`:240`),
`'host'` (`:241`), and `'X-Amz-SignedHeaders': 'host'` (`:230`). A
`signedHeaders` parameter derives all three from one sorted map. **GET and DELETE
pass nothing and must produce byte-identical URLs**, and their existing tests
must pass untouched — that is the cheapest possible proof the refactor is safe.

### 4.3 The literal bug

`presignPost` targets `{endpoint}/{bucket}` (`:178`) — correct for POST, where
the key travels in the form. A PUT must target the **object**:
`{endpoint}/{bucket}/{key}`, which `_presignUrl`'s `canonicalUri` (`:222`)
already builds.

### 4.4 Response shape

```jsonc
{ "method": "PUT",
  "uploadUrl": "https://<acct>.r2.cloudflarestorage.com/<bucket>/<key>?X-Amz-…",
  "headers": { "content-type": "image/jpeg" },
  "key": "deposit/user_…/….jpg",
  "maxBytes": 5242880,
  "expiresInSeconds": 300 }
```

`fields` → `headers`, `method` becomes `PUT`. **A breaking contract change**,
accepted without a compatibility window because there is nothing working to
break: every existing client is already receiving a ticket that cannot be used.

## 5. Security — unchanged where it matters

Not weakened: the key is server-built (`upload_signing_service.dart:98`), the
content-type allowlist still applies (`:29-34`), each purpose keeps its bucket
and prefix (`:69-96`), object ids stay `Random.secure()` (`:125`), and the
role-per-purpose gate in the route is untouched. `content-type` pinning survives
and is now *proven* rather than assumed (probe 4).

Weakened, deliberately and temporarily: the size cap, per §3.

## 6. Tests

The gate that would have caught this, and does not exist today: a test asserting
the ticket is **a shape a storage provider accepts**. Shape-only assertions
cannot detect that the counterparty refuses the request.

- **Rewrite** `upload_signing_test.dart` for the PUT ticket.
- **Keep untouched** the GET/DELETE signing tests (`:78-143`) — the refactor's
  safety proof.
- **New**: `presignPut` targets the object path, not the bucket root — the
  literal defect.
- **New**: the signed-headers list is sorted and matches the returned `headers`
  map, since a mismatch is a 403 at upload time.
- **New**: `contentLength` over `maxBytes`, `<= 0`, or missing → `invalid_input`.
- **New, `@Tags(['r2'])`, self-gating on credentials** (`test/storage/r2_live_test.dart`):
  sign a PUT and actually upload to R2. Skipped without credentials, so CI is
  unaffected — but it exists, and running it is what turns "we think this works"
  into "we watched it work".

  **It earned its place on the first run.** `objectSize` did an HTTP `HEAD`
  against a URL signed for `GET`; SigV4 covers the HTTP method, so the signature
  could never match and R2 answered 403 — in code already merged and deployed.
  The consequence was not a missing size check but a **total upload outage**:
  `objectSize` threw, `verify()` failed closed as designed, and every claim —
  deposit, KYC, review, gallery — would have been refused with
  `storage_unavailable`. The fail-closed posture turned a broken check into a
  visible outage rather than a silent hole, which is the behaviour we wanted,
  but nothing except this test would have found it before a user did.

## 7. Rollout

Backend and contract first (this PR). Clients follow immediately — they are
already broken, so there is no ordering hazard, only the time it takes.

## 8. Not in this PR — stated, not forgotten

1. **Claim-time size enforcement** (§3 layer 2). Until it lands the cap is
   advisory. **Highest-priority follow-up.**
2. **Mobile + web clients** — three Flutter `api_*` services and four web
   helpers still build multipart forms.
3. **R2 bucket CORS**, on all three buckets. Browser uploads fail without it
   regardless of how correct the signature is, and it is Cloudflare-side
   configuration rather than code.
