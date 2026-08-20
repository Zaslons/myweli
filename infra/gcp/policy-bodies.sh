#!/usr/bin/env bash
#
# One way to read a policy body, shared by every tool that needs one.
#
# There were two extractors before this file: `93-sync-runbooks.sh` rendered the
# script and parsed real JSON, while `alert_runbooks_test.dart` ran a regex over
# the raw text. The regex recovers the log literal but NOT which services the
# filter names, because it never interpolates `${SERVICES}` — and that
# distinction is the whole difference between "production is stale" and "staging
# is stale". A third extractor would be the drift this project keeps finding, so
# there is one, and it is this.
#
# Sourced, not executed. The caller must set PROJECT, and CHANNEL if it needs
# notificationChannels to be real.
set -euo pipefail

render() { # $1 script, rest: VAR=VALUE
  local script=$1; shift
  local body="${WORK}/render.sh"
  # The heredoc alone is not the policy. Filters interpolate shell variables —
  # ${SERVICES} names both Cloud Run services — and rendering without them
  # produced `... AND  AND ...`, which read as drift on three policies that were
  # perfectly correct. A check that compares the wrong string is worse than none,
  # so the simple single-quoted assignments are carried across too.
  #
  # Two of the scripts build their bodies inside a `for` loop — 85 over the two
  # database instances, 80 over the two uptime checks, which also sets TITLE and
  # DOC in a `case` the heredoc alone cannot see. In both the `policies create`
  # call sits AFTER the heredoc terminator, so the loop can be replayed up to
  # `JSON` and closed with a `done` that renders every body and creates nothing.
  local first_cat
  # `|| true` on both: a script with no loop makes grep exit 1, and under
  # `set -e` that killed the run before anything printed.
  first_cat=$({ grep -n '^ *cat > ' "${script}" || true; } | head -1 | cut -d: -f1)
  local loop_at=''
  if [[ -n "${first_cat}" ]]; then
    loop_at=$({ head -n "${first_cat}" "${script}" | grep -n '^for ' || true; } | tail -1 | cut -d: -f1)
  fi
  {
    # Simple assignments only — quoted literals and bare words. Anything with a
    # command substitution is resolved by the caller instead, because replaying
    # it here would run gcloud once per render.
    grep -E "^[A-Z][A-Z_]*=('[^']*'|[A-Za-z0-9._:-]+)\$" "${script}" || true
    if [[ -n "${loop_at}" ]]; then
      sed -n "${loop_at},/^JSON$/p" "${script}" \
        | sed -E 's|^ *cat > "?[^ "]*\.json"? |cat |'
      echo done
    else
      sed -n '/^ *cat > /,/^JSON$/p' "${script}" \
        | sed -E 's|^ *cat > "?[^ "]*\.json"? |cat |'
    fi
  } > "${body}"
  # PROJECT and CHANNEL are injected rather than grepped: the scripts set the
  # first bare (`PROJECT=myweli`) and the second by command substitution, and
  # neither form is a quoted literal. `85`'s threshold filter interpolates
  # PROJECT, so without this it rendered `database_id=":myweli-db"` against a
  # live `"myweli:myweli-db"` — drift reported against a correct production
  # policy, which is the renderer being wrong, not production.
  # Stderr is captured rather than left to leak. `80-uptime-checks.sh` looks up
  # its uptime CHECK_ID live, and the deploy service account has no monitoring
  # read — so in CI that produced two raw permission ERRORs inside a step that
  # then passed. Unexplained ERROR lines in a green step teach people to ignore
  # errors, which is the opposite of what a check is for. The caller reports
  # them once, in words.
  local errs="${WORK}/render.err"
  env PROJECT="${PROJECT}" CHANNEL="${CHANNEL}" "$@" bash "${body}" 2>"${errs}"
  if [[ -s "${errs}" ]]; then
    RENDER_NOTES+=("$(basename "${script}"): a live lookup this identity cannot make")
  fi
}

emit() { # split a stream of concatenated JSON objects into files
  python3 - "$1" "$2" <<'PY'
import json,sys
raw=open(sys.argv[1]).read(); dec=json.JSONDecoder(); i=0; n=0
while i < len(raw):
    while i < len(raw) and raw[i] in ' \n\t': i += 1
    if i >= len(raw): break
    obj,i = dec.raw_decode(raw,i)
    json.dump(obj, open(f'{sys.argv[2]}/policy-{n}.json','w')); n += 1
print(n)
PY
}

declare -a RENDER_NOTES=()
declare -a INTENDED=()
n=0
add() { # $1 script, rest env
  local s=$1; shift
  local d="${WORK}/r${n}"; mkdir -p "${d}"
  render "${s}" "$@" > "${d}/raw.json"
  emit "${d}/raw.json" "${d}" >/dev/null
  shopt -s nullglob
  local found=("${d}"/policy-*.json)
  shopt -u nullglob
  if [[ ${#found[@]} -eq 0 ]]; then
    echo "ERROR: ${s} rendered no policy body - the extraction is broken, not the script." >&2
    exit 1
  fi
  # The structural twin of the 200-char documentation floor below: an empty
  # value must be REFUSED, never written. A body with an empty channel would
  # silence the policy while leaving every observable sign of health intact.
  for b in "${found[@]}"; do
    if ! python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
ch=d.get("notificationChannels") or []
sys.exit(0 if ch and all(isinstance(c,str) and c.strip() for c in ch) else 1)' "${b}"; then
      echo "ERROR: ${s} rendered a body with an empty notificationChannels." >&2
      echo "       Writing it would detach the policy from its only channel." >&2
      exit 1
    fi
  done
  INTENDED+=("${found[@]}")
  n=$((n+1))
}

add infra/gcp/80-uptime-checks.sh
add infra/gcp/85-db-capacity-alert.sh
add infra/gcp/86-cron-auth-alert.sh
add infra/gcp/88-email-budget-alert.sh
add infra/gcp/91-armor-deny-alert.sh
add infra/gcp/92-identity-limit-alert.sh
add infra/gcp/94-identity-warning-alert.sh
