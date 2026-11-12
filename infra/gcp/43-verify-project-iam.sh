#!/usr/bin/env bash
#
# Has a broad grant come back into project myweli's IAM policy?
#
# Exit 0 = none of the grants below, in a policy that is really this project's.
# Exit 1 = a forbidden grant, listed, or nothing was measured.
#
# ## Why this exists
#
# On 2026-11-11, on the owner's yes, two grants were removed:
# `roles/iam.serviceAccountTokenCreator` on the project from
# `firebase-adminsdk-fbsvc` (the push key's account), and `roles/editor` from the
# default compute account. Neither was in use. **Google's automation added both,
# on 2026-08-05**: Firebase's service agent when the project joined Firebase, and
# `service-agent-manager` when the Compute API was enabled. So a Firebase console
# action or an API enablement can add them back, and nothing else would say so.
# docs/DEPLOYMENT.md § Phase C, « Project IAM »; BACKEND.md §7 T81;
# docs/design/infra-iam-drift-check.md.
#
# ## What fails it
#
#   1. `roles/owner` or `roles/editor` held by anyone but the owner's account.
#   2. `roles/iam.serviceAccountTokenCreator` on the project, whoever holds it.
#      At project level it mints a token for every service account here,
#      `myweli-run` (secrets, database) and `myweli-deployer` (`run.admin`)
#      included.
#   3. `roles/iam.serviceAccountUser` on the project, whoever holds it: `actAs`
#      on every service account, which with any deploy right is the same reach.
#
# A binding with a condition counts. A condition narrows a grant; it does not
# remove it. And a role read from a conditional policy at policy version 1 comes
# back as `roles/editor_withcond_<hash>`, so that suffix is stripped before
# matching. gcloud asks for version 3 today; this does not depend on it.
#
# ## What it cannot see, so nobody reads it as more
#
#   * A grant on ONE resource. Token Creator granted on `myweli-run` itself is
#     in that account's policy (`gcloud iam service-accounts get-iam-policy`),
#     not the project's. That is where DEPLOYMENT.md says to grant it if a
#     feature ever needs it, so it is the expected place, and this is blind to
#     it.
#   * Any role not named above: `roles/resourcemanager.projectIamAdmin`,
#     `roles/iam.securityAdmin`, `roles/run.admin` to a new member. A denylist
#     names what it names.
#   * Inherited grants. `gcloud projects get-ancestors myweli` lists the project
#     alone on 2026-11-11: no organization, no folder, so nothing is inherited.
#     If the project ever joins an organization, the organization's grants are
#     not in this policy.
#
# ## Read-only, and the identity is too
#
# This calls `gcloud projects get-iam-policy` and nothing else in gcloud. The CI
# identity holds `projectIamPolicyReader`, one permission
# (`resourcemanager.projects.getIamPolicy`), from 41-iam-checks-sa.sh, and the
# daily workflow asks Google whether it can change the policy before this runs.
# backend/test/infra/project_iam_test.dart fails if a write verb appears in this
# file, comments included.
#
# ## The rehearsal seam
#
# PROJECT_IAM_POLICY_FILE=<path> reads a saved policy instead of the live one.
# It exists because the red branches cannot be reached against production
# without putting a forbidden grant back. project_iam_test.dart runs every
# branch through it, and fails if a workflow sets it: a rehearsal on the
# schedule is a monitor measuring a file.
set -uo pipefail

PROJECT="${PROJECT:-myweli}"
OWNER="user:sadreddinedaher@gmail.com"

ERR="$(mktemp)"
trap 'rm -f "$ERR"' EXIT

FIXTURE="${PROJECT_IAM_POLICY_FILE:-}"
if [[ -n "$FIXTURE" ]]; then
  echo "!! PROJECT_IAM_POLICY_FILE is set: this is a REHEARSAL, not a measurement."
  echo "!! Reading ${FIXTURE}. No IAM call will be made."
  echo
  if ! POLICY="$(cat -- "$FIXTURE" 2>"$ERR")"; then
    echo "::error::cannot read ${FIXTURE}: $(cat "$ERR")"
    exit 1
  fi
else
  # stderr apart from stdout: a gcloud warning on a successful read would
  # otherwise land inside the JSON.
  if ! POLICY="$(gcloud projects get-iam-policy "$PROJECT" --format=json 2>"$ERR")"; then
    echo "::error::could not read ${PROJECT}'s IAM policy, so nothing was measured:"
    cat "$ERR"
    exit 1
  fi
fi

# ---------------------------------------------------------------------------
# Is this a policy at all, and is it this project's?
# ---------------------------------------------------------------------------
# **The vacuity guard.** Every rule below loops over the bindings it was given.
# An empty object, an error page or another project's policy would loop zero
# times, or over the wrong grants, and pass. So the owner's own `roles/owner`
# must be there: a policy that does not list them is not the one this checks.
if ! jq -e 'type == "object" and (.bindings | type == "array")' \
     >/dev/null <<<"$POLICY"; then
  echo "::error::what came back is not an IAM policy with bindings, so nothing was measured."
  echo "::error::Refusing to report success."
  exit 1
fi

COUNT="$(jq '.bindings | length' <<<"$POLICY")"
if ! jq -e --arg owner "$OWNER" '
       any(.bindings[];
           (.role | sub("_withcond_.*$"; "")) == "roles/owner"
           and any(.members[]?; . == $owner))' >/dev/null <<<"$POLICY"; then
  echo "::error::the policy read has ${COUNT} bindings and none gives ${OWNER} roles/owner."
  echo "::error::It is not ${PROJECT}'s policy as this check knows it. Refusing to report success."
  exit 1
fi
echo "  read ${COUNT} bindings; ${OWNER} holds roles/owner"
echo

# ---------------------------------------------------------------------------
# The grants that must not be there.
# ---------------------------------------------------------------------------
FOUND="$(jq -r --arg owner "$OWNER" '
  .bindings[] as $b
  | ($b.role | sub("_withcond_.*$"; "")) as $role
  | (if $b.condition then
       " (under the condition « \($b.condition.title // $b.condition.expression) »: a condition narrows a grant, it does not remove it)"
     else "" end) as $cond
  | $b.members[]? as $m
  | if ($role == "roles/owner" or $role == "roles/editor") and $m != $owner then
      "\($role) is held by \($m). Only \($owner) may hold it\($cond)."
    elif $role == "roles/iam.serviceAccountTokenCreator" then
      "\($role) is held by \($m) on the PROJECT: it can mint a token for every service account here\($cond)."
    elif $role == "roles/iam.serviceAccountUser" then
      "\($role) is held by \($m) on the PROJECT: it can act as every service account here\($cond)."
    else empty end
' <<<"$POLICY")"
JQ_EXIT=$?
if [[ "$JQ_EXIT" -ne 0 ]]; then
  echo "::error::the rules could not be evaluated (jq exit ${JQ_EXIT}), so nothing was measured."
  exit 1
fi

if [[ -n "$FOUND" ]]; then
  while IFS= read -r line; do
    echo "  ✗ ${line}"
  done <<<"$FOUND"
  echo
  echo "::error::A BROAD GRANT IS IN ${PROJECT}'s IAM POLICY, listed above."
  echo "Google's automation added the two removed on 2026-11-11 (Firebase, and"
  echo "enabling the Compute API), so look first at what changed in the console or"
  echo "which API was enabled. As the owner, who and when:"
  echo "  gcloud logging read 'protoPayload.methodName=\"SetIamPolicy\"' --project=${PROJECT} --freshness=7d"
  # The removal command is deliberately not printed here: this file carries no
  # write verb at all, and project_iam_test.dart holds it to that.
  echo "Removing it is the owner's decision, not a reflex. docs/DEPLOYMENT.md § Phase C,"
  echo "« Project IAM », says what each grant was, what could break without it, and"
  echo "how it was removed the first time."
  exit 1
fi

echo "  ✓ roles/owner and roles/editor: ${OWNER} only"
echo "  ✓ roles/iam.serviceAccountTokenCreator: not on the project"
echo "  ✓ roles/iam.serviceAccountUser: not on the project"
echo
echo "No broad grant in ${PROJECT}'s IAM policy."
