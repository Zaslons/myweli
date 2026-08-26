# Demo review account — a public credential into a sandboxed salon

| | |
|---|---|
| **Status** | Draft — awaiting owner sign-off before any code |
| **Owner** | Sadreddine |
| **Last updated** | 2026-08-26 — §10's questions decided (owner), reset designed |
| **PRD ref / phase** | store submission (mobile-external-testing.md §5.2) · V1 |
| **Related** | [backend-q1b-smoke-seam.md](backend-q1b-smoke-seam.md) (prior art) · [pro-salon-lifecycle.md](pro-salon-lifecycle.md) · [mobile-external-testing.md](mobile-external-testing.md) · BACKEND.md §7 **T69 (new)** |
| **Skills checked** | myweli-backend-guardrails · myweli-verification-guardrails |

## 1. Goal & scope

**Goal.** Both stores require working sign-in credentials when an app is
gated by a login. The Pro app opens to `/pro/login` and shows nothing without
one (`pro_splash_screen.dart:66-69`), and none of its three methods can be
handed to a reviewer: Google/Apple signs the reviewer into a **fresh account**
— the registration funnel, not a dashboard — and the email OTP goes to an
address we control. This is the blocker for TestFlight external review and for
Play's *App access* declaration, which demands credentials that are
**reusable and bypass one-time passwords**.

What is needed: a fixed credential that signs a reviewer into a
**pre-provisioned, populated, permanently-draft salon**.

**In scope:** the Pro-realm seam (one identity, one fixed code), the sandbox
that bounds what the account can do, and the send-skip for `.test` addresses.

**Out of scope, with reasons:**

- **The consumer app needs no seam.** It opens to `/home` and is fully
  browsable signed-out (`splash_screen.dart:36`); a reviewer who needs an
  account can use Sign in with Apple or Google **as themselves** — consumer
  registration is open and that is the normal product. Booking notes for the
  review form ("bookings require salon confirmation; no money moves through
  the app") are store metadata, not code.
- **No admin-console access** for reviewers, ever.
- **No app changes.** The reviewer walks the existing email-OTP screens; the
  seam lives entirely server-side. Zero Flutter diff is a feature: nothing
  demo-related can ship in the binary.

## 2. The reviewer's experience (UX)

1. Open MyWeli Pro → « Se connecter par e-mail ».
2. Type `revue@myweli.test`, request the code (the app shows the normal
   « Code envoyé » state — the server sent nothing, see §5).
3. Type the fixed code from the review notes.
4. Land on the dashboard of « Salon Démo MyWeli » — a complete draft salon:
   3+ services, photos, a weekly schedule, a filled agenda and client list
   (manual bookings work on drafts by design — `booking_service.dart:301`,
   « the salon owns its calendar »), revenue on the dashboard, the works.

Everything a salon owner does daily works: agenda, manual bookings, clients,
catalogue edits, availability, journal, exports. The two things that do not
(publish, team invitations) fail with a clear French message (§6), and the
review notes say so up front.

**Copy** for the refusals:
« Compte de démonstration — cette action est désactivée. » (403,
`demo_account_locked`).

## 3. API & contract

**No new endpoints and no shape changes** — the seam alters the behaviour of
three existing routes for exactly one identity:

| route | for the demo identity |
|---|---|
| `POST /auth/provider/email/otp/request` | 202 as always; **no mail sent, no OTP record, no budget reserved** |
| `POST /auth/provider/email/otp/verify` | the fixed code (constant-time) replaces the emailed one; everything downstream (session issue, LOGIN-ONLY 404, invitation bridge) unchanged |
| `POST /auth/provider/register` | same substitution — used exactly once, by us, to create the account through the real product (§9) |

`docs/api/openapi.yaml` is untouched: requests and responses are
byte-identical in shape. The 403 `demo_account_locked` is a new error code on
`POST /providers/{id}/publish` and the team-invitation route — those two enum
additions are the only contract diff.

## 4. Data model

The demo account and salon are ordinary rows created through the ordinary
registration flow. Nothing marks them in the database — the identity itself is
the marker (§5), which means there is no flag an operator can forget to set or
accidentally set on a real salon.

**One tiny table** for the reset (§6.3): `demo_snapshot` — a single row
holding the curated salon document (`doc` jsonb), `provider_id`,
`captured_at`, and `last_reset_at`. Interface + in-memory + Postgres, like
every repository. *(The first draft claimed "no migration"; the automatic
reset is what changed that, and one row is the whole cost.)*

## 5. Architecture — the seam

### 5.1 The identity is a compile-time constant

```dart
/// lib/src/auth/demo_seam.dart
const String kDemoProviderEmail = 'revue@myweli.test';
```

`.test` is reserved by RFC 2606 §2 and can never be delegated in public DNS
— the address can never receive mail and can never belong to a real person.
The same structural argument as the Q1b smoke seam
([backend-q1b-smoke-seam.md](backend-q1b-smoke-seam.md) §3.1): the constraint
is not an allowlist an operator maintains, it is a property of the string,
and **no configuration mistake can widen it**. A constant rather than an env
var for the same reason: there is nothing to misconfigure.

### 5.2 The code comes from Secret Manager, and unset means absent

`DEMO_PROVIDER_CODE`, 6 digits (the app's OTP field and `isValidOtpCode`
already expect that shape, and the app must not change). Unset → the seam is
**absent**: the demo identity cannot sign in at all, which is the off switch
if the account is ever abused. Same posture as `SMOKE_OTP_SECRET`; same
boot-time warning when active in production, because a disclosure path
quietly left on is the failure mode worth engineering against.

### 5.3 A pure function, in the `boot_config.dart` shape

```dart
bool demoLoginAllowed({
  required String? configuredCode,   // null/short → seam absent
  required String email,
  required String code,              // constant-time compare
})
```

Routes call it and branch; `ProviderAuthRepository` never learns the seam
exists — the same layering argument as Q1b §3.2. The request route
additionally short-circuits before the repository AND before the send budget:
a `.test` address is structurally undeliverable, so attempting the send would
convert every demo login into a failed Resend call that still consumed a
`cold` budget unit (reserve-before-send is deliberate and stays).

### 5.4 The send-skip generalises, cheaply

While here: **`BudgetedEmailProvider.send`** — the wrapper every send passes
through, and crucially the layer that reserves budget BEFORE delegating —
refuses any `to` ending in `.test` (`ok: false, error: 'unroutable'`) before
the reserve. This also stops the subscription scheduler's future notices to
the demo owner (trial-expiry warnings) from burning budget on an address that
cannot exist. *(First drafted into `ResendEmailProvider`, which is the wrong
layer: the budget is already spent by the time the raw provider runs —
verified against `email_provider.dart` before writing this, not after.)*

## 6. Security & authz — design the room, not the lock

**The credential is public by design.** It will be printed in App Store
Connect review notes and Play's App access form, both read by third-party
staff. Rotation, lockout and brute-force analysis are therefore secondary:
assume everyone has the code, and bound what it opens.

What a holder of the code can do — and the mechanism that bounds each:

| capability | bound by |
|---|---|
| see/edit the demo salon | ownership checks (T50) — the account owns exactly this salon; every other salon's data returns 403 exactly as for any account |
| manual bookings, clients, catalogue, exports | per-identity rate limits (`LIMIT_*`), same as any account; all writes land on the demo salon only |
| **publish** | **refused, structurally** (§6.1) — the salon can never appear on myweli.com, in discovery, or in the sitemap, and can never fire a site rebuild |
| **team invitations** | **refused** — the only surface that emails an arbitrary third party (« X vous invite ») from an authenticated session; a public credential must not become a mail cannon |
| uploads (photos, KYC) | existing signing rate limits; own-prefix storage |
| sessions | normal JWT + rotating refresh; many holders share one account, which is fine — reuse-detection revokes families as designed |
| junk / defacement inside the demo salon | the **7-day automatic reset** (§6.3) — restore from snapshot, wipe + regenerate |

### 6.1 The publish refusal

`SalonProvisioningService.publish()` resolves the salon's **owner membership
email** (the membership rows already carry it — `_ensureOwnerRow` writes it)
and refuses with 403 `demo_account_locked` when it is `kDemoProviderEmail`.
In the service, not the route, for the reason the rebuild fires live in
services: no future caller can route around it. The same check, same error,
in `TeamService.invite`.

Draft is not a degraded state for review purposes — the dashboard is fully
functional on drafts by design (T51), which is precisely why the sandbox
costs the reviewer nothing.

### 6.2 The automatic reset — one mechanism, three problems

**Owner decision (2026-08-26): the demo resets automatically every 7 days.**
The design makes that one mechanism answer three of §10's original questions
at once:

1. **Junk & defacement** — anyone holding the public code can fill the demo
   salon's agenda, rename it, or upload photos. The reset restores the salon
   **document** (name, description, services, photos, availability) from a
   snapshot captured after the owner curates it once through the real app.
2. **A live-looking agenda, forever** — restoring *frozen* bookings would show
   September dates in January. So the reset wipes the salon's appointments and
   clients and **regenerates a small fixed agenda with dates relative to now**
   (a few completed, one today, a couple upcoming), through the real
   `bookManual` path so the rows — and the auto-created client records — are
   exactly what the product produces.
3. **Trial expiry** — rather than a human remembering a periodic `markPaid`
   (a human pretending to be a cron) or a demo-exempt trial (a special case
   inside *real* billing logic, the kind of carve-out that bites later), the
   reset **extends the demo subscription's paid coverage** as it runs. Demo
   concerns stay inside the demo module; billing logic stays untouched; a
   future reviewer never sees an expired banner.

**Mechanics.**

- **Capture**: `POST /admin/demo/snapshot` (admin-authenticated) stores the
  current demo-salon document. Owner-triggered once after curating — and
  re-triggerable any time the demo is improved.
- **Schedule**: the reset **rides the existing daily subscriptions cron** as
  `tickIfDue(now)` — a no-op unless ≥7 days since `last_reset_at`. The cron
  route's own comment reserves extraction of `/internal/cron/maintenance` for
  the day a third task arrives; this is that task, but it is *due-gated
  internally*, so it would need its own cadence logic even on a dedicated
  job — riding is strictly cheaper: no new Scheduler job, no new audience,
  nothing new that can stop silently. The comment is updated to record this.
- **Safety, in the code and not the operator's head**: every destructive step
  re-verifies the target salon's owner-membership email is
  `kDemoProviderEmail` before acting, and the whole reset is a no-op when the
  seam is absent or no snapshot exists (logged, not silent).
- **No rebuild fires** — the salon is draft before and after; the reset never
  touches `status`.

### 6.3 Threat-model delta — new row T69

**T69 — demo review account** (S/E/D): a deliberately public credential into
production. Spoofing a real user: impossible structurally (`.test`).
Elevation: bounded by ownership + the two refusals; the account is an
ordinary provider account with two capabilities subtracted, never a special
path with capabilities added. Disclosure of others' data: none reachable.
DoS/abuse: per-identity rate limits; the off switch is unsetting
`DEMO_PROVIDER_CODE`; junk data accumulates only inside the demo salon (§10
resets). Residual, stated: someone who signs in can deface the demo salon's
own content — visible to the next reviewer only, and cured automatically
within 7 days by the reset (§6.2), or immediately by re-running it.

## 7. Performance

One string comparison per OTP request/verify (the constant-time compare runs
only for the demo identity); one membership read on `publish()` — a rare,
owner-initiated call. Nothing on any hot path.

## 8. Testing plan

Unit (`demo_seam_test.dart`): allowed only when code configured ∧ email
matches ∧ code matches; short/unset code → absent; wrong identity with the
right code → false; constant-time compare used (structural assertion).

Route tests: request for the demo identity sends nothing and reserves no
budget (a recording `EmailProvider` + a recording `SendBudget` both stay
empty) while returning 202; verify with the fixed code issues a session;
wrong fixed code → the normal error, no lockout interference for other
identities; **seam unset → the demo identity behaves exactly like any
unknown address** (the absence case, asserted, not assumed); a **real**
address with the demo code → normal flow untouched (the non-interference
case, the one that matters most).

Service tests: publish on the demo-owned salon → 403 `demo_account_locked`
and **no rebuild fired** (a recording notifier stays empty — this composes
with the [rebuild slice](backend-web-rebuild-hook.md)); invite from the demo
salon → 403; both refusals keyed on the membership email, watched red by
mutating the constant.

Send-skip: a `.test` recipient is refused before the budget reserve (the
recording budget stays empty).

Reset (`demo_reset_test.dart`): due-gating (6 days → no-op, 7 → runs, runs
again only 7 days later); restore actually reverts a defaced document;
appointments/clients wiped and regenerated relative to `now` (asserted
against the injected clock); subscription coverage extended and notices
cleared; **a non-demo salon is untouchable** — the safety check keyed on the
membership email, watched red by mutating the constant; seam absent or no
snapshot → logged no-op; **no rebuild fires** (recording notifier empty).

Each guard watched red; comments stripped before any source-level match; the
mutation list recorded in the PR.

## 9. Rollout

1. Land the seam (one PR: seam + refusals + send-skip + tests + this spec's
   status flip).
2. Mint `DEMO_PROVIDER_CODE` (Secret Manager, pinned version in
   `service.yaml` per the pinning convention), deploy.
3. **Owner, through the real app** (staging first as rehearsal, then prod):
   register `revue@myweli.test` with the fixed code, build « Salon Démo
   MyWeli » — 3+ services, photos, schedule, a plausible agenda of manual
   bookings, the 90-day trial offer. No seed script: the demo salon is
   created through the product it demonstrates, which is itself a rehearsal
   of the salon-onboarding flow.
4. Paste the credentials into both consoles' review forms.
5. After store approval, the code MAY be rotated or unset between review
   cycles; the account data stays.

**Ops note:** ~~the trial expires after 90 days … a periodic admin `markPaid`
keeps the demo clean~~ — superseded by §6.2: the weekly reset extends the
demo subscription's coverage, so no operator task exists. (Kept for the
record: `markPaid` on the demo salon would have been safe — its republish
branch cannot fire on a never-published salon.)

**Rollout gains one step:** after curating the salon (step 3), capture the
snapshot — `POST /admin/demo/snapshot` — before pasting credentials into the
consoles.

## 10. Decisions (were open questions — owner, 2026-08-26)

1. **Reset cadence: automatic, every 7 days** — designed in §6.2.
2. **Trial expiry: folded into the reset** (§6.2 point 3). A periodic manual
   `markPaid` is a human pretending to be a cron; a demo-exempt trial is a
   special case inside real billing logic. The reset extending coverage keeps
   demo concerns inside the demo module.
3. **Play App access wording, as proposed**: the form entry reads — email
   `revue@myweli.test`, code `<the 6 digits>`, both static and reusable; no
   real one-time password is sent for this identity. The fallback (a
   dedicated password field in the app) stays a documented contingency, built
   only if a reviewer rejects this shape.

## 11. Definition of done

- [ ] `analyze` 0 · format clean · full backend suite green · mutations red.
- [ ] OpenAPI error-enum additions in the same PR; threat model T69 added.
- [ ] Boot warning when the seam is active in prod, asserted by a test.
- [ ] Spec status → Built; cross-linked from `demo_seam.dart`, the two
      refusal sites, and `mobile-external-testing.md` §5.2.
- [ ] The store-side halves (§9 steps 2-4) listed as owner tasks, never
      claimed done from here.
