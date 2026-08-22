#!/usr/bin/env bash
#
# The identity the daily production checks use to read log-bucket CONFIGURATION
# — and nothing else.
#
# ## Why not reuse the deployer, and why not roles/logging.viewer
#
# `production-checks.yml` needs to answer one question: is `_Default` still at
# 30 days, as the privacy policy tells users? Two obvious shortcuts are both
# wrong:
#
#   the deployer SA          holds run.admin project-wide. A daily cron should
#                            not be able to deploy.
#   roles/logging.viewer     grants logging.logEntries.list — it can read log
#                            ENTRIES, which on this service contain user IP
#                            addresses and user agents. Granting CI the ability
#                            to read production logs containing PII, in order to
#                            verify a PRIVACY setting, is a net loss.
#
# So: a separate service account holding one custom role with exactly two
# permissions. It can read the retention configuration and cannot read a single
# log line. Reversible with one `gcloud projects remove-iam-policy-binding`.
#
# Idempotent. Safe to re-run.
set -euo pipefail

PROJECT="${PROJECT:-myweli}"
SA="myweli-checks@${PROJECT}.iam.gserviceaccount.com"
ROLE_ID="logBucketConfigReader"
POOL_PROVIDER="projects/731308991240/locations/global/workloadIdentityPools/github/providers/myweli-repo"
REPO="${REPO:-Zaslons/myweli}"

echo "==> Custom role: ${ROLE_ID}"
cat > /tmp/log-reader-role.yaml <<'YAML'
title: Log Bucket Config Reader
description: >-
  Reads Cloud Logging bucket configuration (retention, lock state) and nothing
  else. Deliberately excludes logging.logEntries.list, because log entries on
  this project contain user IP addresses and user agents.
stage: GA
includedPermissions:
- logging.buckets.get
- logging.buckets.list
YAML
if gcloud iam roles describe "${ROLE_ID}" --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud iam roles update "${ROLE_ID}" --project="${PROJECT}" \
    --file=/tmp/log-reader-role.yaml -q >/dev/null
  echo "    updated"
else
  gcloud iam roles create "${ROLE_ID}" --project="${PROJECT}" \
    --file=/tmp/log-reader-role.yaml -q >/dev/null
  echo "    created"
fi
rm -f /tmp/log-reader-role.yaml

echo "==> Service account: ${SA}"
gcloud iam service-accounts describe "${SA}" --project="${PROJECT}" >/dev/null 2>&1 ||
  gcloud iam service-accounts create myweli-checks --project="${PROJECT}" \
    --display-name="Daily production checks (read-only)" -q
echo "    present"

echo "==> Binding the custom role, and only it"
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA}" \
  --role="projects/${PROJECT}/roles/${ROLE_ID}" --condition=None -q >/dev/null
echo "    ${ROLE_ID}"

echo "==> Letting the repo's workflows impersonate it (WIF)"
gcloud iam service-accounts add-iam-policy-binding "${SA}" --project="${PROJECT}" \
  --member="principalSet://iam.googleapis.com/${POOL_PROVIDER%/providers/*}/attribute.repository/${REPO}" \
  --role=roles/iam.workloadIdentityUser -q >/dev/null
echo "    workloadIdentityUser for ${REPO}"

echo
echo "Roles now held by ${SA}:"
gcloud projects get-iam-policy "${PROJECT}" --flatten="bindings[].members" \
  --filter="bindings.members:${SA}" --format="value(bindings.role)" | sed 's/^/  /'
