# Staging — design

| | |
|---|---|
| **Module** | infrastructure (`infra/gcp/`, `backend/`, `.github/workflows/`) |
| **Status** | Phase 1 in progress — §1.1, §1.2, §1.3 **done**; the local environment (§2.2) is the last piece. |
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
smoke-seam warning. One gap the split exposed: with `guardsOn` on, staging would
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

---

## 2. Architecture — what is separate, what is shared

The rule from LAUNCH.md §1.1: **same shape, never the same data.** Applied
resource by resource, with the reason each way.

| Resource | Decision | Why |
|---|---|---|
| Cloud Run service | **separate** `myweli-api-staging`, minScale **0**, maxScale 2 | Saves $18/mo vs matching prod's minScale 1, and *improves* the rehearsal: every staging request then exercises the cold start that runs migrations behind `pg_advisory_lock` before the port binds |
| Cloud SQL | **separate instance** `myweli-db-staging` | Not for tidiness — the arithmetic is already red. `maxConnectionCount: 8` (`database.dart:24`) × maxScale 4 = **32 potential connections** against a db-f1-micro whose default `max_connections` is **25**. Prod stays under only because it rarely scales past 1. Sharing adds a second consumer to a pool that is already over-subscribed on paper |
| Database data | **synthetic by default; a scrubbed prod copy for rehearsals** | §2.1. An empty staging DB certifies every migration as instant (§3.2), but an un-scrubbed prod copy puts real phone numbers behind a reminder cron (§3.3) |
| Secret Manager | **separate versions**, all 17 | `JWT_SECRET` especially: a shared value lets a staging-issued token authenticate against **production**, and staging is where we deliberately mint admin tokens |
| R2 | **3 separate buckets + a bucket-scoped token** | Bucket *names* cannot collide (unique per account). The risk is the **credential**: an account-scoped token reads and writes every bucket regardless of what `R2_BUCKET` says. A staging run of the user-erasure path would delete production objects |
| `WEB_ORIGINS` | **separate**, staging origins only | Copying prod's value means staging accepts browser calls from `https://myweli.com`. When a preview gets CORS-blocked, the fix is a staging origin — **never** widening prod's list |
| `CRON_SECRET` | **separate** | Plus a prod fix: both Scheduler jobs currently carry it as a literal `X-Cron-Secret` header (§7) |
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
`SETUP.md` section for `dart_frog dev`. Two reasons it belongs here rather than
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

### 3.1 One plain env var can permanently delete every production push token

`FCM_PROJECT_ID` is a **plain value** — one of only seven, surrounded by
seventeen `secretKeyRef`s. It is precisely the field a human edits to make
`service-staging.yaml`, and precisely the field a copy-paste reverses.

Point prod at the staging Firebase project and every send fails —
and `fcm_v1_push_provider.dart:114-119` treats a body-wide
`contains('INVALID_ARGUMENT')` as a dead token, so it **prunes them**. Not a
degraded push service: an empty token table, unrecoverable without every user
reopening the app.

**Guards:** a CI assertion pinning `FCM_PROJECT_ID` per service file, and narrow
the invalid-token rule to parse the FCM error and prune only on `UNREGISTERED`.

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

`deploy-backend.yml` is manual, confirm-gated, and **has never run** — all 12
revisions were hand-deployed from a laptop (`lastModifier: sadreddinedaher@…`,
workflow run count 0).

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

`APPLE_CLIENT_IDS` **is** the bundle id (`com.myweli.app`), so phase 8 is a
backend config change too, not only a mobile one.

### 4.1 Staging URL — the `*.run.app` URL, not a hostname

The usual argument for `api-staging.myweli.com` is cookie and CORS fidelity: a
`*.run.app` URL sits on a different registrable domain, so `SameSite` behaviour
diverges from production.

**That argument does not apply here.** The web surface is a BFF — session
cookies are set on the **Next origin** (`lib/session.ts:3`) and the API is called
**server-to-server**. Nothing under `app/`, `components/` or `lib/` imports the
browser API client; `NEXT_PUBLIC_API_BASE_URL` survives only as a server-side
fallback in `server-api.ts`. The browser never sees the API's domain, so the
API's domain cannot affect cookie behaviour. The mobile app talks to the API
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
| Backups + PITR (drop to 1 day on staging) | $0.20–0.50 |
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
4. **Resources** — Cloud SQL instance, secrets, R2 buckets, the service.
5. **PITR restore into staging** (§3.2) — with the anonymisation step built
   into the restore script from the first run (§2.1), never added afterwards.
   Closes LAUNCH.md §5.5.
6. **Pipeline** — parameterise `deploy-backend.yml` with an `environment` input;
   `push: main` → staging; prod stays `workflow_dispatch` + confirm. Run it
   against **staging first**, which is also the first time that workflow ever
   executes.
7. **Vercel Preview → staging** (LAUNCH.md §5.4) — one env-var change per scope,
   after which every PR gets a full web environment on staging automatically.
   The highest value-per-minute step in the plan; do it the day staging exists.
8. **Admin console** — a second Cloudflare Pages project `myweli-admin-staging`,
   and `deploy-admin.yml` parameterised the same way (§2.3).
9. **Mobile** — separate bundle ids (§4), batched with the iOS launch work.

---

## 7. Production bugs this surfaced

Not staging work. Separate slices, and §6 phase 2 because staging would
otherwise expose them.

| Finding | Evidence |
|---|---|
| **`deletionProtectionEnabled: false`** on the production database | `gcloud sql instances describe myweli-db` |
| `CRON_SECRET` stored as a **literal plaintext header** on both Scheduler jobs, readable by anyone with Scheduler view access | `gcloud scheduler jobs describe` |
| Cloud SQL has a **public IP** with `sslMode: ALLOW_UNENCRYPTED_AND_ENCRYPTED` | same |
| FCM `_isInvalidToken` matches body-wide `INVALID_ARGUMENT` → can prune every token (§3.1) | `fcm_v1_push_provider.dart:114-119` |
| `max_connections` 25 vs a possible 32 (§2) | `database.dart:24` × service.yaml maxScale |
| `deploy-admin.yml` auto-deploys to prod on every `mobile/**` push (§3.4) | `.github/workflows/deploy-admin.yml` |

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
