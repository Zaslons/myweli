#!/usr/bin/env bash
# Alert the moment a cron authenticates on the LEGACY shared secret.
#
# WHY. `cron_auth.dart` tries the OIDC token first and falls back to the
# `X-Cron-Secret` header, so a fallback returns the same 200 as a success — the
# route cannot tell you which credential worked, and neither can the cron
# history. `reminders.dart` and `subscriptions.dart` therefore print
# `cron_auth_legacy` when the shared secret is what authenticated.
#
# That gate was placed on purpose and nobody queried it for five days. The
# fallback ran ~2.5 days (2026-08-12 → 2026-08-15, revisions 00013–00016),
# stopped when `-00017-p4j` deployed, and BOTH events went unnoticed — so the
# documentation kept saying the OIDC evidence was owed for two days after it
# existed. A `print` nobody reads is not evidence, it is a diary.
# Details: docs/design/infra-cron-oidc-evidence.md.
#
# WHY A LOG-BASED ALERT, NOT A METRIC + THRESHOLD. This is a should-never-happen
# event, not a rate to watch. `conditionMatchedLog` fires on the FIRST matching
# entry with no aggregation window, which is the right shape: one fallback is
# already the whole finding. A counter metric would need a threshold, and any
# threshold above zero is a decision to tolerate some silent fallbacks.
#
# BOTH SERVICES, deliberately. Production still SENDS the header, so a line there
# means OIDC verification has started failing and the fallback is covering it.
# Staging sends no header at all, so a line there means someone added one — or
# the jobs were rebuilt from production's definition by mistake.
#
# Idempotent-ish, like its siblings: `create` fails if the display name already
# exists. Delete first or edit in the console.
#
# Design: docs/design/infra-cron-oidc-evidence.md §6
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
cat > /tmp/policy-cron-auth-legacy.json <<JSON
{
  "displayName": "A cron authenticated on the LEGACY shared secret",
  "combiner": "OR",
  "conditions": [{
    "displayName": "cron_auth_legacy appeared in the logs",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"cloud_run_revision\\" AND (resource.labels.service_name=\\"myweli-api\\" OR resource.labels.service_name=\\"myweli-api-staging\\") AND textPayload:\\"cron_auth_legacy\\""
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "1800s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "A Cloud Scheduler cron authenticated with the transitional \`X-Cron-Secret\` header instead of its Google-signed OIDC token.\\n\\nOn PRODUCTION this means OIDC verification is failing and the fallback is hiding it - the request still returned 200, which is exactly why this log line exists. Check that the job's oidcToken audience still equals CRON_OIDC_AUDIENCE on the serving revision; they must match exactly.\\n\\nOn STAGING it means something added an X-Cron-Secret header to a job that is meant to carry OIDC only, or the jobs were recreated from production's definition.\\n\\nRunbook: docs/design/infra-cron-oidc-evidence.md",
    "mimeType": "text/markdown"
  }
}
JSON

CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
  --project="${PROJECT}" --policy-from-file=/tmp/policy-cron-auth-legacy.json

echo
echo "Policies now configured:"
gcloud alpha monitoring policies list --project="${PROJECT}" \
  --format='value(displayName)' | sed 's/^/  /'

cat <<'NOTE'

VERIFYING IT CAN FIRE. A log-based alert only sees entries written after it
exists, and production is currently on the OIDC path — so this policy will read
"no incidents" forever whether or not its filter is correct. That is the exact
shape of a check that cannot fire.

*** WAIT SEVERAL MINUTES AFTER CREATING THE POLICY BEFORE TESTING. ***
A newly created policy is not evaluating yet. Measured here: a trigger 58
SECONDS after creation produced the log line and NO incident, which reads
exactly like a broken filter and sent this investigation down the wrong path.
The same trigger against the same policy five hours later opened an incident in
35 seconds. Give it five minutes.

Prove it against the real code path, on staging, by authenticating a cron with
the shared secret on purpose:

  SECRET=$(gcloud secrets versions access latest --secret=STAGING_CRON_SECRET)
  URL=$(gcloud run services describe myweli-api-staging --region europe-west9 \
          --format='value(status.url)')
  curl -s -o /dev/null -w '%{http_code}\n' -X POST \
    -H "X-Cron-Secret: ${SECRET}" "${URL}/internal/cron/reminders"

That returns 200 via the fallback and prints cron_auth_legacy, which is a real
line from the real branch rather than an injected entry. It will open an incident
and send mail - that is the point.

Then confirm the incident WITHOUT the console. There is no incidents API, but
Monitoring writes every opening to Cloud Logging:

  gcloud logging read \
    'logName:"monitoring.googleapis.com%2FViolationOpenEventv1"' \
    --limit=5 --freshness=1h \
    --format='value(timestamp,labels.policy_display_name,labels.terse_message)'

That is the only programmatic proof available. Notification DELIVERY is not
logged anywhere - ViolationOpenEventv1 is the only monitoring.googleapis.com
stream this project has - so the inbox remains the ground truth for the last hop.
NOTE
