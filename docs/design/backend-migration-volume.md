# 60s, measured — and the probe that binds before it

| | |
|---|---|
| **Module** | `backend/lib/src/db/migrations.dart`, `backend/tool/volume_probe.dart` |
| **Status** | **Measured 2026-08-16.** Closes [backend-migration-timeouts.md](backend-migration-timeouts.md) §8 q3 and [infra-staging.md](infra-staging.md) §3.2's timing gate. |
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
3. **The tier bump is unpriced here.** §4 recommends it without saying what it
   costs; that belongs with the launch budget, not with this measurement.
