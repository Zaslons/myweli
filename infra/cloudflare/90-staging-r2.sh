#!/usr/bin/env bash
# Staging object storage — three R2 buckets, their CORS and their lifecycle
# rules (docs/design/infra-staging.md §2, build-order step 3).
#
# WHY THIS IS A SCRIPT AND NOT A CHECKLIST. The plan called this "the only
# genuinely un-scriptable blocker", and most of it turned out not to be:
# `wrangler` creates buckets, sets CORS from a file, adds lifecycle rules from
# flags and enables the r2.dev origin. Only ONE step actually needs the dashboard —
# minting the API token — because Cloudflare does not expose token creation to a
# token. That step is called out below rather than buried.
#
# Everything scripted here is therefore reviewable in a PR, which is the same
# property `infra/gcp/service.yaml` exists for and the same one the Render
# dashboard's cron jobs lacked when the reminder cron was off and nobody knew.
#
# Idempotent: every step tolerates already-exists, so a partial run re-runs.
#
# EVERY STEP READS ITS WORK BACK. The first version did not, and the first real
# run proved why: the CORS file was in the DASHBOARD/API format (a bare array of
# `AllowedOrigins`) while `wrangler r2 bucket cors set --file` wants its own
# shape (`{"rules":[{"allowed":{"origins":…}}]}`). `set -e` did abort the run —
# loudly, to a terminal nobody was reading — and because CORS came before
# lifecycle, NEITHER was applied while the buckets and the public origin were.
# Half-configured, and the only evidence was scrollback.
#
# A step that reports success it has not confirmed is the failure mode this
# whole repository keeps finding. So `verify` below re-reads each setting and
# the script fails if what came back is not what went in.
#
#   npx wrangler login          # once, as the account owner
#   bash infra/cloudflare/90-staging-r2.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRANGLER="npx --yes wrangler@4"

PUBLIC_BUCKET=myweli-uploads-staging
KYC_BUCKET=myweli-kyc-private-staging
DEPOSIT_BUCKET=myweli-deposits-private-staging

# `weur` (Western Europe) matches the backend's europe-west9 (Paris). A location
# hint is advisory — R2 is not regional the way Cloud SQL is — but the objects
# and the service that signs for them may as well be on the same continent.
LOCATION=weur

echo "==> 1/4  Buckets"
for b in "$PUBLIC_BUCKET" "$KYC_BUCKET" "$DEPOSIT_BUCKET"; do
  if $WRANGLER r2 bucket info "$b" >/dev/null 2>&1; then
    echo "    ✓ $b already exists"
  else
    $WRANGLER r2 bucket create "$b" --location "$LOCATION"
    echo "    + created $b"
  fi
done

echo "==> 2/4  Public delivery origin (r2.dev) for $PUBLIC_BUCKET only"
# **Only the public bucket.** The KYC and deposit buckets hold identity
# documents and payment proofs; they have no delivery origin in production and
# must not acquire one here. Staging is where someone reaches for "just make it
# work", which is exactly why the asymmetry is scripted rather than remembered.
#
# r2.dev rather than a `cdn-staging.myweli.com` custom domain: free,
# rate-limited, and adequate for an environment nobody's customers reach.
$WRANGLER r2 bucket dev-url enable "$PUBLIC_BUCKET" --force 2>/dev/null ||
  $WRANGLER r2 bucket dev-url enable "$PUBLIC_BUCKET"
DEV_URL=$($WRANGLER r2 bucket dev-url get "$PUBLIC_BUCKET" 2>/dev/null |
  grep -oE 'https://[a-z0-9.-]+\.r2\.dev' | head -1 || true)

echo "==> 3/4  CORS on $PUBLIC_BUCKET"
# The public bucket is the only one a browser PUTs to directly (the pro photo
# upload posts to a presigned URL). The private two are reached only through
# presigned URLs the backend mints, server-side, so they need no CORS at all —
# and giving them some would be a browser-reachable surface on the buckets that
# hold KYC documents.
#
# `cors-staging-public.json` lists localhost only, because that is the only
# staging origin that exists today. The Vercel preview origins are added when
# Preview is pointed at staging (build-order step 5) — Vercel mints a distinct
# hostname per deployment, so that step has to settle how an exact-match
# allowlist covers them. **Never `https://myweli.com`**: the fix for a
# CORS-blocked preview is a staging origin, never widening production's.
$WRANGLER r2 bucket cors set "$PUBLIC_BUCKET" \
  --file "$HERE/cors-staging-public.json" --force
# Read it back. `set` exiting 0 means the API accepted the request, not that the
# policy is there — and "the CORS configuration does not exist" is exactly what
# this bucket answered after the first run reported nothing wrong.
if ! $WRANGLER r2 bucket cors list "$PUBLIC_BUCKET" 2>&1 | grep -qi 'localhost:3000'; then
  echo "::error:: CORS did not stick on $PUBLIC_BUCKET — read it back and see"
  $WRANGLER r2 bucket cors list "$PUBLIC_BUCKET" || true
  exit 1
fi
echo "    ✓ CORS verified by reading it back"

# The private two must have NO CORS. Asserted rather than assumed: they are
# reached only through presigned URLs the backend mints server-side, and a
# browser-reachable surface on the buckets holding KYC documents and payment
# proofs is the kind of thing that arrives by someone copying a working line.
for b in "$KYC_BUCKET" "$DEPOSIT_BUCKET"; do
  if $WRANGLER r2 bucket cors list "$b" 2>&1 | grep -qiE 'origins|AllowedOrigins'; then
    echo "::error:: $b has a CORS policy and must not"
    exit 1
  fi
  echo "    ✓ $b has no CORS, as intended"
done

echo "==> 4/4  Lifecycle rules on all three"
# docs/BACKEND.md T61 records orphaned uploads as bounded only by a bucket
# lifecycle rule, "Cloudflare-side, outstanding" — designed and never applied.
#
# `lifecycle add` with explicit flags rather than `set --file`: the file schema
# for lifecycle is not documented for wrangler (the docs point at the REST API
# body), and inferring a second undocumented format after the first one was
# wrong is how you get a rule that silently is not there. These flags are read
# from `wrangler r2 bucket lifecycle add --help`.
#
# ONE rule, not two. Cloudflare already creates a "Default Multipart Abort Rule"
# at 7 days on every bucket — verified on all three of these — so a second
# multipart rule would be redundant. `pending/` is where uploads land before
# they are claimed, so anything still there after a day is by construction an
# orphan (docs/design/backend-upload-orphans.md).
for b in "$PUBLIC_BUCKET" "$KYC_BUCKET" "$DEPOSIT_BUCKET"; do
  if $WRANGLER r2 bucket lifecycle list "$b" 2>&1 | grep -q 'expire-pending-uploads'; then
    echo "    ✓ $b already has the rule"
  else
    $WRANGLER r2 bucket lifecycle add "$b" expire-pending-uploads 'pending/' \
      --expire-days 1 --force
  fi
  # Read back, same reason as CORS.
  if ! $WRANGLER r2 bucket lifecycle list "$b" 2>&1 | grep -q 'expire-pending-uploads'; then
    echo "::error:: the lifecycle rule did not stick on $b"
    $WRANGLER r2 bucket lifecycle list "$b" || true
    exit 1
  fi
  echo "    ✓ $b verified"
done

cat <<EOF

Buckets, CORS and lifecycle are done. Two things remain, and the first one is
the one that matters.

────────────────────────────────────────────────────────────────────────────
1. THE API TOKEN — dashboard only, and it must be BUCKET-SCOPED
────────────────────────────────────────────────────────────────────────────

  R2 → Manage R2 API Tokens → Create API token

    Permissions:      Object Read & Write
    Specify bucket(s): $PUBLIC_BUCKET
                       $KYC_BUCKET
                       $DEPOSIT_BUCKET

  **"Apply to all buckets" is the wrong answer, and it is the default.** An
  account-scoped token reads and writes every bucket regardless of what
  \`R2_BUCKET\` says — so a staging run of the user-erasure path would delete
  PRODUCTION objects. The bucket names are isolation; the credential is not,
  unless you scope it here.

  Do not take that on trust. Prove it:

    R2_ACCOUNT_ID=…  R2_ACCESS_KEY_ID=<the new one>  R2_SECRET_ACCESS_KEY=… \\
      dart test --tags r2 test/storage/r2_token_scope_test.dart

  It asserts the token CAN reach all three staging buckets and CANNOT reach any
  production bucket. Both halves — a dead credential fails everything and would
  pass a one-sided check.

  While you are in that screen: **check production's own token the same way.**
  If it was created as "apply to all buckets", staging inherits the blast radius
  no matter how carefully this one is scoped.

────────────────────────────────────────────────────────────────────────────
2. The values, into Secret Manager (build-order step 4)
────────────────────────────────────────────────────────────────────────────

  STAGING_R2_BUCKET           $PUBLIC_BUCKET
  STAGING_R2_KYC_BUCKET       $KYC_BUCKET
  STAGING_R2_DEPOSIT_BUCKET   $DEPOSIT_BUCKET
  STAGING_R2_PUBLIC_BASE_URL  ${DEV_URL:-<the r2.dev URL — see: wrangler r2 bucket dev-url get $PUBLIC_BUCKET>}
  STAGING_R2_ACCESS_KEY_ID    <from the token above>
  STAGING_R2_SECRET_ACCESS_KEY <from the token above>

  R2_ACCOUNT_ID is deliberately SHARED with production — same Cloudflare
  account, so a twin would be byte-identical and two copies of one value is
  drift waiting to happen (infra/gcp/service-staging.yaml).
EOF
