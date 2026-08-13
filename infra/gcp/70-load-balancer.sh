#!/usr/bin/env bash
# api.myweli.com → Cloud Run, via a global external Application Load Balancer.
#
# WHY A LOAD BALANCER AND NOT A DOMAIN MAPPING. Cloud Run's own custom-domain
# feature is the obvious answer and it is not available to us:
#
#   $ gcloud beta run domain-mappings create --domain=api.myweli.com --region=europe-west9
#   501 UNIMPLEMENTED: Creating domain mappings is not allowed in europe-west9.
#
# europe-west9 (Paris) was chosen for proximity to Abidjan
# (docs/design/infra-gcp-migration.md §4.2); this is the price of that choice.
# Note `domain-mappings list` succeeds in the region and returns an empty list,
# which looks like support and is not — only `create` reveals the truth.
#
# A proxied CNAME to the *.run.app URL does not work either: Cloud Run answers
# 404 to any Host header it does not recognise (verified, including a control
# with a nonsense Host). Cloudflare forwards the original Host by default.
#
# COST: the two global forwarding rules are the billable part — roughly
# $18-25/month plus data processing. Everything else here is free. The owner
# approved this cost explicitly before it was created.
#
# Idempotent: every step is `describe || create`, so a partial run re-runs.
#
#   bash infra/gcp/70-load-balancer.sh
set -euo pipefail

PROJECT=myweli
REGION=europe-west9
SERVICE=myweli-api
DOMAIN=api.myweli.com

gcloud services enable compute.googleapis.com -q

# A static anycast IP — free while attached to a forwarding rule, and the value
# the DNS A record points at. Reserving it separately means the address survives
# the rules being rebuilt.
gcloud compute addresses describe myweli-api-ip --global >/dev/null 2>&1 ||
  gcloud compute addresses create myweli-api-ip --global --ip-version=IPV4 -q
IP=$(gcloud compute addresses describe myweli-api-ip --global --format='value(address)')

# The serverless NEG is the only regional object here; everything above it is
# global, which is what lets a Paris-only service sit behind an anycast address.
gcloud compute network-endpoint-groups describe myweli-api-neg --region="$REGION" >/dev/null 2>&1 ||
  gcloud compute network-endpoint-groups create myweli-api-neg \
    --region="$REGION" --network-endpoint-type=serverless \
    --cloud-run-service="$SERVICE" -q

gcloud compute backend-services describe myweli-api-backend --global >/dev/null 2>&1 ||
  gcloud compute backend-services create myweli-api-backend \
    --global --load-balancing-scheme=EXTERNAL_MANAGED -q
gcloud compute backend-services add-backend myweli-api-backend --global \
  --network-endpoint-group=myweli-api-neg \
  --network-endpoint-group-region="$REGION" -q 2>/dev/null || true

gcloud compute url-maps describe myweli-api-urlmap --global >/dev/null 2>&1 ||
  gcloud compute url-maps create myweli-api-urlmap \
    --default-service=myweli-api-backend --global -q

# Google-managed certificate. It stays PROVISIONING until the A record below
# actually resolves to $IP — Google validates by fetching over HTTP-01, so the
# DNS switch has to come first. In Cloudflare the record must be DNS-ONLY
# (grey cloud): a proxied record terminates TLS at Cloudflare and the
# validation never reaches Google.
gcloud compute ssl-certificates describe myweli-api-cert --global >/dev/null 2>&1 ||
  gcloud compute ssl-certificates create myweli-api-cert --domains="$DOMAIN" --global -q

gcloud compute target-https-proxies describe myweli-api-https-proxy --global >/dev/null 2>&1 ||
  gcloud compute target-https-proxies create myweli-api-https-proxy \
    --url-map=myweli-api-urlmap --ssl-certificates=myweli-api-cert --global -q

gcloud compute forwarding-rules describe myweli-api-https-rule --global >/dev/null 2>&1 ||
  gcloud compute forwarding-rules create myweli-api-https-rule \
    --global --load-balancing-scheme=EXTERNAL_MANAGED \
    --address=myweli-api-ip --target-https-proxy=myweli-api-https-proxy --ports=443 -q

# Plain HTTP redirects rather than hanging: a bare http:// call from a mis-set
# client should say "use https", not time out.
gcloud compute url-maps describe myweli-api-redirect --global >/dev/null 2>&1 ||
  gcloud compute url-maps import myweli-api-redirect --global -q --source=/dev/stdin <<'YAML'
name: myweli-api-redirect
defaultUrlRedirect:
  httpsRedirect: true
  redirectResponseCode: MOVED_PERMANENTLY_DEFAULT
  stripQuery: false
YAML

gcloud compute target-http-proxies describe myweli-api-http-proxy --global >/dev/null 2>&1 ||
  gcloud compute target-http-proxies create myweli-api-http-proxy \
    --url-map=myweli-api-redirect --global -q

gcloud compute forwarding-rules describe myweli-api-http-rule --global >/dev/null 2>&1 ||
  gcloud compute forwarding-rules create myweli-api-http-rule \
    --global --load-balancing-scheme=EXTERNAL_MANAGED \
    --address=myweli-api-ip --target-http-proxy=myweli-api-http-proxy --ports=80 -q

cat <<EOF

Load balancer ready.

  DNS (Cloudflare):  A   $DOMAIN   ->  $IP    [DNS only / grey cloud]

  (Historically this also said to delete the CNAME to the old Render service.
   Done at the 2026-08-06 cutover; Render is decommissioned.)

The managed certificate stays PROVISIONING until that record resolves. Watch it:

  gcloud compute ssl-certificates describe myweli-api-cert --global \\
    --format='value(managed.status)'

FOLLOW-UP once traffic is on the LB: Cloud Run still accepts direct public
traffic on its *.run.app URL, so there are two front doors. Setting ingress to
internal-and-cloud-load-balancing closes the second one — but Cloud Scheduler
calls the run.app URL directly today, so its two jobs must be repointed at
$DOMAIN in the same change or the reminder cron silently stops.
EOF
