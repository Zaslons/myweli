#!/usr/bin/env bash
#
# A SECOND custom role for the daily-checks identity: read secret version
# METADATA, and nothing else.
#
# ## Why a second role rather than widening the first
#
# `41-iam-checks-sa.sh` deliberately gives `myweli-checks@` one role with two
# permissions, and `production-checks.yml` runs a DAILY NEGATIVE CONTROL that
# fails the build if that identity is ever widened — "this identity READ A LOG
# ENTRY. The custom role has been widened." Widening the log role to carry
# secret permissions would make that control's message a lie and blur two
# unrelated grants into one.
#
# So the identity ends up holding two narrow roles instead of one broad one, and
# each control names the role it is about.
#
# ## Why not roles/secretmanager.viewer
#
# It is close, and it is a PREDEFINED role: Google can add permissions to it
# without asking, and the whole argument here is that this identity cannot read
# a secret VALUE. A custom role cannot change under us.
#
# ## Metadata is not the secret
#
# `versions.get` and `versions.list` return a version NUMBER and a STATE.
# `versions.access` returns the value, and is deliberately absent. That
# distinction is the entire point of this file, so production-checks.yml proves
# it with a refusal rather than asserting it — an argument nobody has tested is
# a claim, not a control.
#
# Idempotent. Safe to re-run.
set -euo pipefail

PROJECT="${PROJECT:-myweli}"
SA="myweli-checks@${PROJECT}.iam.gserviceaccount.com"
ROLE_ID="secretVersionLister"

echo "==> Custom role: ${ROLE_ID}"
cat > /tmp/secret-pins-role.yaml <<'YAML'
title: Secret Version Lister
description: >-
  Reads Secret Manager version METADATA — the version number and its state —
  so the daily checks can tell whether the versions the service manifests pin
  are still enabled and still newest. Deliberately excludes
  secretmanager.versions.access, which returns the secret VALUE.
stage: GA
includedPermissions:
- secretmanager.secrets.get
- secretmanager.secrets.list
- secretmanager.versions.get
- secretmanager.versions.list
YAML
if gcloud iam roles describe "${ROLE_ID}" --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud iam roles update "${ROLE_ID}" --project="${PROJECT}" \
    --file=/tmp/secret-pins-role.yaml -q >/dev/null
  echo "    updated"
else
  gcloud iam roles create "${ROLE_ID}" --project="${PROJECT}" \
    --file=/tmp/secret-pins-role.yaml -q >/dev/null
  echo "    created"
fi
rm -f /tmp/secret-pins-role.yaml

echo "==> Binding it to ${SA}"
# The service account itself is created by 41-iam-checks-sa.sh; this script adds
# a role to an identity that already exists rather than duplicating it.
gcloud iam service-accounts describe "${SA}" --project="${PROJECT}" >/dev/null 2>&1 || {
  echo "::error::${SA} does not exist. Run 41-iam-checks-sa.sh first." >&2
  exit 1
}
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA}" \
  --role="projects/${PROJECT}/roles/${ROLE_ID}" --condition=None -q >/dev/null
echo "    ${ROLE_ID}"

# **The deployer gets the same role, and only this one.**
#
# The deploy workflow refuses to replace the service when a manifest pins a
# version that is stale or disabled, which needs the same metadata read. That is
# strictly narrower than what myweli-deployer@ already holds — it has run.admin,
# so it can replace the whole service — and catching a bad pin BEFORE the deploy
# is worth more than catching it in the next day's monitor: whoever is deploying
# is mid-procedure and can fix it in a minute.
#
# A disabled pin would also fail at readiness, loudly. A STALE pin would not:
# the deploy succeeds and quietly serves the value nobody meant to be running.
DEPLOYER="myweli-deployer@${PROJECT}.iam.gserviceaccount.com"
echo "==> Binding it to ${DEPLOYER} as well"
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${DEPLOYER}" \
  --role="projects/${PROJECT}/roles/${ROLE_ID}" --condition=None -q >/dev/null
echo "    ${ROLE_ID}"

echo
echo "Roles now held by ${SA}:"
gcloud projects get-iam-policy "${PROJECT}" \
  --flatten="bindings[].members" \
  --filter="bindings.members:${SA}" \
  --format="value(bindings.role)" | sed 's/^/    /'

echo
echo "It can now read version metadata. It still cannot read a secret VALUE —"
echo "production-checks.yml proves that daily, by watching the refusal."
