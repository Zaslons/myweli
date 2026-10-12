# Refresh-token rotation — atomic, with a 30-second grace

| | |
|---|---|
| **Status** | Approved (owner decision 2026-10-12: « atomic + 30 s grace ») — **built 2026-10-12** (#567, §10) — **in production since 2026-10-12 14:10 UTC** with the owner's go: revision `myweli-api-00036-pr2`, image `b15c29b` (`sha256:df5a1213…`), 100 % of traffic; verified by a bogus-token probe of all three refresh routes (each `401 refresh_invalid`, not a 500 — the new step-2 SELECT reads `rotated_at`, so the column exists) and their `INFO: auth_refresh principal=… outcome=invalid` lines in the revision's log |
| **Owner** | backend |
| **Last updated** | 2026-10-12 |
| **PRD ref / phase** | Auth & session — BACKEND.md §3.1, threat T4 / T17 · V1 |
| **ROADMAP entry** | [2026-10-12-refresh-rotation-atomic](../roadmap/entries/2026-10-12-refresh-rotation-atomic.md) |
| **Skills checked** | myweli-backend-guardrails · myweli-verification-guardrails |

## 1. Goal & scope

Make the exchange of a refresh token **atomic** on all three principals —
consumer (`POST /auth/refresh`), provider (`POST /auth/provider/refresh`),
admin (`POST /admin/auth/refresh`) — and replace today's *accidental*
tolerance of concurrent use with a **deliberate, bounded, logged** one.

In scope: the three Postgres repositories and their in-memory twins, one
migration, the refresh routes' outcome log, tests, BACKEND.md §3.1 + T4, the
three endpoints' descriptions in `openapi.yaml`. Out of scope (§9): token
expiry and pruning, ban → revoke, a logout endpoint, the web BFF.

## 2. What is wrong today (verified 2026-10-12)

- **Check-then-act across two pool operations.** Consumer and provider
  `refresh()` read `rotated` with a lock-free `SELECT` outside any transaction,
  then in a separate `runTx` run `UPDATE … SET rotated = true WHERE token_hash
  = @h` — no `AND rotated = false`, row count ignored — and insert a child in
  the family (`postgres_auth_repository.dart:294-329`,
  `postgres_provider_auth_repository.dart:457-492`).
- **Admin has no transaction at all**: SELECT, UPDATE and the child INSERT are
  three independent statements (`postgres_admin_auth_repository.dart:183-232`);
  a failure between UPDATE and INSERT leaves the session unrecoverable.
- So two concurrent exchanges of one token **both succeed** and fork the
  family. Production shows it: 2026-10-07 and 2026-10-10, two consumer
  `/auth/refresh` 200s 6 ms and 71 ms apart, each right after
  `/appointments` + `/me/favorites` 401'd together on a cold start.
- A *sequential* second use (arriving after the first committed) is revoked as
  theft — which signs out legitimate clients that race slightly more slowly:
  the web BFF has no single flight (the Pro dashboard fires ≥ 3 authed calls on
  load), and a refresh whose response was lost leaves the client holding a
  rotated token.
- Nothing logs a refresh outcome: a revocation is invisible in production.

## 3. Decision

**Atomic claim + a 30-second grace.** Exactly one exchange *rotates* a token.
A presentation of an already-rotated token **within 30 s of its rotation** is
a concurrent or retried legitimate use: it is answered with a new pair in the
**same family** (a sibling) and nothing is revoked. After 30 s it is reuse:
the family is revoked (`refresh_reused`), as BACKEND.md §3.1 requires.

**Trade-off, stated.** Today's race already accepts concurrent duplicates for
≈ 100 ms by accident; this makes the window explicit, 30 s, server-clocked and
logged. A thief who replays a stolen token within 30 s of the owner's own
refresh now gets a sibling instead of triggering revocation — the standard
"reuse interval" trade (Auth0, Okta). Reuse after the window is detected
exactly as before, and every grace acceptance is logged. In return no client
race — web, released apps, a lost response retried within 30 s — signs a
user out, and the server can ship without waiting for app releases.

## 4. Data model — migration `0037_refresh_rotated_at`

`ALTER TABLE <t> ADD COLUMN IF NOT EXISTS rotated_at timestamptz` on
`refresh_tokens`, `provider_refresh_tokens`, `admin_refresh_tokens`. Nullable,
no backfill: a row rotated before the migration has `rotated_at IS NULL` and is
treated as rotated long ago (outside the grace). Additive and reversible
(`DROP COLUMN`) — no `rollback-unsafe` declaration needed. No unique index on
the family: siblings within the grace are allowed by design.

## 5. The exchange (one transaction, server clock)

```
BEGIN
  UPDATE <t> SET rotated = true, rotated_at = now()
   WHERE token_hash = @h AND rotated = false
   RETURNING <owner>, family_id [, role]
  → 1 row : issue the child in the same tx           → ok, outcome rotated
  → 0 rows: SELECT <owner>, family_id [, role], rotated_at
              FROM <t> WHERE token_hash = @h FOR UPDATE
     · no row                                         → refresh_invalid
     · rotated_at >= now() - interval '30 seconds'    → sibling, outcome grace
     · otherwise (older, or NULL)                     → DELETE the family,
                                                         REPEATED until it
                                                         deletes 0 rows,
                                                         refresh_reused
COMMIT
```

**Why the DELETE repeats** (added by the review, §10). `FOR UPDATE` makes a
grace exchange wait for a revoke that already holds its row. The other order —
an exchange (grace or plain rotation) holds a family row and is inserting its
child when the revoke's `DELETE` starts — makes the `DELETE` wait on that row,
and its snapshot predates the child, so one `DELETE` leaves the child alive.
Under READ COMMITTED each statement takes a fresh snapshot: the next pass sees
the child. Without contention it is two statements.

Under READ COMMITTED a concurrent second `UPDATE` blocks on the winner's row
lock, re-evaluates `rotated = false` after the commit and matches nothing, so
exactly one caller gets `rotated`. The grace comparison uses the database
clock on both sides (instances never compare their own clocks). The grace is
one constant (`kRefreshReuseGrace = 30 s`) shared by the three Postgres
repositories and passed into the SQL as a parameter; the in-memory twins use
the same constant with an injectable clock.

**Result shape.** `RefreshResult` gains `RefreshOutcome outcome`
(`rotated | grace | reused | invalid`); `ok` and `error` keep their meaning, so
the routes' responses — and the contract — do not change.

## 6. Observability

Each refresh route prints one structured line, the house style
(`print('INFO: auth_refresh …')`): `principal=consumer|provider|admin
outcome=rotated|grace|reused|invalid request_id=<id>`. Never the token, its
hash or any PII. `reused` is the security event worth an alert later; `grace`
counts how often clients race.

## 7. Security / threat model

T4 (and T17's admin refresh): rotation is atomic on every principal; reuse
detection keeps revoking the family outside a 30 s server-clocked grace;
within it a sibling is issued and logged. Residuals unchanged and restated:
revocation does not kill an access JWT already issued (≤ 15 min); refresh
tokens have no absolute expiry (§9).

## 8. Tests

Postgres-backed, in the files that already own each table
(`test/db/postgres_repositories_test.dart` for consumer + provider — the file
TRUNCATEs those tables, so a separate file would race it —
`test/db/postgres_admin_auth_test.dart` for admin):

- **Atomic:** N = 8 concurrent exchanges of one token → all `ok`, **exactly
  one** `outcome == rotated`, the rest `grace`, every child in the token's
  family, the parent rotated once. Repeated to make an interleaving likely.
- **Grace boundary:** after a rotation, set `rotated_at = now() - 31 s` → the
  next exchange is `refresh_reused` and the family is gone (its children no
  longer exchange); at `now() - 29 s` → `grace`, family intact.
- **Pre-migration rows:** `rotated = true, rotated_at = NULL` → `reused`.
- **Unknown token** → `refresh_invalid`.
- **The grace runs from the first rotation:** a grace exchange leaves the
  parent's `rotated_at` exactly as it was (added by the review, §10).
- **A revoke arriving second still empties the family:** an exchange's child
  insert is held (a family-scoped trigger waiting on an advisory lock the test
  owns) while the reuse `DELETE` waits on the exchange's row; once released,
  the family is empty and the minted token is `refresh_invalid` — for a grace
  sibling and for a plain rotation (added by the review, §10).
- **Admin:** the above, plus the exchange is one transaction.
- In-memory twins: the same table of outcomes with an injected clock.
- Route tests keep their current 401 codes; one route test per principal
  asserts the outcome log line (no token in it).

Every new guard watched red (drop `AND rotated = false`; widen/shrink the
grace; skip the family delete; take admin out of the transaction; after the
review: a grace exchange that moves `rotated_at`; a family `DELETE` run once).

## 9. Rollout & follow-ups

- No ordering constraint: the grace covers released apps and the web.
  Production deploy only with the owner's go. After deploy, watch the
  `auth_refresh` lines: `grace` on cold starts, no unexpected `reused`.
- **Follow-ups (separate slices):** absolute refresh-token expiry + pruning of
  rotated rows (they accumulate forever today); a ban revokes the user's
  families and refresh checks `users.status` / `admins.status`; a logout
  endpoint that revokes the family (BACKEND.md §3.1 promises one); an alert on
  `outcome=reused`.

## 10. As built (2026-10-12)

What the build added to — or learned about — the plan above. None of it
changes §3–§6, except the review's repeated family `DELETE` in §5 (last
bullet).

- **One exchange, not three copies.** §5 lives once in
  `backend/lib/src/db/refresh_exchange.dart`; each Postgres repository wraps it
  in its own `runTx` and passes a child insert that writes through that same
  transaction (admin's `_issueInFamily` now takes the session — the pool for a
  login, the transaction for a refresh). The grace goes into the SQL as an
  `interval` parameter from `kRefreshReuseGrace`
  (`backend/lib/src/auth/auth_repository.dart`, beside `RefreshOutcome`). The
  in-memory twins take `clock:` — the `DateTime Function()? clock` pattern of
  `InMemoryLoginThrottle` / `InMemoryRateLimiter` — and share one boundary
  helper, inclusive like the SQL's `>=`.
- **The log line** is `logRefreshOutcome`
  (`backend/lib/src/observability/refresh_log.dart`); the request id comes from
  `requestIdOf(context)`, which reads the `RequestId` the observability
  middleware provides and **never throws** (`none` when absent): the line is
  printed after the rotation committed, and a throw there would turn a success
  into a 500 and cost the client its new pair.
- **Existing reuse tests now step past the grace** — a fake clock in the
  in-memory ones, `rotated_at = now() - 31 s` in the Postgres ones. Every
  asserted code is unchanged; an immediate replay is now *grace* by design.
- **Spec gap closed: the funnel smoke.** `tool/smoke/funnel_smoke_test.dart`
  A33 replayed at once and expected 401 — it would have reddened CI. It now
  expects 200 (a sibling) inside the grace, waits 32 s on real time, then
  401 `refresh_reused` with both descendants dead. The harness is black-box
  against a possibly deployed server, so it cannot backdate `rotated_at`.
- **Admin is proved one transaction from both directions**, by fault
  injection scoped to one admin id: a refused child INSERT leaves the token
  unrotated (catches "no transaction"); a refused COMMIT leaves no child behind
  (catches "child written outside the transaction").
- **Residuals found while building (analysis, not measured):** (1) a reuse
  revoke and a *concurrent* rotation **or grace sibling** of another token of
  the same family can interleave so that the child commits after the
  `DELETE`'s snapshot and survives the revoke — **closed by the review, see
  below**; (2) two *different* tokens of one family, both past the grace
  and presented at the same instant, each hold their own row lock
  (`FOR UPDATE`) and then need the other's in the family `DELETE` — Postgres
  aborts one as a deadlock (that caller gets a 500; the other revokes the
  family). It needs two parties racing to the millisecond; closing it means a
  per-family lock taken before the claim — a follow-up, not this slice.
- **Review (2026-10-12), three findings, all fixed.**
  - *Residual (1) was wider than written, and real.* The step-2 comment and
    two test titles said `FOR UPDATE` keeps a sibling out of a family being
    revoked; that holds only when the revoke locks the row first. Reproduced
    with two `psql` sessions running the exchange's SQL: a grace exchange
    locked its row first, the reuse `DELETE` started while it was inserting,
    waited, and reported `DELETE 3` — the sibling survived, live and
    unrotated, in a family whose caller got `refresh_reused`. The grace made
    it wider: every token rotated in the last 30 s can mint. **Fix:** step 4
    repeats the `DELETE` until it deletes 0 rows (§5). It closes residual (1)
    for plain rotations too. An exchange that arrives after a row is deleted
    still blocks on it and then finds nothing. The comment and titles now say
    what `FOR UPDATE` covers: a revoke that already holds the row. Pinned by
    the "revoke arriving second" tests (§8), ordered by locks, not sleeps.
  - *The grace must run from the first rotation.* No Postgres test checked
    that a grace exchange leaves `rotated_at` alone. If it moved, a thief
    replaying every 29 s would keep the grace open forever. The 29 s → 31 s
    tests now assert it is unchanged (§8).
  - *T17 claimed a ban ends sessions fast.* It does not: `setStatus` only
    writes `users.status`, the ban check is in `_loginAs` (login paths), and
    the exchange never reads `users`. BACKEND.md T17 now says a ban blocks new
    logins only, until the ban → revoke follow-up (§9).
