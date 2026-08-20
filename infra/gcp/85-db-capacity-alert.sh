#!/usr/bin/env bash
# Alert before the database runs out of connections.
#
# WHY THIS ONE AND NOT THE OTHER. docs/design/backend-migration-volume.md §7.4
# names two tripwires: `appointments` past ~50 000 (the migration cliff) and
# `num_backends` approaching the ceiling. Only the second is shipped here as an
# alert, and the asymmetry is deliberate — see §3 below.
#
# THE CEILING IS REAL AND CURRENT. Both instances run the `db-f1-micro` default
# of 25 `max_connections` — verified, neither carries any `databaseFlags` —
# leaving ~22 after `superuser_reserved_connections`. `database.dart` budgets
# `kMaxConnectionsPerInstance` 4 x `maxScale` 4 = 16, comfortable in steady
# state. But `maxScale` is PER REVISION, so a rollout running the draining old
# revision beside the new one can transiently reach eight instances = 32, over
# the ceiling. That is the current configuration at full scale, not a future
# problem, and raising `max_connections` on this tier was already rejected on
# evidence (database.dart: a restart on a ZONAL instance with no replica,
# against an app with no connection retry, on 0.6 GB of RAM).
#
# WHY 16, SUSTAINED FOR 10 MINUTES. 16 is the documented steady-state budget, so
# exceeding it means something is eating into the reserve. But a deploy
# legitimately exceeds it for a minute or two while the old revision drains, and
# an alert that pages on every deploy is an alert someone mutes. Ten minutes of
# sustained overage is not a rollout; it is connections that are not being
# returned.
#
# Idempotent-ish, like 80-uptime-checks.sh: `create` fails if the display name
# already exists. Delete first or edit in the console. The point of this file is
# that the configuration is reviewable, not that it re-runs cleanly.
#
# Design: docs/design/backend-migration-volume.md §7
set -euo pipefail

PROJECT=myweli

# The channel 80-uptime-checks.sh created. Read back rather than re-created — a
# second "Owner email" channel would mean some alerts notify one and some the
# other, which is worse than none because it looks complete.
CHANNEL=$(gcloud beta monitoring channels list --project="${PROJECT}" \
  --filter='displayName="Owner email"' --format='value(name)')
if [[ -z "${CHANNEL}" ]]; then
  echo "::error:: no 'Owner email' notification channel — run 80-uptime-checks.sh first."
  echo "           A policy with no channel notifies nobody, which is this"
  echo "           subsystem's signature failure: configured, green and silent."
  exit 1
fi
echo "notification channel: ${CHANNEL}"

for INSTANCE in myweli-db myweli-db-staging; do
  # Staging gets the same alert deliberately. Its whole job is to fail first, and
  # with `minScale: 0` it holds fewer connections in steady state — so if staging
  # ever sustains 16, something is genuinely leaking and production is next.
  cat > "/tmp/policy-conn-${INSTANCE}.json" <<JSON
{
  "displayName": "${INSTANCE} is running out of connections",
  "combiner": "OR",
  "enabled": true,
  "conditions": [{
    "displayName": "num_backends above the 16-connection budget for 10 minutes",
    "conditionThreshold": {
      "filter": "metric.type=\"cloudsql.googleapis.com/database/postgresql/num_backends\" AND resource.type=\"cloudsql_database\" AND resource.label.database_id=\"${PROJECT}:${INSTANCE}\"",
      "aggregations": [{
        "alignmentPeriod": "300s",
        "perSeriesAligner": "ALIGN_MAX",
        "crossSeriesReducer": "REDUCE_MAX"
      }],
      "comparison": "COMPARISON_GT",
      "thresholdValue": 16,
      "duration": "600s",
      "trigger": { "count": 1 }
    }
  }],
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "\`${INSTANCE}\` has held more than 16 Postgres backends for ten minutes. The ceiling is ~22 (db-f1-micro's default \`max_connections\` of 25, less \`superuser_reserved_connections\`), and 16 is the documented budget: kMaxConnectionsPerInstance 4 x maxScale 4 (backend/lib/src/db/database.dart).\\n\\nA deploy exceeds 16 briefly while the old revision drains. Ten minutes means connections are not being returned, or maxScale has been raised without recomputing the budget.\\n\\nDo NOT fix this by raising \`max_connections\` on this tier - that was rejected on evidence in database.dart. The fix is a tier bump, priced in docs/design/backend-migration-volume.md §7.",
    "mimeType": "text/markdown"
  }
}
JSON

  # CLOUDSDK_CORE_DISABLE_PROMPTS because the alpha component's install prompt
  # fires BEFORE flag parsing, so --quiet alone does not reach it.
  CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
    --project="${PROJECT}" --policy-from-file="/tmp/policy-conn-${INSTANCE}.json"
done

# --- Prove it exists, rather than trusting the exit code ----------------------
# The lesson from every other check in this repo: `create` exiting 0 means the
# API accepted the request. Read the policies back.
echo
echo "Policies now configured:"
gcloud alpha monitoring policies list --project="${PROJECT}" \
  --format='value(displayName)' | sed 's/^/  /'
