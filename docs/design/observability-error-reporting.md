# Observability — error reporting across the three surfaces

| | |
|---|---|
| **Module** | cross-cutting (`backend/`, `web/`, `mobile/`) |
| **Status** | **All three surfaces done** (#359, #360, mobile). Every one is inert until a DSN exists — §9, which is now the only remaining step. |
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

## 5. PR 2 — web — **done**

`app/error.tsx` (route segments) and `app/global-error.tsx` (the root layout
itself, which `error.tsx` cannot catch — it renders *inside* it). Neither
existed: a thrown error showed Next's default page, English, no way out, nothing
reported.

`error.tsx` **reuses `ErrorState`** rather than restating the shape — §12/B6 had
already settled that an error state is "a human French message + a RETRY
control", and Next's `reset` *is* that retry, so the two contracts meet exactly.
`global-error.tsx` cannot reuse it: replacing the root layout means rendering its
own `<html>`/`<body>`, and the thing that failed is the thing `ErrorState`'s
surroundings come from.

**The wiring was the hard part, and the first version of it was dead.** Adding
the SDK and three `sentry.*.config.ts` files produced a green build in which
`Sentry.init` never ran — the config files are inert without `withSentryConfig`,
and Next 14 does not load `instrumentation.ts` without
`experimental.instrumentationHook`. Caught by grepping the built output for
`sentry` and finding nothing; the fixed build shows `instrumentation.js`
server-side and Sentry in the client chunks.

That is the same failure as the backend's captured reporter and the deploy
workflow's unreachable verify URL: **a check that cannot work, in a system that
looks fine.**

Scrubbing is `lib/sentry-scrub.ts`, cookies above all — the session is httpOnly
precisely so JavaScript cannot read it, and forwarding it to an error tracker
would hand over the credential that design protects.

## 6. PR 3 — mobile — **done**

The smallest change, because the seam was built for it. `logger.dart` carried a
literal `TODO(observability)` saying to forward errors "once a DSN is
configured" and to "keep this the single integration point" — so that is exactly
what happened.

`AppLogger` gains a **hook, not an import**, so the file still knows nothing
about Sentry. That matters beyond tidiness: `AppLogger` is imported by roughly
every layer, and a reporter dependency there would put a network SDK in the
import graph of every unit test. The hook is null in tests, so the suite neither
reports nor needs a DSN.

Wiring one call site covers everything, because `main.dart` already funnels
`FlutterError.onError` and every uncaught async error through `runZonedGuarded`
into `AppLogger.error`.

- **`release` is deliberately not set.** SentryFlutter reads it from the platform
  package info and produces `package@version+build` — the shape wanted, and the
  number §1.4's staged rollout is watched on. Setting it by hand would mean a
  `package_info_plus` dependency to reproduce what the SDK already does.
- **Screenshots and view hierarchy are explicitly off.** A screenshot of a
  booking form is a picture of someone's name and phone number, and a default
  can change.
- **Breadcrumbs are dropped entirely.** The booking flow's navigation and taps
  carry salon names, client names and phone numbers, and no filter over
  free-form strings stays safe as screens are added.
- **`sentry_flutter` was pinned to 9.x** to match the backend's major version.
  8.x resolved first and makes `SentryEvent`'s fields final, which leaves no way
  to null them in `beforeSend` — the scrubbing would have had to be rebuilt
  around `copyWith`, which cannot set a field to null anyway.

Size: the release APK is **22.7 MB** against the 30 MB budget, so the native
SDKs cost little — measured rather than assumed, since that gate is the one this
change was most likely to break.

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

**There is no Sentry account, project or DSN.** All three surfaces are complete
and inert: no DSN → the no-op path, which is why dev, CI and every test need no
setup and why the three merges changed nothing at runtime.

### 9.1 The three projects, and which SDK each is

One project per surface — **not** one shared project. Separate projects give each
surface its own issue stream, its own alert rules and its own release health,
which is the whole point of being able to ask "did 1.0.3 make things worse" per
surface.

| Project | Platform to pick in Sentry | Why that one | What we already import |
|---|---|---|---|
| `myweli-backend` | **Dart** | A pure Dart server, not a Flutter app. Picking Flutter here would give instructions for a widget tree that does not exist. | `package:sentry` (9.x) |
| `myweli-web` | **Next.js** (under JavaScript/Browser) | Not "React" and not "Node.js": the Next.js SDK covers client, server and edge runtimes in one, which is what `sentry.{client,server,edge}.config.ts` are. | `@sentry/nextjs` (10.x) |
| `myweli-app` | **Flutter** | Covers Dart errors *and* native iOS/Android crashes. A "Dart" project here would miss the native half, which is most of what a crash-free rate measures. | `sentry_flutter` (9.x) |

### 9.2 Skip every install step the wizard shows

The setup wizard will offer to install packages, write config files and add a
build plugin. **All of that already exists**, and following it would duplicate or
overwrite working configuration.

The **only** thing needed from each project is its **DSN** —
`https://<key>@<org>.ingest.sentry.io/<project-id>`. It is safe to hold in
config: a DSN authorises *writing* events, nothing else. Sentry also shows it
later under *Settings → Projects → <project> → Client Keys (DSN)*.

### 9.3 Products: **Error Monitoring only**

The creation flow asks which products to enable. Pick error monitoring and
nothing else — and none of it is permanent, so the rest can be turned on later
from project settings.

| Product | Now | Why |
|---|---|---|
| **Error Monitoring** | **yes** | The whole point of the slice. |
| Tracing / Performance | no | Every surface ships `tracesSampleRate: 0`, so the tab would receive **nothing** — a dashboard indistinguishable from a broken one, which is the failure shape this project has already hit three times. It is also the main cost driver: billed by span volume, orders of magnitude above error volume. Genuinely useful *later*, once there is traffic worth sampling and a rate worth choosing. |
| Logs | no | The backend already logs structurally to **Cloud Logging** (50 GiB/month free), which is where the container output lives. Sending them to Sentry too means paying to duplicate and creating a second place to look for the same thing. **The bridge already exists**: every unhandled error logs `request_id=…` and Sentry carries that value as a tag, so you read the error in Sentry and grep Cloud Logging for the id. |
| Session Replay | **no** — see §9.4 | It records the session, which here means a booking form being filled with a name and a phone number. |
| Profiling | no | Depends on tracing. |

### 9.4 Two settings that matter, in the web project especially

- **Session Replay: OFF.** Recent Next.js wizards enable it by default. It
  records the user's session — which on MyWeli means a booking form being filled
  with a name and a phone number. Our config never adds the replay integration;
  the risk is accepting a wizard default that does.
- **Data scrubbing: ON** (*Settings → Security & Privacy*), including scrubbing
  IP addresses. Redundant with `beforeSend` on all three surfaces, and worth
  having: the scrubbers run server-side, so they still apply to anything a future
  code path forgets to strip.

Leave performance monitoring alone — every surface ships `tracesSampleRate: 0`,
and it is the main cost driver.

### 9.5 Linking the GitHub repository — yes, with one caveat

Worth doing, and cheap here: **the repo is public**, so the usual objection —
granting a third party read access to private source — does not apply.

It buys **suspect commits** ("this error appeared in `ac36bab`, by this author")
and stack-frame → GitHub line links.

**But it only works where the release identifier maps to a commit**, which is not
uniform across the three:

| Surface | Release | Suspect commits |
|---|---|---|
| `myweli-backend` | the git SHA (`RELEASE=__IMAGE__`, which ends in it) | works |
| `myweli-web` | the git SHA | works |
| `myweli-app` | `package@version+build` | **does not** — that is a version, not a commit |

Mobile's release is deliberately the version + build, because that is what maps a
crash-free rate to a specific TestFlight or Play build — the number §1.4's staged
rollout is watched on. It is the right identifier; it simply is not a commit, so
suspect commits there needs a release-to-commit association wired separately
(`sentry-cli releases set-commits`, in a release workflow). Not worth doing until
mobile is actually distributed.

**Do not block on any of this.** Errors flow without the integration; it is an
enhancement, and a fiddly one can wait until events are arriving.

### 9.6 Then, to switch it on

1. **Backend** — put the DSN in Secret Manager, add `SENTRY_DSN` (via
   `secretKeyRef`) and `RELEASE` (`__IMAGE__`, substituted by the deploy) to
   `infra/gcp/service.yaml`, then run `deploy-backend.yml`.
2. **Web** — set `NEXT_PUBLIC_SENTRY_DSN` and `NEXT_PUBLIC_SENTRY_ENV` **per
   Vercel environment** (Production → `production`, Preview → `preview`), so
   preview noise never pollutes production's release health. `SENTRY_AUTH_TOKEN`
   is optional and server-side only; without it the build still succeeds and
   stack traces stay minified.
3. **Mobile** — add `--dart-define=SENTRY_DSN=…` and `--dart-define=SENTRY_ENV=…`
   to the release build commands in
   [mobile-store-submission.md](mobile-store-submission.md).
4. **Then §7** — trigger one real error per surface and watch it arrive. Until
   that happens the boxes are not merely unticked, they are **untestable**: a
   dashboard that has never received an event is indistinguishable from one that
   is not wired up.

## 10. Open questions

1. **Where do alerts go?** Email is the default and is easy to ignore. WhatsApp
   is where this team already works, but Sentry has no native WhatsApp
   integration — it would need a webhook.
2. **Do we want performance monitoring?** `tracesSampleRate: 0` for now.
   Revisit once error volume is understood; it is the main cost driver.
3. **Self-host later?** Not now. Recorded because the portability argument in §2
   is only real if it is occasionally checked.
