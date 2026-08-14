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
R2_ACCOUNT_ID=… R2_ACCESS_KEY_ID=<staging> R2_SECRET_ACCESS_KEY=<staging> \
  dart test --tags r2 test/storage/r2_token_scope_test.dart
```

It signs a GET for a key that does not exist — read-only, leaves nothing behind —
and reads the answer: **404** from a bucket the token may address, **403** from
one it may not. It asserts the staging buckets answer 404 **and** the production
buckets answer 403. Both halves, because a revoked credential is denied
everywhere and would sail through a check that only looked at the production side.

**Check production's own token the same way while you are in that screen.** If it
was created as "apply to all buckets", staging inherits the blast radius no matter
how carefully this one is scoped.
