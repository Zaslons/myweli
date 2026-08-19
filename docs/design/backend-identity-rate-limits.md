# Per-identity rate limits — design spec

| | |
|---|---|
| **Status** | **Built** — all three slices; enforcing. LAUNCH.md §4's box stays unchecked pending a probe against a deployed environment |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-08-19 |
| **PRD ref / phase** | LAUNCH.md §4 · V1 (launch gate) |
| **Skills checked** | myweli-backend-guardrails · myweli-verification-guardrails |
| **Related** | [backend-rate-limiting.md](backend-rate-limiting.md) (layers 1–2) · [backend-email-send-budget.md](backend-email-send-budget.md) (the pattern) · [BACKEND.md](../BACKEND.md) §3, §7 |

## 1. Why, and what it is not

[backend-rate-limiting.md](backend-rate-limiting.md) §1 measured the API on
2026-08-18 and found two holes. The auth one — **23 accepted OTP requests per
second from one client**, by rotating the identifier — was closed by Cloud Armor
at the load balancer. The other row in that table was never addressed:

> **Booking routes — no limit of any kind.**

Confirmed still true on 2026-08-19: `POST /appointments`,
`POST /appointments/{id}/review` and `POST /uploads/sign` return **no 429 of any
kind**. All three are hard-authenticated — 401 before any parse — so a
per-identity key is viable on every one.

**This is layer 3. It does not replace layer 2.** §1's other finding was 100/100
unauthenticated reads accepted at 42 req/s, and no identity key can touch those:
there is no identity. Layer 2 still owes the anonymous surface, on its own merits
and its own timetable.

## 2. Why this may enforce when layer 2 deliberately may not

The question a reader of [backend-rate-limiting.md](backend-rate-limiting.md) §4
will arrive with, so it is answered first.

§4 keeps the per-IP limiter inert because **its key is unverified**. The app has
never resolved a client IP; `X-Forwarded-For` has a different shape in production
(behind a load balancer, which appends) than on staging (`ingress: all`, reached
directly); and a limiter that hardcodes a position is therefore either trivially
spoofed — trusting a value the client controls — or catastrophically wrong,
keying on the balancer's own address and rationing all traffic together. Only a
measurement against `httpRequest.remoteIp` can settle which.

**None of that applies to a key derived from an HMAC-verified JWT.** A caller
cannot choose another's `sub` without the signing key, and no two callers
collapse into one bucket. There is nothing to measure, so there is nothing to
wait for.

It is also a smaller thing to get wrong: a mis-set per-IP threshold locks out
everyone behind one address, a mis-set per-identity one locks out one account.

**The residual, stated rather than implied.** An identity limit is only as strong
as the cost of minting an identity. That cost is bounded by layer 1 (10/min per
IP on `/auth/*`, live and observed refusing) and by the cold send budget (60
emails/hour globally). That composition is what makes layer 3 sound — and it is
also why layer 3 is not an argument for dropping layer 2.

## 3. The mechanism

`lib/src/security/rate_limiter.dart` — the primitive, domain-free:

```dart
typedef RateVerdict = ({bool ok, int hits, int limit});
abstract interface class RateLimiter {
  Future<RateVerdict> hit(String bucket, {required int limit, required Duration window});
  Future<int> used(String bucket, {required Duration window});
}
```

**The limit and window are parameters, not implementation state** — unlike
`SendBudget`, which owns its two ceilings because they belong to the email
domain. There are six thresholds here across three unrelated domains; baking them
in would make a security primitive import knowledge of bookings and uploads.
`lib/src/security/identity_limits.dart` holds the policy instead, and is the only
file to edit when a number is wrong.

**In Postgres, atomically, one statement** —
`INSERT … ON CONFLICT … DO UPDATE SET hits = hits + 1 RETURNING hits`. A
read-then-write races across instances: two both read 9 against a limit of 10,
both decide there is room, both proceed.

**A sibling of `email_send_budget`, not a generalisation of it.** That table
shipped to production, migrations are forward-only, and `PostgresSendBudget`
queries it by literal name — so renaming it to serve both would break every OTP
email the moment anyone rolled the revision back. Two near-identical tables is
the cheaper mistake. **The rule of three:** a *third* counter is when to extract
a shared windowed counter, not before.

**Fixed window, floored to the epoch** so any duration works and every instance
agrees without coordinating. The cost, stated: at a boundary a caller can spend
`2 × limit` across two adjacent windows. `email_send_budget` has the identical
property and never says so. If it ever matters the answer is a shorter window,
not a sliding one — sliding needs a row per request, which is the write
amplification this design exists to avoid.

**Fail open**, wrapped in `FailOpenRateLimiter` at the composition root. The
opposite call from `UploadVerificationService`, and the difference is the point:
there, letting an unverified object through means paying for arbitrary bytes, so
the failure *is* the harm. Here every real control still holds without the
limiter — slot uniqueness, ownership, the role gates, T61's claim-time size check
— so failing open costs a temporarily absent abuse ceiling, while failing closed
turns a Postgres blip into nobody being able to book.

## 4. The keys

| Surface | Bucket |
|---|---|
| `POST /appointments` | `book:<sub>` |
| `POST /appointments/{id}/review` | `review:<sub>` |
| `POST /uploads/sign` | `sign:<purpose>:<sub>` |

**The booking bucket omits the role.** Including it could only ever *split* a
budget, never merge one, and splitting is a weakening. Consumer ids are minted
`user_…` and provider account ids `provider_…`, so the prefixes are already
disjoint and the role adds nothing. It also stays correct whichever way §8's
missing-role-gate defect is eventually resolved.

**The sign bucket includes the purpose, and must be built only after the service
validates it.** `purpose` is client-supplied and checked against five literals
inside `UploadSigningService`, not at the route. Keying on the raw value would
let an attacker send a fresh random purpose per request: unbounded buckets, the
limit evaporates, and **every miss writes a new row** — turning the limiter into
the amplifier they wanted. **A rate-limit key may only be built from a closed
set.** This is the main reason the check belongs in the service layer.

The purpose is included where the role is not, for a reason that does not apply
to the role: the five purposes are gated to disjoint role sets and have wildly
different honest volumes. A salon loading forty gallery photos in a sitting is
normal; a consumer needing forty avatar signs is not.

**The salon id is deliberately not the key for `gallery`.** It would make a whole
salon team share one budget, so a colleague's portfolio upload would refuse
yours. Bounding storage cost is T61's job, at claim time.

**Count attempts, not successes.** The check sits before the ownership and
existence lookups, because *an attacker chooses whether their attempt succeeds,
so they must not be allowed to choose whether they are counted*. A booking
refused for `slot_unavailable` leaves no row and still cost the round trip.
`SendBudget` established the same discipline.

**On T61's ordering rule.** T61 says a claim path may validate before
authorizing but must never *mutate* before authorizing, and the limiter is an
INSERT placed before authorization. The distinction is the subject: T61 protects
against a mutation whose subject is not yet proven to be the caller's — an object
under a prefix they may not own. The limiter's subject is the caller's own
JWT-verified `sub`, authorized by construction before the handler ran.

## 5. The thresholds

Per hour, per identity. **All guesses, and saying so is the point** — production
holds 0 appointments, 0 salons and 5 users, so there is nothing to calibrate
against. That is the same position that made the Cloud Armor rule ship enforcing
rather than in preview: preview would have learnt nothing while the hole stayed
open.

The sizing principle differs from the email budget's. `kDefaultCeilings.cold` is
~100× real volume because it is *global* and must absorb every user at once.
These are per-identity, so each only has to absorb one determined human.

| Surface | Limit | Why |
|---|---|---|
| booking | 10 | A real consumer books one. The extreme honest case — booking for a family, retrying through a bad mobile connection — is maybe five. Against 23/second, ~8,000× |
| review submit | 5 | Highest per-request cost: an upsert plus `recomputeRatings` (two aggregates and a `providers` write) on a `db-f1-micro`. Honest volume is ~1 per completed visit, ever |
| sign `gallery` | 60 | The genuinely bursty legitimate case |
| sign `review` | 40 | See below — this number is not independent |
| sign `kyc` / `deposit` / `avatar` | 10 | A few documents, one proof per booking, one photo; each with room to retry |

**The composition, which is the non-obvious failure.** A review carries up to six
photos. At a naive `sign:review` of 20, a user submitting five reviews — exactly
the submit ceiling — needs up to thirty signs and is refused by a limit they
never approached on the surface they were using. **Two individually generous
limits can compose into a lockout**, and that produces a support ticket nobody
can diagnose. Hence 40, and a test that fails if `reviewSubmit` is raised without
it.

**One window (hourly) in v1.** An hourly-only booking limit still permits 240/day;
a second daily window is the natural extension and `hit` already takes the window
as a parameter, so it is strictly additive. Open question, not a gap.

**The 80% warning is worth more than the ceiling.** Reuse `warnThreshold` and its
`==`-not-`>=` fire-once trick. With zero production volume this log line is the
only instrument that can say a threshold is wrong *before* it refuses someone.

## 6. What the caller sees

One shared code, `rate_limited`, at 429 — not three. Client behaviour is
identical across all three surfaces (back off, show one French string); three
codes means three branches for one situation. The structured log carries the
path and the limiter's own line carries the bucket, so nothing is lost.

**`Retry-After` is deliberately omitted in v1.** The mechanism exists —
`storageUnavailable()` sets it — but an honest value needs the seconds remaining
in the window plumbed up through three result typedefs. A constant would be a
lie for an hourly window. The tests assert the exact response shape, so adding it
later is a visible contract change.

## 7. Delivery, in three slices

1. **The mechanism, inert** — migration `0034`, the limiter, both
   implementations, the policy, wiring, tests. Nothing calls it; zero behaviour
   change.
2. **The 429 plumbing, still inert** — `rate_limited` in `resultResponse` and in
   the two bespoke switches (`POST /appointments` and the review route each carry
   their own, both falling back to 400). `POST /uploads/sign` inherits it by
   delegating. The mapping lands **before the first emitter**, which is the
   opposite of how `storage_unavailable` had to be retrofitted across four
   places — `resultResponse`'s own comment records that it then "reaches two
   surfaces out of five", and `routes/appointments/index.dart` carries two arms
   that exist only because a code shipped as a 400 first.

   **The gate is an inventory, not a derivation, and that is deliberate.** The
   `storage_unavailable` gate derives its offender set from the services that
   can emit the code — which is the better shape, and impossible here: in this
   slice nothing emits `rate_limited`, so the derived set is empty and the
   assertion is vacuous. An empty check that reads as coverage is the defect
   this whole design is careful about. So slice 2 pins the **eight routes that
   decide `badRequest` as their own fallback**, each declared with whether it is
   rate-limited and why; a ninth appearing fails the test and forces the
   decision. The derived scan, with an `isNotEmpty` guard, lands in slice 3
   where it has emitters to derive from.

   **A measured detail worth keeping:** the codebase writes that fallback three
   different ways — a switch expression yielding a status, one yielding a whole
   `Response`, and a `default:` arm. The first version of the rule knew only the
   first shape and found **four** routes where there are **eight**. A detection
   rule is itself a claim that needs checking.
3. **Wire the three services**, with tests, the contract, and the docs. Done
   2026-08-19. The derived gate promised in slice 2 arrived here, where it has
   emitters to derive from, and **immediately earned itself**: it found three
   routes reading a limited service without mapping the code —
   `providers/{id}/appointments` (calls `bookManual`, not `book`) and the two
   review LIST routes. None can emit `rate_limited`, so each carries a
   `// no-rate-limit:` declaration with its reason. *Reading a limited service
   is not the same as calling its limited method*, and the gate is what turns
   that from a comment into a decision somebody has to make.

## 8. Flagged, not fixed here

**`POST /appointments` has no role gate.** Any non-null principal is routed into
`_book(context, principal.userId)`, so a provider or admin token books and its id
lands in `appointments.user_id` (`text NOT NULL`, no foreign key). The row is
then invisible to its creator — the list branches on role — still fires
`SalonNotifier.notify`, still creates a salon client card, and cannot be
reviewed, because the review route gates `role == 'user'`. A data-integrity
defect rather than privilege escalation: the booking is server-priced and
`pending` like any other. Its own PR, its own test.

## 9. Residuals

- **Minting identities.** One budget per account; bounded by §2's composition.
- **No pruning** on `identity_rate_limits`, same as `email_send_budget`. Bounded
  in practice at one row per active identity per hour; the `window_start` index
  is what makes a future prune a range delete rather than a full scan.
- **T59 erasure does not enumerate this table.** Rows are window-scoped and
  transient, so this is declared rather than solved — but declared explicitly,
  because T59's whole lesson was that every table keyed on a user id as plain
  `text` with no cascade cascaded nothing and nobody noticed. Hashing the `sub`
  into the bucket would remove the question at the cost of debuggability.
- **One extra write per mutating request** on a `db-f1-micro`.

## 10. Tests

Slice 1: under / **at** / over the ceiling · the window rolls · the documented
`2 × limit` boundary · **two identities do not share a budget** · concurrency ·
fail-open with its log line · epoch flooring at two durations · bucket
namespacing · the `signReview ≥ reviewSubmit × 6` composition.

Plus a `DATABASE_URL`-gated suite that proves the atomicity claim against a real
Postgres — asserting that 25 concurrent callers each saw a **distinct**
post-increment value, not merely that ten were allowed, since a count of ten
could come from a different mistake. `PostgresSendBudget` gained the same test
immediately afterwards — it had shipped to production with its atomicity resting
on a reading of its SQL, which is the gap writing this one exposed.

Watched red, slice 1: the off-by-one (`<` for `<=`); the bucket dropping the
identity; the window becoming a constant; fail-open flipped to fail-closed;
`signReview` dropped below the composition floor; and — against a real Postgres —
the atomic upsert rewritten as a read-then-write.

**And adding a second DB-gated file found a drift.** `runMigrations` does not
take the schema lock itself; the caller does, and `dependencies.dart` wraps the
whole setup block in `withSchemaLock` precisely because *"Cloud Run boots cold
instances in parallel where Render never did."* The existing test called it
**bare**, which was safe only while it was the ONLY file that did. Two concurrent
files, and `CREATE TABLE IF NOT EXISTS` is not atomic against a concurrent
creator: both check, both find the table absent, one loses with `23505` on
`pg_type_typname_nsp_index`. Reproduced red and then green against a real
Postgres, on a fresh database each time. Both files now go through the lock, as
production does — which also makes them a more faithful rehearsal of it.
