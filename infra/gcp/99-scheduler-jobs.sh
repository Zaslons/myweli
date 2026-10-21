#!/usr/bin/env bash
# The production Cloud Scheduler jobs, declared in the repo.
#
# WHY THIS FILE EXISTS. The crons used to be Render dashboard jobs, invisible to
# review — which is how the reminders came to be off without anyone noticing.
# Their Cloud Scheduler replacements were then created BY HAND, so they existed
# only in the project (docs/design/infra-gcp-migration.md §5 recorded that
# committing them was owed). A route that nothing calls is the same defect with
# a better dashboard. `test/maintenance/maintenance_wiring_test.dart` holds that
# every route under `routes/internal/cron/` has its job here.
#
# WHAT IT DOES. For each job: if it EXISTS, read it back and say whether it
# matches what is declared here (it never edits a live job — a drift is printed
# for a person to decide); if it is MISSING, print what would be created, and
# create it only with APPLY=1. So a plain run is read-only:
#
#   bash infra/gcp/99-scheduler-jobs.sh            # read back, plan
#   APPLY=1 bash infra/gcp/99-scheduler-jobs.sh    # also create what is missing
#
# THE SHAPE, copied from the two hand-made jobs as read on 2026-10-21: UTC; POST
# to https://api.myweli.com/internal/cron/<name>; a Google-signed OIDC token of
# `myweli-scheduler@` for the audience https://api.myweli.com (it must equal
# CRON_OIDC_AUDIENCE on the serving revision — infra/gcp/service.yaml); a 180 s
# attempt deadline; no retries (every cron is idempotent per tick, and the next
# tick is the retry).
#
# AFTER A CREATE, force one run and read the answer in the service's log —
# Scheduler reporting its own attempt is not evidence the route answered 200:
#
#   gcloud scheduler jobs run myweli-maintenance --location=europe-west9
#
# Staging's twins are created by 90-staging.sh (paused).
#
# Design: docs/design/infra-cron-maintenance.md §2.2, §3
set -euo pipefail

PROJECT=myweli
REGION=europe-west9
BASE=https://api.myweli.com
AUDIENCE=https://api.myweli.com
SCHEDULER_SA="myweli-scheduler@${PROJECT}.iam.gserviceaccount.com"
DEADLINE=180s

DRIFT=0

make_job() { # name schedule path
  local name="$1" schedule="$2" path="$3"
  local uri="${BASE}${path}"
  if gcloud scheduler jobs describe "$name" --location="$REGION" --project="$PROJECT" >/dev/null 2>&1; then
    local live
    live=$(gcloud scheduler jobs describe "$name" --location="$REGION" --project="$PROJECT" \
      --format='value(schedule,timeZone,httpTarget.uri,httpTarget.httpMethod,httpTarget.oidcToken.audience,httpTarget.oidcToken.serviceAccountEmail,attemptDeadline)')
    local want
    want=$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s' "$schedule" UTC "$uri" POST "$AUDIENCE" "$SCHEDULER_SA" "$DEADLINE")
    if [[ "$live" == "$want" ]]; then
      echo "    ✓ $name exists and matches"
    else
      echo "    ✗ $name exists but DIFFERS — not edited; compare and decide:"
      echo "        declared: $want"
      echo "        live:     $live"
      DRIFT=1
    fi
    return
  fi
  if [[ "${APPLY:-0}" != 1 ]]; then
    echo "    + $name is MISSING — would create: '$schedule' UTC POST $uri (APPLY=1 to create)"
    return
  fi
  gcloud scheduler jobs create http "$name" \
    --project="$PROJECT" --location="$REGION" \
    --schedule="$schedule" --time-zone=UTC \
    --uri="$uri" --http-method=POST \
    --oidc-service-account-email="$SCHEDULER_SA" \
    --oidc-token-audience="$AUDIENCE" \
    --attempt-deadline="$DEADLINE" -q
  echo "    + $name created — now force one run and read its 200 in the log"
}

echo "==> Cloud Scheduler jobs (${PROJECT}, ${REGION})"
make_job myweli-reminders     '*/15 * * * *' /internal/cron/reminders
make_job myweli-subscriptions '0 3 * * *'    /internal/cron/subscriptions
make_job myweli-maintenance   '30 3 * * *'   /internal/cron/maintenance

exit "$DRIFT"
