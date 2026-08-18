# The cron OIDC evidence — and the log line nobody read

| | |
|---|---|
| **Module** | infrastructure (Cloud Scheduler, `backend/lib/src/cron_auth.dart`) |
| **Status** | **Evidence obtained 2026-08-17; the header was RETIRED 2026-08-18 — §8.** |
| **Owner** | Sadreddine Daher |
| **Skills checked** | myweli-backend-guardrails |
| **Related** | [DEPLOYMENT.md](../DEPLOYMENT.md) Phase C · [infra-staging.md](infra-staging.md) build order · [BACKEND.md](../BACKEND.md) §7 T21 |

[DEPLOYMENT.md](../DEPLOYMENT.md) has carried the same sentence since the Cloud
Run cutover: *"A transitional `X-Cron-Secret` header is still accepted and is to
be retired once real runs are seen on the OIDC path."*

Unpausing the staging crons produced that evidence in under a minute. Reading the
production logs while looking for it produced a second, better piece — and
corrected a conclusion twice on the way.

---

## 1. Why production's 200s were never evidence

Production's two Scheduler jobs send **both** credentials:

```
myweli-reminders (production)
  oidcToken : aud=https://api.myweli.com
  X-Cron-Secret: True
```

So every one of production's `200`s — every fifteen minutes, for weeks — is
**ambiguous**. It cannot distinguish which credential authenticated. A green cron
history is compatible with the OIDC path being completely broken.

That is the same shape as everything else in this repo's audit history: a check
that cannot fail, believed because it is green. `cron_auth.dart` tries OIDC first
and falls back to the shared secret, so the fallback silently absorbs any OIDC
failure and returns the same 200.

**Staging is the only place that can prove it**, because
[infra-staging.md](infra-staging.md) provisioned its jobs with **OIDC only, no
`X-Cron-Secret`** — deliberately, for exactly this purpose. That decision is why
the evidence took a minute to obtain rather than a day.

## 2. Staging: the positive and the negative half

Both jobs resumed and force-run, 2026-08-17T16:00Z:

| request | result |
|---|---|
| Scheduler → `POST /internal/cron/reminders` (OIDC only) | **200** |
| Scheduler → `POST /internal/cron/subscriptions` (OIDC only) | **200** |
| anonymous `POST /internal/cron/reminders` | **403** `{"error":"forbidden"}` |
| anonymous `POST /internal/cron/subscriptions` | **403** `{"error":"forbidden"}` |
| `POST` with `Authorization: Bearer not-a-real-token` | **403** |

**The negative half is not optional.** A 200 proves authentication only if the
route rejects the unauthenticated — otherwise it proves the endpoint is open,
which is a finding of a very different kind. Both directions were checked before
anything was concluded.

Safe to run at all because staging carries `MESSAGING_PROVIDER=disabled` and
`PUSH_PROVIDER=disabled` on the **serving revision** (read back, not assumed from
the manifest), and holds **0 appointments** — so the reminder tick had nothing to
act on and no channel to act through.

## 3. The log line nobody read — and two wrong conclusions

`reminders.dart:28` carries a deliberate evidence gate:

```dart
if (auth.method == CronAuthMethod.sharedSecret) {
  // The evidence gate: the header stays until a real Scheduler run is seen
  // arriving on the OIDC token instead.
  print('INFO: cron_auth_legacy — … authenticated on the shared secret, not the OIDC token');
}
```

It has been in production the whole time, and nobody had queried it.

**First wrong conclusion.** Grepping an hour of production logs for
`oidc|cron|shared` returned nothing, and I read that as *"the method is not
logged"*. It was a limit-40 grep over all logs — the query was too weak to find
what it was looking for, which is the same defect as a check that cannot fire,
committed in the act of verifying.

**Second wrong conclusion.** A proper query over seven days returned **234**
`cron_auth_legacy` lines, and I read that as *"production has been on the shared
secret this whole time."* Also wrong — it ignored **when**:

| | |
|---|---|
| oldest `cron_auth_legacy` | 2026-08-12T16:15Z, revision `-00013-kmf` |
| newest `cron_auth_legacy` | **2026-08-15T02:00Z**, revision `-00016-pzv` |
| revision `-00017-p4j` created | **2026-08-15T02:11:35Z** — eleven minutes later |

On the current revision, counted directly rather than inferred from the newest
timestamp:

```
cron_auth_legacy on myweli-api-00017-p4j (7d): 0
cron 200s          on myweli-api-00017-p4j (7d): 251
```

**251 consecutive production cron runs on the OIDC path, zero fallbacks.** The
legacy lines are historical, spanning revisions 00013–00016, and they stopped
when `-00017` took over.

Both errors came from the same habit — treating a count as an answer without
asking *when* and *how many out of how many*. The positive control (does this
query shape return anything at all?) is what caught the first; the denominator
caught the second.

## 4. What is now true, and what to do about it

**The condition is met twice over.** Staging proves the OIDC path authenticates
on its own with no fallback present. Production proves the OIDC path is the one
actually in use, 251 runs deep.

**Retiring the header was unblocked here and done in §8**, as its own reviewed
step, in this order:

1. remove the `X-Cron-Secret` header from both production Scheduler jobs, one at a
   time, forcing a run after each and confirming a 200;
2. once both are clean, stop accepting the header in `cron_auth.dart` and delete
   the evidence gate with it;
3. `CRON_SECRET` can then leave `service.yaml` and Secret Manager — and until it
   does, an unset `CRON_SECRET` is still a live fallback, so removing the code
   before the jobs would be the wrong order.

**Do not skip step 1's one-at-a-time.** Production's audience matches on all
three sides (`https://api.myweli.com` in the manifest, the serving revision, and
the job), so it should work — but "should" is what §1 was about, and production
reaches the app through a load balancer that staging does not have.

## 5. Cost of leaving the staging crons enabled

[infra-staging.md](infra-staging.md) created them paused for a real reason:
`*/15` against `minScale: 0` is ~96 cold starts a day, each running the migration
path, in an environment nobody uses between rehearsals.

That is roughly **$0.7–1/month** of Cloud Run time, inside the $0.50–2.00 line §5
already budgets. What it buys is continuous exercise of the boot path — the
`SET LOCAL` migration timeouts and the cron auth — on the environment whose job
is to fail first. Kept enabled on that basis; re-pausing is one command.

## 6. Open

1. ~~**The header is still accepted.**~~ **Retired 2026-08-18 — §8.**
2. ~~**Nothing alerts on `cron_auth_legacy`.**~~ **Shipped — §7.**
3. **Staging's subscription cron has never run on its own schedule** (03:00
   daily); only the forced run is observed.


---

## 7. The alert on `cron_auth_legacy`

`infra/gcp/86-cron-auth-alert.sh`. The gap this closes is the one §3 is about: a
`print` nobody reads is a diary, not evidence. The fallback ran ~2.5 days
unnoticed and then *stopped* unnoticed, so the docs claimed the evidence was owed
for two days after it existed.

**A log-based alert, not a counter metric.** `conditionMatchedLog` fires on the
**first** matching entry with no aggregation window, which is the right shape for
a should-never-happen event — one fallback is already the whole finding, and any
counter threshold above zero is a decision to tolerate some silent fallbacks.

**Both services**, deliberately. Production still *sends* the header, so a line
there means OIDC verification has started failing and the fallback is covering
it. Staging sends no header at all, so a line there means one was added, or the
jobs were recreated from production's definition.

Three filter details worth keeping:

- `textPayload:` — the line is a bare `print`, so it arrives unstructured;
- both service names spelled out rather than a prefix match, because
  `myweli-api` is a prefix of `myweli-api-staging` and a prefix filter would also
  catch any future `myweli-api-*`;
- **no severity clause.** `print` lands at INFO, and a severity filter is one
  more way for the alert to stop matching if the app ever adopts a structured
  logger.

### 7.1 What is proven, and what is not

A log-based alert only sees entries written after it exists, and production is on
the OIDC path — so this policy would read "no incidents" forever whether or not
its filter were correct. That is precisely a check that cannot fire, so it was
attacked from both ends.

| | |
|---|---|
| Policy stored as `conditionMatchedLog`, enabled, 1 channel | ✅ read back from the API |
| Stored filter is the intended one (heredoc escaping survived) | ✅ read back verbatim |
| **The filter matches real log lines** | ✅ run as a `logging read` against 7 days — **234 matches**, the historical production entries |
| **The real code path still emits the line** | ✅ triggered deliberately on staging with the shared secret: HTTP 200 via the fallback, `cron_auth_legacy` logged at `16:32:15Z` |
| Monitoring evaluates the filter → opens an incident | ✅ **verified 2026-08-17T21:38:04Z** — see §7.3 |
| The notification is delivered | ✅ **verified 2026-08-17T21:38:04Z** — the email arrived, see §7.4 |

Running the policy's own stored filter against historical logs is the trick worth
reusing: it proves a filter matches **real** entries without waiting for the
event, and without injecting a synthetic log line that would only prove the
filter matches something you wrote yourself.

### 7.3 It did not fire the first time, and the reason is a trap

The first trigger produced the log line at `16:32:15Z` and **no incident**. That
reads exactly like a broken filter, and it sent this investigation looking for
one.

The policy had been created at **`16:31:17Z`** — **58 seconds earlier**. A newly
created alerting policy is not evaluating yet. The identical trigger against the
identical policy five hours later:

```
log line   2026-08-17T21:37:29Z
incident   2026-08-17T21:38:04Z   (35 seconds later)
```

**Wait several minutes after creating a log-based alert before testing it**, or
the test measures the propagation delay and blames the filter.
`86-cron-auth-alert.sh` now says so where someone will read it.

**And incidents ARE observable programmatically** — this document previously said
they were not, which was wrong. There is no incidents API, but Monitoring writes
every opening to Cloud Logging:

```bash
gcloud logging read 'logName:"monitoring.googleapis.com%2FViolationOpenEventv1"' \
  --limit=5 --freshness=1h \
  --format='value(timestamp,labels.policy_display_name,labels.terse_message)'
```

which returned, verbatim:

```
policy_display_name : A cron authenticated on the LEGACY shared secret
policy_id           : 12705279840136607574
terse_message       : Log match condition fired for Cloud Run Revision with
                      {… service_name=myweli-api-staging}
```

That closes every link except delivery.

### 7.4 The last hop, confirmed — and it settles all five policies

Before this, **five alert policies existed in this project and not one had ever
delivered a notification.** The two uptime checks have never failed (104/0 and
102/0 probes), and the three newer policies were hours old. The channel →
inbox hop had never been exercised, by anything — the same failure shape
`80-uptime-checks.sh` was written to prevent, its own header noting that a policy
with no channel "would have been a policy that notifies nobody".

Neither the API nor the logs could settle it: `verificationStatus` is **absent**
from the channel object, and `ViolationOpenEventv1` is the only
`monitoring.googleapis.com` stream this project has, so an incident *opening* is
recorded and a notification *being sent* is not.

**The mail arrived.**

| | |
|---|---|
| From | `Google Cloud Alerting <alerting-noreply@google.com>` |
| Delivered | `2026-08-17 21:38:04Z` — the same second the incident opened |
| Subject | `[ALERT - No severity] A cron authenticated on the LEGACY shared secret for Cloud Run Revision with {…}` |
| Body | condition `cron_auth_legacy appeared in the logs`, the resource labels, and a VIEW INCIDENT link |

So the channel delivers, and that is proven **once for all five policies** —
including the two uptime checks that guard production. The absent
`verificationStatus` was a red herring: an email channel created by a project
owner needs no verification step.

**The `documentation` field is worth the effort.** The runbook text written into
the policy is rendered in the mail itself, so the notification carries its own
diagnosis rather than just the fact that something fired:

> On PRODUCTION this means OIDC verification is failing and the fallback is
> hiding it — the request still returned 200, which is exactly why this log line
> exists. Check that the job's oidcToken audience still equals
> `CRON_OIDC_AUDIENCE` on the serving revision…

Every policy in `infra/gcp/` sets that field. This is the evidence it reaches a
human at the moment they need it.

**One cosmetic gap:** the subject reads `[ALERT - No severity]` because the
policy sets no `severity`. Harmless, but it means every alert here sorts the same
in a mailbox.

---

## 8. The retirement — 2026-08-18

Done in the order §4 prescribed, because the reverse order removes the fallback
while it is still being sent.

### 8.1 Jobs first — and this is the step that proved it

Production's audience matched on all three sides, so it *should* have worked —
but "should" is what §1 was about, and production reaches the app through a load
balancer that staging does not have. So the header came off **one job at a time**,
each forced immediately afterwards:

| | |
|---|---|
| `myweli-reminders` header cleared → forced run | **200**, zero `cron_auth_legacy` |
| `myweli-subscriptions` header cleared → forced run | **200**, zero `cron_auth_legacy` |

That is the production-side proof that OIDC alone authenticates through the load
balancer, obtained **before** any code depended on it.

Two operational notes for whoever does this again:

- **`gcloud scheduler jobs update http --remove-headers` crashes** — `TypeError:
  'NoneType' object does not support item assignment`. `--clear-headers` works,
  and is safe here because the only custom header on either job was this one.
- **`gcloud scheduler jobs describe` prints the header value verbatim.** That is
  the exposure `cron_auth.dart` documented all along, and it is why the secret
  should be treated as compromised rather than merely unused — see §8.4.

### 8.2 Then the code

`CronAuth` loses `sharedSecret`, `_secret`, the fallback branch, its
constant-time comparison and the `CronAuthMethod` enum; `CronAuthResult` becomes
`({bool ok, String? error})`. Both routes lose the `headerSecret:` argument and
the evidence gate that printed `cron_auth_legacy`.

**The behaviour change is deliberate and worth stating.** Verification used to
fall through to the secret so a misconfigured audience could not take the crons
down. It now returns **403**. An audience that stops matching
`CRON_OIDC_AUDIENCE` fails closed — which is correct, and is why §8.3 exists.

`isConfigured` collapses to `_oidc != null`, and that is complete rather than
partial: `dependencies.dart` builds the verifier as null unless **both**
`CRON_OIDC_AUDIENCE` and `CRON_SERVICE_ACCOUNT` are set, so there is no state
where the route exists but can never authenticate anyone.

The tests that proved the fallback *worked* were **inverted rather than
deleted** — a silently-vanished group is indistinguishable from one that was
never there. `test/cron_auth_test.dart` now asserts a bad token is refused
outright, and greps the source (comments stripped, so the docs may still explain
what went) to prove no parameter or route can accept the header again.

### 8.3 The alert had to move with it

**The `cron_auth_legacy` alert built on 2026-08-17 became permanently inert the
moment the branch that printed that line was deleted.** An alert that cannot fire
is worse than none, because it reads as coverage.

And removing the fallback created a *new* silent failure: a broken audience now
means every cron returns 403 and simply stops, while the service stays healthy
and the uptime checks stay green.

So the policy was **replaced, not kept**: `infra/gcp/86-cron-auth-alert.sh` now
alerts on any `/internal/cron/*` request that does not return 2xx. Its filter was
verified the same way as before — run as a `logging read` against real history,
matching the three genuine 403s from the negative tests in §2.

**Known gap, stated rather than hidden:** this catches a *refused* cron, not an
*absent* one. A job that is paused or deleted produces no log line at all, and
Cloud Monitoring has no absence-of-log condition — that needs a counter metric
plus a threshold plus a window, three numbers to get wrong. Not built.

### 8.4 Config, and the secret itself

`CRON_SECRET` is gone from `service.yaml`, `service-staging.yaml`,
`90-staging.sh` and `.env.example`. The contract was stale in a second way and
is fixed with it: `openapi.yaml` still documented a `?secret=` **query
parameter** that the code had already stopped accepting.

**The Secret Manager entries are NOT deleted here.** They are unmounted and
unaccepted, so they authenticate nothing — but deletion is irreversible and is
one command whenever wanted:

```bash
gcloud secrets delete CRON_SECRET --project=myweli
gcloud secrets delete STAGING_CRON_SECRET --project=myweli
```

Worth doing rather than leaving: the production value was printed in plain text
while stripping the header from the jobs (§8.1), so it should be considered
disclosed. It is inert either way.

### 8.5 What is not true until production deploys

Merging this deploys **staging** automatically; production is a dispatch. Until
that dispatch runs, production serves the old image and would still *accept* the
header — but neither job sends it any more, so the fallback is already
operationally dead. The deploy makes it structural.
