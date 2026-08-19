# The admin-login lockout — design spec

| | |
|---|---|
| **Status** | **Built** — 2026-08-19, three slices; enforcing |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-08-19 |
| **PRD ref / phase** | LAUNCH.md §4 · V1 (launch gate) |
| **Skills checked** | myweli-backend-guardrails · myweli-verification-guardrails |
| **Related** | [backend-rate-limiting.md](backend-rate-limiting.md) (layers 1–3) · [backend-identity-rate-limits.md](backend-identity-rate-limits.md) · [admin-console.md](admin-console.md) · [BACKEND.md](../BACKEND.md) §3, §7 |

## 1. Why, and the premise that had to collapse first

`LoginThrottle` kept admin-login failure state in a plain in-memory `Map` on a
`maxScale: 4` service: **up to 20 guesses per 15 minutes, reset by every cold
start.** Its own comment was the expired deadline — *"move to a shared store if
the API is ever horizontally scaled."*

It was left that way on purpose. [backend-rate-limiting.md](backend-rate-limiting.md)
§1 recorded the reason: admin login *"sits behind Cloudflare Access, so the blast
radius is small."* **That premise fails on two independent grounds.**

1. **Nothing in this repository shows Access is configured.** Every mention is an
   unexecuted instruction — `DEPLOYMENT.md:295`, `deploy-admin.yml:8,24` — or a
   doc repeating one. `infra/cloudflare/` holds only R2 work, and `LAUNCH.md`
   mentions it **zero** times, so nothing tracks whether it was ever done.
2. **Even configured it could not protect this.** Access would front
   `admin.myweli.com` on Cloudflare Pages. The API is `api.myweli.com`, kept
   **DNS-only / grey-cloud on purpose** so Google can validate the managed
   certificate (`70-load-balancer.sh:62-63,101`) — Cloudflare is not in the
   request path. And Cloud Armor's single rule is `startsWith('/auth/')`, which
   **`/admin/auth/login` does not match**.

So `POST https://api.myweli.com/admin/auth/login` is reachable from any address
with no per-IP limit, and this throttle is the only brute-force bound on the
credential `admin/_middleware.dart` calls *"the only thing standing between the
team and everyone's data."*

**The lesson is not the Cloudflare detail.** It is that a justification written
into a design doc becomes the reason nobody looks again. The original sentence is
struck, not deleted, so the shape stays visible.

## 2. Why the `RateLimiter` is not reused

A lockout is a **penalty measured from an event**; a rate limit is a **budget
measured from a clock**. They do not convert:

- Five failures at 10:59:50 would be forgiven at 11:00:00 by an hourly window,
  and that window's documented `2 × limit` boundary property would hand out
  **nine consecutive guesses** against a budget of five.
- `RateLimiter` has no `reset`. Adding one would put an **attacker-callable
  budget refund** on booking, review and signing — `reset` is safe here *only*
  because it sits behind a successful bcrypt.
- Its only decision-grade call increments, but `isLocked` must be a **pure read
  before bcrypt**. Counting successes would lock out a working admin; counting
  only failures means you cannot refuse first.
- The shared instance is wrapped fail-open, which is right for booking and wrong
  here (§4).
- The key is an unauthenticated, attacker-chosen email — violating
  `identity_rate_limits`' own stated invariant.

**The rule of three does not fire.** This is a third counter but not a *windowed*
one. Said in the migration comment, or someone extracts the wrong abstraction.

## 3. The store

Migration `0035_admin_login_throttle`: `key_hash` (PK), `fail_count`,
`locked_until`, `updated_at`, plus an index on `updated_at`.

**`locked_until` is the column `window_start` cannot be** — an absolute instant
set relative to the triggering failure. `fail_count` alone cannot say "three so
far, not yet locked"; `locked_until` alone cannot say the count.

`recordFailure` is **one atomic statement** whose `CASE` carries three
subtleties, each with a test: the expired arm restarts the counter at 1
(reproducing the in-memory lazy delete); a NULL `locked_until` falls through by
three-valued logic, so the obvious `COALESCE` "fix" breaks it; and the threshold
reads the pre-increment value plus one, because Postgres cannot see another
column's new value in the same `SET`.

**The parameters are type-annotated, and that is not decoration.** Without them
the driver inferred `@until` as `text` inside the `CASE` and Postgres refused
with `42804`. Measured against a real server before anything depended on the
statement — the one genuine unknown in this design, resolved first on purpose.

## 4. Fail closed, with a code of its own

`throttle_unavailable` → **503 + `Retry-After`**, the opposite call from the
booking limiter. Its justification — *"every real control still holds without
the limiter"* — is true there and false here, where the password and this
throttle are the complete control set.

**The obvious objection mostly dissolves.** *"A database incident then locks
every admin out"* — but the throttle and the `admins` table share one pool, so a
**total** outage already blocks login whatever this returns. Only **partial**
failure differs, and there the choice is between an unavailable internal console
and unlimited silent guessing.

**The distinct code is the important half.** Returning `locked_out` on a database
failure would tell an operator at 2am that someone guessed too often when the
truth is that Postgres is sick — the confusion `storageUnavailable()` exists to
prevent.

**The asymmetry is the principle:** *the operations that bound the attacker fail
closed; the one that forgives the user fails open.* A failed **count** fails
closed too — an attempt bcrypt rejected but the store never recorded is a
repeatable free guess, which is the whole attack. `reset` fails soft: if it
throws the count is not cleared, which is stricter, never looser.

**Rejected: an in-memory fallback.** It would degrade to today's 20-per-15-minutes
rather than to nothing, which is genuinely the third option — and it silently
reinstates the exact defect this change removes. Recorded here as the answer *if*
console availability during a partial incident ever proves to matter, gated on a
loud log line.

## 5. The key, and why it is hashed

Unknown addresses are counted **deliberately**. Stop counting them and
`locked_out` appears only for real admin addresses, turning the endpoint into an
admin-address oracle.

That leaves the key set **open**, so: the address is capped at 254 chars (RFC
5321) at the route — a boundary the route never had, independent of this change —
and the stored key is a **SHA-256 digest**. Every row is then 64 bytes whatever
was submitted, third-party addresses stay out of the table, and the key is safe
to log. Postgres has `sha256()`, so the break-glass unlock stays one line:

```sql
DELETE FROM admin_login_throttle
 WHERE key_hash = encode(sha256('admin@myweli.ci'::bytea), 'hex');
```

**Rejected: bucketing into a fixed key space.** It closes the set and makes
collisions strictly tighter — and it hands an attacker who knows *no* admin
address a way to lock every admin out by spraying buckets, at a request volume
well under what was already measured. Trading unbounded storage for a cheap
total-console-lockout primitive is the wrong direction.

## 6. The prune is a security parameter

A `fail_count` whose `locked_until` is NULL never decays, so without a prune four
failures spread over a year are still four. **The window is therefore what gives
the counter a decay**, and 24h belongs beside `maxAttempts` and `lockout` rather
than in a maintenance note.

It rides on the existing daily `/internal/cron/subscriptions`: no new Scheduler
job, no new audience to keep in sync, nothing new that can stop silently, and it
is already covered by the missed-cron alert. The deleted count is returned so the
operation is observable. A third maintenance task is when to extract
`/internal/cron/maintenance`.

## 7. Tests

`LoginThrottle` had **no test at all** before this, and
`PostgresAdminAuthRepository` had **no integration coverage of any kind**. Both
gaps are closed. The properties worth naming, because each was unasserted while
the class guarded the credential:

- the boundary instant is still locked (`isAfter` ⇒ `>=` in SQL);
- **the counter restarts at 1 after expiry** — without it, one failure after a
  lockout ends re-locks immediately and the admin never gets back in;
- **`reset` on success** — four wrong attempts on Monday, a successful login,
  four more on Friday, still not locked;
- an unknown address **is counted** (the enumeration property);
- a **disabled** admin with the correct password is refused *and* counted — half
  of a compound condition nothing exercised;
- the lock **does not extend** while held;
- 25 concurrent failures return 25 **distinct** post-increment values;
- the composition root wires the **Postgres** implementation and does **not**
  wrap it fail-open.

## 8. Residuals

- **Check-before-verify TOCTOU** — with four instances mid-bcrypt when the Nth
  failure commits, a handful of guesses slip past. Inherent to refusing before
  verifying; solving it means holding a row lock across bcrypt, which is worse.
- **Clock skew** across instances — milliseconds against fifteen minutes.
- **The deliberate-lockout DoS gets stronger.** Locking a known admin out by
  guessing five times now holds across all instances and survives cold starts.
  That is the unavoidable cost of fixing the hole, bounded at 15 minutes, and
  answered by the break-glass unlock in §5.
- **T59 erasure does not enumerate this table.** Rows are window-scoped and
  transient, and the key is a digest, so this is declared rather than solved.
- **`/admin/*` still matches no Cloud Armor rule.** Separate change, and the
  ordering is deliberate: this throttle is the security fix (it bounds guesses
  per credential, which per-IP cannot), the rule is the storage fix (it bounds
  row growth at the source).
