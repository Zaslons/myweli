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
role. Google's side of this is a list you paste in — or, better, a Google Group
people join themselves (§4.1).

**But "no review on the internal track" is false, and this document said it.**
A *first* release on the internal track is reviewed before it can be published —
hours, up to seven days — **unless the app is not fully configured**, in which
case it ships at once and testers see a placeholder app name for up to 48 hours
until that first review lands. Subsequent builds are not reviewed. The opt-in
link also appears only once the app's status is *Published*, and can take
several hours to propagate. "Minutes" describes updates, not the first build.

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

**And open testing is not the escape hatch it looks like.** Google's own
sentence: *"Open testing becomes available after you gain production access."*
So on a personal post-2023 account the public "anyone can join the beta" track
is locked behind the *same* closed test that locks production — it cannot be
used to get there. ([answer/14151465](https://support.google.com/googleplay/android-developer/answer/14151465))

> **Read the rule in the Play Console rather than here.** Its thresholds have
> changed more than once since it was announced, and this repository cannot see
> which account type we hold or what Google is currently asking of it. The
> console states the requirement against the actual account, and that is the
> authority.

### 4.1 Self-enrolment — reaching salons without collecting their emails

Both tracks above assume you type in each tester's address. Neither platform
requires that, and the alternatives are better for recruiting strangers.

**iOS — the TestFlight public link.** An external group can carry a link
(`testflight.apple.com/join/…`) that anyone opens to join, no invitation and no
address collected. Up to **10,000** testers, and a lower cap can be set (1 to
10,000). Only the **first build of a version** goes to Beta App Review; you may
submit up to six builds in 24 hours. The link can be disabled later.
([App Store Connect Help](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/))

Two consequences of it being public, both operational:

- **Those testers are anonymous to you.** Name and email display as anonymous
  and they are **excluded from the CSV export**. You cannot contact them through
  App Store Connect at all. Run a WhatsApp group alongside from day one.
- Testers need iOS 16+ and the TestFlight app; a build is testable for 90 days
  from upload, across up to 30 of their devices.

**Android — a closed track pointed at a Google Group.** The closed track accepts
`yourgroup@googlegroups.com` in place of an email list, and a Google Group can be
set to **"Anyone can join"** — as opposed to *"Anyone can ask"*, which needs your
approval. Publish the group link and the opt-in link; people enrol themselves and
you never open the tester tab. Unlike internal testing it still **counts as closed
testing**, so the §4 clock runs while you recruit.
([answer/9845334](https://support.google.com/googleplay/android-developer/answer/9845334) ·
[Groups](https://support.google.com/groups/answer/2464926))

The tester's journey has a step people skip: **join the group, *then* open the
opt-in link.** Google's words — *"users must join the group before opting into
your test."* Joining the group alone installs nothing.

**Country targeting will silently break this.** Internal testing is exempt —
*"Country targeting won't apply to apps on the Internal testing track"* — but a
**closed** track syncs its countries from production by default, and production
has no country list because MyWeli is not distributed yet. Unsync and add Côte
d'Ivoire explicitly before publicising anything.
([answer/7550024](https://support.google.com/googleplay/android-developer/answer/7550024))

**The trap that outlives the recruiting.** Applying for production access
requires describing *"whether testers used all available app features"* and
summarising *"the feedback received from testers"*. Anonymous, self-enrolled
group members are exactly the population that cannot be characterised or
contacted. So run the open group for volume **and** keep a named, reachable
cohort of around fifteen real Abidjan salon owners. The group solves
recruitment; it does not solve the application.

**And a tester opted into an internal test is ineligible for that app's closed
test until they opt out.** Another reason not to start salons on internal: each
one would have to be walked back out before the fourteen days could begin.

## 5. What stops it, in the order it bites

### 5.1 Google sign-in fails on every Play-distributed build

Play strips the upload signature and **re-signs with the App Signing key** it
holds. Google resolves an Android sign-in by *(package name, signing
certificate SHA-1)*, and that key's fingerprint is registered nowhere, so the
lookup finds nothing and sign-in fails.

The only fingerprint currently registered is the debug keystore
(`7a5cb3b0…`), which is why sign-in works on a development phone today and
tells you nothing about what a tester will see.

**How it fails — this section had it wrong, and the correction matters.** It
said the failure was *silent*: that Credential Manager returns `canceled`, that
the app cannot tell it from the user dismissing the sheet, and that the button
"simply does nothing". All three are false, and reading the plugin settles it:

- `canceled` has exactly one source, `GetCredentialCancellationException` —
  a genuine user dismissal (`GoogleSignInPlugin.java:307`).
- A missing credential arrives as `NoCredentialException`, and because
  `authenticate()` — the button flow we call — passes `throwForNoAuth: true`
  (`google_sign_in_android.dart:88`), it maps to **`unknownError`**, never
  `canceled` (`:188-218`).
- `api_auth_service.dart` sends anything that is not `canceled` to
  `google_failed`, and both providers suppress the banner for **exactly**
  `cancelled` (`auth_provider.dart:141`, `pro_auth_provider.dart:400`).

So the tester sees « **Connexion Google impossible.** » It is loud, not silent.
The conclusion the section was built on is unchanged — Google sign-in is broken
on a Play-signed build until the SHA-1 is registered — but a wrong mechanism
produces wrong fixes and wrong severity, which is why it is corrected here
rather than quietly rewritten.

**What is genuinely missing is diagnosis, not the error.** Five distinct
`GoogleSignInExceptionCode` values collapse into one opaque `google_failed`,
`e.description` and `e.details` are discarded, and **nothing on any sign-in path
reports to Sentry** — verified: zero Sentry references in `api_auth_service.dart`,
`auth_provider.dart` and `pro_auth_provider.dart`. A misconfigured SHA-1, a
network blip and an unsupported device are indistinguishable in our telemetry.
We would learn about this from a salon owner's message, not a dashboard.

It is a chicken-and-egg, so the order is not negotiable:

1. create the Play app record
2. enrol in Play App Signing
3. read the SHA-1 (**Protected with Play → Play Store distribution → Play
   app signing**; the old *Setup → App integrity* path is gone)
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

And these were researched against Google's and Apple's own pages and came back
**genuinely unsettled** — the silence is verified, not merely unlooked-for:

- **whether Google Group members count toward the 12-testers requirement**
  (§4.1). `answer/14151465` never mentions Google Groups, email lists or any
  tester-adding mechanic. Nothing suggests they do not count; nothing states
  they do.
- **whether TestFlight public links are restricted by country.** No Apple page
  either imposes or rules it out. Test with one Ivorian Apple Account before
  assuming.
- **which App content items gate a closed release.** The **Data safety form is
  confirmed required** for closed, open and production (internal-only apps are
  exempt) — [answer/10787469](https://support.google.com/googleplay/android-developer/answer/10787469).
  The content-ratings page does not mention testing tracks at all. Treat the
  rest as likely but unverified; the release page names whatever is blocking.
- **a separate gate lands 2026-09-30** — *Play Console Requirements*, under
  which apps must be registered in Play Console for Android developer
  verification. Confirm it in the console; it is outside anything this repo
  can see.

## 9. Open questions

1. **The demo-account mechanism** (§5.2) — its own spec before any code.
2. **Which salons, and how they are recruited.** Twelve opted-in testers for
   fourteen days is a commitment from twelve businesses, not a mailing list.
3. **Which consumer accounts book against them** during the cohort, so the Pro
   app is exercised rather than merely installed.
