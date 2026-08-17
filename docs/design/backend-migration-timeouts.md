# Migration timeouts — bounding the lock wait, and the one lock that must NOT be bounded

| | |
|---|---|
| **Module** | `backend/lib/src/db/migrations.dart` (schema setup, boot path) |
| **Status** | **Design → built.** Closes [infra-staging.md](infra-staging.md) §3.2's outstanding guard and [infra-rollback.md](infra-rollback.md) §11 q2. |
| **Owner** | Sadreddine Daher |
| **Skills checked** | myweli-backend-guardrails |
| **Related** | [infra-staging.md](infra-staging.md) §3.2 · [infra-rollback.md](infra-rollback.md) §6 · [BACKEND.md](../BACKEND.md) §2 |

[infra-staging.md](infra-staging.md) §3.2 has prescribed this since staging was
designed: *"`SET lock_timeout = '3s'` and `statement_timeout = '60s'` at the top
of each migration transaction — a migration that cannot get its lock fails the
deploy instead of hanging the service."* `runMigrations` sets neither.

Applying that literally to the whole schema-setup block would have **broken every
normal deploy**. §2 is why, and it is measured rather than argued.

## 1. The hazard this actually closes

Migrations run at boot, behind `pg_advisory_lock`, **before the port binds**. On
Cloud Run that happens while the **previous revision is still serving traffic** —
so the database has concurrent readers throughout.

A migration that does `ALTER TABLE appointments ADD COLUMN …` needs `ACCESS
EXCLUSIVE`. If any session holds a conflicting lock — a slow query, or an
`idle in transaction` connection from the old revision — the `ALTER` waits. And
a *pending* `ACCESS EXCLUSIVE` request **queues every subsequent reader behind
it**, because new `ACCESS SHARE` requests do not jump the lock queue.

That is the classic failure where one migration freezes a table that was
serving fine a second earlier. The migration is not slow; it is *blocked*, and
it takes the table down with it while it waits.

`lock_timeout` is the mitigation: **fail the migration fast rather than freeze
the table**. The revision then never becomes ready, the old one keeps serving,
and the deploy goes red — [infra-rollback.md](infra-rollback.md) §6's
"a failed deploy has already rolled itself back".

Today's 31 migrations are additive and the tables are small, so this has never
bitten. It is a guard for the deploy where it would.

## 2. The measurement that changed the design

Run against PostgreSQL 16 before writing any code, because the whole shape of
the change depends on the answer:

| # | Question | Result |
|---|---|---|
| Q1 | Does `lock_timeout` abort a **waiting `pg_advisory_lock()`**? | **YES** — `canceling statement due to lock timeout`, at 1s |
| Q2 | Does `statement_timeout` abort a waiting `pg_advisory_lock()`? | **YES** — `canceling statement due to statement timeout`, at 1s |
| Q3 | Does `lock_timeout` abort **DDL waiting on a table lock**? | **YES** — at 1s. This is the case §1 wants |
| Q4 | Does `SET LOCAL` take effect inside `pool.runTx` through the Dart driver? | **YES** — `SHOW` reports the set values inside the transaction |
| Q5 | Does `SET LOCAL` **leak** to later users of a pooled connection? | **NO** — six subsequent pooled queries and a later transaction all report `0` |

**Q1 and Q2 are the trap.** `withSchemaLock` acquires a *contended* advisory
lock: when several Cloud Run instances cold-start together, exactly one wins and
**the others are supposed to wait**. That waiting is not a fault — it is the
mutual exclusion working, and it is why the lock exists (`migrations.dart`
documents the two ways a lost race corrupts data).

So a `lock_timeout` or `statement_timeout` set on the *lock-acquiring session*
does not bound a pathology. It **puts a deadline on normal contention**: every
instance that loses the race dies once migrations take longer than the timeout,
and the deploy fails on a service that is behaving exactly as designed.

A naive reading of infra-staging.md §3.2 — "set these on the schema-setup
connection" — is therefore actively harmful, and it fails in the direction that
looks like a flaky deploy rather than a bug.

**Q5 is what makes the safe version possible.** The pool that runs migrations is
the same pool that serves requests. A plain `SET` would ride on a pooled
connection into application queries, so every request on that connection would
silently inherit a 60s `statement_timeout` and a 3s `lock_timeout`. `SET LOCAL`
is transaction-scoped and measurably does not survive the commit.

## 3. Design

**Bound the schema-setup transactions. Do not bound the advisory lock.**

```dart
const Duration kSchemaLockTimeout = Duration(seconds: 3);
const Duration kSchemaStatementTimeout = Duration(seconds: 60);

Future<void> applySchemaTimeouts(TxSession tx) async { … }   // SET LOCAL ×2
```

Called as the first thing inside **every** transaction in the schema-setup path.
There are exactly four: each migration in `runMigrations`, plus
`backfillCatalogueIfNeeded`, `seedLocalitiesIfEmpty` and
`backfillSalonMarketIfNeeded` — the backfills especially, since they are the
statements that touch every row and are the most likely to be both slow and
lock-blocked.

`seedProvidersIfEmpty` is **not** among them, and not by oversight: it opens no
transaction (it inserts row by row on the pool) and it throws unless `ENV == dev`,
so it never runs in staging or production at all.

A test enumerates every `runTx` call in the file and requires each to begin with
the helper, so a fifth transaction added later cannot be silently unguarded —
see §6, which records why the *first* version of that test could not have made
this promise.

`lock_timeout` (3s) is deliberately **much shorter** than `statement_timeout`
(60s). PostgreSQL's own guidance is that a `lock_timeout` at or above
`statement_timeout` is pointless: the statement timeout would fire first and the
lock timeout could never be the reported cause. Keeping them an order of
magnitude apart is what makes *"blocked"* and *"slow"* distinguishable in the
deploy log, which is the entire diagnostic value.

### 3.1 The advisory lock stays unbounded, and that is now a decision

Given Q1/Q2 it cannot take these settings without breaking parallel cold starts.
Two properties make leaving it unbounded acceptable:

- **Cloud Run already bounds it.** `startupProbe` is `periodSeconds: 10 ×
  failureThreshold: 30` = **300s** in both service files. An instance stuck
  waiting is killed by the probe; the revision never becomes ready; the old one
  keeps serving. Safe direction, if quiet.
- **This change makes the wait transitively bounded.** The reason a lock holder
  could previously hang forever was an unbounded blocked migration — precisely
  what §3 fixes. Once the holder can no longer wait indefinitely, neither can
  the waiter.

The residual is diagnostic, not safety: a waiter that is killed by the probe
says nothing about *why*. Recorded as an open question (§8), not fixed here,
because every fix for it is a new way to fail a healthy deploy.

### 3.2 The trade this makes, stated plainly

**A deploy that would previously have succeeded can now fail.** That is not a
side effect; it is the change. Before, an `ALTER` that waited 30s behind a slow
query eventually got its lock and the deploy went green — while for those 30
seconds every reader of that table was queued behind it. Now it fails at 3s and
the deploy goes red.

3s is deliberately short *because waiting is the dangerous state*, not because
waiting is rare. The performance budgets (BACKEND.md §4) put ordinary queries
far below that, so a normal deploy against ordinary traffic should never come
close; if one does, the honest reading is that something is holding a lock it
should not — an `idle in transaction` session, or a query with no bound — and
freezing a table to accommodate it is the worse outcome.

**The recovery is to redeploy**, and it costs a build. A `lock timeout` in the
deploy log names the situation precisely, which is the difference between
retrying blindly and knowing to go look for the session that was holding the
lock.

### 3.3 The escape hatch for a legitimately slow migration

A 60s `statement_timeout` will one day be too short — a backfill over a large
table, or a `CREATE INDEX`. Because the defaults are applied as `SET LOCAL`
*first* and migration statements run *after*, inside the same transaction, a
migration raises its own ceiling simply by making that its first statement:

```dart
(
  id: '00NN_big_backfill',
  statements: [
    "SET LOCAL statement_timeout = '10min'",   // this migration only
    'UPDATE … ',
  ],
),
```

Scoped to that transaction, visible in the diff, and needing no new mechanism.
Tested, so it stays true.

## 4. What is deliberately NOT changed

- **The advisory lock**, per §3.1.
- **`CREATE TABLE IF NOT EXISTS schema_migrations`** and the per-migration
  `SELECT 1 FROM schema_migrations`, which run outside any transaction. Both are
  trivial statements on a tiny table, taken while already holding the schema
  lock. Wrapping them would add a transaction per migration to buy nothing.
- **`seedProvidersIfEmpty`** — dev-only and transaction-free; see §3.
- **Application queries.** Giving the whole pool a `statement_timeout` is a
  defensible idea and a much larger decision — it changes the failure mode of
  every route. Out of scope; §8.

## 5. Security

No new surface: no endpoint, no input, no credential, no threat-model row. The
change is strictly a narrowing — statements that previously could wait forever
now cannot. The one thing to get right is that the narrowing does not escape
into request handling, which is Q5 and is pinned by a test.

## 6. Tests

**Behavioural, `@Tags(['postgres'])`, `DATABASE_URL`-gated** (the shape
`migration_concurrency_test.dart` already uses, on its own scratch database):

- a transaction using the helper reports the configured values via `SHOW`;
- **the values do not survive the commit** — the pooled connection is back to
  `0`, which is Q5 and the one that protects request handling;
- **a blocked `ALTER TABLE` fails fast instead of hanging.** A second connection
  holds a conflicting lock; the guarded statement raises inside `lock_timeout`
  rather than waiting for the holder. Watched hang → watched fail;
- the §3.3 escape hatch: a `SET LOCAL` in a migration's own statements overrides
  the default within its transaction.

**Structural, offline, always runs:**

- **every `runTx` in `migrations.dart` applies the timeouts.** A new backfill
  added later would otherwise be silently unguarded — the failure this repo
  keeps finding. The scan also asserts a plausible number of calls was found, so
  a refactor cannot make it pass by matching nothing.

  **This guard failed its own standard twice, and an adversarial review of this
  change caught both.** Recorded because the second one is the more instructive:

  1. It matched the literal spelling `runTx((tx) async {` and paired it with a
     floor of `>= 4` — today's exact count. That combination detects the pattern
     breaking *downward* only. A **new** transaction spelled any other way is
     not matched, the count stays at four, the floor still passes, and the
     unguarded transaction is never inspected. Demonstrated by appending
     `pool.runTx<void>((TxSession tx) async {` with no timeouts: format clean,
     analyzer clean, whole suite green. And that spelling is the repo's existing
     idiom — `postgres_providers_repository.dart` writes
     `_pool.runTx<List<String>?>((tx) async {` at six sites — so it is the form
     a value-returning schema-setup transaction would *naturally* take. Fixed by
     enumerating loosely (`\brunTx\s*[<(]`) and checking every match, which
     leaves the floor with only one job: noticing the scan collapse to zero.
  2. It read a **240-character window** after the brace and took the first
     non-comment line. A transaction whose opening comment ran longer than that
     had its entire window skipped and failed with *"does not begin with
     `applySchemaTimeouts`"* while the call sat 300 characters away — a guard
     whose failure text is false, on a pure comment edit. The cheapest way to
     get such a suite green again is to delete the comment, or the test. Fixed
     by scanning forward to the first real statement with no byte cap, handling
     `//` and `/* … */` alike;
- `kSchemaLockTimeout < kSchemaStatementTimeout`, per §3;
- both are comfortably inside the 300s `startupProbe` budget, read from the
  service files rather than restated, so a probe change cannot silently
  invalidate the arithmetic.

## 7. Rollout

Ships on a merge to `main`, which deploys staging automatically. Staging is the
right first exercise: `minScale: 0` means every request may cold-start, so the
migration path runs constantly there — the reason infra-staging.md wanted that
configuration.

Nothing to configure, no secret, no manifest change. Reverting is a code revert.

## 8. Open questions

1. **Nothing diagnoses a waiter killed by the probe** (§3.1). A bounded
   `pg_try_advisory_lock` poll with progress logging would say *"still waiting
   for another instance to finish migrating"* instead of dying silently at 300s.
   Deliberately not done here: it changes a load-bearing concurrency primitive,
   and every variant introduces a new way to fail a healthy deploy. Worth doing
   only with a measured boot-time budget in hand.
2. **Application queries have no `statement_timeout`** (§4). A runaway query on
   `db-f1-micro` consumes one of only ~22 available backends until it finishes.
   Separate decision, larger blast radius.
3. ~~**60s may be wrong in either direction.**~~ **Measured 2026-08-16** —
   [backend-migration-volume.md](backend-migration-volume.md). 60s **stays**,
   and the reason is not that it turned out to be generous.

   On `db-f1-micro`, an `EXCLUDE USING gist` build over `appointments` — a shape
   §1 names and this file's migrations use twice — takes **14.3s at 100k rows
   and 264s at 150k**. A cliff, not a slope, caused by **shared-core CPU
   throttling** (CPU pinned flat at 18–19% for fourteen minutes;
   `maintenance_work_mem` was tested at 64/256/512 MB and made no difference).

   Raising this constant would not make such a migration deployable: migrations
   run before the port binds, so the binding ceiling is the **300s
   `startupProbe`**, which the same statement exceeds past ~200k rows. A bigger
   timeout only converts *"aborted in a minute"* into *"revision never became
   ready after five"*. The fix at that size is a **tier bump**, or not building
   the index at boot — see backend-migration-volume.md §4.

   `ADD COLUMN … NOT NULL DEFAULT now()` was confirmed constant-time (~358 ms at
   every tier), so migration 0009's shape is safe at any size.
