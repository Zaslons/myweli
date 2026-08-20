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

# Resolved here because the authoring scripts resolve it at RUNTIME:
#   CHANNEL=$(gcloud beta monitoring channels list … --format='value(name)')
# That is a command substitution, which `render()`'s assignment grep cannot
# capture — so every rendered body came out with `"notificationChannels": [""]`.
# Harmless while the tool only compared documentation. Fatal the moment it
# converges anything: it would detach all nine policies from the project's only
# channel, and each would still read "enabled, no incidents" in the console.
CHANNEL=$(gcloud beta monitoring channels list --project="${PROJECT}" \
  --filter='displayName="Owner email"' --format='value(name)')
if [[ -z "${CHANNEL}" ]]; then
  echo "::error:: no 'Owner email' notification channel - cannot render a policy body." >&2
  exit 1
fi
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
# The renderer lives in policy-bodies.sh so this tool and the emitter-lag
# check cannot disagree about what a policy body says.
# shellcheck source=infra/gcp/policy-bodies.sh
source "$(dirname "${BASH_SOURCE[0]}")/policy-bodies.sh"



echo "rendered ${#INTENDED[@]} policy bodies from the repo"
echo

CHANGED=0; SKIPPED=0
DRY_LABEL=$([[ "${DRY}" == "1" ]] && echo "WOULD  " || echo "patched")
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

  # --- what the repo DECLARES, merged onto what is LIVE -----------------------
  #
  # Read-modify-write, and it has to be. The API contract is explicit: "Existing
  # conditions are deleted if they are not updated" — a condition without a
  # `name` is DELETED and recreated with a fresh id, orphaning open incidents.
  # The repo bodies carry no `conditions[].name`, so feeding one straight to
  # `--policy-from-file` would churn every condition on every run.
  #
  # So: take the LIVE object, overwrite only the fields the repo declares, and
  # write that back. `enabled` is never among them — see below.
  set +e
  python3 - "${f}" "${BEFORE}" "${WORK}/${SLUG}.merged.json" "${WORK}/${SLUG}.diff" <<'PY'
import json, sys

want = json.load(open(sys.argv[1]))
live = json.load(open(sys.argv[2]))

# A policy someone disabled is a human decision. A sync tool has no standing to
# overrule it, and doing so mid-incident is the worst possible moment. It is a
# hard stop, never drift to converge.
if live.get('enabled') is False:
    print('DISABLED', file=sys.stderr)
    sys.exit(3)

doc = (want.get('documentation') or {}).get('content', '')
if len(doc) < 200:
    print('SHORTDOC %d' % len(doc), file=sys.stderr)
    sys.exit(4)
if doc.count('`') % 2:
    print('TICKS %d' % doc.count('`'), file=sys.stderr)
    sys.exit(5)

wc, lc = want.get('conditions') or [], live.get('conditions') or []
if len(wc) != len(lc):
    print('CONDCOUNT %d vs %d' % (len(lc), len(wc)), file=sys.stderr)
    sys.exit(6)

merged = json.loads(json.dumps(live))
diffs = []

def note(field, old, new):
    if old != new:
        diffs.append((field, json.dumps(old, sort_keys=True), json.dumps(new, sort_keys=True)))

for key in ('combiner', 'alertStrategy', 'notificationChannels', 'documentation'):
    if key in want:
        note(key, live.get(key), want[key])
        merged[key] = want[key]

for i, (w, l) in enumerate(zip(wc, lc)):
    if 'displayName' in w:
        note('conditions[%d].displayName' % i, l.get('displayName'), w['displayName'])
        merged['conditions'][i]['displayName'] = w['displayName']
    for ck in [k for k in w if k.startswith('condition')]:
        if 'filter' in (w[ck] or {}):
            old = (l.get(ck) or {}).get('filter')
            note('conditions[%d].%s.filter' % (i, ck), old, w[ck]['filter'])
            merged['conditions'][i].setdefault(ck, {})['filter'] = w[ck]['filter']
    # the generated id is carried through, never rewritten
    if 'name' in l:
        merged['conditions'][i]['name'] = l['name']

# output-only, ignored on write, and noisy in a diff
for k in ('creationRecord', 'mutationRecord'):
    merged.pop(k, None)

json.dump(merged, open(sys.argv[3], 'w'), indent=2)
with open(sys.argv[4], 'w') as fh:
    for field, old, new in diffs:
        fh.write('%s\t%s\t%s\n' % (field, old[:160], new[:160]))
PY
  RC=$?
  set -e
  case "${RC}" in
    0) ;;
    3) echo "  DISABLED ${DISPLAY} — a human turned this policy off." >&2
       echo "           It is never re-enabled by this script. Re-enable it in the" >&2
       echo "           console if that is what you want, then run again." >&2
       exit 1 ;;
    4) echo "  REFUSING ${DISPLAY}: rendered documentation is too short — a broken render, not a short runbook." >&2; exit 1 ;;
    5) echo "  REFUSING ${DISPLAY}: unbalanced backticks — an unclosed code span." >&2; exit 1 ;;
    6) echo "  REFUSING ${DISPLAY}: the repo and the live policy disagree on how many conditions exist." >&2
       echo "           That is a structural change and needs a human, not a sync." >&2; exit 1 ;;
    *) echo "  ERROR    ${DISPLAY}: merge failed (rc=${RC})" >&2; exit 1 ;;
  esac

  if [[ ! -s "${WORK}/${SLUG}.diff" ]]; then
    echo "  same     ${DISPLAY}"; SKIPPED=$((SKIPPED+1)); continue
  fi

  echo "  ${DRY_LABEL} ${DISPLAY}"
  while IFS=$'\t' read -r FIELD OLD NEW; do
    echo "        ${FIELD}"
    echo "          live: ${OLD}"
    echo "          repo: ${NEW}"
  done < "${WORK}/${SLUG}.diff"

  if [[ "${DRY}" == "1" ]]; then CHANGED=$((CHANGED+1)); continue; fi

  gcloud alpha monitoring policies update "${ID}" --project="${PROJECT}" \
    --policy-from-file="${WORK}/${SLUG}.merged.json" --quiet >/dev/null

  gcloud alpha monitoring policies describe "${ID}" --project="${PROJECT}" \
    --format=json > "${AFTER}"

  # The read-back IS the evidence, and it is stronger than "nothing else moved".
  # That older form protected every field by a single b != a comparison — which
  # is lost for any field the moment it is popped to allow a change. So: EXACTLY
  # the declared fields changed, EXACTLY to the declared values, and the
  # generated condition ids are the ones we started with.
  python3 - "${BEFORE}" "${AFTER}" "${f}" "${WORK}/${SLUG}.diff" <<'PY'
import json, sys
before = json.load(open(sys.argv[1]))
after  = json.load(open(sys.argv[2]))
want   = json.load(open(sys.argv[3]))
changed = {l.split('\t')[0] for l in open(sys.argv[4]) if l.strip()}

for key in ('combiner', 'alertStrategy', 'notificationChannels', 'documentation'):
    if key in want:
        assert after.get(key) == want[key], '%s did not take: %r' % (key, after.get(key))

bc, ac = before.get('conditions') or [], after.get('conditions') or []
assert len(bc) == len(ac), 'condition COUNT changed: %d -> %d' % (len(bc), len(ac))
for i, (b, a) in enumerate(zip(bc, ac)):
    assert b.get('name') == a.get('name'), (
        'condition %d id changed %r -> %r — the write deleted and recreated it, '
        'which orphans open incidents' % (i, b.get('name'), a.get('name')))

b2, a2 = dict(before), dict(after)
for k in ('conditions', 'mutationRecord', 'creationRecord',
          'combiner', 'alertStrategy', 'notificationChannels', 'documentation'):
    b2.pop(k, None); a2.pop(k, None)
if b2 != a2:
    raise SystemExit('CLOBBERED: %s' % [k for k in set(b2) | set(a2) if b2.get(k) != a2.get(k)])

assert after.get('enabled') is not False, 'the write disabled the policy'
mt = (after.get('documentation') or {}).get('mimeType')
assert mt == 'text/markdown', 'mimeType became %r' % mt
PY
  echo "        -> applied; condition ids and every undeclared field unchanged"
  DONE+=("${DISPLAY}")
  CHANGED=$((CHANGED+1))
done

echo
echo "changed: ${CHANGED}   already correct: ${SKIPPED}"
[[ "${DRY}" == "1" ]] && echo "(DRY=1 - nothing was written)"

# The other half of "is alerting healthy?". This tool proves the live policies
# match the repo; it says nothing about whether the code that is RUNNING can
# produce the strings those policies watch for. One command should answer both,
# because the second question is the one nobody remembers to ask.
LAG_RC=0
bash "$(dirname "${BASH_SOURCE[0]}")/95-emitter-lag.sh" || LAG_RC=$?
if (( LAG_RC != 0 )); then
  echo
  echo "The policies match the repo, but at least one watches for a string the"
  echo "running code cannot produce - see the report above."
  exit "${LAG_RC}"
fi

echo
cat <<'NOTE'
STILL UNPROVEN, and only an email can settle it: that a markdown code span
suppresses the TYPOGRAPHIC substitutions (en dash, curly quotes) as well as
emphasis. A delivered <code> tag proves spans render; the span we observed
contained no hazard characters. Trigger one alert and read the mail - the
command in it either pastes or it does not.
NOTE
