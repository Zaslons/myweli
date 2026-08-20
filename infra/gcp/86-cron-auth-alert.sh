#!/usr/bin/env bash
# Alert when a cron call is REFUSED.
#
# WHAT THIS REPLACED, AND WHY. Until 2026-08-18 this file alerted on
# `cron_auth_legacy` — the log line the routes printed when a cron authenticated
# on the transitional `X-Cron-Secret` header instead of its OIDC token. That
# header is now retired (docs/design/infra-cron-oidc-evidence.md §8), the branch
# that printed the line is deleted, and so the old policy could never fire again.
# A permanently-inert alert is worse than none, because it looks like coverage.
#
# THE FAILURE MODE MOVED. `cron_auth.dart` used to fall through to the secret
# when OIDC verification failed, precisely so a misconfigured audience could not
# take the crons down. With the fallback gone it fails closed: an audience that
# stops matching `CRON_OIDC_AUDIENCE` — a redeploy, a changed run.app hostname,
# a rotated service account — turns every cron into a 403 and the reminders
# simply stop. Nothing else would notice: the service stays healthy, the uptime
# checks stay green, and Scheduler keeps reporting its own attempts as made.
#
# So the alert now watches for what that looks like from the receiving end: any
# request to `/internal/cron/*` that does not return 2xx.
#
# WHY NOT "no successful run in N minutes". That would also catch a paused or
# deleted job, which is strictly more coverage — but Cloud Monitoring has no
# absence-of-log condition, so it needs a counter metric plus a threshold plus a
# window, and every one of those is a number to get wrong. A 4xx/5xx on a route
# only Cloud Scheduler can reach is unambiguous and fires on the first one.
# Recorded as the known gap: a job that stops running entirely is NOT covered.
#
# BOTH SERVICES. Staging is where a broken audience should surface first — it
# redeploys on every merge to main, and its audience is a `*.run.app` hostname
# that a service recreation would change.
#
# Idempotent-ish, like its siblings: `create` fails if the display name already
# exists. Delete first or edit in the console.
#
# Design: docs/design/infra-cron-oidc-evidence.md §8
set -euo pipefail

PROJECT=myweli

CHANNEL=$(gcloud beta monitoring channels list --project="${PROJECT}" \
  --filter='displayName="Owner email"' --format='value(name)')
if [[ -z "${CHANNEL}" ]]; then
  echo "::error:: no 'Owner email' notification channel — run 80-uptime-checks.sh first."
  exit 1
fi
echo "notification channel: ${CHANNEL}"

# The filter is the whole alert, so it is worth reading carefully:
#   · `textPayload:` is a substring match — the line is a bare `print`, so it
#     arrives as textPayload rather than structured jsonPayload;
#   · both service names are listed explicitly rather than using a prefix match,
#     because `myweli-api` is a prefix of `myweli-api-staging` and a prefix
#     filter would silently also match any future `myweli-api-*` service;
#   · no severity filter. The line is printed at INFO (it is `print`), and
#     filtering on severity is one more way for the alert to stop matching if the
#     app ever switches to a structured logger.
cat > /tmp/policy-cron-refused.json <<JSON
{
  "displayName": "A cron call was REFUSED",
  "combiner": "OR",
  "enabled": true,
  "conditions": [{
    "displayName": "a request to /internal/cron/* did not return 2xx",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"cloud_run_revision\\" AND (resource.labels.service_name=\\"myweli-api\\" OR resource.labels.service_name=\\"myweli-api-staging\\") AND httpRequest.requestUrl:\\"/internal/cron/\\" AND httpRequest.status>=400"
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "1800s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "A request to /internal/cron/* was refused. Since the transitional X-Cron-Secret fallback was retired (2026-08-18) the OIDC token is the ONLY way in, so a 403 here means the crons have stopped - reminders are not being dispatched and nobody else will notice, because the service is healthy and the uptime checks are green.\\n\\nFirst check: the Scheduler job's oidcToken.audience must equal \`CRON_OIDC_AUDIENCE\` on the SERVING revision, exactly. Compare all three - the manifest, the running service, and the job.\\n\\n\`gcloud scheduler jobs describe myweli-reminders --location europe-west9 --format='value(httpTarget.oidcToken.audience)'\`\\n\\n\`gcloud run services describe myweli-api --region europe-west9 --format=json | grep -A1 CRON_OIDC_AUDIENCE\`\\n\\nA 404 instead means \`CRON_OIDC_AUDIENCE\` or \`CRON_SERVICE_ACCOUNT\` is unset on the revision, so the route does not exist at all.\\n\\nRunbook: docs/design/infra-cron-oidc-evidence.md",
    "mimeType": "text/markdown"
  }
}
JSON

CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
  --project="${PROJECT}" --policy-from-file=/tmp/policy-cron-refused.json

echo
echo "Policies now configured:"
gcloud alpha monitoring policies list --project="${PROJECT}" \
  --format='value(displayName)' | sed 's/^/  /'

cat <<'NOTE'

VERIFYING IT CAN FIRE. A log-based alert only sees entries written after it
exists, so a policy whose filter is wrong reads "no incidents" forever and looks
identical to a healthy system.

*** WAIT SEVERAL MINUTES AFTER CREATING THE POLICY BEFORE TESTING. ***
Measured: a trigger 58 SECONDS after creation produced the log line and NO
incident, which reads exactly like a broken filter. The same trigger five hours
later opened an incident in 35 seconds.

The old recipe for this file - send an X-Cron-Secret header - CANNOT work any
more, because that is the whole point of the change: the header is refused. Use
that refusal instead, which is now the thing being watched:

  URL=$(gcloud run services describe myweli-api-staging --region europe-west9 \
          --format='value(status.url)')
  curl -s -o /dev/null -w '%{http_code}\n' -X POST "${URL}/internal/cron/reminders"

An unauthenticated POST returns 403 and is logged as a 4xx on that route, which
is exactly the shape a broken OIDC audience produces. Confirm the incident
without the console - there is no incidents API, but Monitoring logs every
opening:

  gcloud logging read \
    'logName:"monitoring.googleapis.com%2FViolationOpenEventv1"' \
    --limit=5 --freshness=1h \
    --format='value(timestamp,labels.policy_display_name,labels.terse_message)'

Notification DELIVERY is not logged anywhere, but it was confirmed by hand on
2026-08-17: the mail arrived from alerting-noreply@google.com in the same second
the incident opened.
NOTE
