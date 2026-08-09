# Launch readiness — and how we develop once we are public

| | |
|---|---|
| **Status** | Living document. Nothing here is done until its box is ticked **with evidence**. |
| **Order** | **Web first → iOS → Android last** (§3) |
| **Related** | [ROADMAP.md](ROADMAP.md) · [DEPLOYMENT.md](DEPLOYMENT.md) · [BACKEND.md](BACKEND.md) · [design/mobile-store-submission.md](design/mobile-store-submission.md) |

## 0. Why this document exists

We have been shipping quickly and well, but every gate we have answers the same
question: *does the code do what the code says?* Launch introduces three
questions none of our gates can answer:

1. **Is the data real?** Production is currently serving **seeded demo salons**
   (§5.1). Nothing fails; the app looks fine; the marketplace is fictional.
2. **Can we work without breaking the people using it?** Today there is exactly
   **one** backend (`myweli-api`) and **one** database (`myweli-db`). Testing a
   change means testing it on the thing customers use. That is fine while
   nobody uses it and untenable the day after launch.
3. **Would we know if it broke?** There is **no crash reporting, no error
   tracking and no alerting** anywhere in the stack (§5.2). A public service we
   cannot observe is a service we are not really running.

This document is the answer to those three, plus the per-surface checklists.

---

## 1. How companies actually solve "we cannot test on production"

Two separate mechanisms, routinely confused. You need both.

### 1.1 Environments — *which backend and which data*

The standard is three, and the middle one is the one we do not have:

| Environment | Data | Who touches it | Purpose |
|---|---|---|---|
| **local** | mocks, or a throwaway Postgres in Docker | a developer | fast loops, no network |
| **staging** | **fake but realistic**, freely destroyable | developers, testers, automated e2e | the rehearsal — everything is tried here first |
| **production** | real customers, real money, real reputation | nobody, directly | the actual product |

The rule that makes staging worth having: **it must be the same *shape* as
production** — same migrations, same config keys, same storage layout — and
**never the same data**. A staging environment that has drifted structurally
tells you nothing; one that shares production's database is just production
with extra steps.

Concretely for us that means a second Cloud Run service, a second database, a
second set of R2 buckets and a second Firebase project. It is not free, and it
is the single highest-value thing to build before launch.

### 1.2 Pre-release distribution — *which build, in whose hands*

This is the part that surprises people coming from web: an app in the store
cannot be "deployed to a subset of users" the way a website can. The stores
provide separate **tracks** instead.

**iOS — TestFlight.** You upload a build; it goes to testers, not the public.
- *Internal testers* — up to 100 people on your team, **no review**, available
  in minutes. This is the day-to-day one.
- *External testers* — up to 10,000, needs a short review of the first build in
  a version. This is your beta.
- Builds expire after 90 days, which is a feature: it stops stale builds
  lingering.

**Android — Play Console tracks.** Same idea, four rungs:
`internal` (up to 100, minutes) → `closed` (alpha, invited) → `open` (beta,
public opt-in) → `production`. You promote a build up the ladder; the artifact
does not change.

### 1.3 The two axes are independent, and that is the point

A TestFlight build can point at **staging** or at **production**. You want both,
for different jobs:

| Build | Points at | Answers |
|---|---|---|
| dev / simulator | staging | "does my feature work at all?" |
| TestFlight / internal track | **staging** | "does it work on a real device, for someone who is not me?" |
| TestFlight / internal track | **production** | "is this exact artifact safe to release?" — the release candidate |
| store release | production | the public |

We already have the machinery for this: `--dart-define=API_BASE_URL=…` and the
`consumer`/`pro` flavours. What is missing is the staging backend to point at.

### 1.4 The constraint that makes mobile different from web

**You cannot roll back an app release.** Web is a redeploy; a bad app version is
on people's phones until they choose to update, and some never will. Three
consequences, all of which change how we work:

- **The API must stay backward compatible.** Once v1.0 is installed, the backend
  serves v1.0 *forever* — or at least until we can prove nobody is on it. New
  fields are additive; removing or renaming one breaks phones we cannot reach.
  Database migrations follow the same discipline (expand → migrate → contract,
  never a destructive change in one step).
- **Staged rollout.** Play supports percentage rollouts (1% → 5% → 20% → 100%);
  the App Store has phased release over 7 days. Both let you halt. Use them, and
  watch the crash rate between steps — which requires §5.2.
- **A forced-upgrade path.** A minimum-supported-version check the app honours,
  so that when we *must* retire an old client we can tell it to update rather
  than serve it something it will mishandle. **We do not have this** (§5.3).

### 1.5 Feature flags — deploying without exposing

Shipping code to production and *enabling* it are separate acts. `FeatureFlags`
already exists in the app and is used this way (`futureProviderFeatures`,
`appleSignIn`). Post-launch this becomes the normal way to work: merge early,
behind a flag, off; enable for ourselves; then everyone. It also gives a kill
switch that does not need a store release — which, per §1.4, is the only kind of
switch that works quickly on mobile.

---

## 2. What we already have, honestly assessed

Not everything is missing. Worth being precise so we build what is actually
absent:

| Capability | State |
|---|---|
| Per-PR web previews | ✅ Vercel builds every PR — **but see §5.4**, they very likely talk to the production API |
| Backend `ENV` seam | ✅ `dependencies.dart` reads `ENV`; `dev` vs `prod` already gates OTP dev-codes |
| App environment switch | ✅ `API_BASE_URL` + `USE_API_BACKEND` dart-defines |
| Flavours (consumer/pro, both platforms) | ✅ |
| CI: analyze, unit, widget, golden, e2e, APK size, secret scan, funnel smoke | ✅ strong |
| Release signing + store prep | ✅ repo side (#337); accounts pending |
| **Staging environment** | ❌ **nothing** |
| **Crash / error reporting** | ❌ **nothing** |
| **Uptime alerting** | ❌ nothing |
| **Forced upgrade** | ❌ nothing |
| **Production data hygiene** | ❌ seeded demo salons are live |
| **Backup / restore rehearsal** | ⚠️ PITR is on; a restore has never been performed |

---

## 3. Launch order, and why

**Web → iOS → Android.**

- **Web first** because it is the only surface we can fix in minutes. Every
  early mistake — copy, pricing, a broken funnel — is a redeploy rather than a
  store review. It also lets real salons and clients use the product while the
  app is still in TestFlight, so the app launches into something that already
  works.
- **iOS second** because it is furthest along (account exists, signing prepared,
  Sign in with Apple working) and because App Store review is the slower gate —
  starting it while web is live costs nothing.
- **Android last.** It has the most outstanding work (no keystore, no Play
  account, R8 unproven) and the widest device variance, which is where the
  reference low-end Android in ROADMAP §6 has to be honoured.

Each surface has a hard prerequisite: **the one before it is live and stable for
at least a week**, with §5.2's monitoring proving it rather than our impression.

---

## 4. Before ANY launch — the shared gate

These block everything. None is surface-specific.

- [ ] **Staging exists** and the full funnel has been rehearsed on it end to end.
- [ ] **Production contains no seeded/demo data** (§5.1).
- [ ] **Crash reporting and error tracking** are live on backend, web and app,
      and have been *proven* by deliberately triggering an error and seeing it
      arrive.
- [ ] **Uptime alerting** on `api.myweli.com/health` reaching a human.
- [ ] **A database restore has actually been performed** on staging from a real
      backup. PITR that has never been exercised is a hope, not a backup.
- [ ] **Secrets rotated** away from any value that has been in a terminal, a
      log, or a chat during development.
- [ ] **Legal pages live and accurate** — CGU, privacy policy, mentions légales
      (the RCCM line is still "not registered"; that must be true or updated).
- [ ] **A support channel exists** and someone is behind it (WhatsApp per the
      product's context).
- [ ] **Rate limiting** verified on the auth and booking routes against a real
      hostile pattern, not a unit test.
- [ ] **The funnel has been walked by a person who did not build it**, on a real
      phone, on a real Ivorian network.

---

## 5. The specific gaps, with what to do

### 5.1 Production is serving fictional salons

`GET https://api.myweli.com/providers` returns `provider3` « Barber King »,
« Beauté Divine », « Élégance Coiffure », « Nails & Co » — `seedProviders` from
`providers_repository.dart`, complete with invented ratings and review counts.

This is fine today (no users) and unacceptable at launch: a marketplace whose
listings are fabricated is a trust problem and, with invented review counts,
arguably a consumer-protection one.

- [ ] Seeding runs **only** when `ENV != prod`, enforced in code rather than by
      remembering.
- [ ] Production database purged of seed rows before the first real salon.
- [ ] The `asset:` image convention retired for real salons — they upload to R2
      (the convention exists only to serve the demo set; see §21 row 90).

### 5.2 We would not know if it broke

No Crashlytics, Sentry, or equivalent anywhere. Today a crash on a user's phone
is invisible to us forever; a 500 in the backend exists only in Cloud Run logs
nobody is watching.

- [ ] **App**: Crashlytics (Firebase is already wired) or Sentry, on both
      flavours, with the release version attached.
- [ ] **Backend**: structured error reporting to the same place, with the
      request id already in the logs.
- [ ] **Web**: browser error reporting.
- [ ] **Prove it**: trigger one real error per surface and watch it arrive.
- [ ] Alert thresholds agreed — what crash rate halts a staged rollout.

### 5.3 No forced-upgrade path

Per §1.4 we cannot recall a release. Without a minimum-version check we can also
never *retire* one.

- [ ] Backend exposes a minimum supported client version.
- [ ] App checks it at startup and, below the floor, blocks with a « Mettre à
      jour » screen rather than failing in strange ways.
- [ ] Chosen deliberately: this is the only lever that works on a phone we
      cannot reach.

### 5.4 Web previews may write to production

Vercel builds a preview per PR. `NEXT_PUBLIC_API_BASE_URL` appears to be set
per-project, which would mean **every preview deployment reads and writes the
production database**. Harmless now; at launch it means a PR can create bookings
against real salons.

- [ ] Verify which environments the variable is set for in Vercel.
- [ ] Point Preview at **staging**; leave Production pointing at production.

### 5.5 Backups are unrehearsed

- [ ] Restore `myweli-db` to a staging instance from PITR and confirm the data.
      Until that is done we do not know we have backups.

---

## 6. Per-surface checklists

### 6.1 Web (first)

- [ ] Lighthouse/CWV budgets green on the real domain, not a preview.
- [ ] SEO: sitemap, robots, canonical URLs, JSON-LD validating.
- [ ] The full funnel on a real phone browser on a slow connection.
- [ ] 404 and error states reachable and correct.
- [ ] Analytics decision made (we currently have none — deliberate or not).
- [ ] Install-the-app prompts point somewhere real, or are hidden until the apps
      exist. **They currently promise apps that are not published.**

### 6.2 iOS (second)

- [ ] Everything in [mobile-store-submission.md](design/mobile-store-submission.md) §5.
- [ ] A **signed** build verified — production `aps-environment` baked, not just
      configured, and a real push received from the production FCM project.
- [ ] TestFlight internal build exercised by someone other than the developer.
- [ ] Screenshots, description, keywords, age rating, privacy questionnaire.
- [ ] Sign in with Apple working in the signed build (rule 4.8).
- [ ] Phased release enabled.

### 6.3 Android (last)

- [ ] Upload keystore created and **backed up** — losing it ends the listing.
- [ ] Play Console records for both apps; Play App Signing enrolled.
- [ ] R8 decision made and, if enabled, verified on a device (§2 of the
      submission spec).
- [ ] Tested on the **reference low-end device** (2–3 GB RAM, Android 9), not
      only an emulator.
- [ ] Staged rollout starting at a small percentage.
- [ ] Data safety form completed, consistent with the iOS privacy answers.

---

## 7. After launch — the working rhythm

1. Branch → PR → CI, exactly as now.
2. Merge deploys to **staging** automatically.
3. Rehearse on staging: the funnel, the migration, the new screen.
4. Promote the same artifact to production behind a **flag, off**.
5. Enable for ourselves, then a slice, then everyone.
6. For app changes: internal track → beta → staged rollout, watching crash rate
   at each step.
7. Anything schema-shaped: expand → deploy → migrate → contract, never in one
   move, because old clients are still out there.

The discipline this replaces is the one we have been using — merge and it is
live — which is correct for a product with no users and wrong the moment there
is one.
