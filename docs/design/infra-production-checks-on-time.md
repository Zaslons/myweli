# The daily production check, on time — design spec

| | |
|---|---|
| **Status** | **Approved by the owner on 2026-11-26** (« Approve as recommended »: the six recommendations of §11, BACKLOG decisions 266–271), then read by two independent reviewers told to refute it (§12). **Step 1 missed** (§13.1): the probe got one run in fifteen hours and none between 06:00 and 07:00 UTC on 2026-11-27, so B19.2 is not built. **Step 2:** B19.3a, the build, on `feat/b19-3a-outside-trigger` (§13.2), on the owner's « Yes, start step 2 ». Next, each on the owner's word: its merge, then B19.3b–e. |
| **Owner** | the project owner: the answers, each step's go; in step 2, the GitHub App, its key and the environment settings |
| **Last updated** | 2026-11-27 |
| **PRD ref / phase** | none: operations. The monitor of everything this repo cannot check at merge time (`.github/workflows/production-checks.yml`) · V1 |
| **ROADMAP entry** | [2026-11-26-production-checks-on-time-spec.md](../roadmap/entries/2026-11-26-production-checks-on-time-spec.md) |
| **Skills checked** | myweli-verification-guardrails (§16, a monitor nobody reads; §9, a deadline in a document; §12, what a list cannot see; §13, the fix is where the next defect lives) · myweli-backend-guardrails (read only: nothing in `backend/` changes) |
| **Related** | `infra/ci/99-verify-monitor-alive.mjs` (the dead-man check) · [infra-cloudflare-front-door.md](infra-cloudflare-front-door.md) (the Worker posture step 2 copies) · `infra/gcp/40-iam-wif.sh` (the deploy identity, bound by environment) · `.github/workflows/deploy-backend.yml:128-133` (required reviewers, already named there as the owner's) |

---

## 1. Goal & scope

**Goal.** `production-checks.yml` starts close to 06:00 UTC every day, as its own comment promises (« before the Abidjan working day »), and a day it does not is visible.

**Two steps, the second only if the first is not enough:**
1. **Step 1, no new credential:**
   - first a three-day probe: an empty workflow that ticks every hour;
   - then, if those ticks arrive on time, `production-checks.yml` ticks every hour and only the first tick after 06:00 UTC runs the checks (§3), measured for seven mornings.
2. **Step 2, an outside trigger:** a Cloudflare Worker starts the workflow at 06:00 UTC as a GitHub App (§4). It is only safe once GitHub itself, not a line in a workflow file, keeps that App away from the deploys (§4.4), which puts an approval on every deploy.

**Out of scope:** what the twelve checks check; moving the checks off GitHub Actions; anything in `backend/`.

---

## 2. What exists today (OBSERVED unless marked)

### 2.1 GitHub starts the 06:00 run hours late

`production-checks.yml` has one schedule, `cron: '0 6 * * *'`, unchanged since `1e8dfb07` (2026-08-21). It is the repository's only scheduled workflow. The repository is public.

Every scheduled run since the schedule began, read from the API on 2026-11-26 (`gh run list --workflow=production-checks.yml --event schedule`), hours after 06:00 UTC that GitHub created it. The reviewer recomputed the table and it matches:

| month | runs | earliest | median | latest |
|---|---|---|---|---|
| 2026-08 (from the 22nd) | 10 | 0.4 h | 2.8 h | 11.9 h |
| 2026-09 | 30 | 3.7 h | 4.5 h | 6.4 h |
| 2026-10 | 31 | 3.9 h | 5.6 h | 7.9 h |
| 2026-11 (to the 25th) | 25 | 6.1 h | 7.9 h | 10.9 h |

- 2026-08-22 to 08-26: created between 06:22 and 06:37.
- **From 2026-08-27, every run 3.7 to 11.9 hours late**, and later each month.
- 96 days, 96 runs: **none dropped**.
- On 2026-11-26 at 13:24 UTC that day's run had not been created yet.

Nothing in this repository changed on 2026-08-27. The workflow is `active`.

### 2.2 What others report (secondary sources, read 2026-11-26)

- **Daily schedules hours late in 2026:** [discussion #201738](https://github.com/orgs/community/discussions/201738) reports 8–14 h in July. A blog post dates the problem « since approximately August 26, 2026 » ([devactivity](https://devactivity.com/posts/apps-tools/github-actions-cron-chaos-a-critical-threat-to-software-project-development)).
- **No acknowledgement from GitHub** on any of them; githubstatus showed Actions operational.
- **Moving the minute:** #201738's author moved `:00` to `:07` and saw « no measurable difference ». No page measured an improvement.
- **The advice everywhere:** start the workflow from outside through the `workflow_dispatch` API, keeping `schedule` as a backup. How reliable that is gets asserted on every page and measured on none.
- **A frequent schedule:** one public repository's 10-minute schedule arrived on time over the same days (§3.1). Step 1a measures it here.

### 2.3 What watches the monitor

- `infra/ci/99-verify-monitor-alive.mjs`, run by `ci.yml`'s job « The production monitor is still firing », fails every PR when there has been no **scheduled** run in 3 days. It filters on `event=schedule` on purpose: a manual click must not pass for a live schedule.
- **It counts runs created, not runs whose checks ran.**
- **Nothing watches lateness:** a run 11 hours late passes it.

### 2.4 How the alarm opens and closes

- **`report`** (« Say so, if any check failed »): `if: failure()`, on any event. It opens or updates the issue « Production checks are failing ».
- **`clear`** (« Close the alarm, if every check passed »): `if: github.event_name == 'schedule' && success()` (line 695). **A dispatched run never closes the alarm.**
- **The `needs` rule:** a job whose `needs` include a skipped job is skipped too, unless its condition uses `always()` ([workflow syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax)). `success()` alone does not avoid that.

### 2.5 Who can start a deploy

Four workflows accept `workflow_dispatch`: `deploy-backend.yml`, `deploy-admin.yml`, `goldens.yml` and `production-checks.yml`.

**A dispatch can name any branch or tag, and it runs that ref's copy of the file.** A re-run uses the original run's commit for up to 30 days ([re-running workflows](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs)). So a check written into a workflow file today does not reach:
- the 9 other branches on `origin` (6 Dependabot; plus `docs/b16-3-email-taken`, `docs/records-867-878`, and `feat/web-salon-page-live-fallback`, merged on 2026-11-25 and never deleted);
- the 15 dispatches of `deploy-backend.yml` in the last 30 days (the list does not show which environment each targeted), which can be re-run.

**What fences each deploy today:**

| deploy | what holds the power | fenced by |
|---|---|---|
| backend, production and staging | `myweli-deployer@` (project-wide `roles/run.admin`) | **its Workload Identity bindings name only `attribute.environment/backend-production` and `…/backend-staging`** (read with `gcloud … get-iam-policy`, 2026-11-26). Only a job that declares one of those environments gets a deploy token. Both environments have **no protection rule and no branch policy** (`gh api …/environments`, 2026-11-26). Every copy since `db7a273a` (2026-08-13) declares one. |
| admin console | the **repository-level** secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` (`deploy-admin.yml:92-100`) | nothing. Any copy of `deploy-admin.yml`, on any ref, can read them. |

The typed `confirm: deploy` is no guard against a credential that can dispatch: anyone with one can type it.

### 2.6 What the checks' own jobs can do

- **`privacy` (lines 64–86) and `legal` (88–113) set no job-level permissions,** so they inherit the workflow's `issues: write` and `id-token: write` (lines 32–37). Both read `target`.
- **`salonpages`, `access`, `appchain`:** their comments say they hold no such right.
- **The checks' Workload Identity** (`myweli-checks@`) is bound by repository only.
- **Nothing in the workflow pins actor, event or ref, except `clear`.**

### 2.7 The infrastructure step 2 can copy

- **The front door Worker, `myweli-api-front-door`:** plain JavaScript, `workers_dev = false`.
  - It is deployed from the owner's machine by `infra/cloudflare/96-api-front-door.sh`, with a scoped token kept in Secret Manager. That token includes « Workers Scripts: Edit ».
  - Its one secret is piped into `wrangler secret put` over stdin (`96-api-front-door.sh:214-215`).
  - It is pinned by `backend/test/infra/front_door_wiring_test.dart`.
  - Its `wrangler.toml` says « CI has no Cloudflare identity ». **That is no longer true:** `CLOUDFLARE_API_TOKEN` has been a repository secret since 2026-06-29, used by `deploy-admin.yml`.
- **Cloud Scheduler** runs the backend's crons, each a Google-signed OIDC call. It cannot sign a GitHub credential.

---

## 3. Step 1 — an hourly tick, then the morning gate (no new credential)

### 3.1 The idea, and why it is likely to work

- **The hypothesis:** if GitHub's delay falls on infrequent schedules, ticks every hour arrive about on time.
- **What that would give:** the first tick after 06:00 UTC is never far from 06:00, and step 1 only has to let that one run the checks.

**One public data point, read 2026-11-26:** [`simonw/pge-outages`](https://github.com/simonw/pge-outages) has a schedule every 10 minutes. From 2026-11-23 to 11-26:
- **466 scheduled runs,** the longest gap 29 minutes;
- **its first run after 06:00 UTC** was created at 06:19, 06:13, 06:13 and 06:13;
- **on the same days, this repository's daily run** was created between 13:47 and 16:52.

That is one other repository, not this one, so step 1 starts with a probe.

### 3.2 Step 1a — the probe (three days, nothing else touched)

A separate workflow, `.github/workflows/schedule-probe.yml`:
- `on: schedule: - cron: '17 * * * *'` (every hour at :17);
- `permissions: {}`;
- `concurrency: { group: schedule-probe, cancel-in-progress: false }`, so a burst also produces a real « cancelled while pending » run for step 1b's fixtures;
- one job, one step, `run: true`.

It touches no alarm, no check, no test and no secret. No test reads every workflow in a way it would trip: the three that list `.github/workflows` look for specific variable names.

**After three days, read for each day:**
- when the first tick after 06:00 UTC was created;
- the largest gap between ticks;
- how many runs were cancelled while pending.

Then remove the probe: in step 1b's PR if it goes ahead, alone otherwise.

**Step 1b goes ahead when,** on each of the three days, the first tick after 06:00 was created by 07:00 UTC.

### 3.3 Step 1b — the morning gate

**The schedule:** `production-checks.yml`'s cron becomes `'17 * * * *'`.

**A new first job, `morning` (« Is this the morning run? »):**
- `permissions: { contents: read, actions: read }`;
- its logic in `infra/ci/production-checks-morning.mjs`, with fixture inputs built from real run and job shapes;
- **output `go`:**
  - `workflow_dispatch`: always `go`, so a manual run checks now, as today;
  - `schedule`: `go` only when this run's **own `created_at`** (read with `GET /actions/runs/{id}`, never the clock) is on or after 06:00 UTC, and no earlier **scheduled** run created since 06:00 that day **checked**.
- **A run « checked »** when its job named « Real domain — Core Web Vitals (mobile) » has the conclusion `success` or `failure`.
  - Not counted: a run cancelled before it started (it has 0 jobs), a run cancelled mid-flight (`cancelled`), a run whose checks were skipped. The next tick goes.
  - A manual run never counts, so a click at 06:10 does not take the morning run's place.
  - If that job name is not found on a run that has jobs, the gate fails rather than guess.
- **Also output:** this run's `created_at`, which no `github` field holds, for `ontime`.
- **API errors:** retried inside the script. If the gate still fails, `report` names it as « no check ran » rather than as a production failure (§3.4).

**Every check job:** gains `needs: morning` and `if: needs.morning.outputs.go == 'true'`.

**A stop run:** every check is skipped, so `report` (`failure()`) and `clear` (`success()`) are skipped, and the alarm is untouched. The reviewer read both from GitHub's rules. The first real run reads them again.

### 3.4 Lateness and missed days get their own issue

**A new job, `ontime` (« Did the morning run start on time? »),** runs in every `go` run (on a dispatch it passes with a line saying so). It does not fail the run: a late start is not production being wrong. It keeps its own issue, « The morning check starts late », and opens or closes it.
- **It opens that issue when:**
  - this scheduled run was created after **07:00 UTC**;
  - or the previous scheduled run that checked was created before yesterday 06:00, meaning a whole day had no morning run.
- **It closes that issue** on the next on-time morning.

The production alarm keeps meaning « production is already wrong ».

**`report`:**
- its message distinguishes « the gate failed, no check ran » from a failing check;
- `morning` joins both `needs` lists, as the alarm test requires every non-alarm job to (`production_alarm_test.dart:43-53`), with a `MORNING` entry in the status line.

**`clear`:** gains `github.ref == 'refs/heads/main' && github.run_attempt == 1`. Re-running `clear` alone on an old green run must not close a live alarm (§4.5). A re-run of a whole failed run no longer closes it either: the next morning does.

### 3.5 The dead-man check counts runs that checked

`99-verify-monitor-alive.mjs` keeps `event=schedule` and its 3 days. It now asks whether a **run that checked** (§3.3's rule) exists in that window. An hourly gate would otherwise keep it green while every run stopped.

Its messages change too: « Enable workflow » is the wrong fix when runs exist and none checked.

### 3.6 The read-back rule changes with it

`gh run list --workflow=production-checks.yml --limit 3` is the read-back the repository asks for. From 07:17 its three newest runs would be green stop runs, whatever the morning did.

It appears in four places:
- `.claude/skills/myweli-verification-guardrails/SKILL.md:421`;
- `docs/LAUNCH.md:1724`;
- `docs/design/appointment-currency-stamp.md:701`;
- `docs/design/web-swiss-cards.md:1221`.

The same PR adds `node infra/ci/production-checks-morning.mjs --today`, which prints the day's `go` run (its time, conclusion and link), and replaces the rule in all four places.

### 3.7 The comment

`production-checks.yml`'s « 06:00 UTC daily — before the Abidjan working day » is rewritten to say:
- what the gate does;
- that GitHub created daily runs 4 to 12 hours late from 2026-08-27 (§2.1).

### 3.8 Done, or step 2

- **Read seven mornings:** for each, the `go` run's creation time.
- **Step 1 is enough when** all seven were created by 07:00 UTC, the same line `ontime` uses.
- **Otherwise,** step 2, on the owner's word.

### 3.9 Cost

- **Runs:** about 24 a day, 23 of them a gate of a few seconds. The repository is public, where standard runners cost nothing (INFERRED from GitHub's billing pages, not re-read).
- **The Actions list** gets busier: each stop run shows its checks as skipped.
- **`concurrency: production-checks`** stays. A burst leaves one run waiting, and the older pending ones are cancelled. §3.3's rule does not count a cancelled run.

### 3.10 Tests (each watched red, listed in the commit)

**`morning`, with fixtures from real shapes:**
- before 06:00 → stop;
- the first tick after 06:00 → `go`;
- a later tick after one that checked → stop;
- after one whose gate failed → `go`;
- after one cancelled before starting (0 jobs) → `go`;
- after one cancelled mid-flight → `go`;
- after a manual run → `go`;
- a run created 05:59 that starts at 06:01 → stop, and the 06:17 tick → `go`: one `go` only;
- the Core Web Vitals job not found → the gate fails;
- dispatch → `go`.

**`ontime`:**
- created 06:40 → issue closed;
- 07:01 → opened;
- no morning yesterday → opened;
- dispatch → passes with its line.

**`clear`:** a re-run (`run_attempt` 2) and another branch → skipped.

**The dead-man check:** stop runs only for 3 days → fails, with the new message.

**Existing tests updated:**
- `production_alarm_test.dart:77-91` (no `if` on a check job) becomes « exactly the gate expression, still no `continue-on-error` »;
- `production-alarm-status.test.ts` gains `MORNING`;
- `registration-claim.test.ts:904-1018` gains a jobs fixture, and its variable joins the ban list at `:1005`.

**Mutations to watch red:**
- the gate going on every tick;
- the gate reading the clock instead of `created_at`;
- the gate counting a cancelled or a manual run;
- `ontime` failing the run instead of its own issue;
- `clear` without `run_attempt`;
- the dead-man check counting stop runs;
- the read-back script printing the newest run instead of the day's `go`.

**After the merge:** a real stop run, and a real `go` run, read from GitHub: the `needs` rules are the kind a text check passes blind.

---

## 4. Step 2 — the outside trigger (only if step 1 misses)

### 4.1 The shape

- **06:00 UTC:** a Cloudflare cron starts the Worker « myweli-production-checks-trigger ».
- **The Worker:**
  1. signs a JWT with the GitHub App's key;
  2. exchanges it for a 1-hour token, limited to `myweli` and to Actions write;
  3. sends `POST …/actions/workflows/production-checks.yml/dispatches {"ref":"main"}`.
- **The result:** `production-checks.yml` runs as a `workflow_dispatch`, started by « <app>[bot] », with the default `target`.
- **GitHub's own schedule stays as the backup,** with step 1's gate.
- **The backup's `ontime` changes question:** not how late it is itself, but whether the App's run was created by 06:30 UTC that day. If not, it opens its own issue (§3.4) with « the 06:00 trigger did not fire ».

### 4.2 The GitHub App

- **Who creates it:** the owner, in GitHub's settings. Nothing in this repository can create one.
- **Name:** suggested « MyWeli production checks ». Its bot login is read from the first run, then pinned with the IDs (§4.6).
- **Permissions:** Repository → **Actions: Read and write**, nothing else. Metadata: read is automatic.
- **Settings:** no webhook (« Active » unticked), « Only on this account ».
- **Installed on `Zaslons/myweli` only.**
- **Why an App and not a personal token:** a personal token acts as the owner. A run it starts shows `Zaslons`, and nothing could tell it from a real click.

### 4.3 The Worker

`infra/cloudflare/worker/production-checks-trigger/`, plain JavaScript, no dependency.

**`wrangler.toml`:**
- `crons = ["0 6 * * *"]`;
- `workers_dev = false` and no route, so nothing on the internet can call it;
- `[vars]` holding the App's client ID, the installation ID, the repository, the workflow file and `main`;
- no secret in the file.

**Each tick:**
1. **The JWT:** RS256, `iss` = the client ID, `iat` = now − 60 s, `exp` = now + 9 min (GitHub allows 10). Signed with WebCrypto from a PKCS#8 key.
2. **The token:** `POST /app/installations/{id}/access_tokens` with `{"repositories":["myweli"],"permissions":{"actions":"write"}}`. Success is **201**.
3. **The dispatch:** `{"ref":"main"}`, no `inputs`. GitHub's docs, read 2026-11-26, answer 200 with `workflow_run_id`. The Worker accepts 200 or 204.
4. **Retries:** a network error or a 5xx is retried twice, 60 s apart; a 4xx is not. After that the handler throws, so Cloudflare records the event as failed.
5. **Logging:** one line per step. **Never the JWT, the token or the key.**

**Limits on the Free plan** (read 2026-11-26): 5 cron triggers per account, 10 ms CPU per cron invocation (time spent waiting on `fetch` does not count), 50 subrequests, 15 min. One RSA signature is INFERRED to fit. Read the first invocation's CPU time; Workers Paid is $5/month.

### 4.4 The fence: GitHub keeps the App away from the deploys (decision 268)

A line in a workflow file cannot do it (§2.5). These four can, because GitHub enforces them whatever copy of the file runs:

1. **`backend-production`:**
   - required reviewers: the owner;
   - deployment branches: `main` only.

   The App has no Deployments permission and is not a person, so it can never approve. A copy of `deploy-backend.yml` older than 2026-08-13 declares no environment, so the deploy identity, which answers only to the two environments (§2.5), refuses it a token. A run past 30 days cannot be re-run.

   **`backend-staging`:** `main` only. Staging is `absent` today (`infra/gcp/staging.state`). A reviewer rule there would leave every backend merge's run waiting for an approval, for a deploy that does nothing. From `main`, the App could at most redeploy `main` to staging, which every merge already does. When staging comes back, the reviewer rule is added there too.
2. **A new environment, `admin-production`,** with the same two rules. It holds the Cloudflare secrets. `deploy-admin.yml` declares it, and **the repository-level `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` are deleted**, so every older copy of the file fails.
3. **In each deploy job, a first step that refuses a run not started by `Zaslons`** (`github.triggering_actor`, which follows re-runs). It is defence in depth on `main`, not the fence.
4. **Stale branches deleted.**

**What it costs:**
- **Every production deploy, of the backend and of the admin console, waits for an approval.** The owner gives it in GitHub, or says yes in chat and it is given through their GitHub login, as dispatches are today.
- **« Prevent self-review » stays off,** or the person who dispatched could not approve.

**The order:**
1. Build and merge 1–4.
2. The owner sets the environment rules.
3. Read them back with `gh api …/environments`.
4. Only then does the App get created.

### 4.5 The alarm in step 2 (decision 269)

`clear` closes the alarm on the App's run too, but only when all of these hold:
- the run is on `main`, with the default target;
- it is the run's first attempt. Even the owner's re-run of `clear` alone could otherwise close a live alarm; the next morning closes it.

```yaml
if: >-
  success() && github.ref == 'refs/heads/main' &&
  (github.event_name == 'schedule' ||
   (github.triggering_actor == '<app>[bot]' && inputs.target == 'https://myweli.com')) &&
  github.run_attempt == 1
```

- **`success()`, deliberately:** it is false when any need was skipped. A stop run (§3.3) skips every check, so it must never reach `clear`. `!cancelled() && !contains(needs.*.result, 'failure')` would let it through and close the alarm with no check run. That is why `ontime` runs on every `go` run and does not fail it (§3.4).

- **`run_attempt`:** re-running only `clear` on an old green run would otherwise close a live alarm without a single check.
- **Same rule for scheduled runs:** `main` only, first attempt only, added in step 1b already (§3.4).

### 4.6 The key (decision 270)

1. **GitHub's format:** the key arrives as PKCS#1, `BEGIN RSA PRIVATE KEY` (INFERRED; read when generated). WebCrypto imports PKCS#8.
2. **The conversion:** the owner runs `openssl pkcs8 -topk8 -nocrypt` once, on their machine.
3. **Its home:** Secret Manager, `GITHUB_APP_PRODUCTION_CHECKS_KEY`, created by the owner. The deploy script pipes it into `wrangler secret put` over stdin, the front door's gesture. Both `.pem` files are then deleted.
4. **Never** in chat, in the repository, or attached.
5. **The IDs:** the client ID, installation ID and bot login go in one small PR, pinned together by the wiring test.
6. **Rotation:** a new key in the App's settings, a new Secret Manager version, a redeploy, then the old key deleted.

### 4.7 What the key could still do, with the fence in place

Its token has Actions write on `myweli` only. That covers « workflows, workflow runs, and artifacts » (GitHub's docs). The list below is INFERRED: the docs name no endpoints.

**What a leaked key could do:**
- **Start any workflow.**
  - The deploys wait for an approval it cannot give.
  - `goldens.yml` cannot write.
  - `production-checks.yml` can run against any `target`, which can open the alarm but not close it (§4.5).
  - **`privacy` and `legal` run with `issues: write` and `id-token: write` (§2.6). The step 2 build gives both job-level permissions first.**
- **Re-run, cancel or delete runs, logs, artifacts and caches.** Cancelling the backup run every day would hide it from a dead-man check that counts created runs. That is why §3.5 counts runs that checked.
- **Disable a workflow.**
  - `production-checks.yml`: the dead-man check fails every PR within 3 days.
  - `ci.yml`: required checks never report, so nothing merges.

**What it cannot do:** push code, read secrets, change settings, approve a deployment, or touch another repository.

**Detection (best effort, not a control):** the backup run lists every run updated since the previous backup run. It fails when the App started any workflow other than `production-checks.yml`, matched on `triggering_actor`, or when any workflow is not `active`.

### 4.8 Why a Worker (decision 267)

| | Cloudflare Worker (recommended) | Cloud Scheduler | a backend cron route |
|---|---|---|---|
| where the GitHub key lives | a Worker secret, not readable back | in the job's HTTP headers: Scheduler signs only Google tokens | in the production API |
| reachable from the internet | no route | no | yes, behind the cron OIDC check |
| what is new | one Worker, one cron | one job | a route, a GitHub client, the key in production |

### 4.9 Tests (each watched red)

**The Worker** (`node --test`, run in CI):
- the JWT's header and claims; its signature verified with a key pair the test generates;
- a PKCS#1 key refused, with the conversion command in the message;
- the narrowed token body; the token answer is 201;
- the dispatch body is exactly `{"ref":"main"}`;
- retries happen on 5xx and not on 4xx;
- **no log line holds the JWT, the token or the key.**

**Wiring:**
- the cron, `workers_dev = false`, no route, no secret in `[vars]`;
- `deploy-admin.yml` declares `admin-production` and names no repository-level secret;
- every deploy job opens with the owner check (read after stripping comments and `echo` lines);
- every workflow with `workflow_dispatch` is either in a known list or declares a protected environment;
- `clear`'s condition, exactly.

**Read after:**
- the environments' rules, read through the API;
- a dispatch of `deploy-admin.yml` from an old branch fails before it can deploy;
- the first 06:00 run is created by the bot at about 06:00;
- Cloudflare's « Trigger Events » shows the event and its CPU time.

---

## 5. API & contract

- **`docs/api/openapi.yaml`:** no change.
- **GitHub REST, step 1:** runs and jobs.
- **GitHub REST, step 2:** also the installation-token endpoint and dispatch.

---

## 6. Security

- **Step 1:** no new credential.
  - The probe has `permissions: {}`.
  - `morning` and `ontime` read through the run's own `GITHUB_TOKEN`, with job-level `contents: read` and `actions: read`. `ontime` also gets `issues: write` for its own issue.
- **Step 2:** §4.4 and §4.7. It adds one row to `docs/BACKEND.md` §7, the next T number.
- **`privacy` and `legal`:** they get job-level permissions in step 1b's PR (§2.6). That is worth doing even without step 2.

---

## 7. Performance & cost

- **Step 1:** §3.9; the probe is one empty job an hour for three days.
- **Step 2:** one Cloudflare invocation a day, and one more full run a day on GitHub (the backup).

---

## 8. Testing plan

- **Step 1:** the probe needs no test; it is read (§3.2). The gate: §3.10.
- **Step 2:** §4.9.
- **Each guard is watched red,** and the list goes in the commit message.

---

## 9. Rollout

Each step on the owner's word.
1. **This spec:** the answers, then its merge.
2. **Step 1a:** the probe's PR, then three days read (§3.2).
3. **Step 1b, if the probe's ticks arrive by 07:00:**
   1. one PR: the gate, `ontime` and its issue, `clear`, the dead-man check, the read-back script and its four citations, and the probe removed;
   2. seven mornings read (§3.8).
4. **Step 2, only if step 1 misses:**
   1. the build PR (§4.4's fence first, then the Worker, then `clear`);
   2. the owner's environment settings, read back;
   3. the App and its key;
   4. the IDs PR;
   5. the Worker deploy;
   6. the read after (§4.9).

---

## 10. Definition of done

- [ ] The probe read for three days, and removed.
- [ ] Every test of the step built, watched red, listed in the commit.
- [ ] A real stop run and a real `go` run read from GitHub after the merge.
- [ ] Seven mornings read: each `go` run created by 07:00 UTC (step 1), or within 15 minutes of 06:00 (step 2).
- [ ] The workflow comment, the read-back rule in its four places, this spec's status and the BACKLOG updated.
- [ ] Step 2 only: the environment rules read back before the App exists; the key only in Secret Manager and the Worker.

---

## 11. Open questions (decisions 266–271, all answered 2026-11-26: « Approve as recommended »)

1. **Which first?** (decision 266)
   - *Recommended:* step 1: the three-day hourly probe, then the morning gate if its ticks arrive by 07:00. No new credential.
   - Step 2 only if step 1 misses.
   - Alternatives: go straight to step 2 with its fence; or only make the lateness visible (`ontime` and its issue, no hourly tick).
2. **Step 2's trigger, if it comes** (decision 267).
   - *Recommended:* a Cloudflare Worker (§4.8).
   - Alternatives: Cloud Scheduler, or the backend.
3. **Step 2's fence** (decision 268).
   - *Recommended:* required reviewers and `main` only on `backend-production` and a new `admin-production`, with the repository-level Cloudflare secrets moved into the latter; `main` only on `backend-staging`; the owner check in each deploy job; the stale branches deleted (§4.4).
   - **Its cost:** every production deploy waits for an approval.
   - Without the fence the App's key could deploy, so there is no safe alternative short of not building step 2.
4. **Lateness** (decision 269).
   - *Recommended:* a morning run created after 07:00 UTC, or a day with none, opens its own issue, « The morning check starts late », not the production alarm (§3.4). `clear` then closes the alarm only on `main` and on a first attempt (§3.4, §4.5).
   - Alternative: print the delay without any issue.
5. **Step 2's key** (decision 270).
   - *Recommended:* Secret Manager, piped into the Worker by the deploy script (§4.6).
   - Alternative: only the Worker's secret.
6. **When?** (decision 271)
   - *Recommended:* the probe now, as one small PR, on your word; three days read; then step 1b's PR, on your word.
   - Step 2 waits for step 1's seven mornings and your word.

---

## 13. Build record

### 13.1 B19.1, the probe (2026-11-26, `feat/b19-1-schedule-probe`)

**What it is:** `.github/workflows/schedule-probe.yml`, as §3.2 says:
- `cron: '17 * * * *'`;
- `permissions: {}`;
- `concurrency: schedule-probe` (no cancel);
- one job, one step, `run: 'true'`;
- no `workflow_dispatch`, so a manual run cannot pass for a tick.

**Checked before the merge:**
- the file parses, read back as YAML: the schedule, `{}`, the group and the one step;
- the tests that read every workflow file still pass:
  - `project_iam_test`, `console_access_check_test`, `production_alarm_test`, `merge_queue_test`: 112;
  - `app_trust_chain_check_test`: 14.

**Not checkable before the merge:** GitHub runs a schedule only from the default branch. So the first evidence is the first tick after the merge, which should appear within about an hour.

**The read, after three days, read-only:** `gh run list --workflow=schedule-probe.yml --event schedule`, per day:
- the first tick after 06:00 UTC;
- the largest gap;
- the runs cancelled while pending.

**Then removed:** in B19.2's PR, or alone if the ticks are late.

**What it measured (merged 2026-11-26 at 15:43 UTC as `8ac2c73a`, read from the API):**
- the workflow was `active` from 15:43:45 UTC;
- by 2026-11-27 07:07 UTC GitHub had created **one** run, at 00:37:21 UTC (the 00:17 tick, 20 minutes late), `success`, `total_count` 1. The other fourteen hourly ticks never came;
- **no run between 06:00 and 07:00 UTC on 2026-11-27**, and `production-checks.yml`'s 06:00 run had not been created by 07:07 either.

**Read after one morning, not three:** the owner's answer on 2026-11-26, « Yes, decide tomorrow ». §3.2's rule needs every day's first tick by 07:00, so one missed morning settles it. It amends decision 271's three days.

**The verdict:** step 1 misses, and an hourly schedule is no better here than a daily one. B19.2 is not built. Step 2, on the owner's « Yes, start step 2 » (2026-11-27).

### 13.2 B19.3a, step 2's build PR: the plan (2026-11-27, `feat/b19-3a-outside-trigger`)

**What step 2 inherits from step 1, now that there is no gate.**
- **The backup is today's daily schedule,** `cron: '0 6 * * *'`, unchanged. No hourly tick means no stop runs, so §3.3's gate, §3.6's read-back script and the `needs: morning` lines are not built. `gh run list --workflow=production-checks.yml --limit 3` stays a true read-back: each of its runs ran its checks.
- **§3.4's `ontime` and its issue are built here,** in their step 2 form (§4.1). It runs in every run and never fails it. Its question depends on whether the trigger exists yet:
  - **no App yet:** a scheduled run created after 07:00 UTC opens « The morning check starts late » (§3.4). Every scheduled run since 2026-08-27 would. So the issue opens on the first scheduled run after the merge and stays open until the trigger works. That is true, and today nothing says it;
  - **with the App:**
    - the App's own run created by 06:30 UTC closes the issue; created later, it opens it;
    - the backup opens it when its UTC day has no App run on `main` created between 06:00 and 06:30;
  - **a manual run, or one not on `main`:** it passes with a line, and touches nothing.
- **§3.5 is built here:** the dead-man check counts scheduled runs that **checked**. §4.7 relies on it: a leaked key could cancel the backup every day.
- **`clear`:** `success() && github.ref == 'refs/heads/main' && github.event_name == 'schedule' && github.run_attempt == 1`. The App's clause (§4.5) joins it in the IDs PR, once the bot login is known.
- **`privacy` and `legal`:** job-level `permissions: contents: read` (§2.6, §4.7).

**Where the App's bot login lives until the IDs PR:** one exported constant, `TRIGGER_BOT = ''` in `infra/ci/production-checks-ontime.mjs`. The IDs PR sets it together with the client ID and the installation ID in the Worker's `wrangler.toml` and `clear`'s literal, and one wiring test holds all three equal.

**What waits for the IDs PR, because it needs the bot login or the App:**
- `clear`'s App clause;
- §4.7's detection (the App started another workflow; a workflow not `active`);
- a daily read of the environment rules (B19.3b's read-back, repeated). A rule unticked later would otherwise reopen the hole silently (verification guardrails §9).

**This PR, in the order of §9 step 4.1:**
1. **The fence, the part a file can hold (§4.4):**
   - `deploy-admin.yml` declares `environment: admin-production`. Until the owner creates it, GitHub creates it on first use with no rule, and the repository-level secrets still answer, so nothing breaks before B19.3b;
   - each deploy job's first step refuses a run whose `github.triggering_actor` is not `Zaslons`. All 60 recent `deploy-backend.yml` runs and all 91 `deploy-admin.yml` runs, push and dispatch, were started by `Zaslons` (read 2026-11-27);
   - `infra/ci/98-verify-deploy-fence.sh`, read-only, run by the owner's `gh` after B19.3b: both production environments require `Zaslons` and allow `main` only, staging allows `main` only, `admin-production` holds the two Cloudflare secrets, and the repository holds neither.
2. **The Worker** `infra/cloudflare/worker/production-checks-trigger/`: §4.3 exactly. The IDs are empty and the Worker refuses to start without them. Its deploy script is `infra/cloudflare/97-production-checks-trigger.sh`, the front door's gesture: the scoped token from Secret Manager, the key over stdin, a refusal on empty IDs or a PKCS#1 key, and the cron and the absent `workers.dev` address read back. It is not run until B19.3e.
3. **`production-checks.yml`:** the comment (§3.7), `privacy` and `legal`, `ontime`, `report` (its status line and a paragraph on `ontime`), `clear`.
4. **The dead-man check** (§3.5).
5. **`schedule-probe.yml` removed.**
6. **Stale comments:** « CI has no Cloudflare identity » in the front door's `wrangler.toml`, `96-api-front-door.sh` and `infra/cloudflare/README.md` (§2.7).

**Tests:** §4.9 and §3.10's `ontime` and dead-man cases, in `web/tests/` (vitest, the `web` CI job), because a file under `backend/` starts `deploy-backend.yml` on merge. The one exception is `production_alarm_test.dart`, which holds `clear`'s condition as exact text.

**After this PR, each on the owner's word:** B19.3b, the environment rules and secrets, then read back; B19.3c, the App and its key; B19.3d, the IDs PR; B19.3e, the Worker deploy and the read after (§4.9).

**Built (2026-11-27), as planned above.** What was checked before the PR:
- **New tests,** `web/tests/production-checks-trigger.test.ts`, 63:
  - the Worker against a stand-in GitHub: the JWT's header and claims, its signature verified with a key pair the test generates, PKCS#1 refused with the conversion command, the narrowed token body, 201 only, the dispatch body exactly `{"ref":"main"}`, 200 or 204, retries on a 5xx and a network error and none on a 4xx, an empty ID refused before anything is sent, and no log line or error holding the key, the JWT or the token, on four paths;
  - `ontime`'s rules on both sides of each line, and its issue handling against a stand-in GitHub;
  - the fence read-back against a stand-in `gh`: green when every rule holds, red and named for each of eleven missing or unreadable rules;
  - the wiring: every dispatchable workflow deploys nothing or declares a fenced environment in every job; each deploy job opens with the owner check; the Worker's toml; the bot login, the IDs and `clear`'s App clause all set or all empty; the deploy script reads the fence before it deploys and never echoes a credential; one scheduled workflow left.
- **The dead-man check:** six new cases in `registration-claim.test.ts`, and `MONITOR_JOBS_JSON` joins the banned knobs. Run read-only against the real repository: green, on the 2026-11-26 scheduled run whose Core Web Vitals job succeeded.
- **The fence read-back, against today's real settings:** red, and it names every rule that is missing: no reviewer and any branch on `backend-production`, `admin-production` absent, any branch on `backend-staging`, both Cloudflare secrets still repository-level.
- **Existing tests:** `production_alarm_test.dart` holds `clear`'s new condition; with it, the nine backend infra tests that read the workflows pass (164). `production-alarm-status`, `basemap` and `registration-claim` pass (89). Web typecheck and lint clean.
- **Mutations, each watched red, then restored:** 57, each applied to the committed tree, run against its test, then restored; a pass that did not change the file would have counted as no result:
  - **the Worker (11):** inputs in the dispatch; a token not narrowed to the repository, or asking for `contents`; a retried 4xx; the token or the JWT logged; a JWT valid 11 minutes; PKCS#1 not refused by name; 200 accepted for the token; no retry delay; an empty client ID accepted;
  - **its toml (3):** `workers_dev = true`; a route; an hourly cron;
  - **`ontime` (15):** 08:00 instead of 07:00; 06:45 instead of 06:30; the clock instead of `created_at`; the backup ignoring the branch, the actor or the day; a manual run judged; a run off `main` judged; a comment on an open issue every day; the run failed on lateness; a title that merely contains the issue's; an API failure read as a pass; no retry on a 5xx; a retried 4xx; the bot login set without the IDs;
  - **the dead-man check (5):** created runs counted again; a run with no jobs counted; a guess when the Core Web Vitals job is missing; the window ignored; `cancelled` counted as checked;
  - **`production-checks.yml` (8):** `clear` without `run_attempt`, or without `main`; `ontime` off `clear.needs`, off `report.needs`, or off the status line; an `if` on `ontime`; `pull-requests: write` on it; `privacy` back on the workflow's rights;
  - **the deploy files (5):** `deploy-admin.yml` without its environment, or with another; the owner check second; the check reading `actor`; the check that never exits;
  - **the fence read-back (7):** any reviewer accepted; « Prevent self-review » not read; `main` plus another branch accepted; the repository's secrets not read; an unreadable branch rule, environment or secret list passing;
  - **the deploy script (3):** the Worker deployed before the fence is read; the key on argv; the token echoed.

  **The first pass left eight green, and each was looked at:** three were the harness reading the wrong two lines of Dart's output, one ran the wrong test file, one was a mutation that changed nothing (`return 0 || fail()`), and three were real gaps: no test made `ontime` retry, and none read a failed branch-rule or secret-list read in the fence script. Tests added for those; the eight, and three more, re-run on exit codes: 11 red of 11.

**Found by CI, not by the tests:** gitleaks' `private-key` rule, which scans every commit of every branch, read the literal PEM armour lines in the Worker, the deploy script and the test (two armour lines within one match) as a key, on PR #891's first run. No key was ever committed: the test generates its pair at run time. The armour is now built from its label in all three, a scan of every tracked file with the same rule finds nothing (and finds the three old lines in the old commit, the control), and the branch was folded into one commit so that no commit still holds them.

**Not checkable before the merge:**
- `ontime`'s first real run, which should open « The morning check starts late » on the first scheduled run after the merge (every one since 2026-08-27 was created after 07:00);
- the owner check on a real deploy: it passes for `Zaslons` in every run so far, and the next deploy reads it;
- the Worker, until B19.3c–e.

**B19.3b, the owner's settings (GitHub → Settings → Environments), then `bash infra/ci/98-verify-deploy-fence.sh` green:**
1. `backend-production`: Required reviewers → `Zaslons`; « Prevent self-review » off; Deployment branches and tags → Selected → the branch `main`.
2. `admin-production` (created by the merge's first `deploy-admin.yml` run, or by hand): the same two rules; environment secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. GitHub never shows a secret's value, so the token is a new one, minted in Cloudflare with « Cloudflare Pages: Edit » (then the old one is revoked), and the account ID is the value Secret Manager holds as `R2_ACCOUNT_ID`.
3. `backend-staging`: Deployment branches and tags → Selected → `main`.
4. Only then, the repository-level `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` deleted.
5. The stale branches (§4.4 item 4): read on 2026-11-27, every remote branch has an open PR (six Dependabot, #890), so none is stale. `feat/web-salon-page-live-fallback` was deleted on 2026-11-26. With `main` only on each environment, a branch's copy of a deploy file can no longer deploy anyway.
6. From then on, every production deploy waits for the owner's approval: DEPLOYMENT.md gains the step in B19.3b's records.

---

## 12. Independent reviews (2026-11-26)

Two readers, each told to refute: the first read the whole first draft, the second only step 1 after the redesign. Both checked against the code, GitHub's and Cloudflare's docs, and read-only `gh api` and `gcloud`.

### 12.1 First review: the first draft (a Worker and a guard in the workflow files)

**Blocking, and why the design changed:**
1. **A guard in the deploy workflow files cannot hold.**
   - A dispatch can name any of the 9 other branches, and a re-run uses an old commit for 30 days. Both run copies of `deploy-backend.yml` and `deploy-admin.yml` that lack the guard.
   - `deploy-admin.yml`'s Cloudflare secrets are repository-wide.
   - → §2.5, §4.4: the fence moved into GitHub's environments, and the outside trigger became step 2.
2. **The 06:00 run could never close the alarm.** `ontime` ran on scheduled runs only and sat in `clear.needs`, and a skipped need skips `clear`. → `ontime` runs on every `go` run (§3.4).

**Should fix, folded in:**
- **A leaked key could still close the alarm,** from a weaker branch or by re-running only `clear`. → `main` only, first attempt only (§3.4, §4.5).
- **Misuse detection missed things:** re-runs (the runs API's `actor` is the original one), cancellations, and the gaps of a drifting backup. → §4.7: `triggering_actor`, runs updated since the last backup, workflows `active`; called best effort.

**Minor, corrected:**
- « CI has no Cloudflare identity » was copied from a stale comment (§2.7).
- `privacy` and `legal` inherit write rights (§2.6).
- The token endpoint answers 201.
- `ontime` needs `contents: read`.
- The bot login is pinned with the IDs, not guessed.

**Checked and correct:**
- every cited line, and the lateness table;
- every deploy so far started by `Zaslons`;
- a failing first step stops a deploy job;
- a dispatch without `inputs` gets the declared default;
- the Workload Identity conditions;
- the JWT claims and the token narrowing;
- Cloudflare's Free-plan limits;
- that the front door's token can deploy a Worker;
- the stdin pipe into `wrangler secret put`.

### 12.2 Second review: step 1

**Blocking:**
- **The read-back would show green whatever the morning did.** The repository's rule reads the three newest runs, and from 07:17 they are green stop runs. → §3.6: a script that prints the day's `go` run, and the rule replaced in its four places.

**Should fix, folded in:**
- **« Not skipped » counted runs that never checked.** A run cancelled before starting has 0 jobs, and skipped jobs still carry a `started_at`. → « checked » means the Core Web Vitals job concluded `success` or `failure` (§3.3).
- **Two `go` runs if the gate read the clock** (created 05:59, started 06:01). → the run's own `created_at` (§3.3).
- **A day with no tick after 06:00 was invisible.** → `ontime` also opens its issue when no morning run happened the day before (§3.4).
- **Lateness shared the production alarm** and would have held it open all week. → its own issue (§3.4).
- **A gate API error raised a production alarm.** → retries, and a « no check ran » report (§3.3).
- **Existing tests the draft did not list:** the alarm test's « no `if` on a check job », the status line's entries, the registration claim's fixture. → §3.10.

**Minor, corrected:**
- One threshold, not two: 07:00 for both.
- The owner exemption on `clear` dropped.

**The cheaper first step:** test the hypothesis with an empty workflow before building the gate, with `simonw/pge-outages` as the evidence (§3.1, re-read here: 466 runs, first after 06:00 at 06:13–06:19, longest gap 29 minutes). → §3.2.

**Checked and correct:**
- on a stop run, `report` and `clear` are both skipped;
- when the gate fails, `report` fires;
- workflow-level `concurrency` runs one run at a time, and a burst leaves one pending;
- the `created>=` filter works;
- one 100-run page covers three days;
- `github.ref` is `main` on scheduled runs.
