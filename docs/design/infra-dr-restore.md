# Restoring the database — the rehearsal, and the five things that went wrong

| | |
|---|---|
| **Module** | infrastructure (Cloud SQL `myweli-db`, `europe-west9`) |
| **Status** | **Rehearsed end to end, 2026-08-16.** Closes [LAUNCH.md](../LAUNCH.md) §5.5 and gives [infra-rollback.md](infra-rollback.md) §5.3 a procedure instead of a pointer. |
| **Owner** | Sadreddine Daher |
| **Skills checked** | myweli-backend-guardrails |
| **Related** | [infra-rollback.md](infra-rollback.md) §5.3 · [infra-staging.md](infra-staging.md) §3.2 · [LAUNCH.md](../LAUNCH.md) §5.5 |

[LAUNCH.md](../LAUNCH.md) §5.5 said it plainly: *"Until that is done we do not know
we have backups."* We now know. **A point-in-time restore of production works,
takes about half an hour, and has five failure modes that all look like
something else.**

This is the *data* recovery path. Rolling back the deployed **code** is
[infra-rollback.md](infra-rollback.md), and §5 of that document is explicit that
rollback does not reach the database — this is what it hands off to.

---

## 1. The procedure

Cloud SQL's PITR restores into a **new instance**; it cannot rewind an existing
one. That is a feature here — production keeps serving while you work.

```bash
# 1. A point in time inside the 7-day transaction-log window.
gcloud sql instances clone myweli-db myweli-db-dr-<date> \
  --point-in-time='2026-08-16T19:06:55Z'

# 2. Wait on the OPERATION, not the instance state (§2.1).
OP=$(gcloud sql operations list --instance=myweli-db-dr-<date> --limit=1 --format='value(name)')
gcloud sql operations wait "$OP" --timeout=3600

# 3. Look at it. Connect as the OWNING ROLE, never `postgres` (§2.4).
gcloud sql instances patch myweli-db-dr-<date> --authorized-networks="$(curl -4 -s ifconfig.me)/32"
gcloud sql users set-password myweli_app --instance=myweli-db-dr-<date> --password=…
psql "host=<ip> user=myweli_app dbname=myweli sslmode=require" \
  -c 'SELECT count(*) FROM schema_migrations;'

# 4. When finished — deletion protection is INHERITED (§2.3).
gcloud sql instances patch myweli-db-dr-<date> --no-deletion-protection -q
gcloud sql instances delete myweli-db-dr-<date> -q
```

**Promoting a restore to production is deliberately not scripted here.** It means
repointing `DATABASE_URL` at the new instance and redeploying — a decision with
its own data-loss window (everything written between the restore point and the
cutover), which belongs to whoever is holding the incident, not to a snippet.

## 2. What went wrong, and why each one matters

Every item below cost time during a rehearsal with nothing at stake. Under
pressure they would each read as a different, worse problem.

### 2.1 The instance says `RUNNABLE` long before the restore is done

`gcloud sql instances describe` reported `state: RUNNABLE` roughly four minutes
in, while `gcloud sql operations list` still showed `CLONE / RUNNING` — and it
kept saying `RUNNABLE` for another twenty minutes.

**Wait on the operation.** An operator who trusts the instance state concludes
the restore is finished, connects, finds an incomplete database and starts
diagnosing a corrupt backup.

### 2.2 Configuration changes are rejected while the clone runs

Patching `--authorized-networks` during the clone fails. The first attempt here
sent the error to `/dev/null`, so the patch appeared to succeed and the failure
surfaced later as a connection timeout — which reads like a network or firewall
problem, not a sequencing one. **Do not suppress stderr on these commands.**

### 2.3 Deletion protection is inherited by the clone

`gcloud sql instances delete` refuses:

> The instance is protected. Please disable the deletion protection and try again.

Production carries `deletionProtectionEnabled: true`
([infra-prod-hardening.md](infra-prod-hardening.md)) and the clone inherits it.
This is the safety control working — but it means cleanup is **two** commands,
and a rehearsal that forgets the first one leaves a billable instance running.

### 2.4 `postgres` cannot read the application's tables — and the symptom is "empty"

The most dangerous of the five. Cloud SQL's `postgres` role is **not** a true
superuser, and every application table is owned by `myweli_app`. Connected as
`postgres`:

```
migrations applied : ERROR:  permission denied for table schema_migrations
public tables      : 0
```

`information_schema.tables` only lists what the current role may see, so a
perfectly good restore reports **zero tables**. That is indistinguishable from a
failed restore, and it points the investigation at the backup instead of at the
connection. Connect as `myweli_app`; the same database then reports 31
migrations and 39 tables.

### 2.5 `--authorized-networks` needs IPv4

`curl ifconfig.me` returns an IPv6 address on this network, and the flag rejects
it (`Must be specified in CIDR notation`). `curl -4` is the fix. Trivial, but it
is the sort of thing that costs five minutes at 3am.

## 3. The rehearsal — 2026-08-16

Cloned production to a standalone instance, verified, deleted. **Production and
staging were never touched**; a PITR clone reads from backups and transaction
logs, and the target was attached to no service.

| | |
|---|---|
| Source | `myweli-db` (production), `db-f1-micro`, `europe-west9` |
| Restore point | `2026-08-16T19:06:55Z` |
| Clone duration | **26 min 14 s** (19:22:03 → 19:48:18) |
| Instance disk / database size | 105 MB / **10 MB** |
| Result | **31 migrations**, **39 public tables**, latest `0031_booking_window` applied `2026-08-05 19:36:36+00` — the Cloud SQL cutover |

Row counts at the restore point, i.e. what production actually holds:

| table | rows |
|---|---|
| `users` | **5** |
| `providers`, `provider_users`, `appointments`, `reviews`, `device_tokens` | 0 |
| `countries`, `cities` | 1, 1 |

**26 minutes is a floor, not an estimate.** That was 10 MB of data. Restore time
on `db-f1-micro` grows with the database and with the volume of transaction log
to replay from the last base backup, so a restore to a point late in the day
costs more than one taken just after the 02:00 backup. Anyone quoting an RTO
should quote it as *"at least half an hour, measured empty"*.

## 4. What this rehearsal did NOT establish

Stated because the reason for running it was partly wrong.

**It cannot validate the 60s `statement_timeout`.**
[infra-staging.md](infra-staging.md) §3.2 pairs the restore with *"timing the
boot as a gate"*, on the assumption that a production copy carries production
volume. It does not: production holds 5 user rows and no salons, so a restored
copy boots exactly as fast as staging already does.
[backend-migration-timeouts.md](backend-migration-timeouts.md) §8 q3 stays open,
and the thing that would close it is **synthetic volume generated in staging**,
not a copy of an empty production.

**It did not exercise a promotion.** The clone was inspected and deleted. Nobody
has repointed a running service at a restored instance, and §1 deliberately
leaves that unscripted.

**It says nothing about a restore under load.** Production was idle.

## 5. The scrub question is real, and smaller than it looked

[infra-staging.md](infra-staging.md) §2.1 carries an OPEN box: a production copy
behind staging's `ingress: all` — which echoes OTP dev-codes, because
`ENV=staging` is `guardsOn` but not `isProd` — is readable by anyone who guesses
the hostname.

The rehearsal sharpens it in both directions. Production holds **5 user rows**,
so the exposure today is five identities rather than a customer base — but it is
**not zero**, and those rows carry phone numbers and emails. A restore into
staging would have put them behind the open ingress.

Restoring into a **standalone instance attached to nothing** is one of §2.1's
three candidate resolutions, and this rehearsal is the evidence that it is
sufficient for the *verification* purpose: you can prove the backup restores
without exposing anything at all. §2.1's box stays open only for the other
purpose — a prod-volume copy attached to the running staging service — which,
per §4, is not currently worth doing.

## 6. Cost

One `db-f1-micro` for ~40 minutes: a few cents. The rehearsal is cheap enough to
repeat quarterly, and §2's five traps are the argument for doing so — they are
the kind of knowledge that goes stale silently when the platform changes.

## 7. Open questions

1. **No promotion has been rehearsed** (§4). The runbook's hardest step —
   repointing `DATABASE_URL` and accepting the write-loss window — is still
   theory.
2. **RTO is unmeasured against real data** (§3). 26 minutes is the empty floor;
   nobody knows the slope.
3. **Nothing verifies backups routinely.** Five consecutive automated backups
   report `SUCCESSFUL`, and until today that was the only evidence any of them
   were restorable. A scheduled quarterly rehearsal — or a check that at least
   asserts the backup list is fresh — would keep this true rather than
   historical.
