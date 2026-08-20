#!/usr/bin/env bash
#
# Push the runbook text in this repo onto the LIVE alert policies.
#
# ## Why this script has to exist
#
# Every 8x/9x script here only ever calls `policies create`. A policy's identity
# is the numeric id assigned at creation, not its displayName, so re-running one
# against an existing policy fails. That makes the repo unable to reproduce
# production: when the runbooks were last corrected (2026-08-19, see
# backend-email-send-budget.md 8.3) it was done with a hand-written REST PATCH
# that was never committed, and the drift it fixed was invisible again the next day.
#
# ## What it changes, and what it must not
#
# ONLY `documentation.content`. `gcloud alpha monitoring policies update` with
# `--documentation-from-file` and NO `--policy-from-file` does a read-modify-write
# and sends `updateMask=documentation.content` - narrower even than the
# `updateMask=documentation` used in August, because it cannot touch mimeType.
#
# Passing `--policy-from-file` instead would send updateMask=None, a FULL
# REPLACE, and silently drop alertStrategy, notificationChannels and conditions.
# `--fields` does not help: it accepts only `disabled` and `notificationChannels`,
# and requires the policy body it is trying to avoid.
#
# The proof is not the flag name, it is the read-back: this script captures each
# policy before and after and FAILS if anything other than the documentation
# moved.
# ## DRY=1 is the drift detector
#
# `DRY=1 bash infra/gcp/93-sync-runbooks.sh` writes nothing and prints, per
# policy, whether the live text still matches the repo. Run it whenever a runbook
# changes, and after any incident that made someone edit a policy in the console.
#
# This is the check August did not have. The runbooks were corrected on
# 2026-08-19 by a PATCH nobody committed, and by the next day nothing in the repo
# could tell you whether production still carried that text - which is precisely
# how the same class of defect was found again from a delivered email rather than
# from a test.
#
# The guard in backend/test/infra/alert_runbooks_test.dart checks the SCRIPTS.
# Only this dry run checks the LIVE POLICIES, and only it would notice a run that
# stopped halfway.
set -euo pipefail

PROJECT=myweli
DRY=${DRY:-0}
WORK=$(mktemp -d)
BACKUP=${BACKUP_DIR:-/tmp/runbook-backup-$$}
mkdir -p "${BACKUP}"
DONE=()
# The run is NOT atomic: it patches one policy at a time and stops on the first
# failure. It IS idempotent - a policy already matching the repo is skipped - so
# the recovery for a partial run is to fix the cause and run it again. The
# pre-patch capture of every policy touched is kept, so a rollback is possible.
on_exit() {
  local rc=$?
  rm -rf "${WORK}"
  if (( rc != 0 )); then
    echo >&2
    echo "FAILED after patching ${#DONE[@]}: ${DONE[*]:-none}" >&2
    echo "Pre-patch captures kept in ${BACKUP}" >&2
    echo "This script is idempotent - fix the cause and re-run it." >&2
  fi
}
trap on_exit EXIT

# --- the policy bodies, rendered exactly as their authoring script renders them
render() { # $1 script, rest: VAR=VALUE
  local script=$1; shift
  local body="${WORK}/render.sh"
  # The heredoc alone is not the policy. Filters interpolate shell variables —
  # ${SERVICES} names both Cloud Run services — and rendering without them
  # produced `... AND  AND ...`, which read as drift on three policies that were
  # perfectly correct. A check that compares the wrong string is worse than none,
  # so the simple single-quoted assignments are carried across too.
  {
    grep -E "^[A-Z][A-Z_]*='[^']*'\$" "${script}" || true
    sed -n '/^ *cat > /,/^JSON$/p' "${script}" \
      | sed -E 's|^ *cat > "?[^ "]*\.json"? |cat |'
  } > "${body}"
  env "$@" bash "${body}"
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
  INTENDED+=("${found[@]}")
  n=$((n+1))
}

add infra/gcp/85-db-capacity-alert.sh INSTANCE=myweli-db
add infra/gcp/85-db-capacity-alert.sh INSTANCE=myweli-db-staging
add infra/gcp/86-cron-auth-alert.sh
add infra/gcp/88-email-budget-alert.sh
add infra/gcp/91-armor-deny-alert.sh
add infra/gcp/92-identity-limit-alert.sh
add infra/gcp/94-identity-warning-alert.sh

echo "rendered ${#INTENDED[@]} policy bodies from the repo"
echo

CHANGED=0; SKIPPED=0; FILTER_DRIFT=0
for f in "${INTENDED[@]}"; do
  DISPLAY=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["displayName"])' "${f}")
  WANT=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1]))["documentation"]["content"])' "${f}")
  WANT_FILTER=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print("\\n".join(c["conditionMatchedLog"]["filter"] for c in d["conditions"] if "conditionMatchedLog" in c))' "${f}")

  ID=$(gcloud alpha monitoring policies list --project="${PROJECT}" \
        --filter="displayName=\"${DISPLAY}\"" --format='value(name)')
  if [[ -z "${ID}" ]]; then
    echo "  MISSING  ${DISPLAY}"
    echo "           no live policy with this displayName - run its create script first."
    exit 1
  fi
  if [[ $(wc -l <<< "${ID}") -ne 1 ]]; then
    echo "  AMBIGUOUS ${DISPLAY} matches more than one policy:"; echo "${ID}"; exit 1
  fi

  SLUG=$(python3 -c 'import re,sys;print(re.sub(r"[^a-z0-9]+","-",sys.argv[1].lower()).strip("-"))' "${DISPLAY}")
  BEFORE="${BACKUP}/${SLUG}.before.json"
  AFTER="${WORK}/${SLUG}.after.json"
  gcloud alpha monitoring policies describe "${ID}" --project="${PROJECT}" \
    --format=json > "${BEFORE}"

  # THE FILTER IS THE HALF THAT DECIDES WHETHER AN ALERT CAN FIRE AT ALL, and
  # until 2026-08-20 this script did not look at it. A policy shipped with an
  # unanchored filter, the repo was corrected, and the drift check said "same"
  # because it only ever compared documentation.
  #
  # It is reported, not patched. Changing a filter means replacing the whole
  # policy, which regenerates condition IDs unless done as a read-modify-write —
  # a different and riskier operation than swapping a text field. Detection is
  # the half that must never be silent; the fix stays deliberate.
  HAVE_FILTER=$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print("\\n".join(c["conditionMatchedLog"]["filter"] for c in d["conditions"] if "conditionMatchedLog" in c))' "${BEFORE}")
  if [[ "${HAVE_FILTER}" != "${WANT_FILTER}" ]]; then
    echo "  FILTER DRIFT  ${DISPLAY}"
    echo "        live: ${HAVE_FILTER}"
    echo "        repo: ${WANT_FILTER}"
    FILTER_DRIFT=$((FILTER_DRIFT+1))
  fi
  HAVE=$(python3 -c 'import json,sys;print((json.load(open(sys.argv[1])).get("documentation") or {}).get("content",""))' "${BEFORE}")

  # An empty render would BLANK the live runbook, and the read-back below would
  # cheerfully certify it: got == want, both empty. gcloud does not treat an
  # empty file as "no change" either. So the floor is asserted before writing.
  if [[ ${#WANT} -lt 200 ]]; then
    echo "  REFUSING ${DISPLAY}: rendered documentation is only ${#WANT} chars." >&2
    echo "           That is a broken render, not a short runbook." >&2
    exit 1
  fi
  # Balanced backticks prove the escaping survived the heredoc rather than the
  # shell having executed a span and swallowed part of the text.
  TICKS=$(python3 -c 'import sys;print(sys.argv[1].count(chr(96)))' "${WANT}")
  if (( TICKS % 2 )); then
    echo "  REFUSING ${DISPLAY}: ${TICKS} backticks - an unclosed code span." >&2
    exit 1
  fi

  if [[ "${HAVE}" == "${WANT}" ]]; then
    echo "  same     ${DISPLAY}"; SKIPPED=$((SKIPPED+1)); continue
  fi

  printf '%s' "${WANT}" > "${WORK}/${SLUG}.doc.md"
  if [[ "${DRY}" == "1" ]]; then
    echo "  WOULD    ${DISPLAY}  (${#HAVE} -> ${#WANT} chars)"; CHANGED=$((CHANGED+1)); continue
  fi

  gcloud alpha monitoring policies update "${ID}" --project="${PROJECT}" \
    --documentation-from-file="${WORK}/${SLUG}.doc.md" --quiet >/dev/null

  gcloud alpha monitoring policies describe "${ID}" --project="${PROJECT}" \
    --format=json > "${AFTER}"

  # The read-back IS the evidence. Two claims, checked separately:
  #   1. the documentation is now byte-identical to the repo
  #   2. NOTHING else moved
  python3 - "${BEFORE}" "${AFTER}" "${WORK}/${SLUG}.doc.md" <<'PY'
import json,sys
before=json.load(open(sys.argv[1])); after=json.load(open(sys.argv[2]))
want=open(sys.argv[3]).read()
got=(after.get('documentation') or {}).get('content','')
assert got==want, 'documentation did NOT take: stored %d chars, wanted %d' % (len(got),len(want))
b=dict(before); a=dict(after)
for k in ('documentation','mutationRecord','mutationRecords'): b.pop(k,None); a.pop(k,None)
if b!=a:
    diff=[k for k in set(b)|set(a) if b.get(k)!=a.get(k)]
    raise SystemExit('CLOBBERED fields: %s' % diff)
mt=(after.get('documentation') or {}).get('mimeType')
assert mt=='text/markdown', 'mimeType became %r' % mt
PY
  echo "  patched  ${DISPLAY}  (${#HAVE} -> ${#WANT} chars, nothing else moved)"
  DONE+=("${DISPLAY}")
  CHANGED=$((CHANGED+1))
done

echo
echo "changed: ${CHANGED}   already correct: ${SKIPPED}   filter drift: ${FILTER_DRIFT}"
if (( FILTER_DRIFT > 0 )); then
  echo
  echo "A FILTER DIFFERS BETWEEN THE REPO AND THE LIVE POLICY."
  echo "This script does not patch filters - it reports them. Fix one with a"
  echo "read-modify-write, which preserves the condition's generated id:"
  echo
  echo "  ID=\$(gcloud alpha monitoring policies list --project=${PROJECT} \\"
  echo "        --filter='displayName=\"<NAME>\"' --format='value(name)')"
  echo "  gcloud alpha monitoring policies describe \"\$ID\" --project=${PROJECT} --format=json > /tmp/p.json"
  echo "  # edit conditions[].conditionMatchedLog.filter, drop creationRecord and mutationRecord"
  echo "  gcloud alpha monitoring policies update \"\$ID\" --project=${PROJECT} --policy-from-file=/tmp/p.json"
  echo
  echo "Then read it back and assert the condition id and every other field are"
  echo "unchanged - a careless full replace regenerates condition ids."
  exit 1
fi
[[ "${DRY}" == "1" ]] && echo "(DRY=1 - nothing was written)"
echo
cat <<'NOTE'
STILL UNPROVEN, and only an email can settle it: that a markdown code span
suppresses the TYPOGRAPHIC substitutions (en dash, curly quotes) as well as
emphasis. A delivered <code> tag proves spans render; the span we observed
contained no hazard characters. Trigger one alert and read the mail - the
command in it either pastes or it does not.
NOTE
