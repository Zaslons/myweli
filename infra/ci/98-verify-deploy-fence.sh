#!/usr/bin/env bash
# Is the deploy fence in place? Read-only.
# docs/design/infra-production-checks-on-time.md §4.4 (decision 268), B19.3b.
#
# WHY. B19.3 gives a GitHub App the right to start workflows, so that the daily
# production check starts at 06:00 instead of hours late. That right covers the
# deploy workflows too, and no line in a workflow file can hold it back: a
# dispatch runs any branch's copy of the file, and a re-run uses an old commit
# for 30 days. GitHub's environment rules hold whatever copy runs. This reads
# them back, as the owner set them in Settings → Environments:
#
#   backend-production  the owner must approve · `main` only
#   admin-production    the owner must approve · `main` only · holds the two
#                       Cloudflare secrets deploy-admin.yml reads
#   backend-staging     `main` only (staging is absent; a reviewer there would
#                       hold every merge's no-op run — spec §4.4)
#   the repository      holds NEITHER Cloudflare secret, so an old copy of
#                       deploy-admin.yml, which declares no environment, finds
#                       no token
#
# « Prevent self-review » must stay OFF, or the owner who dispatched could not
# approve their own deploy.
#
# WHAT IT NEEDS: `gh`, logged in as the owner. Listing secrets (names only, never
# values) needs admin on the repository, which a workflow's GITHUB_TOKEN does not
# have, so this runs from the owner's machine. Nothing here writes.
#
#   bash infra/ci/98-verify-deploy-fence.sh
#
# Exit 0 = every rule above holds. Exit 1 = it names each one that does not.
set -euo pipefail

OWNER_LOGIN=Zaslons
REPO=${GH_REPO:-Zaslons/myweli}

for tool in gh jq; do
  command -v "$tool" >/dev/null || { echo "::error:: $tool is required"; exit 1; }
done

FAILED=0
ok() { echo "    ✓ $1"; }
bad() { echo "    ✗ $1"; echo "::error:: $1"; FAILED=1; }

# api PATH — one GET; gh's own error goes to the terminal. Each caller turns a
# refusal into a failure, outside the subshell, so that it counts: « I could not
# read it » is never « it is fine ».
api() { gh api "repos/$REPO/$1"; }

# requires_owner ENV — the owner is a required reviewer, and may approve their own run.
requires_owner() {
  local env=$1 json rule
  json=$(api "environments/$env") || { bad "cannot read the environment $env"; return 0; }
  rule=$(jq -c '[.protection_rules[]? | select(.type == "required_reviewers")][0] // empty' <<<"$json")
  if [[ -z "$rule" ]]; then
    bad "$env has no required reviewer: anyone who can start the workflow deploys"
    return 0
  fi
  if jq -e --arg u "$OWNER_LOGIN" \
    'any(.reviewers[]?; .type == "User" and .reviewer.login == $u)' <<<"$rule" >/dev/null; then
    ok "$env requires $OWNER_LOGIN's approval"
  else
    bad "$env requires a reviewer, but not $OWNER_LOGIN"
  fi
  if [[ "$(jq -r '.prevent_self_review // false' <<<"$rule")" == "true" ]]; then
    bad "$env has « Prevent self-review » on: the owner could not approve their own deploy"
  else
    ok "$env lets the owner approve their own deploy"
  fi
}

# main_only ENV — deployments from the branch `main` only, by a custom policy.
main_only() {
  local env=$1 json policies
  json=$(api "environments/$env") || { bad "cannot read the environment $env"; return 0; }
  if [[ "$(jq -r '.deployment_branch_policy.custom_branch_policies // false' <<<"$json")" != "true" ]]; then
    bad "$env accepts any branch (Deployment branches: « Selected branches and tags », then add main)"
    return 0
  fi
  policies=$(api "environments/$env/deployment-branch-policies") ||
    { bad "cannot read $env's branch rules"; return 0; }
  if jq -e '[.branch_policies[]? | {name, type: (.type // "branch")}] == [{"name":"main","type":"branch"}]' \
    <<<"$policies" >/dev/null; then
    ok "$env accepts the branch main, and nothing else"
  else
    bad "$env's branch rules are not exactly « main »: $(jq -c '[.branch_policies[]? | {name, type}]' <<<"$policies")"
  fi
}

CF_SECRETS='["CLOUDFLARE_ACCOUNT_ID","CLOUDFLARE_API_TOKEN"]'

echo "==> backend-production"
requires_owner backend-production
main_only backend-production

echo "==> admin-production"
requires_owner admin-production
main_only admin-production
if ! SECRETS=$(api "environments/admin-production/secrets"); then
  bad "cannot read admin-production's secret names"
else
  if jq -e --argjson want "$CF_SECRETS" '[.secrets[].name] as $have | all($want[]; . as $w | $have | index($w))' \
    <<<"$SECRETS" >/dev/null; then
    ok "admin-production holds CLOUDFLARE_API_TOKEN and CLOUDFLARE_ACCOUNT_ID (names only, values never read)"
  else
    bad "admin-production lacks a Cloudflare secret; it holds: $(jq -c '[.secrets[].name]' <<<"$SECRETS")"
  fi
fi

echo "==> backend-staging"
main_only backend-staging

echo "==> the repository"
if ! SECRETS=$(api "actions/secrets"); then
  bad "cannot read the repository's secret names"
else
  LEFT=$(jq -c --argjson cf "$CF_SECRETS" '[.secrets[].name | select(. as $n | $cf | index($n))]' <<<"$SECRETS")
  if [[ "$LEFT" == "[]" ]]; then
    ok "no repository-level Cloudflare secret: an old copy of deploy-admin.yml finds no token"
  else
    bad "repository-level secrets still hold $LEFT: any branch's copy of deploy-admin.yml can read them. Delete them once admin-production holds both"
  fi
fi

if ((FAILED)); then
  echo "==> The fence is NOT in place. Do not create the GitHub App yet (spec §4.4, « The order »)."
  exit 1
fi
echo "==> The fence is in place."
