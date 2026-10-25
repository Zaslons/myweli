#!/usr/bin/env bash
#
# The two things api.myweli.com's uptime checks already measure and nothing
# watched: the certificate it serves, and how long it takes to answer.
#
# ## Why
#
# `80-uptime-checks.sh` created both checks WITHOUT `--validate-ssl`, so a check
# passed against an expired, revoked or wrong-host certificate — the browsers
# and both apps refuse it, the probe did not — and nothing alerted on the
# certificate's days left, which the checks did record (990 points in the hour before the switch, read from the Monitoring API on 2026-10-25;
# this header first said the metric was never written, which was false). The
# certificate is Cloudflare's since the
# front door moved there (2026-10-07) and renews itself; this is the alarm for
# the day it does not, two weeks before the apps stop connecting.
#
# And a service answering in nine seconds passes every check: up, slow, and
# losing every user who waits for a booking to load. The latency alert is the
# mean across probe regions, so one slow region pages nobody.
#
# Error-rate thresholds stay out, on purpose: with no real traffic there is no
# baseline, and a threshold would be a guess (observability-error-reporting.md
# §8.2). Alerts go where the others go — the owner's e-mail, and Sentry's own
# push for errors (decision 34).
#
# Run by hand, after asking: it changes the cloud. Not re-runnable as is —
# `policies create` makes a second copy; delete the two policies first.
#
# Design: docs/design/hygiene-batch9.md §2.3 (B9.4)
set -euo pipefail

PROJECT=myweli
HOST=api.myweli.com

CHANNEL=$(gcloud beta monitoring channels list --project="${PROJECT}" \
  --filter='displayName="Owner email"' --format='value(name)')
if [[ -z "${CHANNEL}" ]]; then
  echo "::error:: no 'Owner email' notification channel - run 80-uptime-checks.sh first."
  exit 1
fi
echo "notification channel: ${CHANNEL}"

# --- 1. Validate the certificate on both checks --------------------------------
# In place: the checks exist (80), and their ids carry a random suffix, so they
# are read back by display name. A function, not a top-level loop: the runbook
# sync (policy-bodies.sh) replays a `for` that precedes a policy body, and must
# never replay these updates.
validate_ssl() {
  local name=$1 id
  id=$(gcloud monitoring uptime list-configs --project="${PROJECT}" \
    --format='value(name)' | grep "/${name}-" | sed 's|.*/||')
  if [[ -z "${id}" ]]; then
    echo "::error:: no uptime check ${name} - run 80-uptime-checks.sh first."
    exit 1
  fi
  gcloud monitoring uptime update "${id}" --project="${PROJECT}" \
    --validate-ssl=true
  echo "certificate validation on: ${name} (${id})"
}
validate_ssl api-health
validate_ssl api-providers-database

# --- 2. The certificate expires within 14 days -------------------------------
# Both checks probe the same host, so the same certificate: the minimum across
# them and their regions is the one number that matters.
cat > /tmp/policy-tls-expiry.json <<JSON
{
  "displayName": "${HOST}: certificate expires within 14 days",
  "combiner": "OR",
  "enabled": true,
  "conditions": [{
    "displayName": "days left on the certificate ${HOST} serves",
    "conditionThreshold": {
      "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/time_until_ssl_cert_expires\" AND resource.type=\"uptime_url\" AND resource.label.host=\"${HOST}\"",
      "aggregations": [{
        "alignmentPeriod": "3600s",
        "perSeriesAligner": "ALIGN_MIN",
        "crossSeriesReducer": "REDUCE_MIN",
        "groupByFields": ["resource.label.host"]
      }],
      "comparison": "COMPARISON_LT",
      "thresholdValue": 14,
      "duration": "0s",
      "trigger": { "count": 1 }
    }
  }],
  "alertStrategy": { "autoClose": "86400s" },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "The certificate that api.myweli.com presents expires in less than 14 days. When it does, both apps and every browser refuse to connect - the whole product stops, and nothing else alerts on it until it has.\\n\\nWHO SERVES IT. Since 2026-10-07 the front door is a Cloudflare Worker, so the certificate is Cloudflare's edge certificate for the zone, and it renews itself. This firing means the renewal did not happen. Look in the Cloudflare dashboard, under SSL/TLS then Edge Certificates, for the certificate covering api.myweli.com and its status.\\n\\nREAD THE DATE YOURSELF before acting:\\n\\n\`openssl s_client -connect api.myweli.com:443 -servername api.myweli.com </dev/null | openssl x509 -noout -enddate\`\\n\\nIF THE DATE IS FAR AWAY, the probe saw another certificate - a host that stopped resolving to Cloudflare would do it. Check where the name points:\\n\\n\`dig +short api.myweli.com\`\\n\\nRunbook: docs/design/hygiene-batch9.md (B9.4)",
    "mimeType": "text/markdown"
  }
}
JSON

# --- 3. Slower than 3 s, for 15 minutes ---------------------------------------
# The mean across probe regions, per check: a far region on a bad night is not
# an outage. 15 minutes so a deploy's cold start does not page anyone.
cat > /tmp/policy-latency.json <<JSON
{
  "displayName": "${HOST} answers slower than 3 s",
  "combiner": "OR",
  "enabled": true,
  "conditions": [{
    "displayName": "mean probe latency over 3000 ms for 15 minutes",
    "conditionThreshold": {
      "filter": "metric.type=\"monitoring.googleapis.com/uptime_check/request_latency\" AND resource.type=\"uptime_url\" AND resource.label.host=\"${HOST}\"",
      "aggregations": [{
        "alignmentPeriod": "300s",
        "perSeriesAligner": "ALIGN_MEAN",
        "crossSeriesReducer": "REDUCE_MEAN",
        "groupByFields": ["metric.label.check_id"]
      }],
      "comparison": "COMPARISON_GT",
      "thresholdValue": 3000,
      "duration": "900s",
      "trigger": { "count": 1 }
    }
  }],
  "alertStrategy": { "autoClose": "86400s" },
  "notificationChannels": ["${CHANNEL}"],
  "documentation": {
    "content": "api.myweli.com has answered its uptime probes in more than 3 seconds on average, across regions, for 15 minutes. The checks still PASS - the service is up and slow, which is the failure no other alert sees: users waiting on every screen.\\n\\nWHICH CHECK. The condition is per check. If only the database check is slow, Postgres is the suspect - a long query, the instance near its limits (the capacity alert covers the hard ceiling). If both are slow, the service itself is: a cold start loop, CPU throttling, or the front door.\\n\\nLOOK AT THE REQUESTS. Slow requests in the service log, newest first:\\n\\n\`gcloud logging read 'resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"myweli-api\" AND httpRequest.latency>\"3s\"' --limit=20 --freshness=1h --format='value(timestamp,httpRequest.requestUrl,httpRequest.latency)'\`\\n\\nTHEN THE INSTANCES. In the Cloud Run console, the service's Metrics tab: instance count, CPU and request latency. A deploy in the last hour is the first thing to rule out.\\n\\nRunbook: docs/design/hygiene-batch9.md (B9.4)",
    "mimeType": "text/markdown"
  }
}
JSON

for BODY in tls-expiry latency; do
  # CLOUDSDK_CORE_DISABLE_PROMPTS because the alpha component's install prompt
  # fires BEFORE flag parsing, so --quiet alone does not reach it.
  CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies create \
    --project="${PROJECT}" --policy-from-file="/tmp/policy-${BODY}.json"
done

echo
echo "Policies now configured:"
CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies list \
  --project="${PROJECT}" --format='value(displayName)' | sed 's/^/  /'
