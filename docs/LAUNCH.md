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

1. ~~**Is the data real?**~~ **Closed 2026-08-12.** Production served four
   fictional salons with invented ratings; they are deleted, and the deletion
   held through a cold boot. The marketplace is now empty rather than fake —
   which is the correct state before the first real salon.
2. ~~**Can we work without breaking the people using it?**~~ **Closed 2026-08-18.**
   Staging exists and serves — `myweli-api-staging` + `myweli-db-staging`,
   deploying itself on every merge to `main`, with its own secrets, PITR and
   alerting — and **Vercel Preview now reads it**, verified on a real preview
   deployment rather than in the dashboard. Previews no longer write to the
   production database (§5.4).
3. **Would we know if it broke?** **Two surfaces of three** — this line said
   "Closed 2026-08-12" and over-claimed (corrected 2026-08-18 by verifying each
   surface against the deployed artifact rather than the source):
   - **backend — yes.** `SENTRY_DSN` is mounted on the serving revision with a
     real `RELEASE`, and production logs carry the request id that tags the event.
   - **web — yes.** The deployed bundle on `myweli.com` contains a live DSN and
     its own project id, with `environment=production` and the release set to the
     HEAD commit.
   - **app — NO.** `sentry_flutter` is wired, but **no mobile DSN exists**:
     Secret Manager holds one `SENTRY_DSN` and it is the backend's. Release
     builds carry no `--dart-define=SENTRY_DSN`, so mobile crash reporting is
     **code-complete and inert** (§5.2).
   Uptime checks on `/health` and a database-backed route are live and alerting
   to a human, verified against real probe data
   (§5.2, [design/observability-error-reporting.md](design/observability-error-reporting.md)).

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

**Designed in detail in [design/infra-staging.md](design/infra-staging.md)** — **$13–17/month**. It was blocked on three code changes, all now landed (phase 1), plus six production bugs found while auditing the project ([design/infra-prod-hardening.md](design/infra-prod-hardening.md), phase 2). Among them the one that made §5.1 below *untickable*: `seedProvidersIfEmpty` was gated only on the `providers` table being empty, not on `ENV`, so purging the demo salons and deploying re-created them. **Fixed — the purge will now stick.** **Staging is now built and serving** (2026-08-16): its own Cloud Run service, Cloud SQL instance, secrets, PITR and alerting, deploying itself on every merge to `main`.

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
`consumer`/`pro` flavours, and the staging backend to point at now exists. What
is missing is a build actually pointed at it — no TestFlight or internal-track
build has been produced at all (§6.2, §6.3).

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
| Per-PR web previews | ✅ Vercel builds every PR, and since 2026-08-18 they talk to **staging** (§5.4) |
| Backend `ENV` seam | ✅ a three-value enum (`dev`/`staging`/`prod`) splitting `guardsOn` from `isProd`; an unknown value throws at boot |
| App environment switch | ✅ `API_BASE_URL` + `USE_API_BACKEND` dart-defines |
| Flavours (consumer/pro, both platforms) | ✅ |
| CI: analyze, unit, widget, golden, e2e, APK size, secret scan, funnel smoke | ✅ strong |
| Release signing + store prep | ✅ repo side (#337); accounts pending |
| **Staging environment** | ✅ **complete** — `myweli-api-staging` + `myweli-db-staging`, auto-deployed on merge, PITR on, alerting on, **and Vercel Preview pointed at it** (both `API_BASE_URL` and `NEXT_PUBLIC_API_BASE_URL`). The web half closed 2026-08-18 (§5.4) |
| **Crash / error reporting** | ⚠️ **two of three live** (re-verified 2026-08-18 against the deployed artifacts, not the source): **backend** reports with a real release and the request id; **web** ships a DSN in the bundle served from `myweli.com`; **app is inert** — `sentry_flutter` is wired but no mobile DSN exists and no release build defines one |
| **Uptime alerting** | ✅ **live 2026-08-12** — two Cloud Monitoring checks on `api.myweli.com` (`/health` for the process, `/providers` for the database, because `/health` reported ok right through the Render outage), alerting to email when 2+ regions fail for 5+ minutes. Verified against real probe results, not just created ([design/observability-error-reporting.md](design/observability-error-reporting.md) §8.5) |
| **Forced upgrade** | ❌ nothing |
| **Production data hygiene** | ✅ **purged 2026-08-12** — `provider1`–`provider4` deleted, and the purge **survived a forced cold boot** (revision 00014), which is the proof the gate holds. Production now serves zero salons |
| **Backup / restore rehearsal** | ✅ **rehearsed end to end** — restore *and* promotion. A PITR clone recovered data production no longer had (2026-08-12, ~23 min); a second, cleaner run took **26 min 14 s** and found five traps (2026-08-16); and **promotion** — the step that actually ends an incident — was rehearsed at **17 s**, disproving the `DATABASE_URL` mechanism four docs had recorded (2026-08-17, [design/infra-dr-restore.md](design/infra-dr-restore.md) §8). Both numbers are floors, measured on 10 MB |

---

## 3. Launch order, and why

**Web → iOS → Android.**

- **Web first** because it is the only surface we can fix in minutes. Every
  early mistake — copy, pricing, a broken funnel — is a redeploy rather than a
  store review. It also lets real salons and clients use the product while the
  app is still in TestFlight, so the app launches into something that already
  works.
- **iOS second** because it is furthest along (account exists, signing prepared)
  and because App Store review is the slower gate — starting it while web is
  live costs nothing. *This line used to say "Sign in with Apple working"; it is
  not — the entitlement is absent from both entitlements files (§6.2).*
- **Android last.** It has the most outstanding work (no keystore, no Play
  account, R8 unproven) and the widest device variance, which is where the
  reference low-end Android in ROADMAP §6 has to be honoured.

Each surface has a hard prerequisite: **the one before it is live and stable for
at least a week**, with §5.2's monitoring proving it rather than our impression.

---

## 4. Before ANY launch — the shared gate

These block everything. None is surface-specific.

- [x] **Staging exists** and the full funnel has been rehearsed on it end to
      end. **Done 2026-08-18 — 47/47 assertions**, against
      `myweli-api-staging-00014-v6h`: sign-in, salon registration, the go-live
      gate, booking, the pro accepting, cancellation, suspension and every
      refusal in BACKEND.md §5's required list.
      **It had never been run there, and that hid three things:**
      - the harness needed `SMOKE_OTP_SECRET` mounted on staging, since closing
        the `devCode` echo took away its old way in;
      - two assertions were about the **dev fixture**, not the platform — a
        seeded catalogue that only `Env.dev` has, and a `cdn.stub` gallery URL
        that only an empty origin allowlist accepts. Both would have failed
        against production too;
      - the gallery now **uploads for real** (presign → PUT → promote), which
        makes this the first thing in the repo to exercise **R2 end to end**.
      The web half still needs §5.4's preview — which is done, so the remaining
      web rehearsal is a manual walk.
- [x] **Production contains no seeded/demo data** (§5.1). **Closed 2026-08-18**,
      in two halves a month apart.
      - **Demo salons** — purged 2026-08-12 and still gone: `/providers` →
        `total: 0`, with the `ENV` gate that makes it stick in the deployed
        image.
      - **Smoke-test residue** — the Q1b seam ran against production on
        2026-08-06 (production logs show the `SMOKE_OTP_SECRET is set` warning
        and three `POST /auth/email/otp/verify → 200`), and
        [design/backend-q1b-smoke-seam.md](design/backend-q1b-smoke-seam.md) §7's
        "purge by identity suffix" was never run. Erased 2026-08-18 through the
        new `DELETE /admin/users/{id}/erase`, so the tested cascade ran instead
        of hand-written SQL. Verified: **5 → 2 users**, three `user.erase` audit
        rows, and a repeat call returns 404 rather than crashing.
      - **The count in this line was wrong, and it mattered.** It said "the ~5
        `users` rows the PITR restore found", equating the residue with the whole
        table. Two of those five are the owner's own sign-ins — one Google, one
        Apple — so purging "the 5" would have deleted them. Reading the table
        before deleting from it is the only reason that did not happen, and it is
        the reason this checklist now records **what was verified**, not what was
        remembered.
- [ ] **Crash reporting and error tracking** are live on backend, web and app,
      and have been *proven* by deliberately triggering an error and seeing it
      arrive. **The code is done on all three surfaces and is inert**: create the
      Sentry org and three projects, set the DSNs, then prove it. Until that
      happens this box is not merely unticked — it is untestable, and a
      dashboard that has never received an event is indistinguishable from one
      that is not wired up. **Updated 2026-08-18: two of the three are now
      live** (backend, web — DSNs verified on the deployed artifacts). What
      remains is the **mobile** project and DSN, and the deliberate trigger on
      web and app.
- [x] **Uptime alerting** on `api.myweli.com` reaching a human. Done
      2026-08-12 — and on **two** paths, not one: `/health` never touches the
      database, so a check on it alone would miss the outage where the service
      is up and useless.
- [x] **A database restore has actually been performed.** Done 2026-08-12 by
      cloning to a point six minutes before the demo-salon purge: the clone came
      back holding all four salons — data production no longer has. **~23
      minutes** end to end, which is the number to plan an incident around
      (§8 of the hardening doc).
- [ ] **Secrets rotated** away from any value that has been in a terminal, a
      log, or a chat during development. **One was exercised for real**:
      `CRON_SECRET` was printed into a working transcript on 2026-08-18 and
      **deleted** rather than rotated, because the header it authenticated had
      just been retired ([design/infra-cron-oidc-evidence.md](design/infra-cron-oidc-evidence.md) §8).
      That is the cheapest possible outcome and not evidence the others are
      clean — every remaining secret still needs the same question asked of it.
- [ ] **Legal pages live and accurate** — CGU, privacy policy, mentions légales
      (the RCCM line is still "not registered"; that must be true or updated).
      **The privacy policy is live and contains two false statements** (found
      2026-08-18 by reading the deployed page and the deployed bundle side by
      side). Both were true when written and were made false by later changes,
      which is exactly why "accurate" needs re-checking rather than remembering:
      1. « aucun rapport de plantage tiers — pas de Sentry, pas de Crashlytics »
         — the bundle served from `myweli.com` posts to `ingest.de.sentry.io`.
      2. « aucun journal applicatif : notre serveur n'enregistre ni votre
         adresse IP, ni votre navigateur, ni le détail de vos requêtes » —
         Cloud Run logs all three on every request.
      A privacy policy is a **representation to users and to the App Store**;
      a false one is not a documentation bug. Corrected in the same change that
      found it, with the French still owed a review per §"Legal" below.
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

- [x] Seeding runs **only** when `ENV != prod`, enforced in code rather than by
      remembering. **Done** — two independent gates: the call site
      (`dependencies.dart` `if (_env == Env.dev)`) and `seedProvidersIfEmpty`
      itself, which throws before any query for anything but `dev`. Pinned by
      `backend/test/db/seed_gate_test.dart`, and the commit is an ancestor of the
      serving revision.
- [x] Production database purged of seed rows before the first real salon.
      **Done 2026-08-12** and still true four revisions later: `/providers` →
      `total: 0`, and the seed ids/slugs 404. (Test-account residue is a
      separate item — see §4.)
- [ ] The `asset:` image convention retired for real salons — they upload to R2
      (the convention exists only to serve the demo set; see §21 row 90).
      **Nothing enforces it**: `asset:` is still accepted by the gallery origin
      allowlist in every environment. It holds today only because no real salon
      has uploaded yet. Gate it on `Env.dev` and add a test that a
      prod-configured gallery PUT rejects an `asset:` URL.

### 5.2 We would not know if it broke

No Crashlytics, Sentry, or equivalent anywhere. Today a crash on a user's phone
is invisible to us forever; a 500 in the backend exists only in Cloud Run logs
nobody is watching.

- [ ] **App**: Crashlytics (Firebase is already wired) or Sentry, on both
      flavours, with the release version attached. **Code done, inert** —
      `sentry_flutter` is wired and scrubs hard, but **no mobile DSN exists**
      (Secret Manager has one `SENTRY_DSN` and it is the backend's) and no
      release build passes `--dart-define=SENTRY_DSN`. Create the `myweli-app`
      project, then build with the define.
- [x] **Backend**: structured error reporting to the same place, with the
      request id already in the logs. **Done** — verified on the serving
      revision, not in source: `SENTRY_DSN` mounted, `RELEASE` a real short SHA,
      and production logs show `unhandled_route_error request_id=… method=… path=…`
      with the same id tagged on the event.
- [x] **Web**: browser error reporting. **Done** — verified in the *deployed*
      bundle on `myweli.com`, which carries its own DSN, `environment=production`
      and `release=<HEAD sha>`; error boundaries and scrubbing are in
      `app/error.tsx`, `app/global-error.tsx`, `lib/sentry-scrub.ts`.
- [ ] **Prove it**: trigger one real error per surface and watch it arrive.
      **One of three.** Backend has a flush record; web has never been triggered
      against production; mobile is blocked on the DSN above.
- [ ] Alert thresholds agreed — what crash rate halts a staged rollout. The
      number must land **in this document**, not only in a design doc, and the
      crash-free-sessions alert is blocked on the mobile DSN.

### 5.3 No forced-upgrade path

Per §1.4 we cannot recall a release. Without a minimum-version check we can also
never *retire* one.

**Nothing has been built** (verified 2026-08-18): no min-version field in
`openapi.yaml`, no such route, and no startup check in either flavour. It is
also the one gate that is **cheaper before the first release than after** — a
v1.0 shipped without the check can never be told to update, so the floor can
only ever apply from v1.1 onward. That makes this an iOS-blocker, not a
post-launch item.

- [x] Backend exposes a minimum supported client version. **Done 2026-08-18** —
      `GET /client-version`, the floor in the database so it moves in seconds
      rather than a revision rollout
      ([design/client-version-gate.md](design/client-version-gate.md)).
- [x] App checks it at startup and, below the floor, blocks with a « Mettre à
      jour » screen rather than failing in strange ways. **Done** — both
      flavours, decided before the first frame, and **failing open on every
      ambiguity** so a flaky network never bricks a working app.
- [x] Chosen deliberately: this is the only lever that works on a phone we
      cannot reach. **And it is set from the admin console**, not SQL.
- [ ] **Still owed: the iOS `updateUrl`.** It stays NULL until the App Store
      Connect record mints an `adamId`, and the server refuses to block a
      platform it has nowhere to send — so the mechanism is safe today and the
      iOS half is inert until that listing exists.

### 5.4 Web previews DID write to production — ~~confirmed 2026-08-12~~ **fixed 2026-08-18**

Not "may". `NEXT_PUBLIC_API_BASE_URL` is a **single Vercel entry scoped to
Production *and* Preview**, so one value serves both — and since production
works, that value is the production API.

**Every PR preview therefore reads and writes the production database.** A
preview deployment can create real accounts and real bookings against real
salons, and nothing distinguishes them from genuine ones afterwards.

It is harmless *today* and only today: the marketplace is empty (§5.1) and there
are no users. It stops being harmless the moment a real salon signs up.

**The sequencing that followed, which was the real point:** the fix is to point
Preview at staging, and **staging did not exist** (phase 3 of
[design/infra-staging.md](design/infra-staging.md)). There was no good interim
patch either — pointing Preview at nothing breaks the build, and pointing it at
localhost publishes a preview with no salons and no error, which is the failure
§1.3 was built to prevent.

So this is not a task that can be scheduled freely. **Staging must exist before
the first real salon is onboarded**, or previews have to be switched off until
it does. That is a launch-order constraint, not a backlog item.

**Done 2026-08-18.** Preview points at the staging `*.run.app`; Production keeps
`https://api.myweli.com`. Four things this section had wrong, all found by
checking rather than assuming:

1. **It named one variable; two were scoped Production+Preview.** `API_BASE_URL`
   is the one the BFF actually reads (`resolveApiBase()` prefers it over the
   `NEXT_PUBLIC_` one), so splitting only the public one would have left every
   preview talking to production while *looking* split.
2. **The staging `WEB_ORIGINS` change this section demanded was never needed.**
   No browser call crosses origins: the web is a BFF with 72 same-origin route
   handlers, and 227 observed requests across five production pages went to
   `myweli.com` without exception. An exact-match allowlist could not have
   covered previews anyway — Vercel mints a hostname per deployment.
3. **That property was true but unenforced, and eroding.** The API base already
   shipped in four client chunks (via pure helpers living beside a fetcher),
   with `createClient()`'s result discarded. Now `web/lib/api/client.ts` carries
   `import 'server-only'`, so a client component that imports it fails the build
   by name. Measured after: **0** client chunks carry the API base.
4. **There IS a CORS wall — Cloudflare R2, not the backend.** Browser uploads
   (gallery, before/after, KYC, deposit proof, review photos) PUT *directly* to
   R2, whose staging allowlist is `http://localhost:3000`. **Uploads do not work
   on previews.** Accepted deliberately; see §6.1.

- [x] Split the API base into two Vercel scopes — Production →
      `https://api.myweli.com`, Preview → the staging service. **Done
      2026-08-18**, for **both** `API_BASE_URL` and `NEXT_PUBLIC_API_BASE_URL`,
      and verified by reading the values back per scope and by a real preview
      deployment — not from the dashboard.
- [x] ~~Until then, treat every preview deployment as writing to production, and
      do not exercise booking or registration flows on one.~~ **No longer
      necessary.** The production `users` table still carries the test accounts
      from an earlier seam run (§4) — the residue of exactly this hazard, and
      still owed a purge.

### 5.5 Backups are unrehearsed — **rehearsed 2026-08-16**

- [x] Restore `myweli-db` from PITR and confirm the data. **Done** —
      [design/infra-dr-restore.md](design/infra-dr-restore.md). We now know we
      have backups: a point-in-time clone came up with **31 migrations and 39
      tables** intact, in **26 min 14 s**.
      - Restored into a **standalone instance**, not staging as this line
        originally said. Staging is `ingress: all` and echoes OTP dev-codes, and
        production holds 5 user rows — small, but not nothing
        (infra-staging.md §2.1).
      - **26 minutes is a floor**, measured against a 10 MB database. Quote the
        RTO as *"at least half an hour"* and expect it to grow with the data.
      - Five traps found, all of which read as a different problem — the worst
        being that Cloud SQL's `postgres` role cannot see the app's tables, so a
        healthy restore reports **zero tables**.
- [x] **Promotion rehearsed 2026-08-17** (infra-dr-restore.md §8) — and it is
      **not** a `DATABASE_URL` change, which four documents including this line
      claimed. The instance is named in the service manifest **twice** (the
      `cloudsql-instances` annotation and the proxy's argv); `DATABASE_URL` holds
      `127.0.0.1:5432` and names no instance. Promotion is a **two-line diff plus
      a deploy — 17 s**, with every secret untouched and no IAM step.
      - **Commit the change.** A hand-edited service config is reverted by the
        next deploy of the committed manifest — the same trap as a rollback
        traffic pin.
      - The **write-loss window** (everything written after the restore point)
        is the only part that stays a judgement call. No rehearsal can remove it.
- [ ] **Still owed:** RTO against real data. 26 min is the empty floor.

---

## 6. Per-surface checklists

### 6.1 Web (first)

- [ ] Lighthouse/CWV budgets green on the real domain, not a preview.
- [ ] SEO: sitemap, robots, canonical URLs, JSON-LD validating.
- [ ] The full funnel on a real phone browser on a slow connection.
- [ ] 404 and error states reachable and correct.
- [ ] Analytics decision made (we currently have none — deliberate or not).
      **Still none** — and the privacy policy states this as a promise, so
      adding any is a policy change, not just a config one.
- [ ] Install-the-app prompts point somewhere real, or are hidden until the apps
      exist. **They currently promise apps that are not published.**
- [ ] **Uploads cannot be exercised on a preview** — the browser PUTs straight to
      Cloudflare R2, and R2's staging allowlist is exact-match on
      `http://localhost:3000` while Vercel mints a hostname per deployment. Test
      uploads locally, or pin one stable preview alias and allowlist it. The
      failure is now **reported** (`lib/upload-telemetry.ts` tags
      `upload_likely_cors`), where before it produced no signal at all — a user
      saw « Le téléversement a échoué. » and we saw nothing.

### 6.2 iOS (second)

- [ ] Everything in [mobile-store-submission.md](design/mobile-store-submission.md) §5.
      Two of its claims are **stale as of 2026-08-18** and must be corrected
      before they are relied on: the Sign in with Apple line below, and the §4
      privacy table, which still answers "no third-party crash SDK" although
      `sentry_flutter` ships in the app. An App Store privacy answer that
      contradicts the binary is a rejection *and* a legal exposure.
- [ ] A **signed** build verified — production `aps-environment` baked, not just
      configured, and a real push received from the production FCM project.
- [ ] TestFlight internal build exercised by someone other than the developer.
      **No *signed* build exists** — the only archive ever produced was built
      `--no-codesign` (submission spec §6), which is why the box above says the
      production `aps-environment` is configured but not baked. Nothing has been
      uploaded anywhere, so every remaining line in §6.2 is downstream of one
      signed archive.
- [ ] Screenshots, description, keywords, age rating, privacy questionnaire.
- [ ] Sign in with Apple working in the signed build (rule 4.8). **Repo half
      done 2026-08-18** — `com.apple.developer.applesignin` is in both
      entitlements files, pinned by `test/infra/ios_entitlements_test.dart`
      (which also catches the shape where the key exists only in a comment).
      **Account half still owed, and it gates the first signed archive:** the
      capability must be enabled on the App ID for both bundle ids, or code
      signing *fails* — an entitlement the App ID does not grant is an error,
      not a no-op.
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

---

## 8. Reconciled 2026-08-18 — what is actually left

Every box above was re-checked against the **deployed** artifact rather than the
source or the design docs, in both directions: a box ticked that is not true is
worse than one left unticked. Four were ticked, one was **unticked** (production
data hygiene — §4), and a dozen gained the specific reason they are not done.

**What the re-check cost, which is the argument for doing it again before
launch:** three claims in this file were false, and every one had been true when
written. Staging "does not exist" (it does), Sign in with Apple "working" (the
entitlement is absent), error reporting "closed on all three surfaces" (mobile
has no DSN). The same drift had reached the **live privacy policy**, where two
statements had become false — corrected in this change, and now pinned by a test
that fails if the page denies a vendor listed in `package.json`.

Ordered by what unblocks what, not by size:

0. ~~**Stop staging handing out OTP codes.**~~ **Done 2026-08-18**, and it was
   not on this list because nobody knew: staging is `ingress: all` with a
   hostname in a public repo, and returned a `devCode` for **any** address — so
   anyone could hold a session there as anyone. (No mail was involved: staging's
   Resend key is a deliberate dud. An adversarial review caught that
   overstatement before it shipped.) Found by asking what pointing previews at
   staging would actually expose
   ([design/backend-staging-otp-disclosure.md](design/backend-staging-otp-disclosure.md)).
1. ~~**Point Vercel Preview at staging**~~ **Done 2026-08-18** (§5.4), closing
   §0's question 2. It needed **two** variables rather than the one this list
   named, needed **nothing** from staging's `WEB_ORIGINS`, and surfaced a CORS
   wall in Cloudflare R2 that no document had mentioned.
2. ~~**Purge the smoke-test accounts from production**~~ **Done 2026-08-18**
   (§4) — and the target was 3 rows, not the 5 this list had claimed; the other
   two are the owner's real accounts.
3. **Create the mobile Sentry project and DSN** (§5.2), then prove one real error
   per surface. This also unblocks the crash-rate threshold, which §1.4's staged
   rollout is defined in terms of — so it is an iOS prerequisite, not telemetry
   nice-to-have.
4. ~~**Minimum supported version**~~ **Done 2026-08-18** (§5.3), in three
   slices. The mechanism is in the first build, which was the whole point of the
   ordering; every floor ships at 0, so it changes nobody's behaviour until
   someone deliberately raises one.
5. **Enable Sign in with Apple on the App ID** (§6.2) — the entitlement landed
   in the repo on 2026-08-18, but the capability must be granted for both bundle
   ids or the first signed build fails to sign at all.
6. **Rehearse the funnel on staging** (§4) — `funnel_smoke_test.dart` already
   takes `SMOKE_BASE_URL`, so this is a host, not a project. **One prerequisite
   arrived on 2026-08-18:** staging no longer echoes OTP dev-codes, so the
   harness needs `SMOKE_OTP_SECRET` mounted on the staging service — the seam it
   was built for. Not done, deliberately, since nothing runs the funnel against
   staging yet.
7. The rest of the §4 gate, none of which is unblocked by anything above: the
   secrets audit, the support channel, rate limiting against a real hostile
   pattern, and the walk-through by someone who did not build it.

Items 1 and 2 are **closed**. Item 6 is the one that stops being safe the moment
a real salon signs up. Items 3, 4 and 5 become expensive the moment a build is in
someone's hands. Nothing here is large; the ordering is the whole content.

**What the two closed items cost, since it is the argument for the next one.**
Neither was the work the list described. Item 1 needed two Vercel variables
rather than one, needed nothing from the backend allowlist it had demanded for
months, and surfaced a CORS wall in Cloudflare R2 no document had named. Item 2
named five rows when the target was three, and two of the other five were the
owner's own accounts. In both cases the list was written from what was
remembered; both were corrected by reading the live thing first. That is the
habit worth carrying into item 6, not the estimates.
