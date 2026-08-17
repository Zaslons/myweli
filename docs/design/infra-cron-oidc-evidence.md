# The cron OIDC evidence — and the log line nobody read

| | |
|---|---|
| **Module** | infrastructure (Cloud Scheduler, `backend/lib/src/cron_auth.dart`) |
| **Status** | **Evidence obtained 2026-08-17.** Retiring the transitional `X-Cron-Secret` header is now unblocked — and deliberately **not yet done**. |
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

**Retiring the header is unblocked. It is deliberately not done here**, because
it is a change to production's authentication and belongs in its own reviewed
step:

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

1. **The header is still accepted.** §4 is a three-step change nobody has made.
2. **Nothing alerts on `cron_auth_legacy`.** It is a `print` that has to be
   queried, and the history shows what that costs in both directions: the
   fallback was in use for **~2.5 days** (2026-08-12T16:15 → 2026-08-15T02:00)
   without anyone noticing, and then **stopped** without anyone noticing either —
   so the documentation kept saying the evidence was owed for two more days after
   it existed. A log-based metric with an alert would surface a regression to the
   fallback; nothing today would.
3. **Staging's subscription cron has never run on its own schedule** (03:00
   daily); only the forced run is observed.
