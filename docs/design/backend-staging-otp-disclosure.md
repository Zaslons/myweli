# Staging stops handing out OTP codes — design spec

| | |
|---|---|
| **Status** | Built |
| **Owner** | Sadreddine Daher |
| **Last updated** | 2026-08-18 |
| **PRD ref / phase** | security hardening · V1 (launch gate) |
| **ROADMAP entry** | see the `🟢` entry dated 2026-08-18 |
| **Skills checked** | myweli-backend-guardrails · myweli-web-guardrails |
| **Related** | [backend-q1b-smoke-seam.md](backend-q1b-smoke-seam.md) · [infra-staging.md](infra-staging.md) §1.1 · [LAUNCH.md](../LAUNCH.md) §4 |

## 1. Goal & scope

**Found while preparing the Vercel preview split** (LAUNCH.md §5.4): the staging
API is publicly reachable and returns OTP codes inline for **any** address.

```
POST https://myweli-api-staging-…run.app/auth/email/otp/request
{"email": "someone-elses@gmail.com"}
→ 202 {"expiresInSeconds": 300, "devCode": "418306"}
```

Three facts compose into it, each defensible alone:

| Fact | Where |
|---|---|
| staging is open to the internet | `ingress: all`, IAM `allUsers` → `roles/run.invoker` |
| off-prod echoes the code | `devCode: _isProd ? null : code` — `postgres_auth_repository.dart:93` and three siblings |
| ~~staging sends real mail from the launch domain~~ **it does not** | `RESEND_API_KEY` is the placeholder `re_staging_placeholder_delivery_is_disabled` (`90-staging.sh:213`) — non-empty enough to satisfy the boot guard, deliverable to nobody |

And the hostname is **already public**: `infra/gcp/service-staging.yaml:190`, in a
public GitHub repository. Nothing about this was waiting to be discovered.

So anyone who wants a session on staging, as any identity, can have one.

**A correction, because the first draft of this spec overstated it.** It said the
caller could also make MyWeli mail an arbitrary address from
`no-reply@myweli.com`, and called that the serious half. That is **false**: the
key is a deliberate dud, verified by hashing the live secret against the
committed placeholder. Nothing is delivered and the launch domain is not exposed.
The exposure is the disclosure alone — real, but smaller than claimed. Corrected
here rather than only in conversation, because this is the document that argues
for the fix.

**And the dud key is not incidental — it is the trade this change makes.**
`90-staging.sh:207-212` chose an undeliverable key *because* of the echo: "sign-in
still works: `ENV=staging` is not `isProd`, so the OTP is echoed in the response
and nothing needs to arrive." Remove the echo and that sentence stops being
true (§5).

**In scope:** stop the disclosure on every deployed environment.
**Out of scope:** staging's network posture (`ingress: all` is deliberate — the
Vercel preview split needs it) and the R2 upload allowlist (LAUNCH.md §5.4).

## 2. The decision, and the assumption that expired

`boot_config.dart`'s `Env` enum states the current behaviour as a **deliberate
choice**, with a reason:

> · it needs dev's OTP dev-code echo (`!isProd`), because staging runs with no
>   SMS channel and there would otherwise be no way to sign in.

That was true when written. It is **not true now**: staging has a working email
channel (`ResendEmailProvider`, `dependencies.dart:242`) and
`AUTH_METHODS=google,apple,email`. Signing in to staging by email delivers a real
message; Google and Apple never involve an OTP at all. The echo is no longer
load-bearing for anything a human does.

This is the third time this session that a correct decision has been quietly
invalidated by a later change that had no reason to revisit it — the same shape
as the privacy policy's « pas de Sentry » and LAUNCH.md's "staging does not
exist". The countermeasure here is a **test that fails**, not a better comment.

## 3. What changes

`isProd` was answering a question it does not name. `Env` already split
`guardsOn` from `isProd` precisely because one boolean cannot answer two
questions; this is the **third** question hiding inside the second:

- `guardsOn` — *fail fast on missing configuration?* → staging **and** prod
- `isProd` — *is this the real thing?* → prod only
- **`echoesOtpDevCode`** — *may an OTP be returned in an HTTP response?* → **dev only**

The four auth repositories take `isProd` for exactly one purpose — the echo, and
nothing else (verified: `_isProd` has no other reference in any of them). So the
flag is renamed to what it controls rather than reinterpreted, because a flag
whose name and meaning diverge is how this class of defect starts.

```dart
// boot_config.dart
bool get echoesOtpDevCode => this == Env.dev;

// the four repositories
devCode: _echoDevCode ? code : null,
```

**Deployed environments keep exactly one disclosure path: the Q1b seam** — a
constant-time `SMOKE_OTP_SECRET` match (≥32 chars) **and** an identity in the
RFC 2606 `.test` TLD, which is a compile-time constant no environment value can
widen to a real address. That seam was built for production and is now what
staging uses too, which is the correct generalisation: *deployed* is the
property that matters, not *production*.

## 4. Security & threat model

Closes the gap where staging's posture was strictly weaker than production's for
no stated reason. Threat-model delta (BACKEND.md §7):

- **T60** (the smoke seam) is unchanged; its scope widens from prod to every
  deployed environment.
- **There is no email-relay vector**, contrary to this spec's first draft. The
  request still calls the provider, but the provider cannot deliver, so no third
  party can be mailed. If a deliverable key is ever mounted this becomes a real
  open item and must be re-assessed — the send happens before any identity
  check, bounded only by the rate limit at `auth_repository.dart:162`.

## 5. What could break, and why it does not

| Concern | Answer |
|---|---|
| CI funnel smoke | Runs at `ENV: dev` (`ci.yml:155`) — unaffected. |
| Q1b seam CI job | Runs against a real `ENV=prod` server with the secret — unaffected. |
| Signing in to staging by hand | **Google or Apple only.** Email OTP no longer completes — the echo is gone and the Resend key cannot deliver, and those two halves were load-bearing for each other. Phone was already off (`AUTH_METHODS` has no `phone`). A real reduction, accepted deliberately; mount a deliverable key if a human needs the email path, accepting that infra-staging.md §3.3 then no longer holds. |
| Running the funnel **against staging** | Needs `SMOKE_OTP_SECRET` on the service. Not set today, and nothing runs it against staging yet — this becomes a prerequisite of LAUNCH.md §4's "rehearse the funnel on staging". `smoke_target.dart:28` already anticipated the mount. |

## 6. Tests

The guard has to fail for the right reason, so each is written to red first:

- `devCode` is echoed for `Env.dev`, and **not** for `Env.staging` or `Env.prod` —
  across all four repositories, since fixing three of four would look identical
  from any single route test.
- On staging, the seam still discloses for a `.test` identity with the right
  secret, and **denies a real address even with the right secret**.
- A structural test that no auth repository regains a `!isProd`-shaped echo.

## 7. Open questions

1. **Email sign-in on staging is now impossible** (§5). Accepted for now: Google
   and Apple cover a human, the seam covers automation. It becomes a problem the
   first time someone must exercise the email flow end to end on staging — which
   LAUNCH.md §4's "rehearse the funnel on staging" may well require. Fix then by
   mounting a deliverable key, and re-open the relay question in the same
   change.
2. **`SMOKE_OTP_SECRET` on staging** — needed before the funnel can be rehearsed
   there. A cloud change, deliberately not bundled into this PR.
