# External testing — putting both apps in salon owners' hands

| | |
|---|---|
| **Module** | release engineering (`mobile/ios`, `mobile/android`, `backend/`) |
| **Status** | **Plan.** Nothing here is done. §6 is the sequence; §5 is what stops it. |
| **Related** | [mobile-store-submission.md](mobile-store-submission.md) · [LAUNCH.md §1.2](../LAUNCH.md) · [pro-salon-lifecycle.md](pro-salon-lifecycle.md) · [infra-staging.md](infra-staging.md) |

## 1. What this is for

Getting real salon owners in Abidjan to install MyWeli Pro, register their
salon, publish it, and receive a booking — before anything is public.

It is not the same job as store submission ([mobile-store-submission.md](mobile-store-submission.md)),
and it is deliberately sequenced first: a public launch with an empty catalogue
is the largest App Store 2.1 risk we carry, and this is how the catalogue stops
being empty.

## 2. Four distributions, not two

| | consumer (`com.myweli.app`) | pro (`com.myweli.pro`) |
|---|---|---|
| **iOS** | TestFlight | TestFlight |
| **Android** | Play closed track | Play closed track |

**Both apps, or the test measures nothing.** The loop under test is *a client
books → the salon is notified → the salon confirms → the client is notified*.
A salon owner alone on the Pro app is looking at an empty agenda; the dashboard
never lights up, push is never exercised, and the thing they are meant to
evaluate never happens. Someone has to be holding the consumer app and booking.

For the first cohort that someone can be us. It still needs a consumer build in
a tester's hands, and that build has to be the store-signed one — a debug build
on a laptop proves nothing about the artifact salons will run.

## 3. The asymmetry that decides the schedule

This is the single most useful fact in the document, and it is not symmetric
between the platforms.

**A TestFlight *internal* tester is a user on your App Store Connect team.**
The roles that qualify — Admin, App Manager, Developer, Marketing — all carry
console access. Adding a salon owner as an internal tester means giving a
business partner a seat inside the Apple account that holds the certificates and
the contracts. That is not a thing to do. **Salons therefore need *external*
TestFlight**, which means **Beta App Review**, which means **a demo account**
(§5.2).

**A Play internal/closed tester is an email address.** No console access, no
role, no review for the internal track. Google's side of this is a list you
paste in.

So: **Android can have salons testing within days. iOS cannot, and what gates it
is the demo account, not the build.** Plan around that rather than discovering
it after the first rejection.

## 4. Which Android track — closed, not internal

Internal testing is faster and needs less paperwork. Use **closed** anyway.

If the Play developer account is a **personal** account created after
13 November 2023, Google requires a **closed** test with **at least 12 testers
opted in continuously for 14 days** before you may even apply for production
access. **Internal testing does not count toward it.** Running the salon cohort
on the internal track would mean running it twice.

An organisation account is exempt. The cost of choosing closed when you did not
have to is a little more metadata up front; the cost of choosing internal when
you did have to is a fortnight.

> **Read the rule in the Play Console rather than here.** Its thresholds have
> changed more than once since it was announced, and this repository cannot see
> which account type we hold or what Google is currently asking of it. The
> console states the requirement against the actual account, and that is the
> authority.

## 5. What stops it, in the order it bites

### 5.1 Google sign-in fails silently on every Play-distributed build

Play strips the upload signature and **re-signs with the App Signing key** it
holds. Google resolves an Android sign-in by *(package name, signing
certificate SHA-1)*, and that key's fingerprint is registered nowhere. The
lookup finds nothing and Credential Manager returns `canceled` — which the app
cannot distinguish from the user dismissing the sheet. **No error, no log,
nothing in Sentry. The button simply does nothing.**

The only fingerprint currently registered is the debug keystore
(`7a5cb3b0…`), which is why sign-in works on a development phone today and
tells you nothing about what a tester will see.

It is a chicken-and-egg, so the order is not negotiable:

1. create the Play app record
2. enrol in Play App Signing
3. read the SHA-1 (**Setup → App integrity → App signing**)
4. register it on the Android OAuth client in Google Cloud
5. record it in `infra/mobile/signing-manifest.json`
6. **then** invite the first tester

Step 6 is the point. A tester invited at step 2 hits a dead sign-in button and
reports the app as broken, and that first impression is the whole budget you get
with a partner.

`infra/mobile/96-verify-google-identity.mjs` is the release-time gate for this
and reads the manifest; it exists so that this cannot be forgotten twice.

**iOS is unaffected.** An iOS OAuth client is keyed on the bundle id, not on a
signing certificate, so Google sign-in on a TestFlight build behaves exactly as
it does in development.

### 5.2 The demo account — the one piece of real engineering here

Both stores require working sign-in credentials when the app is behind a login.
Ours are Google, Apple and email OTP (`AUTH_METHODS=google,apple,email` in
production; `MESSAGING_PROVIDER=disabled`, so there is no SMS path at all).
None of the three can be handed to a reviewer:

| method | why it fails for a reviewer |
|---|---|
| Google / Apple | they sign in as themselves and get a **brand-new consumer account** — on the Pro app that is the registration funnel, not a dashboard |
| email OTP | the code goes to an address **we** control; the reviewer cannot read it |

And the two apps are not equally exposed:

- **Consumer** opens straight to `/home` (`splash_screen.dart:36`) and is fully
  browsable signed-out — discovery, salon pages, services, prices. A reviewer
  can evaluate most of it with no account, and only needs one to complete a
  booking.
- **Pro** opens to `/pro/login` (`pro_splash_screen.dart:66-69`). **A reviewer
  sees a login wall and nothing else.** Without credentials there is nothing to
  review.

So what is needed is a **pre-provisioned provider account — published, with
services, photos and a schedule — that a reviewer can enter with a fixed
credential.** The repository already has a seam of roughly the right shape (the
`.test`-suffix + secret arrangement in
[backend-q1b-smoke-seam.md](backend-q1b-smoke-seam.md)), but turning it into a
review credential is a change to the authentication path and gets its own design
spec and its own threat-model delta: exactly one allowlisted identity,
rate-limited, and unable to reach any real salon's data.

**This is the largest item in this document and it is on the critical path for
iOS external testing and for Play closed testing.** Nothing else here is
comparable in size. It should start before the console work, not after.

### 5.3 The catalogue has to be filled in the right order

Consumer testers with no salons to book are testing an empty state. So: **Pro
first, publish, then invite consumer testers.**

Publishing is server-authoritative (`SalonProvisioningService.publishGate`) and
the list is short enough to hand a salon owner directly:

- a description, an address, and a **commune that resolves to a known locality**
- latitude/longitude — no map pin, no listing on the discovery map
- **at least 3 active services**
- **at least 3 photos**
- at least one open day in the weekly schedule
- **a live offer** — the 90-day free trial, chosen on the subscription screen

**There is no KYC gate on publishing**, so nothing waits on an admin. A salon
that completes the list is live to consumers the moment it publishes.

Worth saying plainly to the salons: this is roughly half an hour of work, and
three photos is the step people stall on.

### 5.4 No signed build has ever been produced

The only iOS archive this project has made was built `--no-codesign`
([mobile-store-submission.md §6](mobile-store-submission.md)). The production
`aps-environment` is therefore *configured* but never *exercised*, and a
production APNs push to a sandbox token is **silently dropped** — the failure
that looks like nothing happening.

The first TestFlight build is where that gets proven, and it has to be proven
deliberately: send a push to a TestFlight device and watch it arrive.

Two related things that are now fixed and should be confirmed on the first
upload rather than assumed: the build number is the git commit count (so a
second upload is accepted), and the Pro app carries `AppIcon-pro` (so the two
apps are distinguishable on a tester's home screen).

### 5.5 Email delivery is the sign-in path, and nothing here can see it

With `MESSAGING_PROVIDER=disabled`, a salon owner who does not use Google or
Apple signs in by **email OTP**, sent through Resend. `EMAIL_FROM` is not set in
`infra/gcp/service.yaml`, so the sender is the code default,
`MyWeli <no-reply@myweli.com>`.

Whether `myweli.com` is a verified Resend sending domain, and whether SPF, DKIM
and DMARC are published, **cannot be determined from this repository**. If that
mail lands in spam, testers cannot sign in — and they will report it as the app
being broken, not as a mail problem.

**Check it before inviting anyone**, and check it discriminatingly: request one
OTP against production for an address you can read, confirm it arrives in the
inbox rather than the spam folder, and read the Cloud Run logs for the send
result. The endpoint returns `202` whether or not the mail went out — by
design, so that a caller cannot probe which addresses exist — so a `202` is
not evidence of delivery.

Also note the ceiling: `EMAIL_BUDGET_COLD=60` per hour, where *cold* is
"an anonymous caller picked the address" — every sign-in OTP. Twelve salons is
comfortably inside it. A hundred-tester open beta is not, and the symptom is
`email_budget_exhausted` in the logs while users see a code that never arrives.
Raise it before the cohort grows, not after.

## 6. The sequence

### Phase 0 — accounts and records *(owner, both consoles)*

Play: create both apps, enrol in Play App Signing, complete **App content** —
privacy policy, ads declaration, content rating questionnaire, target audience,
data safety, app access. Expect the console to gate the first release on this;
which items are mandatory for which track has moved before, and the release page
names whatever is blocking.

App Store Connect: create both app records against the exact bundle ids;
Distribution certificate; App Store provisioning profiles carrying **Push
Notifications** and **Sign in with Apple**. If any profile was generated before
the Sign in with Apple capability was enabled (2026-08-18), regenerate it —
editing capabilities invalidates existing profiles, and an entitlement the
profile does not grant fails code signing rather than being ignored.

### Phase 1 — Android closed testing *(the fast path)*

Build, upload, **register the App Signing SHA-1 (§5.1) before inviting anyone**,
then paste the tester list. Salons can be installing within days of Phase 0.

### Phase 2 — the demo account *(engineering, §5.2)*

Design spec first. This gates Phase 3 and, depending on what Play asks for under
*App access*, possibly Phase 1 as well.

### Phase 3 — iOS TestFlight external

Beta App Description, feedback email (`support@myweli.com`), privacy policy
URL, the demo credentials, export compliance (already declared in the built
`Info.plist`). Submit for Beta App Review — the first build of each version is
reviewed; later builds of the same version usually are not.

### Phase 4 — run the cohort

Fourteen continuous days if §4 applies. Watch the crash-free rate per build in
Sentry (the release string is the build number), route TestFlight feedback to
`support@myweli.com`, and keep the testers opted in — a tester who uninstalls
stops counting.

## 7. Repo side vs owner side

**Repo:** the demo-account seam (§5.2) · the SHA-1 recorded in
`signing-manifest.json` (§5.1) · `EMAIL_BUDGET_COLD` if the cohort grows
(§5.5) · the iOS `updateUrl` in the version gate, which stays NULL until an App
Store listing exists.

**Owner:** everything inside the two consoles, the keystore and its backup, the
store metadata and screenshots, the privacy questionnaires, and the tester list.

**Neither yet:** `NEXT_PUBLIC_ANDROID_APP_URL` / `NEXT_PUBLIC_IOS_APP_URL`.
These light up the site's install banner and « Télécharger l'app » section, and
they must stay unset through this phase — a closed-track opt-in URL is not a
public listing, and pointing the public site at one shows every visitor a page
they cannot use. `web/lib/appStore.ts` already renders nothing while they are
unset, deliberately.

## 8. What this document does NOT know

Nothing here can see the Apple Developer portal, App Store Connect, the Play
Console, the Resend dashboard or the Google Cloud OAuth client. Every claim
about those is marked as something to check, never as a fact. Specifically
**unverified from this repository**:

- whether the Play developer account is personal or an organisation (§4)
- whether either app record exists in either console (§6 Phase 0)
- whether `myweli.com` is a verified Resend sending domain (§5.5)
- which App content items Play will gate the first closed release on (§6)

## 9. Open questions

1. **The demo-account mechanism** (§5.2) — its own spec before any code.
2. **Which salons, and how they are recruited.** Twelve opted-in testers for
   fourteen days is a commitment from twelve businesses, not a mailing list.
3. **Which consumer accounts book against them** during the cohort, so the Pro
   app is exercised rather than merely installed.
