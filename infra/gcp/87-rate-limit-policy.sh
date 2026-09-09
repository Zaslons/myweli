#!/usr/bin/env bash
#
# RETIRED 2026-09-09 by docs/design/infra-cloudflare-front-door.md — kept as
# the launch-time re-application path (LAUNCH.md §6.5). Re-running it recreates
# a billable resource (a Cloud Armor policy, ~$5/month, plus ~$1/month per
# rule — and it needs the load balancer of `70` to attach to). Do not run
# without the owner's word. What this rule did is now done twice over: by the
# app's per-IP limiter behind the origin gate (10/minute, the authoritative
# bound) and by a Cloudflare rate-limiting rule at the edge (10 per 10 s).
#
# Per-IP rate limiting at the load balancer (Cloud Armor).
#
# ## What this closes
#
# Measured 2026-08-18 against staging, and it is the reason LAUNCH.md §4's
# "verified against a real hostile pattern" could not be ticked:
#
#   · brute-forcing ONE identity is bounded — 5 wrong codes then `otp_locked`,
#     and 4 requests then `otp_resend_limit`. Those live in Postgres, so they
#     hold across instances. They are correct and complete for what they defend.
#   · ROTATING the identity was completely unbounded: 60/60 accepted, 15 in
#     flight, **23 accepted OTP requests per second from one client**.
#
# On production that is 23 real emails a second from `no-reply@myweli.com` to
# addresses an attacker picks. The cost is not the Resend bill — it is mass
# unsolicited mail from the domain we launch on, which is how a domain gets
# blacklisted before it has users.
#
# ## Why HERE and not only in the app
#
# **No longer true as of 2026-09-09** — kept as the reasoning that held while
# the load balancer existed. Production ingress was
# `internal-and-cloud-load-balancing` and the `run.app` URL 404ed, so the LB
# was the ONLY way in and a policy here could not be walked around. Today
# ingress is `all`, the direct door is closed by the origin gate instead, and
# the un-bypassable per-IP bound is the app's limiter keyed on
# `CF-Connecting-IP` behind that gate (infra-cloudflare-front-door.md §5.2).
# The rest of the argument stands: a policy at the edge throttles before the
# request reaches the service, bounds volumetric load rather than only abuse,
# and costs no per-request database write — which is what the Cloudflare edge
# rule now does. The app-level limiter (docs/design/backend-rate-limiting.md
# §2, layer 2) was defence in depth for staging and local runs when this was
# written; it is now the authoritative layer on production.
#
# ## The threshold
#
# 10 requests/minute per IP on `/auth/*` (owner decision). A person asks for an
# OTP once, twice if it did not arrive. That is generous for a human and removes
# ~99% of what was measured.
#
# **Shared NAT is the known false-positive risk** — a salon and its clients on
# one connection share an address. Run with `PREVIEW=1` first if you want to see
# what real traffic does before anything is refused; the rule then logs and
# allows.
#
# Design: docs/design/backend-rate-limiting.md
set -euo pipefail

PROJECT="${MYWELI_GCP_PROJECT:-myweli}"
POLICY=myweli-api-rate-limit
BACKEND=myweli-api-backend
PREVIEW="${PREVIEW:-0}"

# ---- the backend must exist, and must not already be protected ------------
CURRENT=$(gcloud compute backend-services describe "$BACKEND" --global \
  --project="$PROJECT" --format='value(securityPolicy)' 2>/dev/null || true)
if [[ -n "$CURRENT" ]]; then
  echo "::error:: $BACKEND already has a security policy: $CURRENT"
  echo "          Edit that one rather than attaching a second."
  exit 1
fi

if ! gcloud compute security-policies describe "$POLICY" --project="$PROJECT" \
     >/dev/null 2>&1; then
  echo "→ creating policy $POLICY"
  gcloud compute security-policies create "$POLICY" --project="$PROJECT" \
    --description="Per-IP rate limiting. docs/design/backend-rate-limiting.md"
else
  echo "→ policy $POLICY already exists; adding/refreshing the rule"
fi

# ---- the rule -------------------------------------------------------------
# `enforce-on-key=IP` is the whole point: the default key is ALL traffic, which
# would throttle every caller together and turn a 10/minute ceiling into a
# service-wide outage.
ACTION=$([[ "$PREVIEW" == "1" ]] && echo "--preview" || echo "")

gcloud compute security-policies rules create 1000 \
  --project="$PROJECT" \
  --security-policy="$POLICY" \
  --description="auth routes: 10/min per IP (measured attack: 1380/min)" \
  --expression="request.path.startsWith('/auth/')" \
  --action=rate-based-ban \
  --rate-limit-threshold-count=10 \
  --rate-limit-threshold-interval-sec=60 \
  --ban-duration-sec=300 \
  --conform-action=allow \
  --exceed-action=deny-429 \
  --enforce-on-key=IP \
  $ACTION

echo "→ attaching $POLICY to $BACKEND"
gcloud compute backend-services update "$BACKEND" --global \
  --project="$PROJECT" --security-policy="$POLICY"

cat <<'NOTE'

VERIFYING IT. A policy that exists is not a policy that refuses — and a rule
whose expression never matches looks identical to a healthy service.

  # should be refused after ~10 in a minute
  for i in $(seq 1 15); do
    curl -s -o /dev/null -w "%{http_code} " \
      -X POST https://api.myweli.com/auth/email/otp/request \
      -H 'content-type: application/json' \
      -d "{\"email\":\"rl-probe-$i@example.test\"}"
  done; echo

Expect 202s then 429s. If every one is a 202, the EXPRESSION did not match —
check the path prefix before believing the policy works.

And run the control: the same burst against `/providers` must NOT be refused,
or the rule is matching more than it claims.

In PREVIEW=1 mode nothing is refused by design; look at the policy's logs
instead:

  gcloud logging read \
    'resource.type=http_load_balancer AND jsonPayload.enforcedSecurityPolicy.name="myweli-api-rate-limit"' \
    --project=myweli --limit=20 --freshness=1h
NOTE
