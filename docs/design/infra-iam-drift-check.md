# Project IAM drift check: the broad grants removed on 2026-11-11 cannot come back unnoticed — design spec

| | |
|---|---|
| **Status** | **Built 2026-11-11; merged 2026-11-12** (`26c9d630`, #763). Seen red on saved policies and against real Google. The role was granted on the owner's yes the same evening (§6); **green against the live policy as `myweli-checks`**, run [43101801738](https://github.com/Zaslons/myweli/actions/runs/43101801738), dispatched on the branch |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-11 |
| **PRD ref / phase** | Operations, no product requirement · V1 |
| **Module** | `infra/gcp/43-verify-project-iam.sh`, the `iam` job of `.github/workflows/production-checks.yml`, `infra/gcp/41-iam-checks-sa.sh`, `backend/test/infra/project_iam_test.dart` |
| **Origin** | [DEPLOYMENT.md](../DEPLOYMENT.md) § Phase C, « Project IAM » said « Nothing re-checks this yet ». Threat **T81** in [BACKEND.md](../BACKEND.md) §7 |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-verification-guardrails ✓ · myweli-backend-guardrails ✓ · no app, web, API or contract change |

---

## 1. Goal & scope

**Goal.** If project `myweli`'s IAM policy grants one of the broad roles below again, the daily monitor turns red and the owner is told that day.

**Why.** On 2026-11-11, on the owner's yes, two grants were removed: project-level `roles/iam.serviceAccountTokenCreator` from `firebase-adminsdk-fbsvc` (the push key's account) and `roles/editor` from `731308991240-compute@developer`. Neither was in use. **Google's automation added both** on 2026-08-05: Firebase's service agent when the project joined Firebase, and `service-agent-manager` when the Compute API was enabled. So a Firebase console action or an API enablement can add them back. The only thing between that and a leaked push key minting tokens for `myweli-run` was a read-back command in a document. A sentence in a document is a wish (verification guardrails §9).

**In scope:**
- A verifier script with three rules (§3).
- A third narrow custom role for the checks identity, so it can read the policy (§4).
- A daily job with a negative control that asks, without trying, whether that identity can change the policy (§5).
- A test that reaches every red branch on every PR (§7).

**Out of scope, and why:**
- **A full allowlist of every binding.** It would catch any change, but Google adds a service agent each time an API is enabled (`cloudaicompanion.serviceAgent` is one). Each would turn the monitor red for nothing, and a monitor red for the wrong reason hides the right one (guardrails §16). A denylist of the roles that reach everything is quiet until it matters. The trade is stated in §8.
- **Removing what it finds.** The fix is the owner's decision: a grant may be back for a reason. The script names the binding and points at DEPLOYMENT.md, and holds no write verb at all.
- **Narrowing `roles/firebase.sdkAdminServiceAgent`.** A separate decision, already recorded as not done in T81.

## 2. Where it runs

The `iam` job in `production-checks.yml`, beside `retention` and `secretpins`, which already authenticate by WIF as `myweli-checks@myweli.iam.gserviceaccount.com`. Daily at 06:00 UTC, and on `workflow_dispatch`. A failure reaches the `report` job, which mentions the owner on the tracking issue (production-alarm-close.md). It is a monitor, not a gate: nothing merges through it.

## 3. The rules (`infra/gcp/43-verify-project-iam.sh`)

Red when the policy holds any of these:

| Rule | Why it reaches everything |
|---|---|
| `roles/owner` or `roles/editor` for any member but `user:sadreddinedaher@gmail.com` | Editor holds `iam.serviceAccounts.actAs` and `run.services.update`: enough to redeploy the API as `myweli-run` |
| `roles/iam.serviceAccountTokenCreator` on the project, any member | Mints a token for every service account in the project, `myweli-run` and `myweli-deployer` included |
| `roles/iam.serviceAccountUser` on the project, any member | `actAs` on every service account; with any deploy right it is the same reach |

**Details that each close a way round it:**
- **A conditional binding counts.** A condition narrows a grant; it does not remove it. The message names the condition.
- **`_withcond_` is stripped before matching.** Read at policy version 1, a conditional policy renames `roles/editor` to `roles/editor_withcond_<hash>`. gcloud asks for version 3 today (seen with `--log-http`: `{"options": {"requestedPolicyVersion": 3}}`); the script does not depend on it.
- **A `deleted:` member counts.** Undeleting a service account restores its bindings.
- **The match is exact after the strip**, not a prefix: a different role whose name starts the same is not this check's business.

**The vacuity guard.** Every rule loops over the bindings it was given, so an empty object, an error page or another project's policy would pass. The script refuses unless the input is an object with a `bindings` list **and** the owner holds `roles/owner` in it. A policy without that is not the one this checks.

**Read-only by construction.** One gcloud call, `gcloud projects get-iam-policy myweli --format=json`, with stderr kept apart so a warning cannot land inside the JSON. A failed read prints the error and goes red: « nothing was measured » is never a pass.

**The rehearsal seam.** `PROJECT_IAM_POLICY_FILE=<path>` reads a saved policy instead, and says so in capitals. It exists because the red branches cannot be reached against production without putting a forbidden grant back. No workflow may set it (§7).

## 4. The identity's new role

`myweli-checks` held two custom roles: `logBucketConfigReader` and `secretVersionLister`. **Measured on 2026-11-11 with Policy Analyzer** (`gcloud asset analyze-iam-policy`, « fully explored »): no binding gives it `resourcemanager.projects.getIamPolicy`. The control in the same query, `logging.buckets.get`, resolved to `logBucketConfigReader`, so the query does see its grants.

**A third custom role, `projectIamPolicyReader`, with one permission: `resourcemanager.projects.getIamPolicy`.** gcloud's read makes exactly one call, `POST v1/projects/myweli:getIamPolicy` (seen with `--log-http`), so nothing else is needed.

- **Not `roles/iam.securityReviewer`.** It is predefined, so Google can add to it, and it reads every IAM policy in the project rather than this one.
- **Not a widening of the two existing roles**, for the reason `42-iam-secret-pins-sa.sh` gives: each control names the role it is about.
- **Written into `41-iam-checks-sa.sh`**, which creates the identity, as the commands to run on the owner's yes. Reversible: remove the binding, then delete the role.

## 5. The negative control: asked, not attempted

The sibling jobs prove their boundary by watching a refused **read**. Here the dangerous thing is a **write**, and a refused write is a write on the day the control fails. So the first step of the job calls `testIamPermissions` on the project, which returns the subset of the named permissions the caller holds and changes nothing:

- **`resourcemanager.projects.getIamPolicy` must come back.** That is what makes the rest mean something: an empty answer, from the wrong project or the wrong identity, would otherwise read as « holds nothing dangerous ».
- **`resourcemanager.projects.setIamPolicy` and `iam.roles.update` must not.** Either would let CI change what it checks, or widen its own role.
- A non-200, a non-JSON answer, a missing token or a network failure is red: nothing was measured.

## 6. Rollout

1. Merge nothing yet. The branch carries the script, the job, the test and these docs.
2. ~~**The grant, on the owner's yes at that moment.**~~ **Done 2026-11-11**: `CreateRole` at 21:14:39Z and `SetIamPolicy` at 21:14:42Z, by the owner's account (audit log), with the YAML in `41-iam-checks-sa.sh`. The policy read back before and after: exactly one role–member pair added, `projectIamPolicyReader` → `myweli-checks`, none removed, the other 19 unchanged, no condition anywhere. Policy Analyzer lagged a few minutes, then resolved `getIamPolicy` for the identity.
3. ~~**The live green as `myweli-checks`.**~~ **Done 2026-11-11**, run [43101801738](https://github.com/Zaslons/myweli/actions/runs/43101801738), dispatched on the branch at commit `c9d2d866`. Read in the `iam` job's log, not only its conclusion: the control printed « it reads the policy and cannot change it », and the script read **19 bindings**, the count the owner's read gave after the grant, with no rehearsal banner.
4. Merge. Until then the 06:00 schedule runs `main`'s file, which has no `iam` job; the first scheduled run after the merge is the first daily one.

## 7. Tests (`backend/test/infra/project_iam_test.dart`)

It runs the real script and the job's real control step, the way `production_alarm_test.dart` does:
- **Red on each rule**, on saved policies: the two grants of 2026-11-11 put back; Owner or Editor for another user, a group, a deleted account; Token Creator and Service Account User on the project; Editor under a condition; `_withcond_` names.
- **Green** on the live shape of 2026-11-11, on the owner holding Editor too, and on a role whose name only starts the same.
- **Red, not green, when nothing was read**: `{}`, no bindings, bindings not a list, a list, an HTML page, nothing, no owner, the owner under a look-alike role, a missing file.
- **Live, against a stand-in gcloud**: exactly one call, `projects get-iam-policy myweli --format=json`, on green and on red; a refused read is red; a rehearsal calls nothing.
- **No write verb** in the script, comments included; the role in `41-iam-checks-sa.sh` holds `getIamPolicy` and nothing else.
- **Wired**: the job exists, authenticates as `myweli-checks`, runs the script, is in `report.needs` and `clear.needs`; no workflow sets the rehearsal file.
- **The control, against a stand-in curl**: green on `getIamPolicy` alone; red when `setIamPolicy` or `iam.roles.update` comes back; red on `{}`, a 403, a network failure, no token, non-JSON, a list; and it asks by POST, about `myweli`, with the identity's token, for all three permissions.

`production_alarm_test.dart` and `web/tests/production-alarm-status.test.ts` already hold that `report`, `clear` and the issue's status line hear from every job in the file, so they hold the new one too.

## 8. What it cannot see

Stated so that nobody reads it as more:
- **A grant on one resource.** Token Creator granted on `myweli-run` itself lives in that account's policy, not the project's. DEPLOYMENT.md says to grant it there if a feature ever needs it, so it is the expected place, and this check is blind to it.
- **Any role it does not name**: `roles/resourcemanager.projectIamAdmin`, `roles/iam.securityAdmin`, `roles/run.admin` to a new member. A denylist names what it names (§1 says why it is not an allowlist).
- **Inherited grants.** `gcloud projects get-ancestors myweli` listed the project alone on 2026-11-11: no organization, no folder. If it ever joins one, the organization's grants are not in this policy.
- **Whether the identity can read the live policy**, and what Google answers it. Only the daily run shows that; the test cannot.
