# Rollback — getting production back, and what rollback cannot reach

| | |
|---|---|
| **Module** | infrastructure (`infra/gcp/`, `.github/workflows/`, `backend/lib/src/db/`) |
| **Status** | **Written and REHEARSED 2026-08-16.** The two guards (§7) are implemented, and the full pin → blocked-deploy → release cycle was run against staging — §12 is the log. |
| **Owner** | Sadreddine Daher |
| **Decisions** | The pin is a tourniquet, never a fix (§3) · we do **not** make it durable (§3.1) · a deploy may not lift a pin by accident (§7.1) |
| **Related** | [DEPLOYMENT.md](../DEPLOYMENT.md) · [infra-staging.md](infra-staging.md) · [infra-prod-hardening.md](infra-prod-hardening.md) · [LAUNCH.md](../LAUNCH.md) §1.4 |

Written because **no rollback procedure existed anywhere in the repo**, and
because as of 2026-08-16 merging to `main` deploys the backend to staging with
no human in the loop ([#393](https://github.com/Zaslons/myweli/pull/393)). The
gap mattered less when every deploy was a deliberate act.

---

## 0. The 30-second version

Production is serving something bad. You want it to stop serving it **now**, and
you do not want to wait for a build.

```bash
gcloud run services update-traffic myweli-api --region europe-west9 --to-revisions myweli-api-00016-pzv=100
```

That is the whole tourniquet. It moves traffic to an existing revision in
seconds, builds nothing, and needs neither GitHub Actions nor a green CI.

**Then read §3, because that command undoes itself.** It is step one of two, and
the second step is a `git revert`. A pin left alone is a rollback that quietly
stops holding.

To list what you can roll back to:

```bash
gcloud run revisions list --service myweli-api --region europe-west9 --format='table(metadata.name,status.conditions[0].status,spec.containers[0].image.basename(),metadata.creationTimestamp)'
```

Prefer the newest revision whose `STATUS` is `True` and that predates the bad
deploy. Revisions are immutable and are never garbage-collected here, so the
history goes back to the Cloud Run cutover: `myweli-api-00017-p4j` is current,
`00016-pzv` is its predecessor, and `00007-qq5` is a failed one (`STATUS
False`) — a revision that never became ready, which is worth understanding
rather than skipping past, because it is the shape of a deploy that rolled
itself back (§6).

---

## 1. Scope

**Covers:** the dart_frog backend on Cloud Run, staging and production.

**Does not cover, and each for a different reason:**

- **Mobile.** There is no rollback. [LAUNCH.md](../LAUNCH.md) §1.4 is the
  authority: a bad app version is on people's phones until they choose to
  update, and some never will. The controls are *staged rollout* and *halt*,
  which are the pre-release form of the same idea. This is also why the backend
  can never respond to an incident by breaking its own API contract.
- **Web (Vercel).** Vercel keeps every deployment addressable and has instant
  promote-a-previous-deployment built into its dashboard. It needs no procedure
  from us.
- **R2 objects.** Buckets are not versioned. An object deleted by a bad code
  path is gone; the `pending/` lifecycle rule is a deliberate one-way collector.
  See [backend-upload-orphans.md](backend-upload-orphans.md).
- **The database.** Not because it is out of scope, but because rollback does
  not reach it at all. That is §5, and it is the most important section here.

---

## 2. The field that tells the truth

Three fields plausibly answer "what is production running?" and after a pin
**two of them are wrong**:

| Field | After a normal deploy | After a traffic pin |
|---|---|---|
| `spec.template.spec.containers[0].image` | the deployed image ✓ | the **bad** image — the template still describes the newest revision |
| `status.latestReadyRevisionName` | the serving revision ✓ | the **bad** revision — it is ready, it just has no traffic |
| `status.traffic[].revisionName` | the serving revision ✓ | the serving revision ✓ |

Only the last one is about traffic. The other two describe intent and
readiness, and both agree with each other while being wrong, which is the
failure mode that reads as confirmation.

**Measured, not reasoned** — staging pinned from `-00005-xr6` to `-00004-5kw`
on 2026-08-16 (§12):

```
spec.template…image           : …@65de7e70…      ← the image of -00005, the one rolled AWAY from
status.latestReadyRevisionName: myweli-api-staging-00005-xr6   ← likewise
status.traffic[].revisionName : myweli-api-staging-00004-5kw   ← the truth
```

```bash
gcloud run services describe myweli-api --region europe-west9 --format='value(status.traffic[].revisionName)'
```

Note that the deploy workflow's own verify step reads
`spec.template.spec.containers[0].image` — correctly, because at that moment it
is asserting *"the manifest I just applied is the one in place"*, and it runs on
a service it has just un-pinned. It is not a model for incident inspection.

`gcloud run services describe` also prints a human summary at the top; during an
incident use the explicit `--format` above rather than reading the summary,
which abbreviates.

---

## 3. The pin is a tourniquet, and it erases itself

Both `service.yaml` and `service-staging.yaml` end with:

```yaml
  traffic:
    - percent: 100
      latestRevision: true
```

`update-traffic --to-revisions` replaces that live with an explicit
`revisionName`. The committed manifest still says `latestRevision: true`, and
the next deploy runs `gcloud run services replace` — **which puts it back**.

So:

> A traffic pin survives until the next deploy of that service, and then
> silently stops holding. Nothing announces it. The revision it was protecting
> you from becomes the serving revision again, because it is once again the
> latest.

Before 2026-08-16 that was a slow trap: production deploys are dispatch-only, so
someone would have had to type `deploy` to spring it. **Staging now deploys on
every merge to `main` that touches `backend/**` or either manifest**, so a pin on
staging is undone by the next merge — quite possibly within the hour, by someone
who was not part of the incident.

**Therefore the pin is never the fix.** It buys the minutes in which you do the
real one:

1. **Pin** — traffic stops reaching the bad revision. (§0)
2. **Revert** — `git revert <sha>`, open a PR, merge. Staging redeploys itself
   from the reverted source; production is a dispatch (§4.2).
3. **Release the pin** — deliberately, as part of that deploy (§7.1).

### 3.1 Why we do not make the pin durable

The obvious "fix" is to commit an explicit `revisionName` into the manifest so a
deploy cannot undo it. That is worse, and it is worth writing down so nobody
implements it later as an improvement:

- A manifest naming a revision is a manifest that **ignores every subsequent
  deploy**. CI goes green, the workflow's verify step passes, and no new code
  ever serves — the "deploys succeed but nothing changes" failure, which is
  materially harder to notice than an outage.
- Revision names (`myweli-api-00017-p4j`) contain a generated suffix, so the
  value could not be reviewed for correctness in a PR.
- It inverts the default. `latestRevision: true` is right in steady state; the
  pin is right for minutes.

The pin stays ephemeral and the guard in §7.1 supplies what durability was meant
to buy: a deploy cannot lift it *silently*.

---

## 4. The three mechanisms, and when each is right

### 4.1 Traffic pin — seconds, no build

`gcloud run services update-traffic … --to-revisions REV=100`.

**Use when:** production is actively broken and the cause is the deployed code.

**Requires:** `gcloud` authenticated as a principal with `roles/run.admin` on
`myweli`. The owner account has it. Note that this is *not* the WIF path — the
deployer service account is reachable only from a GitHub Actions job declaring
an `environment:`, which is exactly the wrong dependency during an incident.
**A human's own credentials are the right tool here**, and that is deliberate.

**Effects to expect:** the target revision cold-starts. Its boot sequence runs
in full — the `pg_advisory_lock` schema-setup block, `runMigrations` (a no-op,
§5.1) and every fail-fast config guard. Budget for the cold start rather than
assuming instant; `startupProbe` allows up to 300s before it gives up, and a
production cold start with migrations already applied is far below that.

**One thing it does not restore: secret values.** Every `secretKeyRef` in both
manifests uses `key: latest`, which resolves when the instance starts. A
rolled-back revision therefore reads **today's** secrets, not the ones current
when it was built. If the incident was caused by a rotated or corrupted secret,
rolling back the image changes nothing — fix the secret version instead.

### 4.2 Revert the commit — the actual fix

`git revert` on a branch, PR, merge. This is the only mechanism that leaves the
repository describing what is deployed, which is the property the whole
declarative-manifest stance exists to preserve.

- **Staging** redeploys itself on the merge.
- **Production** is `workflow_dispatch` with the typed `deploy` confirmation,
  plus `unpin: yes` if a pin is in place (§7.1).

Prefer `git revert` over a forward "fix" commit written under pressure: a revert
is reviewable as *"this is exactly the inverse of that"*, and the diff to read is
one you have already read once.

### 4.3 Promote an older image — a rollback that respects `latestRevision`

The deploy workflow takes an `image_tag` input (a short SHA). Dispatched with
it, the workflow **builds nothing**, resolves that tag to a digest, and deploys
it as a **new** revision — which is then the latest, so `latestRevision: true`
is satisfied and there is no pin to remember.

That makes it the tidiest emergency mechanism, and it has one sharp edge worth
stating plainly:

> The workflow checks out `main` and applies **today's** `service.yaml`. You get
> the **old image** with the **new manifest**.

Harmless when the bad change was code only. Wrong when it also changed the
manifest — a revision built before a secret existed, deployed against a manifest
that mounts it, gets an environment variable its code never reads (benign), while
the reverse — new manifest dropping a variable the old image fail-fasts on —
**does not become ready at all**. That failure is loud and safe (§6), but it will
cost you the minutes you were trying to save. Check whether the bad deploy
touched `infra/gcp/` before choosing this over §4.1.

### 4.4 Choosing

| Situation | Mechanism |
|---|---|
| Production is down or serving wrong data, right now | §4.1 pin, then §4.2 |
| Bad code, not urgent (staging, or a cosmetic prod bug) | §4.2 alone |
| Need a specific known-good artifact, code-only change | §4.3 |
| The revision never became ready | **nothing** — see §6 |
| A migration is the problem | none of these — see §5.2 |

---

## 4.1 Why there is no canary, and what would change that

Cloud Run can split traffic between revisions, and a production deploy here does
not: `spec.traffic` is `latestRevision: true, percent: 100`, so a deploy is an
instant, total cutover. That was reviewed on 2026-08-19 and **kept**, on three
grounds worth writing down so it is not re-argued from scratch:

1. **A canary needs traffic to compare, and there is none.** Production has 5
   user rows, 0 salons and 0 appointments. Routing 5% of nothing to a new
   revision produces no signal — it produces the *appearance* of caution, which
   is worse, because it reads as a control that is working.
2. **The dangerous class already fails closed.** Migrations run before the port
   binds and the startup probe allows 300s; a revision that cannot migrate, or
   cannot boot, never becomes Ready and therefore never takes traffic. §6 is
   that property. A canary defends against a revision that boots fine and
   behaves badly — a real class, but not the one the schema changes here belong
   to.
3. **Rollback is a real lever, not a theoretical one.** Previous revisions are
   retained, and the schema changes shipping now are additive (`CREATE TABLE IF
   NOT EXISTS`), so the old code runs unchanged against the new schema. §5 is
   where that stops being true — and when it does, expand/contract is the
   answer, not a traffic split.

**What would change the decision:** real user traffic, which makes a percentage
meaningful, or a release whose schema change is not backward-compatible, which
breaks ground 3. Both are already covered by the working rhythm in
[LAUNCH.md](../LAUNCH.md) §7 — "enable for ourselves, then a slice, then
everyone" — so this is not a promise filed in a document with nothing to enforce
it; it is a note explaining why that rhythm's traffic-splitting step is dormant
today. It stays dormant until §7 step 5 is the step being worked.

## 5. What rollback does not undo: the database

**Migrations are one-way.** `backend/lib/src/db/migrations.dart` holds 35
migrations as ordered `(id, statements)` records with **no down statements**, and
none are planned. Rolling the image back rolls the schema back by nothing at all.

This is the section to read *before* an incident, because the question "is it
safe to roll back?" has a different answer depending on what the last migration
did, and you will not want to work that out under pressure.

### 5.1 Why an old image nevertheless boots against a forward schema

`runMigrations` iterates **its own** compiled-in list and, for each id, asks
`SELECT 1 FROM schema_migrations WHERE id = @id`. Rows for migrations it has
never heard of are simply not consulted. An image from before migration `0031`
sees `0031` in the table and does not care.

So the mechanical objection — *"the database is ahead, the old image will refuse
to start"* — does not apply. **Rollback is safe by construction on the boot
path.**

### 5.2 Where it stops being safe: the schema itself

The real constraint is whether the old *code* can run against the new *schema*.
That is a property of the migrations, not of the rollback:

- **Additive** (`ADD COLUMN`, `CREATE TABLE`, `CREATE INDEX`, `DROP NOT NULL`,
  dropping a `UNIQUE` constraint) — old code ignores what it does not select.
  Rollback is safe.
- **Destructive** (`DROP COLUMN`, `DROP TABLE`, `ALTER … RENAME`, `SET NOT
  NULL`, a narrowing type change) — old code selects a column that is gone, or
  inserts a row that now violates a constraint. **Rollback across such a
  migration breaks the old image**, and there is no down statement to undo it.

**Most migrations are additive; five are not, and they say so.** A count is
deliberately not repeated here — a number beside a list is a second source of
truth, and this one was three behind for months. `grep 'rollback-unsafe:'
backend/lib/src/db/migrations.dart` is authoritative, and
`migration_reversibility_test.dart` fails any new narrowing constraint that
is neither declared unsafe nor explained as safe.

The five add a UNIQUE index or an EXCLUDE constraint to a table that already
existed, so an older image can write a row the database now refuses:
`0009` (appointment overlap), `0022` and `0023` (one account per email, where
email had been free text since `0001`/`0003`), and `0026`, which adds BOTH a
per-artist unique slot and a per-artist overlap exclusion — an image that
books per salon has no notion of an artist calendar.

The other statements that look destructive
look destructive are `ALTER TABLE users ALTER COLUMN phone_number DROP NOT NULL`
and two `DROP CONSTRAINT IF EXISTS` on unique indexes — all three *widen* the
schema, which is the safe direction.

That is a fact about the current state, and a runbook resting on a fact that can
silently change is the failure this repository keeps finding. So it is enforced
rather than asserted: see §7.2.

The same discipline is already policy for a second reason —
[LAUNCH.md](../LAUNCH.md) §1.4 requires expand → migrate → contract because
**installed app versions cannot be rolled back**. Backend rollback and mobile
compatibility want the identical property, which is a good sign it is the right
one.

### 5.3 Data written by the bad code

Nothing here addresses it. A revision that wrote wrong rows for twenty minutes
has left them behind, and rolling back the image stops the writing without
touching what was written.

The available recovery is **Cloud SQL point-in-time recovery**, which restores to
a *new instance* — a data-recovery operation with its own downtime, not a
rollback. If an incident needs it, stop following this document and open
**[infra-dr-restore.md](infra-dr-restore.md)**, which has the procedure and the
five traps that cost time when it was rehearsed on 2026-08-16.

Two numbers to carry into that decision: the restore itself took **26 minutes**
against a 10 MB database and grows from there, while **promoting** it — pointing
the service at the restored instance — takes **17 seconds**. The restore
dominates entirely, so an RTO estimate is a restore estimate.

Promotion is a **two-line manifest change**, not a `DATABASE_URL` change
(infra-dr-restore.md §8) — and it carries the **same self-erasing trap as the
traffic pin in §3**: a hand-edited service config is reverted by the next deploy
of the *committed* manifest. Commit the two lines.

What no rehearsal can remove is the **write-loss window**: everything written
between the restore point and the cutover is gone. That part stays a judgement
call.

---

## 6. A failed deploy has already rolled itself back

Worth internalising, because it removes a whole class of panic:

`gcloud run services replace` creates a new revision and shifts traffic **only
once that revision is ready**. A revision that crashes on boot — a missing
secret, a `boot_config.dart` fail-fast, a migration that throws — never becomes
ready, never takes traffic, and the previous revision keeps serving. `replace`
then exits non-zero and the workflow goes red.

`myweli-api-00007-qq5` in the revision list is exactly this: `STATUS False`,
never served, harmless.

**So a red deploy is not an incident.** Fix forward at normal speed.

The deploy that needs this document is the one that went **green** and is wrong:
it became ready, it took traffic, and every check in the workflow passed —
because `/health` reads no config and `/providers` proves only that the database
is reachable.

---

## 7. The two guards this document adds

A runbook whose central steps can be silently skipped is not a control. Two
things here were prose that needed to be properties.

### 7.1 A deploy may not lift a traffic pin by accident

`.github/workflows/deploy-backend.yml` reads the live traffic block before
deploying. If traffic is pinned to an explicit revision, the deploy **fails**
with the pin's revision name and the command to inspect it — unless the run
explicitly declares `unpin: yes`.

- **Production** is dispatched, so the operator sets `unpin: yes` in the same
  form where they type `deploy`. Lifting the pin becomes a second deliberate
  act, in the run that replaces the code the pin was protecting against.
- **A push to `main` carries no inputs**, so `unpin` is empty and a pinned
  staging service fails the deploy rather than quietly un-pinning. Loud, and in
  the safe direction: staging pins are rare and deliberate, and the message says
  what to do.

Failing closed is the right default here because the two outcomes are not
symmetric. A blocked deploy is visible and self-correcting; a silent un-pin
restores the exact revision someone was mid-incident about, and looks like a
successful deploy.

The check must run **before** the build — there is no reason to spend four
minutes of Docker build on a run that cannot deploy — but **after** auth, since
it needs to query Cloud Run.

### 7.2 A destructive migration cannot land unnoticed

`backend/test/db/migration_reversibility_test.dart` scans the migration
statements for the DDL that would break §5.2 and fails on any of it.

It is deliberately **not** a ban. A `DROP COLUMN` is legitimate as the *contract*
step of expand → migrate → contract, once no deployed code reads the column. The
test asks that it be declared: a migration that genuinely intends it carries a
`// rollback-unsafe:` comment naming why, which turns an invisible property of
the schema into a line in a diff — and gives whoever is holding this runbook at
2am a greppable answer to "can I roll back past this?".

The test also pins its own vocabulary against the migration file, so a rename of
the guard comment cannot quietly empty it. That is the same shape as
`r2_manifest_test.dart`'s check on the read-only R2 script, and for the same
reason: **a guard that cannot match is worse than no guard, because it is
believed.**

---

## 8. Staging differs in three ways that matter mid-incident

- **`minScale: 0`** — every rollback target cold-starts from nothing, and the
  cold start is the path that runs migrations behind the advisory lock. Slower
  than production, deliberately (infra-staging.md).
- **`ingress: all` and no load balancer** — the service's own `*.run.app`
  address is the only door, and it is `status.url`, **not** the hostname
  `gcloud run services replace` prints. Cloud Run publishes two.
- **It is not an outage.** Staging has no users. A staging rollback is a
  convenience; prefer §4.2 and let it redeploy.

The service name is `myweli-api-staging` and every command in this document
takes it in place of `myweli-api`.

---

## 9. After a rollback — what to check

```bash
# 1. What is actually serving (§2 — this field, not the other two)
gcloud run services describe myweli-api --region europe-west9 --format='value(status.traffic[].revisionName)'

# 2. It is up, and it knows which environment it is
curl -fsS https://api.myweli.com/health

# 3. The database is reachable — /health never touches it
curl -fsS https://api.myweli.com/providers >/dev/null && echo ok
```

`/health` reporting `"env":"prod"` is the one answer that comes from the running
artifact rather than from the name of the thing you addressed.

Then, before the incident is closed:

- [ ] The pin is recorded somewhere a colleague will see — it is invisible in the
      repository, and §3 is what happens if it is forgotten.
- [ ] A revert PR is open (§4.2). The pin is not the fix.
- [ ] If a migration was involved, §5.2 is answered explicitly rather than
      assumed.

---

## 10. What production and staging looked like when this was written

Recorded so a future reader can tell drift from difference — this is a snapshot,
not a requirement.

| | production | staging |
|---|---|---|
| Service | `myweli-api` | `myweli-api-staging` |
| Serving | `myweli-api-00017-p4j` | `myweli-api-staging-00004-5kw` |
| Traffic | `latestRevision: true`, unpinned | `latestRevision: true`, unpinned |
| Front door | `https://api.myweli.com` (load balancer) | `status.url` (`*.run.app`) |
| Deploy trigger | dispatch + typed `deploy` | **push to `main`** |
| Migrations applied | 31 | 31 |

---

## 11. Open questions

1. ~~**This procedure is unrehearsed.**~~ **Closed 2026-08-16** — rehearsed
   end to end on staging; §12 is the log, and §2's three-field table is now a
   measurement. What remains untested is the same cycle on **production**, where
   the load balancer sits in front and `minScale` is 1; nothing in the mechanism
   differs, but that is an argument, not evidence.
2. ~~**`lock_timeout` / `statement_timeout` are still unimplemented.**~~
   **Closed 2026-08-16** —
   [backend-migration-timeouts.md](backend-migration-timeouts.md). Both are now
   applied as `SET LOCAL` at the top of every schema-setup transaction, so a
   lock-blocked migration fails in 3s instead of hanging the boot until the
   probe gives up at 300s. Watched: with the guard removed, a blocked `ALTER`
   never returns.
   **The advisory lock in `withSchemaLock` is deliberately excluded** — both
   timeouts abort a *waiting* `pg_advisory_lock()`, and that wait is normal
   contention between cold-starting instances, so bounding it would fail healthy
   deploys. §6's "a failed deploy rolls itself back" now holds *quickly* rather
   than after a silent 300s.
3. ~~**Cloud SQL PITR has never been exercised.**~~ **Closed 2026-08-16** —
   [infra-dr-restore.md](infra-dr-restore.md). A point-in-time clone of
   production came up with 31 migrations and 39 tables intact in 26 min 14 s.
   What remains untried is **promoting** one: repointing a running service at a
   restored instance, which is the step that carries the write-loss window.
4. **Nothing records that a pin exists *while it is holding*.** The rehearsal
   improved this by accident: §7.1's `::warning::` surfaces as a **run-level
   annotation** on the deploy that releases a pin, so the release is
   permanently visible on the run rather than buried in step logs. But that
   fires at the *end*. While a pin is in place, the only witnesses are a human's
   memory and the next deploy going red. A scheduled check that alerts on
   `spec.traffic[].revisionName` being non-empty would close it, and now that
   question 1 is answered it is the next thing worth building here.

---

## 12. The rehearsal — 2026-08-16, on staging

Run because §11 question 1 said this document was reasoning rather than
evidence. Recorded in full because the value of a rehearsal is the part that did
not go as written.

| # | Act | Observed |
|---|---|---|
| 0 | baseline | all three fields agree on `-00005-xr6`; `spec.traffic[].revisionName` empty |
| 1 | `update-traffic --to-revisions -00004-5kw=100` | traffic moved; `Routing traffic…done` |
| 2 | inspect | **§2 confirmed** — two fields name `-00005`, only `status.traffic[]` names `-00004` |
| 3 | the pinned revision serves | `/health` ok, `/providers` **HTTP 200** — the rollback target is genuinely serving, database included |
| 4 | dispatch a staging deploy, `unpin` empty | **blocked at the guard**, exit 1, naming `-00004-5kw` |
| 5 | inspect that run's steps | `Configure Docker`, **`Build and push`**, `Deploy`, `Verify` all **`skipped`** |
| 6 | dispatch again with `unpin: yes` | succeeded; the `::warning::` became a **run annotation** |
| 7 | final state | `-00006-pcq` serving, `spec.traffic latestRevision: True`, `/health` + `/providers` ok |
| 8 | production | `myweli-api-00017-p4j` throughout, `"env":"prod"` — never touched |

**Three things the rehearsal established that argument had not:**

- **§7.1's placement earns itself.** Step 5 is the point: the guard sits before
  `Configure Docker` and after auth, so a blocked deploy spends **no Docker
  build at all**. That was a design claim; it is now an observation.
- **`${UNPIN}` is safe under `set -u`.** A dispatch that leaves the input empty,
  and a push which has no `inputs` object whatsoever, both make
  `${{ github.event.inputs.unpin }}` evaluate to `''`, and GitHub still defines
  the env var — so `[ "${UNPIN}" = "yes" ]` compares rather than aborting with
  *unbound variable*. Worth having checked: had it aborted, the deploy would
  still have failed (the safe direction) but with a message about shell scoping
  instead of about a rollback.
- **A dispatch with `unpin` empty is the same code path as a push.** Both
  produce `UNPIN=''`; the guard cannot tell them apart, which is why step 4 is
  evidence about the automatic path even though it was triggered by hand.

**One claim this rehearsal did *not* establish.** §4.1 says to budget for a cold
start on the target revision. `/health` answered in ~0.4s at step 3 — but
`-00004` had been idle for roughly four minutes, well inside the window in which
Cloud Run keeps an idle instance alive. **That is not a cold-start measurement**,
and §4.1's advice stands unverified rather than confirmed.

