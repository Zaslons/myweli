# Observability — error reporting across the three surfaces

| | |
|---|---|
| **Module** | cross-cutting (`backend/`, `web/`, `mobile/`) |
| **Status** | Design. Three PRs, in launch order: backend → web → mobile. |
| **Closes** | [LAUNCH.md](../LAUNCH.md) §5.2 — *"we would not know if it broke"* |
| **Related** | [BACKEND.md](../BACKEND.md) §2, §3.6 · [WEB.md](../WEB.md) · [infra-staging.md](infra-staging.md) §1.1 |

## 1. Why now

LAUNCH.md names three questions the existing gates cannot answer. Two are
closed: production no longer serves fictional salons, and a restore has been
rehearsed. This is the third — **there is no crash reporting, no error tracking
and no alerting anywhere in the stack.**

It is not merely a gap; it **blocks the launch plan**. §1.4 requires staged
rollout for mobile, and staged rollout works by *watching the crash rate between
steps*. Without a crash-free-rate number there is nothing to watch, so the
mechanism that makes an unrecallable app release survivable does not function.

Today a crash on a user's phone is invisible to us forever, and a 500 in the
backend exists only in a Cloud Run log nobody is reading.

## 2. Tool — Sentry, on all three surfaces

**Chosen for one reason above the others: it is error *tracking*, not crash
reporting.** Crashlytics tells you the app died. Most production failures are not
crashes — a 500 on the booking route, a deposit screenshot that fails to upload,
a caught exception that leaves a user on a spinner. Those are the ones that lose
salons, and only handled-error capture sees them.

The rest of the case:

| | |
|---|---|
| **One tool, three surfaces** | When a booking fails, the first question is *which surface broke*. With Crashlytics + Cloud Error Reporting that is answered by correlating timestamps across dashboards. |
| **Release health is cross-surface** | "Did 1.0.3 make things worse" is one question, not three — and it is precisely what §1.4's staged rollout needs. |
| **Symbolication everywhere** | iOS dSYMs, Android R8 mapping (relevant while R8 remains an open decision), and JS source maps. Crashlytics does mobile only. |
| **Portable** | Open-source and self-hostable, so the decision is reversible. |

**Rejected, honestly:** Crashlytics is free and unlimited where Sentry's free
tier is 5,000 errors/month, it feeds Play Console's Android vitals directly, and
Firebase is already wired for push so setup would be smaller. The volume ceiling
is not a real constraint here — exceeding 5k errors/month means a worse problem
than the bill — and **Crashlytics cannot cover backend or web at all**, which
would leave us running three tools at the exact moment we are trying to reduce
the number of places to look.

## 3. What exists today, per surface

Wildly uneven, and the middle row is the finding:

| Surface | Seam | State |
|---|---|---|
| **mobile** | `AppLogger` + `runZonedGuarded` + `FlutterError.onError` | **Ready.** `logger.dart`'s own doc says it exists "so a crash reporter (Sentry / Crashlytics) can be plugged in later without touching call sites." `main.dart` funnels framework errors and uncaught async errors through it already. |
| **backend** | *none* | **BACKEND.md describes middleware that does not exist** — §1 lists `middleware/ … request-id, error→envelope, logging`, §2 says "catch at the edge, log with a request-id, return a generic 500", §3.6 requires "structured logs with a request-id". The chain in `routes/_middleware.dart` is **pure DI providers**. An unhandled throw is whatever dart_frog does by default. |
| **web** | *none* | No `error.tsx`, no `global-error.tsx`, no reporting. |

That backend row is why PR 1 is the largest of the three: it is not "add Sentry",
it is "build the error-handling layer the docs have claimed for months, then
report from it."

## 4. PR 1 — backend

### 4.1 The middleware that should already exist — **shipped as ONE, not two**

`observabilityMiddleware`, outermost in the chain (outside CORS — a 500 without
CORS headers reaches the browser as an opaque network failure, which is how a
server error gets misdiagnosed as a client one). It:

- takes `X-Request-Id` from the caller when present (the load balancer sets one;
  minting a second makes one request look like two across the two logs), else
  mints a UUID — and echoes it on **every** response, success and failure
- returns the **standard envelope** (`{"error":"internal_error"}`, 500) on any
  throw — never a stack trace, per §2's "never leak internals", enforced by
  nothing until now
- logs structurally with the id, method and path, recording the error's **type**
  and not its `toString()`: a thrown Postgres exception can carry row values
- reports it, fire-and-forget, so a slow reporter cannot become the request's
  latency

**Designed as two and shipped as one.** Split, the error handler had to read the
id back out of the request context — a `try`/`catch` around a diagnostic lookup,
inside the handler for the error being diagnosed — plus an ordering rule
("request-id must be outermost") that nothing enforced. Merged, the id is a
local, in scope for both paths.

**The reporter is passed as a callback, and that is load-bearing.** dart_frog
builds the middleware chain *before* the custom entrypoint runs: the generated
`server.dart` calls `buildRootHandler()` on one line and `entrypoint.run(...)` —
where `initializeDatabase()` configures the reporter — on the next. The first
version captured the instance, which froze the no-op that exists at build time:
every error afterwards would have been silently unreported, in a system that
looked wired and green. Caught before merge and pinned by a regression test.

### 4.2 What must never reach Sentry

The scrubbing is the security-sensitive part of this slice, and it is easier to
get right by allowlisting than by blocklisting.

| Never sent | Why |
|---|---|
| `Authorization` header, `X-Cron-Secret` | credentials |
| Request bodies | they carry OTP codes, phone numbers, names, deposit references |
| Query strings | `?secret=` is gone (#352) but the class of mistake is not |
| Cookies | the web session is httpOnly; forwarding it defeats that |
| `phone_number`, `email`, `client_phone`, `client_name` in any captured context | PII, and Ivorian data-protection law applies |

`sendDefaultPii` stays **false** (Sentry's default) and a `beforeSend` hook
strips the above explicitly rather than trusting it. The hook rebuilds
`event.request` from an **allowlist** — an allowlist stays correct when the SDK
adds a field, a blocklist silently does not — and clears `user`, `breadcrumbs`
and `extra` outright. Nothing sets those today, which is exactly why they are
cleared: the guarantee should hold for the code someone writes next year.

`contexts` is deliberately **kept**: OS, runtime and app metadata, no user data,
and the most useful thing left in the event once the request is stripped.

Tested with a synthetic event carrying one of everything forbidden — and the
decisive assertion is on the **serialised payload**, not field by field, because
per-field checks can each pass while a value escapes through a field nobody
thought to check.

### 4.3 Config

`SENTRY_DSN`, optional. **Unset → reporting is a no-op**, so dev and CI need no
setup and a missing DSN is never a boot failure. It is *not* added to the
`guardsOn` fail-fast list: an unreportable error is worse than a missing DSN,
but a backend that refuses to boot because its telemetry is unconfigured is
worse than both.

- `environment` = the `Env` enum (`dev` / `staging` / `prod`) from phase 1, so
  staging noise never pollutes production's release health
- `release` = the image tag (the git SHA), which is what makes release health
  meaningful
- `tracesSampleRate` = 0 initially. Performance monitoring is a separate
  decision with its own cost; this slice is errors only.

## 5. PR 2 — web

- `app/error.tsx` and `app/global-error.tsx` — neither exists, so a render error
  today shows Next.js's default page and reports nothing
- `@sentry/nextjs` for client, server and edge runtimes
- The BFF route handlers report with the request context, which is where a
  failing API call actually surfaces
- **Cookies scrubbed** — the session is httpOnly precisely so it never leaves the
  server

Copy must be French and follow the design system's four-states contract; an
error boundary is a user-facing surface, not a developer one.

## 6. PR 3 — mobile

The smallest change, because the seam was built for it: `AppLogger.error`
becomes the single integration point, and `main.dart`'s existing
`runZonedGuarded` + `FlutterError.onError` already route everything through it.

- `release` = the app version + build number, so crash-free rate maps to a
  TestFlight/Play build
- `environment` from the same dart-define that picks the API base
- Breadcrumbs must not carry PII — the booking flow handles phone numbers and
  names throughout

## 7. Proving it

**LAUNCH.md §5.2 requires this explicitly:** *"trigger one real error per
surface and watch it arrive."* A dashboard that has never received an event is
indistinguishable from one that is not wired up — which is the same class of
failure as the deploy workflow's verify step that could never have passed.

Each PR ships with its error deliberately triggered and the result recorded.

## 8. Alerting — named, not deferred silently

Reporting without alerting is a dashboard nobody opens. Sentry alert rules are
part of PR 3, once all three surfaces report:

- a **new** issue in production → notify
- an issue's rate spiking → notify
- **crash-free rate below threshold** → the gate §1.4's staged rollout depends on

The delivery channel is an open question (§9).

## 9. What is NOT wired yet — the account-side step

**There is no Sentry account, project or DSN.** The code is complete and inert:
`SENTRY_DSN` unset → `NoopErrorReporter`, which is why dev and CI need no setup
and why merging this changes nothing in production.

To switch it on, in this order:

1. Create the Sentry organisation and a project per surface
   (`myweli-backend`, `myweli-web`, `myweli-app`).
2. Put the backend DSN in Secret Manager and add `SENTRY_DSN` (via
   `secretKeyRef`) and `RELEASE` (`__IMAGE__`, substituted by the deploy
   workflow) to `infra/gcp/service.yaml`.
3. Deploy, then §7 — trigger a real error and watch it arrive.

Deliberately **not** added to `service.yaml` in this PR: it would reference a
Secret Manager entry that does not exist, and the next deploy would fail on
telemetry config — the precise failure mode §4.3 exists to avoid.

## 10. Open questions

1. **Where do alerts go?** Email is the default and is easy to ignore. WhatsApp
   is where this team already works, but Sentry has no native WhatsApp
   integration — it would need a webhook.
2. **Do we want performance monitoring?** `tracesSampleRate: 0` for now.
   Revisit once error volume is understood; it is the main cost driver.
3. **Self-host later?** Not now. Recorded because the portability argument in §2
   is only real if it is occasionally checked.
