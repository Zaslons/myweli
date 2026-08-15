#!/usr/bin/env bash
# Read-only R2 configuration checker.
#
# Compares the live Cloudflare account to `r2-manifest.json` and reports drift.
# It NEVER writes: no create, no delete, no `cors set`, no `lifecycle add`. That
# is not a promise in a comment — `r2_manifest_test.dart` greps this file for
# mutating verbs and fails if one appears.
#
# Why read-only, when `90-staging-r2.sh` provisions: production is already
# provisioned, by hand, before that script existed. Pointing a creation script
# at it is how you end up with two lifecycle rules for the same prefix — the
# staging script decides "already there?" by grepping its OWN rule name, and
# production's rule is called something else. The safe tool for an environment
# that already exists is one that can only look.
#
#   bash infra/cloudflare/95-verify-r2.sh production
#   bash infra/cloudflare/95-verify-r2.sh staging
#   bash infra/cloudflare/95-verify-r2.sh            # both
#
# Exit 0 = the live account satisfies the manifest. Exit 1 = drift, listed.
#
# Needs `wrangler login` (an interactive OAuth session), which is why this is
# not a CI job: CI has no Cloudflare identity, and giving it one would mean
# minting a token with bucket-configuration rights — the very thing
# backend-upload-orphans.md §5 argues the application must not hold.
set -euo pipefail

cd "$(dirname "$0")/../.."
# Overridable so the negative tests can point it at a deliberately
# wrong manifest — a checker nobody has watched fail is not a checker.
MANIFEST="${R2_MANIFEST:-infra/cloudflare/r2-manifest.json}"
WRANGLER="npx --yes wrangler@4"

command -v jq >/dev/null || { echo "::error:: jq is required"; exit 1; }
[[ -f "$MANIFEST" ]] || { echo "::error:: $MANIFEST not found"; exit 1; }

ENVS=("${1:-}")
[[ -z "${ENVS[0]}" ]] && ENVS=(production staging)

FAILURES=0
fail() { echo "    ✗ $*"; FAILURES=$((FAILURES + 1)); }
pass() { echo "    ✓ $*"; }

PREFIX=$(jq -r '.lifecycle.prefix' "$MANIFEST")
DAYS=$(jq -r '.lifecycle.expireAfterDays' "$MANIFEST")
REQ_METHODS=$(jq -r '.cors.requiredMethods[]' "$MANIFEST")
REQ_HEADER=$(jq -r '.cors.requiredHeader' "$MANIFEST")

echo "==> Listing buckets"
LIVE_BUCKETS=$($WRANGLER r2 bucket list 2>/dev/null | awk '/^name:/ {print $2}')

for ENV_NAME in "${ENVS[@]}"; do
  jq -e --arg e "$ENV_NAME" '.environments[$e]' "$MANIFEST" >/dev/null 2>&1 || {
    echo "::error:: unknown environment '$ENV_NAME' (expected production or staging)"
    exit 1
  }
  echo
  echo "==> $ENV_NAME"

  PUBLIC=$(jq -r --arg e "$ENV_NAME" '.environments[$e].publicBucket' "$MANIFEST")
  BUCKETS=$(jq -r --arg e "$ENV_NAME" '.environments[$e].buckets[]' "$MANIFEST")

  for B in $BUCKETS; do
    echo "  $B"
    if ! grep -qx "$B" <<<"$LIVE_BUCKETS"; then
      fail "the bucket does not exist"
      continue
    fi

    # Matched on prefix + action, never on name — the two environments named the
    # same rule differently and a name check reports production as missing.
    LC=$($WRANGLER r2 bucket lifecycle list "$B" 2>/dev/null || true)
    if grep -A 3 -E "^prefix: +${PREFIX}$" <<<"$LC" |
      grep -qE "^action: +Expire objects after ${DAYS} days?$"; then
      RULE=$(grep -B 3 -E "^prefix: +${PREFIX}$" <<<"$LC" | awk '/^name:/ {n=$2} END {print n}')
      pass "pending expiry: ${PREFIX} after ${DAYS}d (rule '${RULE}')"
      # Enabled is separate from present: a disabled rule lists identically to
      # an active one except for this line, and collects nothing.
      grep -B 2 -A 3 -E "^prefix: +${PREFIX}$" <<<"$LC" | grep -qE "^enabled: +Yes$" ||
        fail "…but the rule is DISABLED, so nothing is collected"
    else
      fail "NO lifecycle rule for '${PREFIX}' expiring after ${DAYS}d — the"
      fail "  promotion design assumes it; unclaimed uploads accumulate forever"
      echo "$LC" | sed 's/^/      | /'
    fi

    [[ "$B" == "$PUBLIC" ]] || continue

    CORS=$($WRANGLER r2 bucket cors list "$B" 2>/dev/null || true)
    ORIGINS=$(grep -E '^allowed_origins:' <<<"$CORS" | cut -d: -f2- || true)
    METHODS=$(grep -E '^allowed_methods:' <<<"$CORS" | cut -d: -f2- || true)
    HEADERS=$(grep -E '^allowed_headers:' <<<"$CORS" | cut -d: -f2- || true)

    while read -r O; do
      [[ -z "$O" ]] && continue
      grep -qF "$O" <<<"$ORIGINS" &&
        pass "CORS allows $O" ||
        fail "CORS does NOT allow $O — every browser upload fails as an opaque CORS error"
    done < <(jq -r --arg e "$ENV_NAME" '.environments[$e].corsAllowedOrigins[]' "$MANIFEST")

    for M in $REQ_METHODS; do
      grep -qw "$M" <<<"$METHODS" ||
        fail "CORS does not allow $M (live: ${METHODS# })"
    done

    # `*` satisfies it; anything narrower must name it, because the presign
    # SIGNS content-type and storage 403s a request that arrives without it.
    if grep -q '\*' <<<"$HEADERS" || grep -qi "$REQ_HEADER" <<<"$HEADERS"; then
      pass "CORS permits the signed '${REQ_HEADER}' header"
    else
      fail "CORS does not permit '${REQ_HEADER}' (live: ${HEADERS# })"
    fi
  done
done

echo
if ((FAILURES == 0)); then
  echo "Live R2 matches the manifest."
else
  echo "::error:: ${FAILURES} drift(s) — the live account does not match ${MANIFEST}."
  echo "Fix the ACCOUNT if the manifest is right; fix the MANIFEST if the account is."
  echo "Do not fix it by running a provisioning script at production — see the header."
  exit 1
fi
