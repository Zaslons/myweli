#!/usr/bin/env bash
#
# Alert when the web rebuild hook FAILS.
#
# ## Why this exists rather than a note in a document
#
# The web's `/[slug]` route sets `dynamicParams = false` - the only mechanism that
# makes Next serve a real 404 in the HTML instead of a 44-character shell - so the
# set of salon slugs is fixed at BUILD time. The backend therefore asks Vercel to
# rebuild whenever a salon is created, suspended or restored.
#
# Every link in that chain is verified EXCEPT one: nothing has proven that Cloud
# Run can reach Vercel, because production holds zero salons and there is nothing
# to change. The first real salon exercises it.
#
# The notifier **fails open** by design: an unreachable hook is logged and the
# salon is created anyway, because refusing a correct write over a build hook
# would be a self-inflicted outage. That is the right behaviour and it is exactly
# what makes the failure INVISIBLE - the operator sees a salon created, the
# public page 404s, and nothing connects the two.
#
# So the thing that must not be missed becomes an alert rather than a sentence.
# A deadline in a document is a wish; this fires.
#
# Design: docs/design/backend-web-rebuild-hook.md
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
# prefix of `myweli-api-staging`. Staging is not supposed to hold the hook at all
# (`service_files_test.dart` pins that), so a line from there is itself a finding.
#
# `textPayload:` because the line is a bare `print`, which lands at INFO. No
# severity filter, for the same reason as the other log alerts here: it is one
# more way for the alert to stop matching if the app ever adopts a structured
# logger.

cat > /tmp/policy-rebuild-hook.json <<JSON
{
  "displayName": "The web rebuild hook FAILED",
  "combiner": "OR",
  "enabled": true,
  "conditions": [{
    "displayName": "a salon changed and Vercel could not be reached",
    "conditionMatchedLog": {
      "filter": "resource.type=\\"cloud_run_revision\\" AND ${SERVICES} AND textPayload:\\"site_rebuild FAILED\\""
    }
  }],
  "alertStrategy": {
    "notificationRateLimit": { "period": "3600s" },
    "autoClose": "86400s"
  },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "A salon was created, suspended or restored, and the backend could not ask Vercel to rebuild. The line reads like this: \`site_rebuild FAILED reason=salon.created error=SocketException\`.\\n\\nWHAT IS ACTUALLY BROKEN FOR A USER. The web prebuilds the set of salon slugs, because \`/[slug]\` sets \`dynamicParams = false\` - that is what makes an unknown slug serve a real 404 instead of a 44-character blank page. A salon whose page was never built therefore 404s until the next deploy. For a salon that just signed up, their public page does not exist.\\n\\nTHE WRITE ITSELF SUCCEEDED. The notifier fails OPEN on purpose: the salon was created or suspended correctly, and refusing a correct write because a build hook was unreachable would be a self-inflicted outage. Nothing needs undoing. What is missing is only the rebuild.\\n\\nIMMEDIATE FIX, AND IT IS SAFE. Trigger a build by any normal means - push to main, or press Redeploy in Vercel. The build reads the current salon list, so it picks up everything that happened while the hook was failing. There is no queue to drain and no event to replay.\\n\\nTHEN FIND OUT WHY. Read the error text on the log line.\\n\\n\`gcloud logging read 'resource.type=\\"cloud_run_revision\\" AND textPayload=~\\"site_rebuild (sent|FAILED|skipped)\\"' --limit=20 --freshness=6h --format='value(timestamp,textPayload)'\`\\n\\nA CONNECTION ERROR means Cloud Run could not reach \`api.vercel.com\`. This is the hop that has never been exercised - production had zero salons when the hook was configured, so the first real salon is the first test. Check egress from the service.\\n\\nA 4xx STATUS means the hook URL is wrong or was deleted in Vercel. Recreate it under Settings then Git then Deploy Hooks, and add a new version of the \`WEB_DEPLOY_HOOK_URL\` secret. Do not paste the URL anywhere else: anyone holding it can trigger unlimited paid builds.\\n\\nIF THE LINE SAYS \`skipped\` RATHER THAN \`FAILED\`, that is the 60 second cooldown and it is not a fault. Rapid changes deliberately trigger one build, and a dropped event is safe because the next build reads the current state.\\n\\nSILENCE IS NOT SUCCESS. A successful hook logs \`site_rebuild sent reason=salon.created status=201\`. If a salon changed and NEITHER line appears, the secret is not mounted and the no-op notifier is wired instead - check the boot log for a \`WEB_DEPLOY_HOOK_URL\` warning and confirm the mount on the serving revision.\\n\\nRunbook: docs/design/backend-web-rebuild-hook.md",
    "mimeType": "text/markdown"
  }
}
JSON

CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
  --project="${PROJECT}" --policy-from-file=/tmp/policy-rebuild-hook.json

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
