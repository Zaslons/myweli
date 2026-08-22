#!/usr/bin/env bash
#
# Does the live Cloud Logging configuration still keep the promise the privacy
# policy makes to users?
#
# Exit 0 = the live buckets satisfy infra/gcp/logging-manifest.json.
# Exit 1 = drift, listed.
#
# ## Why this exists
#
# web/app/politique-confidentialite/page.tsx states « Ces journaux ... sont
# supprimés automatiquement au bout de 30 jours ». Nothing watched the bucket.
# Raising retention to 400 days would have left the whole suite green while a
# published legal claim became false — the failure class this repo already
# names: « une négation qui vieillit devient un mensonge ».
#
# ## READ-ONLY, and that is enforced rather than promised
#
# This script only ever calls `gcloud logging buckets describe`.
# backend/test/infra/log_retention_test.dart greps it for mutating verbs and
# fails if one appears, the same way r2_manifest_test.dart guards
# infra/cloudflare/95-verify-r2.sh. A commented-out `buckets update` is a line
# someone uncomments at 2am.
#
# ## The footgun this had to be written around
#
# `describe` OMITS `locked` entirely when it is false — it is not `false`, it is
# absent. The control is `_Required`, which GCP always locks and which does
# print `locked: true`. A naive [[ "$LOCKED" == "false" ]] compares against an
# empty string and passes for the wrong reason, which is a check that cannot
# fire dressed as one that can.
set -uo pipefail

PROJECT="${PROJECT:-myweli}"
MANIFEST="${LOGGING_MANIFEST:-$(dirname "${BASH_SOURCE[0]}")/logging-manifest.json}"

fails=0
fail() { echo "  ✗ $*"; fails=$((fails + 1)); }
ok()   { echo "  ✓ $*"; }

if [[ ! -f "${MANIFEST}" ]]; then
  echo "::error:: manifest not found: ${MANIFEST}"
  exit 1
fi

BUCKETS=$(python3 -c "
import json,sys
d=json.load(open('${MANIFEST}'))
for name, b in d['buckets'].items():
    print('%s\t%s\t%s\t%s' % (name, b['location'], b['maxRetentionDays'], b['mustNotBeLocked']))
") || { echo "::error:: could not read ${MANIFEST}"; exit 1; }

if [[ -z "${BUCKETS}" ]]; then
  # A manifest that names no bucket would make every check below vacuous, and
  # the script would exit 0 having verified nothing at all.
  echo "::error:: the manifest names no buckets — refusing to report success"
  exit 1
fi

echo "Cloud Logging retention, project ${PROJECT}"
echo

while IFS=$'\t' read -r NAME LOCATION MAXDAYS MUSTNOTLOCK; do
  [[ -z "${NAME}" ]] && continue
  echo "${NAME} (${LOCATION})"

  LIVE=$(gcloud logging buckets describe "${NAME}" \
           --location="${LOCATION}" --project="${PROJECT}" --format=json 2>&1)
  if [[ $? -ne 0 ]]; then
    # Never suppressed: a permission error and a policy violation must not look
    # the same, and the message is the thing that tells them apart.
    echo "::error:: cannot read ${NAME}: ${LIVE}"
    fails=$((fails + 1))
    continue
  fi

  DAYS=$(printf '%s' "${LIVE}" | python3 -c "import json,sys; print(json.load(sys.stdin).get('retentionDays','MISSING'))")
  # Absent means false. Read it as a tri-state rather than a string compare.
  LOCKED=$(printf '%s' "${LIVE}" | python3 -c "import json,sys; print('true' if json.load(sys.stdin).get('locked') else 'false')")

  if [[ "${DAYS}" == "MISSING" ]]; then
    fail "retentionDays absent from the response — cannot verify the promise"
  elif (( DAYS > MAXDAYS )); then
    fail "retention is ${DAYS} days, manifest ceiling is ${MAXDAYS} — the privacy policy says « au bout de ${MAXDAYS} jours » and that sentence is now false"
  else
    ok "retention ${DAYS} days, at or under the ${MAXDAYS}-day ceiling the policy promises"
  fi

  if [[ "${MUSTNOTLOCK}" == "True" && "${LOCKED}" == "true" ]]; then
    fail "the bucket is LOCKED — that is irreversible, and the manifest records the decision not to"
  else
    ok "not locked (locked=${LOCKED})"
  fi
  echo
done <<< "${BUCKETS}"

if (( fails > 0 )); then
  echo "::error:: ${fails} check(s) failed — the live configuration no longer matches infra/gcp/logging-manifest.json"
  exit 1
fi
echo "Live logging configuration matches the manifest."
