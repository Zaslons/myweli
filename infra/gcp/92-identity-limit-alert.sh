#!/usr/bin/env bash
#
# Alert when a per-identity limit REFUSES someone.
#
# ## Why an alert rather than a probe
#
# The identity limits (booking, review submission, upload signing) were verified
# against the deployed STAGING service with a control — identity A exhausted,
# identity B untouched in the same window. They cannot be verified the same way
# on production, and that is deliberate rather than an oversight: the probe needs
# an access token, the only way to mint one without a real account is the Q1b
# OTP-disclosure seam, and that seam is mounted on staging and **not** on
# production. A standing disclosure path on the real thing is a permanent
# invitation, and `service_files_test.dart` pins its absence.
#
# **Reintroducing the seam to make testing easier would trade a real security
# property for evidence.** So production gets the other half of the pair: it
# cannot be provoked, but it can be OBSERVED.
#
# ## The chain of evidence this completes
#
# 1. **Behaviour** — proven on staging, with the control that distinguishes a
#    per-identity limit from an outage.
# 2. **Identity of the artifact** — production runs the same image DIGEST that
#    staging rehearsed, which the deploy verifies and the `commit` revision label
#    records.
# 3. **Presence** — this alert. The moment the limit does anything in
#    production, we hear about it.
#
# Each link is weak alone. Together they are the strongest thing available
# without weakening the service to observe it.
#
# ## And the case that actually matters is a LEGITIMATE refusal
#
# An attacker being refused is the limit working and needs no one's attention.
# A real person refused mid-booking sees a 429 and gives up, and without this
# line we would learn about it from a complaint, or never. That asymmetry is why
# the log fires on EVERY refusal rather than once per window: one line in an hour
# is a person who hit a ceiling; three hundred is an attacker being held.
#
# Design: docs/design/backend-identity-rate-limits.md §8.2
set -euo pipefail

PROJECT=myweli

CHANNEL=$(gcloud beta monitoring channels list --project="${PROJECT}" \
  --filter='displayName="Owner email"' --format='value(name)')
if [[ -z "${CHANNEL}" ]]; then
  echo "::error:: no 'Owner email' notification channel — run 80-uptime-checks.sh first."
  exit 1
fi
echo "notification channel: ${CHANNEL}"

SERVICES='(resource.labels.service_name=\"myweli-api\" OR resource.labels.service_name=\"myweli-api-staging\")'
# Both services listed explicitly rather than by prefix, because `myweli-api` is
# a prefix of `myweli-api-staging` and a prefix filter would silently also match
# any future `myweli-api-*`.
#
# `textPayload:` because the line is a bare `print`. No severity filter: `print`
# lands at INFO, and filtering on severity is one more way for the alert to stop
# matching if the app ever adopts a structured logger.
#
# NOTE the string is `rate_limited`, which is also the wire error code — the two
# are deliberately the same word, so an operator grepping either finds both.

cat > /tmp/policy-identity-limit.json <<JSON
{
  "displayName": "A per-identity limit REFUSED a request",
  "combiner": "OR",
  "enabled": true,
  "conditions": [{
    "displayName": "booking, review or upload signing was refused",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"cloud_run_revision\\" AND ${SERVICES} AND textPayload:\\"rate_limited bucket=\\""
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "3600s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "A per-identity rate limit refused a request. The line reads like this: \`rate_limited bucket=book:user_abc hits=11 limit=10\`, where the bucket names the surface and the caller.\\n\\nWHY THIS ALERT EXISTS. These limits were verified on staging with a control, and CANNOT be verified the same way on production: the probe needs an access token, and the only way to mint one without a real account is the Q1b seam, which is deliberately absent from production. So production is observed rather than probed. This line is the only signal there will ever be that the limit did something.\\n\\nTHE QUESTION TO ASK IS WHO WAS REFUSED. Count the distinct buckets in the window.\\n\\n\`gcloud logging read 'resource.type=\\"cloud_run_revision\\" AND textPayload:\\"rate_limited bucket=\\"' --limit=50 --freshness=1h --format='value(timestamp,textPayload)'\`\\n\\nMANY buckets, or one bucket at high rate = abuse, and the limit is doing its job. Nothing to do.\\n\\nONE bucket, a handful of lines, spread over minutes = almost certainly a REAL USER who hit a ceiling, and that is the case worth acting on. They saw a 429 and probably gave up. Raise the matching \`LIMIT_*\` in \`infra/gcp/service.yaml\` and deploy - \`LIMIT_BOOKING\`, \`LIMIT_REVIEW_SUBMIT\`, or one of the \`LIMIT_SIGN_*\` set. The defaults they override live in \`kDefaultIdentityLimits\` in \`backend/lib/src/security/identity_limits.dart\`.\\n\\nA console hand-edit DOES work, and is still the wrong move: it needs \`--container app\` because this service runs a cloudsql-proxy sidecar, and the deploy uses \`services replace\`, so the next deploy reverts it. Change the manifest and the number an operator reads is the number in force.\\n\\nWHICH SURFACE. book: = POST /appointments (10/hour). review: = POST /appointments/{id}/review (5/hour, the most expensive per request). sign:PURPOSE: = POST /uploads/sign (10 to 60 by purpose; signReview is deliberately high because a review carries up to six photos and two generous limits can otherwise compose into a lockout).\\n\\nNOTE the app also returns 429 for \`locked_out\`, which is the ADMIN login lockout and a different mechanism entirely. And Cloud Armor returns 429 at the load balancer, whose alert is separate. Three different 429s, three different runbooks.\\n\\nRunbook: docs/design/backend-identity-rate-limits.md",
    "mimeType": "text/markdown"
  }
}
JSON

CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
  --project="${PROJECT}" --policy-from-file=/tmp/policy-identity-limit.json

echo
echo "Policies now configured:"
gcloud alpha monitoring policies list --project="${PROJECT}" \
  --format='value(displayName)' | sed 's/^/  /'

cat <<'NOTE'

VERIFYING IT. A log-based alert only sees entries written after it exists, so a
policy whose filter is wrong reads "no incidents" forever and looks identical to
a service nobody is attacking.

*** WAIT SEVERAL MINUTES AFTER CREATING THE POLICY BEFORE TESTING. ***
Measured on the cron alert: a trigger 58 seconds after creation produced the log
line and NO incident.

Trigger it on STAGING, where a token can be minted through the Q1b seam. Eleven
bookings exhaust the ceiling of ten; the provider need not exist, because the
limit is consumed BEFORE the lookup - which is itself the "count attempts, not
successes" property, observable here rather than argued:

  URL=$(gcloud run services describe myweli-api-staging --region europe-west9 \
          --format='value(status.url)')
  S=$(gcloud secrets versions access latest --secret=STAGING_SMOKE_OTP_SECRET)
  # request + verify an OTP for a .test identity, then:
  for i in $(seq 1 12); do
    curl -s -o /dev/null -w "%{http_code} " -X POST "$URL/appointments" \
      -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
      -d '{"providerId":"p-none","serviceIds":["s1"],"appointmentDateTime":"2026-09-01T10:00:00.000Z"}'
  done; echo

Expect 404 x10 then 429. Then confirm the incident - there is no incidents API,
but Monitoring logs every opening:

  gcloud logging read 'logName:"monitoring.googleapis.com%2FViolationOpenEventv1"' \
    --limit=5 --freshness=1h \
    --format='value(timestamp,labels.policy_display_name)'
NOTE
