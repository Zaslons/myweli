# `infra/cloudflare/`

Object storage for **staging** — build-order step 3 of
[design/infra-staging.md](../../docs/design/infra-staging.md).

| File | What it is |
|---|---|
| [`90-staging-r2.sh`](90-staging-r2.sh) | Creates the three buckets, enables the public delivery origin, applies CORS and lifecycle. Idempotent. |
| [`cors-staging-public.json`](cors-staging-public.json) | CORS for the public bucket only. Staging origins — **never** `myweli.com`. **Wrangler's file format**, which is not the dashboard/API one. |

Verified by
[`backend/test/storage/r2_token_scope_test.dart`](../../backend/test/storage/r2_token_scope_test.dart).

> **The first run half-failed, and that is recorded here rather than quietly
> fixed.** This file was written in the dashboard/API format (a bare array of
> `AllowedOrigins`); `wrangler r2 bucket cors set --file` wants
> `{"rules":[{"allowed":{"origins":…}}]}`. `set -e` aborted the run correctly —
> but CORS came before lifecycle, so **neither** was applied while the buckets
> and the public origin were, and the only evidence was terminal scrollback.
>
> **Confirmed by the corrected run, since the docs do not say:** Cloudflare
> documents only `allowed.origins` and `allowed.methods` for the wrangler shape.
> `allowed.headers`, `exposeHeaders` and `maxAgeSeconds` are undocumented there
> but **work** — set on 2026-08-14 and read back exactly as written
> (`allowed_headers: content-type`, `exposed_headers: etag`,
> `max_age_seconds: 3600`). `content-type` is not optional in practice: the
> signed PUT pins that header, so a preflight without it fails.
>
> Two changes came out of it. The lifecycle rule is now applied with
> `lifecycle add`'s explicit flags instead of a second file whose schema is
> undocumented for wrangler — inferring a second format after the first was
> wrong is how you get a rule that silently is not there. And **every step reads
> its work back**, so a step that did not take effect fails instead of printing
> a tick. A script that reports success it has not confirmed is the failure mode
> this repository keeps finding.

## Why this directory exists

The staging plan called Cloudflare "the only genuinely un-scriptable blocker".
That was mostly wrong: `wrangler` creates buckets, sets CORS and lifecycle from
files, and enables the `r2.dev` origin. **Exactly one step needs the dashboard** —
minting the API token, because Cloudflare does not let a token create a token.

That distinction matters more than the convenience. Configuration that lives only
in a console is invisible to review, and this repo has already paid for that once:
the Render dashboard's cron jobs were unreviewable, which is how the reminder cron
came to be switched off with nobody noticing
([infra-gcp-migration.md](../../docs/design/infra-gcp-migration.md) §5). Anything
that *can* be a committed file should be one.

## The one thing that is not scripted, and the one that checks it

The token must be **bucket-scoped** to the three staging buckets. Cloudflare's
token screen defaults to *"Apply to all buckets"*, and that default is the whole
hazard: bucket names isolate nothing. `R2_BUCKET` decides which bucket the code
*addresses*; an account-scoped token can read and write every bucket in the
account regardless. A staging run of the user-erasure path — which deletes KYC
documents by key — would delete **production** objects, and every log line would
say it was operating on staging.

One radio button, no error, and nothing else in the system can tell. So it is not
left as an instruction:

```bash
R2_ACCOUNT_ID=… R2_ACCESS_KEY_ID=… R2_SECRET_ACCESS_KEY=… \
  R2_TOKEN_UNDER_TEST=staging \
  dart test --tags r2 test/storage/r2_token_scope_test.dart
```

It signs a GET for a key that does not exist — read-only, leaves nothing behind —
and reads the answer: **404** from a bucket the token may address, **403** from
one it may not. It asserts the reachable buckets answer 404 **and** the forbidden
ones answer 403. Both halves, because a revoked credential is denied everywhere
and would sail through a check that only looked at one side.

`R2_TOKEN_UNDER_TEST` picks which side the credential is — `staging` (default) or
`production` — and the two expectations swap. **The bucket lists stay literals
either way**: the variable selects between two hard-coded lists and cannot supply
or empty one, because a list coming from the same environment as the credential
could be emptied to make the test pass. An unrecognised value throws rather than
defaulting, for the same reason `Env.parse` does.

Proven to discriminate rather than merely to assert: the staging token passes as
`staging` and **fails six of seven** as `production`.

## Production's token is NOT scoped — checked 2026-08-15

The staging token is correct: `myweli-staging-backend-r2`, applied to exactly the
three `*-staging` buckets. Production's is not.

The account holds **two** Account API tokens named `R2 Account Token`, both
`Object Read & Write`, both applied to **All buckets**, both issued 2026-06-28,
both Active. There are no User API tokens.

Two separate problems:

- **Production's credential can reach every bucket in the account**, staging
  included — the blast radius runs the opposite way from the one this directory
  was written to close. Bounded, since staging holds synthetic data, but far
  broader than `infra/gcp/service.yaml` needs: only `myweli-uploads`,
  `myweli-kyc-private` and `myweli-deposits-private`.
- **Only one of the two can be in use.** The other is an unidentified live
  credential with account-wide access, and the dashboard does not list access key
  IDs, so which row matches the value in Secret Manager cannot be told by
  inspection.

The fix has the same shape as `infra/gcp/40-iam-wif.sh`'s widen/verify/narrow,
and the ordering is the safety property: create a scoped
`myweli-production-backend-r2`, add new Secret Manager versions **without**
disabling the old ones, deploy, verify with `R2_TOKEN_UNDER_TEST=production`, and
only then delete both old tokens. The verification exists precisely so that the
deletion is not the first time anyone finds out.

## Checking what is already there

`90-staging-r2.sh` **creates** staging. Production was configured by hand before
it existed and must not be pointed at a provisioning script: that script decides
whether a lifecycle rule is present by grepping its own rule name, and
production named the same rule differently — so a run would add a second rule
for the same prefix rather than recognising the first.

For an environment that already exists, use the checker:

```bash
bash infra/cloudflare/95-verify-r2.sh production
bash infra/cloudflare/95-verify-r2.sh staging
bash infra/cloudflare/95-verify-r2.sh            # both
```

It compares the live account to `r2-manifest.json` and **can only read** — no
create, no delete, no `cors set`, no `lifecycle add`. That is enforced, not
promised: `backend/test/infra/r2_manifest_test.dart` fails if a mutating
wrangler subcommand appears in it, comments included.

Needs `wrangler login`. It is not a CI job on purpose — CI has no Cloudflare
identity, and giving it one would mean a token that can reconfigure buckets.
The half that CAN run in CI is that same test, which pins the manifest against
the backend's own constants.
