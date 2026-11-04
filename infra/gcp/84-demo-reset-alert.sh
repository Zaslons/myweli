#!/usr/bin/env bash
#
# Alert when the weekly demo reset is REFUSED.
#
# ## Why this exists rather than a note in a document
#
# The App Store reviewer signs in to a shared demo salon. Every seventh day the
# maintenance cron restores it (the profile, the agenda, the clients, the offer)
# - but only after checking, on its own, that the salon's OWNER row is still the
# demo identity. When it is not, the reset refuses, prints one line and carries
# on: the cron answers 200 and nothing else moves.
#
# That refusal is the demo identity LOST - deleted out of band, or its owner row
# changed - and the next reviewer meets a salon that no longer resets, or no
# account at all. Until 2026-10-21 the cron answered `demoReset: false` for both
# "not the day" and "refused", so nothing told the two apart; it now says
# `refused:not_demo_owned` (docs/design/backend-integrity-batch6.md §2.9), and
# this policy turns the line into a message. Owner decision 22: an alert now,
# no automatic re-creation.
#
# Design: docs/design/backend-integrity-batch6.md §2.9 ·
#         docs/design/backend-demo-review-account.md
set -euo pipefail

PROJECT=myweli

CHANNEL=$(gcloud beta monitoring channels list --project="${PROJECT}" \
  --filter='displayName="Owner email"' --format='value(name)')
if [[ -z "${CHANNEL}" ]]; then
  echo "::error:: no 'Owner email' notification channel - run 80-uptime-checks.sh first."
  exit 1
fi
echo "notification channel: ${CHANNEL}"

SERVICES='(resource.labels.service_name=\"myweli-api\" OR resource.labels.service_name=\"myweli-api-staging\")'
# Both services named explicitly rather than by prefix, because `myweli-api` is a
# prefix of `myweli-api-staging`. A refusal on staging is a finding too: its demo
# salon is the curated copy's twin.
#
# `textPayload:` because the line is a bare `print`, which lands at INFO. No
# severity filter, for the same reason as the other log alerts here.

cat > /tmp/policy-demo-reset.json <<JSON
{
  "displayName": "The weekly demo reset was REFUSED",
  "combiner": "OR",
  "enabled": true,
  "conditions": [{
    "displayName": "the demo salon's owner is no longer the demo identity",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"cloud_run_revision\\" AND ${SERVICES} AND textPayload:\\"demo_reset REFUSED\\""
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "3600s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "The weekly reset of the App Store demo salon refused to run. The line reads like this: \`demo_reset REFUSED provider=... cause=not_demo_owned\`.\\n\\nWHAT IS ACTUALLY BROKEN. The reset only restores a salon whose OWNER row is the demo identity, and it checks that on its own every time. A refusal means the demo identity is LOST: its account was deleted out of band (the app refuses the deletion since 2026-10-13), or the salon's owner row changed. The next reviewer meets a salon that no longer resets - reviewer junk stays, the agenda stops moving - or cannot sign in at all.\\n\\nNOTHING WAS WRITTEN. The refusal happens before any restore; the salon is as the last reviewer left it. The daily cron still answers 200, with \`demoReset\` set to \`refused:not_demo_owned\`.\\n\\nCONFIRM. Read the recent lines:\\n\\n\`gcloud logging read 'resource.type=\\"cloud_run_revision\\" AND textPayload=~\\"demo_reset (ran|REFUSED|captured)\\"' --limit=20 --freshness=8d --format='value(timestamp,textPayload)'\`\\n\\nThen try the demo sign-in in the Pro app with the published review credentials. A login that answers « Compte introuvable » is a deleted identity.\\n\\nRECOVER (there is no automatic re-creation - owner decision 22). Re-register the demo address through the Pro app, re-curate the salon as « Maison Nala » with its logo and catalogue, then recapture the snapshot the reset restores with \`POST /admin/demo/snapshot\` from the admin console. The steps and the assets are in the runbook below.\\n\\nRunbook: docs/design/backend-demo-review-account.md (« If the demo identity is ever lost »)",
    "mimeType": "text/markdown"
  }
}
JSON

CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
  --project="${PROJECT}" --policy-from-file=/tmp/policy-demo-reset.json

# A policy created before its emitter is deployed CANNOT FIRE, and looks exactly
# like a healthy one.
bash "$(dirname "${BASH_SOURCE[0]}")/95-emitter-lag.sh" || {
  echo
  echo "::warning:: the policy was created, but see the report above - a service"
  echo "::warning:: is running code that cannot emit what it watches for. Deploy."
}

echo
echo "Policies now configured:"
gcloud alpha monitoring policies list --project="${PROJECT}" \
  --format='value(displayName)' | sed 's/^/  /'
