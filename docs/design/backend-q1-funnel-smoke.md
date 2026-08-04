# Q1 — the funnel, proven against a real server

> Module: **backend / CI** (docs/MODULES.md). Closes the ROADMAP §1.8 sentence
> that says there is nothing (`docs/ROADMAP.md:191`).
> Guardrails: [BACKEND.md](../BACKEND.md) (§5 testing strategy, §6 DoD, §7 threat model) ·
> [ROADMAP.md](../ROADMAP.md) Part 4 · [DEPLOYMENT.md](../DEPLOYMENT.md) Phase G.
> Prior art: [web-b10-flake.md](web-b10-flake.md) (a gate that lies is worse than no gate;
> retries stay at 0) · [salon-state-and-refusals.md](salon-state-and-refusals.md)
> (the prose tables this slice turns into an executable gate).

| | |
|---|---|
| **Status** | **Draft** — needs sign-off before any code |
| **Owner** | Sadreddine |
| **Last updated** | 2026-08-04 |
| **PRD ref / phase** | Cross-cutting launch readiness (§1.8 🟣 Quality) · V1 |
| **ROADMAP entry** | `docs/ROADMAP.md:191` (the false sentence) · `:373` (the boot-smoke bullet) · `:425` (the backend test-pyramid row) |
| **Skills checked** | myweli-dev-guardrails · myweli-backend-guardrails |

---

## 1. Goal & scope

### 1.1 The sentence this slice makes false

> `docs/ROADMAP.md:191` — "**Quality** — **no E2E/integration tests vs a real
> backend** (unit/handler only); low-end-Android **perf pass** (budgets); …"

That sentence is true today in the sense that matters: 656 backend `test()` calls
across 63 files, and **not one of them opens a socket** — route tests import the
handler and drive it with a mocked `RequestContext`
(`backend/test/providers_test.dart:150-158`). The only committed code that boots
the real server and speaks HTTP to it is the CI job `backend-boot-smoke`
(`.github/workflows/ci.yml:123-212`), and it asserts eleven things, seven of
which are `grep` substring matches.

Q1 grows that job from a boot check into **an end-to-end proof of the booking
funnel** — a salon is registered, completed, published, found, booked, accepted
and cancelled, against the production build path and a real Postgres, with the
refusals asserted alongside the successes.

### 1.2 Why now (the money argument)

DEPLOYMENT.md Phase G (`docs/DEPLOYMENT.md:194-199`) is a **manual** go-live pass
on production — with real SMS, real WhatsApp, real R2, real push. Every defect
that Phase G discovers is discovered after money has been spent and against live
config. Everything in Phase G that does **not** need a paid account (discovery →
provider page → booking → pro accepts) can be proven for free, on every PR,
before any of it is switched on. That is exactly the surface Q1 covers.

### 1.3 In scope

- Extending `backend-boot-smoke` into a real funnel e2e (§5 decides the shape).
- The **anonymous** platform reads (health, discovery, localities).
- The **pro** half: register → the go-live gate refuses → complete the salon →
  offer → publish.
- The **consumer** half: availability → book → the slot is consumed → double-book
  refused.
- The **salon's** answer: list → accept → the state machine holds.
- The **refusals**: row-82's three vocabularies (`not_found` / `provider_not_found`
  / `provider_not_published`), plus the BACKEND.md §5 required security list
  (missing / invalid / expired / replayed tokens, lockout, cross-tenant → 403).
- Cancel, and the slot coming back.
- **Suspension (extra, taken)** — an admin suspends the live salon and row 82's
  fourth vocabulary (`provider_suspended`) is asserted on the consumer side, with
  Decision A's asymmetry proven on the pro side: a *suspended* salon may not
  manual-book, a *draft* one may. `POST /admin/providers/{id}/suspend` exists
  (`backend/routes/admin/providers/[id]/suspend.dart:8`) and
  `ADMIN_EMAIL`/`ADMIN_PASSWORD` seed a staff account when set and are a no-op
  when unset (`backend/lib/src/dependencies.dart:750-752`), so the job supplies
  fake, non-secret values.
- **AOT parity (extra, taken)** — the funnel runs against a `dart compile exe`
  binary built exactly as `backend/Dockerfile:25-27` builds it, not against JIT.
  The artifact under test becomes the artifact that deploys.
- **ROADMAP hygiene (extra, taken)** — the full pass, including the two claims
  that are already false independent of this slice (§9).

### 1.4 Out of scope (deliberately — §8 states the consequences)

Deposits and KYC; reviews, favourites, messaging/outbox, push, uploads;
reschedule; the web BFF and both Flutter apps; load and concurrency; OpenAPI
schema conformance.

**Three items moved OUT of this list by decision** (they were §11's open
questions 2, 5 and 6, and all three were taken): suspension + the admin console's
login, AOT parity, and the full ROADMAP hygiene pass. The admin console's own
surfaces remain out of scope — only `login` and `suspend` are touched, and only
as instruments.

### 1.5 Architecture — no product surface, and the seam question answered

**This slice adds no route, no service, no repository, no DTO, no migration and
no client code.** The layering rule (`routes → services → repositories`) is not
touched because nothing new enters the layers. The deliverable is a test harness
plus CI wiring.

The brief asks that any seam be named and justified. There are exactly two, and
**both already exist and are already env-gated in production**:

| Seam | Where | Why it is safe |
|---|---|---|
| `devCode` echoed in the OTP response | `backend/lib/src/dependencies.dart:99` (`_isProd`), `backend/lib/src/db/postgres_auth_repository.dart:93` (`devCode: _isProd ? null : code`), emitted only when non-null (`backend/routes/auth/email/otp/request.dart:52`) | Shipped since the auth overhaul; `ENV=prod` nulls it. Q1 adds nothing — it consumes what dev/CI already returns. |
| `LogEmailProvider` when `RESEND_API_KEY` is unset | `backend/lib/src/dependencies.dart:199-210` | The no-network fallback. Nothing leaves the runner; **no Resend, and no Twilio at any price**. |

**No new seam is introduced, and none is wanted.** In particular Q1 refuses:
a test-only reset/fixture endpoint in the production binary; an `ENV=test`
branch; any relaxation of a gate to make the funnel easier to drive. Where a gate
makes the funnel expensive (the publish checklist needs 3 services and 3 photos —
`backend/lib/src/salon_provisioning_service.dart:114-116`), the funnel pays the
cost, because paying it *is* the test.

---

## 2. What exists today

### 2.1 The job, measured

`backend-boot-smoke` (`.github/workflows/ci.yml:123-212`): `ubuntu-latest`, no
`needs:`, `working-directory: backend`, its own `postgres:16` service on DB
`myweli_smoke` (`:134-147`), four env vars (`:148-152`) on top of the
workflow-level `TZ: UTC` (`:14-15`). Dart 3.10.7, `dart_frog_cli 1.2.14`,
`dart_frog build` code-gens `build/bin/server.dart` (`:170-171`), then **one**
`run:` block backgrounds `dart build/bin/server.dart`, waits for `/health`, and
makes eleven failable checks (`:174-212`).

Real timings, run `30919441714` (2026-08-04, green):

| Step | Wall clock |
|---|---|
| Initialize containers (Postgres) | 21 s |
| Set up Dart | 7 s |
| `dart pub get` | 2 s |
| Activate `dart_frog_cli` | 5 s |
| `dart_frog build` | 9 s |
| **Boot + all 11 assertions** | **6 s** |
| **Job total** | **53 s** |

For scale, the same run's critical path was *Mobile — APK size* at 8 m 14 s and
*Analyze & Test* at 6 m 39 s. The smoke job has minutes of headroom before it
costs anyone a second of waiting.

### 2.2 What the job proves today

`/health` → `status:"ok"`; `/providers` contains `"id":"provider1"`;
`/localities` contains `"code":"CI"` and `"id":"cocody"`; a phone-OTP
request → `devCode` → verify → a body containing `"accessToken"`
(`.github/workflows/ci.yml:190-211`). No migration or seed step exists in CI
because `backend/main.dart:10-14` calls `initializeDatabase()` before `serve()`,
which runs migrations + the four seeds/backfills
(`backend/lib/src/dependencies.dart:735-745`).

### 2.3 What it cannot prove (and one thing it proves wrongly)

1. **Substring, not structure.** All seven checks are `grep -q` over the whole
   payload. `grep -q '"id":"provider1"'` passes if the string appears anywhere,
   in any nesting, and breaks silently if a response is ever pretty-printed.
2. **No status codes.** `curl -fsS` collapses every 4xx/5xx into an exit code and
   **discards the body**, so a failure shows a bare curl exit, never the error
   envelope.
3. **No refusals at all.** Zero assertions that a route returns the *right*
   failure. Row 82 shipped four days ago with its refusal table living only as
   prose (`docs/design/salon-state-and-refusals.md:352-366`).
4. **One unnamed step.** A red run says only "Boot server + smoke endpoints"; you
   must read the log to learn which of eleven checks died.
5. **The readiness loop has no failure arm** (`:183-189`): if 30 polls fail while
   the process is still alive, the loop simply ends and the next `curl` dies with
   an unexplained exit code. There is no `timeout-minutes:` on the job either, so
   a hang costs up to the 6-hour default.
6. **It asserts an auth route production disables.** `ci.yml:200-211` drives
   `POST /auth/otp/request` (phone). The launch config sets
   `AUTH_METHODS=google,apple,email` (`render.yaml:58-59`), and the phone routes
   answer `404 auth_method_disabled` under it
   (`backend/routes/auth/otp/request.dart:17`). CI is green on a door that is
   bolted shut in production, and the door that is actually used
   (`/auth/email/otp/*`) is never touched. **This is the survey conflict, resolved:
   both surveys were right about different environments** — `AuthMethods.defaults`
   does include `phone` (`backend/lib/src/auth/auth_methods.dart:24`) and CI never
   sets `AUTH_METHODS`, so CI silently runs a configuration production does not.

### 2.4 There is no e2e harness to extend

Confirmed by the survey and by inspection: the only `.sh` files ever committed
are `mobile/scripts/build_consumer.sh`, `build_pro.sh`, `run_pro.sh`,
`tool/update_goldens.sh`; `backend/` has no `bin/`, `tool/` or `scripts/`
directory; `grep -rln "HttpServer\|serve(\|shelf" backend/test/` returns nothing.
The PR1c/PR1d "end-to-end proof" was ~31 inline Bash tool calls in a chat session,
whose only durable trace is prose in
`docs/design/salon-state-and-refusals.md:167,237,352`. Its scratchpad artifacts
live under a session-scoped temp dir and are **not durable** — nothing to port
except the knowledge, which §3 encodes.

`web/tests/e2e/` is a real 17-spec Playwright suite but is hermetic against a Node
stub by design (`web/playwright.config.ts:7`), so it proves nothing about
`dart_frog` and must not be modelled on or counted with.

**Therefore: the thing to extend is the CI job.** §5 decides how.

---

## 3. The funnel as an ordered assertion list

Conventions for the table: **status** is the HTTP status asserted explicitly (not
inferred from curl's exit code); **body invariant** is asserted on decoded JSON,
never on a substring; ids/tokens/slots flow forward from earlier steps. `D` = the
booking date, computed once as *today + 7 days* in UTC. `SALON` = the salon the
smoke registers (§6). All emails/phones carry a per-run nonce.

### Phase 0 — the platform answers (anonymous)

| # | Request | Status | Body invariant | A failure in production means |
|---|---|---|---|---|
| A1 | `GET /health` | 200 | `status == "ok"` | The process is up but not serving; every uptime probe is lying (`backend/routes/health.dart:13-19`). |
| A2 | `GET /providers` | 200 | envelope keys `{items,page,pageSize,total}`; `total >= 4`; an item with `id == "provider1"` whose `services` is non-empty | Migrations or the seed did not run on a real Postgres, or the discovery filter's spelling hides live salons (`backend/lib/src/db/postgres_providers_repository.dart:35`). A blank home screen for every user. |
| A3 | `GET /localities` | 200 | a country with `code == "CI"`; an area with `id == "cocody"` | The multi-pays reference tree is missing → registration cannot resolve an `areaId`, and the publish gate's `profile` key can never be satisfied. |
| A4 | `POST /auth/otp/request` `{phoneNumber}` **with `AUTH_METHODS=google,apple,email`** | **404** | `error == "auth_method_disabled"` | The SMS door is open in a configuration that believes it is shut — at $0.49/segment. This is the assertion that keeps CI honest about production config (`render.yaml:58-59`). |

### Phase 1 — a salon is born, and is invisible while it is a draft

| # | Request | Status | Body invariant | A failure in production means |
|---|---|---|---|---|
| A5 | `POST /auth/provider/email/otp/request` `{email: pro-<nonce>@…}` | 202 | `expiresInSeconds == 300`; `devCode` matches `^\d{6}$` | Pro sign-in is dead at the first step, or (if `devCode` leaks with `ENV=prod`) every account is takeable — the `_isProd` guard is the only thing between the two. |
| A6 | `POST /auth/provider/email/otp/verify` `{email, code}` — no salon yet | **404** | `error == "provider_not_found"` | Login auto-creates salons (T35): typo an email at sign-in and you own a ghost salon. |
| A7 | `POST /auth/provider/register` `{businessName, businessType:"salon", phoneNumber, address, areaId:"cocody", email, code}` — **the same code A6 did not consume** | 201 | flat session: top-level `accessToken`; `provider.providerId != provider.id`; `provider.status == "draft"` | Two things: the login-only verify wrongly consumed the code (registration would be impossible right after a failed login — the exact reason `provider_auth_repository.dart:363-375` does not consume), and the account-id/salon-id distinction that every `/providers/{id}/…` path depends on. |
| A8 | `GET /providers/{SALON}` (anonymous) | **404** | body is exactly `{"error":"not_found"}` | A half-built salon is publicly readable — row 82 / T51's enumeration oracle. Clients would land on a salon with no photos, no hours and no way to book. |
| A9 | `GET /availability?providerId={SALON}&date={D}` (anonymous) | **404** | body is exactly `{"error":"provider_not_found"}` | Same leak through the one public door that accepts an arbitrary id in a query string; and the deliberately *different* vocabulary here (`provider_not_found`, not `not_found`) is what T51 uses to avoid an oracle. |
| A10 | `POST /auth/email/otp/request` + `/verify` for `client-<nonce>@…` | 202, then 200 | verify returns **nested** `tokens.accessToken` + `user.id`, and **no top-level `accessToken`** | The consumer/pro session shapes drifted — `backend/lib/src/responses.dart:44-46` records that this exact drift broke the web BFF once. |
| A11 | `POST /appointments` (consumer bearer) `{providerId: SALON, serviceIds:["nope"], appointmentDateTime: D+09:00Z}` | **409** | `error == "provider_not_published"` | A draft salon takes client bookings it cannot honour. Also pins the *order* of the guards: the salon refusal is answered before service validation (`backend/lib/src/appointments/booking_service.dart:59` vs `:80`), which is why a bogus service id still yields the salon's code. |

> A8 + A9 + A11 are the three vocabularies of
> `docs/design/salon-state-and-refusals.md:363-366`, which today exist only as a
> prose table typed by hand after a manual run. Q1 makes that table executable.

### Phase 2 — the go-live gate, from the inside

| # | Request | Status | Body invariant | A failure in production means |
|---|---|---|---|---|
| A12 | `POST /providers/{SALON}/publish` (pro bearer) | **409** | `error == "incomplete"`; `missing` as a **set** == `{profile, location, services, photos, availability, offer}` | The go-live checklist is not server-authoritative (PRD FR-PRO-ONB-001). A salon with no hours and no services goes live and takes bookings into a void. Set-equality (not "contains") is what makes a *silently dropped* check red. |
| A13 | `PATCH /providers/{SALON}` `{description, latitude, longitude}` | 200 | echoed values persist | The salon can never satisfy `profile`/`location`; the discovery map has no pin. |
| A14 | `POST /providers/{SALON}/services` ×3 (e.g. 5000 XOF / 30 min) | 201 each | server sets `id`, `providerId`, `active == true`; client-sent `id` is ignored | The catalogue accepts client-chosen ids/state — the server stops being the authority on the thing it later prices. |
| A15 | `PUT /providers/{SALON}/gallery` `{imageUrls: [3 urls]}` | 200 | `imageUrls.length == 3` | Photos cannot be attached; the publish gate is unsatisfiable and the listing is blank. |
| A16 | `PUT /providers/{SALON}/availability` `{weeklySchedule "0".."6" 09:00–18:00, bufferMinutes 0, blockedDates []}` | 200 | re-`GET` returns 7 open days and `bookingHorizonDays`/`minimumNoticeMinutes` at their defaults (365/60) | Hours do not persist, or the allow-list at `provider_catalog_service.dart:279-291` silently drops a key and answers 200 anyway — the failure mode that file's own comment warns about. |
| A17 | `POST /providers/{SALON}/publish` | **409** | `missing == ["offer"]` **exactly** | The pricing pivot (T54) is not the last door: either a salon goes live without an offer (free forever), or one of the five completeness checks silently stopped working. |
| A18 | `PUT /providers/{SALON}/subscription` `{tier:"pro"}` | 200 | `status == "trial"`; a `trialEndsAt` in the future | The one-trial-per-salon clock does not start; revenue state is not created at the moment the salon commits. |
| A19 | `POST /providers/{SALON}/publish` | **200** | `status == "active"` | Nobody can ever go live. The single most expensive possible bug in the pro funnel. |
| A20 | `GET /providers/{SALON}` (anonymous) | **200** | `id == SALON`; `name` matches; `reviews` is an array | Paired with A8: publication does not actually open the public door. **A8 and A20 falsify each other** — a server that 404s everything passes A8 and fails A20; one that 200s everything does the reverse. |
| A21 | `GET /providers?q=<unique salon name>` | 200 | `items` contains `SALON` | The salon is readable by direct link but invisible in discovery — i.e. the list filter and the detail gate disagree (they are two different spellings of the same rule: `postgres_providers_repository.dart:35` vs `salon_visibility.dart:42-43`). |

### Phase 3 — the consumer books

| # | Request | Status | Body invariant | A failure in production means |
|---|---|---|---|---|
| A22 | `GET /availability?providerId={SALON}&date={D}&serviceIds={svc1}` | 200 | `slots` non-empty; every entry parses as UTC ISO-8601; capture `s0 = slots[0]` | The slot engine returns nothing for an open, published, in-horizon day — the booking funnel is dead with no error message anywhere (an empty `slots` array is a 200 by design). |
| A23 | `POST /appointments` `{providerId, serviceIds:[svc1], appointmentDateTime: s0}` (consumer bearer) | **201** | `status == "pending"`; `totalPrice == 5000` (the price *we* created); `depositAmount == 0`; `balanceDue == 5000`; `currency == "XOF"`; `userId ==` the consumer; response key is `appointmentDate` | Booking is broken, or — worse and quieter — the server stopped pricing and started trusting the client. `totalPrice` asserted against a value the client never sent is the server-authority proof. |
| A24 | `GET /availability` (same args as A22) | 200 | `slots` does **not** contain `s0` | The engine does not see its own writes: the same slot is sellable twice, and two clients arrive at once. |
| A25 | `POST /appointments` (identical body to A23) | **409** | `error == "slot_unavailable"` | The write path does not re-check the slot it was handed — double-booking with a perfectly valid-looking request. |

> A23's deposit assertions are deterministic because a freshly registered salon
> carries `depositRequired: false`, `depositPercentage: 0.0` and
> `cancellationWindowHours: 24`
> (`backend/lib/src/providers_repository.dart:756-760`). Turning deposits **on**
> would require a KYC-verified account
> (`provider_catalog_service.dart:554-558`) — which is why deposits are out of
> scope (§1.4), not an oversight.

### Phase 4 — the salon answers

| # | Request | Status | Body invariant | A failure in production means |
|---|---|---|---|---|
| A26 | `GET /appointments` (**pro** bearer, no salon id sent) | 200 | `items` contains the appointment id with `status == "pending"` | The pro's agenda is empty while clients are booking — the salon never learns it has a customer. Also proves the salon is resolved from the token's memberships, never from the request. |
| A27 | `POST /appointments/{id}/accept` (pro bearer, no body) | 200 | `status == "confirmed"` | The confirmation transition is broken: every booking stays pending forever and the client is never told yes. |
| A28 | `POST /appointments/{id}/accept` again | **409** | `error == "invalid_state"` | The lifecycle is not a state machine but a setter — re-entrant transitions would let a cancelled or completed booking be resurrected. |
| A29 | `GET /appointments/{id}` (**consumer** bearer) | 200 | `status == "confirmed"`; `providerName ==` the salon's name; `providerPhone` present | The PR1c enrichment does not survive a real Postgres round-trip: the client's own appointment card cannot name the salon it booked (Decision C's whole point). |

### Phase 5 — the refusals (BACKEND.md §5's required list, over real HTTP)

| # | Request | Status | Body invariant | Required category |
|---|---|---|---|---|
| A30 | `GET /appointments`, no `Authorization` header | **401** | `error == "unauthorized"` | **missing auth** |
| A31 | `GET /appointments`, `Authorization: Bearer not-a-token` | **401** | `error == "unauthorized"` | **invalid token** |
| A32 | `GET /appointments` with an HS256 JWT signed by the job's `JWT_SECRET`, `sub` = the real consumer, `exp` 1 h in the past | **401** | `error == "unauthorized"` | **expired token** — minted in the harness with `dart_jsonwebtoken` (already a dependency, `backend/pubspec.yaml:13`), i.e. a token that is *valid in every way except time*. |
| A33 | `POST /auth/refresh` `{R1}` → 200 (yields `R2`); `POST /auth/refresh` `{R1}` again → **401** `refresh_reused`; then `POST /auth/refresh` `{R2}` → **401** `refresh_invalid` | 200, 401, 401 | the three codes above | **replayed token** — and the third call is the one that matters: it proves the *family* was revoked (`postgres_auth_repository.dart:287-290`), not merely the replayed token rejected. |
| A34 | `POST /auth/email/otp/request` for `lock-<nonce>@…`, then 5 verifies with a code derived from `devCode` (first digit +1 mod 10, so it can never accidentally be correct) | 400 ×4 then 400 | `otp_invalid` ×4, then `otp_locked`; a 6th attempt also `otp_locked` | **rate-limit / lockout** (`maxAttempts = 5`, `postgres_auth_repository.dart:18, 238-245`) |
| A35 | `GET /appointments/{id}` with **consumer B's** bearer | **403** | `error == "forbidden"` (not 404) | **cross-tenant → 403** (`backend/routes/appointments/[id]/index.dart:23-25`) |
| A36 | `POST /appointments/{id}/accept` with a **bystander pro's** bearer (a second registration, salon left draft) | **403** | `error == "forbidden"` | **cross-tenant → 403**, and the guard *order*: scope is checked before state (`pro_appointment_service.dart:143-147`), so a confirmed booking still answers 403 and not 409 — the difference between "not yours" and "already done" must not leak. |

> Both cross-tenant assertions use a genuine second tenant (a bystander), per the
> T59 precedent quoted in `docs/BACKEND.md:224`.

### Phase 6 — the consumer leaves

| # | Request | Status | Body invariant | A failure in production means |
|---|---|---|---|---|
| A37 | `POST /appointments/{id}/cancel` (consumer bearer) | 200 | `status == "cancelled"` | Clients cannot cancel; every no-show becomes a manual phone call. |
| A38 | `GET /availability` (same args as A22) | 200 | `slots` contains `s0` again | A cancelled booking keeps holding the slot (`slot_service.dart:398` skips cancelled) — the salon's day silently fills with ghosts. |
| A39 | `POST /appointments/{id}/cancel` again | **409** | `error == "invalid_state"` | Terminal states are not terminal. |
| A40 | harness self-check | — | `stepsCompleted == 39` | See §4.4 — the anti-vacuity guard. |

### Phase 7 — the salon is suspended (extra, taken)

Row 82 ships **four** vocabularies and phases 1–6 execute three. This phase
executes the fourth, and proves the asymmetry Decision A turns on.

| # | Request | Status | Body invariant | A failure in production means |
|---|---|---|---|---|
| A41 | `POST /admin/auth/login` `{email: $ADMIN_EMAIL, password: $ADMIN_PASSWORD}` | 200 | an admin token pair | The staff door is shut, so nothing below can run — and no salon can ever be suspended, which is the platform's only lever against a bad actor. |
| A42 | `POST /admin/providers/{SALON}/suspend` `{reason}` (admin bearer) | 200 | the salon's `status == "suspended"` | Suspension is not enforceable: a salon the platform has decided to stop keeps taking money. |
| A43 | `GET /providers/{SALON}` (anonymous) | **404** | body exactly `{"error":"not_found"}` | A suspended salon stays publicly readable — the same T51 oracle A8 guards, reached from the other direction (draft never-published vs live-then-stopped). |
| A44 | `POST /appointments` `{providerId: SALON, …}` (consumer bearer) | **409** | `error == "provider_suspended"` — **not** `provider_not_published` | The client is told the salon "has not published yet" about a salon that traded yesterday. Row 82 exists because one code carried both states and every client said the wrong thing. |
| A45 | `POST /appointments` with `providerId` = the **bystander's draft** salon | **409** | `error == "provider_not_published"` | Paired with A44: a server that answers one code for everything passes one of these and fails the other. This is what makes A44 non-degenerate. |
| A46 | `POST /appointments/manual` (pro bearer of the **suspended** salon) | **409** | `error == "provider_suspended"` | **Decision A, half one.** A suspended salon must not write its own calendar either — suspension that only stops clients is not suspension. |
| A47 | `POST /appointments/manual` (pro bearer of the **bystander's draft** salon) | **2xx** | the booking is created | **Decision A, half two, and the one that makes A46 mean something.** A salon that has not published yet *owns its calendar*. If this reddens, someone folded the two states together and quietly took the calendar away from every salon still onboarding. |

> A46 + A47 are the executable form of `salon_visibility.dart:74-78`'s comment —
> « `bookManual` deliberately does NOT call this » — which is today asserted only
> in unit tests against an in-memory repository.

**Totals:** 47 assertions, ~55 HTTP requests, 5 identities (1 pro, 1 bystander
pro, 2 consumers, 1 admin) and 1 throwaway email for the lockout.

---

## 4. How each assertion is made falsifiable

The house rule is that a gate is **watched red before it is trusted green**. For a
40-assertion suite, "watch it red" needs to be a procedure, not a vibe.

### 4.1 The mutation ledger (step ① of the build)

Before the harness is wired into CI, each assertion is proven capable of failing
by applying a **one-line mutation to production source**, running the funnel
locally against `dart_frog dev` + a local Postgres, and recording the observed
failure message in this section. A mutation that leaves the suite green is a
defect *in the suite*, and blocks the PR.

| Mutation (revert after observing) | Turns red |
|---|---|
| `backend/routes/health.dart:15` → `'status': 'okay'` | A1 |
| `migrations.dart:856` `seedProvidersIfEmpty` → `return;` first line | A2 |
| `migrations.dart:1088` skip `seedLocalitiesIfEmpty` | A3 |
| Delete the `AUTH_METHODS` gate at `routes/auth/otp/request.dart:16-18` | A4 |
| `dependencies.dart:99` → `_isProd => true` | A5 (no `devCode`) |
| `provider_auth_repository.dart:363` → `consume: true` | A7 (register can no longer reuse the code) |
| `salon_visibility.dart:42-43` → the SHOW form `salon['status'] == 'active'` | ~~**A2, A8, A20 together**~~ → **nothing, correctly.** ✗ This row was wrong. `providers.status` is `NOT NULL DEFAULT 'active'` (0 of 4 seeded rows null, measured) and `postgres_providers_repository.dart:669` folds `?? 'active'` on top, so against Postgres HIDE and SHOW agree on every value the system can produce. They diverge only on a fourth status nothing can create. The status-less document is the **in-memory** repository's, and `salon_visibility_test.dart` is its only possible guard — no live-server test can reach it (§8) |
| `slot_service.dart:59` → drop `requireVisibleSalon` | A9 |
| `booking_service.dart:59` → skip `clientBookingRefusal` | A11 |
| `salon_provisioning_service.dart:114` → `services < 1` | ~~A12~~ → **nothing — a NO-OP mutation.** ✗ This row was wrong too: A12 runs with *zero* services, so `0 < 1` still adds the key, and A17 runs with three, so `3 < 1` is still false. The mutation cannot change behaviour anywhere in this funnel. `services < 0` would have been the mutation that bites |
| `salon_provisioning_service.dart:154` → `subs = null` | A12, A17 |
| `salon_provisioning_service.dart:150` → move `publishGate` after the active early-return | A12/A17 (the gate stops gating) |
| `booking_service.dart` total → read `body['totalPrice']` | A23 |
| `slot_service.dart:398` → stop skipping non-cancelled bookings | A24 (slot never consumed) |
| `booking_service.dart:135-142` → drop the `isAtSameMomentAs` check | A25 |
| `pro_appointment_service.dart:40` `accept` `from:` → `{'pending','confirmed'}` | A28 |
| `appointment_enrichment.dart` → return the row unchanged | A29 |
| `principal.dart:17` → `JWT.decode` instead of `verifyAccessToken` | A31, A32 |
| `postgres_auth_repository.dart:287` → remove the family `DELETE` | A33 (third call) |
| `postgres_auth_repository.dart:18` → `maxAttempts = 999` | A34 |
| `routes/appointments/[id]/index.dart:23` → drop the ownership check | A35 |
| `membership_service` `journalScope` → always `all: true` | A36 |
| `appointment_lifecycle_service.dart:36` → empty `_terminal` | A39 |

Every row is a real defect someone could ship. The ledger is pasted into this
spec (§4.5, filled during the build) with the actual failure text, so a reader can
see both that it fails and *how legibly* it fails.

### 4.2 Paired assertions instead of one-sided ones

Wherever a rule has two sides, both are asserted, so no single degenerate server
can pass: A8/A20 (closed vs open), A22/A24 (slot present vs consumed),
A24/A38 (consumed vs released), A27/A28 (transition vs re-transition),
A35–A36/A26–A27 (refused for a stranger vs allowed for the owner). A server that
answers 404 to everything, or 200 to everything, fails at least one half of each
pair.

### 4.3 Set equality, not containment

A12 and A17 assert the `missing` list as an exact set. `contains` would stay green
while a check silently disappeared — the failure mode that motivates the whole
slice.

### 4.4 The anti-vacuity guard

Two belts:

1. **A40**: the harness counts completed steps and asserts the total. A harness
   that early-returns, or whose arrange phase silently skipped the funnel, fails
   here rather than passing with three assertions.
2. **Fail-closed on configuration.** The harness reads `SMOKE_BASE_URL` and
   **throws** when it is absent. It does **not** use the `skip:` pattern of
   `backend/test/db/postgres_repositories_test.dart:23-31`, because
   green-because-skipped is a failure this project has logged twice already
   (`docs/ROADMAP.md:119`, `:98`).

### 4.5 Observed-red ledger

*(Filled during step ① — one row per mutation with the verbatim failure line.
The PR does not go up with this section empty.)*

### 4.6 One red run on CI, not just locally

After the local ledger, a single throwaway commit on the branch carries one
mutation so the **job itself** is watched red in Actions, proving the gate fails
in the environment it will guard, with a readable message. The commit is then
reverted.

**The mutation this section originally named cannot serve.** It said
`salon_visibility.dart` → SHOW form, on the belief that seeded salons carry a
NULL status. They do not (§4.1, corrected) — that mutation is a no-op against
Postgres and the suite stays green, correctly. Using it here would have
"proved" the gate works by watching it *not* fail.

**Substituted:** `postgres_auth_repository.dart:18` → `maxAttempts = 999`,
which removes the OTP lockout. It is one of BACKEND.md §5's six *required*
security categories and a defect someone could genuinely ship.

**Observed red in Actions:**
<https://github.com/Zaslons/myweli/actions/runs/30938657792> — job
`Backend — boot smoke + funnel e2e`:

```
❌ Phase 5 — the refusals (BACKEND.md §5 required list) A34 OTP lockout (failed)
   no lockout after 6 wrong codes — the OTP is brute-forceable
   (maxAttempts = 5, postgres_auth_repository.dart:18)
```

Legible without opening the source, which is the other half of what §4.6 is
checking. The commit was then reverted.

**And the FIRST attempt at this run went red for the wrong reason, which is the
best argument for doing it at all.** The job died in the boot step with
`curl: (22) 404` before the funnel ran: the old smoke ended with a phone-OTP
round-trip against `/auth/otp/request`, and `AUTH_METHODS=google,apple,email`
now answers that 404 — `curl -fsS` exits 22 on a 404. The wiring commit had
claimed the existing curl checks "stay: they are the boot proof". True of
`/health`, `/providers` and `/localities`; false of that one, which was an
*auth* proof that passed only because CI ran a configuration production does
not. Removed in `45ffc25`. A local-only red would never have found it.


---

## 5. Where it runs — decision

### 5.1 Extend `backend-boot-smoke`. Do not add a job.

**Decision: extend the existing job in place** (same job id `backend-boot-smoke`).

- The funnel must run against **the same binary the boot smoke already builds** —
  that is the entire point of using the production build path. A second job would
  have to rebuild it.
- The measured setup cost is 44 s of the job's 53 s (containers 21 s + Dart 7 s +
  pub 2 s + CLI 5 s + build 9 s). A second job pays all of it again for zero extra
  signal, and doubles the number of servers that can hang.
- B10's lesson: fewer gates that mean something. Two overlapping smoke jobs is how
  you get a red nobody reads.

Changes to the job:

| Change | Why |
|---|---|
| `env: AUTH_METHODS: google,apple,email` | Mirror `render.yaml:58-59` so CI stops proving a configuration production does not run. `ENV=dev` keeps the prod fail-fast paths inert (`dependencies.dart:166-210`), so nothing new is required. |
| `timeout-minutes: 10` | Today a hang costs up to the 6-hour default; the job's p95 is ~1 min. |
| Readiness loop gets an explicit failure arm | `.github/workflows/ci.yml:183-189` currently falls through silently. `echo "server never answered /health in 30s"; exit 1`. |
| The 11 inline `curl`/`grep` checks are **replaced** by the harness | A1–A3 subsume the old health/providers/localities checks structurally; A4–A10 replace the phone-OTP round trip with the email one production actually uses. Nothing is lost. |
| Job display name → `Backend — boot smoke + funnel e2e` | Reality. The **job id stays `backend-boot-smoke`**; branch protection is off (`docs/ROADMAP.md:258`), so no required check breaks — but the id is what any future protection rule would name, so it does not move. |
| `trap cleanup EXIT` kept, plus `kill -9` fallback | A server ignoring SIGTERM currently hangs the step. |

### 5.2 The harness is Dart, not bash

**Decision: a `package:test` file driving real HTTP.**

Bash + curl + grep is what produced the five weaknesses in §2.3. Dart buys, with
**zero new dependencies** (`http: ^1.2.0` and `dart_jsonwebtoken: ^2.14.0` are
already dependencies, `test: ^1.25.0` a dev dependency — `backend/pubspec.yaml`):

- decoded-JSON assertions (kills substring matching);
- explicit status-code assertions **with the body printed on failure** (kills the
  `curl -fsS` blindness);
- one named test per assertion → GitHub shows *which* invariant died;
- the ability to mint the A32 expired token with the server's own JWT library;
- a typed client helper shared by all 40 steps.

### 5.3 Where the file lives

**Preferred:** `backend/tool/smoke/funnel_smoke_test.dart` (+ `_client.dart`),
i.e. **outside `backend/test/`**, so the backend job's bare `dart test`
(`.github/workflows/ci.yml:118-121`) never collects it and the harness can be
fail-closed instead of skip-guarded. Run in CI as:

```sh
dart test tool/smoke/funnel_smoke_test.dart --reporter expanded
```

> ⚠️ **Unverified assumption, spike it first (≤10 min):** that `dart test` accepts
> a path outside `test/`. If it does not:
> **Fallback:** `backend/test/smoke/funnel_smoke_test.dart` with `@Tags(['smoke'])`,
> a **new** `backend/dart_test.yaml` declaring the tag (there is none today —
> `@Tags(['postgres'])` on `backend/test/db/postgres_repositories_test.dart:1` is
> currently undeclared), the backend job changed to
> `dart test --exclude-tags smoke`, and the smoke job to `dart test --tags smoke`.
> The fallback costs one config file and one edit to a green job; both are
> acceptable, but the preferred layout keeps the two suites physically apart.

Either way the file **must not** live in `backend/test/` unguarded: a suite that
needs a running server would fail (or worse, skip) in the unit job.

---

## 6. Seed prerequisites, and whether the smoke publishes a salon itself

### 6.1 What the seed gives us for free

`initializeDatabase()` runs migrations + `seedProvidersIfEmpty` +
`backfillCatalogueIfNeeded` + `seedLocalitiesIfEmpty` +
`backfillSalonMarketIfNeeded` inside the server process
(`backend/lib/src/dependencies.dart:735-745`). Four salons
(`provider1`–`provider4`), all public (they carry **no** `status` key; the column
defaults to `'active'` and `isPublicSalon` is written in the HIDE form —
`salon_visibility.dart:34,42-43`), each with services and Mon–Sat 09:00–18:00
hours. **No consumer users, no pro accounts, no memberships, no subscription
rows.**

### 6.2 The decision: seeded data for the anonymous reads, a self-made salon for the funnel

**Yes — the smoke registers *and publishes its own salon*, and it must.** Three
reasons, in order of force:

1. **The seeded salons have no pro account and no membership row.** `GET /appointments`
   with a pro bearer resolves the salon from the token's memberships
   (`membership_service.dart:68-86`); for `provider1` there is nothing to resolve.
   A27's accept is therefore **impossible** against seeded data — and accept is the
   hop the whole funnel exists to prove.
2. **Publishing a seeded salon is not even possible.** `publish()` evaluates
   `publishGate` at `salon_provisioning_service.dart:150` **before** the idempotent
   already-active early-return at `:160`, so `POST /providers/provider1/publish`
   answers `409 incomplete` with `missing: [services, photos, offer]` — for a salon
   that is live and bookable. **Do not** add a publish call for `provider1` and
   **do not** read that 409 as evidence of anything.
3. **Draft is where row 82 lives.** A freshly registered salon is `draft`
   (`providers_repository.dart:700-748`), which hands us A8/A9/A11 for free.

So: A1–A3 use the seed (proving migrations + seed ran on real Postgres); A4–A39
run on a salon the smoke creates, completes, funds with an offer and publishes.

### 6.3 What the smoke must set up, explicitly

| Prerequisite | How | Note |
|---|---|---|
| Pro identity | email OTP (`/auth/provider/email/otp/request`) + register | `phoneNumber` is **required** and E.164 (`routes/auth/provider/register.dart:33-38`) |
| Locality | `areaId: "cocody"` at register | Stamps commune/city/timezone/currency; without it `profile` can never pass |
| Profile | `PATCH /providers/{id}` `{description, latitude, longitude}` | `description` empty is what keeps `profile` in A12's set; lat/lng are validated as a **pair** (`provider_catalog_service.dart:232-241`) |
| 3 services | `POST …/services` ×3 | Threshold is `< 3` (`salon_provisioning_service.dart:114`) |
| 3 photos | `PUT …/gallery` | `_allowedImageOrigins` is empty when `R2_PUBLIC_BASE_URL` is unset → any URL is accepted in CI (`provider_catalog_service.dart:336-339`) |
| Hours | `PUT …/availability`, **all seven days open** | Deliberately unlike the seed (Mon–Sat): opening `"0".."6"` removes the Sunday-closed trap from every date calculation for good |
| Offer | `PUT …/subscription {tier:"pro"}` | Starts the salon's one trial; without it publish returns `missing:["offer"]` |
| **Not** needed | `ADMIN_EMAIL` / `ADMIN_PASSWORD` | No admin hop in Q1 → suspension is out of scope (§8). Adding them is Open Question 2. |
| **Not** needed | KYC | Only `depositRequired: true` needs a verified account (`provider_catalog_service.dart:554-558`); Q1 leaves deposits off. |

### 6.4 Data hygiene

The Postgres service container is created and destroyed per run, so the funnel
starts from an empty database every time and leaves nothing behind. Identities
still carry a per-run nonce (`GITHUB_RUN_ID` or a timestamp) so the same harness
can be pointed at a long-lived local database without colliding — and so a
developer's second local run does not trip the OTP resend budget.

---

## 7. Runtime budget and flake control

### 7.1 Budget

**Measured locally against the AOT binary on real Postgres** (the CI numbers
land here after the first branch run — see the note below):

| | Before Q1 | Measured now | Hard stop |
|---|---|---|---|
| `dart compile exe` (new) | — | **7.8 s** | — |
| Server boot | ~7 s (JIT) | **3 s** (AOT — *faster* than JIT) | — |
| The 47 funnel cases | — | **1.5 s** | — |
| Job total | 53 s | **≈ 63 s expected** | `timeout-minutes: 12` |

So the whole slice costs about **ten seconds**, against a 90 s allowance for the
compile alone. AOT was expected to be the dominant new cost and is not: it also
*halves* boot time, which pays part of itself back. The job stays roughly an
order of magnitude under the run's critical path (APK size, 8 m 14 s), so it
never becomes the thing anyone waits for.

### 7.2 Flake control

- **Retries stay at 0**, everywhere, per B10 (`docs/design/web-b10-flake.md`). A
  red is information; a retry destroys it. If the funnel flakes, the cause is
  fixed or the assertion is deleted — never re-run.
- **No sleeps** except the existing boot poll. Every assertion is a
  read-your-own-write against one process and one pool; there is no eventual
  consistency to wait on.
- **Never assert on notifications.** `BookingNotifier` is fired with `unawaited`
  (`backend/routes/appointments/[id]/accept.dart:27-33`) — it is the one genuinely
  racy surface in the funnel, and it is out of scope for exactly that reason.
- **No clock ambiguity.** `TZ: UTC` job-wide (`ci.yml:14-15`); the salon timezone
  resolves to Africa/Abidjan = UTC+0. `D` is computed **once** and reused, so a
  run straddling midnight cannot use two different days.
- **No weekday roulette.** All seven days are opened (§6.3), so the seed's
  Sunday-closed trap cannot bite; `D = today + 7 days` clears the 60-minute
  minimum notice and sits far inside the 365-day horizon.
- **The booked instant is never hand-built.** `s0` is taken verbatim from the
  `/availability` response, because the server compares by `isAtSameMomentAs`
  (`booking_service.dart:135-142`) and any hand-formatted ISO string is a coin
  flip.
- **The wrong OTP code is derived from the right one** (first digit +1 mod 10), so
  A34 cannot accidentally guess a valid code (1 in 900 000 is not zero, and CI
  runs a lot).
- **Unique identities per run** (§6.4) so nothing depends on the database being
  pristine.
- **No network egress at all**: `LogEmailProvider` (no `RESEND_API_KEY`), log
  messaging (no Twilio creds), FCM and R2 unset. **Twilio is never touched, and A4
  asserts the SMS door is shut.** Cost of a run: $0.
- **Legible failures**: one named test per assertion; the response body is printed
  on every non-matching status; the server log is still dumped by the `EXIT` trap
  (which fires on green runs too — its presence is not a failure signal).

---

## 8. What this does NOT cover — plainly

Stating this precisely is part of the deliverable, because the ROADMAP rewrite
(§9) must not replace one false sentence with another.

1. ~~**Not the production binary.**~~ **Now covered — the AOT extra was taken.**
   The job compiles with `dart compile exe bin/server.dart -o bin/server` inside
   `build/`, exactly as `backend/Dockerfile:25-27` does, and runs the funnel
   against that executable. What remains uncovered is the **image**, not the
   binary: production copies it into a `scratch` base with a separate runtime
   layer (`Dockerfile:29-32`), and Q1 does not build or boot that container. A
   missing shared object in `scratch` would still reach production.
2. **Not production configuration.** `ENV=dev`, no Resend, no Twilio, no FCM, no
   R2, no `WEB_ORIGINS`, no `CRON_SECRET`. The prod fail-fast branches
   (`dependencies.dart:166-210`) never execute. Real OTP email/SMS, WhatsApp
   confirmation, the reminder cron, R2 uploads and push remain **manual** Phase G
   checks (`docs/DEPLOYMENT.md:194-199`).
3. **Not migrations against existing data.** The DB is empty at every run, so
   `seedProvidersIfEmpty`/`backfillCatalogueIfNeeded` take their *first-boot*
   branches. The risk that actually bites a deploy — a migration meeting a
   populated table — is untested here.
4. **Not the `suspended` state**, and no admin routes at all (no `ADMIN_EMAIL`).
   `provider_suspended` stays covered in-process only
   (`backend/test/appointments/salon_state_refusal_test.dart`).
5. **Not deposits, KYC, reviews, favourites, artists, team invitations,
   multi-salon, clients/notes, earnings, dashboard, journal, notifications,
   uploads, cron.**
6. **Not reschedule** (either role), **not pro manual booking**, and not
   `complete` / `no-show` / `arrive` / `reject`.
7. **Not a race.** A25 proves the double-booking *guard*, sequentially. Two
   simultaneous bookings of one slot are a concurrency question Q1 does not ask.
8. **Not a contract test.** Assertions are hand-written invariants; nothing
   validates responses against `docs/api/openapi.yaml`. BACKEND.md §5's "Contract
   tests" bullet is untouched by this slice.
9. **Not performance.** No latency or payload assertions.
10. **Nothing client-side.** Neither Flutter app nor the Next.js BFF is exercised;
    `web/tests/e2e/` stays hermetic against its stub
    (`web/playwright.config.ts:7`). The new count must **not** be folded into the
    web suite's "168 e2e" figure.
11. **Green here does not mean green in prod.** It means: this build serves this
    funnel against a real Postgres under dev configuration.

---

## 9. Docs to rewrite in the same PR

The stale sentences, quoted, with the fix:

1. **`docs/ROADMAP.md:191`** — the sentence this slice exists to kill:
   > "- **Quality** — **no E2E/integration tests vs a real backend** (unit/handler only); low-end-Android **perf pass** (budgets); **release hardening** (obfuscation, no debug logs, APK size); store **data-safety** disclosures."

   Rewrite: name the funnel e2e, and scope it honestly with §8's limits (CI only,
   dev config, JIT build, empty DB). Keep the perf/hardening/data-safety items —
   they are still true.

2. **`docs/ROADMAP.md:189`** — same bullet block, **already false today**:
   > "- **Deployment/infra** — none in repo (no Dockerfile/host config); backend never run vs real Postgres/R2. The critical path to \"on.\""

   `backend/Dockerfile` and `render.yaml` exist (and ROADMAP:87 already says so),
   and the backend has run against real Postgres in CI since `ci.yml:123`. Fix in
   the same edit or the block contradicts itself. Keep "never run vs real **R2**"
   — that half is still true.

3. **`docs/ROADMAP.md:373`** — the boot-smoke bullet, which now describes the
   wrong thing (it advertises the phone-OTP round trip A4 will close):
   > "- 🟡 **Server boot smoke (CI):** … `/health` → ok, `/providers` → seeded data, and an OTP request→verify **auth round-trip** → tokens."

   Rewrite as the funnel bullet; state that the auth round trip is now the **email**
   path, under the launch `AUTH_METHODS`.

4. **`docs/ROADMAP.md:425`** — the test-pyramid's Backend row, which has no e2e:
   > "| **Backend** | stack-dependent | Unit, API contract, **load** (slot engine, payment callbacks), **security** (authz, rate limits) | Gates Phase 3/4 |"

   Add the funnel-e2e layer. **Do not touch `:422`** ("Integration / E2E … Full
   flows on mocks") or `:275`/`:258` — those are the *Flutter* pyramid and an
   emulator-job deferral; overwriting them trades one false sentence for another.

5. **`docs/ROADMAP.md:81`** — stale headline counts inside §1.8:
   > "**109 PRs merged · 224 backend + 296 mobile tests · analyze 0.**"

   The newest entries say "622 tests backend · 1205 mobiles · 555 web + 168 e2e"
   (`:89`). We are editing §1.8 anyway (the DoD requires a slice refresh); do not
   copy the stale numbers forward. *(Whether to fully refresh them here or in a
   separate hygiene PR: Open Question 6.)*

6. **`docs/BACKEND.md:136-147`** — §5 has **five** layers and no home for this:
   > "- **Unit** … - **Handler tests** … - **Contract tests** … - **Security / negative tests (required gate)** … - **Load tests** … - Coverage must not decrease."

   Add a sixth bullet defining the layer (a live-server funnel e2e in CI: what it
   covers, what it does not, when a PR must keep it green). **Carry the Load and
   Coverage lines forward unchanged** — they are easy to drop in a restructure.
   Note in the same bullet which of the six required security categories the e2e
   now also proves over HTTP (A30–A36) — the in-process tests remain the primary
   gate.

7. **`docs/BACKEND.md:149-162`** — §6 DoD has no e2e checkbox. Recommendation:
   **do not add one** (it would be a lie on most PRs); CI enforces it
   automatically. Open Question 7 if the user disagrees.

8. **`docs/BACKEND.md` §7 threat model** — precedent T38 (`:213`) records e2e
   coverage in the mitigation prose *and* the status cell ("Implemented (R1,
   tested E2E in R2b)"). Candidate rows the funnel now proves end to end: **T50/T51**
   (A8/A9/A11/A20), **T54** (A17–A19), **T55/T40** (A36), **T5** (A26). Row numbers
   and titles are verified against the live table before editing — the DoD box
   "Threat model updated **if** the PR adds an endpoint or trust boundary" does not
   strictly apply (Q1 adds neither), so this is an accuracy improvement, not a gate.

9. **`docs/design/salon-state-and-refusals.md:352-366`** — the three "Verified
   against a running server" prose tables, hand-typed after a manual session.
   Cross-link them to A8/A9/A11 and note that the table is now executed on every
   PR. *(The prose stays: it is the reasoning; the harness is the proof.)*

10. **`docs/design/README.md`** — index row for this spec (status `Draft` →
    `Built` when it lands).

11. **`backend/README.md`** — "## Quality gates (match CI)" lists only
    format/analyze/`dart test`. Add how to run the funnel locally (start Postgres,
    export `DATABASE_URL`/`JWT_SECRET`/`AUTH_METHODS`, `dart_frog dev`,
    `SMOKE_BASE_URL=http://localhost:8080 dart test tool/smoke/…`), including the
    warning that `dart_frog dev` keeps serving the last good build when new code
    fails to compile.

12. **`docs/DEPLOYMENT.md:194-199`** — Phase G: note which of its steps CI now
    proves for free and which still require the paid, manual pass (§8.2).

---

## 10. Definition of done

- [ ] Spec approved before code (this document).
- [ ] Mutation ledger §4.5 filled with observed red output; §4.6 records the CI red run.
- [ ] `dart format` clean · `dart analyze --fatal-infos --fatal-warnings` = 0 (the harness is analysed like any other source).
- [ ] Backend suite unchanged and green; the harness is **not** collected by the backend job's `dart test`.
- [ ] Smoke job green, timed, and the measured numbers written back into §7.1.
- [ ] No new dependency; no new env var beyond `AUTH_METHODS` (a non-secret, mirroring `render.yaml`); no secret added; gitleaks clean.
- [ ] Docs in §9 rewritten in the same PR.
- [ ] Feature branch + PR; no Claude attribution.

---

## 11. Open questions

1. **Job display name.** Rename to `Backend — boot smoke + funnel e2e` (id stays
   `backend-boot-smoke`)? Recommended yes; branch protection is off
   (`ROADMAP.md:258`) so nothing breaks.
2. ~~**Suspension coverage.**~~ **DECIDED: taken, in this PR** (against the
   spec's own recommendation to defer). It is Phase 7 (A41–A47), and it grew
   beyond the "+3 hops" estimate: completing row 82's table honestly needs the
   *paired* assertions too, because a server answering one code for everything
   would otherwise pass. A45 pairs the suspended refusal against a draft one, and
   A46/A47 execute Decision A's asymmetry — which until now existed only as a
   comment plus in-memory unit tests.
3. **Staging.** Should the same harness ever run against the deployed Render
   instance (catching real config drift)? **Recommendation: no** — it would need
   real credentials, would write real rows, and could spend real SMS. Q1 stays
   CI-only.
4. ~~**File placement spike.**~~ **Settled — measured, not assumed.**
   `dart test tool/smoke/spike_test.dart` collects and runs a file outside
   `test/` (`+1 All tests passed`), and a bare `dart test` does **not** collect
   it (grep for a unique marker over the full 622-test run: 0 hits). So the
   preferred path in §5.3 holds and the `dart_test.yaml` + `@Tags` fallback is
   not needed. The harness can be fail-closed rather than `skip:`.
5. ~~**AOT parity.**~~ **DECIDED: taken, in this PR.** The funnel runs against
   the compiled executable. §7.1's budget absorbs it and §8.1 now states the
   narrower residual gap: the binary is covered, the `scratch` image is not.
6. ~~**ROADMAP stale counts.**~~ **DECIDED: the full hygiene pass lands here**,
   including the two claims already false before this slice (`:81`'s counts and
   `:189`'s "backend never run vs real Postgres").
7. **BACKEND.md §6 DoD**: add an e2e checkbox, or leave it CI-enforced (§9.7)?
8. **`GET /health` and readiness.** `/health` is liveness only — it does not touch
   the database (`backend/routes/health.dart`). A Render health check therefore
   reports "up" for a server whose pool is dead. Adding a readiness endpoint would
   be a **product surface change** and is deliberately out of scope here; flagged
   because Q1's boot poll is the place the gap becomes visible.

---

## 12. Known conflicts and unknowns in the source material

Stated rather than smoothed over, per the brief:

- **Phone OTP: enabled or dormant?** Both surveys are right about different
  environments. `AuthMethods.defaults` includes `phone`
  (`auth_methods.dart:21` — `defaults = {'google','apple','email','phone'}`,
  and `:10` says unset → defaults) and the smoke job sets no `AUTH_METHODS`, so
  **CI runs with phone on**. `render.yaml:59-60` declares the key `sync: false`,
  meaning **the value lives in the Render dashboard, not in the repo** — what the
  file carries is the comment at `:58`, « AUTH_METHODS=google,apple,email
  (phone-OTP dormant — SMS too costly) », which documents the intent rather than
  setting it. So production's actual value is **not verifiable from this
  repository**, and that is itself worth knowing: A4 asserts CI matches the
  documented intent, and nothing here can assert what Render is really serving.
  The current smoke's only auth assertion exercises a route the documented
  production config 404s. §5.1 + A4 resolve the CI half.
- **"CI already proves an anonymous phone OTP round-trip"** (seed survey) — true
  today, deliberately false after this slice. `ROADMAP.md:373` must be rewritten
  accordingly (§9.3).
- **The PR1c/PR1d curl script.** Reconstructed into a session-scoped scratchpad
  that is **not durable**; it is not an artifact this spec depends on or cites as
  a location. Its knowledge (session shapes, `providerId` vs `id`,
  `appointmentDateTime` vs `appointmentDate` vs `newDateTime`) is encoded in §3.
- **`dart test` outside `test/`** — unverified; §5.3 carries an explicit fallback.
- **Per-request latency on the runner** — unmeasured. §7.1 sets the budget from the
  measured 6 s step and requires a re-measure on the first branch run.
- **Deposit-policy field asymmetry** (`mobileMoneyOperator` in, `depositMobileMoneyOperator`
  out) and the fraction-vs-percentage trap: real, documented by the surveys, and
  **not exercised** by Q1 because deposits are out of scope (§1.4). Noted so a
  future slice does not rediscover it.
