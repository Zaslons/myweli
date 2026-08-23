#!/usr/bin/env bash
#
# Are the secret versions the manifests pin still the right ones?
#
# Exit 0 = every pin is ENABLED and is the newest enabled version.
# Exit 1 = drift, listed.
#
# ## Why this exists
#
# Every mount in infra/gcp/service*.yaml is pinned to a version number rather
# than `latest`, because Cloud Run resolves a secret reference at container
# start and production runs minScale: 1 — one start per revision, ever. Pinning
# makes a stale value impossible instead of merely detectable.
#
# It trades one silent failure for two loud ones, and this script is where they
# are made loud:
#
#   * **a pin that is no longer newest** — somebody ran `versions add` and did
#     not bump the manifest, so the new value is not in force anywhere and
#     nothing said so;
#   * **a pin that has been DISABLED** — worse, and the reason the ordering rule
#     in DEPLOYMENT.md exists. The running instance survives on a version it
#     already read, so nothing breaks now; it breaks at the next scale-up or the
#     next rollback, which is to say at the worst possible moment.
#
# ## READ-ONLY, and metadata only — enforced rather than promised
#
# This script calls `gcloud secrets versions list` and `... describe`, both of
# which return a version NUMBER and a STATE. It never calls the `access` verb, which
# is the one that returns the value. backend/test/infra/secret_pins_test.dart greps for
# that verb and fails if it appears, the same way log_retention_test.dart guards
# 97-verify-log-retention.sh — including inside comments, because a commented-out call is a line
# someone uncomments at 2am.
#
# The identity this runs as in CI holds exactly four permissions, none of which
# is secretmanager.versions.access, and production-checks.yml proves that with a
# negative control rather than asserting it.
set -uo pipefail

PROJECT="${PROJECT:-myweli}"
HERE="$(dirname "${BASH_SOURCE[0]}")"

fails=0
fail() { echo "  ✗ $*"; fails=$((fails + 1)); }
ok()   { echo "  ✓ $*"; }

# **The rehearsal seam**, and it earns its place: one branch below cannot be
# exercised against the real project, because reaching it needs a secret with
# two ENABLED versions and there is none — creating one is a cloud mutation.
# Without this, "a pin that is no longer newest is caught" would be a claim.
#
# Shape: {"NAME": {"state": "ENABLED", "newest": "3"}}. It is TOTAL, not a
# patch — a secret the fixture omits reads as having no enabled version and
# fails, which is the safe direction for a rehearsal. Announced loudly so a
# rehearsal can never be mistaken for a measurement, and forbidden from both
# workflows by backend/test/infra/secret_pins_test.dart — the
# 99-verify-monitor-alive.mjs idiom.
FIXTURE="${SECRET_PINS_FIXTURE_JSON:-}"
if [[ -n "$FIXTURE" ]]; then
  echo "!! SECRET_PINS_FIXTURE_JSON is set — this is a REHEARSAL, not a measurement."
  echo "!! No Secret Manager call will be made."
  echo
fi

# Metadata only, both of them: a version NUMBER and a STATE. Never a value.
version_state() {  # $1 = secret, $2 = version
  if [[ -n "$FIXTURE" ]]; then
    printf '%s' "$FIXTURE" | jq -r --arg n "$1" '.[$n].state // "NOT_FOUND"'
  else
    gcloud secrets versions describe "$2" --secret="$1" \
      --project="$PROJECT" --format='value(state)' 2>&1
  fi
}

newest_enabled() {  # $1 = secret
  if [[ -n "$FIXTURE" ]]; then
    printf '%s' "$FIXTURE" | jq -r --arg n "$1" '.[$n].newest // ""'
  else
    gcloud secrets versions list "$1" --project="$PROJECT" \
      --filter='state:ENABLED' --sort-by=~createTime --limit=1 \
      --format='value(name)' 2>&1
  fi
}

# ---------------------------------------------------------------------------
# The pins, read out of the manifests that are actually deployed.
# ---------------------------------------------------------------------------
PAIRS=""
for f in "${HERE}/service.yaml" "${HERE}/service-staging.yaml"; do
  [[ -f "$f" ]] || { fail "manifest missing: $f"; continue; }
  # `name: X, key: 'N'` on one line, which is how both files write it.
  while read -r line; do
    n="${line%%|*}"; k="${line##*|}"
    PAIRS+="${n}|${k}"$'\n'
  done < <(sed -n "s/.*secretKeyRef: { name: \([A-Z0-9_]*\), key: '\([0-9]*\)' }.*/\1|\2/p" "$f")
done
PAIRS="$(printf '%s' "$PAIRS" | sort -u | grep -c . >/dev/null && printf '%s' "$PAIRS" | sort -u)"

# **The vacuity guard, and it is not optional.** If the manifests are reshaped
# and the sed stops matching, every loop below runs zero times and this script
# exits 0 having verified nothing — which is the failure it exists to prevent,
# wearing its own uniform.
COUNT="$(printf '%s\n' "$PAIRS" | grep -c '|' || true)"
if [[ "$COUNT" -lt 12 ]]; then
  echo "::error::parsed only ${COUNT} pinned secrets from the manifests."
  echo "::error::Refusing to report success — the shape this script reads has changed."
  exit 1
fi
echo "  ${COUNT} pinned mounts across both manifests"
echo

# ---------------------------------------------------------------------------
# Each pin: still enabled, and still the newest.
# ---------------------------------------------------------------------------
while IFS='|' read -r NAME PIN; do
  [[ -z "$NAME" ]] && continue

  STATE="$(version_state "$NAME" "$PIN")"
  if [[ "$STATE" != "ENABLED" ]]; then
    fail "${NAME} pins v${PIN}, which is ${STATE:-unreadable}. A new container" \
         "cannot start: the running instance survives on what it already read," \
         "so this surfaces at the next scale-up or rollback."
    continue
  fi

  NEWEST="$(newest_enabled "$NAME")"
  if [[ "$NEWEST" != "$PIN" ]]; then
    fail "${NAME} pins v${PIN} but v${NEWEST} is the newest enabled version." \
         "Someone added a version and did not bump the manifest, so the new" \
         "value is in force nowhere."
    continue
  fi

  ok "${NAME} v${PIN}"
done <<< "$PAIRS"

echo
if [[ "$fails" -gt 0 ]]; then
  echo "SECRET PIN DRIFT: ${fails} pin(s) are wrong."
  echo "A pin that is not newest means a value nobody is running. A pin that is"
  echo "DISABLED means the next container start fails. See docs/DEPLOYMENT.md"
  echo "for the ordering rule: never disable a version a live manifest pins."
  exit 1
fi
echo "Every pinned secret version is enabled and current."
