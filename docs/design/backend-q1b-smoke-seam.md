# Q1b — the funnel smoke can authenticate against production

> Module: **auth**. Closes the gap recorded in
> [`infra-gcp-migration.md`](infra-gcp-migration.md) §8, which blocks cutover
> step 2. Prior art: [`backend-q1-funnel-smoke.md`](backend-q1-funnel-smoke.md)
> (the harness), [`auth-social-email.md`](auth-social-email.md) (the OTP design).

## 1. The gap

`infra-gcp-migration.md` §8 makes the Q1 funnel smoke — 47 assertions over real
HTTP — the acceptance gate for the Cloud Run cutover. **It cannot run against
`ENV=prod` as written.**

The harness signs in by reading the code straight off the OTP response
(`tool/smoke/funnel_smoke_test.dart:172`, `:201`):

```dart
final code = req.json['devCode'] as String;
```

Production deliberately suppresses that field — `auth_repository.dart:224` and
`provider_auth_repository.dart:650` both do `devCode: _isProd ? null : code`,
and the routes omit the key entirely when it is null. Against prod the cast is
a null-cast crash on the first sign-in, before assertion #1.

So the gate we wrote down as "the real acceptance test" has never been runnable
in the environment it was meant to certify. That suppression is **correct** and
is not being weakened here.

## 2. What was rejected, and why

| Option | Verdict |
|---|---|
| A real mailbox loop (inbound domain → worker → poll) | **Rejected for now.** Best security — no production seam at all — but it is a whole inbound-email pipeline to build and operate, and it makes the gate depend on mail-delivery latency. Revisit if the seam ever needs to outlive the cutover. |
| A separate `ENV=staging` service | **Rejected.** Doubles the infrastructure and, more importantly, *does not test the thing we are certifying*. The point of the gate is that **this** revision, with **these** secrets, against **this** database, serves the funnel. |
| Return `devCode` behind a secret header alone | **Rejected.** One leaked secret would be an OTP-disclosure primitive for **any** address, which is full account takeover. |
| **Secret header + a structurally unroutable identity** | **Chosen.** §3. |

## 3. Design — two independent conditions, both required

`devCode` is disclosed in production only when **both** hold:

1. **The caller proves possession of `SMOKE_OTP_SECRET`** via the
   `X-Smoke-Secret` request header, compared in **constant time**.
2. **The identity is structurally incapable of being a real user** — its
   address ends in the **`.test` TLD**.

### 3.1 Why `.test` is the load-bearing half

`.test` is **reserved by RFC 2606 §2** and is guaranteed never to be delegated
in the public DNS. An address there can never receive mail and can never be a
real person's address. That makes the constraint *structural* rather than
conventional: it does not depend on an operator maintaining an allowlist
correctly, and **no configuration mistake can widen it**, because the suffix is
a compile-time constant, not an env var.

This is the difference from the rejected header-only option. If
`SMOKE_OTP_SECRET` leaks entirely, the attacker gains the ability to sign in as
throwaway identities at a domain that cannot receive mail — and nothing else.
They cannot obtain a code for `owner@gmail.com`, because no value of any
environment variable can make that address end in `.test`.

Happy accident worth recording: the harness **already** builds every identity
this way (`funnel_smoke_test.dart:196`, `:384`, `:788`, `:815` — all
`…@smoke.test`), so the constraint costs the harness no change at all. The
design was chosen to fit the existing convention, then the convention was
promoted to an enforced rule.

### 3.2 Why the seam lives in the route, not the repository

The routes already hold `result.code` — they need it to render the email
(`routes/auth/email/otp/request.dart:41-46`). So disclosure needs **no
repository change**: `_isProd ? null : code` stays exactly as it is, and the
route decides whether to echo the code it already has.

That also keeps the layering honest: an HTTP header is a route-layer concern and
`AuthRepository` must not learn about headers. Per BACKEND.md §1 the route
parses and delegates; the decision itself is a pure function it delegates to.

### 3.3 The pure function

`lib/src/auth/smoke_seam.dart`, in the shape `boot_config.dart` established —
raw values in, no `Platform.environment` read, fully testable:

```dart
bool smokeDisclosureAllowed({
  required String? configuredSecret,
  required String? providedSecret,
  required String identifier,
})
```

Returns false — the seam is **absent**, not merely closed — unless all of:

- `configuredSecret` is set and **at least 32 characters**. A short secret is
  treated as no secret, so `SMOKE_OTP_SECRET=test` cannot enable disclosure.
- `providedSecret` matches it under a constant-time compare.
- `identifier` ends in `.test` (case-insensitive).

Default posture is off: with `SMOKE_OTP_SECRET` unset there is no behavioural
change anywhere, which is how production runs except during a cutover.

## 4. Config

| Key | Required | Notes |
|---|---|---|
| `SMOKE_OTP_SECRET` | no | ≥32 chars. Unset → seam absent. Secret Manager; set only while a cutover gate is being run |

Non-prod is untouched: `devCode` is still echoed unconditionally off-prod, so CI
and local development need no secret and behave exactly as before.

**Boot-time visibility.** When the seam is active in production the composition
root logs a warning at boot. A disclosure path that is quietly left on is the
failure mode worth engineering against, and the deploy log is where an operator
would see it.

## 5. Security

**Threat-model delta (BACKEND.md §7) — new entry T60.**

*Spoofing / Information disclosure: the smoke seam discloses an OTP.* Mitigated
by (a) constant-time secret comparison, (b) an identity constraint that no
configuration can widen, (c) a 32-character minimum on the secret, (d) default
absent. Residual risk: an attacker holding the secret can authenticate as
`*.test` identities and exercise the consumer/pro funnel in production. Bounded
by §7.

Unchanged and explicitly **not** weakened: OTPs stay hashed at rest, the TTL,
attempt and resend limits still apply to smoke identities, the response is still
identical for known and unknown addresses (T32, no enumeration), and the code is
still never logged.

## 6. Tests

`test/auth/smoke_seam_test.dart` — the required negative tests come first:

- unset / empty / whitespace secret → absent, even with a correct header
- a **short** secret (< 32) → absent, even when the header matches it exactly
- correct secret + **non-`.test`** identity → refused (the account-takeover case)
- `.test` identity + **wrong** secret → refused
- `.test` identity + **no** header → refused
- correct secret + `.test` → allowed; case-insensitive; sub-domains
  (`x@smoke.test`, `x@a.b.test`) allowed
- a look-alike that is not the TLD (`x@smoke.test.evil.com`) → refused

Plus handler tests on both OTP routes: prod + seam → `devCode` present; prod
without the header → absent; non-prod → unchanged.

> **Scope widened 2026-08-18.** This seam was built as *the production
> OTP-disclosure path*. It is now the disclosure path for **every deployed
> environment**: staging used to echo `devCode` unconditionally, which — being
> `ingress: all` with a hostname in a public repo — meant anyone could obtain a
> code for any address. The gate moved from `!isProd` to `Env.dev` only, so
> staging comes through here exactly as production does. The seam itself is
> unchanged; only what falls through to it. See
> [backend-staging-otp-disclosure.md](backend-staging-otp-disclosure.md).

## 7. ~~Open~~ **Resolved — option 3.** Production data pollution

**Raised here because the migration spec did not consider it.** The funnel
creates a salon, services, staff and bookings. Run against production, that data
lands in the **live database**.

At cutover this is tolerable exactly once — there are no real users yet. As a
*recurring* gate it is not: every run would leave a junk salon discoverable in
search results.

`.test` identities make the residue structurally identifiable, so the options
are open rather than blocked:

1. Run the gate once at cutover, then purge by identity suffix. **Recommended
   for cutover.**
2. Add a `POST /internal/smoke/purge` cron-guarded route that deletes every
   `.test` identity and its cascade.
3. Move the recurring gate to a staging database once one exists.

**Decided: option 3.** Staging now exists (docs/design/infra-staging.md), so the
recurring gate runs against it and the question the cutover deferred is closed.

> **The FUTURE was closed; the PAST was not** (found 2026-08-18 while reconciling
> LAUNCH.md). Option 3 stops new residue. It does nothing about the residue
> already there — and option 1's *"then purge by identity suffix"* was never
> run. Production logs show the seam executing against the live database on
> 2026-08-06: the `SMOKE_OTP_SECRET is set` warning, and three
> `POST /auth/email/otp/verify → 200` in the same windows. Those accounts are
> the ~5 `users` rows the DR rehearsal found in production
> (docs/design/infra-dr-restore.md), and they are why LAUNCH.md §4's
> "production contains no seeded/demo data" is **not** ticked.
>
> Worth naming the shape, because it recurs: choosing a decision that prevents a
> problem reads as resolving it, and the heading was struck through accordingly.
> Prevention and cleanup are two tasks, and only one of them was done.

The decision is enforced in code rather than recorded as an intention.
`backend/tool/smoke/smoke_target.dart` refuses any target that is not a loopback
host or the staging Cloud Run service — **deny by default**, so a production
address is refused by not being on the list rather than by appearing on a
denylist that could go stale. A second layer asks the target what it is:
`GET /health` now reports `env`, and the harness aborts when a permitted-looking
URL turns out to be pointed at a `prod` deployment, which is the case no
hostname rule can see.

**Running the gate against production again is possible and deliberate.** It
takes an edit to that file, reviewed — the same shape as mounting
`SMOKE_OTP_SECRET` into `service.yaml`, which it also still requires (that secret
is not mounted today, so the seam is currently absent from production). There is
deliberately **no environment variable that unlocks it**: an override is the
bypass with extra steps, and the accident this guards against is precisely
someone running the documented command with a copied URL.
