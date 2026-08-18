# The email send budget — design spec

| | |
|---|---|
| **Status** | Building |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-08-18 |
| **PRD ref / phase** | LAUNCH.md §4 · V1 (launch gate) |
| **Skills checked** | myweli-backend-guardrails · myweli-verification-guardrails |
| **Related** | [backend-rate-limiting.md](backend-rate-limiting.md) · [BACKEND.md](../BACKEND.md) §3, §7 |

## 1. Why this exists, when Cloud Armor already landed

Cloud Armor bought a **99.3% reduction against the trivial attacker** — one IP,
one loop. It bought nothing against a patient one. Per-IP is the weakest key
there is: rotating mobile addresses or a handful of hosts walk straight through,
and the ceiling can only be loosened over time, never tightened, because
carrier-grade NAT and shared salon connections put many real users behind one
address.

More importantly, **per-IP limits the wrong thing.** It limits *requests*, and
requests are a proxy. The asset is the **email channel and the domain's
reputation**: mass unsolicited mail from `no-reply@myweli.com` is how a domain is
blacklisted before it has users to lose, and no amount of request-shaping
guarantees a bound on that.

So: bound the sends directly. Then no attack *shape* matters — distributed,
slow, rotating identifiers, or a bug in our own code — because the constrained
resource is the one that can actually cause harm.

## 2. The decision that shapes everything: one budget would be a DoS

A single global ceiling is worse than none, and it took a moment to see why.

An attacker exhausts it in a minute. Every legitimate email for the rest of the
window is then dropped — booking confirmations, subscription notices, team
invitations. **A spam-prevention measure becomes an availability attack**, and a
cheaper one than the original, because the attacker no longer needs volume: they
need only to be first.

So the budget is **per class**, and the classes are defined by *who chose the
recipient*:

| Class | Recipient chosen by | Examples | Posture |
|---|---|---|---|
| **cold** | an anonymous caller | OTP to any address someone types | tight — this is the entire attack surface |
| **warm** | an authenticated actor, about their own thing | subscription notice, team invitation to a salon's own colleague | generous — starving these is the DoS above |

The two never share a counter, so exhausting cold cannot touch warm.

## 3. Where the counter lives

**Postgres, not memory.** `LoginThrottle` is the cautionary tale already in this
repo: an in-memory limiter whose own comment said *"move to a shared store if the
API is ever horizontally scaled"*, on a service that has run `maxScale: 4` for
weeks. Per-instance counters mean N× the budget and a reset on every cold start —
which for a *send* budget means the bound simply does not exist.

Migration `0033_email_send_budget`:

```sql
CREATE TABLE email_send_budget (
  bucket       text NOT NULL,        -- the class
  window_start timestamptz NOT NULL, -- truncated to the hour
  sent         int NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket, window_start)
)
```

**Reserve before sending, atomically, in one statement:**

```sql
INSERT INTO email_send_budget (bucket, window_start, sent) VALUES (@b, @w, 1)
ON CONFLICT (bucket, window_start) DO UPDATE SET sent = email_send_budget.sent + 1
RETURNING sent
```

One round trip, no read-then-write race across instances. If the returned count
exceeds the ceiling, the send is refused.

**Reserving before the send means a failed send still consumes budget.** That is
the correct direction: a provider outage must not become an unbounded retry
loop, and over-counting fails closed.

## 4. The seam

A **decorator**, not a change to every call site's logic: `BudgetedEmailProvider`
implements `EmailProvider` and wraps the real one. `dependencies.dart` wraps
whatever provider it built, so every present and future send passes through it —
including ones nobody remembers to route.

`EmailProvider.send` gains a **required** `classification`. Not defaulted:

- defaulting to `warm` means a new cold call site is silently unbudgeted — the
  exact failure this exists to prevent;
- defaulting to `cold` is safe but makes legitimate mail mysteriously fail.

Required means the author decides once, visibly, in review.

## 5. The ceilings

| Class | Ceiling | Reasoning |
|---|---|---|
| cold | **60/hour** | today's real volume is ~37 `/auth/*` requests in **seven days**. 60/hour is ~100× headroom for launch and still bounds a runaway at 1,440/day rather than 2,000,000. |
| warm | **1000/hour** | a bound against a loop in our own code, not against an attacker; it must never be the thing that drops a booking confirmation. |

Both configurable by env, because a launch changes the right number and a
redeploy is a poor way to discover that.

## 6. What the caller sees

`ok: false, error: 'send_budget_exhausted'`. The **route behaviour does not
change**: `/auth/email/otp/request` already ignores the send result and returns
202 either way, deliberately — a caller must not learn whether an address exists
or whether mail went out. Enumeration protection survives.

The operator learns instead: exhaustion is logged, and it is a condition worth
an alert later.

## 7. Threat model (BACKEND.md §7) — T64

**S/D** — an attacker emits mass mail from the launch domain, or starves
legitimate mail. Mitigated by a per-class hourly ceiling in Postgres, shared
across instances, reserved atomically before the send, with cold and warm
counters that cannot touch each other.

Residual, stated: the budget bounds *our* sending, not an attacker's ability to
consume it. A determined attacker can still exhaust the cold budget and deny OTP
email to real users for the rest of the hour. That is strictly better than the
alternative — a blacklisted domain is permanent, an hour of degraded sign-in is
not — but it is a real trade and not a solved problem. Per-recipient-domain
sub-budgets are the next refinement if it ever bites.

## 8. Tests

- Under the ceiling sends; at the ceiling refuses; the window rolls.
- **cold exhaustion does not touch warm** — the DoS this design exists to avoid.
- The reservation is atomic: concurrent sends cannot exceed the ceiling.
- The decorator passes through subject/body/recipient unchanged.
- `/auth/email/otp/request` still returns **202** when the budget refuses —
  enumeration protection is not weakened by the new failure mode.
