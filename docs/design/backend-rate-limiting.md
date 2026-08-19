# Per-source rate limiting — design spec

| | |
|---|---|
| **Status** | Cloud Armor built · app-level limiter groundwork built, enforcement OFF pending measurement |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-08-18 |
| **PRD ref / phase** | LAUNCH.md §4 · V1 (launch gate) |
| **Skills checked** | myweli-backend-guardrails · myweli-verification-guardrails |
| **Related** | [BACKEND.md](../BACKEND.md) §3, §7 · [LAUNCH.md](../LAUNCH.md) §4 |

## 1. What the measurement found

LAUNCH.md §4 asks for rate limiting *"verified against a real hostile pattern,
not a unit test"*. It was verified on 2026-08-18, against staging, and **it
fails**.

**What holds** — database-backed, therefore shared across instances:

| Probe | Result |
|---|---|
| Brute-force one identifier | locked after **exactly 5** wrong codes (`otp_locked`) |
| Resend the same identifier | **4** accepted, then 429 `otp_resend_limit` |

**What does not exist** — no per-IP or per-source limit anywhere, neither in the
app nor at the load balancer:

| Probe | Result |
|---|---|
| Rotate the identifier | **60/60 accepted**, 15 in flight — **23 accepted OTP requests/second** from one client, unbounded |
| Unauthenticated reads | **100/100** at 42 req/s, none refused |
| Booking routes | no limit of any kind |

**The per-identifier limits are correct and complete for what they defend — one
account. Nothing defends the endpoint.**

### Why this is launch-blocking rather than a hardening nicety

23 OTP requests/second on production is **23 real emails/second** from
`no-reply@myweli.com` to addresses the attacker chooses. Staging's Resend key is
a deliberate dud, so nothing was sent during the test; production's is live.

The cost is not the bill. It is mass unsolicited mail from the domain the
product launches on — spam complaints, then blacklisting, before there are any
users to lose.

### A second, smaller finding

`LoginThrottle` keeps state in a plain in-memory `Map`. Its own doc says
*"Single-instance V1 … move to a shared store if the API is ever horizontally
scaled."* Production runs `maxScale: 4`, so the condition it named has been met
and nothing noticed — a design-doc deadline again. It guards **admin login
only**, ~~which sits behind Cloudflare Access, so the blast radius is small.
Left as-is deliberately, and recorded here so the next person does not
rediscover it.~~

**That justification was FALSE, and the throttle moved to Postgres on
2026-08-19** ([backend-admin-login-throttle.md](backend-admin-login-throttle.md)).
The sentence is struck rather than deleted, because the failure it records is
the one worth remembering: *a justification written into a design doc becomes
the reason nobody looks again.* It was wrong on two independent grounds.

1. ~~**Nothing in this repository shows Cloudflare Access is configured.**~~
   **This ground was wrong.** Nothing in the repo *recorded* it — true — but
   that is a fact about our records, not about the world. **Verified 2026-08-19
   by fetching it:** `https://admin.myweli.com` redirects anonymously to
   `blue-base-1ad1.cloudflareaccess.com` and serves the Access sign-in. It is
   configured and it works.
2. **Even configured it could not have protected this.** Access would front
   `admin.myweli.com` on Cloudflare Pages. The API is `api.myweli.com`, which
   `70-load-balancer.sh:62-63,101` keeps **DNS-only / grey-cloud on purpose** so
   Google can validate the managed certificate — Cloudflare is not in the
   request path at all. And layer 1's rule is `startsWith('/auth/')`, which
   **`/admin/auth/login` does not match**.

So the blast radius was not small. The throttle was the only brute-force bound
on the credential `admin/_middleware.dart` calls *"the only thing standing
between the team and everyone's data"*, and across four instances it came to
roughly **20 guesses per 15 minutes, reset by any cold start**.

## 2. The fix, in two layers

**Layer 1 — Cloud Armor at the load balancer.** Production ingress is
`internal-and-cloud-load-balancing`, the `run.app` URL 404s, and an external LB
(`myweli-api-backend`) already exists with **no policy attached**. A per-IP
rate-limit rule there covers every path in, needs no code, adds no per-request
database write, and throttles *before* the request reaches the app — so it also
bounds volumetric load, not just abuse.

Threshold: **10 requests/minute per IP on `/auth/*`** (owner decision). A human
requests an OTP once, twice if it did not arrive. Ten a minute is generous for a
person and removes ~99% of the measured attack.

**Layer 2 — an app-level limiter** (owner decision: defence in depth). It
travels with the code, so it covers staging, local runs, and any future path
that does not go through the LB.

## 3. The detail that decides whether layer 2 works at all

**The app has never seen a client IP.** There is no `X-Forwarded-For` handling
anywhere in `backend/`, verified by grep.

And the header's shape **differs by environment**:

- **production** — behind an external ALB. Google appends, so the client address
  is *not* the leftmost entry; the leftmost is whatever the client sent.
- **staging** — `ingress: all`, no LB, reached directly on `run.app`.

A limiter that hardcodes a position is therefore either **trivially bypassed**
(trusting the leftmost value, which the client controls) or **catastrophically
wrong** (keying on the LB's own address, which limits *all* traffic to
10/minute together).

So the resolver takes a **trusted-proxy depth** and counts from the right, and
the depth is configuration rather than a constant. `clientIpFrom` is a pure
function with exhaustive tests, including the spoofing cases.

## 4. Why enforcement ships OFF

Because §3 is a claim about two deployments, and it has not been measured on
either.

The request log gains the resolved client IP — useful on its own, and the
instrument for this: with the resolver deployed and logging, the resolved value
can be compared against the `httpRequest.remoteIp` **Cloud Run itself records**,
which comes from the infrastructure and no client can forge. They must match.

Only when they match in *both* environments does `RATE_LIMIT_ENFORCE=true` go
on. Turning enforcement on before that risks locking every user out behind one
key, which is a worse outage than the abuse it prevents.

This is the same discipline as the version floor shipping at `0`: **the
mechanism lands first, inert, and the policy is a separate deliberate act.**

## 5. Tests

- `clientIpFrom` — exhaustive: empty, single, multiple, spoofed prefix, depth 0,
  depth 1, depth greater than the list, whitespace, IPv6.
- **The spoofing case is the one that matters**: a client sending
  `X-Forwarded-For: 1.2.3.4` must not be able to move the resolved address.
- The limiter: under the ceiling passes, over it refuses with 429, the window
  rolls, and two different keys do not share a budget.

## 6. Open questions

1. **Cloud Armor does not cover staging**, which has no LB. Acceptable: staging
   is not the launch surface, and layer 2 covers it once enforcing.
2. **Per-IP is defeated by a distributed attacker.** It raises the cost by
   orders of magnitude and removes the trivial single-source case measured
   above; it is not a claim to have solved abuse.
3. **Shared NAT.** A salon and its clients on one connection share an address.
   10/min is generous for humans, but the first weeks of real traffic are the
   test, which is why layer 1 ships in **preview** first if the owner prefers.

## 7. "Revisit the threshold once real traffic exists" was not blocked on traffic

It was blocked on an **instrument**, and that is a different problem with a
different fix.

`myweli-api-backend` had no `logConfig` at all, so load-balancer request logging
was off — and with it off, `enforcedSecurityPolicy`, the only field that records
a refusal, is never written. **Measured 2026-08-19:** eight refusals were
triggered against production while verifying rules 1000 and 1100, and a query
for `outcome="DENY"` over the following six hours returned **nothing**. The
rules worked; the evidence did not exist.

So the open question above could never have been closed by waiting. The traffic
would have arrived and told us nothing — and the failure it hides is the one
§6.3 already names as the real risk: a salon and its clients behind one address,
refused mid-booking, seeing an error while we see silence.

**Closed 2026-08-19** by `infra/gcp/91-armor-deny-alert.sh`: logging enabled at
sample rate 1.0 (the events worth seeing are rare, and sampling rare events away
is how you conclude nothing is happening), plus an alert on
`enforcedSecurityPolicy.outcome="DENY"`.

**Verified as two separate claims**, because the first must hold before the
second can even be tested:

| | |
|---|---|
| refusals are now logged | 15 rotating admin logins → `401 ×10` then `429 ×5`; four DENY entries, tagged priority **1100** — against **zero** before |
| the alert matches | incident *"Cloud Armor REFUSED a request"* opened 23:28:45Z, ~40s after the trigger |

Addresses were rotated on every request, because the app also returns 429
(`locked_out`) and a repeated address would have measured the wrong refusal.

**This alert is a launch-window instrument that retires itself.** With 5 users
and no salons, any DENY is a probe or an attacker and the signal is unambiguous.
Once real traffic exists the same alert becomes noisy and its meaning shifts
from *"someone is being refused"* to *"look at the ratio"* — which is precisely
the condition §6's open question was waiting for. It is what closes that item,
and then what makes itself redundant.
