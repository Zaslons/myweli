#!/usr/bin/env bash
#
# Per-IP rate limiting on the ADMIN login, at the load balancer.
#
# ## The gap this closes
#
# 87-rate-limit-policy.sh matches `request.path.startsWith('/auth/')`.
# `/admin/auth/login` does NOT match that — it starts with `/admin/`. So the one
# endpoint that mints a token every other `/admin/*` route trusts had no per-IP
# limit at all, on a service reachable from any address on the internet.
#
# That went unnoticed because a design doc recorded a reason not to look:
# "admin login sits behind Cloudflare Access, so the blast radius is small."
#
# **Access IS configured — verified 2026-08-19 by fetching it** — and it covers
# `admin.myweli.com`, the Cloudflare Pages bundle. It does not cover the API.
# `api.myweli.com` is deliberately DNS-only / grey-cloud so Google can validate
# the managed certificate (70-load-balancer.sh:62-63), so Cloudflare is not in
# its request path. Measured the same day: an anonymous POST to
# api.myweli.com/admin/auth/login answers 401 directly, no redirect.
#
# ## Why `/admin/auth/` and not `/admin/`
#
# A rule over all of `/admin/` would throttle ordinary console use — the KYC
# queue, analytics, moderation, every paginated read — at ten requests a minute.
# And the admin team plausibly shares one office or salon address, so a per-IP
# ceiling hits all of them together. The login form is the surface that needs
# bounding; the rest of the console is authenticated and already role-gated.
#
# ## What this is, and what it is NOT
#
# **It is the storage fix, not the security fix.** The security fix shipped
# first, deliberately: `admin_login_throttle` (migration 0035) bounds guesses
# PER CREDENTIAL, which per-IP fundamentally cannot — an attacker with a botnet
# walks through any IP ceiling. What per-IP adds is a bound on how fast one
# source can create rows in that table, whose key set is open by design (unknown
# addresses are counted so `locked_out` cannot become an admin-address oracle).
# 10/min caps one address at 14,400 rows/day rather than two million.
#
# Order matters and is deliberate: credential bound first, source bound second.
#
# ## The threshold
#
# 10 requests/minute per IP, 300s ban — the same numbers as the `/auth/*` rule
# rather than tighter ones. Consistency is worth something in a policy somebody
# reads at 3am, and a human logging into a console does it once, twice if they
# fat-finger it. The real bound on guessing is the lockout, not this.
#
# Design: docs/design/backend-admin-login-throttle.md §8
set -euo pipefail

PROJECT="${MYWELI_GCP_PROJECT:-myweli}"
POLICY=myweli-api-rate-limit
BACKEND=myweli-api-backend
PREVIEW="${PREVIEW:-0}"

# ---- the policy must already exist and be attached ------------------------
# This ADDS a rule to the existing policy rather than creating a second one: a
# backend service takes exactly one security policy, so a second would have to
# replace the first, silently dropping the /auth/ rule.
if ! gcloud compute security-policies describe "$POLICY" --project="$PROJECT" \
     >/dev/null 2>&1; then
  echo "::error:: policy $POLICY does not exist — run 87-rate-limit-policy.sh first."
  exit 1
fi

ATTACHED=$(gcloud compute backend-services describe "$BACKEND" --global \
  --project="$PROJECT" --format='value(securityPolicy)' 2>/dev/null || true)
if [[ "$ATTACHED" != *"$POLICY"* ]]; then
  echo "::error:: $BACKEND is not protected by $POLICY (it has: ${ATTACHED:-none})."
  echo "          Adding a rule to a detached policy protects nothing."
  exit 1
fi
echo "→ $POLICY is attached to $BACKEND"

# ---- the rule -------------------------------------------------------------
# Priority 1100, after the /auth/ rule at 1000. The two expressions are
# disjoint, so precedence cannot matter for correctness — but a distinct
# priority is required, and a higher number reads as "added later".
ACTION=$([[ "$PREVIEW" == "1" ]] && echo "--preview" || echo "")

gcloud compute security-policies rules create 1100 \
  --project="$PROJECT" \
  --security-policy="$POLICY" \
  --description="admin login: 10/min per IP (the /auth/ rule at 1000 does not match /admin/)" \
  --expression="request.path.startsWith('/admin/auth/')" \
  --action=rate-based-ban \
  --rate-limit-threshold-count=10 \
  --rate-limit-threshold-interval-sec=60 \
  --ban-duration-sec=300 \
  --conform-action=allow \
  --exceed-action=deny-429 \
  --enforce-on-key=IP \
  $ACTION

echo
echo "Rules now on $POLICY:"
gcloud compute security-policies describe "$POLICY" --project="$PROJECT" \
  --format='table(rules.priority, rules.match.expr.expression, rules.action)' \
  2>/dev/null | head -8

cat <<'NOTE'

VERIFYING IT — and the control is not optional.

A rule that exists is not a rule that refuses, and a rule whose expression never
matches looks exactly like a healthy service. Worse here: a rule that is TOO
BROAD would refuse ordinary console traffic, and you would not see that from the
refusal side alone. So probe in both directions.

*** WAIT ~7 MINUTES AFTER CREATING THE RULE. *** Measured on the /auth/ rule: a
burst two minutes after attaching passed 18/18, which is indistinguishable from
an expression that never matches. It took about seven minutes to propagate.

  # 1. THE RULE FIRES — 15 posts to the admin login
  for i in $(seq 1 15); do
    curl -s -o /dev/null -w "%{http_code} " \
      -X POST https://api.myweli.com/admin/auth/login \
      -H 'Content-Type: application/json' \
      -d '{"email":"probe@myweli.test","password":"x"}'
  done; echo

  Expect roughly `401 x10` then `429 x5`. The 401s are the API answering (bad
  credentials); the 429s are Cloud Armor. Note the app ALSO returns 429 for
  `locked_out` — distinguish them by the body: Cloud Armor's is an HTML error
  page, the app's is {"error":"locked_out"}. Use a fresh probe address so the
  per-credential lockout does not fire first and confuse the two.

  # 2. THE CONTROL — the console must still work
  for i in $(seq 1 15); do
    curl -s -o /dev/null -w "%{http_code} " https://api.myweli.com/health
  done; echo

  Expect `200 x15`. If these are refused, the expression is too broad and the
  admin console is about to break for everyone.

Without the control a burst of 429s proves only that SOMETHING is being refused,
which is equally consistent with having broken the API.
NOTE
