#!/usr/bin/env bash
# Does api.myweli.com answer, and can it still reach its database?
#
# WHY THIS EXISTS SEPARATELY FROM ERROR REPORTING. Sentry tells you the service
# threw. It cannot tell you the service is GONE — a crashed, unreachable or
# unrouted API produces no errors at all, so the dashboard stays clean while
# nothing works. Error alerting and uptime alerting answer different questions
# and only one of them catches the worst case.
#
# WHY TWO CHECKS AND NOT ONE. `/health` never touches the database. It reported
# `ok` throughout the Render outage, which is exactly why a single check on it
# would be one more thing that looks like monitoring and is not. `/providers`
# runs a real query, so it fails when Postgres is unreachable even though the
# process is fine.
#
# The pair also DIAGNOSES rather than just alarming:
#
#   /health quiet, /providers firing  → the process is up, Postgres is gone
#   both firing                       → the service itself is down
#
# which is the same reasoning the deploy workflow's verify step uses.
#
# WHY 2 REGIONS AND 5 MINUTES. Uptime checks probe from several locations; a
# single flaky one is common and must not page anyone at 3am. Requiring two
# failing locations sustained for five minutes filters that without meaningfully
# delaying a real outage.
#
# Idempotent-ish: `create` fails if the display name already exists. Delete
# first, or edit in the console — the point of this file is that the
# configuration is reviewable and reproducible, not that it re-runs cleanly.
#
# Applied 2026-08-12. Verified by querying the Monitoring API for real probe
# results rather than by these commands exiting 0:
#   api-health--JDCry3em2M:              passed=104  failed=0
#   api-providers-database-kxq3vEwoNZ4:  passed=102  failed=0
#
# Design: docs/design/observability-error-reporting.md §8.5
set -euo pipefail

PROJECT=myweli
HOST=api.myweli.com

# --- 1. Somewhere for an alert to go -----------------------------------------
# The project had NO notification channels, so any alert policy would have been
# a policy that notifies nobody — the same failure shape as everything else in
# this subsystem: configured, green and silent.
gcloud beta monitoring channels create \
  --project="${PROJECT}" \
  --display-name="Owner email" \
  --type=email \
  --channel-labels=email_address=sadreddinedaher@gmail.com \
  --description="Where production alerts go."

CHANNEL=$(gcloud beta monitoring channels list --project="${PROJECT}" \
  --filter='displayName="Owner email"' --format='value(name)')

# --- 2. The two checks --------------------------------------------------------
gcloud monitoring uptime create "api-health" \
  --project="${PROJECT}" \
  --resource-type=uptime-url \
  --resource-labels=host="${HOST}",project_id="${PROJECT}" \
  --protocol=https --path=/health --period=5 --timeout=10

gcloud monitoring uptime create "api-providers-database" \
  --project="${PROJECT}" \
  --resource-type=uptime-url \
  --resource-labels=host="${HOST}",project_id="${PROJECT}" \
  --protocol=https --path=/providers --period=5 --timeout=10

# --- 3. Alert on each ---------------------------------------------------------
# The check_id is generated at creation (display name + a random suffix), so it
# has to be read back rather than assumed.
for NAME in api-health api-providers-database; do
  CHECK_ID=$(gcloud monitoring uptime list-configs --project="${PROJECT}" \
    --format='value(name)' | grep "/${NAME}-" | sed 's|.*/||')

  case "${NAME}" in
    api-health)
      TITLE="${HOST} is not answering"
      DOC="The process is down or unreachable. /health never touches the database, so this firing ALONE means the service itself is gone; if it is quiet while the database check fires, the process is up and Postgres is not."
      ;;
    api-providers-database)
      TITLE="${HOST} cannot reach the database"
      DOC="A DB-backed route is failing. /health can report ok throughout a database outage - it did exactly that during the Render incident - so this is the check that catches a service which is technically up and completely useless."
      ;;
  esac

  cat > "/tmp/policy-${NAME}.json" <<JSON
{
  "displayName": "${TITLE}",
  "combiner": "OR",
  "conditions": [{
    "displayName": "uptime check ${CHECK_ID} failing from 2+ locations",
    "conditionThreshold": {
      "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/check_passed\" AND resource.type=\"uptime_url\" AND metric.label.check_id=\"${CHECK_ID}\"",
      "aggregations": [{
        "alignmentPeriod": "300s",
        "perSeriesAligner": "ALIGN_NEXT_OLDER",
        "crossSeriesReducer": "REDUCE_COUNT_FALSE",
        "groupByFields": ["resource.label.host"]
      }],
      "comparison": "COMPARISON_GT",
      "thresholdValue": 1,
      "duration": "300s",
      "trigger": { "count": 1 }
    }
  }],
  "notificationChannels": ["${CHANNEL}"],
  "documentation": { "content": "${DOC}", "mimeType": "text/markdown" }
}
JSON

  # CLOUDSDK_CORE_DISABLE_PROMPTS because the alpha component's install prompt
  # fires BEFORE flag parsing, so --quiet alone does not reach it.
  CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
    --project="${PROJECT}" --policy-from-file="/tmp/policy-${NAME}.json"
done

# --- 4. Prove the checks actually report --------------------------------------
# `create` exiting 0 means the API accepted the config, not that a probe ever
# ran. Wait a round, then read real results.
echo "Waiting for a probe round..."
sleep 360
curl -s -G \
  -H "Authorization: Bearer $(gcloud auth print-access-token)" \
  "https://monitoring.googleapis.com/v3/projects/${PROJECT}/timeSeries" \
  --data-urlencode 'filter=metric.type="monitoring.googleapis.com/uptime_check/check_passed" AND resource.type="uptime_url"' \
  --data-urlencode "interval.startTime=$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ)" \
  --data-urlencode "interval.endTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  | python3 -c "import json,sys,collections; d=json.load(sys.stdin); a=collections.defaultdict(lambda:[0,0]); [a[s['metric']['labels']['check_id']].__setitem__(0 if p['value']['boolValue'] else 1, a[s['metric']['labels']['check_id']][0 if p['value']['boolValue'] else 1]+1) for s in d.get('timeSeries',[]) for p in s.get('points',[])]; [print(f'{k}: passed={v[0]} failed={v[1]}') for k,v in a.items()]"
