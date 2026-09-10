#!/usr/bin/env bash
#
# Is the front door serving what docs/design/infra-cloudflare-front-door.md §8
# says it serves? The acceptance of rollout step 8 (§9), scripted rather than
# narrated.
#
# Exit 0 = every check passed, and at least 8 of them ran.
# Exit 1 = a FAIL, listed — or too few checks ran to mean anything.
#
# ## What it proves, in order
#
#   1. the per-IP limit on /auth/*: 15 POSTs to the OTP request route from
#      this address → at least one is NOT 429, then 429s WITH the house JSON
#      envelope (`rate_limited`), not an HTML page. This is the 87/89 burst
#      probe, now expecting the app's answer instead of Cloud Armor's;
#   2. the control: 15 GETs of /health → all 200. Without it a burst of 429s
#      proves only that SOMETHING is being refused, which is equally
#      consistent with having broken the API (the 89 rule);
#   3. the direct door: /providers on the *.run.app URL → 403 `origin_required`,
#      /health → 200, and the OLDER alias also → 403 (§11 open question 4);
#   4. `cf-ray` on the public hostname — the request went through Cloudflare;
#   5. both uptime checks exist AND reported passes in the last 30 minutes —
#      Google's probes are not being challenged by the proxy (§11 question 3);
#   6. an OPTIONS preflight from https://admin.myweli.com returns
#      `access-control-allow-origin` — the Worker forwards OPTIONS with the
#      header, so CORS still answers;
#   7. a GET with the Dart HTTP client's User-Agent → 200 — the Browser
#      Integrity Check question, answered with the client the apps ship;
#   8. (opt-in, RUN_CRON=1) a forced run of the `myweli-reminders` Scheduler
#      job succeeds through Cloudflare → Worker → origin. Staging cannot
#      rehearse this path: its audience is its own run.app URL.
#
# ## READ-ONLY, with ONE named exception
#
# Every call here is a GET, an OPTIONS, a POST to a route whose job is to be
# probed, or a gcloud read. backend/test/infra/front_door_scripts_test.dart
# greps this file for mutating gcloud verbs, comments included (a commented-out
# call is a line someone uncomments at 2am), and fails if one appears.
#
# The one exception is `gcloud scheduler jobs run`, which does mutate: it
# enqueues one execution of the reminder cron. It is the rehearsal §9 step 8
# requires, it runs ONLY behind RUN_CRON=1, and the same pin holds that it
# appears nowhere else in this file. Default off, so that running this script
# on a whim never dispatches a reminder.
#
# ## The burst is PACED, and why
#
# The edge rule (§5.4) blocks after the 10th request in a 10-second window,
# with an HTML answer. This check wants the APP's answer — the authoritative
# 10/minute — so the 15 POSTs are spaced 1.2 s apart: at most 9 land in any
# 10-second window, and the 11th meets the app limiter rather than the edge.
# An HTML 429 here is therefore reported as a FAIL naming the edge, not waved
# through as "some 429".
#
# The app limiter's window is a FIXED calendar minute (`windowStart` floors to
# the epoch), not a sliding one. A burst that starts at second 48 straddles two
# windows and no window sees 11 hits — a false FAIL that names three wrong
# causes. So the burst waits for the top of a minute first, and prints the
# second it started on.
#
#   bash infra/gcp/72-verify-front-door.sh
#   RUN_CRON=1 bash infra/gcp/72-verify-front-door.sh    # with the cron rehearsal
set -uo pipefail

PROJECT="${PROJECT:-myweli}"
REGION=europe-west9
HOST=https://api.myweli.com
DIRECT=https://myweli-api-5a24ymhbbq-od.a.run.app
ALIAS=https://myweli-api-731308991240.europe-west9.run.app
DART_UA='Dart/3.5 (dart:io)'
CURL=(curl -s --max-time 20)

COUNT=0
fails=0
ok()   { COUNT=$((COUNT + 1)); echo "  ok    $*"; }
FAIL() { COUNT=$((COUNT + 1)); fails=$((fails + 1)); echo "  FAIL  $*"; }

BODY=$(mktemp)
trap 'rm -f "${BODY}"' EXIT

echo "Front door acceptance — ${HOST}, project ${PROJECT}"
echo

# ---------------------------------------------------------------------------
# 1. The per-IP limit, from this address, paced (see header).
# ---------------------------------------------------------------------------
echo "1. per-IP limit on /auth/email/otp/request (15 POSTs, 1.2 s apart)"
# Wait for the top of a UTC minute so all 15 land in ONE fixed window.
if (( 10#$(date -u +%S) > 5 )); then
  echo "      aligning to the next minute (the limiter's window is a fixed calendar minute)…"
  while (( 10#$(date -u +%S) > 5 )); do sleep 1; done
fi
echo "      started at second $(date -u +%S) of $(date -u +%H:%M)"
CODES=""
NON429=0
JSON429=0
OTHER429=0
for i in $(seq 1 15); do
  CODE=$("${CURL[@]}" -o "${BODY}" -w '%{http_code}' \
    -X POST "${HOST}/auth/email/otp/request" \
    -H 'content-type: application/json' \
    -d "{\"email\":\"rl-probe-$i@example.test\"}" || echo "000")
  CODES="${CODES}${CODE} "
  if [[ "${CODE}" == "429" ]]; then
    if grep -q '"rate_limited"' "${BODY}"; then
      JSON429=$((JSON429 + 1))
    else
      OTHER429=$((OTHER429 + 1))
    fi
  else
    NON429=$((NON429 + 1))
  fi
  sleep 1.2
done
echo "      ${CODES}"
if (( NON429 < 1 )); then
  FAIL "every POST was refused — the burst never reached the route (or this address is already banned); no proof the route works"
elif (( JSON429 < 1 )); then
  FAIL "no 429 with the rate_limited envelope — the app limiter did not refuse (ORIGIN_AUTH_MODE log? CF-Connecting-IP absent? limit raised?)"
elif (( OTHER429 > 0 )); then
  FAIL "${OTHER429} 429(s) WITHOUT the JSON envelope — the EDGE rule answered (HTML), so the app's authoritative limit was not observed"
else
  ok "${NON429} accepted, then ${JSON429} × 429 {\"error\":\"rate_limited\"}"
fi

# ---------------------------------------------------------------------------
# 2. The control.
# ---------------------------------------------------------------------------
echo "2. control: 15 GETs of /health"
CODES=""
BAD=0
for _ in $(seq 1 15); do
  CODE=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "${HOST}/health" || echo "000")
  CODES="${CODES}${CODE} "
  [[ "${CODE}" == "200" ]] || BAD=$((BAD + 1))
done
echo "      ${CODES}"
if (( BAD > 0 )); then
  FAIL "${BAD} of 15 /health GETs were not 200 — the limit (or the edge rule) is matching more than /auth/"
else
  ok "15 × 200"
fi

# ---------------------------------------------------------------------------
# 3. The direct door — both aliases.
# ---------------------------------------------------------------------------
echo "3. the direct door"
CODE=$("${CURL[@]}" -o "${BODY}" -w '%{http_code}' "${DIRECT}/providers" || echo "000")
if [[ "${CODE}" == "403" ]] && grep -q 'origin_required' "${BODY}"; then
  ok "${DIRECT}/providers → 403 origin_required"
else
  FAIL "${DIRECT}/providers → ${CODE} $(head -c 120 "${BODY}") — expected 403 origin_required; the reopened door is not closed"
fi
CODE=$("${CURL[@]}" -o /dev/null -w '%{http_code}' "${DIRECT}/health" || echo "000")
if [[ "${CODE}" == "200" ]]; then
  ok "${DIRECT}/health → 200 (the liveness probe's path stays open)"
else
  FAIL "${DIRECT}/health → ${CODE}, expected 200"
fi
CODE=$("${CURL[@]}" -o "${BODY}" -w '%{http_code}' "${ALIAS}/providers" || echo "000")
if [[ "${CODE}" == "403" ]]; then
  ok "${ALIAS}/providers → 403 (the older alias is gated too)"
else
  FAIL "${ALIAS}/providers → ${CODE}, expected 403 — the older run.app alias is a way around the gate"
fi

# ---------------------------------------------------------------------------
# 4. Through Cloudflare.
# ---------------------------------------------------------------------------
echo "4. cf-ray on the public hostname"
HEAD=$(curl -sI --max-time 20 "${HOST}/health" || true)
if grep -qi '^cf-ray:' <<< "${HEAD}"; then
  ok "${HOST}/health carries cf-ray"
else
  FAIL "${HOST}/health carries no cf-ray — the record is not proxied, or Cloudflare is not answering"
fi

# ---------------------------------------------------------------------------
# 5. The uptime checks: present, and passing.
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# 4b. Plain http:// must be redirected to https:// on THIS hostname — the
# load balancer's redirect url-map did it; now the Worker (or Always Use
# HTTPS at the edge) must. A redirect naming the run.app host would send the
# client to the direct door and a 403.
# ---------------------------------------------------------------------------
echo "4b. http://api.myweli.com/health → 301 to https:// on the same hostname"
RES=$(curl -s -o /dev/null --max-time 20 -w '%{http_code} %{redirect_url}' "http://api.myweli.com/health" || echo "000")
RCODE=${RES%% *}
RURL=${RES#* }
case "${RCODE}" in
  301 | 302 | 307 | 308)
    if [[ "${RURL}" == https://api.myweli.com/* ]]; then
      ok "http:// → ${RCODE} ${RURL}"
    else
      FAIL "http:// → ${RCODE} to '${RURL}' — the redirect must stay on api.myweli.com, never name the run.app host"
    fi
    ;;
  *) FAIL "http://api.myweli.com/health → ${RCODE} — expected a redirect to https://" ;;
esac

echo "5. uptime checks"
CONFIGS=$(gcloud monitoring uptime list-configs --project="${PROJECT}" \
  --format='value(name)' 2>/dev/null || true)
for NAME in api-health api-providers-database; do
  if grep -q "/${NAME}-" <<< "${CONFIGS}"; then
    ok "uptime check ${NAME} exists"
  else
    FAIL "uptime check ${NAME} not found in list-configs"
  fi
done

# The pattern 80-uptime-checks.sh uses to prove a check actually reports:
# read the check_passed series over the last 30 minutes (six rounds of a
# 5-minute check) and count true/false per check id.
START=$(date -u -v-30M +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -d '30 minutes ago' +%Y-%m-%dT%H:%M:%SZ)
END=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SERIES=$(curl -s -G --max-time 30 \
  -H "Authorization: Bearer $(gcloud auth print-access-token 2>/dev/null)" \
  "https://monitoring.googleapis.com/v3/projects/${PROJECT}/timeSeries" \
  --data-urlencode 'filter=metric.type="monitoring.googleapis.com/uptime_check/check_passed" AND resource.type="uptime_url"' \
  --data-urlencode "interval.startTime=${START}" \
  --data-urlencode "interval.endTime=${END}" 2>/dev/null \
  | python3 -c '
import json, sys, collections
d = json.load(sys.stdin)
a = collections.defaultdict(lambda: [0, 0])
for s in d.get("timeSeries", []):
    cid = s["metric"]["labels"]["check_id"]
    for p in s.get("points", []):
        a[cid][0 if p["value"]["boolValue"] else 1] += 1
for k, v in sorted(a.items()):
    print(f"{k} {v[0]} {v[1]}")
' 2>/dev/null || true)
for NAME in api-health api-providers-database; do
  LINE=$(grep "^${NAME}-" <<< "${SERIES}" || true)
  if [[ -z "${LINE}" ]]; then
    FAIL "uptime check ${NAME}: no check_passed points in the last 30 minutes — the probes are not reporting"
    continue
  fi
  PASSED=$(awk '{print $2}' <<< "${LINE}")
  FAILED=$(awk '{print $3}' <<< "${LINE}")
  if (( PASSED > 0 && FAILED == 0 )); then
    ok "uptime check ${NAME}: passed=${PASSED} failed=0 in the last 30 minutes"
  else
    FAIL "uptime check ${NAME}: passed=${PASSED} failed=${FAILED} — Google's probes are being refused or challenged"
  fi
done

# ---------------------------------------------------------------------------
# 6. CORS preflight from the admin console's origin.
# ---------------------------------------------------------------------------
echo "6. OPTIONS preflight from https://admin.myweli.com"
HEAD=$(curl -s -D - -o /dev/null --max-time 20 -X OPTIONS "${HOST}/providers" \
  -H 'Origin: https://admin.myweli.com' \
  -H 'Access-Control-Request-Method: GET' || true)
if grep -qi '^access-control-allow-origin:' <<< "${HEAD}"; then
  ok "preflight answered with access-control-allow-origin"
else
  FAIL "preflight carries no access-control-allow-origin — the Worker is not forwarding OPTIONS, or the gate refuses it before CORS"
fi

# ---------------------------------------------------------------------------
# 7. The Dart client's User-Agent.
# ---------------------------------------------------------------------------
echo "7. GET /health as '${DART_UA}'"
CODE=$("${CURL[@]}" -o /dev/null -w '%{http_code}' -A "${DART_UA}" "${HOST}/health" || echo "000")
if [[ "${CODE}" == "200" ]]; then
  ok "Dart User-Agent → 200 (not challenged)"
else
  FAIL "Dart User-Agent → ${CODE} — Browser Integrity Check or Bot Fight Mode is challenging the apps' HTTP client"
fi

# ---------------------------------------------------------------------------
# 8. THE ONE MUTATING CALL — opt-in. Forces one run of the reminder cron and
#    waits for the Scheduler to record the attempt.
# ---------------------------------------------------------------------------
if [[ "${RUN_CRON:-0}" == "1" ]]; then
  echo "8. forced run of myweli-reminders (RUN_CRON=1) — this dispatches the cron ONCE"
  BEFORE=$(gcloud scheduler jobs describe myweli-reminders --location="${REGION}" \
    --project="${PROJECT}" --format='value(lastAttemptTime)' 2>/dev/null || true)
  if gcloud scheduler jobs run myweli-reminders --location="${REGION}" --project="${PROJECT}" >/dev/null 2>&1; then
    AFTER=""
    STATE=""
    for _ in $(seq 1 12); do
      sleep 5
      AFTER=$(gcloud scheduler jobs describe myweli-reminders --location="${REGION}" \
        --project="${PROJECT}" --format='value(lastAttemptTime)' 2>/dev/null || true)
      [[ -n "${AFTER}" && "${AFTER}" != "${BEFORE}" ]] && break
    done
    if [[ -z "${AFTER}" || "${AFTER}" == "${BEFORE}" ]]; then
      FAIL "myweli-reminders: no new attempt recorded within 60 s of the forced run"
    else
      # `lastAttemptTime` moves at DISPATCH; `status` is written only when the
      # response arrives — reading it now would report the PREVIOUS attempt's
      # outcome. So the outcome is read where it is unambiguous: the service's
      # own request log, for a cron request stamped after the dispatch.
      HTTP_STATUS=""
      for _ in $(seq 1 9); do
        sleep 5
        HTTP_STATUS=$(gcloud logging read \
          "resource.type=\"cloud_run_revision\" AND resource.labels.service_name=\"myweli-api\" AND httpRequest.requestUrl:\"/internal/cron/reminders\" AND timestamp>=\"${AFTER}\"" \
          --project="${PROJECT}" --limit=1 --format='value(httpRequest.status)' 2>/dev/null | head -1 || true)
        [[ -n "${HTTP_STATUS}" ]] && break
      done
      if [[ "${HTTP_STATUS}" == "200" ]]; then
        ok "myweli-reminders dispatched at ${AFTER}; the service logged HTTP 200 for it (through the Worker)"
      elif [[ -z "${HTTP_STATUS}" ]]; then
        FAIL "myweli-reminders dispatched at ${AFTER} but no cron request reached the service's log within 45 s — refused at the edge or by the gate before Cloud Run saw it"
      else
        FAIL "myweli-reminders dispatched at ${AFTER}; the service logged HTTP ${HTTP_STATUS} — the OIDC call through the Worker was refused"
      fi
    fi
  else
    FAIL "gcloud could not force-run myweli-reminders"
  fi
else
  echo "8. cron rehearsal skipped (set RUN_CRON=1 to force one run of myweli-reminders)"
fi

# ---------------------------------------------------------------------------
# The vacuity floor. Without the cron, the checks above number 12; a run that
# performed fewer than 9 has lost a section to a parse error or a dead
# network, and must not read as a pass.
# ---------------------------------------------------------------------------
echo
if [[ "${COUNT}" -lt 9 ]]; then
  echo "::error:: only ${COUNT} checks ran."
  echo "::error:: Refusing to report success — a section above did not execute."
  exit 1
fi
if (( fails > 0 )); then
  echo "::error:: ${fails} of ${COUNT} checks FAILED — the front door is not serving what the spec says."
  exit 1
fi
echo "${COUNT} checks passed. The front door serves what docs/design/infra-cloudflare-front-door.md §8 says."
