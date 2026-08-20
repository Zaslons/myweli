#!/usr/bin/env bash
#
# Make a Cloud Armor refusal VISIBLE, and alert on the first one.
#
# ## The gap
#
# Two rate-limit rules are live and enforcing (87, 89). Neither leaves a trace.
# `myweli-api-backend` has no `logConfig` at all, so load-balancer request
# logging is off — and with it off, Cloud Armor's `enforcedSecurityPolicy`
# field, which is the only record that a request was refused, is never written.
#
# Measured 2026-08-19: eight refusals were triggered against production while
# verifying rules 1000 and 1100, and a query for
# `jsonPayload.enforcedSecurityPolicy.outcome="DENY"` over the following six
# hours returned NOTHING. The rules work; the evidence does not exist.
#
# ## Why that matters more than it sounds
#
# The four-item security list ends with "revisit the Cloud Armor threshold once
# real traffic exists — with data". **That item was not blocked on traffic. It
# was blocked on an instrument.** Waiting for users does not help if nothing
# records what happens to them, so the item could never have been closed, and
# would have looked merely deferred for as long as anyone left it.
#
# And the failure it hides is the one the design already flagged as the real
# risk: **shared NAT**. A salon and its clients behind one address share a
# ceiling. If that refuses a real customer mid-booking, the customer sees an
# error, and we see nothing at all — an invisible outage for the people we are
# least able to afford losing.
#
# ## What this is, and when it stops being useful
#
# **A launch-window instrument.** Right now production has 5 users and no
# salons, so ANY deny is a probe or an attacker and the signal is unambiguous.
# Once real traffic exists the same alert becomes noisy and its meaning shifts
# from "someone is being refused" to "look at the ratio" — which is exactly the
# point at which the threshold decision becomes possible, i.e. exactly what
# item 4 was waiting for. So this alert is what CLOSES that item, and then what
# retires itself.
#
# Sample rate is 1.0 deliberately: the events worth seeing are rare, and
# sampling rare events away is how you conclude nothing is happening. Revisit
# when volume makes the cost visible, which at today's numbers it is not.
#
# Design: docs/design/backend-rate-limiting.md §6
set -euo pipefail

PROJECT="${MYWELI_GCP_PROJECT:-myweli}"
BACKEND=myweli-api-backend

# ---- 1. make the refusal observable ---------------------------------------
echo "→ enabling request logging on ${BACKEND}"
gcloud compute backend-services update "$BACKEND" --global \
  --project="$PROJECT" \
  --enable-logging \
  --logging-sample-rate=1.0

gcloud compute backend-services describe "$BACKEND" --global \
  --project="$PROJECT" --format='value(logConfig.enable,logConfig.sampleRate)' \
  | sed 's/^/  logConfig now: /'

# ---- 2. alert on the first refusal ----------------------------------------
CHANNEL=$(gcloud beta monitoring channels list --project="${PROJECT}" \
  --filter='displayName="Owner email"' --format='value(name)')
if [[ -z "${CHANNEL}" ]]; then
  echo "::error:: no 'Owner email' notification channel — run 80-uptime-checks.sh first."
  exit 1
fi

# The filter is the whole alert:
#   · `enforcedSecurityPolicy` is written ONLY when a security policy evaluated
#     the request, which is why step 1 has to come first — with logging off the
#     field never exists and this filter can never match, which reads exactly
#     like a service nobody is attacking;
#   · `outcome="DENY"` rather than any 429, because the app returns 429 too
#     (`locked_out`, `rate_limited`) and those are different events with
#     different runbooks;
#   · no service-name filter: there is one load balancer, and adding a
#     dimension that can drift is how a filter quietly stops matching.
cat > /tmp/policy-armor-deny.json <<JSON
{
  "displayName": "Cloud Armor REFUSED a request",
  "combiner": "OR",
  "enabled": true,
  "conditions": [{
    "displayName": "a rate-limit rule denied a request at the load balancer",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"http_load_balancer\\" AND jsonPayload.enforcedSecurityPolicy.outcome=\\"DENY\\""
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "3600s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "Cloud Armor refused a request at the load balancer. Two rules can do this: priority 1000, 10/min per IP on /auth/*, and priority 1100, the same on /admin/auth/.\\n\\nWHAT THIS IS NOT. The app also returns 429 - \`locked_out\` for the admin lockout, \`rate_limited\` for the per-identity limits. Those are the app refusing a caller it recognises, and they are working as designed. This alert is only the load balancer refusing an ADDRESS.\\n\\nTHE QUESTION TO ASK IS WHICH KIND. Read the log entry's remoteIp and requestUrl.\\n\\n\`gcloud logging read 'resource.type=\\"http_load_balancer\\" AND jsonPayload.enforcedSecurityPolicy.outcome=\\"DENY\\"' --limit=20 --freshness=1h --format='value(timestamp, httpRequest.remoteIp, httpRequest.requestUrl)'\`\\n\\nMany distinct addresses, or one address at high rate on /auth/ = abuse, and the rule is doing its job. Nothing to do.\\n\\nONE address, low rate, spread over minutes = almost certainly a REAL USER, and this is the case the threshold was always going to get wrong. A salon and its clients share one connection, so a per-IP ceiling hits all of them together. Raise the threshold in infra/gcp/87-rate-limit-policy.sh (or 89 for admin) and re-run it - do NOT edit the rule by hand, the next run of the script would revert it.\\n\\nWHY THIS ALERT EXISTS AT ALL. Until 2026-08-19 the load balancer wrote no request logs, so a refusal left no trace whatever - eight were triggered against production while verifying the rules and none was recorded. That is also why 'revisit the threshold once real traffic exists' could never have been done: the traffic would have arrived and told us nothing.\\n\\nRunbook: docs/design/backend-rate-limiting.md",
    "mimeType": "text/markdown"
  }
}
JSON

echo "→ creating the alert policy"
CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
  --project="${PROJECT}" --policy-from-file=/tmp/policy-armor-deny.json

# A policy created before its emitter is deployed CANNOT FIRE, and looks exactly
# like a healthy one. That is not hypothetical: it is how the identity-limit
# alert spent two hours blind on 2026-08-20. Warned, not refused - staging the
# alert just ahead of the deploy is a legitimate order, and a hard stop here
# would only push someone into creating the policy in the console instead.
bash "$(dirname "${BASH_SOURCE[0]}")/95-emitter-lag.sh" || {
  echo
  echo "::warning:: the policy was created, but see the report above - a service"
  echo "::warning:: is running code that cannot emit what it watches for. Deploy."
}

echo
echo "Policies now configured:"
gcloud alpha monitoring policies list --project="${PROJECT}" \
  --format='value(displayName)' | sed 's/^/  /'

cat <<'NOTE'

VERIFYING IT. Two separate claims, and the first must hold before the second
can be tested at all: that a refusal is now LOGGED, and that the alert MATCHES.

*** WAIT SEVERAL MINUTES AFTER CREATING THE POLICY. *** Measured on the cron
alert: a trigger 58 seconds after creation produced the log line and NO
incident, which reads exactly like a broken filter.

  # trigger a refusal — rotate the address so the APP's own 429 (locked_out at
  # five failures) cannot fire first and be mistaken for Cloud Armor's
  for i in $(seq 1 15); do
    curl -s -o /dev/null -w "%{http_code} " \
      -X POST https://api.myweli.com/admin/auth/login \
      -H 'Content-Type: application/json' \
      -d "{\"email\":\"deny-probe-$i@myweli.test\",\"password\":\"x\"}"
  done; echo

Expect 401 x10 then 429 x5. Then, one to two minutes later:

  gcloud logging read \
    'resource.type="http_load_balancer" AND jsonPayload.enforcedSecurityPolicy.outcome="DENY"' \
    --limit=5 --freshness=10m \
    --format='value(timestamp, httpRequest.remoteIp, httpRequest.requestUrl)'

An empty result here means logging did not take effect, NOT that the alert is
broken — distinguish the two before concluding anything. Then confirm the
incident:

  gcloud logging read 'logName:"monitoring.googleapis.com%2FViolationOpenEventv1"' \
    --limit=5 --freshness=1h \
    --format='value(timestamp,labels.policy_display_name)'
NOTE
