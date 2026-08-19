#!/usr/bin/env bash
# Alert on the email send budget — BOTH when it is about to bind, and when it
# has bound.
#
# WHY THIS EXISTS. The send budget (docs/design/backend-email-send-budget.md)
# refuses outbound mail past a per-hour ceiling. Its failure mode is completely
# silent from outside: `/auth/email/otp/request` returns 202 whether or not mail
# went out — deliberately, so a caller cannot learn whether an address exists —
# so a refused user sees a normal screen and simply never receives a code. The
# service stays healthy, the uptime checks stay green, and nothing 5xxes. The
# first signal would be a complaint, and before launch there is nobody to
# complain.
#
# TWO POLICIES, BECAUSE ONE OF THEM ARRIVES IN TIME AND THE OTHER DOES NOT.
#   · WARNING at 80% of the ceiling — every message is still going out. This is
#     the one that matters for the case we actually expect: real growth quietly
#     outrunning a number picked before launch. Acting on it costs one env var.
#   · EXHAUSTED — mail is being dropped right now. By the time this fires the
#     harm has started; it is an alarm, not a warning.
# An alert that can only fire after users have been turned away is worth having
# and is not worth *only* having.
#
# BOTH SERVICES. A mail loop in our own code is exactly the kind of bug that
# shows up in staging first — it redeploys on every merge to main. And staging's
# normal traffic comes nowhere near the warning threshold (a funnel rehearsal
# sends a handful of OTPs against a ceiling of 60), so including it costs no
# noise while making both policies testable somewhere that is not production.
#
# WHY LOG-MATCH AND NOT A METRIC. The same reason as 86-cron-auth-alert.sh:
# Cloud Monitoring has no absence-of-log condition, and a counter metric plus a
# threshold plus a window is three more numbers to get wrong. These two strings
# are printed by exactly one place in the code, and a test in
# backend/test/email/send_budget_test.dart fails if either is renamed without
# this file following — so the filter cannot quietly stop matching.
#
# NUMBERING: 87 is the Cloud Armor rate-limit policy, which landed just before
# this.
#
# NO ANGLE BRACKETS IN THE RUNBOOK TEXT. `documentation.content` is declared
# text/markdown and the notification email renders it as HTML, so a `<n>` or a
# `<cold|warm>` placeholder is parsed as a tag and DELETED before it reaches the
# reader. The first version of this file shipped that way: the sentence naming
# the log line to grep for arrived as `class= sent= ceiling=`, which is the one
# sentence a paged operator most needs. Concrete example values instead — more
# useful than placeholders anyway, and nothing can eat them. A test in
# backend/test/email/send_budget_test.dart fails if a `<` ever returns.
#
# Idempotent-ish, like its siblings: `create` fails if the display name already
# exists. Delete first or edit in the console.
#
# Design: docs/design/backend-email-send-budget.md §8
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
# Both service names are listed explicitly rather than using a prefix match,
# because `myweli-api` is a prefix of `myweli-api-staging` and a prefix filter
# would silently also match any future `myweli-api-*` service.
#
# `textPayload:` is a substring match — the lines are bare `print`s, so they
# arrive as textPayload rather than jsonPayload. No severity filter: `print`
# lands at INFO, and filtering on severity is one more way for the alert to stop
# matching if the app ever adopts a structured logger.

cat > /tmp/policy-email-budget-exhausted.json <<JSON
{
  "displayName": "Email send budget EXHAUSTED - mail is being dropped",
  "combiner": "OR",
  "conditions": [{
    "displayName": "a send was refused by the budget",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"cloud_run_revision\\" AND ${SERVICES} AND textPayload:\\"email_budget_exhausted\\""
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "1800s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "Outbound email is being REFUSED by the send budget. The log line names the class and the numbers, and reads like this: email_budget_exhausted class=cold sent=61 ceiling=60. The class is cold or warm.\\n\\nNobody outside will report this. /auth/email/otp/request returns 202 whether or not mail went out, so a refused user sees a normal screen and never receives a code.\\n\\nclass=cold - OTP mail. Either someone is hammering sign-in, or the ceiling is now too low for real traffic. Check which BEFORE raising it: count distinct recipients in the window. Many recipients, few each = an attack, and the budget is doing its job. Few recipients, many each = our own retry loop. Steady legitimate growth = raise EMAIL_BUDGET_COLD.\\n\\nclass=warm - authenticated mail: booking confirmations, subscription notices, team invitations. This is almost never an attacker, because warm sends require a session. Treat it as our bug or as real growth, and raise EMAIL_BUDGET_WARM immediately - dropping these is worse than the thing the budget prevents.\\n\\nThe ceilings are env vars on the Cloud Run service (EMAIL_BUDGET_COLD / EMAIL_BUDGET_WARM, defaults 60 / 1000 per hour). Change them in infra/gcp/service.yaml and deploy - a hand 'gcloud run services update' is reverted by the next deploy of the committed manifest.\\n\\nRunbook: docs/design/backend-email-send-budget.md",
    "mimeType": "text/markdown"
  }
}
JSON

cat > /tmp/policy-email-budget-warning.json <<JSON
{
  "displayName": "Email send budget at 80%",
  "combiner": "OR",
  "conditions": [{
    "displayName": "a class crossed 80% of its hourly ceiling",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"cloud_run_revision\\" AND ${SERVICES} AND textPayload:\\"email_budget_warning\\""
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "3600s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "A send class has used 80% of its hourly ceiling. NOTHING HAS BEEN DROPPED YET - every message in this window is still going out. This is the alert you can act on cheaply.\\n\\nThe line reads like this: email_budget_warning class=cold sent=48 ceiling=60, where the class is cold or warm. It is emitted once per class per hour, so a repeat means a new window crossed the mark again.\\n\\nIf this fires twice in a row on class=cold with a normal-looking spread of recipients, the ceiling is simply too low for current traffic - raise EMAIL_BUDGET_COLD in infra/gcp/service.yaml and deploy. If it fires with the same handful of recipients, look for a retry loop first.\\n\\nOn class=warm, raise it. Warm mail is booking confirmations and subscription notices; the warm ceiling exists to catch a loop in our own code, not to ration real customers.\\n\\nIgnoring this alert means the next one you get is the EXHAUSTED alarm, and by then users are being turned away.\\n\\nRunbook: docs/design/backend-email-send-budget.md",
    "mimeType": "text/markdown"
  }
}
JSON

for f in exhausted warning; do
  echo
  echo "creating policy: ${f}"
  CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
    --project="${PROJECT}" --policy-from-file="/tmp/policy-email-budget-${f}.json"
done

echo
echo "Policies now configured:"
gcloud alpha monitoring policies list --project="${PROJECT}" \
  --format='value(displayName)' | sed 's/^/  /'

cat <<'NOTE'

VERIFYING THEY CAN FIRE. A log-based alert only sees entries written after it
exists, so a policy whose filter is wrong reads "no incidents" forever and looks
identical to a healthy system.

*** WAIT SEVERAL MINUTES AFTER CREATING THE POLICIES BEFORE TESTING. ***
Measured on the cron alert: a trigger 58 SECONDS after creation produced the log
line and NO incident, which reads exactly like a broken filter. The same trigger
five hours later opened an incident in 35 seconds.

ONE RUN EXERCISES BOTH POLICIES, because 48 crosses the warning and 61 exhausts
the default ceiling of 60. Rotate the address on every request - which is also
the precise attack the budget exists to defeat, so the probe and the threat are
the same shape:

  URL=$(gcloud run services describe myweli-api-staging --region europe-west9 \
          --format='value(status.url)')
  for i in $(seq 1 61); do
    curl -s -o /dev/null -X POST "${URL}/auth/email/otp/request" \
      -H 'Content-Type: application/json' \
      -d "{\"email\":\"budget-probe-${i}@myweli.test\"}"
  done

RUN IT AGAINST STAGING, NOT PRODUCTION, and not only because production is the
live surface. 87-rate-limit-policy.sh puts Cloud Armor on the production load
balancer at 10 requests/minute per IP over /auth/* with a five-minute ban, so
the probe would be refused at request 11, never reach 48, print neither line,
and read exactly like two broken filters. Staging is not behind that load
balancer and the app-level limiter is not built yet, so 61 requests go through.

No mail actually leaves: the budget is reserved BEFORE the send, and the
addresses are .test, which no provider will deliver to. The identities this
leaves behind carry the .test suffix the purge script already keys on.

Confirm both incidents without the console - there is no incidents API, but
Monitoring logs every opening:

  gcloud logging read \
    'logName:"monitoring.googleapis.com%2FViolationOpenEventv1"' \
    --limit=5 --freshness=1h \
    --format='value(timestamp,labels.policy_display_name,labels.terse_message)'

Expect TWO policy names in that output. One means the other filter is wrong.
NOTE
