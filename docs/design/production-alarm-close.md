# Production alarm — closed when all is green, and it reaches a person (B9.16) — design spec

| | |
|---|---|
| **Status** | **Built 2026-11-02**, #726. The owner approved it the same day: the @mention route, and a mention on every failing day. **The close is proved by a real run on 2026-11-03, and the owner reports that the email arrived; a real reopening is not proved** (§5) |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-11-04 |
| **PRD ref / phase** | Operations, no product requirement · V1 |
| **Module** | `.github/workflows/production-checks.yml`, `backend/test/infra/production_alarm_test.dart` |
| **Origin** | BACKLOG B9.16. `myweli-verification-guardrails` rule 16 records the incident |
| **Skills checked** | myweli-dev-guardrails ✓ · myweli-verification-guardrails ✓ · no app, web, backend or contract change |

---

## 1. Goal & scope

**Goal.** When the daily monitor fails, the owner finds out that day, by email. An open alarm means something is failing now.

**Why.** The monitor was red from 2026-10-21 to 2026-11-02 and nobody noticed for 13 days. Its only signal was a bot comment on issue #549, which has been open since 2026-09-16, including two fully green weeks in October.

**In scope:**
- A new job that closes the alarm after a fully green scheduled run (§3.1).
- An @mention of the owner in the failure comment and the closing comment (§3.2).
- A guard that runs both jobs' scripts (§4).

**Out of scope:**
- A red manual run still reopens the alarm and comments, as it does today, even if it measured another site. The next green scheduled run closes it again, so the mistake corrects itself within a day. Restricting that is a separate decision.
- The Cloud Monitoring « Owner email » channel. It is the fallback if the mention's email does not arrive (§6).
- The GitHub mobile app. It only shows what GitHub already sends, so it would change nothing here.

---

## 2. What was measured (2026-11-02)

**The owner's GitHub inbox has no thread for #549.** Read with the owner's own `gh` login, read-only, across all pages for this repo:
- 404 threads, from 2026-08-02 to today. All are pull requests, with the reasons `author`, `state_change` or `comment`.
- None for #549 or any other issue, although #549 has 33 comments, the latest at 14:17 UTC today.
- None for failed Actions runs, although the scheduled runs are under the owner's account.
- The control: PR threads from today do appear, so the empty result for #549 means something.

**The owner reports that the emails they get are Vercel's.** They do not have the GitHub app.

**What this cannot show.** The account's email settings are not readable from here. Whether the owner watches the repo is not readable either: the check returned a 404, which looks the same with or without a subscription, because this login lacks the `notifications` scope. So closing the issue alone would not get a failure noticed, as far as anything here can see. A reopening notifies the same nobody.

**The lookup, against the real repo, outside a checkout:**

| Command | Result |
|---|---|
| Without `GH_REPO` | `not a git repository`, exit 1 |
| With `GH_REPO` | `549` |
| With `GH_REPO`, a title that matches nothing | nothing printed, exit 0 |

**Today's run:** six of the seven checks passed. Only `privacy` failed, on the stale match #725 fixes.

**Eight checks since 2026-11-05 (B11.3):** `cardphoto` joined them, and its comment on a close says what it means. It reads nothing until a public salon has a photo, and a green run then claims nothing about one: the run's log says which ([web-swiss-cards.md](web-swiss-cards.md) §9).

---

## 3. The change

### 3.1 The other half: closing the alarm

A new job, next to `report`:

```yaml
clear:
  name: Close the alarm, if every check passed
  needs: [cwv, privacy, legal, retention, attestation, secretpins, basemap]
  if: github.event_name == 'schedule' && success()
```

Its script uses the same lookup as `report`, including `// empty`, then:
- No issue with that exact title: says so and exits 0.
- Already closed: says so and exits 0.
- Open: `gh issue close` with a comment that links the run and mentions the owner.

It sets `GH_REPO`, because it does not check out the repo, like `report`.

| The run | What happens to the alarm |
|---|---|
| Scheduled, all eight passed, issue open | **Closed**, with a comment and a mention |
| Scheduled, all eight passed, issue closed or missing | Nothing, and the job passes |
| Scheduled, at least one failed | As today: reopened if closed, then a comment, now with a mention |
| Scheduled, cancelled | Nothing: neither job runs |
| Manual, all passed | **Nothing.** A manual run can measure another site through `target` |
| Manual, at least one failed | As today, now with a mention (§1, out of scope) |
| A failed scheduled run, re-run by hand, now passing | Closed. It should still count as a `schedule` event aimed at production (expected from GitHub's behaviour, not observed here) |

**If the close itself fails** (a GitHub outage, say), the job goes red, the alarm stays open, and the next green run tries again. It errs towards leaving the alarm on.

### 3.2 Reaching the owner

The failure comment and the closing comment both start with `@Zaslons`. A mention is what makes GitHub notify someone who is not watching the repo.

- **The login is written out, not `github.repository_owner`.** The person is who should be told, even if the repo moves to an organisation.
- **Every failing day sends a mention, not only the first.** The incident was 13 quiet days, and nothing sends this mail unless something is broken.
- **A recovery sends one too.** That is what lets the next green run test delivery without a real failure.

### 3.3 The comment that is no longer true

The comment above `report` says every other alert reaches a person and this one did not. Now it will say what was measured and why the mention exists.

---

## 4. The guard

`backend/test/infra/production_alarm_test.dart`. It reads the parsed YAML, so a comment cannot satisfy it, and it runs the real scripts.

**The scripts, run with a stand-in `gh`.** It uses the real `jq` and behaves like the real `gh` measured in §2: it fails without `GH_REPO`, and lists only open issues unless told `--state all`. Only the env names the YAML declares are passed in.

| Job | Situation | Expected |
|---|---|---|
| `clear` | Open | Closes that issue; the comment mentions the owner and links the run |
| `clear` | Already closed | Does not close; exits 0 |
| `clear` | No issue | Does not close or view anything; exits 0 |
| `clear` | Only a similar title | Does not close; exits 0 |
| `clear` | `gh` fails on the lookup | Fails, rather than reporting nothing to do |
| `report` | No issue | Creates it with that title; the body mentions the owner |
| `report` | Open | Comments with the mention; no reopen |
| `report` | **Closed** | **Reopens and comments with the mention.** This is the point of B9.16 |

**The structure, derived rather than listed:**
- `clear.needs` and `report.needs` each equal every other job in the file. A new check missing from `clear.needs` would let the alarm close while that check is red.
- `clear.if` and `report.if` are exactly as written. Changing when the alarm closes should be a deliberate edit.
- No check job has `continue-on-error` or its own `if`, on the job or a step, since either could count an unpassed check as passed.
- `clear` has no `permissions` block of its own, which would drop `issues: write`.

**Mutations, watched on committed work: 33 of 34 went red.** A harness refused a dirty tree, asserted that each mutation changed the file, ran the unmutated control first, and restored by checksum. They covered:
- each part of both `if` lines, and each `needs` list;
- an eighth check in neither list;
- `GH_REPO` in both jobs, and `GH_TOKEN` in `clear`;
- `// empty` in both jobs;
- the no-issue and already-closed branches, and the reopen;
- `--state all` in `report`;
- each mention, the run link, and the title changed in one job only;
- the exact-title match, and a swallowed lookup failure;
- each `gh` write swapped for `echo`;
- `continue-on-error` and `if` on a check job and on a step;
- `permissions` on each job, and `issues: write` removed from the workflow.

**The one that stayed green, as predicted:** removing `--state all` from `clear`. That job only ever closes open issues, so its behaviour does not change.

**The real scripts against the real repo, read-only.** A wrapper passed `issue list` and `issue view` to the real `gh` and recorded writes without running them. Both ran outside a checkout, and #549 stayed untouched at 33 comments:

| Job | With `GH_REPO` | Without `GH_REPO` |
|---|---|---|
| `clear` | exit 0, one write recorded: `gh issue close 549` with the mention and link | exit 1, `not a git repository`, nothing written |
| `report` | exit 0, one write recorded: `gh issue comment 549` with the mention | exit 1, `not a git repository`, nothing written |

**What this guard cannot see:**
- How GitHub evaluates the `if`. It reads that line as text; only GitHub runs it, and neither `act` nor `actionlint` is installed here.
- Whether GitHub accepts the file. Nothing parses a `schedule` and `workflow_dispatch` workflow before it reaches `main`. The new job follows `report`'s shape, which lowers that risk without removing it. If GitHub stopped scheduling the file, `The production monitor is still firing` would fail after three days. A rejected file might instead log a failed run, which that job cannot tell apart, and that has not been measured. Reading the next run (§5) settles it.
- Whether a mention from the bot notifies anyone, and whether the email is delivered. See §5.

---

## 5. What is not proved until it runs

**The first real proof is the next scheduled green run closing #549.** That needs both #725 and this PR merged first. The cron says 06:00 UTC, but the last ten runs started between about 10:00 and 14:15 UTC.

Reading that run answers three things:
1. Did the `clear` job run, and did #549 close with the comment?
2. Did `report` skip?
3. **Did the owner get the email?** Only the owner can answer this one.

The first real reopening proves the failure path, and that can only happen when something fails. The guard covers its logic until then.

Nothing is dispatched and #549 is not closed by hand without the owner's explicit go.

**Read at 16:05 UTC on 2026-11-04, by GET, answering the three:**

1. **Yes.** Scheduled run `41642929847`, on `4e78e485`, `success`. `clear` ran, and #549 closed at 13:20:16 UTC on 2026-11-03, with a comment that mentions the owner, says every check passed and links the run.
2. **Yes.** `report` was skipped.
3. **Yes, as the owner reports it on 2026-11-04.** GitHub recorded a `mentioned` event for the owner at 13:21:10 UTC, and their inbox now holds a thread for #549 with the reason `mention`, marked read, where §2 found none. So the mention reached GitHub's inbox. The email itself cannot be read from here.

The next scheduled run, `41838514759` on 2026-11-04, was green too: `clear` ran against the closed issue, and #549 stayed closed with no new comment, as the guard's « Already closed » row expects. **Still not proved by a real run:** the failure path, a reopening.

---

## 6. Rollout and owner steps

A workflow change takes effect when it reaches `main`. There is no deploy.

**The owner:** asked on 2026-11-04, they report that the closing email of 2026-11-03 arrived (§5). Nothing is left for them here.

**If a later mention does not arrive,** check at github.com/settings/notifications that **Email** is on under « Participating, @mentions and custom », and that the default notification address is the mailbox they read. If it is, the next step is the Cloud Monitoring « Owner email » channel, which is a cloud change and needs the owner's go.

---

## 7. Definition of done

- [x] Owner's sign-off on this spec.
- [x] Guard green; mutations watched on committed work (§4).
- [x] Indexed in `docs/design/README.md`; roadmap entry added; B9.16 ticked in `docs/BACKLOG.md`, with « B9.16 open » removed from the Batch 9 heading and row 9.
- [ ] Feature branch and PR; merged only on the owner's word; no Claude attribution.
- [x] The next scheduled green run read, on 2026-11-04 (§5). The owner reports that the email arrived.
