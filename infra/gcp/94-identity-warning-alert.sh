#!/usr/bin/env bash
#
# The other two things a per-identity limit can do, besides refuse.
#
# ## Why a warning, when the refusal is already alerted
#
# The refusal alert tells you someone was turned away. This one tells you someone
# is ABOUT to be, while they can still finish what they are doing. That is the
# same reason the send budget's 80% warning is worth more than its exhaustion
# alarm, and the pairing here is deliberately modelled on it.
#
# The two differ in cadence, and the difference is load-bearing. The refusal
# fires on EVERY refused request, because there the count is the signal - one
# line in an hour is a person, three hundred is an attacker being held. The
# warning fires ONCE per bucket per window, by an exact equality in
# `allowUnderLimit`, so `notificationRateLimit` of 3600s means one notification
# per crossing rather than a flood.
#
# ## Why the second policy, which is not a warning at all
#
# `FailOpenRateLimiter` allows the request when the limiter throws. That is the
# right choice - every real control still holds without it, and failing closed
# would turn a Postgres blip into nobody being able to book - but while it lasts
# the surface has NO per-identity ceiling. Nothing said so until now.
#
# It also explains a silence in the first policy: the warning fires on `==`, once
# per window, so if the counter advanced while the caller saw a failure, that
# window's warning is gone for good rather than late.
#
# Design: docs/design/backend-identity-rate-limits.md
set -euo pipefail

PROJECT=myweli

CHANNEL=$(gcloud beta monitoring channels list --project="${PROJECT}" \
  --filter='displayName="Owner email"' --format='value(name)')
if [[ -z "${CHANNEL}" ]]; then
  echo "::error:: no 'Owner email' notification channel - run 80-uptime-checks.sh first."
  exit 1
fi
echo "notification channel: ${CHANNEL}"

# Both services named explicitly rather than by prefix: `myweli-api` is a prefix
# of `myweli-api-staging`, so a prefix filter would silently also match any
# future `myweli-api-*`.
SERVICES='(resource.labels.service_name=\"myweli-api\" OR resource.labels.service_name=\"myweli-api-staging\")'

cat > /tmp/policy-identity-warning.json <<JSON
{
  "displayName": "A per-identity limit is CLOSE to refusing",
  "combiner": "OR",
  "conditions": [{
    "displayName": "a bucket crossed 80% of its ceiling",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"cloud_run_revision\\" AND ${SERVICES} AND textPayload:\\"rate_limit_warning bucket=\\""
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "3600s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "NOTHING HAS BEEN REFUSED YET - every request in this window is still being served. A per-identity bucket has crossed 80% of its ceiling. The line reads like this: \`rate_limit_warning bucket=book:user_abc hits=8 limit=10\`, where the bucket names the surface and the caller.\\n\\nTHIS IS THE ALERT YOU CAN ACT ON CHEAPLY. Its whole worth is being early: the person it names can still finish what they are doing. By the time the sibling alarm fires they have seen a 429 and probably given up.\\n\\nIT IS EMITTED ONCE PER BUCKET PER HOUR, so a repeat means a new window crossed the mark again - not that the same crossing is being re-announced. Count the distinct buckets in the window.\\n\\n\`gcloud logging read 'resource.type=\\"cloud_run_revision\\" AND textPayload:\\"rate_limit_warning bucket=\\"' --limit=50 --freshness=2h --format='value(timestamp,textPayload)'\`\\n\\nMANY buckets = the ceilings are too low for real behaviour, and the number is the thing to change. ONE bucket, twice in a row = one person or one script; look at what they are doing before raising anything.\\n\\nREVIEW SUBMISSION IS THE TIGHT ONE. Its ceiling is 5, so this warns at 4 and the refusal lands at 6 - it buys exactly ONE further request of notice, and on that surface both alerts will often arrive within seconds of each other. Booking warns at 8 of 10. Upload signing warns at 48 of 60 for a gallery and 32 of 40 for a review, and is the one that can warn on legitimate heavy use, because a photo-rich review signs many uploads.\\n\\nIGNORING THIS MEANS THE NEXT MAIL YOU GET IS THE REFUSAL ALERT, and by then someone has been turned away. The remediation - which ceiling to raise and where - is in that alert's runbook, so there is one copy of it.\\n\\nRunbook: docs/design/backend-identity-rate-limits.md",
    "mimeType": "text/markdown"
  }
}
JSON

cat > /tmp/policy-identity-unavailable.json <<JSON
{
  "displayName": "A per-identity limit could NOT be enforced",
  "combiner": "OR",
  "conditions": [{
    "displayName": "the limiter threw and the request was allowed through",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"cloud_run_revision\\" AND ${SERVICES} AND textPayload:\\"rate_limit_unavailable\\""
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "1800s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "THE LIMITER COULD NOT ANSWER, AND THE REQUEST WAS ALLOWED THROUGH. The line reads like this: \`rate_limit_unavailable bucket=book:user_abc\`. While this is happening, that surface has NO per-identity ceiling at all - every caller is unbounded.\\n\\nFAILING OPEN IS THE RIGHT CHOICE HERE and is not the problem. Every real control still holds without the limiter: slot uniqueness, ownership, the role gate, the role-to-purpose gate, the claim-time size check. Failing closed would turn a Postgres blip into nobody being able to book. The problem would be not KNOWING, which is what this alert exists to prevent.\\n\\n\`gcloud logging read 'resource.type=\\"cloud_run_revision\\" AND textPayload:\\"rate_limit_unavailable\\"' --limit=50 --freshness=1h --format='value(timestamp,textPayload)'\`\\n\\nA HANDFUL OF LINES = a transient pool or connection blip, and the ceilings resumed on their own. Check the database capacity alerts for the same minutes before concluding anything. A SUSTAINED STREAM = the limiter is effectively off, and the abuse ceilings this project spent real effort on are not in force.\\n\\nIT ALSO EXPLAINS A SILENCE. The 80% warning fires on an exact equality, once per bucket per window. If the counter advanced in the database but the caller was handed a failure, the warning for that window is gone for good - it does not arrive late. So a window containing these lines may be missing a warning that was genuinely earned. The refusal alert is unaffected, because it re-fires on every subsequent request.\\n\\nRunbook: docs/design/backend-identity-rate-limits.md",
    "mimeType": "text/markdown"
  }
}
JSON

for f in warning unavailable; do
  CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
    --project="${PROJECT}" --policy-from-file="/tmp/policy-identity-${f}.json"
done

echo
echo "Policies now configured:"
gcloud alpha monitoring policies list --project="${PROJECT}" \
  --format='value(displayName)' | sed 's/^/  /'

cat <<'NOTE'

VERIFYING THEM. A log-based alert only sees entries written after it exists, so a
policy whose filter is wrong reads "no incidents" forever and looks identical to
a service nobody is straining.

*** WAIT SEVERAL MINUTES AFTER CREATING A POLICY BEFORE TESTING. ***
Measured on the cron alert: a trigger 58 seconds after creation produced the log
line and NO incident.

ONE RUN EXERCISES THE WARNING AND THE REFUSAL, because 12 bookings against a
ceiling of 10 crosses warnAt=8 at request 8 and refuses at 11. Trigger it on
STAGING, where a token can be minted through the Q1b seam:

  for i in $(seq 1 12); do
    curl -s -o /dev/null -w "%{http_code} " -X POST "$URL/appointments"       -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json'       -d '{"providerId":"p-none","serviceIds":["s1"],"appointmentDateTime":"2026-09-01T10:00:00.000Z"}'
  done; echo

Expect 404 x10 then 429. Then:

  gcloud logging read 'logName:"monitoring.googleapis.com%2FViolationOpenEventv1"'     --limit=5 --freshness=1h     --format='value(timestamp,labels.policy_display_name)'

EXPECT TWO POLICY NAMES IN THAT OUTPUT - the warning and the refusal. One name
means the other filter is wrong, and that is the whole point of triggering both
with a single run.

THE UNAVAILABLE POLICY CANNOT BE TRIGGERED THIS WAY, and should not be: it needs
the limiter to throw. Do not take the database down to test it. Its filter is the
same shape as the two proven ones, and the string is pinned by a test.
NOTE
