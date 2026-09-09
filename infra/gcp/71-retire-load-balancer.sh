#!/usr/bin/env bash
#
# Retire the global load balancer that 70-load-balancer.sh built — and with it
# the Cloud Armor policy (87, 89) and the alert that watched it (91).
#
# ## Why
#
# Billing by SKU over three settled days (docs/design/infra-cloudflare-front-
# door.md §0): the forwarding-rule minimum ($18.26/month) and Cloud Armor
# ($8.21/month) are flat charges that run at zero traffic, and together they
# are more than half of the bill. `api.myweli.com` is now served by Cloudflare
# → the `myweli-api-front-door` Worker → the service's *.run.app URL, and the
# reopened direct door is closed by the origin gate in the backend. Nothing
# below is on the request path any more; it is only on the invoice.
#
# ## READ BEFORE DELETE — the PITR-purge lesson
#
# Every resource is described and printed with its live state BEFORE anything
# is removed, and the script refuses to go on unless three observations hold,
# each of which would be false if the cutover were incomplete:
#
#   1. `dig +short api.myweli.com` returns no 8.232.126.191 — the record is
#      proxied, so the load balancer's address serves nobody;
#   2. `curl -sI https://api.myweli.com/health` is 200 AND carries `cf-ray` —
#      the hostname answers, and it answers through Cloudflare;
#   3. the direct door answers 403 `origin_required` on /providers and 200 on
#      /health — enforcement is LIVE, so deleting the load balancer removes no
#      protection. In `log` mode the door is open and this refuses.
#
# Nothing is deleted before all three pass. This is what the manifest means by
# "keep the load balancer alive UNTIL enforcement is proven".
#
# ## Order — reverse of 70, because each object references the next
#
#   forwarding rules → target proxies → URL maps → detach the security policy
#   → backend service → serverless NEG → managed certificate → static address
#   → security policy → the "Cloud Armor REFUSED a request" alert policy.
#
# The alert policy is found by displayName (the 93-sync-runbooks.sh idiom) and
# NEVER the "Owner email" notification channel, which every other alert shares.
#
# Idempotent in the other direction: a resource already gone is reported and
# skipped, so a partial run re-runs. What this script cannot do itself is
# printed at the end as follow-ups.
#
# ## Guard
#
#   CONFIRM=retire bash infra/gcp/71-retire-load-balancer.sh
#
# Without CONFIRM=retire it prints the plan and exits 1. A pin in
# backend/test/infra/front_door_scripts_test.dart holds this guard, the order
# above, and that this file contains no provisioning verb at all — the word is
# deliberately absent from these comments too, so that a commented-out line
# cannot become the thing someone uncomments at 2am.
set -euo pipefail

PROJECT="${MYWELI_GCP_PROJECT:-myweli}"
REGION=europe-west9
DOMAIN=api.myweli.com
LB_IP=8.232.126.191
DIRECT=https://myweli-api-5a24ymhbbq-od.a.run.app
ARMOR_ALERT='Cloud Armor REFUSED a request'

if [[ "${CONFIRM:-}" != "retire" ]]; then
  echo "::error:: refusing to run without CONFIRM=retire."
  echo "          This deletes the load balancer, its address and certificate,"
  echo "          the Cloud Armor policy and the '${ARMOR_ALERT}' alert."
  echo "          Read the plan in the header of this file first, then:"
  echo
  echo "            CONFIRM=retire bash infra/gcp/71-retire-load-balancer.sh"
  exit 1
fi

# ---------------------------------------------------------------------------
# 1. What exists right now, with its live state. Printed, never assumed.
# ---------------------------------------------------------------------------
echo "Load balancer stack for ${DOMAIN}, project ${PROJECT} — live state:"
echo

show() { # $1 label, rest: the describe command
  local label=$1; shift
  local out
  if out=$("$@" 2>/dev/null); then
    echo "  ${label}"
    printf '%s\n' "${out}" | sed 's/^/      /'
  else
    echo "  ${label}: (absent)"
  fi
}

show "forwarding rule myweli-api-https-rule" \
  gcloud compute forwarding-rules describe myweli-api-https-rule --global \
    --project="${PROJECT}" --format='value(IPAddress,portRange,target)'
show "forwarding rule myweli-api-http-rule" \
  gcloud compute forwarding-rules describe myweli-api-http-rule --global \
    --project="${PROJECT}" --format='value(IPAddress,portRange,target)'
show "target proxy myweli-api-https-proxy" \
  gcloud compute target-https-proxies describe myweli-api-https-proxy --global \
    --project="${PROJECT}" --format='value(urlMap,sslCertificates)'
show "target proxy myweli-api-http-proxy" \
  gcloud compute target-http-proxies describe myweli-api-http-proxy --global \
    --project="${PROJECT}" --format='value(urlMap)'
show "url map myweli-api-urlmap" \
  gcloud compute url-maps describe myweli-api-urlmap --global \
    --project="${PROJECT}" --format='value(defaultService)'
show "url map myweli-api-redirect" \
  gcloud compute url-maps describe myweli-api-redirect --global \
    --project="${PROJECT}" --format='value(defaultUrlRedirect.httpsRedirect)'
show "backend service myweli-api-backend" \
  gcloud compute backend-services describe myweli-api-backend --global \
    --project="${PROJECT}" --format='value(securityPolicy,logConfig.enable,backends[0].group)'
show "serverless NEG myweli-api-neg (${REGION})" \
  gcloud compute network-endpoint-groups describe myweli-api-neg --region="${REGION}" \
    --project="${PROJECT}" --format='value(networkEndpointType,cloudRun.service)'
show "managed certificate myweli-api-cert" \
  gcloud compute ssl-certificates describe myweli-api-cert --global \
    --project="${PROJECT}" --format='value(managed.status,managed.domains)'
show "static address myweli-api-ip" \
  gcloud compute addresses describe myweli-api-ip --global \
    --project="${PROJECT}" --format='value(address,status)'
show "security policy myweli-api-rate-limit" \
  gcloud compute security-policies describe myweli-api-rate-limit \
    --project="${PROJECT}" --format='value(rules[].priority)'

ALERT_ID=$(gcloud alpha monitoring policies list --project="${PROJECT}" \
  --filter="displayName=\"${ARMOR_ALERT}\"" --format='value(name)' 2>/dev/null || true)
if [[ -n "${ALERT_ID}" ]]; then
  echo "  alert policy '${ARMOR_ALERT}'"
  printf '%s\n' "${ALERT_ID}" | sed 's/^/      /'
else
  echo "  alert policy '${ARMOR_ALERT}': (absent)"
fi
echo

# ---------------------------------------------------------------------------
# 2. The three observations. Any one false → nothing is touched.
# ---------------------------------------------------------------------------
echo "Is the cutover complete? Three observations, each required:"
echo

DIG=$(dig +short "${DOMAIN}" 2>/dev/null || true)
if [[ -z "${DIG}" ]]; then
  echo "::error:: (1) dig +short ${DOMAIN} returned nothing — the record does not resolve."
  exit 1
fi
if grep -qF "${LB_IP}" <<< "${DIG}"; then
  echo "::error:: (1) ${DOMAIN} still resolves to ${LB_IP} — the record is DNS-only."
  echo "          The load balancer is serving traffic. Run 96-api-front-door.sh"
  echo "          (proxied record) and come back when dig shows Cloudflare addresses."
  exit 1
fi
echo "  ✓ (1) ${DOMAIN} resolves to $(tr '\n' ' ' <<< "${DIG}")— not ${LB_IP}"

HEAD=$(curl -sI --max-time 20 "https://${DOMAIN}/health" 2>/dev/null || true)
STATUS=$(printf '%s' "${HEAD}" | head -1 | awk '{print $2}')
if [[ "${STATUS}" != "200" ]]; then
  echo "::error:: (2) https://${DOMAIN}/health answered '${STATUS:-nothing}', expected 200."
  exit 1
fi
if ! grep -qi '^cf-ray:' <<< "${HEAD}"; then
  echo "::error:: (2) https://${DOMAIN}/health is 200 but carries no cf-ray header —"
  echo "          it is not being served through Cloudflare, so the load balancer"
  echo "          may still be the thing answering."
  exit 1
fi
echo "  ✓ (2) https://${DOMAIN}/health → 200, through Cloudflare (cf-ray present)"

BODY=$(mktemp)
CODE=$(curl -s --max-time 20 -o "${BODY}" -w '%{http_code}' "${DIRECT}/providers" || true)
if [[ "${CODE}" != "403" ]] || ! grep -q 'origin_required' "${BODY}"; then
  echo "::error:: (3) ${DIRECT}/providers answered '${CODE}' $(head -c 200 "${BODY}")"
  echo "          expected 403 with origin_required. Enforcement is NOT live"
  echo "          (ORIGIN_AUTH_MODE is still 'log', or the gate is not deployed),"
  echo "          so the load balancer is still the only thing closing that door."
  rm -f "${BODY}"
  exit 1
fi
CODE=$(curl -s --max-time 20 -o /dev/null -w '%{http_code}' "${DIRECT}/health" || true)
if [[ "${CODE}" != "200" ]]; then
  echo "::error:: (3) ${DIRECT}/health answered '${CODE}', expected 200 — ingress is"
  echo "          not open, or the /health exemption is gone (the liveness probe"
  echo "          would be failing too)."
  rm -f "${BODY}"
  exit 1
fi
rm -f "${BODY}"
echo "  ✓ (3) the direct door: /providers → 403 origin_required, /health → 200"
echo
echo "All three hold. Deleting, in reverse-reference order."
echo

# ---------------------------------------------------------------------------
# 3. Delete. Each step: gone already → say so and continue.
# ---------------------------------------------------------------------------
if gcloud compute forwarding-rules describe myweli-api-https-rule --global --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute forwarding-rules delete myweli-api-https-rule --global --project="${PROJECT}" -q
  echo "  − forwarding rule myweli-api-https-rule"
else
  echo "  · forwarding rule myweli-api-https-rule already gone"
fi
if gcloud compute forwarding-rules describe myweli-api-http-rule --global --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute forwarding-rules delete myweli-api-http-rule --global --project="${PROJECT}" -q
  echo "  − forwarding rule myweli-api-http-rule"
else
  echo "  · forwarding rule myweli-api-http-rule already gone"
fi

if gcloud compute target-https-proxies describe myweli-api-https-proxy --global --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute target-https-proxies delete myweli-api-https-proxy --global --project="${PROJECT}" -q
  echo "  − target proxy myweli-api-https-proxy"
else
  echo "  · target proxy myweli-api-https-proxy already gone"
fi
if gcloud compute target-http-proxies describe myweli-api-http-proxy --global --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute target-http-proxies delete myweli-api-http-proxy --global --project="${PROJECT}" -q
  echo "  − target proxy myweli-api-http-proxy"
else
  echo "  · target proxy myweli-api-http-proxy already gone"
fi

if gcloud compute url-maps describe myweli-api-urlmap --global --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute url-maps delete myweli-api-urlmap --global --project="${PROJECT}" -q
  echo "  − url map myweli-api-urlmap"
else
  echo "  · url map myweli-api-urlmap already gone"
fi
if gcloud compute url-maps describe myweli-api-redirect --global --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute url-maps delete myweli-api-redirect --global --project="${PROJECT}" -q
  echo "  − url map myweli-api-redirect"
else
  echo "  · url map myweli-api-redirect already gone"
fi

# Detach before deleting the backend: a policy still referenced by a backend
# service cannot be deleted, and the backend cannot be deleted while a URL map
# references it — which is why the maps went first.
if gcloud compute backend-services describe myweli-api-backend --global --project="${PROJECT}" >/dev/null 2>&1; then
  ATTACHED=$(gcloud compute backend-services describe myweli-api-backend --global \
    --project="${PROJECT}" --format='value(securityPolicy)' 2>/dev/null || true)
  if [[ -n "${ATTACHED}" ]]; then
    gcloud compute backend-services update myweli-api-backend --global \
      --project="${PROJECT}" --security-policy="" -q
    echo "  − detached the security policy from myweli-api-backend"
  fi
  gcloud compute backend-services delete myweli-api-backend --global --project="${PROJECT}" -q
  echo "  − backend service myweli-api-backend"
else
  echo "  · backend service myweli-api-backend already gone"
fi

if gcloud compute network-endpoint-groups describe myweli-api-neg --region="${REGION}" --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute network-endpoint-groups delete myweli-api-neg --region="${REGION}" --project="${PROJECT}" -q
  echo "  − serverless NEG myweli-api-neg"
else
  echo "  · serverless NEG myweli-api-neg already gone"
fi

if gcloud compute ssl-certificates describe myweli-api-cert --global --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute ssl-certificates delete myweli-api-cert --global --project="${PROJECT}" -q
  echo "  − managed certificate myweli-api-cert"
else
  echo "  · managed certificate myweli-api-cert already gone"
fi

# Only now: observation (1) proved DNS no longer points here, so releasing the
# address strands nobody. It is the one object whose deletion is not reversible
# — a new reservation gets a new address, and DNS would have to follow it.
if gcloud compute addresses describe myweli-api-ip --global --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute addresses delete myweli-api-ip --global --project="${PROJECT}" -q
  echo "  − static address myweli-api-ip (${LB_IP})"
else
  echo "  · static address myweli-api-ip already gone"
fi

if gcloud compute security-policies describe myweli-api-rate-limit --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud compute security-policies delete myweli-api-rate-limit --project="${PROJECT}" -q
  echo "  − security policy myweli-api-rate-limit (rules 1000, 1100)"
else
  echo "  · security policy myweli-api-rate-limit already gone"
fi

# The alert, by displayName. Its filter names http_load_balancer, a resource
# that no longer exists, so it could never fire again — and 93-sync-runbooks.sh
# would report the rendered policy as having no live twin if policy-bodies.sh
# still listed 91 (it does not, while this is retired). The "Owner email"
# channel is shared by every other alert and is deliberately never touched.
if [[ -n "${ALERT_ID}" ]]; then
  if [[ $(wc -l <<< "${ALERT_ID}") -ne 1 ]]; then
    echo "::error:: more than one alert policy is named '${ARMOR_ALERT}':"
    printf '%s\n' "${ALERT_ID}"
    echo "          Delete by hand — refusing to guess."
    exit 1
  fi
  CLOUDSDK_CORE_DISABLE_PROMPTS=1 gcloud alpha monitoring policies delete "${ALERT_ID}" \
    --project="${PROJECT}" --quiet
  echo "  − alert policy '${ARMOR_ALERT}'"
else
  echo "  · alert policy '${ARMOR_ALERT}' already gone"
fi

cat <<EOF

Retired. Two follow-ups this script cannot do itself:

  1. DNS (Cloudflare): the proxied A record for ${DOMAIN} still holds
     ${LB_IP}, an address that now belongs to nobody. Set its content to
     192.0.2.0 (the documented originless placeholder for a Worker route);
     the Worker answers regardless of the record's content, so this is
     hygiene, not a cutover.

  2. Billing → Reports, tomorrow, by SKU. These rows must be GONE:
        Cloud Load Balancer Forwarding Rule Minimum Global
        Cloud Armor (policy, rules, requests)
     If either still bills after a settled day, something above was not
     deleted — re-run this script; it reports what is left.

Already done in this change: policy-bodies.sh no longer lists 91, so
93-sync-runbooks.sh and 95-emitter-lag.sh will not look for the deleted alert.
Re-application, if the load balancer ever comes back: LAUNCH.md §6.5.
EOF
