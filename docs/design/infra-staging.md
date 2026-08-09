# Staging — design

| | |
|---|---|
| **Module** | infrastructure (`infra/gcp/`, `backend/`, `.github/workflows/`) |
| **Status** | Design. **Blocked on §1** — three code changes must land before any resource is created. |
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

### 1.1 `ENV` is binary, and neither value is safe for staging

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

### 1.2 Seeding has no environment check, so purging production does not stick

`seedProvidersIfEmpty` (`dependencies.dart:788`) is gated on **one** condition:
the `providers` table being empty. Not on `ENV`.

So the sequence LAUNCH.md §4 requires — purge the demo salons, then deploy —
**re-creates them**. Any deploy does. So does a `minScale` instance recycle. The
§5.1 box *"seeding runs only when `ENV != prod`"* is not merely unticked; it
cannot be ticked without this change.

**Change:** `if (env == Env.dev) await seedProvidersIfEmpty(pool);`, and make
`seedProvidersIfEmpty` itself throw when called with prod-shaped config so the
guard survives a refactor.

### 1.3 The API base has silent fallbacks on every build path

- `app_config.dart:15-23` — `USE_API_BACKEND` defaults **false**, `API_BASE_URL`
  defaults to `http://localhost:8080`
- `web/lib/server-api.ts:4-7` — falls back to `http://localhost:8080`

A staging TestFlight build missing one `--dart-define` does not error. It runs
**entirely on in-app mocks**: full salon list, working search, bookings that
appear to succeed. It looks like a healthy staging environment and is testing
nothing. This is the failure mode most likely to waste a week.

**Change:** make it fail closed — a release build asserts `useApiBackend` is
true and `apiBaseUrl` is non-default; the web BFF throws instead of defaulting.

---

## 2. Architecture — what is separate, what is shared

The rule from LAUNCH.md §1.1: **same shape, never the same data.** Applied
resource by resource, with the reason each way.

| Resource | Decision | Why |
|---|---|---|
| Cloud Run service | **separate** `myweli-api-staging`, minScale **0**, maxScale 2 | Saves $18/mo vs matching prod's minScale 1, and *improves* the rehearsal: every staging request then exercises the cold start that runs migrations behind `pg_advisory_lock` before the port binds |
| Cloud SQL | **separate instance** `myweli-db-staging` | Not for tidiness — the arithmetic is already red. `maxConnectionCount: 8` (`database.dart:24`) × maxScale 4 = **32 potential connections** against a db-f1-micro whose default `max_connections` is **25**. Prod stays under only because it rarely scales past 1. Sharing adds a second consumer to a pool that is already over-subscribed on paper |
| Database data | **restored from a prod PITR backup** | §3.2 — an empty staging DB certifies every migration as instant |
| Secret Manager | **separate versions**, all 17 | `JWT_SECRET` especially: a shared value lets a staging-issued token authenticate against **production**, and staging is where we deliberately mint admin tokens |
| R2 | **3 separate buckets + a bucket-scoped token** | Bucket *names* cannot collide (unique per account). The risk is the **credential**: an account-scoped token reads and writes every bucket regardless of what `R2_BUCKET` says. A staging run of the user-erasure path would delete production objects |
| `WEB_ORIGINS` | **separate**, staging origins only | Copying prod's value means staging accepts browser calls from `https://myweli.com`. When a preview gets CORS-blocked, the fix is a staging origin — **never** widening prod's list |
| `CRON_SECRET` | **separate** | Plus a prod fix: both Scheduler jobs currently carry it as a literal `X-Cron-Secret` header (§7) |
| `MESSAGING_PROVIDER` | **`disabled`, and it stays that way** | §3.3 |
| Artifact Registry | **shared** — same `:${SHA}` image | Deploy the identical immutable digest to staging, then promote **that same digest** to prod. A separately built prod image is a different artifact and defeats the rehearsal |
| Firebase / FCM | **see §4 — this is the open decision** | |
| Ingress | **`all`** on staging, using the **`*.run.app` URL** — *not* prod's `internal-and-cloud-load-balancing` | Copying prod's value verbatim makes staging unreachable by its own cron, and Cloud Run domain mappings are unimplemented in europe-west9. The $18.25 hostname is **declined** — see §4.1 |

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

What the hostname would still buy is rehearsing prod's ingress chain — ALB →
serverless NEG → backend service → url-map → managed cert. That path is
provisioned once by a committed script (`infra/gcp/70-load-balancer.sh`) and
changes rarely, so **$18.25/month is not worth it today**. Revisit if the
ingress path itself becomes something we modify, or if a browser-direct API call
is ever introduced — that second condition is what would make this decision
wrong, so it belongs in review.

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
2. **Prod fixes** (§7) — they are prod bugs, and staging is where we would
   otherwise discover them by accident.
3. **`infra/gcp/service-staging.yaml`** + the provisioning script, committed.
   Building staging by hand produces a second undocumented environment and
   doubles the drift surface — the thing that made this design necessary.
4. **Resources** — Cloud SQL instance, secrets, R2 buckets, the service.
5. **PITR restore into staging** (§3.2) — closes LAUNCH.md §5.5.
6. **Pipeline** — parameterise `deploy-backend.yml` with an `environment` input;
   `push: main` → staging; prod stays `workflow_dispatch` + confirm. Run it
   against **staging first**, which is also the first time that workflow ever
   executes.
7. **Vercel Preview → staging** (LAUNCH.md §5.4).
8. **Mobile** — separate bundle ids (§4), batched with the iOS launch work.

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
