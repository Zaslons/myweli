# 60s, measured — and the probe that binds before it

| | |
|---|---|
| **Module** | `backend/lib/src/db/migrations.dart`, `backend/tool/volume_probe.dart` |
| **Status** | **Measured 2026-08-16; dedicated-core tier measured and priced 2026-08-17 (§7).** Closes [backend-migration-timeouts.md](backend-migration-timeouts.md) §8 q3 and [infra-staging.md](infra-staging.md) §3.2's timing gate. |
| **Owner** | Sadreddine Daher |
| **Skills checked** | myweli-backend-guardrails |
| **Related** | [backend-migration-timeouts.md](backend-migration-timeouts.md) · [infra-dr-restore.md](infra-dr-restore.md) §4 · [infra-staging.md](infra-staging.md) §3.2 |

`kSchemaStatementTimeout = 60s` shipped unmeasured. §3.2 expected a production
PITR restore to supply the volume; the restore ran and production held **5 user
rows** ([infra-dr-restore.md](infra-dr-restore.md) §4), so it answered nothing.
This is the measurement, against synthetic volume on a throwaway instance of the
**same tier as production**.

**The headline is not the one that was expected.** 60s is a fine default, and it
is also almost irrelevant — because on `db-f1-micro` the statement that matters
blows through the **300s `startupProbe` budget** not long after it blows through
60s, and no timeout setting can fix that.

## 1. The numbers

`db-f1-micro`, `europe-west9`, PostgreSQL 16.14, real schema from
`runMigrations`, `appointments` rows generated server-side
(`backend/tool/volume_probe.dart`).

| rows | `CREATE INDEX` | `CREATE UNIQUE INDEX … WHERE` | **`EXCLUDE USING gist`** | `ADD COLUMN NOT NULL DEFAULT now()` |
|---|---|---|---|---|
| 25 000 | 438 ms | 710 ms | **3.1 s** | 362 ms |
| 50 000 | 919 ms | 678 ms | **6.2 s** | 356 ms |
| 100 000 | 1.1 s | 954 ms | **14.3 s** | 358 ms |
| 150 000 | — | — | **264 s** | — |
| 200 000 | — | — | **320 s / 339 s** (two runs) | — |

Every shape is one `migrations.dart` already uses. The GiST exclusion appears
**twice** — `appointments_no_overlap` (0009) and `appointments_artist_no_overlap`
(0026) — and it is the only one that matters.

## 2. Four findings

### 2.1 60s is crossed between 100k and 150k appointments

At 100 000 rows the GiST build takes 14.3s — comfortable, 4× headroom. At
150 000 it takes **264s**. The crossing is somewhere in between, and the exact
point is not worth chasing because of §2.2.

Plain btree and partial-unique index builds are **not** the problem: about a
second at 100 000 rows, and they scale sanely.

### 2.2 It is a cliff, not a slope

1.5× the data cost **18× the time**. Anything that reads the 25k–100k rows as a
trend and extrapolates gets the wrong answer by an order of magnitude — as this
investigation did, predicting ~32s for 200 000 and measuring 339s.

### 2.3 It is not `maintenance_work_mem`

The obvious explanation, tested and **refuted**. At 150 000 rows:

| `maintenance_work_mem` | GiST build |
|---|---|
| 64 MB (default) | 264 s |
| 256 MB | 230 s |
| 512 MB | 259 s |

Within noise. Raising it is not a mitigation, and a migration that sets it is
buying nothing.

### 2.4 It is the machine: shared-core CPU throttling

CPU utilisation during fourteen consecutive minutes of index building:

```
23:41  18.3%   23:45  18.4%   23:49  19.2%   23:53  18.7%
23:42  18.2%   23:46  18.7%   23:50  18.1%   23:54  18.8%
23:43  18.8%   23:47  18.1%   23:51  18.1%
23:44  18.9%   23:48  18.9%   23:52  18.3%
```

A dead-flat ceiling at ~18–19% across the whole build. `db-f1-micro` is a
**shared-core, burstable** machine; sustained CPU work is capped once burst
credit is gone. The build is not using more CPU because it cannot. That is why
memory made no difference, and it is why **the tier — not the timeout — is the
binding constraint**.

## 3. The consequence that changes the guidance

`service.yaml` and `service-staging.yaml` both set `startupProbe:
periodSeconds: 10 × failureThreshold: 30` = **300s**, and migrations run
**before the port binds**. So the real ceiling on any single migration is not
`statement_timeout`, it is the probe.

| appointments | GiST build | vs `statement_timeout` 60s | vs `startupProbe` 300s |
|---|---|---|---|
| 100 000 | 14.3 s | fits | fits |
| 150 000 | 264 s | **aborted at 60s** | fits, with ~36s to spare for the rest of boot |
| 200 000 | 320–339 s | **aborted at 60s** | **exceeds — the revision can never become ready** |

Past roughly 200 000 appointments, raising `statement_timeout` does not make
such a migration deployable. It moves the failure from *"statement aborted at
60s, deploy red in a minute"* to *"revision never became ready, deploy red after
five"* — slower, and much harder to read.

**So the recommendation is not a bigger number.**

## 4. What to do

**Keep `kSchemaStatementTimeout = 60s`.** It is a good runaway guard, it fails in
the safe direction ([infra-rollback.md](infra-rollback.md) §6), and raising it
would buy nothing for the one statement that needs it (§3).

**An index-building migration on a large table must use the §3.3 escape hatch —
and must be checked against 300s, not 60s.** The escape hatch raises
`statement_timeout` for one transaction; it does not raise the probe budget.
Before adding one, run `volume_probe.dart` against the current row count.

**Past ~150 000 appointments, do not build a GiST index at boot at all.** The
options, in order of preference:

- **bump the tier.** Every number here is a shared-core artefact; this is the
  actual fix and it is a one-line change to the instance;
- **build it outside the migration path** — a maintenance operation against the
  live database, then a migration that only records the id. For a *plain* index,
  `CREATE INDEX CONCURRENTLY` does this without an `ACCESS EXCLUSIVE` lock, at
  the cost of not running inside a transaction. **Note it does not solve the
  exclusion constraint**: `ADD CONSTRAINT … USING INDEX` accepts only
  `UNIQUE`/`PRIMARY KEY`, never `EXCLUDE`;
- **do not add the constraint.** The overlap guard is worth its cost today
  because the table is empty. On a large table it is a design decision, not a
  free correctness win.

**`ADD COLUMN … NOT NULL DEFAULT now()` is safe at any size.** Constant ~358 ms
at every tier — PostgreSQL's metadata-only path, confirmed rather than assumed.
Migration 0009 does exactly this and would be fine on a table of any size.

## 5. How to re-run it

```bash
gcloud sql instances create <name> --database-version=POSTGRES_16 \
  --edition=ENTERPRISE --tier=db-f1-micro --region=europe-west9 --no-backup
# … create database `myweli`, set a password, authorise your IPv4 …
DATABASE_URL=… dart run tool/volume_probe.dart 25000 50000 100000
```

**Not against staging.** The probe leaves hundreds of thousands of appointments
behind, and staging runs `minScale: 0`, so every cold start would then pay to
read them. A throwaway instance costs about a cent and takes ~7 minutes to
provision.

Two traps met while doing it, both worth knowing:

- the `postgres` Dart driver cancels a statement after a **5-minute** default
  `queryTimeout`, which surfaces as `57014 canceling statement due to user
  request` and looks like a server-side timeout. Past ~150 000 rows the probe
  must be driven from `psql`, or the driver caps the measurement;
- `TRUNCATE appointments` fails on a foreign key from `disputes`. A run that
  ignores the error silently re-measures the previous tier — one of the numbers
  above was caught that way, reporting "150 000" for a table that still held
  200 000. **Always assert the row count before timing.**

## 6. Open questions

1. **The knee is located to within 100k–150k, not pinned.** Enough to act on;
   pinning it exactly costs another ~20 minutes of f1-micro time and changes no
   recommendation.
2. **Only `appointments` was measured.** It is the table that grows fastest and
   carries every expensive shape, but `reviews` and `salon_clients` will follow
   it eventually.
3. ~~**The tier bump is unpriced here.**~~ **Priced — §7.**


---

## 7. What the tier bump costs, and why it is not needed yet

§4 recommends a tier bump without a number. Here it is, from the **live Cloud
Billing catalog** for `europe-west9` (Zonal, Enterprise edition, PostgreSQL),
730 h/month. The method is validated against a previously audited figure:
`0.0122 × 730 = $8.91`, exactly the `db-f1-micro` line in
[infra-staging.md](infra-staging.md) §5.

| SKU (Zonal, Enterprise, Paris) | rate | per month |
|---|---|---|
| Micro instance (`db-f1-micro`) | $0.0122/h | **$8.91** |
| Small instance (`db-g1-small`) | $0.0406/h | **$29.64** |
| Dedicated vCPU | $0.0479/h | **$34.97** each |
| RAM | $0.0081/GiB/h | **$5.91** per GiB |
| Standard storage | $0.1972/GiB/mo | $1.97 for 10 GiB |

### 7.1 The options, per instance

| tier | cores | RAM | compute | + storage | vs today | fixes the cliff? |
|---|---|---|---|---|---|---|
| `db-f1-micro` — today | **shared** | 0.6 GiB | $8.91 | $10.88 | — | — |
| `db-g1-small` | **shared** | 1.7 GiB | $29.64 | $31.61 | **+$20.73** | **NO** |
| `db-custom-1-3840` | **1 dedicated** | 3.75 GiB | $57.14 | $59.11 | **+$48.23** | **yes — measured, §7.3** |
| `db-custom-2-7680` | 2 dedicated | 7.5 GiB | $114.28 | $116.25 | +$105.38 | no better than 1 vCPU here |

**`db-g1-small` is a trap, and it is the obvious choice.** It reads as "the next
tier up", costs 2.8× the current bill, and **does not fix anything measured here**
— it is still a *shared-core* machine, so the throttling that produced the cliff
(§2.4) is unchanged. What it triples is RAM, which §2.3 measured to be
irrelevant. Paying +$20.73/month for it would buy nothing on this axis.

**Two vCPUs buy nothing either.** A GiST index build is single-threaded, so the
second core cannot shorten the statement that matters. It would help concurrent
query load — a different problem.

So the answer is `db-custom-1-3840`, the cheapest dedicated-core tier Cloud SQL
offers (custom instances have a 3.75 GiB floor), at **+$48.23/month per
instance**:

- **production only — +$579/year.** The production database line goes from
  ~$11 to ~$59/month: a **5.4×** increase, and the largest single infra change
  proposed so far.
- **both instances — +$1,158/year.** Staging's whole budget is $13–17/month
  ([infra-staging.md](infra-staging.md) §5), so this roughly **quadruples** the
  environment deliberately designed to be cheap.

### 7.2 It is not needed yet, and the reason is not "we can't afford it"

The cliff bites between **100 000 and 150 000 appointments** (§2.1). Production
holds **zero** ([infra-dr-restore.md](infra-dr-restore.md) §3). There is no
migration urgency at any price.

**But a different constraint probably binds first, and it is live today.** Both
instances run the `db-f1-micro` default of **25** `max_connections` — verified,
neither carries any `databaseFlags` — leaving ~22 after
`superuser_reserved_connections`. `database.dart` budgets
`kMaxConnectionsPerInstance` 4 × `maxScale` 4 = **16**, comfortable in steady
state. But `maxScale` is **per revision**, so a rollout running the draining old
revision beside the new one can transiently reach eight instances = **32**, over
the ceiling.

That is not a future problem, it is the current configuration at full scale, and
raising `max_connections` on a `db-f1-micro` was already rejected on evidence
(`database.dart`: a restart on a ZONAL instance with no replica, against an app
with no connection retry, and ~800 MB of backends on a 0.6 GB machine).

**So the tier bump's first payoff is connection headroom, not migration speed.**
Migration speed is the second-order benefit, arriving at 100k appointments.

### 7.3 Measured on a dedicated core — and it refuted half the projection

This section used to argue from a laptop and call the speedup 3.6–5.6×. A
throwaway `db-custom-1-3840` was then measured directly (**$0.014**, 11 minutes),
and the conclusion survived while the reasoning did not.

| `appointments` | `db-f1-micro` GiST | `db-custom-1-3840` GiST | |
|---|---|---|---|
| 25 000 | 3.1 s | **3.6 s** | dedicated core *slower* |
| 50 000 | 6.2 s | **8.2 s** | slower |
| 100 000 | 14.3 s | **16.4 s** | slower |
| 150 000 | **264 s** | **26.2 s** | **10× faster** |

**Below ~100k the dedicated core is not faster. It is marginally slower.** The
projection assumed the small-tier `f1-micro` numbers were already throttled;
they were not — those builds finish inside the burst allowance, so the two
machines are comparable, and a shared core with burst credit available is a
perfectly good machine.

**What the money buys is the absence of the cliff, not speed.** The dedicated
core scales smoothly — 3.6 → 8.2 → 16.4 → 26.2 s, close to linear — while
`f1-micro` goes 14.3 → **264** the moment sustained work outlasts its credit.
That is a 10× gap at 150k and it widens above.

Note `maintenance_work_mem` is **64 MB on both tiers**, so the dedicated core
removes the cliff *without any extra memory* — independent confirmation of §2.3.
What differs is `shared_buffers` (128 MB → 1222 MB) and, decisively, an
unthrottled core.

**60s at 150k becomes comfortable**: 26.2 s, with 2.3× headroom. Extrapolating
the near-linear curve puts the 60s crossing near ~350k rows — but §2.2 is the
standing warning against exactly that arithmetic, so treat it as indicative and
re-run the probe before relying on it.

### 7.4 The finding that reframes the whole purchase

`db-custom-1-3840` reports **`max_connections=100`**, against `db-f1-micro`'s 25.

§7.2 argued the connection ceiling binds before the migration cliff. A tier bump
**quadruples** it, taking the rollout-overlap worst case (8 instances × 4 = 32)
from *over* the ~22 usable to comfortably inside ~97. That is the constraint
which is real today, and it is fixed as a side effect.

So the purchase is **headroom, in two independent forms** — 4× the connections
now, and no migration cliff later — and in neither case is it *speed*. Anyone
justifying it as "the database will be faster" will be disappointed at current
volumes, and measurably so.

### 7.5 Recommendation, and the tripwire that shipped

**Do not bump now.** At today's volumes a dedicated core is not faster (§7.3),
and the connection ceiling is a rollout-time transient rather than a steady-state
failure. Current `num_backends` on both instances: **2**.

**Skip `db-g1-small` when the time comes.** It is shared-core, so it fixes
neither thing the bump is for.

**One tripwire shipped, one deliberately not.**

`infra/gcp/85-db-capacity-alert.sh` creates an alert policy per instance on
`num_backends` **> 16 sustained for 10 minutes** — 16 being the documented budget
(`kMaxConnectionsPerInstance` 4 × `maxScale` 4), and ten minutes being long
enough that a draining rollout does not page anyone. Verified by resolving the
policy's own filter against live data rather than trusting `create`'s exit code:
both instances return real series, max 2, so the policy can fire.

**The `appointments` row-count tripwire is a manual gate, not an alert, and that
is the honest design.** Cloud Monitoring has no row-count metric, and the
available proxies do not work at this scale:

- `disk/bytes_used` is dominated by a ~90–105 MB baseline of system pages and
  WAL, while 50 000 appointments adds only ~25 MB of table and index. The signal
  sits inside the noise, and a threshold picked anyway would fire either
  constantly or far too late.
- A log-based metric would need the application to emit the count at boot. On
  production, `minScale: 1` means boot happens only on deploy, so the metric
  would be as stale as the last release — and a `COUNT(*)` in the boot path is a
  cost on the one code path recently hardened.

So the row count is checked **when it matters**, which is when someone is about
to add an index — exactly where BACKEND.md §2 already sends them:

```sql
SELECT count(*) FROM appointments;   -- past ~50 000? run tool/volume_probe.dart first
```

A gate at the point of decision beats an alert nobody can act on, and it is
better than an alert with a threshold chosen to make a graph look reassuring.
