#!/usr/bin/env bash
#
# The identity the daily production checks use to read log-bucket CONFIGURATION
# — and nothing else.
#
# (It has since gained two more narrow roles, each for one check: secret
# version METADATA from 42-iam-secret-pins-sa.sh, and the project's IAM policy
# from the section at the end of this file. It still reads no log entry, no
# secret value, and writes nothing.)
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

# ## A third role, added 2026-11-11: read the project's IAM policy
#
# `43-verify-project-iam.sh` fails the daily checks when a broad grant comes
# back: Owner or Editor for anyone but the owner, or Token Creator / Service
# Account User on the whole project. Google's automation added two such grants
# on 2026-08-05 and they were removed on 2026-11-11 (DEPLOYMENT.md § Phase C,
# « Project IAM »). Reading the policy needs one permission, and it is the only
# call that script makes:
#
#   resourcemanager.projects.getIamPolicy
#
# Not roles/iam.securityReviewer: it is predefined, so Google can add to it,
# and it reads every IAM policy in the project, not this one. Not a widening of
# the two roles above, for the reason 42-iam-secret-pins-sa.sh gives: each
# control in production-checks.yml names the role it is about. And never
# setIamPolicy: a checker that can change what it checks is not a check. The
# daily job asks Google, every run, whether this identity can.
#
# Measured before the grant (2026-11-11, Policy Analyzer, fully explored): no
# binding gives this identity getIamPolicy. The control in the same query,
# logging.buckets.get, resolved to logBucketConfigReader.
#
# The two commands, run on the owner's yes on 2026-11-11 (audit log:
# CreateRole 21:14:39Z, SetIamPolicy 21:14:42Z). Read back: exactly this one
# role–member pair added, nothing removed.
#
#   gcloud iam roles create projectIamPolicyReader --project=myweli --file=<the YAML below>
#   gcloud projects add-iam-policy-binding myweli \
#     --member=serviceAccount:myweli-checks@myweli.iam.gserviceaccount.com \
#     --role=projects/myweli/roles/projectIamPolicyReader --condition=None
#
# Reversible: remove the binding, then delete the role.
POLICY_ROLE_ID="projectIamPolicyReader"

echo "==> Custom role: ${POLICY_ROLE_ID}"
cat > /tmp/iam-policy-reader-role.yaml <<'YAML'
title: Project IAM Policy Reader
description: >-
  Reads this project's IAM policy, who holds which role, so the daily checks
  can tell whether a broad grant has come back. Deliberately excludes
  resourcemanager.projects.setIamPolicy: a checker that can change what it
  checks is not a check.
stage: GA
includedPermissions:
- resourcemanager.projects.getIamPolicy
YAML
if gcloud iam roles describe "${POLICY_ROLE_ID}" --project="${PROJECT}" >/dev/null 2>&1; then
  gcloud iam roles update "${POLICY_ROLE_ID}" --project="${PROJECT}" \
    --file=/tmp/iam-policy-reader-role.yaml -q >/dev/null
  echo "    updated"
else
  gcloud iam roles create "${POLICY_ROLE_ID}" --project="${PROJECT}" \
    --file=/tmp/iam-policy-reader-role.yaml -q >/dev/null
  echo "    created"
fi
rm -f /tmp/iam-policy-reader-role.yaml

echo "==> Binding it to ${SA}"
gcloud projects add-iam-policy-binding "${PROJECT}" \
  --member="serviceAccount:${SA}" \
  --role="projects/${PROJECT}/roles/${POLICY_ROLE_ID}" --condition=None -q >/dev/null
echo "    ${POLICY_ROLE_ID}"

echo
echo "Roles now held by ${SA}:"
gcloud projects get-iam-policy "${PROJECT}" --flatten="bindings[].members" \
  --filter="bindings.members:${SA}" --format="value(bindings.role)" | sed 's/^/  /'
