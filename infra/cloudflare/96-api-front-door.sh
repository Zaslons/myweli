#!/usr/bin/env bash
# api.myweli.com behind Cloudflare — the front door without the load balancer
# (docs/design/infra-cloudflare-front-door.md §5.4; steps 1–5 in the spec's
# order, each read back before the next one starts).
#
# WHY A WORKER. Billing → Reports, three settled days, by SKU: ≈$50/month, of
# which $26.5 is two flat network charges that run at zero traffic — the global
# load balancer's forwarding-rule minimum and Cloud Armor. Cloud Run domain
# mappings are still unimplemented in europe-west9, so the LB was the documented
# price of a custom domain in Paris, never an over-build; the only cheaper path
# is the one infra-gcp-migration.md §7.2 declined on 2026-08-06 as « operating a
# proxy to save $18/month »: a Cloudflare Worker in front of Cloud Run. At
# $26.5/month, forever, it is now worth operating (spec §0, §1). The Worker
# forwards every request to the run.app hostname and adds ONE secret header;
# the backend's origin gate refuses anything without it, which is what makes
# the edge rate limit un-bypassable once ingress opens to `all`.
#
# THE ONE TOKEN — dashboard only. Only ONE step needs the dashboard — minting
# the API token — because Cloudflare does not expose token creation to a token
# (the same note as 90-staging-r2.sh). Its scope, spec §6.3 verbatim:
#
#   Custom token, scoped to **zone `myweli.com`** only, **no R2, no Pages**:
#   Account → *Workers Scripts: Edit* · *Account Settings: Read* · User → *User
#   Details: Read* (what `wrangler` needs to deploy) · Zone → *Workers Routes:
#   Edit* · *DNS: Edit* · *Zone WAF: Edit* (the rate-limiting rule; the docs
#   spell it « Write » in one place and « Edit » in another — same permission)
#   · *Zone Settings: Read* · *Zone: Read*. Stored with
#   `pbpaste | gcloud secrets create CLOUDFLARE_FRONT_DOOR_TOKEN --project myweli --replication-policy=automatic --data-file=-`
#   — the exact gesture used for `SENTRY_AUTH_TOKEN`.
#
# This script reads that token from Secret Manager into CLOUDFLARE_API_TOKEN
# (what `wrangler` and `curl` consume), NEVER prints it, and never puts it in a
# URL. CI never reads it: production-checks.yml asserts CI cannot read any
# secret value, and the Worker is not a CI deploy — the R2 stance (« CI has no
# Cloudflare identity ») stays true (spec §6.2).
#
# EVERY STEP READS ITS WORK BACK. The R2 script's first run aborted « loudly,
# to a terminal nobody was reading » and left the buckets half-configured; a
# step that reports success it has not confirmed is the failure mode this
# repository keeps finding. So each step below re-reads what it set and exits
# 1 with a `::error::` line when what came back is not what went in.
#
# Idempotent — safe to re-run at launch (LAUNCH.md §6.5): an already-proxied
# record is left alone, `wrangler deploy` and `secret put` are upserts, and the
# rate-limit ruleset is only ever PUT when every rule in it is ours.
#
# WHAT IT NEEDS: gcloud (logged in as the owner), jq, curl, dig, node/npx. No
# `wrangler login`: the token in the environment is wrangler's identity here.
# If the token can see more than one Cloudflare account, wrangler also needs
# CLOUDFLARE_ACCOUNT_ID — the value the backend already holds as R2_ACCOUNT_ID
# (the same account, shared by design: 90-staging-r2.sh) — read below when not
# already exported.
#
# Run AFTER production deploy phase A (ingress: all + ORIGIN_AUTH_SECRET +
# ORIGIN_AUTH_MODE: log — spec §9 step 4) and BEFORE phase B (enforce):
#
#   bash infra/cloudflare/96-api-front-door.sh
#
# Then: measure the log-mode window (§9 step 6), phase B, and
# infra/gcp/72-verify-front-door.sh. Only after that: 71-retire-load-balancer.sh.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRANGLER="npx --yes wrangler@4"

PROJECT=myweli
ZONE_NAME=myweli.com
API_HOST=api.myweli.com
WORKER_NAME=myweli-api-front-door
WORKER_DIR="$HERE/worker/api-front-door"
CF_API=https://api.cloudflare.com/client/v4
# The load balancer's static address (infra/gcp/70-load-balancer.sh). While
# the LB is alive, a proxied record keeps pointing at it — the fail-open target
# still serves the hostname with a valid certificate. After the LB is retired,
# 71-retire-load-balancer.sh's follow-up sets the documented originless
# placeholder 192.0.2.0. Named here only so the read-back can assert that
# `dig` no longer returns it: a proxied record answers with Cloudflare's
# addresses, never the origin's.
LB_IP=8.232.126.191
# The origin refuses to boot on a shorter secret (kMinOriginAuthSecretLength in
# lib/src/security/origin_auth.dart). Checked here BEFORE the Worker gets it,
# so a Worker is never deployed with a value the origin will reject.
MIN_SECRET_LENGTH=32
# Ownership marker for step 5. `PUT …/entrypoint` replaces the WHOLE rules list
# of the phase, so the script only ever writes when every existing rule carries
# this description — a rule the owner made by hand in the dashboard is never
# clobbered.
RULE_DESCRIPTION='api.myweli.com auth burst guard (edge) — infra/cloudflare/96-api-front-door.sh'

for tool in gcloud jq curl dig npx; do
  command -v "$tool" >/dev/null || { echo "::error:: $tool is required"; exit 1; }
done
[[ -f "$WORKER_DIR/wrangler.toml" ]] ||
  { echo "::error:: $WORKER_DIR/wrangler.toml not found — run from the repo checkout"; exit 1; }

# Two scratch files, both removed on any exit: the bearer header curl reads
# (0600, so the token is on no command line — `ps` shows arguments, and
# `-H "Authorization: Bearer $TOKEN"` would be one) and the body of the one
# API call whose HTTP status matters (step 5's ownership check).
AUTH_HEADER_FILE=$(mktemp)
ENTRY_FILE=$(mktemp)
trap 'rm -f "$AUTH_HEADER_FILE" "$ENTRY_FILE"' EXIT
chmod 600 "$AUTH_HEADER_FILE" "$ENTRY_FILE"

# cf METHOD PATH [JSON_BODY] — one Cloudflare API call. Prints the response
# body on stdout; on `success: false` (or a non-JSON answer) prints the API's
# own errors and returns 1, which under `set -e` stops the script at the step
# that failed instead of letting the next step build on nothing. The bearer
# token travels in a header read from the scratch file — never in the URL
# (proxies and shell history keep URLs), never as an argument, never in any
# echo.
cf() {
  local method="$1" path="$2" body="${3:-}" out
  if [[ -n "$body" ]]; then
    out=$(curl -sS -X "$method" "$CF_API$path" -H "@$AUTH_HEADER_FILE" \
      -H 'Content-Type: application/json' --data "$body")
  else
    out=$(curl -sS -X "$method" "$CF_API$path" -H "@$AUTH_HEADER_FILE")
  fi
  if [[ "$(jq -r '.success // false' <<<"$out" 2>/dev/null)" != "true" ]]; then
    echo "::error:: Cloudflare API $method $path refused:" >&2
    jq -r '.errors[]? | "      [\(.code)] \(.message)"' <<<"$out" >&2 2>/dev/null ||
      echo "      $out" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

echo "==> 1/5  Token and zone"
# Read, exported, never echoed. `wrangler` picks it up from the environment
# and `cf` from the header file; nothing below expands it into a command line
# that `ps` or the shell history could show.
CLOUDFLARE_API_TOKEN=$(gcloud secrets versions access latest \
  --secret=CLOUDFLARE_FRONT_DOOR_TOKEN --project="$PROJECT") ||
  { echo "::error:: cannot read CLOUDFLARE_FRONT_DOOR_TOKEN from Secret Manager — mint it in the dashboard (scope in the header) and store it with the gcloud secrets create line above"; exit 1; }
export CLOUDFLARE_API_TOKEN
[[ -n "$CLOUDFLARE_API_TOKEN" ]] ||
  { echo "::error:: CLOUDFLARE_FRONT_DOOR_TOKEN is empty"; exit 1; }
printf 'Authorization: Bearer %s\n' "$CLOUDFLARE_API_TOKEN" >"$AUTH_HEADER_FILE"

# The zone id by NAME, so nothing in this file has to be updated if the zone is
# ever re-created — and as the first read-back of the token itself: a token
# scoped to the wrong zone (or to none) returns an empty list here, not later.
ZONE_JSON=$(cf GET "/zones?name=$ZONE_NAME")
ZONE_ID=$(jq -r '.result[0].id // empty' <<<"$ZONE_JSON")
[[ -n "$ZONE_ID" ]] ||
  { echo "::error:: zone $ZONE_NAME is not visible to this token — it is not scoped to the zone (spec §6.3) or is not the token you think it is"; exit 1; }
[[ "$(jq -r '.result[0].name' <<<"$ZONE_JSON")" == "$ZONE_NAME" ]] ||
  { echo "::error:: /zones?name=$ZONE_NAME answered a different zone — refusing to touch it"; exit 1; }
echo "    ✓ token read from Secret Manager (not shown); zone $ZONE_NAME = $ZONE_ID"

if [[ -z "${CLOUDFLARE_ACCOUNT_ID:-}" ]]; then
  # Not a secret in the credential sense, but it lives in Secret Manager
  # because the backend reads it from there; treated the same way — used,
  # not printed. Optional: wrangler resolves the account itself when the token
  # can see exactly one.
  CLOUDFLARE_ACCOUNT_ID=$(gcloud secrets versions access latest \
    --secret=R2_ACCOUNT_ID --project="$PROJECT" 2>/dev/null || true)
  [[ -n "$CLOUDFLARE_ACCOUNT_ID" ]] && export CLOUDFLARE_ACCOUNT_ID
fi

echo "==> 2/5  Zone prechecks — SSL mode, security level, browser check"
# `flexible` loops against an HTTPS-redirecting origin: Cloudflare connects to
# the origin over plain HTTP, the LB answers 301 → https, Cloudflare connects
# over HTTP again. While the proxied record still points at the LB (the
# fail-open path, step 4) that loop is one toggle away — so the mode is a
# precondition, not a note.
SSL_MODE=$(cf GET "/zones/$ZONE_ID/settings/ssl" | jq -r '.result.value')
case "$SSL_MODE" in
  full | strict) echo "    ✓ ssl mode: $SSL_MODE" ;;
  *)
    echo "::error:: zone SSL mode is '$SSL_MODE' — must be full or strict (flexible loops against the HTTPS-redirecting origin). Set SSL/TLS → Overview → Full (strict) in the dashboard and re-run."
    exit 1
    ;;
esac
# Reported, not asserted: Browser Integrity Check and Bot Fight Mode can
# challenge non-browser clients, and Google's uptime probes, Cloud Scheduler,
# Vercel's build fetch and the Dart HTTP client cannot answer a challenge.
# These values go on the cutover checklist; infra/gcp/72-verify-front-door.sh
# proves each client end-to-end (spec §5.4 step 2, §11 item 3).
SECURITY_LEVEL=$(cf GET "/zones/$ZONE_ID/settings/security_level" | jq -r '.result.value')
BROWSER_CHECK=$(cf GET "/zones/$ZONE_ID/settings/browser_check" | jq -r '.result.value')
echo "    · security_level: $SECURITY_LEVEL   (note it — 72-verify-front-door.sh proves the non-browser clients)"
echo "    · browser_check:  $BROWSER_CHECK   (\"on\" = Browser Integrity Check may challenge the Dart client / probes)"

echo "==> 3/5  Worker $WORKER_NAME — deploy, secret, read back"
# The origin's own floor, applied before the Worker ever holds the value:
# length only, counted through a pipe, the value itself never lands in a
# variable or on the terminal.
SECRET_LENGTH=$(gcloud secrets versions access latest \
  --secret=ORIGIN_AUTH_SECRET --project="$PROJECT" | wc -c | tr -d ' ') ||
  { echo "::error:: cannot read ORIGIN_AUTH_SECRET from Secret Manager — create it first (spec §6.2, §9 step 2)"; exit 1; }
if ((SECRET_LENGTH < MIN_SECRET_LENGTH)); then
  echo "::error:: ORIGIN_AUTH_SECRET is $SECRET_LENGTH chars; the origin refuses to boot below $MIN_SECRET_LENGTH (kMinOriginAuthSecretLength). Generate it as spec §6.2 says (64 chars) — not deploying a Worker with a value the origin will reject."
  exit 1
fi
echo "    ✓ ORIGIN_AUTH_SECRET exists and is $SECRET_LENGTH chars (value not shown)"

# `wrangler deploy` reads wrangler.toml: the script name, the route on
# myweli.com and the ORIGIN_HOST var. It is an upsert — re-running redeploys
# the same code and re-asserts the route. Traffic does not reach the Worker
# until the record is proxied (step 4), so the seconds between this deploy and
# the secret landing below serve nobody the 500 the Worker would answer.
(cd "$WORKER_DIR" && $WRANGLER deploy)

# The secret, by stdin pipe — wrangler reads the value from stdin when piped,
# so it is never typed, never echoed, never in an argument. Each `secret put`
# creates and deploys a new Worker version with the same code.
gcloud secrets versions access latest --secret=ORIGIN_AUTH_SECRET --project="$PROJECT" |
  (cd "$WORKER_DIR" && $WRANGLER secret put ORIGIN_AUTH_SECRET)

# Read back — three views of the same deployment, none of which shows a value:
# `secret list` prints names and types only; `deployments list` proves a
# version is live; the routes API proves the route exists on THIS zone and
# points at THIS script, which is what the toml claimed and the dashboard
# could have changed since.
if ! (cd "$WORKER_DIR" && $WRANGLER secret list 2>&1) | grep -q 'ORIGIN_AUTH_SECRET'; then
  echo "::error:: ORIGIN_AUTH_SECRET is not among the Worker's secrets after 'secret put' — read it back and see"
  (cd "$WORKER_DIR" && $WRANGLER secret list) || true
  exit 1
fi
echo "    ✓ secret ORIGIN_AUTH_SECRET is bound (names only, no values, are listed)"
echo "    · deployments:"
(cd "$WORKER_DIR" && $WRANGLER deployments list 2>&1) | head -n 20 | sed 's/^/      | /'

ROUTES_JSON=$(cf GET "/zones/$ZONE_ID/workers/routes")
ROUTE_SCRIPT=$(jq -r --arg p "$API_HOST/*" \
  '.result[]? | select(.pattern == $p) | .script // empty' <<<"$ROUTES_JSON")
if [[ "$ROUTE_SCRIPT" != "$WORKER_NAME" ]]; then
  echo "::error:: no route '$API_HOST/*' → '$WORKER_NAME' on zone $ZONE_NAME after deploy (found script: '${ROUTE_SCRIPT:-none}'). The toml's [[routes]] did not take; check the token has Workers Routes: Edit on the zone."
  jq -r '.result[]? | "      \(.pattern) → \(.script // "-")"' <<<"$ROUTES_JSON" || true
  exit 1
fi
echo "    ✓ route $API_HOST/* → $WORKER_NAME verified by reading it back"

echo "==> 4/5  DNS — proxy the $API_HOST A record (content unchanged)"
# The route only fires on a PROXIED (orange-cloud) record; an unproxied record
# never reaches the Worker. The record's content is left exactly as it is: the
# LB address while the LB lives (fail-open still serves), the 192.0.2.0
# placeholder once 71-retire-load-balancer.sh's follow-up sets it. This script
# flips one flag and never creates a record — a hostname with no record is a
# state this script did not expect, and inventing one is how the wrong origin
# gets served.
DNS_JSON=$(cf GET "/zones/$ZONE_ID/dns_records?type=A&name=$API_HOST")
RECORD_COUNT=$(jq -r '.result | length' <<<"$DNS_JSON")
if [[ "$RECORD_COUNT" != "1" ]]; then
  echo "::error:: expected exactly one A record for $API_HOST, found $RECORD_COUNT — create it DNS-only at the LB address (70-load-balancer.sh) or resolve the duplicate in the dashboard, then re-run"
  jq -r '.result[]? | "      \(.name) A \(.content) proxied=\(.proxied)"' <<<"$DNS_JSON" || true
  exit 1
fi
RECORD_ID=$(jq -r '.result[0].id' <<<"$DNS_JSON")
RECORD_CONTENT=$(jq -r '.result[0].content' <<<"$DNS_JSON")
RECORD_PROXIED=$(jq -r '.result[0].proxied' <<<"$DNS_JSON")
if [[ "$RECORD_PROXIED" == "true" ]]; then
  echo "    ✓ $API_HOST A $RECORD_CONTENT is already proxied"
else
  # PATCH, not PUT: only `proxied` changes; name, content, TTL and comment stay
  # whatever the record holds.
  cf PATCH "/zones/$ZONE_ID/dns_records/$RECORD_ID" '{"proxied": true}' >/dev/null
  echo "    + $API_HOST A $RECORD_CONTENT → proxied"
fi
# Read back from the API first (the flag), then from the world (the effect).
DNS_AFTER=$(cf GET "/zones/$ZONE_ID/dns_records/$RECORD_ID")
[[ "$(jq -r '.result.proxied' <<<"$DNS_AFTER")" == "true" ]] ||
  { echo "::error:: the A record for $API_HOST reads proxied=false after the PATCH — the flip did not stick"; exit 1; }
[[ "$(jq -r '.result.content' <<<"$DNS_AFTER")" == "$RECORD_CONTENT" ]] ||
  { echo "::error:: the A record's content changed ($RECORD_CONTENT → $(jq -r '.result.content' <<<"$DNS_AFTER")) — this script only flips 'proxied'; something else is editing the record"; exit 1; }

# Ask the zone's own nameservers: a recursive resolver may keep the old answer
# for the record's TTL and report a failure that is only a cache. A proxied
# record answers with Cloudflare's anycast addresses, so the LB's address must
# be absent. Retried, because the edge takes a moment to publish.
AUTH_NS=$(dig +short NS "$ZONE_NAME" | head -n 1)
DIG_OK=0
for attempt in 1 2 3 4 5 6; do
  ANSWER=$(dig +short "@${AUTH_NS:-1.1.1.1}" "$API_HOST" A 2>/dev/null || true)
  if [[ -n "$ANSWER" ]] && ! grep -qx "$LB_IP" <<<"$ANSWER"; then
    DIG_OK=1
    break
  fi
  echo "    … attempt $attempt: dig still answers '${ANSWER:-nothing}' — waiting 10 s"
  sleep 10
done
if ((DIG_OK == 0)); then
  echo "::error:: dig @${AUTH_NS:-1.1.1.1} $API_HOST still returns the LB address ($LB_IP) or nothing — the record is not being served proxied"
  exit 1
fi
echo "    ✓ dig: $API_HOST → $(tr '\n' ' ' <<<"$ANSWER")(Cloudflare, not $LB_IP)"

# The effect end to end: a response that carries `cf-ray` came through
# Cloudflare's edge. Retried for the same reason. Read-only GET of /health.
CF_RAY_OK=0
for attempt in 1 2 3 4 5 6; do
  HEAD_OUT=$(curl -sI --max-time 15 "https://$API_HOST/health" 2>/dev/null || true)
  if grep -qi '^cf-ray:' <<<"$HEAD_OUT"; then
    CF_RAY_OK=1
    break
  fi
  echo "    … attempt $attempt: no cf-ray on https://$API_HOST/health yet — waiting 10 s"
  sleep 10
done
if ((CF_RAY_OK == 0)); then
  echo "::error:: https://$API_HOST/health carries no cf-ray header — requests are not going through Cloudflare (last headers below)"
  sed 's/^/      | /' <<<"$HEAD_OUT"
  exit 1
fi
echo "    ✓ https://$API_HOST/health: $(head -n 1 <<<"$HEAD_OUT" | tr -d '\r') · $(grep -i '^cf-ray:' <<<"$HEAD_OUT" | tr -d '\r')"

echo "==> 5/5  Edge rate-limit rule (http_ratelimit phase)"
# Free plan: ONE rule, IP characteristic, 10 s period, 10 s timeout, fields
# Path and Verified Bot only — so no http.host clause (the two prefixes are
# served by nothing else on the zone) and both prefixes share one expression.
# cf.colo.id is mandatory via the API (the dashboard adds it silently).
# 10 per 10 s, not 5: the web BFF's single egress address must not be blocked
# by two visitors requesting codes at once. This is BURST protection — edge
# counters are per data centre and imprecise; the origin's Postgres limiter
# (10/minute per IP) is the authoritative one (spec §5.4).
#
# UNVERIFIED in the docs: whether the Free plan accepts a function or an `or`
# in the expression. This PUT is the proof; if the API refuses it, cf() prints
# the refusal and the script stops here — the fallbacks are in spec §11 item 1
# (a `matches "^/(admin/)?auth/"` regex, then `/auth/` alone at the edge).
RULE_BODY=$(jq -n --arg d "$RULE_DESCRIPTION" '{
  rules: [{
    description: $d,
    expression: "starts_with(http.request.uri.path, \"/auth/\") or starts_with(http.request.uri.path, \"/admin/auth/\")",
    action: "block",
    ratelimit: {
      characteristics: ["cf.colo.id", "ip.src"],
      period: 10,
      requests_per_period: 10,
      mitigation_timeout: 10
    },
    enabled: true
  }]
}')

# OWNERSHIP CHECK BEFORE ANY PUT. The entry point either does not exist yet
# (404 — PUT creates it) or holds rules; PUT replaces the whole list, so a rule
# whose description is not ours means a human made it and this script must not
# be the thing that deletes it.
ENTRY_STATUS=$(curl -sS -o "$ENTRY_FILE" -w '%{http_code}' \
  "$CF_API/zones/$ZONE_ID/rulesets/phases/http_ratelimit/entrypoint" \
  -H "@$AUTH_HEADER_FILE")
case "$ENTRY_STATUS" in
  200)
    FOREIGN=$(jq -r --arg d "$RULE_DESCRIPTION" \
      '[.result.rules[]? | select((.description // "") != $d)] | length' "$ENTRY_FILE")
    if [[ "$FOREIGN" != "0" ]]; then
      echo "::error:: the http_ratelimit ruleset already holds $FOREIGN rule(s) this script did not write — PUT would replace the whole list, so refusing. Rules found:"
      jq -r '.result.rules[]? | "      \(.id)  \(.description // "(no description)")  \(.expression)"' "$ENTRY_FILE"
      echo "      Delete or re-describe them in the dashboard (Security → WAF → Rate limiting rules) if they are obsolete, then re-run."
      exit 1
    fi
    echo "    ✓ existing ruleset holds only our rule(s) — safe to replace"
    ;;
  404)
    echo "    · no http_ratelimit ruleset yet — PUT creates it"
    ;;
  *)
    echo "::error:: GET …/rulesets/phases/http_ratelimit/entrypoint answered HTTP $ENTRY_STATUS:"
    jq -r '.errors[]? | "      [\(.code)] \(.message)"' "$ENTRY_FILE" 2>/dev/null || sed 's/^/      /' "$ENTRY_FILE"
    exit 1
    ;;
esac

PUT_JSON=$(cf PUT "/zones/$ZONE_ID/rulesets/phases/http_ratelimit/entrypoint" "$RULE_BODY")
RULE_ID=$(jq -r --arg d "$RULE_DESCRIPTION" \
  '.result.rules[]? | select(.description == $d) | .id' <<<"$PUT_JSON" | head -n 1)

# Read back with a fresh GET, and compare every number that was sent — an
# accepted PUT that was normalised to something else is the case worth
# catching, and `.success: true` alone would not.
READ_JSON=$(cf GET "/zones/$ZONE_ID/rulesets/phases/http_ratelimit/entrypoint")
LIVE_RULE=$(jq -c --arg d "$RULE_DESCRIPTION" \
  '.result.rules[]? | select(.description == $d)' <<<"$READ_JSON" | head -n 1)
[[ -n "$LIVE_RULE" ]] ||
  { echo "::error:: the rate-limit rule is not in the ruleset after the PUT — read it back and see"; jq '.result.rules' <<<"$READ_JSON"; exit 1; }
for check in \
  '.action == "block"' \
  '.enabled == true' \
  '(.expression | contains("/auth/")) and (.expression | contains("/admin/auth/"))' \
  '(.ratelimit.characteristics | sort) == ["cf.colo.id", "ip.src"]' \
  '.ratelimit.period == 10' \
  '.ratelimit.requests_per_period == 10' \
  '.ratelimit.mitigation_timeout == 10'; do
  if [[ "$(jq -r "$check" <<<"$LIVE_RULE")" != "true" ]]; then
    echo "::error:: the live rate-limit rule does not satisfy: $check"
    echo "      live: $LIVE_RULE"
    exit 1
  fi
done
RULE_ID=$(jq -r '.id' <<<"$LIVE_RULE")
echo "    ✓ rule $RULE_ID: block · 10 per 10 s per IP · /auth/* and /admin/auth/* — verified by reading it back"

cat <<EOF

The front door is up: route $API_HOST/* → $WORKER_NAME → run.app, record
proxied, edge burst rule $RULE_ID live. Every step above was read back.

────────────────────────────────────────────────────────────────────────────
ONE step is dashboard-only — do it now, before phase B
────────────────────────────────────────────────────────────────────────────

  Workers & Pages → $WORKER_NAME → Settings → Domains & Routes →
  route $API_HOST/* → Fail mode → **Fail closed**

  Workers Free is 100 000 requests/day (reset midnight UTC). Past the cap,
  "Fail open" BYPASSES the Worker: requests go straight to wherever the
  proxied record points, without the origin-auth header — the exact state
  the gate exists to refuse. "Fail closed" answers a clean Error 1027 and is
  the documented recommendation for a security-critical Worker. The default
  is not stated in the docs, so it is set by hand and recorded in
  DEPLOYMENT.md (spec §5.3, §11 item 2). Re-read it at launch (LAUNCH.md §6.5).

  Cutover checklist values from step 2:  ssl=$SSL_MODE
  security_level=$SECURITY_LEVEL  browser_check=$BROWSER_CHECK

Next — measure the log-mode window (spec §9 step 6), deploy phase B
(ORIGIN_AUTH_MODE: enforce), then prove the live path end to end:

  bash infra/gcp/72-verify-front-door.sh

Only when that is green: CONFIRM=retire bash infra/gcp/71-retire-load-balancer.sh
EOF
