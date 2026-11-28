# The test twins against Postgres — a survey of the 28 other stores

| | |
|---|---|
| **Module** | backend: every repository with an in-memory twin (`lib/src/**`) and a Postgres twin (`lib/src/db/postgres_*.dart`) |
| **Status** | **Answered 2026-11-24, « Approve as recommended »** (§6: decisions 219–223, batch 16); **merged** (#855, `adaae165`). Docs only: a survey, then each fix through its own short spec. B16.1's: [provider-category-column.md](provider-category-column.md). B16.4's (the auth group): [auth-store-twins.md](auth-store-twins.md), which probed this group's rows on both twins: B-P1-b is also a production behaviour (Postgres replaces a Pro account's link), B-P1-a sits beside a sign-up race that answers 500, and B-P2-b was closed by B16.3a. |
| **Owner** | the project owner: the answers, then each spec, build, merge and deploy, each on the owner's word |
| **Last updated** | 2026-11-24 |
| **PRD ref / phase** | none: test fidelity, and three production defects it turned up · V1 |
| **ROADMAP entry** | [2026-11-24-twin-fidelity-survey.md](../roadmap/entries/2026-11-24-twin-fidelity-survey.md) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails · myweli-verification-guardrails · [BACKEND.md](../BACKEND.md) §1, §5 |
| **Related** | [appointment-twin-update.md](appointment-twin-update.md) (the bookings store, fixed in B15.1, and the method used here) |

---

## 1. Goal, scope and method

**The defect class.** Service and handler tests run against in-memory twins of the Postgres repositories. A twin that behaves differently from Postgres, in a way a caller can see, lets a test pass for code that production would break. The bookings store had it (B15.1, merged 2026-11-24). This survey looks for the same class in the **28 other stores**.

**Four kinds of difference were looked for:**
- **F1, writes:** a twin keeps a key or value Postgres drops, ignores or rejects (constraints, casts, foreign keys, cascades), or the reverse;
- **F2, aliasing:** a twin stores the caller's object, or hands out its own, so editing what was passed or returned changes the store;
- **F3, read shape:** keys or types that differ between the two reads;
- **F4, semantics:** filters, order, limits, conflicts, clocks, null-versus-throw.

**Method:**
1. **Four independent readers,** each with a share of the 28 pairs. Each was told to cite `file:line` on both sides, name a concrete input and both answers, search for the production callers, rate the severity, and mark anything unconfirmed. They were read-only.
2. **Eight differences proven by probe** (§3.1): one throwaway test made the same calls on both twins, against a disposable local Postgres 16 database dropped afterwards. Each probe row carries a **control**, a value both twins must agree on, which they did. That shows the write happened, so the difference is real.
3. **The three production defects** (§2) were also read end to end in the code before being written down.

**Not covered:**
- concurrency and transactions (two requests at once);
- the Postgres-only behaviour no twin models on purpose: the purge's cascades, proven on real Postgres in `postgres_salon_purge_test.dart`;
- the bookings store (done in B15.1).

**What « read, not probed » means below:** one reader cited both sides. It is likely right, but it is not an observation.

---

## 2. Three production defects — Postgres itself is wrong

These are not test gaps. In each, the twin does what the code means, and Postgres does not.

### 2.1 A salon that changes category stays listed under the old one (proven)

- **Where the category lives:** a salon's category is in two places, the `data` document and a `category` column. The discovery filter `GET /providers?category=` reads the column (`postgres_providers_repository.dart:39-41`).
- **What writes it:** only `createSalon` (`:701-709`). `updateProfile` syncs name, description, address and commune into their columns (`:369`), and not category.
- **It is reachable:** `category` is one of the profile fields a salon can edit (`provider_catalog_service.dart:204`, « the listing category »).
- **Probe:** `updateProfile('provider3', {'category': 'nails'})` on a `barber` salon, then the filter. The document reads `nails` on both twins, which is the control.

  | | In memory | Postgres |
  |---|---|---|
  | listed under `nails` | yes | **no** |
  | listed under `barber` | no | **yes** |

- **For users:** in the apps and on the website, filtering discovery by category hides that salon under its new category and shows it under its old one. The salon's own page shows the new one.
- **Unknown, and readable on your yes:** whether any production salon has a column that differs from its document (Q2).

### 2.2 The demo salon's reset leaves a reviewer's services and hours in place (proven)

- **How the reset restores the salon:** it sends the captured document back through `updateProfile`. Its comment (`demo_reset_service.dart:143-145`) says « everything the catalog surfaces can write gets reverted ».
- **What Postgres does with it:** the keys go into the `data` document. `byId` reads services and availability from their own tables, and `featured` and `status` from columns (`postgres_providers_repository.dart:119-120`, `:665-671`). So the restore never reaches them. `category` (§2.1) is the same.
- **Probe:** `updateProfile('provider2', {'services': [one new service]})`, then `byId`.

  | | In memory | Postgres |
  |---|---|---|
  | services after the write | `[probe_only]` | **`[service4]`**, unchanged |

- **For users:** the demo salon exists for the store reviewers. A reviewer who adds, removes or reprices a service, or changes the hours, leaves it that way for the next reviewer after the weekly reset. Only the agenda, the client book, KYC and the offer are truly reset.
- **The test that should catch it uses the in-memory twin:** `demo_reset_test.dart:119-125` even creates its services through `updateProfile`.

### 2.3 `PATCH /me` with an email another account uses answers 500 (proven)

- **The route** (`routes/me/index.dart:84`) passes the new email to `updateUser`. It has no check that the email is free, and no catch.
- **Postgres** has a unique index on `lower(email)` (`migrations.dart:526`), so the update throws `23505`, and the person gets a server error instead of a sentence they can act on.
- **The in-memory twin** accepts the change and repoints its email index at the editing account (`auth_repository.dart:506-514`).
- **Probe:** two accounts A and B, then `updateUser(A, email: B's)`, then a later sign-in by B's email.

  | | In memory | Postgres |
  |---|---|---|
  | the update | succeeds | **throws `UniqueViolationException` 23505** |
  | a later sign-in by B's email reaches | **A, the wrong account** | B |

- **For users:** rare, because it takes typing someone else's address. When it happens, the answer is a generic failure. A clear refusal (`409 email_taken`, with French copy in the apps) is the fix.
- **The twin's half is worse in a test than in production:** a test would « prove » that B's sign-in reaches A.
- *2026-11-26 — wider than this section says* ([account-email-change.md](account-email-change.md) §2.4, B16.3): the address a person types is stored unproven, and every sign-in finds an account by it, so its real owner lands in the typer's account, on both twins. The fix is that spec's, not a `409` alone.

### 2.4 Two smaller production inconsistencies

- **A re-submitted review, R1 (proven):**
  - Postgres keeps the first review's id on conflict (`postgres_reviews_repository.dart:27-31`).
  - The service returns a fresh id in the `201` body (`reviews_service.dart:191-207`).
  - So that id doesn't exist: `reviewById(returned id)` is `null`, where the twin finds it.
  - The apps take review ids from list reads, not from this body (searched in `mobile/lib` and `web/lib`), so no screen breaks today.
- **A reminder mark for a booking just deleted, D-3 (proven):**
  - `markIfNew` throws `23503` on Postgres, through the foreign key to `appointments`, where the twin returns `true`.
  - `ReminderScheduler.tick` has no per-booking catch (`reminder_scheduler.dart:27-42`), so a booking deleted between the window read and the mark aborts the rest of that tick.
  - The next tick recovers. It is a race.

---

## 3. The twin differences

### 3.1 Proven by probe (8)

| ID | Store · method | In memory | Postgres | Reach |
|---|---|---|---|---|
| A-P1 | providers · `updateProfile` → `query(category:)` | found under the new category | under the old one | **production defect, §2.1** |
| A-P2 | providers · `updateProfile({services, …})` | replaces services | ignored by reads | **production defect, §2.2** |
| B-P2-a | auth · `updateUser(email: taken)` | repoints the email | throws 23505 | **production defect, §2.3** |
| A-R1 | reviews · `upsertByAppointment` twice | keeps the new id | keeps the first id | the `201` id, §2.4 |
| C-D1 | disputes after `appointments.wipeForProvider` | the dispute stays (1 → 1) | cascaded away (1 → 0) | the demo reset; admin counts |
| C-S1 | subscriptions · `create` on an existing row | **resets the trial** and clears `paidUntil` | changes the tier only | a choice racing `createIfAbsent`; « one trial, never reset » |
| A-C1 | clients · `list` past the last page | total 3 | total 0 | the client list's `total` |
| D-3 | reminder log · `markIfNew(unknown booking)` | `true` | throws 23503 | the reminder tick, §2.4 |

### 3.2 Read by one reader, not probed (31)

**Reachable from production code** (a caller exists, though no user-visible bug is known today):

| ID | Store · method | The difference | Source |
|---|---|---|---|
| B-P1-b | provider auth · `loginWithSocial` with a new sub | the twin keeps the old sub signing in; Postgres replaces it | twin `:448-456`, PG `:165-171` |
| B-P2-b | consumer auth · the same | the same; Postgres creates a new user when no email comes | twin `:397-407`, PG `:195-231` |
| B-P1-a | provider auth · `register` | the email code is spent at the check in memory, at the insert in Postgres | twin `:550,601,661`, PG `:242-263`, `:287-290` |
| D-1 | membership · `firstActiveForAccount` | list order in memory, `invited_at` in Postgres: a member of two salons can land in a different one | twin `:240-245`, PG `:26-36` |
| A-P3 | providers · `query(q:)`, `listForAdmin(q:)` | Postgres `ILIKE` with `%` and `_` unescaped (`q='_'` matches every salon); the twin matches across field boundaries. **`query(q:)`'s half closed by A4-api (2026-11-25, [consumer-search.md](consumer-search.md) §3.1), with a contract on both twins; `listForAdmin(q:)` remains (B16.8).** | PG `:47-52`, twin `:239-243` |
| A-C2 | clients · `list(query:)` | the same unescaped `ILIKE` | PG `:55`, twin `:167-168` |
| A-P4 | providers · `listForAdmin` | rating order in Postgres, insertion order in memory | PG `:842` |
| B-P2-c | consumer auth · `listUsers` | newest first and per-column `ILIKE` in Postgres; oldest first in memory | PG `:482-497`, twin `:476-491` |
| A-C3 | clients · `create` duplicate | Postgres returns the existing row; the twin adds a second one (race only) | PG `:124`, twin `:239-242` |
| D-2 | membership · `resendInvite` after a revoke | the twin re-sends to a revoked member; Postgres refuses (race only) | twin `:438-446`, PG `:243-255` |

**Test-only** (no production caller reaches the difference; a test could still pin the wrong behaviour):
- **Aliasing (F2):** providers (A-P6: **7 test sites rely on it**), provider auth (B-P1-c: 4 test files rely on it), disputes (C-D2), demo snapshot (C-M1, a shallow copy shares the live salon's lists; fixed in B16.2, [demo-reset-restore.md](demo-reset-restore.md) §5.3), notifications (D-4), both audit logs (D-5), messaging outbox (D-6).
- **Writes (F1):**
  - reviews keep `moderationStatus` and a null `userName` (A-R2);
  - the Apple-token `kind` check (B-P4-a);
  - foreign keys the twins don't model: validation, place notices, subscriptions, disputes (C-X1);
  - non-JSON audit values (D-5).
- **Shape (F3):**
  - `moderationStatus` in review reads (A-R3);
  - stale `googleSub` and `emailVerified` in Postgres's provider-auth results (B-P1-d);
  - subscription times not in UTC in memory (C-S2);
  - outbox `params` typed `Map<String,String>` in memory (D-6).
- **Semantics (F4):**
  - `replaceAvailability` (A-P5);
  - the login throttle's expiry and `maxAttempts: 1` (B-P5-a, B-P5-b);
  - the purge's tie-break, its missing-queue-row case and three missing `rows_purged_at` guards (C-P1–C-P3). **In none of them does the twin delete where Postgres would not on a reachable path;**
  - validation `submit` with no row (C-V1);
  - notification sort ties within one millisecond (D-4).
- **Unconfirmed:** whether Postgres's collation orders ids differently from Dart under a `LIMIT` (C-X2). The repository cannot show the database's collation.

### 3.3 No difference found (9)

Admin auth, idempotency, rate limiter, client version, device tokens, notification preferences, send budget, favorites, messaging preferences.

---

## 4. What guards the twins today

| Has a contract run on both twins | Postgres-only tests | No Postgres test at all |
|---|---|---|
| bookings (B15.1), Apple tokens, idempotency, membership (invite, ensure-owner), salon validation, place notices, providers (suspension only), provider auth (KYC only) | purge, subscriptions, rate limiter, send budget, favorites, notifications, client version, provider audit, device tokens, notification prefs, admin audit log | demo snapshot, disputes, messaging outbox, messaging prefs, reminder log |

**The pattern:** where a contract runs on both twins, the readers found nothing reachable. Every reachable difference in §3 sits in a store, or a method, without one.

---

## 5. What this suggests

1. **Fix the three production defects first, each through its own short spec** (Q1):
   - **§2.1, the category:** keep the column in step with the document, then one read of production to see whether any salon already differs (Q2);
   - **§2.2, the demo reset:** restore services and hours through the real writers (`replaceAvailability`, the service writes), not through `updateProfile`;
   - **§2.3, `PATCH /me`:** refuse a taken email with `409 email_taken`, in the API, the contract and both apps' copy.
2. **Then the reachable twin differences, as B15.1 did for bookings:** a contract run on both twins, red first, with the twin brought into line. Grouped by store (Q3): auth (B-P1-a, B-P1-b, B-P2-b, B-P2-c), membership (D-1, D-2), subscriptions (C-S1), clients (A-C1, A-C2, A-C3), providers (A-P3, A-P4), reviews (A-R1, A-R2, A-R3), disputes and the reminder log (C-D1, D-3).
3. **The test-only differences:** fix each when its store is next touched, not in a sweep (Q4). Exception: the aliasing that tests rely on (providers, provider auth) needs those tests rewritten first, as its own small piece.
4. **One rule for BACKEND.md** (Q5): a store with writes has a contract run on both twins. That is the guard §4 shows working.

---

## 6. Questions for the owner — answered 2026-11-24, « Approve as recommended » (decisions 219–223)

Numbered from **219**, after batch 15's 214–218. This is batch 16 in the BACKLOG.

**Q1. The three production defects (§2): fix them, and in what order?**
- **Recommended: yes, in this order:**
  1. the category (§2.1): discovery, every user;
  2. the demo reset (§2.2): what store reviewers see;
  3. the taken email (§2.3): rare, but a server error.
- Each gets its own short spec and PR, and each deploy is on your word. → ✅ **Decision 219.**
- Or another order.

**Q2. Before fixing the category: read production to see whether any salon's `category` column already differs from its document?**
- **Recommended: yes, read-only**, the same method as batch 14's reads: the Auth Proxy, a read-only session, a probe write refused, aggregates only. A salon that differs gets its column set from its document in the fix's migration, which is your yes again. → ✅ **Decision 220.** The read itself runs on the owner's word when B16.1 starts.
- Or skip the read and let the migration align every salon.

**Q3. The reachable twin differences (§3.2's first table, and the proven ones of §3.1 beyond §2.1–§2.3): fix them by store, B15.1's way?**
- **Recommended: yes, after Q1's three.** One spec per store group (§5.2), each red first with a contract on both twins. → ✅ **Decision 221.**
- Or only those with a security angle: the old sub that keeps signing in (B-P1-b, B-P2-b).
- Or none for now.

**Q4. The test-only differences (§3.2, second list)?**
- **Recommended: fix each when its store is next touched;** they stay listed here. → ✅ **Decision 222.**
- Or a sweep now.

**Q5. A rule in BACKEND.md §5: a store with writes has a contract run on both twins?**
- **Recommended: yes,** written now, enforced as each store is touched. §4 shows it is the guard that works. → ✅ **Decision 223**, written in [BACKEND.md](../BACKEND.md) §5 in the same PR.
- Or leave it unwritten.

---

## 7. Review log

- **2026-11-24, surveyed:** four independent readers, each citing both sides, covered 28 pairs. Then one throwaway probe on both twins (a disposable database, dropped afterwards) proved eight differences, each with a control. The three production defects were also read end to end.
- **Not yet reviewed by a second reader as a document.** The readers' findings that were not probed are marked as such.
- **2026-11-24, answered:** « Approve as recommended », all five (decisions 219–223, batch 16 in the BACKLOG). **Found while recording them:** §5.2's auth group left out B-P2-c, which sits in §3.2's first table and so in Q3's scope; it is added there. The BACKEND.md §5 rule (decision 223) is written in this PR.
- **2026-11-24, decision 220's read** (20:39 UTC, read-only, the probe write refused): 9 salons, all drafts; 8 agree, 1 differs (column `salon`, document `barber`). So §2.1's « unknown » is answered: it has happened once; none of the nine is public today. Recorded in [provider-category-column.md](provider-category-column.md) §2.4.
