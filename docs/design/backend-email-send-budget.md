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

The operator learns instead — see §8, which is the half of this design that
turns a silent refusal into something anybody finds out about.

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

## 8. Observability — and why an exhaustion alarm is not enough on its own

The refusal is invisible from outside **by construction**: the route returns 202
either way so a caller cannot learn whether an address exists (§6). That is the
right call for enumeration, and it means a refused user sees a normal screen and
simply never receives a code. Nothing 5xxes, the service stays healthy, the
uptime checks stay green. Before launch there is nobody to complain, and after
launch the complaint arrives long after the hour it describes.

So the budget emits two lines, and **the order they arrive in is the point**:

| line | when | what it means |
| --- | --- | --- |
| `email_budget_warning class=… sent=… ceiling=…` | at 80% of the ceiling | nothing has been dropped; every message in this window is still going out |
| `email_budget_exhausted class=… sent=… ceiling=…` | past the ceiling | mail is being dropped right now |

Alerting only on exhaustion would be alerting only after the harm starts. For an
attack that is tolerable — the budget is doing its job and there is nothing to
tune. But for the case we actually expect, **real growth quietly outrunning a
number picked before launch**, it is too late: the first thing we would learn is
that someone could not sign in. The warning converts that into a decision that
costs one environment variable, taken while everything still works.

**Once per window per class, never a flood.** The threshold is compared with
`==`, not `>=`. That is safe across instances precisely because of §3: the upsert
hands each caller a distinct post-increment value, so the 48th send is seen by
exactly one request, whichever instance it landed on. A ceiling below 5 floors
the threshold to 0 and therefore never warns — deliberate, since at that size
exhaustion is the only signal that means anything.

**Neither line carries the recipient.** An OTP address is exactly what an
attacker would want read back out of the logs.

Both are picked up by `infra/gcp/88-email-budget-alert.sh`, which creates two
Cloud Monitoring log-match policies on the existing *Owner email* channel, with
different runbooks — a cold exhaustion is "someone is hammering sign-in, or the
ceiling is too low"; a warm one is "we are dropping booking confirmations, raise
it now". Log-match rather than a counter metric for the same reason as
`86-cron-auth-alert.sh`: a metric needs a threshold and a window, which is two
more numbers to get wrong.

**The filter cannot quietly rot.** An alert that greps for a string the code no
longer prints reads as coverage forever. A test in
`backend/test/email/send_budget_test.dart` reads the script and fails if either
line is renamed without it following.

Staging is included in both policies. A mail loop in our own code surfaces there
first — it redeploys on every merge to main — and staging's normal traffic comes
nowhere near 48 sends in an hour, so it costs no noise while making both
policies testable outside production.

### 8.1 Verified live, 2026-08-19 — both fired

Created against `myweli-api-staging` (running the image the send-budget commit
built — digest matched against what the deploy pushed, and since migrations run
before the port opens, a serving revision *is* the proof `0033` applied). Waited
**nine minutes** for propagation, then fired 61 rotating `.test` addresses on top
of one shape-checking request.

What the service printed — the arithmetic is the interesting part:

```
02:36:26  email_budget_warning   class=cold sent=48 ceiling=60
02:36:35  email_budget_exhausted class=cold sent=61 ceiling=60
02:36:36  email_budget_exhausted class=cold sent=62 ceiling=60
```

62 = 1 + 61 across two separate bursts, which is the shared Postgres counter
being exactly right rather than approximately right. The warning appears **once**
— not fourteen times for 48 through 61 — so the `==` comparison holds in a real
deployment with real concurrency, not only in the unit test. And it lands **nine
seconds before the first refusal** in a synthetic burst; under real traffic that
lead is hours.

All 62 requests returned **202**. The caller genuinely cannot tell a refusal from
a send, which is §6 holding under live conditions rather than by assertion.

Monitoring then opened both incidents at **02:37:09**, ~33 s after the lines were
written — two distinct policy names in `ViolationOpenEventv1`, which is the
check the script prescribes: one name would have meant the other filter was
wrong.

*Not* verified: notification **delivery**. Google logs incident opening and
nothing about the mail it sends, so the last hop is confirmable only by looking
in the inbox.

**Known gap, stated rather than implied.** These are log-*match* alerts: they
fire on a line appearing. Nothing detects the opposite — a budget that has
stopped counting because the table is missing or the pool is down. That failure
opens the ceiling rather than closing it, so it is a spam risk rather than an
availability one, and it is not covered here.

## 9. Tests

- Under the ceiling sends; at the ceiling refuses; the window rolls.
- **cold exhaustion does not touch warm** — the DoS this design exists to avoid.
- The reservation is atomic: concurrent sends cannot exceed the ceiling.
- The decorator passes through subject/body/recipient unchanged.
- `/auth/email/otp/request` still returns **202** when the budget refuses —
  enumeration protection is not weakened by the new failure mode.
- The warning fires **once**, at 80%, **while every message is still going
  out** — and strictly *before* the first refusal, which is the property that
  makes it worth having.
- Each class warns on its own counter; a ceiling too small for an 80% is silent.
- Neither log line contains the recipient.
- The alert script greps for the strings the code actually prints.

Watched red: a single global budget (the DoS in §2), never refusing, never
warning, warning on *every* send past the mark, and an alert filter pointed at a
renamed line.
