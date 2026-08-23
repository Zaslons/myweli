# Staging — design

| | |
|---|---|
| **Module** | infrastructure (`infra/gcp/`, `backend/`, `.github/workflows/`) |
| **Status** | **Phases 1 and 2 complete.** §1's three code changes and the local environment (§2.2) are done; §7's six production bugs are fixed ([infra-prod-hardening.md](infra-prod-hardening.md)). **No staging resource exists yet** — that is phase 3. |
| **Decisions** | Staging URL = `*.run.app` (§4.1) · separate bundle ids, deferred to phase 8 (§4) |
| **Cost** | **$13–17/month** — the $18.25 hostname is declined (§4.1) |
| **Related** | [LAUNCH.md](../LAUNCH.md) · [infra-gcp-migration.md](infra-gcp-migration.md) · [DEPLOYMENT.md](../DEPLOYMENT.md) |

Grounded in the live project: `myweli` (731308991240), `europe-west9` (Paris),
Cloud Run `myweli-api` rev `myweli-api-00012-mzb`, Cloud SQL `myweli-db`
(db-f1-micro, ZONAL). Prices are from the live Cloud Billing catalog for
europe-west9, not list-price guesses.

---

## 1. Three code changes that must land FIRST

Creating the staging resources before these is worse than having no staging: it
produces an environment that is confidently wrong.

### 1.1 `ENV` is binary, and neither value is safe for staging — **DONE**

`dependencies.dart:102` — `bool get _isProd => (Platform.environment['ENV'] ?? 'dev') == 'prod'`.

One flag conflates two independent questions: *which environment is this?* and
*are the production guards on?* That leaves staging with no correct setting:

| Setting | What happens |
|---|---|
| `ENV=prod` | correct guards, but staging is indistinguishable from production in every log line, header and error path |
| `ENV=staging` | **every guard silently turns off** — `DATABASE_URL`/`JWT_SECRET` stop failing fast, the R2/FCM/Google/Apple/Resend config guards go quiet, CORS opens, and OTP responses echo `devCode` |

`ENV=staging` is the natural choice and it makes staging **not
production-shaped**, which is the one property staging exists to have. Every
deploy would pass.

**Change:** parse a three-value enum `{dev, staging, prod}` and split the two
questions — `guardsOn = env != dev`, `isProd = env == prod`. Staging then runs
production's guards while remaining identifiable.

**Landed.** `Env` lives in `boot_config.dart`; an unrecognised value now throws
at boot rather than degrading to `dev`. Of the eighteen `_isProd` call sites,
**thirteen became `guardsOn`** (every fail-fast, plus CORS deny-by-default) and
**five stayed `isProd`** — the four auth-repository `devCode` echoes and the
smoke-seam warning. *(The four echoes moved again on 2026-08-18, to a third
getter `echoesOtpDevCode` that is `dev`-only — see §2.1's resolved note. Two
questions turned out to be three.)* One gap the split exposed: with `guardsOn` on, staging would
have refused to boot without FCM, so `PUSH_PROVIDER=disabled` was added,
mirroring `MESSAGING_PROVIDER=disabled`.

### 1.2 Seeding has no environment check, so purging production does not stick — **DONE**

`seedProvidersIfEmpty` (`dependencies.dart:788`) is gated on **one** condition:
the `providers` table being empty. Not on `ENV`.

So the sequence LAUNCH.md §4 requires — purge the demo salons, then deploy —
**re-creates them**. Any deploy does. So does a `minScale` instance recycle. The
§5.1 box *"seeding runs only when `ENV != prod`"* is not merely unticked; it
cannot be ticked without this change.

**Change:** `if (env == Env.dev) await seedProvidersIfEmpty(pool);`, and make
`seedProvidersIfEmpty` itself throw when called with prod-shaped config so the
guard survives a refactor.

**Landed**, both halves. `seedLocalitiesIfEmpty` is deliberately *not* gated —
the Ivorian geography tree is genuine reference data, not demo content. The
refusal is proven to fire **before any query**, so it is safe against a
production pool.

### 1.3 The API base has silent fallbacks on every build path — **DONE**

- `app_config.dart:15-23` — `USE_API_BACKEND` defaults **false**, `API_BASE_URL`
  defaults to `http://localhost:8080`
- `web/lib/server-api.ts:4-7` — falls back to `http://localhost:8080`

A staging TestFlight build missing one `--dart-define` does not error. It runs
**entirely on in-app mocks**: full salon list, working search, bookings that
appear to succeed. It looks like a healthy staging environment and is testing
nothing. This is the failure mode most likely to waste a week.

**Change:** make it fail closed — a release build asserts `useApiBackend` is
true and `apiBaseUrl` is non-default; the web BFF throws instead of defaulting.

**Landed, and the web half turned out to be the worse of the two.** The mobile
failure is silent *success*; the web fallback looked like a loud failure
(connection errors) and is not — `lib/api/localities.ts` and
`lib/api/providers.ts` degrade to **empty results**, and the ISR pages call them
during `next build`. A production deploy missing the variable therefore
published a marketplace with **no salons in it and no error anywhere**.

Both now refuse: the app shows a blocking `BUILD MISCONFIGURED` screen in
release (verified by building a real release web bundle with and without the
defines), and `web/lib/api-base.ts` throws in production. CI's two web builds
now state their API base explicitly — they had been building against the
localhost fallback all along.

### 1.4 The `guardsOn` fail-fasts did not actually fire at boot — **DONE**

Found while building phase 3, and it falsifies a premise of §1.1 above: "with
`guardsOn` on, staging would have refused to boot without FCM" was **not true**.
Only three guards were ever boot-fatal — `ENV`, `DATABASE_URL`, `JWT_SECRET`.
Every other one is a lazy Dart `final` handed to routes through
`provider<T>((_) => x)`, and a lambda is not an evaluation, so each fired on the
first request that reached a route needing it.

The consequence lands squarely on this document's build order: `/health` reads
nothing, `/providers` reads only the repository and the slot service, and those
two are exactly what `deploy-backend.yml`'s verify step checks. **A staging
service missing every lazy secret would have deployed green.** The environment
whose entire job is to be a rehearsal would have been unable to tell you it was
misconfigured — and neither could production.

`_assertConfiguredDependenciesResolve()` now forces all eleven inside
`initializeDatabase()`, before `serve()`, reporting every failure in one error.
Two fixes rode with it: `WEB_ORIGINS` joined the guarded set (an unset value
blocks the web app and admin console while the service looks healthy), and
`STORAGE_PROVIDER=disabled` gives storage the escape hatch §1.1 gave push —
with the gallery's origin allowlist now derived from the storage service in use,
so switching storage off cannot switch the origin check off with it. See
docs/BACKEND.md §3.2.2.

---

## 2. Architecture — what is separate, what is shared

The rule from LAUNCH.md §1.1: **same shape, never the same data.** Applied
resource by resource, with the reason each way.

| Resource | Decision | Why |
|---|---|---|
| Cloud Run service | **separate** `myweli-api-staging`, minScale **0**, maxScale 2 | Saves $18/mo vs matching prod's minScale 1, and *improves* the rehearsal: every staging request then exercises the cold start that runs migrations behind `pg_advisory_lock` before the port binds |
| Cloud SQL | **separate instance** `myweli-db-staging` | Not for tidiness — the arithmetic was already red: `maxConnectionCount: 8` × maxScale 4 = **32** against a db-f1-micro whose default `max_connections` is **25**. Lowered to **4** in phase 2 PR D (4 × 4 = 16 inside the ~22 actually usable), so the ceiling is no longer breached — but sharing the instance would still add a second consumer to a budget with no room for one |
| Database data | **synthetic by default; a scrubbed prod copy for rehearsals** | §2.1. An empty staging DB certifies every migration as instant (§3.2), but an un-scrubbed prod copy puts real phone numbers behind a reminder cron (§3.3) |
| Secret Manager | **separate versions** — the **18** `service.yaml` mounts, not all 20 that exist | `JWT_SECRET` especially: a shared value lets a staging-issued token authenticate against **production**, and staging is where we deliberately mint admin tokens. `SMOKE_OTP_SECRET` is unmounted, and `R2_ENDPOINT` is a secret with **zero versions** deliberately left unreferenced (it is derived from `R2_ACCOUNT_ID`) — anyone scripting "twin every secret" copies a stray. The single exception worth sharing is `SENTRY_DSN`: `error_reporter.dart` already tags events with `Env`, so staging lands in the same project tagged `staging` |
| R2 | **3 separate buckets + a bucket-scoped token** | Bucket *names* cannot collide (unique per account). The risk is the **credential**: an account-scoped token reads and writes every bucket regardless of what `R2_BUCKET` says. A staging run of the user-erasure path would delete production objects. Provisioned by [`infra/cloudflare/90-staging-r2.sh`](../../infra/cloudflare/90-staging-r2.sh); the scoping is **proven**, not assumed, by `backend/test/storage/r2_token_scope_test.dart` |
| `WEB_ORIGINS` | **separate**, staging origins only | Copying prod's value means staging accepts browser calls from `https://myweli.com`. When a preview gets CORS-blocked, the fix is a staging origin — **never** widening prod's list |
| ~~`CRON_SECRET`~~ | **retired 2026-08-18** | It was separate per environment, and both Scheduler jobs carried it as a literal `X-Cron-Secret` header (§7). Now removed everywhere — OIDC is the only cron auth ([infra-cron-oidc-evidence.md](infra-cron-oidc-evidence.md) §8) |
| `MESSAGING_PROVIDER` | **`disabled`, and it stays that way** | §3.3 |
| Artifact Registry | **shared** — same `:${SHA}` image | Deploy the identical immutable digest to staging, then promote **that same digest** to prod. A separately built prod image is a different artifact and defeats the rehearsal |
| Firebase / FCM | **separate project**, from phase 8 | Enabled by §4's separate bundle ids. Until phase 8 the app is not part of staging at all, so there is nothing for a staging Firebase project to serve — and sharing prod's would put staging pushes on real phones |
| Ingress | **`all`** on staging, using the **`*.run.app` URL** — *not* prod's `internal-and-cloud-load-balancing` | Copying prod's value verbatim makes staging unreachable by its own cron, and Cloud Run domain mappings are unimplemented in europe-west9. The $18.25 hostname is **declined** — see §4.1 |

### 2.1 No shared database — and what data staging actually holds

**Staging and production never share a database.** Not the same instance, not
the same instance with two databases on it. The connection arithmetic above is
the local reason; the general one is that a shared database makes staging a
production client, which is the exact thing it exists not to be.

But "separate database" leaves a second question, and §3.2 and LAUNCH.md §1.1
pull in opposite directions on it. Resolving it explicitly:

| | Data | When |
|---|---|---|
| **Default state** | **synthetic**, seeded by a committed script, ids namespaced `stg_` | always — this is what staging looks like day to day |
| **Migration rehearsal** | a **prod-volume copy, anonymised on the way in** | deliberately, before a release carrying a schema change |

LAUNCH.md's rule — *never the same data* — stands. The rehearsal copy is not
shared data; it is a **derived, scrubbed snapshot**, and the scrub is not
optional:

- `appointments.client_phone`, client names and emails **replaced**, not
  obscured. Staging's reminder cron reads those columns, and
  `MESSAGING_PROVIDER=disabled` is a setting one person can change (§3.3).
- Anything that could identify a real salon or client. Copying real personal
  data into a lower-trust environment is a data-protection question in Côte
  d'Ivoire as much as a technical one, and it is easier to never hold it than to
  justify holding it.
- The scrub belongs **in the restore script**, so an un-scrubbed restore is not
  a thing anyone can do by forgetting a step.

> **RESOLVED 2026-08-18 — and the resolution is broader than any of the three
> options below.** The dev-code echo is now gated on `Env.dev` alone, so **no
> deployed environment discloses an OTP** and the tension disappears rather than
> being managed: a public ingress no longer implies a signable identity, whatever
> database is attached. That is option 3 without its hard part — no "is this a
> derived copy?" marker is needed, because the answer does not depend on the data.
>
> Worth recording how it was found, because the process failed here. This block
> said **"Decide before build-order step 5"**. Step 5 happened — the restore was
> rehearsed on 2026-08-16 — and no decision was made or noticed; the item was
> simply passed over. It surfaced two days later from an unrelated direction,
> while checking whether the Vercel preview split was safe. **A deadline written
> into a design doc is not a mechanism.** The mechanism is
> `backend/test/auth/staging_otp_disclosure_test.dart`, which fails if the echo
> comes back.
>
> The original entry, for the record:
>
> > **OPEN — the rehearsal copy and the public ingress are in tension.** Surfaced
> > while writing `service-staging.yaml`, which needs a truthful comment about what
> > the open ingress exposes. Staging is `ingress: all` with no load balancer (its
> > `*.run.app` URL is the only door, §4.1) *and* it echoes the OTP dev-code,
> > because `ENV=staging` is `guardsOn` but not `isProd` — so **anyone who finds
> > the URL can sign in as any identity in whatever database is attached.**
> >
> > For the synthetic default state that is the design working as intended. For
> > the rehearsal row it is not: the scrub replaces phones, names and emails, and
> > leaves the appointments, deposits and KYC references around them intact and
> > real-shaped. A prod-volume copy behind that ingress is readable by an
> > unauthenticated caller who guesses the hostname.
> >
> > Three candidate resolutions, none chosen yet: restore into a **temporary
> > instance not attached to the public service** (cleanest, but then the
> > rehearsal is not timing the real service's boot, which is the point of §3.2);
> > **close the ingress for the duration** of a rehearsal; or **suppress the
> > dev-code echo when the database is a derived copy**, which needs a marker the
> > app can read. **Decide before build-order step 5**, which is where the restore
> > first happens.

Namespacing matters more than it sounds: `seedProviders` uses fixed ids today,
so a staging and a production database contain the **same primary keys**. A log
line or a screenshot showing `provider3` is then ambiguous about which
environment produced it — for the entire life of the project.

### 2.2 The four environments, and which one you actually work in

| | Where | Data | What it answers |
|---|---|---|---|
| **local** | your Mac | throwaway Postgres, or in-app mocks | "does my change work at all?" — the loop you live in |
| **preview** | Vercel, per PR | staging's | "does this branch's web work?" — automatic, already exists |
| **staging** | GCP | synthetic; scrubbed prod copy for rehearsals | "does it work for someone who is not me, against a real backend?" |
| **production** | GCP | real | the product |

**Local is where you will spend almost all your time**, and it is the one this
project has never written down. There is no `docker-compose.yml` and no
documented way to run the backend locally; CI stands up `postgres:16` with
`postgres://postgres:postgres@localhost:5432/myweli_test` (`ci.yml:85-121`) and
that definition exists **only inside the workflow file**.

So phase 1 gains a piece: a committed `docker-compose.yml` at the repo root
giving you Postgres 16 on one command, matching CI's image exactly, plus a
`SETUP.md` section for `dart_frog dev`. **Landed** — `docker compose up -d`,
then `dart_frog dev`, with the Android-emulator host alias written down because
`localhost` there is the emulator itself. Two reasons it belongs here rather than
in "nice to have":

1. Without it, "test it locally first" has no definition, so the honest path of
   least resistance is testing against staging — which turns staging into
   everyone's local environment and makes it unavailable for its actual job.
2. It is the cheapest environment by a wide margin. Every bug caught locally is
   one that never occupies staging, a deploy, or your attention.

**Rule of thumb once all four exist:** local for the loop, preview for the web
branch, staging for the rehearsal before a release, production for nothing but
serving users.

### 2.3 How each client surface reaches staging

There are **three** client surfaces, not two. The admin console is easy to miss:
it is a Flutter **Web** app built from `mobile/lib/main_admin.dart` and deployed
to Cloudflare Pages, so it lives in the mobile tree but behaves like a website.

| Surface | Built from | Hosted | Talks to the API |
|---|---|---|---|
| Public + consumer + pro web | `web/` | Vercel | **server-to-server** (BFF) |
| Admin console | `mobile/lib/main_admin.dart` | Cloudflare Pages | **from the browser**, cross-origin |
| Consumer + pro apps | `mobile/` | App Store / Play | direct, bearer tokens |

#### Web (`web/`) — free, and it already half-works

Vercel has three environment scopes. Set the API base per scope, once:

| Scope | `API_BASE_URL` / `NEXT_PUBLIC_API_BASE_URL` |
|---|---|
| Production (`myweli.com`) | `https://api.myweli.com` |
| **Preview** (every PR) | **the staging `*.run.app` URL** |
| Development (local) | `http://localhost:8080` |

That is the whole change. **Every PR then gets a complete web environment
running against staging, automatically**, with no per-PR work — Vercel already
builds them (all ten checks on this repo include one). It closes LAUNCH.md §5.4,
and it is the single highest-value hour in this whole plan.

No CORS work is needed: the browser only ever talks to the Next origin (§4.1).

Worth adding once staging exists: pin a **`staging.myweli.com`** alias to the
`main`-branch deployment, so there is one durable URL to hand someone rather than
a fresh per-deployment URL each time.

#### Admin console — a separate Pages project

Today `deploy-admin.yml` fires on **every push touching `mobile/**`** and ships
to production with `API_BASE_URL=https://api.myweli.com` **hardcoded**
(§3.4). So a mobile-only change deploys the admin console to production.

For staging, create a second Cloudflare Pages project **`myweli-admin-staging`**
rather than a branch deployment of the production project. Two reasons:

- The origin is then **stable and predictable** —
  `myweli-admin-staging.pages.dev` — which staging's `WEB_ORIGINS` can allowlist
  exactly. This surface *is* a browser-direct caller, so CORS genuinely applies
  to it, unlike `web/`.
- Production's Pages project is never touched by a staging deploy, which is the
  failure §3.4 describes.

The workflow becomes environment-parameterised the same way `deploy-backend.yml`
does in phase 6: `main` → staging project, production behind the same manual
confirm as the backend.

#### Mobile apps — dart-defines, then tracks

The build already carries the switch:

```
flutter build ipa --flavor consumer --release \
  --dart-define=USE_API_BACKEND=true \
  --dart-define=API_BASE_URL=https://myweli-api-staging-….a.run.app
```

§1.3 is what makes this trustworthy — until the fallbacks are removed, a build
missing either define silently runs on mocks and looks healthy.

Distribution is the second axis (LAUNCH.md §1.2): a staging-pointed build goes to
**TestFlight internal** or the **Play internal track**, both of which reach a
tester in minutes without review. The release candidate is the *same* pipeline
pointed at production.

**Until phase 8, this surface does not participate.** Without separate bundle
ids a staging build cannot sit beside the production app on your phone, so
installing one replaces the other. That is the accepted, bounded cost recorded
in §4 — and it is tolerable only because mobile launches last.

---

## 3. The four failure modes worth designing against

### 3.1 One plain env var is a hazard — but not the one first written here

`FCM_PROJECT_ID` is a **plain value** — one of only seven, surrounded by
seventeen `secretKeyRef`s. It is precisely the field a human edits to make
`service-staging.yaml`, and precisely the field a copy-paste reverses. Pointing
production at the staging Firebase project silently stops every push, so a CI
assertion pinning it per service file is still worth having.

> **Correction (phase 2).** This section originally claimed that misdirection
> would then **delete every push token**. It would not: a wrong project answers
> **403** `PERMISSION_DENIED` / `SENDER_ID_MISMATCH`, which the provider already
> counted as a failed send. That path was never the bug.
>
> The real defect was worse and had nothing to do with staging.
> `_isInvalidToken` substring-matched `INVALID_ARGUMENT`, and FCM v1's envelope
> carries that string in `error.status` for **every** 400 — so it was
> functionally `if (statusCode == 400) return true`. Since `send` posts an
> identical payload per token, any payload-level 400 pruned **all** of them. And
> it was reachable by an ordinary salon owner: `businessName` had no length
> bound and is interpolated into every booking push, so a long enough name
> oversized the payload and deleted that salon's clients' tokens.
>
> Fixed in phase 2 PR A — the envelope is parsed, pruning requires 404 +
> `UNREGISTERED` or a `message.token` field violation, and the name and payload
> are both bounded. Recorded as **T62** in BACKEND.md §7.

### 3.2 An empty staging database certifies every migration as instant

Migrations run **at boot, in one transaction, before the port binds**
(`migrations.dart:830-852`). The codebase already contains
`ALTER TABLE appointments ... EXCLUDE USING gist` (:272, :661) and bare
non-`CONCURRENT` `CREATE INDEX` — both take `ACCESS EXCLUSIVE` and build inline.

On an empty staging table: milliseconds. On production with real appointments:
a lock held while the table rebuilds, with `minScale=1` meaning **the service
cannot serve until it finishes**. Staging would say fine.

**Guards:** `SET lock_timeout = '3s'` and `statement_timeout = '60s'` at the top
of each migration transaction — a migration that cannot get its lock fails the
deploy instead of hanging the service. And restore a **prod PITR backup** into
staging before rehearsing, timing the boot as a gate. This is also LAUNCH.md
§5.5's unrehearsed-restore box, closed by the same act.

> **The timeouts are implemented (2026-08-16) — but NOT where this paragraph
> says, and the difference matters.**
> [backend-migration-timeouts.md](backend-migration-timeouts.md).
>
> "At the top of each migration transaction" is exactly right, and applying it
> one level up — to the schema-setup *connection*, where `withSchemaLock` takes
> its advisory lock — would have broken every normal deploy. Measured against
> PostgreSQL 16: **both** `lock_timeout` and `statement_timeout` abort a
> **waiting `pg_advisory_lock()`**. That lock is contended by design, since
> cold-starting instances are *supposed* to queue behind whichever one is
> migrating, so a timeout there puts a deadline on healthy contention rather
> than on a fault.
>
> They are therefore applied as `SET LOCAL` inside each transaction — measured
> not to survive the commit, which matters because the same pool serves
> requests — and the advisory lock is deliberately left unbounded.
>
> **The prod-PITR restore half was run on 2026-08-16, and it cannot answer the
> 60s question** — [infra-dr-restore.md](infra-dr-restore.md).
>
> This paragraph assumed a production copy carries production volume. It does
> not: production holds **5 user rows and no salons**, so a restored copy boots
> exactly as fast as staging already does. The restore was still worth running —
> it proved the backups are restorable and closed LAUNCH.md §5.5 — but the
> *timing gate* this paragraph asks for needs **synthetic volume generated in
> staging**, not a copy of an empty production.
>
> **The timing gate this paragraph asks for was then run against synthetic
> volume instead, on 2026-08-16** —
> [backend-migration-volume.md](backend-migration-volume.md).
>
> This paragraph's instinct was right and its arithmetic was optimistic. The
> `EXCLUDE USING gist` it names takes **14.3s at 100k appointments and 264s at
> 150k** on `db-f1-micro` — a cliff caused by shared-core CPU throttling. So
> `statement_timeout = 60s` stays, but it is **not** the binding constraint:
> migrations run before the port binds, so the **300s `startupProbe`** is, and
> the same statement exceeds *that* past ~200k rows. At that size the answer is
> a tier bump or not building the index at boot — not a larger timeout.

### 3.3 Staging seeded from prod + any live channel = real SMS to real customers

Two individually correct guards that are jointly dangerous. §3.2 wants a prod
restore; that data contains real phone numbers in `appointments.client_phone`.
The reminder cron then messages them from staging.

`MESSAGING_PROVIDER=disabled` today makes this inert — which is exactly why it
must be written down as a **standing constraint** rather than a coincidence.
When the channel is switched on after company registration, staging gets its own
subaccount with a **recipient allowlist of team numbers**, never prod's
credentials.

### 3.4 The pipeline that auto-deploys to production is the one nobody is watching

`deploy-backend.yml` is manual and confirm-gated. When this was written it had
**never run** — all 12 revisions were hand-deployed from a laptop. It has since
run: of 16 revisions, `00013`, `00015` and `00016` carry
`lastModifier: myweli-deployer@`, so the declarative path is now the live one
and the confirm gate is a real gate rather than an untested one.

Meanwhile `deploy-admin.yml` fires on **every push to main** touching `mobile/**`
and ships the admin console to production with
`--dart-define=API_BASE_URL=https://api.myweli.com` hardcoded. The moment we
start merging staging-targeted work, that is a production deploy nobody asked
for.

**Also:** the funnel smoke harness (`ci.yml:167-253`) **writes** — it creates
users, salons and bookings, and in Phase 7 **suspends a salon**. It is driven by
`SMOKE_BASE_URL`. Today there is one plausible hostname so the risk is
theoretical; staging creates a second, and a wrong value points a
salon-suspending test at production. It must refuse `api.myweli.com` by
construction.

---

## 4. Staging's app identity — separate bundle ids, sequenced with iOS

**Long-term answer: separate bundle ids** (`com.myweli.app.staging`). This is
what mobile teams converge on, and the reasons are not aesthetic:

- **Side-by-side install.** The decisive one. Testing staging must not mean
  uninstalling production — losing the session, the data, and any ability to
  compare the two.
- **Push isolation.** A staging push physically cannot reach a customer.
- **A separate crash-free rate.** Staging crashes must not pollute the metric
  that gates production's staged rollout (LAUNCH.md §1.4).
- **Visual distinction** — a badged icon and a different display name, so a
  staging screenshot is never mistaken for a production bug.

Both platforms provide the mechanism deliberately: Android `applicationIdSuffix`,
iOS per-configuration bundle ids — the same flavour machinery `setup_flavours.rb`
already drives for consumer/pro.

**Sequencing: not now — with the iOS launch (phase 8).** Three reasons.

1. Web launches first (LAUNCH.md §3), and web staging needs none of this.
2. We already carry two bundle ids (consumer + pro). Adding staging makes
   **four** — four Firebase apps, four provisioning profiles, four App Store
   Connect records, since TestFlight requires a record per bundle id.
3. That work batches naturally with the certificate and profile work iOS launch
   requires anyway. Doing it now means opening the same consoles twice.

The cost of deferring is real and bounded: until phase 8, **app builds point at
production**, so the app is the one surface without a rehearsal. Accepted
knowingly, because it is exactly the surface that launches last.

`APPLE_CLIENT_IDS` **is** the set of bundle ids — `com.myweli.app` AND `com.myweli.pro`, because Apple has no `serverClientId` indirection and the `aud` is whichever app is running (both call it). Written here as singular before the Pro flavour shipped; measured 2026-08-23, both are present. So phase 8 is a
backend config change too, not only a mobile one.

### 4.1 Staging URL — the `*.run.app` URL, not a hostname

The usual argument for `api-staging.myweli.com` is cookie and CORS fidelity: a
`*.run.app` URL sits on a different registrable domain, so `SameSite` behaviour
diverges from production.

**That argument does not apply here.** The web surface is a BFF — session
cookies are set on the **Next origin** (`lib/session.ts:3`) and the API is called
**server-to-server** through 72 route handlers under `app/api/`. The browser
never sees the API's domain, so the API's domain cannot affect cookie behaviour.

> **The conclusion held; the reason given for it was false, and it had already
> started to rot** (corrected 2026-08-18 while executing step 7). This paragraph
> used to claim "Nothing under `app/`, `components/` or `lib/` imports the
> browser API client; `NEXT_PUBLIC_API_BASE_URL` survives only as a server-side
> fallback in `server-api.ts`." Both halves were wrong:
> `lib/api/{providers,localities}.ts` are under `lib/` and do import it, and
> `resolvePublicApiBase()` demonstrably shipped the API base into **four**
> production client chunks — with `createClient()`'s return value discarded, so
> nothing *called* it. True conclusion, false premise, and the gap between them
> was one `api.GET(...)` in a client component.
>
> Now enforced instead of asserted: the pure locality lookups moved to
> `web/lib/localities.ts`, and `web/lib/api/client.ts` carries
> `import 'server-only'`. A client component that imports it **fails the build**
> and the error names the file. Measured after: the API base appears in **0**
> client chunks, down from 4. That guard is what the CORS decision now rests on
> — an exact-match `WEB_ORIGINS` could never list a per-deployment Vercel
> hostname anyway. The mobile app talks to the API
directly but authenticates with bearer tokens, not cookies.

One browser-direct caller **does** exist — the admin console (§2.3) calls the
API cross-origin from Flutter Web. It does not change the conclusion, because
the Flutter client authenticates with **bearer tokens and sets no cookies**
(`api_constants.dart:20`, and nothing in `mobile/lib` touches `Cookie` or
`withCredentials`). Cross-origin without cookies needs CORS, which a `*.run.app`
origin serves exactly as well as a custom domain — it just has to be in staging's
`WEB_ORIGINS`.

What the hostname would still buy is rehearsing prod's ingress chain — ALB →
serverless NEG → backend service → url-map → managed cert. That path is
provisioned once by a committed script (`infra/gcp/70-load-balancer.sh`) and
changes rarely, so **$18.25/month is not worth it today**.

**The condition that would reverse this** is narrower than "a browser-direct
call": it is a browser-direct call that relies on **cookies**, since only then
does the API's registrable domain start to matter. Introducing one is the change
that should send someone back to this section.

---

## 5. Cost

| Line | Monthly |
|---|---|
| Cloud SQL db-f1-micro, 24/7 | **$8.91** — 60–70% of the total, and it cannot scale to zero |
| Cloud SQL storage, 10 GiB PD_SSD | $1.97 |
| Backups + PITR (drop to 1 day on staging) | $0.20–0.50 — **PITR enabled 2026-08-17**; the instance had been provisioned without it, so this line was budgeted and not delivered. One `gcloud sql instances patch --enable-point-in-time-recovery`, 5 minutes, logs in Cloud Storage (not instance disk). Retention stays at **1 backup / 1 day of logs**, exactly as this line always specified — the log-retention default of 7 was lowered to match, because with one base backup every WAL segment older than a day is unreadable and the `7` only misled. **Exercised, not just configured**: a marker written 18 min after the base backup came back in a clone restored to a point after it — see [infra-dr-restore.md](infra-dr-restore.md) §8.4–8.5 |
| Cloud Run, minScale 0 | $0.50–2.00 |
| Secret Manager, ~17 versions | $1.02 — the 6-version free tier is already consumed by prod's 19 |
| R2, Scheduler, Artifact Registry, logging, egress | ~$0 |
| **Recommended total** | **$13–17** |
| ~~load-balanced `api-staging.myweli.com`~~ | **declined** — §4.1 |

**Do not** stop the instance between rehearsals: it saves $0.44/month, because
suspending the instance charge immediately starts the IPv4 reservation charge.

The $3–5 floor — a separate *database* on the existing instance — is rejected
on §2's connection arithmetic, not on principle.

---

## 6. Build order

Each phase is a PR. Nothing in phase 2+ starts until §1 is merged.

1. **Code guards** (§1) — the `ENV` enum, the seeding gate, fail-closed API base.
   No infrastructure. This is also what makes LAUNCH.md §5.1 tickable.
   **Plus the local environment (§2.2)** — a committed `docker-compose.yml` and
   a documented `dart_frog dev`. It ships first because without it there is no
   defined alternative to testing against staging.
2. **Prod fixes** (§7) — they are prod bugs, and staging is where we would
   otherwise discover them by accident.
3. **`infra/gcp/service-staging.yaml`** + the provisioning script, committed.
   Building staging by hand produces a second undocumented environment and
   doubles the drift surface — the thing that made this design necessary.
   **Done** (PR #369), and with it **`infra/cloudflare/`** — the R2 half.

   > **"The only genuinely un-scriptable blocker" was mostly wrong.** `wrangler`
   > creates the buckets, sets CORS and lifecycle from committed JSON, and
   > enables the `r2.dev` origin, so `90-staging-r2.sh` does all of it. **One**
   > step needs the dashboard: minting the API token, because Cloudflare does
   > not let a token create a token.
   >
   > That step is also the one that matters, so it is not left as an
   > instruction. The token must be **bucket-scoped**, Cloudflare's screen
   > defaults to *"apply to all buckets"*, and nothing else in the system can
   > tell the difference — bucket names isolate nothing, since an account-scoped
   > token reads and writes every bucket regardless of what `R2_BUCKET` says.
   > `backend/test/storage/r2_token_scope_test.dart` proves it by signing a GET
   > for a key that does not exist and reading the answer: 404 from a bucket the
   > token may address, 403 from one it may not. Both halves asserted — a
   > revoked credential is denied everywhere and would pass a one-sided check.
4. **Resources** — Cloud SQL instance, the runtime identity, secrets, the
   service, the crons. (R2 moved up into step 3, since it turned out to be
   committable configuration rather than dashboard work.)
   [`infra/gcp/90-staging.sh`](../../infra/gcp/90-staging.sh), run once by the
   owner: the deploy service account holds `run.admin` and
   `artifactregistry.writer` and deliberately nothing else, so it can deploy a
   service it cannot provision.

   > **Staging gets its own runtime identity**, `myweli-run-staging@`. Reusing
   > production's would be cheaper and would make the secret split cosmetic —
   > that account holds `secretAccessor` on every production secret version, so
   > a manifest naming `DATABASE_URL` instead of `STAGING_DATABASE_URL` would
   > simply work, and the isolation would rest on nobody mistyping a YAML key in
   > a file a push trigger deploys.
   >
   > The crons are created **paused**: `*/15` against `minScale: 0` is ~96 cold
   > starts a day, each running migrations, for an environment nobody is using
   > between rehearsals. They carry **OIDC only, no `X-Cron-Secret`** — staging
   > is where that path can be proven to carry traffic on its own, which is the
   > evidence production needs before retiring the header (BACKEND.md §7 T21).
   >
   > **Resumed 2026-08-17, and the evidence this paragraph predicted was
   > obtained immediately.** Both jobs forced a run: `/internal/cron/reminders`
   > and `/internal/cron/subscriptions` each answered **200**, and because these
   > jobs send **no `X-Cron-Secret` at all**, a 200 can only mean the OIDC token
   > verified. The negative half was checked too — an anonymous POST and a POST
   > with a junk bearer both return **403 `forbidden`** — because a 200 proves
   > authentication only if the route rejects the unauthenticated. See
   > [infra-cron-oidc-evidence.md](infra-cron-oidc-evidence.md).
   >
   > The cost this paragraph names is real and small: ~96 cold starts a day is
   > roughly **$0.7–1/month** of Cloud Run time, inside the $0.50–2.00 line §5
   > already budgets. What it buys is continuous exercise of the boot path —
   > migrations under the `SET LOCAL` timeouts, and the cron auth — on the
   > environment whose job is to fail first. Re-pausing is one command if the
   > noise is ever unwanted.
   >
   > `backend/test/infra/service_files_test.dart` asserts the script provisions
   > **exactly** the seventeen secrets the manifest mounts. A secret added to one
   > and forgotten in the other fails at revision creation with no application
   > log — the deploy simply does not come up, and the cause is a name in a file
   > nobody is looking at.
4b. **The WIF trust condition** — [`infra/gcp/40-iam-wif.sh`](../../infra/gcp/40-iam-wif.sh).

   > The provider is pinned on `assertion.repository` alone and the deployer's
   > binding on `attribute.repository`, so **any workflow, on any branch, with
   > `id-token: write` can mint a token for `myweli-deployer@`** — which holds
   > project-wide `roles/run.admin`, enough to replace *production*. Harmless
   > while deploys are `workflow_dispatch` + a typed confirm; the moment
   > `push: main` is uncommented, the blast radius of any merged workflow file
   > becomes production. **That trigger must not be enabled before this lands.**
   >
   > Three steps, and the order is the safety property: `widen` is additive (both
   > the old and the new trust work), a **real deploy** then proves the
   > `environment` claim actually arrives, and only then does `narrow` remove the
   > repository-wide binding. Reversed, the first evidence that the claim is
   > missing would be a broken pipeline with no way to deploy the fix.
   >
   > Enforced by the binding rather than by the provider's CEL condition: a
   > `principalSet` naming an attribute simply does not match a token lacking it,
   > whereas a condition referencing an absent claim is an evaluation hazard that
   > cannot be tested without applying it to the live provider.
   >
   > The script also commits the **baseline** — the pool, provider and bindings
   > that have existed since the migration and lived only in the project, making
   > the most security-relevant piece of this infrastructure the one piece nobody
   > could review.
5. **PITR restore into staging** (§3.2) — with the anonymisation step built
   into the restore script from the first run (§2.1), never added afterwards.
   Closes LAUNCH.md §5.5.
6. **Pipeline** — parameterise `deploy-backend.yml` with an `environment` input;
   `push: main` → staging; prod stays `workflow_dispatch` + confirm. Run it
   against **staging first**, which is also the first time that workflow ever
   executes.
7. ~~**Vercel Preview → staging**~~ **Done 2026-08-18** (LAUNCH.md §5.4). Both
   `API_BASE_URL` **and** `NEXT_PUBLIC_API_BASE_URL` now point Preview at the
   staging `*.run.app` and Production at `https://api.myweli.com`.
   **Two things this plan got wrong, worth keeping:**
   - it said "one env-var change". `API_BASE_URL` was also scoped
     Production+Preview, and it is the one the BFF actually reads
     (`resolveApiBase()` prefers it) — so changing only the `NEXT_PUBLIC_` one
     would have left every preview talking to production while *looking* split;
   - `vercel env rm <name> preview` removes the **whole variable**, not the one
     scope. Doing it to a Production+Preview entry deleted production's value
     outright. Caught by reading the state back; the live site was unaffected
     because the value was already baked into the deployed build, and the next
     production build would have failed loudly rather than silently — which is
     precisely what `web/lib/api-base.ts` was written to guarantee.
8. **Admin console** — a second Cloudflare Pages project `myweli-admin-staging`,
   and `deploy-admin.yml` parameterised the same way (§2.3).
9. **Mobile** — separate bundle ids (§4), batched with the iOS launch work.

---

## 7. Production bugs this surfaced

Not staging work. Separate slices, and §6 phase 2 because staging would
otherwise expose them.

**All six are closed** — four in code/CI, two applied to the live project. Three
were misdiagnosed here and are corrected below; two of the fixes originally
proposed would have caused an outage. What actually happened, with before/after
for each cloud change, is in
**[infra-prod-hardening.md](infra-prod-hardening.md)**.

| Finding | Evidence |
|---|---|
| ~~`deletionProtectionEnabled: false`~~ — **FIXED**, applied to the live instance | [infra-prod-hardening.md](infra-prod-hardening.md) §3.1 |
| `CRON_SECRET` a **literal plaintext header** on both Scheduler jobs — **understated**: it was also accepted as `?secret=`, the OIDC token was present but unenforced, and the default compute SA can read it via `roles/editor`. **FIXED in code** (PR #352); **the header itself was retired on 2026-08-18** once staging proved the OIDC path alone and production showed 251 runs with no fallback | §5 of the hardening doc |
| ~~Cloud SQL has a **public IP**~~ — **half wrong: the IP is load-bearing**, the proxy has no `--private-ip` and Cloud Run has no VPC egress, so removing it would take production down. The SSL half was real and is **FIXED** (`ENCRYPTED_ONLY`) | [infra-prod-hardening.md](infra-prod-hardening.md) §2.2, §3.2 |
| FCM `_isInvalidToken` matched body-wide `INVALID_ARGUMENT` → pruned on **any** 400. **A security bug**, remotely reachable via an unbounded `businessName`. **FIXED** (PR #351), recorded as **T62** | §3.1, corrected |
| ~~`max_connections` 25 vs a possible 32~~ — **FIXED (PR D)** by lowering the pool to 4, *not* by patching the flag: that `requiresRestart` on a ZONAL instance whose app has no connection retry, and 100 backends would not fit in 0.6 GB | `database.dart` × service.yaml maxScale; pinned in `test/db/pool_sizing_test.dart` |
| ~~`deploy-admin.yml` auto-deploys to prod on every `mobile/**` push~~ — **89 production deploys**. **FIXED** (PR #354): `workflow_dispatch` + confirm, with the admin build moved into CI | §3.4 |

---

## 8. What cannot be duplicated

- **Production APNs delivery.** A staging Firebase project + development
  provisioning yields **sandbox** tokens; the store build talks to production
  APNs. → verify on a TestFlight build against prod, deliberately.
- **App Store / Play review.** One-shot, human, against the production bundle id.
  → TestFlight internal is the rehearsal.
- **Real SMS over Ivorian carrier routes.** Twilio magic numbers never traverse a
  carrier; WhatsApp template approval is per-WABA.
- **Apple/Google sign-in identity.** No sandbox exists (§4).
- **The `api.myweli.com` cutover itself** — one global IP, one managed cert.
- **Production data volume** — hence §3.2's restore, which is the closest
  available substitute.
